/// Interactive task picker TUI for zr — selects tasks with fuzzy search & metadata preview.
/// Used by `zr run` (no args) and `zr interactive` commands.
/// Features: real-time fuzzy search, keyboard navigation, metadata preview pane.
const std = @import("std");
const builtin = @import("builtin");
const config_mod = @import("../config/types.zig");
const levenshtein = @import("../util/levenshtein.zig");
const sailor = @import("sailor");
const stui = sailor.tui;

const TaskConfig = config_mod.TaskConfig;
const WorkflowConfig = config_mod.WorkflowConfig;
const Config = config_mod.Config;

const IS_POSIX = builtin.os.tag != .windows;

/// Item type in picker (task or workflow)
pub const ItemKind = enum { task, workflow };

/// Picker item with metadata
pub const PickerItem = struct {
    name: []const u8,
    kind: ItemKind,
    /// Fuzzy search score (lower = better match, 0 = exact)
    score: usize = 0,
};

/// Picker configuration
pub const PickerConfig = struct {
    /// Enable fuzzy search filtering
    fuzzy_search: bool = true,
    /// Show metadata preview pane
    show_preview: bool = true,
    /// Initial search query
    initial_query: []const u8 = "",
};

/// Picker result
pub const PickerResult = struct {
    /// Selected item name
    name: []const u8,
    /// Selected item kind
    kind: ItemKind,
    /// Whether user executed (Enter) or cancelled (q/Esc)
    executed: bool,
};

/// Raw terminal mode helpers (POSIX only)
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

/// Fuzzy search: filter items by query using Levenshtein distance
fn fuzzyFilter(
    allocator: std.mem.Allocator,
    all_items: []const PickerItem,
    query: []const u8,
) !std.ArrayList(PickerItem) {
    var filtered: std.ArrayList(PickerItem) = .{};
    errdefer filtered.deinit(allocator);

    const max_distance: usize = 3;

    for (all_items) |item| {
        if (query.len == 0) {
            // No query — include all with score 0
            try filtered.append(allocator, .{ .name = item.name, .kind = item.kind, .score = 0 });
            continue;
        }

        // Case-insensitive substring match (score = 0 for exact substring)
        if (std.ascii.indexOfIgnoreCase(item.name, query) != null) {
            try filtered.append(allocator, .{ .name = item.name, .kind = item.kind, .score = 0 });
            continue;
        }

        // Levenshtein distance match (score = distance)
        const distance = levenshtein.distance(allocator, item.name, query) catch max_distance + 1;
        if (distance <= max_distance) {
            try filtered.append(allocator, .{ .name = item.name, .kind = item.kind, .score = distance });
        }
    }

    // Sort by score (lower first), then alphabetically
    std.mem.sort(PickerItem, filtered.items, {}, itemLessThan);

    return filtered;
}

fn itemLessThan(_: void, a: PickerItem, b: PickerItem) bool {
    if (a.score != b.score) return a.score < b.score;
    return std.mem.lessThan(u8, a.name, b.name);
}

