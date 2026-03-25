const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

/// HashMap for storing environment variable key-value pairs
/// Caller owns the map and must deinit it
pub fn parseDotenv(allocator: Allocator, content: []const u8) !std.StringHashMap([]const u8) {
    var env_map = std.StringHashMap([]const u8).init(allocator);
    errdefer env_map.deinit();

    var lines = mem.tokenizeSequence(u8, content, "\n");
    var line_num: usize = 0;

    while (lines.next()) |raw_line| {
        line_num += 1;
        const line = mem.trim(u8, raw_line, " \t\r");

        // Skip empty lines and comments
        if (line.len == 0 or line[0] == '#') continue;

        // Find the '=' separator
        const eq_idx = mem.indexOf(u8, line, "=") orelse {
            return error.InvalidFormat;
        };

        const key_part = mem.trim(u8, line[0..eq_idx], " \t");
        const value_part = mem.trim(u8, line[eq_idx + 1 ..], " \t");

        if (key_part.len == 0) {
            return error.EmptyKey;
        }

        // Parse the value (handle quoted and unquoted)
        const value = try parseValue(allocator, value_part);
        errdefer allocator.free(value);

        // Store in map with owned copies
        // If key already exists, remove it and free the old entry
        if (env_map.fetchRemove(key_part)) |old_entry| {
            allocator.free(old_entry.key);
            allocator.free(old_entry.value);
        }

        const key = try allocator.dupe(u8, key_part);
        errdefer allocator.free(key);

        try env_map.put(key, value);
    }

    return env_map;
}

/// Parse a value that may be quoted, with escape sequences
fn parseValue(allocator: Allocator, value_part: []const u8) ![]const u8 {
    if (value_part.len == 0) {
        return try allocator.dupe(u8, "");
    }

    // Check if value is quoted (double or single quotes)
    if ((value_part[0] == '"' or value_part[0] == '\'') and value_part.len >= 2) {
        const quote_char = value_part[0];

        // Find closing quote
        var closing_idx: ?usize = null;
        var i: usize = 1;
        while (i < value_part.len) : (i += 1) {
            if (value_part[i] == '\\' and i + 1 < value_part.len) {
                // Skip escaped character
                i += 1;
                continue;
            }
            if (value_part[i] == quote_char) {
                closing_idx = i;
                break;
            }
        }

        if (closing_idx == null) {
            return error.UnclosedQuote;
        }

        const quoted_content = value_part[1..closing_idx.?];
        return try unescapeString(allocator, quoted_content);
    }

    // Unquoted value - return as-is, stripped of trailing comment
    var end_idx = value_part.len;

    // Check for inline comment (# outside quotes)
    for (0..value_part.len) |idx| {
        if (value_part[idx] == '#') {
            end_idx = idx;
            break;
        }
    }

    const unquoted = mem.trim(u8, value_part[0..end_idx], " \t");
    return try allocator.dupe(u8, unquoted);
}

/// Unescape escape sequences in a string
fn unescapeString(allocator: Allocator, escaped: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);
    errdefer {
        // Already deinitialized by defer
    }

    var i: usize = 0;
    while (i < escaped.len) : (i += 1) {
        if (escaped[i] == '\\' and i + 1 < escaped.len) {
            const next_char = escaped[i + 1];
            switch (next_char) {
                'n' => try result.append(allocator, '\n'),
                't' => try result.append(allocator, '\t'),
                'r' => try result.append(allocator, '\r'),
                '\\' => try result.append(allocator, '\\'),
                '"' => try result.append(allocator, '"'),
                '\'' => try result.append(allocator, '\''),
                else => {
                    // Unknown escape sequence - keep as-is
                    try result.append(allocator, '\\');
                    try result.append(allocator, next_char);
                },
            }
            i += 1; // Skip the escaped character
        } else {
            try result.append(allocator, escaped[i]);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Deinit the environment map and free all allocated strings
pub fn deinitDotenv(env_map: *std.StringHashMap([]const u8), allocator: Allocator) void {
    var it = env_map.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    env_map.deinit();
}

// ============================================================================
// Tests
// ============================================================================

test "parseDotenv basic key=value" {
    const allocator = std.testing.allocator;
    const content = "KEY=value";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    const val = env_map.get("KEY");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("value", val.?);
}

test "parseDotenv multiple key-value pairs" {
    const allocator = std.testing.allocator;
    const content =
        \\KEY1=value1
        \\KEY2=value2
        \\KEY3=value3
    ;
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 3);
    try std.testing.expectEqualStrings("value1", env_map.get("KEY1").?);
    try std.testing.expectEqualStrings("value2", env_map.get("KEY2").?);
    try std.testing.expectEqualStrings("value3", env_map.get("KEY3").?);
}

test "parseDotenv empty file" {
    const allocator = std.testing.allocator;
    const content = "";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 0);
}

