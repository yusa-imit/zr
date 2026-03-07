const std = @import("std");
const types = @import("../config/types.zig");

/// Cache entry metadata stored on disk.
/// File name: <hex-hash>.ok  (task succeeded)
/// File name: <hex-hash>.fail (task failed — stored so we don't cache failures by default)
///
/// Cache directory: $HOME/.zr/cache/  (falls back to /tmp/.zr/cache/ if HOME unset)
pub const CacheStore = struct {
    /// Base directory for cache files (owned).
    dir_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !CacheStore {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
        defer if (home) |h| allocator.free(h);

        const dir_path = if (home) |h|
            try std.fs.path.join(allocator, &[_][]const u8{ h, ".zr", "cache" })
        else
            try allocator.dupe(u8, "/tmp/.zr/cache");

        // Ensure directory exists
        std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return CacheStore{
            .dir_path = dir_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CacheStore) void {
        self.allocator.free(self.dir_path);
    }

    /// Compute a 64-bit hash key for a task based on its cmd and env vars.
    /// Returns the hash as a hex string (16 chars, caller owns memory).
    pub fn computeKey(allocator: std.mem.Allocator, cmd: []const u8, env: ?[]const [2][]const u8) ![]u8 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(cmd);
        if (env) |pairs| {
            for (pairs) |pair| {
                hasher.update(pair[0]);
                hasher.update("=");
                hasher.update(pair[1]);
                hasher.update(";");
            }
        }
        const hash_val = hasher.final();
        return std.fmt.allocPrint(allocator, "{x:0>16}", .{hash_val});
    }

    /// Check if a successful cache entry exists for the given key.
    pub fn hasHit(self: *const CacheStore, key: []const u8) bool {
        const file_name = std.fmt.allocPrint(self.allocator, "{s}.ok", .{key}) catch return false;
        defer self.allocator.free(file_name);

        const path = std.fs.path.join(self.allocator, &[_][]const u8{ self.dir_path, file_name }) catch return false;
        defer self.allocator.free(path);

        // Try to stat the file; success means cache hit
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Record a successful task execution in the cache.
    /// Uses atomic write (temp file + rename) to prevent race conditions in concurrent writes.
    pub fn recordHit(self: *const CacheStore, key: []const u8) !void {
        const file_name = try std.fmt.allocPrint(self.allocator, "{s}.ok", .{key});
        defer self.allocator.free(file_name);

        const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.dir_path, file_name });
        defer self.allocator.free(path);

        // Write to temporary file first (use timestamp + thread ID for uniqueness)
        const timestamp = std.time.nanoTimestamp();
        const thread_id = std.Thread.getCurrentId();
        const temp_name = try std.fmt.allocPrint(self.allocator, "{s}.tmp.{d}.{d}", .{ key, timestamp, thread_id });
        defer self.allocator.free(temp_name);

        const temp_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.dir_path, temp_name });
        defer self.allocator.free(temp_path);

        // Create temp file
        const file = try std.fs.cwd().createFile(temp_path, .{ .truncate = true });
        file.close();

        // Atomically rename to final name (this operation is atomic on POSIX and Windows)
        std.fs.cwd().rename(temp_path, path) catch |err| {
            // Clean up temp file on failure
            std.fs.cwd().deleteFile(temp_path) catch {};
            return err;
        };
    }

    /// Remove a specific cache entry.
    pub fn invalidate(self: *const CacheStore, key: []const u8) void {
        const file_name = std.fmt.allocPrint(self.allocator, "{s}.ok", .{key}) catch return;
        defer self.allocator.free(file_name);

        const path = std.fs.path.join(self.allocator, &[_][]const u8{ self.dir_path, file_name }) catch return;
        defer self.allocator.free(path);

        std.fs.cwd().deleteFile(path) catch {};
    }

    /// Remove all cache entries. Returns the number of entries deleted.
    pub fn clearAll(self: *const CacheStore) !usize {
        var dir = std.fs.cwd().openDir(self.dir_path, .{ .iterate = true }) catch return 0;
        defer dir.close();

        var count: usize = 0;
        var it = dir.iterate();
        // Collect file names first to avoid iterator invalidation during deletion
        var names = std.ArrayList([]u8){};
        defer {
            for (names.items) |n| self.allocator.free(n);
            names.deinit(self.allocator);
        }

        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".ok")) continue;
            const name_copy = try self.allocator.dupe(u8, entry.name);
            try names.append(self.allocator, name_copy);
        }

        for (names.items) |name| {
            dir.deleteFile(name) catch continue;
            count += 1;
        }

        return count;
    }

    /// Clear cache for a specific workspace member by computing keys for all tasks in the config.
    /// This requires loading the config file and computing cache keys for each task.
    /// Returns the number of entries deleted.
    pub fn clearForMember(
        self: *const CacheStore,
        member_path: []const u8,
        config: types.Config,
    ) !usize {
        var count: usize = 0;

        // Iterate through tasks in the config and invalidate their cache entries
        var task_it = config.tasks.iterator();
        while (task_it.next()) |entry| {
            const task = entry.value_ptr;

            // Compute cache key for this task
            const key = try CacheStore.computeKey(self.allocator, task.cmd, if (task.env.len > 0) task.env else null);
            defer self.allocator.free(key);

            // Check if cache entry exists
            if (self.hasHit(key)) {
                self.invalidate(key);
                count += 1;
            }
        }

        _ = member_path; // Path may be needed for future enhancements

        return count;
    }

    /// Get cache statistics.
    pub fn getStats(self: *const CacheStore) !CacheStats {
        var stats = CacheStats{
            .total_entries = 0,
            .total_size_bytes = 0,
            .cache_dir = self.dir_path,
        };

        var dir = std.fs.cwd().openDir(self.dir_path, .{ .iterate = true }) catch {
            // Directory doesn't exist yet
            return stats;
        };
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".ok")) continue;

            stats.total_entries += 1;

            // Get file size
            const file = dir.openFile(entry.name, .{}) catch continue;
            defer file.close();
            const stat = file.stat() catch continue;
            stats.total_size_bytes += stat.size;
        }

        return stats;
    }
};

