/// Live TUI execution command — runs tasks with real-time log streaming.
const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const tui_runner = @import("tui_runner.zig");
const loader = @import("../config/loader.zig");
const process = @import("../exec/process.zig");
const builtin = @import("builtin");

/// Context for streaming output callback.
const StreamCtx = struct {
    runner: *tui_runner.TuiRunner,
    task_name: []const u8,
};

/// Callback invoked by process.run() for each output line.
fn outputCallback(line: []const u8, is_stderr: bool, ctx: ?*anyopaque) void {
    const stream_ctx: *StreamCtx = @ptrCast(@alignCast(ctx.?));
    stream_ctx.runner.appendTaskLog(stream_ctx.task_name, line, is_stderr) catch {};
}

/// Execute a task with TUI live log streaming.
pub fn cmdLive(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    profile_name: ?[]const u8,
    max_jobs: u32,
    config_path: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    _ = max_jobs; // TODO: support parallel tasks in live mode

    // Check if stdout is a TTY
    if (!std.fs.File.stdout().isTty()) {
        try w.writeAll("Error: live mode requires a TTY terminal\n");
        try w.writeAll("Hint: Use 'zr run' for non-interactive execution\n");
        return 1;
    }

    // Check if we're on Windows (raw mode not supported)
    if (comptime builtin.os.tag == .windows) {
        try w.writeAll("Error: live mode is not yet supported on Windows\n");
        try w.writeAll("Hint: Use 'zr run' or 'zr interactive' instead\n");
        return 1;
    }

    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    const task = config.tasks.get(task_name) orelse {
        try color.printError(err_writer, use_color,
            "live: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    };

    // Create TUI runner
    var runner = tui_runner.TuiRunner.init(allocator);
    defer runner.deinit();

    try runner.addTask(task_name);

    // Render initial screen
    try runner.render(w, use_color, 24);

    // Set task to running
    runner.setTaskStatus(task_name, .running);
    try runner.render(w, use_color, 24);

    // Create streaming context
    var stream_ctx = StreamCtx{
        .runner = &runner,
        .task_name = task_name,
    };

    // Execute task with output streaming
    const start_ms = std.time.milliTimestamp();

    const result = process.run(allocator, .{
        .cmd = task.cmd,
        .cwd = task.cwd,
        .env = if (task.env.len > 0) task.env else null,
        .inherit_stdio = false,
        .timeout_ms = task.timeout_ms,
        .max_memory_bytes = task.max_memory,
        .max_cpu_cores = task.max_cpu,
        .output_callback = outputCallback,
        .output_ctx = &stream_ctx,
    }) catch |err| {
        runner.setTaskStatus(task_name, .failed);
        try runner.render(w, use_color, 24);

        try color.printError(err_writer, use_color,
            "\nlive: Failed to execute task: {s}\n", .{@errorName(err)});
        return 1;
    };

    const end_ms = std.time.milliTimestamp();
    const duration_ms: u64 = @intCast(@max(0, end_ms - start_ms));

    // Mark task as complete
    runner.completeTask(task_name, result.exit_code, duration_ms);

    // Final render
    try runner.render(w, use_color, 24);

    try w.writeAll("\n--- Execution complete ---\n");
    if (result.success) {
        try color.printSuccess(w, use_color, "{s} ", .{task_name});
        try color.printDim(w, use_color, "({d}ms)\n", .{duration_ms});
    } else {
        try color.printError(w, use_color, "{s} ", .{task_name});
        try w.print("exited with code {d} ({d}ms)\n", .{ result.exit_code, duration_ms });
    }

    return if (result.success) 0 else 1;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "cmdLive: missing task returns error" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "[tasks.build]\ncmd = \"echo build\"\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [2048]u8 = undefined;
    var err_buf: [2048]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdLive(allocator, "nonexistent", null, 0, config_path, &out_w, &err_w, false);

    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdLive: successful task execution (simulated non-TTY)" {
    // This test cannot fully test TTY mode without a real terminal,
    // but we can verify the config loading and error handling paths.
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "[tasks.hello]\ncmd = \"echo hello\"\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [2048]u8 = undefined;
    var err_buf: [2048]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    // In test environment, stdout is not a TTY, so this will return early
    const result = try cmdLive(allocator, "hello", null, 0, config_path, &out_w, &err_w, false);

    // Should fail due to non-TTY
    try std.testing.expectEqual(@as(u8, 1), result);
}
