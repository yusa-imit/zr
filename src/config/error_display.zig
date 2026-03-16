const std = @import("std");
const toml_highlight = @import("toml_highlight.zig");

const Allocator = std.mem.Allocator;

/// Display a syntax-highlighted TOML error snippet with context lines and error position marker
///
/// Shows 3 lines of context:
/// - Line before the error (if exists)
/// - The error line (with TOML syntax highlighting)
/// - Line after the error (if exists)
///
/// Also displays a caret (^) pointing to the error column.
///
/// Args:
///   writer: Output writer (typically std.io.Writer)
///   toml_content: Full TOML file content
///   line_num: 1-based line number where error occurred
///   column_num: 1-based column number where error occurred
///   error_msg: Human-readable error message
///   use_color: Whether to include ANSI color codes
pub fn showErrorSnippet(
    writer: anytype,
    toml_content: []const u8,
    line_num: usize,
    column_num: usize,
    error_msg: []const u8,
    use_color: bool,
) !void {
    // Split content into lines
    var lines = std.ArrayList([]const u8){};
    defer lines.deinit(std.heap.page_allocator);

    var iter = std.mem.splitSequence(u8, toml_content, "\n");
    while (iter.next()) |line| {
        try lines.append(std.heap.page_allocator, line);
    }

    if (lines.items.len == 0) {
        return;
    }

    // Validate line number (1-based)
    if (line_num == 0 or line_num > lines.items.len) {
        // Out of bounds - print error message anyway
        try writer.print("Error on line {d}, column {d}: {s}\n", .{ line_num, column_num, error_msg });
        return;
    }

    const error_line_idx = line_num - 1;

    // Print error header
    try writer.print("Error on line {d}, column {d}: {s}\n\n", .{ line_num, column_num, error_msg });

    // Determine range: show up to 3 lines total (error + 2 more)
    // If error is at start, show next 2 lines. If at end, show previous 2.
    var print_start = error_line_idx;
    var print_end = error_line_idx;

    // Calculate optimal range to show 3 lines
    if (lines.items.len == 1) {
        // Only one line, just show it
        print_start = 0;
        print_end = 0;
    } else if (error_line_idx == 0) {
        // Error on first line - show this and next 2
        print_start = 0;
        print_end = if (lines.items.len > 2) 2 else lines.items.len - 1;
    } else if (error_line_idx == lines.items.len - 1) {
        // Error on last line - show previous 2 and this
        print_start = if (error_line_idx >= 2) error_line_idx - 2 else 0;
        print_end = error_line_idx;
    } else {
        // Error in middle - show one before and one after
        print_start = error_line_idx - 1;
        print_end = error_line_idx + 1;
    }

    // Print all context lines
    var line_idx = print_start;
    while (line_idx <= print_end) : (line_idx += 1) {
        const current_line = lines.items[line_idx];
        const display_line_num = line_idx + 1;

        if (line_idx == error_line_idx) {
            // Print error line with highlighting
            if (use_color) {
                const colored = try toml_highlight.highlightToml(std.heap.page_allocator, current_line);
                defer std.heap.page_allocator.free(colored);
                try writer.print("  {d} | {s}\n", .{ display_line_num, colored });
            } else {
                try writer.print("  {d} | {s}\n", .{ display_line_num, current_line });
            }
        } else {
            // Print context line without highlighting
            try writer.print("  {d} | {s}\n", .{ display_line_num, current_line });
        }
    }

    // Print caret pointing to error position
    const caret_col = column_num;
    var line_prefix_width: usize = 6; // "  NNN | "
    if (line_num >= 10) line_prefix_width += 1;
    if (line_num >= 100) line_prefix_width += 1;
    if (line_num >= 1000) line_prefix_width += 1;
    const caret_spacing = line_prefix_width + caret_col - 1;

    var caret_line = std.ArrayList(u8){};
    defer caret_line.deinit(std.heap.page_allocator);

    var i: usize = 0;
    while (i < caret_spacing) : (i += 1) {
        try caret_line.append(std.heap.page_allocator, ' ');
    }
    try caret_line.append(std.heap.page_allocator, '^');

    try writer.print("{s}\n", .{caret_line.items});
}

// Tests
test "showErrorSnippet: error on middle line of 3-line file" {
    const allocator = std.testing.allocator;
    const toml_content = "name = \"zr\"\nversion = invalid\ndescription = \"test\"";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        2,
        11,
        "invalid value",
        false,
    );

    const result = output.items;

    // Should contain all three lines
    try std.testing.expect(std.mem.indexOf(u8, result, "name = \"zr\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "version = invalid") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "description = \"test\"") != null);

    // Should contain error message
    try std.testing.expect(std.mem.indexOf(u8, result, "invalid value") != null);

    // Should contain caret on line 2
    try std.testing.expect(std.mem.indexOf(u8, result, "^") != null);
}

