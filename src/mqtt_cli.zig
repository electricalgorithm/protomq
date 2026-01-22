const std = @import("std");
const MqttClient = @import("client/client.zig").MqttClient;
const pb_registry = @import("protocol/protobuf/registry.zig");
const pb_parser = @import("protocol/protobuf/parser.zig");
const pb_encoder = @import("protocol/protobuf/encoder.zig");
const pb_json = @import("protocol/protobuf/json_converter.zig");

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

            try client.run(onMessage);
        } else {
            std.debug.print("Error: --topic is required for subscribe\n", .{});
            try client.disconnect();
        }
    } else if (std.mem.eql(u8, command, "connect")) {
        try client.disconnect();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printUsage();
    }
}

fn onMessage(topic: []const u8, message: []const u8) void {
    std.debug.print("📥 [{s}] ({d} bytes): {s}\n", .{ topic, message.len, message });
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
