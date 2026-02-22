const std = @import("std");
const types = @import("types.zig");
const config = @import("../config/loader.zig");
const common = @import("../cli/common.zig");
const exec = @import("../exec/scheduler.zig");

const BenchmarkRun = types.BenchmarkRun;
const BenchmarkStats = types.BenchmarkStats;
const BenchmarkConfig = types.BenchmarkConfig;

/// Run a task multiple times and collect statistics.
pub fn runBenchmark(
    allocator: std.mem.Allocator,
    bench_config: *const BenchmarkConfig,
) !BenchmarkStats {
    // Load configuration with profile support
    const cfg_path = bench_config.config_path orelse "zr.toml";

    // Get stderr writer for common.loadConfig error reporting
    var err_buf: [8192]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_writer = stderr_file.writer(&err_buf);

    var cfg = (try common.loadConfig(allocator, cfg_path, bench_config.profile, &err_writer.interface, false)) orelse {
        std.debug.print("Failed to load configuration from {s}\n", .{cfg_path});
        return error.ConfigLoadFailed;
    };
    defer cfg.deinit();

    // Verify the task exists
    if (cfg.tasks.get(bench_config.task_name) == null) {
        std.debug.print("Task '{s}' not found in configuration\n", .{bench_config.task_name});
        return error.TaskNotFound;
    }

    var runs_list = std.ArrayList(BenchmarkRun){};
    defer runs_list.deinit(allocator);

    var successful: usize = 0;
    var failed: usize = 0;

    // Warmup runs
    if (!bench_config.quiet) {
        std.debug.print("Running {d} warmup iterations...\n", .{bench_config.warmup_runs});
    }
    var i: usize = 0;
    while (i < bench_config.warmup_runs) : (i += 1) {
        _ = try runSingleIteration(allocator, &cfg, bench_config.task_name, bench_config.profile, true);
    }

    // Actual benchmark runs
    if (!bench_config.quiet) {
        std.debug.print("Running {d} benchmark iterations...\n", .{bench_config.iterations});
    }
    i = 0;
    while (i < bench_config.iterations) : (i += 1) {
        if (!bench_config.quiet) {
            std.debug.print("\rIteration {d}/{d}...", .{ i + 1, bench_config.iterations });
        }

        const run = try runSingleIteration(allocator, &cfg, bench_config.task_name, bench_config.profile, bench_config.quiet);
        try runs_list.append(allocator, run);

        if (run.exit_code == 0) {
            successful += 1;
        } else {
            failed += 1;
        }
    }
    if (!bench_config.quiet) {
        std.debug.print("\n", .{});
    }

    // Calculate statistics
    const runs_slice = try allocator.alloc(BenchmarkRun, runs_list.items.len);
    @memcpy(runs_slice, runs_list.items);

    return calculateStats(allocator, runs_slice, successful, failed);
}

/// Run a single iteration of the task.
fn runSingleIteration(
    allocator: std.mem.Allocator,
    cfg: *config.Config,
    task_name: []const u8,
    profile: ?[]const u8,
    quiet: bool,
) !BenchmarkRun {
    // Profile is already applied in runBenchmark via common.loadConfig
    _ = profile;

    const start_time = std.time.nanoTimestamp();

    const task_names = &[_][]const u8{task_name};

    const result = try exec.run(
        allocator,
        cfg,
        task_names,
        .{
            .max_jobs = 1,
            .monitor = false,
            .use_color = false,
            .task_control = null,
            // In quiet mode, don't inherit stdio to suppress task output
            .inherit_stdio = !quiet,
        },
    );

    const end_time = std.time.nanoTimestamp();
    const duration: u64 = @intCast(end_time - start_time);

    // Determine exit code from results
    var exit_code: u8 = 0;
    for (result.results.items) |r| {
        if (r.exit_code != 0) {
            exit_code = r.exit_code;
            break;
        }
    }

    // Clean up results
    var sched_result = result;
    sched_result.deinit(allocator);

    return BenchmarkRun{
        .duration_ns = duration,
        .exit_code = exit_code,
        .timestamp = std.time.timestamp(),
    };
}

