const std = @import("std");
const position_mod = @import("position.zig");
const jsonrpc = @import("../jsonrpc/types.zig");
const writer = @import("../jsonrpc/writer.zig");
const document_mod = @import("document.zig");
const config_parser = @import("../config/parser.zig");

/// Completion item kinds (LSP specification)
pub const CompletionItemKind = enum(u8) {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
};

/// Completion item
pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionItemKind,
    detail: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    insertText: ?[]const u8 = null,

    pub fn toJson(self: *const CompletionItem, allocator: std.mem.Allocator) ![]const u8 {
        var json = std.ArrayList(u8){};
        defer json.deinit(allocator);

        try json.appendSlice(allocator, "{\"label\":\"");
        try json.appendSlice(allocator, self.label);
        try json.appendSlice(allocator, "\",\"kind\":");
        const kind_num = try std.fmt.allocPrint(allocator, "{d}", .{@intFromEnum(self.kind)});
        defer allocator.free(kind_num);
        try json.appendSlice(allocator, kind_num);

        if (self.detail) |detail| {
            try json.appendSlice(allocator, ",\"detail\":\"");
            try json.appendSlice(allocator, detail);
            try json.appendSlice(allocator, "\"");
        }

        if (self.documentation) |doc| {
            try json.appendSlice(allocator, ",\"documentation\":\"");
            try json.appendSlice(allocator, doc);
            try json.appendSlice(allocator, "\"");
        }

        if (self.insertText) |text| {
            try json.appendSlice(allocator, ",\"insertText\":\"");
            try json.appendSlice(allocator, text);
            try json.appendSlice(allocator, "\"");
        }

        try json.appendSlice(allocator, "}");
        return json.toOwnedSlice(allocator);
    }
};

/// Completion context
const CompletionContext = enum {
    TaskName, // Inside deps = [...], or workflow dependencies
    FieldName, // TOML field name in [tasks.*] section
    Expression, // Inside ${...} expression
    ToolName, // After toolchain = "..."
    MatrixValue, // Inside [matrix] section
    Unknown,
};

/// Handle textDocument/completion request
pub fn handleCompletion(
    allocator: std.mem.Allocator,
    request: *const jsonrpc.Request,
    params: []const u8,
    doc_store: *document_mod.DocumentStore,
) ![]const u8 {
    // Use arena allocator for all temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Extract textDocument and position objects from nested JSON structure
    // LSP spec: {"textDocument":{"uri":"..."},"position":{"line":...,"character":...}}
    const textDocument = extractJsonObject(params, "textDocument") orelse {
        return createEmptyCompletionResponse(allocator, request.id);
    };
    const position = extractJsonObject(params, "position") orelse {
        return createEmptyCompletionResponse(allocator, request.id);
    };

    // Extract URI from textDocument object
    var uri_buf: [512]u8 = undefined;
    const uri = extractJsonString(textDocument, "uri", &uri_buf) orelse {
        return createEmptyCompletionResponse(allocator, request.id);
    };

    // Extract line and character from position object
    const line = extractJsonNumber(position, "line") orelse return createEmptyCompletionResponse(allocator, request.id);
    const character = extractJsonNumber(position, "character") orelse return createEmptyCompletionResponse(allocator, request.id);

    const pos = position_mod.Position{
        .line = @intCast(line),
        .character = @intCast(character),
    };

    // Get document text
    const doc = doc_store.get(uri) orelse {
        return createEmptyCompletionResponse(allocator, request.id);
    };

    // Determine completion context
    const context = try determineContext(arena_alloc, doc.content, pos);

    // Generate completions based on context
    var items = std.ArrayList(CompletionItem){};
    defer items.deinit(arena_alloc);

    switch (context) {
        .TaskName => try addTaskNameCompletions(arena_alloc, doc.content, &items),
        .FieldName => try addFieldNameCompletions(arena_alloc, &items),
        .Expression => try addExpressionCompletions(arena_alloc, &items),
        .ToolName => try addToolNameCompletions(arena_alloc, &items),
        .MatrixValue => try addMatrixValueCompletions(arena_alloc, &items),
        .Unknown => {}, // No completions
    }

    // Build JSON response (using parent allocator for the final response)
    return try createCompletionResponse(allocator, request.id, items.items);
}

