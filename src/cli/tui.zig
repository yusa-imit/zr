/// Interactive TUI for zr — task/workflow picker with raw-mode keyboard input.
/// On non-TTY environments (pipes, CI) falls back to a plain text message.
const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const run_cmd = @import("run.zig");
const color = @import("../output/color.zig");

const IS_POSIX = builtin.os.tag != .windows;

// ---------------------------------------------------------------------------
// Item types
// ---------------------------------------------------------------------------

const ItemKind = enum { task, workflow };

const Item = struct {
    name: []const u8,
    kind: ItemKind,
};

// ---------------------------------------------------------------------------
// Raw terminal mode (POSIX only)
// ---------------------------------------------------------------------------

/// Saves and returns the original termios; leaves stdin in raw (unbuffered,
/// no-echo) mode.  Only compiled on POSIX targets.
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
    // VMIN=1: return after at least 1 byte; VTIME=0: no timeout.
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(stdin.handle, .NOW, raw);
    return original;
}

/// Restore the original termios saved by enterRawMode().
fn leaveRawMode(original: if (IS_POSIX) std.posix.termios else void) void {
    if (comptime !IS_POSIX) return;
    std.posix.tcsetattr(std.fs.File.stdin().handle, .NOW, original) catch {};
}

/// Read a single byte from stdin.  Returns null on EOF or error.
fn readByte() ?u8 {
    const stdin = std.fs.File.stdin();
    var b: [1]u8 = undefined;
    const n = stdin.read(&b) catch return null;
    if (n == 0) return null;
    return b[0];
}

// ---------------------------------------------------------------------------
// String comparison helper for sorting
// ---------------------------------------------------------------------------

fn strLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn itemLessThan(_: void, a: Item, b: Item) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

// ---------------------------------------------------------------------------
// Screen-drawing helpers
// ---------------------------------------------------------------------------

