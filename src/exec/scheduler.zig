const std = @import("std");
const loader = @import("../config/loader.zig");
const dag_mod = @import("../graph/dag.zig");
const topo_sort = @import("../graph/topo_sort.zig");
const process = @import("process.zig");

pub const SchedulerError = error{
    TaskNotFound,
    CycleDetected,
    BuildFailed,
    NodeNotFound,
} || std.mem.Allocator.Error;

pub const SchedulerConfig = struct {
    /// Maximum number of tasks to run concurrently within a level.
    /// Default 0 means "use all CPU cores".
    max_jobs: u32 = 0,
    /// Whether child processes inherit parent stdio.
    /// Set to false in tests to prevent deadlock in background test environments.
    inherit_stdio: bool = true,
};

pub const TaskResult = struct {
    task_name: []const u8,
    success: bool,
    exit_code: u8,
    duration_ms: u64,
};

pub const ScheduleResult = struct {
    results: std.ArrayList(TaskResult),
    total_success: bool,

    pub fn deinit(self: *ScheduleResult, allocator: std.mem.Allocator) void {
        for (self.results.items) |result| {
            allocator.free(result.task_name);
        }
        self.results.deinit(allocator);
    }
};

/// Context passed to each worker thread.
const WorkerCtx = struct {
    allocator: std.mem.Allocator,
    task_name: []const u8, // owned slice, freed by worker after use
    cmd: []const u8,
    cwd: ?[]const u8,
    inherit_stdio: bool,
    timeout_ms: ?u64,
    allow_failure: bool,
    /// Pointer to shared results list — protected by results_mutex.
    results: *std.ArrayList(TaskResult),
    results_mutex: *std.Thread.Mutex,
    /// Semaphore used to limit concurrency; released when worker finishes.
    semaphore: *std.Thread.Semaphore,
    /// Set to true if any task fails; checked before launching new tasks.
    failed: *std.atomic.Value(bool),
};

fn workerFn(ctx: WorkerCtx) void {
    defer {
        ctx.semaphore.post();
        ctx.allocator.free(ctx.task_name);
    }

    // Run the process
    const proc_result = process.run(ctx.allocator, .{
        .cmd = ctx.cmd,
        .cwd = ctx.cwd,
        .env = null,
        .inherit_stdio = ctx.inherit_stdio,
        .timeout_ms = ctx.timeout_ms,
    }) catch process.ProcessResult{
        .exit_code = 1,
        .duration_ms = 0,
        .success = false,
    };

    // Allocate an owned copy of the name for TaskResult
    const owned_name = ctx.allocator.dupe(u8, ctx.task_name) catch {
        if (!proc_result.success and !ctx.allow_failure) ctx.failed.store(true, .release);
        return;
    };

    ctx.results_mutex.lock();
    defer ctx.results_mutex.unlock();

    ctx.results.append(ctx.allocator, .{
        .task_name = owned_name,
        .success = proc_result.success,
        .exit_code = proc_result.exit_code,
        .duration_ms = proc_result.duration_ms,
    }) catch {
        ctx.allocator.free(owned_name);
        if (!proc_result.success and !ctx.allow_failure) ctx.failed.store(true, .release);
        return;
    };

    // Only propagate failure to global flag if allow_failure is not set
    if (!proc_result.success and !ctx.allow_failure) {
        ctx.failed.store(true, .release);
    }
}

/// Collect all transitive dependencies of the requested tasks.
/// Returns a StringHashMap(void) of all task names that need to run.
fn collectDeps(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    task_names: []const []const u8,
) !std.StringHashMap(void) {
    var needed = std.StringHashMap(void).init(allocator);
    errdefer needed.deinit();

    // Stack-based DFS to find all transitive deps
    var stack = std.ArrayList([]const u8){};
    defer stack.deinit(allocator);

    for (task_names) |name| {
        try stack.append(allocator, name);
    }

    while (stack.pop()) |name| {
        if (needed.contains(name)) continue;

        const task = config.tasks.get(name) orelse return error.TaskNotFound;
        try needed.put(task.name, {});

        for (task.deps) |dep| {
            if (!needed.contains(dep)) {
                try stack.append(allocator, dep);
            }
        }
    }

    return needed;
}

