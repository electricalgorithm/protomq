const std = @import("std");

/// MQTT Packet Types (v3.1.1)
pub const PacketType = enum(u4) {
    RESERVED = 0,
    CONNECT = 1,
    CONNACK = 2,
    PUBLISH = 3,
    PUBACK = 4,
    PUBREC = 5,
    PUBREL = 6,
    PUBCOMP = 7,
    SUBSCRIBE = 8,
    SUBACK = 9,
    UNSUBSCRIBE = 10,
    UNSUBACK = 11,
    PINGREQ = 12,
    PINGRESP = 13,
    DISCONNECT = 14,
    RESERVED2 = 15,
};

/// MQTT Connect Return Codes
pub const ConnectReturnCode = enum(u8) {
    accepted = 0,
    unacceptable_protocol = 1,
    identifier_rejected = 2,
    server_unavailable = 3,
    bad_credentials = 4,
    not_authorized = 5,
};

/// QoS levels (only QoS 0 supported in MVP)
pub const QoS = enum(u2) {
    at_most_once = 0,
    at_least_once = 1,
    exactly_once = 2,
};

/// MQTT Fixed Header
pub const FixedHeader = struct {
    packet_type: PacketType,
    flags: u4,
    remaining_length: u32,

    /// Parse fixed header from buffer
    pub fn parse(buffer: []const u8) !FixedHeader {
        if (buffer.len < 2) {
            return error.InsufficientData;
        }

        const byte1 = buffer[0];
        const packet_type = @as(PacketType, @enumFromInt((byte1 >> 4) & 0x0F));
        const flags: u4 = @intCast(byte1 & 0x0F);

        // Parse remaining length (variable length encoding)
        var remaining_length: u32 = 0;
        var multiplier: u32 = 1;
        var index: usize = 1;

        while (true) {
            if (index >= buffer.len) {
                return error.InsufficientData;
            }

            const encoded_byte = buffer[index];
            remaining_length += (encoded_byte & 0x7F) * multiplier;

            if ((encoded_byte & 0x80) == 0) {
                break;
            }

            multiplier *= 128;
            index += 1;

            if (index > 4) {
                return error.MalformedRemainingLength;
            }
        }

        return FixedHeader{
            .packet_type = packet_type,
            .flags = flags,
            .remaining_length = remaining_length,
        };
    }

    /// Calculate the size of the fixed header in bytes
    pub fn size(self: FixedHeader) usize {
        var len: usize = 1; // First byte
        var remaining = self.remaining_length;

        // Count bytes needed for remaining length
        len += 1;
        while (remaining > 127) {
            remaining /= 128;
            len += 1;
        }

        return len;
    }

    /// Encode fixed header to buffer
    pub fn encode(self: FixedHeader, buffer: []u8) !usize {
        if (buffer.len < 2) {
            return error.BufferTooSmall;
        }

        // First byte: packet type and flags
        buffer[0] = (@as(u8, @intFromEnum(self.packet_type)) << 4) | @as(u8, self.flags);

        // Encode remaining length
        var index: usize = 1;
        var remaining = self.remaining_length;

        while (true) {
            if (index >= buffer.len) {
                return error.BufferTooSmall;
            }

            var encoded_byte: u8 = @intCast(remaining % 128);
            remaining /= 128;

            if (remaining > 0) {
                encoded_byte |= 0x80;
            }

            buffer[index] = encoded_byte;
            index += 1;

            if (remaining == 0) {
                break;
            }
        }

        return index;
    }
};

