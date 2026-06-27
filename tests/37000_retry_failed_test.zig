const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Retry Failed Tests ───────────────────────────────────────────────────────
//
// Tests for `zr run --retry-failed` (v1.107.0):
//
// 37000: --retry-failed with no failures file → prints message, exits 0
// 37001: run failing task → creates .zr/last-failures.txt with failed task name
// 37002: --retry-failed re-runs only the failed task
// 37003: --retry-failed --dry-run shows which tasks would be retried
// 37004: successful run clears last-failures.txt (no failures to retry after success)
// 37005: --retry-failed with multiple failed tasks runs all of them
//

// Test 37000: --retry-failed with no failures file → message + exit 0
test "retry-failed: no previous failures file exits 0 with message" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo compiled"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "--retry-failed" }, tmp_path);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "No previous failures") != null or
        std.mem.indexOf(u8, result.stderr, "No previous failures") != null);
}

// Test 37001: run failing task → creates .zr/last-failures.txt
test "retry-failed: failing run creates last-failures.txt" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.fail-task]
        \\cmd = "sh -c 'exit 1'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run failing task
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "fail-task" }, tmp_path);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.exit_code);

    // Check .zr/last-failures.txt was created
    const failures_content = try tmp.dir.readFileAlloc(testing.allocator, ".zr/last-failures.txt", 4096);
    defer testing.allocator.free(failures_content);

    try testing.expect(std.mem.indexOf(u8, failures_content, "fail-task") != null);
}

// Test 37002: --retry-failed re-runs the failed task
test "retry-failed: retries only the previously failed task" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A task that always fails
    const toml =
        \\[tasks.always-fail]
        \\cmd = "sh -c 'exit 1'"
        \\
        \\[tasks.always-pass]
        \\cmd = "echo pass"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // First run: only run always-fail to create failures file
    var first = try runZr(testing.allocator, &.{ "--config", config, "run", "always-fail" }, tmp_path);
    defer first.deinit();
    try testing.expectEqual(@as(u8, 1), first.exit_code);

    // Second run: --retry-failed should retry always-fail (and fail again)
    var retry = try runZr(testing.allocator, &.{ "--config", config, "run", "--retry-failed" }, tmp_path);
    defer retry.deinit();
    // Should fail (retrying a task that always fails)
    try testing.expectEqual(@as(u8, 1), retry.exit_code);
    // Output should mention the task name
    try testing.expect(std.mem.indexOf(u8, retry.stdout, "always-fail") != null or
        std.mem.indexOf(u8, retry.stderr, "always-fail") != null);
}

// Test 37003: --retry-failed --dry-run shows which tasks would be retried
test "retry-failed: --dry-run shows tasks without running them" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.fail-task]
        \\cmd = "sh -c 'exit 1'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Create failures file first
    var fail_run = try runZr(testing.allocator, &.{ "--config", config, "run", "fail-task" }, tmp_path);
    defer fail_run.deinit();
    try testing.expectEqual(@as(u8, 1), fail_run.exit_code);

    // Now run --retry-failed --dry-run
    var dry = try runZr(testing.allocator, &.{ "--config", config, "run", "--retry-failed", "--dry-run" }, tmp_path);
    defer dry.deinit();

    try testing.expectEqual(@as(u8, 0), dry.exit_code);
    // Dry-run output should mention the task
    try testing.expect(std.mem.indexOf(u8, dry.stdout, "fail-task") != null);
}

// Test 37004: successful run clears last-failures.txt
test "retry-failed: successful run clears the failures file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.passing]
        \\cmd = "echo success"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Manually write a stale failures file
    try tmp.dir.makePath(".zr");
    const stale = "old-failed-task\n";
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = stale });

    // Run a passing task
    var success = try runZr(testing.allocator, &.{ "--config", config, "run", "passing" }, tmp_path);
    defer success.deinit();
    try testing.expectEqual(@as(u8, 0), success.exit_code);

    // Now --retry-failed should report no failures (file cleared)
    var retry = try runZr(testing.allocator, &.{ "--config", config, "run", "--retry-failed" }, tmp_path);
    defer retry.deinit();
    try testing.expectEqual(@as(u8, 0), retry.exit_code);
    try testing.expect(std.mem.indexOf(u8, retry.stdout, "No previous failures") != null or
        std.mem.indexOf(u8, retry.stderr, "No previous failures") != null);
}

// Test 37005: --retry-failed with multiple failed tasks runs all of them
test "retry-failed: multiple failed tasks are all retried" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.fail-a]
        \\cmd = "sh -c 'exit 1'"
        \\
        \\[tasks.fail-b]
        \\cmd = "sh -c 'exit 1'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run both failing tasks in one go (comma-separated)
    var first = try runZr(testing.allocator, &.{ "--config", config, "run", "fail-a,fail-b" }, tmp_path);
    defer first.deinit();
    try testing.expectEqual(@as(u8, 1), first.exit_code);

    // Check failures file has both tasks
    const failures_content = try tmp.dir.readFileAlloc(testing.allocator, ".zr/last-failures.txt", 4096);
    defer testing.allocator.free(failures_content);
    try testing.expect(std.mem.indexOf(u8, failures_content, "fail-a") != null);
    try testing.expect(std.mem.indexOf(u8, failures_content, "fail-b") != null);

    // Retry: both tasks should be retried
    var retry = try runZr(testing.allocator, &.{ "--config", config, "run", "--retry-failed" }, tmp_path);
    defer retry.deinit();
    try testing.expectEqual(@as(u8, 1), retry.exit_code);
    const all_output = try std.mem.concat(testing.allocator, u8, &.{ retry.stdout, retry.stderr });
    defer testing.allocator.free(all_output);
    try testing.expect(std.mem.indexOf(u8, all_output, "fail-a") != null);
    try testing.expect(std.mem.indexOf(u8, all_output, "fail-b") != null);
}
