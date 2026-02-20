const std = @import("std");

/// Match a pattern against a string using glob syntax.
/// Supports: * (any chars), ? (one char), literal matching
/// Does NOT support: character classes [], brace expansion {}
pub fn match(pattern: []const u8, str: []const u8) bool {
    return matchImpl(pattern, str, 0, 0);
}

fn matchImpl(pattern: []const u8, str: []const u8, p_idx: usize, s_idx: usize) bool {
    // End of both pattern and string = match
    if (p_idx == pattern.len and s_idx == str.len) return true;

    // End of pattern but not string = no match
    if (p_idx == pattern.len) return false;

    // Handle * wildcard
    if (pattern[p_idx] == '*') {
        // Try matching * with 0 characters
        if (matchImpl(pattern, str, p_idx + 1, s_idx)) return true;

        // Try matching * with 1+ characters
        if (s_idx < str.len) {
            return matchImpl(pattern, str, p_idx, s_idx + 1);
        }

        return false;
    }

    // End of string but pattern has non-* characters = no match
    if (s_idx == str.len) return false;

    // Handle ? wildcard (matches any single char)
    if (pattern[p_idx] == '?') {
        return matchImpl(pattern, str, p_idx + 1, s_idx + 1);
    }

    // Literal character match
    if (pattern[p_idx] == str[s_idx]) {
        return matchImpl(pattern, str, p_idx + 1, s_idx + 1);
    }

    return false;
}

/// Find all files matching a glob pattern in a directory.
/// Pattern should be relative to base_dir.
/// Returns an array of paths relative to base_dir.
/// Caller owns the returned array and all path strings.
pub fn find(
    allocator: std.mem.Allocator,
    base_dir: std.fs.Dir,
    pattern: []const u8,
) ![][]const u8 {
    var results = std.ArrayList([]const u8){};
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    // Split pattern into directory and filename parts
    const sep_idx = std.mem.lastIndexOfScalar(u8, pattern, '/');

    if (sep_idx) |idx| {
        // Pattern has directory component (e.g., "src/*.zig")
        const dir_pattern = pattern[0..idx];
        const file_pattern = pattern[idx + 1 ..];

        // For now, only support literal directory path (no wildcards in dirs)
        var dir = base_dir.openDir(dir_pattern, .{ .iterate = true }) catch return results.toOwnedSlice(allocator);
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            if (match(file_pattern, entry.name)) {
                const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_pattern, entry.name });
                try results.append(allocator, full_path);
            }
        }
    } else {
        // Pattern is just filename (e.g., "*.zig")
        var iter = base_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            if (match(pattern, entry.name)) {
                const path = try allocator.dupe(u8, entry.name);
                try results.append(allocator, path);
            }
        }
    }

    return results.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "match - literal" {
    try std.testing.expect(match("hello", "hello"));
    try std.testing.expect(!match("hello", "world"));
    try std.testing.expect(!match("hello", "hell"));
    try std.testing.expect(!match("hello", "hello!"));
}

test "match - single wildcard *" {
    try std.testing.expect(match("*.txt", "file.txt"));
    try std.testing.expect(match("*.txt", ".txt"));
    try std.testing.expect(!match("*.txt", "file.zig"));
    try std.testing.expect(match("test*", "test"));
    try std.testing.expect(match("test*", "test123"));
    try std.testing.expect(match("*test", "mytest"));
    try std.testing.expect(match("*", "anything"));
}

test "match - question mark ?" {
    try std.testing.expect(match("file?.txt", "file1.txt"));
    try std.testing.expect(match("file?.txt", "fileX.txt"));
    try std.testing.expect(!match("file?.txt", "file.txt"));
    try std.testing.expect(!match("file?.txt", "file12.txt"));
}

test "match - combined wildcards" {
    try std.testing.expect(match("*.??g", "test.zig"));
    try std.testing.expect(match("*.??g", "main.log"));
    try std.testing.expect(!match("*.??g", "file.z"));
    try std.testing.expect(match("test*.txt", "test123.txt"));
    try std.testing.expect(match("*test*", "mytestfile"));
}

test "match - edge cases" {
    try std.testing.expect(match("", ""));
    try std.testing.expect(!match("", "x"));
    try std.testing.expect(match("*", ""));
    try std.testing.expect(match("**", "anything"));
}

test "find - basic pattern matching" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test files
    try tmp_dir.dir.writeFile(.{ .sub_path = "test1.txt", .data = "content" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test2.txt", .data = "content" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "other.zig", .data = "content" });

    // Find *.txt files
    const results = try find(allocator, tmp_dir.dir, "*.txt");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "find - no matches" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "file.txt", .data = "content" });

    const results = try find(allocator, tmp_dir.dir, "*.zig");
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "find - subdirectory pattern" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create subdirectory
    try tmp_dir.dir.makeDir("src");
    try tmp_dir.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "content" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "src/util.zig", .data = "content" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "README.md", .data = "content" });

    // Find src/*.zig files
    const results = try find(allocator, tmp_dir.dir, "src/*.zig");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);

    // Check paths start with src/
    for (results) |path| {
        try std.testing.expect(std.mem.startsWith(u8, path, "src/"));
    }
}

test "find - empty directory" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const results = try find(allocator, tmp_dir.dir, "*.txt");
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}
