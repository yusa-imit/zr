// src/jsonrpc/parser.zig
//
// JSON-RPC 2.0 message parser
// Supports both Content-Length framing (LSP) and newline-delimited (MCP)

const std = @import("std");
const types = @import("types.zig");
const Message = types.Message;
const MessageId = types.MessageId;
const Request = types.Request;
const Notification = types.Notification;
const Response = types.Response;
const ErrorResponse = types.ErrorResponse;
const ErrorObject = types.ErrorObject;
const ErrorCode = types.ErrorCode;

/// Parse a JSON-RPC message from a JSON string
pub fn parseMessage(allocator: std.mem.Allocator, json_text: []const u8) !Message {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidRequest;

    const obj = root.object;

    // Validate jsonrpc version
    const jsonrpc_val = obj.get("jsonrpc") orelse return error.InvalidRequest;
    if (jsonrpc_val != .string) return error.InvalidRequest;
    if (!std.mem.eql(u8, jsonrpc_val.string, types.JSONRPC_VERSION)) {
        return error.InvalidRequest;
    }

    // Check if it's a response or request/notification
    const has_id = obj.contains("id");
    const has_result = obj.contains("result");
    const has_error = obj.contains("error");
    const has_method = obj.contains("method");

    if (has_result or has_error) {
        // It's a response
        if (!has_id) return error.InvalidRequest;

        const id = try parseMessageId(allocator, obj.get("id").?);
        errdefer id.deinit(allocator);

        if (has_result) {
            // Success response - store result as JSON string
            var result_str = std.ArrayList(u8).init(allocator);
            defer result_str.deinit();
            try std.json.stringify(obj.get("result").?, .{}, result_str.writer());

            return Message{
                .response = Response{
                    .jsonrpc = try allocator.dupe(u8, types.JSONRPC_VERSION),
                    .id = id,
                    .result = try result_str.toOwnedSlice(),
                },
            };
        } else {
            // Error response
            const err_obj = try parseErrorObject(allocator, obj.get("error").?);
            return Message{
                .error_response = ErrorResponse{
                    .jsonrpc = try allocator.dupe(u8, types.JSONRPC_VERSION),
                    .id = id,
                    .@"error" = err_obj,
                },
            };
        }
    } else if (has_method) {
        // It's a request or notification
        const method_val = obj.get("method").?;
        if (method_val != .string) return error.InvalidRequest;
        const method = try allocator.dupe(u8, method_val.string);
        errdefer allocator.free(method);

        // Store params as JSON string
        const params = if (obj.get("params")) |p| blk: {
            var params_str = std.ArrayList(u8).init(allocator);
            defer params_str.deinit();
            try std.json.stringify(p, .{}, params_str.writer());
            break :blk try params_str.toOwnedSlice();
        } else null;
        errdefer if (params) |par| allocator.free(par);

        if (has_id) {
            // Request
            const id = try parseMessageId(allocator, obj.get("id").?);
            return Message{
                .request = Request{
                    .jsonrpc = try allocator.dupe(u8, types.JSONRPC_VERSION),
                    .id = id,
                    .method = method,
                    .params = params,
                },
            };
        } else {
            // Notification
            return Message{
                .notification = Notification{
                    .jsonrpc = try allocator.dupe(u8, types.JSONRPC_VERSION),
                    .method = method,
                    .params = params,
                },
            };
        }
    } else {
        return error.InvalidRequest;
    }
}

fn parseMessageId(allocator: std.mem.Allocator, value: std.json.Value) !MessageId {
    return switch (value) {
        .string => |s| MessageId{ .string = try allocator.dupe(u8, s) },
        .integer => |i| MessageId{ .number = i },
        .null => MessageId.null_id,
        else => error.InvalidRequest,
    };
}

fn parseErrorObject(allocator: std.mem.Allocator, value: std.json.Value) !ErrorObject {
    if (value != .object) return error.InvalidRequest;
    const obj = value.object;

    const code_val = obj.get("code") orelse return error.InvalidRequest;
    if (code_val != .integer) return error.InvalidRequest;
    const code: ErrorCode = @enumFromInt(@as(i32, @intCast(code_val.integer)));

    const message_val = obj.get("message") orelse return error.InvalidRequest;
    if (message_val != .string) return error.InvalidRequest;
    const message = try allocator.dupe(u8, message_val.string);
    errdefer allocator.free(message);

    // Store data as JSON string if present
    const data = if (obj.get("data")) |d| blk: {
        var data_str = std.ArrayList(u8).init(allocator);
        defer data_str.deinit();
        try std.json.stringify(d, .{}, data_str.writer());
        break :blk try data_str.toOwnedSlice();
    } else null;

    return ErrorObject{
        .code = code,
        .message = message,
        .data = data,
    };
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "parse request with string id" {
    const allocator = std.testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":"req-1","method":"test/method","params":{"key":"value"}}
    ;

    var msg = try parseMessage(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(Message.request, std.meta.activeTag(msg));
    try std.testing.expectEqualStrings("test/method", msg.request.method);
    try std.testing.expectEqualStrings("req-1", msg.request.id.string);
}

test "parse request with number id" {
    const allocator = std.testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":42,"method":"test/method"}
    ;

    var msg = try parseMessage(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(Message.request, std.meta.activeTag(msg));
    try std.testing.expectEqual(42, msg.request.id.number);
}

test "parse notification (no id)" {
    const allocator = std.testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","method":"notify/something","params":[1,2,3]}
    ;

    var msg = try parseMessage(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(Message.notification, std.meta.activeTag(msg));
    try std.testing.expectEqualStrings("notify/something", msg.notification.method);
}

test "parse success response" {
    const allocator = std.testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":{"status":"ok"}}
    ;

    var msg = try parseMessage(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(Message.response, std.meta.activeTag(msg));
    try std.testing.expectEqual(1, msg.response.id.number);
}

test "parse error response" {
    const allocator = std.testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":"err-1","error":{"code":-32601,"message":"Method not found"}}
    ;

    var msg = try parseMessage(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(Message.error_response, std.meta.activeTag(msg));
    try std.testing.expectEqualStrings("err-1", msg.error_response.id.string);
    try std.testing.expectEqual(ErrorCode.method_not_found, msg.error_response.@"error".code);
    try std.testing.expectEqualStrings("Method not found", msg.error_response.@"error".message);
}

test "parse request with null id" {
    const allocator = std.testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":null,"method":"test"}
    ;

    var msg = try parseMessage(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(Message.request, std.meta.activeTag(msg));
    try std.testing.expectEqual(MessageId.null_id, std.meta.activeTag(msg.request.id));
}

test "parse invalid version" {
    const allocator = std.testing.allocator;

    const json =
        \\{"jsonrpc":"1.0","id":1,"method":"test"}
    ;

    try std.testing.expectError(error.InvalidRequest, parseMessage(allocator, json));
}

test "parse malformed JSON" {
    const allocator = std.testing.allocator;

    const json = "{invalid json";

    try std.testing.expectError(error.UnexpectedEndOfInput, parseMessage(allocator, json));
}
