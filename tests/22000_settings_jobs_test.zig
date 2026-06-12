const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── [settings] jobs & default_timeout Tests ─────────────────────────────────
//
// Tests for [settings] section with jobs and default_timeout support:
// 1. [settings] jobs = N is parsed without error; tasks run successfully
// 2. --jobs CLI flag overrides [settings] jobs
// 3. [settings] jobs = 1 doesn't break sequential runs
// 4. [settings] default_timeout applies to tasks with no explicit timeout
// 5. Task-level timeout overrides [settings] default_timeout
// 6. [settings] jobs + default_profile coexist without conflict
//

test "22000: [settings] jobs = 2 allows tasks to run successfully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\jobs = 2
        \\
        \\[tasks.hello]
        \\cmd = "echo hello-from-settings"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello-from-settings") != null);
}

test "22001: --jobs CLI flag overrides [settings] jobs" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\jobs = 99
        \\
        \\[tasks.work]
        \\cmd = "echo working"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // --jobs 1 on CLI should override settings jobs = 99
    var result = try runZr(allocator, &.{ "--config", config, "--jobs", "1", "run", "work" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "working") != null);
}

test "22002: [settings] jobs = 1 runs tasks sequentially without error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\jobs = 1
        \\
        \\[tasks.step1]
        \\cmd = "echo step1"
        \\
        \\[tasks.step2]
        \\cmd = "echo step2"
        \\deps = ["step1"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "step2" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step2") != null);
}

test "22003: [settings] default_timeout causes timeout when task exceeds it" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_timeout = 1
        \\
        \\[tasks.slow]
        \\cmd = "sleep 3"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "slow" }, tmp_path);
    defer result.deinit();

    // Task should fail due to timeout (exit code 124 or non-zero)
    try std.testing.expect(result.exit_code != 0);
}

test "22004: Task-level timeout overrides [settings] default_timeout" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_timeout = 1
        \\
        \\[tasks.medium]
        \\cmd = "sleep 2 && echo done"
        \\timeout = 5
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "medium" }, tmp_path);
    defer result.deinit();

    // Task-level timeout = 5s > sleep 2s, so it should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "done") != null);
}

test "22005: [settings] jobs and default_profile coexist" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\jobs = 2
        \\default_profile = "fast"
        \\
        \\[vars]
        \\MODE = "slow"
        \\
        \\[profiles.fast]
        \\[profiles.fast.vars]
        \\MODE = "fast"
        \\
        \\[tasks.check]
        \\cmd = "echo mode={{MODE}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "check" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both settings should apply: jobs=2 (no error) and default_profile=fast (MODE=fast)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mode=fast") != null);
}
