/// Integration tests for error message quality and consistency.
/// Verifies that error codes, hints, and suggestions appear in actual CLI output.
const std = @import("std");
const helpers = @import("helpers.zig");

const expect = std.testing.expect;

// Test: Unknown command shows error code and suggestions
test "unknown command: shows E100 error code" {
    const allocator = std.testing.allocator;
    var result = try helpers.runZr(allocator, &.{"unknowncommand"}, null);
    defer result.deinit();

    // Should show error code E100
    try expect(std.mem.indexOf(u8, result.stderr, "[E100]") != null);
    // Should mention the unknown command
    try expect(std.mem.indexOf(u8, result.stderr, "unknowncommand") != null);
    // Should provide hint
    try expect(std.mem.indexOf(u8, result.stderr, "Hint:") != null);
    // Exit code should be 1
    try expect(result.exit_code == 1);
}

test "unknown command: suggests similar commands" {
    const allocator = std.testing.allocator;
    var result = try helpers.runZr(allocator, &.{"rnu"}, null); // Close to "run"
    defer result.deinit();

    // Should show error code
    try expect(std.mem.indexOf(u8, result.stderr, "[E100]") != null);
    // Should suggest "run"
    try expect(std.mem.indexOf(u8, result.stderr, "Did you mean") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "zr run") != null);
    // Exit code should be 1
    try expect(result.exit_code == 1);
}

test "missing task argument: shows clear error with hint" {
    const allocator = std.testing.allocator;
    var result = try helpers.runZr(allocator, &.{"run"}, null);
    defer result.deinit();

    // Should mention missing task name
    try expect(std.mem.indexOf(u8, result.stderr, "missing task name") != null);
    // Should provide hint with example
    try expect(std.mem.indexOf(u8, result.stderr, "Hint:") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "zr run") != null);
    // Exit code should be 1
    try expect(result.exit_code == 1);
}

test "config not found: suggests zr init" {
    const allocator = std.testing.allocator;

    // Run in temporary directory without zr.toml
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try helpers.runZr(allocator, &.{"list"}, tmp_path);
    defer result.deinit();

    // Should mention config not found or no configuration
    try expect(std.mem.indexOf(u8, result.stderr, "zr.toml") != null or
        std.mem.indexOf(u8, result.stderr, "No configuration") != null or
        std.mem.indexOf(u8, result.stderr, "not found") != null);
    // Should suggest zr init
    try expect(std.mem.indexOf(u8, result.stderr, "zr init") != null);
    // Exit code should be 1
    try expect(result.exit_code == 1);
}

test "task not found: lists available tasks" {
    const allocator = std.testing.allocator;

    // Create temporary config with some tasks
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const config_path = try helpers.writeTmpConfig(allocator, tmp_dir.dir,
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
    );
    defer allocator.free(config_path);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try helpers.runZr(allocator, &.{ "run", "unknown-task" }, tmp_path);
    defer result.deinit();

    // Should mention task not found
    try expect(std.mem.indexOf(u8, result.stderr, "unknown-task") != null or
        std.mem.indexOf(u8, result.stderr, "not found") != null);
    // Should suggest running zr list
    try expect(std.mem.indexOf(u8, result.stderr, "zr list") != null or
        std.mem.indexOf(u8, result.stderr, "available") != null);
    // Exit code should be 1
    try expect(result.exit_code == 1);
}

test "error messages: include actionable hints" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const config_path = try helpers.writeTmpConfig(allocator, tmp_dir.dir,
        \\[tasks.build]
        \\cmd = "echo test"
    );
    defer allocator.free(config_path);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try helpers.runZr(allocator, &.{ "run", "missing" }, tmp_path);
    defer result.deinit();

    // Should include "Hint:" section
    try expect(std.mem.indexOf(u8, result.stderr, "Hint:") != null or
        std.mem.indexOf(u8, result.stderr, "hint:") != null);
    // Exit code should be 1
    try expect(result.exit_code == 1);
}

test "error messages: use error symbols" {
    const allocator = std.testing.allocator;

    // This test verifies the error symbol (✗) or text equivalent appears in output
    var result = try helpers.runZr(allocator, &.{"unknowncommand"}, null);
    defer result.deinit();

    // Should include error symbol (✗) or text equivalent
    try expect(std.mem.indexOf(u8, result.stderr, "✗") != null or
        std.mem.indexOf(u8, result.stderr, "error") != null or
        std.mem.indexOf(u8, result.stderr, "Error") != null);
}
