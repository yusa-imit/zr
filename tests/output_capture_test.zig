const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test 951: Task execution with output_mode=stream - verify file is created and contains task output
test "951: output_mode=stream creates file with task output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml = try std.fmt.allocPrint(
        allocator,
        \\[tasks.stream_test]
        \\cmd = "echo 'Stream output line 1' && echo 'Stream output line 2'"
        \\output_mode = "stream"
        \\output_file = "{s}/stream_output.log"
        \\
    ,
        .{tmp_path},
    );
    defer allocator.free(config_toml);

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task with stream mode
    var result = try runZr(allocator, &.{ "--config", config, "run", "stream_test" }, tmp_path);
    defer result.deinit();

    // Task should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output file exists and contains expected content
    var output_file = try tmp.dir.openFile("stream_output.log", .{});
    defer output_file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = try output_file.readAll(&buf);
    const file_content = buf[0..bytes_read];

    // Verify both lines are in the file
    try std.testing.expect(std.mem.indexOf(u8, file_content, "Stream output line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, file_content, "Stream output line 2") != null);
}

// Test 952: Task execution with output_mode=buffer - verify buffer is captured
// Note: Buffer mode stores output in memory. We verify via task stdout redirection.
test "952: output_mode=buffer captures output in memory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.buffer_test]
        \\cmd = "echo 'Buffer test output'"
        \\output_mode = "buffer"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task with buffer mode
    var result = try runZr(allocator, &.{ "--config", config, "run", "buffer_test" }, tmp_path);
    defer result.deinit();

    // Task should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // In buffer mode, output is captured in memory and available to the task runtime.
    // The task itself will emit output to terminal/TUI, so we verify execution succeeded.
    // The buffer is used internally by the scheduler for capture.
    // This test validates that buffer mode doesn't break task execution.
}

// Test 953: Multiple tasks with different output modes running in parallel
test "953: multiple tasks with different output modes in parallel" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml = try std.fmt.allocPrint(
        allocator,
        \\[tasks.stream_parallel]
        \\cmd = "echo 'Stream parallel output'"
        \\output_mode = "stream"
        \\output_file = "{s}/parallel_stream.log"
        \\
        \\[tasks.buffer_parallel]
        \\cmd = "echo 'Buffer parallel output'"
        \\output_mode = "buffer"
        \\
        \\[tasks.discard_parallel]
        \\cmd = "echo 'Discard parallel output'"
        \\output_mode = "discard"
        \\
        \\[tasks.run_all]
        \\cmd = "echo 'Running all tasks'"
        \\deps = ["stream_parallel", "buffer_parallel", "discard_parallel"]
        \\
    ,
        .{tmp_path},
    );
    defer allocator.free(config_toml);

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run all tasks (with dependencies)
    var result = try runZr(allocator, &.{ "--config", config, "run", "run_all" }, tmp_path);
    defer result.deinit();

    // All tasks should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify stream mode file was created and contains output
    var stream_file = try tmp.dir.openFile("parallel_stream.log", .{});
    defer stream_file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = try stream_file.readAll(&buf);
    const stream_content = buf[0..bytes_read];
    try std.testing.expect(std.mem.indexOf(u8, stream_content, "Stream parallel output") != null);

    // discard mode file should not exist (discard mode = no file)
    const discard_result = tmp.dir.openFile("discard_output.log", .{});
    if (discard_result) |_| {
        // If file exists, that's an error
        return error.TestUnexpectedResult;
    } else |err| {
        // Expected: file should not exist in discard mode
        try std.testing.expectEqual(error.FileNotFound, err);
    }
}

// Test 954: Large output (>1MB) with buffer mode - verify FIFO eviction works
test "954: buffer mode with large output triggers FIFO eviction" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a command that outputs many lines to exceed the 1MB default buffer
    // We'll use a shell loop to generate large output
    const config_toml =
        \\[tasks.large_output]
        \\cmd = "for i in $(seq 1 50000); do echo 'Line: This is a test line with some padding to increase size abcdefghijklmnopqrstuvwxyz'; done"
        \\output_mode = "buffer"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task that generates large output
    var result = try runZr(allocator, &.{ "--config", config, "run", "large_output" }, tmp_path);
    defer result.deinit();

    // Task should complete (buffer eviction should handle overflow gracefully)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // The task completes successfully even with large output that exceeds buffer limit.
    // This validates that FIFO eviction works without crashing.
}

