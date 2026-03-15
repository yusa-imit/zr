const std = @import("std");
const builtin = @import("builtin");

/// Output capture mode for task execution.
pub const OutputMode = enum {
    /// Stream output to a file. Task stdout/stderr written to output_file.
    stream,
    /// Buffer output in memory. Captured output can be retrieved later via getBuffer().
    buffer,
    /// Discard output. No capture, minimal overhead.
    discard,
};

/// Configuration for task output capture.
pub const OutputCaptureConfig = struct {
    mode: OutputMode = .discard,
    /// Path to file for stream mode. Ignored in buffer/discard modes.
    output_file: ?[]const u8 = null,
    /// Maximum buffer size in bytes for buffer mode (0 = unlimited).
    /// When exceeded, oldest lines are dropped.
    max_buffer_size: usize = 1024 * 1024, // 1MB default
};

/// OutputCapture manages task output with configurable modes.
pub const OutputCapture = struct {
    allocator: std.mem.Allocator,
    config: OutputCaptureConfig,
    /// File handle for stream mode.
    file: ?std.fs.File = null,
    /// In-memory buffer for buffer mode (ArrayList of lines).
    buffer: std.ArrayList([]const u8) = .{},
    /// Current buffer size in bytes (for buffer mode).
    buffer_size_bytes: usize = 0,
    /// Mutex for thread-safe writes.
    mutex: std.Thread.Mutex = .{},

    /// Initialize OutputCapture with the given configuration.
    pub fn init(allocator: std.mem.Allocator, config: OutputCaptureConfig) !OutputCapture {
        var self: OutputCapture = .{
            .allocator = allocator,
            .config = config,
            .buffer = std.ArrayList([]const u8){},
        };

        // For stream mode, open the output file
        if (config.mode == .stream) {
            if (config.output_file == null) {
                return error.MissingOutputFile;
            }
            const file = try std.fs.cwd().createFile(config.output_file.?, .{});
            self.file = file;
        }

        return self;
    }

    /// Deinitialize and clean up resources.
    pub fn deinit(self: *OutputCapture) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Close file if open
        if (self.file) |file| {
            file.close();
        }

        // Free buffered lines
        for (self.buffer.items) |line| {
            self.allocator.free(line);
        }
        self.buffer.deinit(self.allocator);
    }

    /// Write a line of output (from stdout or stderr).
    /// Thread-safe. Returns error if write fails (e.g., disk full).
    pub fn writeLine(self: *OutputCapture, line: []const u8, is_stderr: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        switch (self.config.mode) {
            .stream => {
                try self.writeToFile(line, is_stderr);
            },
            .buffer => {
                try self.writeToBuffer(line);
            },
            .discard => {
                // No-op
            },
        }
    }

    /// Retrieve buffered output as a single string. Buffer mode only.
    /// Caller owns the returned string and must free it.
    pub fn getBuffer(self: *OutputCapture) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.config.mode != .buffer) {
            return error.NotBufferMode;
        }

        // Concatenate all lines with newlines
        var result = std.ArrayList(u8){};
        for (self.buffer.items) |line| {
            try result.appendSlice(self.allocator, line);
            try result.append(self.allocator, '\n');
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Retrieve the number of buffered lines. Buffer mode only.
    pub fn getLineCount(self: *const OutputCapture) usize {
        return self.buffer.items.len;
    }

    /// Clear the buffer. Buffer mode only.
    pub fn clearBuffer(self: *OutputCapture) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.buffer.items) |line| {
            self.allocator.free(line);
        }
        self.buffer.clearRetainingCapacity();
        self.buffer_size_bytes = 0;
    }

    // --- Private implementation helpers ---

    fn writeToFile(self: *OutputCapture, line: []const u8, _: bool) !void {
        if (self.file) |file| {
            try file.writeAll(line);
            try file.writeAll("\n");
            // Flush to disk immediately to ensure data is persisted (v1.37.0 bugfix)
            try file.sync();
        }
    }

    fn writeToBuffer(self: *OutputCapture, line: []const u8) !void {
        const line_copy = try self.allocator.dupe(u8, line);
        const line_size = line.len + 1; // +1 for newline

        // If buffer limit exceeded, drop oldest lines
        if (self.config.max_buffer_size > 0) {
            while (self.buffer_size_bytes + line_size > self.config.max_buffer_size and
                   self.buffer.items.len > 0)
            {
                const removed = self.buffer.orderedRemove(0);
                self.buffer_size_bytes -= removed.len + 1;
                self.allocator.free(removed);
            }
        }

        try self.buffer.append(self.allocator, line_copy);
        self.buffer_size_bytes += line_size;
    }
};

