const std = @import("std");
const color = @import("color.zig");

/// Filter options for task output streams
pub const FilterOptions = struct {
    /// Pattern to match (shows only matching lines) - substring or pipe-separated alternatives
    grep_pattern: ?[]const u8 = null,
    /// Pattern for inverted match (hides matching lines)
    grep_v_pattern: ?[]const u8 = null,
    /// Pattern to highlight in output (shows all lines with matches highlighted)
    highlight_pattern: ?[]const u8 = null,
    /// Number of context lines before/after matches (like grep -C)
    context_lines: u32 = 0,

    /// Check if any filtering is enabled
    pub fn isEnabled(self: FilterOptions) bool {
        return self.grep_pattern != null or
            self.grep_v_pattern != null or
            self.highlight_pattern != null;
    }
};

/// Streaming line filter for task output
pub const LineFilter = struct {
    allocator: std.mem.Allocator,
    options: FilterOptions,
    use_color: bool,

    // Parsed alternatives for pipe-separated patterns (error|warning)
    grep_alternatives: ?[][]const u8 = null,
    grep_v_alternatives: ?[][]const u8 = null,
    highlight_alternatives: ?[][]const u8 = null,

    // Context buffer for -C option
    context_buffer: std.ArrayListUnmanaged([]const u8) = .{},
    lines_since_match: u32 = std.math.maxInt(u32),

    pub fn init(allocator: std.mem.Allocator, options: FilterOptions, use_color: bool) !LineFilter {
        var self = LineFilter{
            .allocator = allocator,
            .options = options,
            .use_color = use_color,
        };

        // Parse pipe-separated patterns into alternatives
        if (options.grep_pattern) |pattern| {
            self.grep_alternatives = try parseAlternatives(allocator, pattern);
        }
        if (options.grep_v_pattern) |pattern| {
            self.grep_v_alternatives = try parseAlternatives(allocator, pattern);
        }
        if (options.highlight_pattern) |pattern| {
            self.highlight_alternatives = try parseAlternatives(allocator, pattern);
        }

        return self;
    }

    pub fn deinit(self: *LineFilter) void {
        if (self.grep_alternatives) |alts| {
            for (alts) |alt| self.allocator.free(alt);
            self.allocator.free(alts);
        }
        if (self.grep_v_alternatives) |alts| {
            for (alts) |alt| self.allocator.free(alt);
            self.allocator.free(alts);
        }
        if (self.highlight_alternatives) |alts| {
            for (alts) |alt| self.allocator.free(alt);
            self.allocator.free(alts);
        }

        for (self.context_buffer.items) |line| {
            self.allocator.free(line);
        }
        self.context_buffer.deinit(self.allocator);
    }

    /// Filter a single line and write result to writer if it should be shown
    /// Returns true if line was written, false if filtered out
    pub fn filterLine(self: *LineFilter, line: []const u8, writer: anytype) !bool {
        // --grep-v: hide lines matching pattern (inverted match)
        if (self.grep_v_alternatives) |alternatives| {
            for (alternatives) |alt| {
                if (std.mem.indexOf(u8, line, alt) != null) {
                    return false; // Skip this line
                }
            }
        }

        // --grep: show only lines matching pattern
        if (self.grep_alternatives) |alternatives| {
            var matches = false;
            for (alternatives) |alt| {
                if (std.mem.indexOf(u8, line, alt) != null) {
                    matches = true;
                    break;
                }
            }

            if (matches) {
                // Flush context buffer (lines before this match)
                try self.flushContextBuffer(writer);

                // Write the matching line (with highlighting if --highlight also set)
                try self.writeLine(line, writer);

                self.lines_since_match = 0;
                return true;
            } else {
                // No match - buffer for context if needed
                if (self.options.context_lines > 0) {
                    if (self.lines_since_match < self.options.context_lines) {
                        // This is within N lines after a match - write immediately
                        try self.writeLine(line, writer);
                        self.lines_since_match += 1;
                        return true;
                    } else {
                        // Buffer for potential context before next match
                        try self.addToContextBuffer(line);
                    }
                }
                return false;
            }
        }

        // No grep filter - just highlight if requested
        try self.writeLine(line, writer);
        return true;
    }

    /// Add line to context buffer (FIFO, max size = context_lines)
    fn addToContextBuffer(self: *LineFilter, line: []const u8) !void {
        const owned_line = try self.allocator.dupe(u8, line);
        try self.context_buffer.append(self.allocator, owned_line);

        // Keep buffer size <= context_lines
        if (self.context_buffer.items.len > self.options.context_lines) {
            const removed = self.context_buffer.orderedRemove(0);
            self.allocator.free(removed);
        }
    }

    /// Flush context buffer to writer
    fn flushContextBuffer(self: *LineFilter, writer: anytype) !void {
        for (self.context_buffer.items) |line| {
            try self.writeLine(line, writer);
        }
        // Clear buffer after flushing
        for (self.context_buffer.items) |line| {
            self.allocator.free(line);
        }
        self.context_buffer.clearRetainingCapacity();
    }

    /// Write line to writer with optional highlighting
    fn writeLine(self: *LineFilter, line: []const u8, writer: anytype) !void {
        // If --highlight is set and line contains pattern, inject ANSI colors
        if (self.highlight_alternatives) |alternatives| {
            if (try self.highlightMatches(line, alternatives, writer)) {
                try writer.writeAll("\n");
                return;
            }
        }

        // No highlighting - write raw line
        try writer.writeAll(line);
        try writer.writeAll("\n");
    }

    /// Highlight matches in line with ANSI color codes
    /// Returns true if any matches were found, false otherwise
    fn highlightMatches(self: *LineFilter, line: []const u8, alternatives: [][]const u8, writer: anytype) !bool {
        if (!self.use_color) {
            // No color support - write raw line
            return false;
        }

        // Find all occurrences of any alternative and highlight them
        var matches = std.ArrayList(Match){};
        defer matches.deinit(self.allocator);

        for (alternatives) |alt| {
            var start: usize = 0;
            while (std.mem.indexOfPos(u8, line, start, alt)) |pos| {
                try matches.append(self.allocator, .{ .start = pos, .end = pos + alt.len });
                start = pos + alt.len;
            }
        }

        if (matches.items.len == 0) {
            return false;
        }

        // Sort matches by start position
        std.sort.pdq(Match, matches.items, {}, matchLessThan);

        // Write line with highlighted matches
        var last_end: usize = 0;
        for (matches.items) |match| {
            // Skip overlapping matches
            if (match.start < last_end) continue;

            // Write text before match
            if (match.start > last_end) {
                try writer.writeAll(line[last_end..match.start]);
            }

            // Write match with highlighting (bold yellow)
            try writer.writeAll("\x1b[1;33m");
            try writer.writeAll(line[match.start..match.end]);
            try writer.writeAll("\x1b[0m");

            last_end = match.end;
        }

        // Write remaining text after last match
        if (last_end < line.len) {
            try writer.writeAll(line[last_end..]);
        }

        return true;
    }
};

