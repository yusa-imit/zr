const std = @import("std");
const storage = @import("storage.zig");

pub const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    data_dir: []const u8 = ".zr-registry",
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,
    storage: storage.Storage,
    server: std.net.Server,

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !Server {
        // Initialize storage.
        const store = try storage.Storage.init(allocator, config.data_dir);

        // Create TCP server.
        const address = try std.net.Address.parseIp(config.host, config.port);
        const server_socket = try address.listen(.{
            .reuse_address = true,
        });

        return Server{
            .allocator = allocator,
            .config = config,
            .storage = store,
            .server = server_socket,
        };
    }

    pub fn deinit(self: *Server) void {
        self.storage.deinit();
        self.server.deinit();
    }

    /// Start the server and accept connections.
    pub fn serve(self: *Server) !void {
        std.debug.print("Registry server listening on {s}:{d}\n", .{ self.config.host, self.config.port });

        while (true) {
            const connection = try self.server.accept();
            // Handle request in same thread (simple implementation).
            self.handleConnection(connection) catch |err| {
                std.debug.print("Error handling connection: {}\n", .{err});
            };
        }
    }

    fn handleConnection(self: *Server, connection: std.net.Server.Connection) !void {
        defer connection.stream.close();

        var buf: [4096]u8 = undefined;
        const n = try connection.stream.read(&buf);
        if (n == 0) return;

        const request_line = std.mem.sliceTo(buf[0..n], '\r');

        // Parse HTTP request line.
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return error.InvalidRequest;
        const path = parts.next() orelse return error.InvalidRequest;

        if (!std.mem.eql(u8, method, "GET")) {
            return self.sendResponse(connection.stream, 405, "Method Not Allowed", "text/plain");
        }

        try self.handleRequest(connection.stream, path);
    }

    fn handleRequest(self: *Server, stream: std.net.Stream, path: []const u8) !void {
        // Parse path and query string.
        var path_iter = std.mem.splitScalar(u8, path, '?');
        const base_path = path_iter.next() orelse return error.InvalidRequest;
        const query_string = path_iter.next();

        // Route to handlers.
        if (std.mem.eql(u8, base_path, "/v1/plugins/search")) {
            return self.handleSearch(stream, query_string);
        } else if (std.mem.startsWith(u8, base_path, "/v1/plugins/")) {
            // Check if it's a specific plugin or list.
            const plugin_path = base_path["/v1/plugins/".len..];
            if (plugin_path.len == 0) {
                return self.handleList(stream, query_string);
            } else {
                return self.handleGet(stream, plugin_path);
            }
        } else if (std.mem.eql(u8, base_path, "/health")) {
            return self.sendResponse(stream, 200, "{\"status\":\"ok\"}", "application/json");
        } else {
            return self.sendResponse(stream, 404, "Not Found", "text/plain");
        }
    }

    fn handleSearch(self: *Server, stream: std.net.Stream, query_string: ?[]const u8) !void {
        const query = self.parseQueryParam(query_string, "q") orelse "";
        const limit = self.parseIntParam(query_string, "limit") orelse 50;
        const offset = self.parseIntParam(query_string, "offset") orelse 0;

        const results = try self.storage.search(query, limit, offset);
        defer self.allocator.free(results);

        // Build JSON response.
        var json_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer json_buf.deinit(self.allocator);
        const writer = json_buf.writer(self.allocator);

        try writer.writeAll("{\"total\":");
        try writer.print("{d}", .{self.storage.count()});
        try writer.writeAll(",\"offset\":");
        try writer.print("{d}", .{offset});
        try writer.writeAll(",\"limit\":");
        try writer.print("{d}", .{limit});
        try writer.writeAll(",\"plugins\":[");

        for (results, 0..) |entry, i| {
            if (i > 0) try writer.writeAll(",");
            try self.writePluginJson(writer, &entry);
        }

        try writer.writeAll("]}");

        try self.sendResponse(stream, 200, json_buf.items, "application/json");
    }

    fn handleGet(self: *Server, stream: std.net.Stream, path: []const u8) !void {
        // Parse org/name from path.
        var path_iter = std.mem.splitScalar(u8, path, '/');
        const org = path_iter.next() orelse return error.InvalidRequest;
        const name = path_iter.next() orelse return error.InvalidRequest;

        const entry = self.storage.get(org, name);
        if (entry == null) {
            return self.sendResponse(stream, 404, "{\"error\":\"Plugin not found\"}", "application/json");
        }

        // Build JSON response with full details.
        var json_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer json_buf.deinit(self.allocator);
        const writer = json_buf.writer(self.allocator);

        try self.writePluginDetailsJson(writer, entry.?);

        try self.sendResponse(stream, 200, json_buf.items, "application/json");
    }

    fn handleList(self: *Server, stream: std.net.Stream, query_string: ?[]const u8) !void {
        const limit = self.parseIntParam(query_string, "limit") orelse 50;
        const offset = self.parseIntParam(query_string, "offset") orelse 0;

        const results = try self.storage.list(limit, offset);
        defer self.allocator.free(results);

        // Build JSON response.
        var json_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer json_buf.deinit(self.allocator);
        const writer = json_buf.writer(self.allocator);

        try writer.writeAll("{\"total\":");
        try writer.print("{d}", .{self.storage.count()});
        try writer.writeAll(",\"offset\":");
        try writer.print("{d}", .{offset});
        try writer.writeAll(",\"limit\":");
        try writer.print("{d}", .{limit});
        try writer.writeAll(",\"plugins\":[");

        for (results, 0..) |entry, i| {
            if (i > 0) try writer.writeAll(",");
            try self.writePluginJson(writer, &entry);
        }

        try writer.writeAll("]}");

        try self.sendResponse(stream, 200, json_buf.items, "application/json");
    }

    fn writePluginJson(self: *Server, writer: anytype, entry: *const storage.PluginEntry) !void {
        _ = self;
        try writer.writeAll("{");
        try writer.print("\"name\":\"{s}\"", .{entry.name});
        try writer.print(",\"org\":\"{s}\"", .{entry.org});
        try writer.print(",\"version\":\"{s}\"", .{entry.version});
        try writer.print(",\"description\":\"{s}\"", .{entry.description});
        try writer.print(",\"author\":\"{s}\"", .{entry.author});
        try writer.print(",\"repository\":\"{s}\"", .{entry.repository});
        try writer.writeAll(",\"tags\":[");
        for (entry.tags, 0..) |tag, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("\"{s}\"", .{tag});
        }
        try writer.writeAll("]");
        try writer.print(",\"downloads\":{d}", .{entry.downloads});
        try writer.print(",\"updated_at\":\"{s}\"", .{entry.updated_at});
        try writer.writeAll("}");
    }

    fn writePluginDetailsJson(self: *Server, writer: anytype, entry: *const storage.PluginEntry) !void {
        _ = self;
        try writer.writeAll("{");
        try writer.print("\"name\":\"{s}\"", .{entry.name});
        try writer.print(",\"org\":\"{s}\"", .{entry.org});
        try writer.print(",\"version\":\"{s}\"", .{entry.version});
        try writer.print(",\"description\":\"{s}\"", .{entry.description});
        try writer.print(",\"author\":\"{s}\"", .{entry.author});
        try writer.print(",\"repository\":\"{s}\"", .{entry.repository});
        try writer.writeAll(",\"tags\":[");
        for (entry.tags, 0..) |tag, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("\"{s}\"", .{tag});
        }
        try writer.writeAll("]");
        try writer.print(",\"downloads\":{d}", .{entry.downloads});
        try writer.writeAll(",\"versions\":[");
        for (entry.versions, 0..) |ver, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("\"{s}\"", .{ver});
        }
        try writer.writeAll("]");
        try writer.print(",\"readme\":\"{s}\"", .{entry.readme});
        try writer.print(",\"created_at\":\"{s}\"", .{entry.created_at});
        try writer.print(",\"updated_at\":\"{s}\"", .{entry.updated_at});
        try writer.writeAll("}");
    }

    fn parseQueryParam(self: *Server, query_string: ?[]const u8, key: []const u8) ?[]const u8 {
        _ = self;
        if (query_string == null) return null;

        var params = std.mem.splitScalar(u8, query_string.?, '&');
        while (params.next()) |param| {
            var kv = std.mem.splitScalar(u8, param, '=');
            const k = kv.next() orelse continue;
            const v = kv.next() orelse continue;
            if (std.mem.eql(u8, k, key)) return v;
        }

        return null;
    }

    fn parseIntParam(self: *Server, query_string: ?[]const u8, key: []const u8) ?usize {
        const str = self.parseQueryParam(query_string, key) orelse return null;
        return std.fmt.parseInt(usize, str, 10) catch null;
    }

    fn sendResponse(
        self: *Server,
        stream: std.net.Stream,
        status: u16,
        body: []const u8,
        content_type: []const u8,
    ) !void {
        _ = self;
        const status_text = switch (status) {
            200 => "OK",
            404 => "Not Found",
            405 => "Method Not Allowed",
            500 => "Internal Server Error",
            else => "Unknown",
        };

        var response_buf: [8192]u8 = undefined;
        const response = try std.fmt.bufPrint(
            &response_buf,
            "HTTP/1.1 {d} {s}\r\n" ++
                "Content-Type: {s}\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n" ++
                "{s}",
            .{ status, status_text, content_type, body.len, body },
        );

        _ = try stream.writeAll(response);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Server: init and deinit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_dir);

    // Use a random high port to avoid conflicts.
    const config = ServerConfig{
        .host = "127.0.0.1",
        .port = 9876,
        .data_dir = data_dir,
    };

    var server = try Server.init(allocator, config);
    defer server.deinit();

    try std.testing.expectEqual(@as(usize, 0), server.storage.count());
}

test "Server: parseQueryParam" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_dir);

    const config = ServerConfig{ .port = 9877, .data_dir = data_dir };
    var server = try Server.init(allocator, config);
    defer server.deinit();

    const result = server.parseQueryParam("q=docker&limit=10", "q");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("docker", result.?);

    const limit = server.parseIntParam("q=docker&limit=10", "limit");
    try std.testing.expectEqual(@as(usize, 10), limit.?);
}
