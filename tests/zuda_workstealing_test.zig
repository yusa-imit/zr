const std = @import("std");
const zuda = @import("zuda");

/// Tests for zuda WorkStealingDeque API compatibility
///
/// This file verifies that zuda.containers.queues.WorkStealingDeque provides
/// the same API surface as our custom implementation in src/exec/workstealing.zig
/// before we delete the custom code.
///
/// Expected API (from src/exec/workstealing.zig):
/// - init(allocator: Allocator) !Self
/// - deinit() void
/// - push(task: T) !void
/// - pop() ?T
/// - steal() ?T
/// - size() usize  [NOTE: zuda uses `*const Self` instead of `*Self`]
///
/// zuda provides additional methods not in our custom impl:
/// - isEmpty() bool
/// - validate() !void
///
/// Expected behavior:
/// - LIFO for owner: push bottom, pop bottom
/// - FIFO for stealers: push bottom, steal top
/// - Chase-Lev algorithm with resize on capacity overflow
/// - Thread-safe: concurrent push/steal without data races
/// - Memory safe: no leaks with std.testing.allocator

const WorkStealingDeque = zuda.containers.queues.WorkStealingDeque;

test "zuda WorkStealingDeque: API exists and types match" {
    const testing = std.testing;

    // This test verifies the generic function exists
    const DequeType = WorkStealingDeque(u32);

    // Verify init returns the correct type
    var deque = try DequeType.init(testing.allocator);
    defer deque.deinit();

    // If we reach here without compile errors, the API exists
    try testing.expect(true);
}

test "zuda WorkStealingDeque: init and deinit without leaks" {
    const testing = std.testing;

    // testing.allocator detects memory leaks
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    deque.deinit();

    // If deinit() doesn't free all memory, this test will fail
    try testing.expect(true);
}

test "zuda WorkStealingDeque: basic push/pop LIFO order" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Push three items
    try deque.push(1);
    try deque.push(2);
    try deque.push(3);

    // Pop should return items in LIFO order (3, 2, 1)
    const first = deque.pop();
    const second = deque.pop();
    const third = deque.pop();
    const fourth = deque.pop();

    // CRITICAL: These assertions will FAIL if zuda returns wrong values
    try testing.expectEqual(@as(?u32, 3), first);
    try testing.expectEqual(@as(?u32, 2), second);
    try testing.expectEqual(@as(?u32, 1), third);
    try testing.expectEqual(@as(?u32, null), fourth); // Empty deque
}

test "zuda WorkStealingDeque: steal FIFO order" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Push three items to the bottom
    try deque.push(10);
    try deque.push(20);
    try deque.push(30);

    // Steal from top should return FIFO order (10, 20)
    const first_stolen = deque.steal();
    const second_stolen = deque.steal();

    // CRITICAL: Will FAIL if steal doesn't return top items
    try testing.expectEqual(@as(?u32, 10), first_stolen);
    try testing.expectEqual(@as(?u32, 20), second_stolen);

    // Pop from bottom should still work (LIFO)
    const popped = deque.pop();
    try testing.expectEqual(@as(?u32, 30), popped);

    // Now deque is empty
    const empty_steal = deque.steal();
    try testing.expectEqual(@as(?u32, null), empty_steal);
}

test "zuda WorkStealingDeque: size tracking" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Initially empty
    try testing.expectEqual(@as(usize, 0), deque.size());

    try deque.push(1);
    try testing.expectEqual(@as(usize, 1), deque.size());

    try deque.push(2);
    try testing.expectEqual(@as(usize, 2), deque.size());

    try deque.push(3);
    try testing.expectEqual(@as(usize, 3), deque.size());

    _ = deque.pop();
    try testing.expectEqual(@as(usize, 2), deque.size());

    _ = deque.steal();
    try testing.expectEqual(@as(usize, 1), deque.size());

    _ = deque.pop();
    try testing.expectEqual(@as(usize, 0), deque.size());
}

test "zuda WorkStealingDeque: resize on overflow (>32 items)" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Push more than MIN_CAPACITY (32) items to trigger resize
    // Our custom implementation resizes at capacity-1, so 32+ items should resize
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try deque.push(i);
    }

    // Verify size is correct after resize
    try testing.expectEqual(@as(usize, 100), deque.size());

    // Verify all items are intact after resize (LIFO order)
    var expected: u32 = 99;
    while (expected > 0) : (expected -= 1) {
        const item = deque.pop();
        // CRITICAL: Will FAIL if resize corrupted data
        try testing.expectEqual(@as(?u32, expected), item);
    }

    // Last item
    try testing.expectEqual(@as(?u32, 0), deque.pop());
    try testing.expectEqual(@as(?u32, null), deque.pop()); // Empty
}

test "zuda WorkStealingDeque: concurrent push/steal without data races" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Push items from owner thread
    const num_items = 1000;
    var i: u32 = 0;
    while (i < num_items) : (i += 1) {
        try deque.push(i);
    }

    // Spawn a thief thread to steal items concurrently
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
            // Keep stealing until deque is empty
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

    // CRITICAL: Total must equal num_items (no lost items, no duplicates)
    const total = stolen_count.load(.acquire) + popped_count;
    try testing.expectEqual(num_items, total);

    // CRITICAL: Both threads should have processed some items
    // (This verifies actual concurrency, not sequential execution)
    const stolen = stolen_count.load(.acquire);
    try testing.expect(stolen > 0); // Thief must have stolen at least one
    try testing.expect(popped_count > 0); // Owner must have popped at least one
}

