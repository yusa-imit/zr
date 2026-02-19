const std = @import("std");
const plugin_loader = @import("../plugin/loader.zig");
pub const PluginConfig = plugin_loader.PluginConfig;
pub const PluginSourceKind = plugin_loader.SourceKind;

/// Workspace (monorepo) configuration from [workspace] section.
pub const Workspace = struct {
    /// Glob patterns for member directories (e.g. "packages/*", "apps/*").
    members: [][]const u8,
    /// Patterns to ignore when discovering members.
    ignore: [][]const u8,

    pub fn deinit(self: *Workspace, allocator: std.mem.Allocator) void {
        for (self.members) |m| allocator.free(m);
        allocator.free(self.members);
        for (self.ignore) |ig| allocator.free(ig);
        allocator.free(self.ignore);
    }
};

pub const Config = struct {
    tasks: std.StringHashMap(Task),
    workflows: std.StringHashMap(Workflow),
    profiles: std.StringHashMap(Profile),
    /// Workspace config from [workspace] section, or null if not present.
    workspace: ?Workspace = null,
    /// Plugin configs from [plugins.NAME] sections (owned).
    plugins: []PluginConfig = &.{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .tasks = std.StringHashMap(Task).init(allocator),
            .workflows = std.StringHashMap(Workflow).init(allocator),
            .profiles = std.StringHashMap(Profile).init(allocator),
            .workspace = null,
            .plugins = &.{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        var it = self.tasks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.tasks.deinit();
        var wit = self.workflows.iterator();
        while (wit.next()) |entry| {
            // Workflow.deinit frees entry.value_ptr.name, which is the same
            // allocation as entry.key_ptr.* — do NOT free the key separately.
            entry.value_ptr.deinit(self.allocator);
        }
        self.workflows.deinit();
        var pit = self.profiles.iterator();
        while (pit.next()) |entry| {
            // Profile.deinit frees entry.value_ptr.name (same allocation as key)
            entry.value_ptr.deinit(self.allocator);
        }
        self.profiles.deinit();
        if (self.workspace) |*ws| ws.deinit(self.allocator);
        for (self.plugins) |*p| {
            var pc = p.*;
            pc.deinit(self.allocator);
        }
        if (self.plugins.len > 0) self.allocator.free(self.plugins);
    }

    /// Apply a named profile to this config. Merges profile env vars into all tasks
    /// and applies any task-level overrides (cmd, cwd, env additions).
    /// Returns error.ProfileNotFound if the profile doesn't exist.
    pub fn applyProfile(self: *Config, profile_name: []const u8) !void {
        const profile = self.profiles.get(profile_name) orelse return error.ProfileNotFound;

        var task_it = self.tasks.iterator();
        while (task_it.next()) |entry| {
            const task = entry.value_ptr;

            // Build merged env: existing task env + profile global env (profile wins)
            // First find if there's a task-level override in the profile
            const task_override: ?ProfileTaskOverride = if (profile.task_overrides.get(task.name)) |ov| ov else null;

            // Count extra env entries: profile global + task-override env
            const extra_global = profile.env.len;
            const extra_task = if (task_override) |ov| ov.env.len else 0;
            const total_env = task.env.len + extra_global + extra_task;

            if (total_env > task.env.len) {
                // Allocate new env slice
                const new_env = try self.allocator.alloc([2][]const u8, total_env);
                var env_duped: usize = 0;
                errdefer {
                    for (new_env[0..env_duped]) |pair| {
                        self.allocator.free(pair[0]);
                        self.allocator.free(pair[1]);
                    }
                    self.allocator.free(new_env);
                }

                // Copy existing task env
                for (task.env, 0..) |pair, i| {
                    new_env[i][0] = try self.allocator.dupe(u8, pair[0]);
                    errdefer self.allocator.free(new_env[i][0]);
                    new_env[i][1] = try self.allocator.dupe(u8, pair[1]);
                    env_duped += 1;
                }

                // Append profile global env
                for (profile.env, 0..) |pair, i| {
                    const idx = task.env.len + i;
                    new_env[idx][0] = try self.allocator.dupe(u8, pair[0]);
                    errdefer self.allocator.free(new_env[idx][0]);
                    new_env[idx][1] = try self.allocator.dupe(u8, pair[1]);
                    env_duped += 1;
                }

                // Append profile task-level env overrides
                if (task_override) |ov| {
                    for (ov.env, 0..) |pair, i| {
                        const idx = task.env.len + extra_global + i;
                        new_env[idx][0] = try self.allocator.dupe(u8, pair[0]);
                        errdefer self.allocator.free(new_env[idx][0]);
                        new_env[idx][1] = try self.allocator.dupe(u8, pair[1]);
                        env_duped += 1;
                    }
                }

                // Free old env and replace
                for (task.env) |pair| {
                    self.allocator.free(pair[0]);
                    self.allocator.free(pair[1]);
                }
                self.allocator.free(task.env);
                task.env = new_env;
            }

            // Apply task-level cmd/cwd overrides
            if (task_override) |ov| {
                if (ov.cmd) |new_cmd| {
                    self.allocator.free(task.cmd);
                    task.cmd = try self.allocator.dupe(u8, new_cmd);
                }
                if (ov.cwd) |new_cwd| {
                    if (task.cwd) |old_cwd| self.allocator.free(old_cwd);
                    task.cwd = try self.allocator.dupe(u8, new_cwd);
                }
            }
        }
    }

    /// Add a task directly (useful for tests and programmatic construction).
    pub fn addTask(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, null, 0, false);
    }

    /// Add a task with all fields (for tests or programmatic use with full options).
    pub fn addTaskFull(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        timeout_ms: ?u64,
        allow_failure: bool,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, timeout_ms, allow_failure, 0, 0, false, null, 0, false);
    }

    /// Add a task with deps_serial (for tests or programmatic use).
    pub fn addTaskWithSerial(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        deps_serial: []const []const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, deps_serial, &[_][2][]const u8{}, null, false, 0, 0, false, null, 0, false);
    }

    /// Add a task with env pairs (for tests or programmatic use with env overrides).
    pub fn addTaskWithEnv(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        env: []const [2][]const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, env, null, false, 0, 0, false, null, 0, false);
    }

    /// Add a task with retry settings (for tests or programmatic use).
    pub fn addTaskWithRetry(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        retry_max: u32,
        retry_delay_ms: u64,
        retry_backoff: bool,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, null, false, retry_max, retry_delay_ms, retry_backoff, null, 0, false);
    }

    /// Add a task with a condition expression (for tests or programmatic use).
    pub fn addTaskWithCondition(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        condition: ?[]const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, condition, 0, false);
    }

    /// Add a workflow (for tests or programmatic use).
    pub fn addWorkflow(
        self: *Config,
        name: []const u8,
        description: ?[]const u8,
        stages: []const Stage,
    ) !void {
        const wf_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(wf_name);

        const wf_desc = if (description) |d| try self.allocator.dupe(u8, d) else null;
        errdefer if (wf_desc) |d| self.allocator.free(d);

        const wf_stages = try self.allocator.alloc(Stage, stages.len);
        var stages_duped: usize = 0;
        errdefer {
            for (wf_stages[0..stages_duped]) |*s| s.deinit(self.allocator);
            self.allocator.free(wf_stages);
        }
        for (stages, 0..) |stage, i| {
            const s_name = try self.allocator.dupe(u8, stage.name);
            errdefer self.allocator.free(s_name);

            const s_tasks = try self.allocator.alloc([]const u8, stage.tasks.len);
            var tasks_duped: usize = 0;
            errdefer {
                for (s_tasks[0..tasks_duped]) |t| self.allocator.free(t);
                self.allocator.free(s_tasks);
            }
            for (stage.tasks, 0..) |t, j| {
                s_tasks[j] = try self.allocator.dupe(u8, t);
                tasks_duped += 1;
            }

            const s_cond = if (stage.condition) |c| try self.allocator.dupe(u8, c) else null;
            errdefer if (s_cond) |c| self.allocator.free(c);

            wf_stages[i] = Stage{
                .name = s_name,
                .tasks = s_tasks,
                .parallel = stage.parallel,
                .fail_fast = stage.fail_fast,
                .condition = s_cond,
            };
            stages_duped += 1;
        }

        const wf = Workflow{
            .name = wf_name,
            .description = wf_desc,
            .stages = wf_stages,
        };

        try self.workflows.put(wf_name, wf);
    }
};

