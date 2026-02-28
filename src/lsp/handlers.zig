const std = @import("std");
const jsonrpc = @import("../jsonrpc/types.zig");
const writer = @import("../jsonrpc/writer.zig");
const document_mod = @import("document.zig");
const diagnostics_mod = @import("diagnostics.zig");
const completion_mod = @import("completion.zig");
const config_parser = @import("../config/parser.zig");

/// LSP server capabilities
pub const ServerCapabilities = struct {
    textDocumentSync: i32 = 1, // Full sync
    diagnosticProvider: bool = true,
    completionProvider: bool = true,
    hoverProvider: bool = true,
    definitionProvider: bool = true,

    pub fn toJson(allocator: std.mem.Allocator) ![]const u8 {
        // Return static JSON string (duplicated for consistent memory management)
        const json_str = "{\"textDocumentSync\":1,\"diagnosticProvider\":true,\"completionProvider\":{\"triggerCharacters\":[\"\\\"\",\"$\",\".\",\"{\"]},\"hoverProvider\":true,\"definitionProvider\":true}";
        return allocator.dupe(u8, json_str);
    }
};

/// Handle initialize request
pub fn handleInitialize(
    allocator: std.mem.Allocator,
    request: *const jsonrpc.Request,
) ![]const u8 {
    const capabilities = try ServerCapabilities.toJson(allocator);
    defer allocator.free(capabilities);

    const result = try std.fmt.allocPrint(allocator,
        \\{{"capabilities":{s}}}
    , .{capabilities});
    defer allocator.free(result);

    var response = try writer.createResponse(allocator, request.id, result);
    defer response.deinit(allocator);

    return writer.serializeMessage(allocator, .{ .response = response });
}

/// Handle initialized notification (no response)
pub fn handleInitialized() !void {
    // Initialized notification received, server is ready
}

/// Handle shutdown request
pub fn handleShutdown(
    allocator: std.mem.Allocator,
    request: *const jsonrpc.Request,
) ![]const u8 {
    var response = try writer.createResponse(allocator, request.id, "null");
    defer response.deinit(allocator);

    return writer.serializeMessage(allocator, .{ .response = response });
}

/// Handle textDocument/didOpen notification
pub fn handleDidOpen(
    allocator: std.mem.Allocator,
    params: []const u8,
    doc_store: *document_mod.DocumentStore,
) !?[]const u8 {
    // Parse params to extract URI, text, version
    // Simplified JSON parsing - in production, use proper JSON parser
    var uri_buf: [512]u8 = undefined;
    var text_buf: [65536]u8 = undefined;

    const uri = extractJsonString(params, "uri", &uri_buf) orelse return null;
    const text = extractJsonString(params, "text", &text_buf) orelse "";
    const version = extractJsonNumber(params, "version") orelse 1;

    // Open document in store
    try doc_store.open(uri, text, @intCast(version));

    // Generate diagnostics for the document
    return try generateDiagnostics(allocator, uri, text);
}

/// Handle textDocument/didChange notification
pub fn handleDidChange(
    allocator: std.mem.Allocator,
    params: []const u8,
    doc_store: *document_mod.DocumentStore,
) !?[]const u8 {
    var uri_buf: [512]u8 = undefined;
    var text_buf: [65536]u8 = undefined;

    const uri = extractJsonString(params, "uri", &uri_buf) orelse return null;
    const version = extractJsonNumber(params, "version") orelse 1;

    // Extract new text from contentChanges array
    const text = extractContentChanges(params, &text_buf) orelse "";

    // Update document in store
    try doc_store.change(uri, text, @intCast(version));

    // Generate diagnostics for the updated document
    return try generateDiagnostics(allocator, uri, text);
}

/// Handle textDocument/didClose notification
pub fn handleDidClose(
    params: []const u8,
    doc_store: *document_mod.DocumentStore,
) !void {
    var uri_buf: [512]u8 = undefined;
    const uri = extractJsonString(params, "uri", &uri_buf) orelse return;

    doc_store.close(uri);
}

