const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

const BASIC_TOML =
    \\[tasks.build]
    \\cmd = "echo 'Building...'"
    \\
    \\[tasks.test]
    \\cmd = "echo 'Testing...'"
    \\
;

const INVALID_TOML =
    \\[tasks.build
    \\cmd = "echo 'test'"
    \\
;

// ---------------------------------------------------------------------------
// Integration tests for `zr interactive` (alias: `zr i`) command
// ---------------------------------------------------------------------------

test "827: interactive graceful fallback in non-TTY environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    // Run zr interactive in non-TTY environment (the test harness redirects stdin)
    // Should show a fallback message rather than entering interactive mode
    var result = try runZr(allocator, &.{"interactive"}, tmp_path);
    defer result.deinit();

    // Should exit cleanly (exit code 0)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should show a message indicating TUI is not available
    const stdout_lower = try std.ascii.allocLowerString(allocator, result.stdout);
    defer allocator.free(stdout_lower);

    // Check for fallback message (case-insensitive)
    const has_tty_message = std.mem.indexOf(u8, stdout_lower, "tty") != null or
        std.mem.indexOf(u8, stdout_lower, "terminal") != null or
        std.mem.indexOf(u8, stdout_lower, "list") != null;

    try std.testing.expect(has_tty_message);
}

test "828: interactive works with empty config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "" });

    // Run zr interactive - should exit cleanly even with no tasks
    var result = try runZr(allocator, &.{"i"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "829: interactive shows error on invalid config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = INVALID_TOML });

    // Run zr interactive - should fail with parse error
    var result = try runZr(allocator, &.{"interactive"}, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(result.stderr.len > 0);
}

test "830: interactive respects --no-color flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    // Run with --no-color
    var result = try runZr(allocator, &.{ "i", "--no-color" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should not contain ANSI escape codes
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\x1b[") == null);
}

test "831: interactive alias i works correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    // Test that 'i' is an alias for 'interactive'
    var result_full = try runZr(allocator, &.{"interactive"}, tmp_path);
    defer result_full.deinit();

    var result_alias = try runZr(allocator, &.{"i"}, tmp_path);
    defer result_alias.deinit();

    // Both should have same exit code
    try std.testing.expectEqual(result_full.exit_code, result_alias.exit_code);

    // Both should show similar output (both have fallback message)
    const has_output_full = result_full.stdout.len > 0 or result_full.stderr.len > 0;
    const has_output_alias = result_alias.stdout.len > 0 or result_alias.stderr.len > 0;
    try std.testing.expectEqual(has_output_full, has_output_alias);
}
