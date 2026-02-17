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
    max_jobs: u32 = 1,
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

/// Run tasks in topological order (sequential for Phase 1).
/// Uses getExecutionLevels to determine the correct run order.
pub fn run(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    task_names: []const []const u8,
    sched_config: SchedulerConfig,
) SchedulerError!ScheduleResult {
    _ = sched_config;

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

    // Get execution levels
    var levels = topo_sort.getExecutionLevels(allocator, &subdag) catch {
        return error.CycleDetected;
    };
    defer levels.deinit(allocator);

    var total_success = true;

    // Execute level by level (sequentially within each level for Phase 1)
    for (levels.levels.items) |level| {
        for (level.items) |task_name| {
            const task = config.tasks.get(task_name) orelse return error.TaskNotFound;

            const proc_result = process.run(allocator, .{
                .cmd = task.cmd,
                .cwd = task.cwd,
                .env = null,
            }) catch process.ProcessResult{
                // If process failed to even spawn, treat as failure with code 1
                .exit_code = 1,
                .duration_ms = 0,
                .success = false,
            };

            const owned_name = try allocator.dupe(u8, task_name);
            try results.append(allocator, .{
                .task_name = owned_name,
                .success = proc_result.success,
                .exit_code = proc_result.exit_code,
                .duration_ms = proc_result.duration_ms,
            });

            if (!proc_result.success) {
                total_success = false;
                // Stop on first failure
                return ScheduleResult{
                    .results = results,
                    .total_success = false,
                };
            }
        }
    }

    return ScheduleResult{
        .results = results,
        .total_success = total_success,
    };
}

test "ScheduleResult: deinit frees memory" {
    const allocator = std.testing.allocator;

    var result = ScheduleResult{
        .results = std.ArrayList(TaskResult){},
        .total_success = true,
    };

    // Allocate a task name to verify deinit frees it
    const name = try allocator.dupe(u8, "build");
    try result.results.append(allocator, .{
        .task_name = name,
        .success = true,
        .exit_code = 0,
        .duration_ms = 42,
    });

    result.deinit(allocator);
    // If memory is freed correctly, testing.allocator will not report a leak
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
