const std = @import("std");
const Connection = @import("../common/connection.zig").Connection;
const packet = @import("../protocol/mqtt/packet.zig");
const Parser = @import("../protocol/mqtt/parser.zig").Parser;

/// Simple MQTT Client
pub const MqttClient = struct {
    allocator: std.mem.Allocator,
    connection: ?Connection,
    parser: Parser,
    client_id: []const u8,
    packet_id_counter: u16,

    // Buffer for reading/writing packets
    buffer: []u8,

    pub fn init(allocator: std.mem.Allocator, client_id: []const u8) !MqttClient {
        const id_copy = try allocator.dupe(u8, client_id);
        const buffer = try allocator.alloc(u8, 4096); // 4KB buffer

        return MqttClient{
            .allocator = allocator,
            .connection = null,
            .parser = Parser.init(allocator),
            .client_id = id_copy,
            .packet_id_counter = 1,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *MqttClient) void {
        self.allocator.free(self.buffer);
        self.allocator.free(self.client_id);
        if (self.connection) |*conn| {
            conn.deinit();
        }
    }

    /// Connect to MQTT broker
    pub fn connect(self: *MqttClient, host: []const u8, port: u16) !void {
        // TCP Connect
        const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp(host, port));

        // Initialize Connection
        if (self.connection) |*conn| {
            conn.deinit();
        }
        self.connection = try Connection.init(self.allocator, stream.handle, true);
        self.connection.?.state = .connected;

        // Send CONNECT packet
        const connect_packet = packet.ConnectPacket{
            .protocol_name = "MQTT",
            .protocol_level = 4, // v3.1.1
            .flags = .{
                .clean_session = 1,
                .will_flag = 0,
                .will_qos = 0,
                .will_retain = 0,
                .password_flag = 0,
                .username_flag = 0,
            },
            .keep_alive = 60,
            .client_id = self.client_id,
            .will_topic = null,
            .will_message = null,
            .username = null,
            .password = null,
        };

        const len = try connect_packet.encode(self.buffer);
        _ = try self.connection.?.write(self.buffer[0..len]);

        // Wait for CONNACK
        // Simple blocking read for now
        self.connection.?.offset = 0;
        const bytes_read = try self.connection.?.read();
        const response = self.connection.?.read_buffer[0..bytes_read];

        // TODO: Use Parser properly when it supports CONNACK parsing
        // Current parser only parses Client->Server packets?
        // Let's check Parser.parse* methods.
        // Parser.parseConnect, parsePublish, parseSubscribe.
        // It does NOT have parseConnack!

        // Manual check for now
        const header = try packet.FixedHeader.parse(response);
        if (header.packet_type != .CONNACK) {
            return error.UnexpectedPacket;
        }
        // Skip header
        // Simple check of return code at offset header.size() + 1
        if (response.len >= header.size() + 2) {
            const ret_code = response[header.size() + 1];
            if (ret_code != 0) return error.ConnectionRefused;
        }
    }

    /// Publish message
    pub fn publish(self: *MqttClient, topic: []const u8, message: []const u8) !void {
        if (self.connection == null or !self.connection.?.isActive()) return error.NotConnected;

        const publish_packet = packet.PublishPacket{
            .topic = topic,
            .qos = .at_most_once,
            .retain = false,
            .dup = false,
            .packet_id = null,
            .payload = message,
        };

        const len = try publish_packet.encode(self.buffer);
        _ = try self.connection.?.write(self.buffer[0..len]);
    }

    /// Subscribe to topic
    pub fn subscribe(self: *MqttClient, topic: []const u8) !void {
        if (self.connection == null or !self.connection.?.isActive()) return error.NotConnected;

        const pid = self.nextPacketId();

        var topic_filters = [_]packet.SubscribePacket.TopicFilter{
            .{ .topic = topic, .qos = .at_most_once },
        };

        const subscribe_packet = packet.SubscribePacket{
            .packet_id = pid,
            .topics = &topic_filters,
        };

        const len = try subscribe_packet.encode(self.buffer);
        _ = try self.connection.?.write(self.buffer[0..len]);

        // Wait for SUBACK
        self.connection.?.offset = 0;
        const bytes_read = try self.connection.?.read();
        const response = self.connection.?.read_buffer[0..bytes_read];

        const header = try packet.FixedHeader.parse(response);
        if (header.packet_type != .SUBACK) {
            return error.UnexpectedPacket;
        }
        // Could verify Packet ID here
    }

    /// Disconnect
    pub fn disconnect(self: *MqttClient) !void {
        if (self.connection == null) return;

        const disconnect_packet = packet.DisconnectPacket{};
        const len = try disconnect_packet.encode(self.buffer);
        _ = try self.connection.?.write(self.buffer[0..len]);

        self.connection.?.close();
    }

    /// Loop to receive messages (Blocking)
    /// Calls callback with (topic, message)
    pub fn run(self: *MqttClient, callback: *const fn (topic: []const u8, message: []const u8) void) !void {
        if (self.connection == null) return error.NotConnected;

        while (self.connection.?.isActive()) {
            self.connection.?.offset = 0;
            const bytes_read = self.connection.?.read() catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (bytes_read == 0) break;

            const buffer = self.connection.?.read_buffer[0..bytes_read];
            const header = try packet.FixedHeader.parse(buffer);

            if (header.packet_type == .PUBLISH) {
                // Use parser to parse PUBLISH packet
                // Parser.parsePublish works for incoming PUBLISH
                const publish_pkt = try self.parser.parsePublish(buffer);
                callback(publish_pkt.topic, publish_pkt.payload);
            } else if (header.packet_type == .PINGRESP) {
                // Ignore
            }
        }
    }

    fn nextPacketId(self: *MqttClient) u16 {
        const id = self.packet_id_counter;
        self.packet_id_counter +%= 1;
        if (self.packet_id_counter == 0) self.packet_id_counter = 1;
        return id;
    }
};
