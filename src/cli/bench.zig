const std = @import("std");
const types = @import("../bench/types.zig");
const runner = @import("../bench/runner.zig");
const formatter = @import("../bench/formatter.zig");

const BenchmarkConfig = types.BenchmarkConfig;

/// Parse and execute the bench command.
pub fn cmdBench(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len == 0) {
        try printHelp();
        return 1;
    }

    // Check for help flag
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
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
                std.debug.print("Invalid iterations value: {s}\n", .{value});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--iterations") or std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Missing value for --iterations\n", .{});
                return 1;
            }
            config.iterations = std.fmt.parseInt(usize, args[i], 10) catch {
                std.debug.print("Invalid iterations value: {s}\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "--warmup=")) {
            const eq_idx = std.mem.indexOf(u8, arg, "=") orelse continue;
            const value = arg[eq_idx + 1 ..];
            config.warmup_runs = std.fmt.parseInt(usize, value, 10) catch {
                std.debug.print("Invalid warmup value: {s}\n", .{value});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Missing value for --warmup\n", .{});
                return 1;
            }
            config.warmup_runs = std.fmt.parseInt(usize, args[i], 10) catch {
                std.debug.print("Invalid warmup value: {s}\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            const eq_idx = std.mem.indexOf(u8, arg, "=") orelse continue;
            config.config_path = arg[eq_idx + 1 ..];
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Missing value for --config\n", .{});
                return 1;
            }
            config.config_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "--profile=") or std.mem.startsWith(u8, arg, "-p=")) {
            const eq_idx = std.mem.indexOf(u8, arg, "=") orelse continue;
            config.profile = arg[eq_idx + 1 ..];
        } else if (std.mem.eql(u8, arg, "--profile") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Missing value for --profile\n", .{});
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
            std.debug.print("Unknown format. Supported: text, json, csv\n", .{});
            return 1;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            return 1;
        }
    }

    // Run benchmark
    var stats = runner.runBenchmark(allocator, &config) catch |err| {
        std.debug.print("Benchmark failed: {}\n", .{err});
        return 1;
    };
    defer stats.deinit();

    // Print results
    var out_buf: [8192]u8 = undefined;
    const stdout_f = std.fs.File.stdout();
    var stdout_w = stdout_f.writer(&out_buf);
    switch (config.format) {
        .text => try formatter.printText(&stdout_w.interface, &stats),
        .json => try formatter.printJson(&stdout_w.interface, &stats),
        .csv => try formatter.printCsv(&stdout_w.interface, &stats),
    }
    try stdout_w.interface.flush();

    // Return error code if any runs failed
    if (stats.failed_runs > 0) {
        return 1;
    }

    return 0;
}

fn printHelp() !void {
    var buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var stderr_w = stderr_f.writer(&buf);
    defer stderr_w.interface.flush() catch {};
    try stderr_w.interface.print(
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
    const args = &[_][]const u8{"--help"};
    const exit_code = try cmdBench(allocator, args);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