/// Render picker UI to buffer
fn renderPicker(
    allocator: std.mem.Allocator,
    buf: *stui.Buffer,
    items: []const PickerItem,
    selected: usize,
    query: []const u8,
    config: *const Config,
    show_preview: bool,
) !void {
    const screen_width = buf.width;
    const screen_height = buf.height;

    // Header
    var header_buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "zr Task Picker — {d} items", .{items.len}) catch "zr Task Picker";
    buf.setString(0, 0, header, stui.Style{ .bold = true });

    // Search query line
    var query_buf: [256]u8 = undefined;
    const query_line = std.fmt.bufPrint(&query_buf, "Search: {s}_", .{query}) catch "Search: ";
    buf.setString(0, 1, query_line, stui.Style{ .fg = .bright_cyan });

    // Keyboard shortcuts
    buf.setString(0, 2, "[arrows/j/k] Move  [/] Search  [Enter] Run  [q] Quit",
        stui.Style{ .fg = .bright_black });

    // Item list (left side or full width)
    const list_width = if (show_preview and screen_width > 60) screen_width / 2 else screen_width;
    const list_height = if (screen_height > 4) screen_height - 4 else 1;
    const list_area = stui.Rect.new(0, 3, list_width, list_height);

    if (items.len > 0) {
        const labels = try buildItemLabels(allocator, items);
        defer freeItemLabels(allocator, labels);

        const list = stui.widgets.List.init(labels)
            .withSelected(selected)
            .withSelectedStyle(stui.Style{ .fg = .bright_cyan, .bold = true })
            .withHighlightSymbol("> ");

        list.render(buf, list_area);
    } else {
        buf.setString(2, 4, "(no matching tasks)", stui.Style{ .fg = .bright_black });
    }

    // Metadata preview pane (right side)
    if (show_preview and screen_width > 60 and items.len > 0 and selected < items.len) {
        const preview_x = list_width + 1;
        const preview_width = screen_width - preview_x;
        try renderPreviewPane(allocator, buf, preview_x, 3, preview_width, list_height, items[selected], config);
    }

    // Footer
    const footer_y = if (screen_height > 1) screen_height - 1 else 0;
    if (items.len > 0 and selected < items.len) {
        const current_item = items[selected];
        const kind_name = switch (current_item.kind) {
            .task => "Task",
            .workflow => "Workflow",
        };
        var footer_buf: [256]u8 = undefined;
        const footer = std.fmt.bufPrint(&footer_buf, "Selected: {s} '{s}' (score: {d})", .{kind_name, current_item.name, current_item.score}) catch "Selected";
        buf.setString(0, footer_y, footer, stui.Style{ .fg = .bright_black });
    }
}

/// Render metadata preview pane
fn renderPreviewPane(
    allocator: std.mem.Allocator,
    buf: *stui.Buffer,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    item: PickerItem,
    config: *const Config,
) !void {
    _ = allocator; // reserved for future use

    var line: u16 = y;
    const max_line = y + height;

    // Draw separator (vertical line)
    var sep_y: u16 = y;
    while (sep_y < max_line) : (sep_y += 1) {
        buf.setString(x - 1, sep_y, "│", .{});
    }

    // Item name header
    buf.setString(x, line, item.name, stui.Style{ .bold = true, .fg = .bright_cyan });
    line += 1;
    if (line >= max_line) return;

    // Item kind
    const kind_str = switch (item.kind) {
        .task => "Task",
        .workflow => "Workflow",
    };
    var kind_buf: [64]u8 = undefined;
    const kind_line = std.fmt.bufPrint(&kind_buf, "Type: {s}", .{kind_str}) catch "Type: Unknown";
    buf.setString(x, line, kind_line, stui.Style{ .fg = .bright_black });
    line += 2;
    if (line >= max_line) return;

    // Task metadata
    if (item.kind == .task) {
        const task = config.tasks.get(item.name) orelse return;

        // Command
        buf.setString(x, line, "Command:", stui.Style{ .bold = true });
        line += 1;
        if (line >= max_line) return;

        // Wrap command if too long
        const cmd = task.cmd;
        const cmd_display = if (cmd.len > width - 2) cmd[0..@min(cmd.len, width - 5)] else cmd;
        buf.setString(x + 2, line, cmd_display, stui.Style{ .fg = .bright_black });
        line += 1;
        if (line >= max_line) return;

        // Description
        if (task.description) |desc| {
            line += 1;
            if (line >= max_line) return;
            buf.setString(x, line, "Description:", stui.Style{ .bold = true });
            line += 1;
            if (line >= max_line) return;

            const desc_display = if (desc.len > width - 2) desc[0..@min(desc.len, width - 5)] else desc;
            buf.setString(x + 2, line, desc_display, stui.Style{ .fg = .bright_black });
            line += 1;
            if (line >= max_line) return;
        }

        // Dependencies
        if (task.deps.len > 0) {
            line += 1;
            if (line >= max_line) return;
            buf.setString(x, line, "Dependencies:", stui.Style{ .bold = true });
            line += 1;
            if (line >= max_line) return;

            for (task.deps) |dep| {
                if (line >= max_line) break;
                var dep_buf: [128]u8 = undefined;
                const dep_line = std.fmt.bufPrint(&dep_buf, "  • {s}", .{dep}) catch dep;
                buf.setString(x + 2, line, dep_line, stui.Style{ .fg = .bright_black });
                line += 1;
            }
        }

        // Tags
        if (task.tags.len > 0) {
            line += 1;
            if (line >= max_line) return;
            buf.setString(x, line, "Tags:", stui.Style{ .bold = true });
            line += 1;
            if (line >= max_line) return;

            var tag_buf: [256]u8 = undefined;
            var tag_stream = std.io.fixedBufferStream(&tag_buf);
            for (task.tags, 0..) |tag, i| {
                tag_stream.writer().print("{s}{s}", .{if (i > 0) ", " else "", tag}) catch break;
            }
            const tag_line = tag_stream.getWritten();
            buf.setString(x + 2, line, tag_line, stui.Style{ .fg = .bright_black });
        }
    }
}

