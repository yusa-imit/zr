const std = @import("std");
const builtin = @import("builtin");
const native = @import("native.zig");

pub const WatchMode = enum {
    /// Native OS-specific watchers (inotify/kqueue/ReadDirectoryChangesW)
    native,
    /// Polling-based fallback
    polling,
};

/// A file change event: the path that changed.
pub const WatchEvent = struct {
    /// Slice into a path owned by the watcher's internal map.
    /// Valid until the next call to waitForChange or deinit.
    path: []const u8,
};

/// Directories to skip during recursive walks.
const SKIP_DIRS = [_][]const u8{
    ".git",
    "node_modules",
    "zig-out",
    ".zig-cache",
};

/// Adaptive filesystem watcher that uses native OS APIs when available,
/// falling back to polling mode if needed.
///
/// Native modes:
/// - Linux: inotify
/// - macOS: kqueue
/// - Windows: ReadDirectoryChangesW
///
/// Fallback: polling-based mtime checking
pub const Watcher = struct {
    mode: WatchMode,
    impl: union(WatchMode) {
        native: NativeWatcherWrapper,
        polling: PollingWatcher,
    },

    const Self = @This();

    const NativeWatcherWrapper = struct {
        allocator: std.mem.Allocator,
        watcher: native.NativeWatcher,
    };

    /// Initialize the watcher with the preferred mode.
    /// If native mode is requested but fails, falls back to polling automatically.
    pub fn init(allocator: std.mem.Allocator, paths: []const []const u8, mode: WatchMode, poll_ms: u64) !Self {
        if (mode == .native) {
            if (supportsNativeMode()) {
                if (native.NativeWatcher.init(allocator, paths)) |watcher| {
                    return Self{
                        .mode = .native,
                        .impl = .{ .native = .{ .allocator = allocator, .watcher = watcher } },
                    };
                } else |_| {
                    // Fall back to polling on error
                }
            }
        }

        // Use polling mode
        const polling_watcher = try PollingWatcher.init(allocator, paths, poll_ms);
        return Self{
            .mode = .polling,
            .impl = .{ .polling = polling_watcher },
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.impl) {
            .native => |*wrapper| wrapper.watcher.deinit(),
            .polling => |*watcher| watcher.deinit(),
        }
    }

    /// Wait for a filesystem change. Blocks until a change is detected.
    pub fn waitForChange(self: *Self) !WatchEvent {
        return switch (self.impl) {
            .native => |*wrapper| {
                const event = try wrapper.watcher.waitForEvent();
                return WatchEvent{ .path = event.path };
            },
            .polling => |*watcher| try watcher.waitForChange(),
        };
    }

    fn supportsNativeMode() bool {
        return builtin.os.tag == .linux or builtin.os.tag == .macos or builtin.os.tag == .windows;
    }
};

