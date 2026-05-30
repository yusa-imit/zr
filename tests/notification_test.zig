const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Test Fixtures ──────────────────────────────────────────────────────

const BASIC_NOTIFICATION_TOML =
    \\[tasks.build]
    \\cmd = "echo building"
    \\notify = true
    \\
;

const NOTIFY_ON_FAILURE_TOML =
    \\[tasks.deploy]
    \\cmd = "echo deploying"
    \\notify = true
    \\notify_on = "failure"
    \\
;

const NOTIFY_ON_SUCCESS_TOML =
    \\[tasks.test]
    \\cmd = "echo testing"
    \\notify = true
    \\notify_on = "success"
    \\
;

const NOTIFY_WITH_TITLE_TOML =
    \\[tasks.release]
    \\cmd = "echo releasing"
    \\notify = true
    \\notify_title = "Production Release"
    \\
;

const MULTIPLE_NOTIFY_TASKS_TOML =
    \\[tasks.lint]
    \\cmd = "echo linting"
    \\notify = true
    \\notify_on = "failure"
    \\
    \\[tasks.format]
    \\cmd = "echo formatting"
    \\notify = true
    \\notify_on = "success"
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "12000: task with notify = true parses without error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, BASIC_NOTIFICATION_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    // Parser now supports notify field, so this should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "12001: notify_on = 'failure' parses correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, NOTIFY_ON_FAILURE_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    // Parser now supports notify_on field, so this should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "12002: notify_on = 'success' parses correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, NOTIFY_ON_SUCCESS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    // Parser now supports notify_on field, so this should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "12003: --notify flag is accepted by CLI" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Test that --notify flag is recognized (it should be a valid flag, not "unknown flag")
    // Use a nonexistent task to verify the flag is parsed correctly
    var result = try runZr(allocator, &.{ "run", "--notify", "nonexistent_task" }, tmp_path);
    defer result.deinit();

    // Should fail because task doesn't exist, but NOT because of unknown flag
    try std.testing.expect(result.exit_code != 0);
    // Verify the error is NOT about unknown flag
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown flag") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unexpected argument") == null);
}

test "12004: notify_title parses correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, NOTIFY_WITH_TITLE_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    // Parser now supports notify_title field, so this should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "12005: task with notify = true executes its command successfully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, BASIC_NOTIFICATION_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run the task (not just validate) — the notification flag should not prevent execution
    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Command output should be present regardless of notification setting
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "12006: failing task with notify_on = 'failure' still propagates exit code" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const failing_notify_toml =
        \\[tasks.fail-notified]
        \\cmd = "exit 1"
        \\notify = true
        \\notify_on = "failure"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, failing_notify_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // A failing task with notification enabled should still fail (exit code != 0)
    var result = try runZr(allocator, &.{ "--config", config, "run", "fail-notified" }, tmp_path);
    defer result.deinit();

    // Notification should NOT swallow the task failure
    try std.testing.expect(result.exit_code != 0);
}

test "12007: --notify flag does not change task exit code" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, BASIC_NOTIFICATION_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // With --notify flag, successful task still succeeds
    var result = try runZr(allocator, &.{ "--config", config, "run", "--notify", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}
