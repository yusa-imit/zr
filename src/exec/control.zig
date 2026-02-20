/// Interactive task control — cancel/retry/pause signals for running tasks.
/// Thread-safe control flags and operations for managing task execution lifecycle.
const std = @import("std");

pub const ControlSignal = enum(u8) {
    none = 0,
    cancel = 1,
    pause = 2,
    resume_task = 3,
};

/// Thread-safe control handle for a running task.
/// Shared between execution thread and UI/control thread.
pub const TaskControl = struct {
    /// Current control signal (atomic u8)
    signal: std.atomic.Value(u8),
    /// Task name (owned)
    task_name: []const u8,
    /// Process ID (set after spawn, 0 means not set)
    pid: std.atomic.Value(i32),
    /// Whether task has finished (atomic)
    finished: std.atomic.Value(bool),
    /// Allocator used for task_name
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, task_name: []const u8) !*TaskControl {
        const ctrl = try allocator.create(TaskControl);
        ctrl.* = TaskControl{
            .signal = std.atomic.Value(u8).init(@intFromEnum(ControlSignal.none)),
            .task_name = try allocator.dupe(u8, task_name),
            .pid = std.atomic.Value(i32).init(0),
            .finished = std.atomic.Value(bool).init(false),
            .allocator = allocator,
        };
        return ctrl;
    }

    pub fn deinit(self: *TaskControl) void {
        self.allocator.free(self.task_name);
        self.allocator.destroy(self);
    }

    /// Set the process ID after spawning.
    pub fn setPid(self: *TaskControl, pid: std.process.Child.Id) void {
        self.pid.store(pid, .release);
    }

    /// Get the process ID (returns 0 if not set).
    pub fn getPid(self: *TaskControl) std.process.Child.Id {
        return self.pid.load(.acquire);
    }

    /// Request cancellation of the running task.
    pub fn requestCancel(self: *TaskControl) void {
        self.signal.store(@intFromEnum(ControlSignal.cancel), .release);
    }

    /// Request pause of the running task (SIGSTOP).
    pub fn requestPause(self: *TaskControl) void {
        self.signal.store(@intFromEnum(ControlSignal.pause), .release);
    }

    /// Request resume of a paused task (SIGCONT).
    pub fn requestResume(self: *TaskControl) void {
        self.signal.store(@intFromEnum(ControlSignal.resume_task), .release);
    }

    /// Check if cancellation was requested.
    pub fn isCancelRequested(self: *TaskControl) bool {
        return self.signal.load(.acquire) == @intFromEnum(ControlSignal.cancel);
    }

    /// Check if pause was requested.
    pub fn isPauseRequested(self: *TaskControl) bool {
        return self.signal.load(.acquire) == @intFromEnum(ControlSignal.pause);
    }

    /// Check if resume was requested.
    pub fn isResumeRequested(self: *TaskControl) bool {
        return self.signal.load(.acquire) == @intFromEnum(ControlSignal.resume_task);
    }

    /// Clear the current signal (after processing).
    pub fn clearSignal(self: *TaskControl) void {
        self.signal.store(@intFromEnum(ControlSignal.none), .release);
    }

    /// Mark task as finished.
    pub fn markFinished(self: *TaskControl) void {
        self.finished.store(true, .release);
    }

    /// Check if task has finished.
    pub fn isFinished(self: *TaskControl) bool {
        return self.finished.load(.acquire);
    }
};

