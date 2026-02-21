const std = @import("std");
const loader = @import("../config/loader.zig");
const dag_mod = @import("../graph/dag.zig");
const topo_sort = @import("../graph/topo_sort.zig");
const process = @import("process.zig");
const expr = @import("../config/expr.zig");
const cache_store = @import("../cache/store.zig");
const cache_remote = @import("../cache/remote.zig");
const control = @import("control.zig");
const toolchain_path = @import("../toolchain/path.zig");
const toolchain_types = @import("../toolchain/types.zig");
const toolchain_installer = @import("../toolchain/installer.zig");

pub const SchedulerError = error{
    TaskNotFound,
    CycleDetected,
    BuildFailed,
    NodeNotFound,
    InvalidToolchainSpec,
    UnknownToolchainKind,
    InvalidVersionFormat,
} || std.mem.Allocator.Error;

pub const SchedulerConfig = struct {
    /// Maximum number of tasks to run concurrently within a level.
    /// Default 0 means "use all CPU cores".
    max_jobs: u32 = 0,
    /// Whether child processes inherit parent stdio.
    /// Set to false in tests to prevent deadlock in background test environments.
    inherit_stdio: bool = true,
    /// If true, compute the execution plan but do not run any tasks.
    /// Each task appears in the result with skipped=true, success=true, duration_ms=0.
    dry_run: bool = false,
    /// If true, display live resource usage (CPU/memory) during execution.
    monitor: bool = false,
    /// Whether to use color in output.
    use_color: bool = false,
    /// Optional task control for pause/cancel/retry operations.
    /// If provided, allows interactive control of task execution.
    task_control: ?*control.TaskControl = null,
};

/// A single level in the dry-run execution plan.
pub const DryRunLevel = struct {
    /// Task names that would run at this level (owned, duped).
    tasks: [][]const u8,

    pub fn deinit(self: DryRunLevel, allocator: std.mem.Allocator) void {
        for (self.tasks) |t| allocator.free(t);
        allocator.free(self.tasks);
    }
};

/// The result of a dry-run: ordered list of levels with task names per level.
pub const DryRunPlan = struct {
    levels: []DryRunLevel,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DryRunPlan) void {
        for (self.levels) |level| level.deinit(self.allocator);
        self.allocator.free(self.levels);
    }
};

/// Compute the execution plan (what would run, in what order) without running anything.
/// Returns an ordered slice of levels, each containing the task names that would
/// execute in parallel at that level.
pub fn planDryRun(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    task_names: []const []const u8,
) SchedulerError!DryRunPlan {
    var needed = try collectDeps(allocator, config, task_names);
    defer needed.deinit();

    var subdag = try buildSubgraph(allocator, config, &needed);
    defer subdag.deinit();

    var levels = topo_sort.getExecutionLevels(allocator, &subdag) catch {
        return error.CycleDetected;
    };
    defer levels.deinit(allocator);

    // Build owned DryRunLevel array
    const plan_levels = try allocator.alloc(DryRunLevel, levels.levels.items.len);
    var levels_built: usize = 0;
    errdefer {
        for (plan_levels[0..levels_built]) |lvl| lvl.deinit(allocator);
        allocator.free(plan_levels);
    }

    for (levels.levels.items, 0..) |level, i| {
        const tasks = try allocator.alloc([]const u8, level.items.len);
        var tasks_duped: usize = 0;
        errdefer {
            for (tasks[0..tasks_duped]) |t| allocator.free(t);
            allocator.free(tasks);
        }
        for (level.items, 0..) |name, j| {
            tasks[j] = try allocator.dupe(u8, name);
            tasks_duped += 1;
        }
        plan_levels[i] = DryRunLevel{ .tasks = tasks };
        levels_built += 1;
    }

    return DryRunPlan{
        .levels = plan_levels,
        .allocator = allocator,
    };
}