/// Build a DAG from a subset of tasks in the config.
fn buildSubgraph(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    needed: *const std.StringHashMap(void),
) !dag_mod.DAG {
    var subdag = dag_mod.DAG.init(allocator);
    errdefer subdag.deinit();

    var it = needed.keyIterator();
    while (it.next()) |name_ptr| {
        const name = name_ptr.*;
        try subdag.addNode(name);

        const task = config.tasks.get(name) orelse continue;
        for (task.deps) |dep| {
            // Only include deps that are in our needed set
            if (needed.contains(dep)) {
                try subdag.addEdge(name, dep);
            }
        }
    }

    return subdag;
}

/// Resolve the effective concurrency limit.
/// Returns 1 for sequential execution, or the number of logical CPUs for 0 / uncapped.
fn resolveMaxJobs(max_jobs: u32) u32 {
    if (max_jobs == 0) {
        return @intCast(std.Thread.getCpuCount() catch 4);
    }
    return max_jobs;
}

/// Run tasks with their dependencies respected, executing independent tasks in parallel.
/// Tasks within the same execution level have no inter-dependencies and are run concurrently
/// up to `sched_config.max_jobs` threads. Levels are executed sequentially.
pub fn run(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    task_names: []const []const u8,
    sched_config: SchedulerConfig,
) SchedulerError!ScheduleResult {
    var results = std.ArrayList(TaskResult){};
    errdefer {
        for (results.items) |r| {
            allocator.free(r.task_name);
        }
        results.deinit(allocator);
    }

    // Collect transitive deps
    var needed = try collectDeps(allocator, config, task_names);
    defer needed.deinit();

    // Build subgraph
    var subdag = try buildSubgraph(allocator, config, &needed);
    defer subdag.deinit();

    // Get execution levels (each level can run in parallel)
    var levels = topo_sort.getExecutionLevels(allocator, &subdag) catch {
        return error.CycleDetected;
    };
    defer levels.deinit(allocator);

    const concurrency = resolveMaxJobs(sched_config.max_jobs);

    var results_mutex = std.Thread.Mutex{};
    var failed = std.atomic.Value(bool).init(false);
    var semaphore = std.Thread.Semaphore{ .permits = concurrency };

    // Execute level by level (sequentially between levels, parallel within a level)
    for (levels.levels.items) |level| {
        // Stop processing further levels if a previous level had a failure
        if (failed.load(.acquire)) break;

        // Collect threads for this level so we can join them all
        var threads = std.ArrayList(std.Thread){};
        defer threads.deinit(allocator);

        for (level.items) |task_name| {
            // Stop spawning new tasks if failure detected
            if (failed.load(.acquire)) break;

            const task = config.tasks.get(task_name) orelse return error.TaskNotFound;

            // Acquire a slot; blocks if concurrency cap is reached
            semaphore.wait();

            // If failure was detected while we were waiting, release and stop
            if (failed.load(.acquire)) {
                semaphore.post();
                break;
            }

            // Dupe task_name so the worker owns it (freed in workerFn defer)
            const owned_task_name = try allocator.dupe(u8, task_name);

            const ctx = WorkerCtx{
                .allocator = allocator,
                .task_name = owned_task_name,
                .cmd = task.cmd,
                .cwd = task.cwd,
                .inherit_stdio = sched_config.inherit_stdio,
                .timeout_ms = task.timeout_ms,
                .allow_failure = task.allow_failure,
                .results = &results,
                .results_mutex = &results_mutex,
                .semaphore = &semaphore,
                .failed = &failed,
            };

            const thread = std.Thread.spawn(.{}, workerFn, .{ctx}) catch {
                // If spawn fails, release the semaphore slot we reserved and the name
                semaphore.post();
                allocator.free(owned_task_name);
                failed.store(true, .release);
                break;
            };
            try threads.append(allocator, thread);
        }

        // Join all threads spawned for this level
        for (threads.items) |thread| {
            thread.join();
        }
    }

    const total_success = !failed.load(.acquire);

    return ScheduleResult{
        .results = results,
        .total_success = total_success,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ScheduleResult: deinit frees memory" {
    const allocator = std.testing.allocator;

    var result = ScheduleResult{
        .results = std.ArrayList(TaskResult){},
        .total_success = true,
    };

    const name = try allocator.dupe(u8, "build");
    try result.results.append(allocator, .{
        .task_name = name,
        .success = true,
        .exit_code = 0,
        .duration_ms = 42,
    });

    result.deinit(allocator);
}

test "TaskResult: struct fields are correct" {
    const result = TaskResult{
        .task_name = "test",
        .success = false,
        .exit_code = 1,
        .duration_ms = 100,
    };

    try std.testing.expectEqualStrings("test", result.task_name);
    try std.testing.expect(!result.success);
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expectEqual(@as(u64, 100), result.duration_ms);
}

test "collectDeps: returns task not found for missing task" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();

    const names = [_][]const u8{"nonexistent"};
    const result = collectDeps(allocator, &config, &names);
    try std.testing.expectError(error.TaskNotFound, result);
}