/// MQTT CONNECT packet
pub const ConnectPacket = struct {
    protocol_name: []const u8,
    protocol_level: u8,
    flags: ConnectFlags,
    keep_alive: u16,
    client_id: []const u8,
    will_topic: ?[]const u8,
    will_message: ?[]const u8,
    username: ?[]const u8,
    password: ?[]const u8,

    pub const ConnectFlags = packed struct {
        reserved: u1 = 0,
        clean_session: u1,
        will_flag: u1,
        will_qos: u2,
        will_retain: u1,
        password_flag: u1,
        username_flag: u1,
    };
    pub fn encode(self: ConnectPacket, buffer: []u8) !usize {
        var len: usize = 0;

        // Protocol name (MQTT) + Level + Flags + Keep Alive
        len += 2 + self.protocol_name.len + 1 + 1 + 2;

        // Payload length
        len += 2 + self.client_id.len;
        if (self.will_topic) |t| len += 2 + t.len;
        if (self.will_message) |m| len += 2 + m.len;
        if (self.username) |u| len += 2 + u.len;
        if (self.password) |p| len += 2 + p.len;

        const header = FixedHeader{
            .packet_type = .CONNECT,
            .flags = 0,
            .remaining_length = @intCast(len),
        };

        var offset = try header.encode(buffer);
        if (buffer.len < offset + len) return error.BufferTooSmall;

        // Variable Header
        // Protocol Name
        buffer[offset] = @intCast(self.protocol_name.len >> 8);
        buffer[offset + 1] = @intCast(self.protocol_name.len & 0xFF);
        offset += 2;
        @memcpy(buffer[offset .. offset + self.protocol_name.len], self.protocol_name);
        offset += self.protocol_name.len;

        // Protocol Level
        buffer[offset] = self.protocol_level;
        offset += 1;

        // Flags
        var flags_byte: u8 = 0;
        if (self.flags.clean_session == 1) flags_byte |= 0x02;
        if (self.flags.will_flag == 1) flags_byte |= 0x04;
        flags_byte |= (@as(u8, self.flags.will_qos) << 3) & 0x18;
        if (self.flags.will_retain == 1) flags_byte |= 0x20;
        if (self.flags.password_flag == 1) flags_byte |= 0x40;
        if (self.flags.username_flag == 1) flags_byte |= 0x80;
        buffer[offset] = flags_byte;
        offset += 1;

        // Keep Alive
        buffer[offset] = @intCast(self.keep_alive >> 8);
        buffer[offset + 1] = @intCast(self.keep_alive & 0xFF);
        offset += 2;

        // Payload
        // Client ID
        buffer[offset] = @intCast(self.client_id.len >> 8);
        buffer[offset + 1] = @intCast(self.client_id.len & 0xFF);
        offset += 2;
        @memcpy(buffer[offset .. offset + self.client_id.len], self.client_id);
        offset += self.client_id.len;

        if (self.will_topic) |topic| {
            buffer[offset] = @intCast(topic.len >> 8);
            buffer[offset + 1] = @intCast(topic.len & 0xFF);
            offset += 2;
            @memcpy(buffer[offset .. offset + topic.len], topic);
            offset += topic.len;

            if (self.will_message) |msg| {
                buffer[offset] = @intCast(msg.len >> 8);
                buffer[offset + 1] = @intCast(msg.len & 0xFF);
                offset += 2;
                @memcpy(buffer[offset .. offset + msg.len], msg);
                offset += msg.len;
            }
        }

        if (self.username) |user| {
            buffer[offset] = @intCast(user.len >> 8);
            buffer[offset + 1] = @intCast(user.len & 0xFF);
            offset += 2;
            @memcpy(buffer[offset .. offset + user.len], user);
            offset += user.len;
        }

        if (self.password) |pass| {
            buffer[offset] = @intCast(pass.len >> 8);
            buffer[offset + 1] = @intCast(pass.len & 0xFF);
            offset += 2;
            @memcpy(buffer[offset .. offset + pass.len], pass);
            offset += pass.len;
        }

        return offset;
    }
};

/// MQTT CONNACK packet
pub const ConnackPacket = struct {
    session_present: bool,
    return_code: ConnectReturnCode,

    pub fn encode(self: ConnackPacket, buffer: []u8) !usize {
        const header = FixedHeader{
            .packet_type = .CONNACK,
            .flags = 0,
            .remaining_length = 2,
        };

        var written = try header.encode(buffer);

        if (buffer.len < written + 2) {
            return error.BufferTooSmall;
        }

        buffer[written] = if (self.session_present) @as(u8, 1) else 0;
        written += 1;
        buffer[written] = @intFromEnum(self.return_code);
        written += 1;

        return written;
    }
};

