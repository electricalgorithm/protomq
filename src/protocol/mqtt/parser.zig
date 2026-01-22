const std = @import("std");
const packet = @import("packet.zig");

/// MQTT Protocol Parser
pub const Parser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return Parser{
            .allocator = allocator,
        };
    }

    /// Parse MQTT string (length-prefixed)
    pub fn parseString(buffer: []const u8, offset: *usize) ![]const u8 {
        if (offset.* + 2 > buffer.len) {
            return error.InsufficientData;
        }

        const len = (@as(u16, buffer[offset.*]) << 8) | buffer[offset.* + 1];
        offset.* += 2;

        if (offset.* + len > buffer.len) {
            return error.InsufficientData;
        }

        const str = buffer[offset.* .. offset.* + len];
        offset.* += len;

        return str;
    }

    /// Parse CONNECT packet
    pub fn parseConnect(self: *Parser, buffer: []const u8) !packet.ConnectPacket {
        var offset: usize = 0;

        // Parse fixed header first to skip it
        const header = try packet.FixedHeader.parse(buffer);
        offset = header.size();

        // Protocol name
        const protocol_name = try parseString(buffer, &offset);

        // Protocol level
        if (offset >= buffer.len) return error.InsufficientData;
        const protocol_level = buffer[offset];
        offset += 1;

        // Connect flags
        if (offset >= buffer.len) return error.InsufficientData;
        const flags_byte = buffer[offset];
        offset += 1;

        const flags = packet.ConnectPacket.ConnectFlags{
            .clean_session = @intCast((flags_byte >> 1) & 0x01),
            .will_flag = @intCast((flags_byte >> 2) & 0x01),
            .will_qos = @intCast((flags_byte >> 3) & 0x03),
            .will_retain = @intCast((flags_byte >> 5) & 0x01),
            .password_flag = @intCast((flags_byte >> 6) & 0x01),
            .username_flag = @intCast((flags_byte >> 7) & 0x01),
        };

        // Keep alive
        if (offset + 2 > buffer.len) return error.InsufficientData;
        const keep_alive = (@as(u16, buffer[offset]) << 8) | buffer[offset + 1];
        offset += 2;

        // Client ID
        const client_id = try parseString(buffer, &offset);

        // Will topic and message (if will_flag set)
        var will_topic: ?[]const u8 = null;
        var will_message: ?[]const u8 = null;
        if (flags.will_flag == 1) {
            will_topic = try parseString(buffer, &offset);
            will_message = try parseString(buffer, &offset);
        }

        // Username (if username_flag set)
        var username: ?[]const u8 = null;
        if (flags.username_flag == 1) {
            username = try parseString(buffer, &offset);
        }

        // Password (if password_flag set)
        var password: ?[]const u8 = null;
        if (flags.password_flag == 1) {
            password = try parseString(buffer, &offset);
        }

        _ = self;

        return packet.ConnectPacket{
            .protocol_name = protocol_name,
            .protocol_level = protocol_level,
            .flags = flags,
            .keep_alive = keep_alive,
            .client_id = client_id,
            .will_topic = will_topic,
            .will_message = will_message,
            .username = username,
            .password = password,
        };
    }

    /// Parse PUBLISH packet
    pub fn parsePublish(self: *Parser, buffer: []const u8) !packet.PublishPacket {
        var offset: usize = 0;

        const header = try packet.FixedHeader.parse(buffer);
        offset = header.size();

        const dup = (header.flags & 0x08) != 0;
        const qos = @as(packet.QoS, @enumFromInt((header.flags >> 1) & 0x03));
        const retain = (header.flags & 0x01) != 0;

        // Topic name
        const topic = try parseString(buffer, &offset);

        // Packet ID (only for QoS > 0)
        var packet_id: ?u16 = null;
        if (qos != .at_most_once) {
            if (offset + 2 > buffer.len) return error.InsufficientData;
            packet_id = (@as(u16, buffer[offset]) << 8) | buffer[offset + 1];
            offset += 2;
        }

        // Payload (rest of the packet)
        const payload = buffer[offset..];

        _ = self;

        return packet.PublishPacket{
            .topic = topic,
            .qos = qos,
            .retain = retain,
            .dup = dup,
            .packet_id = packet_id,
            .payload = payload,
        };
    }

    /// Parse SUBSCRIBE packet
    pub fn parseSubscribe(self: *Parser, buffer: []const u8) !packet.SubscribePacket {
        var offset: usize = 0;

        const header = try packet.FixedHeader.parse(buffer);
        offset = header.size();

        // Packet ID
        if (offset + 2 > buffer.len) return error.InsufficientData;
        const packet_id = (@as(u16, buffer[offset]) << 8) | buffer[offset + 1];
        offset += 2;

        // Parse topic filters
        var topics: std.ArrayList(packet.SubscribePacket.TopicFilter) = .empty;

        while (offset < buffer.len) {
            const topic = try parseString(buffer, &offset);

            if (offset >= buffer.len) return error.InsufficientData;
            const qos_byte = buffer[offset];
            offset += 1;

            const qos = @as(packet.QoS, @enumFromInt(qos_byte & 0x03));

            try topics.append(self.allocator, .{
                .topic = topic,
                .qos = qos,
            });
        }

        return packet.SubscribePacket{
            .packet_id = packet_id,
            .topics = try topics.toOwnedSlice(self.allocator),
        };
    }

    /// Parse UNSUBSCRIBE packet
    pub fn parseUnsubscribe(self: *Parser, buffer: []const u8) ![][]const u8 {
        var offset: usize = 0;

        const header = try packet.FixedHeader.parse(buffer);
        offset = header.size();

        // Skip packet ID
        offset += 2;

        // Parse topics
        var topics: std.ArrayList([]const u8) = .empty;

        while (offset < buffer.len) {
            const topic = try parseString(buffer, &offset);
            try topics.append(self.allocator, topic);
        }

        return try topics.toOwnedSlice(self.allocator);
    }
};

// Tests

test "parseString" {
    // String "MQTT" encoded as: 0x00 0x04 'M' 'Q' 'T' 'T'
    const data = [_]u8{ 0x00, 0x04, 'M', 'Q', 'T', 'T' };
    var offset: usize = 0;

    const result = try Parser.parseString(&data, &offset);

    try std.testing.expectEqualStrings("MQTT", result);
    try std.testing.expectEqual(@as(usize, 6), offset);
}

test "Parser parseConnect" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator);

    // Minimal CONNECT packet
    const data = [_]u8{
        0x10, 0x10, // Fixed header: CONNECT, remaining length = 16
        0x00, 0x04, 'M', 'Q', 'T', 'T', // Protocol name
        0x04, // Protocol level
        0x02, // Flags: clean session
        0x00, 0x3C, // Keep alive = 60
        0x00, 0x04, 't', 'e', 's', 't', // Client ID = "test"
    };

    defer allocator.free(data[0..0]); // Dummy defer for consistency

    const connect = try parser.parseConnect(&data);

    try std.testing.expectEqualStrings("MQTT", connect.protocol_name);
    try std.testing.expectEqual(@as(u8, 4), connect.protocol_level);
    try std.testing.expectEqual(@as(u1, 1), connect.flags.clean_session);
    try std.testing.expectEqual(@as(u16, 60), connect.keep_alive);
    try std.testing.expectEqualStrings("test", connect.client_id);
}
