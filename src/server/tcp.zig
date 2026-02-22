const std = @import("std");
const Connection = @import("../common/connection.zig").Connection;
const types = @import("../common/types.zig");
const errors = @import("../common/errors.zig");
const TopicBroker = @import("../broker/broker.zig").TopicBroker;
const MqttHandler = @import("../broker/mqtt_handler.zig").MqttHandler;
const IOContext = @import("event_loop.zig").IOContext;
const packet = @import("../protocol/mqtt/packet.zig");
const SchemaManager = @import("schema_manager.zig").SchemaManager;
const build_options = @import("build_options");
const AdminServer = if (build_options.admin_server) @import("admin.zig").AdminServer else void;

pub const EventType = enum(u32) {
    mqtt_listener = 0,
    mqtt_client = 1,
    admin_listener = 2,
    admin_client = 3,
};

pub fn packUdata(evt: EventType, index: u32) usize {
    return (@as(usize, @intFromEnum(evt)) << 32) | @as(usize, index);
}

pub fn unpackUdata(udata: usize) struct { evt: EventType, index: u32 } {
    return .{
        .evt = @enumFromInt(@as(u32, @truncate(udata >> 32))),
        .index = @as(u32, @truncate(udata)),
    };
}

const ConnectionList = std.ArrayListUnmanaged(?*Connection);