/// Determine completion context based on cursor position
fn determineContext(allocator: std.mem.Allocator, text: []const u8, pos: position_mod.Position) !CompletionContext {
    const offset = position_mod.positionToByteOffset(text, pos) orelse return .Unknown;

    // Find the current line
    var line_start = offset;
    while (line_start > 0 and text[line_start - 1] != '\n') : (line_start -= 1) {}
    var line_end = offset;
    while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
    const line_text = text[line_start..line_end];

    // Check for expression context (inside ${...})
    if (isInExpression(text, offset)) {
        return .Expression;
    }

    // Check for deps array context
    if (std.mem.indexOf(u8, line_text, "deps") != null and std.mem.indexOf(u8, line_text, "[") != null) {
        return .TaskName;
    }

    // Check for workflow dependency context
    if (std.mem.indexOf(u8, line_text, "depends_on") != null) {
        return .TaskName;
    }

    // Check for toolchain field
    if (std.mem.indexOf(u8, line_text, "toolchain") != null and std.mem.indexOf(u8, line_text, "=") != null) {
        return .ToolName;
    }

    // Check if we're in a [tasks.*] section
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const in_task_section = isInTaskSection(arena.allocator(), text, offset) catch false;

    if (in_task_section) {
        // Check if we're at the start of a line (field name completion)
        var i = offset;
        while (i > line_start and (text[i - 1] == ' ' or text[i - 1] == '\t')) : (i -= 1) {}
        if (i == line_start or text[i - 1] == '\n') {
            return .FieldName;
        }
    }

    // Check for [matrix] section
    if (isInMatrixSection(text, offset)) {
        return .MatrixValue;
    }

    return .Unknown;
}

/// Check if cursor is inside an expression ${...}
fn isInExpression(text: []const u8, offset: usize) bool {
    var depth: i32 = 0;
    var i: usize = 0;
    while (i < offset and i < text.len) : (i += 1) {
        if (i + 1 < text.len and text[i] == '$' and text[i + 1] == '{') {
            depth += 1;
            i += 1; // Skip '{'
        } else if (text[i] == '}' and depth > 0) {
            depth -= 1;
        }
    }
    return depth > 0;
}

/// Check if cursor is in a [tasks.*] section
fn isInTaskSection(allocator: std.mem.Allocator, text: []const u8, offset: usize) !bool {
    // Find the most recent section header before offset
    var i: usize = offset;
    while (i > 0) : (i -= 1) {
        if (text[i] == '[' and (i == 0 or text[i - 1] == '\n')) {
            // Found a section header
            var j = i + 1;
            while (j < text.len and text[j] != ']' and text[j] != '\n') : (j += 1) {}
            if (j < text.len and text[j] == ']') {
                const section_name = text[i + 1 .. j];
                if (std.mem.startsWith(u8, section_name, "tasks.")) {
                    return true;
                }
            }
            return false;
        }
    }
    _ = allocator;
    return false;
}

/// Check if cursor is in a [matrix] section
fn isInMatrixSection(text: []const u8, offset: usize) bool {
    var i: usize = offset;
    while (i > 0) : (i -= 1) {
        if (text[i] == '[' and (i == 0 or text[i - 1] == '\n')) {
            var j = i + 1;
            while (j < text.len and text[j] != ']' and text[j] != '\n') : (j += 1) {}
            if (j < text.len and text[j] == ']') {
                const section_name = text[i + 1 .. j];
                if (std.mem.eql(u8, section_name, "matrix")) {
                    return true;
                }
            }
            return false;
        }
    }
    return false;
}

