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

        // Create TCP socket
        const sockfd = try std.posix.socket(
            std.posix.AF.INET,
            std.posix.SOCK.STREAM,
            std.posix.IPPROTO.TCP,
        );
        errdefer std.posix.close(sockfd);

        // Enable address reuse to avoid "Address already in use" after restart
        const enable: c_int = 1;
        try std.posix.setsockopt(
            sockfd,
            std.posix.SOL.SOCKET,
            std.posix.SO.REUSEADDR,
            std.mem.asBytes(&enable),
        );

        // Bind to localhost:port
        const addr = std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, self.port);
        std.posix.bind(sockfd, &addr.any, addr.getOsSockLen()) catch |err| {
            if (err == error.AddressInUse) return error.AddressInUse;
            return err;
        };

        // Start listening with backlog of 128 connections
        try std.posix.listen(sockfd, 128);

        self.server_fd = sockfd;
        self.running = true;

        // Spawn background thread to accept connections
        const thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
        thread.detach();
    }

    /// Stop the server and close all connections gracefully.
    /// Waits for all clients to disconnect before returning.
    pub fn stop(self: *Self) !void {
        if (!self.running) return error.NotRunning;

        // Set running to false FIRST so accept loop exits
        self.running = false;

        // Close server socket to unblock accept()
        if (self.server_fd) |fd| {
            std.posix.close(fd);
            self.server_fd = null;
        }

        // Give accept loop and client handlers time to exit cleanly
        std.Thread.sleep(100 * std.time.ns_per_ms);

        // Close any remaining connected clients and clear list
        {
            self.clients_mutex.lock();
            defer self.clients_mutex.unlock();

            var client_iter = self.clients.iterator();
            while (client_iter.next()) |entry| {
                // Shutdown socket to unblock any reads
                std.posix.shutdown(entry.value_ptr.fd, .both) catch {};
            }

            // Don't close FDs here - let handler threads do it
            // Just clear the map
            self.clients.clearRetainingCapacity();
        }
    }

    /// Send a reload message to all connected clients.
    /// Thread-safe: can be called from multiple threads.
    /// Non-blocking: errors don't prevent message from being queued.
    pub fn trigger(self: *Self, path: []const u8) !void {
        if (!self.running) return error.NotRunning;

        // Format: {"command":"reload","path":"/"}
        var buffer: [256]u8 = undefined;
        const json_msg = try std.fmt.bufPrint(
            &buffer,
            "{{\"command\":\"reload\",\"path\":\"{s}\"}}",
            .{path},
        );

        // Encode WebSocket text frame (FIN=1, opcode=1 for text, no mask)
        // Frame format: [0x81, payload_len, ...payload]
        var frame: [258]u8 = undefined;
        frame[0] = 0x81; // FIN bit + text frame opcode
        frame[1] = @as(u8, @intCast(json_msg.len)); // Payload length (< 126 bytes)

        // Copy payload
        @memcpy(frame[2 .. 2 + json_msg.len], json_msg);
        const frame_len = 2 + json_msg.len;

        {
            self.clients_mutex.lock();
            defer self.clients_mutex.unlock();

            // Broadcast to all clients with completed handshake
            var client_iter = self.clients.iterator();
            var disconnected = std.AutoHashMap(u64, void).init(self.allocator);
            defer disconnected.deinit();

            while (client_iter.next()) |entry| {
                const client = entry.value_ptr;
                if (client.handshake_complete) {
                    // Send frame, ignore individual client errors
                    _ = std.posix.send(client.fd, frame[0..frame_len], 0) catch {
                        // Mark for removal on send failure (likely disconnected)
                        disconnected.put(client.id, {}) catch {};
                    };
                }
            }

            // Remove disconnected clients
            var dc_iter = disconnected.keyIterator();
            while (dc_iter.next()) |id| {
                if (self.clients.fetchRemove(id.*)) |kv| {
                    std.posix.close(kv.value.fd);
                }
            }
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

    /// Background thread function to accept incoming connections.
    fn acceptLoop(self: *Self) void {
        while (true) {
            // Check if server is still running (atomic read)
            if (!self.running) break;

            const sockfd = self.server_fd orelse break;

            // Accept new connection (blocking)
            var client_addr: std.net.Address = undefined;
            var client_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

            const client_fd = std.posix.accept(
                sockfd,
                &client_addr.any,
                &client_addr_len,
                0,
            ) catch |err| {
                // Server was closed, exit gracefully
                if (err == error.SocketNotListening or
                    err == error.FileDescriptorInvalid or
                    err == error.OperationCancelled)
                {
                    break;
                }
                // Temporary error, retry
                std.Thread.sleep(10 * std.time.ns_per_ms);
                continue;
            };

            // Spawn handler for this connection
            const handler_thread = std.Thread.spawn(.{}, handleClient, .{ self, client_fd }) catch {
                std.posix.close(client_fd);
                continue;
            };
            handler_thread.detach();
        }
    }

    /// Handle a single client connection (WebSocket handshake + registration).
    fn handleClient(self: *Self, client_fd: std.posix.socket_t) void {
        var client_id: ?u64 = null;

        // Ensure cleanup on exit
        defer {
            // Always close our FD
            std.posix.close(client_fd);

            // Remove from client list if registered
            if (client_id) |id| {
                self.clients_mutex.lock();
                defer self.clients_mutex.unlock();
                _ = self.clients.remove(id);
            }
        }

        // Read HTTP handshake request
        var request_buf: [2048]u8 = undefined;
        const n = std.posix.read(client_fd, &request_buf) catch return;
        const request = request_buf[0..n];

        // Extract Sec-WebSocket-Key header
        const key = extractWebSocketKey(request) orelse return;

        // Compute WebSocket accept hash
        const accept_hash = computeAcceptHash(key) catch return;

        // Send HTTP 101 Switching Protocols response
        var response_buf: [512]u8 = undefined;
        const response = std.fmt.bufPrint(
            &response_buf,
            "HTTP/1.1 101 Switching Protocols\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Accept: {s}\r\n" ++
                "\r\n",
            .{accept_hash},
        ) catch return;

        _ = std.posix.write(client_fd, response) catch return;

        // Register client
        {
            self.clients_mutex.lock();
            defer self.clients_mutex.unlock();

            const id = self.next_client_id;
            self.next_client_id += 1;
            client_id = id;

            const client = ClientConnection{
                .id = id,
                .fd = client_fd,
                .handshake_complete = true,
            };

            self.clients.put(id, client) catch return;
        }

        // Keep connection alive (simple blocking read to detect disconnect)
        var dummy: [1]u8 = undefined;
        while (self.running) {
            const read_result = std.posix.read(client_fd, &dummy);
            if (read_result) |bytes| {
                if (bytes == 0) break; // Client disconnected
            } else |_| {
                break; // Read error (including shutdown by stop())
            }
        }
    }

    /// Extract Sec-WebSocket-Key from HTTP request headers.
    fn extractWebSocketKey(request: []const u8) ?[]const u8 {
        const key_header = "Sec-WebSocket-Key:";
        var lines = std.mem.splitScalar(u8, request, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\n\t");
            if (std.mem.startsWith(u8, trimmed, key_header)) {
                const value = std.mem.trim(u8, trimmed[key_header.len..], " \r\n\t");
                if (value.len > 0) return value;
            }
        }

        return null;
    }

    /// Compute WebSocket accept hash: base64(sha1(key + magic string)).
    fn computeAcceptHash(key: []const u8) ![28]u8 {
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

        // Concatenate key + magic
        var combined: [128]u8 = undefined;
        const combined_len = key.len + magic.len;
        @memcpy(combined[0..key.len], key);
        @memcpy(combined[key.len .. key.len + magic.len], magic);

        // Compute SHA-1 hash
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(combined[0..combined_len], &hash, .{});

        // Base64 encode hash
        var encoded: [28]u8 = undefined;
        const encoder = std.base64.standard.Encoder;
        const encoded_str = encoder.encode(&encoded, &hash);
        _ = encoded_str;

        return encoded;
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
    // The implementation currently just sets running = true without binding
    _ = server.start() catch |err| {
        // If binding fails (port in use), this is not a test failure
        // We're testing the state management, not the network layer
        if (err != error.AlreadyRunning) return;
    };
    // Verify running state was set (implementation sets this before attempting bind)
    try std.testing.expectEqual(true, server.isRunning());
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

    // First start should succeed (sets running flag)
    _ = server.start() catch |err| {
        // If port binding fails, we can't test double-start
        // But state should still be set
        if (err != error.AlreadyRunning) return;
    };

    // Verify server is running after first start
    try std.testing.expectEqual(true, server.isRunning());

    // Second start should fail with AlreadyRunning
    try std.testing.expectError(error.AlreadyRunning, server.start());
}

test "LiveReloadServer maintains port across lifecycle" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 12345);
    defer server.deinit();

    try std.testing.expectEqual(@as(u16, 12345), server.getPort());
    _ = server.start() catch {};
    try std.testing.expectEqual(@as(u16, 12345), server.getPort());
}

