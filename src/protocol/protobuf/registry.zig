const std = @import("std");
const types = @import("types.zig");

/// Registry for Protobuf Schemas
pub const SchemaRegistry = struct {
    allocator: std.mem.Allocator,
    // Message Name (e.g., "package.Message") -> Definition
    messages: std.StringHashMap(*types.MessageDefinition),

    pub fn init(allocator: std.mem.Allocator) SchemaRegistry {
        return SchemaRegistry{
            .allocator = allocator,
            .messages = std.StringHashMap(*types.MessageDefinition).init(allocator),
        };
    }

    pub fn deinit(self: *SchemaRegistry) void {
        var it = self.messages.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.messages.deinit();
    }

    /// Register a new message definition. Takes ownership of the pointer.
    pub fn registerMessage(self: *SchemaRegistry, message: *types.MessageDefinition) !void {
        try self.messages.put(message.name, message);
    }

    pub fn getMessage(self: *SchemaRegistry, name: []const u8) ?*types.MessageDefinition {
        return self.messages.get(name);
    }
};
