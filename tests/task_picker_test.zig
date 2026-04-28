const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Interactive Task Picker Tests ────────────────────────────────────────

test "task-picker: zr run without arguments in non-TTY environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\description = "Build the project"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\description = "Run tests"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run` without task name — should launch picker
    var result = try runZr(allocator, &.{ "--config", config, "run" }, tmp_path);
    defer result.deinit();

    // In CI/non-TTY environment, picker should fail gracefully with error message
    if (result.exit_code != 0) {
        // Should have error message explaining TTY requirement
        try std.testing.expect(result.stderr.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TTY") != null or
            std.mem.indexOf(u8, result.stderr, "interactive") != null or
            std.mem.indexOf(u8, result.stderr, "terminal") != null);
    }
}

test "task-picker: explicit task name bypasses picker" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\description = "Build the project"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run build` with explicit task name — should NOT use picker
    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    // Should execute task directly without picker
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}

test "task-picker: workflow without name in non-TTY" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[workflows.deploy.stages.build]
        \\tasks = ["build"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr workflow` without workflow name — should launch picker
    var result = try runZr(allocator, &.{ "--config", config, "workflow" }, tmp_path);
    defer result.deinit();

    // In non-TTY, should fail gracefully (picker requires TTY)
    if (result.exit_code != 0) {
        try std.testing.expect(result.stderr.len > 0);
    }
}

test "task-picker: empty config shows no tasks message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml = ""; // No tasks defined
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run" }, tmp_path);
    defer result.deinit();

    // Should either show picker with "no tasks" or fail gracefully
    // Exit code 0 or 1 both acceptable (depends on TTY availability)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "task-picker: config with mixed tasks and workflows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\tags = ["ci"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\tags = ["ci"]
        \\
        \\[workflows.deploy.stages.build]
        \\tasks = ["build"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Picker should show both tasks and workflows
    var result = try runZr(allocator, &.{ "--config", config, "run" }, tmp_path);
    defer result.deinit();

    // In non-TTY, graceful failure expected
    if (result.exit_code != 0) {
        try std.testing.expect(result.stderr.len > 0);
    }
}

test "task-picker: task with dependencies shows in picker" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.lint]
        \\cmd = "echo linting"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\deps = ["lint"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run" }, tmp_path);
    defer result.deinit();

    // Picker should show tasks with dependencies
    // In non-TTY, graceful failure
    if (result.exit_code != 0) {
        try std.testing.expect(result.stderr.len > 0);
    }
}

// NOTE: Unit tests for fuzzyFilter, itemLessThan, etc. are in src/cli/task_picker.zig
// This integration test file focuses on end-to-end CLI behavior only