pub const Task = struct {
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: [][]const u8,
    /// Sequential dependencies: run in array order before this task, one at a time.
    deps_serial: [][]const u8,
    /// Environment variable overrides. Each entry is [key, value] (owned, duped).
    env: [][2][]const u8,
    /// Timeout in milliseconds. null means no timeout.
    timeout_ms: ?u64 = null,
    /// If true, a non-zero exit code is treated as success for dependency purposes.
    allow_failure: bool = false,
    /// Maximum number of retry attempts after the first failure (0 = no retry).
    retry_max: u32 = 0,
    /// Delay between retry attempts in milliseconds.
    retry_delay_ms: u64 = 0,
    /// If true, delay doubles on each retry attempt (exponential backoff).
    retry_backoff: bool = false,
    /// Optional condition expression. If null, task always runs.
    /// If set, evaluated before the task runs; task is skipped if false.
    condition: ?[]const u8 = null,
    /// Maximum number of concurrent instances of this task (0 = unlimited).
    max_concurrent: u32 = 0,
    /// If true, cache successful runs and skip on subsequent runs with same cmd+env.
    cache: bool = false,

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.cmd);
        if (self.cwd) |cwd| allocator.free(cwd);
        if (self.description) |desc| allocator.free(desc);
        for (self.deps) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.deps);
        for (self.deps_serial) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.deps_serial);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.env);
        if (self.condition) |c| allocator.free(c);
    }
};

