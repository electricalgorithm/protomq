const std = @import("std");

/// Default MQTT port
pub const DEFAULT_PORT: u16 = 1883;

/// Default host address
pub const DEFAULT_HOST: []const u8 = "0.0.0.0";

/// Maximum number of concurrent connections
pub const MAX_CONNECTIONS: usize = 1000;

/// Buffer size for reading/writing
pub const BUFFER_SIZE: usize = 4096;

/// Maximum message payload size (256KB)
pub const MAX_PAYLOAD_SIZE: usize = 256 * 1024;

/// Keep-alive timeout in seconds
pub const KEEP_ALIVE_TIMEOUT: u64 = 60;

/// Connection state
pub const ConnectionState = enum {
    connecting,
    connected,
    disconnecting,
    disconnected,
};

/// QoS levels (only QoS 0 for MVP)
pub const QoS = enum(u8) {
    at_most_once = 0,
    at_least_once = 1, // Not implemented in MVP
    exactly_once = 2, // Not implemented in MVP
};
