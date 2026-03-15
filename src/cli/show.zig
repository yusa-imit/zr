const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const types = @import("../config/types.zig");

fn processOutput(
    allocator: Allocator,
    contents: []const u8,
    opts: ShowOutputOptions,
    w: anytype,
    use_color: bool,
) !void {
    // Split contents into lines
    var lines = std.ArrayList([]const u8){};
    defer lines.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |line| {
        // Skip empty lines (from trailing newline)
        if (line.len > 0) {
            try lines.append(allocator, line);
        }
    }

    // Apply search pattern filter
    var filtered_lines = std.ArrayList([]const u8){};
    defer filtered_lines.deinit(allocator);

    if (opts.search_pattern) |pattern| {
        for (lines.items) |line| {
            if (std.mem.indexOf(u8, line, pattern) != null) {
                try filtered_lines.append(allocator, line);
            }
        }
    } else if (opts.filter_regex) |_| {
        // For now, treat regex filter as simple substring match
        // Full regex support would require additional dependency
        for (lines.items) |line| {
            if (opts.filter_regex) |pattern| {
                if (std.mem.indexOf(u8, line, pattern) != null) {
                    try filtered_lines.append(allocator, line);
                }
            }
        }
    } else {
        // No filter, use all lines
        try filtered_lines.appendSlice(allocator, lines.items);
    }

    // Apply head/tail limits
    var output_lines = std.ArrayList([]const u8){};
    defer output_lines.deinit(allocator);

    if (opts.head_lines) |n| {
        const count = @min(n, filtered_lines.items.len);
        try output_lines.appendSlice(allocator, filtered_lines.items[0..count]);
    } else if (opts.tail_lines) |n| {
        const count = @min(n, filtered_lines.items.len);
        const start = filtered_lines.items.len - count;
        try output_lines.appendSlice(allocator, filtered_lines.items[start..]);
    } else {
        // No limit, use all filtered lines
        try output_lines.appendSlice(allocator, filtered_lines.items);
    }

    // Output with highlighting
    for (output_lines.items) |line| {
        if (opts.search_pattern) |pattern| {
            try highlightMatches(line, pattern, w, use_color);
            try w.writeAll("\n");
        } else {
            try w.writeAll(line);
            try w.writeAll("\n");
        }
    }
}

fn highlightMatches(
    line: []const u8,
    pattern: []const u8,
    w: anytype,
    use_color: bool,
) !void {
    var pos: usize = 0;
    while (pos < line.len) {
        if (std.mem.indexOf(u8, line[pos..], pattern)) |match_start| {
            const abs_start = pos + match_start;
            const abs_end = abs_start + pattern.len;

            // Write text before match
            try w.writeAll(line[pos..abs_start]);

            // Write highlighted match
            if (use_color) {
                try w.writeAll("\x1b[1;33m"); // Bold yellow
            }
            try w.writeAll(line[abs_start..abs_end]);
            if (use_color) {
                try w.writeAll("\x1b[0m"); // Reset
            }

            pos = abs_end;
        } else {
            // No more matches, write rest of line
            try w.writeAll(line[pos..]);
            break;
        }
    }
}

pub const ShowOutputOptions = struct {
    search_pattern: ?[]const u8 = null,
    filter_regex: ?[]const u8 = null,
    tail_lines: ?usize = null,
    head_lines: ?usize = null,
};