/// Generate diagnostics for a document
fn generateDiagnostics(
    allocator: std.mem.Allocator,
    uri: []const u8,
    text: []const u8,
) ![]const u8 {
    var diagnostics = std.ArrayList(diagnostics_mod.Diagnostic){};
    defer {
        for (diagnostics.items) |*diag| {
            diag.deinit();
        }
        diagnostics.deinit(allocator);
    }

    // Try parsing the TOML to find errors
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Attempt to parse TOML
    const parse_result = config_parser.parseToml(arena_alloc, text);

    if (parse_result) |_| {
        // Success - no diagnostics
    } else |err| {
        // Parse error - create diagnostic
        const diag = try diagnostics_mod.fromTomlError(allocator, text, err, null);
        try diagnostics.append(allocator, diag);
    }

    // Build publishDiagnostics notification
    var diag_json = std.ArrayList(u8){};
    defer diag_json.deinit(allocator);

    try diag_json.appendSlice(allocator, "[");
    for (diagnostics.items, 0..) |diag, i| {
        if (i > 0) try diag_json.appendSlice(allocator, ",");
        const json = try diag.toJson(allocator);
        defer allocator.free(json);
        try diag_json.appendSlice(allocator, json);
    }
    try diag_json.appendSlice(allocator, "]");

    return std.fmt.allocPrint(allocator,
        \\{{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{{"uri":"{s}","diagnostics":{s}}}}}
    , .{ uri, diag_json.items });
}

/// Extract string value from JSON (simplified parser)
fn extractJsonString(json: []const u8, key: []const u8, buffer: []u8) ?[]const u8 {
    // Find key pattern: "key":"value"
    const pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{key}) catch return null;
    defer std.heap.page_allocator.free(pattern);

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    // Find closing quote
    var i = value_start;
    var buf_idx: usize = 0;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (buf_idx >= buffer.len) return null;
        // Handle escaped quotes
        if (json[i] == '\\' and i + 1 < json.len and json[i + 1] == '"') {
            buffer[buf_idx] = '"';
            buf_idx += 1;
            i += 1;
        } else if (json[i] == '\\' and i + 1 < json.len and json[i + 1] == 'n') {
            buffer[buf_idx] = '\n';
            buf_idx += 1;
            i += 1;
        } else {
            buffer[buf_idx] = json[i];
            buf_idx += 1;
        }
    }

    return buffer[0..buf_idx];
}

/// Extract number value from JSON
fn extractJsonNumber(json: []const u8, key: []const u8) ?i64 {
    const pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{key}) catch return null;
    defer std.heap.page_allocator.free(pattern);

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    // Skip whitespace
    var i = value_start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t')) : (i += 1) {}

    // Parse number
    var num: i64 = 0;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {
        num = num * 10 + (json[i] - '0');
    }

    return num;
}

/// Extract text from contentChanges array
fn extractContentChanges(json: []const u8, buffer: []u8) ?[]const u8 {
    // Find "contentChanges":[{"text":"..."}]
    const changes_start = std.mem.indexOf(u8, json, "\"contentChanges\":[") orelse return null;
    const text_start_pattern = "\"text\":\"";
    const text_start = std.mem.indexOf(u8, json[changes_start..], text_start_pattern) orelse return null;
    const value_start = changes_start + text_start + text_start_pattern.len;

    var i = value_start;
    var buf_idx: usize = 0;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (buf_idx >= buffer.len) return null;
        // Handle escaped characters
        if (json[i] == '\\' and i + 1 < json.len) {
            if (json[i + 1] == '"') {
                buffer[buf_idx] = '"';
                buf_idx += 1;
                i += 1;
            } else if (json[i + 1] == 'n') {
                buffer[buf_idx] = '\n';
                buf_idx += 1;
                i += 1;
            } else if (json[i + 1] == '\\') {
                buffer[buf_idx] = '\\';
                buf_idx += 1;
                i += 1;
            } else {
                buffer[buf_idx] = json[i];
                buf_idx += 1;
            }
        } else {
            buffer[buf_idx] = json[i];
            buf_idx += 1;
        }
    }

    return buffer[0..buf_idx];
}

test "extractJsonString" {
    var buffer: [256]u8 = undefined;
    const json = "{\"uri\":\"file:///test.toml\",\"version\":1}";

    const result = extractJsonString(json, "uri", &buffer);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("file:///test.toml", result.?);
}

test "extractJsonNumber" {
    const json = "{\"uri\":\"test\",\"version\":42}";
    const result = extractJsonNumber(json, "version");
    try std.testing.expectEqual(@as(i64, 42), result.?);
}
