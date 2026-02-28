// src/mcp/handlers.zig
//
// MCP tool handlers - maps MCP tool calls to existing CLI functions
// Real implementations for list_tasks and show_task; others are stubs

const std = @import("std");
const list = @import("../cli/list.zig");
const show = @import("../cli/show.zig");

/// Tool handler result
pub const ToolResult = struct {
    /// JSON string result (owned by caller)
    json: []const u8,
    /// Exit code
    exit_code: u8,

    pub fn deinit(self: *ToolResult, allocator: std.mem.Allocator) void {
        allocator.free(self.json);
    }
};

/// Handle MCP tool call
pub fn handleTool(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    params_json: ?[]const u8,
) !ToolResult {
    if (std.mem.eql(u8, tool_name, "run_task")) {
        return try handleRunTask(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "list_tasks")) {
        return try handleListTasks(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "show_task")) {
        return try handleShowTask(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "validate_config")) {
        return try handleValidateConfig(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "show_graph")) {
        return try handleShowGraph(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "run_workflow")) {
        return try handleRunWorkflow(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "task_history")) {
        return try handleTaskHistory(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "estimate_duration")) {
        return try handleEstimateDuration(allocator, params_json orelse "{}");
    } else if (std.mem.eql(u8, tool_name, "generate_config")) {
        return try handleGenerateConfig(allocator, params_json orelse "{}");
    }

    return error.MethodNotFound;
}

/// Parse JSON string field from params
fn parseStringParam(params_json: []const u8, field_name: []const u8, default_value: []const u8) []const u8 {
    const search = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{field_name}) catch return default_value;
    defer std.heap.page_allocator.free(search);

    if (std.mem.indexOf(u8, params_json, search)) |start_idx| {
        const value_start = start_idx + search.len;
        if (value_start >= params_json.len) return default_value;

        // Skip whitespace
        var i = value_start;
        while (i < params_json.len and (params_json[i] == ' ' or params_json[i] == '\t')) : (i += 1) {}

        if (i >= params_json.len) return default_value;

        // String value: extract between quotes
        if (params_json[i] == '"') {
            i += 1;
            const str_start = i;
            while (i < params_json.len and params_json[i] != '"') : (i += 1) {}
            if (i > str_start) {
                return params_json[str_start..i];
            }
        }
    }

    return default_value;
}

/// Create a buffered writer for an ArrayList
fn createBufferedWriter(buf: *std.ArrayList(u8)) std.io.FixedBufferStream([]u8) {
    // Use a FixedBufferStream to write to a dynamically growing buffer
    // We'll use the ArrayList's internal buffer
    return std.io.fixedBufferStream(@as([]u8, buf.items[0.. buf.items.len]));
}

// ────────────────────────────────────────────────────────────────────────────
// Individual tool handlers
// ────────────────────────────────────────────────────────────────────────────

fn handleListTasks(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    const config_path = parseStringParam(params_json, "config_path", "zr.toml");
    const filter_pattern_str = parseStringParam(params_json, "filter_pattern", "");
    const filter_pattern = if (filter_pattern_str.len > 0) filter_pattern_str else null;

    // Create temporary file for stdout/stderr
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const stdout_path = "mcp_stdout.txt";
    const stderr_path = "mcp_stderr.txt";

    const stdout_file = try tmp_dir.dir.createFile(stdout_path, .{ .read = true });
    defer stdout_file.close();
    const stderr_file = try tmp_dir.dir.createFile(stderr_path, .{ .read = true });
    defer stderr_file.close();

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buf);
    var stderr_writer = stderr_file.writer(&stderr_buf);

    // Call real CLI function with JSON output enabled
    const exit_code = list.cmdList(
        allocator,
        config_path,
        true, // json_output = true
        false, // tree_mode = false
        filter_pattern,
        null, // filter_tags
        &stdout_writer.interface,
        &stderr_writer.interface,
        false, // use_color = false
    ) catch |err| {
        const error_json = try std.fmt.allocPrint(allocator,
            \\{{"success":false,"error":"{s}"}}
        , .{@errorName(err)});
        return ToolResult{ .json = error_json, .exit_code = 1 };
    };

    // Flush writers
    stdout_writer.interface.flush() catch {};
    stderr_writer.interface.flush() catch {};

    // Read back the output
    try stdout_file.seekTo(0);
    const output = try stdout_file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    errdefer allocator.free(output);

    // cmdList returns JSON directly, so just return it
    if (exit_code == 0 and output.len > 0) {
        return ToolResult{
            .json = output,
            .exit_code = exit_code,
        };
    } else {
        allocator.free(output);
        try stderr_file.seekTo(0);
        const err_output = try stderr_file.readToEndAlloc(allocator, 64 * 1024); // 64KB max
        defer allocator.free(err_output);

        const error_json = try std.fmt.allocPrint(allocator,
            \\{{"success":false,"message":"{s}"}}
        , .{if (err_output.len > 0) err_output else "Command failed"});
        return ToolResult{ .json = error_json, .exit_code = exit_code };
    }
}

