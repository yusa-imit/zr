/// Interactive task execution with cancel/retry controls.
/// Shows live task status and allows keyboard control during execution.
const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const run_cmd = @import("run.zig");
const control = @import("../exec/control.zig");
const color = @import("../output/color.zig");

const IS_POSIX = builtin.os.tag != .windows;

// ---------------------------------------------------------------------------
// Terminal helpers
// ---------------------------------------------------------------------------

fn enterRawMode() !if (IS_POSIX) std.posix.termios else void {
    if (comptime !IS_POSIX) return;

    const stdin = std.fs.File.stdin();
    const original = try std.posix.tcgetattr(stdin.handle);
    var raw = original;

    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0; // Non-blocking read
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 100ms timeout

    try std.posix.tcsetattr(stdin.handle, .NOW, raw);
    return original;
}

fn leaveRawMode(original: if (IS_POSIX) std.posix.termios else void) void {
    if (comptime !IS_POSIX) return;
    std.posix.tcsetattr(std.fs.File.stdin().handle, .NOW, original) catch {};
}

fn readByte() ?u8 {
    const stdin = std.fs.File.stdin();
    var b: [1]u8 = undefined;
    const n = stdin.read(&b) catch return null;
    if (n == 0) return null;
    return b[0];
}

// ---------------------------------------------------------------------------
// Control panel rendering
// ---------------------------------------------------------------------------

fn drawControlPanel(
    w: *std.Io.Writer,
    task_name: []const u8,
    ctrl: *control.TaskControl,
    use_color: bool,
) !void {
    // Clear screen and move to top
    try w.writeAll("\x1b[2J\x1b[H");

    if (use_color) try w.writeAll(color.Code.bold);
    try w.print("Running: {s}\n\n", .{task_name});
    if (use_color) try w.writeAll(color.Code.reset);

    try w.writeAll("Controls:\n");
    try w.writeAll("  [");
    if (use_color) try w.writeAll(color.Code.bright_cyan);
    try w.writeAll("c");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("] Cancel task\n");

    try w.writeAll("  [");
    if (use_color) try w.writeAll(color.Code.bright_cyan);
    try w.writeAll("p");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("] Pause task\n");

    try w.writeAll("  [");
    if (use_color) try w.writeAll(color.Code.bright_cyan);
    try w.writeAll("r");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("] Resume task\n\n");

    const pid = ctrl.getPid();
    if (pid != 0) {
        try w.print("Process ID: {d}\n", .{pid});
    }

    if (ctrl.isCancelRequested()) {
        if (use_color) try w.writeAll(color.Code.bright_red);
        try w.writeAll("Status: Cancelling...\n");
        if (use_color) try w.writeAll(color.Code.reset);
    } else if (ctrl.isPauseRequested()) {
        if (use_color) try w.writeAll(color.Code.bright_yellow);
        try w.writeAll("Status: Pausing...\n");
        if (use_color) try w.writeAll(color.Code.reset);
    } else if (ctrl.isResumeRequested()) {
        if (use_color) try w.writeAll(color.Code.bright_green);
        try w.writeAll("Status: Resuming...\n");
        if (use_color) try w.writeAll(color.Code.reset);
    } else {
        if (use_color) try w.writeAll(color.Code.bright_green);
        try w.writeAll("Status: Running\n");
        if (use_color) try w.writeAll(color.Code.reset);
    }

    try w.writeAll("\n--- Task Output Below ---\n\n");
}

// ---------------------------------------------------------------------------
// Keyboard input handler thread
// ---------------------------------------------------------------------------

const InputCtx = struct {
    ctrl: *control.TaskControl,
    original_termios: if (IS_POSIX) std.posix.termios else void,
    running: *std.atomic.Value(bool),
};

