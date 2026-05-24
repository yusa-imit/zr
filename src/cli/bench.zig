const std = @import("std");
const types = @import("../bench/types.zig");
const runner = @import("../bench/runner.zig");
const formatter = @import("../bench/formatter.zig");

const BenchmarkConfig = types.BenchmarkConfig;

/// Parse and execute the bench command.
pub fn cmdBench(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    if (args.len == 0) {
        try printHelp(ew);
        return 1;
    }

    // Check for help flag
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(ew);
            return 0;
        }
    }

    var config = BenchmarkConfig{
        .task_name = args[0],
    };

    // Parse flags
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--iterations=") or std.mem.startsWith(u8, arg, "-n=")) {
            const eq_idx = std.mem.indexOf(u8, arg, "=") orelse continue;
            const value = arg[eq_idx + 1 ..];
            config.iterations = std.fmt.parseInt(usize, value, 10) catch {
                try ew.print("Invalid iterations value: {s}\n", .{value});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--iterations") or std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("Missing value for --iterations\n", .{});
                return 1;
            }
            config.iterations = std.fmt.parseInt(usize, args[i], 10) catch {
                try ew.print("Invalid iterations value: {s}\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "--warmup=")) {
            const eq_idx = std.mem.indexOf(u8, arg, "=") orelse continue;
            const value = arg[eq_idx + 1 ..];
            config.warmup_runs = std.fmt.parseInt(usize, value, 10) catch {
                try ew.print("Invalid warmup value: {s}\n", .{value});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("Missing value for --warmup\n", .{});
                return 1;
            }
            config.warmup_runs = std.fmt.parseInt(usize, args[i], 10) catch {
                try ew.print("Invalid warmup value: {s}\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            const eq_idx = std.mem.indexOf(u8, arg, "=") orelse continue;
            config.config_path = arg[eq_idx + 1 ..];
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("Missing value for --config\n", .{});
                return 1;
            }
            config.config_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "--profile=") or std.mem.startsWith(u8, arg, "-p=")) {
            const eq_idx = std.mem.indexOf(u8, arg, "=") orelse continue;
            config.profile = arg[eq_idx + 1 ..];
        } else if (std.mem.eql(u8, arg, "--profile") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("Missing value for --profile\n", .{});
                return 1;
            }
            config.profile = args[i];
        } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
            config.quiet = true;
        } else if (std.mem.eql(u8, arg, "--format=json")) {
            config.format = .json;
        } else if (std.mem.eql(u8, arg, "--format=csv")) {
            config.format = .csv;
        } else if (std.mem.eql(u8, arg, "--format=text")) {
            config.format = .text;
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            try ew.print("✗ [Bench]: unknown format\n\n  Hint: Supported formats: text, json, csv\n", .{});
            return 1;
        } else if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("✗ [Bench]: missing value for --format\n\n  Hint: Supported formats: text, json, csv\n", .{});
                return 1;
            }
            const fmt = args[i];
            if (std.mem.eql(u8, fmt, "json")) {
                config.format = .json;
            } else if (std.mem.eql(u8, fmt, "csv")) {
                config.format = .csv;
            } else if (std.mem.eql(u8, fmt, "text")) {
                config.format = .text;
            } else {
                try ew.print("✗ [Bench]: unknown format '{s}'\n\n  Hint: Supported formats: text, json, csv\n", .{fmt});
                return 1;
            }
        } else {
            try ew.print("✗ [Bench]: unknown argument: {s}\n", .{arg});
            return 1;
        }
    }

    // Run benchmark
    var stats = runner.runBenchmark(allocator, &config) catch |err| {
        try ew.print("✗ [Bench]: benchmark failed: {}\n", .{err});
        return 1;
    };
    defer stats.deinit();

    // Print results
    switch (config.format) {
        .text => try formatter.printText(w, &stats),
        .json => try formatter.printJson(w, &stats),
        .csv => try formatter.printCsv(w, &stats),
    }

    // Return error code if any runs failed
    if (stats.failed_runs > 0) {
        return 1;
    }

    return 0;
}

fn printHelp(ew: *std.Io.Writer) !void {
    try ew.print(
        \\Usage: zr bench <task> [options]
        \\
        \\Run a task multiple times and collect performance statistics.
        \\
        \\Options:
        \\  --iterations, -n <N>    Number of benchmark iterations (default: 10)
        \\  --warmup <N>            Number of warmup runs before benchmarking (default: 2)
        \\  --profile, -p <name>    Use a specific profile
        \\  --config <path>         Path to config file (default: zr.toml)
        \\  --quiet, -q             Suppress iteration progress output
        \\  --format <fmt>          Output format: text (default), json, csv
        \\  --help, -h              Show this help message
        \\
        \\Examples:
        \\  zr bench build                    Benchmark the 'build' task
        \\  zr bench test -n 20               Run 20 iterations
        \\  zr bench build --format=json      Output as JSON
        \\  zr bench test --warmup 5          Use 5 warmup runs
        \\
    , .{});
}

test "cmdBench help" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    const args = &[_][]const u8{"--help"};
    const exit_code = try cmdBench(allocator, args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "cmdBench writes help to writer when --help provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = &[_][]const u8{"--help"};

    // This should FAIL until cmdBench is refactored to accept writers
    const code = try cmdBench(allocator, args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdBench writes error to ew when unknown flag provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = &[_][]const u8{ "mytask", "--unknown-flag" };

    // This should FAIL until cmdBench is refactored to accept writers
    const code = try cmdBench(allocator, args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 1), code);
}
