const std = @import("std");

/// Wire Type from Protobuf Spec
pub const WireType = enum(u3) {
    Varint = 0,
    Fixed64 = 1,
    LengthDelimited = 2,
    StartGroup = 3,
    EndGroup = 4,
    Fixed32 = 5,
};

/// Scalar Type from Protobuf Spec
pub const FieldType = enum {
    Double,
    Float,
    Int64,
    UInt64,
    Int32,
    Fixed64,
    Fixed32,
    Bool,
    String,
    Group, // Deprecated but exists
    Message,
    Bytes,
    UInt32,
    Enum,
    SFixed32,
    SFixed64,
    SInt32,
    SInt64,
};

pub const FieldLabel = enum {
    Optional,
    Required, // Proto2 only, treated as Optional in Proto3
    Repeated,
};

/// Definition of a single field in a .proto message
pub const FieldDefinition = struct {
    name: []const u8,
    tag: u32,
    type: FieldType,
    label: FieldLabel,
    type_name: ?[]const u8 = null, // For Message/Enum types, e.g., ".package.Message"
};

/// Definition of a message type
pub const MessageDefinition = struct {
    name: []const u8,
    // Tag -> Field Mapping
    fields: std.AutoHashMap(u32, FieldDefinition),
    // Full source code of the .proto file defining this message (for discovery)
    source_code: []const u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, source: []const u8) !MessageDefinition {
        return MessageDefinition{
            .name = try allocator.dupe(u8, name),
            .fields = std.AutoHashMap(u32, FieldDefinition).init(allocator),
            .source_code = try allocator.dupe(u8, source),
        };
    }

    pub fn deinit(self: *MessageDefinition, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.source_code);
        var it = self.fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.name);
            if (entry.value_ptr.type_name) |tn| {
                allocator.free(tn);
            }
        }
        self.fields.deinit();
    }
};

/// Generic Value holder for Dynamic Protobuf
pub const ProtoValue = union(enum) {
    varint: u64,
    fixed64: u64,
    fixed32: u32,
    bytes: []u8, // string or bytes
    message: std.AutoHashMap(u32, ProtoValue), // nested message
    repeated: std.ArrayListUnmanaged(*ProtoValue), // repeated field (pointers to break recursion, unmanaged to fix compilation)

    pub fn deinit(self: *ProtoValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .bytes => |b| allocator.free(b),
            .message => |*m| {
                var it = m.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                m.deinit();
            },
            .repeated => |*list| {
                for (list.items) |item| {
                    item.deinit(allocator);
                    allocator.destroy(item);
                }
                list.deinit(allocator);
            },
            else => {},
        }
    }

    // Helper to traverse/debug
    pub fn debugPrint(
        self: ProtoValue,
    ) void {
        const std_debug = @import("std").debug;
        switch (self) {
            .varint => |v| std_debug.print("{d}", .{v}),
            .fixed64 => |v| std_debug.print("{d}", .{v}),
            .fixed32 => |v| std_debug.print("{d}", .{v}),
            .bytes => |b| {
                std_debug.print("\"", .{});
                for (b) |c| {
                    if (std.ascii.isPrint(c)) {
                        std_debug.print("{c}", .{c});
                    } else {
                        std_debug.print("\\x{x:0>2}", .{c});
                    }
                }
                std_debug.print("\"", .{});
            },
            .message => |m| {
                std_debug.print("{{", .{});
                var it = m.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) std_debug.print(", ", .{});
                    std_debug.print("{d}: ", .{entry.key_ptr.*});
                    entry.value_ptr.debugPrint();
                    first = false;
                }
                std_debug.print("}}", .{});
            },
            .repeated => |list| {
                std_debug.print("[", .{});
                for (list.items, 0..) |item, i| {
                    if (i > 0) std_debug.print(", ", .{});
                    item.debugPrint();
                }
                std_debug.print("]", .{});
            },
        }
    }
};
