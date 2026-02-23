const std = @import("std");
const types = @import("types.zig");
const registry = @import("registry.zig");

pub const DecoderError = error{
    Truncated,
    Overflow,
    UnsupportedWireType,
    UnknownMessageType,
    MissingRegistrySupport,
    MissingTypeName,
    OutOfMemory,
};

pub const Decoder = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    cursor: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Decoder {
        return Decoder{
            .allocator = allocator,
            .source = source,
            .cursor = 0,
        };
    }

    pub fn decodeMessage(self: *Decoder, schema: *types.MessageDefinition, reg: *registry.SchemaRegistry) DecoderError!types.ProtoValue {
        var map = std.AutoHashMap(u32, types.ProtoValue).init(self.allocator);
        errdefer {
            var it = map.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            map.deinit();
        }

        while (self.cursor < self.source.len) {
            // Read Tag
            const tag_val = try self.readVarint();
            const field_num = @as(u32, @intCast(tag_val >> 3));
            const wire_type = @as(types.WireType, @enumFromInt(tag_val & 0x07));

            // Lookup Field
            if (schema.fields.get(field_num)) |field_def| {
                const value = try self.decodeValue(wire_type, field_def, reg);

                // Handle Repeated
                if (field_def.label == .Repeated) {
                    const result = try map.getOrPut(field_num);
                    if (!result.found_existing) {
                        result.value_ptr.* = types.ProtoValue{ .repeated = std.ArrayListUnmanaged(*types.ProtoValue){} };
                    }
                    const ptr = try self.allocator.create(types.ProtoValue);
                    ptr.* = value;
                    try result.value_ptr.repeated.append(self.allocator, ptr);
                } else {
                    // Overwrite if exists (last wins)
                    if (try map.fetchPut(field_num, value)) |kv| {
                        var old = kv.value;
                        old.deinit(self.allocator);
                    }
                }
            } else {
                try self.skipField(wire_type);
            }
        }

        return types.ProtoValue{ .message = map };
    }

    fn decodeValue(self: *Decoder, wire_type: types.WireType, field: types.FieldDefinition, reg: *registry.SchemaRegistry) DecoderError!types.ProtoValue {
        switch (wire_type) {
            .Varint => {
                const val = try self.readVarint();
                return types.ProtoValue{ .varint = val };
            },
            .Fixed32 => {
                const val = try self.readFixed32();
                if (field.type == .Float) {
                    return types.ProtoValue{ .float32 = @bitCast(val) };
                }
                return types.ProtoValue{ .fixed32 = val };
            },
            .Fixed64 => {
                const val = try self.readFixed64();
                if (field.type == .Double) {
                    return types.ProtoValue{ .float64 = @bitCast(val) };
                }
                return types.ProtoValue{ .fixed64 = val };
            },
            .LengthDelimited => {
                const len = try self.readVarint();
                const usize_len = @as(usize, @intCast(len));
                if (self.cursor + usize_len > self.source.len) return DecoderError.Truncated;

                const data = self.source[self.cursor .. self.cursor + usize_len];
                self.cursor += usize_len;

                if (field.type == .String) {
                    return types.ProtoValue{ .bytes = try self.allocator.dupe(u8, data) };
                } else if (field.type == .Bytes) {
                    return types.ProtoValue{ .bytes = try self.allocator.dupe(u8, data) };
                } else if (field.type == .Message) {
                    // Nested Message
                    if (field.type_name) |tn| {
                        if (reg.getMessage(tn)) |nested_schema| {
                            var sub_decoder = Decoder.init(self.allocator, data);
                            return try sub_decoder.decodeMessage(nested_schema, reg);
                        } else {
                            // std.debug.print("Undefined message type: {s}\n", .{tn});
                            return DecoderError.UnknownMessageType;
                        }
                    } else {
                        return DecoderError.MissingTypeName;
                    }
                } else {
                    // Treat as bytes if packing not supported/known
                    return types.ProtoValue{ .bytes = try self.allocator.dupe(u8, data) };
                }
            },
            else => return DecoderError.UnsupportedWireType,
        }
    }

    fn skipField(self: *Decoder, wire_type: types.WireType) DecoderError!void {
        switch (wire_type) {
            .Varint => _ = try self.readVarint(),
            .Fixed64 => self.cursor += 8,
            .LengthDelimited => {
                const len = try self.readVarint();
                self.cursor += @as(usize, @intCast(len));
            },
            .Fixed32 => self.cursor += 4,
            else => return DecoderError.UnsupportedWireType,
        }
        if (self.cursor > self.source.len) return DecoderError.Truncated;
    }

    // Primitives
    fn readVarint(self: *Decoder) DecoderError!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;

        while (self.cursor < self.source.len) {
            const b = self.source[self.cursor];
            self.cursor += 1;

            result |= @as(u64, b & 0x7F) << shift;
            if ((b & 0x80) == 0) return result;

            shift += 7;
            if (shift >= 64) return DecoderError.Overflow;
        }
        return DecoderError.Truncated;
    }

    fn readFixed64(self: *Decoder) DecoderError!u64 {
        if (self.cursor + 8 > self.source.len) return DecoderError.Truncated;
        const slice = self.source[self.cursor .. self.cursor + 8];
        self.cursor += 8;
        return std.mem.readInt(u64, slice[0..8], .little);
    }

    fn readFixed32(self: *Decoder) DecoderError!u32 {
        if (self.cursor + 4 > self.source.len) return DecoderError.Truncated;
        const slice = self.source[self.cursor .. self.cursor + 4];
        self.cursor += 4;
        return std.mem.readInt(u32, slice[0..4], .little);
    }
};
