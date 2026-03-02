/// Unicode utility functions for proper text display.
/// Wraps sailor's Unicode width calculation for CJK/emoji support.
const std = @import("std");
const sailor = @import("sailor");

/// Calculate display width of a UTF-8 string, accounting for:
/// - CJK characters (width 2)
/// - Emoji (width 2)
/// - Combining characters (width 0)
/// - Control characters (width 0)
///
/// Returns the number of terminal columns needed to display the string.
pub fn displayWidth(str: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;

    while (i < str.len) {
        const len = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        if (i + len > str.len) break;

        const codepoint = std.unicode.utf8Decode(str[i..][0..len]) catch {
            i += 1;
            width += 1;
            continue;
        };

        width += charWidth(codepoint);
        i += len;
    }

    return width;
}

/// Calculate display width of a single Unicode codepoint.
/// Returns 0, 1, or 2 depending on character category.
pub fn charWidth(codepoint: u21) usize {
    // Sailor v1.1.0+ provides Unicode width calculation
    // For now, use simple heuristics until we expose sailor's implementation

    // Control characters
    if (codepoint < 0x20 or (codepoint >= 0x7F and codepoint < 0xA0)) {
        return 0;
    }

    // CJK Unified Ideographs (width 2)
    if (codepoint >= 0x4E00 and codepoint <= 0x9FFF) {
        return 2;
    }

    // Hangul Syllables (width 2)
    if (codepoint >= 0xAC00 and codepoint <= 0xD7AF) {
        return 2;
    }

    // Hiragana and Katakana (width 2)
    if (codepoint >= 0x3040 and codepoint <= 0x30FF) {
        return 2;
    }

    // Emoji (width 2) - simplified range
    if (codepoint >= 0x1F300 and codepoint <= 0x1F9FF) {
        return 2;
    }

    // Combining characters (width 0)
    if (codepoint >= 0x0300 and codepoint <= 0x036F) {
        return 0;
    }

    // Default: single width
    return 1;
}

/// Truncate a UTF-8 string to fit within a maximum display width.
/// Returns a slice of the input string that fits within max_width columns.
/// Ensures we don't cut in the middle of a multi-byte character.
pub fn truncateToWidth(str: []const u8, max_width: usize) []const u8 {
    var width: usize = 0;
    var i: usize = 0;
    var last_boundary: usize = 0;

    while (i < str.len and width < max_width) {
        const len = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        if (i + len > str.len) break;

        const codepoint = std.unicode.utf8Decode(str[i..][0..len]) catch {
            i += 1;
            width += 1;
            continue;
        };

        const char_w = charWidth(codepoint);
        if (width + char_w > max_width) break;

        width += char_w;
        i += len;
        last_boundary = i;
    }

    return str[0..last_boundary];
}

/// Pad a string to a specific display width with spaces.
/// Accounts for wide characters (CJK/emoji) that take 2 columns.
pub fn padToWidth(allocator: std.mem.Allocator, str: []const u8, target_width: usize) ![]const u8 {
    const current_width = displayWidth(str);
    if (current_width >= target_width) {
        return allocator.dupe(u8, str);
    }

    const padding_needed = target_width - current_width;
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len + padding_needed);
    errdefer result.deinit();

    try result.appendSlice(str);
    try result.appendNTimes(' ', padding_needed);

    return try result.toOwnedSlice();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "displayWidth: ASCII" {
    try std.testing.expectEqual(@as(usize, 5), displayWidth("hello"));
    try std.testing.expectEqual(@as(usize, 0), displayWidth(""));
    try std.testing.expectEqual(@as(usize, 3), displayWidth("foo"));
}

test "displayWidth: CJK characters" {
    // "你好" (hello in Chinese) - 2 chars, 4 columns
    try std.testing.expectEqual(@as(usize, 4), displayWidth("你好"));

    // "こんにちは" (hello in Japanese) - 5 chars, 10 columns
    try std.testing.expectEqual(@as(usize, 10), displayWidth("こんにちは"));

    // "안녕" (hello in Korean) - 2 chars, 4 columns
    try std.testing.expectEqual(@as(usize, 4), displayWidth("안녕"));
}

test "displayWidth: emoji" {
    // Single emoji (width 2)
    try std.testing.expectEqual(@as(usize, 2), displayWidth("😀"));

    // Multiple emoji
    try std.testing.expectEqual(@as(usize, 4), displayWidth("😀😁"));
}

test "displayWidth: mixed content" {
    // "Hello 世界" - 6 ASCII + 1 space + 2 CJK = 7 + 4 = 11 columns
    try std.testing.expectEqual(@as(usize, 11), displayWidth("Hello 世界"));
}

test "charWidth: various ranges" {
    // ASCII
    try std.testing.expectEqual(@as(usize, 1), charWidth('A'));
    try std.testing.expectEqual(@as(usize, 1), charWidth('z'));

    // Control characters
    try std.testing.expectEqual(@as(usize, 0), charWidth(0x00)); // NUL
    try std.testing.expectEqual(@as(usize, 0), charWidth(0x1F)); // Unit separator

    // CJK
    try std.testing.expectEqual(@as(usize, 2), charWidth(0x4E00)); // CJK start
    try std.testing.expectEqual(@as(usize, 2), charWidth(0x9FFF)); // CJK end

    // Hangul
    try std.testing.expectEqual(@as(usize, 2), charWidth(0xAC00)); // Hangul start

    // Emoji
    try std.testing.expectEqual(@as(usize, 2), charWidth(0x1F600)); // Grinning face
}

test "truncateToWidth: ASCII" {
    try std.testing.expectEqualStrings("hel", truncateToWidth("hello", 3));
    try std.testing.expectEqualStrings("hello", truncateToWidth("hello", 10));
    try std.testing.expectEqualStrings("", truncateToWidth("hello", 0));
}

test "truncateToWidth: CJK" {
    // "你好世界" - each char is 2 columns
    const input = "你好世界";

    // Truncate to 4 columns = 2 characters
    const result = truncateToWidth(input, 4);
    try std.testing.expectEqual(@as(usize, 4), displayWidth(result));

    // Truncate to 6 columns = 3 characters
    const result2 = truncateToWidth(input, 6);
    try std.testing.expectEqual(@as(usize, 6), displayWidth(result2));
}

test "truncateToWidth: mixed content" {
    const input = "Hello 世界";

    // Truncate to 7 columns = "Hello " (6 ASCII + 1 space)
    const result = truncateToWidth(input, 7);
    try std.testing.expectEqualStrings("Hello ", result);

    // Truncate to 9 columns = "Hello 世" (7 + 2)
    const result2 = truncateToWidth(input, 9);
    try std.testing.expectEqual(@as(usize, 9), displayWidth(result2));
}

test "padToWidth: basic" {
    const allocator = std.testing.allocator;

    const result = try padToWidth(allocator, "hi", 5);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hi   ", result);
}

test "padToWidth: CJK" {
    const allocator = std.testing.allocator;

    // "你好" is 4 columns, pad to 8
    const result = try padToWidth(allocator, "你好", 8);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 8), displayWidth(result));
}

test "padToWidth: no padding needed" {
    const allocator = std.testing.allocator;

    const result = try padToWidth(allocator, "hello", 3);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello", result);
}
