const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Shell-Evaluated Variables Tests ────────────────────────────────────────
//
// Tests for `VERSION = {cmd = "..."}` syntax in [vars] section (v1.102.0+):
//
// 31000: Basic cmd var — execute shell command and use stdout
// 31001: Static + cmd vars together — mix static strings and cmd vars in [vars]
// 31002: on_error = "empty" (default) — failed cmd results in empty string
// 31003: on_error = "fail" — failed cmd causes config load failure with exit 1
// 31004: Cmd var in task env field — variable evaluated before env substitution
// 31005: Cmd var with whitespace trimming — leading/trailing spaces removed from output
//

const BASIC_CMD_VAR_TOML =
    \\[vars]
    \\VERSION = {cmd = "echo v1.2.3"}
    \\
    \\[tasks.show_version]
    \\cmd = "echo VERSION={{VERSION}}"
    \\
;

const STATIC_AND_CMD_VARS_TOML =
    \\[vars]
    \\STATIC = "hello"
    \\CMD = {cmd = "echo world"}
    \\
    \\[tasks.combined]
    \\cmd = "echo {{STATIC}} {{CMD}}"
    \\
;

const ON_ERROR_EMPTY_TOML =
    \\[vars]
    \\FAIL_VAR = {cmd = "false"}
    \\
    \\[tasks.show_fail]
    \\cmd = "echo result=[{{FAIL_VAR}}]"
    \\
;

const ON_ERROR_FAIL_TOML =
    \\[vars]
    \\FAIL_VAR = {cmd = "false", on_error = "fail"}
    \\
    \\[tasks.show_fail]
    \\cmd = "echo result"
    \\
;

const CMD_VAR_IN_ENV_TOML =
    \\[vars]
    \\DB_URL = {cmd = "echo localhost:5432"}
    \\
    \\[tasks.connect]
    \\env = {CONN = "{{DB_URL}}"}
    \\cmd = "echo database=$CONN"
    \\
;

const CMD_VAR_WITH_WHITESPACE_TOML =
    \\[vars]
    \\VALUE = {cmd = "echo '  spaced  '"}
    \\
    \\[tasks.show_trimmed]
    \\cmd = "echo trimmed=[{{VALUE}}]"
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "31000: basic cmd var — execute shell command and use stdout" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, BASIC_CMD_VAR_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show_version" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain the cmd var value "v1.2.3" (not literal {cmd=...})
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "v1.2.3") != null);
    // Verify it actually substituted and ran the command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "VERSION=v1.2.3") != null);
}

test "31001: static + cmd vars together — mix static strings and cmd vars in same [vars]" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, STATIC_AND_CMD_VARS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "combined" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain both STATIC value "hello" and CMD value "world"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "world") != null);
    // Verify they appear together in the output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello world") != null);
}

test "31002: on_error = empty (default) — failed cmd results in empty string var" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ON_ERROR_EMPTY_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show_fail" }, tmp_path);
    defer result.deinit();

    // Even though the cmd failed, the task should run with empty var (on_error default = "empty")
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should show result=[] (empty value between brackets)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "result=[]") != null);
}

test "31003: on_error = fail — failed cmd causes config load failure with exit 1" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ON_ERROR_FAIL_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show_fail" }, tmp_path);
    defer result.deinit();

    // Config loading should fail because on_error="fail" and the cmd failed
    try std.testing.expect(result.exit_code != 0);
    // Error message should mention the failed command or variable evaluation
    const combined = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "false") != null or
        std.mem.indexOf(u8, combined, "FAIL_VAR") != null or
        std.mem.indexOf(u8, combined, "error") != null);
}

test "31004: cmd var in task env field — variable evaluated before env substitution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, CMD_VAR_IN_ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "connect" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // The env var CONN should receive the substituted value from DB_URL cmd var
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "database=localhost:5432") != null);
}

test "31005: cmd var with whitespace trimming — leading/trailing spaces removed" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, CMD_VAR_WITH_WHITESPACE_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show_trimmed" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // The VALUE should be trimmed to "spaced" (no leading/trailing whitespace)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "trimmed=[spaced]") != null);
    // Verify that leading/trailing spaces are NOT present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "  spaced  ") == null);
}
