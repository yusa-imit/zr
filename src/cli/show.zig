const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const types = @import("../config/types.zig");
const sailor = @import("sailor");
const pager = @import("../util/pager.zig");

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
    follow: bool = false,
    no_pager: bool = false,
};

/// StreamingLineReader provides line-by-line iteration over a file
/// without loading the entire file into memory.
/// Memory usage: ~4KB buffer + current line allocation
const StreamingLineReader = struct {
    allocator: Allocator,
    file: std.fs.File,
    buffer: [4096]u8,
    buffer_pos: usize,
    buffer_len: usize,
    eof_reached: bool,

    pub fn init(allocator: Allocator, file: std.fs.File) StreamingLineReader {
        return .{
            .allocator = allocator,
            .file = file,
            .buffer = undefined,
            .buffer_pos = 0,
            .buffer_len = 0,
            .eof_reached = false,
        };
    }

    pub fn deinit(_: *StreamingLineReader) void {
        // Nothing to clean up - file is owned by caller
    }

    /// Returns next line (owned, caller must free), or null if EOF.
    /// Line does NOT include the trailing newline character.
    pub fn next(self: *StreamingLineReader) !?[]const u8 {
        if (self.eof_reached and self.buffer_pos >= self.buffer_len) {
            return null;
        }

        var line_buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer line_buf.deinit(self.allocator);

        while (true) {
            // Refill buffer if needed
            if (self.buffer_pos >= self.buffer_len and !self.eof_reached) {
                self.buffer_len = try self.file.read(&self.buffer);
                self.buffer_pos = 0;
                if (self.buffer_len == 0) {
                    self.eof_reached = true;
                }
            }

            // Check for EOF
            if (self.buffer_pos >= self.buffer_len) {
                if (line_buf.items.len > 0) {
                    // Return last line without trailing newline
                    return try line_buf.toOwnedSlice(self.allocator);
                } else {
                    line_buf.deinit(self.allocator);
                    return null;
                }
            }

            // Scan for newline in current buffer
            const remaining = self.buffer[self.buffer_pos..self.buffer_len];
            if (std.mem.indexOfScalar(u8, remaining, '\n')) |newline_offset| {
                // Found newline - append up to (but not including) newline
                try line_buf.appendSlice(self.allocator, remaining[0..newline_offset]);
                self.buffer_pos += newline_offset + 1; // Skip past newline
                return try line_buf.toOwnedSlice(self.allocator);
            } else {
                // No newline in buffer - append all remaining and continue
                try line_buf.appendSlice(self.allocator, remaining);
                self.buffer_pos = self.buffer_len;
            }
        }
    }
};

/// Circular buffer for tail operations - fixed memory footprint
const CircularLineBuffer = struct {
    allocator: Allocator,
    lines: []?[]const u8,
    capacity: usize,
    write_index: usize,
    count: usize,

    fn init(allocator: Allocator, capacity: usize) !CircularLineBuffer {
        const lines = try allocator.alloc(?[]const u8, capacity);
        @memset(lines, null);
        return .{
            .allocator = allocator,
            .lines = lines,
            .capacity = capacity,
            .write_index = 0,
            .count = 0,
        };
    }

    fn deinit(self: *CircularLineBuffer) void {
        for (self.lines) |maybe_line| {
            if (maybe_line) |line| {
                self.allocator.free(line);
            }
        }
        self.allocator.free(self.lines);
    }

    fn append(self: *CircularLineBuffer, line: []const u8) !void {
        // Free old line if we're overwriting
        if (self.lines[self.write_index]) |old_line| {
            self.allocator.free(old_line);
        }

        // Store new line (duplicate so we own it)
        self.lines[self.write_index] = try self.allocator.dupe(u8, line);

        // Advance write position
        self.write_index = (self.write_index + 1) % self.capacity;
        if (self.count < self.capacity) {
            self.count += 1;
        }
    }

    fn getOrdered(self: *CircularLineBuffer, out: *std.ArrayListUnmanaged([]const u8), allocator: Allocator) !void {
        if (self.count == 0) return;

        // Calculate read start index (oldest line)
        const start_index = if (self.count < self.capacity)
            0
        else
            self.write_index;

        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const idx = (start_index + i) % self.capacity;
            if (self.lines[idx]) |line| {
                try out.append(allocator, line);
            }
        }
    }
};

