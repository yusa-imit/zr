// src/jsonrpc/types.zig
//
// JSON-RPC 2.0 type definitions shared by MCP and LSP servers
// Phase 9B — Foundation for AI integration (MCP) and editor integration (LSP)

const std = @import("std");

/// JSON-RPC 2.0 version string
pub const JSONRPC_VERSION = "2.0";

/// JSON-RPC message ID (can be string, number, or null)
pub const MessageId = union(enum) {
    string: []const u8,
    number: i64,
    null_id: void,

    pub fn deinit(self: MessageId, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |s| allocator.free(s),
            .number, .null_id => {},
        }
    }

    pub fn clone(self: MessageId, allocator: std.mem.Allocator) !MessageId {
        return switch (self) {
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .number => |n| .{ .number = n },
            .null_id => .null_id,
        };
    }
};

/// JSON-RPC error codes (standard + custom)
pub const ErrorCode = enum(i32) {
    // JSON-RPC standard errors
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,

    // LSP/MCP specific errors (-32000 to -32099 reserved for implementation)
    server_not_initialized = -32002,
    unknown_error = -32001,

    pub fn message(self: ErrorCode) []const u8 {
        return switch (self) {
            .parse_error => "Parse error",
            .invalid_request => "Invalid Request",
            .method_not_found => "Method not found",
            .invalid_params => "Invalid params",
            .internal_error => "Internal error",
            .server_not_initialized => "Server not initialized",
            .unknown_error => "Unknown error",
        };
    }
};

/// JSON-RPC error object
pub const ErrorObject = struct {
    code: ErrorCode,
    message: []const u8,
    data: ?[]const u8 = null, // Raw JSON string

    pub fn deinit(self: *ErrorObject, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.data) |d| {
            allocator.free(d);
        }
    }
};

/// JSON-RPC request message
pub const Request = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    id: MessageId,
    method: []const u8,
    params: ?[]const u8 = null, // Raw JSON string

    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        allocator.free(self.jsonrpc);
        self.id.deinit(allocator);
        allocator.free(self.method);
        if (self.params) |p| {
            allocator.free(p);
        }
    }
};

/// JSON-RPC notification (request without id)
pub const Notification = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    method: []const u8,
    params: ?[]const u8 = null, // Raw JSON string

    pub fn deinit(self: *Notification, allocator: std.mem.Allocator) void {
        allocator.free(self.jsonrpc);
        allocator.free(self.method);
        if (self.params) |p| {
            allocator.free(p);
        }
    }
};

/// JSON-RPC response message (success)
pub const Response = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    id: MessageId,
    result: []const u8, // Raw JSON string

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.jsonrpc);
        self.id.deinit(allocator);
        allocator.free(self.result);
    }
};

/// JSON-RPC error response
pub const ErrorResponse = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    id: MessageId,
    @"error": ErrorObject,

    pub fn deinit(self: *ErrorResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.jsonrpc);
        self.id.deinit(allocator);
        self.@"error".deinit(allocator);
    }
};

/// Any JSON-RPC message (request, notification, response, or error)
pub const Message = union(enum) {
    request: Request,
    notification: Notification,
    response: Response,
    error_response: ErrorResponse,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .request => |*r| r.deinit(allocator),
            .notification => |*n| n.deinit(allocator),
            .response => |*resp| resp.deinit(allocator),
            .error_response => |*e| e.deinit(allocator),
        }
    }
};

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "MessageId: string clone and deinit" {
    const allocator = std.testing.allocator;

    const id = MessageId{ .string = try allocator.dupe(u8, "test-id") };
    defer id.deinit(allocator);

    const cloned = try id.clone(allocator);
    defer cloned.deinit(allocator);

    try std.testing.expectEqualStrings("test-id", cloned.string);
}

test "MessageId: number clone" {
    const allocator = std.testing.allocator;

    const id = MessageId{ .number = 42 };
    const cloned = try id.clone(allocator);

    try std.testing.expectEqual(42, cloned.number);
}

test "ErrorCode: messages" {
    try std.testing.expectEqualStrings("Parse error", ErrorCode.parse_error.message());
    try std.testing.expectEqualStrings("Method not found", ErrorCode.method_not_found.message());
}

test "ErrorObject: init and deinit" {
    const allocator = std.testing.allocator;

    var err = ErrorObject{
        .code = .internal_error,
        .message = try allocator.dupe(u8, "Something went wrong"),
        .data = null,
    };
    defer err.deinit(allocator);

    try std.testing.expectEqual(ErrorCode.internal_error, err.code);
    try std.testing.expectEqualStrings("Something went wrong", err.message);
}