/// Global registry for active task controls.
/// Allows UI threads to look up and control running tasks by name.
pub const ControlRegistry = struct {
    mutex: std.Thread.Mutex,
    controls: std.StringHashMapUnmanaged(*TaskControl),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ControlRegistry {
        return ControlRegistry{
            .mutex = std.Thread.Mutex{},
            .controls = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ControlRegistry) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.controls.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        self.controls.deinit(self.allocator);
    }

    /// Register a task control (takes ownership of ctrl).
    pub fn register(self: *ControlRegistry, ctrl: *TaskControl) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const key = try self.allocator.dupe(u8, ctrl.task_name);
        errdefer self.allocator.free(key);

        try self.controls.put(self.allocator, key, ctrl);
    }

    /// Unregister a task control (caller must deinit ctrl).
    pub fn unregister(self: *ControlRegistry, task_name: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.controls.fetchRemove(task_name)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Find a task control by name (returns null if not found or finished).
    pub fn find(self: *ControlRegistry, task_name: []const u8) ?*TaskControl {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ctrl = self.controls.get(task_name) orelse return null;
        if (ctrl.isFinished()) return null;
        return ctrl;
    }

    /// Get all active task names (caller owns returned slice and strings).
    pub fn getActiveTaskNames(self: *ControlRegistry, allocator: std.mem.Allocator) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (names.items) |name| allocator.free(name);
            names.deinit(allocator);
        }

        var it = self.controls.iterator();
        while (it.next()) |entry| {
            if (!entry.value_ptr.*.isFinished()) {
                try names.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        return names.toOwnedSlice(allocator);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "TaskControl: init and basic operations" {
    const allocator = std.testing.allocator;

    var ctrl = try TaskControl.init(allocator, "test-task");
    defer ctrl.deinit();

    try std.testing.expectEqualStrings("test-task", ctrl.task_name);
    try std.testing.expectEqual(false, ctrl.isCancelRequested());
    try std.testing.expectEqual(false, ctrl.isFinished());

    ctrl.requestCancel();
    try std.testing.expectEqual(true, ctrl.isCancelRequested());

    ctrl.clearSignal();
    try std.testing.expectEqual(false, ctrl.isCancelRequested());

    ctrl.markFinished();
    try std.testing.expectEqual(true, ctrl.isFinished());
}

test "TaskControl: pause and resume" {
    const allocator = std.testing.allocator;

    var ctrl = try TaskControl.init(allocator, "pausable");
    defer ctrl.deinit();

    ctrl.requestPause();
    try std.testing.expectEqual(true, ctrl.isPauseRequested());
    try std.testing.expectEqual(false, ctrl.isResumeRequested());

    ctrl.requestResume();
    try std.testing.expectEqual(true, ctrl.isResumeRequested());
    try std.testing.expectEqual(false, ctrl.isPauseRequested());
}

test "ControlRegistry: register and find" {
    const allocator = std.testing.allocator;

    var registry = ControlRegistry.init(allocator);
    defer registry.deinit();

    var ctrl = try TaskControl.init(allocator, "my-task");

    try registry.register(ctrl);

    const found = registry.find("my-task");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("my-task", found.?.task_name);

    registry.unregister("my-task");
    ctrl.deinit();

    const not_found = registry.find("my-task");
    try std.testing.expect(not_found == null);
}

test "ControlRegistry: finished tasks not found" {
    const allocator = std.testing.allocator;

    var registry = ControlRegistry.init(allocator);
    defer registry.deinit();

    var ctrl = try TaskControl.init(allocator, "finished-task");

    try registry.register(ctrl);

    ctrl.markFinished();

    const found = registry.find("finished-task");
    try std.testing.expect(found == null); // finished tasks not returned

    registry.unregister("finished-task");
    ctrl.deinit();
}

test "ControlRegistry: getActiveTaskNames" {
    const allocator = std.testing.allocator;

    var registry = ControlRegistry.init(allocator);
    defer registry.deinit();

    var ctrl1 = try TaskControl.init(allocator, "task-a");
    var ctrl2 = try TaskControl.init(allocator, "task-b");
    var ctrl3 = try TaskControl.init(allocator, "task-c");

    try registry.register(ctrl1);
    try registry.register(ctrl2);
    try registry.register(ctrl3);

    ctrl2.markFinished(); // task-b is finished

    const active = try registry.getActiveTaskNames(allocator);
    defer {
        for (active) |name| allocator.free(name);
        allocator.free(active);
    }

    // Should have 2 active tasks (task-a and task-c)
    try std.testing.expectEqual(@as(usize, 2), active.len);

    // Check names (order may vary)
    var found_a = false;
    var found_c = false;
    for (active) |name| {
        if (std.mem.eql(u8, name, "task-a")) found_a = true;
        if (std.mem.eql(u8, name, "task-c")) found_c = true;
    }
    try std.testing.expect(found_a);
    try std.testing.expect(found_c);

    registry.unregister("task-a");
    registry.unregister("task-b");
    registry.unregister("task-c");
    ctrl1.deinit();
    ctrl2.deinit();
    ctrl3.deinit();
}