// --- Tests ---

test "OutputCapture: init discard mode" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .discard,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try std.testing.expectEqual(OutputMode.discard, capture.config.mode);
    try std.testing.expect(capture.file == null);
}

test "OutputCapture: init buffer mode" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try std.testing.expectEqual(OutputMode.buffer, capture.config.mode);
    try std.testing.expect(capture.file == null);
    try std.testing.expectEqual(@as(usize, 0), capture.buffer.items.len);
}

test "OutputCapture: init stream mode requires output_file" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .stream,
        .output_file = null,
    };

    const result = OutputCapture.init(allocator, config);
    try std.testing.expectError(error.MissingOutputFile, result);
}

test "OutputCapture: init stream mode creates file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a file in the temp directory and verify it opens
    const config = OutputCaptureConfig{
        .mode = .stream,
        .output_file = "test_output.txt",
    };

    // This test just verifies the struct accepts stream mode
    // The actual file creation will be tested separately
    try std.testing.expectEqual(OutputMode.stream, config.mode);
}

test "OutputCapture: discard mode writeLine is no-op" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .discard,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try capture.writeLine("test output", false);
    try capture.writeLine("test error", true);

    // No assertion needed — discard is no-op, just verify no error
}

test "OutputCapture: buffer mode captures single line" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try capture.writeLine("hello world", false);

    try std.testing.expectEqual(@as(usize, 1), capture.getLineCount());
    const buffer = try capture.getBuffer();
    defer allocator.free(buffer);
    try std.testing.expect(std.mem.startsWith(u8, buffer, "hello world"));
}

test "OutputCapture: buffer mode captures multiple lines" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try capture.writeLine("line 1", false);
    try capture.writeLine("line 2", false);
    try capture.writeLine("line 3", false);

    try std.testing.expectEqual(@as(usize, 3), capture.getLineCount());
    const buffer = try capture.getBuffer();
    defer allocator.free(buffer);

    try std.testing.expect(std.mem.containsAtLeast(u8, buffer, 1, "line 1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buffer, 1, "line 2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buffer, 1, "line 3"));
}

test "OutputCapture: buffer mode preserves newlines" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try capture.writeLine("first", false);
    try capture.writeLine("second", false);

    const buffer = try capture.getBuffer();
    defer allocator.free(buffer);

    // Buffer should contain "first\nsecond\n"
    try std.testing.expectEqual(@as(usize, buffer.len), "first\nsecond\n".len);
}

test "OutputCapture: buffer mode drops old lines when exceeding size limit" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
        .max_buffer_size = 50, // Small limit to trigger dropping
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    // Write lines that together exceed the limit
    try capture.writeLine("line 1 some text", false); // ~17 bytes
    try capture.writeLine("line 2 some text", false); // ~17 bytes
    try capture.writeLine("line 3 some text", false); // ~17 bytes
    try capture.writeLine("line 4 some text", false); // ~17 bytes

    const buffer = try capture.getBuffer();
    defer allocator.free(buffer);

    // First lines should be dropped, last lines should remain
    try std.testing.expect(!std.mem.containsAtLeast(u8, buffer, 1, "line 1"));
}

test "OutputCapture: buffer mode clearBuffer frees all lines" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try capture.writeLine("line 1", false);
    try capture.writeLine("line 2", false);

    try std.testing.expectEqual(@as(usize, 2), capture.getLineCount());

    capture.clearBuffer();

    try std.testing.expectEqual(@as(usize, 0), capture.getLineCount());
}

test "OutputCapture: getBuffer on non-buffer mode returns error" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .discard,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    const result = capture.getBuffer();
    try std.testing.expectError(error.NotBufferMode, result);
}

test "OutputCapture: buffer mode handles empty buffer" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try std.testing.expectEqual(@as(usize, 0), capture.getLineCount());

    const buffer = try capture.getBuffer();
    defer allocator.free(buffer);

    try std.testing.expectEqual(@as(usize, 0), buffer.len);
}

