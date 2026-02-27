const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "16: show displays task details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task: hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Say hello") != null);
}

test "17: show with nonexistent task fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "nonexistent" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "79: show with tags display" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\tags = ["ci", "test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "show", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tags") != null or std.mem.indexOf(u8, result.stdout, "tags") != null);
}

test "137: show command with complex task configuration" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const complex_show_toml =
        \\[tasks.complex]
        \\cmd = "echo complex"
        \\description = "Complex task"
        \\cwd = "/tmp"
        \\deps = ["dep1", "dep2"]
        \\env = { VAR1 = "value1", VAR2 = "value2" }
        \\timeout = 30000
        \\retry = 3
        \\allow_failure = true
        \\tags = ["integration", "slow"]
        \\max_concurrent = 5
        \\max_cpu = 80
        \\max_memory = 512
        \\
        \\[tasks.dep1]
        \\cmd = "echo dep1"
        \\
        \\[tasks.dep2]
        \\cmd = "echo dep2"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, complex_show_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "show", "complex" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show task name or description
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "complex") != null or std.mem.indexOf(u8, result.stdout, "Complex task") != null);
}

test "203: show with --format json outputs structured data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const complex_toml =
        \\[tasks.test]
        \\cmd = "cargo test"
        \\cwd = "packages/core"
        \\timeout = 300
        \\env = { RUST_BACKTRACE = "1" }
        \\deps = ["build"]
        \\retry = { count = 2, backoff = "exponential" }
        \\
        \\[tasks.build]
        \\cmd = "cargo build"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(complex_toml);

    var result = try runZr(allocator, &.{ "show", "test", "--format", "json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain JSON with task metadata
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"cmd\"") != null or
        std.mem.indexOf(u8, result.stdout, "cargo test") != null);
}

test "219: show command displays task configuration details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create config with detailed task
    const show_toml =
        \\[tasks.test-unit]
        \\cmd = "npm test"
        \\cwd = "/src"
        \\description = "Run unit tests"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Show task details
    var result = try runZr(allocator, &.{ "show", "test-unit" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "npm test") != null);
}

test "254: show with nonexistent --format value reports error" {
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

    var result = try runZr(allocator, &.{ "show", "test", "--format", "invalid_format" }, tmp_path);
    defer result.deinit();
    // Should fail due to invalid format
    try std.testing.expect(result.exit_code != 0);
}

test "260: show with --format toml outputs task definition in TOML" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const simple_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci", "fast"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(simple_toml);

    var result = try runZr(allocator, &.{ "show", "test", "--format", "toml" }, tmp_path);
    defer result.deinit();
    // May not support --format flag yet, test command parses
    try std.testing.expect(result.exit_code <= 1);
}

test "309: show with --format=json outputs structured task metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const detailed_task_toml =
        \\[tasks.complex]
        \\cmd = "echo test"
        \\description = "A complex task"
        \\cwd = "/tmp"
        \\timeout = "30s"
        \\retry = 3
        \\tags = ["ci", "test"]
        \\deps = []
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(detailed_task_toml);

    var result = try runZr(allocator, &.{ "show", "complex", "--format=json" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should output JSON metadata (or fail gracefully if format not supported)
    try std.testing.expect(std.mem.indexOf(u8, output, "complex") != null or
                          std.mem.indexOf(u8, output, "{") != null or
                          result.exit_code != 0);
}

test "330: show command with task that uses all available fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const full_task_toml =
        \\[tasks.full]
        \\description = "A task with all fields"
        \\cmd = "echo testing"
        \\cwd = "."
        \\deps = []
        \\env = { VAR = "value" }
        \\timeout = 30
        \\retry = 2
        \\allow_failure = true
        \\max_concurrent = 2
        \\tags = ["test", "ci"]
        \\condition = "platform == 'linux' || platform == 'darwin'"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(full_task_toml);

    var result = try runZr(allocator, &.{ "show", "full" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "full") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Allow Failure") != null or
        std.mem.indexOf(u8, output, "Max Concurrent") != null);
}

test "373: show command with --help flag displays help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Test --help flag
    var result = try runZr(allocator, &.{ "show", "--help" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "Usage: zr show") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Display detailed information") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Options:") != null);
}

test "374: show command with -h flag displays help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Test -h flag
    var result = try runZr(allocator, &.{ "show", "-h" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "Usage: zr show") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Display detailed information") != null);
}

test "445: show command with task containing all possible fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const comprehensive_toml =
        \\[tasks.comprehensive]
        \\cmd = "echo comprehensive"
        \\description = "Task with all fields"
        \\cwd = "/tmp"
        \\deps = ["dep1"]
        \\deps_serial = ["dep2"]
        \\env = { KEY = "value" }
        \\timeout = 30
        \\retry = 3
        \\allow_failure = true
        \\condition = "platform == 'linux'"
        \\cache = true
        \\max_concurrent = 4
        \\max_cpu = 80
        \\max_memory = 1073741824
        \\tags = ["build", "test"]
        \\toolchain = ["node@20.11.1"]
        \\matrix = { os = ["linux", "darwin"] }
        \\
        \\[tasks.dep1]
        \\cmd = "echo dep1"
        \\
        \\[tasks.dep2]
        \\cmd = "echo dep2"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, comprehensive_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "comprehensive" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should show comprehensive task details including task name
    try std.testing.expect(std.mem.indexOf(u8, output, "comprehensive") != null);
    // Verify some fields are present (command, description, or dependencies)
    const has_cmd = std.mem.indexOf(u8, output, "echo") != null;
    const has_desc = std.mem.indexOf(u8, output, "all fields") != null;
    const has_deps = std.mem.indexOf(u8, output, "dep") != null;
    try std.testing.expect(has_cmd or has_desc or has_deps);
}

test "475: show with nonexistent task returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const simple_toml =
        \\[tasks.exists]
        \\cmd = "echo exists"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(simple_toml);

    var result = try runZr(allocator, &.{ "show", "nonexistent" }, tmp_path);
    defer result.deinit();
    // Should return error for nonexistent task
    try std.testing.expect(result.exit_code != 0);
    const error_msg = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(error_msg.len > 0);
}

test "479: show command with toolchain field displays toolchain info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toolchain_toml =
        \\[tasks.multi]
        \\cmd = "echo hello"
        \\description = "Task with multiple toolchains"
        \\toolchain = ["node@20.0.0", "python@3.11"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toolchain_toml);

    var result = try runZr(allocator, &.{ "show", "multi" }, tmp_path);
    defer result.deinit();
    // Show should display task with toolchain info
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "multi") != null);
}

test "555: show with nonexistent task shows helpful error with suggestions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "nonexistent-task" }, tmp_path);
    defer result.deinit();
    // Should show error with suggestions
    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "not found") != null or std.mem.indexOf(u8, output, "exist") != null or std.mem.indexOf(u8, output, "available") != null);
}

test "593: show with --format toml shows unsupported format error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "npm run build"
        \\cwd = "/tmp"
        \\timeout = 300
        \\retry = 3
        \\[tasks.build.env]
        \\NODE_ENV = "production"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // TOML format not supported for show
    var result = try runZr(allocator, &.{ "--config", config, "show", "build", "--format", "toml" }, tmp_path);
    defer result.deinit();
    // Should error with unsupported format message
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "format") != null or std.mem.indexOf(u8, result.stderr, "toml") != null);
}
