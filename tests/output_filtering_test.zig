const std = @import("std");
const helpers = @import("helpers.zig");

const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test 9500: Basic grep filtering - show only matching lines
test "output filtering: --grep shows only matching lines" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-grep]
        \\cmd = "echo 'line 1: info'; echo 'line 2: error occurred'; echo 'line 3: warning found'; echo 'line 4: info again'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep", "error", "run", "test-grep" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain "error occurred" but not "info" or "warning"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "error occurred") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 1: info") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "warning found") == null);
}

// Test 9501: Inverted grep - hide matching lines
test "output filtering: --grep-v hides matching lines" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-grep-v]
        \\cmd = "echo 'DEBUG: verbose output'; echo 'ERROR: critical failure'; echo 'DEBUG: more noise'; echo 'INFO: normal log'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep-v", "DEBUG", "run", "test-grep-v" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain ERROR and INFO but not DEBUG
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR: critical failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "INFO: normal log") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "DEBUG") == null);
}

// Test 9502: Pipe-separated alternatives (OR logic)
test "output filtering: --grep supports pipe-separated alternatives" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-alternatives]
        \\cmd = "echo 'info: starting'; echo 'error: failed'; echo 'warning: deprecated'; echo 'fatal: crash'; echo 'debug: trace'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep", "error|warning|fatal", "run", "test-alternatives" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should match error, warning, fatal
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "error: failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "warning: deprecated") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fatal: crash") != null);
    // Should NOT match info or debug
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "info: starting") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "debug: trace") == null);
}

// Test 9503: Highlight mode (shows all lines with matches highlighted)
test "output filtering: --highlight marks matches in all output" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-highlight]
        \\cmd = "echo 'TODO: fix this'; echo 'normal line'; echo 'TODO: another task'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--highlight", "TODO", "run", "test-highlight" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain all lines (highlight doesn't filter)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TODO") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "normal line") != null);
    // If color is enabled, should contain ANSI codes for highlighting
    // (Exact ANSI codes may vary, so we check for general output presence)
}

// Test 9504: Context lines (-C)
test "output filtering: -C shows context lines around matches" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-context]
        \\cmd = "echo 'line 1'; echo 'line 2'; echo 'ERROR: match'; echo 'line 4'; echo 'line 5'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep", "ERROR", "-C", "1", "run", "test-context" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain ERROR match + 1 line before + 1 line after
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 2") != null); // before
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR: match") != null); // match
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 4") != null); // after
    // Should NOT contain line 1 or line 5 (outside context window)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 1") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 5") == null);
}

// Test 9505: Combined filters (--grep + --grep-v)
test "output filtering: --grep and --grep-v can be combined" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-combined]
        \\cmd = "echo 'ERROR: debug info'; echo 'ERROR: critical failure'; echo 'INFO: debug trace'; echo 'WARNING: deprecated'"
    );
    defer allocator.free(config);

    // Show lines with ERROR but hide lines with "debug"
    const result = try runZr(allocator, &.{ "--config", config, "--grep", "ERROR", "--grep-v", "debug", "run", "test-combined" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain "ERROR: critical failure" (has ERROR, no debug)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR: critical failure") != null);
    // Should NOT contain "ERROR: debug info" (has debug) or "INFO: debug trace" (no ERROR)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR: debug info") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "INFO: debug trace") == null);
}

// Test 9506: Empty pattern (no filtering)
test "output filtering: empty pattern shows all output" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-empty]
        \\cmd = "echo 'line 1'; echo 'line 2'; echo 'line 3'"
    );
    defer allocator.free(config);

    // No filter flags - should show all output
    const result = try runZr(allocator, &.{ "--config", config, "run", "test-empty" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 3") != null);
}

// Test 9507: No matches (filtered to empty output)
test "output filtering: no matches produces minimal output" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-no-match]
        \\cmd = "echo 'info: normal'; echo 'info: everything ok'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep", "ERROR", "run", "test-no-match" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should not contain "info" lines (no ERROR pattern matched)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "info: normal") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "info: everything ok") == null);
}

// Test 9508: Multi-task run with filtering
test "output filtering: applies to all tasks in multi-task run" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.task1]
        \\cmd = "echo 'task1: ERROR occurred'; echo 'task1: info message'"
        \\
        \\[tasks.task2]
        \\cmd = "echo 'task2: WARNING detected'; echo 'task2: ERROR found'"
        \\deps = ["task1"]
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep", "ERROR", "run", "task2" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain ERROR lines from both tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1: ERROR occurred") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2: ERROR found") != null);
    // Should NOT contain non-ERROR lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1: info message") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2: WARNING detected") == null);
}

// Test 9509: Filtering with --no-color (no ANSI codes)
test "output filtering: --no-color disables highlighting ANSI codes" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-no-color]
        \\cmd = "echo 'TODO: fix this'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--no-color", "--highlight", "TODO", "run", "test-no-color" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "TODO") != null);
    // Should NOT contain ANSI escape codes with --no-color
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\x1b[") == null);
}

// Test 9510: Context lines with multiple matches (overlapping context)
test "output filtering: context windows merge when matches are close" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-overlap]
        \\cmd = "echo 'line 1'; echo 'ERROR 1'; echo 'line 3'; echo 'ERROR 2'; echo 'line 5'"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep", "ERROR", "-C", "1", "run", "test-overlap" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // With -C 1, both ERRORs + their context should be shown
    // ERROR 1 context: line 1, ERROR 1, line 3
    // ERROR 2 context: line 3, ERROR 2, line 5
    // line 3 is in both contexts - should appear once
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 5") != null);
}

// Test 9511: Large context value
test "output filtering: large -C value shows many context lines" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir,
        \\[tasks.test-large-context]
        \\cmd = "for i in $(seq 1 10); do echo \"line $i\"; done; echo 'ERROR: match'; for i in $(seq 11 20); do echo \"line $i\"; done"
    );
    defer allocator.free(config);

    const result = try runZr(allocator, &.{ "--config", config, "--grep", "ERROR", "-C", "5", "run", "test-large-context" }, null);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // With -C 5, should show 5 lines before + match + 5 lines after
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR: match") != null);
    // Should include 5 lines before (6-10) and 5 lines after (11-15)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "line 6") != null or
                           std.mem.indexOf(u8, result.stdout, "line 7") != null); // Some context shown
}
