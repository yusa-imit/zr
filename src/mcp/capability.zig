// src/mcp/capability.zig
//
// MCP capability negotiation for Model Context Protocol
// Phase 10A — MCP Server implementation

const std = @import("std");

/// MCP tool names - all 9 tools defined in PRD Section 5.12
pub const TOOL_NAMES = [_][]const u8{
    "run_task",
    "list_tasks",
    "show_task",
    "validate_config",
    "show_graph",
    "run_workflow",
    "task_history",
    "estimate_duration",
    "generate_config",
};

/// Get MCP server capabilities - returns JSON string
pub fn getCapabilities(allocator: std.mem.Allocator) ![]const u8 {
    // Manually construct the JSON for capabilities
    // This avoids complex std.json.Value construction issues in Zig 0.15
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll(
        \\{"capabilities":{"tools":{"definitions":[
        \\{"name":"run_task","description":"Execute a task by name. Returns task output and exit status.","input_schema":{"type":"object","properties":{"task":{"type":"string","description":"Task name to execute"},"args":{"type":"array","items":{"type":"string"},"description":"Additional arguments"},"parallel":{"type":"integer","description":"Number of parallel workers"}},"required":["task"]}},
        \\{"name":"list_tasks","description":"List all available tasks in the current configuration.","input_schema":{"type":"object","properties":{"pattern":{"type":"string","description":"Filter tasks by name pattern"},"tags":{"type":"string","description":"Filter by tags (comma-separated)"}},"required":[]}},
        \\{"name":"show_task","description":"Show detailed information about a specific task.","input_schema":{"type":"object","properties":{"task":{"type":"string","description":"Task name to show details for"}},"required":["task"]}},
        \\{"name":"validate_config","description":"Validate the zr.toml configuration file for errors.","input_schema":{"type":"object","properties":{"config_path":{"type":"string","description":"Path to zr.toml (default: ./zr.toml)"}},"required":[]}},
        \\{"name":"show_graph","description":"Show the task dependency graph.","input_schema":{"type":"object","properties":{"format":{"type":"string","enum":["ascii","json","dot"],"description":"Output format (default: ascii)"}},"required":[]}},
        \\{"name":"run_workflow","description":"Execute a workflow by name.","input_schema":{"type":"object","properties":{"workflow":{"type":"string","description":"Workflow name to execute"}},"required":["workflow"]}},
        \\{"name":"task_history","description":"Query task execution history.","input_schema":{"type":"object","properties":{"task":{"type":"string","description":"Filter by task name"},"limit":{"type":"integer","description":"Number of entries to show (default: 10)"}},"required":[]}},
        \\{"name":"estimate_duration","description":"Estimate duration for a task based on historical data.","input_schema":{"type":"object","properties":{"task":{"type":"string","description":"Task name to estimate"}},"required":["task"]}},
        \\{"name":"generate_config","description":"Auto-generate zr.toml from detected project languages (uses LanguageProvider).","input_schema":{"type":"object","properties":{"output_path":{"type":"string","description":"Where to write generated config (default: ./zr.toml)"}},"required":[]}}
        \\]}}}
    );

    return try buf.toOwnedSlice(allocator);
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "getCapabilities: returns valid JSON" {
    const allocator = std.testing.allocator;

    const json = try getCapabilities(allocator);
    defer allocator.free(json);

    // Parse back to verify it's valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // Verify structure
    try std.testing.expect(parsed.value.object.get("capabilities") != null);
}

test "getCapabilities: includes 9 tools" {
    const allocator = std.testing.allocator;

    const json = try getCapabilities(allocator);
    defer allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const cap = parsed.value.object.get("capabilities").?.object;
    const tools_obj = cap.get("tools").?.object;
    const definitions = tools_obj.get("definitions").?.array;

    // Should have exactly 9 tools
    try std.testing.expectEqual(@as(usize, 9), definitions.items.len);
}