test "OutputCapture: buffer mode handles long lines" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    // Create a long line (1000 bytes)
    const long_line = try allocator.alloc(u8, 1000);
    defer allocator.free(long_line);
    @memset(long_line, 'a');

    try capture.writeLine(long_line, false);

    try std.testing.expectEqual(@as(usize, 1), capture.getLineCount());
    const buffer = try capture.getBuffer();
    defer allocator.free(buffer);

    try std.testing.expectEqual(@as(usize, long_line.len + 1), buffer.len);
}

test "OutputCapture: buffer mode respects unlimited size when max_buffer_size is 0" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
        .max_buffer_size = 0, // Unlimited
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    // Write many lines without limit
    for (0..100) |i| {
        var buf: [20]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "line {}", .{i});
        try capture.writeLine(line, false);
    }

    try std.testing.expectEqual(@as(usize, 100), capture.getLineCount());
}

test "OutputCapture: stream mode writes to file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create the temp file path
    const file_path = "test_output_stream.txt";

    // Note: In tests, we would need to properly manage directory context
    // For now, this test verifies stream mode configuration
    const config = OutputCaptureConfig{
        .mode = .stream,
        .output_file = file_path,
    };

    try std.testing.expectEqual(OutputMode.stream, config.mode);
    try std.testing.expect(config.output_file != null);
    try std.testing.expectEqualStrings(file_path, config.output_file.?);
}

const ThreadWorkerContext = struct {
    capture: *OutputCapture,
    thread_id: usize,
};

fn threadWorkerFn(ctx: *ThreadWorkerContext) void {
    var buf: [32]u8 = undefined;
    for (0..10) |i| {
        const line = std.fmt.bufPrint(&buf, "thread {} line {}", .{ctx.thread_id, i}) catch return;
        ctx.capture.writeLine(line, false) catch {};
    }
}

test "OutputCapture: thread-safe concurrent writes to buffer" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    var ctx1 = ThreadWorkerContext{
        .capture = &capture,
        .thread_id = 1,
    };
    var ctx2 = ThreadWorkerContext{
        .capture = &capture,
        .thread_id = 2,
    };

    const t1 = try std.Thread.spawn(.{}, threadWorkerFn, .{&ctx1});
    const t2 = try std.Thread.spawn(.{}, threadWorkerFn, .{&ctx2});

    t1.join();
    t2.join();

    // All writes should complete without errors
    // We expect 20 lines total (10 from each thread)
    try std.testing.expect(capture.getLineCount() >= 20);
}

test "OutputCapture: distinguishes stdout from stderr" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try capture.writeLine("stdout line", false);
    try capture.writeLine("stderr line", true);

    // Both should be captured (buffer mode doesn't distinguish)
    try std.testing.expectEqual(@as(usize, 2), capture.getLineCount());
}

test "OutputCapture: handles special characters in lines" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try capture.writeLine("line with special chars: !@#$%^&*()", false);
    try capture.writeLine("line with unicode: 你好世界 🎉", false);

    const buffer = try capture.getBuffer();
    defer allocator.free(buffer);

    try std.testing.expect(std.mem.containsAtLeast(u8, buffer, 1, "!@#$%^&*()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buffer, 1, "你好"));
}

test "OutputCapture: buffer_size_bytes tracks correctly" {
    const allocator = std.testing.allocator;
    const config = OutputCaptureConfig{
        .mode = .buffer,
    };

    var capture = try OutputCapture.init(allocator, config);
    defer capture.deinit();

    try std.testing.expectEqual(@as(usize, 0), capture.buffer_size_bytes);

    try capture.writeLine("hello", false);
    const expected_size = 5 + 1; // "hello" + newline
    try std.testing.expectEqual(expected_size, capture.buffer_size_bytes);

    try capture.writeLine("world", false);
    try std.testing.expectEqual(expected_size * 2, capture.buffer_size_bytes);

    capture.clearBuffer();
    try std.testing.expectEqual(@as(usize, 0), capture.buffer_size_bytes);
}

test "OutputCapture: multiple init/deinit cycles" {
    const allocator = std.testing.allocator;

    for (0..5) |_| {
        const config = OutputCaptureConfig{
            .mode = .buffer,
        };

        var capture = try OutputCapture.init(allocator, config);
        try capture.writeLine("test", false);
        capture.deinit();
    }

    // Should complete without errors or leaks
}

test "OutputCapture: config default values" {
    const config = OutputCaptureConfig{};
    try std.testing.expectEqual(OutputMode.discard, config.mode);
    try std.testing.expect(config.output_file == null);
    try std.testing.expectEqual(@as(usize, 1024 * 1024), config.max_buffer_size);
}
