// src/mcp/server.zig
//
// MCP server main loop - implements Model Context Protocol over JSON-RPC
// Phase 10A — MCP Server implementation

const std = @import("std");
const jsonrpc = @import("../jsonrpc/types.zig");
const parser = @import("../jsonrpc/parser.zig");
const writer = @import("../jsonrpc/writer.zig");
const capability = @import("capability.zig");
const handlers = @import("handlers.zig");
const line_input = @import("../cli/line_input.zig");
const assert = @import("../stdx.zig").assert;

/// Upper bound on one newline-delimited JSON-RPC request, in bytes.
const request_bytes_max: u32 = line_input.buffer_bytes_max;

const RequestLine = union(enum) {
    /// One request without its newline; borrows the caller's buffer.
    text: []const u8,
    /// The client closed stdin, or sent an empty line, which ends the session.
    end,
    /// The line exceeded the buffer; it was consumed through its newline.
    too_long,
};

/// Reads the next request line from `source`, a pointer to a value with `read([]u8) !usize`.
/// `buffer.len` is the request limit and must be non-zero. A line that does not fit is an
/// operating error (the bytes come from a client), reported as `.too_long`.
fn next_request_line(source: anytype, buffer: []u8) !RequestLine {
    assert(buffer.len > 0);
    assert(buffer.len <= request_bytes_max);

    const line = line_input.readLine(source, buffer) catch |err| switch (err) {
        error.LineTooLong => return .too_long,
        else => return err,
    };
    switch (line) {
        .eof => return .end,
        .text => |text| {
            if (text.len == 0) return .end;
            return .{ .text = text };
        },
    }
}

/// MCP server state
const ServerState = enum {
    uninitialized,
    initialized,
    shutdown,
};

/// Run MCP server (JSON-RPC over stdio, newline-delimited framing)
pub fn serve(allocator: std.mem.Allocator) !u8 {
    // For MCP server over stdio, we implement the protocol directly without Transport
    // to avoid Zig 0.15 reader/writer type conversion complexity.
    // The protocol is simple: newline-delimited JSON-RPC messages.

    const stdin_file = std.fs.File.stdin();
    const stdout_file = std.fs.File.stdout();

    var state = ServerState.uninitialized;

    // One request line is stored in this buffer, allocated once, so input cannot grow memory.
    const line_buf = try allocator.alloc(u8, request_bytes_max);
    defer allocator.free(line_buf);

    // Main server loop
    while (true) {
        const json_text = switch (next_request_line(&stdin_file, line_buf) catch |err| {
            std.debug.print("MCP server: read error: {s}\n", .{@errorName(err)});
            return 1;
        }) {
            .text => |text| text,
            .end => break,
            .too_long => {
                std.debug.print("MCP server: request over {d} bytes\n", .{request_bytes_max});
                continue;
            },
        };

        // Parse the JSON-RPC message
        var message = parser.parseMessage(allocator, json_text) catch |err| {
            std.debug.print("MCP server: failed to parse message: {s}\n", .{@errorName(err)});
            continue;
        };
        defer message.deinit(allocator);

        switch (message) {
            .request => |req| {
                const response = handleRequest(allocator, &state, req) catch |err| {
                    std.debug.print("MCP server: error handling request: {s}\n", .{@errorName(err)});
                    const err_code: jsonrpc.ErrorCode = switch (err) {
                        error.MethodNotFound => .method_not_found,
                        error.InvalidParams, error.MissingToolName => .invalid_params,
                        error.ServerNotInitialized => .server_not_initialized,
                        else => .internal_error,
                    };
                    var err_resp = jsonrpc.ErrorResponse{
                        .jsonrpc = jsonrpc.JSONRPC_VERSION,
                        .id = try req.id.clone(allocator),
                        .@"error" = .{
                            .code = err_code,
                            .message = try allocator.dupe(u8, @errorName(err)),
                        },
                    };
                    defer err_resp.deinit(allocator);
                    const err_json = try writer.serializeMessage(allocator, .{ .error_response = err_resp });
                    defer allocator.free(err_json);
                    try stdout_file.writeAll(err_json);
                    try stdout_file.writeAll("\n");
                    continue;
                };
                defer {
                    var mut_response = response;
                    mut_response.deinit(allocator);
                }

                const resp_json = try writer.serializeMessage(allocator, .{ .response = response });
                defer allocator.free(resp_json);
                try stdout_file.writeAll(resp_json);
                try stdout_file.writeAll("\n");
            },
            .notification => |notif| {
                if (std.mem.eql(u8, notif.method, "exit")) {
                    break;
                }
            },
            .response, .error_response => {
                std.debug.print("MCP server: unexpected response message\n", .{});
            },
        }
    }
    return 0;
}