/// Build item labels for List widget
fn buildItemLabels(allocator: std.mem.Allocator, items: []const PickerItem) ![][]const u8 {
    const labels = try allocator.alloc([]const u8, items.len);
    for (items, 0..) |item, i| {
        const prefix = switch (item.kind) {
            .task => "[T]",
            .workflow => "[W]",
        };
        labels[i] = try std.fmt.allocPrint(allocator, "{s} {s}", .{prefix, item.name});
    }
    return labels;
}

fn freeItemLabels(allocator: std.mem.Allocator, labels: [][]const u8) void {
    for (labels) |label| {
        allocator.free(label);
    }
    allocator.free(labels);
}

/// Render buffer to terminal
fn renderBuffer(buf: *stui.Buffer, w: anytype) !void {
    try w.writeAll("\x1b[2J\x1b[H"); // Clear screen + cursor home

    var y: u16 = 0;
    while (y < buf.height) : (y += 1) {
        var x: u16 = 0;
        while (x < buf.width) : (x += 1) {
            const cell = buf.getConst(x, y) orelse continue;

            // Emit style codes
            if (cell.style.bold) try w.writeAll("\x1b[1m");
            if (cell.style.fg) |fg| {
                switch (fg) {
                    .red => try w.writeAll("\x1b[31m"),
                    .green => try w.writeAll("\x1b[32m"),
                    .yellow => try w.writeAll("\x1b[33m"),
                    .blue => try w.writeAll("\x1b[34m"),
                    .magenta => try w.writeAll("\x1b[35m"),
                    .cyan => try w.writeAll("\x1b[36m"),
                    .white => try w.writeAll("\x1b[37m"),
                    .bright_red => try w.writeAll("\x1b[91m"),
                    .bright_green => try w.writeAll("\x1b[92m"),
                    .bright_yellow => try w.writeAll("\x1b[93m"),
                    .bright_blue => try w.writeAll("\x1b[94m"),
                    .bright_cyan => try w.writeAll("\x1b[96m"),
                    .bright_white => try w.writeAll("\x1b[97m"),
                    else => {},
                }
            }

            // Emit character
            var utf8_buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch 1;
            try w.writeAll(utf8_buf[0..len]);

            // Reset style
            if (cell.style.bold or cell.style.fg != null) {
                try w.writeAll("\x1b[0m");
            }
        }
        try w.writeAll("\n");
    }
}