test "resolveMaxJobs: zero returns cpu count (>= 1)" {
    const count = resolveMaxJobs(0);
    try std.testing.expect(count >= 1);
}

test "resolveMaxJobs: explicit value is preserved" {
    try std.testing.expectEqual(@as(u32, 4), resolveMaxJobs(4));
    try std.testing.expectEqual(@as(u32, 1), resolveMaxJobs(1));
}

test "run: single task succeeds" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("echo-task", "echo hello", null, null, &[_][]const u8{});

    const task_names = [_][]const u8{"echo-task"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
    try std.testing.expectEqualStrings("echo-task", result.results.items[0].task_name);
}

test "run: failing task sets total_success false" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("fail-task", "exit 1", null, null, &[_][]const u8{});

    const task_names = [_][]const u8{"fail-task"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(!result.total_success);
}

test "run: parallel tasks within a level" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    // Two independent tasks — same level, run in parallel
    try config.addTask("task-a", "true", null, null, &[_][]const u8{});
    try config.addTask("task-b", "true", null, null, &[_][]const u8{});

    const task_names = [_][]const u8{ "task-a", "task-b" };
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 2, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 2), result.results.items.len);
}

test "run: dependency order is respected" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("base", "true", null, null, &[_][]const u8{});
    try config.addTask("child", "true", null, null, &[_][]const u8{"base"});

    const task_names = [_][]const u8{"child"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 2, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 2), result.results.items.len);
}

test "run: allow_failure lets pipeline continue on failure" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    // Failing task with allow_failure = true
    try config.addTaskFull("fail-ok", "exit 1", null, null, &[_][]const u8{}, null, true);

    const task_names = [_][]const u8{"fail-ok"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    // total_success should be true because allow_failure is set
    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
    // The task itself is still recorded as failed
    try std.testing.expect(!result.results.items[0].success);
}

test "run: allow_failure false (default) fails pipeline" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTaskFull("fail-bad", "exit 1", null, null, &[_][]const u8{}, null, false);

    const task_names = [_][]const u8{"fail-bad"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(!result.total_success);
}

test "run: cycle detected returns error" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("a", "true", null, null, &[_][]const u8{"b"});
    try config.addTask("b", "true", null, null, &[_][]const u8{"a"});

    const task_names = [_][]const u8{"a"};
    const result = run(allocator, &config, &task_names, .{ .inherit_stdio = false });
    try std.testing.expectError(error.CycleDetected, result);
}
