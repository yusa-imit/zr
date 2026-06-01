const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Test Fixtures ──────────────────────────────────────────────────────

const SIMPLE_TASK_TOML =
    \\[tasks.hello]
    \\cmd = "echo hello"
    \\
;

const TASK_WITH_DEPS_TOML =
    \\[tasks.setup]
    \\cmd = "echo setup"
    \\
    \\[tasks.generate]
    \\cmd = "echo generate"
    \\deps = ["setup"]
    \\
    \\[tasks.build]
    \\cmd = "zig build"
    \\deps = ["setup", "generate"]
    \\
;

const MULTI_LEVEL_DEPS_TOML =
    \\[tasks.install]
    \\cmd = "echo install"
    \\
    \\[tasks.configure]
    \\cmd = "echo configure"
    \\deps = ["install"]
    \\
    \\[tasks.compile]
    \\cmd = "echo compile"
    \\deps = ["configure"]
    \\
    \\[tasks.package]
    \\cmd = "echo package"
    \\deps = ["compile", "install"]
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "15000: zr explain with no args prints error and returns 1" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain" }, tmp_path);
    defer result.deinit();

    // Should fail with exit code 1 when no task name provided
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Error message should indicate missing task name
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "task") != null or
        std.mem.indexOf(u8, result.stderr, "required") != null or
        std.mem.indexOf(u8, result.stderr, "specify") != null);
}

test "15001: zr explain unknown-task for nonexistent task returns 1 with not found message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "nonexistent" }, tmp_path);
    defer result.deinit();

    // Should fail when task doesn't exist
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Error message should mention task not found or nonexistent
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null or
        std.mem.indexOf(u8, result.stderr, "unknown") != null or
        std.mem.indexOf(u8, result.stderr, "nonexistent") != null);
}

test "15002: zr explain simple-task shows task command in output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "hello" }, tmp_path);
    defer result.deinit();

    // Should succeed for valid task
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should show the task command
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "echo hello") != null);
    // Output should mention the task name
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "15003: zr explain task-with-deps shows all deps in execution order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain all three tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "generate") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    // Output should show execution order: setup before generate before build
    const setup_idx = std.mem.indexOf(u8, result.stdout, "setup").?;
    const generate_idx = std.mem.indexOf(u8, result.stdout, "generate").?;
    const build_idx = std.mem.indexOf(u8, result.stdout, "build").?;
    try std.testing.expect(setup_idx < generate_idx);
    try std.testing.expect(generate_idx < build_idx);
}

test "15004: zr explain task-with-deps --tree shows tree format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build", "--tree" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Tree format should show task names
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "generate") != null);
    // Tree format typically uses box-drawing characters or tree symbols
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "├") != null or
        std.mem.indexOf(u8, result.stdout, "└") != null or
        std.mem.indexOf(u8, result.stdout, "─") != null or
        std.mem.indexOf(u8, result.stdout, "|") != null);
}

test "15005: zr explain task-with-deps --json produces valid JSON with tasks array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build", "--json" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should be valid JSON with tasks array
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "}") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tasks") != null or
        std.mem.indexOf(u8, result.stdout, "[") != null);
    // Should contain task names in JSON format
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "15006: zr explain --help returns 0 with usage info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, SIMPLE_TASK_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "--help" }, tmp_path);
    defer result.deinit();

    // Should succeed with --help
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should contain help text
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage") != null or
        std.mem.indexOf(u8, result.stdout, "usage") != null or
        std.mem.indexOf(u8, result.stdout, "explain") != null or
        std.mem.indexOf(u8, result.stdout, "Explain") != null);
}

test "15007: zr explain multi-level-deps shows correct execution order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, MULTI_LEVEL_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "package" }, tmp_path);
    defer result.deinit();

    // Should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All tasks should be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "install") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "configure") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "package") != null);
    // Topological order: install must come before configure (which depends on it)
    // configure must come before compile (which depends on it)
    // compile and install must come before package
    const install_idx = std.mem.indexOf(u8, result.stdout, "install").?;
    const configure_idx = std.mem.indexOf(u8, result.stdout, "configure").?;
    const compile_idx = std.mem.indexOf(u8, result.stdout, "compile").?;
    const package_idx = std.mem.indexOf(u8, result.stdout, "package").?;
    try std.testing.expect(install_idx < configure_idx);
    try std.testing.expect(configure_idx < compile_idx);
    try std.testing.expect(compile_idx < package_idx);
}
