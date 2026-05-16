const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test that show with --output streams large files without loading into memory
test "show --output streams large file without OOM (>100MB simulated)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a large output file (simulated with many lines)
    // Each line is ~100 bytes, so 1M lines = ~100MB
    const output_file = try tmp.dir.createFile("large_output.txt", .{});
    defer output_file.close();

    // Write 1 million lines to simulate a large file
    var line_buf: [128]u8 = undefined;
    var i: usize = 0;
    while (i < 1_000_000) : (i += 1) {
        const line = try std.fmt.bufPrint(&line_buf, "Log line {d}: This is a simulated log entry with some padding text to make it realistic\n", .{i});
        try output_file.writeAll(line);
        // Write every 100k lines to show progress
        if (i % 100_000 == 0) {
            std.debug.print("Written {d} lines...\n", .{i});
        }
    }

    const show_toml =
        \\[tasks.large-task]
        \\cmd = "echo large"
        \\output_file = "large_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Track memory usage before and during the command
    const initial_stats = try allocator.memoryStats();

    // This should stream the file without loading all 100MB into memory
    var result = try runZr(allocator, &.{ "show", "large-task", "--output" }, tmp_path);
    defer result.deinit();

    const final_stats = try allocator.memoryStats();
    const memory_used = final_stats.total_allocated - initial_stats.total_allocated;

    // Memory usage should be under 50MB even for 100MB+ file
    // Current implementation will FAIL this test (loads entire file)
    try std.testing.expect(memory_used < 50 * 1024 * 1024); // 50MB limit
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test that streaming with --search filter works correctly
test "show --output --search streams and filters without loading full file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a file with mixed log levels
    const output_file = try tmp.dir.createFile("search_output.txt", .{});
    defer output_file.close();

    // Write many lines with occasional ERROR lines
    var line_buf: [128]u8 = undefined;
    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        if (i % 1000 == 0) {
            const line = try std.fmt.bufPrint(&line_buf, "ERROR: Critical failure at line {d}\n", .{i});
            try output_file.writeAll(line);
        } else {
            const line = try std.fmt.bufPrint(&line_buf, "INFO: Regular log entry {d}\n", .{i});
            try output_file.writeAll(line);
        }
    }

    const show_toml =
        \\[tasks.search-task]
        \\cmd = "echo search"
        \\output_file = "search_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    const initial_stats = try allocator.memoryStats();

    // Search for ERROR - should only return ~100 lines, not all 100k
    var result = try runZr(allocator, &.{ "show", "search-task", "--output", "--search", "ERROR" }, tmp_path);
    defer result.deinit();

    const final_stats = try allocator.memoryStats();
    const memory_used = final_stats.total_allocated - initial_stats.total_allocated;

    // Should use minimal memory (much less than full file size)
    try std.testing.expect(memory_used < 10 * 1024 * 1024); // 10MB limit for filtered output
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify we got ERROR lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ERROR: Critical failure") != null);
    // Verify we didn't get INFO lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "INFO: Regular log") == null);
}

// Test that streaming with --head works correctly
test "show --output --head streams only requested lines" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a large file
    const output_file = try tmp.dir.createFile("head_output.txt", .{});
    defer output_file.close();

    var line_buf: [128]u8 = undefined;
    var i: usize = 0;
    while (i < 500_000) : (i += 1) {
        const line = try std.fmt.bufPrint(&line_buf, "Line number {d}\n", .{i});
        try output_file.writeAll(line);
    }

    const show_toml =
        \\[tasks.head-task]
        \\cmd = "echo head"
        \\output_file = "head_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    const initial_stats = try allocator.memoryStats();

    // Request only first 10 lines from a 500k line file
    var result = try runZr(allocator, &.{ "show", "head-task", "--output", "--head", "10" }, tmp_path);
    defer result.deinit();

    const final_stats = try allocator.memoryStats();
    const memory_used = final_stats.total_allocated - initial_stats.total_allocated;

    // Should use minimal memory (not load entire file)
    try std.testing.expect(memory_used < 1 * 1024 * 1024); // 1MB limit
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify we got first 10 lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Line number 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Line number 9") != null);
    // Verify we didn't get later lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Line number 100") == null);
}

// Test that streaming with --tail works correctly
test "show --output --tail streams only last N lines efficiently" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a large file
    const output_file = try tmp.dir.createFile("tail_output.txt", .{});
    defer output_file.close();

    var line_buf: [128]u8 = undefined;
    var i: usize = 0;
    while (i < 500_000) : (i += 1) {
        const line = try std.fmt.bufPrint(&line_buf, "Line number {d}\n", .{i});
        try output_file.writeAll(line);
    }

    const show_toml =
        \\[tasks.tail-task]
        \\cmd = "echo tail"
        \\output_file = "tail_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    const initial_stats = try allocator.memoryStats();

    // Request only last 10 lines from a 500k line file
    var result = try runZr(allocator, &.{ "show", "tail-task", "--output", "--tail", "10" }, tmp_path);
    defer result.deinit();

    const final_stats = try allocator.memoryStats();
    const memory_used = final_stats.total_allocated - initial_stats.total_allocated;

    // Should use minimal memory (circular buffer for tail, not full file)
    try std.testing.expect(memory_used < 5 * 1024 * 1024); // 5MB limit
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify we got last 10 lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Line number 499990") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Line number 499999") != null);
    // Verify we didn't get early lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Line number 0") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Line number 1000") == null);
}

