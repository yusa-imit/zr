const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Test Fixtures ──────────────────────────────────────────────────────

/// Multiple tasks where one fails and others follow
const FAIL_FAST_BASIC_TOML =
    \\[tasks.task_a]
    \\cmd = "echo task_a_output"
    \\
    \\[tasks.task_b]
    \\cmd = "false"
    \\
    \\[tasks.task_c]
    \\cmd = "echo task_c_output"
    \\
;

/// Multiple tasks for glob pattern testing (alphabetical: test_a < test_b < test_c)
/// Uses UPPERCASE echo strings to distinguish execution output from "Selected" list display
const FAIL_FAST_GLOB_TOML =
    \\[tasks.test_a]
    \\cmd = "echo EXECUTED_FIRST"
    \\
    \\[tasks.test_b]
    \\cmd = "false"
    \\
    \\[tasks.test_c]
    \\cmd = "echo EXECUTED_THIRD"
    \\
    \\[tasks.build]
    \\cmd = "echo EXECUTED_BUILD"
    \\
;

/// Multiple tasks with tags for tag filter testing (alphabetical: a_lint, b_format, c_test)
/// Uses UPPERCASE echo strings to distinguish execution from "Selected" list display
const FAIL_FAST_TAG_TOML =
    \\[tasks.a_lint]
    \\cmd = "echo LINTING_DONE"
    \\tags = ["check"]
    \\
    \\[tasks.b_format]
    \\cmd = "false"
    \\tags = ["check"]
    \\
    \\[tasks.c_test]
    \\cmd = "echo TESTING_DONE"
    \\tags = ["check"]
    \\
    \\[tasks.build]
    \\cmd = "echo BUILDING_DONE"
    \\
;

/// Multiple tasks all succeeding
const FAIL_FAST_SUCCESS_TOML =
    \\[tasks.task_a]
    \\cmd = "echo task_a"
    \\
    \\[tasks.task_b]
    \\cmd = "echo task_b"
    \\
    \\[tasks.task_c]
    \\cmd = "echo task_c"
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "600: run with --fail-fast glob pattern stops on first failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_FAST_GLOB_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Tasks sorted alphabetically: test_a (success), test_b (fail), test_c (should be skipped)
    // Run with glob pattern test_* and --fail-fast
    var result = try runZr(allocator, &.{ "--config", config, "run", "test_*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code non-zero)
    try std.testing.expect(result.exit_code != 0);

    // EXECUTED_FIRST (from test_a) should be in output (ran before failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_FIRST") != null);

    // EXECUTED_THIRD (from test_c) should NOT be in output (stopped after test_b failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_THIRD") == null);
}

test "601: run with --fail-fast tag filter stops on first failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_FAST_TAG_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Tasks sorted alphabetically: a_lint (success), b_format (fail), c_test (should be skipped)
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=check", "*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code non-zero)
    try std.testing.expect(result.exit_code != 0);

    // LINTING_DONE should be in output (a_lint ran before b_format failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "LINTING_DONE") != null);

    // TESTING_DONE should NOT be in output (stopped after b_format failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TESTING_DONE") == null);
}

test "602: run without --fail-fast continues despite failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_FAST_GLOB_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run WITHOUT --fail-fast — test_a (success), test_b (fail), test_c (should still run)
    var result = try runZr(allocator, &.{ "--config", config, "run", "test_*" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code non-zero due to test_b failure)
    try std.testing.expect(result.exit_code != 0);

    // Both EXECUTED_FIRST (from test_a) and EXECUTED_THIRD (from test_c) should be in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_FIRST") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_THIRD") != null);
}

test "603: run with --fail-fast when all tasks succeed executes all tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_FAST_SUCCESS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with --fail-fast but all tasks succeed
    // All tasks should execute since none fail
    var result = try runZr(allocator, &.{ "--config", config, "run", "task_*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should succeed (all tasks passed)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // All tasks should be in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task_a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task_b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task_c") != null);
}

test "604: run with --fail-fast error message names the failing task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_FAST_BASIC_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run: task_a (success), task_b (fail), task_c (should be skipped due to --fail-fast)
    var result = try runZr(allocator, &.{ "--config", config, "run", "task_*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Exit code should be non-zero (task_b failed)
    try std.testing.expect(result.exit_code != 0);

    // task_c should NOT have executed (stopped after task_b failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task_c_output") == null);

    // Error message should mention the failing task name
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "task_b") != null);
}