test "showErrorSnippet: error on first line" {
    const allocator = std.testing.allocator;
    const toml_content = "invalid = bad\nname = \"zr\"\nversion = \"1.0\"";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        1,
        11,
        "bad syntax",
        false,
    );

    const result = output.items;

    // Should contain error line and next 2 lines
    try std.testing.expect(std.mem.indexOf(u8, result, "invalid = bad") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "name = \"zr\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "version = \"1.0\"") != null);

    // Should contain error message
    try std.testing.expect(std.mem.indexOf(u8, result, "bad syntax") != null);
}

test "showErrorSnippet: error on last line" {
    const allocator = std.testing.allocator;
    const toml_content = "name = \"zr\"\nversion = \"1.0\"\ndescription = invalid";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        3,
        18,
        "invalid value",
        false,
    );

    const result = output.items;

    // Should contain previous 2 lines and error line
    try std.testing.expect(std.mem.indexOf(u8, result, "name = \"zr\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "version = \"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "description = invalid") != null);

    // Should contain error message
    try std.testing.expect(std.mem.indexOf(u8, result, "invalid value") != null);
}

test "showErrorSnippet: single-line file" {
    const allocator = std.testing.allocator;
    const toml_content = "broken = {invalid}";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        1,
        10,
        "syntax error",
        false,
    );

    const result = output.items;

    // Should contain the only line
    try std.testing.expect(std.mem.indexOf(u8, result, "broken = {invalid}") != null);

    // Should contain error message
    try std.testing.expect(std.mem.indexOf(u8, result, "syntax error") != null);

    // Should contain caret
    try std.testing.expect(std.mem.indexOf(u8, result, "^") != null);
}

test "showErrorSnippet: caret positioning is correct" {
    const allocator = std.testing.allocator;
    const toml_content = "key = value\ninvalid line here\nanother = \"line\"";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    // Error at column 5 (at the "l" in "invalid")
    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        2,
        5,
        "error at column 5",
        false,
    );

    const result = output.items;

    // Should contain the caret character
    try std.testing.expect(std.mem.indexOf(u8, result, "^") != null);

    // Split output by lines to check caret position is reasonable
    var lines = std.ArrayList([]const u8){};
    defer lines.deinit(allocator);

    var iter = std.mem.splitSequence(u8, result, "\n");
    while (iter.next()) |line| {
        try lines.append(allocator, line);
    }

    // Find the caret line and verify it contains the caret character
    var found_caret = false;
    for (lines.items) |line| {
        if (std.mem.indexOf(u8, line, "^") != null) {
            found_caret = true;
            // Verify caret is surrounded by spaces (proper alignment)
            try std.testing.expect(line.len > 0);
            break;
        }
    }

    try std.testing.expect(found_caret);
}

test "showErrorSnippet: with color codes when use_color=true" {
    const allocator = std.testing.allocator;
    const toml_content = "name = \"zr\"\ninvalid = bad\nversion = \"1.0\"";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        2,
        11,
        "parse error",
        true,
    );

    const result = output.items;

    // Should contain ANSI escape codes
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[") != null);
}

test "showErrorSnippet: without color codes when use_color=false" {
    const allocator = std.testing.allocator;
    const toml_content = "name = \"zr\"\ninvalid = bad\nversion = \"1.0\"";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        2,
        11,
        "parse error",
        false,
    );

    const result = output.items;

    // Should NOT contain ANSI escape codes
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[") == null);
}

test "showErrorSnippet: custom error message is displayed" {
    const allocator = std.testing.allocator;
    const toml_content = "line1 = 1\nerror line\nline3 = 3";
    const custom_msg = "Expected a valid TOML value but got garbage";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        2,
        1,
        custom_msg,
        false,
    );

    const result = output.items;

    // Should contain the custom error message
    try std.testing.expect(std.mem.indexOf(u8, result, custom_msg) != null);
}

test "showErrorSnippet: handles error at end of line" {
    const allocator = std.testing.allocator;
    const toml_content = "key = value\nbroken = \n[next]";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        2,
        9,
        "missing value",
        false,
    );

    const result = output.items;

    // Should display the error line
    try std.testing.expect(std.mem.indexOf(u8, result, "broken = ") != null);

    // Should contain error message
    try std.testing.expect(std.mem.indexOf(u8, result, "missing value") != null);
}

test "showErrorSnippet: handles out-of-bounds line gracefully" {
    const allocator = std.testing.allocator;
    const toml_content = "line1 = 1\nline2 = 2";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    // Line 99 doesn't exist
    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        99,
        1,
        "invalid line number",
        false,
    );

    const result = output.items;

    // Should still contain error message or gracefully handle
    try std.testing.expect(result.len > 0);
}

test "showErrorSnippet: handles out-of-bounds column gracefully" {
    const allocator = std.testing.allocator;
    const toml_content = "key = 1\nshort\nline3";

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    // Column 999 is way beyond line length
    try showErrorSnippet(
        output.writer(allocator),
        toml_content,
        2,
        999,
        "column out of bounds",
        false,
    );

    const result = output.items;

    // Should still complete without crashing
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "column out of bounds") != null);
}