/// MQTT PUBLISH packet
pub const PublishPacket = struct {
    topic: []const u8,
    qos: QoS,
    retain: bool,
    dup: bool,
    packet_id: ?u16,
    payload: []const u8,
    pub fn encode(self: PublishPacket, buffer: []u8) !usize {
        var len: usize = 0;
        len += 2 + self.topic.len; // Topic
        if (self.qos != .at_most_once) len += 2; // Packet ID
        len += self.payload.len;

        var flags: u4 = 0;
        if (self.retain) flags |= 0x01;
        flags |= @as(u4, @intFromEnum(self.qos)) << 1;
        if (self.dup) flags |= 0x08;

        const header = FixedHeader{
            .packet_type = .PUBLISH,
            .flags = flags,
            .remaining_length = @intCast(len),
        };

        var offset = try header.encode(buffer);
        if (buffer.len < offset + len) return error.BufferTooSmall;

        // Topic
        buffer[offset] = @intCast(self.topic.len >> 8);
        buffer[offset + 1] = @intCast(self.topic.len & 0xFF);
        offset += 2;
        @memcpy(buffer[offset .. offset + self.topic.len], self.topic);
        offset += self.topic.len;

        // Packet ID (if QoS > 0)
        if (self.qos != .at_most_once) {
            if (self.packet_id) |pid| {
                buffer[offset] = @intCast(pid >> 8);
                buffer[offset + 1] = @intCast(pid & 0xFF);
                offset += 2;
            } else {
                return error.PacketIdRequired; // Error if packet_id missing for QoS > 0
            }
        }

        // Payload
        @memcpy(buffer[offset .. offset + self.payload.len], self.payload);
        offset += self.payload.len;

        return offset;
    }
};

/// MQTT SUBSCRIBE packet
pub const SubscribePacket = struct {
    packet_id: u16,
    topics: []TopicFilter,

    pub const TopicFilter = struct {
        topic: []const u8,
        qos: QoS,
    };
    pub fn encode(self: SubscribePacket, buffer: []u8) !usize {
        var len: usize = 2; // Packet ID
        for (self.topics) |tf| {
            len += 2 + tf.topic.len + 1; // Topic string + QoS byte
        }

        const header = FixedHeader{
            .packet_type = .SUBSCRIBE,
            .flags = 0x02, // Required by spec
            .remaining_length = @intCast(len),
        };

        var offset = try header.encode(buffer);
        if (buffer.len < offset + len) return error.BufferTooSmall;

        // Packet ID
        buffer[offset] = @intCast(self.packet_id >> 8);
        buffer[offset + 1] = @intCast(self.packet_id & 0xFF);
        offset += 2;

        // Topics
        for (self.topics) |tf| {
            buffer[offset] = @intCast(tf.topic.len >> 8);
            buffer[offset + 1] = @intCast(tf.topic.len & 0xFF);
            offset += 2;
            @memcpy(buffer[offset .. offset + tf.topic.len], tf.topic);
            offset += tf.topic.len;

            buffer[offset] = @intFromEnum(tf.qos);
            offset += 1;
        }

        return offset;
    }
};

/// MQTT SUBACK packet
pub const SubackPacket = struct {
    packet_id: u16,
    return_codes: []u8,

    pub fn encode(self: SubackPacket, buffer: []u8) !usize {
        const remaining_length: u32 = 2 + @as(u32, @intCast(self.return_codes.len));

        const header = FixedHeader{
            .packet_type = .SUBACK,
            .flags = 0,
            .remaining_length = remaining_length,
        };

        var written = try header.encode(buffer);

        if (buffer.len < written + 2 + self.return_codes.len) {
            return error.BufferTooSmall;
        }

        // Packet ID (MSB, LSB)
        buffer[written] = @intCast((self.packet_id >> 8) & 0xFF);
        written += 1;
        buffer[written] = @intCast(self.packet_id & 0xFF);
        written += 1;

        // Return codes
        @memcpy(buffer[written .. written + self.return_codes.len], self.return_codes);
        written += self.return_codes.len;

        return written;
    }
};

