const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrEnv = helpers.runZrEnv;

// ── Run-Level Lifecycle Hooks Tests ────────────────────────────────────────
//
// Tests for `[settings]` lifecycle hook fields (v2.0.0 milestone):
//
// 1. `before_all = ["setup"]` — tasks run BEFORE any other task
// 2. `after_all = ["cleanup"]` — tasks run AFTER everything, EVEN IF main failed
// 3. `on_error = ["alert"]` — tasks run ONLY when main run fails
// 4. `on_success = ["notify"]` — tasks run ONLY when main run succeeds
// 5. `before_all` failure aborts the run without executing main tasks
// 6. `--dry-run` shows "Run lifecycle hooks:" section
//

const BEFORE_ALL_TOML =
    \\[settings]
    \\before_all = ["setup"]
    \\
    \\[tasks.setup]
    \\cmd = "echo SETUP_RAN"
    \\
    \\[tasks.main]
    \\cmd = "echo MAIN_RAN"
    \\
;

const AFTER_ALL_TOML =
    \\[settings]
    \\after_all = ["cleanup"]
    \\
    \\[tasks.cleanup]
    \\cmd = "echo CLEANUP_RAN"
    \\
    \\[tasks.fail]
    \\cmd = "exit 1"
    \\
;

const ON_ERROR_TOML =
    \\[settings]
    \\on_error = ["handle-err"]
    \\
    \\[tasks.handle-err]
    \\cmd = "echo ERROR_HANDLED"
    \\
    \\[tasks.fail-task]
    \\cmd = "exit 1"
    \\
    \\[tasks.ok]
    \\cmd = "echo OK"
    \\
;

const ON_SUCCESS_TOML =
    \\[settings]
    \\on_success = ["notify"]
    \\
    \\[tasks.notify]
    \\cmd = "echo NOTIFY_RAN"
    \\
    \\[tasks.build]
    \\cmd = "echo BUILD_DONE"
    \\
    \\[tasks.fail-build]
    \\cmd = "exit 1"
    \\
;

const BEFORE_ALL_ABORTS_TOML =
    \\[settings]
    \\before_all = ["check"]
    \\
    \\[tasks.check]
    \\cmd = "exit 1"
    \\
    \\[tasks.main]
    \\cmd = "echo MAIN_SHOULD_NOT_RUN"
    \\
;

const DRY_RUN_HOOKS_TOML =
    \\[settings]
    \\before_all = ["setup"]
    \\after_all = ["cleanup"]
    \\on_error = ["alert"]
    \\on_success = ["notify"]
    \\
    \\[tasks.setup]
    \\cmd = "echo setup"
    \\
    \\[tasks.cleanup]
    \\cmd = "echo cleanup"
    \\
    \\[tasks.alert]
    \\cmd = "echo alert"
    \\
    \\[tasks.notify]
    \\cmd = "echo notify"
    \\
    \\[tasks.main]
    \\cmd = "echo main"
    \\
;

test "29000: before_all tasks run before the main task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with before_all configuration
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BEFORE_ALL_TOML });

    // Run: zr run main
    var result = try runZr(allocator, &.{ "run", "main" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Stdout should contain both SETUP_RAN and MAIN_RAN
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "SETUP_RAN") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "MAIN_RAN") != null);

    // SETUP_RAN must appear before MAIN_RAN in output (order verification)
    const setup_pos = std.mem.indexOf(u8, result.stdout, "SETUP_RAN").?;
    const main_pos = std.mem.indexOf(u8, result.stdout, "MAIN_RAN").?;
    try std.testing.expect(setup_pos < main_pos);
}

test "29001: after_all always runs even when main task fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with after_all configuration
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = AFTER_ALL_TOML });

    // Run: zr run fail
    var result = try runZr(allocator, &.{ "run", "fail" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code != 0) because the main task fails
    try std.testing.expect(result.exit_code != 0);

    // Stdout should contain CLEANUP_RAN (after_all hook ran even after failure)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "CLEANUP_RAN") != null);
}