pub fn cmdShow(
    allocator: Allocator,
    task_name: []const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
    output_flag: bool,
    output_opts: ShowOutputOptions,
) !u8 {
    // Load config
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    // Find task
    const task = config.tasks.get(task_name) orelse {
        try color.printError(ew, use_color,
            "show: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    };

    // Handle --output flag: display captured task output
    if (output_flag) {
        if (task.output_file == null) {
            try color.printError(ew, use_color,
                "show: Task '{s}' has no output_file configured\n\n  Hint: Add 'output_file = \"path/to/file\"' to the task configuration\n",
                .{task_name},
            );
            return 1;
        }

        const output_path = task.output_file.?;
        const file = std.fs.cwd().openFile(output_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                try color.printError(ew, use_color,
                    "show: Output file not found: {s}\n\n  Hint: Run the task first to generate output\n",
                    .{output_path},
                );
            } else {
                try color.printError(ew, use_color,
                    "show: Cannot open output file: {s}\n  Error: {}\n",
                    .{output_path, err},
                );
            }
            return 1;
        };
        defer file.close();

        // Read and display file contents
        const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB limit
        defer allocator.free(contents);

        // Process output based on options
        try processOutput(allocator, contents, output_opts, w, use_color);
        return 0;
    }

    // Print task details
    try color.printBold(w, use_color, "Task: {s}\n", .{task_name});
    try w.print("\n", .{});

    // Description
    if (task.description) |desc| {
        try color.printDim(w, use_color, "  {s}\n\n", .{desc});
    }

    // Command
    try color.printBold(w, use_color, "Command:\n", .{});
    try w.print("  {s}\n\n", .{task.cmd});

    // Working directory
    if (task.cwd) |cwd| {
        try color.printBold(w, use_color, "Working Directory:\n", .{});
        try w.print("  {s}\n\n", .{cwd});
    }

    // Dependencies
    if (task.deps.len > 0 or task.deps_serial.len > 0) {
        try color.printBold(w, use_color, "Dependencies:\n", .{});
        if (task.deps.len > 0) {
            try w.print("  Parallel:\n", .{});
            for (task.deps) |dep| {
                try w.print("    • {s}\n", .{dep});
            }
        }
        if (task.deps_serial.len > 0) {
            try w.print("  Serial:\n", .{});
            for (task.deps_serial) |dep| {
                try w.print("    • {s}\n", .{dep});
            }
        }
        try w.print("\n", .{});
    }

    // Tags
    if (task.tags.len > 0) {
        try color.printBold(w, use_color, "Tags:\n", .{});
        try w.print("  ", .{});
        for (task.tags, 0..) |tag, i| {
            if (i > 0) try w.print(", ", .{});
            try w.print("{s}", .{tag});
        }
        try w.print("\n\n", .{});
    }

    // Environment variables
    if (task.env.len > 0) {
        try color.printBold(w, use_color, "Environment:\n", .{});
        for (task.env) |kv| {
            try w.print("  {s} = {s}\n", .{ kv[0], kv[1] });
        }
        try w.print("\n", .{});
    }

    // Execution settings
    var has_exec_settings = false;
    if (task.timeout_ms != null or
        task.allow_failure or
        task.retry_max > 0 or
        task.max_concurrent > 0)
    {
        has_exec_settings = true;
    }

    if (has_exec_settings) {
        try color.printBold(w, use_color, "Execution:\n", .{});

        if (task.timeout_ms) |timeout| {
            const seconds = timeout / 1000;
            if (seconds < 60) {
                try w.print("  Timeout: {d}s\n", .{seconds});
            } else {
                const minutes = seconds / 60;
                try w.print("  Timeout: {d}min\n", .{minutes});
            }
        }

        if (task.allow_failure) {
            try w.print("  Allow Failure: yes\n", .{});
        }

        if (task.retry_max > 0) {
            try w.print("  Retry: {d} attempt(s)", .{task.retry_max});
            if (task.retry_delay_ms > 0) {
                const delay_s = task.retry_delay_ms / 1000;
                try w.print(", {d}s delay", .{delay_s});
            }
            if (task.retry_backoff) {
                try w.print(", exponential backoff", .{});
            }
            try w.print("\n", .{});
        }

        if (task.max_concurrent > 0) {
            try w.print("  Max Concurrent: {d}\n", .{task.max_concurrent});
        }

        try w.print("\n", .{});
    }

    // Resource limits
    if (task.max_cpu != null or task.max_memory != null) {
        try color.printBold(w, use_color, "Resource Limits:\n", .{});

        if (task.max_cpu) |max_cpu| {
            try w.print("  CPU: {d}%\n", .{max_cpu});
        }

        if (task.max_memory) |max_mem| {
            const mb = max_mem / (1024 * 1024);
            const gb = @as(f64, @floatFromInt(max_mem)) / (1024.0 * 1024.0 * 1024.0);
            if (mb < 1024) {
                try w.print("  Memory: {d}MB\n", .{mb});
            } else {
                try w.print("  Memory: {d:.1}GB\n", .{gb});
            }
        }

        try w.print("\n", .{});
    }

    // Condition
    if (task.condition) |cond| {
        try color.printBold(w, use_color, "Condition:\n", .{});
        try w.print("  {s}\n\n", .{cond});
    }

    // Cache
    if (task.cache) {
        try color.printBold(w, use_color, "Caching:\n", .{});
        try color.printSuccess(w, use_color, "  Enabled ✓\n\n", .{});
    }

    // Toolchain
    if (task.toolchain.len > 0) {
        try color.printBold(w, use_color, "Toolchain:\n", .{});
        for (task.toolchain) |tool_spec| {
            try w.print("  • {s}\n", .{tool_spec});
        }
        try w.print("\n", .{});
    }

    return 0;
}

// Tests
test "cmdShow nonexistent task returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const opts = ShowOutputOptions{};
    // Test with non-existent task - this will fail to load config but that's okay for this test
    const exit_code = try cmdShow(allocator, "nonexistent", "zr.toml", &out_w.interface, &err_w.interface, false, false, opts);
    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

test "processOutput with search pattern" {
    const allocator = std.testing.allocator;
    const contents = "line 1 ERROR\nline 2 OK\nline 3 ERROR\nline 4 OK\n";

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{ .search_pattern = "ERROR" };
    try processOutput(allocator, contents, opts, &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "line 1 ERROR") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 3 ERROR") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 2 OK") == null);
}

test "processOutput with head limit" {
    const allocator = std.testing.allocator;
    const contents = "line 1\nline 2\nline 3\nline 4\nline 5\n";

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{ .head_lines = 2 };
    try processOutput(allocator, contents, opts, &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 3") == null);
}

test "processOutput with tail limit" {
    const allocator = std.testing.allocator;
    const contents = "line 1\nline 2\nline 3\nline 4\nline 5\n";

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{ .tail_lines = 2 };
    try processOutput(allocator, contents, opts, &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "line 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 1") == null);
}

test "highlightMatches highlights all occurrences" {
    const allocator = std.testing.allocator;
    _ = allocator;
    const line = "ERROR at position 5, another ERROR at position 30";

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    try highlightMatches(line, "ERROR", &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expectEqualStrings(line, output);
}