/// Legacy polling-based filesystem watcher for compatibility.
const PollingWatcher = struct {
    allocator: std.mem.Allocator,
    /// Paths to watch (dirs or individual files). Caller owns.
    paths: []const []const u8,
    /// Poll interval in milliseconds.
    poll_ms: u64,
    /// Internal mtime snapshot: path (owned) → last mtime nanoseconds.
    mtimes: std.StringHashMap(i128),

    const Self = @This();

    /// Initialize the watcher. Takes an initial mtime snapshot.
    pub fn init(allocator: std.mem.Allocator, paths: []const []const u8, poll_ms: u64) !Self {
        var self = Self{
            .allocator = allocator,
            .paths = paths,
            .poll_ms = poll_ms,
            .mtimes = std.StringHashMap(i128).init(allocator),
        };
        try self.snapshot();
        return self;
    }

    pub fn deinit(self: *Self) void {
        var it = self.mtimes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.mtimes.deinit();
    }

    /// Block until a filesystem change is detected.
    /// Returns a WatchEvent describing the changed path.
    /// The returned path is owned by the watcher's internal map; it is
    /// valid until the next call to waitForChange or deinit.
    pub fn waitForChange(self: *Self) !WatchEvent {
        while (true) {
            std.Thread.sleep(self.poll_ms * std.time.ns_per_ms);

            // Walk all paths and compare mtimes.
            for (self.paths) |root| {
                const changed = try self.checkPath(root);
                if (changed) |path| {
                    return WatchEvent{ .path = path };
                }
            }
        }
    }

    // --- internals ---

    /// Scan all watched paths and record their current mtimes.
    fn snapshot(self: *Self) !void {
        for (self.paths) |root| {
            try self.snapshotPath(root);
        }
    }

    /// Snapshot a single path (file or directory).
    fn snapshotPath(self: *Self, root: []const u8) !void {
        const stat = std.fs.cwd().statFile(root) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied, error.IsDir => {
                // Try as directory
                try self.snapshotDir(root);
                return;
            },
            else => return err,
        };
        if (stat.kind == .directory) {
            try self.snapshotDir(root);
        } else {
            try self.recordMtime(root, stat.mtime);
        }
    }

    fn snapshotDir(self: *Self, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();
        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (shouldSkip(entry.basename)) continue;
            if (entry.kind == .directory) continue;

            // Build full path: dir_path + "/" + entry.path
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.path });
            defer self.allocator.free(full_path);

            const stat = dir.statFile(entry.path) catch continue;
            try self.recordMtime(full_path, stat.mtime);
        }
    }

    fn recordMtime(self: *Self, path: []const u8, mtime: i128) !void {
        if (self.mtimes.contains(path)) {
            // Update existing entry's value (key already owned).
            const entry = self.mtimes.getEntry(path).?;
            entry.value_ptr.* = mtime;
        } else {
            const owned_path = try self.allocator.dupe(u8, path);
            errdefer self.allocator.free(owned_path);
            try self.mtimes.put(owned_path, mtime);
        }
    }

    /// Check one root path for changes. Returns a changed path or null.
    fn checkPath(self: *Self, root: []const u8) !?[]const u8 {
        const stat = std.fs.cwd().statFile(root) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied, error.IsDir => {
                return try self.checkDir(root);
            },
            else => return err,
        };
        if (stat.kind == .directory) {
            return try self.checkDir(root);
        }
        return try self.checkFile(root, stat.mtime);
    }

    fn checkDir(self: *Self, dir_path: []const u8) !?[]const u8 {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return null;
        defer dir.close();
        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (shouldSkip(entry.basename)) continue;
            if (entry.kind == .directory) continue;

            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.path });
            defer self.allocator.free(full_path);

            const stat = dir.statFile(entry.path) catch continue;

            if (try self.checkFile(full_path, stat.mtime)) |changed| {
                // `changed` points into mtimes map (owned key) — safe to return.
                return changed;
            }
        }
        return null;
    }

    /// Compare mtime to stored value. Updates stored mtime if changed.
    /// Returns the owned path key from the map if changed, else null.
    fn checkFile(self: *Self, path: []const u8, mtime: i128) !?[]const u8 {
        if (self.mtimes.getEntry(path)) |entry| {
            if (entry.value_ptr.* != mtime) {
                entry.value_ptr.* = mtime;
                return entry.key_ptr.*;
            }
        } else {
            // New file — record and report as changed.
            const owned = try self.allocator.dupe(u8, path);
            try self.mtimes.put(owned, mtime);
            return self.mtimes.getEntry(path).?.key_ptr.*;
        }
        return null;
    }
};

fn shouldSkip(basename: []const u8) bool {
    for (SKIP_DIRS) |skip| {
        if (std.mem.eql(u8, basename, skip)) return true;
    }
    return false;
}

// --- Tests ---

test "watcher native mode compiles and initializes" {
    const allocator = std.testing.allocator;
    const watch_paths = [_][]const u8{"."};

    var watcher = try Watcher.init(allocator, &watch_paths, .native, 500);
    defer watcher.deinit();

    // Just verify it initialized successfully
    try std.testing.expect(watcher.mode == .native or watcher.mode == .polling);
}

test "watcher polling mode detects file change" {
    const allocator = std.testing.allocator;

    // Create a temp dir with a file.
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write initial file.
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.txt", .data = "hello" });

    const watch_paths = [_][]const u8{tmp_path};

    var watcher = try Watcher.init(allocator, &watch_paths, .polling, 10);
    defer watcher.deinit();

    // Modify the file — sleep briefly to ensure mtime difference on fast filesystems.
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.txt", .data = "world" });

    // checkPath should detect the change (internal polling watcher)
    const changed = try watcher.impl.polling.checkPath(tmp_path);
    try std.testing.expect(changed != null);
}

test "watcher detects new file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write one file initially.
    try tmp_dir.dir.writeFile(.{ .sub_path = "a.txt", .data = "a" });

    const watch_paths = [_][]const u8{tmp_path};
    var watcher = try Watcher.init(allocator, &watch_paths, .polling, 10);
    defer watcher.deinit();

    // Add a new file — watcher should see it as changed.
    try tmp_dir.dir.writeFile(.{ .sub_path = "b.txt", .data = "b" });

    const changed = try watcher.impl.polling.checkPath(tmp_path);
    try std.testing.expect(changed != null);
}

test "watcher no change" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp_dir.dir.writeFile(.{ .sub_path = "stable.txt", .data = "content" });

    const watch_paths = [_][]const u8{tmp_path};
    var watcher = try Watcher.init(allocator, &watch_paths, .polling, 10);
    defer watcher.deinit();

    // No modification — should return null.
    const changed = try watcher.impl.polling.checkPath(tmp_path);
    try std.testing.expect(changed == null);
}

test "shouldSkip skips known dirs" {
    try std.testing.expect(shouldSkip(".git"));
    try std.testing.expect(shouldSkip("node_modules"));
    try std.testing.expect(shouldSkip("zig-out"));
    try std.testing.expect(shouldSkip(".zig-cache"));
    try std.testing.expect(!shouldSkip("src"));
    try std.testing.expect(!shouldSkip("my_file.zig"));
}