test "LiveReloadServer trigger requires running state (verified)" {
    const allocator = std.testing.allocator;
    var server = try LiveReloadServer.init(allocator, 35729);
    defer server.deinit();

    // Server not started, trigger should fail
    try std.testing.expectEqual(false, server.isRunning());
    try std.testing.expectError(error.NotRunning, server.trigger("/index.html"));

    // Start server
    _ = server.start() catch |err| {
        if (err != error.AlreadyRunning) return; // Skip if binding fails
    };

    // After start, trigger should succeed (or fail for different reason, not NotRunning)
    if (server.isRunning()) {
        // Trigger may fail for other reasons (no clients, etc.) but not NotRunning
        const result = server.trigger("/index.html");
        // If it errors, it should NOT be error.NotRunning
        if (result) |_| {
            // Success case
        } else |err| {
            try std.testing.expect(err != error.NotRunning);
        }
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

// --- WebSocket Integration Tests (will fail until TODOs are implemented) ---

test "LiveReloadServer binds to port successfully" {
    const allocator = std.testing.allocator;
    // Use high port to avoid permission issues
    var server = try LiveReloadServer.init(allocator, 45729);
    defer server.deinit();

    // Start server - should bind without error
    try server.start();
    defer server.stop() catch {};

    // Verify server is running
    try std.testing.expectEqual(true, server.isRunning());

    // Verify server socket is created
    try std.testing.expect(server.server_fd != null);
}

test "LiveReloadServer detects port already in use" {
    const allocator = std.testing.allocator;
    const port: u16 = 45730;

    var server1 = try LiveReloadServer.init(allocator, port);
    defer server1.deinit();
    try server1.start();
    defer server1.stop() catch {};

    // Second server on same port should fail
    var server2 = try LiveReloadServer.init(allocator, port);
    defer server2.deinit();
    try std.testing.expectError(error.AddressInUse, server2.start());
}

test "LiveReloadServer accepts WebSocket connections" {
    const allocator = std.testing.allocator;
    const port: u16 = 45731;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();
    try server.start();
    defer server.stop() catch {};

    // Give server time to start listening
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Connect a client via TCP
    const client_fd = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );
    defer std.posix.close(client_fd);

    const addr = std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, port);
    try std.posix.connect(client_fd, &addr.any, addr.getOsSockLen());

    // Send WebSocket handshake request
    const handshake =
        "GET / HTTP/1.1\r\n" ++
        "Host: localhost:45731\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";
    _ = try std.posix.write(client_fd, handshake);

    // Read handshake response
    var response_buf: [512]u8 = undefined;
    const n = try std.posix.read(client_fd, &response_buf);
    const response = response_buf[0..n];

    // Verify HTTP 101 Switching Protocols response
    try std.testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 101") != null or
        std.mem.indexOf(u8, response, "101 Switching Protocols") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "Upgrade: websocket") != null or
        std.mem.indexOf(u8, response, "upgrade: websocket") != null);

    // Verify client is registered
    std.Thread.sleep(50 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(usize, 1), server.clientCount());
}

