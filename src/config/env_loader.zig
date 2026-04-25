const std = @import("std");

/// Load environment variables from a .env file.
/// Format: KEY=value, KEY="quoted value", # comments, empty lines ignored.
/// Returns a StringHashMap of loaded variables (caller owns).
pub fn loadEnvFile(allocator: std.mem.Allocator, file_path: []const u8) !std.StringHashMap([]const u8) {
    var env_map = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    // Handle both absolute and relative paths
    const file: std.fs.File = blk: {
        // Check if path is absolute (starts with / on Unix, or has drive letter on Windows)
        const is_abs = std.fs.path.isAbsolute(file_path);
        const result = if (is_abs)
            std.fs.openFileAbsolute(file_path, .{})
        else
            std.fs.cwd().openFile(file_path, .{});

        break :blk result catch |err| {
            // Missing .env file is not an error — return empty map
            if (err == error.FileNotFound) {
                return env_map;
            }
            return err;
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB limit
    defer allocator.free(content);

    var line_it = std.mem.splitScalar(u8, content, '\n');
    while (line_it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Find the first '=' separator
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_idx| {
            const key = std.mem.trim(u8, trimmed[0..eq_idx], &std.ascii.whitespace);
            if (key.len == 0) continue; // Invalid: no key

            var value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], &std.ascii.whitespace);

            // Handle quoted values: "value" or 'value'
            if (value.len >= 2) {
                if ((value[0] == '"' and value[value.len - 1] == '"') or
                    (value[0] == '\'' and value[value.len - 1] == '\''))
                {
                    value = value[1 .. value.len - 1];
                }
            }

            // Store (dupe both key and value)
            const key_owned = try allocator.dupe(u8, key);
            errdefer allocator.free(key_owned);
            const value_owned = try allocator.dupe(u8, value);
            errdefer allocator.free(value_owned);

            // If key already exists, free old value and replace
            if (try env_map.fetchPut(key_owned, value_owned)) |old_entry| {
                allocator.free(old_entry.key);
                allocator.free(old_entry.value);
            }
        }
        // Lines without '=' are ignored (invalid format)
    }

    return env_map;
}

/// Load multiple .env files with override semantics (later files override earlier).
/// Returns a merged StringHashMap (caller owns).
pub fn loadEnvFiles(allocator: std.mem.Allocator, file_paths: []const []const u8) !std.StringHashMap([]const u8) {
    var merged = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = merged.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        merged.deinit();
    }

    for (file_paths) |file_path| {
        var file_map = try loadEnvFile(allocator, file_path);
        defer {
            var it = file_map.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            file_map.deinit();
        }

        // Merge into result (later values override earlier)
        var it = file_map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Check if key already exists before we dupe
            if (merged.get(key)) |_| {
                // Key exists, so we'll override it
                // First, get and free the old value (but keep the key pointer for now)
                if (merged.getPtr(key)) |old_entry_ptr| {
                    allocator.free(old_entry_ptr.*);
                    old_entry_ptr.* = try allocator.dupe(u8, value);
                }
            } else {
                // Key doesn't exist, insert it
                const key_owned = try allocator.dupe(u8, key);
                errdefer allocator.free(key_owned);
                const value_owned = try allocator.dupe(u8, value);
                errdefer allocator.free(value_owned);
                try merged.put(key_owned, value_owned);
            }
        }
    }

    return merged;
}

test "loadEnvFile: basic KEY=value" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create .env file
    const env_content = "KEY1=value1\nKEY2=value2\n";
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    const allocator = testing.allocator;
    const path = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path);

    var env_map = try loadEnvFile(allocator, path);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqual(@as(usize, 2), env_map.count());
    try testing.expectEqualStrings("value1", env_map.get("KEY1").?);
    try testing.expectEqualStrings("value2", env_map.get("KEY2").?);
}

test "loadEnvFile: quoted values" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env_content = "KEY1=\"value with spaces\"\nKEY2='single quoted'\n";
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    const allocator = testing.allocator;
    const path = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path);

    var env_map = try loadEnvFile(allocator, path);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqualStrings("value with spaces", env_map.get("KEY1").?);
    try testing.expectEqualStrings("single quoted", env_map.get("KEY2").?);
}

test "loadEnvFile: comments and empty lines" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env_content = "# Comment line\nKEY1=value1\n\nKEY2=value2\n# Another comment\n";
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    const allocator = testing.allocator;
    const path = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path);

    var env_map = try loadEnvFile(allocator, path);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqual(@as(usize, 2), env_map.count());
}

test "loadEnvFile: missing file returns empty map" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = try loadEnvFile(allocator, "/nonexistent/file.env");
    defer env_map.deinit();

    try testing.expectEqual(@as(usize, 0), env_map.count());
}

test "loadEnvFiles: multiple files with override" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = "KEY1=base\nKEY2=base2\n" });
    try tmp.dir.writeFile(.{ .sub_path = ".env.local", .data = "KEY1=override\n" });

    const allocator = testing.allocator;
    const path1 = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path1);
    const path2 = try tmp.dir.realpathAlloc(allocator, ".env.local");
    defer allocator.free(path2);

    const paths = [_][]const u8{ path1, path2 };
    var env_map = try loadEnvFiles(allocator, &paths);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqualStrings("override", env_map.get("KEY1").?);
    try testing.expectEqualStrings("base2", env_map.get("KEY2").?);
}
