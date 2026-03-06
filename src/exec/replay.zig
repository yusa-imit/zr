const std = @import("std");
const loader = @import("../config/loader.zig");
const timeline = @import("timeline.zig");

/// Captured context for a failed task execution.
pub const FailureContext = struct {
    /// Task name.
    task_name: []const u8,
    /// Command that was executed.
    cmd: []const u8,
    /// Working directory.
    cwd: ?[]const u8,
    /// Environment variables at time of failure.
    env: ?[]const [2][]const u8,
    /// Exit code.
    exit_code: u8,
    /// Stdout captured during execution.
    stdout: []const u8,
    /// Stderr captured during execution.
    stderr: []const u8,
    /// Timestamp when failure occurred (nanoseconds).
    timestamp_ns: u64,
    /// Timeline events leading up to failure.
    timeline_events: []timeline.TimelineEvent,

    pub fn deinit(self: *FailureContext, allocator: std.mem.Allocator) void {
        allocator.free(self.task_name);
        allocator.free(self.cmd);
        if (self.cwd) |cwd| allocator.free(cwd);
        if (self.env) |env| {
            for (env) |kv| {
                allocator.free(kv[0]);
                allocator.free(kv[1]);
            }
            allocator.free(env);
        }
        allocator.free(self.stdout);
        allocator.free(self.stderr);
        for (self.timeline_events) |event| {
            allocator.free(event.task_name);
            if (event.context) |ctx| allocator.free(ctx);
        }
        allocator.free(self.timeline_events);
    }

    /// Format the failure context as a diagnostic report.
    pub fn formatReport(self: *const FailureContext, writer: anytype) !void {
        try writer.writeAll("=== Task Failure Report ===\n");
        try writer.print("Task: {s}\n", .{self.task_name});
        try writer.print("Command: {s}\n", .{self.cmd});
        if (self.cwd) |cwd| {
            try writer.print("Working Directory: {s}\n", .{cwd});
        }
        try writer.print("Exit Code: {d}\n", .{self.exit_code});
        try writer.print("Timestamp: {d}ns\n", .{self.timestamp_ns});

        if (self.env) |env| {
            try writer.writeAll("\nEnvironment Variables:\n");
            for (env) |kv| {
                try writer.print("  {s}={s}\n", .{ kv[0], kv[1] });
            }
        }

        if (self.stdout.len > 0) {
            try writer.writeAll("\nStdout:\n");
            try writer.writeAll(self.stdout);
            if (!std.mem.endsWith(u8, self.stdout, "\n")) {
                try writer.writeByte('\n');
            }
        }

        if (self.stderr.len > 0) {
            try writer.writeAll("\nStderr:\n");
            try writer.writeAll(self.stderr);
            if (!std.mem.endsWith(u8, self.stderr, "\n")) {
                try writer.writeByte('\n');
            }
        }

        if (self.timeline_events.len > 0) {
            try writer.writeAll("\nTimeline:\n");
            for (self.timeline_events) |event| {
                try event.format("", .{}, writer);
                try writer.writeByte('\n');
            }
        }
    }
};

