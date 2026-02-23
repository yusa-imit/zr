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
/// Supports wildcards in both directory and filename components.
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
        // Pattern has directory component (e.g., "src/*.zig" or "packages/*/src")
        const dir_pattern = pattern[0..idx];
        const file_pattern = pattern[idx + 1 ..];

        // Check if directory pattern contains wildcards
        const has_wildcards = std.mem.indexOfAny(u8, dir_pattern, "*?") != null;

        if (has_wildcards) {
            // Recursively find matching directories, then search for files
            const matching_dirs = try findDirs(allocator, base_dir, dir_pattern);
            defer {
                for (matching_dirs) |d| allocator.free(d);
                allocator.free(matching_dirs);
            }

            for (matching_dirs) |dir_path| {
                var dir = base_dir.openDir(dir_path, .{ .iterate = true }) catch continue;
                defer dir.close();

                var iter = dir.iterate();
                while (try iter.next()) |entry| {
                    if (entry.kind != .file) continue;

                    if (match(file_pattern, entry.name)) {
                        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
                        try results.append(allocator, full_path);
                    }
                }
            }
        } else {
            // Literal directory path (no wildcards in dirs)
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
        }
    } else {
        // Pattern is just filename (e.g., "*.zig")
        // NOTE: We reopen base_dir with explicit .iterate = true permission
        // to avoid EBADF on Linux when the dir fd is in an unexpected state.
        // This fixes a race condition in CI where tmpDir's fd isn't iterable.
        var iter_dir = try base_dir.openDir(".", .{ .iterate = true });
        defer iter_dir.close();

        var iter = iter_dir.iterate();
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

/// Find all directories matching a glob pattern.
/// Pattern can contain wildcards (*,?) and path separators (/).
/// Returns an array of directory paths relative to base_dir.
/// Caller owns the returned array and all path strings.
pub fn findDirs(
    allocator: std.mem.Allocator,
    base_dir: std.fs.Dir,
    pattern: []const u8,
) ![][]const u8 {
    var results = std.ArrayList([]const u8){};
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    // Split pattern by first '/' to process path component by component
    const sep_idx = std.mem.indexOfScalar(u8, pattern, '/');

    if (sep_idx) |idx| {
        // Pattern has multiple components (e.g., "packages/*/src")
        const first_component = pattern[0..idx];
        const rest_pattern = pattern[idx + 1 ..];

        // Check if first component has wildcards
        const has_wildcards = std.mem.indexOfAny(u8, first_component, "*?") != null;

        if (has_wildcards) {
            // Match directories against first component pattern
            var iter_dir = try base_dir.openDir(".", .{ .iterate = true });
            defer iter_dir.close();

            var iter = iter_dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind != .directory) continue;
                if (entry.name[0] == '.') continue; // Skip hidden dirs

                if (match(first_component, entry.name)) {
                    // Recursively search in matched directory
                    var subdir = base_dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                    defer subdir.close();

                    const sub_results = try findDirs(allocator, subdir, rest_pattern);
                    defer {
                        for (sub_results) |r| allocator.free(r);
                        allocator.free(sub_results);
                    }

                    // Prepend current directory name to all sub-results
                    for (sub_results) |sub_path| {
                        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ entry.name, sub_path });
                        try results.append(allocator, full_path);
                    }
                }
            }
        } else {
            // Literal directory name - open it and continue recursively
            var subdir = base_dir.openDir(first_component, .{ .iterate = true }) catch return results.toOwnedSlice(allocator);
            defer subdir.close();

            const sub_results = try findDirs(allocator, subdir, rest_pattern);
            defer {
                for (sub_results) |r| allocator.free(r);
                allocator.free(sub_results);
            }

            for (sub_results) |sub_path| {
                const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ first_component, sub_path });
                try results.append(allocator, full_path);
            }
        }
    } else {
        // Pattern is a single component (e.g., "*" or "src")
        // This is the final component - match directories
        const has_wildcards = std.mem.indexOfAny(u8, pattern, "*?") != null;

        if (has_wildcards) {
            var iter_dir = try base_dir.openDir(".", .{ .iterate = true });
            defer iter_dir.close();

            var iter = iter_dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind != .directory) continue;
                if (entry.name[0] == '.') continue; // Skip hidden dirs

                if (match(pattern, entry.name)) {
                    const path = try allocator.dupe(u8, entry.name);
                    try results.append(allocator, path);
                }
            }
        } else {
            // Literal directory name - just check if it exists
            base_dir.access(pattern, .{}) catch return results.toOwnedSlice(allocator);
            const path = try allocator.dupe(u8, pattern);
            try results.append(allocator, path);
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

test "findDirs - simple wildcard" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test directories
    try tmp_dir.dir.makeDir("pkg1");
    try tmp_dir.dir.makeDir("pkg2");
    try tmp_dir.dir.makeDir("other");

    const results = try findDirs(allocator, tmp_dir.dir, "pkg*");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "findDirs - nested pattern" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create nested structure: packages/pkg1/src, packages/pkg2/src
    try tmp_dir.dir.makeDir("packages");
    try tmp_dir.dir.makeDir("packages/pkg1");
    try tmp_dir.dir.makeDir("packages/pkg1/src");
    try tmp_dir.dir.makeDir("packages/pkg2");
    try tmp_dir.dir.makeDir("packages/pkg2/src");
    try tmp_dir.dir.makeDir("packages/other");

    const results = try findDirs(allocator, tmp_dir.dir, "packages/*/src");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
    // Both paths should start with "packages/"
    for (results) |path| {
        try std.testing.expect(std.mem.startsWith(u8, path, "packages/"));
        try std.testing.expect(std.mem.endsWith(u8, path, "/src"));
    }
}

test "findDirs - literal path" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("src");

    const results = try findDirs(allocator, tmp_dir.dir, "src");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("src", results[0]);
}

test "findDirs - nonexistent path" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const results = try findDirs(allocator, tmp_dir.dir, "nonexistent");
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "find - wildcards in directory path" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create structure: packages/pkg1/main.zig, packages/pkg2/main.zig
    try tmp_dir.dir.makeDir("packages");
    try tmp_dir.dir.makeDir("packages/pkg1");
    try tmp_dir.dir.makeDir("packages/pkg2");
    try tmp_dir.dir.writeFile(.{ .sub_path = "packages/pkg1/main.zig", .data = "content" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "packages/pkg2/main.zig", .data = "content" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "packages/pkg1/util.zig", .data = "content" });

    const results = try find(allocator, tmp_dir.dir, "packages/*/main.zig");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
    for (results) |path| {
        try std.testing.expect(std.mem.endsWith(u8, path, "/main.zig"));
    }
}

test "findDirs - skips hidden directories" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("visible");
    try tmp_dir.dir.makeDir(".hidden");

    const results = try findDirs(allocator, tmp_dir.dir, "*");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    // Should only find "visible", not ".hidden"
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("visible", results[0]);
}
