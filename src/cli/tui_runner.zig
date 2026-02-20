/// TUI live execution — real-time log streaming for running tasks.
///
/// When tasks execute, this module captures their stdout/stderr and displays
/// them in an interactive TUI with status indicators, progress tracking,
/// and scrollable log views.
const std = @import("std");
const builtin = @import("builtin");
const color = @import("../output/color.zig");

const IS_POSIX = builtin.os.tag != .windows;

/// Maximum lines to buffer per task before discarding old lines.
const MAX_LOG_LINES = 1000;

/// Status of a single task in the execution.
pub const TaskStatus = enum {
    pending,
    running,
    success,
    failed,
    skipped,
};

/// Log entry for a single line of output.
const LogLine = struct {
    text: []const u8, // owned
    is_stderr: bool,
};

/// Runtime state for a single task.
pub const TaskState = struct {
    name: []const u8, // borrowed from config
    status: TaskStatus,
    exit_code: u8,
    duration_ms: u64,
    logs: std.ArrayListUnmanaged(LogLine),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) TaskState {
        return .{
            .name = name,
            .status = .pending,
            .exit_code = 0,
            .duration_ms = 0,
            .logs = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TaskState) void {
        for (self.logs.items) |line| {
            self.allocator.free(line.text);
        }
        self.logs.deinit(self.allocator);
    }

    /// Append a log line; if buffer exceeds MAX_LOG_LINES, discard oldest.
    pub fn appendLog(self: *TaskState, text: []const u8, is_stderr: bool) !void {
        const owned = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned);

        if (self.logs.items.len >= MAX_LOG_LINES) {
            // Discard oldest line.
            const old = self.logs.orderedRemove(0);
            self.allocator.free(old.text);
        }

        try self.logs.append(self.allocator, .{ .text = owned, .is_stderr = is_stderr });
    }
};