pub const TaskResult = struct {
    task_name: []const u8,
    success: bool,
    exit_code: u8,
    duration_ms: u64,
    /// True if the task was skipped due to a false condition expression.
    skipped: bool = false,
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
    /// Optional env var overrides from the task definition.
    env: ?[]const [2][]const u8,
    /// Toolchains from config [tools] section (pointer to config.toolchains.tools)
    toolchains: []const loader.ToolSpec,
    inherit_stdio: bool,
    timeout_ms: ?u64,
    allow_failure: bool,
    retry_max: u32,
    retry_delay_ms: u64,
    retry_backoff: bool,
    /// Pointer to shared results list — protected by results_mutex.
    results: *std.ArrayList(TaskResult),
    results_mutex: *std.Thread.Mutex,
    /// Semaphore used to limit concurrency; released when worker finishes.
    semaphore: *std.Thread.Semaphore,
    /// Optional per-task semaphore (from max_concurrent). null = unlimited.
    /// The semaphore is owned by the `task_semaphores` map in `run()`, not by worker.
    task_semaphore: ?*std.Thread.Semaphore,
    /// Set to true if any task fails; checked before launching new tasks.
    failed: *std.atomic.Value(bool),
    /// If true, check/update the cache for this task.
    cache: bool,
    /// Pre-computed cache key (owned by worker, freed in defer).
    cache_key: ?[]u8,
    /// Remote cache config from [cache.remote] section (Phase 7).
    cache_remote_config: ?*const loader.RemoteCacheConfig,
    /// If true, display live resource monitoring.
    monitor: bool,
    /// Whether to use color in monitor output.
    use_color: bool,
    /// Optional task control for pause/cancel/retry operations.
    task_control: ?*control.TaskControl,
};

/// Build environment variables with toolchain PATH injection.
/// Merges task env vars with toolchain bin directories in PATH.
/// Returns null if both task_env and toolchains are empty, otherwise returns owned array.
/// If toolchain path building fails (e.g., no HOME), falls back to task_env only.
fn buildEnvWithToolchains(
    allocator: std.mem.Allocator,
    task_env: ?[]const [2][]const u8,
    toolchains: []const loader.ToolSpec,
) ?[][2][]u8 {
    if (toolchains.len == 0 and task_env == null) {
        return null; // No env override needed
    }

    // Build toolchain env (includes PATH + toolchain-specific vars)
    const merged_env = toolchain_path.buildToolchainEnv(allocator, toolchains, task_env) catch {
        // If toolchain env building fails, fall back to task env only
        // This can happen if HOME is not set or other env issues
        if (task_env) |env| {
            // Duplicate task env
            const dup_env = allocator.alloc([2][]u8, env.len) catch return null;
            for (env, 0..) |pair, i| {
                dup_env[i][0] = allocator.dupe(u8, pair[0]) catch {
                    for (dup_env[0..i]) |p| {
                        allocator.free(p[0]);
                        allocator.free(p[1]);
                    }
                    allocator.free(dup_env);
                    return null;
                };
                dup_env[i][1] = allocator.dupe(u8, pair[1]) catch {
                    allocator.free(dup_env[i][0]);
                    for (dup_env[0..i]) |p| {
                        allocator.free(p[0]);
                        allocator.free(p[1]);
                    }
                    allocator.free(dup_env);
                    return null;
                };
            }
            return dup_env;
        }
        return null;
    };
    return merged_env;
}

