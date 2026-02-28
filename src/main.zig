const std = @import("std");
const TcpServer = @import("server/tcp.zig").TcpServer;
const types = @import("common/types.zig");

/// Entry point for the MQTT server
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("ProtoMQ Server Starting...\n", .{});
    std.debug.print("Version: 0.2.0\n", .{});
    std.debug.print("Zig Version: {s}\n\n", .{@import("builtin").zig_version_string});

    // Create and start TCP server
    var server = try TcpServer.init(allocator, types.DEFAULT_HOST, types.DEFAULT_PORT);
    defer server.deinit();

    // Run the server (this blocks)
    try server.run();

    std.debug.print("\n✓ Server stopped cleanly\n", .{});
}

test "basic sanity test" {
    try std.testing.expect(true);
}
