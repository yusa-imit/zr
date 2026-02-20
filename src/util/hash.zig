const std = @import("std");

/// Hash a file's contents using Wyhash and return a 64-bit hash.
/// Returns error.FileNotFound if the file doesn't exist.
/// Returns error.AccessDenied if the file cannot be read.
pub fn hashFile(allocator: std.mem.Allocator, path: []const u8) !u64 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.AccessDenied => return error.AccessDenied,
        else => return err,
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 100 * 1024 * 1024) catch |err| switch (err) {
        error.AccessDenied => return error.AccessDenied,
        else => return err,
    };
    defer allocator.free(contents);

    return std.hash.Wyhash.hash(0, contents);
}

/// Hash a string using Wyhash and return a 64-bit hash.
pub fn hashString(s: []const u8) u64 {
    return std.hash.Wyhash.hash(0, s);
}

/// Hash multiple strings together using Wyhash.
pub fn hashStrings(strings: []const []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (strings) |s| {
        hasher.update(s);
    }
    return hasher.final();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "hashString - basic" {
    const h1 = hashString("hello");
    const h2 = hashString("hello");
    const h3 = hashString("world");

    // Same input produces same hash
    try std.testing.expectEqual(h1, h2);

    // Different input produces different hash
    try std.testing.expect(h1 != h3);
}

test "hashString - empty" {
    const h = hashString("");
    try std.testing.expect(h != 0);
}

test "hashStrings - multiple inputs" {
    const h1 = hashStrings(&.{ "hello", "world" });
    const h2 = hashStrings(&.{ "hello", "world" });
    const h3 = hashStrings(&.{ "world", "hello" });

    // Same inputs in same order produce same hash
    try std.testing.expectEqual(h1, h2);

    // Different order produces different hash
    try std.testing.expect(h1 != h3);
}

test "hashStrings - empty array" {
    const h = hashStrings(&.{});
    try std.testing.expect(h != 0);
}

test "hashFile - basic" {
    const allocator = std.testing.allocator;

    // Create a temporary file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_content = "test file content for hashing";
    {
        const file = try tmp_dir.dir.createFile("test.txt", .{});
        defer file.close();
        try file.writeAll(test_content);
    }

    // Hash the file
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);
    const hash = try hashFile(allocator, path);

    // Hash should be deterministic
    const hash2 = try hashFile(allocator, path);
    try std.testing.expectEqual(hash, hash2);

    // Hash should match direct string hash
    const direct_hash = hashString(test_content);
    try std.testing.expectEqual(direct_hash, hash);
}

test "hashFile - nonexistent file" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.FileNotFound, hashFile(allocator, "/nonexistent/file.txt"));
}

test "hashFile - large file" {
    const allocator = std.testing.allocator;

    // Create a temporary file with larger content
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const file = try tmp_dir.dir.createFile("large.bin", .{});
        defer file.close();

        // Write 1MB of data
        var i: usize = 0;
        while (i < 1024) : (i += 1) {
            try file.writeAll(&([_]u8{0xAA} ** 1024));
        }
    }

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("large.bin", &path_buf);
    const hash = try hashFile(allocator, path);

    // Hash should be non-zero
    try std.testing.expect(hash != 0);
}

test "hashFile - empty file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const file = try tmp_dir.dir.createFile("empty.txt", .{});
        file.close();
    }

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("empty.txt", &path_buf);
    const hash = try hashFile(allocator, path);

    // Empty file should hash to same as empty string
    const empty_hash = hashString("");
    try std.testing.expectEqual(empty_hash, hash);
}