/// Handle a single JSON-RPC request
fn handleRequest(
    allocator: std.mem.Allocator,
    state: *ServerState,
    req: jsonrpc.Request,
) !jsonrpc.Response {
    // Handle MCP initialization
    if (std.mem.eql(u8, req.method, "initialize")) {
        if (state.* != .uninitialized) {
            return error.AlreadyInitialized;
        }
        state.* = .initialized;

        // MCP-spec initialize response: { protocolVersion, capabilities, serverInfo }
        // Tools are NOT included here — clients must call tools/list to discover them.
        const cap_json = try capability.getCapabilities(allocator);
        return jsonrpc.Response{
            .jsonrpc = try allocator.dupe(u8, jsonrpc.JSONRPC_VERSION),
            .id = try req.id.clone(allocator),
            .result = cap_json,
        };
    }

    // Handle shutdown
    if (std.mem.eql(u8, req.method, "shutdown")) {
        state.* = .shutdown;
        const result = try allocator.dupe(u8, "null");
        return jsonrpc.Response{
            .jsonrpc = try allocator.dupe(u8, jsonrpc.JSONRPC_VERSION),
            .id = try req.id.clone(allocator),
            .result = result,
        };
    }

    // Check if initialized before handling tool calls
    if (state.* != .initialized) {
        return error.ServerNotInitialized;
    }

    // Handle tools/list — MCP discovery endpoint
    if (std.mem.eql(u8, req.method, "tools/list")) {
        const tools_json = try capability.getToolsList(allocator);
        return jsonrpc.Response{
            .jsonrpc = try allocator.dupe(u8, jsonrpc.JSONRPC_VERSION),
            .id = try req.id.clone(allocator),
            .result = tools_json,
        };
    }

    // Handle tool calls (tools/call method in MCP)
    if (std.mem.eql(u8, req.method, "tools/call")) {
        return try handleToolCall(allocator, req);
    }

    // Unknown method
    return error.MethodNotFound;
}

