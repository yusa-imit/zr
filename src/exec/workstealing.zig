const std = @import("std");

/// A work-stealing deque for efficient task distribution.
/// Workers push/pop from the bottom (LIFO for cache locality).
/// Stealers take from the top (FIFO for load balancing).
///
/// Based on the Chase-Lev deque algorithm:
/// https://www.dre.vanderbilt.edu/~schmidt/PDF/work-stealing-dequeue.pdf
pub fn WorkStealingDeque(comptime T: type) type {
    return struct {
        const Self = @This();
        const MIN_CAPACITY = 32;

        items: []T,
        allocator: std.mem.Allocator,
        top: std.atomic.Value(usize), // Stealers pop from top (FIFO)
        bottom: std.atomic.Value(usize), // Owner pushes/pops from bottom (LIFO)
        capacity: usize,
        mutex: std.Thread.Mutex, // Protects resize operations

        pub fn init(allocator: std.mem.Allocator) !Self {
            const items = try allocator.alloc(T, MIN_CAPACITY);
            return Self{
                .items = items,
                .allocator = allocator,
                .top = std.atomic.Value(usize).init(0),
                .bottom = std.atomic.Value(usize).init(0),
                .capacity = MIN_CAPACITY,
                .mutex = std.Thread.Mutex{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        /// Push a task to the bottom of the deque (owner thread only).
        pub fn push(self: *Self, task: T) !void {
            const b = self.bottom.load(.acquire);
            const t = self.top.load(.acquire);
            const size = b -% t;

            // Resize if full (only owner can resize)
            if (size >= self.capacity - 1) {
                self.mutex.lock();
                defer self.mutex.unlock();
                try self.resize();
            }

            self.items[b % self.capacity] = task;
            // Release ensures the task write is visible before bottom increment
            self.bottom.store(b +% 1, .release);
        }

        /// Pop a task from the bottom of the deque (owner thread only).
        /// Returns null if the deque is empty.
        pub fn pop(self: *Self) ?T {
            const b = self.bottom.load(.acquire) -% 1;
            self.bottom.store(b, .release);
            std.atomic.fence(.seq_cst); // Full fence to order with steal operations

            const t = self.top.load(.acquire);

            if (t <= b) {
                // Non-empty deque
                const task = self.items[b % self.capacity];

                if (t == b) {
                    // Last item: race with stealers
                    // Try to claim it atomically
                    if (self.top.cmpxchgStrong(t, t +% 1, .seq_cst, .seq_cst)) |_| {
                        // Lost race to a stealer
                        self.bottom.store(b +% 1, .release);
                        return null;
                    }
                    // Won the race
                    self.bottom.store(b +% 1, .release);
                    return task;
                }

                // Multiple items left
                return task;
            } else {
                // Empty deque
                self.bottom.store(b +% 1, .release);
                return null;
            }
        }

        /// Steal a task from the top of the deque (other threads).
        /// Returns null if the deque is empty or if we lose a race with the owner or other stealers.
        pub fn steal(self: *Self) ?T {
            const t = self.top.load(.acquire);
            std.atomic.fence(.seq_cst); // Full fence to order with pop operations
            const b = self.bottom.load(.acquire);

            if (t < b) {
                // Non-empty deque
                const task = self.items[t % self.capacity];

                // Try to claim this task atomically
                if (self.top.cmpxchgStrong(t, t +% 1, .seq_cst, .seq_cst)) |_| {
                    // Lost race to another stealer or the owner
                    return null;
                }

                // Successfully stolen
                return task;
            }

            // Empty deque
            return null;
        }

        /// Returns the approximate size of the deque.
        /// This is a snapshot and may not be accurate due to concurrent modifications.
        pub fn size(self: *Self) usize {
            const b = self.bottom.load(.acquire);
            const t = self.top.load(.acquire);
            return b -% t;
        }

        /// Resize the deque to double its capacity (owner thread only, must hold mutex).
        fn resize(self: *Self) !void {
            const new_capacity = self.capacity * 2;
            const new_items = try self.allocator.alloc(T, new_capacity);

            const t = self.top.load(.acquire);
            const b = self.bottom.load(.acquire);

            // Copy existing items to new array
            var i: usize = 0;
            var idx = t;
            while (idx < b) : (idx +%= 1) {
                new_items[i] = self.items[idx % self.capacity];
                i += 1;
            }

            self.allocator.free(self.items);
            self.items = new_items;
            self.capacity = new_capacity;

            // Reset indices to avoid wraparound issues
            self.top.store(0, .release);
            self.bottom.store(i, .release);
        }
    };
}

test "WorkStealingDeque: basic push/pop" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    try deque.push(1);
    try deque.push(2);
    try deque.push(3);

    try testing.expectEqual(@as(?u32, 3), deque.pop());
    try testing.expectEqual(@as(?u32, 2), deque.pop());
    try testing.expectEqual(@as(?u32, 1), deque.pop());
    try testing.expectEqual(@as(?u32, null), deque.pop());
}

test "WorkStealingDeque: steal" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    try deque.push(10);
    try deque.push(20);
    try deque.push(30);

    // Steal from the top (FIFO order)
    try testing.expectEqual(@as(?u32, 10), deque.steal());
    try testing.expectEqual(@as(?u32, 20), deque.steal());

    // Pop from bottom (LIFO order)
    try testing.expectEqual(@as(?u32, 30), deque.pop());
    try testing.expectEqual(@as(?u32, null), deque.steal());
}

test "WorkStealingDeque: resize" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Push more than MIN_CAPACITY items to trigger resize
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try deque.push(i);
    }

    // Verify all items are intact after resize
    var expected: u32 = 99;
    while (expected > 0) : (expected -= 1) {
        const item = deque.pop();
        try testing.expectEqual(@as(?u32, expected), item);
    }
}

test "WorkStealingDeque: concurrent push/steal" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Push items from owner thread
    const num_items = 1000;
    var i: u32 = 0;
    while (i < num_items) : (i += 1) {
        try deque.push(i);
    }

    // Spawn a thief thread to steal items
    const ThiefCtx = struct {
        deque_ptr: *WorkStealingDeque(u32),
        stolen_count: *std.atomic.Value(u32),
    };

    var stolen_count = std.atomic.Value(u32).init(0);
    const thief_ctx = ThiefCtx{
        .deque_ptr = &deque,
        .stolen_count = &stolen_count,
    };

    const thief_fn = struct {
        fn run(ctx: ThiefCtx) void {
            var count: u32 = 0;
            while (ctx.deque_ptr.steal()) |_| {
                count += 1;
            }
            ctx.stolen_count.store(count, .release);
        }
    }.run;

    const thread = try std.Thread.spawn(.{}, thief_fn, .{thief_ctx});
    thread.join();

    // Pop remaining items from owner thread
    var popped_count: u32 = 0;
    while (deque.pop()) |_| {
        popped_count += 1;
    }

    const total = stolen_count.load(.acquire) + popped_count;
    try testing.expectEqual(num_items, total);
}