/// Run interactive picker and return selected item
pub fn runPicker(
    allocator: std.mem.Allocator,
    config: *const Config,
    picker_config: PickerConfig,
    w: anytype,
) !PickerResult {
    // Collect all items
    var all_items: std.ArrayList(PickerItem) = .{};
    defer all_items.deinit(allocator);

    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        try all_items.append(allocator, .{ .name = entry.key_ptr.*, .kind = .task });
    }

    var wf_it = config.workflows.iterator();
    while (wf_it.next()) |entry| {
        try all_items.append(allocator, .{ .name = entry.key_ptr.*, .kind = .workflow });
    }

    // Sort alphabetically
    std.mem.sort(PickerItem, all_items.items, {}, itemLessThan);

    // Initial fuzzy filter
    var query: std.ArrayList(u8) = .{};
    defer query.deinit(allocator);
    try query.appendSlice(allocator, picker_config.initial_query);

    var filtered = try fuzzyFilter(allocator, all_items.items, query.items);
    defer filtered.deinit(allocator);

    var selected: usize = 0;

    // Enter raw mode
    const original = try enterRawMode();
    defer leaveRawMode(original);

    // TUI event loop
    const screen_width: u16 = if (picker_config.show_preview) 100 else 60;
    const screen_height: u16 = 30;

    var buf = try stui.Buffer.init(allocator, screen_width, screen_height);
    defer buf.deinit();

    var search_mode = false;

    while (true) {
        // Render current state
        try renderPicker(allocator, &buf, filtered.items, selected, query.items, config, picker_config.show_preview);
        try renderBuffer(&buf, w);

        // Read input
        const byte = readByte() orelse continue;

        // Handle search mode
        if (search_mode) {
            if (byte == 27) { // Esc
                search_mode = false;
                continue;
            } else if (byte == 13) { // Enter
                search_mode = false;
                // Refilter with query
                filtered.deinit(allocator);
                filtered = try fuzzyFilter(allocator, all_items.items, query.items);
                selected = 0;
                continue;
            } else if (byte == 127 or byte == 8) { // Backspace
                if (query.items.len > 0) {
                    _ = query.pop();
                    // Real-time filtering
                    filtered.deinit(allocator);
                    filtered = try fuzzyFilter(allocator, all_items.items, query.items);
                    selected = 0;
                }
                continue;
            } else if (byte >= 32 and byte < 127) { // Printable char
                try query.append(allocator, byte);
                // Real-time filtering
                filtered.deinit(allocator);
                filtered = try fuzzyFilter(allocator, all_items.items, query.items);
                selected = 0;
                continue;
            }
        }

        // Normal mode navigation
        switch (byte) {
            'q' => {
                return PickerResult{ .name = "", .kind = .task, .executed = false };
            },
            '/' => {
                search_mode = true;
                query.clearRetainingCapacity();
            },
            'j', 66 => { // j or Down arrow
                if (filtered.items.len > 0) {
                    selected = @min(selected + 1, filtered.items.len - 1);
                }
            },
            'k', 65 => { // k or Up arrow
                if (selected > 0) {
                    selected -= 1;
                }
            },
            'g' => {
                selected = 0;
            },
            'G' => {
                if (filtered.items.len > 0) {
                    selected = filtered.items.len - 1;
                }
            },
            13 => { // Enter
                if (filtered.items.len > 0 and selected < filtered.items.len) {
                    const item = filtered.items[selected];
                    return PickerResult{ .name = item.name, .kind = item.kind, .executed = true };
                }
            },
            27 => { // Esc
                if (search_mode) {
                    search_mode = false;
                }
            },
            else => {},
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "fuzzyFilter exact substring match" {
    const allocator = std.testing.allocator;

    const items = [_]PickerItem{
        .{ .name = "build", .kind = .task },
        .{ .name = "test-build", .kind = .task },
        .{ .name = "deploy", .kind = .workflow },
    };

    const items_slice: []const PickerItem = &items;
    var filtered = try fuzzyFilter(allocator, items_slice, "build");
    defer filtered.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), filtered.items.len);
    try std.testing.expectEqualStrings("build", filtered.items[0].name);
    try std.testing.expectEqual(@as(usize, 0), filtered.items[0].score);
}

test "fuzzyFilter Levenshtein distance" {
    const allocator = std.testing.allocator;

    const items = [_]PickerItem{
        .{ .name = "build", .kind = .task },
        .{ .name = "biuld", .kind = .task }, // distance 2
        .{ .name = "deploy", .kind = .workflow },
    };

    const items_slice: []const PickerItem = &items;
    var filtered = try fuzzyFilter(allocator, items_slice, "build");
    defer filtered.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), filtered.items.len);
    try std.testing.expectEqualStrings("build", filtered.items[0].name);
    try std.testing.expectEqualStrings("biuld", filtered.items[1].name);
}

test "fuzzyFilter empty query returns all" {
    const allocator = std.testing.allocator;

    const items = [_]PickerItem{
        .{ .name = "build", .kind = .task },
        .{ .name = "test", .kind = .task },
    };

    const items_slice: []const PickerItem = &items;
    var filtered = try fuzzyFilter(allocator, items_slice, "");
    defer filtered.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), filtered.items.len);
}

test "fuzzyFilter no matches" {
    const allocator = std.testing.allocator;

    const items = [_]PickerItem{
        .{ .name = "build", .kind = .task },
        .{ .name = "test", .kind = .task },
    };

    const items_slice: []const PickerItem = &items;
    var filtered = try fuzzyFilter(allocator, items_slice, "xxxxxxxxx");
    defer filtered.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), filtered.items.len);
}
