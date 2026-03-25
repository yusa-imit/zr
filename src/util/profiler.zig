const std = @import("std");

/// Performance profiler for tracking function execution time and frequency
pub const Profiler = struct {
    allocator: std.mem.Allocator,
    samples: std.ArrayListUnmanaged(Sample),
    enabled: bool,

    pub const Sample = struct {
        name: []const u8,
        duration_ns: u64,
        timestamp_ms: i64,
    };

    pub fn init(allocator: std.mem.Allocator) Profiler {
        return Profiler{
            .allocator = allocator,
            .samples = .{},
            .enabled = true,
        };
    }

    pub fn deinit(self: *Profiler) void {
        for (self.samples.items) |sample| {
            self.allocator.free(sample.name);
        }
        self.samples.deinit(self.allocator);
    }

    /// Record a sample with the given name and duration
    pub fn record(self: *Profiler, name: []const u8, duration_ns: u64) !void {
        if (!self.enabled) return;

        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);

        const sample = Sample{
            .name = name_owned,
            .duration_ns = duration_ns,
            .timestamp_ms = std.time.milliTimestamp(),
        };

        try self.samples.append(self.allocator, sample);
    }

    /// Get statistics for a specific operation name
    pub fn getStats(self: *const Profiler, name: []const u8) ?Stats {
        var count: usize = 0;
        var total_ns: u64 = 0;
        var min_ns: u64 = std.math.maxInt(u64);
        var max_ns: u64 = 0;

        for (self.samples.items) |sample| {
            if (std.mem.eql(u8, sample.name, name)) {
                count += 1;
                total_ns += sample.duration_ns;
                if (sample.duration_ns < min_ns) min_ns = sample.duration_ns;
                if (sample.duration_ns > max_ns) max_ns = sample.duration_ns;
            }
        }

        if (count == 0) return null;

        return Stats{
            .count = count,
            .total_ns = total_ns,
            .avg_ns = total_ns / count,
            .min_ns = min_ns,
            .max_ns = max_ns,
        };
    }

    /// Get all unique operation names
    pub fn getOperationNames(self: *const Profiler, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.StringHashMap(void).init(allocator);
        defer names.deinit();

        for (self.samples.items) |sample| {
            try names.put(sample.name, {});
        }

        var result = try allocator.alloc([]const u8, names.count());
        var iter = names.keyIterator();
        var i: usize = 0;
        while (iter.next()) |key| : (i += 1) {
            result[i] = try allocator.dupe(u8, key.*);
        }

        return result;
    }

    /// Clear all recorded samples
    pub fn clear(self: *Profiler) void {
        for (self.samples.items) |sample| {
            self.allocator.free(sample.name);
        }
        self.samples.clearRetainingCapacity();
    }

    /// Enable profiling
    pub fn enable(self: *Profiler) void {
        self.enabled = true;
    }

    /// Disable profiling
    pub fn disable(self: *Profiler) void {
        self.enabled = false;
    }
};

pub const Stats = struct {
    count: usize,
    total_ns: u64,
    avg_ns: u64,
    min_ns: u64,
    max_ns: u64,

    /// Format stats as human-readable string
    pub fn format(
        self: Stats,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const avg_us = self.avg_ns / 1000;
        const min_us = self.min_ns / 1000;
        const max_us = self.max_ns / 1000;

        try writer.print("count={d}, avg={d}µs, min={d}µs, max={d}µs", .{
            self.count,
            avg_us,
            min_us,
            max_us,
        });
    }
};

/// Scoped timer for automatic duration tracking
pub const Timer = struct {
    profiler: *Profiler,
    name: []const u8,
    start_ns: u64,

    pub fn start(profiler: *Profiler, name: []const u8) Timer {
        return Timer{
            .profiler = profiler,
            .name = name,
            .start_ns = @intCast(std.time.nanoTimestamp()),
        };
    }

    pub fn stop(self: *Timer) !void {
        const end_ns: u64 = @intCast(std.time.nanoTimestamp());
        const duration_ns = end_ns - self.start_ns;
        try self.profiler.record(self.name, duration_ns);
    }
};