/// Add task name completions by parsing existing tasks
fn addTaskNameCompletions(allocator: std.mem.Allocator, text: []const u8, items: *std.ArrayList(CompletionItem)) !void {
    // Parse TOML to find task names (using the arena allocator from caller)
    const parse_result = config_parser.parseToml(allocator, text) catch {
        // If parsing fails, fall back to regex-like extraction
        return;
    };

    // Extract task names from parsed config
    var iter = parse_result.tasks.iterator();
    while (iter.next()) |entry| {
        const task_name = entry.key_ptr.*;
        const task = entry.value_ptr.*;

        try items.append(allocator, .{
            .label = task_name,
            .kind = .Value,
            .detail = task.description,
            .documentation = task.cmd,
        });
    }
}

/// Add field name completions for [tasks.*] sections
fn addFieldNameCompletions(allocator: std.mem.Allocator, items: *std.ArrayList(CompletionItem)) !void {
    const fields = [_]struct { name: []const u8, doc: []const u8 }{
        .{ .name = "cmd", .doc = "Command to execute" },
        .{ .name = "description", .doc = "Task description" },
        .{ .name = "deps", .doc = "Task dependencies" },
        .{ .name = "env", .doc = "Environment variables" },
        .{ .name = "dir", .doc = "Working directory" },
        .{ .name = "timeout", .doc = "Execution timeout" },
        .{ .name = "retry", .doc = "Retry count on failure" },
        .{ .name = "condition", .doc = "Conditional execution" },
        .{ .name = "cache", .doc = "Output caching" },
        .{ .name = "toolchain", .doc = "Required toolchain" },
        .{ .name = "platform", .doc = "Platform constraint" },
        .{ .name = "arch", .doc = "Architecture constraint" },
        .{ .name = "tags", .doc = "Task tags" },
        .{ .name = "template", .doc = "Task template" },
        .{ .name = "params", .doc = "Template parameters" },
    };

    for (fields) |field| {
        try items.append(allocator, .{
            .label = field.name,
            .kind = .Field,
            .documentation = field.doc,
            .insertText = field.name,
        });
    }
}

/// Add expression keyword completions
fn addExpressionCompletions(allocator: std.mem.Allocator, items: *std.ArrayList(CompletionItem)) !void {
    const keywords = [_]struct { name: []const u8, doc: []const u8 }{
        .{ .name = "platform.os", .doc = "Current OS (linux, macos, windows)" },
        .{ .name = "platform.is_linux", .doc = "True if running on Linux" },
        .{ .name = "platform.is_macos", .doc = "True if running on macOS" },
        .{ .name = "platform.is_windows", .doc = "True if running on Windows" },
        .{ .name = "arch.name", .doc = "Current architecture (x86_64, aarch64)" },
        .{ .name = "arch.is_x86_64", .doc = "True if x86_64 architecture" },
        .{ .name = "arch.is_aarch64", .doc = "True if ARM64 architecture" },
        .{ .name = "file.exists", .doc = "Check if file exists" },
        .{ .name = "file.changed", .doc = "Check if file changed since last run" },
        .{ .name = "file.newer", .doc = "Compare file modification times" },
        .{ .name = "file.hash", .doc = "Get file content hash" },
        .{ .name = "env", .doc = "Get environment variable" },
        .{ .name = "shell", .doc = "Execute shell command and capture output" },
        .{ .name = "semver", .doc = "Semantic version comparison" },
        .{ .name = "task.status", .doc = "Get task status (success, failed)" },
        .{ .name = "task.output", .doc = "Get task stdout" },
    };

    for (keywords) |keyword| {
        try items.append(allocator, .{
            .label = keyword.name,
            .kind = .Keyword,
            .documentation = keyword.doc,
            .insertText = keyword.name,
        });
    }
}

