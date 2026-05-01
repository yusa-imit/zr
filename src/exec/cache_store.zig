const std = @import("std");
const cache_key_mod = @import("cache_key.zig");

/// Cache storage for task execution results (Phase 2 - Cache Key Generation).
/// Stores task outputs (stdout, stderr) and metadata in .zr/cache/<cache_key>/
/// with ISO 8601 timestamps and manifest.json for metadata tracking.
pub const CacheStore = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CacheStore {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CacheStore) void {
        _ = self;
    }

    /// Cache manifest metadata stored in manifest.json
    pub const Manifest = struct {
        timestamp: []const u8, // ISO 8601 format
        task_name: []const u8,
        cache_key: []const u8,
        exit_code: u8,
        duration_ms: u64,
    };

    /// Store task execution result in cache.
    /// Creates .zr/cache/<cache_key>/ directory with:
    /// - manifest.json (metadata)
    /// - stdout (stdout output)
    /// - stderr (stderr output)
    pub fn store(
        self: *CacheStore,
        cache_key: []const u8,
        task_name: []const u8,
        exit_code: u8,
        duration_ms: u64,
        stdout: []const u8,
        stderr: []const u8,
    ) !void {
        // Create cache directory structure: .zr/cache/<cache_key>/
        const cache_dir = try std.fmt.allocPrint(
            self.allocator,
            ".zr/cache/{s}",
            .{cache_key},
        );
        defer self.allocator.free(cache_dir);

        // Ensure parent directories exist
        try std.fs.cwd().makePath(cache_dir);

        // Generate ISO 8601 timestamp
        const timestamp = try self.generateTimestamp();
        defer self.allocator.free(timestamp);

        // Create manifest
        const manifest = Manifest{
            .timestamp = timestamp,
            .task_name = task_name,
            .cache_key = cache_key,
            .exit_code = exit_code,
            .duration_ms = duration_ms,
        };

        // Write manifest.json
        const manifest_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/manifest.json",
            .{cache_dir},
        );
        defer self.allocator.free(manifest_path);

        try self.writeManifest(manifest, manifest_path);

        // Write stdout file
        const stdout_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/stdout",
            .{cache_dir},
        );
        defer self.allocator.free(stdout_path);

        try std.fs.cwd().writeFile(.{
            .sub_path = stdout_path,
            .data = stdout,
        });

        // Write stderr file
        const stderr_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/stderr",
            .{cache_dir},
        );
        defer self.allocator.free(stderr_path);

        try std.fs.cwd().writeFile(.{
            .sub_path = stderr_path,
            .data = stderr,
        });
    }

    /// Retrieve cached entry by cache_key.
    /// Returns null if cache entry doesn't exist.
    pub fn retrieve(self: *CacheStore, cache_key: []const u8) !?CachedEntry {
        const cache_dir = try std.fmt.allocPrint(
            self.allocator,
            ".zr/cache/{s}",
            .{cache_key},
        );
        defer self.allocator.free(cache_dir);

        // Try to open cache directory
        var dir = std.fs.cwd().openDir(cache_dir, .{}) catch {
            return null; // Cache entry doesn't exist
        };
        defer dir.close();

        // Try to read manifest.json
        const manifest = self.readManifest(dir) catch {
            return null; // Corrupted or missing manifest
        };

        // Try to read stdout
        const stdout = dir.readFileAlloc(self.allocator, "stdout", 1024 * 1024) catch |err| {
            if (manifest.task_name) |name| self.allocator.free(name);
            if (manifest.cache_key) |key| self.allocator.free(key);
            if (manifest.timestamp) |ts| self.allocator.free(ts);
            return err;
        };

        // Try to read stderr
        const stderr = dir.readFileAlloc(self.allocator, "stderr", 1024 * 1024) catch |err| {
            self.allocator.free(stdout);
            if (manifest.task_name) |name| self.allocator.free(name);
            if (manifest.cache_key) |key| self.allocator.free(key);
            if (manifest.timestamp) |ts| self.allocator.free(ts);
            return err;
        };

        return CachedEntry{
            .manifest = manifest,
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    /// Invalidate (clear) cache entry for a specific cache_key.
    pub fn invalidate(self: *CacheStore, cache_key: []const u8) !void {
        const cache_dir = try std.fmt.allocPrint(
            self.allocator,
            ".zr/cache/{s}",
            .{cache_key},
        );
        defer self.allocator.free(cache_dir);

        std.fs.cwd().deleteTree(cache_dir) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };
    }

    /// Clear all cache entries (removes entire .zr/cache directory).
    pub fn clearAll(_: *CacheStore) !void {
        std.fs.cwd().deleteTree(".zr/cache") catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };
    }

    // ─── Private helper functions ───

    /// Generate ISO 8601 timestamp (caller owns memory).
    fn generateTimestamp(self: *CacheStore) ![]const u8 {
        const now = std.time.nanoTimestamp();
        const seconds = @divTrunc(now, 1_000_000_000);
        const nanos = @mod(now, 1_000_000_000);

        // Days since Unix epoch (1970-01-01)
        const seconds_u64 = @as(u64, @intCast(if (seconds < 0) 0 else seconds));
        const days_since_epoch = seconds_u64 / (24 * 60 * 60);

        // Compute year, month, day (simplified Gregorian calendar)
        var year: u32 = 1970;
        var days_left: u64 = days_since_epoch;

        while (true) {
            const days_in_year: u64 = if (isLeapYear(year)) 366 else 365;
            if (days_left < days_in_year) break;
            days_left -= days_in_year;
            year += 1;
        }

        const days_in_months = [_]u32{
            if (isLeapYear(year)) 29 else 28, // February
            31, // January (reordered for loop)
            31, // March
            30, // April
            31, // May
            30, // June
            31, // July
            31, // August
            30, // September
            31, // October
            30, // November
            31, // December
        };

        var month: u32 = 1;
        var day: u32 = 1;

        for (days_in_months) |month_days| {
            if (days_left < month_days) {
                day = @as(u32, @intCast(days_left)) + 1;
                break;
            }
            days_left -= month_days;
            month += 1;
        }

        // Compute hour, minute, second
        const secs_in_day = @mod(seconds, 24 * 60 * 60);
        const secs_in_day_u32 = @as(u32, @intCast(secs_in_day));
        const hour = secs_in_day_u32 / 3600;
        const minute = (secs_in_day_u32 % 3600) / 60;
        const second = secs_in_day_u32 % 60;
        const millis_u64 = @as(u64, @intCast(if (nanos < 0) 0 else nanos));
        const millis = @as(u32, @intCast(millis_u64 / 1_000_000));

        return std.fmt.allocPrint(
            self.allocator,
            "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z",
            .{ year, month, day, hour, minute, second, millis },
        );
    }

    fn isLeapYear(year: u32) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }

    /// Write manifest as JSON to manifest.json file.
    fn writeManifest(self: *CacheStore, manifest: Manifest, path: []const u8) !void {
        var json_buf = std.ArrayList(u8){};
        defer json_buf.deinit(self.allocator);

        const writer = json_buf.writer(self.allocator);
        try writer.print("{{", .{});
        try writer.print("\"timestamp\":\"{s}\",", .{manifest.timestamp});
        try writer.print("\"task_name\":\"{s}\",", .{manifest.task_name});
        try writer.print("\"cache_key\":\"{s}\",", .{manifest.cache_key});
        try writer.print("\"exit_code\":{},", .{manifest.exit_code});
        try writer.print("\"duration_ms\":{}", .{manifest.duration_ms});
        try writer.print("}}", .{});

        try std.fs.cwd().writeFile(.{
            .sub_path = path,
            .data = json_buf.items,
        });
    }

    /// Read and parse manifest.json from cache directory.
    /// Caller owns returned Manifest fields.
    fn readManifest(self: *CacheStore, dir: std.fs.Dir) !Manifest {
        const manifest_data = try dir.readFileAlloc(self.allocator, "manifest.json", 8192);
        defer self.allocator.free(manifest_data);

        // Simple JSON parsing (not using std.json due to complexity)
        var manifest = Manifest{
            .timestamp = "",
            .task_name = "",
            .cache_key = "",
            .exit_code = 0,
            .duration_ms = 0,
        };

        // Extract "timestamp" value
        if (self.extractJsonString(manifest_data, "timestamp")) |value| {
            manifest.timestamp = try self.allocator.dupe(u8, value);
        }

        // Extract "task_name" value
        if (self.extractJsonString(manifest_data, "task_name")) |value| {
            manifest.task_name = try self.allocator.dupe(u8, value);
        }

        // Extract "cache_key" value
        if (self.extractJsonString(manifest_data, "cache_key")) |value| {
            manifest.cache_key = try self.allocator.dupe(u8, value);
        }

        // Extract "exit_code" value
        if (self.extractJsonNumber(manifest_data, "exit_code")) |value| {
            manifest.exit_code = @as(u8, @intCast(value));
        }

        // Extract "duration_ms" value
        if (self.extractJsonNumber(manifest_data, "duration_ms")) |value| {
            manifest.duration_ms = @as(u64, @intCast(value));
        }

        return manifest;
    }

    /// Extract a JSON string value by key (simple parser for our use case).
    fn extractJsonString(_: *CacheStore, json: []const u8, key: []const u8) ?[]const u8 {
        // Build search string on stack (max key length ~100)
        var search_buf: [256]u8 = undefined;
        const search = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{key}) catch return null;

        const start_idx = std.mem.indexOf(u8, json, search) orelse return null;
        const value_start = start_idx + search.len;

        // Find closing quote
        var idx = value_start;
        while (idx < json.len) : (idx += 1) {
            if (json[idx] == '"' and (idx == 0 or json[idx - 1] != '\\')) {
                return json[value_start..idx];
            }
        }

        return null;
    }

    /// Extract a JSON number value by key.
    fn extractJsonNumber(_: *CacheStore, json: []const u8, key: []const u8) ?i64 {
        // Build search string on stack
        var search_buf: [256]u8 = undefined;
        const search = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;

        const start_idx = std.mem.indexOf(u8, json, search) orelse return null;
        var idx = start_idx + search.len;

        // Skip whitespace
        while (idx < json.len and (json[idx] == ' ' or json[idx] == '\t')) : (idx += 1) {}

        // Find end of number
        const num_start = idx;
        while (idx < json.len and (std.ascii.isDigit(json[idx]) or json[idx] == '-')) : (idx += 1) {}

        if (idx > num_start) {
            return std.fmt.parseInt(i64, json[num_start..idx], 10) catch null;
        }

        return null;
    }
};

pub const CachedEntry = struct {
    manifest: CacheStore.Manifest,
    stdout: []const u8,
    stderr: []const u8,

    pub fn deinit(self: *CachedEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.manifest.timestamp);
        allocator.free(self.manifest.task_name);
        allocator.free(self.manifest.cache_key);
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

// ─── Tests ───

test "CacheStore: init creates store" {
    const allocator = std.testing.allocator;
    var store = CacheStore.init(allocator);
    defer store.deinit();
}

test "CacheStore: store creates cache directory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const orig_cwd = std.fs.cwd();
    var tmp_dir = try orig_cwd.makeOpenPath(".zr/cache/test", .{});
    defer tmp_dir.close();

    var store = CacheStore.init(allocator);
    defer store.deinit();

    const cache_key = "test_cache_key_12345";
    try store.store(cache_key, "test_task", 0, 100, "stdout data", "stderr data");

    // Verify cache directory was created
    const cache_dir = try std.fmt.allocPrint(allocator, ".zr/cache/{s}", .{cache_key});
    defer allocator.free(cache_dir);

    var dir = try std.fs.cwd().openDir(cache_dir, .{});
    defer dir.close();

    // Cleanup
    try store.invalidate(cache_key);
}
