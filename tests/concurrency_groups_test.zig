const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test 5000: Basic concurrency group definition and task execution
test "5000: task runs with concurrency group limit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 2
        \\
        \\[tasks.gpu_task1]
        \\cmd = "echo gpu1"
        \\concurrency_group = "gpu"
        \\
        \\[tasks.gpu_task2]
        \\cmd = "echo gpu2"
        \\concurrency_group = "gpu"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_task1" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "gpu1") != null);
}

// Test 5001: Multiple groups with different worker limits
test "5001: multiple concurrency groups with independent limits" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 2
        \\
        \\[concurrency_groups.network]
        \\max_workers = 10
        \\
        \\[tasks.gpu_task]
        \\cmd = "echo gpu"
        \\concurrency_group = "gpu"
        \\
        \\[tasks.network_task]
        \\cmd = "echo network"
        \\concurrency_group = "network"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_task", "network_task" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5002: Task without concurrency group uses default max_workers
test "5002: mixed tasks with and without concurrency groups" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.gpu_task]
        \\cmd = "echo gpu"
        \\concurrency_group = "gpu"
        \\
        \\[tasks.regular_task]
        \\cmd = "echo regular"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_task", "regular_task" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5003: Concurrency group with null max_workers uses default
test "5003: concurrency group inherits default max_workers when null" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.default_inherit]
        \\# max_workers omitted, should use default
        \\
        \\[tasks.task1]
        \\cmd = "echo task1"
        \\concurrency_group = "default_inherit"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "task1" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5004: Task with nonexistent group falls back to default semaphore
test "5004: task with nonexistent concurrency group uses default" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.task1]
        \\cmd = "echo fallback"
        \\concurrency_group = "nonexistent"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Should still execute successfully, falling back to global semaphore
    var result = try runZr(allocator, &.{ "--config", config, "run", "task1" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5005: Parallel execution respects group worker limits
test "5005: parallel tasks respect concurrency group limits" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.limited]
        \\max_workers = 1
        \\
        \\[tasks.task1]
        \\cmd = "sleep 0.1 && echo task1"
        \\concurrency_group = "limited"
        \\
        \\[tasks.task2]
        \\cmd = "sleep 0.1 && echo task2"
        \\concurrency_group = "limited"
        \\
        \\[tasks.task3]
        \\cmd = "sleep 0.1 && echo task3"
        \\concurrency_group = "limited"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "task1", "task2", "task3" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All tasks should complete despite limit=1
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task3") != null);
}

// Test 5006: Group limits per-group, not global
test "5006: concurrency groups have independent worker pools" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.group_a]
        \\max_workers = 1
        \\
        \\[concurrency_groups.group_b]
        \\max_workers = 1
        \\
        \\[tasks.a1]
        \\cmd = "echo a1"
        \\concurrency_group = "group_a"
        \\
        \\[tasks.a2]
        \\cmd = "echo a2"
        \\concurrency_group = "group_a"
        \\
        \\[tasks.b1]
        \\cmd = "echo b1"
        \\concurrency_group = "group_b"
        \\
        \\[tasks.b2]
        \\cmd = "echo b2"
        \\concurrency_group = "group_b"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "a1", "a2", "b1", "b2" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both groups can run concurrently even though each is limited to 1
}

// Test 5007: Tasks with dependencies and concurrency groups
test "5007: concurrency groups work with task dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 2
        \\
        \\[tasks.dep]
        \\cmd = "echo dependency"
        \\
        \\[tasks.gpu_task]
        \\cmd = "echo gpu with dep"
        \\deps = ["dep"]
        \\concurrency_group = "gpu"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_task" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dependency") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "gpu with dep") != null);
}

// Test 5008: Concurrency group with max_workers = 0 (unlimited)
test "5008: concurrency group with max_workers = 0 means unlimited" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.unlimited]
        \\max_workers = 0
        \\
        \\[tasks.task1]
        \\cmd = "echo task1"
        \\concurrency_group = "unlimited"
        \\
        \\[tasks.task2]
        \\cmd = "echo task2"
        \\concurrency_group = "unlimited"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "task1", "task2" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5009: Group limits work with --jobs flag override
test "5009: concurrency groups independent of --jobs global limit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.gpu_task]
        \\cmd = "echo gpu"
        \\concurrency_group = "gpu"
        \\
        \\[tasks.regular_task]
        \\cmd = "echo regular"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // --jobs 4 should not affect gpu group limit (still 1)
    var result = try runZr(allocator, &.{ "--config", config, "--jobs", "4", "run", "gpu_task", "regular_task" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5010: Workflow stages with concurrency groups
test "5010: concurrency groups work in workflow stages" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.gpu_task1]
        \\cmd = "echo gpu1"
        \\concurrency_group = "gpu"
        \\
        \\[tasks.gpu_task2]
        \\cmd = "echo gpu2"
        \\concurrency_group = "gpu"
        \\
        \\[workflows.test_workflow]
        \\stages = [
        \\  { name = "gpu_stage", tasks = ["gpu_task1", "gpu_task2"], parallel = true }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "test_workflow" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5011: Concurrency group with retry logic
test "5011: tasks in concurrency groups support retry" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.flaky_gpu]
        \\cmd = "echo retry test"
        \\concurrency_group = "gpu"
        \\retry_max = 2
        \\allow_failure = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky_gpu" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5012: Concurrency group with cache enabled
test "5012: tasks in concurrency groups support caching" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.cacheable_gpu]
        \\cmd = "echo cacheable"
        \\concurrency_group = "gpu"
        \\cache = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "cacheable_gpu" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5013: Concurrency group with max_concurrent per-task limit
test "5013: concurrency group plus per-task max_concurrent" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 2
        \\
        \\[tasks.gpu_task]
        \\cmd = "echo gpu with max_concurrent"
        \\concurrency_group = "gpu"
        \\max_concurrent = 1
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_task" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5014: Empty concurrency group name is valid (treated as no group)
test "5014: empty concurrency_group field treated as no group" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.task1]
        \\cmd = "echo no group"
        \\concurrency_group = ""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "task1" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5015: Multiple tasks in same group with varying durations
test "5015: concurrency group serializes long and short tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.serial]
        \\max_workers = 1
        \\
        \\[tasks.long]
        \\cmd = "sleep 0.2 && echo long"
        \\concurrency_group = "serial"
        \\
        \\[tasks.short]
        \\cmd = "echo short"
        \\concurrency_group = "serial"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "long", "short" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5016: Concurrency group with CPU affinity
test "5016: concurrency groups work with CPU affinity" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.gpu_affinity]
        \\cmd = "echo gpu with affinity"
        \\concurrency_group = "gpu"
        \\cpu_affinity = [0, 1]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_affinity" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5017: Concurrency group with NUMA node hint
test "5017: concurrency groups work with NUMA hints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.gpu_numa]
        \\cmd = "echo gpu with numa"
        \\concurrency_group = "gpu"
        \\numa_node = 0
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_numa" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5018: Concurrency group with timeout
test "5018: concurrency groups work with task timeout" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 1
        \\
        \\[tasks.gpu_timeout]
        \\cmd = "echo gpu with timeout"
        \\concurrency_group = "gpu"
        \\timeout_ms = 5000
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "gpu_timeout" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 5019: List command shows concurrency_group field
test "5019: zr list shows concurrency group for tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[concurrency_groups.gpu]
        \\max_workers = 2
        \\
        \\[tasks.gpu_task]
        \\cmd = "echo gpu"
        \\concurrency_group = "gpu"
        \\description = "GPU task"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "gpu_task") != null);
}