/// MQTT PINGREQ packet
pub const PingreqPacket = struct {
    pub fn encode(self: PingreqPacket, buffer: []u8) !usize {
        _ = self;
        const header = FixedHeader{
            .packet_type = .PINGREQ,
            .flags = 0,
            .remaining_length = 0,
        };

        return try header.encode(buffer);
    }
};

/// MQTT PINGRESP packet
pub const PingrespPacket = struct {
    pub fn encode(buffer: []u8) !usize {
        const header = FixedHeader{
            .packet_type = .PINGRESP,
            .flags = 0,
            .remaining_length = 0,
        };

        return try header.encode(buffer);
    }
};

/// MQTT DISCONNECT packet
pub const DisconnectPacket = struct {
    pub fn encode(self: DisconnectPacket, buffer: []u8) !usize {
        _ = self;
        const header = FixedHeader{
            .packet_type = .DISCONNECT,
            .flags = 0,
            .remaining_length = 0,
        };

        return try header.encode(buffer);
    }
};

/// MQTT UNSUBSCRIBE packet
pub const UnsubscribePacket = struct {
    packet_id: u16,
    topics: [][]const u8,

    pub fn encode(self: UnsubscribePacket, buffer: []u8) !usize {
        var len: usize = 2; // Packet ID
        for (self.topics) |topic| {
            len += 2 + topic.len; // Topic string
        }

        const header = FixedHeader{
            .packet_type = .UNSUBSCRIBE,
            .flags = 0x02, // Required by spec
            .remaining_length = @intCast(len),
        };

        var offset = try header.encode(buffer);
        if (buffer.len < offset + len) return error.BufferTooSmall;

        // Packet ID
        buffer[offset] = @intCast(self.packet_id >> 8);
        buffer[offset + 1] = @intCast(self.packet_id & 0xFF);
        offset += 2;

        // Topics
        for (self.topics) |topic| {
            buffer[offset] = @intCast(topic.len >> 8);
            buffer[offset + 1] = @intCast(topic.len & 0xFF);
            offset += 2;
            @memcpy(buffer[offset .. offset + topic.len], topic);
            offset += topic.len;
        }

        return offset;
    }
};

// Tests

test "FixedHeader parse" {
    // CONNACK packet: type=2, flags=0, remaining_length=2
    const data = [_]u8{ 0x20, 0x02 };
    const header = try FixedHeader.parse(&data);

    try std.testing.expectEqual(PacketType.CONNACK, header.packet_type);
    try std.testing.expectEqual(@as(u4, 0), header.flags);
    try std.testing.expectEqual(@as(u32, 2), header.remaining_length);
}

test "FixedHeader encode" {
    const header = FixedHeader{
        .packet_type = .CONNACK,
        .flags = 0,
        .remaining_length = 2,
    };

    var buffer: [10]u8 = undefined;
    const written = try header.encode(&buffer);

    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(@as(u8, 0x20), buffer[0]);
    try std.testing.expectEqual(@as(u8, 0x02), buffer[1]);
}

test "ConnackPacket encode" {
    const packet = ConnackPacket{
        .session_present = false,
        .return_code = .accepted,
    };

    var buffer: [10]u8 = undefined;
    const written = try packet.encode(&buffer);

    try std.testing.expectEqual(@as(usize, 4), written);
    try std.testing.expectEqual(@as(u8, 0x20), buffer[0]); // CONNACK
    try std.testing.expectEqual(@as(u8, 0x02), buffer[1]); // Remaining length
    try std.testing.expectEqual(@as(u8, 0x00), buffer[2]); // Session present
    try std.testing.expectEqual(@as(u8, 0x00), buffer[3]); // Return code
}

test "PingrespPacket encode" {
    var buffer: [10]u8 = undefined;
    const written = try PingrespPacket.encode(&buffer);

    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(@as(u8, 0xD0), buffer[0]); // PINGRESP
    try std.testing.expectEqual(@as(u8, 0x00), buffer[1]); // Remaining length
}