/// Add toolchain name completions
fn addToolNameCompletions(allocator: std.mem.Allocator, items: *std.ArrayList(CompletionItem)) !void {
    const tools = [_]struct { name: []const u8, doc: []const u8 }{
        .{ .name = "node", .doc = "Node.js runtime" },
        .{ .name = "python", .doc = "Python interpreter" },
        .{ .name = "zig", .doc = "Zig compiler" },
        .{ .name = "go", .doc = "Go compiler" },
        .{ .name = "rust", .doc = "Rust compiler" },
        .{ .name = "deno", .doc = "Deno runtime" },
        .{ .name = "bun", .doc = "Bun runtime" },
        .{ .name = "java", .doc = "Java Development Kit" },
    };

    for (tools) |tool| {
        try items.append(allocator, .{
            .label = tool.name,
            .kind = .Value,
            .documentation = tool.doc,
            .insertText = tool.name,
        });
    }
}

/// Add matrix value completions
fn addMatrixValueCompletions(allocator: std.mem.Allocator, items: *std.ArrayList(CompletionItem)) !void {
    // Common matrix dimensions
    const dimensions = [_][]const u8{ "os", "arch", "version", "env" };

    for (dimensions) |dim| {
        try items.append(allocator, .{
            .label = dim,
            .kind = .Field,
            .documentation = "Matrix dimension",
        });
    }
}

/// Create completion response
fn createCompletionResponse(allocator: std.mem.Allocator, request_id: jsonrpc.MessageId, items: []const CompletionItem) ![]const u8 {
    var json = std.ArrayList(u8){};
    defer json.deinit(allocator);

    try json.appendSlice(allocator, "[");
    for (items, 0..) |*item, i| {
        if (i > 0) try json.appendSlice(allocator, ",");
        const item_json = try item.toJson(allocator);
        defer allocator.free(item_json);
        try json.appendSlice(allocator, item_json);
    }
    try json.appendSlice(allocator, "]");

    const result = try json.toOwnedSlice(allocator);
    defer allocator.free(result);

    var response = try writer.createResponse(allocator, request_id, result);
    defer response.deinit(allocator);

    return writer.serializeMessage(allocator, .{ .response = response });
}

/// Create empty completion response
fn createEmptyCompletionResponse(allocator: std.mem.Allocator, request_id: jsonrpc.MessageId) ![]const u8 {
    var response = try writer.createResponse(allocator, request_id, "[]");
    defer response.deinit(allocator);
    return writer.serializeMessage(allocator, .{ .response = response });
}

/// Extract nested JSON object
fn extractJsonObject(json: []const u8, key: []const u8) ?[]const u8 {
    // Find key pattern: "key":{...}
    const pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":{{", .{key}) catch return null;
    defer std.heap.page_allocator.free(pattern);

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const obj_start = start_idx + pattern.len - 1; // Include the opening brace

    // Find matching closing brace
    var depth: i32 = 0;
    var i = obj_start;
    while (i < json.len) : (i += 1) {
        if (json[i] == '{') depth += 1;
        if (json[i] == '}') {
            depth -= 1;
            if (depth == 0) {
                return json[obj_start..i + 1];
            }
        }
    }

    return null;
}

/// Extract string from JSON (simplified)
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

test "determineContext - expression" {
    const text = "cmd = \"echo ${platform.os}\"";
    const pos = position_mod.Position{ .line = 0, .character = 15 }; // Inside ${...}
    const context = try determineContext(std.testing.allocator, text, pos);
    try std.testing.expectEqual(CompletionContext.Expression, context);
}

test "determineContext - deps" {
    const text = "deps = [\"build\", \"\"]";
    const pos = position_mod.Position{ .line = 0, .character = 18 }; // Inside array
    const context = try determineContext(std.testing.allocator, text, pos);
    try std.testing.expectEqual(CompletionContext.TaskName, context);
}

test "isInExpression" {
    try std.testing.expect(isInExpression("${platform.os}", 5));
    try std.testing.expect(!isInExpression("${platform.os}", 0));
    try std.testing.expect(!isInExpression("platform.os", 5));
}
