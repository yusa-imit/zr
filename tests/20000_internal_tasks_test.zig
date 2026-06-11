const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Integration Tests for Internal Task Flag Feature ───────────────────────────
//
// Tests for Internal Task Visibility feature (v1.91.0):
// Tasks with `internal = true` are hidden from `zr list` by default.
// They remain runnable via `zr run <task-name>` and visible with `zr list --all`.
//
// TOML syntax:
// [tasks.helper]
// cmd = "..."
// internal = true      # Hide from list, show with --all flag
//
// Behavior:
// - `zr list` — internal tasks are filtered out
// - `zr list --all` — internal tasks shown with "(internal)" marker
// - `zr run <internal-task>` — works normally, internal flag has no effect
// - `zr explain <internal-task>` — works normally
// - Levenshtein suggestions include internal tasks (they're still valid tasks)
//

test "20000: internal = true task is hidden from zr list output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.helper]
        \\cmd = "echo helper"
        \\internal = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // "build" should be in the output (public task)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);

    // "helper" should NOT be in the output (internal task, hidden by default)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "helper") == null);
}

test "20001: internal = true task IS shown in zr list --all output with (internal) marker" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.helper]
        \\cmd = "echo helper"
        \\internal = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--all" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Both "build" and "helper" should be in the output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "helper") != null);

    // The output should include a marker indicating the task is internal
    // This could be "(internal)" or similar — just verify it's explicitly marked
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "internal") != null);
}

test "20002: zr run <internal-task> runs successfully (internal doesn't block execution)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.helper]
        \\cmd = "echo internal_task_ran"
        \\internal = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "helper" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // The internal task should execute and produce its output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "internal_task_ran") != null);
}

test "20003: multiple tasks — only non-internal shown in zr list (default)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks._setup]
        \\cmd = "echo setup"
        \\internal = true
        \\
        \\[tasks._teardown]
        \\cmd = "echo teardown"
        \\internal = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Public tasks should be shown
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);

    // Internal tasks should be hidden
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "_setup") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "_teardown") == null);
}

test "20004: zr run with typo suggests internal task via Levenshtein distance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\internal = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Try to run with a typo: "deplo" instead of "deploy"
    var result = try runZr(allocator, &.{ "--config", config, "run", "deplo" }, null);
    defer result.deinit();

    // Should fail (task not found)
    try std.testing.expect(result.exit_code != 0);

    // The error output should suggest "deploy" (the internal task) as a possible match
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "deploy") != null);
}

test "20005: internal = false (explicit) behaves same as omitting internal field (shown in list)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.with_explicit_false]
        \\cmd = "echo explicit_false"
        \\internal = false
        \\
        \\[tasks.without_internal]
        \\cmd = "echo without_internal"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Both tasks should be visible (internal=false is same as omitting it)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "with_explicit_false") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "without_internal") != null);

    // Neither should have an "(internal)" marker since both are public
    // (If marker is present, it indicates the field defaults incorrectly)
    const count_internal_markers = std.mem.count(u8, result.stdout, "(internal)");
    try std.testing.expectEqual(@as(usize, 0), count_internal_markers);
}

test "20006: zr explain <internal-task> works and shows task details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.helper]
        \\cmd = "echo helper"
        \\description = "Helper task"
        \\internal = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "helper" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // The explain output should show the task details
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Helper task") != null or
        std.mem.indexOf(u8, result.stdout, "echo helper") != null);
}
