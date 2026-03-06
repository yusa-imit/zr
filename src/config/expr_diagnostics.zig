const std = @import("std");

/// Stack frame representing a single level in expression evaluation.
pub const StackFrame = struct {
    /// The expression being evaluated at this level.
    expr: []const u8,
    /// Type of expression (e.g., "OR", "AND", "platform", "file.exists", etc.).
    expr_type: []const u8,
    /// Line number in the config file (if available).
    line: ?usize = null,
    /// Column number in the config file (if available).
    column: ?usize = null,

    pub fn format(
        self: StackFrame,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        if (self.line) |l| {
            if (self.column) |c| {
                try writer.print("  at {s} (line {d}, col {d}): {s}", .{
                    self.expr_type, l, c, self.expr,
                });
                return;
            }
            try writer.print("  at {s} (line {d}): {s}", .{
                self.expr_type, l, self.expr,
            });
            return;
        }
        try writer.print("  at {s}: {s}", .{ self.expr_type, self.expr });
    }
};

/// Diagnostic context for tracking expression evaluation stack.
pub const DiagContext = struct {
    allocator: std.mem.Allocator,
    /// Stack of frames representing the evaluation path.
    stack: std.ArrayList(StackFrame),
    /// Whether to collect stack traces (disabled in performance-critical paths).
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) DiagContext {
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(StackFrame){},
        };
    }

    pub fn deinit(self: *DiagContext) void {
        self.stack.deinit(self.allocator);
    }

    /// Push a new frame onto the stack.
    pub fn push(self: *DiagContext, frame: StackFrame) !void {
        if (!self.enabled) return;
        try self.stack.append(self.allocator, frame);
    }

    /// Pop the top frame from the stack.
    pub fn pop(self: *DiagContext) void {
        if (!self.enabled or self.stack.items.len == 0) return;
        _ = self.stack.pop();
    }

    /// Format the stack trace as a string.
    pub fn formatStackTrace(self: *const DiagContext, writer: anytype) !void {
        if (self.stack.items.len == 0) {
            try writer.writeAll("  (no stack trace available)\n");
            return;
        }

        try writer.writeAll("Expression evaluation stack:\n");
        // Print in reverse order (most recent first)
        var i = self.stack.items.len;
        while (i > 0) {
            i -= 1;
            try self.stack.items[i].format("", .{}, writer);
            try writer.writeByte('\n');
        }
    }
};

/// Error with diagnostic context.
pub const DiagnosticError = struct {
    /// The error that occurred.
    err: anyerror,
    /// Diagnostic context with stack trace.
    context: DiagContext,
    /// Human-readable error message.
    message: []const u8,

    pub fn deinit(self: *DiagnosticError, allocator: std.mem.Allocator) void {
        self.context.deinit();
        allocator.free(self.message);
    }

    /// Format the full diagnostic error with stack trace.
    pub fn format(
        self: DiagnosticError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Expression Error: {s}\n", .{self.message});
        try writer.print("Error type: {s}\n", .{@errorName(self.err)});
        try self.context.formatStackTrace(writer);
    }
};

test "StackFrame formatting" {
    const frame1 = StackFrame{
        .expr = "platform == \"linux\"",
        .expr_type = "platform",
        .line = 42,
        .column = 10,
    };

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try frame1.format("", .{}, buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings(
        "  at platform (line 42, col 10): platform == \"linux\"",
        buf.items,
    );
}

test "DiagContext stack operations" {
    var ctx = DiagContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{
        .expr = "platform == \"linux\" && arch == \"x86_64\"",
        .expr_type = "AND",
    });
    try ctx.push(.{
        .expr = "platform == \"linux\"",
        .expr_type = "platform",
    });

    try std.testing.expectEqual(@as(usize, 2), ctx.stack.items.len);

    ctx.pop();
    try std.testing.expectEqual(@as(usize, 1), ctx.stack.items.len);
}

test "DiagContext stack trace formatting" {
    var ctx = DiagContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{
        .expr = "outer expression",
        .expr_type = "OR",
        .line = 10,
    });
    try ctx.push(.{
        .expr = "inner expression",
        .expr_type = "platform",
        .line = 10,
        .column = 15,
    });

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try ctx.formatStackTrace(buf.writer(std.testing.allocator));

    const expected =
        \\Expression evaluation stack:
        \\  at platform (line 10, col 15): inner expression
        \\  at OR (line 10): outer expression
        \\
    ;
    try std.testing.expectEqualStrings(expected, buf.items);
}
