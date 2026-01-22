const std = @import("std");
const types = @import("types.zig");
const registry = @import("registry.zig");

pub const EncoderError = error{
    InvalidTopLevelType,
    TypeMismatch,
    UnknownMessageType,
    MissingTypeName,
    OutOfMemory, // For allocator
};

pub const Encoder = struct {
    allocator: std.mem.Allocator,
    registry: *registry.SchemaRegistry,

    pub fn init(allocator: std.mem.Allocator, reg: *registry.SchemaRegistry) Encoder {
        return Encoder{
            .allocator = allocator,
            .registry = reg,
        };
    }

    pub fn encode(self: *Encoder, value: types.ProtoValue, schema: *types.MessageDefinition) EncoderError![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        errdefer buffer.deinit(self.allocator);

        switch (value) {
            .message => |map| {
                try self.encodeMessageBody(&buffer, map, schema);
            },
            else => return EncoderError.InvalidTopLevelType,
        }
        return buffer.toOwnedSlice(self.allocator);
    }

    // Internal helper that writes to an existing buffer
    fn encodeMessageBody(self: *Encoder, buffer: *std.ArrayListUnmanaged(u8), map: std.AutoHashMap(u32, types.ProtoValue), schema: *types.MessageDefinition) EncoderError!void {
        var it = map.iterator();
        while (it.next()) |entry| {
            const field_num = entry.key_ptr.*;
            const val = entry.value_ptr.*;

            // We rely on Schema to determine how to encode (especially wire types and packing)
            if (schema.fields.get(field_num)) |field_def| {
                if (val == .repeated) {
                    // Check for packed? (Not implemented yet, assume non-packed for primitives for now unless proto3 default?)
                    // Proto3 defaults to packed for scalars.
                    // For now, simple repeated.
                    for (val.repeated.items) |item| {
                        try self.encodeField(buffer, field_num, item.*, field_def);
                    }
                } else {
                    try self.encodeField(buffer, field_num, val, field_def);
                }
            } else {
                // Ignore unknown fields in encoding for now (or Passthrough?)
            }
        }
    }

    fn encodeField(self: *Encoder, buffer: *std.ArrayListUnmanaged(u8), field_num: u32, value: types.ProtoValue, def: types.FieldDefinition) EncoderError!void {
        const wire_type = getWireType(def.type);
        const tag = (field_num << 3) | @intFromEnum(wire_type);

        try self.writeVarint(buffer, tag);

        switch (value) {
            .varint => |v| try self.writeVarint(buffer, v),
            .fixed64 => |v| try self.writeFixed64(buffer, v),
            .fixed32 => |v| try self.writeFixed32(buffer, v),
            .bytes => |b| {
                try self.writeVarint(buffer, b.len);
                try buffer.appendSlice(self.allocator, b);
            },
            .message => |m| {
                // Recurse
                if (def.type_name) |tn| {
                    if (self.registry.getMessage(tn)) |nested_schema| {
                        // We need to encode body to temporary buffer to get size
                        var sub_buffer = std.ArrayListUnmanaged(u8){};
                        defer sub_buffer.deinit(self.allocator);

                        try self.encodeMessageBody(&sub_buffer, m, nested_schema);

                        // Write length
                        try self.writeVarint(buffer, sub_buffer.items.len);
                        // Write data
                        try buffer.appendSlice(self.allocator, sub_buffer.items);
                    } else return EncoderError.UnknownMessageType;
                } else return EncoderError.MissingTypeName;
            },
            else => return EncoderError.TypeMismatch,
        }
    }

    fn getWireType(ft: types.FieldType) types.WireType {
        switch (ft) {
            .Int32, .Int64, .UInt32, .UInt64, .Bool, .Enum, .SInt32, .SInt64 => return .Varint,
            .Fixed64, .SFixed64, .Double => return .Fixed64,
            .String, .Bytes, .Message => return .LengthDelimited,
            .Fixed32, .SFixed32, .Float => return .Fixed32,
            else => return .LengthDelimited, // Fallback
        }
    }

    fn writeVarint(self: *Encoder, buffer: *std.ArrayListUnmanaged(u8), value: u64) EncoderError!void {
        var v = value;
        while (v >= 0x80) {
            try buffer.append(self.allocator, @as(u8, @intCast((v & 0x7F) | 0x80)));
            v >>= 7;
        }
        try buffer.append(self.allocator, @as(u8, @intCast(v)));
    }

    fn writeFixed64(self: *Encoder, buffer: *std.ArrayListUnmanaged(u8), value: u64) EncoderError!void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .little);
        try buffer.appendSlice(self.allocator, &bytes);
    }

    fn writeFixed32(self: *Encoder, buffer: *std.ArrayListUnmanaged(u8), value: u32) EncoderError!void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try buffer.appendSlice(self.allocator, &bytes);
    }
};