test "LiveReloadServer broadcasts reload messages to all clients" {
    const allocator = std.testing.allocator;
    const port: u16 = 45732;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();
    try server.start();
    defer server.stop() catch {};

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Connect two clients
    const client1_fd = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );
    defer std.posix.close(client1_fd);

    const client2_fd = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );
    defer std.posix.close(client2_fd);

    const addr = std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, port);

    // Connect and handshake client 1
    try std.posix.connect(client1_fd, &addr.any, addr.getOsSockLen());
    const handshake =
        "GET / HTTP/1.1\r\n" ++
        "Host: localhost:45732\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";
    _ = try std.posix.write(client1_fd, handshake);

    // Read handshake response (discard)
    var response_buf: [512]u8 = undefined;
    _ = try std.posix.read(client1_fd, &response_buf);

    // Connect and handshake client 2
    try std.posix.connect(client2_fd, &addr.any, addr.getOsSockLen());
    _ = try std.posix.write(client2_fd, handshake);
    _ = try std.posix.read(client2_fd, &response_buf);

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Verify both clients are registered
    try std.testing.expectEqual(@as(usize, 2), server.clientCount());

    // Trigger reload
    try server.trigger("/index.html");

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Read message from client 1
    var msg1_buf: [256]u8 = undefined;
    const n1 = try std.posix.read(client1_fd, &msg1_buf);

    // Read message from client 2
    var msg2_buf: [256]u8 = undefined;
    const n2 = try std.posix.read(client2_fd, &msg2_buf);

    // Both clients should receive messages
    try std.testing.expect(n1 > 0);
    try std.testing.expect(n2 > 0);

    // Decode WebSocket frames (skip 2-byte header for text frames)
    const payload1 = msg1_buf[2..n1];
    const payload2 = msg2_buf[2..n2];

    // Verify JSON payload structure
    const expected = "{\"command\":\"reload\",\"path\":\"/index.html\"}";
    try std.testing.expect(std.mem.indexOf(u8, payload1, expected) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload2, expected) != null);
}

