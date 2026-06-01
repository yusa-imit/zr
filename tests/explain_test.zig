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

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Must mention "required" — the exact phrase from the error message
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "required") != null);
    // Must not print a successful plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Execution plan") == null);
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

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Must say "not found" and mention the task name
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "nonexistent") != null);
    // Must not print a successful plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Execution plan") == null);
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

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check task count in header
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tasks to run (3)") != null);
    // Verify each task appears at its numbered step — setup first, build last
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[1] setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[2] generate") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[3] build") != null);
    // Step markers must appear in ascending order
    const s1 = std.mem.indexOf(u8, result.stdout, "[1]").?;
    const s2 = std.mem.indexOf(u8, result.stdout, "[2]").?;
    const s3 = std.mem.indexOf(u8, result.stdout, "[3]").?;
    try std.testing.expect(s1 < s2);
    try std.testing.expect(s2 < s3);
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

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Must contain JSON structure keys
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"tasks\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"total\"") != null);
    // Must contain all three task names as JSON string literals
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"setup\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"generate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"build\"") != null);
    // Must show total=3
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"total\":3") != null);
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

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify task count
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tasks to run (4)") != null);
    // Topological order via section headers: install first, package last
    // install has no deps → [1]; configure depends on install → [2]; compile → [3]; package → [4]
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[1] install") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[2] configure") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[3] compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[4] package") != null);
    // Step markers must be in order
    const s1 = std.mem.indexOf(u8, result.stdout, "[1]").?;
    const s2 = std.mem.indexOf(u8, result.stdout, "[2]").?;
    const s3 = std.mem.indexOf(u8, result.stdout, "[3]").?;
    const s4 = std.mem.indexOf(u8, result.stdout, "[4]").?;
    try std.testing.expect(s1 < s2);
    try std.testing.expect(s2 < s3);
    try std.testing.expect(s3 < s4);
}

test "15008: zr explain task-with-deps --tree shows recursive dependency structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, TASK_WITH_DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "build", "--tree" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Root task at top level (no connector prefix)
    try std.testing.expect(std.mem.startsWith(u8, result.stdout, "build\n"));
    // Direct deps of build shown with tree connectors
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "├── setup") != null or
        std.mem.indexOf(u8, result.stdout, "└── setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "└── generate") != null);
    // generate's transitive dep on setup shown recursively
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "already shown") != null);
}