test "Profiler: init and deinit" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try std.testing.expect(profiler.enabled);
    try std.testing.expectEqual(@as(usize, 0), profiler.samples.items.len);
}

test "Profiler: record sample" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.record("test_op", 1000);

    try std.testing.expectEqual(@as(usize, 1), profiler.samples.items.len);
    try std.testing.expectEqualStrings("test_op", profiler.samples.items[0].name);
    try std.testing.expectEqual(@as(u64, 1000), profiler.samples.items[0].duration_ns);
}

test "Profiler: getStats" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.record("test_op", 1000);
    try profiler.record("test_op", 2000);
    try profiler.record("test_op", 3000);

    const stats = profiler.getStats("test_op").?;

    try std.testing.expectEqual(@as(usize, 3), stats.count);
    try std.testing.expectEqual(@as(u64, 6000), stats.total_ns);
    try std.testing.expectEqual(@as(u64, 2000), stats.avg_ns);
    try std.testing.expectEqual(@as(u64, 1000), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 3000), stats.max_ns);
}

test "Profiler: getStats for non-existent operation" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    const stats = profiler.getStats("nonexistent");
    try std.testing.expect(stats == null);
}

test "Profiler: multiple operations" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.record("op1", 1000);
    try profiler.record("op2", 2000);
    try profiler.record("op1", 3000);

    const stats1 = profiler.getStats("op1").?;
    const stats2 = profiler.getStats("op2").?;

    try std.testing.expectEqual(@as(usize, 2), stats1.count);
    try std.testing.expectEqual(@as(usize, 1), stats2.count);
    try std.testing.expectEqual(@as(u64, 2000), stats1.avg_ns);
    try std.testing.expectEqual(@as(u64, 2000), stats2.avg_ns);
}

test "Profiler: clear samples" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.record("test_op", 1000);
    try std.testing.expectEqual(@as(usize, 1), profiler.samples.items.len);

    profiler.clear();
    try std.testing.expectEqual(@as(usize, 0), profiler.samples.items.len);
}

test "Profiler: enable/disable" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    profiler.disable();
    try profiler.record("test_op", 1000);
    try std.testing.expectEqual(@as(usize, 0), profiler.samples.items.len);

    profiler.enable();
    try profiler.record("test_op", 1000);
    try std.testing.expectEqual(@as(usize, 1), profiler.samples.items.len);
}

test "Timer: scoped timing" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    {
        var timer = Timer.start(&profiler, "test_op");
        // Do some work (busy loop for a short time)
        var i: u64 = 0;
        while (i < 10000) : (i += 1) {
            std.mem.doNotOptimizeAway(&i);
        }
        try timer.stop();
    }

    try std.testing.expectEqual(@as(usize, 1), profiler.samples.items.len);
    const sample = profiler.samples.items[0];
    try std.testing.expectEqualStrings("test_op", sample.name);
    // Duration should be > 0
    try std.testing.expect(sample.duration_ns > 0);
}

test "Profiler: getOperationNames" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.record("op1", 1000);
    try profiler.record("op2", 2000);
    try profiler.record("op1", 3000);

    const names = try profiler.getOperationNames(allocator);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    try std.testing.expectEqual(@as(usize, 2), names.len);

    // Check both names are present (order not guaranteed)
    var found_op1 = false;
    var found_op2 = false;
    for (names) |name| {
        if (std.mem.eql(u8, name, "op1")) found_op1 = true;
        if (std.mem.eql(u8, name, "op2")) found_op2 = true;
    }
    try std.testing.expect(found_op1);
    try std.testing.expect(found_op2);
}

test "Stats: format" {
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const stats = Stats{
        .count = 5,
        .total_ns = 10_000_000,
        .avg_ns = 2_000_000,
        .min_ns = 1_000_000,
        .max_ns = 3_000_000,
    };

    // Use custom formatter
    try stats.format("", .{}, writer);

    const expected = "count=5, avg=2000µs, min=1000µs, max=3000µs";
    const actual = fbs.getWritten();
    try std.testing.expectEqualStrings(expected, actual);
}