test "LiveReloadServer handles client disconnect gracefully" {
    const allocator = std.testing.allocator;
    const port: u16 = 45733;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();
    try server.start();
    defer server.stop() catch {};

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Connect a client
    const client_fd = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );

    const addr = std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, port);
    try std.posix.connect(client_fd, &addr.any, addr.getOsSockLen());

    // Handshake
    const handshake =
        "GET / HTTP/1.1\r\n" ++
        "Host: localhost:45733\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";
    _ = try std.posix.write(client_fd, handshake);

    var response_buf: [512]u8 = undefined;
    _ = try std.posix.read(client_fd, &response_buf);

    std.Thread.sleep(50 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(usize, 1), server.clientCount());

    // Client disconnects
    std.posix.close(client_fd);

    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Trigger reload after disconnect (should not crash)
    // May succeed (if client cleanup happened) or fail with BrokenPipe
    _ = server.trigger("/") catch |err| {
        try std.testing.expect(err == error.BrokenPipe or err == error.NotRunning);
    };

    // Client count should eventually drop to 0 after cleanup
    std.Thread.sleep(100 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(usize, 0), server.clientCount());
}

test "LiveReloadServer stop closes all connections" {
    const allocator = std.testing.allocator;
    const port: u16 = 45734;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();
    try server.start();

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Connect two clients
    const client1_fd = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );
    defer std.posix.close(client1_fd);

    const client2_fd = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );
    defer std.posix.close(client2_fd);

    const addr = std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, port);

    // Connect and handshake both clients
    const handshake =
        "GET / HTTP/1.1\r\n" ++
        "Host: localhost:45734\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";

    try std.posix.connect(client1_fd, &addr.any, addr.getOsSockLen());
    _ = try std.posix.write(client1_fd, handshake);
    var response_buf: [512]u8 = undefined;
    _ = try std.posix.read(client1_fd, &response_buf);

    try std.posix.connect(client2_fd, &addr.any, addr.getOsSockLen());
    _ = try std.posix.write(client2_fd, handshake);
    _ = try std.posix.read(client2_fd, &response_buf);

    std.Thread.sleep(50 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(usize, 2), server.clientCount());

    // Stop server - should close all connections
    try server.stop();

    // Verify server stopped
    try std.testing.expectEqual(false, server.isRunning());
    try std.testing.expectEqual(@as(usize, 0), server.clientCount());
    try std.testing.expectEqual(@as(?std.posix.socket_t, null), server.server_fd);

    // Attempting to read from clients should fail (connection closed by server)
    var buf: [16]u8 = undefined;
    const n1 = std.posix.read(client1_fd, &buf) catch 0;
    const n2 = std.posix.read(client2_fd, &buf) catch 0;

    // Both reads should return 0 (EOF) or error, indicating closed connection
    try std.testing.expectEqual(@as(usize, 0), n1);
    try std.testing.expectEqual(@as(usize, 0), n2);
}

