// src/jsonrpc/writer.zig
//
// JSON-RPC 2.0 message serialization

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
    // TODO(Zig 0.15): std.json.writeStream doesn't exist
    // Manually build JSON strings for now
    return switch (message) {
        .request => |req| try buildRequestJson(allocator, req),
        .notification => |notif| try buildNotificationJson(allocator, notif),
        .response => |resp| try buildResponseJson(allocator, resp),
        .error_response => |err| try buildErrorResponseJson(allocator, err),
    };
}

fn buildRequestJson(allocator: std.mem.Allocator, req: Request) ![]const u8 {
    const id_str = switch (req.id) {
        .string => |s| try std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .number => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        .null_id => try allocator.dupe(u8, "null"),
    };
    defer allocator.free(id_str);

    if (req.params) |params| {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"method":"{s}","params":{s}}}
        , .{ req.jsonrpc, id_str, req.method, params });
    } else {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"method":"{s}"}}
        , .{ req.jsonrpc, id_str, req.method });
    }
}

fn buildNotificationJson(allocator: std.mem.Allocator, notif: Notification) ![]const u8 {
    if (notif.params) |params| {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","method":"{s}","params":{s}}}
        , .{ notif.jsonrpc, notif.method, params });
    } else {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","method":"{s}"}}
        , .{ notif.jsonrpc, notif.method });
    }
}

fn buildResponseJson(allocator: std.mem.Allocator, resp: Response) ![]const u8 {
    const id_str = switch (resp.id) {
        .string => |s| try std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .number => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        .null_id => try allocator.dupe(u8, "null"),
    };
    defer allocator.free(id_str);

    return try std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"{s}","id":{s},"result":{s}}}
    , .{ resp.jsonrpc, id_str, resp.result });
}

fn buildErrorResponseJson(allocator: std.mem.Allocator, err: ErrorResponse) ![]const u8 {
    const id_str = switch (err.id) {
        .string => |s| try std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .number => |n| try std.fmt.allocPrint(allocator, "{d}", .{n}),
        .null_id => try allocator.dupe(u8, "null"),
    };
    defer allocator.free(id_str);

    if (err.@"error".data) |data| {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"error":{{"code":{d},"message":"{s}","data":{s}}}}}
        , .{ err.jsonrpc, id_str, @intFromEnum(err.@"error".code), err.@"error".message, data });
    } else {
        return try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"{s}","id":{s},"error":{{"code":{d},"message":"{s}"}}}}
        , .{ err.jsonrpc, id_str, @intFromEnum(err.@"error".code), err.@"error".message });
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
