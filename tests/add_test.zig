const std = @import("std");
const helpers = @import("helpers.zig");

test "add: no arguments shows error" {
    const allocator = std.testing.allocator;
    var result = try helpers.runZr(allocator, &[_][]const u8{"add"}, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "add: missing type") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Hint: zr add task") != null);
}

test "add: unknown type shows error" {
    const allocator = std.testing.allocator;
    var result = try helpers.runZr(allocator, &[_][]const u8{ "add", "unknown" }, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "add: unknown type 'unknown'") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Hint: zr add task") != null);
}

test "add: task without config file shows error" {
    const allocator = std.testing.allocator;

    // Create temporary directory
    const tmp_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var tmp_dir = try std.fs.cwd().makeOpenPath("test-add-tmp", .{});
    defer {
        std.fs.cwd().deleteTree("test-add-tmp") catch {};
    }
    defer tmp_dir.close();

    const tmp_abs = try tmp_dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_abs);

    // Simulate EOF on stdin by closing stdin (this will cause the command to fail gracefully)
    var result = try helpers.runZr(allocator, &[_][]const u8{ "add", "task", "test-task" }, tmp_abs);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    // Should either error about missing config or cancelled by user (due to EOF)
    const has_error = std.mem.indexOf(u8, result.stderr, "config file not found") != null or
        std.mem.indexOf(u8, result.stderr, "Cancelled by user") != null;
    try std.testing.expect(has_error);
}

test "add: workflow without config file shows error" {
    const allocator = std.testing.allocator;

    var tmp_dir = try std.fs.cwd().makeOpenPath("test-add-workflow-tmp", .{});
    defer {
        std.fs.cwd().deleteTree("test-add-workflow-tmp") catch {};
    }
    defer tmp_dir.close();

    const tmp_abs = try tmp_dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_abs);

    var result = try helpers.runZr(allocator, &[_][]const u8{ "add", "workflow", "test-workflow" }, tmp_abs);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const has_error = std.mem.indexOf(u8, result.stderr, "config file not found") != null or
        std.mem.indexOf(u8, result.stderr, "Cancelled by user") != null;
    try std.testing.expect(has_error);
}

test "add: profile without config file shows error" {
    const allocator = std.testing.allocator;

    var tmp_dir = try std.fs.cwd().makeOpenPath("test-add-profile-tmp", .{});
    defer {
        std.fs.cwd().deleteTree("test-add-profile-tmp") catch {};
    }
    defer tmp_dir.close();

    const tmp_abs = try tmp_dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_abs);

    var result = try helpers.runZr(allocator, &[_][]const u8{ "add", "profile", "test-profile" }, tmp_abs);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const has_error = std.mem.indexOf(u8, result.stderr, "config file not found") != null or
        std.mem.indexOf(u8, result.stderr, "Cancelled by user") != null;
    try std.testing.expect(has_error);
}

test "add: help shows in main help" {
    const allocator = std.testing.allocator;
    var result = try helpers.runZr(allocator, &[_][]const u8{"--help"}, null);
    defer result.deinit();

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "add <type> [name]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Interactively add a task, workflow, or profile") != null);
}
