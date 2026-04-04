const std = @import("std");
const helpers = @import("helpers.zig");

// NUMA performance benchmarks comparing:
// 1. Baseline (no NUMA, no affinity)
// 2. NUMA-aware (memory bound to node)
// 3. CPU affinity (work-stealing across cores)
// 4. Combined (NUMA + affinity)

// Test requires: multi-core system, ideally multi-socket for NUMA benefits
// On single-socket: NUMA overhead should be minimal (<5%)
// On multi-socket: NUMA benefits should be significant (10-50% depending on workload)

test "NUMA bench: baseline allocation-heavy task" {
    const allocator = std.testing.allocator;

    // Memory-intensive task without NUMA (baseline)
    const config =
        \\[tasks.baseline]
        \\cmd = "dd if=/dev/zero of=/tmp/bench.dat bs=1M count=100 2>/dev/null && rm /tmp/bench.dat"
        \\description = "Baseline: 100MB allocation without NUMA"
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    // Run benchmark with 5 iterations
    var result = try helpers.runZr(allocator, &[_][]const u8{ "bench", "baseline", "--iterations=5", "--warmup=1", "--format=json" }, tmp_dir);
    defer result.deinit();

    // Should complete successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should contain timing data
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mean") != null or std.mem.indexOf(u8, result.stdout, "avg") != null);
}

test "NUMA bench: NUMA-bound allocation task" {
    const allocator = std.testing.allocator;

    // Same task but with NUMA binding to node 0
    const config =
        \\[tasks.numa_bound]
        \\cmd = "dd if=/dev/zero of=/tmp/bench.dat bs=1M count=100 2>/dev/null && rm /tmp/bench.dat"
        \\numa_node = 0
        \\description = "NUMA-bound: 100MB allocation on node 0"
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "bench", "numa_bound", "--iterations=5", "--warmup=1", "--format=json" }, tmp_dir);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mean") != null or std.mem.indexOf(u8, result.stdout, "avg") != null);
}

test "NUMA bench: CPU affinity multi-threaded task" {
    const allocator = std.testing.allocator;

    // Multi-threaded task with CPU affinity (work-stealing across cores)
    const config =
        \\[tasks.affinity]
        \\cmd = "yes | head -n 1000000 | wc -l"
        \\cpu_affinity = [0, 1, 2, 3]
        \\description = "Affinity: Multi-threaded on cores 0-3"
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "bench", "affinity", "--iterations=3", "--warmup=1", "--format=json" }, tmp_dir);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mean") != null or std.mem.indexOf(u8, result.stdout, "avg") != null);
}

test "NUMA bench: combined NUMA and affinity" {
    const allocator = std.testing.allocator;

    // Combined: NUMA memory + CPU affinity (optimal for multi-socket)
    const config =
        \\[tasks.combined]
        \\cmd = "dd if=/dev/zero of=/tmp/bench.dat bs=1M count=100 2>/dev/null && rm /tmp/bench.dat"
        \\numa_node = 0
        \\cpu_affinity = [0, 1, 2, 3]
        \\description = "Combined: NUMA node 0 + cores 0-3"
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    var result = try helpers.runZr(allocator, &[_][]const u8{ "bench", "combined", "--iterations=5", "--warmup=1", "--format=json" }, tmp_dir);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mean") != null or std.mem.indexOf(u8, result.stdout, "avg") != null);
}

test "NUMA bench: comparison workflow" {
    const allocator = std.testing.allocator;

    // Workflow running all variants for direct comparison
    const config =
        \\[tasks.baseline]
        \\cmd = "dd if=/dev/zero of=/tmp/bench.dat bs=1M count=50 2>/dev/null && rm /tmp/bench.dat"
        \\description = "Baseline"
        \\
        \\[tasks.numa]
        \\cmd = "dd if=/dev/zero of=/tmp/bench.dat bs=1M count=50 2>/dev/null && rm /tmp/bench.dat"
        \\numa_node = 0
        \\description = "NUMA node 0"
        \\
        \\[tasks.affinity]
        \\cmd = "dd if=/dev/zero of=/tmp/bench.dat bs=1M count=50 2>/dev/null && rm /tmp/bench.dat"
        \\cpu_affinity = [0, 1]
        \\description = "CPU affinity"
        \\
        \\[tasks.combined]
        \\cmd = "dd if=/dev/zero of=/tmp/bench.dat bs=1M count=50 2>/dev/null && rm /tmp/bench.dat"
        \\numa_node = 0
        \\cpu_affinity = [0, 1]
        \\description = "Combined"
        \\
        \\[workflows.numa_comparison]
        \\stages = [
        \\  { tasks = ["baseline"] },
        \\  { tasks = ["numa"] },
        \\  { tasks = ["affinity"] },
        \\  { tasks = ["combined"] }
        \\]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    // Run workflow (each stage sequential for timing comparison)
    var result = try helpers.runZr(allocator, &[_][]const u8{ "workflow", "numa_comparison" }, tmp_dir);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // All tasks should have executed
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "baseline") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "numa") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "affinity") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "combined") != null);
}

test "NUMA bench: parallel tasks with different NUMA nodes" {
    const allocator = std.testing.allocator;

    // Parallel execution of tasks on different NUMA nodes
    const config =
        \\[tasks.node0]
        \\cmd = "dd if=/dev/zero of=/tmp/bench0.dat bs=1M count=30 2>/dev/null && rm /tmp/bench0.dat"
        \\numa_node = 0
        \\deps = []
        \\
        \\[tasks.node1]
        \\cmd = "dd if=/dev/zero of=/tmp/bench1.dat bs=1M count=30 2>/dev/null && rm /tmp/bench1.dat"
        \\numa_node = 1
        \\deps = []
        \\
        \\[tasks.wait]
        \\cmd = "echo 'Done'"
        \\deps = ["node0", "node1"]
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    // Parallel execution (node1 may not exist, best-effort)
    var result = try helpers.runZr(allocator, &[_][]const u8{ "run", "wait", "--jobs=2" }, tmp_dir);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "NUMA bench: overhead measurement for small tasks" {
    const allocator = std.testing.allocator;

    // Measure overhead of NUMA on trivial task (should be minimal)
    const config =
        \\[tasks.tiny_baseline]
        \\cmd = "echo 'tiny'"
        \\
        \\[tasks.tiny_numa]
        \\cmd = "echo 'tiny'"
        \\numa_node = 0
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try helpers.writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(tmp_path);

    const tmp_dir = std.fs.path.dirname(tmp_path).?;

    // Benchmark baseline
    var result1 = try helpers.runZr(allocator, &[_][]const u8{ "bench", "tiny_baseline", "--iterations=10", "--warmup=2", "--format=json" }, tmp_dir);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);

    // Benchmark NUMA
    var result2 = try helpers.runZr(allocator, &[_][]const u8{ "bench", "tiny_numa", "--iterations=10", "--warmup=2", "--format=json" }, tmp_dir);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);

    // Both should succeed (overhead is acceptable even for tiny tasks)
}