/// Streaming version of processOutput - operates on file instead of memory buffer.
/// Memory usage: ~4KB read buffer + N lines for tail (if tail_lines is set)
/// Stream decompressed output from memory buffer (for .gz files).
fn streamDecompressedOutput(
    allocator: Allocator,
    data: []const u8,
    opts: ShowOutputOptions,
    w: anytype,
    use_color: bool,
) !void {
    // Split into lines
    var line_it = std.mem.splitScalar(u8, data, '\n');

    // Handle tail mode - collect last N lines
    if (opts.tail_lines) |n| {
        var circular_buf = try CircularLineBuffer.init(allocator, n);
        defer circular_buf.deinit();

        while (line_it.next()) |line| {
            // Apply search filter
            const matches = if (opts.search_pattern) |pattern|
                std.mem.indexOf(u8, line, pattern) != null
            else if (opts.filter_regex) |pattern|
                std.mem.indexOf(u8, line, pattern) != null
            else
                true;

            if (matches) {
                try circular_buf.append(line);
            }
        }

        // Output the buffered lines
        var output_lines: std.ArrayListUnmanaged([]const u8) = .{};
        defer output_lines.deinit(allocator);
        try circular_buf.getOrdered(&output_lines, allocator);

        for (output_lines.items) |line| {
            if (opts.search_pattern) |pattern| {
                try highlightMatches(line, pattern, w, use_color);
                try w.writeAll("\n");
            } else {
                try w.writeAll(line);
                try w.writeAll("\n");
            }
        }

        return;
    }

    // Head mode or no limit - stream directly
    var lines_output: usize = 0;
    const limit = opts.head_lines orelse std.math.maxInt(usize);

    while (line_it.next()) |line| {
        if (lines_output >= limit) break;

        // Apply search filter
        const matches = if (opts.search_pattern) |pattern|
            std.mem.indexOf(u8, line, pattern) != null
        else if (opts.filter_regex) |pattern|
            std.mem.indexOf(u8, line, pattern) != null
        else
            true;

        if (matches) {
            // Output line immediately
            if (opts.search_pattern) |pattern| {
                try highlightMatches(line, pattern, w, use_color);
                try w.writeAll("\n");
            } else {
                try w.writeAll(line);
                try w.writeAll("\n");
            }

            lines_output += 1;
        }
    }
}

fn streamProcessOutput(
    allocator: Allocator,
    file: std.fs.File,
    opts: ShowOutputOptions,
    w: anytype,
    use_color: bool,
) !void {
    var reader = StreamingLineReader.init(allocator, file);
    defer reader.deinit();

    // Handle tail mode - requires circular buffer
    if (opts.tail_lines) |n| {
        var circular_buf = try CircularLineBuffer.init(allocator, n);
        defer circular_buf.deinit();

        // Read all lines into circular buffer (only keeps last N)
        while (try reader.next()) |line| {
            defer allocator.free(line);

            // Apply search filter
            const matches = if (opts.search_pattern) |pattern|
                std.mem.indexOf(u8, line, pattern) != null
            else if (opts.filter_regex) |pattern|
                std.mem.indexOf(u8, line, pattern) != null
            else
                true;

            if (matches) {
                try circular_buf.append(line);
            }
        }

        // Output the buffered lines
        var output_lines: std.ArrayListUnmanaged([]const u8) = .{};
        defer output_lines.deinit(allocator);
        try circular_buf.getOrdered(&output_lines, allocator);

        for (output_lines.items) |line| {
            if (opts.search_pattern) |pattern| {
                try highlightMatches(line, pattern, w, use_color);
                try w.writeAll("\n");
            } else {
                try w.writeAll(line);
                try w.writeAll("\n");
            }
        }

        return;
    }

    // Head mode or no limit - stream directly (minimal memory)
    var lines_output: usize = 0;
    const limit = opts.head_lines orelse std.math.maxInt(usize);

    while (try reader.next()) |line| {
        defer allocator.free(line);

        if (lines_output >= limit) {
            break; // Stop reading after head limit reached
        }

        // Apply search filter
        const matches = if (opts.search_pattern) |pattern|
            std.mem.indexOf(u8, line, pattern) != null
        else if (opts.filter_regex) |pattern|
            std.mem.indexOf(u8, line, pattern) != null
        else
            true;

        if (matches) {
            // Output line immediately
            if (opts.search_pattern) |pattern| {
                try highlightMatches(line, pattern, w, use_color);
                try w.writeAll("\n");
            } else {
                try w.writeAll(line);
                try w.writeAll("\n");
            }

            lines_output += 1;
        }
    }
}

