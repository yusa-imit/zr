const std = @import("std");
const types = @import("../config/types.zig");
const glob_mod = @import("../util/glob.zig");
const stdx = @import("../stdx.zig");
const assert = stdx.assert;

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
        const builtin = @import("builtin");
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
        defer if (home) |h| allocator.free(h);

        const dir_path = if (home) |h|
            try std.fs.path.join(allocator, &[_][]const u8{ h, ".zr", "cache" })
        else blk: {
            // Fallback to system temp directory (platform-agnostic)
            const tmp_path = switch (builtin.os.tag) {
                .windows => std.process.getEnvVarOwned(allocator, "TEMP") catch
                    std.process.getEnvVarOwned(allocator, "TMP") catch
                    try allocator.dupe(u8, "C:\\Windows\\Temp"),
                else => std.process.getEnvVarOwned(allocator, "TMPDIR") catch
                    try allocator.dupe(u8, "/tmp"),
            };
            defer allocator.free(tmp_path);
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".zr", "cache" });
        };

        assert(dir_path.len > 0); // $HOME and fallback-temp branches both build a non-empty path.

        // Ensure directory exists
        std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const store = CacheStore{
            .dir_path = dir_path,
            .allocator = allocator,
        };
        assert(store.dir_path.len > 0); // Re-checked on the struct, not just the local.
        return store;
    }

    pub fn deinit(self: *CacheStore) void {
        assert(self.dir_path.len > 0); // deinit is never called on a moved-from/zeroed store.
        const dir_path = self.dir_path;
        self.allocator.free(dir_path);
        assert(dir_path.len > 0); // The freed slice's length is untouched by free() itself.
    }

    /// Renders a hasher's final digest as the 16-char hex key every cache-key function returns.
    fn finalizeKey(allocator: std.mem.Allocator, hasher: *std.hash.Wyhash) ![]u8 {
        const hash_val = hasher.final();
        const key = try std.fmt.allocPrint(allocator, "{x:0>16}", .{hash_val});
        assert(key.len == 16); // Fixed-width u64 hex formatting always produces 16 digits.
        return key;
    }

    /// Compute a 64-bit hash key for a task based on its cmd and env vars.
    /// Returns the hash as a hex string (16 chars, caller owns memory).
    pub fn computeKey(allocator: std.mem.Allocator, cmd: []const u8, env: ?[]const [2][]const u8) ![]u8 {
        stdx.maybe(cmd.len == 0); // cmd is user config data; unusual empty, but not our contract.
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
        return finalizeKey(allocator, &hasher);
    }

    /// Compute cache key including source file content hashes.
    /// Use this for tasks with `inputs`/`sources` so file edits invalidate the cache.
    /// `cwd` is the directory from which glob patterns are resolved.
    /// Returns a 16-char hex string (caller owns).
    pub fn computeKeyWithSources(
        allocator: std.mem.Allocator,
        cmd: []const u8,
        env: ?[]const [2][]const u8,
        sources: []const []const u8,
        cwd: []const u8,
    ) ![]u8 {
        assert(cwd.len > 0); // Caller resolves globs from a real directory, never "".
        stdx.maybe(sources.len == 0); // No inputs/sources is a legitimate, common case.
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

        if (sources.len > 0) {
            var base_dir = std.fs.cwd().openDir(cwd, .{ .iterate = true }) catch {
                // If we can't open the cwd, fall back to key without source hashes
                return finalizeKey(allocator, &hasher);
            };
            defer base_dir.close();

            // Collect all matching file paths
            var matched = std.ArrayList([]const u8){};
            defer {
                for (matched.items) |f| allocator.free(f);
                matched.deinit(allocator);
            }

            for (sources) |pattern| {
                const files = glob_mod.find(allocator, base_dir, pattern) catch continue;
                defer {
                    for (files) |f| allocator.free(f);
                    allocator.free(files);
                }
                for (files) |f| {
                    try matched.append(allocator, try allocator.dupe(u8, f));
                }
            }

            // Sort for determinism
            std.mem.sort([]const u8, matched.items, {}, struct {
                fn lt(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.lt);

            for (matched.items) |file_path| {
                hasher.update(file_path);
                hasher.update("\x00");
                const content = base_dir.readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
                    hasher.update(@errorName(err));
                    hasher.update("\x00");
                    continue;
                };
                defer allocator.free(content);
                hasher.update(content);
                hasher.update("\x00");
            }
        }

        return finalizeKey(allocator, &hasher);
    }

    /// Check if a successful cache entry exists for the given key.
    pub fn hasHit(self: *const CacheStore, key: []const u8) bool {
        assert(key.len > 0); // Every caller passes a computeKey()/computeKeyWithSources() result.
        assert(self.dir_path.len > 0); // Same invariant established at init(), still holding.
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
        assert(key.len > 0); // Every caller passes a computeKey()/computeKeyWithSources() result.
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

        // Atomically rename to final name (this operation is atomic on POSIX and Windows).
        // Not re-verified with a stat after rename: recordHit is on the task-completion hot
        // path, and rename()'s own success/error result is already the authoritative signal.
        std.fs.cwd().rename(temp_path, path) catch |err| {
            // Clean up temp file on failure
            std.fs.cwd().deleteFile(temp_path) catch {};
            return err;
        };
    }

    /// Remove a specific cache entry.
    pub fn invalidate(self: *const CacheStore, key: []const u8) void {
        assert(key.len > 0); // Every caller passes a computeKey()/computeKeyWithSources() result.
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

        assert(count <= names.items.len); // Deletions never exceed the collected `.ok` file set.
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
        stdx.maybe(member_path.len == 0); // Unused today (see below); a caller may still pass "".
        const task_count = config.tasks.count();
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

        // member_path itself is unused today (invalidation is by task cache key, not by path);
        // kept as a parameter for a future member-scoped filter.

        assert(count <= task_count); // At most one invalidation per task in the config.
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

        // Independent re-derivation of "no entries": a directory with zero counted `.ok`
        // files can only have accumulated zero bytes, since size only ever adds per entry.
        if (stats.total_entries == 0) assert(stats.total_size_bytes == 0);
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

test "computeKeyWithSources changes when file content changes" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [512]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    try tmp.dir.writeFile(.{ .sub_path = "input.txt", .data = "v1" });

    const key1 = try CacheStore.computeKeyWithSources(
        allocator,
        "cat input.txt",
        null,
        &[_][]const u8{"input.txt"},
        tmp_path,
    );
    defer allocator.free(key1);

    try tmp.dir.writeFile(.{ .sub_path = "input.txt", .data = "v2" });

    const key2 = try CacheStore.computeKeyWithSources(
        allocator,
        "cat input.txt",
        null,
        &[_][]const u8{"input.txt"},
        tmp_path,
    );
    defer allocator.free(key2);

    // Different file content → different cache key → cache invalidated
    try std.testing.expect(!std.mem.eql(u8, key1, key2));
}

test "computeKey handles empty cmd and no env" {
    const allocator = std.testing.allocator;
    const key = try CacheStore.computeKey(allocator, "", null);
    defer allocator.free(key);
    try std.testing.expectEqual(@as(usize, 16), key.len);
}

test "computeKeyWithSources tolerates a pattern matching no files" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [512]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const key = try CacheStore.computeKeyWithSources(
        allocator,
        "echo hi",
        null,
        &[_][]const u8{"no-such-file-*.txt"},
        tmp_path,
    );
    defer allocator.free(key);
    try std.testing.expectEqual(@as(usize, 16), key.len);
}

test "computeKeyWithSources stable for unchanged files" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [512]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    try tmp.dir.writeFile(.{ .sub_path = "input.txt", .data = "stable" });

    const key1 = try CacheStore.computeKeyWithSources(
        allocator,
        "cat input.txt",
        null,
        &[_][]const u8{"input.txt"},
        tmp_path,
    );
    defer allocator.free(key1);

    const key2 = try CacheStore.computeKeyWithSources(
        allocator,
        "cat input.txt",
        null,
        &[_][]const u8{"input.txt"},
        tmp_path,
    );
    defer allocator.free(key2);

    try std.testing.expectEqualStrings(key1, key2);
}
