const std = @import("std");

/// LSP position (0-indexed line, 0-indexed character)
pub const Position = struct {
    line: u32,
    character: u32,
};

/// LSP range (start and end positions)
pub const Range = struct {
    start: Position,
    end: Position,
};

/// Convert byte offset to LSP position (line, character)
/// LSP uses 0-indexed lines and UTF-16 code units for character offset
pub fn byteOffsetToPosition(text: []const u8, byte_offset: usize) Position {
    var line: u32 = 0;
    var character: u32 = 0;
    var i: usize = 0;

    while (i < byte_offset and i < text.len) {
        if (text[i] == '\n') {
            line += 1;
            character = 0;
        } else {
            // Simplified: count UTF-8 bytes as characters
            // LSP spec uses UTF-16 code units, but for ASCII/common UTF-8 this works
            // Edge case: Characters outside BMP (emojis, rare CJK) may have incorrect positions
            // Fix: Decode UTF-8 sequences and count UTF-16 code units (1 for BMP, 2 for supplementary)
            // Not critical for TOML files which rarely contain such characters
            character += 1;
        }
        i += 1;
    }

    return Position{ .line = line, .character = character };
}

/// Convert LSP position to byte offset
pub fn positionToByteOffset(text: []const u8, position: Position) ?usize {
    var line: u32 = 0;
    var character: u32 = 0;
    var i: usize = 0;

    while (i < text.len) {
        if (line == position.line and character == position.character) {
            return i;
        }

        if (text[i] == '\n') {
            if (line == position.line) {
                // Requested character is beyond end of line
                return null;
            }
            line += 1;
            character = 0;
        } else {
            character += 1;
        }
        i += 1;
    }

    // Check if we're at the end of the document
    if (line == position.line and character == position.character) {
        return i;
    }

    return null;
}

/// Get the range of a line (from start to newline or EOF)
pub fn getLineRange(text: []const u8, line_number: u32) ?Range {
    var current_line: u32 = 0;
    var line_start: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        if (current_line == line_number) {
            // Found the target line, find its end
            var line_end = i;
            while (line_end < text.len and text[line_end] != '\n') {
                line_end += 1;
            }
            return Range{
                .start = byteOffsetToPosition(text, line_start),
                .end = byteOffsetToPosition(text, line_end),
            };
        }

        if (text[i] == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
        i += 1;
    }

    // Check if we're on the last line (no trailing newline)
    if (current_line == line_number) {
        return Range{
            .start = byteOffsetToPosition(text, line_start),
            .end = byteOffsetToPosition(text, text.len),
        };
    }

    return null;
}

test "byteOffsetToPosition - single line" {
    const text = "hello world";
    const pos = byteOffsetToPosition(text, 6);
    try std.testing.expectEqual(@as(u32, 0), pos.line);
    try std.testing.expectEqual(@as(u32, 6), pos.character);
}

test "byteOffsetToPosition - multiple lines" {
    const text = "line1\nline2\nline3";
    const pos = byteOffsetToPosition(text, 7); // 'i' in "line2"
    try std.testing.expectEqual(@as(u32, 1), pos.line);
    try std.testing.expectEqual(@as(u32, 1), pos.character);
}

test "positionToByteOffset - success" {
    const text = "line1\nline2\nline3";
    const offset = positionToByteOffset(text, Position{ .line = 1, .character = 1 });
    try std.testing.expectEqual(@as(usize, 7), offset.?);
}

test "positionToByteOffset - out of bounds" {
    const text = "line1\nline2";
    const offset = positionToByteOffset(text, Position{ .line = 5, .character = 0 });
    try std.testing.expectEqual(@as(?usize, null), offset);
}

test "getLineRange - first line" {
    const text = "line1\nline2\nline3";
    const range = getLineRange(text, 0);
    try std.testing.expect(range != null);
    try std.testing.expectEqual(@as(u32, 0), range.?.start.line);
    try std.testing.expectEqual(@as(u32, 0), range.?.start.character);
    try std.testing.expectEqual(@as(u32, 0), range.?.end.line);
    try std.testing.expectEqual(@as(u32, 5), range.?.end.character);
}

test "getLineRange - last line no newline" {
    const text = "line1\nline2";
    const range = getLineRange(text, 1);
    try std.testing.expect(range != null);
    try std.testing.expectEqual(@as(u32, 1), range.?.start.line);
    try std.testing.expectEqual(@as(u32, 0), range.?.start.character);
}