/// TUI runner state — manages multiple tasks and their logs.
pub const TuiRunner = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayListUnmanaged(TaskState),
    selected_task: usize,
    scroll_offset: usize,
    mutex: std.Thread.Mutex,
    should_quit: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) TuiRunner {
        return .{
            .allocator = allocator,
            .tasks = .empty,
            .selected_task = 0,
            .scroll_offset = 0,
            .mutex = .{},
            .should_quit = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *TuiRunner) void {
        for (self.tasks.items) |*task| {
            task.deinit();
        }
        self.tasks.deinit(self.allocator);
    }

    /// Add a task to the runner.
    pub fn addTask(self: *TuiRunner, name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const task = TaskState.init(self.allocator, name);
        try self.tasks.append(self.allocator, task);
    }

    /// Update task status (thread-safe).
    pub fn setTaskStatus(self: *TuiRunner, name: []const u8, status: TaskStatus) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.name, name)) {
                task.status = status;
                return;
            }
        }
    }

    /// Append a log line to a task (thread-safe).
    pub fn appendTaskLog(self: *TuiRunner, name: []const u8, text: []const u8, is_stderr: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.name, name)) {
                try task.appendLog(text, is_stderr);
                return;
            }
        }
    }

    /// Mark task as complete with exit code and duration.
    pub fn completeTask(self: *TuiRunner, name: []const u8, exit_code: u8, duration_ms: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.name, name)) {
                task.status = if (exit_code == 0) .success else .failed;
                task.exit_code = exit_code;
                task.duration_ms = duration_ms;
                return;
            }
        }
    }

    /// Render the TUI screen to the writer.
    pub fn render(self: *TuiRunner, w: anytype, use_color: bool, terminal_height: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clear screen and move to top-left.
        try w.writeAll("\x1b[2J\x1b[H");

        // Header
        if (use_color) try w.writeAll(color.Code.bold);
        try w.writeAll("zr Live Execution");
        if (use_color) try w.writeAll(color.Code.reset);
        try w.writeAll("  [");
        if (use_color) try w.writeAll(color.Code.bright_cyan);
        try w.writeAll("\u{2191}\u{2193}");
        if (use_color) try w.writeAll(color.Code.reset);
        try w.writeAll("] Switch Task  [");
        if (use_color) try w.writeAll(color.Code.bright_cyan);
        try w.writeAll("PgUp/PgDn");
        if (use_color) try w.writeAll(color.Code.reset);
        try w.writeAll("] Scroll  [");
        if (use_color) try w.writeAll(color.Code.bright_cyan);
        try w.writeAll("q");
        if (use_color) try w.writeAll(color.Code.reset);
        try w.writeAll("] Quit\n\n");

        // Task list (left column)
        try w.writeAll("Tasks:\n");
        for (self.tasks.items, 0..) |*task, i| {
            const is_selected = (i == self.selected_task);
            const status_str = switch (task.status) {
                .pending => "⏸ ",
                .running => "▶ ",
                .success => "✓ ",
                .failed => "✗ ",
                .skipped => "⊘ ",
            };
            const status_color = switch (task.status) {
                .pending => color.Code.dim,
                .running => color.Code.bright_cyan,
                .success => color.Code.bright_green,
                .failed => color.Code.bright_red,
                .skipped => color.Code.dim,
            };

            if (is_selected) {
                if (use_color) try w.writeAll(color.Code.bright_yellow);
                try w.writeAll(">");
                if (use_color) try w.writeAll(color.Code.reset);
            } else {
                try w.writeAll(" ");
            }

            if (use_color) try w.writeAll(status_color);
            try w.writeAll(status_str);
            if (use_color) try w.writeAll(color.Code.reset);
            try w.print("{s}", .{task.name});

            if (task.status == .success or task.status == .failed) {
                try w.print(" ({d}ms)", .{task.duration_ms});
            }
            try w.writeAll("\n");
        }

        // Logs for selected task (right column)
        try w.writeAll("\n--- Logs ");
        if (self.tasks.items.len > 0 and self.selected_task < self.tasks.items.len) {
            const selected = &self.tasks.items[self.selected_task];
            try w.print("({s})", .{selected.name});
            try w.writeAll(" ---\n");

            const log_count = selected.logs.items.len;
            const display_height = if (terminal_height > 15) terminal_height - 15 else 10;

            if (log_count == 0) {
                try w.writeAll("  (no output yet)\n");
            } else {
                const start_idx = @min(self.scroll_offset, if (log_count > display_height) log_count - display_height else 0);
                const end_idx = @min(start_idx + display_height, log_count);

                for (selected.logs.items[start_idx..end_idx]) |line| {
                    if (line.is_stderr and use_color) {
                        try w.writeAll(color.Code.bright_red);
                    }
                    try w.print("{s}\n", .{line.text});
                    if (line.is_stderr and use_color) {
                        try w.writeAll(color.Code.reset);
                    }
                }

                if (end_idx < log_count) {
                    try w.print("\n... ({d} more lines, scroll down) ...\n", .{log_count - end_idx});
                }
            }
        } else {
            try w.writeAll(" ---\n  (no tasks)\n");
        }
    }
};

// ---------------------------------------------------------------------------
// Raw terminal mode (POSIX only) — reused from tui.zig
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
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

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

/// Background thread that handles keyboard input for the TUI.
fn inputThread(runner: *TuiRunner) void {
    if (comptime !IS_POSIX) return;

    const original = enterRawMode() catch return;
    defer leaveRawMode(original);

    while (!runner.should_quit.load(.seq_cst)) {
        const byte = readByte() orelse break;

        switch (byte) {
            'q', 'Q' => {
                runner.should_quit.store(true, .seq_cst);
                break;
            },

            'k', 'j' => {
                runner.mutex.lock();
                defer runner.mutex.unlock();

                if (byte == 'k' and runner.selected_task > 0) {
                    runner.selected_task -= 1;
                    runner.scroll_offset = 0;
                } else if (byte == 'j' and runner.selected_task + 1 < runner.tasks.items.len) {
                    runner.selected_task += 1;
                    runner.scroll_offset = 0;
                }
            },

            0x1b => { // ESC sequence
                const b2 = readByte() orelse continue;
                if (b2 == '[') {
                    const b3 = readByte() orelse continue;
                    switch (b3) {
                        'A' => { // Up arrow
                            runner.mutex.lock();
                            defer runner.mutex.unlock();
                            if (runner.selected_task > 0) {
                                runner.selected_task -= 1;
                                runner.scroll_offset = 0;
                            }
                        },
                        'B' => { // Down arrow
                            runner.mutex.lock();
                            defer runner.mutex.unlock();
                            if (runner.selected_task + 1 < runner.tasks.items.len) {
                                runner.selected_task += 1;
                                runner.scroll_offset = 0;
                            }
                        },
                        '5' => { // Page Up
                            _ = readByte(); // consume '~'
                            runner.mutex.lock();
                            defer runner.mutex.unlock();
                            if (runner.scroll_offset >= 10) {
                                runner.scroll_offset -= 10;
                            } else {
                                runner.scroll_offset = 0;
                            }
                        },
                        '6' => { // Page Down
                            _ = readByte(); // consume '~'
                            runner.mutex.lock();
                            defer runner.mutex.unlock();
                            runner.scroll_offset += 10;
                        },
                        else => {},
                    }
                }
            },

            else => {},
        }
    }
}