/// Replay manager for failed task executions.
pub const ReplayManager = struct {
    allocator: std.mem.Allocator,
    /// Storage directory for failure contexts.
    storage_dir: []const u8,
    /// Map of task name to failure context.
    failures: std.StringHashMap(FailureContext),

    pub fn init(allocator: std.mem.Allocator, storage_dir: []const u8) !ReplayManager {
        return .{
            .allocator = allocator,
            .storage_dir = try allocator.dupe(u8, storage_dir),
            .failures = std.StringHashMap(FailureContext).init(allocator),
        };
    }

    pub fn deinit(self: *ReplayManager) void {
        var it = self.failures.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var ctx = entry.value_ptr.*;
            ctx.deinit(self.allocator);
        }
        self.failures.deinit();
        self.allocator.free(self.storage_dir);
    }

    /// Capture a failure context for later replay.
    pub fn captureFailure(
        self: *ReplayManager,
        task_name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        env: ?[]const [2][]const u8,
        exit_code: u8,
        stdout: []const u8,
        stderr: []const u8,
        timeline_events: []const timeline.TimelineEvent,
    ) !void {
        // Dupe all fields for owned storage
        const owned_task_name = try self.allocator.dupe(u8, task_name);
        errdefer self.allocator.free(owned_task_name);

        const owned_cmd = try self.allocator.dupe(u8, cmd);
        errdefer self.allocator.free(owned_cmd);

        const owned_cwd = if (cwd) |c| try self.allocator.dupe(u8, c) else null;
        errdefer if (owned_cwd) |c| self.allocator.free(c);

        const owned_env = if (env) |e| blk: {
            const arr = try self.allocator.alloc([2][]const u8, e.len);
            errdefer self.allocator.free(arr);
            var i: usize = 0;
            errdefer {
                for (arr[0..i]) |kv| {
                    self.allocator.free(kv[0]);
                    self.allocator.free(kv[1]);
                }
            }
            for (e, 0..) |kv, j| {
                arr[j] = .{
                    try self.allocator.dupe(u8, kv[0]),
                    try self.allocator.dupe(u8, kv[1]),
                };
                i = j + 1;
            }
            break :blk arr;
        } else null;
        errdefer if (owned_env) |e| {
            for (e) |kv| {
                self.allocator.free(kv[0]);
                self.allocator.free(kv[1]);
            }
            self.allocator.free(e);
        };

        const owned_stdout = try self.allocator.dupe(u8, stdout);
        errdefer self.allocator.free(owned_stdout);

        const owned_stderr = try self.allocator.dupe(u8, stderr);
        errdefer self.allocator.free(owned_stderr);

        const owned_timeline = try self.allocator.alloc(timeline.TimelineEvent, timeline_events.len);
        errdefer self.allocator.free(owned_timeline);
        var timeline_duped: usize = 0;
        errdefer {
            for (owned_timeline[0..timeline_duped]) |event| {
                self.allocator.free(event.task_name);
                if (event.context) |ctx| self.allocator.free(ctx);
            }
        }
        for (timeline_events, 0..) |event, i| {
            owned_timeline[i] = .{
                .event_type = event.event_type,
                .task_name = try self.allocator.dupe(u8, event.task_name),
                .timestamp_ns = event.timestamp_ns,
                .context = if (event.context) |ctx| try self.allocator.dupe(u8, ctx) else null,
            };
            timeline_duped = i + 1;
        }

        const context = FailureContext{
            .task_name = owned_task_name,
            .cmd = owned_cmd,
            .cwd = owned_cwd,
            .env = owned_env,
            .exit_code = exit_code,
            .stdout = owned_stdout,
            .stderr = owned_stderr,
            .timestamp_ns = @as(u64, @intCast(@max(0, std.time.nanoTimestamp()))),
            .timeline_events = owned_timeline,
        };

        // Replace if already exists
        if (self.failures.fetchRemove(task_name)) |existing| {
            self.allocator.free(existing.key);
            var old_ctx = existing.value;
            old_ctx.deinit(self.allocator);
        }

        const key = try self.allocator.dupe(u8, task_name);
        try self.failures.put(key, context);
    }

    /// Get a failure context by task name.
    pub fn getFailure(self: *const ReplayManager, task_name: []const u8) ?*const FailureContext {
        return self.failures.getPtr(task_name);
    }

    /// List all captured failure task names.
    pub fn listFailures(self: *const ReplayManager, allocator: std.mem.Allocator) ![][]const u8 {
        const names = try allocator.alloc([]const u8, self.failures.count());
        var i: usize = 0;
        var it = self.failures.keyIterator();
        while (it.next()) |key| : (i += 1) {
            names[i] = key.*;
        }
        return names;
    }

    /// Clear all captured failures.
    pub fn clearAll(self: *ReplayManager) void {
        var it = self.failures.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var ctx = entry.value_ptr.*;
            ctx.deinit(self.allocator);
        }
        self.failures.clearRetainingCapacity();
    }
};

test "FailureContext basic" {
    const ctx = FailureContext{
        .task_name = "build",
        .cmd = "zig build",
        .cwd = "/tmp/project",
        .env = null,
        .exit_code = 1,
        .stdout = "Building...\n",
        .stderr = "error: undefined symbol\n",
        .timestamp_ns = 1000000000,
        .timeline_events = &[_]timeline.TimelineEvent{},
    };

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try ctx.formatReport(buf.writer(std.testing.allocator));
    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Task: build") != null);
}

test "ReplayManager capture and retrieve" {
    var mgr = try ReplayManager.init(std.testing.allocator, "/tmp/replay");
    defer mgr.deinit();

    const events = [_]timeline.TimelineEvent{
        .{
            .event_type = .started,
            .task_name = "build",
            .timestamp_ns = 100,
        },
        .{
            .event_type = .completed,
            .task_name = "build",
            .timestamp_ns = 200,
        },
    };

    try mgr.captureFailure(
        "build",
        "zig build",
        "/tmp",
        null,
        1,
        "output",
        "error",
        &events,
    );

    const failure = mgr.getFailure("build");
    try std.testing.expect(failure != null);
    try std.testing.expectEqualStrings("build", failure.?.task_name);
    try std.testing.expectEqual(@as(u8, 1), failure.?.exit_code);
}

test "ReplayManager list and clear" {
    var mgr = try ReplayManager.init(std.testing.allocator, "/tmp/replay");
    defer mgr.deinit();

    try mgr.captureFailure("build", "cmd1", null, null, 1, "", "", &[_]timeline.TimelineEvent{});
    try mgr.captureFailure("test", "cmd2", null, null, 2, "", "", &[_]timeline.TimelineEvent{});

    const names = try mgr.listFailures(std.testing.allocator);
    defer std.testing.allocator.free(names);

    try std.testing.expectEqual(@as(usize, 2), names.len);

    mgr.clearAll();
    try std.testing.expectEqual(@as(usize, 0), mgr.failures.count());
}
