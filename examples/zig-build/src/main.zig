const std = @import("std");

/// Add two integers
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

/// Greet someone by name
pub fn greet(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "Hello, {s}!", .{name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        const name = args[1];
        const message = try greet(allocator, name);
        defer allocator.free(message);
        try stdout.print("{s}\n", .{message});
    } else {
        try stdout.print("Hello, World!\n", .{});
    }

    const result = add(2, 3);
    try stdout.print("2 + 3 = {d}\n", .{result});
}

// Tests
test "add function" {
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
    try std.testing.expectEqual(@as(i32, 0), add(-1, 1));
    try std.testing.expectEqual(@as(i32, -5), add(-2, -3));
}

test "greet function" {
    const allocator = std.testing.allocator;
    const greeting = try greet(allocator, "Alice");
    defer allocator.free(greeting);
    try std.testing.expectEqualStrings("Hello, Alice!", greeting);
}