test "605: run with --fail-fast and --dry-run shows all tasks without executing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_FAST_GLOB_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with both --fail-fast and --dry-run
    var result = try runZr(allocator, &.{ "--config", config, "run", "test_*", "--fail-fast", "--dry-run" }, tmp_path);
    defer result.deinit();

    // Should succeed (dry-run doesn't execute)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // No tasks should have actually executed — EXECUTED_* strings must not appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_FIRST") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_THIRD") == null);

    // Task names should appear in the dry-run preview output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test_a") != null or
        std.mem.indexOf(u8, result.stdout, "test_b") != null or
        std.mem.indexOf(u8, result.stdout, "test_c") != null);
}

test "606: run with --fail-fast on first task failure stops immediately" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // task_1 fails first (alphabetically first), task_2 and task_3 should be skipped
    // Use unique echo strings (not the task names) to distinguish execution from "Selected" display
    const config_toml =
        \\[tasks.task_1]
        \\cmd = "false"
        \\
        \\[tasks.task_2]
        \\cmd = "echo EXECUTED_SECOND"
        \\
        \\[tasks.task_3]
        \\cmd = "echo EXECUTED_THIRD"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // First task fails immediately
    var result = try runZr(allocator, &.{ "--config", config, "run", "task_*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should fail
    try std.testing.expect(result.exit_code != 0);

    // task_2 and task_3 should not execute (their echo strings absent)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_SECOND") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_THIRD") == null);
}

test "607: run with --fail-fast multiple tags AND filter stops on first failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Tasks with both tags, sorted: check_1 < check_2 < check_3. "other" has only "validate".
    // UPPERCASE echo strings to distinguish from task names in "Selected" list
    const config_toml =
        \\[tasks.check_1]
        \\cmd = "echo EXECUTED_CHECK_ONE"
        \\tags = ["validate", "critical"]
        \\
        \\[tasks.check_2]
        \\cmd = "false"
        \\tags = ["validate", "critical"]
        \\
        \\[tasks.check_3]
        \\cmd = "echo EXECUTED_CHECK_THREE"
        \\tags = ["validate", "critical"]
        \\
        \\[tasks.other]
        \\cmd = "echo EXECUTED_OTHER"
        \\tags = ["validate"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with multiple tag filters (AND logic) and --fail-fast
    var result = try runZr(allocator, &.{ "--config", config, "run", "--tag=validate", "--tag=critical", "*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should fail
    try std.testing.expect(result.exit_code != 0);

    // check_1 should execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_CHECK_ONE") != null);

    // check_3 should not execute (stopped at check_2)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_CHECK_THREE") == null);

    // other should not execute (doesn't have critical tag — only has "validate")
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_OTHER") == null);
}

test "608: run with --fail-fast and --json output includes executed tasks only" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_FAST_GLOB_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with both --fail-fast and --format json (JSON output)
    // test_a (success), test_b (fail), test_c (should be skipped due to --fail-fast)
    var result = try runZr(allocator, &.{ "--config", config, "--format", "json", "run", "test_*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should fail (test_b fails)
    try std.testing.expect(result.exit_code != 0);

    // Output should contain JSON structure (at minimum a recognizable field)
    try std.testing.expect(
        std.mem.indexOf(u8, result.stdout, "\"tasks\"") != null or
        std.mem.indexOf(u8, result.stdout, "\"failed\"") != null or
        std.mem.indexOf(u8, result.stdout, "\"status\"") != null or
        std.mem.indexOf(u8, result.stdout, "\"task\"") != null
    );

    // test_c must not have executed (--fail-fast stopped at test_b)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_THIRD") == null);
}

test "609: run with --fail-fast preserves task execution order before failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Tasks sorted alphabetically: a_first, b_second, c_third (fails), d_fourth
    // Use unique UPPERCASE strings to distinguish execution from "Selected" list display
    const config_toml =
        \\[tasks.a_first]
        \\cmd = "echo EXECUTED_FIRST"
        \\
        \\[tasks.b_second]
        \\cmd = "echo EXECUTED_SECOND"
        \\
        \\[tasks.c_third]
        \\cmd = "false"
        \\
        \\[tasks.d_fourth]
        \\cmd = "echo EXECUTED_FOURTH"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run all tasks with --fail-fast (glob selects all, sorted alphabetically)
    var result = try runZr(allocator, &.{ "--config", config, "run", "*", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should fail
    try std.testing.expect(result.exit_code != 0);

    // a_first and b_second should be in output (before c_third failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_FIRST") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_SECOND") != null);

    // d_fourth should not be in output (stopped at c_third)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "EXECUTED_FOURTH") == null);
}
