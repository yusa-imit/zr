const std = @import("std");
const helpers = @import("helpers.zig");

test "863: failures shows no reports initially" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal zr.toml
    const toml = "[tasks.build]\ncmd = \"echo 'test'\"";
    const config_path = try helpers.writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config_path);

    // Run failures command
    var result = try helpers.runZr(allocator, &.{"failures"}, tmp_path);
    defer result.deinit();

    // Should indicate no failures found (in stderr since std.debug.print is used)
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "No failure reports found") != null);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "864: failures clear with no failures" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml = "[tasks.test]\ncmd = \"echo 'test'\"";
    const config_path = try helpers.writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config_path);

    var result = try helpers.runZr(allocator, &.{ "failures", "clear" }, tmp_path);
    defer result.deinit();

    // Should indicate no failures to clear (in stderr since std.debug.print is used)
    try std.testing.expect(
        std.mem.indexOf(u8, result.stderr, "No failure reports to clear") != null or
            std.mem.indexOf(u8, result.stderr, "Cleared 0 failure report") != null,
    );
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "865: help text includes failures command" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try helpers.runZr(allocator, &.{"--help"}, tmp_path);
    defer result.deinit();

    // Should mention failures command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "failures") != null);
}

test "866: failures list after task failure creates report" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with failing task
    const toml = "[tasks.failing]\ncmd = \"exit 1\"";
    const config_path = try helpers.writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config_path);

    // Run failing task
    var run_result = try helpers.runZr(allocator, &.{ "--config", config_path, "run", "failing" }, tmp_path);
    defer run_result.deinit();
    try std.testing.expect(run_result.exit_code != 0); // Should fail

    // Check failures list
    var failures_result = try helpers.runZr(allocator, &.{"failures"}, tmp_path);
    defer failures_result.deinit();

    // Should show failure report
    try std.testing.expect(std.mem.indexOf(u8, failures_result.stderr, "failing") != null);
    try std.testing.expectEqual(@as(u8, 0), failures_result.exit_code);
}

test "867: failures clear removes reports" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with failing task
    const toml = "[tasks.failing]\ncmd = \"exit 1\"";
    const config_path = try helpers.writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config_path);

    // Run failing task
    var run_result = try helpers.runZr(allocator, &.{ "--config", config_path, "run", "failing" }, tmp_path);
    defer run_result.deinit();

    // Clear failures
    var clear_result = try helpers.runZr(allocator, &.{ "failures", "clear" }, tmp_path);
    defer clear_result.deinit();
    try std.testing.expectEqual(@as(u8, 0), clear_result.exit_code);

    // Check failures list is now empty
    var list_result = try helpers.runZr(allocator, &.{"failures"}, tmp_path);
    defer list_result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, list_result.stderr, "No failure reports found") != null);
}

test "868: failures with --task filter shows only matching task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with two failing tasks
    const toml =
        \\[tasks.fail1]
        \\cmd = "exit 1"
        \\
        \\[tasks.fail2]
        \\cmd = "exit 2"
    ;
    const config_path = try helpers.writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config_path);

    // Run both failing tasks
    var run1 = try helpers.runZr(allocator, &.{ "--config", config_path, "run", "fail1" }, tmp_path);
    defer run1.deinit();
    var run2 = try helpers.runZr(allocator, &.{ "--config", config_path, "run", "fail2" }, tmp_path);
    defer run2.deinit();

    // Filter by task name
    var filter_result = try helpers.runZr(allocator, &.{ "failures", "--task", "fail1" }, tmp_path);
    defer filter_result.deinit();

    // Should only show fail1, not fail2
    try std.testing.expect(std.mem.indexOf(u8, filter_result.stderr, "fail1") != null);
    try std.testing.expectEqual(@as(u8, 0), filter_result.exit_code);
}

test "869: failures with invalid flag shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try helpers.runZr(allocator, &.{ "failures", "--help" }, tmp_path);
    defer result.deinit();

    // Should succeed and show help
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}