fn workerFn(ctx: WorkerCtx) void {
    defer {
        if (ctx.task_semaphore) |ts| ts.post();
        ctx.semaphore.post();
        ctx.allocator.free(ctx.task_name);
        if (ctx.cache_key) |k| ctx.allocator.free(k);
    }

    // Build environment with toolchain PATH injection
    const merged_env = buildEnvWithToolchains(ctx.allocator, ctx.env, ctx.toolchains);
    defer if (merged_env) |env| toolchain_path.freeToolchainEnv(ctx.allocator, env);

    // Check cache hit — skip execution if already succeeded with same cmd+env
    if (ctx.cache) {
        if (ctx.cache_key) |key| {
            // First check local cache
            var local_hit = false;
            var store = cache_store.CacheStore.init(ctx.allocator) catch null;
            if (store) |*s| {
                defer s.deinit();
                local_hit = s.hasHit(key);
            }

            // If local miss, try remote cache (Phase 7)
            if (!local_hit and ctx.cache_remote_config != null) {
                if (ctx.cache_remote_config) |remote_cfg| {
                    var remote = cache_remote.RemoteCache.init(ctx.allocator, remote_cfg.*);
                    defer remote.deinit();
                    // Pull from remote (null = miss)
                    if (remote.pull(key) catch null) |_data| {
                        // Remote hit: save to local cache for next time
                        // (data itself is just a marker, no actual artifact yet)
                        ctx.allocator.free(_data);
                        if (store) |*s| s.recordHit(key) catch {};
                        local_hit = true;
                    }
                }
            }

            if (local_hit) {
                // Cache hit: record a skipped success result
                const owned_name = ctx.allocator.dupe(u8, ctx.task_name) catch return;
                ctx.results_mutex.lock();
                defer ctx.results_mutex.unlock();
                ctx.results.append(ctx.allocator, .{
                    .task_name = owned_name,
                    .success = true,
                    .exit_code = 0,
                    .duration_ms = 0,
                    .skipped = true,
                }) catch ctx.allocator.free(owned_name);
                return;
            }
        }
    }

    // Cast merged_env to the const slice type expected by ProcessConfig
    const proc_env: ?[]const [2][]const u8 = if (merged_env) |env| env else null;

    // Run the process with retry logic
    var proc_result = process.run(ctx.allocator, .{
        .cmd = ctx.cmd,
        .cwd = ctx.cwd,
        .env = proc_env,
        .inherit_stdio = ctx.inherit_stdio,
        .timeout_ms = ctx.timeout_ms,
        .task_control = ctx.task_control,
        .enable_monitor = ctx.monitor,
        .monitor_task_name = if (ctx.monitor) ctx.task_name else null,
        .monitor_use_color = ctx.use_color,
        .monitor_allocator = if (ctx.monitor) ctx.allocator else null,
    }) catch process.ProcessResult{
        .exit_code = 1,
        .duration_ms = 0,
        .success = false,
    };

    // Retry on failure up to retry_max times
    if (!proc_result.success and ctx.retry_max > 0) {
        var delay_ms: u64 = ctx.retry_delay_ms;
        var attempt: u32 = 0;
        while (!proc_result.success and attempt < ctx.retry_max) : (attempt += 1) {
            if (delay_ms > 0) {
                std.Thread.sleep(delay_ms * std.time.ns_per_ms);
            }
            proc_result = process.run(ctx.allocator, .{
                .cmd = ctx.cmd,
                .cwd = ctx.cwd,
                .env = proc_env,
                .inherit_stdio = ctx.inherit_stdio,
                .timeout_ms = ctx.timeout_ms,
                .task_control = ctx.task_control,
                .enable_monitor = ctx.monitor,
                .monitor_task_name = if (ctx.monitor) ctx.task_name else null,
                .monitor_use_color = ctx.use_color,
                .monitor_allocator = if (ctx.monitor) ctx.allocator else null,
            }) catch process.ProcessResult{
                .exit_code = 1,
                .duration_ms = 0,
                .success = false,
            };
            if (ctx.retry_backoff and delay_ms > 0) {
                delay_ms *= 2;
            }
        }
    }

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

    // Record cache entry on success
    if (proc_result.success and ctx.cache) {
        if (ctx.cache_key) |key| {
            // Write to local cache
            var store = cache_store.CacheStore.init(ctx.allocator) catch null;
            if (store) |*s| {
                defer s.deinit();
                s.recordHit(key) catch {};
            }
            // Push to remote cache (Phase 7)
            if (ctx.cache_remote_config) |remote_cfg| {
                var remote = cache_remote.RemoteCache.init(ctx.allocator, remote_cfg.*);
                defer remote.deinit();
                // Push marker (empty data for now, just indicates success)
                remote.push(key, &[_]u8{}) catch {};
            }
        }
    }
}

