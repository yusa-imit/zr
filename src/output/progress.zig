/// Terminal progress bar for task execution feedback.
///
/// Renders a compact progress bar to stderr (or any writer) when a TTY is detected.
/// Uses ANSI escape codes for in-place updates via carriage return (\r).
///
/// Example output:
///   [=========>          ] 45%  9/20  build-frontend
///   [===================>] 100% 20/20  Done
///
/// Thread-safety: `tick()` and `finish()` are NOT thread-safe; call from a
/// single coordinating thread (e.g., the scheduler's main thread between levels).
const std = @import("std");

/// Width (in chars) of the bar's fill region (between '[' and ']').
const BAR_WIDTH: usize = 20;

/// A simple single-line progress bar that rewrites itself in place on a TTY.
pub const ProgressBar = struct {
    writer: *std.Io.Writer,
    use_color: bool,
    total: usize,
    current: usize,
    /// Last task label shown in the bar. Not owned — caller keeps it alive.
    label: []const u8,
    /// True if at least one render has been emitted (so we can overwrite).
    started: bool,

    /// Create a new progress bar.
    /// `writer` should be stderr (not stdout) when used alongside task output.
    /// `total` is the total number of steps.
    pub fn init(writer: *std.Io.Writer, use_color: bool, total: usize) ProgressBar {
        return .{
            .writer = writer,
            .use_color = use_color,
            .total = total,
            .current = 0,
            .label = "",
            .started = false,
        };
    }

    /// Advance progress by one step and render.
    /// `task_label` is the name of the task just completed (non-owning).
    pub fn tick(self: *ProgressBar, task_label: []const u8) void {
        if (self.current < self.total) self.current += 1;
        self.label = task_label;
        self.render() catch {};
    }

    /// Mark progress complete (sets current = total) and render a final line.
    pub fn finish(self: *ProgressBar) void {
        self.current = self.total;
        self.label = "Done";
        self.render() catch {};
        // Move to next line so subsequent output doesn't overwrite the bar.
        self.writer.writeAll("\n") catch {};
    }

    /// Render the bar in-place using carriage return (stays on same line).
    /// On first call, no CR is needed; subsequent calls overwrite.
    fn render(self: *ProgressBar) !void {
        const pct: usize = if (self.total == 0) 100 else self.current * 100 / self.total;
        const filled: usize = if (self.total == 0) BAR_WIDTH else self.current * BAR_WIDTH / self.total;

        // Overwrite previous render by returning to start of line.
        if (self.started) {
            try self.writer.writeAll("\r");
        }
        self.started = true;

        if (self.use_color) {
            // Dim bracket
            try self.writer.writeAll("\x1b[2m[\x1b[0m");
            // Green fill
            try self.writer.writeAll("\x1b[32m");
            var i: usize = 0;
            while (i < BAR_WIDTH) : (i += 1) {
                if (i < filled) {
                    try self.writer.writeAll("=");
                } else if (i == filled and filled < BAR_WIDTH) {
                    try self.writer.writeAll(">");
                } else {
                    try self.writer.writeAll(" ");
                }
            }
            try self.writer.writeAll("\x1b[0m");
            // Dim bracket
            try self.writer.writeAll("\x1b[2m]\x1b[0m");
            // Percentage — cyan
            try self.writer.print(" \x1b[36m{d:>3}%\x1b[0m", .{pct});
            // Count
            try self.writer.print(" \x1b[2m{d}/{d}\x1b[0m", .{ self.current, self.total });
            // Label — bold
            if (self.label.len > 0) {
                try self.writer.print("  \x1b[1m{s}\x1b[0m", .{self.label});
            }
        } else {
            try self.writer.writeAll("[");
            var i: usize = 0;
            while (i < BAR_WIDTH) : (i += 1) {
                if (i < filled) {
                    try self.writer.writeAll("=");
                } else if (i == filled and filled < BAR_WIDTH) {
                    try self.writer.writeAll(">");
                } else {
                    try self.writer.writeAll(" ");
                }
            }
            try self.writer.writeAll("]");
            try self.writer.print(" {d:>3}% {d}/{d}", .{ pct, self.current, self.total });
            if (self.label.len > 0) {
                try self.writer.print("  {s}", .{self.label});
            }
        }
    }
};

/// Render a one-shot summary bar (used after `scheduler.run` to summarize results).
/// Shows passed/failed/skipped counts in a compact line.
pub fn printSummary(
    writer: *std.Io.Writer,
    use_color: bool,
    passed: usize,
    failed: usize,
    skipped: usize,
    elapsed_ms: u64,
) !void {
    const total = passed + failed + skipped;
    if (use_color) {
        try writer.print("\x1b[1m{d}\x1b[0m tasks ", .{total});
        if (passed > 0) {
            try writer.print("\x1b[32m✓ {d} passed\x1b[0m", .{passed});
        }
        if (failed > 0) {
            if (passed > 0) try writer.writeAll("  ");
            try writer.print("\x1b[31m✗ {d} failed\x1b[0m", .{failed});
        }
        if (skipped > 0) {
            if (passed > 0 or failed > 0) try writer.writeAll("  ");
            try writer.print("\x1b[33m⊘ {d} skipped\x1b[0m", .{skipped});
        }
        try writer.print("  \x1b[2m({d}ms)\x1b[0m\n", .{elapsed_ms});
    } else {
        try writer.print("{d} tasks", .{total});
        if (passed > 0) try writer.print("  v {d} passed", .{passed});
        if (failed > 0) try writer.print("  x {d} failed", .{failed});
        if (skipped > 0) try writer.print("  - {d} skipped", .{skipped});
        try writer.print("  ({d}ms)\n", .{elapsed_ms});
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ProgressBar: basic tick and finish (no-color)" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    var bar = ProgressBar.init(&writer, false, 5);
    bar.tick("compile");
    bar.tick("link");
    bar.finish();

    const out = buf[0..writer.end];
    // Should contain progress indicators
    try std.testing.expect(std.mem.indexOf(u8, out, "[") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "5/5") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Done") != null);
    // Should have a trailing newline after finish
    try std.testing.expect(out[out.len - 1] == '\n');
}

test "ProgressBar: 0-total treated as 100%" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    var bar = ProgressBar.init(&writer, false, 0);
    bar.finish();

    const out = buf[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, out, "100%") != null);
}

test "ProgressBar: single step reaches 100%" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    var bar = ProgressBar.init(&writer, false, 1);
    bar.tick("build");
    bar.finish();

    const out = buf[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, out, "100%") != null);
}

test "ProgressBar: color mode output contains ANSI codes" {
    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    var bar = ProgressBar.init(&writer, true, 3);
    bar.tick("test");

    const out = buf[0..writer.end];
    // ANSI escape prefix
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[") != null);
}

test "printSummary: no-color format" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try printSummary(&writer, false, 8, 2, 1, 1234);

    const out = buf[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, out, "11 tasks") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "8 passed") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "2 failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "1 skipped") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "1234ms") != null);
}

test "printSummary: all passed no-color" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try printSummary(&writer, false, 5, 0, 0, 42);

    const out = buf[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, out, "5 tasks") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "5 passed") != null);
    // No "failed" or "skipped" in output
    try std.testing.expect(std.mem.indexOf(u8, out, "failed") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "skipped") == null);
}

test "printSummary: color mode contains ANSI codes" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try printSummary(&writer, true, 3, 1, 0, 99);

    const out = buf[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[") != null);
}
