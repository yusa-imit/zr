/// TUI live execution — real-time log streaming for running tasks.
///
/// Uses sailor.tui widgets (Buffer, Block, List, Paragraph, layout.split)
/// for structured rendering. Status icons and log display are composed
/// into a cell buffer and flushed to the writer with color.Code ANSI codes.
const std = @import("std");
const builtin = @import("builtin");
const color = @import("../output/color.zig");
const sailor = @import("sailor");
const stui = sailor.tui;

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

    /// Build a display label for a task including status icon and duration.
    fn buildTaskLabel(allocator: std.mem.Allocator, task: *const TaskState) ![]const u8 {
        const status_str: []const u8 = switch (task.status) {
            .pending => "\xe2\x8f\xb8 ",
            .running => "\xe2\x96\xb6 ",
            .success => "\xe2\x9c\x93 ",
            .failed => "\xe2\x9c\x97 ",
            .skipped => "\xe2\x8a\x98 ",
        };

        if (task.status == .success or task.status == .failed) {
            return try std.fmt.allocPrint(allocator, "{s}{s} ({d}ms)", .{ status_str, task.name, task.duration_ms });
        }
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ status_str, task.name });
    }

    /// Render the TUI screen to the writer using sailor.tui widgets.
    pub fn render(self: *TuiRunner, w: anytype, use_color: bool, terminal_height: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const screen_width: u16 = 80;
        const screen_height: u16 = @intCast(@min(terminal_height, 50));

        var buf = try stui.Buffer.init(self.allocator, screen_width, screen_height);
        defer buf.deinit();

        // Layout: header (2), task list block, log block
        const full_area = stui.Rect.new(0, 0, screen_width, screen_height);
        const task_list_height: u16 = @intCast(@min(self.tasks.items.len + 2, 12));
        const chunks = try stui.layout.split(
            self.allocator,
            .vertical,
            full_area,
            &[_]stui.Constraint{
                .{ .length = 2 },
                .{ .length = task_list_height },
                .{ .min = 5 },
            },
        );
        defer self.allocator.free(chunks);

        // --- Header ---
        buf.setString(0, chunks[0].y, "zr Live Execution", stui.Style{ .bold = true });
        buf.setString(18, chunks[0].y, "  [^v] Switch Task  [PgUp/PgDn] Scroll  [q] Quit",
            stui.Style{ .fg = .bright_cyan });

        // --- Task list ---
        if (self.tasks.items.len > 0) {
            var labels = try self.allocator.alloc([]const u8, self.tasks.items.len);
            defer {
                for (labels) |l| self.allocator.free(l);
                self.allocator.free(labels);
            }
            for (self.tasks.items, 0..) |*task, i| {
                labels[i] = try buildTaskLabel(self.allocator, task);
            }

            const task_block = stui.widgets.Block.init()
                .withTitle("Tasks", .top_left)
                .withTitleStyle(stui.Style{ .bold = true });

            const task_list = stui.widgets.List.init(labels)
                .withSelected(self.selected_task)
                .withBlock(task_block)
                .withSelectedStyle(stui.Style{ .fg = .bright_yellow })
                .withHighlightSymbol("> ");

            task_list.render(&buf, chunks[1]);
        } else {
            buf.setString(2, chunks[1].y, "(no tasks)", stui.Style{ .dim = true });
        }

        // --- Logs ---
        if (self.tasks.items.len > 0 and self.selected_task < self.tasks.items.len) {
            const selected = &self.tasks.items[self.selected_task];

            const log_title = try std.fmt.allocPrint(self.allocator, "Logs ({s})", .{selected.name});
            defer self.allocator.free(log_title);

            const log_block = stui.widgets.Block.init()
                .withTitle(log_title, .top_left)
                .withTitleStyle(stui.Style{ .bold = true });

            log_block.render(&buf, chunks[2]);
            const inner = log_block.inner(chunks[2]);

            const log_count = selected.logs.items.len;
            if (log_count == 0) {
                buf.setString(inner.x + 1, inner.y, "(no output yet)", stui.Style{ .dim = true });
            } else {
                const display_height: usize = inner.height;
                const start_idx = @min(self.scroll_offset, if (log_count > display_height) log_count - display_height else 0);
                const end_idx = @min(start_idx + display_height, log_count);

                for (selected.logs.items[start_idx..end_idx], 0..) |line, row| {
                    const log_style: stui.Style = if (line.is_stderr and use_color)
                        .{ .fg = .bright_red }
                    else
                        .{};
                    buf.setString(inner.x, inner.y + @as(u16, @intCast(row)), line.text, log_style);
                }

                if (end_idx < log_count) {
                    const more_msg = try std.fmt.allocPrint(self.allocator, "... ({d} more lines, scroll down) ...", .{log_count - end_idx});
                    defer self.allocator.free(more_msg);
                    const msg_y = chunks[2].y + chunks[2].height -| 1;
                    buf.setString(chunks[2].x + 1, msg_y, more_msg, stui.Style{ .dim = true });
                }
            }
        } else {
            const no_task_block = stui.widgets.Block.init()
                .withTitle("Logs", .top_left)
                .withTitleStyle(stui.Style{ .bold = true });
            no_task_block.render(&buf, chunks[2]);
            const inner = no_task_block.inner(chunks[2]);
            buf.setString(inner.x + 1, inner.y, "(no tasks)", stui.Style{ .dim = true });
        }

        // --- Flush buffer to writer ---
        try w.writeAll("\x1b[2J\x1b[H");
        var y: u16 = 0;
        while (y < buf.height) : (y += 1) {
            var x: u16 = 0;
            while (x < buf.width) : (x += 1) {
                const cell = buf.getConst(x, y) orelse continue;
                if (use_color) try emitCellStyle(w, cell.style);
                var utf8_buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch 1;
                try w.writeAll(utf8_buf[0..len]);
                if (use_color and cellHasStyle(cell.style)) {
                    try w.writeAll(color.Code.reset);
                }
            }
            if (y + 1 < buf.height) {
                try w.writeAll("\n");
            }
        }
    }

    fn cellHasStyle(s: stui.Style) bool {
        return s.fg != null or s.bg != null or s.bold or s.dim or
            s.italic or s.underline;
    }

    fn emitCellStyle(w: anytype, s: stui.Style) !void {
        if (s.bold) try w.writeAll(color.Code.bold);
        if (s.dim) try w.writeAll(color.Code.dim);
        if (s.fg) |fg| {
            switch (fg) {
                .red => try w.writeAll(color.Code.red),
                .green => try w.writeAll(color.Code.green),
                .yellow => try w.writeAll(color.Code.yellow),
                .blue => try w.writeAll(color.Code.blue),
                .magenta => try w.writeAll(color.Code.magenta),
                .cyan => try w.writeAll(color.Code.cyan),
                .white => try w.writeAll(color.Code.white),
                .bright_red => try w.writeAll(color.Code.bright_red),
                .bright_green => try w.writeAll(color.Code.bright_green),
                .bright_yellow => try w.writeAll(color.Code.bright_yellow),
                .bright_blue => try w.writeAll(color.Code.bright_blue),
                .bright_cyan => try w.writeAll(color.Code.bright_cyan),
                .bright_white => try w.writeAll(color.Code.bright_white),
                else => {},
            }
        }
    }
};

