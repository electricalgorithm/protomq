const std = @import("std");
const types = @import("types.zig");

/// Client connection representation
pub const Connection = struct {
    allocator: std.mem.Allocator,
    socket: std.posix.socket_t,
    state: types.ConnectionState,
    read_buffer: []u8,
    write_buffer: []u8,
    offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator, socket: std.posix.socket_t, blocking: bool) !Connection {
        const read_buffer = try allocator.alloc(u8, types.BUFFER_SIZE);
        const write_buffer = try allocator.alloc(u8, types.BUFFER_SIZE);

        // Set non-blocking mode if requested
        if (!blocking) {
            const flags = try std.posix.fcntl(socket, std.posix.F.GETFL, 0);
            const nonblock = std.posix.O{ .NONBLOCK = true };
            const nonblock_u32: u32 = @bitCast(nonblock);
            _ = try std.posix.fcntl(socket, std.posix.F.SETFL, flags | @as(usize, nonblock_u32));
        }

        return Connection{
            .allocator = allocator,
            .socket = socket,
            .state = .connecting,
            .read_buffer = read_buffer,
            .write_buffer = write_buffer,
            .offset = 0,
        };
    }

    pub fn deinit(self: *Connection) void {
        self.allocator.free(self.read_buffer);
        self.allocator.free(self.write_buffer);
        self.close();
    }

    /// Read data from the socket into read_buffer (Non-blocking)
    /// Returns number of bytes read, or error.WouldBlock if no data available.
    pub fn read(self: *Connection) !usize {
        if (self.state == .disconnected) {
            return error.ConnectionClosed;
        }

        if (self.offset >= self.read_buffer.len) {
            return error.BufferOverflow; // Need larger buffer or consume data
        }

        const bytes_read = std.posix.read(self.socket, self.read_buffer[self.offset..]) catch |err| {
            return switch (err) {
                error.WouldBlock => error.WouldBlock,
                error.ConnectionResetByPeer => error.EndOfStream,
                else => err,
            };
        };

        if (bytes_read == 0) {
            return error.EndOfStream;
        }

        self.offset += bytes_read;
        return bytes_read;
    }

    /// Consume bytes from the beginning of the read buffer
    pub fn consume(self: *Connection, count: usize) void {
        if (count == 0) return;
        if (count >= self.offset) {
            self.offset = 0;
            return;
        }
        std.mem.copyForwards(u8, self.read_buffer[0 .. self.offset - count], self.read_buffer[count..self.offset]);
        self.offset -= count;
    }

    /// Write data from buffer to the socket
    pub fn write(self: *Connection, data: []const u8) !usize {
        if (self.state == .disconnected) {
            return error.ConnectionClosed;
        }

        const bytes_written = try std.posix.write(self.socket, data);
        return bytes_written;
    }

    /// Close the connection
    pub fn close(self: *Connection) void {
        if (self.state != .disconnected) {
            std.posix.close(self.socket);
            self.state = .disconnected;
        }
    }

    /// Check if connection is still active
    pub fn isActive(self: *Connection) bool {
        return self.state == .connected;
    }
};

// Tests

test "Connection init and deinit" {
    const allocator = std.testing.allocator;
    const fake_socket: std.posix.socket_t = 0;
    var conn = try Connection.init(allocator, fake_socket, true);
    defer conn.deinit();

    try std.testing.expect(conn.state == .connecting);
    try std.testing.expect(conn.read_buffer.len == types.BUFFER_SIZE);
    try std.testing.expect(conn.write_buffer.len == types.BUFFER_SIZE);
}