test "parseDotenv comments are ignored" {
    const allocator = std.testing.allocator;
    const content =
        \\# This is a comment
        \\KEY=value
        \\# Another comment
    ;
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value", env_map.get("KEY").?);
}

test "parseDotenv empty lines are ignored" {
    const allocator = std.testing.allocator;
    const content =
        \\KEY1=value1
        \\
        \\KEY2=value2
        \\
    ;
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 2);
    try std.testing.expectEqualStrings("value1", env_map.get("KEY1").?);
    try std.testing.expectEqualStrings("value2", env_map.get("KEY2").?);
}

test "parseDotenv whitespace around key and value is trimmed" {
    const allocator = std.testing.allocator;
    const content = "  KEY  =  value  ";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value", env_map.get("KEY").?);
}

test "parseDotenv double-quoted value with spaces" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"value with spaces\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value with spaces", env_map.get("KEY").?);
}

test "parseDotenv single-quoted value with spaces" {
    const allocator = std.testing.allocator;
    const content = "KEY='value with spaces'";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value with spaces", env_map.get("KEY").?);
}

test "parseDotenv escape sequence newline in double quotes" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"line1\\nline2\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("line1\nline2", env_map.get("KEY").?);
}

test "parseDotenv escape sequence tab in double quotes" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"col1\\tcol2\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("col1\tcol2", env_map.get("KEY").?);
}

test "parseDotenv escape sequence backslash in double quotes" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"path\\\\to\\\\file\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("path\\to\\file", env_map.get("KEY").?);
}

test "parseDotenv escape sequence escaped quote in double quotes" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"say \\\"hello\\\"\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("say \"hello\"", env_map.get("KEY").?);
}

test "parseDotenv multiple escape sequences" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"line1\\nline2\\ttab\\\\slash\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("line1\nline2\ttab\\slash", env_map.get("KEY").?);
}

test "parseDotenv unquoted value" {
    const allocator = std.testing.allocator;
    const content = "KEY=unquoted_value";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("unquoted_value", env_map.get("KEY").?);
}

test "parseDotenv empty value" {
    const allocator = std.testing.allocator;
    const content = "KEY=";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("", env_map.get("KEY").?);
}

test "parseDotenv quoted empty value" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("", env_map.get("KEY").?);
}

test "parseDotenv inline comment in unquoted value" {
    const allocator = std.testing.allocator;
    const content = "KEY=value # this is a comment";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value", env_map.get("KEY").?);
}

test "parseDotenv inline comment ignored in quoted value" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"value # not a comment\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value # not a comment", env_map.get("KEY").?);
}

test "parseDotenv error on missing equals sign" {
    const allocator = std.testing.allocator;
    const content = "INVALID_LINE";
    const result = parseDotenv(allocator, content);

    try std.testing.expectError(error.InvalidFormat, result);
}

test "parseDotenv error on empty key" {
    const allocator = std.testing.allocator;
    const content = "=value";
    const result = parseDotenv(allocator, content);

    try std.testing.expectError(error.EmptyKey, result);
}

test "parseDotenv error on unclosed double quote" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"unclosed";
    const result = parseDotenv(allocator, content);

    try std.testing.expectError(error.UnclosedQuote, result);
}

test "parseDotenv error on unclosed single quote" {
    const allocator = std.testing.allocator;
    const content = "KEY='unclosed";
    const result = parseDotenv(allocator, content);

    try std.testing.expectError(error.UnclosedQuote, result);
}

