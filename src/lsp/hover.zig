const std = @import("std");
const position_mod = @import("position.zig");
const jsonrpc = @import("../jsonrpc/types.zig");
const writer = @import("../jsonrpc/writer.zig");
const document_mod = @import("document.zig");
const config_parser = @import("../config/parser.zig");

/// Handle textDocument/hover request
pub fn handleHover(
    allocator: std.mem.Allocator,
    request: *const jsonrpc.Request,
    params: []const u8,
    doc_store: *document_mod.DocumentStore,
) ![]const u8 {
    // Extract URI and position from params
    var uri_buf: [512]u8 = undefined;
    const uri = extractJsonString(params, "uri", &uri_buf) orelse {
        return createEmptyHoverResponse(allocator, request.id);
    };

    const line = extractJsonNumber(params, "line") orelse return createEmptyHoverResponse(allocator, request.id);
    const character = extractJsonNumber(params, "character") orelse return createEmptyHoverResponse(allocator, request.id);

    const pos = position_mod.Position{
        .line = @intCast(line),
        .character = @intCast(character),
    };

    // Get document text
    const doc = doc_store.get(uri) orelse {
        return createEmptyHoverResponse(allocator, request.id);
    };

    // Find hover information at the position
    const hover_content = try findHoverContent(allocator, doc.content, pos);
    defer if (hover_content) |content| allocator.free(content);

    if (hover_content) |content| {
        return try createHoverResponse(allocator, request.id, content);
    } else {
        return createEmptyHoverResponse(allocator, request.id);
    }
}

/// Find hover content at the given position
fn findHoverContent(allocator: std.mem.Allocator, text: []const u8, pos: position_mod.Position) !?[]const u8 {
    const offset = position_mod.positionToByteOffset(text, pos) orelse return null;

    // Find the current line
    var line_start = offset;
    while (line_start > 0 and text[line_start - 1] != '\n') : (line_start -= 1) {}
    var line_end = offset;
    while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
    const line_text = text[line_start..line_end];

    // Check if hovering over a field name
    if (std.mem.indexOf(u8, line_text, "=")) |eq_idx| {
        const field_end = eq_idx;
        var field_start: usize = 0;
        var i = eq_idx;
        while (i > 0) : (i -= 1) {
            if (line_text[i - 1] == ' ' or line_text[i - 1] == '\t' or i == 1) {
                field_start = if (i == 1) 0 else i;
                break;
            }
        }
        const field_name = std.mem.trim(u8, line_text[field_start..field_end], " \t");

        // Check if cursor is over the field name
        const cursor_in_line = offset - line_start;
        if (cursor_in_line >= field_start and cursor_in_line < field_end) {
            return try getFieldDocumentation(allocator, field_name);
        }
    }

    // Check if hovering over a task name in deps array
    if (std.mem.indexOf(u8, line_text, "deps")) |_| {
        const task_name = extractTaskNameAtPosition(line_text, offset - line_start);
        if (task_name) |name| {
            return try getTaskDocumentation(allocator, text, name);
        }
    }

    // Check if hovering over an expression keyword
    if (isInExpression(text, offset)) {
        const keyword = extractKeywordAtPosition(text, offset);
        if (keyword) |kw| {
            return try getExpressionDocumentation(allocator, kw);
        }
    }

    return null;
}

/// Check if cursor is inside an expression ${...}
fn isInExpression(text: []const u8, offset: usize) bool {
    var depth: i32 = 0;
    var i: usize = 0;
    while (i < offset and i < text.len) : (i += 1) {
        if (i + 1 < text.len and text[i] == '$' and text[i + 1] == '{') {
            depth += 1;
            i += 1;
        } else if (text[i] == '}' and depth > 0) {
            depth -= 1;
        }
    }
    return depth > 0;
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

/// Extract keyword at the given position
fn extractKeywordAtPosition(text: []const u8, offset: usize) ?[]const u8 {
    // Find the start and end of the word at offset
    var start = offset;
    while (start > 0 and isWordChar(text[start - 1])) : (start -= 1) {}

    var end = offset;
    while (end < text.len and isWordChar(text[end])) : (end += 1) {}

    if (end > start) {
        return text[start..end];
    }

    return null;
}

/// Check if character is part of a word (identifier)
fn isWordChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or ch == '.';
}

/// Get documentation for a field name
fn getFieldDocumentation(allocator: std.mem.Allocator, field_name: []const u8) !?[]const u8 {
    const docs = std.StaticStringMap([]const u8).initComptime(.{
        .{ "cmd", "Command to execute. Supports shell syntax and environment variable expansion." },
        .{ "description", "Human-readable description of the task." },
        .{ "deps", "Parallel dependencies: all tasks in this array run concurrently before this task." },
        .{ "deps_serial", "Sequential dependencies: run in array order before this task, one at a time." },
        .{ "env", "Environment variable overrides in key = \"value\" format." },
        .{ "dir", "Working directory for command execution. Defaults to project root." },
        .{ "timeout", "Execution timeout (e.g., \"30s\", \"5m\"). null means no timeout." },
        .{ "retry", "Maximum number of retry attempts after the first failure (0 = no retry)." },
        .{ "retry_delay", "Delay between retry attempts (e.g., \"1s\", \"500ms\")." },
        .{ "retry_backoff", "If true, delay doubles on each retry attempt (exponential backoff)." },
        .{ "allow_failure", "If true, a non-zero exit code is treated as success for dependency purposes." },
        .{ "condition", "Conditional execution expression. Task only runs if condition evaluates to true." },
        .{ "cache", "Output caching configuration. Enables incremental builds." },
        .{ "toolchain", "Required toolchain (e.g., \"node@20.0.0\", \"python@3.11\")." },
        .{ "platform", "Platform constraint (e.g., \"linux\", \"macos\", \"windows\")." },
        .{ "arch", "Architecture constraint (e.g., \"x86_64\", \"aarch64\")." },
        .{ "tags", "Task tags for filtering (e.g., [\"test\", \"ci\"])." },
        .{ "template", "Task template name to inherit from." },
        .{ "params", "Template parameters for substitution." },
    });

    if (docs.get(field_name)) |doc| {
        return try allocator.dupe(u8, doc);
    }

    return null;
}

