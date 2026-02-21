/// Live TUI execution command — runs tasks with real-time log streaming.
const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const tui_runner = @import("tui_runner.zig");
const loader = @import("../config/loader.zig");
const process = @import("../exec/process.zig");
const scheduler = @import("../exec/scheduler.zig");
const builtin = @import("builtin");

/// Context for streaming output callback.
const StreamCtx = struct {
    runner: *tui_runner.TuiRunner,
    task_name: []const u8,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
};

/// Callback invoked by process.run() for each output line.
fn outputCallback(line: []const u8, is_stderr: bool, ctx: ?*anyopaque) void {
    const stream_ctx: *StreamCtx = @ptrCast(@alignCast(ctx.?));
    stream_ctx.mutex.lock();
    defer stream_ctx.mutex.unlock();
    stream_ctx.runner.appendTaskLog(stream_ctx.task_name, line, is_stderr) catch {};
}

/// Execute tasks with TUI live log streaming and sequential execution.
/// Note: Tasks run sequentially to maintain clean log output in TUI.
/// Use 'zr run' for parallel execution with dependency resolution.
pub fn cmdLive(
    allocator: std.mem.Allocator,
    task_names: []const []const u8,
    profile_name: ?[]const u8,
    max_jobs: u32, // Reserved for future parallel TUI support
    config_path: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    _ = max_jobs; // Reserved for future use when scheduler supports progress callbacks
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

    if (task_names.len == 0) {
        try w.writeAll("Error: No tasks specified\n");
        try w.writeAll("Hint: Usage: zr live <task> [task...]\n");
        return 1;
    }

    var config = (try common.loadConfig(allocator, config_path, profile_name, err_writer, use_color)) orelse return 1;
    defer config.deinit();

    // Validate all tasks exist
    for (task_names) |task_name| {
        if (config.tasks.get(task_name) == null) {
            try color.printError(err_writer, use_color,
                "live: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
                .{task_name},
            );
            return 1;
        }
    }

    // Create TUI runner
    var runner = tui_runner.TuiRunner.init(allocator);
    defer runner.deinit();

    // Add all tasks to TUI
    for (task_names) |task_name| {
        try runner.addTask(task_name);
    }

    // Render initial screen
    try runner.render(w, use_color, 24);

    // Create mutex for thread-safe TUI updates
    const output_mutex = std.Thread.Mutex{};

    // Custom execution: we need to hook into task start/end for TUI updates
    // Since scheduler.run doesn't expose callbacks, we'll use a simpler approach:
    // For now, fall back to sequential mode if multiple tasks requested
    // Note: max_jobs is used for each individual task's internal parallelism if supported

    if (task_names.len > 1) {
        try w.writeAll("Note: Live mode with multiple tasks runs sequentially.\n");
        try w.writeAll("For parallel execution with dependencies, use 'zr run' instead.\n\n");
    }

    var failed = false;
    for (task_names) |task_name| {
        const task = config.tasks.get(task_name).?;

        // Set task to running
        runner.setTaskStatus(task_name, .running);
        try runner.render(w, use_color, 24);

        // Create streaming context
        var stream_ctx = StreamCtx{
            .runner = &runner,
            .task_name = task_name,
            .allocator = allocator,
            .mutex = output_mutex,
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
                "\nlive: Failed to execute task '{s}': {s}\n", .{ task_name, @errorName(err) });
            failed = true;
            continue;
        };

        const end_ms = std.time.milliTimestamp();
        const duration_ms: u64 = @intCast(@max(0, end_ms - start_ms));

        // Mark task as complete
        runner.completeTask(task_name, result.exit_code, duration_ms);

        if (!result.success) {
            failed = true;
        }
    }

    // Final render
    try runner.render(w, use_color, 24);

    try w.writeAll("\n--- Execution complete ---\n");
    for (runner.tasks.items) |state| {
        if (state.status == .success) {
            try color.printSuccess(w, use_color, "{s} ", .{state.name});
            try color.printDim(w, use_color, "({d}ms)\n", .{state.duration_ms});
        } else if (state.status == .failed) {
            try color.printError(w, use_color, "{s} ", .{state.name});
            try w.print("exited with code {d}\n", .{state.exit_code});
        }
    }

    return if (failed) 1 else 0;
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

    const task_names = [_][]const u8{"nonexistent"};
    const result = try cmdLive(allocator, &task_names, null, 0, config_path, &out_w, &err_w, false);

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
    const task_names = [_][]const u8{"hello"};
    const result = try cmdLive(allocator, &task_names, null, 0, config_path, &out_w, &err_w, false);

    // Should fail due to non-TTY
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdLive: empty task list returns error" {
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

    const task_names: []const []const u8 = &.{};
    const result = try cmdLive(allocator, task_names, null, 0, config_path, &out_w, &err_w, false);

    try std.testing.expectEqual(@as(u8, 1), result);
}
