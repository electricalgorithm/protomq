const std = @import("std");

/// Common error types used throughout the application
pub const ServerError = error{
    /// Socket creation failed
    SocketCreationFailed,
    /// Failed to bind to address
    BindFailed,
    /// Failed to listen on socket
    ListenFailed,
    /// Failed to accept connection
    AcceptFailed,
    /// Connection closed by peer
    ConnectionClosed,
    /// Invalid packet received
    InvalidPacket,
    /// Protocol violation
    ProtocolViolation,
    /// Resource limit reached
    ResourceLimitReached,
};

pub const ClientError = error{
    /// Connection failed
    ConnectionFailed,
    /// Authentication failed
    AuthenticationFailed,
    /// Subscription failed
    SubscriptionFailed,
    /// Publish failed
    PublishFailed,
};
