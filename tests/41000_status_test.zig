const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Status Command Tests ───────────────────────────────────────────────────────
//
// Tests for `zr status` command (v1.111.0+):
//
// 41000: status without zr.toml shows error "No zr.toml found" and suggests "zr init"
// 41001: status with valid config shows task count and "No run history" when fresh
// 41002: status with `.zr/last-failures.txt` containing failed tasks lists them
// 41003: status suggests `zr run --retry-failed` when failures exist
// 41004: status --json outputs JSON with config info and last failures
// 41005: status with empty/absent failures file shows "All tasks succeeded"
//

// Test 41000: status without zr.toml shows error
test "41000: status without zr.toml shows error and init suggestion" {
    var result = try runZr(testing.allocator, &.{ "status", "--config=/nonexistent/path/zr.toml" }, null);
    defer result.deinit();

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Should show error about missing config
    try testing.expect(std.mem.indexOf(u8, combined, "No zr.toml found") != null);
    // Should suggest zr init
    try testing.expect(std.mem.indexOf(u8, combined, "zr init") != null);
    // Should indicate error (either exit code 1 or error marker in output)
    try testing.expect(result.exit_code != 0 or std.mem.indexOf(u8, combined, "✗") != null);
}

// Test 41001: status with valid config shows task count and no history message
test "41001: status with valid config shows task count and no run history" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[tasks.lint]
        \\cmd = "echo linting"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{"status"}, tmp_path);
    defer result.deinit();

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Should show config is healthy
    try testing.expect(std.mem.indexOf(u8, combined, "zr.toml") != null);
    // Should indicate task count (3 tasks)
    try testing.expect(std.mem.indexOf(u8, combined, "3") != null);
    // Should show no run history
    try testing.expect(std.mem.indexOf(u8, combined, "No run history") != null);
    // Exit code should be 0 (success)
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 41002: status with failed tasks in `.zr/last-failures.txt` lists them
test "41002: status with last-failures.txt lists failed tasks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[tasks.lint]
        \\cmd = "echo linting"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Create .zr directory and last-failures.txt
    try tmp.dir.makePath(".zr");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = "test\nlint\n" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{"status"}, tmp_path);
    defer result.deinit();

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Should show last run had failures
    try testing.expect(std.mem.indexOf(u8, combined, "failed") != null or std.mem.indexOf(u8, combined, "failure") != null);
    // Should list the failed task names
    try testing.expect(std.mem.indexOf(u8, combined, "test") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "lint") != null);
    // Exit code should be 0 (status command itself succeeds)
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 41003: status suggests `zr run --retry-failed` when failures exist
test "41003: status suggests retry-failed hint when failures exist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Create .zr directory with last failures
    try tmp.dir.makePath(".zr");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = "test\n" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{"status"}, tmp_path);
    defer result.deinit();

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Should suggest running with --retry-failed
    try testing.expect(std.mem.indexOf(u8, combined, "retry-failed") != null or std.mem.indexOf(u8, combined, "--retry-failed") != null or std.mem.indexOf(u8, combined, "Hint") != null);
}

// Test 41004: status --json outputs JSON with config and failures
test "41004: status --json outputs JSON format" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Create .zr directory with last failures
    try tmp.dir.makePath(".zr");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = "test\n" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{ "status", "--json" }, tmp_path);
    defer result.deinit();

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Should output valid JSON-like content (at least contains braces)
    try testing.expect(std.mem.indexOf(u8, combined, "{") != null or std.mem.indexOf(u8, combined, "[") != null);
    // Should include task count or config info
    try testing.expect(std.mem.indexOf(u8, combined, "task") != null or std.mem.indexOf(u8, combined, "config") != null);
    // Exit code should be 0
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 41005: status with empty failures file or no failures shows success message
test "41005: status with no failures shows all succeeded message" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    // Create .zr directory but with EMPTY last-failures.txt (previous run succeeded)
    try tmp.dir.makePath(".zr");
    try tmp.dir.writeFile(.{ .sub_path = ".zr/last-failures.txt", .data = "" });

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var result = try runZr(testing.allocator, &.{"status"}, tmp_path);
    defer result.deinit();

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Should indicate all tasks succeeded or no failures
    try testing.expect(
        std.mem.indexOf(u8, combined, "All tasks succeeded") != null or
            std.mem.indexOf(u8, combined, "succeeded") != null or
            std.mem.indexOf(u8, combined, "No failed") != null or
            std.mem.indexOf(u8, combined, "no failures") != null,
    );
    // Exit code should be 0
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}
