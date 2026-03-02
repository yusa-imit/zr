const std = @import("std");

/// StringPool provides string interning to reduce memory allocations
/// for duplicate strings (common in TOML parsing with repeated keys).
pub const StringPool = struct {
    allocator: std.mem.Allocator,
    /// Maps string content to owned interned string
    pool: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) StringPool {
        return .{
            .allocator = allocator,
            .pool = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *StringPool) void {
        var it = self.pool.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.pool.deinit();
    }

    /// Intern a string. Returns a deduplicated copy.
    /// If the string was previously interned, returns the existing allocation.
    /// Otherwise, allocates and stores a new copy.
    pub fn intern(self: *StringPool, str: []const u8) ![]const u8 {
        if (self.pool.get(str)) |existing| {
            return existing;
        }

        const duped = try self.allocator.dupe(u8, str);
        try self.pool.put(duped, duped);
        return duped;
    }

    /// Get an interned string if it exists, without allocating.
    /// Returns null if the string hasn't been interned yet.
    pub fn get(self: *const StringPool, str: []const u8) ?[]const u8 {
        return self.pool.get(str);
    }

    /// Returns the number of unique strings in the pool.
    pub fn count(self: *const StringPool) usize {
        return self.pool.count();
    }
};

test "StringPool basic interning" {
    var pool = StringPool.init(std.testing.allocator);
    defer pool.deinit();

    const s1 = try pool.intern("hello");
    const s2 = try pool.intern("hello");
    const s3 = try pool.intern("world");

    // Same string should return same pointer
    try std.testing.expectEqual(s1.ptr, s2.ptr);
    try std.testing.expect(s1.ptr != s3.ptr);
    try std.testing.expectEqual(@as(usize, 2), pool.count());
}

test "StringPool memory efficiency" {
    var pool = StringPool.init(std.testing.allocator);
    defer pool.deinit();

    // Simulate repeated TOML keys
    const keys = [_][]const u8{ "cmd", "deps", "env", "cmd", "deps", "cmd" };

    var interned = std.ArrayList([]const u8).init(std.testing.allocator);
    defer interned.deinit();

    for (keys) |key| {
        try interned.append(try pool.intern(key));
    }

    // Only 3 unique strings despite 6 calls
    try std.testing.expectEqual(@as(usize, 3), pool.count());

    // All "cmd" refs point to same allocation
    try std.testing.expectEqual(interned.items[0].ptr, interned.items[3].ptr);
    try std.testing.expectEqual(interned.items[0].ptr, interned.items[5].ptr);
}

test "StringPool get without allocation" {
    var pool = StringPool.init(std.testing.allocator);
    defer pool.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), pool.get("missing"));

    const interned = try pool.intern("exists");
    const retrieved = pool.get("exists");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(interned.ptr, retrieved.?.ptr);
}