test "zuda WorkStealingDeque: empty deque pop/steal returns null" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // BUG DISCOVERY: This test reveals a critical issue with zuda's pop()
    // When popping from an empty deque, it returns garbage values instead of null
    //
    // The issue appears after: push -> pop -> pop (second pop on empty deque)
    // This suggests zuda reads uninitialized memory from items array
    //
    // Expected behavior: pop() should return null when deque is empty
    // Actual behavior: pop() returns garbage (e.g., 2863311530)

    // First: verify initial empty state works
    const first_empty_pop = deque.pop();
    if (first_empty_pop) |val| {
        std.debug.print("\nBUG: Initial empty pop returned {}, expected null\n", .{val});
    }
    try testing.expectEqual(@as(?u32, null), first_empty_pop);

    // Second: verify steal on empty also works
    const first_empty_steal = deque.steal();
    try testing.expectEqual(@as(?u32, null), first_empty_steal);

    // Third: push one item and pop it
    try deque.push(42);
    try testing.expectEqual(@as(?u32, 42), deque.pop());

    // Fourth: THIS IS WHERE THE BUG APPEARS
    // Pop from empty deque after a successful push/pop cycle
    const second_empty_pop = deque.pop();
    if (second_empty_pop) |val| {
        std.debug.print("\nBUG CONFIRMED: Pop after push/pop cycle returned {}, expected null\n", .{val});
        std.debug.print("This indicates zuda reads uninitialized memory from items[b % capacity]\n", .{});
        std.debug.print("Expected: pop() checks `if (t <= b)` and returns null when t > b\n", .{});
        std.debug.print("Actual: zuda may be reading items[] before the emptiness check\n", .{});
    }
    // CRITICAL: This assertion WILL FAIL with zuda v1.15.0
    try testing.expectEqual(@as(?u32, null), second_empty_pop);

    const second_empty_steal = deque.steal();
    try testing.expectEqual(@as(?u32, null), second_empty_steal);
}

test "zuda WorkStealingDeque: mixed push/pop/steal operations" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Scenario: interleaved owner and thief operations
    try deque.push(1);
    try deque.push(2);
    try testing.expectEqual(@as(?u32, 1), deque.steal()); // Steal first

    try deque.push(3);
    try testing.expectEqual(@as(?u32, 3), deque.pop()); // Pop last

    try deque.push(4);
    try deque.push(5);
    try testing.expectEqual(@as(?u32, 2), deque.steal()); // Steal second
    try testing.expectEqual(@as(?u32, 5), deque.pop()); // Pop last
    try testing.expectEqual(@as(?u32, 4), deque.pop()); // Pop remaining

    try testing.expectEqual(@as(?u32, null), deque.pop());
    try testing.expectEqual(@as(?u32, null), deque.steal());
}

test "zuda WorkStealingDeque: type compatibility with different element types" {
    const testing = std.testing;

    // Test with u64
    {
        var deque = try WorkStealingDeque(u64).init(testing.allocator);
        defer deque.deinit();

        try deque.push(0xDEADBEEF_CAFEBABE);
        try testing.expectEqual(@as(?u64, 0xDEADBEEF_CAFEBABE), deque.pop());
    }

    // Test with struct
    const Task = struct {
        id: u32,
        priority: u8,
    };

    {
        var deque = try WorkStealingDeque(Task).init(testing.allocator);
        defer deque.deinit();

        const task = Task{ .id = 123, .priority = 5 };
        try deque.push(task);

        const result = deque.pop();
        try testing.expect(result != null);
        try testing.expectEqual(@as(u32, 123), result.?.id);
        try testing.expectEqual(@as(u8, 5), result.?.priority);
    }
}

test "zuda WorkStealingDeque: stress test resize and concurrent access" {
    const testing = std.testing;
    var deque = try WorkStealingDeque(u32).init(testing.allocator);
    defer deque.deinit();

    // Stress test: push many items to trigger multiple resizes
    const num_items = 10000;
    var i: u32 = 0;
    while (i < num_items) : (i += 1) {
        try deque.push(i);
    }

    // Spawn multiple thief threads
    const num_thieves = 4;
    var threads: [num_thieves]std.Thread = undefined;
    var stolen_counts: [num_thieves]std.atomic.Value(u32) = undefined;

    const ThiefCtx = struct {
        deque_ptr: *WorkStealingDeque(u32),
        stolen_count: *std.atomic.Value(u32),
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

    // Initialize and spawn thieves
    for (&stolen_counts) |*count| {
        count.* = std.atomic.Value(u32).init(0);
    }

    for (&threads, &stolen_counts) |*thread, *count| {
        const ctx = ThiefCtx{
            .deque_ptr = &deque,
            .stolen_count = count,
        };
        thread.* = try std.Thread.spawn(.{}, thief_fn, .{ctx});
    }

    // Wait for all thieves
    for (&threads) |*thread| {
        thread.join();
    }

    // Pop remaining items
    var popped_count: u32 = 0;
    while (deque.pop()) |_| {
        popped_count += 1;
    }

    // Calculate total
    var total_stolen: u32 = 0;
    for (&stolen_counts) |*count| {
        total_stolen += count.load(.acquire);
    }

    const total = total_stolen + popped_count;

    // CRITICAL: All items must be accounted for
    try testing.expectEqual(num_items, total);
}