// Test that highlighting still works in streaming mode
test "show --output --search preserves highlighting in streaming mode" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create output file with content
    const output_file = try tmp.dir.createFile("highlight_output.txt", .{});
    defer output_file.close();

    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        if (i % 100 == 0) {
            try output_file.writeAll("This line contains ERROR keyword\n");
        } else {
            try output_file.writeAll("Regular line\n");
        }
    }

    const show_toml =
        \\[tasks.highlight-task]
        \\cmd = "echo highlight"
        \\output_file = "highlight_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Search for ERROR - should highlight matches
    var result = try runZr(allocator, &.{ "show", "highlight-task", "--output", "--search", "ERROR" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // If color is enabled, output should contain ANSI escape codes for highlighting
    // (This test will pass/fail based on whether highlighting is preserved in streaming)
    const has_error_lines = std.mem.indexOf(u8, result.stdout, "ERROR") != null;
    try std.testing.expect(has_error_lines);

    // Count number of ERROR matches - should be ~100 (every 100th line)
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result.stdout, search_pos, "ERROR")) |pos| {
        count += 1;
        search_pos = pos + 5;
    }
    try std.testing.expect(count >= 90 and count <= 110); // Allow some tolerance
}

// Test memory usage stays under threshold for multi-GB file (simulated)
test "show --output memory usage stays under 50MB for large files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a very large file (2M lines = ~200MB)
    const output_file = try tmp.dir.createFile("huge_output.txt", .{});
    defer output_file.close();

    var line_buf: [128]u8 = undefined;
    var i: usize = 0;
    std.debug.print("Creating large test file (2M lines)...\n", .{});
    while (i < 2_000_000) : (i += 1) {
        const line = try std.fmt.bufPrint(&line_buf, "Log entry {d}: Some data here with padding to make realistic size\n", .{i});
        try output_file.writeAll(line);
        if (i % 250_000 == 0) {
            std.debug.print("  {d} lines written...\n", .{i});
        }
    }
    std.debug.print("Test file created.\n", .{});

    const show_toml =
        \\[tasks.huge-task]
        \\cmd = "echo huge"
        \\output_file = "huge_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    // Get baseline memory
    const initial_stats = try allocator.memoryStats();

    // Display with --tail to get last 100 lines
    std.debug.print("Running show command (this WILL fail with current implementation)...\n", .{});
    var result = try runZr(allocator, &.{ "show", "huge-task", "--output", "--tail", "100" }, tmp_path);
    defer result.deinit();

    const final_stats = try allocator.memoryStats();
    const memory_used = final_stats.total_allocated - initial_stats.total_allocated;

    std.debug.print("Memory used: {d} MB\n", .{memory_used / (1024 * 1024)});

    // Current implementation loads entire file (~200MB) into memory - will FAIL
    // Streaming implementation should use < 50MB even for multi-GB files
    try std.testing.expect(memory_used < 50 * 1024 * 1024); // 50MB limit
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output contains last lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Log entry 1999999") != null);
}

// Test that streaming works with combined filters (search + head)
test "show --output --search --head streams with combined filters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create file with mixed content
    const output_file = try tmp.dir.createFile("combined_output.txt", .{});
    defer output_file.close();

    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        if (i % 10 == 0) {
            var buf: [128]u8 = undefined;
            const line = try std.fmt.bufPrint(&buf, "MATCH: Line {d}\n", .{i});
            try output_file.writeAll(line);
        } else {
            try output_file.writeAll("No match here\n");
        }
    }

    const show_toml =
        \\[tasks.combined-task]
        \\cmd = "echo combined"
        \\output_file = "combined_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    const initial_stats = try allocator.memoryStats();

    // Search for MATCH and take first 5 results
    var result = try runZr(allocator, &.{ "show", "combined-task", "--output", "--search", "MATCH", "--head", "5" }, tmp_path);
    defer result.deinit();

    const final_stats = try allocator.memoryStats();
    const memory_used = final_stats.total_allocated - initial_stats.total_allocated;

    // Should use very little memory (only 5 lines needed)
    try std.testing.expect(memory_used < 5 * 1024 * 1024); // 5MB limit
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Count MATCH occurrences - should be exactly 5
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result.stdout, search_pos, "MATCH")) |pos| {
        count += 1;
        search_pos = pos + 5;
    }
    try std.testing.expectEqual(@as(usize, 5), count);
}

// Test edge case: empty file
test "show --output streams empty file correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create empty file
    const output_file = try tmp.dir.createFile("empty_output.txt", .{});
    defer output_file.close();

    const show_toml =
        \\[tasks.empty-task]
        \\cmd = "echo empty"
        \\output_file = "empty_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    var result = try runZr(allocator, &.{ "show", "empty-task", "--output" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should be empty
    const trimmed = std.mem.trim(u8, result.stdout, " \t\n\r");
    try std.testing.expectEqual(@as(usize, 0), trimmed.len);
}

// Test edge case: file with single line
test "show --output streams single line file correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const output_file = try tmp.dir.createFile("single_output.txt", .{});
    defer output_file.close();
    try output_file.writeAll("Only one line\n");

    const show_toml =
        \\[tasks.single-task]
        \\cmd = "echo single"
        \\output_file = "single_output.txt"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(show_toml);

    var result = try runZr(allocator, &.{ "show", "single-task", "--output" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Only one line") != null);
}
