const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "silent mode: successful task suppresses output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const silent_success_toml =
        \\[tasks.quiet]
        \\cmd = "echo 'This should not appear'"
        \\silent = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, silent_success_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "quiet" }, tmp_path);
    defer result.deinit();

    // Task should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should be suppressed (neither stdout nor stderr should contain the echo output)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "This should not appear") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "This should not appear") == null);
}

test "silent mode: failed task shows buffered output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const silent_fail_toml =
        \\[tasks.noisy-failure]
        \\cmd = "echo 'Error details' && false"
        \\silent = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, silent_fail_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "noisy-failure" }, tmp_path);
    defer result.deinit();

    // Task should fail
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Output should be shown on failure (buffered output dumped to stderr)
    const combined_output = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Error details") != null);
}

test "silent mode: non-silent task shows output normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const non_silent_toml =
        \\[tasks.verbose]
        \\cmd = "echo 'Always visible'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, non_silent_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "verbose" }, tmp_path);
    defer result.deinit();

    // Task should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should be visible (default behavior)
    const combined_output = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Always visible") != null);
}

test "silent mode: mixed silent and non-silent tasks in workflow" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const mixed_toml =
        \\[tasks.silent-prep]
        \\cmd = "echo 'Silent prep work'"
        \\silent = true
        \\
        \\[tasks.loud-build]
        \\cmd = "echo 'Building loudly'"
        \\deps = ["silent-prep"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, mixed_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "loud-build" }, tmp_path);
    defer result.deinit();

    // Workflow should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const combined_output = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);

    // Silent task output should be suppressed
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Silent prep work") == null);

    // Loud task output should be visible
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Building loudly") != null);
}

test "silent mode: default false when field omitted" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const default_toml =
        \\[tasks.default-noisy]
        \\cmd = "echo 'Default behavior'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, default_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "default-noisy" }, tmp_path);
    defer result.deinit();

    // Task should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should be visible (silent defaults to false)
    const combined_output = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Default behavior") != null);
}

test "silent mode: explicit silent = false shows output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const explicit_false_toml =
        \\[tasks.explicit]
        \\cmd = "echo 'Explicitly loud'"
        \\silent = false
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, explicit_false_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "explicit" }, tmp_path);
    defer result.deinit();

    // Task should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should be visible
    const combined_output = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Explicitly loud") != null);
}

test "silent mode: multiple silent tasks all suppress output on success" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const multi_silent_toml =
        \\[tasks.quiet1]
        \\cmd = "echo 'Hidden output 1'"
        \\silent = true
        \\
        \\[tasks.quiet2]
        \\cmd = "echo 'Hidden output 2'"
        \\silent = true
        \\
        \\[tasks.aggregate]
        \\cmd = "echo 'Final step'"
        \\deps = ["quiet1", "quiet2"]
        \\silent = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, multi_silent_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "aggregate" }, tmp_path);
    defer result.deinit();

    // All tasks should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const combined_output = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);

    // All outputs should be suppressed
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Hidden output 1") == null);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Hidden output 2") == null);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, "Final step") == null);
}

test "silent mode: JSON output includes silent field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const json_test_toml =
        \\[tasks.json-silent]
        \\cmd = "true"
        \\silent = true
        \\
        \\[tasks.json-loud]
        \\cmd = "true"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, json_test_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--format=json" }, tmp_path);
    defer result.deinit();

    // List should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // JSON should include silent field for both tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"silent\"") != null);
}
