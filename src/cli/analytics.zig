const std = @import("std");
const types = @import("../analytics/types.zig");
const collector = @import("../analytics/collector.zig");
const html_gen = @import("../analytics/html.zig");
const json_gen = @import("../analytics/json.zig");
const platform = @import("../util/platform.zig");
const analytics_tui = @import("analytics_tui.zig");

pub fn cmdAnalytics(allocator: std.mem.Allocator, args: []const []const u8, global_json: bool, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    var json_output = global_json;
    var output_path: ?[]const u8 = null;
    var limit: ?usize = null;
    var no_open = false;
    var tui_mode = false;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--tui")) {
            tui_mode = true;
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "--format=json")) {
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
                try ew.print("✗ [Analytics]: --output requires a file path\n", .{});
                return 1;
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--limit") or std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("✗ [Analytics]: --limit requires a number\n", .{});
                return 1;
            }
            limit = std.fmt.parseInt(usize, args[i], 10) catch {
                try ew.print("✗ [Analytics]: invalid limit value: {s}\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w);
            return 0;
        } else {
            try ew.print("✗ [Analytics]: unknown flag: {s}\n", .{arg});
            try printHelp(w);
            return 1;
        }
    }

    // If TUI mode requested, delegate to TUI module
    if (tui_mode) {
        // Filter out --tui flag before passing to TUI module
        var filtered_args = std.ArrayList([]const u8){};
        defer filtered_args.deinit(allocator);

        for (args) |arg| {
            if (!std.mem.eql(u8, arg, "--tui")) {
                try filtered_args.append(allocator, arg);
            }
        }

        return analytics_tui.cmdAnalyticsTui(allocator, filtered_args.items, w, ew);
    }

    // Collect analytics data
    var report = collector.collectAnalytics(allocator, limit) catch |err| {
        try ew.print("✗ [Analytics]: failed to collect analytics: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer report.deinit();

    if (report.total_executions == 0) {
        try w.print("No execution history found. Run some tasks first with `zr run <task>`.\n", .{});
        return 0;
    }

    // Generate report
    const content = if (json_output)
        json_gen.generateJsonReport(allocator, &report) catch |err| {
            try ew.print("✗ [Analytics]: failed to generate JSON report: {s}\n", .{@errorName(err)});
            return 1;
        }
    else
        html_gen.generateHtmlReport(allocator, &report) catch |err| {
            try ew.print("✗ [Analytics]: failed to generate HTML report: {s}\n", .{@errorName(err)});
            return 1;
        };
    defer allocator.free(content);

    // Output or save
    if (output_path) |path| {
        // Write to file
        const file = std.fs.cwd().createFile(path, .{}) catch |err| {
            try ew.print("✗ [Analytics]: failed to create output file: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer file.close();

        file.writeAll(content) catch |err| {
            try ew.print("✗ [Analytics]: failed to write output file: {s}\n", .{@errorName(err)});
            return 1;
        };

        try w.print("✓ Report saved to {s}\n", .{path});

        // Open in browser if HTML (unless --no-open)
        if (!json_output and !no_open) {
            try openInBrowser(path, w);
        }
    } else if (json_output) {
        // Print JSON to stdout
        const stdout = std.fs.File.stdout();
        try stdout.writeAll(content);
    } else {
        // Get system temp directory
        const builtin = @import("builtin");
        const tmp_dir_path = switch (builtin.os.tag) {
            .windows => std.process.getEnvVarOwned(allocator, "TEMP") catch
                        std.process.getEnvVarOwned(allocator, "TMP") catch
                        try allocator.dupe(u8, "C:\\Windows\\Temp"),
            else => std.process.getEnvVarOwned(allocator, "TMPDIR") catch
                    try allocator.dupe(u8, "/tmp"),
        };
        defer allocator.free(tmp_dir_path);

        // Save to temp file and open in browser (platform-agnostic)
        const temp_filename = try std.fmt.allocPrint(allocator, "zr-analytics-{d}.html", .{std.time.timestamp()});
        defer allocator.free(temp_filename);

        const temp_path_for_write = try std.fs.path.join(allocator, &[_][]const u8{ tmp_dir_path, temp_filename });
        defer allocator.free(temp_path_for_write);

        const file = std.fs.cwd().createFile(temp_path_for_write, .{}) catch |err| {
            try ew.print("✗ [Analytics]: failed to create temporary file: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer file.close();

        file.writeAll(content) catch |err| {
            try ew.print("✗ [Analytics]: failed to write temporary file: {s}\n", .{@errorName(err)});
            return 1;
        };

        try w.print("✓ Report generated: {s}\n", .{temp_path_for_write});
        if (!no_open) {
            try openInBrowser(temp_path_for_write, w);
        }
    }

    return 0;
}

fn openInBrowser(path: []const u8, w: *std.Io.Writer) !void {
    const builtin = @import("builtin");

    const cmd = switch (builtin.os.tag) {
        .macos => "open",
        .linux => "xdg-open",
        .windows => "start",
        else => {
            try w.print("Note: Opening browser not supported on this platform. View the report at: {s}\n", .{path});
            return;
        },
    };

    var child = std.process.Child.init(&.{ cmd, path }, std.heap.page_allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    _ = child.spawnAndWait() catch {
        try w.print("Note: Failed to open browser automatically. View the report at: {s}\n", .{path});
        return;
    };

    try w.print("Opening report in browser...\n", .{});
}

fn printHelp(w: *std.Io.Writer) !void {
    try w.print(
        \\Usage: zr analytics [options]
        \\
        \\Generate build analysis reports from execution history.
        \\
        \\Options:
        \\  --tui               Launch interactive TUI dashboard
        \\  --json              Output JSON format instead of HTML
        \\  -o, --output <path> Save report to file (default: open in browser)
        \\  -n, --limit <N>     Analyze only the last N executions
        \\  --no-open           Do not open the report in browser
        \\  -h, --help          Show this help message
        \\
        \\Examples:
        \\  zr analytics                    # Generate HTML report and open in browser
        \\  zr analytics --tui              # Launch interactive TUI dashboard
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
    , .{});
}

test "cmdAnalytics help" {
    // Verifies that --help flag returns exit code 0
    // Help content is verified by integration tests
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const result = try cmdAnalytics(allocator, &.{"--help"}, false, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "cmdAnalytics writes help to writer when --help provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{"--help"};

    // This should FAIL until cmdAnalytics is refactored to accept writers
    const code = try cmdAnalytics(allocator, &args, false, &out_w.interface, &err_w.interface);

    // Help should exit with 0
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdAnalytics writes error to ew when unknown flag provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{"--unknown-flag"};

    // This should FAIL until cmdAnalytics is refactored to accept writers
    const code = try cmdAnalytics(allocator, &args, false, &out_w.interface, &err_w.interface);

    // Unknown flag should exit with 1
    try std.testing.expectEqual(@as(u8, 1), code);
}
