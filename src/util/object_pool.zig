const std = @import("std");

/// ObjectPool provides reusable object allocation to reduce memory churn.
/// Objects are recycled instead of being freed and reallocated.
pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        /// Available objects ready for reuse
        pool: std.ArrayList(*T),
        /// All allocated objects (for cleanup)
        all: std.ArrayList(*T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .pool = std.ArrayList(*T).init(allocator),
                .all = std.ArrayList(*T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // Free all allocated objects
            for (self.all.items) |obj| {
                self.allocator.destroy(obj);
            }
            self.pool.deinit();
            self.all.deinit();
        }

        /// Acquire an object from the pool or allocate a new one.
        /// Caller must call release() when done to return it to the pool.
        pub fn acquire(self: *Self) !*T {
            if (self.pool.items.len > 0) {
                return self.pool.pop();
            }

            // Allocate new object
            const obj = try self.allocator.create(T);
            try self.all.append(obj);
            return obj;
        }

        /// Return an object to the pool for reuse.
        /// The object should not be accessed after calling this.
        pub fn release(self: *Self, obj: *T) !void {
            try self.pool.append(obj);
        }

        /// Returns the number of objects currently available in the pool.
        pub fn available(self: *const Self) usize {
            return self.pool.items.len;
        }

        /// Returns the total number of allocated objects.
        pub fn total(self: *const Self) usize {
            return self.all.items.len;
        }
    };
}

test "ObjectPool basic acquire and release" {
    const TestStruct = struct {
        value: u32,
    };

    var pool = ObjectPool(TestStruct).init(std.testing.allocator);
    defer pool.deinit();

    const obj1 = try pool.acquire();
    obj1.value = 42;
    try std.testing.expectEqual(@as(u32, 42), obj1.value);
    try std.testing.expectEqual(@as(usize, 0), pool.available());
    try std.testing.expectEqual(@as(usize, 1), pool.total());

    try pool.release(obj1);
    try std.testing.expectEqual(@as(usize, 1), pool.available());

    const obj2 = try pool.acquire();
    try std.testing.expectEqual(obj1, obj2); // Same pointer reused
    try std.testing.expectEqual(@as(usize, 0), pool.available());
}

test "ObjectPool multiple objects" {
    const TestStruct = struct {
        id: u32,
        name: [32]u8,
    };

    var pool = ObjectPool(TestStruct).init(std.testing.allocator);
    defer pool.deinit();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();

    obj1.id = 1;
    obj2.id = 2;
    obj3.id = 3;

    try std.testing.expectEqual(@as(usize, 3), pool.total());
    try std.testing.expectEqual(@as(usize, 0), pool.available());

    try pool.release(obj1);
    try pool.release(obj2);

    try std.testing.expectEqual(@as(usize, 2), pool.available());

    const obj4 = try pool.acquire();
    try std.testing.expectEqual(obj2, obj4); // LIFO reuse
}

test "ObjectPool deinit cleanup" {
    const TestStruct = struct {
        data: [64]u8,
    };

    var pool = ObjectPool(TestStruct).init(std.testing.allocator);

    _ = try pool.acquire();
    _ = try pool.acquire();
    _ = try pool.acquire();

    try std.testing.expectEqual(@as(usize, 3), pool.total());

    // deinit should free all objects without memory leaks
    pool.deinit();
}