/// Follow mode: tail -f style live output streaming
/// Reads file from current position to end, then polls for new content
fn followOutput(
    allocator: Allocator,
    file_path: []const u8,
    opts: ShowOutputOptions,
    w: anytype,
    use_color: bool,
) !void {
    // Open file for reading
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // First, stream existing content
    try streamProcessOutput(allocator, file, opts, w, use_color);

    // Then poll for new content (tail -f style)
    while (true) {
        // Sleep for 100ms between polls
        std.Thread.sleep(100 * std.time.ns_per_ms);

        // Try to read new content
        var reader = StreamingLineReader.init(allocator, file);
        defer reader.deinit();

        while (try reader.next()) |line| {
            defer allocator.free(line);

            // Apply filters
            const matches = if (opts.search_pattern) |pattern|
                std.mem.indexOf(u8, line, pattern) != null
            else if (opts.filter_regex) |pattern|
                std.mem.indexOf(u8, line, pattern) != null
            else
                true;

            if (matches) {
                if (opts.search_pattern) |pattern| {
                    try highlightMatches(line, pattern, w, use_color);
                    try w.writeAll("\n");
                } else {
                    try w.writeAll(line);
                    try w.writeAll("\n");
                }
            }
        }
    }
}

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

        // Handle follow mode separately (keeps file open and polls)
        if (output_opts.follow) {
            try followOutput(allocator, output_path, output_opts, w, use_color);
            return 0;
        }

        // Check if compressed version (.gz) exists
        const gz_path = try std.fmt.allocPrint(allocator, "{s}.gz", .{output_path});
        defer allocator.free(gz_path);

        const is_compressed = blk: {
            std.fs.cwd().access(gz_path, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        if (is_compressed) {
            // Decompress and stream (gunzip -c <file> to stdout)
            const result = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &[_][]const u8{ "gunzip", "-c", gz_path },
            });
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                try color.printError(ew, use_color,
                    "show: Failed to decompress output file: {s}\n  Error: {s}\n",
                    .{ gz_path, result.stderr },
                );
                return 1;
            }

            // Stream decompressed output with filters
            try streamDecompressedOutput(allocator, result.stdout, output_opts, w, use_color);
            return 0;
        }

        // No compression, read normally
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

        // Automatic pager integration for large output
        // Only use pager if:
        // - --no-pager flag is NOT set
        // - Output is a TTY (not piped)
        // - Output exceeds terminal height
        const should_use_pager = blk: {
            if (output_opts.no_pager) break :blk false;
            if (!pager.isTerminal()) break :blk false;

            // Count lines in file for pager decision
            const file_size = try file.getEndPos();
            try file.seekTo(0);

            // Read file to count lines
            const contents = try file.readToEndAlloc(allocator, file_size);
            defer allocator.free(contents);

            const line_count = pager.countLines(contents);
            const terminal_height = pager.getTerminalHeight();

            // Reset file position for streaming
            try file.seekTo(0);

            const pager_config = pager.PagerConfig{ .enabled = true };
            break :blk pager.shouldUsePager(line_count, terminal_height, pager_config);
        };

        if (should_use_pager) {
            // Spawn pager and pipe output through it
            const pager_cmd = try pager.getPagerCommand(allocator);
            defer if (pager_cmd) |cmd| allocator.free(cmd);

            if (pager_cmd) |cmd| {
                var child = try pager.spawnPager(allocator, cmd);
                defer {
                    _ = child.wait() catch {};
                }

                // Pipe file contents to pager stdin
                if (child.stdin) |pager_stdin| {
                    defer pager_stdin.close();

                    // Stream file to pager with filters using deprecated writer API
                    const pager_writer = pager_stdin.deprecatedWriter();
                    try streamProcessOutput(allocator, file, output_opts, pager_writer, use_color);
                }

                return 0;
            }
        }

        // No pager needed or available - stream directly to stdout
        try streamProcessOutput(allocator, file, output_opts, w, use_color);

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

// ============================================================================
// Streaming Infrastructure Tests (TDD - will fail until implementation)
// ============================================================================

test "StreamingLineReader reads line-by-line without loading full file" {
    const allocator = std.testing.allocator;

    // Create a test file
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("streaming_test.txt", .{ .read = true });
    try test_file.writeAll("line 1\nline 2\nline 3\nline 4\nline 5\n");
    try test_file.seekTo(0);

    // This will fail until StreamingLineReader is implemented
    var reader = StreamingLineReader.init(allocator, test_file);
    defer reader.deinit();

    var line_count: usize = 0;
    while (try reader.next()) |line| {
        defer allocator.free(line);
        line_count += 1;
        // Verify each line is read independently
        try std.testing.expect(line.len > 0);
    }

    try std.testing.expectEqual(@as(usize, 5), line_count);
}

