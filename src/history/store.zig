const std = @import("std");

/// A single execution history record.
pub const Record = struct {
    /// Unix timestamp (seconds since epoch) of when the run started.
    timestamp: i64,
    /// Name of the task that was requested (not necessarily all deps).
    task_name: []const u8,
    /// Whether all tasks in the run succeeded.
    success: bool,
    /// Total wall-clock duration in milliseconds.
    duration_ms: u64,
    /// Number of tasks that ran (including deps).
    task_count: u32,
    /// Total number of retry attempts across all tasks (0 if all succeeded on first try).
    retry_count: u32,

    pub fn deinit(self: Record, allocator: std.mem.Allocator) void {
        allocator.free(self.task_name);
    }
};

/// History store backed by a line-delimited text file.
/// Each line: `<timestamp>\t<task_name>\t<ok|fail>\t<duration_ms>\t<task_count>\t<retry_count>`
pub const Store = struct {
    path: []const u8, // owned
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Store {
        return Store{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: Store) void {
        self.allocator.free(self.path);
    }

    /// Append a record to the history file. Creates the file if it doesn't exist.
    pub fn append(self: *const Store, record: Record) !void {
        const file = std.fs.cwd().openFile(self.path, .{ .mode = .read_write }) catch |err| blk: {
            if (err == error.FileNotFound) {
                break :blk try std.fs.cwd().createFile(self.path, .{});
            }
            return err;
        };
        defer file.close();

        // Seek to end for appending
        try file.seekFromEnd(0);

        var line_buf: [1024]u8 = undefined;
        const status = if (record.success) "ok" else "fail";
        const line = try std.fmt.bufPrint(&line_buf, "{d}\t{s}\t{s}\t{d}\t{d}\t{d}\n", .{
            record.timestamp,
            record.task_name,
            status,
            record.duration_ms,
            record.task_count,
            record.retry_count,
        });
        try file.writeAll(line);
    }

    /// Load the last `limit` records from the history file.
    /// Returns an owned ArrayList; caller must deinit each Record and the list.
    pub fn loadLast(self: *const Store, allocator: std.mem.Allocator, limit: usize) !std.ArrayList(Record) {
        var records = std.ArrayList(Record){};
        errdefer {
            for (records.items) |r| r.deinit(allocator);
            records.deinit(allocator);
        }

        const content = std.fs.cwd().readFileAlloc(allocator, self.path, 1024 * 1024) catch |err| {
            if (err == error.FileNotFound) return records;
            return err;
        };
        defer allocator.free(content);

        // Parse all lines and collect the last `limit`
        var line_it = std.mem.splitScalar(u8, content, '\n');
        // Collect all valid records first (may be more than limit)
        var all = std.ArrayList(Record){};
        defer {
            // Only free the ones NOT transferred to `records`
            // (we transfer all, then trim below)
            for (all.items) |r| r.deinit(allocator);
            all.deinit(allocator);
        }

        while (line_it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            const record = parseLine(allocator, trimmed) catch continue;
            try all.append(allocator, record);
        }

        // Take the last `limit` records
        const start = if (all.items.len > limit) all.items.len - limit else 0;
        const slice = all.items[start..];

        for (slice) |r| {
            // Dupe task_name so it's independent of `all`'s memory
            const owned = Record{
                .timestamp = r.timestamp,
                .task_name = try allocator.dupe(u8, r.task_name),
                .success = r.success,
                .duration_ms = r.duration_ms,
                .task_count = r.task_count,
                .retry_count = r.retry_count,
            };
            try records.append(allocator, owned);
        }

        // all.items will be freed by errdefer/defer above (they still own their copies)
        return records;
    }
};

/// Parse a single history line.
fn parseLine(allocator: std.mem.Allocator, line: []const u8) !Record {
    var it = std.mem.splitScalar(u8, line, '\t');

    const ts_str = it.next() orelse return error.InvalidFormat;
    const name_str = it.next() orelse return error.InvalidFormat;
    const status_str = it.next() orelse return error.InvalidFormat;
    const dur_str = it.next() orelse return error.InvalidFormat;
    const count_str = it.next() orelse return error.InvalidFormat;
    const retry_str = it.next(); // Optional for backward compatibility

    const timestamp = std.fmt.parseInt(i64, ts_str, 10) catch return error.InvalidFormat;
    const duration_ms = std.fmt.parseInt(u64, dur_str, 10) catch return error.InvalidFormat;
    const task_count = std.fmt.parseInt(u32, count_str, 10) catch return error.InvalidFormat;
    const retry_count = if (retry_str) |s| std.fmt.parseInt(u32, s, 10) catch 0 else 0;
    const success = std.mem.eql(u8, status_str, "ok");

    return Record{
        .timestamp = timestamp,
        .task_name = try allocator.dupe(u8, name_str),
        .success = success,
        .duration_ms = duration_ms,
        .task_count = task_count,
        .retry_count = retry_count,
    };
}

/// Return the default history file path in the user's home directory.
/// Returns an owned slice; caller must free.
pub fn defaultHistoryPath(allocator: std.mem.Allocator) ![]const u8 {
    // Use .zr_history in the current working directory for simplicity.
    // A future version can use $HOME/.zr/history.
    return allocator.dupe(u8, ".zr_history");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "parseLine: valid line with retry_count" {
    const allocator = std.testing.allocator;
    const line = "1700000000\tbuild\tok\t1234\t3\t2";
    const record = try parseLine(allocator, line);
    defer record.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 1700000000), record.timestamp);
    try std.testing.expectEqualStrings("build", record.task_name);
    try std.testing.expect(record.success);
    try std.testing.expectEqual(@as(u64, 1234), record.duration_ms);
    try std.testing.expectEqual(@as(u32, 3), record.task_count);
    try std.testing.expectEqual(@as(u32, 2), record.retry_count);
}