// ---------------------------------------------------------------------------
// Raw terminal mode (POSIX only)
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

            0x1b => {
                const b2 = readByte() orelse continue;
                if (b2 == '[') {
                    const b3 = readByte() orelse continue;
                    switch (b3) {
                        'A' => {
                            runner.mutex.lock();
                            defer runner.mutex.unlock();
                            if (runner.selected_task > 0) {
                                runner.selected_task -= 1;
                                runner.scroll_offset = 0;
                            }
                        },
                        'B' => {
                            runner.mutex.lock();
                            defer runner.mutex.unlock();
                            if (runner.selected_task + 1 < runner.tasks.items.len) {
                                runner.selected_task += 1;
                                runner.scroll_offset = 0;
                            }
                        },
                        '5' => {
                            _ = readByte();
                            runner.mutex.lock();
                            defer runner.mutex.unlock();
                            if (runner.scroll_offset >= 10) {
                                runner.scroll_offset -= 10;
                            } else {
                                runner.scroll_offset = 0;
                            }
                        },
                        '6' => {
                            _ = readByte();
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
pub fn start(allocator: std.mem.Allocator) !*TuiRunner {
    const runner = try allocator.create(TuiRunner);
    runner.* = TuiRunner.init(allocator);

    const thread = try std.Thread.spawn(.{}, inputThread, .{runner});
    thread.detach();

    return runner;
}

/// Stop the TUI runner and clean up.
pub fn stop(runner: *TuiRunner, allocator: std.mem.Allocator) void {
    runner.should_quit.store(true, .seq_cst);
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

    var i: usize = 0;
    while (i < MAX_LOG_LINES + 100) : (i += 1) {
        const line = try std.fmt.allocPrint(allocator, "Line {d}", .{i});
        defer allocator.free(line);
        try runner.appendTaskLog("spam", line, false);
    }

    try std.testing.expectEqual(@as(usize, MAX_LOG_LINES), runner.tasks.items[0].logs.items.len);
}

test "TuiRunner: render with no tasks" {
    const allocator = std.testing.allocator;

    var runner = TuiRunner.init(allocator);
    defer runner.deinit();

    var out_buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
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

    var out_buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var w = fbs.writer();

    try runner.render(&w, false, 24);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Compiling...") != null);
}