fn inputHandler(ctx: InputCtx) void {
    while (ctx.running.load(.acquire)) {
        const byte = readByte() orelse {
            std.Thread.sleep(50 * std.time.ns_per_ms);
            continue;
        };

        switch (byte) {
            'c', 'C' => ctx.ctrl.requestCancel(),
            'p', 'P' => ctx.ctrl.requestPause(),
            'r', 'R' => ctx.ctrl.requestResume(),
            'q', 'Q' => ctx.ctrl.requestCancel(), // Quit = cancel
            else => {},
        }
    }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn cmdInteractiveRun(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (comptime !IS_POSIX) {
        // Fall back to normal run on Windows
        return run_cmd.cmdRun(
            allocator,
            task_name,
            null,
            false,
            0,
            config_path,
            false,
            false, // monitor
            w,
            ew,
            use_color,
            null, // task_control
        );
    }

    const is_tty = std.fs.File.stdout().isTty();
    if (!is_tty) {
        // Fall back to normal run in non-TTY environments
        return run_cmd.cmdRun(
            allocator,
            task_name,
            null,
            false,
            0,
            config_path,
            false,
            false, // monitor
            w,
            ew,
            use_color,
            null,
        );
    }

    // Create control handle
    var ctrl = try control.TaskControl.init(allocator, task_name);
    defer ctrl.deinit();

    // Enter raw mode
    const original_termios = enterRawMode() catch {
        // Fall back to normal run if raw mode fails
        return run_cmd.cmdRun(
            allocator,
            task_name,
            null,
            false,
            0,
            config_path,
            false,
            false, // monitor
            w,
            ew,
            use_color,
            null,
        );
    };
    defer leaveRawMode(original_termios);

    // Draw initial control panel
    try drawControlPanel(w, task_name, ctrl, use_color);

    // Start keyboard input handler thread
    var running = std.atomic.Value(bool).init(true);
    const input_ctx = InputCtx{
        .ctrl = ctrl,
        .original_termios = original_termios,
        .running = &running,
    };
    const input_thread = try std.Thread.spawn(.{}, inputHandler, .{input_ctx});

    // Run task (this will block until task completes or is cancelled)
    const result = run_cmd.cmdRun(
        allocator,
        task_name,
        null,
        false,
        0,
        config_path,
        false,
        false, // monitor
        w,
        ew,
        use_color,
        ctrl,
    ) catch |err| {
        running.store(false, .release);
        input_thread.join();
        return err;
    };

    // Stop input handler
    running.store(false, .release);
    input_thread.join();

    // Mark task as finished
    ctrl.markFinished();

    // Restore normal terminal
    leaveRawMode(original_termios);

    // Show result
    try w.writeAll("\n\n");
    if (result == 0) {
        if (use_color) try w.writeAll(color.Code.bright_green);
        try w.writeAll("✓ Task completed successfully\n");
        if (use_color) try w.writeAll(color.Code.reset);
    } else {
        if (use_color) try w.writeAll(color.Code.bright_red);
        try w.print("✗ Task failed with exit code {d}\n", .{result});
        if (use_color) try w.writeAll(color.Code.reset);
    }

    // Ask if user wants to retry
    if (result != 0) {
        try w.writeAll("\nRetry? [y/N]: ");
        // Re-enter raw mode for single key read
        _ = enterRawMode() catch return result;
        const retry_byte = readByte();
        leaveRawMode(original_termios);

        if (retry_byte) |byte| {
            if (byte == 'y' or byte == 'Y') {
                try w.writeAll("\n\nRetrying...\n\n");
                return cmdInteractiveRun(
                    allocator,
                    task_name,
                    config_path,
                    w,
                    ew,
                    use_color,
                );
            }
        }
    }

    return result;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "cmdInteractiveRun: basic functionality" {
    // Note: Cannot fully test TTY interaction in automated tests.
    // This test just ensures the module compiles and basic types are correct.
    const allocator = std.testing.allocator;

    var ctrl = try control.TaskControl.init(allocator, "test-task");
    defer ctrl.deinit();

    try std.testing.expectEqualStrings("test-task", ctrl.task_name);
}
