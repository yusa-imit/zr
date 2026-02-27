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
    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();

    var jw = std.json.writeStream(string.writer(), .{});

    switch (message) {
        .request => |req| try writeRequest(&jw, req),
        .notification => |notif| try writeNotification(&jw, notif),
        .response => |resp| try writeResponse(&jw, resp),
        .error_response => |err| try writeErrorResponse(&jw, err),
    }

    return try string.toOwnedSlice();
}

fn writeRequest(jw: anytype, req: Request) !void {
    try jw.beginObject();
    try jw.objectField("jsonrpc");
    try jw.write(req.jsonrpc);
    try jw.objectField("id");
    try writeMessageId(jw, req.id);
    try jw.objectField("method");
    try jw.write(req.method);
    if (req.params) |params| {
        try jw.objectField("params");
        try jw.print("{s}", .{params}); // params is already JSON
    }
    try jw.endObject();
}

fn writeNotification(jw: anytype, notif: Notification) !void {
    try jw.beginObject();
    try jw.objectField("jsonrpc");
    try jw.write(notif.jsonrpc);
    try jw.objectField("method");
    try jw.write(notif.method);
    if (notif.params) |params| {
        try jw.objectField("params");
        try jw.print("{s}", .{params}); // params is already JSON
    }
    try jw.endObject();
}

fn writeResponse(jw: anytype, resp: Response) !void {
    try jw.beginObject();
    try jw.objectField("jsonrpc");
    try jw.write(resp.jsonrpc);
    try jw.objectField("id");
    try writeMessageId(jw, resp.id);
    try jw.objectField("result");
    try jw.print("{s}", .{resp.result}); // result is already JSON
    try jw.endObject();
}

fn writeErrorResponse(jw: anytype, err: ErrorResponse) !void {
    try jw.beginObject();
    try jw.objectField("jsonrpc");
    try jw.write(err.jsonrpc);
    try jw.objectField("id");
    try writeMessageId(jw, err.id);
    try jw.objectField("error");
    try jw.beginObject();
    try jw.objectField("code");
    try jw.write(@intFromEnum(err.@"error".code));
    try jw.objectField("message");
    try jw.write(err.@"error".message);
    if (err.@"error".data) |data| {
        try jw.objectField("data");
        try jw.print("{s}", .{data}); // data is already JSON
    }
    try jw.endObject();
    try jw.endObject();
}

fn writeMessageId(jw: anytype, id: MessageId) !void {
    switch (id) {
        .string => |s| try jw.write(s),
        .number => |n| try jw.write(n),
        .null_id => try jw.write(null),
    }
}

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
