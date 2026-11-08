//! JSON-RPC 2.0 message serialization shared by the MCP and LSP servers.
//!
//! Invariants: every string field (`id`, `method`, error `message`) is written through
//! `std.json.fmt`, so quotes, backslashes and control bytes are escaped and the output parses as
//! JSON. `params`, `result` and error `data` are already raw JSON text and are written verbatim;
//! the caller guarantees they are valid JSON.
//!
//! Allocation: `serializeMessage` returns a caller-owned slice; `createResponse` and
//! `createErrorResponse` return values whose strings the caller frees through `deinit`. Nothing is
//! retained after a call returns.

const std = @import("std");
const types = @import("types.zig");
const Message = types.Message;
const Request = types.Request;
const Notification = types.Notification;
const Response = types.Response;
const ErrorResponse = types.ErrorResponse;
const MessageId = types.MessageId;

/// Serialize a JSON-RPC message to a string
pub fn serializeMessage(allocator: std.mem.Allocator, message: Message) ![]const u8 {
    // Note: Zig 0.15.2 does not provide std.json.stringify for arbitrary structs.
    // Manual JSON string building is the standard approach for this version.
    return switch (message) {
        .request => |req| try buildRequestJson(allocator, req),
        .notification => |notif| try buildNotificationJson(allocator, notif),
        .response => |resp| try buildResponseJson(allocator, resp),
        .error_response => |err| try buildErrorResponseJson(allocator, err),
    };
}

/// Render a message id as JSON text; string ids are quoted and escaped. Caller frees the result.
fn formatId(allocator: std.mem.Allocator, id: MessageId) ![]const u8 {
    return switch (id) {
        .string => |s| try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(s, .{})}),
        .number => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        .null_id => try allocator.dupe(u8, "null"),
    };
}

fn buildRequestJson(allocator: std.mem.Allocator, req: Request) ![]const u8 {
    const id_str = try formatId(allocator, req.id);
    defer allocator.free(id_str);

    if (req.params) |params| {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"method":{f},"params":{s}}}
        , .{ req.jsonrpc, id_str, std.json.fmt(req.method, .{}), params });
    } else {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"method":{f}}}
        , .{ req.jsonrpc, id_str, std.json.fmt(req.method, .{}) });
    }
}

fn buildNotificationJson(allocator: std.mem.Allocator, notif: Notification) ![]const u8 {
    if (notif.params) |params| {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","method":{f},"params":{s}}}
        , .{ notif.jsonrpc, std.json.fmt(notif.method, .{}), params });
    } else {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","method":{f}}}
        , .{ notif.jsonrpc, std.json.fmt(notif.method, .{}) });
    }
}

fn buildResponseJson(allocator: std.mem.Allocator, resp: Response) ![]const u8 {
    const id_str = try formatId(allocator, resp.id);
    defer allocator.free(id_str);

    return try std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"{s}","id":{s},"result":{s}}}
    , .{ resp.jsonrpc, id_str, resp.result });
}

fn buildErrorResponseJson(allocator: std.mem.Allocator, err: ErrorResponse) ![]const u8 {
    const id_str = try formatId(allocator, err.id);
    defer allocator.free(id_str);

    const code = @intFromEnum(err.@"error".code);
    const message = std.json.fmt(err.@"error".message, .{});
    if (err.@"error".data) |data| {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"error":{{"code":{d},"message":{f},"data":{s}}}}}
        , .{ err.jsonrpc, id_str, code, message, data });
    } else {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"error":{{"code":{d},"message":{f}}}}}
        , .{ err.jsonrpc, id_str, code, message });
    }
}

// Deprecated write functions - removed for Zig 0.15 compatibility

/// Create a success response
pub fn createResponse(allocator: std.mem.Allocator, id: MessageId, result: []const u8) !Response {
    return Response{
        .jsonrpc = try allocator.dupe(u8, types.JSONRPC_VERSION),
        .id = try id.clone(allocator),
        .result = try allocator.dupe(u8, result),
    };
}

/// Create an error response
pub fn createErrorResponse(
    allocator: std.mem.Allocator,
    id: MessageId,
    code: types.ErrorCode,
    message: []const u8,
    data: ?[]const u8,
) !ErrorResponse {
    return ErrorResponse{
        .jsonrpc = try allocator.dupe(u8, types.JSONRPC_VERSION),
        .id = try id.clone(allocator),
        .@"error" = .{
            .code = code,
            .message = try allocator.dupe(u8, message),
            .data = if (data) |d| try allocator.dupe(u8, d) else null,
        },
    };
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "serialize request with string id" {
    const allocator = std.testing.allocator;

    const req = Request{
        .jsonrpc = types.JSONRPC_VERSION,
        .id = .{ .string = "test-id" },
        .method = "test/method",
        .params = null,
    };

    const json = try serializeMessage(allocator, .{ .request = req });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"test-id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"method\":\"test/method\"") != null);
}

