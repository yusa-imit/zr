const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── zr list --sort Tests ───────────────────────────────────────────────────────
//
// These tests verify the --sort flag for `zr list`:
//   --sort=name    Alphabetical (default)
//   --sort=freq    Most-executed tasks first (requires history)
//   --sort=time    Slowest tasks first (requires history)
//   --sort=recent  Most-recently-run tasks first (requires history)
//
// Without history data, freq/time/recent fall back to alphabetical order.
//

const MULTI_TASK_TOML =
    \\[tasks.zzz]
    \\cmd = "echo zzz"
    \\description = "Z task"
    \\
    \\[tasks.aaa]
    \\cmd = "echo aaa"
    \\description = "A task"
    \\
    \\[tasks.mmm]
    \\cmd = "echo mmm"
    \\description = "M task"
    \\
;

test "list --sort=name: tasks appear in alphabetical order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort=name" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const stdout = result.stdout;

    // aaa must appear before mmm and zzz
    const aaa_pos = std.mem.indexOf(u8, stdout, "aaa") orelse return error.NotFound;
    const mmm_pos = std.mem.indexOf(u8, stdout, "mmm") orelse return error.NotFound;
    const zzz_pos = std.mem.indexOf(u8, stdout, "zzz") orelse return error.NotFound;
    try std.testing.expect(aaa_pos < mmm_pos);
    try std.testing.expect(mmm_pos < zzz_pos);
}

test "list --sort=freq: command succeeds with no history (falls back to alpha)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort=freq" }, tmp_path);
    defer result.deinit();

    // Should succeed even without history
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All tasks should appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "aaa") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mmm") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zzz") != null);
}

test "list --sort=time: command succeeds with no history (falls back to alpha)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort=time" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "aaa") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mmm") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zzz") != null);
}

test "list --sort=recent: command succeeds with no history (falls back to alpha)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort=recent" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "aaa") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mmm") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zzz") != null);
}

test "list --sort: space-separated form works (--sort name)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort", "name" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Tasks should still appear in alphabetical order
    const aaa_pos = std.mem.indexOf(u8, result.stdout, "aaa") orelse return error.NotFound;
    const zzz_pos = std.mem.indexOf(u8, result.stdout, "zzz") orelse return error.NotFound;
    try std.testing.expect(aaa_pos < zzz_pos);
}

test "list --sort: unknown key still exits successfully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    // Unknown sort key should fall back to alphabetical (graceful degradation)
    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort=bogus" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "aaa") != null);
}

test "list --sort=freq: after running tasks, most-run task appears first" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    // Run "zzz" three times to make it the most frequent
    for (0..3) |_| {
        var r = try runZr(allocator, &.{ "--config", config, "run", "zzz" }, tmp_path);
        defer r.deinit();
        try std.testing.expectEqual(@as(u8, 0), r.exit_code);
    }
    // Run "aaa" once
    {
        var r = try runZr(allocator, &.{ "--config", config, "run", "aaa" }, tmp_path);
        defer r.deinit();
        try std.testing.expectEqual(@as(u8, 0), r.exit_code);
    }

    // Now list --sort=freq: zzz (3 runs) should appear before aaa (1 run)
    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort=freq" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const zzz_pos = std.mem.indexOf(u8, result.stdout, "zzz") orelse return error.NotFound;
    const aaa_pos = std.mem.indexOf(u8, result.stdout, "aaa") orelse return error.NotFound;
    // Most frequent (zzz) should appear before less frequent (aaa)
    try std.testing.expect(zzz_pos < aaa_pos);
}

test "list --sort=recent: most-recently-run task appears first" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_TASK_TOML);
    defer allocator.free(config);

    // Run "aaa" first, then "zzz" last
    {
        var r = try runZr(allocator, &.{ "--config", config, "run", "aaa" }, tmp_path);
        defer r.deinit();
        try std.testing.expectEqual(@as(u8, 0), r.exit_code);
    }
    {
        var r = try runZr(allocator, &.{ "--config", config, "run", "zzz" }, tmp_path);
        defer r.deinit();
        try std.testing.expectEqual(@as(u8, 0), r.exit_code);
    }

    // list --sort=recent: zzz (most recently run) should appear before aaa
    var result = try runZr(allocator, &.{ "--config", config, "list", "--sort=recent" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const zzz_pos = std.mem.indexOf(u8, result.stdout, "zzz") orelse return error.NotFound;
    const aaa_pos = std.mem.indexOf(u8, result.stdout, "aaa") orelse return error.NotFound;
    try std.testing.expect(zzz_pos < aaa_pos);
}

test "list --sort=freq combined with filter pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build-dev]
        \\cmd = "echo build-dev"
        \\
        \\[tasks.build-prod]
        \\cmd = "echo build-prod"
        \\
        \\[tasks.test-unit]
        \\cmd = "echo test-unit"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run build-prod twice to make it most frequent
    for (0..2) |_| {
        var r = try runZr(allocator, &.{ "--config", config, "run", "build-prod" }, tmp_path);
        defer r.deinit();
    }

    // list "build" --sort=freq: only build tasks, sorted by frequency
    var result = try runZr(allocator, &.{ "--config", config, "list", "build", "--sort=freq" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // test-unit should not appear (filtered out by "build" pattern)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test-unit") == null);
    // Both build tasks should appear
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build-prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build-dev") != null);
    // build-prod (2 runs) should appear before build-dev (0 runs)
    const prod_pos = std.mem.indexOf(u8, result.stdout, "build-prod") orelse return error.NotFound;
    const dev_pos = std.mem.indexOf(u8, result.stdout, "build-dev") orelse return error.NotFound;
    try std.testing.expect(prod_pos < dev_pos);
}
