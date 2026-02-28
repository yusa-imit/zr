/// Interactive TUI for zr — task/workflow picker with raw-mode keyboard input.
/// Uses sailor.tui widgets (Buffer, List) for layout and composing the screen.
/// On non-TTY environments (pipes, CI) falls back to a plain text message.
const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const run_cmd = @import("run.zig");
const color = @import("../output/color.zig");
const sailor = @import("sailor");
const stui = sailor.tui;

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
// Sailor buffer rendering helper
// ---------------------------------------------------------------------------

/// Render a sailor Buffer to a writer. Uses color.Code ANSI sequences
/// to avoid sailor's std.fmt compatibility issues with Io.Writer.
fn renderBuffer(buf: *stui.Buffer, w: anytype, use_color: bool) !void {
    try w.writeAll("\x1b[2J\x1b[H");

    var y: u16 = 0;
    while (y < buf.height) : (y += 1) {
        var x: u16 = 0;
        while (x < buf.width) : (x += 1) {
            const cell = buf.getConst(x, y) orelse continue;
            if (use_color) {
                try emitCellStyle(w, cell.style);
            }
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

/// Emit ANSI codes for a sailor style using color.Code string constants.
fn emitCellStyle(w: anytype, s: stui.Style) !void {
    if (s.bold) try w.writeAll(color.Code.bold);
    if (s.dim) try w.writeAll(color.Code.dim);
    if (s.fg) |fg| {
        try emitFgColor(w, fg);
    }
}

fn emitFgColor(w: anytype, c: stui.Color) !void {
    switch (c) {
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

// ---------------------------------------------------------------------------
// Screen-drawing helpers using sailor.tui widgets
// ---------------------------------------------------------------------------

fn buildItemLabels(allocator: std.mem.Allocator, items: []const Item) ![][]const u8 {
    const labels = try allocator.alloc([]const u8, items.len);
    var count: usize = 0;
    errdefer {
        for (labels[0..count]) |l| allocator.free(l);
        allocator.free(labels);
    }
    for (items) |item| {
        const kind_label: []const u8 = switch (item.kind) {
            .task => "task",
            .workflow => "wf  ",
        };
        labels[count] = try std.fmt.allocPrint(allocator, "{s}  {s}", .{ kind_label, item.name });
        count += 1;
    }
    return labels;
}

fn freeItemLabels(allocator: std.mem.Allocator, labels: [][]const u8) void {
    for (labels) |l| allocator.free(l);
    allocator.free(labels);
}

/// Write the full TUI screen using sailor.tui List widget for layout.
fn drawScreen(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    items: []const Item,
    selected: usize,
    use_color: bool,
) !void {
    const screen_width: u16 = 60;
    const screen_height: u16 = @intCast(@min(@as(usize, 30), items.len + 5));

    var buf = try stui.Buffer.init(allocator, screen_width, screen_height);
    defer buf.deinit();

    // Header
    buf.setString(0, 0, "zr Interactive Mode", stui.Style{ .bold = true });
    buf.setString(0, 1, "[^v] Navigate  [Enter] Run  [q] Quit  [r] Refresh",
        stui.Style{ .fg = .bright_cyan });

    if (items.len == 0) {
        buf.setString(2, 3, "(no tasks or workflows defined)", .{});
        try renderBuffer(&buf, w, use_color);
        return;
    }

    // Item list using sailor List widget
    const labels = try buildItemLabels(allocator, items);
    defer freeItemLabels(allocator, labels);

    const list_area = stui.Rect.new(0, 3, screen_width, screen_height - 3);
    const list = stui.widgets.List.init(labels)
        .withSelected(selected)
        .withSelectedStyle(stui.Style{ .fg = .bright_cyan })
        .withHighlightSymbol("> ");

    list.render(&buf, list_area);

    try renderBuffer(&buf, w, use_color);
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
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    var items: std.ArrayListUnmanaged(Item) = .empty;
    defer items.deinit(allocator);

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

    if (!is_tty) {
        try w.writeAll("No TTY detected. Run 'zr list' to see available tasks.\n");
        return 0;
    }

    if (comptime !IS_POSIX) {
        try w.writeAll("No TTY detected. Run 'zr list' to see available tasks.\n");
        return 0;
    }

    const original_termios = enterRawMode() catch {
        try w.writeAll("No TTY detected. Run 'zr list' to see available tasks.\n");
        return 0;
    };
    defer leaveRawMode(original_termios);

    var selected: usize = 0;
    const item_count = items.items.len;

    try drawScreen(allocator, w, items.items, selected, use_color);
    try w.flush();

    while (true) {
        const byte = readByte() orelse break;

        switch (byte) {
            'q', 'Q' => break,

            'k' => {
                if (item_count > 0 and selected > 0) selected -= 1;
                try drawScreen(allocator, w, items.items, selected, use_color);
                try w.flush();
            },

            'j' => {
                if (item_count > 0 and selected + 1 < item_count) selected += 1;
                try drawScreen(allocator, w, items.items, selected, use_color);
                try w.flush();
            },

            'r', 'R' => {
                try drawScreen(allocator, w, items.items, selected, use_color);
                try w.flush();
            },

            0x1b => {
                const b2 = readByte() orelse continue;
                if (b2 == '[') {
                    const b3 = readByte() orelse continue;
                    switch (b3) {
                        'A' => {
                            if (item_count > 0 and selected > 0) selected -= 1;
                            try drawScreen(allocator, w, items.items, selected, use_color);
                            try w.flush();
                        },
                        'B' => {
                            if (item_count > 0 and selected + 1 < item_count) selected += 1;
                            try drawScreen(allocator, w, items.items, selected, use_color);
                            try w.flush();
                        },
                        else => {},
                    }
                }
            },

            0x0D, '\n' => {
                if (item_count == 0) continue;

                const sel_item = items.items[selected];

                try w.writeAll("\x1b[2J\x1b[H");
                try w.print("Running: {s}\n\n", .{sel_item.name});
                try w.flush();

                leaveRawMode(original_termios);

                _ = run_cmd.cmdRun(
                    allocator,
                    sel_item.name,
                    null,
                    false,
                    0,
                    config_path,
                    false,
                    false,
                    w,
                    ew,
                    use_color,
                    null,
                ) catch {};

                _ = enterRawMode() catch {};

                try w.writeAll("\n--- Press any key to return ---");
                try w.flush();
                _ = readByte();

                try drawScreen(allocator, w, items.items, selected, use_color);
                try w.flush();
            },

            else => {},
        }
    }

    try w.writeAll("\x1b[2J\x1b[H");
    try w.flush();

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
        false,
    );

    try std.testing.expectEqual(@as(u8, 0), result);

    const output = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, output, "No TTY detected") != null);
}

test "cmdInteractive: empty config shows no-TTY message" {
    const allocator = std.testing.allocator;

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
        false,
    );

    try std.testing.expectEqual(@as(u8, 0), result);

    const output = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, output, "No TTY detected") != null);
}