/// Get documentation for a task by name
fn getTaskDocumentation(allocator: std.mem.Allocator, text: []const u8, task_name: []const u8) !?[]const u8 {
    // Parse TOML to find the task
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const parse_result = config_parser.parseToml(arena.allocator(), text) catch {
        return null;
    };

    if (parse_result.tasks.get(task_name)) |task| {
        var doc = std.ArrayList(u8){};
        defer doc.deinit(allocator);

        try doc.appendSlice(allocator, "**Task: ");
        try doc.appendSlice(allocator, task_name);
        try doc.appendSlice(allocator, "**\n\n");

        if (task.description) |desc| {
            try doc.appendSlice(allocator, desc);
            try doc.appendSlice(allocator, "\n\n");
        }

        try doc.appendSlice(allocator, "Command: `");
        try doc.appendSlice(allocator, task.cmd);
        try doc.appendSlice(allocator, "`\n\n");

        if (task.deps.len > 0) {
            try doc.appendSlice(allocator, "Dependencies: ");
            for (task.deps, 0..) |dep, i| {
                if (i > 0) try doc.appendSlice(allocator, ", ");
                try doc.appendSlice(allocator, dep);
            }
            try doc.appendSlice(allocator, "\n");
        }

        const owned = try doc.toOwnedSlice(allocator);
        return owned;
    }

    return null;
}

/// Get documentation for an expression keyword
fn getExpressionDocumentation(allocator: std.mem.Allocator, keyword: []const u8) !?[]const u8 {
    const docs = std.StaticStringMap([]const u8).initComptime(.{
        .{ "platform.os", "Current operating system: \"linux\", \"macos\", or \"windows\"" },
        .{ "platform.is_linux", "Boolean: true if running on Linux" },
        .{ "platform.is_macos", "Boolean: true if running on macOS" },
        .{ "platform.is_windows", "Boolean: true if running on Windows" },
        .{ "arch.name", "Current architecture: \"x86_64\" or \"aarch64\"" },
        .{ "arch.is_x86_64", "Boolean: true if x86_64 architecture" },
        .{ "arch.is_aarch64", "Boolean: true if ARM64 architecture" },
        .{ "file.exists", "Function: file.exists(\"path\") - Check if file exists" },
        .{ "file.changed", "Function: file.changed(\"path\") - Check if file changed since last run" },
        .{ "file.newer", "Function: file.newer(\"path1\", \"path2\") - Compare file modification times" },
        .{ "file.hash", "Function: file.hash(\"path\") - Get file content hash (SHA-256)" },
        .{ "env", "Function: env(\"VAR_NAME\") - Get environment variable value" },
        .{ "shell", "Function: shell(\"command\") - Execute shell command and capture output" },
        .{ "semver", "Function: semver(\"1.0.0\", \">=\", \"0.9.0\") - Semantic version comparison" },
        .{ "task.status", "Function: task.status(\"task_name\") - Get task status (\"success\", \"failed\", \"pending\")" },
        .{ "task.output", "Function: task.output(\"task_name\") - Get task stdout" },
    });

    if (docs.get(keyword)) |doc| {
        return try allocator.dupe(u8, doc);
    }

    return null;
}

/// Create hover response with content
fn createHoverResponse(allocator: std.mem.Allocator, request_id: jsonrpc.MessageId, content: []const u8) ![]const u8 {
    // Escape content for JSON
    var escaped = std.ArrayList(u8){};
    defer escaped.deinit(allocator);

    for (content) |ch| {
        if (ch == '"') {
            try escaped.appendSlice(allocator, "\\\"");
        } else if (ch == '\\') {
            try escaped.appendSlice(allocator, "\\\\");
        } else if (ch == '\n') {
            try escaped.appendSlice(allocator, "\\n");
        } else if (ch == '\r') {
            try escaped.appendSlice(allocator, "\\r");
        } else if (ch == '\t') {
            try escaped.appendSlice(allocator, "\\t");
        } else {
            try escaped.append(allocator, ch);
        }
    }

    const result = try std.fmt.allocPrint(allocator,
        \\{{"contents":{{"kind":"markdown","value":"{s}"}}}}
    , .{escaped.items});
    defer allocator.free(result);

    var response = try writer.createResponse(allocator, request_id, result);
    defer response.deinit(allocator);

    return writer.serializeMessage(allocator, .{ .response = response });
}

/// Create empty hover response (no hover information)
fn createEmptyHoverResponse(allocator: std.mem.Allocator, request_id: jsonrpc.MessageId) ![]const u8 {
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

test "isInExpression" {
    try std.testing.expect(isInExpression("cmd = \"${platform.os}\"", 12));
    try std.testing.expect(!isInExpression("cmd = \"platform.os\"", 12));
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

test "isWordChar" {
    try std.testing.expect(isWordChar('a'));
    try std.testing.expect(isWordChar('Z'));
    try std.testing.expect(isWordChar('0'));
    try std.testing.expect(isWordChar('_'));
    try std.testing.expect(isWordChar('.'));
    try std.testing.expect(!isWordChar(' '));
    try std.testing.expect(!isWordChar('"'));
}
