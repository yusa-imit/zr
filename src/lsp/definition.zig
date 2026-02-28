const std = @import("std");
const position_mod = @import("position.zig");
const jsonrpc = @import("../jsonrpc/types.zig");
const writer = @import("../jsonrpc/writer.zig");
const document_mod = @import("document.zig");
const config_parser = @import("../config/parser.zig");

/// Location represents a location in a document
pub const Location = struct {
    uri: []const u8,
    range: position_mod.Range,

    pub fn toJson(self: *const Location, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator,
            \\{{"uri":"{s}","range":{{"start":{{"line":{d},"character":{d}}},"end":{{"line":{d},"character":{d}}}}}}}
        , .{
            self.uri,
            self.range.start.line,
            self.range.start.character,
            self.range.end.line,
            self.range.end.character,
        });
    }
};

/// Handle textDocument/definition request
pub fn handleDefinition(
    allocator: std.mem.Allocator,
    request: *const jsonrpc.Request,
    params: []const u8,
    doc_store: *document_mod.DocumentStore,
) ![]const u8 {
    // Extract URI and position from params
    var uri_buf: [512]u8 = undefined;
    const uri = extractJsonString(params, "uri", &uri_buf) orelse {
        return createEmptyDefinitionResponse(allocator, request.id);
    };

    const line = extractJsonNumber(params, "line") orelse return createEmptyDefinitionResponse(allocator, request.id);
    const character = extractJsonNumber(params, "character") orelse return createEmptyDefinitionResponse(allocator, request.id);

    const pos = position_mod.Position{
        .line = @intCast(line),
        .character = @intCast(character),
    };

    // Get document text
    const doc = doc_store.get(uri) orelse {
        return createEmptyDefinitionResponse(allocator, request.id);
    };

    // Find definition at the position
    const location = try findDefinition(allocator, doc.content, uri, pos);
    defer if (location) |loc| allocator.free(loc.uri);

    if (location) |loc| {
        return try createDefinitionResponse(allocator, request.id, &loc);
    } else {
        return createEmptyDefinitionResponse(allocator, request.id);
    }
}

/// Find definition at the given position
fn findDefinition(
    allocator: std.mem.Allocator,
    text: []const u8,
    uri: []const u8,
    pos: position_mod.Position,
) !?Location {
    const offset = position_mod.positionToByteOffset(text, pos) orelse return null;

    // Find the current line
    var line_start = offset;
    while (line_start > 0 and text[line_start - 1] != '\n') : (line_start -= 1) {}
    var line_end = offset;
    while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
    const line_text = text[line_start..line_end];

    // Check if we're hovering over a task name in deps array
    if (std.mem.indexOf(u8, line_text, "deps")) |_| {
        const task_name = extractTaskNameAtPosition(line_text, offset - line_start);
        if (task_name) |name| {
            return try findTaskDefinition(allocator, text, uri, name);
        }
    }

    // Check if we're hovering over a task name in workflow dependencies
    if (std.mem.indexOf(u8, line_text, "depends_on")) |_| {
        const task_name = extractTaskNameAtPosition(line_text, offset - line_start);
        if (task_name) |name| {
            return try findTaskDefinition(allocator, text, uri, name);
        }
    }

    return null;
}

/// Extract task name at the given position within a line
fn extractTaskNameAtPosition(line: []const u8, cursor: usize) ?[]const u8 {
    // Find if we're inside quotes
    var in_quotes = false;
    var quote_start: usize = 0;
    var quote_end: usize = 0;

    for (line, 0..) |ch, i| {
        if (ch == '"') {
            if (!in_quotes) {
                in_quotes = true;
                quote_start = i + 1;
            } else {
                quote_end = i;
                // Check if cursor is within this quoted string
                if (cursor >= quote_start and cursor <= quote_end) {
                    return line[quote_start..quote_end];
                }
                in_quotes = false;
            }
        }
    }

    return null;
}

/// Find the definition location of a task
fn findTaskDefinition(
    allocator: std.mem.Allocator,
    text: []const u8,
    uri: []const u8,
    task_name: []const u8,
) !?Location {
    // Search for [tasks.<task_name>] section header
    const pattern = try std.fmt.allocPrint(allocator, "[tasks.{s}]", .{task_name});
    defer allocator.free(pattern);

    const start_offset = std.mem.indexOf(u8, text, pattern) orelse return null;

    // Calculate position of the section header
    const start_pos = position_mod.byteOffsetToPosition(text, start_offset);
    const end_pos = position_mod.byteOffsetToPosition(text, start_offset + pattern.len);

    return Location{
        .uri = try allocator.dupe(u8, uri),
        .range = .{
            .start = start_pos,
            .end = end_pos,
        },
    };
}

/// Create definition response with location
fn createDefinitionResponse(
    allocator: std.mem.Allocator,
    request_id: jsonrpc.MessageId,
    location: *const Location,
) ![]const u8 {
    const location_json = try location.toJson(allocator);
    defer allocator.free(location_json);

    var response = try writer.createResponse(allocator, request_id, location_json);
    defer response.deinit(allocator);

    return writer.serializeMessage(allocator, .{ .response = response });
}

/// Create empty definition response (no definition found)
fn createEmptyDefinitionResponse(allocator: std.mem.Allocator, request_id: jsonrpc.MessageId) ![]const u8 {
    var response = try writer.createResponse(allocator, request_id, "null");
    defer response.deinit(allocator);
    return writer.serializeMessage(allocator, .{ .response = response });
}

/// Extract string from JSON
fn extractJsonString(json: []const u8, key: []const u8, buffer: []u8) ?[]const u8 {
    const pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{key}) catch return null;
    defer std.heap.page_allocator.free(pattern);

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    var i = value_start;
    var buf_idx: usize = 0;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (buf_idx >= buffer.len) return null;
        if (json[i] == '\\' and i + 1 < json.len and json[i + 1] == '"') {
            buffer[buf_idx] = '"';
            buf_idx += 1;
            i += 1;
        } else {
            buffer[buf_idx] = json[i];
            buf_idx += 1;
        }
    }

    return buffer[0..buf_idx];
}

/// Extract number from JSON
fn extractJsonNumber(json: []const u8, key: []const u8) ?i64 {
    const pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{key}) catch return null;
    defer std.heap.page_allocator.free(pattern);

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    var i = value_start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t')) : (i += 1) {}

    var num: i64 = 0;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') : (i += 1) {
        num = num * 10 + (json[i] - '0');
    }

    return num;
}

test "extractTaskNameAtPosition" {
    const line = "deps = [\"build\", \"test\"]";
    const name1 = extractTaskNameAtPosition(line, 10);
    try std.testing.expect(name1 != null);
    try std.testing.expectEqualStrings("build", name1.?);

    const name2 = extractTaskNameAtPosition(line, 19);
    try std.testing.expect(name2 != null);
    try std.testing.expectEqualStrings("test", name2.?);
}

test "findTaskDefinition - pattern creation" {
    const allocator = std.testing.allocator;
    const text = "[tasks.build]\ncmd = \"make\"\n[tasks.test]\ncmd = \"make test\"";

    const loc = try findTaskDefinition(allocator, text, "file:///test.toml", "build");
    try std.testing.expect(loc != null);
    defer if (loc) |l| allocator.free(l.uri);

    try std.testing.expectEqual(@as(u32, 0), loc.?.range.start.line);
}
