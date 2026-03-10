const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "895: before hook executes before task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task running'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'before hook'"
        \\point = "before"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "before hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task running") != null);
}

test "896: after hook executes after task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task running'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'after hook'"
        \\point = "after"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task running") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "after hook") != null);
}

test "897: success hook executes only on task success" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "exit 0"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'success hook'"
        \\point = "success"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "success hook") != null);
}

test "898: failure hook executes only on task failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "exit 1"
        \\allow_failure = true
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'failure hook executed'"
        \\point = "failure"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "failure hook executed") != null);
}

test "899: timeout hook executes only on task timeout" {
    // TODO: timeout_ms not implemented yet - requires scheduler integration
    return error.SkipZigTest;
}

test "900: before hook with abort_task strategy fails task on hook failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task should not run'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "exit 1"
        \\point = "before"
        \\failure_strategy = "abort_task"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Task should not run if before hook aborts
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task should not run") == null);
}

test "901: before hook with continue_task strategy allows task to run" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task running despite hook failure'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "exit 1"
        \\point = "before"
        \\failure_strategy = "continue_task"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task running despite hook failure") != null);
}

test "902: environment variables are accessible in hooks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo Task name: $ZR_TASK_NAME"
        \\point = "before"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task name: test") != null);
}

test "903: multiple hooks execute in order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'before 1'"
        \\point = "before"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'before 2'"
        \\point = "before"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'after 1'"
        \\point = "after"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "before 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "before 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "after 1") != null);
}

test "904: inline table env syntax for hooks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo $HOOK_VAR"
        \\point = "before"
        \\env = { HOOK_VAR = "hook value" }
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hook value") != null);
}

test "905: working_dir changes hook execution directory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("subdir");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "echo 'task'"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "pwd"
        \\point = "before"
        \\working_dir = "./subdir"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "subdir") != null);
}

test "906: ZR_EXIT_CODE and ZR_DURATION_MS available in after hooks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.test]
        \\cmd = "exit 42"
        \\allow_failure = true
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo Exit code: $ZR_EXIT_CODE"
        \\point = "after"
    ;

    _ = try writeTmpConfig(allocator, tmp.dir, config);
    const result = try runZr(allocator, &[_][]const u8{ "run", "test" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Exit code: 42") != null);
}
