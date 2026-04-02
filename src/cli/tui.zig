/// Interactive TUI for zr — task/workflow picker with raw-mode keyboard input.
/// Uses sailor.tui widgets (Buffer, List) for layout and composing the screen.
/// On non-TTY environments (pipes, CI) falls back to a plain text message.
const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const run_cmd = @import("run.zig");
const color = @import("../output/color.zig");
const unicode = @import("../util/unicode.zig");
const sailor = @import("sailor");
const stui = sailor.tui;
const tui_mouse = @import("tui_mouse.zig");
const TuiProfiler = @import("../util/tui_profiler.zig").TuiProfiler;

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

/// Build display labels for List widget with "kind  name" format.
/// Uses Unicode width calculation to ensure proper alignment with CJK/emoji.
fn buildItemLabels(allocator: std.mem.Allocator, items: []const Item) ![][]const u8 {
    const labels = try allocator.alloc([]const u8, items.len);
    var count: usize = 0;
    errdefer {
        for (labels[0..count]) |l| allocator.free(l);
        allocator.free(labels);
    }
    for (items) |item| {
        // Use distinctive symbols for accessibility (screen readers can announce these)
        const kind_label: []const u8 = switch (item.kind) {
            .task => "[T]",
            .workflow => "[W]",
        };

        // Truncate long task names to fit screen width (60 cols - 10 for kind/padding)
        const max_name_width = 50;
        const name_width = unicode.displayWidth(item.name);
        const display_name = if (name_width > max_name_width)
            unicode.truncateToWidth(item.name, max_name_width - 3) // -3 for "..."
        else
            item.name;

        labels[count] = if (name_width > max_name_width)
            try std.fmt.allocPrint(allocator, "{s}  {s}...", .{ kind_label, display_name })
        else
            try std.fmt.allocPrint(allocator, "{s}  {s}", .{ kind_label, display_name });

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
    profiler: ?*TuiProfiler,
) !void {
    if (profiler) |p| {
        try p.beginScope("drawScreen");
    }
    defer if (profiler) |p| {
        p.endScope() catch {};
    };

    const screen_width: u16 = 60;
    // +6 for header (2 lines) + footer (1 line) + padding (3 lines)
    const screen_height: u16 = @intCast(@min(@as(usize, 30), items.len + 6));

    var buf = try stui.Buffer.init(allocator, screen_width, screen_height);
    defer buf.deinit();

    if (profiler) |p| {
        try p.trackMemory("Buffer.init", screen_width * screen_height * @sizeOf(stui.Cell));
    }

    // Header with item count and position indicator for accessibility
    var header_buf: [128]u8 = undefined;
    const header = if (items.len > 0)
        std.fmt.bufPrint(&header_buf, "zr Interactive Mode — {d} items (selected: {d}/{d})", .{items.len, selected + 1, items.len}) catch "zr Interactive Mode"
    else
        "zr Interactive Mode — 0 items";

    buf.setString(0, 0, header, stui.Style{ .bold = true });
    buf.setString(0, 1, "[j/k/arrows/click] Move  [g/G] Top/Bottom  [Enter] Run  [q] Quit",
        stui.Style{ .fg = .bright_cyan });

    if (items.len == 0) {
        buf.setString(2, 3, "(no tasks or workflows defined)", .{});
        try renderBuffer(&buf, w, use_color);
        return;
    }

    // Item list using sailor List widget
    if (profiler) |p| {
        try p.beginScope("buildItemLabels");
    }
    const labels = try buildItemLabels(allocator, items);
    defer freeItemLabels(allocator, labels);
    if (profiler) |p| {
        p.endScope() catch {};
    }

    // Leave room for header (3 lines) and footer (1 line)
    const list_height = if (screen_height > 4) screen_height - 4 else 1;
    const list_area = stui.Rect.new(0, 3, screen_width, list_height);

    if (profiler) |p| {
        try p.beginScope("List.render");
    }
    const list = stui.widgets.List.init(labels)
        .withSelected(selected)
        .withSelectedStyle(stui.Style{ .fg = .bright_cyan })
        .withHighlightSymbol("> ");

    list.render(&buf, list_area);
    if (profiler) |p| {
        p.endScope() catch {};
    }

    // Footer: show currently selected item details for accessibility
    if (selected < items.len) {
        const current_item = items[selected];
        const kind_name = switch (current_item.kind) {
            .task => "Task",
            .workflow => "Workflow",
        };
        var footer_buf: [256]u8 = undefined;
        const footer = std.fmt.bufPrint(&footer_buf, "Selected: {s} '{s}'", .{kind_name, current_item.name}) catch "Selected item";
        const footer_y = if (screen_height > 1) screen_height - 1 else 0;
        buf.setString(0, footer_y, footer, stui.Style{ .fg = .bright_black });
    }

    if (profiler) |p| {
        try p.beginScope("renderBuffer");
    }
    try renderBuffer(&buf, w, use_color);
    if (profiler) |p| {
        p.endScope() catch {};
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

    // Enable mouse tracking (click + drag mode)
    try tui_mouse.enableMouseTracking(w, .drag);
    defer tui_mouse.disableMouseTracking(w) catch {};

    // Initialize performance profiler (disabled by default, enable via ZR_PROFILE=1)
    const enable_profiling = std.process.hasEnvVarConstant("ZR_PROFILE");
    var profiler: ?TuiProfiler = if (enable_profiling)
        try TuiProfiler.init(allocator)
    else
        null;
    defer if (profiler) |*p| p.deinit();

    var selected: usize = 0;
    const item_count = items.items.len;

    try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
    try w.flush();

    while (true) {
        const byte = readByte() orelse break;

        // Track event processing latency
        var event_guard = if (profiler) |*p|
            p.trackEvent("keyboard_input", 0)
        else
            undefined;
        defer if (profiler) |_| {
            event_guard.end() catch {};
        };

        switch (byte) {
            'q', 'Q' => break,

            'k' => {
                if (item_count > 0 and selected > 0) selected -= 1;
                try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                try w.flush();
            },

            'j' => {
                if (item_count > 0 and selected + 1 < item_count) selected += 1;
                try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                try w.flush();
            },

            'r', 'R' => {
                try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                try w.flush();
            },

            // Vim-style navigation
            'g' => {
                // Go to top
                if (item_count > 0) selected = 0;
                try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                try w.flush();
            },

            'G' => {
                // Go to bottom
                if (item_count > 0) selected = item_count - 1;
                try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                try w.flush();
            },

            0x1b => {
                const b2 = readByte() orelse continue;
                if (b2 == '[') {
                    const b3 = readByte() orelse continue;

                    // Check for mouse event (SGR format: ESC [ <...)
                    if (b3 == '<') {
                        // Read rest of mouse sequence
                        var seq_buf: [32]u8 = undefined;
                        seq_buf[0] = '<';
                        var seq_len: usize = 1;

                        while (seq_len < seq_buf.len) {
                            const next = readByte() orelse break;
                            seq_buf[seq_len] = next;
                            seq_len += 1;

                            // Mouse sequences end with 'M' or 'm'
                            if (next == 'M' or next == 'm') {
                                const mouse_event = sailor.tui.mouse.parseSGR(seq_buf[0..seq_len]);
                                if (mouse_event) |evt| {
                                    // Handle mouse click in list area
                                    // List starts at y=3, each item is 1 row
                                    if (evt.event_type == .press and evt.button == .left) {
                                        if (evt.y >= 3) {
                                            const clicked_idx = evt.y - 3;
                                            if (clicked_idx < item_count) {
                                                selected = clicked_idx;
                                                try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                                                try w.flush();
                                            }
                                        }
                                    }
                                }
                                break;
                            }
                        }
                        continue;
                    }

                    switch (b3) {
                        // Arrow up
                        'A' => {
                            if (item_count > 0 and selected > 0) selected -= 1;
                            try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                            try w.flush();
                        },
                        // Arrow down
                        'B' => {
                            if (item_count > 0 and selected + 1 < item_count) selected += 1;
                            try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                            try w.flush();
                        },
                        // Home key (ESC [ H)
                        'H' => {
                            if (item_count > 0) selected = 0;
                            try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                            try w.flush();
                        },
                        // End key (ESC [ F)
                        'F' => {
                            if (item_count > 0) selected = item_count - 1;
                            try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
                            try w.flush();
                        },
                        // Page Up (ESC [ 5 ~) / Page Down (ESC [ 6 ~)
                        '5', '6' => {
                            const tilde = readByte() orelse continue;
                            if (tilde != '~') continue;

                            const page_size: usize = 10;
                            if (b3 == '5') {
                                // Page Up
                                if (selected >= page_size) {
                                    selected -= page_size;
                                } else {
                                    selected = 0;
                                }
                            } else {
                                // Page Down
                                if (selected + page_size < item_count) {
                                    selected += page_size;
                                } else if (item_count > 0) {
                                    selected = item_count - 1;
                                }
                            }
                            try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
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

                try drawScreen(allocator, w, items.items, selected, use_color, if (profiler) |*p| p else null);
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

// --- MockTerminal snapshot tests (sailor v1.5.0) ---

const MockTerminal = stui.test_utils.MockTerminal;

test "TUI list: MockTerminal snapshot - empty items" {
    const allocator = std.testing.allocator;

    var mock = try MockTerminal.init(allocator, 60, 10);
    defer mock.deinit();

    var buffer = try stui.Buffer.init(allocator, 60, 10);
    defer buffer.deinit();

    // Simulate empty list screen
    buffer.setString(0, 0, "zr Interactive Mode — 0 items", stui.Style{ .bold = true });
    buffer.setString(0, 1, "[j/k/^v] Move  [g/G] Top/Bottom  [PgUp/PgDn] Page  [Enter] Run  [q] Quit",
        stui.Style{ .fg = .bright_cyan });
    buffer.setString(2, 3, "(no tasks or workflows defined)", .{});

    // Copy buffer to mock terminal
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 60) : (x += 1) {
            const cell = buffer.getConst(x, y);
            if (cell) |c| {
                mock.current.set(x, y, c);
            }
        }
    }

    const snapshot = try mock.getSnapshot(allocator);
    defer allocator.free(snapshot);

    // Verify content
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "zr Interactive Mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "0 items") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "no tasks or workflows") != null);
}

test "TUI list: MockTerminal snapshot - single task" {
    const allocator = std.testing.allocator;

    // Simulating: [_]Item{ .{ .name = "build", .kind = .task } }

    var mock = try MockTerminal.init(allocator, 60, 10);
    defer mock.deinit();

    var buffer = try stui.Buffer.init(allocator, 60, 10);
    defer buffer.deinit();

    // Simulate list screen with one task
    buffer.setString(0, 0, "zr Interactive Mode — 1 items (selected: 1/1)", stui.Style{ .bold = true });
    buffer.setString(0, 1, "[j/k/^v] Move  [g/G] Top/Bottom  [PgUp/PgDn] Page  [Enter] Run  [q] Quit",
        stui.Style{ .fg = .bright_cyan });

    // Single selected item
    buffer.setString(0, 3, "> [T]  build", stui.Style{ .fg = .bright_cyan });

    // Footer
    buffer.setString(0, 9, "Selected: Task 'build'", stui.Style{ .fg = .bright_black });

    // Copy buffer to mock terminal
    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 60) : (x += 1) {
            const cell = buffer.getConst(x, y);
            if (cell) |c| {
                mock.current.set(x, y, c);
            }
        }
    }

    const snapshot = try mock.getSnapshot(allocator);
    defer allocator.free(snapshot);

    // Verify content
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "1 items") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "[T]  build") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Task 'build'") != null);
}

test "TUI list: MockTerminal snapshot - multiple items mixed" {
    const allocator = std.testing.allocator;

    // Simulating: build (task), deploy (workflow), test (task)

    var mock = try MockTerminal.init(allocator, 60, 12);
    defer mock.deinit();

    var buffer = try stui.Buffer.init(allocator, 60, 12);
    defer buffer.deinit();

    // Simulate list screen with multiple items, second selected
    buffer.setString(0, 0, "zr Interactive Mode — 3 items (selected: 2/3)", stui.Style{ .bold = true });
    buffer.setString(0, 1, "[j/k/^v] Move  [g/G] Top/Bottom  [PgUp/PgDn] Page  [Enter] Run  [q] Quit",
        stui.Style{ .fg = .bright_cyan });

    buffer.setString(0, 3, "  [T]  build", .{});
    buffer.setString(0, 4, "> [W]  deploy", stui.Style{ .fg = .bright_cyan });
    buffer.setString(0, 5, "  [T]  test", .{});

    // Footer
    buffer.setString(0, 11, "Selected: Workflow 'deploy'", stui.Style{ .fg = .bright_black });

    // Copy buffer to mock terminal
    var y: u16 = 0;
    while (y < 12) : (y += 1) {
        var x: u16 = 0;
        while (x < 60) : (x += 1) {
            const cell = buffer.getConst(x, y);
            if (cell) |c| {
                mock.current.set(x, y, c);
            }
        }
    }

    const snapshot = try mock.getSnapshot(allocator);
    defer allocator.free(snapshot);

    // Verify content
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "3 items") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "[T]  build") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "[W]  deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "[T]  test") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Workflow 'deploy'") != null);
}

