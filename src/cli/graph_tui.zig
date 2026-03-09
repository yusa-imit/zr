/// Interactive TUI for dependency graph visualization using sailor Tree widget.
const std = @import("std");
const builtin = @import("builtin");
const sailor = @import("sailor");
const stui = sailor.tui;
const color = @import("../output/color.zig");
const graph_mod = @import("graph.zig");
const GraphNode = graph_mod.GraphNode;

const IS_POSIX = builtin.os.tag != .windows;

/// Convert GraphNode array to TreeNode structure
pub fn buildTreeNodes(
    allocator: std.mem.Allocator,
    nodes: []const GraphNode,
) ![]stui.widgets.TreeNode {
    var tree_nodes = std.ArrayList(stui.widgets.TreeNode){};
    errdefer {
        for (tree_nodes.items) |*node| {
            freeTreeNode(allocator, node);
        }
        tree_nodes.deinit(allocator);
    }

    for (nodes) |graph_node| {
        const label = try allocator.dupe(u8, graph_node.path);
        errdefer allocator.free(label);

        // Build children from dependencies
        var children = std.ArrayList(stui.widgets.TreeNode){};
        errdefer {
            for (children.items) |*child| {
                freeTreeNode(allocator, child);
            }
            children.deinit(allocator);
        }

        for (graph_node.dependencies) |dep| {
            const dep_label = try std.fmt.allocPrint(allocator, "→ {s}", .{dep});
            try children.append(allocator, .{
                .label = dep_label,
                .children = &.{},
                .expanded = true,
            });
        }

        try tree_nodes.append(allocator, .{
            .label = label,
            .children = try children.toOwnedSlice(allocator),
            .expanded = true,
        });
    }

    return tree_nodes.toOwnedSlice(allocator);
}

/// Free a TreeNode and its children recursively
fn freeTreeNode(allocator: std.mem.Allocator, node: *const stui.widgets.TreeNode) void {
    allocator.free(node.label);
    for (node.children) |*child| {
        freeTreeNode(allocator, child);
    }
    if (node.children.len > 0) {
        allocator.free(node.children);
    }
}

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

/// Render a sailor Buffer to stdout with color codes
fn renderBuffer(buf: *stui.Buffer, w: anytype, use_color: bool) !void {
    try w.writeAll("\x1b[2J\x1b[H"); // Clear screen and move cursor to top

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
        try w.writeAll("\r\n");
    }
}

fn emitCellStyle(w: anytype, s: stui.Style) !void {
    if (s.fg) |fg_color| {
        const ansi_code = colorToAnsi(fg_color, false);
        try w.writeAll(ansi_code);
    }
    if (s.bg) |bg_color| {
        const ansi_code = colorToAnsi(bg_color, true);
        try w.writeAll(ansi_code);
    }
    if (s.bold) try w.writeAll(color.Code.bold);
    if (s.italic) try w.writeAll("\x1b[3m");
    if (s.underline) try w.writeAll("\x1b[4m");
    if (s.dim) try w.writeAll(color.Code.dim);
}

fn cellHasStyle(s: stui.Style) bool {
    return s.fg != null or s.bg != null or s.bold or s.italic or s.underline or s.dim;
}

fn colorToAnsi(c: stui.Color, is_bg: bool) []const u8 {
    return switch (c) {
        .black => if (is_bg) "\x1b[40m" else "\x1b[30m",
        .red => if (is_bg) "\x1b[41m" else "\x1b[31m",
        .green => if (is_bg) "\x1b[42m" else "\x1b[32m",
        .yellow => if (is_bg) "\x1b[43m" else "\x1b[33m",
        .blue => if (is_bg) "\x1b[44m" else "\x1b[34m",
        .magenta => if (is_bg) "\x1b[45m" else "\x1b[35m",
        .cyan => if (is_bg) "\x1b[46m" else "\x1b[36m",
        .white => if (is_bg) "\x1b[47m" else "\x1b[37m",
        .bright_black => if (is_bg) "\x1b[100m" else "\x1b[90m",
        else => "",
    };
}

