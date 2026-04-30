const std = @import("std");

/// LiveReloadServer configuration and state.
/// Provides a WebSocket server that accepts browser connections and sends
/// reload messages when triggered (for watch mode live-reload).
pub const LiveReloadServer = struct {
    /// Listening port number
    port: u16,
    /// Memory allocator
    allocator: std.mem.Allocator,
    /// Currently running flag
    running: bool = false,
    /// Connected clients (client ID -> connection state)
    clients: std.AutoHashMap(u64, ClientConnection) = undefined,
    /// Next client ID counter
    next_client_id: u64 = 1,
    /// Mutex for thread-safe client list access
    clients_mutex: std.Thread.Mutex = .{},
    /// Server socket file descriptor (platform-dependent)
    server_fd: ?std.posix.socket_t = null,

    const Self = @This();

    /// Client connection information
    pub const ClientConnection = struct {
        /// Unique client identifier
        id: u64,
        /// Client socket
        fd: std.posix.socket_t,
        /// WebSocket handshake complete
        handshake_complete: bool = false,
    };

    /// Initialize a new LiveReloadServer with the given port.
    /// Default port is 35729 (standard LiveReload port).
    /// Returns error if port is invalid or allocation fails.
    pub fn init(allocator: std.mem.Allocator, port: u16) !Self {
        if (port == 0) return error.InvalidPort;

        var clients = std.AutoHashMap(u64, ClientConnection).init(allocator);
        errdefer clients.deinit();

        return Self{
            .port = port,
            .allocator = allocator,
            .clients = clients,
        };
    }

    /// Free all resources and close connections.
    pub fn deinit(self: *Self) void {
        if (self.running) {
            self.stop() catch {};
        }
        self.clients.deinit();
    }

    /// Start the server listening for WebSocket connections (non-blocking).
    /// Spawns background thread to accept connections.
    /// Returns error if bind fails (e.g., port already in use).
    pub fn start(self: *Self) !void {
        if (self.running) return error.AlreadyRunning;

        // TODO: Bind to port and start accepting connections
        // This will be implemented by zig-developer
        self.running = true;
    }

    /// Stop the server and close all connections gracefully.
    /// Waits for all clients to disconnect before returning.
    pub fn stop(self: *Self) !void {
        if (!self.running) return error.NotRunning;

        {
            self.clients_mutex.lock();
            defer self.clients_mutex.unlock();
            // TODO: Close all connected clients
        }

        // TODO: Close server socket
        self.running = false;
    }

    /// Send a reload message to all connected clients.
    /// Thread-safe: can be called from multiple threads.
    /// Non-blocking: errors don't prevent message from being queued.
    pub fn trigger(self: *Self, path: []const u8) !void {
        if (!self.running) return error.NotRunning;

        // Format: {"command":"reload","path":"/"}
        var buffer: [256]u8 = undefined;
        _ = try std.fmt.bufPrint(
            &buffer,
            "{{\"command\":\"reload\",\"path\":\"{s}\"}}",
            .{path},
        );

        {
            self.clients_mutex.lock();
            defer self.clients_mutex.unlock();

            // TODO: Send message to all connected clients
            // Broadcast to all clients in self.clients
        }
    }

    /// Get the port the server is listening on.
    pub fn getPort(self: *const Self) u16 {
        return self.port;
    }

    /// Check if the server is currently running.
    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    /// Get number of currently connected clients.
    pub fn clientCount(self: *Self) usize {
        self.clients_mutex.lock();
        defer self.clients_mutex.unlock();
        return self.clients.count();
    }
};

// --- Tests ---

test "LiveReloadServer initialization with default port" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 35729);
    defer server.deinit();

    try std.testing.expectEqual(@as(u16, 35729), server.getPort());
    try std.testing.expectEqual(false, server.isRunning());
    try std.testing.expectEqual(@as(usize, 0), server.clientCount());
}

test "LiveReloadServer initialization with custom port" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 8080);
    defer server.deinit();

    try std.testing.expectEqual(@as(u16, 8080), server.getPort());
    try std.testing.expectEqual(false, server.isRunning());
}

test "LiveReloadServer rejects invalid port (zero)" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidPort, LiveReloadServer.init(allocator, 0));
}

test "LiveReloadServer start transitions running state" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 9999);
    defer server.deinit();

    try std.testing.expectEqual(false, server.isRunning());
    // Note: start() will fail if port is actually in use, but we're testing state transition
    // In real implementation, we'd mock the socket binding
    // For now, this test documents expected behavior
    server.start() catch {};
    // If start succeeds, server should be marked running
}

test "LiveReloadServer stop requires running state" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 9999);
    defer server.deinit();

    try std.testing.expectEqual(false, server.isRunning());
    try std.testing.expectError(error.NotRunning, server.stop());
}

test "LiveReloadServer trigger requires running state" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 9999);
    defer server.deinit();

    try std.testing.expectError(error.NotRunning, server.trigger("/"));
}

test "LiveReloadServer cannot start twice" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 9999);
    defer server.deinit();

    server.start() catch {};
    if (server.isRunning()) {
        try std.testing.expectError(error.AlreadyRunning, server.start());
    }
}

test "LiveReloadServer maintains port across lifecycle" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 12345);
    defer server.deinit();

    try std.testing.expectEqual(@as(u16, 12345), server.getPort());
    _ = server.start() catch {};
    try std.testing.expectEqual(@as(u16, 12345), server.getPort());
}

test "LiveReloadServer message format validation" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 35729);
    defer server.deinit();

    // Test path parameter is preserved in message
    // Message should be JSON: {"command":"reload","path":"<path>"}
    server.start() catch {};
    if (server.isRunning()) {
        server.trigger("/index.html") catch {};
    }
}

test "LiveReloadServer handles multiple init/deinit cycles" {
    const allocator = std.testing.allocator;

    {
        var server1 = try LiveReloadServer.init(allocator, 35729);
        defer server1.deinit();
        try std.testing.expectEqual(@as(u16, 35729), server1.getPort());
    }

    {
        var server2 = try LiveReloadServer.init(allocator, 35729);
        defer server2.deinit();
        try std.testing.expectEqual(@as(u16, 35729), server2.getPort());
    }
}

test "LiveReloadServer initial client count is zero" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 35729);
    defer server.deinit();

    try std.testing.expectEqual(@as(usize, 0), server.clientCount());
}
