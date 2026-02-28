const std = @import("std");
const jsonrpc_types = @import("../jsonrpc/types.zig");
const jsonrpc_parser = @import("../jsonrpc/parser.zig");
const document_mod = @import("document.zig");
const handlers = @import("handlers.zig");
const completion_mod = @import("completion.zig");
const hover_mod = @import("hover.zig");
const definition_mod = @import("definition.zig");

/// LSP server state
pub const Server = struct {
    allocator: std.mem.Allocator,
    doc_store: document_mod.DocumentStore,
    initialized: bool = false,
    shutdown_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator) Server {
        return Server{
            .allocator = allocator,
            .doc_store = document_mod.DocumentStore.init(allocator),
        };
    }

    pub fn deinit(self: *Server) void {
        self.doc_store.deinit();
    }

    /// Main server loop - read from stdin, write to stdout
    pub fn run(self: *Server) !void {
        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();

        var header_buf = std.ArrayList(u8){};
        defer header_buf.deinit(self.allocator);

        var read_buf: [1]u8 = undefined;

        while (!self.shutdown_requested) {
            // Read Content-Length header
            header_buf.clearRetainingCapacity();
            var content_length: ?usize = null;

            // Read headers until \r\n\r\n
            var prev_char: u8 = 0;
            var empty_line_count: u8 = 0;

            while (true) {
                const n = stdin.read(&read_buf) catch |err| {
                    if (err == error.EndOfStream) return;
                    return err;
                };
                if (n == 0) return; // EOF

                const ch = read_buf[0];
                try header_buf.append(self.allocator, ch);

                // Detect \r\n\r\n (end of headers)
                if (ch == '\n' and prev_char == '\r') {
                    empty_line_count += 1;
                    if (empty_line_count == 2) break;
                } else if (ch != '\r' and ch != '\n') {
                    empty_line_count = 0;
                }
                prev_char = ch;
            }

            // Parse Content-Length from headers
            const headers = header_buf.items;
            if (std.mem.indexOf(u8, headers, "Content-Length: ")) |idx| {
                const value_start = idx + "Content-Length: ".len;
                var value_end = value_start;
                while (value_end < headers.len and headers[value_end] >= '0' and headers[value_end] <= '9') {
                    value_end += 1;
                }
                const length_str = headers[value_start..value_end];
                content_length = std.fmt.parseInt(usize, length_str, 10) catch null;
            }

            const len = content_length orelse continue;

            // Read JSON content
            const json_buf = try self.allocator.alloc(u8, len);
            defer self.allocator.free(json_buf);

            var bytes_read: usize = 0;
            while (bytes_read < len) {
                const n = try stdin.read(json_buf[bytes_read..]);
                if (n == 0) return; // EOF
                bytes_read += n;
            }

            // Parse and handle message
            try self.handleMessage(json_buf, stdout);
        }
    }

    fn handleMessage(self: *Server, json: []const u8, stdout: std.fs.File) !void {
        var message = jsonrpc_parser.parseMessage(self.allocator, json) catch |err| {
            std.debug.print("LSP: failed to parse message: {}\n", .{err});
            return;
        };
        defer message.deinit(self.allocator);

        switch (message) {
            .request => |req| {
                const response_json = try self.handleRequest(req);
                if (response_json) |resp_json| {
                    defer self.allocator.free(resp_json);
                    try self.writeResponse(stdout, resp_json);
                }
            },
            .notification => |notif| {
                const notif_json = try self.handleNotification(notif);
                if (notif_json) |resp_json| {
                    defer self.allocator.free(resp_json);
                    try self.writeResponse(stdout, resp_json);
                }
            },
            .response, .error_response => {
                // Server doesn't handle responses/errors (only sends them)
            },
        }
    }

    fn writeResponse(self: *Server, stdout: std.fs.File, json: []const u8) !void {
        const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{json.len});
        defer self.allocator.free(header);

        try stdout.writeAll(header);
        try stdout.writeAll(json);
        // Don't call sync() - writeAll() is unbuffered and sync() fails on pipes/TTYs
    }

    /// Handle JSON-RPC request (expects response)
    fn handleRequest(self: *Server, request: jsonrpc_types.Request) !?[]const u8 {
        if (std.mem.eql(u8, request.method, "initialize")) {
            self.initialized = true;
            return try handlers.handleInitialize(self.allocator, &request);
        } else if (std.mem.eql(u8, request.method, "shutdown")) {
            // Don't set shutdown_requested here - wait for exit notification
            return try handlers.handleShutdown(self.allocator, &request);
        } else if (std.mem.eql(u8, request.method, "textDocument/completion")) {
            if (!self.initialized) {
                return try self.errorResponse(request.id, .server_not_initialized, "Server not initialized");
            }
            const params = request.params orelse return try self.errorResponse(request.id, .invalid_params, "Missing params");
            return try completion_mod.handleCompletion(self.allocator, &request, params, &self.doc_store);
        } else if (std.mem.eql(u8, request.method, "textDocument/hover")) {
            if (!self.initialized) {
                return try self.errorResponse(request.id, .server_not_initialized, "Server not initialized");
            }
            const params = request.params orelse return try self.errorResponse(request.id, .invalid_params, "Missing params");
            return try hover_mod.handleHover(self.allocator, &request, params, &self.doc_store);
        } else if (std.mem.eql(u8, request.method, "textDocument/definition")) {
            if (!self.initialized) {
                return try self.errorResponse(request.id, .server_not_initialized, "Server not initialized");
            }
            const params = request.params orelse return try self.errorResponse(request.id, .invalid_params, "Missing params");
            return try definition_mod.handleDefinition(self.allocator, &request, params, &self.doc_store);
        } else {
            // Unknown method
            if (!self.initialized) {
                return try self.errorResponse(request.id, .server_not_initialized, "Server not initialized");
            }
            return try self.errorResponse(request.id, .method_not_found, "Method not found");
        }
    }

    /// Handle JSON-RPC notification (no response expected)
    fn handleNotification(self: *Server, notification: jsonrpc_types.Notification) !?[]const u8 {
        if (std.mem.eql(u8, notification.method, "initialized")) {
            try handlers.handleInitialized();
            return null;
        } else if (std.mem.eql(u8, notification.method, "exit")) {
            self.shutdown_requested = true;
            return null;
        } else if (std.mem.eql(u8, notification.method, "textDocument/didOpen")) {
            const params = notification.params orelse return null;
            return try handlers.handleDidOpen(self.allocator, params, &self.doc_store);
        } else if (std.mem.eql(u8, notification.method, "textDocument/didChange")) {
            const params = notification.params orelse return null;
            return try handlers.handleDidChange(self.allocator, params, &self.doc_store);
        } else if (std.mem.eql(u8, notification.method, "textDocument/didClose")) {
            const params = notification.params orelse return null;
            try handlers.handleDidClose(params, &self.doc_store);
            return null;
        } else {
            // Unknown notification - ignore
            return null;
        }
    }

    /// Create error response
    fn errorResponse(self: *Server, id: jsonrpc_types.MessageId, code: jsonrpc_types.ErrorCode, message: []const u8) ![]const u8 {
        const msg_copy = try self.allocator.dupe(u8, message);
        defer self.allocator.free(msg_copy);

        const error_obj = jsonrpc_types.ErrorObject{
            .code = code,
            .message = msg_copy,
        };

        const id_json = switch (id) {
            .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
            .number => |n| try std.fmt.allocPrint(self.allocator, "{d}", .{n}),
            .null_id => try self.allocator.dupe(u8, "null"),
        };
        defer self.allocator.free(id_json);

        return std.fmt.allocPrint(self.allocator,
            \\{{"jsonrpc":"2.0","id":{s},"error":{{"code":{d},"message":"{s}"}}}}
        , .{ id_json, @intFromEnum(error_obj.code), error_obj.message });
    }
};

/// Entry point for LSP server
pub fn serve(allocator: std.mem.Allocator) !u8 {
    var server = Server.init(allocator);
    defer server.deinit();

    try server.run();
    return 0;
}

test "Server - init and deinit" {
    const allocator = std.testing.allocator;
    var server = Server.init(allocator);
    defer server.deinit();

    try std.testing.expect(!server.initialized);
    try std.testing.expect(!server.shutdown_requested);
}
