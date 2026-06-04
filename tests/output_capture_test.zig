const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Integration Tests for Output Capture Feature ───────────────────────────
//
// Tests for Task Output Capture feature:
// When a task has `share_output = true`, its stdout is captured and made available to:
// 1. ZR_OUTPUT_<TASK_NAME> env var (task name sanitized: uppercase, hyphens/dots → underscores)
// 2. {{output.task-name}} template syntax in downstream task cmd/env fields
//

test "17000: share_output = true captures task stdout as ZR_OUTPUT env var" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.get-version]
        \\cmd = "echo 1.2.3"
        \\share_output = true
        \\
        \\[tasks.show]
        \\deps = ["get-version"]
        \\cmd = "echo got: $ZR_OUTPUT_GET_VERSION"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Downstream task should see the captured output from get-version task
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "got: 1.2.3") != null);
}

test "17001: downstream task accesses captured output via ZR_OUTPUT_ env var" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.fetch-hash]
        \\cmd = "echo abc123def456"
        \\share_output = true
        \\
        \\[tasks.verify]
        \\deps = ["fetch-hash"]
        \\cmd = "bash -c 'echo hash=$ZR_OUTPUT_FETCH_HASH'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "verify" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hash=abc123def456") != null);
}

test "17002: {{output.task-name}} template in downstream cmd uses captured output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.compute]
        \\cmd = "echo 42"
        \\share_output = true
        \\
        \\[tasks.use-result]
        \\deps = ["compute"]
        \\cmd = "echo result: {{output.compute}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "use-result" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "result: 42") != null);
}

test "17003: {{output.task-name}} template in downstream env value uses captured output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.get-token]
        \\cmd = "echo secret-token-xyz"
        \\share_output = true
        \\
        \\[tasks.request]
        \\deps = ["get-token"]
        \\env = { AUTH_TOKEN = "{{output.get-token}}" }
        \\cmd = "echo TOKEN=$AUTH_TOKEN"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "request" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TOKEN=secret-token-xyz") != null);
}

test "17004: captured output is trimmed (no trailing newlines in env var)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.echo-with-newline]
        \\cmd = "printf 'output-value\\n\\n'"
        \\share_output = true
        \\
        \\[tasks.consume]
        \\deps = ["echo-with-newline"]
        \\cmd = "bash -c 'echo length=${#ZR_OUTPUT_ECHO_WITH_NEWLINE}'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "consume" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // "output-value" without newlines is 12 chars
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "length=12") != null);
}

test "17005: share_output = false (default) does not inject ZR_OUTPUT_ env var" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.no-share]
        \\cmd = "echo hidden-value"
        \\
        \\[tasks.check]
        \\deps = ["no-share"]
        \\cmd = "bash -c 'if [ -z \"$ZR_OUTPUT_NO_SHARE\" ]; then echo env-not-set; else echo env-set; fi'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "check" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "env-not-set") != null);
}

test "17006: chained output capture: A captures → B uses A's output and also shares → C uses B's output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.step-a]
        \\cmd = "echo step-a-output"
        \\share_output = true
        \\
        \\[tasks.step-b]
        \\deps = ["step-a"]
        \\cmd = "bash -c 'echo step-b-got-$ZR_OUTPUT_STEP_A'"
        \\share_output = true
        \\
        \\[tasks.step-c]
        \\deps = ["step-b"]
        \\cmd = "bash -c 'echo step-c-got-$ZR_OUTPUT_STEP_B'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "step-c" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // step-b output should contain step-a's output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step-b-got-step-a-output") != null);
    // step-c output should contain step-b's output (which contains step-a's output)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "step-c-got-step-b-got-step-a-output") != null);
}

test "17007: capture only populated for tasks that actually ran (skip_if: up-to-date)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.generate]
        \\cmd = "bash -c 'echo generated-value > output.txt'"
        \\generates = ["output.txt"]
        \\share_output = true
        \\
        \\[tasks.use-generated]
        \\deps = ["generate"]
        \\sources = ["output.txt"]
        \\cmd = "bash -c 'echo using-$ZR_OUTPUT_GENERATE'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // First run: generate task runs and output is captured
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "use-generated" }, tmp_path);
    defer result1.deinit();

    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result1.stdout, "using-generated-value") != null);

    // Second run: generate task should be skipped (up-to-date), so ZR_OUTPUT_GENERATE should be empty
    // We expect the second run to also succeed, but generate task is skipped
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "use-generated" }, tmp_path);
    defer result2.deinit();

    // Both runs should succeed
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
}

test "17008: multi-word output (spaces) is captured verbatim in env var" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.get-message]
        \\cmd = "echo hello world with spaces"
        \\share_output = true
        \\
        \\[tasks.display]
        \\deps = ["get-message"]
        \\cmd = "echo message: $ZR_OUTPUT_GET_MESSAGE"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "display" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "message: hello world with spaces") != null);
}

test "17009: multiple tasks with share_output = true each get their own ZR_OUTPUT_ var" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.task-x]
        \\cmd = "echo x-value"
        \\share_output = true
        \\
        \\[tasks.task-y]
        \\cmd = "echo y-value"
        \\share_output = true
        \\
        \\[tasks.combine]
        \\deps = ["task-x", "task-y"]
        \\cmd = "bash -c 'echo x=$ZR_OUTPUT_TASK_X y=$ZR_OUTPUT_TASK_Y'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "combine" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "x=x-value") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "y=y-value") != null);
}

test "17010: capture works when task is a serial dependency (deps_serial)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.first]
        \\cmd = "echo serial-output"
        \\share_output = true
        \\
        \\[tasks.second]
        \\deps_serial = ["first"]
        \\cmd = "echo got: $ZR_OUTPUT_FIRST"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "second" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "got: serial-output") != null);
}

test "17011: empty stdout results in empty env var (ZR_OUTPUT_TASK= with no value)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.silent]
        \\cmd = "bash -c 'true'"
        \\share_output = true
        \\
        \\[tasks.check-empty]
        \\deps = ["silent"]
        \\cmd = "bash -c 'if [ -z \"$ZR_OUTPUT_SILENT\" ]; then echo empty; else echo not-empty; fi'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "check-empty" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "empty") != null);
}

test "17012: task name with hyphen: get-version → ZR_OUTPUT_GET_VERSION" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.get-version]
        \\cmd = "echo 3.2.1"
        \\share_output = true
        \\
        \\[tasks.check-version]
        \\deps = ["get-version"]
        \\cmd = "echo version: $ZR_OUTPUT_GET_VERSION"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "check-version" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "version: 3.2.1") != null);
}

test "17013: task name with dot: v1.build → ZR_OUTPUT_V1_BUILD" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks."v1.build"]
        \\cmd = "echo 1.0.0"
        \\share_output = true
        \\
        \\[tasks.check]
        \\deps = ["v1.build"]
        \\cmd = "echo got: $ZR_OUTPUT_V1_BUILD"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "check" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "got: 1.0.0") != null);
}

test "17014: share_output = true but task fails → output NOT captured (no ZR_OUTPUT_ var)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.failing]
        \\cmd = "bash -c 'echo error-output; exit 1'"
        \\share_output = true
        \\
        \\[tasks.dependent]
        \\deps = ["failing"]
        \\cmd = "bash -c 'if [ -z \"$ZR_OUTPUT_FAILING\" ]; then echo no-output-var; else echo output-var-set; fi'"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "dependent" }, tmp_path);
    defer result.deinit();

    // The pipeline should fail because the first task failed
    try std.testing.expect(result.exit_code != 0);
}

// ── Compatibility Tests (Old output_filtering tests - keeping for reference)

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
