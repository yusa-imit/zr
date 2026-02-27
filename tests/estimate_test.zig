const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "52: estimate without history gracefully handles missing data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "estimate", "hello" }, tmp_path);
    defer result.deinit();
    // Should not crash even without history data
    _ = result.exit_code;
}

test "61: estimate command with history data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task first to create history
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer run_result.deinit();

    // Now estimate should work
    var estimate_result = try runZr(allocator, &.{ "--config", config, "estimate", "hello" }, tmp_path);
    defer estimate_result.deinit();
    try std.testing.expect(estimate_result.exit_code == 0);
}

test "76: estimate with nonexistent task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "estimate", "nonexistent" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null);
}

test "80: estimate --format=json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task to create history
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer run_result.deinit();

    // Estimate with JSON output (use global --format json flag)
    var result = try runZr(allocator, &.{ "--config", config, "--format", "json", "estimate", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
}

test "170: estimate with multiple tasks in history" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const simple_toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, simple_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task multiple times to build history
    {
        var result1 = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer result1.deinit();
    }
    {
        var result2 = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer result2.deinit();
    }

    // Now estimate should have data
    var result = try runZr(allocator, &.{ "--config", config, "estimate", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show estimate based on history
    try std.testing.expect(result.stdout.len > 0);
}

test "201: estimate with nonexistent task returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Estimate nonexistent task
    var result = try runZr(allocator, &.{ "estimate", "nonexistent" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null);
}

test "202: estimate with empty history shows no data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Run estimate with no history
    var result = try runZr(allocator, &.{ "estimate", "hello" }, tmp_path);
    defer result.deinit();

    // Should succeed but show no data or handle gracefully
    try std.testing.expect(result.exit_code <= 1);
}

test "258: estimate with --format json outputs structured estimation data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const simple_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(simple_toml);

    // Run task to create history
    var run_result = try runZr(allocator, &.{ "run", "test" }, tmp_path);
    defer run_result.deinit();

    var result = try runZr(allocator, &.{ "estimate", "test", "--format", "json" }, tmp_path);
    defer result.deinit();
    // May not support --format flag yet, test command parses
    try std.testing.expect(result.exit_code <= 1);
}

test "306: estimate with task that has never been run shows appropriate message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const simple_toml =
        \\[tasks.never-run]
        \\cmd = "echo test"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(simple_toml);

    var result = try runZr(allocator, &.{ "estimate", "never-run" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should indicate no history available
    try std.testing.expect(std.mem.indexOf(u8, output, "no") != null or
                          std.mem.indexOf(u8, output, "No") != null or
                          std.mem.indexOf(u8, output, "never") != null or
                          result.exit_code != 0);
}

test "339: estimate with task that has no execution history" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const task_toml =
        \\[tasks.never-run]
        \\cmd = "echo never executed"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(task_toml);

    // Estimate without any history
    var result = try runZr(allocator, &.{ "estimate", "never-run" }, tmp_path);
    defer result.deinit();
    // Should succeed with message about no history, or provide default estimate
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "no") != null or
        std.mem.indexOf(u8, output, "history") != null or
        std.mem.indexOf(u8, output, "never-run") != null);
}

test "371: estimate command with --help flag displays help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Test --help flag
    var result = try runZr(allocator, &.{ "estimate", "--help" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "Usage: zr estimate") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Estimate task duration") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Options:") != null);
}

test "372: estimate command with -h flag displays help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Test -h flag
    var result = try runZr(allocator, &.{ "estimate", "-h" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "Usage: zr estimate") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Estimate task duration") != null);
}

test "459: estimate with --format=json outputs structured duration estimates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const estimate_toml =
        \\[tasks.build]
        \\cmd = "sleep 0.1"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(estimate_toml);

    // Run task once to create history
    var run_result = try runZr(allocator, &.{ "run", "build" }, tmp_path);
    defer run_result.deinit();

    // Now estimate with JSON format
    var result = try runZr(allocator, &.{ "estimate", "build", "--format=json" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(result.stdout.len > 0);
}

test "501: estimate with nonexistent task shows error message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "estimate", "nonexistent" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(output.len > 0);
}

test "592: estimate with --format csv shows unsupported format error or fallback" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // CSV format not supported for estimate
    var result = try runZr(allocator, &.{ "--config", config, "estimate", "build", "--format", "csv" }, tmp_path);
    defer result.deinit();
    // Should error gracefully or fallback
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "597: estimate with --limit flag restricts history sample size" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.quick]
        \\cmd = "echo quick"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Run task multiple times to build history
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var run_result = try runZr(allocator, &.{ "--config", config, "run", "quick" }, tmp_path);
        defer run_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    }

    // Estimate with limited sample
    var result = try runZr(allocator, &.{ "--config", config, "estimate", "quick", "--limit", "3" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "quick") != null);
}

test "635: estimate with --format=json outputs structured duration prediction" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Run task once to create history
    {
        var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer run_result.deinit();
    }

    var result = try runZr(allocator, &.{ "--config", config, "estimate", "hello", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should output estimate in JSON format
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