test "parseLine: backward compatibility (no retry_count)" {
    const allocator = std.testing.allocator;
    const line = "1700000000\tbuild\tok\t1234\t3";
    const record = try parseLine(allocator, line);
    defer record.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 1700000000), record.timestamp);
    try std.testing.expectEqualStrings("build", record.task_name);
    try std.testing.expect(record.success);
    try std.testing.expectEqual(@as(u64, 1234), record.duration_ms);
    try std.testing.expectEqual(@as(u32, 3), record.task_count);
    try std.testing.expectEqual(@as(u32, 0), record.retry_count); // defaults to 0
}

test "parseLine: fail status" {
    const allocator = std.testing.allocator;
    const line = "1700000001\ttest\tfail\t500\t1\t0";
    const record = try parseLine(allocator, line);
    defer record.deinit(allocator);

    try std.testing.expect(!record.success);
    try std.testing.expectEqual(@as(u32, 0), record.retry_count);
}

test "parseLine: invalid format returns error" {
    const allocator = std.testing.allocator;
    const result = parseLine(allocator, "not-a-valid-line");
    try std.testing.expectError(error.InvalidFormat, result);
}

test "Store: append and loadLast round-trip" {
    const allocator = std.testing.allocator;

    // Use a temp file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const hist_path = try std.fmt.allocPrint(allocator, "{s}/test_history.log", .{tmp_path});
    defer allocator.free(hist_path);

    var store = try Store.init(allocator, hist_path);
    defer store.deinit();

    // Append two records
    const r1 = Record{
        .timestamp = 1000,
        .task_name = "build",
        .success = true,
        .duration_ms = 200,
        .task_count = 2,
        .retry_count = 1,
    };
    const r2 = Record{
        .timestamp = 2000,
        .task_name = "test",
        .success = false,
        .duration_ms = 50,
        .task_count = 1,
        .retry_count = 3,
    };

    try store.append(r1);
    try store.append(r2);

    // Load last 2
    var loaded = try store.loadLast(allocator, 2);
    defer {
        for (loaded.items) |r| r.deinit(allocator);
        loaded.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), loaded.items.len);
    try std.testing.expectEqualStrings("build", loaded.items[0].task_name);
    try std.testing.expect(loaded.items[0].success);
    try std.testing.expectEqualStrings("test", loaded.items[1].task_name);
    try std.testing.expect(!loaded.items[1].success);
}

test "Store: loadLast with limit smaller than total" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const hist_path = try std.fmt.allocPrint(allocator, "{s}/test_history2.log", .{tmp_path});
    defer allocator.free(hist_path);

    var store = try Store.init(allocator, hist_path);
    defer store.deinit();

    // Append 5 records
    var i: i64 = 0;
    while (i < 5) : (i += 1) {
        try store.append(Record{
            .timestamp = i * 100,
            .task_name = "task",
            .success = true,
            .duration_ms = 10,
            .task_count = 1,
            .retry_count = 0,
        });
    }

    // Load only last 3
    var loaded = try store.loadLast(allocator, 3);
    defer {
        for (loaded.items) |r| r.deinit(allocator);
        loaded.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), loaded.items.len);
    // The last 3 have timestamps 200, 300, 400
    try std.testing.expectEqual(@as(i64, 200), loaded.items[0].timestamp);
    try std.testing.expectEqual(@as(i64, 400), loaded.items[2].timestamp);
}

test "Store: loadLast on missing file returns empty list" {
    const allocator = std.testing.allocator;

    var store = try Store.init(allocator, "/tmp/zr_test_nonexistent_history_12345.log");
    defer store.deinit();

    var loaded = try store.loadLast(allocator, 10);
    defer loaded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), loaded.items.len);
}
