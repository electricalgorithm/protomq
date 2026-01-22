const std = @import("std");
const pb_registry = @import("../protocol/protobuf/registry.zig");
const pb_parser = @import("../protocol/protobuf/parser.zig");
const pb_types = @import("../protocol/protobuf/types.zig");

pub const SchemaManager = struct {
    allocator: std.mem.Allocator,
    registry: pb_registry.SchemaRegistry,
    // MQTT Topic Pattern -> Message Type Name
    topic_mapping: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) SchemaManager {
        return SchemaManager{
            .allocator = allocator,
            .registry = pb_registry.SchemaRegistry.init(allocator),
            .topic_mapping = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *SchemaManager) void {
        self.registry.deinit();
        var it = self.topic_mapping.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.topic_mapping.deinit();
    }

    /// Load all .proto files from a directory
    pub fn loadSchemasFromDir(self: *SchemaManager, dir_path: []const u8) !void {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".proto")) {
                const file_content = try dir.readFileAlloc(self.allocator, entry.name, 10 * 1024 * 1024);
                defer self.allocator.free(file_content);

                var parser = pb_parser.ProtoParser.init(self.allocator, file_content);
                try parser.parse(&self.registry);

                std.debug.print("Loaded schema: {s}\n", .{entry.name});
            }
        }
    }

    /// Link an MQTT topic to a Protobuf message type
    pub fn mapTopicToSchema(self: *SchemaManager, topic: []const u8, message_type: []const u8) !void {
        const topic_dupe = try self.allocator.dupe(u8, topic);
        const msg_dupe = try self.allocator.dupe(u8, message_type);
        try self.topic_mapping.put(topic_dupe, msg_dupe);
    }

    pub fn getMessageDefinitionForTopic(self: *SchemaManager, topic: []const u8) ?*pb_types.MessageDefinition {
        // Simple exact match for now. Wildcards could be added later.
        if (self.topic_mapping.get(topic)) |msg_name| {
            return self.registry.getMessage(msg_name);
        }
        return null;
    }
};
