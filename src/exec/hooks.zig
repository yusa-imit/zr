const std = @import("std");
const process = @import("process.zig");

/// Hook execution point
pub const HookPoint = enum {
    before, // Execute before task starts
    after, // Execute after task completes (any status)
    success, // Execute only on successful completion
    failure, // Execute only on failure
    timeout, // Execute only on timeout
};

/// Hook failure handling strategy
pub const HookFailureStrategy = enum {
    continue_task, // Continue with task even if hook fails
    abort_task, // Abort task if hook fails
};

/// Context passed to hook commands
pub const HookContext = struct {
    task_name: []const u8,
    exit_code: ?u8, // null for 'before' hooks
    duration_ms: ?u64, // null for 'before' hooks
    error_message: ?[]const u8, // null on success
};

/// Hook definition
pub const Hook = struct {
    cmd: []const u8,
    point: HookPoint,
    failure_strategy: HookFailureStrategy = .continue_task,
    working_dir: ?[]const u8 = null,
    env: ?std.StringHashMap([]const u8) = null,

    pub fn deinit(self: *Hook, allocator: std.mem.Allocator) void {
        if (self.env) |*e| {
            var it = e.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            e.deinit();
        }
    }
};

/// Hook execution result
pub const HookResult = struct {
    success: bool,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    duration_ms: u64,

    pub fn deinit(self: HookResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// Hook executor
pub const HookExecutor = struct {
    allocator: std.mem.Allocator,
    verbose: bool = false,

    pub fn init(allocator: std.mem.Allocator) HookExecutor {
        return .{
            .allocator = allocator,
        };
    }

    /// Execute a hook with the given context
    ///
    /// KNOWN ISSUE (v1.24.0): Integration tests for hooks leak ~64KB per test invocation.
    /// - Unit tests in this file pass without leaks
    /// - Integration tests (full subprocess) leak one 64KB block per test
    /// - Likely cause: std.process.getEnvMap() arena allocation not being freed
    /// - Pattern: addresses like 0x11e7e0000 (page-aligned, 64KB blocks)
    /// - Investigation needed: compare subprocess env handling vs direct calls
    /// - Minimal reproduction: /tmp/test_hook_leak.zig does NOT leak
    /// - Tests affected: 895-906 (excluding 899 which is skipped)
    pub fn execute(
        self: *HookExecutor,
        hook: *const Hook,
        context: HookContext,
    ) !HookResult {
        const start_time = std.time.milliTimestamp();

        // Expand environment variables in command
        const expanded_cmd = try self.expandCommand(hook.cmd, context);
        defer self.allocator.free(expanded_cmd);

        if (self.verbose) {
            std.debug.print("Executing hook: {s}\n", .{expanded_cmd});
        }

        // Build environment - get current environment
        var env_map = try std.process.getEnvMap(self.allocator);
        defer env_map.deinit();

        // Add hook-specific variables
        // Note: EnvMap.put() duplicates strings internally, so we don't need to manage ownership
        try env_map.put("ZR_TASK_NAME", context.task_name);
        if (context.exit_code) |code| {
            const code_str = try std.fmt.allocPrint(self.allocator, "{d}", .{code});
            defer self.allocator.free(code_str);
            try env_map.put("ZR_EXIT_CODE", code_str);
        }
        if (context.duration_ms) |duration| {
            const duration_str = try std.fmt.allocPrint(self.allocator, "{d}", .{duration});
            defer self.allocator.free(duration_str);
            try env_map.put("ZR_DURATION_MS", duration_str);
        }
        if (context.error_message) |err_msg| {
            try env_map.put("ZR_ERROR_MESSAGE", err_msg);
        }

        // Add user-defined environment variables
        if (hook.env) |user_env| {
            var it = user_env.iterator();
            while (it.next()) |entry| {
                try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Execute command
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", expanded_cmd },
            .cwd = hook.working_dir,
            .env_map = &env_map,
            .max_output_bytes = 10 * 1024 * 1024, // 10MB limit
        }) catch |err| {
            const stderr = try std.fmt.allocPrint(self.allocator, "Failed to execute hook: {s}", .{@errorName(err)});
            return HookResult{
                .success = false,
                .exit_code = 255,
                .stdout = try self.allocator.dupe(u8, ""),
                .stderr = stderr,
                .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
            };
        };

        const end_time = std.time.milliTimestamp();
        const duration_ms: u64 = @intCast(end_time - start_time);

        const success = switch (result.term) {
            .Exited => |code| code == 0,
            else => false,
        };

        const exit_code: u8 = switch (result.term) {
            .Exited => |code| code,
            else => 255,
        };

        return HookResult{
            .success = success,
            .exit_code = exit_code,
            .stdout = result.stdout,
            .stderr = result.stderr,
            .duration_ms = duration_ms,
        };
    }

    /// Expand environment variables in command string
    fn expandCommand(self: *HookExecutor, cmd: []const u8, context: HookContext) ![]u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < cmd.len) {
            if (cmd[i] == '$' and i + 1 < cmd.len and cmd[i + 1] == '{') {
                // Find closing brace
                const start = i + 2;
                var end = start;
                while (end < cmd.len and cmd[end] != '}') : (end += 1) {}

                if (end < cmd.len) {
                    const var_name = cmd[start..end];
                    const value = try self.getContextVariable(var_name, context);
                    // Check if we need to free this - only allocated strings
                    const is_allocated = std.mem.eql(u8, var_name, "EXIT_CODE") or std.mem.eql(u8, var_name, "DURATION_MS");
                    defer if (is_allocated and !std.mem.eql(u8, value, "N/A")) self.allocator.free(value);
                    try result.appendSlice(self.allocator, value);
                    i = end + 1;
                } else {
                    // No closing brace, treat as literal
                    try result.append(self.allocator, cmd[i]);
                    i += 1;
                }
            } else {
                try result.append(self.allocator, cmd[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    fn getContextVariable(self: *HookExecutor, name: []const u8, context: HookContext) ![]const u8 {
        if (std.mem.eql(u8, name, "TASK_NAME")) {
            return context.task_name;
        } else if (std.mem.eql(u8, name, "EXIT_CODE")) {
            if (context.exit_code) |code| {
                return try std.fmt.allocPrint(self.allocator, "{d}", .{code});
            }
            return "N/A";
        } else if (std.mem.eql(u8, name, "DURATION_MS")) {
            if (context.duration_ms) |duration| {
                return try std.fmt.allocPrint(self.allocator, "{d}", .{duration});
            }
            return "N/A";
        } else if (std.mem.eql(u8, name, "ERROR_MESSAGE")) {
            if (context.error_message) |msg| {
                return msg;
            }
            return "";
        }
        // Unknown variable, return empty string
        return "";
    }
};

test "HookExecutor.expandCommand" {
    const allocator = std.testing.allocator;
    var executor = HookExecutor.init(allocator);

    const ctx = HookContext{
        .task_name = "test-task",
        .exit_code = 42,
        .duration_ms = 1000,
        .error_message = null,
    };

    const cmd = "echo Task: ${TASK_NAME}, Exit: ${EXIT_CODE}, Duration: ${DURATION_MS}ms";
    const expanded = try executor.expandCommand(cmd, ctx);
    defer allocator.free(expanded);

    try std.testing.expectEqualStrings("echo Task: test-task, Exit: 42, Duration: 1000ms", expanded);
}

test "HookExecutor.expandCommand with missing context" {
    const allocator = std.testing.allocator;
    var executor = HookExecutor.init(allocator);

    const ctx = HookContext{
        .task_name = "test-task",
        .exit_code = null,
        .duration_ms = null,
        .error_message = null,
    };

    const cmd = "echo Exit: ${EXIT_CODE}";
    const expanded = try executor.expandCommand(cmd, ctx);
    defer allocator.free(expanded);

    try std.testing.expectEqualStrings("echo Exit: N/A", expanded);
}

test "HookExecutor.execute simple command" {
    const allocator = std.testing.allocator;
    var executor = HookExecutor.init(allocator);

    const hook = Hook{
        .cmd = "echo 'hook executed'",
        .point = .before,
    };

    const ctx = HookContext{
        .task_name = "test",
        .exit_code = null,
        .duration_ms = null,
        .error_message = null,
    };

    const result = try executor.execute(&hook, ctx);
    defer result.deinit(allocator);

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hook executed") != null);
}

test "HookExecutor.execute with environment variable expansion" {
    const allocator = std.testing.allocator;
    var executor = HookExecutor.init(allocator);

    const hook = Hook{
        .cmd = "echo ${TASK_NAME}",
        .point = .before,
    };

    const ctx = HookContext{
        .task_name = "my-task",
        .exit_code = null,
        .duration_ms = null,
        .error_message = null,
    };

    const result = try executor.execute(&hook, ctx);
    defer result.deinit(allocator);

    try std.testing.expect(result.success);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "my-task") != null);
}

test "HookExecutor.execute failing command" {
    const allocator = std.testing.allocator;
    var executor = HookExecutor.init(allocator);

    const hook = Hook{
        .cmd = "exit 1",
        .point = .before,
    };

    const ctx = HookContext{
        .task_name = "test",
        .exit_code = null,
        .duration_ms = null,
        .error_message = null,
    };

    const result = try executor.execute(&hook, ctx);
    defer result.deinit(allocator);

    try std.testing.expect(!result.success);
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}
