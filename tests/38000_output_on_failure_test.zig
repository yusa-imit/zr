const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Output-On-Failure Flag Tests ─────────────────────────────────────────────
//
// Tests for `--output-on-failure` flag (v1.107.0):
//
// 38000: successful task output is suppressed with --output-on-failure
// 38001: failed task output IS shown with --output-on-failure
// 38002: failed task output has header "Output (taskname):" before the output
// 38003: without --output-on-failure, task output streams normally (existing behavior)
// 38004: --output-on-failure with multiple tasks: only failed tasks show output
// 38005: --output-on-failure + --dry-run: shows plan, no output buffering needed
//

// Test 38000: successful task output is suppressed with --output-on-failure
test "output-on-failure: successful task output is suppressed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.success]
        \\cmd = "echo SUCCESS_OUTPUT_SHOULD_BE_HIDDEN"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "success", "--output-on-failure" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    // Verify that the task output (SUCCESS_OUTPUT_SHOULD_BE_HIDDEN) is NOT in stdout
    try testing.expect(std.mem.indexOf(u8, result.stdout, "SUCCESS_OUTPUT_SHOULD_BE_HIDDEN") == null);
}

// Test 38001: failed task output IS shown with --output-on-failure
test "output-on-failure: failed task output IS shown" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.failure]
        \\cmd = "sh -c 'echo FAILURE_OUTPUT_SHOULD_BE_SHOWN; exit 1'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "failure", "--output-on-failure" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 1);

    // Verify that the task output (FAILURE_OUTPUT_SHOULD_BE_SHOWN) IS in stdout or stderr
    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    try testing.expect(std.mem.indexOf(u8, combined, "FAILURE_OUTPUT_SHOULD_BE_SHOWN") != null);
}

// Test 38002: failed task output has header "Output (taskname):" before the output
test "output-on-failure: failed task output has correct header" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.myfail]
        \\cmd = "sh -c 'echo task_output; exit 1'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "myfail", "--output-on-failure" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 1);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Verify header format "Output (taskname):" exists
    try testing.expect(std.mem.indexOf(u8, combined, "Output (myfail):") != null);
}

// Test 38003: without --output-on-failure, task output streams normally (existing behavior)
test "output-on-failure: without flag, output streams normally" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.normal]
        \\cmd = "echo NORMAL_OUTPUT_SHOULD_APPEAR"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run WITHOUT --output-on-failure flag
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "normal" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    // Verify that the task output (NORMAL_OUTPUT_SHOULD_APPEAR) IS in stdout
    try testing.expect(std.mem.indexOf(u8, result.stdout, "NORMAL_OUTPUT_SHOULD_APPEAR") != null);
}

// Test 38004: --output-on-failure with multiple tasks: only failed tasks show output
test "output-on-failure: with multiple tasks, only failed tasks show output" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.pass1]
        \\cmd = "echo PASS1_OUTPUT_HIDDEN"
        \\
        \\[tasks.fail1]
        \\cmd = "sh -c 'echo FAIL1_OUTPUT_SHOWN; exit 1'"
        \\
        \\[tasks.pass2]
        \\cmd = "echo PASS2_OUTPUT_HIDDEN"
        \\deps = ["fail1"]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "pass2", "--output-on-failure" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 1);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Successful tasks' output should be suppressed
    try testing.expect(std.mem.indexOf(u8, combined, "PASS1_OUTPUT_HIDDEN") == null);
    try testing.expect(std.mem.indexOf(u8, combined, "PASS2_OUTPUT_HIDDEN") == null);

    // Failed task's output should appear
    try testing.expect(std.mem.indexOf(u8, combined, "FAIL1_OUTPUT_SHOWN") != null);
}

// Test 38005: --output-on-failure + --dry-run: shows plan, no output buffering needed
test "output-on-failure: compatible with --dry-run" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.task1]
        \\cmd = "echo output1"
        \\
        \\[tasks.task2]
        \\cmd = "echo output2"
        \\deps = ["task1"]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "task2", "--dry-run", "--output-on-failure" }, tmp_path);
    defer result.deinit();

    // Dry-run should succeed (exit code 0)
    try testing.expect(result.exit_code == 0);

    // Verify the dry-run plan is shown (typical dry-run behavior)
    // The output should contain the task plan (no actual execution, so no task output)
    try testing.expect(result.stdout.len > 0 or result.stderr.len > 0);
}