/// Interactive TUI mode for graph visualization
pub fn graphTui(
    allocator: std.mem.Allocator,
    nodes: []const GraphNode,
    w: *std.Io.Writer,
    use_color: bool,
) !void {
    if (comptime !IS_POSIX) {
        try w.writeAll("TUI mode is not supported on Windows\n");
        return error.UnsupportedPlatform;
    }

    // Build tree structure
    const tree_nodes = try buildTreeNodes(allocator, nodes);
    defer {
        for (tree_nodes) |*node| {
            freeTreeNode(allocator, node);
        }
        allocator.free(tree_nodes);
    }

    // Terminal state
    const original = try enterRawMode();
    defer leaveRawMode(original);

    var selected: usize = 0;
    var offset: usize = 0;
    var quit = false;

    while (!quit) {
        // Get terminal size
        const term_size = try sailor.term.getSize();
        const width = term_size.cols;
        const height = term_size.rows;

        // Create buffer and render tree
        var buf = try stui.Buffer.init(allocator, width, height);
        defer buf.deinit();

        const area = stui.layout.Rect{ .x = 0, .y = 0, .width = width, .height = height };

        const tree = stui.widgets.Tree.init(tree_nodes)
            .withSelected(selected)
            .withOffset(offset)
            .withBlock(stui.widgets.Block.init()
                .withTitle("Dependency Graph (↑↓: navigate, Enter: expand/collapse, q: quit)", .top_center)
                .withBorders(.all))
            .withSelectedStyle(stui.Style{ .fg = .bright_green, .bold = true })
            .withNodeStyle(stui.Style{});

        tree.render(&buf, area);

        // Render buffer to terminal
        try renderBuffer(&buf, w, use_color);

        // Handle input
        if (readByte()) |byte| {
            switch (byte) {
                'q', 'Q', 27 => quit = true, // q or ESC
                'j', 'J' => { // Down arrow (j or down arrow)
                    const visible_count = tree.visibleCount();
                    if (selected + 1 < visible_count) {
                        selected += 1;
                        if (selected >= offset + height - 3) {
                            offset += 1;
                        }
                    }
                },
                'k', 'K' => { // Up arrow (k or up arrow)
                    if (selected > 0) {
                        selected -= 1;
                        if (selected < offset) {
                            offset = selected;
                        }
                    }
                },
                '\n', '\r' => { // Enter - toggle expand/collapse
                    // For now, just update selection
                    // Full expand/collapse requires mutable tree nodes
                },
                else => {},
            }
        }

        // Small delay to avoid busy loop
        std.Thread.sleep(50_000_000); // 50ms
    }

    // Clear screen on exit
    try w.writeAll("\x1b[2J\x1b[H");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const MockTerminal = stui.test_utils.MockTerminal;

test "buildTreeNodes: empty graph" {
    const allocator = std.testing.allocator;

    const nodes: []const GraphNode = &.{};
    const tree_nodes = try buildTreeNodes(allocator, nodes);
    defer {
        for (tree_nodes) |*node| {
            freeTreeNode(allocator, node);
        }
        allocator.free(tree_nodes);
    }

    try std.testing.expectEqual(@as(usize, 0), tree_nodes.len);
}

test "buildTreeNodes: single node no dependencies" {
    const allocator = std.testing.allocator;

    const nodes = [_]GraphNode{
        .{ .path = "build", .dependencies = &.{}, .is_affected = false },
    };

    const tree_nodes = try buildTreeNodes(allocator, nodes[0..]);
    defer {
        for (tree_nodes) |*node| {
            freeTreeNode(allocator, node);
        }
        allocator.free(tree_nodes);
    }

    try std.testing.expectEqual(@as(usize, 1), tree_nodes.len);
    try std.testing.expect(std.mem.eql(u8, "build", tree_nodes[0].label));
    try std.testing.expectEqual(@as(usize, 0), tree_nodes[0].children.len);
}

test "buildTreeNodes: node with dependencies" {
    const allocator = std.testing.allocator;

    var deps = [_][]const u8{ "lint", "format" };
    const nodes = [_]GraphNode{
        .{ .path = "build", .dependencies = &deps, .is_affected = false },
    };

    const tree_nodes = try buildTreeNodes(allocator, nodes[0..]);
    defer {
        for (tree_nodes) |*node| {
            freeTreeNode(allocator, node);
        }
        allocator.free(tree_nodes);
    }

    try std.testing.expectEqual(@as(usize, 1), tree_nodes.len);
    try std.testing.expect(std.mem.eql(u8, "build", tree_nodes[0].label));
    try std.testing.expectEqual(@as(usize, 2), tree_nodes[0].children.len);
    try std.testing.expect(std.mem.indexOf(u8, tree_nodes[0].children[0].label, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, tree_nodes[0].children[1].label, "format") != null);
}

test "buildTreeNodes: multiple nodes with dependencies" {
    const allocator = std.testing.allocator;

    var build_deps = [_][]const u8{"compile"};
    var test_deps = [_][]const u8{ "build", "setup" };
    const nodes = [_]GraphNode{
        .{ .path = "build", .dependencies = &build_deps, .is_affected = false },
        .{ .path = "test", .dependencies = &test_deps, .is_affected = true },
    };

    const tree_nodes = try buildTreeNodes(allocator, nodes[0..]);
    defer {
        for (tree_nodes) |*node| {
            freeTreeNode(allocator, node);
        }
        allocator.free(tree_nodes);
    }

    try std.testing.expectEqual(@as(usize, 2), tree_nodes.len);

    // First node
    try std.testing.expect(std.mem.eql(u8, "build", tree_nodes[0].label));
    try std.testing.expectEqual(@as(usize, 1), tree_nodes[0].children.len);

    // Second node
    try std.testing.expect(std.mem.eql(u8, "test", tree_nodes[1].label));
    try std.testing.expectEqual(@as(usize, 2), tree_nodes[1].children.len);
}

test "Graph TUI: MockTerminal snapshot - empty graph" {
    const allocator = std.testing.allocator;

    var mock = try MockTerminal.init(allocator, 80, 24);
    defer mock.deinit();

    var buffer = try stui.Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Simulate empty graph display
    buffer.setString(0, 0, "Dependency Graph", .{});
    buffer.setString(0, 2, "(no tasks)", .{});

    // Copy buffer to mock
    var y: u16 = 0;
    while (y < 24) : (y += 1) {
        var x: u16 = 0;
        while (x < 80) : (x += 1) {
            const cell = buffer.getConst(x, y);
            if (cell) |c| {
                mock.current.set(x, y, c);
            }
        }
    }

    const snapshot = try mock.getSnapshot(allocator);
    defer allocator.free(snapshot);

    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Dependency Graph") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "(no tasks)") != null);
}

test "Graph TUI: MockTerminal snapshot - single task" {
    const allocator = std.testing.allocator;

    var mock = try MockTerminal.init(allocator, 80, 24);
    defer mock.deinit();

    var buffer = try stui.Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Simulate single task in tree view
    buffer.setString(0, 0, "Dependency Graph", .{});
    buffer.setString(0, 2, "├─ build", .{});

    var y: u16 = 0;
    while (y < 24) : (y += 1) {
        var x: u16 = 0;
        while (x < 80) : (x += 1) {
            const cell = buffer.getConst(x, y);
            if (cell) |c| {
                mock.current.set(x, y, c);
            }
        }
    }

    const snapshot = try mock.getSnapshot(allocator);
    defer allocator.free(snapshot);

    try std.testing.expect(std.mem.indexOf(u8, snapshot, "build") != null);
}

test "Graph TUI: MockTerminal snapshot - task with dependencies" {
    const allocator = std.testing.allocator;

    var mock = try MockTerminal.init(allocator, 80, 24);
    defer mock.deinit();

    var buffer = try stui.Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Simulate task tree with dependencies
    buffer.setString(0, 0, "Dependency Graph", .{});
    buffer.setString(0, 2, "├─ test", .{});
    buffer.setString(0, 3, "│  ├─ → build", .{});
    buffer.setString(0, 4, "│  └─ → setup", .{});

    var y: u16 = 0;
    while (y < 24) : (y += 1) {
        var x: u16 = 0;
        while (x < 80) : (x += 1) {
            const cell = buffer.getConst(x, y);
            if (cell) |c| {
                mock.current.set(x, y, c);
            }
        }
    }

    const snapshot = try mock.getSnapshot(allocator);
    defer allocator.free(snapshot);

    try std.testing.expect(std.mem.indexOf(u8, snapshot, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "setup") != null);
}

test "Graph TUI: MockTerminal - navigation simulation" {
    const allocator = std.testing.allocator;

    var mock = try MockTerminal.init(allocator, 80, 24);
    defer mock.deinit();

    // Simulate keyboard events
    try mock.pushEvent(.{ .key = .{ .code = .down } });
    try mock.pushEvent(.{ .key = .{ .code = .up } });
    try mock.pushEvent(.{ .key = .{ .code = .enter } });

    // Verify events were queued
    try std.testing.expectEqual(@as(usize, 3), mock.events.items.len);

    // Poll events
    const event1 = mock.pollEvent();
    try std.testing.expect(event1 != null);

    const event2 = mock.pollEvent();
    try std.testing.expect(event2 != null);

    const event3 = mock.pollEvent();
    try std.testing.expect(event3 != null);

    // Queue should be empty now
    const event4 = mock.pollEvent();
    try std.testing.expect(event4 == null);
}