pub const CacheStats = struct {
    total_entries: usize,
    total_size_bytes: u64,
    cache_dir: []const u8,
};

// --- Tests ---

test "computeKey is deterministic" {
    const allocator = std.testing.allocator;
    const key1 = try CacheStore.computeKey(allocator, "echo hello", null);
    defer allocator.free(key1);
    const key2 = try CacheStore.computeKey(allocator, "echo hello", null);
    defer allocator.free(key2);
    try std.testing.expectEqualStrings(key1, key2);
}

test "computeKey differs for different cmds" {
    const allocator = std.testing.allocator;
    const key1 = try CacheStore.computeKey(allocator, "echo hello", null);
    defer allocator.free(key1);
    const key2 = try CacheStore.computeKey(allocator, "echo world", null);
    defer allocator.free(key2);
    try std.testing.expect(!std.mem.eql(u8, key1, key2));
}

test "computeKey differs for different env" {
    const allocator = std.testing.allocator;
    const env1 = [_][2][]const u8{.{ "FOO", "bar" }};
    const env2 = [_][2][]const u8{.{ "FOO", "baz" }};
    const key1 = try CacheStore.computeKey(allocator, "make build", &env1);
    defer allocator.free(key1);
    const key2 = try CacheStore.computeKey(allocator, "make build", &env2);
    defer allocator.free(key2);
    try std.testing.expect(!std.mem.eql(u8, key1, key2));
}

test "key is 16 hex chars" {
    const allocator = std.testing.allocator;
    const key = try CacheStore.computeKey(allocator, "zig build", null);
    defer allocator.free(key);
    try std.testing.expectEqual(@as(usize, 16), key.len);
    for (key) |c| {
        try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }
}

test "hasHit returns false for unknown key" {
    const allocator = std.testing.allocator;
    var store = try CacheStore.init(allocator);
    defer store.deinit();
    try std.testing.expect(!store.hasHit("deadbeefdeadbeef"));
}

test "recordHit and hasHit roundtrip" {
    const allocator = std.testing.allocator;
    var store = try CacheStore.init(allocator);
    defer store.deinit();

    const key = try CacheStore.computeKey(allocator, "zr-test-cache-roundtrip", null);
    defer allocator.free(key);

    // Ensure clean state
    store.invalidate(key);
    try std.testing.expect(!store.hasHit(key));

    try store.recordHit(key);
    try std.testing.expect(store.hasHit(key));

    // Cleanup
    store.invalidate(key);
    try std.testing.expect(!store.hasHit(key));
}

test "clearAll removes cache entries" {
    const allocator = std.testing.allocator;
    var store = try CacheStore.init(allocator);
    defer store.deinit();

    const key1 = try CacheStore.computeKey(allocator, "zr-clear-test-1", null);
    defer allocator.free(key1);
    const key2 = try CacheStore.computeKey(allocator, "zr-clear-test-2", null);
    defer allocator.free(key2);

    try store.recordHit(key1);
    try store.recordHit(key2);

    try std.testing.expect(store.hasHit(key1));
    try std.testing.expect(store.hasHit(key2));

    const removed = try store.clearAll();
    try std.testing.expect(removed >= 2);

    try std.testing.expect(!store.hasHit(key1));
    try std.testing.expect(!store.hasHit(key2));
}