/// Async TCP Server Implementation
pub const TcpServer = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    listener_socket: std.posix.socket_t,
    connections: ConnectionList,
    running: bool,
    broker: TopicBroker,
    mqtt_handler: MqttHandler,
    io_context: IOContext,
    schema_manager: SchemaManager,
    admin_server: AdminServer,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !TcpServer {
        const address = try std.net.Address.parseIp(host, port);

        var broker = TopicBroker.init(allocator);
        errdefer broker.deinit();

        const io_ctx = try IOContext.init(allocator);

        var server = TcpServer{
            .allocator = allocator,
            .address = address,
            .listener_socket = -1, // Invalid init
            .connections = .{},
            .running = false,
            .broker = broker,
            .mqtt_handler = undefined,
            .io_context = io_ctx,
            .schema_manager = SchemaManager.init(allocator),
            .admin_server = if (build_options.admin_server) try AdminServer.init(allocator, undefined, 8080) else {},
        };

        server.mqtt_handler = MqttHandler.init(allocator);
        if (build_options.admin_server) {
            server.admin_server.schema_manager = &server.schema_manager;
        }

        // Load Schemas
        try server.schema_manager.loadSchemasFromDir("schemas");
        // Example Mapping: sensor/data -> iot.sensor.SensorData
        try server.schema_manager.mapTopicToSchema("sensor/data", "SensorData");

        return server;
    }

    pub fn deinit(self: *TcpServer) void {
        for (self.connections.items) |conn_opt| {
            if (conn_opt) |conn| {
                conn.deinit();
                self.allocator.destroy(conn);
            }
        }
        self.connections.deinit(self.allocator);

        if (self.listener_socket != -1) {
            std.posix.close(self.listener_socket);
        }

        self.io_context.deinit();
        self.mqtt_handler.deinit();
        self.broker.deinit();
        if (build_options.admin_server) {
            self.admin_server.deinit();
        }
        self.schema_manager.deinit();
    }

    pub fn listen(self: *TcpServer) !void {
        // Create socket
        self.listener_socket = try std.posix.socket(self.address.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);

        // Setsockopt ReuseAddr
        try std.posix.setsockopt(self.listener_socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        // Bind
        try std.posix.bind(self.listener_socket, &self.address.any, self.address.getOsSockLen());

        // Listen
        try std.posix.listen(self.listener_socket, 128);

        // Non-blocking
        const flags = try std.posix.fcntl(self.listener_socket, std.posix.F.GETFL, 0);
        // On MacOS check for packed struct O
        const nonblock = std.posix.O{ .NONBLOCK = true };
        const nonblock_u32: u32 = @bitCast(nonblock);
        _ = try std.posix.fcntl(self.listener_socket, std.posix.F.SETFL, flags | @as(usize, nonblock_u32));

        // Register with Event Loop
        try self.io_context.registerRead(self.listener_socket, packUdata(.mqtt_listener, 0));

        std.debug.print("✓ Server listening on {any} (Async)\n", .{self.address});
        self.running = true;

        if (build_options.admin_server) {
            self.admin_server.tcp_server = self;
            self.admin_server.schema_manager = &self.schema_manager;
            try self.admin_server.listen(&self.io_context);
        }
    }

    pub fn run(self: *TcpServer) !void {
        try self.listen();

        std.debug.print("✓ Server running. Press Ctrl+C to stop.\n", .{});

        while (self.running) {
            _ = try self.io_context.run(1000, self, onEvent);
        }
    }

    fn onEvent(self: *TcpServer, udata: usize) void {
        const ev_info = unpackUdata(udata);
        switch (ev_info.evt) {
            .mqtt_listener => {
                self.handleAccept() catch |err| {
                    std.debug.print("Accept error: {}\n", .{err});
                };
            },
            .mqtt_client => {
                const index = ev_info.index;
                if (index < self.connections.items.len) {
                    if (self.connections.items[index]) |conn| {
                        self.handleClient(conn, index) catch |err| {
                            std.debug.print("Client error (idx {d}): {}\n", .{ index, err });
                            self.closeClient(index);
                        };
                    }
                }
            },
            .admin_listener => {
                if (build_options.admin_server) {
                    self.admin_server.handleAccept() catch |err| {
                        std.debug.print("Admin Accept error: {}\n", .{err});
                    };
                }
            },
            .admin_client => {
                if (build_options.admin_server) {
                    self.admin_server.handleClient(ev_info.index) catch |err| {
                        std.debug.print("Admin Client error (idx {d}): {}\n", .{ ev_info.index, err });
                        self.admin_server.closeClient(ev_info.index);
                    };
                }
            },
        }
    }

    fn handleAccept(self: *TcpServer) !void {
        // Accept loop until EAGAIN
        while (true) {
            var addr: std.net.Address = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);

            const fd = std.posix.accept(self.listener_socket, &addr.any, &addr_len, 0) catch |err| {
                if (err == error.WouldBlock) return;
                return err;
            };

            std.debug.print("✓ Accepted connection from {any}\n", .{addr});

            // Make sure new socket is non-blocking
            const conn = try self.allocator.create(Connection);
            conn.* = try Connection.init(self.allocator, fd, false); // Non-blocking!

            // Find free slot or append
            var slot_idx: usize = 0;
            var found = false;
            for (self.connections.items, 0..) |item, i| {
                if (item == null) {
                    self.connections.items[i] = conn;
                    slot_idx = i;
                    found = true;
                    break;
                }
            }
            if (!found) {
                try self.connections.append(self.allocator, conn);
                slot_idx = self.connections.items.len - 1;
            }

            try self.io_context.registerRead(fd, packUdata(.mqtt_client, @intCast(slot_idx)));
        }
    }

    fn handleClient(self: *TcpServer, conn: *Connection, index: usize) !void {
        // Read data
        const bytes_read = conn.read() catch |err| {
            if (err == error.WouldBlock) return;
            return err; // Propagate error to close client
        };

        if (bytes_read == 0) {
            // EOF
            self.closeClient(index);
            return;
        }

        // Process Buffer (Loop for multiple packets)
        while (true) {
            const buffer_span = conn.read_buffer[0..conn.offset];

            // Need at least header (2 bytes)
            if (buffer_span.len < 2) break;

            const header = packet.FixedHeader.parse(buffer_span) catch |err| {
                if (err == error.IncompletePacket) break;
                return err;
            };

            const total_len = header.size() + header.remaining_length;
            if (buffer_span.len < total_len) break; // Incomplete

            // Full packet available
            const packet_data = buffer_span[0..total_len];

            self.mqtt_handler.handlePacket(conn, index, packet_data, &self.broker, self.connections.items, &self.schema_manager) catch |err| {
                std.debug.print("Packet handle error: {}\n", .{err});
            };

            // Consume
            conn.consume(total_len);
        }
    }

    fn closeClient(self: *TcpServer, index: usize) void {
        if (index < self.connections.items.len) {
            if (self.connections.items[index]) |conn| {
                // Remove from poller
                self.io_context.remove(conn.socket) catch {};

                conn.deinit();
                self.allocator.destroy(conn);
                self.connections.items[index] = null;

                // Cleanup broker session
                self.broker.removeClient(index);

                std.debug.print("✓ Client {d} disconnected\n", .{index});
            }
        }
    }
};
