// src/mcp/handlers.zig
//
// MCP tool handlers - maps MCP tool calls to existing CLI functions
// Phase 10A — MCP Server implementation (simplified version for initial implementation)
//
// TODO: Full integration with all CLI functions will be completed in follow-up commits.
// For now, we provide stub implementations that return success to enable MCP server testing.

const std = @import("std");

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
    // For Phase 10A initial implementation, return stub responses
    // Full CLI integration will be added in follow-up commits

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

// ────────────────────────────────────────────────────────────────────────────
// Individual tool handlers (stub implementations for Phase 10A)
// ────────────────────────────────────────────────────────────────────────────

fn handleRunTask(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"run_task handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleListTasks(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"tasks":[],"workflows":[],"message":"list_tasks handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleShowTask(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"show_task handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleValidateConfig(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"validate_config handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleShowGraph(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"show_graph handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleRunWorkflow(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"run_workflow handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleTaskHistory(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"task_history handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleEstimateDuration(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"estimate_duration handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

fn handleGenerateConfig(allocator: std.mem.Allocator, params_json: []const u8) !ToolResult {
    _ = params_json;
    const result_json = try allocator.dupe(u8,
        \\{"success":true,"message":"generate_config handler not yet implemented","stub":true}
    );
    return ToolResult{ .json = result_json, .exit_code = 0 };
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "handleTool: unknown tool returns error" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MethodNotFound, handleTool(allocator, "unknown_tool", null));
}

test "handleTool: run_task returns stub" {
    const allocator = std.testing.allocator;
    var result = try handleTool(allocator, "run_task", null);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.json, "stub") != null);
}

test "handleTool: list_tasks returns stub" {
    const allocator = std.testing.allocator;
    var result = try handleTool(allocator, "list_tasks", null);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.json, "tasks") != null);
}
