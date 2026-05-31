const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Test Fixtures ──────────────────────────────────────────────────────

const BASIC_VARS_TOML =
    \\[vars]
    \\build_dir = "dist"
    \\
    \\[tasks.build]
    \\cmd = "echo building to {{build_dir}}"
    \\
;

const VARS_IN_ENV_TOML =
    \\[vars]
    \\node_version = "20"
    \\
    \\[tasks.publish]
    \\env = { VERSION = "{{node_version}}" }
    \\cmd = "echo version is $VERSION"
    \\
;

// Note: cwd substitution test uses a subdir created by a preceding dep task
const VARS_IN_CWD_TOML_FMT =
    \\[vars]
    \\work_subdir = "mysubdir"
    \\
    \\[tasks.prepare]
    \\cmd = "mkdir -p mysubdir"
    \\
    \\[tasks.work]
    \\deps = ["prepare"]
    \\cwd = "{{work_subdir}}"
    \\cmd = "pwd"
    \\
;

const UNDEFINED_VAR_TOML =
    \\[tasks.undefined]
    \\cmd = "echo undefined: {{UNDEFINED}}"
    \\
;

const EMPTY_VARS_TOML =
    \\[vars]
    \\
    \\[tasks.hello]
    \\cmd = "echo hello"
    \\
;

const RUNTIME_OVERRIDE_TOML =
    \\[vars]
    \\key = "default"
    \\
    \\[tasks.show]
    \\cmd = "echo value={{key}}"
    \\
;

const MULTIPLE_VARS_TOML =
    \\[vars]
    \\first = "one"
    \\second = "two"
    \\
    \\[tasks.multi]
    \\cmd = "echo {{first}} and {{second}}"
    \\
;

const NO_PLACEHOLDERS_TOML =
    \\[vars]
    \\unused = "value"
    \\
    \\[tasks.simple]
    \\cmd = "echo simple task"
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "14000: vars: basic substitution in cmd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, BASIC_VARS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain the substituted value "dist"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dist") != null);
}

test "14001: vars: substitution in env values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, VARS_IN_ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "publish" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // The env var VERSION should have been substituted with "20"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "version is 20") != null);
}

test "14002: vars: substitution in cwd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, VARS_IN_CWD_TOML_FMT);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "work" }, tmp_path);
    defer result.deinit();

    // Task should succeed: mkdir created the subdir, then work ran with cwd=mysubdir
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // pwd output should contain "mysubdir" (the substituted cwd value)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "mysubdir") != null);
}

test "14003: vars: undefined variable left as-is" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, UNDEFINED_VAR_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "undefined" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Undefined variable should remain as literal "{{UNDEFINED}}"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{{UNDEFINED}}") != null);
}

test "14004: vars: empty [vars] section works normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, EMPTY_VARS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();

    // Empty [vars] should not break task execution
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "14005: vars: runtime param overrides var with same name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, RUNTIME_OVERRIDE_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with runtime param key=override to override the default var value
    var result = try runZr(allocator, &.{ "--config", config, "run", "show", "key=override" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should show the runtime param value "override", not the var default "default"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value=override") != null);
    // Verify the default value is NOT in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value=default") == null);
}

test "14006: vars: multiple vars in single cmd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, MULTIPLE_VARS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "multi" }, tmp_path);
    defer result.deinit();

    // Command should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both substituted values should appear in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "one") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "two") != null);
}

test "14007: vars: var with no tasks uses no {{}} placeholders" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, NO_PLACEHOLDERS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "simple" }, tmp_path);
    defer result.deinit();

    // Unused vars should not break task execution
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "simple task") != null);
}

test "14008: vars: validate works when [vars] precedes [tasks]" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[vars]
        \\build_dir = "dist"
        \\
        \\[tasks.build]
        \\cmd = "echo building to {{build_dir}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Bug regression: parser was not resetting in_vars when entering [tasks.X],
    // causing cmd field to be parsed as a vars entry instead of a task field.
    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "valid") != null);
    // Must NOT report "must have cmd or deps" error
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "must have") == null);
}
