const std = @import("std");
const helpers = @import("helpers.zig");

test "resource monitoring: basic resource limits" {
    const allocator = std.testing.allocator;

    // Create a zr.toml with resource limits
    const config =
        \\[tasks.limited]
        \\cmd = "echo 'testing resource limits'"
        \\max_memory_mb = 100
        \\max_cpu_percent = 50
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "limited", "--list" }, tmp_dir);
    defer result.deinit();

    // Should parse without errors
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: CPU affinity configuration" {
    const allocator = std.testing.allocator;

    // Create a task with CPU affinity set
    const config =
        \\[tasks.affinity_test]
        \\cmd = "echo 'testing cpu affinity'"
        \\cpu_affinity = [0, 1]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"validate"}, tmp_dir);
    defer result.deinit();

    // Should validate successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: NUMA node preference" {
    const allocator = std.testing.allocator;

    // Create a task with NUMA node preference
    const config =
        \\[tasks.numa_task]
        \\cmd = "echo 'testing numa preference'"
        \\numa_node = 0
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"validate"}, tmp_dir);
    defer result.deinit();

    // Should validate successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: resource metrics collection" {
    const allocator = std.testing.allocator;

    // Create a simple task
    const config =
        \\[tasks.metrics_test]
        \\cmd = "echo 'collecting metrics'"
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "metrics_test" }, tmp_dir);
    defer result.deinit();

    // Task should complete successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: multiple tasks with different limits" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.low_mem]
        \\cmd = "echo 'low memory task'"
        \\max_memory_mb = 50
        \\
        \\[tasks.high_mem]
        \\cmd = "echo 'high memory task'"
        \\max_memory_mb = 500
        \\
        \\[tasks.cpu_limited]
        \\cmd = "echo 'cpu limited task'"
        \\max_cpu_percent = 25
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"list"}, tmp_dir);
    defer result.deinit();

    // Should list all tasks
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "low_mem") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "high_mem") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "cpu_limited") != null);
}

test "resource monitoring: invalid memory limit" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.invalid_mem]
        \\cmd = "echo 'test'"
        \\max_memory_mb = -1
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"validate"}, tmp_dir);
    defer result.deinit();

    // Should fail validation
    try std.testing.expect(result.exit_code != 0);
}

test "resource monitoring: invalid CPU percent" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.invalid_cpu]
        \\cmd = "echo 'test'"
        \\max_cpu_percent = 150
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"validate"}, tmp_dir);
    defer result.deinit();

    // Should fail validation (CPU percent > 100 is invalid)
    try std.testing.expect(result.exit_code != 0);
}

test "resource monitoring: timeout with resource limits" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.timeout_test]
        \\cmd = "sleep 10"
        \\timeout_ms = 100
        \\max_memory_mb = 100
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "timeout_test" }, tmp_dir);
    defer result.deinit();

    // Task should timeout (exit code 1)
    try std.testing.expect(result.exit_code != 0);
}

test "resource monitoring: parallel tasks with affinity" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.task1]
        \\cmd = "echo 'task 1'"
        \\cpu_affinity = [0]
        \\
        \\[tasks.task2]
        \\cmd = "echo 'task 2'"
        \\cpu_affinity = [1]
        \\deps = []
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "task2", "--jobs=2" }, tmp_dir);
    defer result.deinit();

    // Tasks should complete successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: resource limits with retry" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.retry_limited]
        \\cmd = "exit 1"
        \\max_retries = 2
        \\max_memory_mb = 100
        \\max_cpu_percent = 50
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "retry_limited", "--list" }, tmp_dir);
    defer result.deinit();

    // Should parse successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: zero memory limit" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.zero_mem]
        \\cmd = "echo 'test'"
        \\max_memory_mb = 0
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"validate"}, tmp_dir);
    defer result.deinit();

    // Zero means "no limit" - should be valid
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: empty CPU affinity array" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.no_affinity]
        \\cmd = "echo 'test'"
        \\cpu_affinity = []
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"validate"}, tmp_dir);
    defer result.deinit();

    // Empty affinity array should be valid (no affinity set)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "resource monitoring: large CPU affinity list" {
    const allocator = std.testing.allocator;

    const config =
        \\[tasks.many_cpus]
        \\cmd = "echo 'test'"
        \\cpu_affinity = [0, 1, 2, 3, 4, 5, 6, 7]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{"validate"}, tmp_dir);
    defer result.deinit();

    // Should validate successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}