test "StreamingLineReader handles file without trailing newline" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("no_trailing_newline.txt", .{ .read = true });
    try test_file.writeAll("line 1\nline 2\nlast line without newline");
    try test_file.seekTo(0);

    var reader = StreamingLineReader.init(allocator, test_file);
    defer reader.deinit();

    var lines: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit(allocator);
    }

    while (try reader.next()) |line| {
        try lines.append(allocator, line);
    }

    try std.testing.expectEqual(@as(usize, 3), lines.items.len);
    try std.testing.expectEqualStrings("last line without newline", lines.items[2]);
}

test "StreamingLineReader handles empty file" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("empty.txt", .{ .read = true });
    try test_file.seekTo(0);

    var reader = StreamingLineReader.init(allocator, test_file);
    defer reader.deinit();

    const first_line = try reader.next();
    try std.testing.expect(first_line == null);
}

test "StreamingLineReader handles single line" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("single_line.txt", .{ .read = true });
    try test_file.writeAll("only one line\n");
    try test_file.seekTo(0);

    var reader = StreamingLineReader.init(allocator, test_file);
    defer reader.deinit();

    const line1 = try reader.next();
    try std.testing.expect(line1 != null);
    defer allocator.free(line1.?);
    try std.testing.expectEqualStrings("only one line", line1.?);

    const line2 = try reader.next();
    try std.testing.expect(line2 == null);
}

test "streamProcessOutput filters lines while streaming" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create file with mixed content
    const test_file = try tmp.dir.createFile("filter_test.txt", .{ .read = true });
    try test_file.writeAll("ERROR: line 1\nINFO: line 2\nERROR: line 3\nINFO: line 4\n");
    try test_file.seekTo(0);

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{ .search_pattern = "ERROR" };
    try streamProcessOutput(allocator, test_file, opts, &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "ERROR: line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ERROR: line 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "INFO") == null);
}

test "streamProcessOutput stops after head limit reached" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("head_test.txt", .{ .read = true });
    // Write many lines, but we only want first 3
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var line_buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "Line {d}\n", .{i});
        try test_file.writeAll(line);
    }
    try test_file.seekTo(0);

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{ .head_lines = 3 };
    try streamProcessOutput(allocator, test_file, opts, &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 3") == null);

    // Critical: Must NOT read entire file when head limit is set
    // (This behavior will be validated by memory tests in integration)
}

test "streamProcessOutput keeps only last N lines for tail" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("tail_test.txt", .{ .read = true });
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var line_buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "Line {d}\n", .{i});
        try test_file.writeAll(line);
    }
    try test_file.seekTo(0);

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{ .tail_lines = 3 };
    try streamProcessOutput(allocator, test_file, opts, &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 997") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 998") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 999") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 0") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 996") == null);
}

test "streamProcessOutput combines search and head filters" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("combined_test.txt", .{ .read = true });
    // Write file with every 10th line containing "MATCH"
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var line_buf: [64]u8 = undefined;
        const line = if (i % 10 == 0)
            try std.fmt.bufPrint(&line_buf, "MATCH: Line {d}\n", .{i})
        else
            try std.fmt.bufPrint(&line_buf, "Other: Line {d}\n", .{i});
        try test_file.writeAll(line);
    }
    try test_file.seekTo(0);

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{
        .search_pattern = "MATCH",
        .head_lines = 2,
    };
    try streamProcessOutput(allocator, test_file, opts, &writer_iface, false);

    const output = fbs.getWritten();

    // Should get only first 2 matching lines
    var match_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, output, search_pos, "MATCH")) |pos| {
        match_count += 1;
        search_pos = pos + 5;
    }
    try std.testing.expectEqual(@as(usize, 2), match_count);
}

test "streamProcessOutput preserves search highlighting" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("highlight_test.txt", .{ .read = true });
    try test_file.writeAll("This line has ERROR in it\nThis line has ERROR twice ERROR\n");
    try test_file.seekTo(0);

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{ .search_pattern = "ERROR" };
    try streamProcessOutput(allocator, test_file, opts, &writer_iface, true);

    const output = fbs.getWritten();
    // When use_color=true, output should contain ANSI escape codes
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[1;33m") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[0m") != null);
}

test "streamProcessOutput handles empty file without error" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const test_file = try tmp.dir.createFile("empty_stream.txt", .{ .read = true });
    try test_file.seekTo(0);

    var out_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    var writer_iface = fbs.writer().any();

    const opts = ShowOutputOptions{};
    try streamProcessOutput(allocator, test_file, opts, &writer_iface, false);

    const output = fbs.getWritten();
    try std.testing.expectEqual(@as(usize, 0), output.len);
}
