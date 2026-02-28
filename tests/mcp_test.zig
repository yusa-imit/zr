const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrWithStdin = helpers.runZrWithStdin;
const writeTmpConfig = helpers.writeTmpConfig;

test "mcp: missing subcommand shows error" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{"mcp"}, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "missing subcommand") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Hint: zr mcp serve") != null);
}

test "mcp: unknown subcommand shows error" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "mcp", "invalid" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown subcommand") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "'invalid'") != null);
}

test "mcp serve: responds to initialize request" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create minimal config for MCP server
    const config_content =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config_path);

    // Send an initialize request via stdin
    const initialize_request =
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}
        \\
    ;

    var result = try runZrWithStdin(allocator, tmp.dir, &.{ "mcp", "serve" }, initialize_request);
    defer result.deinit();

    // MCP server should respond with a valid initialize response
    // The response should be in JSON-RPC format
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"result\"") != null);

    // Should contain server capabilities
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "capabilities") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tools") != null);
}

test "mcp serve: lists available tools" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create config
    const config_content =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config_path);

    // Send initialize + tools/list requests
    const requests =
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
        \\{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        \\{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
        \\
    ;

    var result = try runZrWithStdin(allocator, tmp.dir, &.{ "mcp", "serve" }, requests);
    defer result.deinit();

    // Should list MCP tools
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "run_task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "list_tasks") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "show_task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "validate_config") != null);
}

test "mcp serve: run_task tool executes task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create config with a simple echo task
    const config_content =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config_path);

    // Send initialize + tools/call request
    const requests =
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"run_task","arguments":{"task_name":"hello"}}}
        \\
    ;

    var result = try runZrWithStdin(allocator, tmp.dir, &.{ "mcp", "serve" }, requests);
    defer result.deinit();

    // Should execute the task and return results
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"id\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"result\"") != null or
        std.mem.indexOf(u8, result.stdout, "content") != null);
}
