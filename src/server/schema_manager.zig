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

    pub fn getDiscoveryValue(self: *SchemaManager, allocator: std.mem.Allocator) !pb_types.ProtoValue {
        var root_map = std.AutoHashMap(u32, pb_types.ProtoValue).init(allocator);
        // We use a simple errdefer approach: if we fail before returning,
        // we might leak partial structures if we are not careful.
        // For simplicity in this step, we assume allocs succeed or we accept leak on crash for now (MVP).
        // specific cleanups would be verbose.

        var schemas_list = std.ArrayListUnmanaged(*pb_types.ProtoValue){};

        var it = self.topic_mapping.iterator();
        while (it.next()) |entry| {
            const topic = entry.key_ptr.*;
            const msg_type = entry.value_ptr.*;

            var info_map = std.AutoHashMap(u32, pb_types.ProtoValue).init(allocator);

            // Tag 1: topic
            const topic_copy = try allocator.dupe(u8, topic);
            try info_map.put(1, .{ .bytes = topic_copy });

            // Tag 2: message_type
            const type_copy = try allocator.dupe(u8, msg_type);
            try info_map.put(2, .{ .bytes = type_copy });

            // Tag 3: schema_source
            if (self.registry.getMessage(msg_type)) |def| {
                const source_copy = try allocator.dupe(u8, def.source_code);
                // std.debug.print("DEBUG: Found schema for {s}, source len: {d}\n", .{ msg_type, def.source_code.len });
                try info_map.put(3, .{ .bytes = source_copy });
            }

            const info_ptr = try allocator.create(pb_types.ProtoValue);
            info_ptr.* = .{ .message = info_map };

            try schemas_list.append(allocator, info_ptr);
        }

        try root_map.put(1, .{ .repeated = schemas_list });

        return pb_types.ProtoValue{ .message = root_map };
    }
};
