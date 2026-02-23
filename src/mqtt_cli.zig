const std = @import("std");
const MqttClient = @import("client/client.zig").MqttClient;
const pb_registry = @import("protocol/protobuf/registry.zig");
const pb_parser = @import("protocol/protobuf/parser.zig");
const pb_encoder = @import("protocol/protobuf/encoder.zig");
const pb_decoder = @import("protocol/protobuf/decoder.zig");
const pb_json = @import("protocol/protobuf/json_converter.zig");
const packet = @import("protocol/mqtt/packet.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "help")) {
        printUsage();
        return;
    }

    // Default configuration
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 1883;
    var raw_topic: ?[]const u8 = null;
    var message: []const u8 = "hello";
    var client_id: []const u8 = "protomq-cli";
    var proto_dir: ?[]const u8 = null;
    var proto_type: ?[]const u8 = null;

    // Parse flags
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--host")) {
            if (i + 1 < args.len) {
                host = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--port")) {
            if (i + 1 < args.len) {
                port = try std.fmt.parseInt(u16, args[i + 1], 10);
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--topic") or std.mem.eql(u8, arg, "-t")) {
            if (i + 1 < args.len) {
                raw_topic = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--message") or std.mem.eql(u8, arg, "-m")) {
            if (i + 1 < args.len) {
                message = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--id")) {
            if (i + 1 < args.len) {
                client_id = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--proto-dir")) {
            if (i + 1 < args.len) {
                proto_dir = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--type")) {
            if (i + 1 < args.len) {
                proto_type = args[i + 1];
                i += 1;
            }
        }
    }

    var client = try MqttClient.init(allocator, client_id);
    defer client.deinit();

    std.debug.print("🔌 Connecting to {s}:{} as '{s}'...\n", .{ host, port, client_id });
    try client.connect(host, port);
    std.debug.print("✅ Connected!\n", .{});

    if (std.mem.eql(u8, command, "publish") or std.mem.eql(u8, command, "pub")) {
        if (raw_topic) |topic| {
            var payload: []const u8 = message;
            var free_payload = false;
            defer if (free_payload) allocator.free(payload);

            // Handle Protobuf encoding if requested
            if (proto_dir != null and proto_type != null) {
                std.debug.print("📦 Encoding message as Protobuf type '{s}'...\n", .{proto_type.?});

                var registry = pb_registry.SchemaRegistry.init(allocator);
                defer registry.deinit();

                // Load schemas from dir
                var dir = try std.fs.cwd().openDir(proto_dir.?, .{ .iterate = true });
                defer dir.close();
                var it = dir.iterate();
                while (try it.next()) |entry| {
                    if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".proto")) {
                        const content = try dir.readFileAlloc(allocator, entry.name, 1024 * 1024);
                        defer allocator.free(content);
                        var parser = pb_parser.ProtoParser.init(allocator, content);
                        try parser.parse(&registry);
                    }
                }

                if (registry.getMessage(proto_type.?)) |def| {
                    // Parse JSON
                    var json_parsed = try std.json.parseFromSlice(std.json.Value, allocator, message, .{});
                    defer json_parsed.deinit();

                    // Convert to ProtoValue
                    var proto_val = try pb_json.jsonToProtoValue(allocator, &registry, json_parsed.value, def);
                    defer proto_val.deinit(allocator);

                    // Encode
                    var encoder = pb_encoder.Encoder.init(allocator, &registry);
                    payload = try encoder.encode(proto_val, def);
                    free_payload = true;
                } else {
                    std.debug.print("❌ Error: Message type '{s}' not found in schemas.\n", .{proto_type.?});
                    return;
                }
            }

            std.debug.print("📤 Publishing to '{s}' ({d} bytes)\n", .{ topic, payload.len });
            try client.publish(topic, payload);
            std.debug.print("✅ Published.\n", .{});
        } else {
            std.debug.print("Error: --topic is required for publish\n", .{});
        }
        try client.disconnect();
    } else if (std.mem.eql(u8, command, "subscribe") or std.mem.eql(u8, command, "sub")) {
        if (raw_topic) |topic| {
            std.debug.print("👂 Subscribing to '{s}'...\n", .{topic});
            try client.subscribe(topic);
            std.debug.print("✅ Subscribed. Waiting for messages (Ctrl+C to stop)...\n", .{});

            var sub_ctx = SubscribeContext{
                .allocator = allocator,
                .registry = pb_registry.SchemaRegistry.init(allocator),
                .topic_mapping = std.StringHashMap([]const u8).init(allocator),
            };

            if (proto_dir) |dir_path| {
                std.debug.print("🔍 Fetching schemas via Service Discovery...\n", .{});

                // Load schemas from dir first (so we have discovery.proto)
                var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch null;
                if (dir) |*d| {
                    defer d.close();
                    var it = d.iterate();
                    while (it.next() catch null) |entry| {
                        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".proto")) {
                            const content = d.readFileAlloc(allocator, entry.name, 1024 * 1024) catch continue;
                            defer allocator.free(content);
                            var p = pb_parser.ProtoParser.init(allocator, content);
                            p.parse(&sub_ctx.registry) catch {};
                        }
                    }
                }

                // Temporary subscribe to discovery response
                try client.subscribe("$SYS/discovery/response");
                try client.publish("$SYS/discovery/request", "");

                // Wait for the response
                while (client.connection.?.isActive()) {
                    client.connection.?.offset = 0;
                    const bytes_read = try client.connection.?.read();
                    if (bytes_read == 0) break;

                    const buffer = client.connection.?.read_buffer[0..bytes_read];
                    const header = try packet.FixedHeader.parse(buffer);

                    if (header.packet_type == .PUBLISH) {
                        const pub_pkt = try client.parser.parsePublish(buffer);
                        // Is this the discovery response?
                        if (std.mem.eql(u8, pub_pkt.topic, "$SYS/discovery/response")) {
                            if (sub_ctx.registry.getMessage("ServiceDiscoveryResponse")) |schema| {
                                var decoder = pb_decoder.Decoder.init(allocator, pub_pkt.payload);
                                if (decoder.decodeMessage(schema, &sub_ctx.registry)) |decoded_val| {
                                    var val = decoded_val;
                                    defer val.deinit(allocator);

                                    // Iterate entries and add to mapping
                                    if (std.meta.activeTag(val) == .message) {
                                        if (val.message.get(1)) |schemas_val| {
                                            if (std.meta.activeTag(schemas_val) == .repeated) {
                                                for (schemas_val.repeated.items) |schema_info_ptr| {
                                                    const schema_info = schema_info_ptr.*;
                                                    if (std.meta.activeTag(schema_info) == .message) {
                                                        const t = schema_info.message.get(1);
                                                        const m = schema_info.message.get(2);
                                                        const s = schema_info.message.get(3);
                                                        if (t != null and m != null and
                                                            std.meta.activeTag(t.?) == .bytes and
                                                            std.meta.activeTag(m.?) == .bytes)
                                                        {
                                                            sub_ctx.topic_mapping.put(try allocator.dupe(u8, t.?.bytes), try allocator.dupe(u8, m.?.bytes)) catch {};

                                                            // If there's an embedded schema, parse it too
                                                            if (s != null and std.meta.activeTag(s.?) == .bytes and s.?.bytes.len > 0) {
                                                                var p = pb_parser.ProtoParser.init(allocator, s.?.bytes);
                                                                p.parse(&sub_ctx.registry) catch {};
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else |_| {}
                            }
                            break;
                        }
                    }
                }

                std.debug.print("✅ Loaded {d} mappings.\n", .{sub_ctx.topic_mapping.count()});
            }

            // If --type is given, directly register the subscribed topic→type mapping
            // (overrides / supplements discovery, useful when server doesn't advertise this topic)
            if (proto_type) |msg_type| {
                // Only load schemas from dir when proto-dir is set but we skipped discovery
                if (proto_dir == null) {
                    std.debug.print("⚠ --type requires --proto-dir to load schemas. Ignoring --type.\n", .{});
                } else {
                    const topic_key = try allocator.dupe(u8, topic);
                    const type_val = try allocator.dupe(u8, msg_type);
                    try sub_ctx.topic_mapping.put(topic_key, type_val);
                    std.debug.print("📌 Forced mapping: '{s}' → '{s}'\n", .{ topic, msg_type });
                }
            }

            try client.run(&sub_ctx, onMessage);
        } else {
            std.debug.print("Error: --topic is required for subscribe\n", .{});
            try client.disconnect();
        }
    } else if (std.mem.eql(u8, command, "connect")) {
        try client.disconnect();
    } else if (std.mem.eql(u8, command, "discover")) {
        std.debug.print("🔍 Discovering services...\n", .{});

        try client.subscribe("$SYS/discovery/response");
        try client.publish("$SYS/discovery/request", "");

        while (client.connection.?.isActive()) {
            client.connection.?.offset = 0;
            const bytes_read = try client.connection.?.read();
            if (bytes_read == 0) break;

            const buffer = client.connection.?.read_buffer[0..bytes_read];
            const header = try packet.FixedHeader.parse(buffer);

            if (header.packet_type == .PUBLISH) {
                const pub_pkt = try client.parser.parsePublish(buffer);
                if (std.mem.eql(u8, pub_pkt.topic, "$SYS/discovery/response")) {
                    std.debug.print("📥 Received Discovery Response ({d} bytes)\n", .{pub_pkt.payload.len});

                    if (proto_dir) |dir_path| {
                        var registry = pb_registry.SchemaRegistry.init(allocator);
                        defer registry.deinit();

                        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
                        defer dir.close();
                        var it = dir.iterate();
                        while (try it.next()) |entry| {
                            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".proto")) {
                                const content = try dir.readFileAlloc(allocator, entry.name, 1024 * 1024);
                                defer allocator.free(content);
                                var p = pb_parser.ProtoParser.init(allocator, content);
                                try p.parse(&registry);
                            }
                        }

                        if (registry.getMessage("ServiceDiscoveryResponse")) |schema| {
                            var decoder = pb_decoder.Decoder.init(allocator, pub_pkt.payload);
                            var val = try decoder.decodeMessage(schema, &registry);
                            defer val.deinit(allocator);
                            std.debug.print("Services:\n", .{});
                            val.debugPrint();
                            std.debug.print("\n", .{});
                        } else {
                            std.debug.print("⚠ 'ServiceDiscoveryResponse' schema not found in provided --proto-dir\n", .{});
                        }
                    } else {
                        std.debug.print("⚠ --proto-dir not provided, cannot decode response.\n", .{});
                    }
                    break;
                }
            }
        }
        try client.disconnect();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printUsage();
    }
}

const SubscribeContext = struct {
    allocator: std.mem.Allocator,
    registry: pb_registry.SchemaRegistry,
    topic_mapping: std.StringHashMap([]const u8),
};

fn onMessage(ctx_ptr: *anyopaque, topic: []const u8, message: []const u8) void {
    const ctx: *SubscribeContext = @ptrCast(@alignCast(ctx_ptr));
    std.debug.print("📥 [{s}] ({d} bytes): ", .{ topic, message.len });

    // Ignore discovery responses received during normal operation
    if (std.mem.eql(u8, topic, "$SYS/discovery/response")) {
        std.debug.print("[Ignored Discovery Response]\n", .{});
        return;
    }

    var decoded = false;
    if (ctx.topic_mapping.get(topic)) |message_type| {
        if (ctx.registry.getMessage(message_type)) |schema| {
            var decoder = pb_decoder.Decoder.init(ctx.allocator, message);
            if (decoder.decodeMessage(schema, &ctx.registry)) |decoded_val| {
                var val = decoded_val;
                std.debug.print("\n", .{});
                val.debugPrint();
                std.debug.print("\n", .{});
                val.deinit(ctx.allocator);
                decoded = true;
            } else |err| {
                std.debug.print("[Decode Error: {}] ", .{err});
            }
        }
    }

    if (!decoded) {
        std.debug.print("{s}\n", .{message});
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: protomq-cli <command> [options]
        \\
        \\Commands:
        \\  connect      Test connection to broker
        \\  publish      Publish a message to a topic
        \\  subscribe    Subscribe to a topic and listen for messages
        \\
        \\Options:
        \\  --host <ip>       Broker IP (default: 127.0.0.1)
        \\  --port <port>     Broker Port (default: 1883)
        \\  --id <client_id>  Client ID (default: protomq-cli)
        \\  -t, --topic <topic>   Topic to publish/subscribe (Required)
        \\  -m, --message <msg>   Message payload (default: "hello")
        \\  --proto-dir <dir>  Directory with .proto files for encoding
        \\  --type <name>      Protobuf message type for encoding
        \\
        \\Examples:
        \\  protomq-cli subscribe -t "sensors/temp"
        \\  protomq-cli publish -t "sensor/data" --proto-dir schemas --type SensorData -m '{{"device_id": "sensor-1", "temperature": 22.5}}'
        \\
    , .{});
}
