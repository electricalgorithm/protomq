const std = @import("std");
const pb_types = @import("types.zig");
const pb_registry = @import("registry.zig");

pub const ConversionError = error{
    TypeMismatch,
    MissingField,
    InvalidJson,
    UnknownMessageType,
    OutOfMemory,
};

pub fn jsonToProtoValue(allocator: std.mem.Allocator, registry: *pb_registry.SchemaRegistry, json_val: std.json.Value, def: *pb_types.MessageDefinition) ConversionError!pb_types.ProtoValue {
    var map = std.AutoHashMap(u32, pb_types.ProtoValue).init(allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        map.deinit();
    }

    const obj = switch (json_val) {
        .object => |o| o,
        else => return error.InvalidJson,
    };

    var it = def.fields.iterator();
    while (it.next()) |entry| {
        const field_def = entry.value_ptr.*;
        if (obj.get(field_def.name)) |val| {
            const proto_val = try convertValue(allocator, registry, val, field_def);
            try map.put(field_def.tag, proto_val);
        } else if (field_def.label == .Required) {
            return error.MissingField;
        }
    }

    return pb_types.ProtoValue{ .message = map };
}

fn convertValue(allocator: std.mem.Allocator, registry: *pb_registry.SchemaRegistry, val: std.json.Value, field_def: pb_types.FieldDefinition) ConversionError!pb_types.ProtoValue {
    if (field_def.label == .Repeated) {
        const array = switch (val) {
            .array => |a| a,
            else => return error.TypeMismatch,
        };

        var list = std.ArrayListUnmanaged(*pb_types.ProtoValue){};
        errdefer {
            for (list.items) |item| {
                item.deinit(allocator);
                allocator.destroy(item);
            }
            list.deinit(allocator);
        }

        for (array.items) |item| {
            var elem_def = field_def;
            elem_def.label = .Optional;

            const proto_val = try convertSingleValue(allocator, registry, item, elem_def);
            const ptr = try allocator.create(pb_types.ProtoValue);
            ptr.* = proto_val;
            try list.append(allocator, ptr);
        }

        return pb_types.ProtoValue{ .repeated = list };
    } else {
        return try convertSingleValue(allocator, registry, val, field_def);
    }
}

fn convertSingleValue(allocator: std.mem.Allocator, registry: *pb_registry.SchemaRegistry, val: std.json.Value, field_def: pb_types.FieldDefinition) ConversionError!pb_types.ProtoValue {
    switch (field_def.type) {
        .Int32, .Int64, .UInt32, .UInt64, .SInt32, .SInt64, .Enum => {
            const int_val = switch (val) {
                .integer => |i| @as(u64, @intCast(i)),
                .float => |f| @as(u64, @intFromFloat(f)),
                .number_string => |s| std.fmt.parseInt(u64, s, 10) catch return error.TypeMismatch,
                else => return error.TypeMismatch,
            };
            return pb_types.ProtoValue{ .varint = int_val };
        },
        .Bool => {
            const bool_val = switch (val) {
                .bool => |b| b,
                else => return error.TypeMismatch,
            };
            return pb_types.ProtoValue{ .varint = if (bool_val) @as(u64, 1) else 0 };
        },
        .Float, .Fixed32, .SFixed32 => {
            const float_val = switch (val) {
                .float => |f| @as(f32, @floatCast(f)),
                .integer => |i| @as(f32, @floatFromInt(i)),
                .number_string => |s| std.fmt.parseFloat(f32, s) catch return error.TypeMismatch,
                else => return error.TypeMismatch,
            };
            return pb_types.ProtoValue{ .fixed32 = @bitCast(float_val) };
        },
        .Double, .Fixed64, .SFixed64 => {
            const double_val = switch (val) {
                .float => |f| f,
                .integer => |i| @as(f64, @floatFromInt(i)),
                .number_string => |s| std.fmt.parseFloat(f64, s) catch return error.TypeMismatch,
                else => return error.TypeMismatch,
            };
            return pb_types.ProtoValue{ .fixed64 = @bitCast(double_val) };
        },
        .String, .Bytes => {
            const str_val = switch (val) {
                .string => |s| s,
                else => return error.TypeMismatch,
            };
            return pb_types.ProtoValue{ .bytes = try allocator.dupe(u8, str_val) };
        },
        .Message => {
            if (field_def.type_name) |tn| {
                if (registry.getMessage(tn)) |nested_def| {
                    return try jsonToProtoValue(allocator, registry, val, nested_def);
                } else {
                    return error.UnknownMessageType;
                }
            } else {
                return error.TypeMismatch;
            }
        },
        else => return error.TypeMismatch,
    }
}