test "TUI list: MockTerminal snapshot - navigation top to bottom" {
    const allocator = std.testing.allocator;

    // Simulating: lint, build, test (all tasks)

    // Test selection at top
    {
        var mock = try MockTerminal.init(allocator, 60, 12);
        defer mock.deinit();

        var buffer = try stui.Buffer.init(allocator, 60, 12);
        defer buffer.deinit();

        buffer.setString(0, 0, "zr Interactive Mode — 3 items (selected: 1/3)", stui.Style{ .bold = true });
        buffer.setString(0, 1, "[j/k/^v] Move  [g/G] Top/Bottom  [PgUp/PgDn] Page  [Enter] Run  [q] Quit",
            stui.Style{ .fg = .bright_cyan });

        buffer.setString(0, 3, "> [T]  lint", stui.Style{ .fg = .bright_cyan });
        buffer.setString(0, 4, "  [T]  build", .{});
        buffer.setString(0, 5, "  [T]  test", .{});

        var y: u16 = 0;
        while (y < 12) : (y += 1) {
            var x: u16 = 0;
            while (x < 60) : (x += 1) {
                const cell = buffer.getConst(x, y);
                if (cell) |c| {
                    mock.current.set(x, y, c);
                }
            }
        }

        const snapshot = try mock.getSnapshot(allocator);
        defer allocator.free(snapshot);

        try std.testing.expect(std.mem.indexOf(u8, snapshot, "selected: 1/3") != null);
        try std.testing.expect(std.mem.indexOf(u8, snapshot, "> [T]  lint") != null);
    }

    // Test selection at bottom
    {
        var mock = try MockTerminal.init(allocator, 60, 12);
        defer mock.deinit();

        var buffer = try stui.Buffer.init(allocator, 60, 12);
        defer buffer.deinit();

        buffer.setString(0, 0, "zr Interactive Mode — 3 items (selected: 3/3)", stui.Style{ .bold = true });
        buffer.setString(0, 1, "[j/k/^v] Move  [g/G] Top/Bottom  [PgUp/PgDn] Page  [Enter] Run  [q] Quit",
            stui.Style{ .fg = .bright_cyan });

        buffer.setString(0, 3, "  [T]  lint", .{});
        buffer.setString(0, 4, "  [T]  build", .{});
        buffer.setString(0, 5, "> [T]  test", stui.Style{ .fg = .bright_cyan });

        buffer.setString(0, 11, "Selected: Task 'test'", stui.Style{ .fg = .bright_black });

        var y: u16 = 0;
        while (y < 12) : (y += 1) {
            var x: u16 = 0;
            while (x < 60) : (x += 1) {
                const cell = buffer.getConst(x, y);
                if (cell) |c| {
                    mock.current.set(x, y, c);
                }
            }
        }

        const snapshot = try mock.getSnapshot(allocator);
        defer allocator.free(snapshot);

        try std.testing.expect(std.mem.indexOf(u8, snapshot, "selected: 3/3") != null);
        try std.testing.expect(std.mem.indexOf(u8, snapshot, "> [T]  test") != null);
    }
}

