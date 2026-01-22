const std = @import("std");
const builtin = @import("builtin");

/// uniform interface for Async I/O Event Loop
pub const IOContext = struct {
    backend: Backend,

    pub fn init(allocator: std.mem.Allocator) !IOContext {
        return IOContext{
            .backend = try Backend.init(allocator),
        };
    }

    pub fn deinit(self: *IOContext) void {
        self.backend.deinit();
    }

    /// Register a socket for read events
    pub fn registerRead(self: *IOContext, socket: std.posix.socket_t, data: usize) !void {
        try self.backend.registerRead(socket, data);
    }

    /// Remove a socket from monitoring
    pub fn remove(self: *IOContext, socket: std.posix.socket_t) !void {
        try self.backend.remove(socket);
    }

    /// Wait for events
    /// Returns number of events processed
    /// context: User data passed to callback
    /// callback: fn(context: Context, data: usize) void
    pub fn run(self: *IOContext, timeout_ms: i32, context: anytype, callback: fn (ctx: @TypeOf(context), data: usize) void) !usize {
        return self.backend.run(timeout_ms, context, callback);
    }
};

const Backend = if (builtin.os.tag == .linux) EpollBackend else KqueueBackend;

/// Kqueue Backend (MacOS/BSD)
const KqueueBackend = struct {
    kq_fd: std.posix.fd_t,
    events: [64]std.posix.Kevent,

    // Kqueue Constants (MacOS/BSD)
    const EVFILT_READ: i16 = -1;
    const EV_ADD: u16 = 0x0001;
    const EV_DELETE: u16 = 0x0002;
    const EV_ENABLE: u16 = 0x0004;

    pub fn init(allocator: std.mem.Allocator) !KqueueBackend {
        _ = allocator;
        const kq = try std.posix.kqueue();
        return KqueueBackend{
            .kq_fd = kq,
            .events = undefined,
        };
    }

    pub fn deinit(self: *KqueueBackend) void {
        std.posix.close(self.kq_fd);
    }

    pub fn registerRead(self: *KqueueBackend, socket: std.posix.socket_t, data: usize) !void {
        const event = std.posix.Kevent{
            .ident = @intCast(socket),
            .filter = EVFILT_READ,
            .flags = EV_ADD | EV_ENABLE,
            .fflags = 0,
            .data = 0,
            .udata = data,
        };

        try change(self.kq_fd, &[1]std.posix.Kevent{event});
    }

    pub fn remove(self: *KqueueBackend, socket: std.posix.socket_t) !void {
        const event = std.posix.Kevent{
            .ident = @intCast(socket),
            .filter = EVFILT_READ,
            .flags = EV_DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        };
        // Ignore error if it doesn't exist
        _ = change(self.kq_fd, &[1]std.posix.Kevent{event}) catch {};
    }

    pub fn run(self: *KqueueBackend, timeout_ms: i32, context: anytype, callback: fn (ctx: @TypeOf(context), data: usize) void) !usize {
        var ts: std.posix.timespec = undefined;
        var ts_ptr: ?*const std.posix.timespec = null;

        if (timeout_ms >= 0) {
            ts.sec = @divTrunc(timeout_ms, 1000);
            ts.nsec = @rem(timeout_ms, 1000) * 1000000;
            ts_ptr = &ts;
        }

        const n = try std.posix.kevent(self.kq_fd, &[_]std.posix.Kevent{}, self.events[0..], ts_ptr);

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const ev = self.events[i];
            callback(context, ev.udata);
        }
        return n;
    }

    // Helper wrapper for kevent changelist
    fn change(kq: std.posix.fd_t, changes: []const std.posix.Kevent) !void {
        _ = try std.posix.kevent(kq, changes, &[_]std.posix.Kevent{}, null);
    }
};

/// Epoll Backend (Linux)
const EpollBackend = struct {
    epoll_fd: std.posix.fd_t,
    // Use std.os.linux for Linux structures
    events: [64]std.os.linux.epoll_event,

    pub fn init(allocator: std.mem.Allocator) !EpollBackend {
        _ = allocator;
        const fd = try std.posix.epoll_create1(0);
        return EpollBackend{
            .epoll_fd = fd,
            .events = undefined,
        };
    }

    pub fn deinit(self: *EpollBackend) void {
        std.posix.close(self.epoll_fd);
    }

    pub fn registerRead(self: *EpollBackend, socket: std.posix.socket_t, data: usize) !void {
        var event = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN,
            .data = .{ .ptr = data },
        };
        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, socket, &event);
    }

    pub fn remove(self: *EpollBackend, socket: std.posix.socket_t) !void {
        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, socket, null);
    }

    pub fn run(self: *EpollBackend, timeout_ms: i32, context: anytype, callback: fn (ctx: @TypeOf(context), data: usize) void) !usize {
        const n = std.posix.epoll_wait(self.epoll_fd, self.events[0..], timeout_ms);

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const ev = self.events[i];
            callback(context, ev.data.ptr);
        }
        return n;
    }
};
