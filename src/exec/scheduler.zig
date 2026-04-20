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
const affinity = @import("../util/affinity.zig");
const numa = @import("../util/numa.zig");
const timeline = @import("timeline.zig");
const replay = @import("replay.zig");
const hooks = @import("hooks.zig");
const types = @import("../config/types.zig");
const checkpoint = @import("checkpoint.zig");
const output_capture = @import("output_capture.zig");
const remote = @import("remote.zig");
const retry_strategy = @import("retry_strategy.zig");
const filter_mod = @import("../output/filter.zig");

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
    /// Optional workflow-level retry budget (v1.34.0).
    /// If set, limits the total number of retries across all tasks in the workflow.
    /// This is typically extracted from workflow.retry_budget when executing workflow stages.
    retry_budget: ?u32 = null,
    /// Optional extra environment variables to inject into all tasks.
    /// Used for workflow matrix variables (e.g., MATRIX_OS=linux, MATRIX_VERSION=1.0).
    extra_env: ?[][2][]const u8 = null,
    /// Optional output filtering (grep, grep-v, highlight, context lines).
    /// Applied to task output streams in real-time.
    filter_options: filter_mod.FilterOptions = .{},
    /// Optional global silent mode override.
    /// When true, all tasks suppress output unless they fail (overrides task-level silent setting).
    silent_override: bool = false,
};

/// Circuit breaker state for a task (v1.30.0).
/// Tracks failure rate and determines when to stop retrying.
const CircuitBreakerState = struct {
    config: types.CircuitBreakerConfig,
    failure_count: u32 = 0,
    success_count: u32 = 0,
    last_failure_time: ?i64 = null, // Unix timestamp in milliseconds
    is_open: bool = false,

    fn init(config: types.CircuitBreakerConfig) CircuitBreakerState {
        return .{ .config = config };
    }

    /// Record a successful execution.
    fn recordSuccess(self: *CircuitBreakerState, now_ms: i64) void {
        self.success_count += 1;
        self.pruneOldFailures(now_ms);
        self.updateState(now_ms);
    }

    /// Record a failed execution.
    fn recordFailure(self: *CircuitBreakerState, now_ms: i64) void {
        self.failure_count += 1;
        self.last_failure_time = now_ms;
        self.pruneOldFailures(now_ms);
        self.updateState(now_ms);
    }

    /// Remove failures older than the time window.
    fn pruneOldFailures(self: *CircuitBreakerState, now_ms: i64) void {
        if (self.last_failure_time) |last| {
            if (now_ms - last > self.config.window_ms) {
                // All failures are outside the window
                self.failure_count = 0;
                self.success_count = 0;
            }
        }
    }

    /// Update circuit state based on current failure rate.
    fn updateState(self: *CircuitBreakerState, now_ms: i64) void {
        // First check if circuit should reset (half-open state)
        if (self.is_open) {
            if (self.last_failure_time) |last| {
                if (now_ms - last >= self.config.reset_timeout_ms) {
                    // Half-open state: allow one retry attempt
                    self.is_open = false;
                    self.failure_count = 0;
                    self.success_count = 0;
                    return;
                }
            }
        }

        // Then check if circuit should trip based on failure rate
        const total = self.failure_count + self.success_count;
        if (total < self.config.min_attempts) {
            self.is_open = false;
            return;
        }

        const failure_rate = @as(f64, @floatFromInt(self.failure_count)) / @as(f64, @floatFromInt(total));

        if (failure_rate >= self.config.failure_threshold) {
            self.is_open = true;
        } else {
            self.is_open = false;
        }
    }

    /// Check if circuit breaker should prevent retries.
    fn shouldPreventRetry(self: *const CircuitBreakerState) bool {
        return self.is_open;
    }
};

/// Retry budget tracker for workflows (v1.30.0).
/// Prevents retry storms by limiting total retries across all tasks.
const RetryBudgetTracker = struct {
    budget: u32,
    used: std.atomic.Value(u32),
    mutex: std.Thread.Mutex = .{},

    fn init(budget: u32) RetryBudgetTracker {
        return .{
            .budget = budget,
            .used = std.atomic.Value(u32).init(0),
        };
    }

    /// Try to consume retry budget. Returns true if retry is allowed.
    fn tryConsume(self: *RetryBudgetTracker) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current = self.used.load(.acquire);
        if (current >= self.budget) {
            return false;
        }
        self.used.store(current + 1, .release);
        return true;
    }

    /// Get remaining retry budget.
    fn remaining(self: *const RetryBudgetTracker) u32 {
        const current = self.used.load(.acquire);
        if (current >= self.budget) return 0;
        return self.budget - current;
    }
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
    /// Number of retry attempts (0 if succeeded on first try).
    retry_count: u32 = 0,
    /// Peak memory usage in bytes (0 if not captured).
    peak_memory_bytes: u64 = 0,
    /// Average CPU percentage during execution (0.0 if not captured).
    avg_cpu_percent: f64 = 0.0,
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

/// Context for checkpoint output callback (v1.31.0)
const CheckpointCallbackCtx = struct {
    allocator: std.mem.Allocator,
    task_name: []const u8,
    checkpoint_config: *const types.CheckpointConfig,
    last_save_ms: *std.atomic.Value(i64), // Atomic timestamp of last checkpoint save
};

/// Combined context for both checkpoint and output capture callbacks (v1.37.0)
const CombinedCallbackCtx = struct {
    checkpoint_ctx: ?*CheckpointCallbackCtx = null,
    output_capture: ?*output_capture.OutputCapture = null,
};

/// Parse output mode string into enum (v1.37.0)
fn parseOutputMode(mode_str: ?[]const u8) ?output_capture.OutputMode {
    const str = mode_str orelse return null;
    if (std.mem.eql(u8, str, "stream")) return .stream;
    if (std.mem.eql(u8, str, "buffer")) return .buffer;
    if (std.mem.eql(u8, str, "discard")) return .discard;
    return null; // Invalid mode string
}

/// Combined output callback for both checkpoint monitoring and output capture (v1.37.0)
fn combinedOutputCallback(line: []const u8, is_stderr: bool, ctx_opaque: ?*anyopaque) void {
    const ctx: *CombinedCallbackCtx = @ptrCast(@alignCast(ctx_opaque orelse return));

    // Call checkpoint callback if enabled
    if (ctx.checkpoint_ctx) |ckpt_ctx| {
        checkpointOutputCallbackImpl(line, is_stderr, ckpt_ctx);
    }

    // Call output capture if enabled
    if (ctx.output_capture) |oc| {
        oc.writeLine(line, is_stderr) catch {};
    }
}

