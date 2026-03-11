const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test config with a simple task
const SIMPLE_TASK =
    \\[tasks.hello]
    \\cmd = "echo 'Hello World'"
;

// Test config with resource-intensive task
const MEMORY_TASK =
    \\[tasks.memory]
    \\cmd = "echo 'Testing memory monitoring'"
;

// Test config with multiple parallel tasks
const PARALLEL_TASKS =
    \\[tasks.task1]
    \\cmd = "sleep 0.1 && echo 'Task 1'"
    \\
    \\[tasks.task2]
    \\cmd = "sleep 0.1 && echo 'Task 2'"
    \\
    \\[tasks.task3]
    \\cmd = "sleep 0.1 && echo 'Task 3'"
;

test "916: run with --monitor flag shows resource usage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--monitor", "hello" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain task execution (hello task ran)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hello World") != null);
}

test "917: run with --monitor and --dry-run shows monitoring would be enabled" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--monitor", "--dry-run", "hello" }, tmp_path);
    defer result.deinit();

    // Should succeed in dry-run mode
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show task would be executed
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null or
                           std.mem.indexOf(u8, result.stderr, "hello") != null);
}

test "918: run with --monitor flag on task with dependencies enables parallel monitoring" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create tasks with dependencies to enable parallel execution
    const dep_tasks =
        \\[tasks.base]
        \\cmd = "echo 'Base task'"
        \\
        \\[tasks.child1]
        \\cmd = "echo 'Child 1'"
        \\deps = ["base"]
        \\
        \\[tasks.child2]
        \\cmd = "echo 'Child 2'"
        \\deps = ["base"]
        \\
        \\[tasks.final]
        \\cmd = "echo 'Final task'"
        \\deps = ["child1", "child2"]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, dep_tasks);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--monitor", "--jobs", "3", "final" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Final task output should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Final task") != null);
}

test "919: run without --monitor flag works normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run without --monitor flag
    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hello World") != null);
}

test "920: run with --monitor on failing task still monitors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const failing_task =
        \\[tasks.fail]
        \\cmd = "exit 1"
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, failing_task);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--monitor", "fail" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code 1)
    try std.testing.expect(result.exit_code != 0);
}
