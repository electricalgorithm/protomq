const std = @import("std");
const SchemaManager = @import("schema_manager.zig").SchemaManager;
const Connection = @import("../common/connection.zig").Connection;
const IOContext = @import("event_loop.zig").IOContext;
const pb_parser = @import("../protocol/protobuf/parser.zig");
const tcp = @import("tcp.zig");

const ConnectionList = std.ArrayListUnmanaged(?*Connection);

pub const AdminServer = struct {
    allocator: std.mem.Allocator,
    schema_manager: *SchemaManager,
    address: std.net.Address,
    listener_socket: std.posix.socket_t,
    connections: ConnectionList,
    io_context: *IOContext,
    admin_token: []const u8,
    tcp_server: ?*tcp.TcpServer,

    const SchemaPayload = struct {
        topic: []const u8,
        message_type: []const u8,
        proto_file_content: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, schema_mgr: *SchemaManager, port: u16) !AdminServer {
        const address = try std.net.Address.parseIp("127.0.0.1", port);
        const token = std.posix.getenv("ADMIN_TOKEN") orelse "admin_secret";
        return AdminServer{
            .allocator = allocator,
            .schema_manager = schema_mgr,
            .address = address,
            .listener_socket = -1,
            .connections = .{},
            .io_context = undefined,
            .admin_token = token,
            .tcp_server = null,
        };
    }

    pub fn deinit(self: *AdminServer) void {
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
    }

    pub fn listen(self: *AdminServer, io_context: *IOContext) !void {
        self.io_context = io_context;
        self.listener_socket = try std.posix.socket(self.address.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        try std.posix.setsockopt(self.listener_socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try std.posix.bind(self.listener_socket, &self.address.any, self.address.getOsSockLen());
        try std.posix.listen(self.listener_socket, 128);

        const flags = try std.posix.fcntl(self.listener_socket, std.posix.F.GETFL, 0);
        const nonblock = std.posix.O{ .NONBLOCK = true };
        const nonblock_u32: u32 = @bitCast(nonblock);
        _ = try std.posix.fcntl(self.listener_socket, std.posix.F.SETFL, flags | @as(usize, nonblock_u32));

        try self.io_context.registerRead(self.listener_socket, tcp.packUdata(.admin_listener, 0));
        std.debug.print("Admin Server listening on HTTP {any} (Async)\n", .{self.address});
    }

    pub fn handleAccept(self: *AdminServer) !void {
        while (true) {
            var addr: std.net.Address = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);

            const fd = std.posix.accept(self.listener_socket, &addr.any, &addr_len, 0) catch |err| {
                if (err == error.WouldBlock) return;
                return err;
            };

            const conn = try self.allocator.create(Connection);
            conn.* = try Connection.init(self.allocator, fd, false);

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

            try self.io_context.registerRead(fd, tcp.packUdata(.admin_client, @intCast(slot_idx)));
        }
    }

    pub fn closeClient(self: *AdminServer, index: usize) void {
        if (index < self.connections.items.len) {
            if (self.connections.items[index]) |conn| {
                self.io_context.remove(conn.socket) catch {};
                conn.deinit();
                self.allocator.destroy(conn);
                self.connections.items[index] = null;
            }
        }
    }

    pub fn handleClient(self: *AdminServer, index: usize) !void {
        const conn = self.connections.items[index] orelse return;
        const bytes_read = conn.read() catch |err| {
            if (err == error.WouldBlock) return;
            return err;
        };

        if (bytes_read == 0) {
            self.closeClient(index);
            return;
        }

        while (true) {
            const buffer_span = conn.read_buffer[0..conn.offset];
            if (std.mem.indexOf(u8, buffer_span, "\r\n\r\n")) |header_end| {
                const request_text = buffer_span[0..header_end];
                var body = buffer_span[header_end + 4 ..];

                var content_length: usize = 0;
                var lines = std.mem.splitSequence(u8, request_text, "\r\n");
                _ = lines.next();
                while (lines.next()) |line| {
                    if (std.mem.startsWith(u8, line, "Content-Length: ")) {
                        const cl_str = line[16..];
                        content_length = std.fmt.parseInt(usize, std.mem.trim(u8, cl_str, " "), 10) catch 0;
                    }
                }

                if (body.len < content_length) {
                    break; // Wait for full body
                }

                body = body[0..content_length];

                self.handleHttpRequest(conn, request_text, body) catch |err| {
                    std.debug.print("Admin HTTP error: {}\n", .{err});
                    _ = conn.write("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n") catch {};
                };

                self.closeClient(index);
                break;
            } else {
                break; // Wait for full headers
            }
        }
    }

    fn handleHttpRequest(self: *AdminServer, conn: *Connection, request_text: []const u8, body: []const u8) !void {
        var lines = std.mem.splitSequence(u8, request_text, "\r\n");
        const request_line = lines.next() orelse "";

        var auth_header: ?[]const u8 = null;
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "Authorization: Bearer ")) {
                auth_header = line[22..];
            }
        }

        if (auth_header == null or !std.mem.eql(u8, auth_header.?, self.admin_token)) {
            _ = try conn.write("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n");
            return;
        }

        var parts = std.mem.splitSequence(u8, request_line, " ");
        const method = parts.next() orelse "";
        const path = parts.next() orelse "";

        if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/api/v1/schemas")) {
            var json_builder = std.ArrayListUnmanaged(u8){};
            defer json_builder.deinit(self.allocator);

            try json_builder.append(self.allocator, '{');
            var first = true;
            var it = self.schema_manager.topic_mapping.iterator();
            while (it.next()) |entry| {
                if (!first) {
                    try json_builder.append(self.allocator, ',');
                }
                first = false;
                try std.fmt.format(json_builder.writer(self.allocator), "\"{s}\":\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try json_builder.append(self.allocator, '}');

            const response = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}", .{ json_builder.items.len, json_builder.items });
            defer self.allocator.free(response);

            _ = try conn.write(response);
        } else if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/metrics")) {
            var active_conns: usize = 0;
            var total_msgs: u64 = 0;
            if (self.tcp_server) |srv| {
                for (srv.connections.items) |cmd_opt| {
                    if (cmd_opt != null) {
                        active_conns += 1;
                    }
                }
                total_msgs = srv.broker.total_messages_routed;
            }

            const active_schemas = self.schema_manager.topic_mapping.count();

            const metrics_json = try std.fmt.allocPrint(self.allocator,
                \\{{"connections":{d},"messages_routed":{d},"schemas":{d},"memory_mb":0}}
            , .{ active_conns, total_msgs, active_schemas });
            defer self.allocator.free(metrics_json);

            const response = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}", .{ metrics_json.len, metrics_json });
            defer self.allocator.free(response);

            _ = try conn.write(response);
        } else if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/api/v1/schemas")) {
            const parsed = std.json.parseFromSlice(SchemaPayload, self.allocator, body, .{ .ignore_unknown_fields = true }) catch {
                _ = try conn.write("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n");
                return;
            };
            defer parsed.deinit();

            // Save to file
            const file_name = try std.fmt.allocPrint(self.allocator, "{s}.proto", .{parsed.value.message_type});
            defer self.allocator.free(file_name);

            var dir = std.fs.cwd().openDir("schemas", .{}) catch |err| blk: {
                if (err == error.FileNotFound) {
                    try std.fs.cwd().makeDir("schemas");
                    break :blk try std.fs.cwd().openDir("schemas", .{});
                }
                return err;
            };
            defer dir.close();

            const file = try dir.createFile(file_name, .{ .truncate = true });
            defer file.close();
            try file.writeAll(parsed.value.proto_file_content);

            var parser = pb_parser.ProtoParser.init(self.allocator, parsed.value.proto_file_content);
            parser.parse(&self.schema_manager.registry) catch {
                _ = try conn.write("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n");
                return;
            };

            try self.schema_manager.mapTopicToSchema(parsed.value.topic, parsed.value.message_type);

            _ = try conn.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK");
        } else {
            const response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found";
            _ = try conn.write(response);
        }
    }
};
