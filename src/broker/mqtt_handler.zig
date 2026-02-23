const std = @import("std");
const packet = @import("../protocol/mqtt/packet.zig");
const parser = @import("../protocol/mqtt/parser.zig");
const TopicBroker = @import("broker.zig").TopicBroker;
const Connection = @import("../common/connection.zig").Connection;
const SchemaManager = @import("../server/schema_manager.zig").SchemaManager;
const pb_decoder = @import("../protocol/protobuf/decoder.zig");
const pb_encoder = @import("../protocol/protobuf/encoder.zig");

/// MQTT Session state for a client
pub const Session = struct {
    client_id: []const u8,
    clean_session: bool,
    connected: bool,
    packet_id_counter: u16,

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8, clean_session: bool) !Session {
        const id_copy = try allocator.dupe(u8, client_id);
        return Session{
            .client_id = id_copy,
            .clean_session = clean_session,
            .connected = true,
            .packet_id_counter = 1,
        };
    }

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.client_id);
    }

    pub fn nextPacketId(self: *Session) u16 {
        const id = self.packet_id_counter;
        self.packet_id_counter +%= 1;
        if (self.packet_id_counter == 0) {
            self.packet_id_counter = 1;
        }
        return id;
    }
};

/// MQTT Protocol Handler
pub const MqttHandler = struct {
    allocator: std.mem.Allocator,
    parser: parser.Parser,
    sessions: std.AutoHashMap(usize, Session), // client_id -> Session

    pub fn init(allocator: std.mem.Allocator) MqttHandler {
        return MqttHandler{
            .allocator = allocator,
            .parser = parser.Parser.init(allocator),
            .sessions = std.AutoHashMap(usize, Session).init(allocator),
        };
    }

    pub fn deinit(self: *MqttHandler) void {
        var it = self.sessions.valueIterator();
        while (it.next()) |session| {
            session.deinit(self.allocator);
        }
        self.sessions.deinit();
    }

    /// Handle incoming MQTT packet
    pub fn handlePacket(self: *MqttHandler, conn: *Connection, client_index: usize, buffer: []const u8, broker: *TopicBroker, connections: []?*Connection, schema_manager: *SchemaManager) !void {
        if (buffer.len < 2) {
            return error.InsufficientData;
        }

        const header = try packet.FixedHeader.parse(buffer);

        switch (header.packet_type) {
            .CONNECT => try self.handleConnect(conn, client_index, buffer),
            .PUBLISH => try self.handlePublish(conn, client_index, buffer, broker, connections, schema_manager),
            // Other handlers don't need connections list yet
            .SUBSCRIBE => try self.handleSubscribe(conn, client_index, buffer, broker),
            .UNSUBSCRIBE => try self.handleUnsubscribe(conn, client_index, buffer, broker),
            .PINGREQ => try self.handlePingreq(conn),
            .DISCONNECT => try self.handleDisconnect(conn, client_index, broker),
            else => {
                std.debug.print("⚠ Unhandled packet type: {}\n", .{header.packet_type});
            },
        }
    }

    fn handleConnect(self: *MqttHandler, conn: *Connection, client_index: usize, buffer: []const u8) !void {
        const connect_packet = try self.parser.parseConnect(buffer);

        std.debug.print("← CONNECT from client '{s}'\n", .{connect_packet.client_id});

        // Create session
        const session = try Session.init(
            self.allocator,
            connect_packet.client_id,
            connect_packet.flags.clean_session == 1,
        );
        try self.sessions.put(client_index, session);

        // Send CONNACK
        const connack = packet.ConnackPacket{
            .session_present = false,
            .return_code = .accepted,
        };

        var response_buffer: [1024]u8 = undefined;
        const written = try connack.encode(&response_buffer);
        _ = try conn.write(response_buffer[0..written]);

        std.debug.print("→ CONNACK sent (accepted)\n", .{});
    }

    fn handlePublish(self: *MqttHandler, conn: *Connection, client_index: usize, buffer: []const u8, broker: *TopicBroker, connections: []?*Connection, schema_manager: *SchemaManager) !void {
        _ = conn;
        const publish_packet = try self.parser.parsePublish(buffer);

        if (std.mem.eql(u8, publish_packet.topic, "$SYS/discovery/request")) {
            try self.handleDiscoveryRequest(broker, schema_manager, connections);
            return;
        }

        std.debug.print("← PUBLISH to '{s}' ({d} bytes)\n", .{ publish_packet.topic, publish_packet.payload.len });

        // Try decoding if schema exists
        if (schema_manager.getMessageDefinitionForTopic(publish_packet.topic)) |schema| {
            std.debug.print("  [Protobuf] Found schema for topic '{s}': {s}\n", .{ publish_packet.topic, schema.name });
            var decoder = pb_decoder.Decoder.init(self.allocator, publish_packet.payload);
            const decoded = decoder.decodeMessage(schema, &schema_manager.registry) catch |err| blk: {
                std.debug.print("  [Protobuf] ⚠ Decode error: {}\n", .{err});
                break :blk null;
            };

            if (decoded) |val| {
                var v = val;
                defer v.deinit(self.allocator);
                std.debug.print("  [Protobuf] Decoded Value: ", .{});
                v.debugPrint();
                std.debug.print("\n", .{});
            }
        } else {
            std.debug.print("  [Raw] Payload: {s}\n", .{publish_packet.payload});
        }

        // Get all subscribers for this topic
        var subscribers = try broker.getSubscribers(publish_packet.topic, self.allocator);
        defer subscribers.deinit(self.allocator);

        std.debug.print("  Found {} subscriber(s)\n", .{subscribers.items.len});

        // Forward message to all subscribers
        for (subscribers.items) |sub_index| {
            if (sub_index < connections.len) {
                if (connections[sub_index]) |sub_conn| {
                    if (sub_index != client_index) { // Don't echo back to sender usually
                        // In full MQTT, we might handle packet ID mapping, but for now exact forwarding
                        _ = sub_conn.write(buffer) catch |err| {
                            std.debug.print("  ⚠ Failed to forward to client {}: {}\n", .{ sub_index, err });
                            continue;
                        };
                        broker.total_messages_routed += 1;
                        std.debug.print("  → Forwarded to client {}\n", .{sub_index});
                    }
                }
            }
        }
    }

    fn handleSubscribe(self: *MqttHandler, conn: *Connection, client_index: usize, buffer: []const u8, broker: *TopicBroker) !void {
        const subscribe_packet = try self.parser.parseSubscribe(buffer);

        std.debug.print("← SUBSCRIBE (packet_id={})\n", .{subscribe_packet.packet_id});

        var return_codes = try self.allocator.alloc(u8, subscribe_packet.topics.len);
        defer self.allocator.free(return_codes);

        for (subscribe_packet.topics, 0..) |topic_filter, i| {
            std.debug.print("  Topic: '{s}' (QoS {})\n", .{ topic_filter.topic, @intFromEnum(topic_filter.qos) });

            try broker.subscribe(topic_filter.topic, client_index);

            // Return granted QoS (we only support QoS 0)
            return_codes[i] = 0;
        }

        // Send SUBACK
        const suback = packet.SubackPacket{
            .packet_id = subscribe_packet.packet_id,
            .return_codes = return_codes,
        };

        var response_buffer: [1024]u8 = undefined;
        const written = try suback.encode(&response_buffer);
        _ = try conn.write(response_buffer[0..written]);

        std.debug.print("→ SUBACK sent\n", .{});
    }

    fn handleUnsubscribe(self: *MqttHandler, conn: *Connection, client_index: usize, buffer: []const u8, broker: *TopicBroker) !void {
        const topics = try self.parser.parseUnsubscribe(buffer);
        defer self.allocator.free(topics);

        std.debug.print("← UNSUBSCRIBE\n", .{});

        for (topics) |topic| {
            std.debug.print("  Topic: '{s}'\n", .{topic});
            try broker.unsubscribe(topic, client_index);
        }

        // Send UNSUBACK
        // TODO: Implement UNSUBACK packet encoding

        _ = conn;
    }

    fn handlePingreq(self: *MqttHandler, conn: *Connection) !void {
        std.debug.print("← PINGREQ\n", .{});

        var response_buffer: [10]u8 = undefined;
        const written = try packet.PingrespPacket.encode(&response_buffer);
        _ = try conn.write(response_buffer[0..written]);

        std.debug.print("→ PINGRESP sent\n", .{});

        _ = self;
    }

    fn handleDisconnect(self: *MqttHandler, conn: *Connection, client_index: usize, broker: *TopicBroker) !void {
        std.debug.print("← DISCONNECT\n", .{});

        // Clean up session
        if (self.sessions.fetchRemove(client_index)) |entry| {
            var session = entry.value;
            session.deinit(self.allocator);
        }

        // Remove all subscriptions
        broker.removeClient(client_index);

        conn.state = .disconnecting;
    }

    fn handleDiscoveryRequest(self: *MqttHandler, broker: *TopicBroker, schema_manager: *SchemaManager, connections: []?*Connection) !void {
        std.debug.print("  [Discovery] Received request\n", .{});

        // 1. Get the response value
        var value = schema_manager.getDiscoveryValue(self.allocator) catch |err| {
            std.debug.print("  [Discovery] Failed to build response value: {}\n", .{err});
            return;
        };
        defer value.deinit(self.allocator);

        // 2. Get the schema
        const schema = schema_manager.registry.getMessage("ServiceDiscoveryResponse");
        if (schema == null) {
            std.debug.print("  [Discovery] ⚠ Schema 'ServiceDiscoveryResponse' not found!\n", .{});
            return;
        }

        // 3. Encode Protobuf
        var encoder = pb_encoder.Encoder.init(self.allocator, &schema_manager.registry);
        const pb_payload = try encoder.encode(value, schema.?);
        defer self.allocator.free(pb_payload);

        // 4. Create response packet
        const response_topic = "$SYS/discovery/response";
        const pub_packet = packet.PublishPacket{
            .topic = response_topic,
            .qos = .at_most_once,
            .retain = false,
            .dup = false,
            .packet_id = null,
            .payload = pb_payload,
        };

        // 5. Encode MQTT Packet
        const total_size = pb_payload.len + response_topic.len + 20; // Safe buffer margin
        const msg_buffer = try self.allocator.alloc(u8, total_size);
        defer self.allocator.free(msg_buffer);

        const written = try pub_packet.encode(msg_buffer);
        const bytes_to_send = msg_buffer[0..written];

        // 6. Send to subscribers
        var subscribers = try broker.getSubscribers(response_topic, self.allocator);
        defer subscribers.deinit(self.allocator);

        std.debug.print("  [Discovery] Sending response to {} subscriber(s)\n", .{subscribers.items.len});

        for (subscribers.items) |sub_index| {
            if (sub_index < connections.len) {
                if (connections[sub_index]) |sub_conn| {
                    _ = sub_conn.write(bytes_to_send) catch |err| {
                        std.debug.print("  ⚠ Failed to send discovery to client {}: {}\n", .{ sub_index, err });
                        continue;
                    };
                }
            }
        }
    }
};