/// Handle MCP tool call
fn handleToolCall(
    allocator: std.mem.Allocator,
    req: jsonrpc.Request,
) !jsonrpc.Response {
    // Parse params to extract tool name
    const params_json = req.params orelse return error.InvalidParams;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, params_json, .{});
    defer parsed.deinit();

    const params_obj = parsed.value.object;
    const tool_name_val = params_obj.get("name") orelse return error.MissingToolName;
    const tool_name = tool_name_val.string;

    // Pass the full params_json to handlers
    // Handlers use parseStringParam() to extract individual arguments
    // This approach avoids needing to serialize std.json.Value back to JSON
    // (which would require manual implementation in Zig 0.15)
    const tool_params: ?[]const u8 = params_json;

    // Call the tool handler
    var tool_result = handlers.handleTool(allocator, tool_name, tool_params) catch |err| {
        if (err == error.MethodNotFound) {
            return error.MethodNotFound;
        }
        return err;
    };
    defer tool_result.deinit(allocator);

    // Build MCP tool response format
    const result_json = try std.fmt.allocPrint(allocator,
        \\{{"content":[{{"type":"text","text":{s}}}]}}
    , .{tool_result.json});

    return jsonrpc.Response{
        .jsonrpc = try allocator.dupe(u8, jsonrpc.JSONRPC_VERSION),
        .id = try req.id.clone(allocator),
        .result = result_json,
    };
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "handleRequest: initialize sets state" {
    const allocator = std.testing.allocator;
    var state = ServerState.uninitialized;

    const req = jsonrpc.Request{
        .jsonrpc = jsonrpc.JSONRPC_VERSION,
        .id = .{ .number = 1 },
        .method = "initialize",
        .params = null,
    };

    var resp = try handleRequest(allocator, &state, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(ServerState.initialized, state);
    try std.testing.expect(std.mem.indexOf(u8, resp.result, "capabilities") != null);
}

test "handleRequest: shutdown sets state" {
    const allocator = std.testing.allocator;
    var state = ServerState.initialized;

    const req = jsonrpc.Request{
        .jsonrpc = jsonrpc.JSONRPC_VERSION,
        .id = .{ .number = 2 },
        .method = "shutdown",
        .params = null,
    };

    var resp = try handleRequest(allocator, &state, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(ServerState.shutdown, state);
}

test "handleRequest: tool call without initialize returns error" {
    const allocator = std.testing.allocator;
    var state = ServerState.uninitialized;

    const req = jsonrpc.Request{
        .jsonrpc = jsonrpc.JSONRPC_VERSION,
        .id = .{ .number = 3 },
        .method = "tools/call",
        .params = try allocator.dupe(u8,
            \\{"name":"list_tasks"}
        ),
    };
    defer allocator.free(req.params.?);

    try std.testing.expectError(error.ServerNotInitialized, handleRequest(allocator, &state, req));
}

const TestSource = struct {
    data: []const u8,
    position: usize = 0,

    pub fn read(source: *TestSource, out: []u8) error{NotOpenForReading}!usize {
        if (source.position >= source.data.len) return 0;
        out[0] = source.data[source.position];
        source.position += 1;
        return 1;
    }
};

const BrokenSource = struct {
    pub fn read(_: *BrokenSource, _: []u8) error{ NotOpenForReading, InputOutput }!usize {
        return error.InputOutput;
    }
};

test "next_request_line returns each line, then end on eof" {
    var source = TestSource{ .data = "{\"a\":1}\n{\"b\":2}\n" };
    var buffer: [32]u8 = undefined;

    const first = try next_request_line(&source, &buffer);
    try std.testing.expectEqualStrings("{\"a\":1}", first.text);
    const second = try next_request_line(&source, &buffer);
    try std.testing.expectEqualStrings("{\"b\":2}", second.text);
    try std.testing.expectEqual(RequestLine.end, try next_request_line(&source, &buffer));
}

test "next_request_line treats an empty line as the end of the session" {
    var source = TestSource{ .data = "\n{\"a\":1}\n" };
    var buffer: [32]u8 = undefined;

    try std.testing.expectEqual(RequestLine.end, try next_request_line(&source, &buffer));
}

test "next_request_line skips an over-long line and keeps framing" {
    var source = TestSource{ .data = "0123456789\nok\n" };
    var buffer: [4]u8 = undefined;

    try std.testing.expectEqual(RequestLine.too_long, try next_request_line(&source, &buffer));
    const next = try next_request_line(&source, &buffer);
    try std.testing.expectEqualStrings("ok", next.text);
}

test "next_request_line accepts a line of exactly the buffer size" {
    var source = TestSource{ .data = "abcd\n" };
    var buffer: [4]u8 = undefined;

    const line = try next_request_line(&source, &buffer);
    try std.testing.expectEqualStrings("abcd", line.text);
}

test "next_request_line propagates a read error" {
    var source = BrokenSource{};
    var buffer: [4]u8 = undefined;

    try std.testing.expectError(error.InputOutput, next_request_line(&source, &buffer));
}