test "parseDotenv complex real-world example" {
    const allocator = std.testing.allocator;
    const content =
        \\# Database configuration
        \\DB_HOST=localhost
        \\DB_PORT=5432
        \\DB_USER=admin
        \\DB_PASS="p@ssw0rd!#"
        \\
        \\# API configuration
        \\API_URL="https://api.example.com"
        \\API_KEY="key_with\\nnewline"
        \\API_TIMEOUT=30
        \\
        \\# Logging
        \\LOG_LEVEL=debug
        \\LOG_FILE="/var/log/app.log"
    ;
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 9);
    try std.testing.expectEqualStrings("localhost", env_map.get("DB_HOST").?);
    try std.testing.expectEqualStrings("5432", env_map.get("DB_PORT").?);
    try std.testing.expectEqualStrings("admin", env_map.get("DB_USER").?);
    try std.testing.expectEqualStrings("p@ssw0rd!#", env_map.get("DB_PASS").?);
    try std.testing.expectEqualStrings("https://api.example.com", env_map.get("API_URL").?);
    try std.testing.expectEqualStrings("30", env_map.get("API_TIMEOUT").?);
    try std.testing.expectEqualStrings("debug", env_map.get("LOG_LEVEL").?);
    try std.testing.expectEqualStrings("/var/log/app.log", env_map.get("LOG_FILE").?);
}

test "parseDotenv special characters in unquoted value" {
    const allocator = std.testing.allocator;
    const content = "KEY=user@example.com";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("user@example.com", env_map.get("KEY").?);
}

test "parseDotenv numeric value" {
    const allocator = std.testing.allocator;
    const content = "PORT=8080";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("8080", env_map.get("PORT").?);
}

test "parseDotenv boolean-like values" {
    const allocator = std.testing.allocator;
    const content =
        \\DEBUG=true
        \\ENABLED=false
    ;
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 2);
    try std.testing.expectEqualStrings("true", env_map.get("DEBUG").?);
    try std.testing.expectEqualStrings("false", env_map.get("ENABLED").?);
}

test "parseDotenv URL value" {
    const allocator = std.testing.allocator;
    const content = "DATABASE_URL=postgres://user:pass@localhost:5432/dbname";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("postgres://user:pass@localhost:5432/dbname", env_map.get("DATABASE_URL").?);
}

test "parseDotenv tabs and mixed whitespace" {
    const allocator = std.testing.allocator;
    const content = "KEY\t=\tvalue";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value", env_map.get("KEY").?);
}

test "parseDotenv carriage return handling" {
    const allocator = std.testing.allocator;
    const content = "KEY=value\r\nKEY2=value2\r\n";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 2);
    try std.testing.expectEqualStrings("value", env_map.get("KEY").?);
    try std.testing.expectEqualStrings("value2", env_map.get("KEY2").?);
}

test "parseDotenv duplicate keys - last one wins" {
    const allocator = std.testing.allocator;
    const content =
        \\KEY=value1
        \\KEY=value2
    ;
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value2", env_map.get("KEY").?);
}

test "parseDotenv key with underscores and numbers" {
    const allocator = std.testing.allocator;
    const content = "MY_VAR_123=test_value_456";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("test_value_456", env_map.get("MY_VAR_123").?);
}

test "parseValue unquoted with trailing spaces" {
    const allocator = std.testing.allocator;
    const content = "KEY=value   ";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("value", env_map.get("KEY").?);
}

test "parseDotenv quoted value with leading spaces" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"  spaced  \"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("  spaced  ", env_map.get("KEY").?);
}

test "parseDotenv equals sign in quoted value" {
    const allocator = std.testing.allocator;
    const content = "EQUATION=\"x=y+z\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("x=y+z", env_map.get("EQUATION").?);
}

test "parseDotenv escape carriage return" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"line1\\rline2\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("line1\rline2", env_map.get("KEY").?);
}

test "parseDotenv single quote escapes in double quotes" {
    const allocator = std.testing.allocator;
    const content = "KEY=\"don't need escaping\"";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("don't need escaping", env_map.get("KEY").?);
}

test "parseDotenv double quote escapes in single quotes not supported" {
    const allocator = std.testing.allocator;
    const content = "KEY='just \" double quote'";
    var env_map = try parseDotenv(allocator, content);
    defer deinitDotenv(&env_map, allocator);

    try std.testing.expect(env_map.count() == 1);
    try std.testing.expectEqualStrings("just \" double quote", env_map.get("KEY").?);
}
