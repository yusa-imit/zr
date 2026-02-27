// src/jsonrpc/transport.zig
//
// JSON-RPC transport layer for stdio communication
// Supports both Content-Length framing (LSP) and newline-delimited (MCP)

const std = @import("std");
const types = @import("types.zig");
const parser = @import("parser.zig");
const writer = @import("writer.zig");
const Message = types.Message;

/// Transport framing mode
pub const FramingMode = enum {
    /// Content-Length: N\r\n\r\n{json} (LSP style)
    content_length,
    /// {json}\n (MCP style, newline-delimited)
    newline_delimited,
};

/// JSON-RPC transport over stdio
pub const Transport = struct {
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,
    mode: FramingMode,

    /// Initialize transport with given reader/writer (typically stdin/stdout)
    pub fn init(allocator: std.mem.Allocator, rdr: std.io.AnyReader, wtr: std.io.AnyWriter, mode: FramingMode) Transport {
        return .{
            .allocator = allocator,
            .reader = rdr,
            .writer = wtr,
            .mode = mode,
        };
    }


    /// Read a JSON-RPC message from the transport
    pub fn readMessage(self: *Transport) !Message {
        const json_text = switch (self.mode) {
            .content_length => try self.readContentLength(),
            .newline_delimited => try self.readNewlineDelimited(),
        };
        defer self.allocator.free(json_text);

        return try parser.parseMessage(self.allocator, json_text);
    }

    /// Write a JSON-RPC message to the transport
    pub fn writeMessage(self: *Transport, message: Message) !void {
        const json_text = try writer.serializeMessage(self.allocator, message);
        defer self.allocator.free(json_text);

        switch (self.mode) {
            .content_length => try self.writeContentLength(json_text),
            .newline_delimited => try self.writeNewlineDelimited(json_text),
        }
    }

    // ──── Content-Length framing ────

    fn readContentLength(self: *Transport) ![]const u8 {
        // Read headers until we find Content-Length
        var content_length: ?usize = null;

        var header_buf: [256]u8 = undefined;
        while (true) {
            const line = try self.reader.readUntilDelimiter(&header_buf, '\n');

            // Trim \r if present
            const trimmed = if (line.len > 0 and line[line.len - 1] == '\r')
                line[0 .. line.len - 1]
            else
                line;

            // Empty line signals end of headers
            if (trimmed.len == 0) break;

            // Parse Content-Length header
            if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
                const value_str = std.mem.trim(u8, trimmed[15..], " \t");
                content_length = try std.fmt.parseInt(usize, value_str, 10);
            }
        }

        if (content_length == null) return error.MissingContentLength;

        // Read the JSON body
        const body = try self.allocator.alloc(u8, content_length.?);
        errdefer self.allocator.free(body);

        const bytes_read = try self.reader.readAll(body);
        if (bytes_read != content_length.?) return error.UnexpectedEof;

        return body;
    }

    fn writeContentLength(self: *Transport, json_text: []const u8) !void {
        // Write Content-Length header
        try self.writer.print("Content-Length: {d}\r\n\r\n", .{json_text.len});
        // Write JSON body
        try self.writer.writeAll(json_text);
        // Flush to ensure immediate delivery
        if (@hasDecl(@TypeOf(self.writer), "context")) {
            if (@hasDecl(@TypeOf(self.writer.context.*), "flush")) {
                try self.writer.context.flush();
            }
        }
    }

    // ──── Newline-delimited framing ────

    fn readNewlineDelimited(self: *Transport) ![]const u8 {
        var line_buf = std.ArrayList(u8){};
        defer line_buf.deinit(self.allocator);

        // Read until newline
        try self.reader.streamUntilDelimiter(line_buf.writer(self.allocator), '\n', null);

        return try line_buf.toOwnedSlice(self.allocator);
    }

    fn writeNewlineDelimited(self: *Transport, json_text: []const u8) !void {
        try self.writer.writeAll(json_text);
        try self.writer.writeByte('\n');
        // Flush
        if (@hasDecl(@TypeOf(self.writer), "context")) {
            if (@hasDecl(@TypeOf(self.writer.context.*), "flush")) {
                try self.writer.context.flush();
            }
        }
    }
};

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "Content-Length framing: write and read" {
    const allocator = std.testing.allocator;

    // Create a pipe for testing
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const req = types.Request{
        .jsonrpc = types.JSONRPC_VERSION,
        .id = .{ .number = 1 },
        .method = "test/method",
        .params = null,
    };

    const json = try writer.serializeMessage(allocator, .{ .request = req });
    defer allocator.free(json);

    // Write with Content-Length framing
    var buf_writer = buf.writer().any();
    const expected_header = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n\r\n", .{json.len});
    defer allocator.free(expected_header);

    try buf_writer.writeAll(expected_header);
    try buf_writer.writeAll(json);

    // Read back
    var fbs = std.io.fixedBufferStream(buf.items);
    var transport = Transport{
        .allocator = allocator,
        .reader = fbs.reader().any(),
        .writer = std.io.null_writer.any(),
        .mode = .content_length,
    };

    const read_json = try transport.readContentLength();
    defer allocator.free(read_json);

    try std.testing.expectEqualStrings(json, read_json);
}

test "Newline-delimited framing: write and read" {
    const allocator = std.testing.allocator;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const notif = types.Notification{
        .jsonrpc = types.JSONRPC_VERSION,
        .method = "notify",
        .params = null,
    };

    const json = try writer.serializeMessage(allocator, .{ .notification = notif });
    defer allocator.free(json);

    // Write with newline delimiter
    var buf_writer = buf.writer().any();
    try buf_writer.writeAll(json);
    try buf_writer.writeByte('\n');

    // Read back
    var fbs = std.io.fixedBufferStream(buf.items);
    var transport = Transport{
        .allocator = allocator,
        .reader = fbs.reader().any(),
        .writer = std.io.null_writer.any(),
        .mode = .newline_delimited,
    };

    const read_json = try transport.readNewlineDelimited();
    defer allocator.free(read_json);

    try std.testing.expectEqualStrings(json, read_json);
}

test "Content-Length: missing header" {
    const allocator = std.testing.allocator;

    const input = "\r\n{\"invalid\":true}";
    var fbs = std.io.fixedBufferStream(input);

    var transport = Transport{
        .allocator = allocator,
        .reader = fbs.reader().any(),
        .writer = std.io.null_writer.any(),
        .mode = .content_length,
    };

    try std.testing.expectError(error.MissingContentLength, transport.readContentLength());
}