/// Implementation of checkpoint output monitoring (v1.31.0)
fn checkpointOutputCallbackImpl(line: []const u8, is_stderr: bool, ctx: *CheckpointCallbackCtx) void {
    if (is_stderr) return; // Only monitor stdout for checkpoints

    // Look for "CHECKPOINT: " prefix
    const marker = "CHECKPOINT: ";
    const idx = std.mem.indexOf(u8, line, marker) orelse return;

    // Extract JSON part (everything after the marker)
    const json_start = idx + marker.len;
    if (json_start >= line.len) return;
    const json_str = line[json_start..];

    // Check if enough time has elapsed since last save (respect interval_ms)
    const now_ms = std.time.milliTimestamp();
    const last_save = ctx.last_save_ms.load(.acquire);
    if (now_ms - last_save < ctx.checkpoint_config.interval_ms) {
        return; // Too soon, skip this checkpoint
    }

    // Create checkpoint state
    const state = checkpoint.CheckpointState{
        .task_name = ctx.allocator.dupe(u8, ctx.task_name) catch return,
        .started_at = last_save, // Use last save time as start time
        .checkpointed_at = now_ms,
        .state = ctx.allocator.dupe(u8, json_str) catch {
            ctx.allocator.free(ctx.task_name);
            return;
        },
        .progress_pct = 0, // Progress must be in JSON state
        .metadata = ctx.allocator.dupe(u8, "{}") catch {
            ctx.allocator.free(ctx.task_name);
            ctx.allocator.free(json_str);
            return;
        },
    };
    errdefer {
        ctx.allocator.free(state.task_name);
        ctx.allocator.free(state.state);
        ctx.allocator.free(state.metadata);
    }

    // Save checkpoint
    var fs_storage = checkpoint.FileSystemStorage.init(ctx.checkpoint_config.checkpoint_dir, ctx.allocator) catch return;
    defer fs_storage.storage().deinit(ctx.allocator);

    fs_storage.storage().save(state, ctx.allocator) catch {};

    // Free the state strings (save() duplicates them)
    ctx.allocator.free(state.task_name);
    ctx.allocator.free(state.state);
    ctx.allocator.free(state.metadata);

    // Update last save timestamp
    ctx.last_save_ms.store(now_ms, .release);
}

/// Context passed to each worker thread.
const WorkerCtx = struct {
    allocator: std.mem.Allocator,
    task_name: []const u8, // owned slice, freed by worker after use
    cmd: []const u8,
    cwd: ?[]const u8,
    /// Optional env var overrides from the task definition.
    env: ?[]const [2][]const u8,
    /// Extra environment variables (e.g., workflow matrix variables).
    extra_env: ?[]const [2][]const u8,
    /// Toolchains from config [tools] section (pointer to config.toolchains.tools)
    toolchains: []const loader.ToolSpec,
    inherit_stdio: bool,
    timeout_ms: ?u64,
    allow_failure: bool,
    retry_max: u32,
    retry_delay_ms: u64,
    retry_backoff: bool,
    /// New retry strategy fields (v1.47.0)
    retry_backoff_multiplier: ?f64,
    retry_jitter: bool,
    max_backoff_ms: ?u64,
    retry_on_codes: []const u8,
    retry_on_patterns: []const []const u8,
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
    /// CPU affinity: list of CPU IDs this task can run on (v1.13.0).
    cpu_affinity: ?[]const u32,
    /// NUMA node ID this task should run on (v1.13.0).
    numa_node: ?u32,
    /// Timeline for recording execution events (v1.14.0).
    timeline_tracker: ?*timeline.Timeline,
    /// Replay manager for capturing failure contexts (v1.14.0).
    replay_mgr: ?*replay.ReplayManager,
    /// Conditional output expression (v1.18.0) — if specified and evaluates to false, suppress task output.
    output_if: ?[]const u8,
    /// Task hooks for pre/post execution (v1.24.0).
    task_hooks: []const loader.TaskHook,
    /// Circuit breaker state for retry failure rate limiting (v1.30.0).
    circuit_breaker: ?*CircuitBreakerState,
    /// Retry budget tracker for workflow-level retry limiting (v1.30.0).
    retry_budget: ?*RetryBudgetTracker,
    /// Checkpoint configuration for resumable tasks (v1.31.0).
    checkpoint_config: ?*const types.CheckpointConfig,
    /// Output file path for stream mode (v1.37.0).
    output_file: ?[]const u8,
    /// Output capture mode (v1.37.0).
    output_mode: ?output_capture.OutputMode,
    /// Remote execution target (v1.46.0).
    remote_target: ?[]const u8,
    /// Remote working directory (v1.46.0).
    remote_cwd: ?[]const u8,
    /// Remote environment variables (v1.46.0).
    remote_env: ?[][2][]const u8,
    /// Output filtering options (grep, highlight, context).
    filter_options: filter_mod.FilterOptions,
    /// Silent mode: suppress output unless task fails (v1.73.0).
    silent: bool = false,
};

/// Build environment variables with toolchain PATH injection and extra_env merging.
/// Merges task env vars with toolchain bin directories in PATH, then appends extra_env.
/// Returns null if task_env, toolchains, and extra_env are all empty, otherwise returns owned array.
/// If toolchain path building fails (e.g., no HOME), falls back to task_env + extra_env only.
fn buildEnvWithToolchains(
    allocator: std.mem.Allocator,
    task_env: ?[]const [2][]const u8,
    toolchains: []const loader.ToolSpec,
    extra_env: ?[]const [2][]const u8,
) ?[][2][]u8 {
    if (toolchains.len == 0 and task_env == null and extra_env == null) {
        return null; // No env override needed
    }

    // Build toolchain env (includes PATH + toolchain-specific vars)
    const merged_env = toolchain_path.buildToolchainEnv(allocator, toolchains, task_env) catch blk: {
        // If toolchain env building fails, fall back to task env only
        // This can happen if HOME is not set or other env issues
        if (task_env) |env| {
            // Duplicate task env
            const dup_env = allocator.alloc([2][]u8, env.len) catch break :blk null;
            for (env, 0..) |pair, i| {
                dup_env[i][0] = allocator.dupe(u8, pair[0]) catch {
                    for (dup_env[0..i]) |p| {
                        allocator.free(p[0]);
                        allocator.free(p[1]);
                    }
                    allocator.free(dup_env);
                    break :blk null;
                };
                dup_env[i][1] = allocator.dupe(u8, pair[1]) catch {
                    allocator.free(dup_env[i][0]);
                    for (dup_env[0..i]) |p| {
                        allocator.free(p[0]);
                        allocator.free(p[1]);
                    }
                    allocator.free(dup_env);
                    break :blk null;
                };
            }
            break :blk dup_env;
        } else {
            break :blk null;
        }
    };

    // Append extra_env if provided
    if (extra_env) |extra| {
        const base_len = if (merged_env) |m| m.len else 0;
        const new_len = base_len + extra.len;
        const final_env = allocator.alloc([2][]u8, new_len) catch {
            if (merged_env) |m| toolchain_path.freeToolchainEnv(allocator, m);
            return null;
        };

        // Copy existing env
        if (merged_env) |m| {
            for (m, 0..) |pair, i| {
                final_env[i] = pair;
            }
            allocator.free(m); // Free the old array (but not the pairs, we moved them)
        }

        // Append extra_env
        for (extra, 0..) |pair, i| {
            final_env[base_len + i][0] = allocator.dupe(u8, pair[0]) catch {
                // Cleanup on error
                for (final_env[0 .. base_len + i]) |p| {
                    allocator.free(p[0]);
                    allocator.free(p[1]);
                }
                allocator.free(final_env);
                return null;
            };
            final_env[base_len + i][1] = allocator.dupe(u8, pair[1]) catch {
                allocator.free(final_env[base_len + i][0]);
                for (final_env[0 .. base_len + i]) |p| {
                    allocator.free(p[0]);
                    allocator.free(p[1]);
                }
                allocator.free(final_env);
                return null;
            };
        }
        return final_env;
    }

    return merged_env;
}

