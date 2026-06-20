const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

// ── Comma-Separated Multi-Task Run Tests ──────────────────────────────────────
//
// Tests for `zr run task1,task2,task3` feature (v1.101.0+):
//
// 1. Basic two-task sequential run succeeds
// 2. Three tasks run in order
// 3. Without --fail-fast, all tasks run even if first fails
// 4. With --fail-fast, stops after first failure
// 5. Unknown task in list returns error
// 6. Trailing/leading commas edge case
// 7. --dry-run works with comma list
// 8. All tasks in list succeed → exit 0
//

const TWO_TASK_TOML =
    \\[tasks.build]
    \\cmd = "echo BUILD_DONE"
    \\
    \\[tasks.test]
    \\cmd = "echo TEST_DONE"
    \\
;

const THREE_TASK_TOML =
    \\[tasks.a]
    \\cmd = "echo A"
    \\
    \\[tasks.b]
    \\cmd = "echo B"
    \\
    \\[tasks.c]
    \\cmd = "echo C"
    \\
;

const FAIL_THEN_OK_TOML =
    \\[tasks.fail]
    \\cmd = "exit 1"
    \\
    \\[tasks.ok]
    \\cmd = "echo OK_AFTER_FAIL"
    \\
;

const FAIL_FAST_TOML =
    \\[tasks.fail]
    \\cmd = "exit 1"
    \\
    \\[tasks.ok]
    \\cmd = "echo SHOULD_NOT_RUN"
    \\
;

const NONEXISTENT_TOML =
    \\[tasks.build]
    \\cmd = "echo build"
    \\
;

const THREE_SUCCESS_TOML =
    \\[tasks.task1]
    \\cmd = "echo task1_done"
    \\
    \\[tasks.task2]
    \\cmd = "echo task2_done"
    \\
    \\[tasks.task3]
    \\cmd = "echo task3_done"
    \\
;

test "30000: basic two-task sequential run succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with build and test tasks
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = TWO_TASK_TOML });

    // Run: zr run build,test
    var result = try runZr(allocator, &.{ "run", "build,test" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Stdout should contain both BUILD_DONE and TEST_DONE
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "BUILD_DONE") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TEST_DONE") != null);

    // BUILD_DONE must appear before TEST_DONE in output (sequential order)
    const build_pos = std.mem.indexOf(u8, result.stdout, "BUILD_DONE").?;
    const test_pos = std.mem.indexOf(u8, result.stdout, "TEST_DONE").?;
    try std.testing.expect(build_pos < test_pos);
}

test "30001: three tasks run in order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with tasks a, b, c
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = THREE_TASK_TOML });

    // Run: zr run a,b,c
    var result = try runZr(allocator, &.{ "run", "a,b,c" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Stdout should contain A, B, C
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "A") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "B") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "C") != null);

    // Verify order: A before B before C
    const a_pos = std.mem.indexOf(u8, result.stdout, "A").?;
    const b_pos = std.mem.indexOf(u8, result.stdout, "B").?;
    const c_pos = std.mem.indexOf(u8, result.stdout, "C").?;
    try std.testing.expect(a_pos < b_pos);
    try std.testing.expect(b_pos < c_pos);
}

test "30002: without --fail-fast, all tasks run even if first fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with fail and ok tasks
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = FAIL_THEN_OK_TOML });

    // Run: zr run fail,ok (without --fail-fast)
    var result = try runZr(allocator, &.{ "run", "fail,ok" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code != 0) because fail task failed
    try std.testing.expect(result.exit_code != 0);

    // Stdout should contain OK_AFTER_FAIL (second task ran despite first failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "OK_AFTER_FAIL") != null);
}

test "30003: with --fail-fast, stops after first failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with fail and ok tasks
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = FAIL_FAST_TOML });

    // Run: zr run fail,ok --fail-fast
    var result = try runZr(allocator, &.{ "run", "fail,ok", "--fail-fast" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code != 0) because fail task failed
    try std.testing.expect(result.exit_code != 0);

    // Stdout should NOT contain SHOULD_NOT_RUN (second task should not execute with --fail-fast)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "SHOULD_NOT_RUN") == null);
}

test "30004: unknown task in list returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with only build task (no nonexistent task)
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = NONEXISTENT_TOML });

    // Run: zr run build,nonexistent
    var result = try runZr(allocator, &.{ "run", "build,nonexistent" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code != 0) because nonexistent task is not found
    try std.testing.expect(result.exit_code != 0);

    // Stderr should contain error message about nonexistent task
    // (stderr or stdout may contain the error depending on implementation)
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "nonexistent") != null);
}

test "30005: trailing comma edge case" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with build and test tasks
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = TWO_TASK_TOML });

    // Run: zr run build, (trailing comma, should run only build)
    // Note: implementation should handle trailing/leading commas gracefully
    var result = try runZr(allocator, &.{ "run", "build," }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0) if build succeeds
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Stdout should contain BUILD_DONE
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "BUILD_DONE") != null);
}

test "30006: --dry-run works with comma list" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with build and test tasks
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = TWO_TASK_TOML });

    // Run: zr run --dry-run build,test
    var result = try runZr(allocator, &.{ "run", "--dry-run", "build,test" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0) with dry-run
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should mention both tasks in dry-run preview (doesn't execute them)
    // Check for task names in combined output (--dry-run displays task plan)
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "build") != null or
        std.mem.indexOf(u8, combined, "test") != null);
}

test "30007: all tasks in list succeed → overall exit 0" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with three successful tasks
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = THREE_SUCCESS_TOML });

    // Run: zr run task1,task2,task3
    var result = try runZr(allocator, &.{ "run", "task1,task2,task3" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0) when all tasks succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Stdout should contain output from all three tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1_done") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2_done") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task3_done") != null);
}
