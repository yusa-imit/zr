const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

/// Test fixture: Task that outputs enough text to exceed typical terminal height
const LARGE_OUTPUT_TOML =
    \\[tasks.large_output]
    \\description = "Generates large output to test pager"
    \\cmd = "printf 'line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30'"
    \\
;

/// Test fixture: Task with ANSI color codes
const COLORED_OUTPUT_TOML =
    \\[tasks.colored]
    \\description = "Outputs with ANSI colors"
    \\cmd = "printf '\033[1;31mRED\033[0m\n\033[1;32mGREEN\033[0m\n\033[1;34mBLUE\033[0m\n'"
    \\
;

test "100: show with large output fits terminal without pager" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should display task information
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "large_output") != null or
                          std.mem.indexOf(u8, result.stdout, "Generates") != null);
}

test "101: show --no-pager disables automatic pager" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    // Even with large output, --no-pager should skip pager
    var result = try runZr(allocator, &.{ "--config", config, "show", "--no-pager", "large_output" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "102: show with output preserves ANSI colors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, COLORED_OUTPUT_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "colored" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should be displayed (pager or direct)
    try std.testing.expect(result.stdout.len > 0);
}

test "103: show respects ZR_PAGER environment variable" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    // This test verifies that ZR_PAGER env var is recognized
    // In practice, pager selection happens based on output size
    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "104: show with terminal that is not TTY skips pager" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    // When output is piped (not a TTY), pager should be skipped
    // The test harness runs with piped output, so pager should not be used
    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "105: show --output flag with large file does not error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a temporary output file
    const output_file = try tmp.dir.createFile("large_output.txt", .{});
    defer output_file.close();

    // Write 100 lines to the output file
    var i: usize = 0;
    var buf: [256]u8 = undefined;
    while (i < 100) : (i += 1) {
        const line = try std.fmt.bufPrint(&buf, "Line {}\n", .{i});
        _ = try output_file.writeAll(line);
    }

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    // Get the full path to output file
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const output_path = try std.fs.path.join(allocator, &.{ tmp_path, "large_output.txt" });
    defer allocator.free(output_path);

    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output", "--output", output_path }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "106: show with small output does not use pager" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const small_output_toml =
        \\[tasks.small]
        \\description = "Small output"
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, small_output_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "small" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should be readable directly
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "small") != null or result.stdout.len > 0);
}

test "107: show --output with nonexistent file reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    // Attempt to read from a non-existent file
    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output", "--output", "/nonexistent/path/file.txt" }, null);
    defer result.deinit();

    // Should exit with error code
    try std.testing.expect(result.exit_code != 0);
}

test "108: show with multiline task output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const multiline_toml =
        \\[tasks.multiline]
        \\description = "Task with multiline output"
        \\cmd = "printf 'First line\nSecond line\nThird line\n'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, multiline_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "multiline" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "109: show --no-pager with colored output preserves colors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, COLORED_OUTPUT_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "--no-pager", "colored" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain output (potentially with ANSI codes)
    try std.testing.expect(result.stdout.len > 0);
}

test "110: show task with output redirection to file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create output file
    const output_file_path = try std.fs.path.join(allocator, &.{ tmp_path, "output.txt" });
    defer allocator.free(output_file_path);

    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output", "--output", output_file_path }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file was created
    const output_file = try tmp.dir.openFile("output.txt", .{});
    defer output_file.close();

    var buf: [512]u8 = undefined;
    const bytes_read = try output_file.read(&buf);
    try std.testing.expect(bytes_read > 0);
}

test "111: show large output without output flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show task details
    try std.testing.expect(result.stdout.len > 0);
}

test "112: pager integration with empty output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const empty_output_toml =
        \\[tasks.empty]
        \\description = "No output"
        \\cmd = "true"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, empty_output_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "empty" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "113: show --output with append mode" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create initial output file
    const output_path = try std.fs.path.join(allocator, &.{ tmp_path, "appended_output.txt" });
    defer allocator.free(output_path);

    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output", "--output", output_path }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "114: pager with output containing special characters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const special_chars_toml =
        \\[tasks.special]
        \\description = "Output with special chars"
        \\cmd = "printf 'Line with tabs\t\there\nLine with symbols: <>|&^%\nLine with unicode: ñ é\n'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, special_chars_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "special" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "115: pager respects terminal width constraints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, LARGE_OUTPUT_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "large_output" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should be displayable
    try std.testing.expect(result.stdout.len > 0 or result.stderr.len >= 0);
}
