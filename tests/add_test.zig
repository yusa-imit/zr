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

    // Create temporary directory in /tmp to avoid parent directory search finding project zr.toml
    const tmp_base = "/tmp/zr-test-add-task";
    std.fs.deleteTreeAbsolute(tmp_base) catch {};
    try std.fs.makeDirAbsolute(tmp_base);
    defer std.fs.deleteTreeAbsolute(tmp_base) catch {};

    // Simulate EOF on stdin by closing stdin (this will cause the command to fail gracefully)
    var result = try helpers.runZr(allocator, &[_][]const u8{ "add", "task", "test-task" }, tmp_base);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    // Should either error about missing config or cancelled by user (due to EOF)
    const has_error = std.mem.indexOf(u8, result.stderr, "config file not found") != null or
        std.mem.indexOf(u8, result.stderr, "Cancelled by user") != null;
    try std.testing.expect(has_error);
}

test "add: workflow without config file shows error" {
    const allocator = std.testing.allocator;

    // Create temporary directory in /tmp to avoid parent directory search finding project zr.toml
    const tmp_base = "/tmp/zr-test-add-workflow";
    std.fs.deleteTreeAbsolute(tmp_base) catch {};
    try std.fs.makeDirAbsolute(tmp_base);
    defer std.fs.deleteTreeAbsolute(tmp_base) catch {};

    var result = try helpers.runZr(allocator, &[_][]const u8{ "add", "workflow", "test-workflow" }, tmp_base);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const has_error = std.mem.indexOf(u8, result.stderr, "config file not found") != null or
        std.mem.indexOf(u8, result.stderr, "Cancelled by user") != null;
    try std.testing.expect(has_error);
}

test "add: profile without config file shows error" {
    const allocator = std.testing.allocator;

    // Create temporary directory in /tmp to avoid parent directory search finding project zr.toml
    const tmp_base = "/tmp/zr-test-add-profile";
    std.fs.deleteTreeAbsolute(tmp_base) catch {};
    try std.fs.makeDirAbsolute(tmp_base);
    defer std.fs.deleteTreeAbsolute(tmp_base) catch {};

    var result = try helpers.runZr(allocator, &[_][]const u8{ "add", "profile", "test-profile" }, tmp_base);
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
