const std = @import("std");
const types = @import("types.zig");
const registry = @import("registry.zig");
const parser = @import("parser.zig");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");

test "Protobuf Codec - Round Trip" {
    const allocator = std.testing.allocator;

    // 1. Setup Registry & Schema
    var reg = registry.SchemaRegistry.init(allocator);
    defer reg.deinit();

    const proto_source =
        \\syntax = "proto3";
        \\package test;
        \\
        \\message Address {
        \\  string street = 1;
        \\  int32 number = 2;
        \\}
        \\
        \\message Person {
        \\  string name = 1;
        \\  int32 id = 2;
        \\  repeated string emails = 3;
        \\  Address address = 4;
        \\}
    ;

    var p = parser.ProtoParser.init(allocator, proto_source);
    try p.parse(&reg);

    const person_schema = reg.getMessage("Person").?;

    // 2. Construct ProtoValue Manually
    var person_map = std.AutoHashMap(u32, types.ProtoValue).init(allocator);

    // name = "Alice"
    try person_map.put(1, types.ProtoValue{ .bytes = try allocator.dupe(u8, "Alice") });
    // id = 101
    try person_map.put(2, types.ProtoValue{ .varint = 101 });

    // emails = ["a@b.com", "c@d.com"]
    var emails_list = std.ArrayListUnmanaged(*types.ProtoValue){};

    const e1 = try allocator.create(types.ProtoValue);
    e1.* = types.ProtoValue{ .bytes = try allocator.dupe(u8, "a@b.com") };
    try emails_list.append(allocator, e1);

    const e2 = try allocator.create(types.ProtoValue);
    e2.* = types.ProtoValue{ .bytes = try allocator.dupe(u8, "c@d.com") };
    try emails_list.append(allocator, e2);

    try person_map.put(3, types.ProtoValue{ .repeated = emails_list });

    // address = { street: "Main St", number: 42 }
    var addr_map = std.AutoHashMap(u32, types.ProtoValue).init(allocator);
    try addr_map.put(1, types.ProtoValue{ .bytes = try allocator.dupe(u8, "Main St") });
    try addr_map.put(2, types.ProtoValue{ .varint = 42 });
    try person_map.put(4, types.ProtoValue{ .message = addr_map });

    var original = types.ProtoValue{ .message = person_map };
    defer original.deinit(allocator);

    // 3. Encode
    var enc = encoder.Encoder.init(allocator, &reg);
    const bytes = try enc.encode(original, person_schema);
    defer allocator.free(bytes);

    // 4. Decode
    var dec = decoder.Decoder.init(allocator, bytes);
    var decoded = try dec.decodeMessage(person_schema, &reg);
    defer decoded.deinit(allocator);

    // 5. Verify
    const d_map = decoded.message;

    // Check Name
    const name_val = d_map.get(1).?;
    try std.testing.expectEqualStrings("Alice", name_val.bytes);

    // Check ID
    const id_val = d_map.get(2).?;
    try std.testing.expectEqual(@as(u64, 101), id_val.varint);

    // Check Emails
    const emails_val = d_map.get(3).?;
    try std.testing.expectEqual(@as(usize, 2), emails_val.repeated.items.len);
    try std.testing.expectEqualStrings("a@b.com", emails_val.repeated.items[0].*.bytes);
    try std.testing.expectEqualStrings("c@d.com", emails_val.repeated.items[1].*.bytes);

    // Check Address
    const addr_val = d_map.get(4).?;
    const am = addr_val.message;
    try std.testing.expectEqualStrings("Main St", am.get(1).?.bytes);
    try std.testing.expectEqual(@as(u64, 42), am.get(2).?.varint);
}