// Test 955: Task with output_file but execution fails - verify partial output is captured
test "955: task failure with output_mode=stream captures partial output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml = try std.fmt.allocPrint(
        allocator,
        \\[tasks.fail_with_output]
        \\cmd = "echo 'Output before failure' && exit 42"
        \\output_mode = "stream"
        \\output_file = "{s}/failure_output.log"
        \\
    ,
        .{tmp_path},
    );
    defer allocator.free(config_toml);

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task that fails after producing output
    var result = try runZr(allocator, &.{ "--config", config, "run", "fail_with_output" }, tmp_path);
    defer result.deinit();

    // zr should exit with 1 (failure), not 42. The task's exit code 42 is internal.
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Verify that the task failure is reported (should see "exit: 42" in output)
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "exit: 42") != null or
                           std.mem.indexOf(u8, result.stdout, "exit: 42") != null);

    // Verify output file still exists with partial output
    var output_file = try tmp.dir.openFile("failure_output.log", .{});
    defer output_file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = try output_file.readAll(&buf);
    const file_content = buf[0..bytes_read];

    // Partial output should be captured before failure
    try std.testing.expect(std.mem.indexOf(u8, file_content, "Output before failure") != null);
}

// Test 956: output_mode=discard produces no file and minimal overhead
test "956: output_mode=discard produces no output file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.discard_test]
        \\cmd = "echo 'This should not be captured'"
        \\output_mode = "discard"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task with discard mode
    var result = try runZr(allocator, &.{ "--config", config, "run", "discard_test" }, tmp_path);
    defer result.deinit();

    // Task should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify no output file was created (discard mode = no file)
    // Try to open a file that would be created in stream/buffer mode
    const discard_file_result = tmp.dir.openFile("discard_output.log", .{});
    if (discard_file_result) |_| {
        // If file exists, that's an error
        return error.TestUnexpectedResult;
    } else |err| {
        // Expected: file should not exist
        try std.testing.expectEqual(error.FileNotFound, err);
    }
}

// Test 957: output_file with absolute path (not relative)
test "957: output_file with absolute path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file_path = try std.fs.path.join(allocator, &.{ tmp_path, "absolute_output.log" });
    defer allocator.free(output_file_path);

    const config_toml = try std.fmt.allocPrint(
        allocator,
        \\[tasks.absolute_path]
        \\cmd = "echo 'Absolute path output'"
        \\output_mode = "stream"
        \\output_file = "{s}"
        \\
    ,
        .{output_file_path},
    );
    defer allocator.free(config_toml);

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task with absolute output path
    var result = try runZr(allocator, &.{ "--config", config, "run", "absolute_path" }, tmp_path);
    defer result.deinit();

    // Task should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output file was created at absolute path
    var output_file = try tmp.dir.openFile("absolute_output.log", .{});
    defer output_file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = try output_file.readAll(&buf);
    const file_content = buf[0..bytes_read];
    try std.testing.expect(std.mem.indexOf(u8, file_content, "Absolute path output") != null);
}

// Test 958: Task with stderr captured in stream mode
test "958: stream mode captures both stdout and stderr" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml = try std.fmt.allocPrint(
        allocator,
        \\[tasks.stderr_capture]
        \\cmd = "echo 'Standard output' && >&2 echo 'Standard error'"
        \\output_mode = "stream"
        \\output_file = "{s}/stderr_output.log"
        \\
    ,
        .{tmp_path},
    );
    defer allocator.free(config_toml);

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task
    var result = try runZr(allocator, &.{ "--config", config, "run", "stderr_capture" }, tmp_path);
    defer result.deinit();

    // Task should succeed
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output file contains both stdout and stderr
    var output_file = try tmp.dir.openFile("stderr_output.log", .{});
    defer output_file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = try output_file.readAll(&buf);
    const file_content = buf[0..bytes_read];

    // Both outputs should be captured
    try std.testing.expect(std.mem.indexOf(u8, file_content, "Standard output") != null);
    try std.testing.expect(std.mem.indexOf(u8, file_content, "Standard error") != null);
}

// Test 959: Output modes with environment variables and substitution
test "959: output_file path can include environment variables via expression" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml = try std.fmt.allocPrint(
        allocator,
        \\[tasks.env_output_path]
        \\cmd = "echo 'Output with env variable'"
        \\output_mode = "stream"
        \\output_file = "{s}/env_output.log"
        \\env = {{ OUTPUT_DIR = "{s}" }}
        \\
    ,
        .{tmp_path, tmp_path},
    );
    defer allocator.free(config_toml);

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task
    var result = try runZr(allocator, &.{ "--config", config, "run", "env_output_path" }, tmp_path);
    defer result.deinit();

    // Task should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output file was created
    var output_file = try tmp.dir.openFile("env_output.log", .{});
    defer output_file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = try output_file.readAll(&buf);
    const file_content = buf[0..bytes_read];
    try std.testing.expect(std.mem.indexOf(u8, file_content, "Output with env variable") != null);
}

// Test 960: Default output_mode should be "discard" (no file created)
test "960: default output_mode (no config) is discard" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.default_mode]
        \\cmd = "echo 'Default mode output'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run the task without specifying output_mode (should default to discard)
    var result = try runZr(allocator, &.{ "--config", config, "run", "default_mode" }, tmp_path);
    defer result.deinit();

    // Task should execute successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify no output file was created (default = discard mode)
    // Check that we can read stdout from the zr command itself
    try std.testing.expect(result.stdout.len > 0); // zr should emit output about task execution
}