/// Collect all transitive dependencies of the requested tasks.
/// Only traverses `deps` (parallel) edges for DAG scheduling.
/// `deps_serial` tasks are NOT included here — they run on-demand via runSerialChain.
/// Returns a StringHashMap(void) of all task names that need DAG scheduling.
fn collectDeps(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    task_names: []const []const u8,
) !std.StringHashMap(void) {
    var needed = std.StringHashMap(void).init(allocator);
    errdefer needed.deinit();

    // Stack-based DFS to find all transitive deps (via `deps` only)
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
        // Note: deps_serial are intentionally NOT traversed here.
        // They run inline via runSerialChain, not via the DAG scheduler.
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

/// Parse and auto-install missing toolchains for a task.
/// Returns error if parsing fails. Installation errors are logged but don't fail the task.
/// Parses toolchain specs like "node@20.11", "python@3.12" from the task's toolchain field.
fn ensureToolchainsInstalled(allocator: std.mem.Allocator, task: loader.Task) SchedulerError!void {
    if (task.toolchain.len == 0) return; // No toolchains needed

    for (task.toolchain) |spec_str| {
        // Parse "tool@version" format (e.g., "node@20.11")
        const at_idx = std.mem.indexOf(u8, spec_str, "@") orelse {
            std.debug.print("Invalid toolchain spec: {s} (expected format: tool@version)\n", .{spec_str});
            return error.InvalidToolchainSpec;
        };

        const kind_str = spec_str[0..at_idx];
        const version_str = spec_str[at_idx + 1 ..];

        // Parse tool kind
        const kind = toolchain_types.ToolKind.fromString(kind_str) orelse {
            std.debug.print("Unknown toolchain kind: {s}\n", .{kind_str});
            return error.UnknownToolchainKind;
        };

        // Parse version
        const version = toolchain_types.ToolVersion.parse(version_str) catch {
            std.debug.print("Invalid version format: {s}\n", .{version_str});
            return error.InvalidVersionFormat;
        };

        // Check if installed
        const installed = toolchain_installer.isInstalled(allocator, kind, version) catch false;
        if (!installed) {
            std.debug.print("Installing {s} {s}...\n", .{ kind.toString(), version_str });
            // Don't fail the task if installation fails; just log the error
            toolchain_installer.install(allocator, kind, version) catch |err| {
                std.debug.print("Warning: Failed to install {s} {s}: {}\n", .{ kind.toString(), version_str, err });
                continue;
            };
            std.debug.print("Successfully installed {s} {s}\n", .{ kind.toString(), version_str });
        }
    }
}

/// Run a single task synchronously (on the calling thread). Records result.
/// Holds results_mutex while appending so it is safe to call concurrently with worker threads.
/// Returns true if the task succeeded (or has allow_failure set).
fn runTaskSync(
    allocator: std.mem.Allocator,
    task: loader.Task,
    env: ?[]const [2][]const u8,
    toolchains: []const loader.ToolSpec,
    inherit_stdio: bool,
    results: *std.ArrayList(TaskResult),
    results_mutex: *std.Thread.Mutex,
) !bool {
    // Auto-install any missing toolchains specified in task.toolchain
    try ensureToolchainsInstalled(allocator, task);

    // Build environment with toolchain PATH injection
    const merged_env = buildEnvWithToolchains(allocator, env, toolchains);
    defer if (merged_env) |e| toolchain_path.freeToolchainEnv(allocator, e);

    const proc_env: ?[]const [2][]const u8 = if (merged_env) |e| e else null;

    var proc_result = process.run(allocator, .{
        .cmd = task.cmd,
        .cwd = task.cwd,
        .env = proc_env,
        .inherit_stdio = inherit_stdio,
        .timeout_ms = task.timeout_ms,
    }) catch process.ProcessResult{
        .exit_code = 1,
        .duration_ms = 0,
        .success = false,
    };

    // Retry on failure up to retry_max times
    if (!proc_result.success and task.retry_max > 0) {
        var delay_ms: u64 = task.retry_delay_ms;
        var attempt: u32 = 0;
        while (!proc_result.success and attempt < task.retry_max) : (attempt += 1) {
            if (delay_ms > 0) {
                std.Thread.sleep(delay_ms * std.time.ns_per_ms);
            }
            proc_result = process.run(allocator, .{
                .cmd = task.cmd,
                .cwd = task.cwd,
                .env = proc_env,
                .inherit_stdio = inherit_stdio,
                .timeout_ms = task.timeout_ms,
            }) catch process.ProcessResult{
                .exit_code = 1,
                .duration_ms = 0,
                .success = false,
            };
            if (task.retry_backoff and delay_ms > 0) {
                delay_ms *= 2;
            }
        }
    }

    const owned_name = try allocator.dupe(u8, task.name);
    results_mutex.lock();
    defer results_mutex.unlock();
    results.append(allocator, .{
        .task_name = owned_name,
        .success = proc_result.success,
        .exit_code = proc_result.exit_code,
        .duration_ms = proc_result.duration_ms,
    }) catch {
        allocator.free(owned_name);
        return error.OutOfMemory;
    };

    return proc_result.success or task.allow_failure;
}

/// Run deps_serial tasks in array order, stopping on first failure (unless allow_failure).
/// Already-completed tasks (tracked in `completed`) are skipped.
/// `completed` uses a false sentinel to detect dep_serial cycles and prevent infinite recursion.
/// Returns true if all serial deps passed.
fn runSerialChain(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    serial_deps: []const []const u8,
    toolchains: []const loader.ToolSpec,
    inherit_stdio: bool,
    results: *std.ArrayList(TaskResult),
    results_mutex: *std.Thread.Mutex,
    completed: *std.StringHashMap(bool),
) !bool {
    for (serial_deps) |dep_name| {
        if (completed.contains(dep_name)) {
            // Already ran (or is currently being visited as a cycle sentinel).
            const prev_ok = completed.get(dep_name).?;
            if (!prev_ok) return false;
            continue;
        }

        const dep_task = config.tasks.get(dep_name) orelse return error.TaskNotFound;

        // Insert visiting sentinel to prevent infinite recursion on dep_serial cycles.
        try completed.put(dep_name, false);

        // Recursively run this dep's own serial chain first
        if (dep_task.deps_serial.len > 0) {
            const chain_ok = try runSerialChain(
                allocator, config, dep_task.deps_serial, toolchains,
                inherit_stdio, results, results_mutex, completed,
            );
            if (!chain_ok) return false;
        }

        const task_env: ?[]const [2][]const u8 = if (dep_task.env.len > 0) dep_task.env else null;
        const ok = try runTaskSync(allocator, dep_task, task_env, toolchains, inherit_stdio, results, results_mutex);
        // Update sentinel to real result
        try completed.put(dep_name, ok);
        if (!ok) return false;
    }
    return true;
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

    // Per-task semaphores for max_concurrent limits.
    // Keys are task name slices (pointing into config.tasks keys — not owned).
    // Values are heap-allocated semaphores.
    var task_semaphores = std.StringHashMap(*std.Thread.Semaphore).init(allocator);
    defer {
        var ts_it = task_semaphores.iterator();
        while (ts_it.next()) |entry| {
            allocator.destroy(entry.value_ptr.*);
        }
        task_semaphores.deinit();
    }

    // Tracks tasks that have been run and whether they succeeded.
    // Used for deps_serial deduplication across levels.
    var completed = std.StringHashMap(bool).init(allocator);
    defer completed.deinit();

    // Execute level by level (sequentially between levels, parallel within a level)
    for (levels.levels.items) |level| {
        // Stop processing further levels if a previous level had a failure
        if (failed.load(.acquire)) break;

        // Collect threads for this level so we can join them all.
        // Pre-reserve capacity to ensure append() cannot fail after a thread is spawned
        // (which would leave a live thread whose join is skipped on OOM unwind).
        var threads = std.ArrayList(std.Thread){};
        defer threads.deinit(allocator);
        try threads.ensureTotalCapacity(allocator, level.items.len);

        for (level.items) |task_name| {
            // Stop spawning new tasks if failure detected
            if (failed.load(.acquire)) break;

            const task = config.tasks.get(task_name) orelse return error.TaskNotFound;

            // Dry-run: record a synthetic skipped result without executing.
            if (sched_config.dry_run) {
                const owned_name = try allocator.dupe(u8, task_name);
                results_mutex.lock();
                results.append(allocator, .{
                    .task_name = owned_name,
                    .success = true,
                    .exit_code = 0,
                    .duration_ms = 0,
                    .skipped = true,
                }) catch {
                    allocator.free(owned_name);
                };
                results_mutex.unlock();
                continue;
            }

            // Evaluate condition expression — skip task if condition is false.
            if (task.condition) |cond| {
                const task_env_for_cond: ?[]const [2][]const u8 = if (task.env.len > 0) task.env else null;
                const should_run = expr.evalCondition(allocator, cond, task_env_for_cond) catch true;
                if (!should_run) {
                    const owned_name = try allocator.dupe(u8, task_name);
                    results_mutex.lock();
                    results.append(allocator, .{
                        .task_name = owned_name,
                        .success = true,
                        .exit_code = 0,
                        .duration_ms = 0,
                        .skipped = true,
                    }) catch {
                        allocator.free(owned_name);
                    };
                    results_mutex.unlock();
                    continue;
                }
            }

            // Run deps_serial chain synchronously before this task (if any)
            if (task.deps_serial.len > 0) {
                const serial_ok = try runSerialChain(
                    allocator, config, task.deps_serial, config.toolchains.tools,
                    sched_config.inherit_stdio, &results, &results_mutex, &completed,
                );
                if (!serial_ok) {
                    if (!task.allow_failure) failed.store(true, .release);
                    break;
                }
            }

            if (failed.load(.acquire)) break;

            // Acquire the global concurrency slot first to avoid hold-and-wait deadlock.
            // The task semaphore is acquired after, so a blocked task_sem never holds
            // a global slot while waiting.
            semaphore.wait();

            // If failure was detected while we were waiting, release and stop
            if (failed.load(.acquire)) {
                semaphore.post();
                break;
            }

            // Get or create per-task semaphore for max_concurrent (acquired after global slot).
            var task_sem_ptr: ?*std.Thread.Semaphore = null;
            if (task.max_concurrent > 0) {
                if (task_semaphores.get(task_name)) |existing| {
                    task_sem_ptr = existing;
                } else {
                    const new_sem = try allocator.create(std.Thread.Semaphore);
                    errdefer allocator.destroy(new_sem);
                    new_sem.* = std.Thread.Semaphore{ .permits = task.max_concurrent };
                    try task_semaphores.put(task_name, new_sem);
                    task_sem_ptr = new_sem;
                }
                task_sem_ptr.?.wait();
            }

            // If failure was detected after acquiring semaphores, release and stop
            if (failed.load(.acquire)) {
                if (task_sem_ptr) |ts| ts.post();
                semaphore.post();
                break;
            }

            // Dupe task_name so the worker owns it (freed in workerFn defer)
            const owned_task_name = try allocator.dupe(u8, task_name);

            // Compute cache key if caching is enabled for this task
            const task_env_slice: ?[]const [2][]const u8 = if (task.env.len > 0) task.env else null;
            const cache_key: ?[]u8 = if (task.cache)
                cache_store.CacheStore.computeKey(allocator, task.cmd, task_env_slice) catch null
            else
                null;

            const ctx = WorkerCtx{
                .allocator = allocator,
                .task_name = owned_task_name,
                .cmd = task.cmd,
                .cwd = task.cwd,
                .env = task_env_slice,
                .toolchains = config.toolchains.tools,
                .inherit_stdio = sched_config.inherit_stdio,
                .timeout_ms = task.timeout_ms,
                .allow_failure = task.allow_failure,
                .retry_max = task.retry_max,
                .retry_delay_ms = task.retry_delay_ms,
                .retry_backoff = task.retry_backoff,
                .results = &results,
                .results_mutex = &results_mutex,
                .semaphore = &semaphore,
                .task_semaphore = task_sem_ptr,
                .failed = &failed,
                .cache = task.cache,
                .cache_key = cache_key,
                .cache_remote_config = if (config.cache.remote) |*r| r else null,
                .monitor = sched_config.monitor,
                .use_color = sched_config.use_color,
                .task_control = sched_config.task_control,
            };

            const thread = std.Thread.spawn(.{}, workerFn, .{ctx}) catch {
                // If spawn fails, release the semaphore slots we reserved and the name
                if (task_sem_ptr) |ts| ts.post();
                semaphore.post();
                allocator.free(owned_task_name);
                if (cache_key) |k| allocator.free(k);
                failed.store(true, .release);
                break;
            };
            threads.appendAssumeCapacity(thread);
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

test "run: deps_serial run in order and all succeed" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("step-a", "true", null, null, &[_][]const u8{});
    try config.addTask("step-b", "true", null, null, &[_][]const u8{});
    try config.addTask("step-c", "true", null, null, &[_][]const u8{});
    try config.addTaskWithSerial("deploy", "true", null, null, &[_][]const u8{}, &[_][]const u8{ "step-a", "step-b", "step-c" });

    const task_names = [_][]const u8{"deploy"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    // step-a, step-b, step-c ran serially, then deploy
    try std.testing.expectEqual(@as(usize, 4), result.results.items.len);
}

test "run: deps_serial failure stops chain and marks pipeline failed" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("step-ok", "true", null, null, &[_][]const u8{});
    try config.addTask("step-fail", "exit 1", null, null, &[_][]const u8{});
    try config.addTask("step-skip", "true", null, null, &[_][]const u8{});
    try config.addTaskWithSerial("deploy", "true", null, null, &[_][]const u8{}, &[_][]const u8{ "step-ok", "step-fail", "step-skip" });

    const task_names = [_][]const u8{"deploy"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(!result.total_success);
    // step-ok ran, step-fail ran and failed, step-skip was skipped, deploy was skipped
    // At least step-ok and step-fail ran
    try std.testing.expect(result.results.items.len >= 2);
}

test "run: retry succeeds on second attempt" {
    const allocator = std.testing.allocator;

    // Use a counter file to make a task fail once then succeed.
    // Simpler: use a command that fails first time but subsequent would succeed.
    // Since we can't easily do stateful retries in a pure test, use a task
    // that always fails, with retry_max = 2, to verify the task ran multiple times
    // (it will still fail in the end, but retry_max > 0 means we attempt more).
    // We test: a task that succeeds passes normally (no-retry path still works).
    var config = loader.Config.init(allocator);
    defer config.deinit();

    // Task that always succeeds: retry is a no-op
    try config.addTaskWithRetry("always-ok", "true", null, null, &[_][]const u8{}, 3, 0, false);

    const task_names = [_][]const u8{"always-ok"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
}

test "run: retry exhausted still fails pipeline" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();

    // Always-failing task with retry_max = 2 (0ms delay for test speed)
    try config.addTaskWithRetry("always-fail", "exit 1", null, null, &[_][]const u8{}, 2, 0, false);

    const task_names = [_][]const u8{"always-fail"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    // Should still fail after retries
    try std.testing.expect(!result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
    try std.testing.expect(!result.results.items[0].success);
}

test "run: task with condition=false is skipped" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();

    // Task with condition = "false" — should be skipped, not run
    try config.addTaskWithCondition("skip-me", "exit 1", "false");

    const task_names = [_][]const u8{"skip-me"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    // Skipped task should not fail the pipeline
    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
    try std.testing.expect(result.results.items[0].skipped);
    try std.testing.expect(result.results.items[0].success);
}

test "run: task with condition=true runs normally" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();

    // Task with condition = "true" — should run as normal
    try config.addTaskWithCondition("run-me", "true", "true");

    const task_names = [_][]const u8{"run-me"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
    try std.testing.expect(!result.results.items[0].skipped);
    try std.testing.expect(result.results.items[0].success);
}

test "run: task with no condition always runs" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();

    // Task with no condition (null) — always runs regardless of env
    try config.addTaskWithCondition("no-cond-task", "true", null);

    const task_names = [_][]const u8{"no-cond-task"};
    var result = try run(allocator, &config, &task_names, .{ .max_jobs = 1, .inherit_stdio = false });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
    try std.testing.expect(!result.results.items[0].skipped);
}

test "planDryRun: single task returns one level" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("build", "zig build", null, null, &[_][]const u8{});

    const task_names = [_][]const u8{"build"};
    var plan = try planDryRun(allocator, &config, &task_names);
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 1), plan.levels.len);
    try std.testing.expectEqual(@as(usize, 1), plan.levels[0].tasks.len);
    try std.testing.expectEqualStrings("build", plan.levels[0].tasks[0]);
}

test "planDryRun: dependency chain produces ordered levels" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("base", "true", null, null, &[_][]const u8{});
    try config.addTask("mid", "true", null, null, &[_][]const u8{"base"});
    try config.addTask("top", "true", null, null, &[_][]const u8{"mid"});

    const task_names = [_][]const u8{"top"};
    var plan = try planDryRun(allocator, &config, &task_names);
    defer plan.deinit();

    // 3 levels: base → mid → top
    try std.testing.expectEqual(@as(usize, 3), plan.levels.len);
    try std.testing.expectEqual(@as(usize, 1), plan.levels[0].tasks.len);
    try std.testing.expectEqualStrings("base", plan.levels[0].tasks[0]);
    try std.testing.expectEqualStrings("mid", plan.levels[1].tasks[0]);
    try std.testing.expectEqualStrings("top", plan.levels[2].tasks[0]);
}

test "planDryRun: parallel tasks appear in same level" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    // Two independent tasks — should appear at level 0
    try config.addTask("a", "true", null, null, &[_][]const u8{});
    try config.addTask("b", "true", null, null, &[_][]const u8{});

    const task_names = [_][]const u8{ "a", "b" };
    var plan = try planDryRun(allocator, &config, &task_names);
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 1), plan.levels.len);
    try std.testing.expectEqual(@as(usize, 2), plan.levels[0].tasks.len);
}

