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

/// MCP tool definitions (camelCase inputSchema per MCP spec).
/// Shared by getCapabilities (initialize) and getToolsList (tools/list).
const TOOLS_JSON =
    \\[{"name":"run_task","description":"Execute a task by name. Returns task output and exit status.","inputSchema":{"type":"object","properties":{"task":{"type":"string","description":"Task name to execute"},"args":{"type":"array","items":{"type":"string"},"description":"Additional arguments"},"parallel":{"type":"integer","description":"Number of parallel workers"}},"required":["task"]}},
    \\{"name":"list_tasks","description":"List all available tasks in the current configuration.","inputSchema":{"type":"object","properties":{"pattern":{"type":"string","description":"Filter tasks by name pattern"},"tags":{"type":"string","description":"Filter by tags (comma-separated)"}},"required":[]}},
    \\{"name":"show_task","description":"Show detailed information about a specific task.","inputSchema":{"type":"object","properties":{"task":{"type":"string","description":"Task name to show details for"}},"required":["task"]}},
    \\{"name":"validate_config","description":"Validate the zr.toml configuration file for errors.","inputSchema":{"type":"object","properties":{"config_path":{"type":"string","description":"Path to zr.toml (default: ./zr.toml)"}},"required":[]}},
    \\{"name":"show_graph","description":"Show the task dependency graph.","inputSchema":{"type":"object","properties":{"format":{"type":"string","enum":["ascii","json","dot"],"description":"Output format (default: ascii)"}},"required":[]}},
    \\{"name":"run_workflow","description":"Execute a workflow by name.","inputSchema":{"type":"object","properties":{"workflow":{"type":"string","description":"Workflow name to execute"}},"required":["workflow"]}},
    \\{"name":"task_history","description":"Query task execution history.","inputSchema":{"type":"object","properties":{"task":{"type":"string","description":"Filter by task name"},"limit":{"type":"integer","description":"Number of entries to show (default: 10)"}},"required":[]}},
    \\{"name":"estimate_duration","description":"Estimate duration for a task based on historical data.","inputSchema":{"type":"object","properties":{"task":{"type":"string","description":"Task name to estimate"}},"required":["task"]}},
    \\{"name":"generate_config","description":"Auto-generate zr.toml from detected project languages.","inputSchema":{"type":"object","properties":{"output_path":{"type":"string","description":"Where to write generated config (default: ./zr.toml)"}},"required":[]}}]
;

/// Get MCP server capabilities for the initialize response.
/// Per MCP spec: returns { protocolVersion, capabilities: { tools: {} }, serverInfo }.
/// Tool definitions are NOT embedded here — clients call tools/list to discover them.
pub fn getCapabilities(allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        \\{{"protocolVersion":"2024-11-05","capabilities":{{"tools":{{}}}},"serverInfo":{{"name":"zr","version":"1.0.0"}}}}
    , .{});
}

/// Get the tools/list response body: { "tools": [...] }
/// Uses camelCase inputSchema as required by the MCP spec.
pub fn getToolsList(allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{{\"tools\":{s}}}", .{TOOLS_JSON});
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "getCapabilities: returns MCP-spec initialize structure" {
    const allocator = std.testing.allocator;

    const json = try getCapabilities(allocator);
    defer allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // Must have protocolVersion, capabilities, serverInfo (MCP spec)
    try std.testing.expect(parsed.value.object.get("protocolVersion") != null);
    try std.testing.expect(parsed.value.object.get("capabilities") != null);
    try std.testing.expect(parsed.value.object.get("serverInfo") != null);

    // capabilities.tools must be an empty object (no tool definitions here)
    const cap = parsed.value.object.get("capabilities").?.object;
    try std.testing.expect(cap.get("tools") != null);
}

test "getToolsList: returns tools/list response with 9 tools" {
    const allocator = std.testing.allocator;

    const json = try getToolsList(allocator);
    defer allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const tools = parsed.value.object.get("tools").?.array;
    try std.testing.expectEqual(@as(usize, 9), tools.items.len);

    // Verify first tool uses camelCase inputSchema (not input_schema)
    const first_tool = tools.items[0].object;
    try std.testing.expect(first_tool.get("inputSchema") != null);
    try std.testing.expect(first_tool.get("input_schema") == null);
}
