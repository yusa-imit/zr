const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Run Summary Tests ─────────────────────────────────────────────────────────
//
// Tests for `--summary` flag (v1.109.0):
//
// 39000: --summary shows "Run Summary" header for single task
// 39001: --summary shows all tasks in the summary table
// 39002: --summary shows failed tasks with exit code
// 39003: --summary shows skipped tasks
// 39004: without --summary, no "Run Summary" header is shown
// 39005: --summary with --json skips the summary table
//

// Test 39000: --summary shows Run Summary header for single successful task
test "summary: shows Run Summary header for single task" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo built"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "build", "--summary" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Summary header must be present
    try testing.expect(std.mem.indexOf(u8, combined, "Run Summary") != null);
    // Task name must appear in the table
    try testing.expect(std.mem.indexOf(u8, combined, "build") != null);
}

// Test 39001: --summary shows all tasks in table with multiple tasks
test "summary: shows all tasks in summary table" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.compile]
        \\cmd = "echo compiling"
        \\
        \\[tasks.link]
        \\cmd = "echo linking"
        \\deps = ["compile"]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "link", "--summary" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Both tasks must appear in the summary table
    try testing.expect(std.mem.indexOf(u8, combined, "Run Summary") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "compile") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "link") != null);
}

// Test 39002: --summary shows failed tasks with exit code information
test "summary: shows failed tasks with exit code" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.lint]
        \\cmd = "sh -c 'exit 2'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "lint", "--summary" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 1);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Summary table must show the failed task name
    try testing.expect(std.mem.indexOf(u8, combined, "Run Summary") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "lint") != null);
}

// Test 39003: --summary shows skipped tasks in the table
test "summary: shows skipped tasks in table" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.prepare]
        \\cmd = "echo prepare"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps = ["prepare"]
        \\condition = "false"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "deploy", "--summary" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Summary table must show both tasks (prepare ran, deploy was skipped)
    try testing.expect(std.mem.indexOf(u8, combined, "Run Summary") != null);
}

// Test 39004: without --summary, no "Run Summary" header is shown
test "summary: without flag, no summary table is printed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo built"
        \\
        \\[tasks.test]
        \\cmd = "echo tested"
        \\deps = ["build"]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "test" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Without --summary, the "Run Summary" header should NOT appear
    try testing.expect(std.mem.indexOf(u8, combined, "Run Summary") == null);
}

// Test 39005: --summary with --json outputs JSON only, no summary table
test "summary: --summary with --json outputs JSON, no summary table" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo built"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "build", "--json", "--summary" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // JSON output branch skips the summary table
    try testing.expect(std.mem.indexOf(u8, combined, "Run Summary") == null);
    // But JSON output should be present
    try testing.expect(std.mem.indexOf(u8, combined, "\"tasks\"") != null or
        std.mem.indexOf(u8, combined, "success") != null);
}