test "serialize notification" {
    const allocator = std.testing.allocator;

    const notif = Notification{
        .jsonrpc = types.JSONRPC_VERSION,
        .method = "notify/event",
        .params = null,
    };

    const json = try serializeMessage(allocator, .{ .notification = notif });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"method\":\"notify/event\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\"") == null); // No id in notification
}

test "serialize response" {
    const allocator = std.testing.allocator;

    const resp = Response{
        .jsonrpc = types.JSONRPC_VERSION,
        .id = .{ .number = 42 },
        .result = "true",
    };

    const json = try serializeMessage(allocator, .{ .response = resp });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":true") != null);
}

test "serialize error response" {
    const allocator = std.testing.allocator;

    const err_resp = ErrorResponse{
        .jsonrpc = types.JSONRPC_VERSION,
        .id = .{ .string = "err-1" },
        .@"error" = .{
            .code = .method_not_found,
            .message = "Method not found",
            .data = null,
        },
    };

    const json = try serializeMessage(allocator, .{ .error_response = err_resp });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"code\":-32601") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"message\":\"Method not found\"") != null);
}

test "createResponse helper" {
    const allocator = std.testing.allocator;

    const id = MessageId{ .string = try allocator.dupe(u8, "test") };
    defer id.deinit(allocator);

    var resp = try createResponse(allocator, id, "100");
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("test", resp.id.string);
    try std.testing.expectEqualStrings("100", resp.result);
}

test "createErrorResponse helper" {
    const allocator = std.testing.allocator;

    const id = MessageId{ .number = 99 };

    var err_resp = try createErrorResponse(allocator, id, .invalid_params, "Bad params", null);
    defer err_resp.deinit(allocator);

    try std.testing.expectEqual(99, err_resp.id.number);
    try std.testing.expectEqual(types.ErrorCode.invalid_params, err_resp.@"error".code);
    try std.testing.expectEqualStrings("Bad params", err_resp.@"error".message);
}

test "serialize error response escapes quotes, backslashes and control bytes" {
    const allocator = std.testing.allocator;

    const err_resp = ErrorResponse{
        .jsonrpc = types.JSONRPC_VERSION,
        .id = .{ .string = "id\"1\\" },
        .@"error" = .{
            .code = .method_not_found,
            .message = "Unknown method \"a\\b\"\nline2",
            .data = null,
        },
    };

    const json = try serializeMessage(allocator, .{ .error_response = err_resp });
    defer allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try std.testing.expectEqualStrings("id\"1\\", root.get("id").?.string);
    const message = root.get("error").?.object.get("message").?.string;
    try std.testing.expectEqualStrings("Unknown method \"a\\b\"\nline2", message);
}

test "serialize request and notification escape the method name" {
    const allocator = std.testing.allocator;

    const req = Request{ .id = .{ .string = "a\"b" }, .method = "m\"x\\y", .params = null };
    const req_json = try serializeMessage(allocator, .{ .request = req });
    defer allocator.free(req_json);
    const req_parsed = try std.json.parseFromSlice(std.json.Value, allocator, req_json, .{});
    defer req_parsed.deinit();
    try std.testing.expectEqualStrings("m\"x\\y", req_parsed.value.object.get("method").?.string);
    try std.testing.expectEqualStrings("a\"b", req_parsed.value.object.get("id").?.string);

    const notif = Notification{ .method = "n\"\t", .params = null };
    const notif_json = try serializeMessage(allocator, .{ .notification = notif });
    defer allocator.free(notif_json);
    const notif_parsed = try std.json.parseFromSlice(std.json.Value, allocator, notif_json, .{});
    defer notif_parsed.deinit();
    try std.testing.expectEqualStrings("n\"\t", notif_parsed.value.object.get("method").?.string);
}

test "serialize response escapes a string id" {
    const allocator = std.testing.allocator;

    const resp = Response{ .id = .{ .string = "q\"\n" }, .result = "null" };
    const json = try serializeMessage(allocator, .{ .response = resp });
    defer allocator.free(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("q\"\n", parsed.value.object.get("id").?.string);
}