/// Calculate statistical summary from runs.
fn calculateStats(
    allocator: std.mem.Allocator,
    runs: []const BenchmarkRun,
    successful: usize,
    failed: usize,
) !BenchmarkStats {
    if (runs.len == 0) {
        return BenchmarkStats.init(allocator);
    }

    // Calculate mean
    var sum: u64 = 0;
    var min: u64 = runs[0].duration_ns;
    var max: u64 = runs[0].duration_ns;

    for (runs) |run| {
        sum += run.duration_ns;
        if (run.duration_ns < min) min = run.duration_ns;
        if (run.duration_ns > max) max = run.duration_ns;
    }

    const mean = sum / runs.len;

    // Calculate standard deviation
    var variance_sum: u64 = 0;
    for (runs) |run| {
        const diff: i64 = @as(i64, @intCast(run.duration_ns)) - @as(i64, @intCast(mean));
        const diff_u: u64 = @intCast(@abs(diff));
        variance_sum += diff_u * diff_u;
    }
    const variance = variance_sum / runs.len;
    const std_dev = @as(u64, @intFromFloat(@sqrt(@as(f64, @floatFromInt(variance)))));

    // Calculate median (sort a copy)
    const sorted_durations = try allocator.alloc(u64, runs.len);
    defer allocator.free(sorted_durations);

    for (runs, 0..) |run, i| {
        sorted_durations[i] = run.duration_ns;
    }
    std.mem.sort(u64, sorted_durations, {}, comptime std.sort.asc(u64));

    const median = if (sorted_durations.len % 2 == 0)
        (sorted_durations[sorted_durations.len / 2 - 1] + sorted_durations[sorted_durations.len / 2]) / 2
    else
        sorted_durations[sorted_durations.len / 2];

    return BenchmarkStats{
        .mean_ns = mean,
        .median_ns = median,
        .min_ns = min,
        .max_ns = max,
        .std_dev_ns = std_dev,
        .runs = runs,
        .total_runs = runs.len,
        .successful_runs = successful,
        .failed_runs = failed,
        .allocator = allocator,
    };
}

test "calculateStats basic" {
    const allocator = std.testing.allocator;

    const runs = try allocator.alloc(BenchmarkRun, 5);
    defer allocator.free(runs);

    runs[0] = .{ .duration_ns = 100, .exit_code = 0, .timestamp = 0 };
    runs[1] = .{ .duration_ns = 200, .exit_code = 0, .timestamp = 0 };
    runs[2] = .{ .duration_ns = 150, .exit_code = 0, .timestamp = 0 };
    runs[3] = .{ .duration_ns = 180, .exit_code = 0, .timestamp = 0 };
    runs[4] = .{ .duration_ns = 120, .exit_code = 0, .timestamp = 0 };

    var stats = try calculateStats(allocator, runs, 5, 0);
    defer stats.deinit();

    try std.testing.expectEqual(@as(usize, 5), stats.total_runs);
    try std.testing.expectEqual(@as(usize, 5), stats.successful_runs);
    try std.testing.expectEqual(@as(usize, 0), stats.failed_runs);
    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 200), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 150), stats.mean_ns); // (100+200+150+180+120)/5 = 750/5 = 150
    try std.testing.expectEqual(@as(u64, 150), stats.median_ns); // sorted: [100,120,150,180,200]
}

test "calculateStats empty runs" {
    const allocator = std.testing.allocator;

    const runs = try allocator.alloc(BenchmarkRun, 0);
    defer allocator.free(runs);

    var stats = try calculateStats(allocator, runs, 0, 0);
    defer stats.deinit();

    try std.testing.expectEqual(@as(usize, 0), stats.total_runs);
}