/// Start the TUI runner with background input handling.
/// Returns a handle to the runner that should be deinitialized when done.
pub fn start(allocator: std.mem.Allocator) !*TuiRunner {
    const runner = try allocator.create(TuiRunner);
    runner.* = TuiRunner.init(allocator);

    // Spawn input handling thread.
    const thread = try std.Thread.spawn(.{}, inputThread, .{runner});
    thread.detach();

    return runner;
}

/// Stop the TUI runner and clean up.
pub fn stop(runner: *TuiRunner, allocator: std.mem.Allocator) void {
    runner.should_quit.store(true, .seq_cst);
    // Give input thread time to exit cleanly.
    std.Thread.sleep(100 * std.time.ns_per_ms);
    runner.deinit();
    allocator.destroy(runner);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "TuiRunner: init and deinit" {
    const allocator = std.testing.allocator;

    var runner = TuiRunner.init(allocator);
    defer runner.deinit();

    try std.testing.expectEqual(@as(usize, 0), runner.tasks.items.len);
    try std.testing.expectEqual(@as(usize, 0), runner.selected_task);
}

test "TuiRunner: add task and update status" {
    const allocator = std.testing.allocator;

    var runner = TuiRunner.init(allocator);
    defer runner.deinit();

    try runner.addTask("build");
    try runner.addTask("test");

    try std.testing.expectEqual(@as(usize, 2), runner.tasks.items.len);

    runner.setTaskStatus("build", .running);
    try std.testing.expectEqual(TaskStatus.running, runner.tasks.items[0].status);

    runner.completeTask("build", 0, 123);
    try std.testing.expectEqual(TaskStatus.success, runner.tasks.items[0].status);
    try std.testing.expectEqual(@as(u64, 123), runner.tasks.items[0].duration_ms);
}

test "TuiRunner: append logs" {
    const allocator = std.testing.allocator;

    var runner = TuiRunner.init(allocator);
    defer runner.deinit();

    try runner.addTask("compile");
    try runner.appendTaskLog("compile", "Building src/main.zig", false);
    try runner.appendTaskLog("compile", "Error: undefined symbol", true);

    try std.testing.expectEqual(@as(usize, 2), runner.tasks.items[0].logs.items.len);
    try std.testing.expect(std.mem.eql(u8, "Building src/main.zig", runner.tasks.items[0].logs.items[0].text));
    try std.testing.expect(runner.tasks.items[0].logs.items[1].is_stderr);
}

test "TuiRunner: log buffer limit" {
    const allocator = std.testing.allocator;

    var runner = TuiRunner.init(allocator);
    defer runner.deinit();

    try runner.addTask("spam");

    // Add MAX_LOG_LINES + 100 lines.
    var i: usize = 0;
    while (i < MAX_LOG_LINES + 100) : (i += 1) {
        const line = try std.fmt.allocPrint(allocator, "Line {d}", .{i});
        defer allocator.free(line);
        try runner.appendTaskLog("spam", line, false);
    }

    // Should cap at MAX_LOG_LINES.
    try std.testing.expectEqual(@as(usize, MAX_LOG_LINES), runner.tasks.items[0].logs.items.len);
}

test "TuiRunner: render with no tasks" {
    const allocator = std.testing.allocator;

    var runner = TuiRunner.init(allocator);
    defer runner.deinit();

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();

    try runner.render(&w, false, 24);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "zr Live Execution") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(no tasks)") != null);
}

test "TuiRunner: render with tasks" {
    const allocator = std.testing.allocator;

    var runner = TuiRunner.init(allocator);
    defer runner.deinit();

    try runner.addTask("build");
    try runner.addTask("test");
    runner.setTaskStatus("build", .running);
    try runner.appendTaskLog("build", "Compiling...", false);

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();

    try runner.render(&w, false, 24);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Compiling...") != null);
}