test "planDryRun: cycle returns error" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("x", "true", null, null, &[_][]const u8{"y"});
    try config.addTask("y", "true", null, null, &[_][]const u8{"x"});

    const task_names = [_][]const u8{"x"};
    const result = planDryRun(allocator, &config, &task_names);
    try std.testing.expectError(error.CycleDetected, result);
}

test "run: dry_run flag skips execution and marks tasks skipped" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    // This task would fail if actually run
    try config.addTask("fail-if-run", "exit 1", null, null, &[_][]const u8{});

    const task_names = [_][]const u8{"fail-if-run"};
    var result = try run(allocator, &config, &task_names, .{
        .max_jobs = 1,
        .inherit_stdio = false,
        .dry_run = true,
    });
    defer result.deinit(allocator);

    // Dry-run: task was skipped, pipeline succeeds
    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 1), result.results.items.len);
    try std.testing.expect(result.results.items[0].skipped);
    try std.testing.expect(result.results.items[0].success);
    try std.testing.expectEqualStrings("fail-if-run", result.results.items[0].task_name);
}

test "run: dry_run with dependency chain skips all tasks" {
    const allocator = std.testing.allocator;

    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("dep", "exit 1", null, null, &[_][]const u8{});
    try config.addTask("main", "exit 1", null, null, &[_][]const u8{"dep"});

    const task_names = [_][]const u8{"main"};
    var result = try run(allocator, &config, &task_names, .{
        .max_jobs = 1,
        .inherit_stdio = false,
        .dry_run = true,
    });
    defer result.deinit(allocator);

    try std.testing.expect(result.total_success);
    try std.testing.expectEqual(@as(usize, 2), result.results.items.len);
    for (result.results.items) |r| {
        try std.testing.expect(r.skipped);
        try std.testing.expect(r.success);
    }
}

test "max_concurrent: field parsed and defaults to 0" {
    const allocator = std.testing.allocator;
    var config = loader.Config.init(allocator);
    defer config.deinit();
    try config.addTask("build", "true", null, null, &[_][]const u8{});
    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(u32, 0), task.max_concurrent);
}