/// Write the full TUI screen to the writer.
fn drawScreen(
    w: *std.Io.Writer,
    items: []const Item,
    selected: usize,
    use_color: bool,
) !void {
    // Clear screen and move cursor to top-left.
    try w.writeAll("\x1b[2J\x1b[H");

    if (use_color) {
        try w.writeAll(color.Code.bold);
    }
    try w.writeAll("zr Interactive Mode  ");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("[");
    if (use_color) try w.writeAll(color.Code.bright_cyan);
    try w.writeAll("\u{2191}\u{2193}");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("] Navigate  [");
    if (use_color) try w.writeAll(color.Code.bright_cyan);
    try w.writeAll("Enter");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("] Run  [");
    if (use_color) try w.writeAll(color.Code.bright_cyan);
    try w.writeAll("q");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("] Quit  [");
    if (use_color) try w.writeAll(color.Code.bright_cyan);
    try w.writeAll("r");
    if (use_color) try w.writeAll(color.Code.reset);
    try w.writeAll("] Refresh\n\n");

    if (items.len == 0) {
        try w.writeAll("  (no tasks or workflows defined)\n");
        return;
    }

    for (items, 0..) |item, i| {
        const is_selected = (i == selected);
        const kind_label: []const u8 = switch (item.kind) {
            .task => "task",
            .workflow => "wf  ",
        };

        if (is_selected) {
            if (use_color) try w.writeAll(color.Code.bright_cyan);
            try w.print("> {s}  {s}\n", .{ kind_label, item.name });
            if (use_color) try w.writeAll(color.Code.reset);
        } else {
            try w.print("  {s}  {s}\n", .{ kind_label, item.name });
        }
    }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn cmdInteractive(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    return cmdInteractiveInner(
        allocator,
        config_path,
        w,
        ew,
        use_color,
        std.fs.File.stdout().isTty(),
    );
}

// ---------------------------------------------------------------------------
// Inner implementation (accepts explicit is_tty for testability)
// ---------------------------------------------------------------------------

fn cmdInteractiveInner(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
    is_tty: bool,
) !u8 {
    // --- Load config -----------------------------------------------------------
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    // --- Build sorted item list ------------------------------------------------
    var items: std.ArrayListUnmanaged(Item) = .empty;
    defer items.deinit(allocator);

    // Collect task names.
    var task_names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer task_names.deinit(allocator);

    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        try task_names.append(allocator, entry.key_ptr.*);
    }
    std.mem.sort([]const u8, task_names.items, {}, strLessThan);

    for (task_names.items) |name| {
        try items.append(allocator, .{ .name = name, .kind = .task });
    }

    // Collect workflow names.
    var wf_names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer wf_names.deinit(allocator);

    var wf_it = config.workflows.iterator();
    while (wf_it.next()) |entry| {
        try wf_names.append(allocator, entry.key_ptr.*);
    }
    std.mem.sort([]const u8, wf_names.items, {}, strLessThan);

    for (wf_names.items) |name| {
        try items.append(allocator, .{ .name = name, .kind = .workflow });
    }

    // --- Non-TTY fallback ------------------------------------------------------
    if (!is_tty) {
        try w.writeAll("No TTY detected. Run 'zr list' to see available tasks.\n");
        return 0;
    }

    // --- TTY interactive mode (POSIX only) -------------------------------------
    if (comptime !IS_POSIX) {
        // Windows: raw mode not supported; fall back gracefully.
        try w.writeAll("No TTY detected. Run 'zr list' to see available tasks.\n");
        return 0;
    }

    // Enter raw mode.
    const original_termios = enterRawMode() catch {
        try w.writeAll("No TTY detected. Run 'zr list' to see available tasks.\n");
        return 0;
    };
    defer leaveRawMode(original_termios);

    var selected: usize = 0;
    const item_count = items.items.len;

    // Initial draw.
    try drawScreen(w, items.items, selected, use_color);

    // Main event loop.
    while (true) {
        const byte = readByte() orelse break;

        switch (byte) {
            'q', 'Q' => break,

            'k' => {
                if (item_count > 0 and selected > 0) {
                    selected -= 1;
                }
                try drawScreen(w, items.items, selected, use_color);
            },

            'j' => {
                if (item_count > 0 and selected + 1 < item_count) {
                    selected += 1;
                }
                try drawScreen(w, items.items, selected, use_color);
            },

            'r', 'R' => {
                try drawScreen(w, items.items, selected, use_color);
            },

            // ESC sequence: check for arrow keys (\x1b[A / \x1b[B).
            0x1b => {
                const b2 = readByte() orelse continue;
                if (b2 == '[') {
                    const b3 = readByte() orelse continue;
                    switch (b3) {
                        'A' => { // Up arrow
                            if (item_count > 0 and selected > 0) selected -= 1;
                            try drawScreen(w, items.items, selected, use_color);
                        },
                        'B' => { // Down arrow
                            if (item_count > 0 and selected + 1 < item_count) selected += 1;
                            try drawScreen(w, items.items, selected, use_color);
                        },
                        else => {},
                    }
                }
            },

            // Enter key (CR or LF).
            0x0D, '\n' => {
                if (item_count == 0) continue;

                const sel_item = items.items[selected];

                // Clear screen before running.
                try w.writeAll("\x1b[2J\x1b[H");
                try w.print("Running: {s}\n\n", .{sel_item.name});

                // Leave raw mode while the task runs so its output is visible.
                leaveRawMode(original_termios);

                _ = run_cmd.cmdRun(
                    allocator,
                    sel_item.name,
                    null,
                    false,
                    0,
                    config_path,
                    false,
                    false, // monitor
                    w,
                    ew,
                    use_color,
                ) catch {};

                // Re-enter raw mode for the next keypress.
                _ = enterRawMode() catch {};

                try w.writeAll("\n--- Press any key to return ---");
                _ = readByte();

                try drawScreen(w, items.items, selected, use_color);
            },

            else => {},
        }
    }

    // Clear screen on exit.
    try w.writeAll("\x1b[2J\x1b[H");

    return 0;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "cmdInteractive: missing config returns error code 1" {
    const allocator = std.testing.allocator;

    var out_buf: [512]u8 = undefined;
    var err_buf: [512]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdInteractiveInner(
        allocator,
        "/nonexistent/path/that/does/not/exist/zr.toml",
        &out_w,
        &err_w,
        false,
        false,
    );

    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdInteractive: non-TTY falls back gracefully" {
    const allocator = std.testing.allocator;

    // Create a temp config with a task.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml = "[tasks.hello]\ncmd = \"echo hello\"\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [512]u8 = undefined;
    var err_buf: [512]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdInteractiveInner(
        allocator,
        config_path,
        &out_w,
        &err_w,
        false,
        false, // is_tty = false → non-interactive path
    );

    try std.testing.expectEqual(@as(u8, 0), result);

    const output = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, output, "No TTY detected") != null);
}

test "cmdInteractive: empty config shows no-TTY message" {
    const allocator = std.testing.allocator;

    // Empty TOML (no tasks, no workflows).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "" });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [512]u8 = undefined;
    var err_buf: [512]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdInteractiveInner(
        allocator,
        config_path,
        &out_w,
        &err_w,
        false,
        false, // non-TTY
    );

    try std.testing.expectEqual(@as(u8, 0), result);

    const output = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, output, "No TTY detected") != null);
}