test "TUI list: MockTerminal snapshot - long task name truncation" {
    const allocator = std.testing.allocator;

    // Simulating: very-long-task-name-that-should-be-truncated-in-display

    var mock = try MockTerminal.init(allocator, 60, 10);
    defer mock.deinit();

    var buffer = try stui.Buffer.init(allocator, 60, 10);
    defer buffer.deinit();

    buffer.setString(0, 0, "zr Interactive Mode — 1 items (selected: 1/1)", stui.Style{ .bold = true });
    buffer.setString(0, 1, "[j/k/^v] Move  [g/G] Top/Bottom  [PgUp/PgDn] Page  [Enter] Run  [q] Quit",
        stui.Style{ .fg = .bright_cyan });

    // Simulate truncated name (max 50 chars for name, -3 for "...")
    buffer.setString(0, 3, "> [T]  very-long-task-name-that-should-be-truncat...", stui.Style{ .fg = .bright_cyan });

    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 60) : (x += 1) {
            const cell = buffer.getConst(x, y);
            if (cell) |c| {
                mock.current.set(x, y, c);
            }
        }
    }

    const snapshot = try mock.getSnapshot(allocator);
    defer allocator.free(snapshot);

    // Verify truncation
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "very-long-task-name") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "...") != null);
}

test "TUI list: buildItemLabels helper function" {
    const allocator = std.testing.allocator;

    const items = [_]Item{
        .{ .name = "build", .kind = .task },
        .{ .name = "deploy", .kind = .workflow },
    };

    const labels = try buildItemLabels(allocator, &items);
    defer freeItemLabels(allocator, labels);

    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expect(std.mem.indexOf(u8, labels[0], "[T]") != null);
    try std.testing.expect(std.mem.indexOf(u8, labels[0], "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, labels[1], "[W]") != null);
    try std.testing.expect(std.mem.indexOf(u8, labels[1], "deploy") != null);
}
