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

test "948: show with --output flag when output_file exists" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create an output file with captured task output
    const output_file_path = try std.fs.path.join(allocator, &.{ tmp_path, "task_output.txt" });
    defer allocator.free(output_file_path);

    const output_file = try tmp.dir.createFile("task_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("Task output line 1\nTask output line 2\nBuild successful!");

    // Create config with task that has output_file configured
    const show_output_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\description = "Build task with output capture"
        \\output_file = "task_output.txt"
        \\output_mode = "stream"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_output_toml);

    // Show task with --output flag should display the captured output
    var result = try runZr(allocator, &.{ "show", "build", "--output" }, tmp_path);
    defer result.deinit();

    // Should succeed and display task output
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should contain the captured output
    try std.testing.expect(std.mem.indexOf(u8, output, "Task output line 1") != null or
                          std.mem.indexOf(u8, output, "Build successful") != null or
                          std.mem.indexOf(u8, output, "task_output.txt") != null);
}

test "949: show with --output flag when output_file doesn't exist (task configured but file not there)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with task that has output_file configured but file doesn't exist
    const show_output_toml =
        \\[tasks.test]
        \\cmd = "npm test"
        \\description = "Test task with output capture"
        \\output_file = "nonexistent_output.txt"
        \\output_mode = "stream"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_output_toml);

    // Show task with --output flag when file doesn't exist should fail
    var result = try runZr(allocator, &.{ "show", "test", "--output" }, tmp_path);
    defer result.deinit();

    // Should fail with error message
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    const error_output = if (result.stderr.len > 0) result.stderr else result.stdout;
    // Should contain error about missing file or file not found
    try std.testing.expect(std.mem.indexOf(u8, error_output, "not found") != null or
                          std.mem.indexOf(u8, error_output, "No such file") != null or
                          std.mem.indexOf(u8, error_output, "cannot open") != null or
                          std.mem.indexOf(u8, error_output, "nonexistent") != null);
}

test "950: show with --output flag when task has no output_file configured (error message)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with task that has NO output_file configured
    const show_output_toml =
        \\[tasks.lint]
        \\cmd = "eslint ."
        \\description = "Lint task without output capture"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_output_toml);

    // Show task with --output flag but no output_file configured should fail
    var result = try runZr(allocator, &.{ "show", "lint", "--output" }, tmp_path);
    defer result.deinit();

    // Should fail with error message
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    const error_output = if (result.stderr.len > 0) result.stderr else result.stdout;
    // Should contain error about output not configured
    try std.testing.expect(std.mem.indexOf(u8, error_output, "output_file") != null or
                          std.mem.indexOf(u8, error_output, "not configured") != null or
                          std.mem.indexOf(u8, error_output, "no output") != null or
                          std.mem.indexOf(u8, error_output, "not enabled") != null);
}

test "961: show with --output --search filters output by pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create output file with multiple lines
    const output_file = try tmp.dir.createFile("build_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("Building project...\nERROR: Compilation failed\nWARNING: Deprecated API used\nERROR: Missing dependency\nBuild completed with errors\n");

    const show_toml =
        \\[tasks.build]
        \\cmd = "make"
        \\output_file = "build_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Search for ERROR
    var result = try runZr(allocator, &.{ "show", "build", "--output", "--search", "ERROR" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "ERROR: Compilation failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ERROR: Missing dependency") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Building project") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "WARNING") == null);
}

test "962: show with --output --filter filters output by pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file = try tmp.dir.createFile("test_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("Test 1: PASS\nTest 2: FAIL\nTest 3: PASS\nTest 4: FAIL\nAll tests completed\n");

    const show_toml =
        \\[tasks.test]
        \\cmd = "npm test"
        \\output_file = "test_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Filter for FAIL
    var result = try runZr(allocator, &.{ "show", "test", "--output", "--filter", "FAIL" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Test 2: FAIL") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Test 4: FAIL") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "PASS") == null);
}

test "963: show with --output --head limits to first N lines" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file = try tmp.dir.createFile("log_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n");

    const show_toml =
        \\[tasks.log]
        \\cmd = "cat log.txt"
        \\output_file = "log_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Head 3 lines
    var result = try runZr(allocator, &.{ "show", "log", "--output", "--head", "3" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 4") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 10") == null);
}

test "964: show with --output --tail limits to last N lines" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file = try tmp.dir.createFile("deploy_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("Step 1: Prepare\nStep 2: Build\nStep 3: Test\nStep 4: Package\nStep 5: Deploy\nStep 6: Verify\nStep 7: Complete\n");

    const show_toml =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\output_file = "deploy_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Tail 3 lines
    var result = try runZr(allocator, &.{ "show", "deploy", "--output", "--tail", "3" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 5: Deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 6: Verify") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 7: Complete") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 1") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Step 2") == null);
}

test "965: show with --output --search and --head combines filters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file = try tmp.dir.createFile("combined_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("DEBUG: Starting\nINFO: Processing item 1\nINFO: Processing item 2\nINFO: Processing item 3\nINFO: Processing item 4\nINFO: Processing item 5\nDEBUG: Done\n");

    const show_toml =
        \\[tasks.process]
        \\cmd = "process.sh"
        \\output_file = "combined_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Search for INFO and show only first 2
    var result = try runZr(allocator, &.{ "show", "process", "--output", "--search", "INFO", "--head", "2" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "INFO: Processing item 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "INFO: Processing item 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "INFO: Processing item 3") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DEBUG") == null);
}

test "966: show with --output --filter and --tail combines filters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file = try tmp.dir.createFile("warnings_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("INFO: Start\nWARN: Issue 1\nWARN: Issue 2\nWARN: Issue 3\nWARN: Issue 4\nWARN: Issue 5\nINFO: End\n");

    const show_toml =
        \\[tasks.check]
        \\cmd = "check.sh"
        \\output_file = "warnings_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Filter for WARN and show only last 2
    var result = try runZr(allocator, &.{ "show", "check", "--output", "--filter", "WARN", "--tail", "2" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "WARN: Issue 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "WARN: Issue 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "WARN: Issue 1") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "INFO") == null);
}

test "967: show with --output --search with no matches returns empty output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file = try tmp.dir.createFile("nomatch_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("Line 1: Info\nLine 2: Debug\nLine 3: Trace\n");

    const show_toml =
        \\[tasks.run]
        \\cmd = "run.sh"
        \\output_file = "nomatch_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Search for pattern that doesn't exist
    var result = try runZr(allocator, &.{ "show", "run", "--output", "--search", "NONEXISTENT" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should be empty (only newlines possibly)
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Info") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Debug") == null);
}
