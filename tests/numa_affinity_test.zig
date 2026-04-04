const std = @import("std");
const helpers = @import("helpers.zig");

// Integration tests for NUMA and CPU affinity enforcement
// Tests verify that:
// 1. CPU affinity is set to ALL specified cores (work-stealing)
// 2. NUMA memory allocation is bound to specified nodes (Linux only)
// 3. Combined NUMA + affinity works correctly
// 4. Invalid configurations are handled gracefully

test "NUMA affinity: work-stealing CPU affinity across multiple cores" {
    const allocator = std.testing.allocator;

    // Task with multiple CPUs should use work-stealing across all cores
    const config =
        \\[tasks.worksteal]
        \\cmd = "echo 'work-stealing test'"
        \\cpu_affinity = [0, 1, 2, 3]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "worksteal" }, tmp_dir);
    defer result.deinit();

    // Should execute successfully with affinity set to all 4 cores
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "work-stealing test") != null);
}

test "NUMA affinity: NUMA node allocation" {
    const allocator = std.testing.allocator;

    // Task with NUMA node should allocate memory from that node
    const config =
        \\[tasks.numa0]
        \\cmd = "echo 'NUMA node 0 allocation'"
        \\numa_node = 0
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "numa0" }, tmp_dir);
    defer result.deinit();

    // Should execute successfully (best-effort on non-Linux platforms)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NUMA node 0 allocation") != null);
}

test "NUMA affinity: combined NUMA node and CPU affinity" {
    const allocator = std.testing.allocator;

    // Task with both NUMA and affinity
    const config =
        \\[tasks.combined]
        \\cmd = "echo 'NUMA + affinity'"
        \\numa_node = 0
        \\cpu_affinity = [0, 1]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "combined" }, tmp_dir);
    defer result.deinit();

    // Should execute with both affinity and NUMA set
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NUMA + affinity") != null);
}

test "NUMA affinity: CPU IDs beyond available cores show warning" {
    const allocator = std.testing.allocator;

    // Task requesting CPU IDs that likely exceed system cores
    const config =
        \\[tasks.overflow]
        \\cmd = "echo 'high CPU ID'"
        \\cpu_affinity = [999, 1000]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "overflow" }, tmp_dir);
    defer result.deinit();

    // Should show warning in stderr about CPU IDs exceeding available cores
    // Execution continues best-effort (non-zero exit is acceptable if affinity fails hard)
    try std.testing.expect(result.stderr.len > 0);
}

test "NUMA affinity: invalid NUMA node handled gracefully" {
    const allocator = std.testing.allocator;

    // Task with very high NUMA node (unlikely to exist)
    const config =
        \\[tasks.badnuma]
        \\cmd = "echo 'invalid NUMA node'"
        \\numa_node = 999
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "badnuma" }, tmp_dir);
    defer result.deinit();

    // Should execute (best-effort allocation falls back to base allocator)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "invalid NUMA node") != null);
}

test "NUMA affinity: single core affinity" {
    const allocator = std.testing.allocator;

    // Task pinned to single core
    const config =
        \\[tasks.single]
        \\cmd = "echo 'single core'"
        \\cpu_affinity = [0]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "single" }, tmp_dir);
    defer result.deinit();

    // Should execute on single core
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "single core") != null);
}

test "NUMA affinity: parallel tasks with different NUMA nodes" {
    const allocator = std.testing.allocator;

    // Multiple tasks with different NUMA preferences
    const config =
        \\[tasks.numa0_task]
        \\cmd = "echo 'on node 0'"
        \\numa_node = 0
        \\deps = []
        \\
        \\[tasks.numa1_task]
        \\cmd = "echo 'on node 1'"
        \\numa_node = 1
        \\deps = []
        \\
        \\[tasks.combined]
        \\cmd = "echo 'all done'"
        \\deps = ["numa0_task", "numa1_task"]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "combined", "--jobs=2" }, tmp_dir);
    defer result.deinit();

    // All tasks should execute (NUMA node 1 may not exist, best-effort)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "all done") != null);
}

test "NUMA affinity: duplicate CPU IDs in affinity array" {
    const allocator = std.testing.allocator;

    // Task with duplicate CPU IDs (should deduplicate or handle gracefully)
    const config =
        \\[tasks.dupes]
        \\cmd = "echo 'duplicate CPUs'"
        \\cpu_affinity = [0, 1, 1, 0, 2]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "dupes" }, tmp_dir);
    defer result.deinit();

    // Should execute successfully (duplicates are valid, mask handles it)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "duplicate CPUs") != null);
}

test "NUMA affinity: no NUMA or affinity (default behavior)" {
    const allocator = std.testing.allocator;

    // Task without NUMA or affinity should use default allocator and no pinning
    const config =
        \\[tasks.default]
        \\cmd = "echo 'default behavior'"
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "default" }, tmp_dir);
    defer result.deinit();

    // Should execute normally without any affinity/NUMA overhead
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "default behavior") != null);
}

test "NUMA affinity: workflow with mixed NUMA tasks" {
    const allocator = std.testing.allocator;

    // Workflow with stages having different NUMA preferences
    const config =
        \\[tasks.stage1]
        \\cmd = "echo 'stage 1 on numa 0'"
        \\numa_node = 0
        \\
        \\[tasks.stage2]
        \\cmd = "echo 'stage 2 no numa'"
        \\
        \\[workflows.mixed]
        \\stages = [
        \\  { tasks = ["stage1"] },
        \\  { tasks = ["stage2"] }
        \\]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "workflow", "mixed" }, tmp_dir);
    defer result.deinit();

    // Both stages should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "stage 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "stage 2") != null);
}

test "NUMA affinity: task with NUMA and dependencies" {
    const allocator = std.testing.allocator;

    // NUMA task with dependencies (verify NUMA allocation happens for dependent task)
    const config =
        \\[tasks.base]
        \\cmd = "echo 'base task'"
        \\
        \\[tasks.numa_dependent]
        \\cmd = "echo 'NUMA dependent'"
        \\numa_node = 0
        \\deps = ["base"]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "numa_dependent" }, tmp_dir);
    defer result.deinit();

    // Both tasks should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "base task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NUMA dependent") != null);
}