pub const Stage = struct {
    name: []const u8,
    tasks: [][]const u8,
    parallel: bool = true,
    fail_fast: bool = false,
    condition: ?[]const u8 = null,

    pub fn deinit(self: *Stage, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.tasks) |t| allocator.free(t);
        allocator.free(self.tasks);
        if (self.condition) |c| allocator.free(c);
    }
};

pub const Workflow = struct {
    name: []const u8,
    description: ?[]const u8,
    stages: []Stage,

    pub fn deinit(self: *Workflow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |d| allocator.free(d);
        for (self.stages) |*stage| stage.deinit(allocator);
        allocator.free(self.stages);
    }
};

/// Per-task overrides within a profile.
pub const ProfileTaskOverride = struct {
    /// Optional command override (replaces task cmd).
    cmd: ?[]const u8 = null,
    /// Optional working directory override.
    cwd: ?[]const u8 = null,
    /// Additional env vars merged into task env (profile wins over task defaults).
    env: [][2][]const u8,

    pub fn deinit(self: *ProfileTaskOverride, allocator: std.mem.Allocator) void {
        if (self.cmd) |c| allocator.free(c);
        if (self.cwd) |c| allocator.free(c);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.env);
    }
};

/// A named profile that overrides config at runtime.
pub const Profile = struct {
    name: []const u8,
    /// Global env vars added to all tasks when this profile is active.
    env: [][2][]const u8,
    /// Per-task overrides keyed by task name.
    task_overrides: std.StringHashMap(ProfileTaskOverride),

    pub fn deinit(self: *Profile, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.env);
        var it = self.task_overrides.iterator();
        while (it.next()) |entry| {
            // key is same allocation as ProfileTaskOverride name stored inside
            // the map; we manage keys separately.
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.task_overrides.deinit();
    }
};