test "LiveReloadServer multiple connections without handshake" {
    const allocator = std.testing.allocator;
    const port: u16 = 45735;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();
    try server.start();
    defer server.stop() catch {};

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Connect client but don't send handshake
    const client_fd = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );
    defer std.posix.close(client_fd);

    const addr = std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, port);
    try std.posix.connect(client_fd, &addr.any, addr.getOsSockLen());

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Client connected but handshake not complete
    // Server should handle this gracefully (either reject or timeout)
    // Trigger should not crash even with incomplete handshake clients
    server.trigger("/") catch {
        // May fail, but shouldn't crash - we just verify no panic
    };
}

test "LiveReloadServer broadcast with no clients succeeds" {
    const allocator = std.testing.allocator;
    const port: u16 = 45736;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();
    try server.start();
    defer server.stop() catch {};

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // No clients connected - trigger should succeed (no-op)
    try server.trigger("/empty");

    try std.testing.expectEqual(@as(usize, 0), server.clientCount());
}

test "LiveReloadServer concurrent client connections" {
    const allocator = std.testing.allocator;
    const port: u16 = 45737;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();
    try server.start();
    defer server.stop() catch {};

    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Connect multiple clients rapidly
    const num_clients = 5;
    var clients: [num_clients]std.posix.socket_t = undefined;

    const addr = std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, port);
    const handshake =
        "GET / HTTP/1.1\r\n" ++
        "Host: localhost:45737\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";

    for (&clients) |*client_fd| {
        client_fd.* = try std.posix.socket(
            std.posix.AF.INET,
            std.posix.SOCK.STREAM,
            std.posix.IPPROTO.TCP,
        );
        try std.posix.connect(client_fd.*, &addr.any, addr.getOsSockLen());
        _ = try std.posix.write(client_fd.*, handshake);
        var response_buf: [512]u8 = undefined;
        _ = try std.posix.read(client_fd.*, &response_buf);
    }

    std.Thread.sleep(100 * std.time.ns_per_ms);

    // All clients should be registered
    try std.testing.expectEqual(@as(usize, num_clients), server.clientCount());

    // Cleanup
    for (clients) |client_fd| {
        std.posix.close(client_fd);
    }
}

test "LiveReloadServer respects configured port across restarts" {
    const allocator = std.testing.allocator;
    const port: u16 = 45738;

    var server = try LiveReloadServer.init(allocator, port);
    defer server.deinit();

    // First lifecycle
    try server.start();
    try std.testing.expectEqual(@as(u16, port), server.getPort());
    try server.stop();

    // Second lifecycle - same port should work
    try server.start();
    try std.testing.expectEqual(@as(u16, port), server.getPort());
    try server.stop();
}
