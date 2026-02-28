// src/mcp/server.zig
//
// MCP server main loop - implements Model Context Protocol over JSON-RPC
// Phase 10A — MCP Server implementation

const std = @import("std");
const jsonrpc = @import("../jsonrpc/types.zig");
const transport = @import("../jsonrpc/transport.zig");
const parser = @import("../jsonrpc/parser.zig");
const writer = @import("../jsonrpc/writer.zig");
const capability = @import("capability.zig");
const handlers = @import("handlers.zig");

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

    // Input buffer for reading lines from stdin
    var line_buf = std.ArrayList(u8){};
    defer line_buf.deinit(allocator);

    // Buffer for reading stdin
    var read_buf: [1]u8 = undefined;

    // Main server loop
    while (true) {
        // Read a line from stdin (newline-delimited) - byte by byte
        line_buf.clearRetainingCapacity();
        while (true) {
            const n = stdin_file.read(&read_buf) catch |err| {
                if (err == error.EndOfStream) break;
                std.debug.print("MCP server: read error: {s}\n", .{@errorName(err)});
                return 1;
            };
            if (n == 0) break; // EOF
            if (read_buf[0] == '\n') break; // End of line
            try line_buf.append(allocator, read_buf[0]);
        }

        if (line_buf.items.len == 0) break; // EOF with no data

        const json_text = line_buf.items;

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
                    const err_resp = jsonrpc.ErrorResponse{
                        .jsonrpc = jsonrpc.JSONRPC_VERSION,
                        .id = try req.id.clone(allocator),
                        .@"error" = .{
                            .code = .internal_error,
                            .message = try allocator.dupe(u8, @errorName(err)),
                        },
                    };
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

        // Return capabilities
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
        const result = try allocator.dupe(u8, "{}");
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
        .params = try allocator.dupe(u8, \\{"name":"list_tasks"}
        ),
    };
    defer allocator.free(req.params.?);

    try std.testing.expectError(error.ServerNotInitialized, handleRequest(allocator, &state, req));
}
