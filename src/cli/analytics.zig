const std = @import("std");
const types = @import("../analytics/types.zig");
const collector = @import("../analytics/collector.zig");
const html_gen = @import("../analytics/html.zig");
const json_gen = @import("../analytics/json.zig");
const platform = @import("../util/platform.zig");

pub fn cmdAnalytics(allocator: std.mem.Allocator, args: []const []const u8, global_json: bool) !u8 {
    var json_output = global_json;
    var output_path: ?[]const u8 = null;
    var limit: ?usize = null;
    var no_open = false;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "--format=json")) {
            json_output = true;
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            // other --format values: ignore (default to HTML)
        } else if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i < args.len and std.mem.eql(u8, args[i], "json")) {
                json_output = true;
            }
        } else if (std.mem.eql(u8, arg, "--no-open")) {
            no_open = true;
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: --output requires a file path\n", .{});
                return 1;
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--limit") or std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: --limit requires a number\n", .{});
                return 1;
            }
            limit = std.fmt.parseInt(usize, args[i], 10) catch {
                std.debug.print("error: invalid limit value: {s}\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return 0;
        } else {
            std.debug.print("error: unknown flag: {s}\n", .{arg});
            try printHelp();
            return 1;
        }
    }

    // Collect analytics data
    var report = collector.collectAnalytics(allocator, limit) catch |err| {
        std.debug.print("error: failed to collect analytics: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer report.deinit();

    if (report.total_executions == 0) {
        std.debug.print("No execution history found. Run some tasks first with `zr run <task>`.\n", .{});
        return 0;
    }

    // Generate report
    const content = if (json_output)
        json_gen.generateJsonReport(allocator, &report) catch |err| {
            std.debug.print("error: failed to generate JSON report: {s}\n", .{@errorName(err)});
            return 1;
        }
    else
        html_gen.generateHtmlReport(allocator, &report) catch |err| {
            std.debug.print("error: failed to generate HTML report: {s}\n", .{@errorName(err)});
            return 1;
        };
    defer allocator.free(content);

    // Output or save
    if (output_path) |path| {
        // Write to file
        const file = std.fs.cwd().createFile(path, .{}) catch |err| {
            std.debug.print("error: failed to create output file: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer file.close();

        file.writeAll(content) catch |err| {
            std.debug.print("error: failed to write output file: {s}\n", .{@errorName(err)});
            return 1;
        };

        std.debug.print("✓ Report saved to {s}\n", .{path});

        // Open in browser if HTML (unless --no-open)
        if (!json_output and !no_open) {
            try openInBrowser(path);
        }
    } else if (json_output) {
        // Print JSON to stdout
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(content);
    } else {
        // Save to temp file and open in browser
        const temp_path = try std.fmt.allocPrint(allocator, "/tmp/zr-analytics-{d}.html", .{std.time.timestamp()});
        defer allocator.free(temp_path);

        const file = std.fs.cwd().createFile(temp_path, .{}) catch |err| {
            std.debug.print("error: failed to create temporary file: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer file.close();

        file.writeAll(content) catch |err| {
            std.debug.print("error: failed to write temporary file: {s}\n", .{@errorName(err)});
            return 1;
        };

        std.debug.print("✓ Report generated: {s}\n", .{temp_path});
        if (!no_open) {
            try openInBrowser(temp_path);
        }
    }

    return 0;
}

fn openInBrowser(path: []const u8) !void {
    const builtin = @import("builtin");

    const cmd = switch (builtin.os.tag) {
        .macos => "open",
        .linux => "xdg-open",
        .windows => "start",
        else => {
            std.debug.print("Note: Opening browser not supported on this platform. View the report at: {s}\n", .{path});
            return;
        },
    };

    var child = std.process.Child.init(&.{ cmd, path }, std.heap.page_allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    _ = child.spawnAndWait() catch {
        std.debug.print("Note: Failed to open browser automatically. View the report at: {s}\n", .{path});
        return;
    };

    std.debug.print("Opening report in browser...\n", .{});
}

fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\Usage: zr analytics [options]
        \\
        \\Generate build analysis reports from execution history.
        \\
        \\Options:
        \\  --json              Output JSON format instead of HTML
        \\  -o, --output <path> Save report to file (default: open in browser)
        \\  -n, --limit <N>     Analyze only the last N executions
        \\  --no-open           Do not open the report in browser
        \\  -h, --help          Show this help message
        \\
        \\Examples:
        \\  zr analytics                    # Generate HTML report and open in browser
        \\  zr analytics --json             # Output JSON to stdout
        \\  zr analytics -o report.html     # Save HTML to file
        \\  zr analytics --limit 100        # Analyze last 100 executions only
        \\
        \\Report Contents:
        \\  - Task execution time trends
        \\  - Cache hit rates (overall and per-task)
        \\  - Failure pattern analysis
        \\  - Critical path identification
        \\  - Parallelization efficiency metrics
        \\
    );
}

test "cmdAnalytics help" {
    const result = try cmdAnalytics(std.testing.allocator, &.{"--help"}, false);
    try std.testing.expectEqual(@as(u8, 0), result);
}