test "29002: on_error runs when main task fails, does NOT run on success" {
    const allocator = std.testing.allocator;

    // Part A: on_error should run when main task fails
    {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);

        try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = ON_ERROR_TOML });

        // Run the failing task
        var result = try runZr(allocator, &.{ "run", "fail-task" }, tmp_path);
        defer result.deinit();

        // Should fail (exit code != 0)
        try std.testing.expect(result.exit_code != 0);

        // Stdout should contain ERROR_HANDLED (on_error hook ran)
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR_HANDLED") != null);
    }

    // Part B: on_error should NOT run when main task succeeds
    {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);

        try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = ON_ERROR_TOML });

        // Run the successful task
        var result = try runZr(allocator, &.{ "run", "ok" }, tmp_path);
        defer result.deinit();

        // Should succeed (exit code 0)
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);

        // Stdout should contain OK
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "OK") != null);

        // Stdout should NOT contain ERROR_HANDLED (on_error hook should NOT run on success)
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR_HANDLED") == null);
    }
}

test "29003: on_success runs when all tasks succeed, does NOT run on failure" {
    const allocator = std.testing.allocator;

    // Part A: on_success should run when main task succeeds
    {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);

        try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = ON_SUCCESS_TOML });

        // Run the successful task
        var result = try runZr(allocator, &.{ "run", "build" }, tmp_path);
        defer result.deinit();

        // Should succeed (exit code 0)
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);

        // Stdout should contain NOTIFY_RAN (on_success hook ran)
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NOTIFY_RAN") != null);

        // Stdout should also contain BUILD_DONE
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "BUILD_DONE") != null);
    }

    // Part B: on_success should NOT run when main task fails
    {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);

        try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = ON_SUCCESS_TOML });

        // Run the failing task
        var result = try runZr(allocator, &.{ "run", "fail-build" }, tmp_path);
        defer result.deinit();

        // Should fail (exit code != 0)
        try std.testing.expect(result.exit_code != 0);

        // Stdout should NOT contain NOTIFY_RAN (on_success hook should NOT run on failure)
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NOTIFY_RAN") == null);
    }
}

test "29004: before_all failure aborts the run without executing main tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml where before_all task fails
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BEFORE_ALL_ABORTS_TOML });

    // Run: zr run main
    var result = try runZr(allocator, &.{ "run", "main" }, tmp_path);
    defer result.deinit();

    // Should fail (exit code != 0) because before_all hook fails
    try std.testing.expect(result.exit_code != 0);

    // Stdout should NOT contain MAIN_SHOULD_NOT_RUN
    // (the main task should never execute because before_all failed)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "MAIN_SHOULD_NOT_RUN") == null);
}

test "29005: --dry-run shows Run lifecycle hooks section when hooks are configured" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create zr.toml with all lifecycle hooks configured
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = DRY_RUN_HOOKS_TOML });

    // Run: zr run --dry-run main
    var result = try runZr(allocator, &.{ "run", "--dry-run", "main" }, tmp_path);
    defer result.deinit();

    // Should succeed with exit code 0 (dry-run doesn't execute)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Dry-run output should mention lifecycle hooks
    // Check for "Run lifecycle hooks:" or similar wording in output
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);

    try std.testing.expect(std.mem.indexOf(u8, combined, "lifecycle") != null or
        std.mem.indexOf(u8, combined, "Lifecycle") != null or
        std.mem.indexOf(u8, combined, "hook") != null or
        std.mem.indexOf(u8, combined, "Hook") != null or
        std.mem.indexOf(u8, combined, "before_all") != null or
        std.mem.indexOf(u8, combined, "after_all") != null or
        std.mem.indexOf(u8, combined, "on_error") != null or
        std.mem.indexOf(u8, combined, "on_success") != null);
}
