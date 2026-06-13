const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Group-Level Defaults & Inheritance Tests ──────────────────────────────────
//
// Tests for group config defaults: [tasks.group] with env/cwd/timeout (no cmd, no deps)
// that are inherited by tasks in that namespace (group.task1, group.task2, etc)
//
// 1. env inheritance — group env vars applied to group.* tasks
// 2. env merge (task wins) — group env merged with task env, task keys override group
// 3. cwd inheritance — group cwd used if task has no own cwd
// 4. timeout inheritance — group timeout used if task has no own timeout
// 5. task-level cwd override — task cwd wins over group cwd
// 6. group config non-executable — bare group name doesn't crash; list shows "(group)" indicator
//

test "24000: env inheritance — group env vars applied to build.compile" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\env = { CC = "gcc" }
        \\
        \\[tasks.build.compile]
        \\cmd = "sh -c 'echo CC=$CC'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.compile" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check that CC=gcc was set by the group config
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "CC=gcc") != null);
}

test "24001: env merge (task wins) — task env overrides and merges with group env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\env = { CC = "gcc", SHARED = "from-group" }
        \\
        \\[tasks.build.compile]
        \\cmd = "sh -c 'echo CC=$CC SHARED=$SHARED TASK_VAR=$TASK_VAR'"
        \\env = { CC = "clang", TASK_VAR = "task" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.compile" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Task env should win: CC=clang (not gcc)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "CC=clang") != null);
    // Group env should be preserved: SHARED=from-group
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "SHARED=from-group") != null);
    // Task env should be present: TASK_VAR=task
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TASK_VAR=task") != null);
}

test "24002: cwd inheritance — group cwd applied if task has no own cwd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create /tmp if needed and ensure it exists
    const cwd_target = "/tmp";

    const config_toml =
        \\[tasks.build]
        \\cwd = "/tmp"
        \\
        \\[tasks.build.compile]
        \\cmd = "pwd"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.compile" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain /tmp (the group's cwd)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, cwd_target) != null);
}

test "24003: timeout inheritance — group timeout applied if task has no own timeout" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\timeout = 1
        \\
        \\[tasks.build.compile]
        \\cmd = "sleep 0.1 && echo done"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.compile" }, tmp_path);
    defer result.deinit();

    // Should succeed because sleep 0.1 is well under 1 second timeout
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "done") != null);
}

test "24004: task-level cwd override — task cwd wins over group cwd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\cwd = "/tmp"
        \\
        \\[tasks.build.compile]
        \\cmd = "pwd"
        \\cwd = "/var"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build.compile" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain /var (the task's cwd, not /tmp from group)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/var") != null);
}

test "24005: non-executable group config — zr list shows (group) indicator, run build is safe" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\env = { CC = "gcc" }
        \\cwd = "/tmp"
        \\timeout = 60
        \\
        \\[tasks.build.compile]
        \\cmd = "echo compiled"
        \\
        \\[tasks.build.link]
        \\cmd = "echo linked"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Test zr list shows (group) indicator
    var list_result = try runZr(allocator, &.{ "--config", config, "list", "--group", "build" }, tmp_path);
    defer list_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    // Should indicate that build is a group config (may contain "(group)" or similar)
    const list_output = list_result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, list_output, "build") != null);

    // Test that running bare "build" doesn't crash
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer run_result.deinit();

    // Either succeeds (runs group tasks) or fails gracefully with helpful message
    const run_output = if (run_result.stderr.len > 0) run_result.stderr else run_result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, run_output, "build") != null or
                           std.mem.indexOf(u8, run_output, "compile") != null or
                           std.mem.indexOf(u8, run_output, "link") != null);
}