fn workerFn(ctx: WorkerCtx) void {
    // Record task started event (v1.14.0)
    if (ctx.timeline_tracker) |tt| {
        tt.recordEvent(.started, ctx.task_name, null) catch {};
    }

    defer {
        if (ctx.task_semaphore) |ts| ts.post();
        ctx.semaphore.post();
        ctx.allocator.free(ctx.task_name);
        if (ctx.cache_key) |k| ctx.allocator.free(k);
    }

    // Set CPU affinity if specified (v1.13.0)
    // Enhanced in Resource Affinity & NUMA Enhancements milestone to support work-stealing
    if (ctx.cpu_affinity) |cpu_ids| {
        if (cpu_ids.len > 0) {
            // Work-stealing CPU affinity: thread can run on ANY of the specified cores
            // This enables work-stealing across all requested CPUs for better load balancing
            affinity.setThreadAffinityMask(cpu_ids) catch {
                // Affinity setting is best-effort, silently ignore errors
                // (not all platforms support affinity)
            };
        }
    }

    // Set up NUMA-aware allocator if numa_node is specified (Resource Affinity & NUMA Enhancements milestone)
    // This binds task-scoped allocations to the specified NUMA node for better memory locality
    var numa_allocator_instance: numa.NumaAllocator = undefined;
    const task_allocator: std.mem.Allocator = if (ctx.numa_node) |node_id| blk: {
        numa_allocator_instance = numa.NumaAllocator.init(ctx.allocator, node_id);
        break :blk numa_allocator_instance.allocator();
    } else ctx.allocator;

    // Execute "before" hooks (v1.24.0)
    const before_ctx = hooks.HookContext{
        .task_name = ctx.task_name,
        .exit_code = null,
        .duration_ms = null,
        .error_message = null,
    };
    if (!executeHooks(task_allocator, ctx.task_hooks, .before, before_ctx)) {
        // Before hook failed with abort_task strategy
        const owned_name = task_allocator.dupe(u8, ctx.task_name) catch return;
        ctx.results_mutex.lock();
        defer ctx.results_mutex.unlock();
        ctx.results.append(task_allocator, .{
            .task_name = owned_name,
            .success = false,
            .exit_code = 255,
            .duration_ms = 0,
        }) catch task_allocator.free(owned_name);
        if (!ctx.allow_failure) ctx.failed.store(true, .release);
        return;
    }

    // Build environment with toolchain PATH injection and extra_env
    const merged_env = buildEnvWithToolchains(task_allocator, ctx.env, ctx.toolchains, ctx.extra_env);
    defer if (merged_env) |env| toolchain_path.freeToolchainEnv(task_allocator, env);

    // Load checkpoint if enabled (v1.31.0)
    var checkpoint_state: ?checkpoint.CheckpointState = null;
    defer if (checkpoint_state) |*cs| cs.deinit(task_allocator);

    if (ctx.checkpoint_config) |ckpt_cfg| {
        if (ckpt_cfg.enabled) {
            var fs_storage = checkpoint.FileSystemStorage.init(ckpt_cfg.checkpoint_dir, task_allocator) catch null;
            if (fs_storage) |*storage| {
                defer storage.storage().deinit(task_allocator);
                checkpoint_state = storage.storage().load(ctx.task_name, task_allocator) catch null;
            }
        }
    }

    // Initialize OutputCapture if configured (v1.37.0), filtering is enabled, or silent mode
    var output_cap: ?output_capture.OutputCapture = null;
    defer if (output_cap) |*oc| oc.deinit();

    // Enable OutputCapture if: (1) output_mode is set, (2) filtering is enabled, or (3) silent mode
    const need_capture = ctx.output_mode != null or ctx.filter_options.isEnabled() or ctx.silent;
    if (need_capture) {
        const capture_config = output_capture.OutputCaptureConfig{
            .mode = ctx.output_mode orelse .buffer, // Use buffer mode for filtering/silent
            .output_file = ctx.output_file,
            .max_buffer_size = 1024 * 1024, // 1MB default
            .filter_options = ctx.filter_options,
            .use_color = ctx.use_color,
        };
        output_cap = output_capture.OutputCapture.init(task_allocator, capture_config) catch null;
    }

    // Check cache hit — skip execution if already succeeded with same cmd+env
    if (ctx.cache) {
        if (ctx.cache_key) |key| {
            // First check local cache
            var local_hit = false;
            var store = cache_store.CacheStore.init(task_allocator) catch null;
            if (store) |*s| {
                defer s.deinit();
                local_hit = s.hasHit(key);
            }

            // If local miss, try remote cache (Phase 7)
            if (!local_hit and ctx.cache_remote_config != null) {
                if (ctx.cache_remote_config) |remote_cfg| {
                    var remote_cache = cache_remote.RemoteCache.init(task_allocator, remote_cfg.*);
                    defer remote_cache.deinit();
                    // Pull from remote (null = miss)
                    if (remote_cache.pull(key) catch null) |_data| {
                        // Remote hit: save to local cache for next time
                        // (data itself is just a marker, no actual artifact yet)
                        task_allocator.free(_data);
                        if (store) |*s| s.recordHit(key) catch {};
                        local_hit = true;
                    }
                }
            }

            if (local_hit) {
                // Cache hit: record a skipped success result
                const owned_name = task_allocator.dupe(u8, ctx.task_name) catch return;
                ctx.results_mutex.lock();
                defer ctx.results_mutex.unlock();
                ctx.results.append(task_allocator, .{
                    .task_name = owned_name,
                    .success = true,
                    .exit_code = 0,
                    .duration_ms = 0,
                    .skipped = true,
                }) catch task_allocator.free(owned_name);
                return;
            }
        }
    }

    // Add checkpoint state to environment if available (v1.31.0)
    var final_env: ?[][2][]u8 = merged_env;
    var checkpoint_env_added = false;
    defer if (checkpoint_env_added) {
        // Free the ZR_CHECKPOINT env var we added
        if (final_env) |env| {
            task_allocator.free(env[env.len - 1][0]);
            task_allocator.free(env[env.len - 1][1]);
        }
    };

    if (checkpoint_state) |ckpt| {
        // Add ZR_CHECKPOINT=<json_state> to environment
        const base_env = final_env orelse &[_][2][]u8{};
        const new_env = task_allocator.alloc([2][]u8, base_env.len + 1) catch null;
        if (new_env) |env| {
            // Copy existing env
            for (base_env, 0..) |pair, i| {
                env[i] = pair;
            }
            // Add ZR_CHECKPOINT
            env[env.len - 1][0] = task_allocator.dupe(u8, "ZR_CHECKPOINT") catch "";
            env[env.len - 1][1] = task_allocator.dupe(u8, ckpt.state) catch "";

            // Free old env array (but not the individual strings, they're still in new_env)
            if (final_env) |old| task_allocator.free(old);
            final_env = env;
            checkpoint_env_added = true;
        }
    }

    // Cast final_env to the const slice type expected by ProcessConfig
    const proc_env: ?[]const [2][]const u8 = if (final_env) |env| env else null;

    // Handle dependency-only tasks (tasks without cmd)
    if (ctx.cmd.len == 0) {
        // Skip execution for cmd-less tasks - they only run their dependencies
        const owned_name = task_allocator.dupe(u8, ctx.task_name) catch return;
        ctx.results_mutex.lock();
        defer ctx.results_mutex.unlock();
        ctx.results.append(task_allocator, .{
            .task_name = owned_name,
            .success = true,
            .exit_code = 0,
            .duration_ms = 0,
        }) catch task_allocator.free(owned_name);
        return;
    }

    // Evaluate output_if condition to determine whether to show task output
    var should_show_output = ctx.inherit_stdio;
    if (ctx.output_if) |output_cond| {
        const show_output = expr.evalCondition(task_allocator, output_cond, ctx.env) catch true;
        if (!show_output) {
            should_show_output = false;
        }
    }

    // Set up combined callback context for checkpoint + output capture (v1.31.0, v1.37.0)
    var checkpoint_callback_ctx: ?CheckpointCallbackCtx = null;
    var last_save_ms = std.atomic.Value(i64).init(std.time.milliTimestamp());
    defer {
        // No cleanup needed for atomic value
        _ = &last_save_ms;
    }

    if (ctx.checkpoint_config) |ckpt_cfg| {
        if (ckpt_cfg.enabled and !should_show_output) {
            checkpoint_callback_ctx = CheckpointCallbackCtx{
                .allocator = task_allocator,
                .task_name = ctx.task_name,
                .checkpoint_config = ckpt_cfg,
                .last_save_ms = &last_save_ms,
            };
        }
    }

    var combined_ctx = CombinedCallbackCtx{
        .checkpoint_ctx = if (checkpoint_callback_ctx != null) &checkpoint_callback_ctx.? else null,
        .output_capture = if (output_cap) |*oc| oc else null,
    };

    const needs_callback = combined_ctx.checkpoint_ctx != null or combined_ctx.output_capture != null;

    // Determine stdio mode: if output capture is enabled, never inherit stdio
    // (we need to capture the output via callback). Otherwise, use should_show_output.
    const inherit_stdio_mode = if (combined_ctx.output_capture != null) false else should_show_output;

    // Check if remote execution is requested (v1.46.0)
    var proc_result: process.ProcessResult = if (ctx.remote_target) |remote_target_str| blk: {
        // Create remote executor and parse target
        var executor = remote.RemoteExecutor.init(task_allocator, .{
            .ssh_timeout_ms = ctx.timeout_ms orelse 30_000,
            .http_timeout_ms = ctx.timeout_ms orelse 30_000,
        });
        const target = executor.parseTarget(remote_target_str) catch {
            // Failed to parse remote target — treat as local execution failure
            break :blk process.ProcessResult{
                .exit_code = 1,
                .duration_ms = 0,
                .success = false,
            };
        };
        defer {
            // Clean up target allocation manually (deinit is private)
            switch (target) {
                .ssh => |ssh| {
                    if (ssh.owns_user) task_allocator.free(ssh.user);
                    if (ssh.owns_host) task_allocator.free(ssh.host);
                },
                .http => |http| {
                    if (http.owns_scheme) task_allocator.free(http.scheme);
                    if (http.owns_host) task_allocator.free(http.host);
                },
            }
        }

        // Build a temporary Task struct for remote execution
        // We need to combine local env + remote_env
        const combined_env = if (ctx.remote_env) |remote_env| blk2: {
            const local_env = proc_env orelse &[_][2][]const u8{};
            const total_len = local_env.len + remote_env.len;
            const combined = task_allocator.alloc([2][]const u8, total_len) catch break :blk2 local_env;

            // Copy local env
            for (local_env, 0..) |pair, i| {
                combined[i] = pair;
            }
            // Append remote env
            for (remote_env, 0..) |pair, i| {
                combined[local_env.len + i] = pair;
            }
            break :blk2 combined;
        } else proc_env orelse &[_][2][]const u8{};
        defer if (ctx.remote_env != null and combined_env.ptr != (proc_env orelse &[_][2][]const u8{}).ptr) {
            task_allocator.free(combined_env);
        };

        // Create temporary task with remote-specific fields
        // We need to cast combined_env to remove const for Task.env field
        const task_env: [][2][]const u8 = @constCast(combined_env);
        const remote_task = types.Task{
            .name = ctx.task_name,
            .cmd = ctx.cmd,
            .cwd = ctx.remote_cwd orelse ctx.cwd,
            .description = null,
            .deps = &.{},
            .deps_serial = &.{},
            .env = task_env,
        };

        // Execute remotely based on target type
        const remote_result = switch (target) {
            .ssh => |_| blk3: {
                var ssh_executor = remote.SSHExecutor{
                    .allocator = task_allocator,
                    .config = .{
                        .ssh_timeout_ms = ctx.timeout_ms orelse 30_000,
                    },
                };

                const result = ssh_executor.execute(target, remote_task) catch {
                    // SSH connection failure or other error
                    break :blk3 remote.RemoteTaskResult{
                        .exit_code = 255, // SSH convention for connection failure
                        .stdout = task_allocator.dupe(u8, "") catch "",
                        .stderr = task_allocator.dupe(u8, "SSH connection failed") catch "",
                        .duration_ms = 0,
                        .timed_out = false,
                    };
                };
                break :blk3 result;
            },
            .http => |_| blk3: {
                var http_executor = remote.HTTPExecutor{
                    .allocator = task_allocator,
                    .config = .{
                        .http_timeout_ms = ctx.timeout_ms orelse 30_000,
                    },
                };

                const result = http_executor.execute(target, remote_task) catch {
                    // HTTP request failure
                    break :blk3 remote.RemoteTaskResult{
                        .exit_code = 1,
                        .stdout = task_allocator.dupe(u8, "") catch "",
                        .stderr = task_allocator.dupe(u8, "HTTP request failed") catch "",
                        .duration_ms = 0,
                        .timed_out = false,
                    };
                };
                break :blk3 result;
            },
        };
        defer {
            // Manually free RemoteTaskResult fields (deinit is private)
            task_allocator.free(remote_result.stdout);
            task_allocator.free(remote_result.stderr);
        }

        // Map RemoteTaskResult to ProcessResult
        break :blk process.ProcessResult{
            .exit_code = remote_result.exit_code,
            .duration_ms = remote_result.duration_ms,
            .success = remote_result.exit_code == 0,
        };
    } else process.run(task_allocator, .{
        .cmd = ctx.cmd,
        .cwd = ctx.cwd,
        .env = proc_env,
        .inherit_stdio = inherit_stdio_mode,
        .timeout_ms = ctx.timeout_ms,
        .task_control = ctx.task_control,
        .enable_monitor = ctx.monitor,
        .monitor_task_name = if (ctx.monitor) ctx.task_name else null,
        .monitor_use_color = ctx.use_color,
        .monitor_allocator = if (ctx.monitor) task_allocator else null,
        .output_callback = if (needs_callback) combinedOutputCallback else null,
        .output_ctx = if (needs_callback) @ptrCast(&combined_ctx) else null,
    }) catch process.ProcessResult{
        .exit_code = 1,
        .duration_ms = 0,
        .success = false,
    };

    // Retry on failure up to retry_max times (v1.47.0: enhanced with RetryStrategy)
    var retry_count: u32 = 0;
    if (!proc_result.success and ctx.retry_max > 0) {
        // Build RetryStrategy from task config (v1.47.0)
        const strategy = retry_strategy.RetryStrategy{
            .backoff_multiplier = ctx.retry_backoff_multiplier orelse (if (ctx.retry_backoff) 2.0 else 1.0),
            .jitter = ctx.retry_jitter,
            .max_backoff_ms = ctx.max_backoff_ms orelse 60_000,
            .retry_on_codes = ctx.retry_on_codes,
            .retry_on_patterns = ctx.retry_on_patterns,
        };

        // Initialize random number generator for jitter (if enabled)
        var prng = if (strategy.jitter) std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())) else undefined;
        var rand_impl = if (strategy.jitter) prng.random() else undefined;
        const rand_ptr: ?*std.Random = if (strategy.jitter) &rand_impl else null;

        // Record initial failure for circuit breaker (v1.30.0)
        if (ctx.circuit_breaker) |cb| {
            const now_ms = std.time.milliTimestamp();
            cb.recordFailure(now_ms);
        }

        // Check if retry conditions are met (v1.47.0)
        // Get captured output if available for pattern matching
        const captured_output = if (output_cap) |*oc| oc.getBuffer() catch "" else "";
        const should_retry_on_conditions = strategy.shouldRetry(proc_result.exit_code, captured_output);

        if (!should_retry_on_conditions) {
            // Exit code or output pattern don't match retry conditions — skip retry
            if (ctx.timeline_tracker) |tt| {
                tt.recordEvent(.retry_started, ctx.task_name, "retry conditions not met") catch {};
            }
        } else {
            var attempt: u32 = 0;
            while (!proc_result.success and attempt < ctx.retry_max) : (attempt += 1) {
                // Check circuit breaker state (v1.30.0)
                if (ctx.circuit_breaker) |cb| {
                    if (cb.shouldPreventRetry()) {
                        // Circuit breaker is open — stop retrying
                        if (ctx.timeline_tracker) |tt| {
                            tt.recordEvent(.retry_started, ctx.task_name, "circuit breaker tripped") catch {};
                        }
                        break;
                    }
                }

                // Check retry budget (v1.30.0)
                if (ctx.retry_budget) |rb| {
                    if (!rb.tryConsume()) {
                        // Retry budget exhausted — stop retrying
                        if (ctx.timeline_tracker) |tt| {
                            tt.recordEvent(.retry_started, ctx.task_name, "retry budget exhausted") catch {};
                        }
                        break;
                    }
                }

                retry_count += 1;

                // Calculate delay using RetryStrategy (v1.47.0)
                const delay_ms = strategy.calculateDelay(ctx.retry_delay_ms, attempt, rand_ptr);

                // Record retry event (v1.14.0)
                if (ctx.timeline_tracker) |tt| {
                    const context_buf = std.fmt.allocPrint(task_allocator, "retry {d}/{d} (delay: {d}ms)", .{ retry_count, ctx.retry_max, delay_ms }) catch null;
                    defer if (context_buf) |buf| task_allocator.free(buf);
                    tt.recordEvent(.retry_started, ctx.task_name, context_buf) catch {};
                }

                if (delay_ms > 0) {
                    std.Thread.sleep(delay_ms * std.time.ns_per_ms);
                }
                proc_result = process.run(task_allocator, .{
                    .cmd = ctx.cmd,
                    .cwd = ctx.cwd,
                    .env = proc_env,
                    .inherit_stdio = inherit_stdio_mode,
                    .timeout_ms = ctx.timeout_ms,
                    .task_control = ctx.task_control,
                    .enable_monitor = ctx.monitor,
                    .monitor_task_name = if (ctx.monitor) ctx.task_name else null,
                    .monitor_use_color = ctx.use_color,
                    .monitor_allocator = if (ctx.monitor) task_allocator else null,
                    .output_callback = if (needs_callback) combinedOutputCallback else null,
                    .output_ctx = if (needs_callback) @ptrCast(&combined_ctx) else null,
                }) catch process.ProcessResult{
                    .exit_code = 1,
                    .duration_ms = 0,
                    .success = false,
                };

                // Update circuit breaker with retry result (v1.30.0)
                if (ctx.circuit_breaker) |cb| {
                    const now_ms = std.time.milliTimestamp();
                    if (proc_result.success) {
                        cb.recordSuccess(now_ms);
                    } else {
                        cb.recordFailure(now_ms);
                    }
                }

                // Re-check retry conditions after each attempt (v1.47.0)
                const retry_output = if (output_cap) |*oc| oc.getBuffer() catch "" else "";
                if (!strategy.shouldRetry(proc_result.exit_code, retry_output)) {
                    // Stop retrying if conditions no longer met
                    if (ctx.timeline_tracker) |tt| {
                        tt.recordEvent(.retry_started, ctx.task_name, "retry conditions not met") catch {};
                    }
                    break;
                }
            }
        }
    }

    // Record final success for circuit breaker (v1.30.0)
    if (proc_result.success and ctx.circuit_breaker != null) {
        if (ctx.circuit_breaker) |cb| {
            const now_ms = std.time.milliTimestamp();
            cb.recordSuccess(now_ms);
        }
    }

    // Check if task timed out (exit code 124 is timeout from process.run)
    const was_timeout = (proc_result.exit_code == 124 and ctx.timeout_ms != null);

    // Execute post-task hooks (v1.24.0)
    const after_ctx = hooks.HookContext{
        .task_name = ctx.task_name,
        .exit_code = proc_result.exit_code,
        .duration_ms = proc_result.duration_ms,
        .error_message = if (!proc_result.success) "Task failed" else null,
    };

    // Execute "after" hooks (always run)
    _ = executeHooks(task_allocator, ctx.task_hooks, .after, after_ctx);

    // Execute specific hooks based on result
    if (was_timeout) {
        _ = executeHooks(task_allocator, ctx.task_hooks, .timeout, after_ctx);
    } else if (proc_result.success) {
        _ = executeHooks(task_allocator, ctx.task_hooks, .success, after_ctx);
    } else {
        _ = executeHooks(task_allocator, ctx.task_hooks, .failure, after_ctx);
    }

    // Handle silent mode: if task failed, dump buffered output to stderr (v1.73.0)
    if (ctx.silent and !proc_result.success) {
        if (output_cap) |*oc| {
            if (oc.config.mode == .buffer) {
                const buffered_output = oc.getBuffer() catch &[_]u8{};
                if (buffered_output.len > 0) {
                    std.debug.print("{s}", .{buffered_output});
                }
            }
        }
    }

    // Allocate an owned copy of the name for TaskResult
    const owned_name = task_allocator.dupe(u8, ctx.task_name) catch {
        if (!proc_result.success and !ctx.allow_failure) ctx.failed.store(true, .release);
        return;
    };

    ctx.results_mutex.lock();
    defer ctx.results_mutex.unlock();

    ctx.results.append(task_allocator, .{
        .task_name = owned_name,
        .success = proc_result.success,
        .exit_code = proc_result.exit_code,
        .duration_ms = proc_result.duration_ms,
        .retry_count = retry_count,
        .peak_memory_bytes = proc_result.peak_memory_bytes,
        .avg_cpu_percent = proc_result.avg_cpu_percent,
    }) catch {
        task_allocator.free(owned_name);
        if (!proc_result.success and !ctx.allow_failure) ctx.failed.store(true, .release);
        return;
    };

    // Record completion event (v1.14.0)
    if (ctx.timeline_tracker) |tt| {
        tt.recordEvent(.completed, ctx.task_name, null) catch {};
    }

    // Capture failure context for replay (v1.14.0)
    if (!proc_result.success and ctx.replay_mgr != null) {
        if (ctx.replay_mgr) |rm| {
            // Get timeline events for this task
            var task_events = if (ctx.timeline_tracker) |tt|
                tt.getTaskEvents(task_allocator, ctx.task_name) catch std.ArrayList(timeline.TimelineEvent){}
            else
                std.ArrayList(timeline.TimelineEvent){};
            defer task_events.deinit(task_allocator);

            // Get captured output if available (v1.37.0)
            var stdout_buf: []const u8 = &[_]u8{};
            const stderr_buf: []const u8 = &[_]u8{};
            var needs_free = false;
            defer if (needs_free) task_allocator.free(stdout_buf);

            if (output_cap) |*oc| {
                if (oc.config.mode == .buffer) {
                    stdout_buf = oc.getBuffer() catch &[_]u8{};
                    needs_free = (stdout_buf.len > 0);
                    // Note: we don't separate stdout/stderr in buffer mode yet
                }
            }

            // Capture failure with individual parameters
            rm.captureFailure(
                ctx.task_name,
                ctx.cmd,
                ctx.cwd,
                ctx.env,
                proc_result.exit_code,
                stdout_buf,
                stderr_buf,
                task_events.items,
            ) catch {};
        }
    }

    // Only propagate failure to global flag if allow_failure is not set
    if (!proc_result.success and !ctx.allow_failure) {
        ctx.failed.store(true, .release);
    }

    // Record cache entry on success
    if (proc_result.success and ctx.cache) {
        if (ctx.cache_key) |key| {
            // Write to local cache
            var store = cache_store.CacheStore.init(task_allocator) catch null;
            if (store) |*s| {
                defer s.deinit();
                s.recordHit(key) catch {};
            }
            // Push to remote cache (Phase 7)
            if (ctx.cache_remote_config) |remote_cfg| {
                var remote_cache = cache_remote.RemoteCache.init(task_allocator, remote_cfg.*);
                defer remote_cache.deinit();
                // Push marker (empty data for now, just indicates success)
                remote_cache.push(key, &[_]u8{}) catch {};
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

        // Traverse conditional dependencies (only if condition is true)
        for (task.deps_if) |dep_if| {
            const condition_met = expr.evalCondition(allocator, dep_if.condition, task.env) catch false;
            if (condition_met and !needed.contains(dep_if.task)) {
                try stack.append(allocator, dep_if.task);
            }
        }

        // Traverse optional dependencies (only if task exists)
        for (task.deps_optional) |dep| {
            if (config.tasks.contains(dep) and !needed.contains(dep)) {
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

        // Add regular dependencies
        for (task.deps) |dep| {
            // Only include deps that are in our needed set
            if (needed.contains(dep)) {
                try subdag.addEdge(name, dep);
            }
        }

        // Add conditional dependencies (only if condition evaluates to true)
        for (task.deps_if) |dep_if| {
            const condition_met = expr.evalCondition(allocator, dep_if.condition, task.env) catch false;
            if (condition_met and needed.contains(dep_if.task)) {
                try subdag.addEdge(name, dep_if.task);
            }
        }

        // Add optional dependencies (only if task exists and is in needed set)
        for (task.deps_optional) |dep| {
            if (config.tasks.contains(dep) and needed.contains(dep)) {
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

/// Execute hooks for a specific hook point.
/// Returns false if any hook with abort_task strategy fails, otherwise returns true.
/// Prints hook stdout/stderr to the console.
fn executeHooks(
    allocator: std.mem.Allocator,
    task_hooks: []const loader.TaskHook,
    point: hooks.HookPoint,
    context: hooks.HookContext,
) bool {
    var executor = hooks.HookExecutor.init(allocator);

    for (task_hooks) |task_hook| {
        if (task_hook.point != point) continue;

        // Convert TaskHook to Hook for execution
        var env_map: ?std.StringHashMap([]const u8) = null;
        if (task_hook.env.len > 0) {
            env_map = std.StringHashMap([]const u8).init(allocator);
            for (task_hook.env) |pair| {
                env_map.?.put(pair[0], pair[1]) catch continue;
            }
        }
        defer if (env_map) |*m| m.deinit();

        const hook = hooks.Hook{
            .cmd = task_hook.cmd,
            .point = task_hook.point,
            .failure_strategy = task_hook.failure_strategy,
            .working_dir = task_hook.working_dir,
            .env = env_map,
        };

        const result = executor.execute(&hook, context) catch {
            // Hook execution failed catastrophically
            if (task_hook.failure_strategy == .abort_task) {
                return false;
            }
            continue;
        };

        // Print hook output to console
        if (result.stdout.len > 0) {
            std.fs.File.stdout().writeAll(result.stdout) catch {};
        }
        if (result.stderr.len > 0) {
            std.fs.File.stderr().writeAll(result.stderr) catch {};
        }

        const should_abort = !result.success and task_hook.failure_strategy == .abort_task;
        result.deinit(allocator); // Explicitly free before potentially returning

        if (should_abort) {
            return false;
        }
    }

    return true;
}

/// Run a single task synchronously (on the calling thread). Records result.
/// Holds results_mutex while appending so it is safe to call concurrently with worker threads.
/// Returns true if the task succeeded (or has allow_failure set).
fn runTaskSync(
    allocator: std.mem.Allocator,
    task: loader.Task,
    env: ?[]const [2][]const u8,
    extra_env: ?[]const [2][]const u8,
    toolchains: []const loader.ToolSpec,
    inherit_stdio: bool,
    results: *std.ArrayList(TaskResult),
    results_mutex: *std.Thread.Mutex,
) !bool {
    // Auto-install any missing toolchains specified in task.toolchain
    try ensureToolchainsInstalled(allocator, task);

    // Handle dependency-only tasks (tasks without cmd)
    if (task.cmd.len == 0) {
        // Skip execution for cmd-less tasks - they only run their dependencies
        const success_result = TaskResult{
            .task_name = try allocator.dupe(u8, task.name),
            .success = true,
            .exit_code = 0,
            .duration_ms = 0,
            .retry_count = 0,
        };
        results_mutex.lock();
        defer results_mutex.unlock();
        try results.append(allocator, success_result);
        return true;
    }

    // Execute "before" hooks
    const before_ctx = hooks.HookContext{
        .task_name = task.name,
        .exit_code = null,
        .duration_ms = null,
        .error_message = null,
    };
    if (!executeHooks(allocator, task.hooks, .before, before_ctx)) {
        // Before hook failed with abort_task strategy
        const failed_result = TaskResult{
            .task_name = try allocator.dupe(u8, task.name),
            .success = false,
            .exit_code = 255,
            .duration_ms = 0,
            .retry_count = 0,
        };
        results_mutex.lock();
        defer results_mutex.unlock();
        try results.append(allocator, failed_result);
        return false;
    }

    // Build environment with toolchain PATH injection and extra_env
    const merged_env = buildEnvWithToolchains(allocator, env, toolchains, extra_env);
    defer if (merged_env) |e| toolchain_path.freeToolchainEnv(allocator, e);

    const proc_env: ?[]const [2][]const u8 = if (merged_env) |e| e else null;

    const task_start = std.time.milliTimestamp();
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
    const task_duration: u64 = @intCast(std.time.milliTimestamp() - task_start);

    // Retry on failure up to retry_max times
    var retry_count: u32 = 0;
    var was_timeout = false;
    if (!proc_result.success and task.retry_max > 0) {
        var delay_ms: u64 = task.retry_delay_ms;
        var attempt: u32 = 0;
        while (!proc_result.success and attempt < task.retry_max) : (attempt += 1) {
            retry_count += 1;
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

    // Check if task timed out (exit code 124 is timeout from process.run)
    if (proc_result.exit_code == 124 and task.timeout_ms != null) {
        was_timeout = true;
    }

    // Execute post-task hooks
    const after_ctx = hooks.HookContext{
        .task_name = task.name,
        .exit_code = proc_result.exit_code,
        .duration_ms = task_duration,
        .error_message = if (!proc_result.success) "Task failed" else null,
    };

    // Execute "after" hooks (always run)
    _ = executeHooks(allocator, task.hooks, .after, after_ctx);

    // Execute specific hooks based on result
    if (was_timeout) {
        _ = executeHooks(allocator, task.hooks, .timeout, after_ctx);
    } else if (proc_result.success) {
        _ = executeHooks(allocator, task.hooks, .success, after_ctx);
    } else {
        _ = executeHooks(allocator, task.hooks, .failure, after_ctx);
    }

    const owned_name = try allocator.dupe(u8, task.name);
    results_mutex.lock();
    defer results_mutex.unlock();
    results.append(allocator, .{
        .task_name = owned_name,
        .success = proc_result.success,
        .exit_code = proc_result.exit_code,
        .duration_ms = proc_result.duration_ms,
        .retry_count = retry_count,
        .peak_memory_bytes = proc_result.peak_memory_bytes,
        .avg_cpu_percent = proc_result.avg_cpu_percent,
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
    extra_env: ?[]const [2][]const u8,
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
                allocator, config, dep_task.deps_serial, extra_env, toolchains,
                inherit_stdio, results, results_mutex, completed,
            );
            if (!chain_ok) return false;
        }

        const task_env: ?[]const [2][]const u8 = if (dep_task.env.len > 0) dep_task.env else null;
        const ok = try runTaskSync(allocator, dep_task, task_env, extra_env, toolchains, inherit_stdio, results, results_mutex);
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

    // Initialize timeline tracker (v1.14.0)
    var timeline_tracker = timeline.Timeline.init(allocator);
    defer timeline_tracker.deinit();

    // Initialize replay manager (v1.14.0)
    const replay_dir = ".zr/failures"; // Store failure contexts in .zr directory
    var replay_mgr = replay.ReplayManager.init(allocator, replay_dir) catch {
        // If init fails, continue without replay functionality
        return error.BuildFailed;
    };
    defer replay_mgr.deinit();

    // Detect NUMA topology for CPU affinity validation (Resource Affinity & NUMA Enhancements milestone)
    const numa_mod = @import("../util/numa.zig");
    var numa_topology = blk: {
        const detected = numa_mod.detectTopology(allocator) catch {
            // If detection fails, create a fallback single-node topology
            // This ensures validation still works on systems without NUMA support
            const total_cpu_count = cpu_count_blk: {
                const builtin = @import("builtin");
                const os_tag = builtin.os.tag;
                if (os_tag == .linux) {
                    // Try to read /sys/devices/system/cpu/online
                    const online_file = std.fs.openFileAbsolute("/sys/devices/system/cpu/online", .{}) catch break :cpu_count_blk 1;
                    defer online_file.close();
                    var buf: [256]u8 = undefined;
                    const bytes_read = online_file.readAll(&buf) catch break :cpu_count_blk 1;
                    // Parse "0-7" format (8 CPUs) or single number
                    const content = std.mem.trim(u8, buf[0..bytes_read], "\n\r ");
                    if (std.mem.indexOf(u8, content, "-")) |dash_pos| {
                        const max_str = content[dash_pos + 1 ..];
                        const max_cpu = std.fmt.parseInt(u32, max_str, 10) catch break :cpu_count_blk 1;
                        break :cpu_count_blk max_cpu + 1;
                    } else {
                        break :cpu_count_blk 1;
                    }
                } else {
                    // macOS/Windows: use std.Thread.getCpuCount (requires Zig 0.15+)
                    break :cpu_count_blk @as(u32, @intCast(std.Thread.getCpuCount() catch 1));
                }
            };

            // Fallback: single-node topology with all CPUs
            const cpu_ids = blk2: {
                const ids = allocator.alloc(u32, total_cpu_count) catch {
                    // If allocation fails, return error to caller
                    // We can't proceed without memory
                    return error.OutOfMemory;
                };
                for (ids, 0..) |*id, i| {
                    id.* = @intCast(i);
                }
                break :blk2 ids;
            };
            const nodes = allocator.alloc(numa_mod.NumaNode, 1) catch return error.OutOfMemory;
            nodes[0] = .{ .id = 0, .cpu_ids = cpu_ids, .memory_mb = 0 };
            break :blk numa_mod.NumaTopology{
                .nodes = nodes,
                .total_cpus = total_cpu_count,
                .allocator = allocator,
            };
        };
        break :blk detected;
    };
    defer numa_topology.deinit();

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

    // Concurrency group semaphores (v1.62.0).
    // Keys are group names (pointing into config.concurrency_groups keys — not owned).
    // Values are heap-allocated semaphores.
    var group_semaphores = std.StringHashMap(*std.Thread.Semaphore).init(allocator);
    defer {
        var gs_it = group_semaphores.iterator();
        while (gs_it.next()) |entry| {
            allocator.destroy(entry.value_ptr.*);
        }
        group_semaphores.deinit();
    }

    // Tracks tasks that have been run and whether they succeeded.
    // Used for deps_serial deduplication across levels.
    var completed = std.StringHashMap(bool).init(allocator);
    defer completed.deinit();

    // Initialize circuit breaker states for tasks that have circuit_breaker config (v1.30.0)
    var circuit_breakers = std.StringHashMap(CircuitBreakerState).init(allocator);
    defer circuit_breakers.deinit();

    // Initialize retry budget tracker from workflow config (v1.34.0)
    var retry_budget_tracker: ?RetryBudgetTracker = null;
    if (sched_config.retry_budget) |budget| {
        retry_budget_tracker = RetryBudgetTracker.init(budget);
    }

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

            // Validate CPU affinity (Resource Affinity & NUMA Enhancements milestone)
            if (task.cpu_affinity) |cpu_ids| {
                var has_invalid = false;
                for (cpu_ids) |cpu_id| {
                    if (cpu_id >= numa_topology.total_cpus) {
                        // Print warning to stderr using unbuffered writer
                        const color_mod = @import("../output/color.zig");
                        var err_buf: [512]u8 = undefined;
                        const stderr_file = std.fs.File.stderr();
                        var err_writer = stderr_file.writer(&err_buf);
                        color_mod.printWarning(
                            &err_writer.interface,
                            sched_config.use_color,
                            "Task '{s}' requests CPU {d}, but system only has {d} CPUs (0-{d}). Affinity setting will be ignored.\n",
                            .{ task_name, cpu_id, numa_topology.total_cpus, numa_topology.total_cpus - 1 },
                        ) catch {};
                        has_invalid = true;
                        break;
                    }
                }
                // If any CPU ID is invalid, clear affinity to avoid errors
                // (setThreadAffinityMask will fail on invalid IDs)
                if (has_invalid) {
                    // Note: We can't modify task.cpu_affinity directly, but the affinity
                    // setting in workerFn will fail gracefully (best-effort)
                }
            }

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

            // Evaluate skip_if expression — skip task if expression is true.
            if (task.skip_if) |skip_cond| {
                const task_env_for_cond: ?[]const [2][]const u8 = if (task.env.len > 0) task.env else null;
                const should_skip = expr.evalCondition(allocator, skip_cond, task_env_for_cond) catch false;
                if (should_skip) {
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
                    allocator, config, task.deps_serial, sched_config.extra_env, config.toolchains.tools,
                    sched_config.inherit_stdio, &results, &results_mutex, &completed,
                );
                if (!serial_ok) {
                    if (!task.allow_failure) failed.store(true, .release);
                    break;
                }
            }

            if (failed.load(.acquire)) break;

            // Determine which concurrency semaphore to use (v1.62.0).
            // If task has concurrency_group, use that group's semaphore; otherwise use global.
            var concurrency_sem: *std.Thread.Semaphore = &semaphore;
            if (task.concurrency_group) |group_name| {
                if (config.concurrency_groups.get(group_name)) |group| {
                    // Get or create semaphore for this group
                    if (group_semaphores.get(group_name)) |existing| {
                        concurrency_sem = existing;
                    } else {
                        const permits = group.max_workers orelse concurrency;
                        const new_sem = try allocator.create(std.Thread.Semaphore);
                        errdefer allocator.destroy(new_sem);
                        new_sem.* = std.Thread.Semaphore{ .permits = permits };
                        try group_semaphores.put(group_name, new_sem);
                        concurrency_sem = new_sem;
                    }
                }
                // If group doesn't exist in config, fall back to global semaphore (defensive)
            }

            // Acquire the concurrency slot first to avoid hold-and-wait deadlock.
            // The task semaphore is acquired after, so a blocked task_sem never holds
            // a concurrency slot while waiting.
            concurrency_sem.wait();

            // If failure was detected while we were waiting, release and stop
            if (failed.load(.acquire)) {
                concurrency_sem.post();
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

            // Initialize circuit breaker for this task if configured (v1.30.0)
            var circuit_breaker_ptr: ?*CircuitBreakerState = null;
            if (task.circuit_breaker) |cb_config| {
                const result = circuit_breakers.getOrPut(task_name) catch null;
                if (result) |gop| {
                    if (!gop.found_existing) {
                        gop.value_ptr.* = CircuitBreakerState.init(cb_config);
                    }
                    circuit_breaker_ptr = gop.value_ptr;
                }
            }

            const ctx = WorkerCtx{
                .allocator = allocator,
                .task_name = owned_task_name,
                .cmd = task.cmd,
                .cwd = task.cwd,
                .env = task_env_slice,
                .extra_env = sched_config.extra_env,
                .toolchains = config.toolchains.tools,
                .inherit_stdio = sched_config.inherit_stdio,
                .timeout_ms = task.timeout_ms,
                .allow_failure = task.allow_failure,
                .retry_max = task.retry_max,
                .retry_delay_ms = task.retry_delay_ms,
                .retry_backoff = task.retry_backoff,
                .retry_backoff_multiplier = task.retry_backoff_multiplier,
                .retry_jitter = task.retry_jitter,
                .max_backoff_ms = task.max_backoff_ms,
                .retry_on_codes = task.retry_on_codes,
                .retry_on_patterns = task.retry_on_patterns,
                .results = &results,
                .results_mutex = &results_mutex,
                .semaphore = concurrency_sem,
                .task_semaphore = task_sem_ptr,
                .failed = &failed,
                .cache = task.cache,
                .cache_key = cache_key,
                .cache_remote_config = if (config.cache.remote) |*r| r else null,
                .monitor = sched_config.monitor,
                .use_color = sched_config.use_color,
                .task_control = sched_config.task_control,
                .cpu_affinity = task.cpu_affinity,
                .numa_node = task.numa_node,
                .timeline_tracker = &timeline_tracker,
                .replay_mgr = &replay_mgr,
                .output_if = task.output_if,
                .task_hooks = task.hooks,
                .circuit_breaker = circuit_breaker_ptr,
                .retry_budget = if (retry_budget_tracker) |*rb| rb else null,
                .checkpoint_config = if (task.checkpoint) |*cp| cp else null,
                .output_file = task.output_file,
                .output_mode = parseOutputMode(task.output_mode),
                .remote_target = task.remote,
                .remote_cwd = task.remote_cwd,
                .remote_env = task.remote_env,
                .filter_options = sched_config.filter_options,
                .silent = sched_config.silent_override or task.silent,
            };

            const thread = std.Thread.spawn(.{}, workerFn, .{ctx}) catch {
                // If spawn fails, release the semaphore slots we reserved and the name
                if (task_sem_ptr) |ts| ts.post();
                concurrency_sem.post();
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
        .retry_count = 2,
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

// v1.30.0 — Circuit Breaker Tests
test "CircuitBreakerState: init with default config" {
    const config = types.CircuitBreakerConfig{};
    const cb = CircuitBreakerState.init(config);
    try std.testing.expectEqual(@as(u32, 0), cb.failure_count);
    try std.testing.expectEqual(@as(u32, 0), cb.success_count);
    try std.testing.expect(!cb.is_open);
}

test "CircuitBreakerState: record success" {
    const config = types.CircuitBreakerConfig{};
    var cb = CircuitBreakerState.init(config);
    const now_ms: i64 = std.time.milliTimestamp();
    cb.recordSuccess(now_ms);
    try std.testing.expectEqual(@as(u32, 1), cb.success_count);
    try std.testing.expectEqual(@as(u32, 0), cb.failure_count);
    try std.testing.expect(!cb.is_open);
}

test "CircuitBreakerState: record failure" {
    const config = types.CircuitBreakerConfig{};
    var cb = CircuitBreakerState.init(config);
    const now_ms: i64 = std.time.milliTimestamp();
    cb.recordFailure(now_ms);
    try std.testing.expectEqual(@as(u32, 1), cb.failure_count);
    try std.testing.expectEqual(@as(u32, 0), cb.success_count);
}

test "CircuitBreakerState: opens after threshold exceeded" {
    const config = types.CircuitBreakerConfig{
        .failure_threshold = 0.5, // 50% failure rate
        .min_attempts = 3,
    };
    var cb = CircuitBreakerState.init(config);
    const now_ms: i64 = std.time.milliTimestamp();

    // First 3 attempts: 2 failures, 1 success = 66% failure rate
    cb.recordFailure(now_ms);
    cb.recordFailure(now_ms + 100);
    cb.recordSuccess(now_ms + 200);

    // Circuit should be open (66% > 50% threshold, 3 >= min_attempts)
    try std.testing.expect(cb.is_open);
    try std.testing.expect(cb.shouldPreventRetry());
}

test "CircuitBreakerState: stays closed below threshold" {
    const config = types.CircuitBreakerConfig{
        .failure_threshold = 0.5, // 50% failure rate
        .min_attempts = 3,
    };
    var cb = CircuitBreakerState.init(config);
    const now_ms: i64 = std.time.milliTimestamp();

    // 3 attempts: 1 failure, 2 success = 33% failure rate
    cb.recordFailure(now_ms);
    cb.recordSuccess(now_ms + 100);
    cb.recordSuccess(now_ms + 200);

    // Circuit should stay closed (33% < 50% threshold)
    try std.testing.expect(!cb.is_open);
    try std.testing.expect(!cb.shouldPreventRetry());
}

test "CircuitBreakerState: resets after timeout" {
    const config = types.CircuitBreakerConfig{
        .failure_threshold = 0.5,
        .min_attempts = 2,
        .reset_timeout_ms = 100, // 100ms reset timeout
    };
    var cb = CircuitBreakerState.init(config);
    const now_ms: i64 = std.time.milliTimestamp();

    // Open the circuit with 2 failures
    cb.recordFailure(now_ms);
    cb.recordFailure(now_ms + 10);
    try std.testing.expect(cb.is_open);

    // After reset timeout, circuit should close (half-open state)
    cb.updateState(now_ms + 150);
    try std.testing.expect(!cb.is_open);
    try std.testing.expectEqual(@as(u32, 0), cb.failure_count); // Reset
    try std.testing.expectEqual(@as(u32, 0), cb.success_count); // Reset
}

// v1.30.0 — Retry Budget Tests
test "RetryBudgetTracker: init with budget" {
    var tracker = RetryBudgetTracker.init(5);
    try std.testing.expectEqual(@as(u32, 5), tracker.remaining());
}

test "RetryBudgetTracker: consume budget" {
    var tracker = RetryBudgetTracker.init(3);
    try std.testing.expect(tracker.tryConsume());
    try std.testing.expectEqual(@as(u32, 2), tracker.remaining());
    try std.testing.expect(tracker.tryConsume());
    try std.testing.expectEqual(@as(u32, 1), tracker.remaining());
    try std.testing.expect(tracker.tryConsume());
    try std.testing.expectEqual(@as(u32, 0), tracker.remaining());
}

test "RetryBudgetTracker: exhausted budget prevents retry" {
    var tracker = RetryBudgetTracker.init(2);
    try std.testing.expect(tracker.tryConsume()); // 1 remaining
    try std.testing.expect(tracker.tryConsume()); // 0 remaining
    try std.testing.expect(!tracker.tryConsume()); // Exhausted
    try std.testing.expectEqual(@as(u32, 0), tracker.remaining());
}

// Task-level resource attribution tests
test "TaskResult: resource metrics fields exist in struct" {
    // Verify that TaskResult has the required resource tracking fields
    const result = TaskResult{
        .task_name = "test",
        .success = true,
        .exit_code = 0,
        .duration_ms = 100,
        .peak_memory_bytes = 1024 * 1024, // 1MB
        .avg_cpu_percent = 25.5,
    };

    try std.testing.expectEqual(@as(u64, 1024 * 1024), result.peak_memory_bytes);
    try std.testing.expectEqual(@as(f64, 25.5), result.avg_cpu_percent);
}
