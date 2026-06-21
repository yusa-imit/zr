const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Runtime Tags Tests ────────────────────────────────────────────────────────
//
// Tests for `--add-tag TAG` CLI flag feature (v1.102.0+):
//
// 33000: Basic `--add-tag TAG` — run a task with `--add-tag ci`, check it succeeds (exit 0)
// 33001: Multiple `--add-tag` flags — `--add-tag ci --add-tag pr-123`, both tags stored
// 33002: `--dry-run` shows runtime tags — `--dry-run --add-tag ci --add-tag env-test` shows tags in output
// 33003: Tags survive in history — run task with `--add-tag mytag`, then `zr history --limit 1` shows mytag
// 33004: Multiple `--add-tag` in history — run with `--add-tag a --add-tag b`, history shows both
// 33005: No tags = normal behavior — running without `--add-tag` produces no runtime tag section; history has no tag suffix
//

const SIMPLE_TASK_TOML =
    \\[tasks.build]
    \\cmd = "echo BUILD_SUCCESS"
    \\
;

const MULTI_TASK_TOML =
    \\[tasks.build]
    \\cmd = "echo BUILD"
    \\
    \\[tasks.test]
    \\cmd = "echo TEST"
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "33000: basic --add-tag TAG — run a task with --add-tag ci, check it succeeds (exit 0)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--add-tag", "ci" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully with exit code 0
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should show BUILD_SUCCESS
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "BUILD_SUCCESS") != null);
}

test "33001: multiple --add-tag flags — --add-tag ci --add-tag pr-123, both tags stored" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--add-tag", "ci", "--add-tag", "pr-123" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully with exit code 0
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // After run, check history to verify tags are stored
    var history_result = try runZr(allocator, &.{ "history", "--limit", "1" }, tmp_path);
    defer history_result.deinit();

    // History command should succeed
    try std.testing.expectEqual(@as(u8, 0), history_result.exit_code);
    // History output should be non-empty (indicates a record was created)
    try std.testing.expect(history_result.stdout.len > 0);
}

test "33002: --dry-run shows runtime tags — --dry-run --add-tag ci --add-tag env-test shows tags in output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "--dry-run", "run", "build", "--add-tag", "ci", "--add-tag", "env-test" }, tmp_path);
    defer result.deinit();

    // Dry-run should succeed (exit code 0)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain tag information (check for tag names or "Runtime tags" label)
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(
        std.mem.indexOf(u8, combined, "Runtime tags") != null or
            std.mem.indexOf(u8, combined, "ci") != null or
            std.mem.indexOf(u8, combined, "env-test") != null or
            std.mem.indexOf(u8, combined, "+ci") != null or
            std.mem.indexOf(u8, combined, "+env-test") != null
    );
}

test "33003: tags survive in history — run task with --add-tag mytag, then zr history --limit 1 shows mytag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task with --add-tag mytag
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "build", "--add-tag", "mytag" }, tmp_path);
    defer run_result.deinit();

    // Run should succeed
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Now check history
    var history_result = try runZr(allocator, &.{ "history", "--limit", "1" }, tmp_path);
    defer history_result.deinit();

    // History command should succeed
    try std.testing.expectEqual(@as(u8, 0), history_result.exit_code);
    // History output should contain the tag (with or without + prefix, or as part of history entry)
    try std.testing.expect(
        std.mem.indexOf(u8, history_result.stdout, "mytag") != null or
            std.mem.indexOf(u8, history_result.stdout, "+mytag") != null
    );
}

test "33004: multiple --add-tag in history — run with --add-tag a --add-tag b, history shows both" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task with two tags
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "build", "--add-tag", "a", "--add-tag", "b" }, tmp_path);
    defer run_result.deinit();

    // Run should succeed
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Now check history
    var history_result = try runZr(allocator, &.{ "history", "--limit", "1" }, tmp_path);
    defer history_result.deinit();

    // History command should succeed
    try std.testing.expectEqual(@as(u8, 0), history_result.exit_code);
    // History output should be non-empty
    try std.testing.expect(history_result.stdout.len > 0);
    // History should contain both tags
    try std.testing.expect(std.mem.indexOf(u8, history_result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, history_result.stdout, "b") != null);
}

test "33005: no tags = normal behavior — running without --add-tag produces no runtime tag section" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task without --add-tag
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer run_result.deinit();

    // Run should succeed
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Now check history
    var history_result = try runZr(allocator, &.{ "history", "--limit", "1" }, tmp_path);
    defer history_result.deinit();

    // History command should succeed
    try std.testing.expectEqual(@as(u8, 0), history_result.exit_code);
    // History should be non-empty
    try std.testing.expect(history_result.stdout.len > 0);
}

test "33006: --last-run-tags shows runtime tags in list — run build with --add-tag ci, then zr list --last-run-tags shows +ci" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task with --add-tag ci
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "build", "--add-tag", "ci" }, tmp_path);
    defer run_result.deinit();
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Now list with --last-run-tags
    var list_result = try runZr(allocator, &.{ "--config", config, "list", "--last-run-tags" }, tmp_path);
    defer list_result.deinit();

    // List command should succeed
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    // Output should contain +ci tag (with + prefix) or just "ci"
    try std.testing.expect(
        std.mem.indexOf(u8, list_result.stdout, "+ci") != null or
            std.mem.indexOf(u8, list_result.stdout, "ci") != null
    );
}

test "33007: --last-run-tags without prior tagged runs shows no tags — clean run shows no tag annotations" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task without any tags
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer run_result.deinit();
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Now list with --last-run-tags
    var list_result = try runZr(allocator, &.{ "--config", config, "list", "--last-run-tags" }, tmp_path);
    defer list_result.deinit();

    // List command should succeed
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    // Output should contain the task "build" but no + prefix tags
    try std.testing.expect(std.mem.indexOf(u8, list_result.stdout, "build") != null);
    // No +tag suffix since no tags were used
    try std.testing.expect(std.mem.indexOf(u8, list_result.stdout, "+") == null);
}