fn handleShowTask(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    const task_name = parseStringParam(params_json, "task", "");
    const config_path = parseStringParam(params_json, "config_path", "zr.toml");

    if (task_name.len == 0) {
        const error_json = try allocator.dupe(u8,
            \\{"success":false,"error":"task parameter is required"}
        );
        return ToolResult{ .json = error_json, .exit_code = 1 };
    }

    // Create temporary file for stdout/stderr
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const stdout_path = "mcp_stdout.txt";
    const stderr_path = "mcp_stderr.txt";

    const stdout_file = try tmp_dir.dir.createFile(stdout_path, .{ .read = true });
    defer stdout_file.close();
    const stderr_file = try tmp_dir.dir.createFile(stderr_path, .{ .read = true });
    defer stderr_file.close();

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buf);
    var stderr_writer = stderr_file.writer(&stderr_buf);

    const exit_code = show.cmdShow(
        allocator,
        task_name,
        config_path,
        &stdout_writer.interface,
        &stderr_writer.interface,
        false, // use_color = false
    ) catch |err| {
        const error_json = try std.fmt.allocPrint(allocator,
            \\{{"success":false,"error":"{s}"}}
        , .{@errorName(err)});
        return ToolResult{ .json = error_json, .exit_code = 1 };
    };

    // Flush writers
    stdout_writer.interface.flush() catch {};
    stderr_writer.interface.flush() catch {};

    if (exit_code == 0) {
        try stdout_file.seekTo(0);
        const output_text = try stdout_file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(output_text);

        // Simple JSON escaping for newlines and quotes
        var escaped = std.ArrayList(u8){};
        defer escaped.deinit(allocator);
        for (output_text) |c| {
            switch (c) {
                '"' => try escaped.appendSlice(allocator, "\\\""),
                '\\' => try escaped.appendSlice(allocator, "\\\\"),
                '\n' => try escaped.appendSlice(allocator, "\\n"),
                '\r' => try escaped.appendSlice(allocator, "\\r"),
                '\t' => try escaped.appendSlice(allocator, "\\t"),
                else => try escaped.append(allocator, c),
            }
        }

        const result_json = try std.fmt.allocPrint(allocator,
            \\{{"success":true,"task":"{s}","output":"{s}"}}
        , .{ task_name, escaped.items });
        return ToolResult{ .json = result_json, .exit_code = exit_code };
    } else {
        const error_json = try std.fmt.allocPrint(allocator,
            \\{{"success":false,"error":"Task '{s}' not found"}}
        , .{task_name});
        return ToolResult{ .json = error_json, .exit_code = exit_code };
    }
}

// Stub implementations for remaining handlers (to be implemented in future commits)

fn handleRunTask(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":false,"error":"run_task not yet implemented - use 'zr run <task>' in terminal"}
    );
    return ToolResult{ .json = result_json, .exit_code = 1 };
}

fn handleValidateConfig(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":false,"error":"validate_config not yet implemented - use 'zr validate' in terminal"}
    );
    return ToolResult{ .json = result_json, .exit_code = 1 };
}

fn handleShowGraph(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":false,"error":"show_graph not yet implemented - use 'zr run <task>' in terminal"}
    );
    return ToolResult{ .json = result_json, .exit_code = 1 };
}

fn handleRunWorkflow(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":false,"error":"run_workflow not yet implemented - use 'zr workflow <name>' in terminal"}
    );
    return ToolResult{ .json = result_json, .exit_code = 1 };
}

fn handleTaskHistory(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":false,"error":"task_history not yet implemented - use 'zr history' in terminal"}
    );
    return ToolResult{ .json = result_json, .exit_code = 1 };
}

fn handleEstimateDuration(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":false,"error":"estimate_duration not yet implemented - use 'zr estimate <task>' in terminal"}
    );
    return ToolResult{ .json = result_json, .exit_code = 1 };
}

fn handleGenerateConfig(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":false,"error":"generate_config not yet implemented - use 'zr init --detect' in terminal"}
    );
    return ToolResult{ .json = result_json, .exit_code = 1 };
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "handleTool: unknown tool returns error" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MethodNotFound, handleTool(allocator, "unknown_tool", null));
}

test "handleTool: list_tasks calls real implementation" {
    const allocator = std.testing.allocator;

    // Note: Will fail without a real zr.toml, but that's expected in test environment
    // The test verifies the handler doesn't crash and returns proper error JSON
    var result = handleTool(allocator, "list_tasks", null) catch |err| {
        // Expected to fail - just verify it's a known error type
        try std.testing.expect(err == error.OutOfMemory or err == error.FileNotFound or err == error.AccessDenied);
        return;
    };
    defer result.deinit(allocator);

    // If it succeeded, verify it returns JSON
    try std.testing.expect(result.json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.json, "{") != null);
}

test "handleTool: show_task requires task parameter" {
    const allocator = std.testing.allocator;

    var result = try handleTool(allocator, "show_task", "{}");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.json, "required") != null);
}

test "handleTool: unimplemented handlers return error" {
    const allocator = std.testing.allocator;

    const unimplemented = [_][]const u8{
        "run_task",
        "validate_config",
        "show_graph",
        "run_workflow",
        "task_history",
        "estimate_duration",
        "generate_config",
    };

    for (unimplemented) |tool_name| {
        var result = try handleTool(allocator, tool_name, null);
        defer result.deinit(allocator);

        try std.testing.expectEqual(@as(u8, 1), result.exit_code);
        try std.testing.expect(std.mem.indexOf(u8, result.json, "not yet implemented") != null);
    }
}