const Match = struct {
    start: usize,
    end: usize,
};

fn matchLessThan(_: void, a: Match, b: Match) bool {
    return a.start < b.start;
}

/// Parse pipe-separated alternatives (e.g., "error|warning|fatal")
fn parseAlternatives(allocator: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
    var list = std.ArrayList([]const u8){};
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }

    var it = std.mem.splitScalar(u8, pattern, '|');
    while (it.next()) |alt| {
        if (alt.len > 0) {
            const owned = try allocator.dupe(u8, alt);
            try list.append(allocator, owned);
        }
    }

    return list.toOwnedSlice(allocator);
}

test "FilterOptions.isEnabled" {
    const testing = std.testing;

    // No filters
    const no_filter = FilterOptions{};
    try testing.expect(!no_filter.isEnabled());

    // With grep
    const with_grep = FilterOptions{ .grep_pattern = "error" };
    try testing.expect(with_grep.isEnabled());

    // With grep-v
    const with_grep_v = FilterOptions{ .grep_v_pattern = "debug" };
    try testing.expect(with_grep_v.isEnabled());

    // With highlight
    const with_highlight = FilterOptions{ .highlight_pattern = "TODO" };
    try testing.expect(with_highlight.isEnabled());
}

test "LineFilter basic grep" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var filter = try LineFilter.init(allocator, .{
        .grep_pattern = "error",
    }, false);
    defer filter.deinit();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    // Matching line
    try testing.expect(try filter.filterLine("fatal error occurred", buf.writer(allocator)));
    try testing.expectEqualStrings("fatal error occurred\n", buf.items);

    // Non-matching line
    buf.clearRetainingCapacity();
    try testing.expect(!try filter.filterLine("everything is fine", buf.writer(allocator)));
    try testing.expectEqualStrings("", buf.items);
}

test "LineFilter inverted grep" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var filter = try LineFilter.init(allocator, .{
        .grep_v_pattern = "debug",
    }, false);
    defer filter.deinit();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    // Non-matching line (should be shown)
    try testing.expect(try filter.filterLine("error occurred", buf.writer(allocator)));
    try testing.expectEqualStrings("error occurred\n", buf.items);

    // Matching line (should be hidden)
    buf.clearRetainingCapacity();
    try testing.expect(!try filter.filterLine("debug: verbose output", buf.writer(allocator)));
    try testing.expectEqualStrings("", buf.items);
}

test "LineFilter pipe-separated alternatives" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var filter = try LineFilter.init(allocator, .{
        .grep_pattern = "error|warning|fatal",
    }, false);
    defer filter.deinit();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    // Match "error"
    try testing.expect(try filter.filterLine("fatal error occurred", buf.writer(allocator)));
    try testing.expectEqualStrings("fatal error occurred\n", buf.items);

    // Match "warning"
    buf.clearRetainingCapacity();
    try testing.expect(try filter.filterLine("warning: deprecated", buf.writer(allocator)));
    try testing.expectEqualStrings("warning: deprecated\n", buf.items);

    // No match
    buf.clearRetainingCapacity();
    try testing.expect(!try filter.filterLine("info: all good", buf.writer(allocator)));
    try testing.expectEqualStrings("", buf.items);
}

test "LineFilter highlighting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var filter = try LineFilter.init(allocator, .{
        .highlight_pattern = "TODO",
    }, true);
    defer filter.deinit();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    // Line with TODO
    try testing.expect(try filter.filterLine("// TODO: fix this", buf.writer(allocator)));
    // Should contain ANSI codes and original text
    try testing.expect(std.mem.indexOf(u8, buf.items, "TODO") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[1;33m") != null);
}