/// One dimension of a matrix definition: a named variable and its possible values.
pub const MatrixDim = struct {
    key: []const u8,
    values: [][]const u8,

    pub fn deinit(self: *MatrixDim, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        for (self.values) |v| allocator.free(v);
        allocator.free(self.values);
    }
};

/// Parse a duration string like "5m", "30s", "1h", "500ms" into milliseconds.
/// Returns null if the format is unrecognized.
pub fn parseDurationMs(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    if (std.mem.endsWith(u8, s, "ms")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 2], 10) catch return null;
        return n;
    } else if (std.mem.endsWith(u8, s, "h")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 3_600_000;
    } else if (std.mem.endsWith(u8, s, "m")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 60_000;
    } else if (std.mem.endsWith(u8, s, "s")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 1_000;
    }
    return null;
}

pub fn addTaskImpl(
    config: *Config,
    allocator: std.mem.Allocator,
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: []const []const u8,
    deps_serial: []const []const u8,
    env: []const [2][]const u8,
    timeout_ms: ?u64,
    allow_failure: bool,
    retry_max: u32,
    retry_delay_ms: u64,
    retry_backoff: bool,
    condition: ?[]const u8,
    max_concurrent: u32,
    cache: bool,
) !void {
    const task_name = try allocator.dupe(u8, name);
    errdefer allocator.free(task_name);

    const task_cmd = try allocator.dupe(u8, cmd);
    errdefer allocator.free(task_cmd);

    const task_cwd = if (cwd) |c| try allocator.dupe(u8, c) else null;
    errdefer if (task_cwd) |c| allocator.free(c);

    const task_desc = if (description) |d| try allocator.dupe(u8, d) else null;
    errdefer if (task_desc) |d| allocator.free(d);

    const task_deps = try allocator.alloc([]const u8, deps.len);
    var deps_duped: usize = 0;
    errdefer {
        for (task_deps[0..deps_duped]) |d| allocator.free(d);
        allocator.free(task_deps);
    }
    for (deps, 0..) |dep, i| {
        task_deps[i] = try allocator.dupe(u8, dep);
        deps_duped += 1;
    }

    const task_deps_serial = try allocator.alloc([]const u8, deps_serial.len);
    var serial_duped: usize = 0;
    errdefer {
        for (task_deps_serial[0..serial_duped]) |d| allocator.free(d);
        allocator.free(task_deps_serial);
    }
    for (deps_serial, 0..) |dep, i| {
        task_deps_serial[i] = try allocator.dupe(u8, dep);
        serial_duped += 1;
    }

    // Dupe each env pair ([key, value]) independently for safe partial cleanup.
    const task_env = try allocator.alloc([2][]const u8, env.len);
    var env_duped: usize = 0;
    errdefer {
        for (task_env[0..env_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(task_env);
    }
    for (env, 0..) |pair, i| {
        task_env[i][0] = try allocator.dupe(u8, pair[0]);
        // If key dupe succeeds but value dupe fails, free the key we just duped.
        errdefer allocator.free(task_env[i][0]);
        task_env[i][1] = try allocator.dupe(u8, pair[1]);
        env_duped += 1;
    }

    const task_condition = if (condition) |c| try allocator.dupe(u8, c) else null;
    errdefer if (task_condition) |c| allocator.free(c);

    const task = Task{
        .name = task_name,
        .cmd = task_cmd,
        .cwd = task_cwd,
        .description = task_desc,
        .deps = task_deps,
        .deps_serial = task_deps_serial,
        .env = task_env,
        .timeout_ms = timeout_ms,
        .allow_failure = allow_failure,
        .retry_max = retry_max,
        .retry_delay_ms = retry_delay_ms,
        .retry_backoff = retry_backoff,
        .condition = task_condition,
        .max_concurrent = max_concurrent,
        .cache = cache,
    };

    try config.tasks.put(task_name, task);
}
