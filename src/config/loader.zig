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

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        return try parseToml(allocator, content);
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

fn parseToml(allocator: std.mem.Allocator, content: []const u8) !Config {
    var config = Config.init(allocator);
    errdefer config.deinit();

    var lines = std.mem.splitScalar(u8, content, '\n');

    // These are non-owning slices into `content` — addTask dupes them
    var current_task: ?[]const u8 = null;
    var task_cmd: ?[]const u8 = null;
    var task_cwd: ?[]const u8 = null;
    var task_desc: ?[]const u8 = null;
    var task_timeout_ms: ?u64 = null;
    var task_allow_failure: bool = false;
    var task_retry_max: u32 = 0;
    var task_retry_delay_ms: u64 = 0;
    var task_retry_backoff: bool = false;
    var task_condition: ?[]const u8 = null;
    var task_max_concurrent: u32 = 0;
    var task_cache: bool = false;
    // Matrix raw inline table string (non-owning slice into content)
    var task_matrix_raw: ?[]const u8 = null;

    // Non-owning slices into content — addTask dupes them
    var task_deps = std.ArrayList([]const u8){};
    defer task_deps.deinit(allocator);
    var task_deps_serial = std.ArrayList([]const u8){};
    defer task_deps_serial.deinit(allocator);
    // Non-owning slices into content for env pairs — addTask dupes them
    var task_env = std.ArrayList([2][]const u8){};
    defer task_env.deinit(allocator);

    // Workflow parsing state — non-owning slices into content
    var current_workflow: ?[]const u8 = null;
    var workflow_desc: ?[]const u8 = null;
    // Stages accumulate here; each Stage is owned (duped) when built
    var workflow_stages = std.ArrayList(Stage){};
    defer {
        for (workflow_stages.items) |*s| s.deinit(allocator);
        workflow_stages.deinit(allocator);
    }

    // Stage parsing state (pending stage being built)
    // stage_name is a non-owning slice into content
    var stage_name: ?[]const u8 = null;
    // stage_tasks items are non-owning slices into content
    var stage_tasks = std.ArrayList([]const u8){};
    defer stage_tasks.deinit(allocator);
    var stage_parallel: bool = true;
    var stage_fail_fast: bool = false;
    var stage_condition: ?[]const u8 = null;

    // Profile parsing state
    // current_profile: non-owning slice into content (profile name)
    var current_profile: ?[]const u8 = null;
    // profile_env: accumulated non-owning env pairs for the current profile's global env
    var profile_env = std.ArrayList([2][]const u8){};
    defer profile_env.deinit(allocator);
    // current_profile_task: if inside [profiles.X.tasks.Y], this is Y (non-owning)
    var current_profile_task: ?[]const u8 = null;
    // profile_task_env: env pairs for current profile task override (non-owning)
    var profile_task_env = std.ArrayList([2][]const u8){};
    defer profile_task_env.deinit(allocator);
    // profile_task_cmd / profile_task_cwd: non-owning slices into content
    var profile_task_cmd: ?[]const u8 = null;
    var profile_task_cwd: ?[]const u8 = null;
    // Per-profile accumulated task overrides (owned, flushed into Profile on profile end)
    var profile_task_overrides = std.StringHashMap(ProfileTaskOverride).init(allocator);
    defer {
        var pit2 = profile_task_overrides.iterator();
        while (pit2.next()) |e| {
            allocator.free(e.key_ptr.*);
            e.value_ptr.deinit(allocator);
        }
        profile_task_overrides.deinit();
    }

    // Workspace parsing state
    var in_workspace: bool = false;
    // Accumulated non-owning slices for workspace fields; flushed at end
    var ws_members = std.ArrayList([]const u8){};
    defer ws_members.deinit(allocator);
    var ws_ignore = std.ArrayList([]const u8){};
    defer ws_ignore.deinit(allocator);

    // Plugin parsing state
    // current_plugin_name: non-owning slice into content (plugin key under [plugins.*])
    var current_plugin_name: ?[]const u8 = null;
    // plugin_source: non-owning slice into content
    var plugin_source: ?[]const u8 = null;
    var plugin_kind: PluginSourceKind = .local;
    // Accumulated config pairs for the current plugin (non-owning slices into content)
    var plugin_cfg_pairs = std.ArrayList([2][]const u8){};
    defer plugin_cfg_pairs.deinit(allocator);
    // Collected PluginConfig list (owned) — transferred to config.plugins at end
    var plugin_list = std.ArrayList(PluginConfig){};
    defer {
        for (plugin_list.items) |*pc| pc.deinit(allocator);
        plugin_list.deinit(allocator);
    }

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "[[workflows.") and std.mem.endsWith(u8, trimmed, ".stages]]")) {
            in_workspace = false;
            // Flush pending stage into workflow_stages
            if (stage_name) |sn| {
                const s_tasks = try allocator.alloc([]const u8, stage_tasks.items.len);
                var tduped: usize = 0;
                errdefer {
                    for (s_tasks[0..tduped]) |t| allocator.free(t);
                    allocator.free(s_tasks);
                }
                for (stage_tasks.items, 0..) |t, i| {
                    s_tasks[i] = try allocator.dupe(u8, t);
                    tduped += 1;
                }
                const s_cond = if (stage_condition) |c| try allocator.dupe(u8, c) else null;
                errdefer if (s_cond) |c| allocator.free(c);
                const new_stage = Stage{
                    .name = try allocator.dupe(u8, sn),
                    .tasks = s_tasks,
                    .parallel = stage_parallel,
                    .fail_fast = stage_fail_fast,
                    .condition = s_cond,
                };
                try workflow_stages.append(allocator, new_stage);
            }
            // Reset stage state
            stage_name = null;
            stage_tasks.clearRetainingCapacity();
            stage_parallel = true;
            stage_fail_fast = false;
            stage_condition = null;
        } else if (std.mem.startsWith(u8, trimmed, "[workflows.") and !std.mem.startsWith(u8, trimmed, "[[")) {
            in_workspace = false;
            // Flush pending stage (if any)
            if (stage_name) |sn| {
                const s_tasks = try allocator.alloc([]const u8, stage_tasks.items.len);
                var tduped: usize = 0;
                errdefer {
                    for (s_tasks[0..tduped]) |t| allocator.free(t);
                    allocator.free(s_tasks);
                }
                for (stage_tasks.items, 0..) |t, i| {
                    s_tasks[i] = try allocator.dupe(u8, t);
                    tduped += 1;
                }
                const s_cond = if (stage_condition) |c| try allocator.dupe(u8, c) else null;
                errdefer if (s_cond) |c| allocator.free(c);
                const new_stage = Stage{
                    .name = try allocator.dupe(u8, sn),
                    .tasks = s_tasks,
                    .parallel = stage_parallel,
                    .fail_fast = stage_fail_fast,
                    .condition = s_cond,
                };
                try workflow_stages.append(allocator, new_stage);
                stage_name = null;
                stage_tasks.clearRetainingCapacity();
                stage_parallel = true;
                stage_fail_fast = false;
                stage_condition = null;
            }
            // Flush pending workflow (if any)
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity();
            }
            // Flush pending task (if any — tasks may precede workflow sections)
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    if (task_matrix_raw) |mraw| {
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache);
                    }
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_cmd = null;
                task_cwd = null;
                task_desc = null;
                task_timeout_ms = null;
                task_allow_failure = false;
                task_retry_max = 0;
                task_retry_delay_ms = 0;
                task_retry_backoff = false;
                task_condition = null;
                task_max_concurrent = 0;
                task_cache = false;
                task_matrix_raw = null;
                current_task = null;
            }
            // Parse new workflow name from "[workflows.X]"
            const wf_start = "[workflows.".len;
            const wf_end = std.mem.indexOf(u8, trimmed[wf_start..], "]") orelse continue;
            current_workflow = trimmed[wf_start..][0..wf_end];
            workflow_desc = null;
        } else if (std.mem.startsWith(u8, trimmed, "[profiles.") and std.mem.indexOf(u8, trimmed, ".tasks.") != null) {
            in_workspace = false;
            // Section: [profiles.X.tasks.Y] — per-task override within profile X
            // Flush pending profile task override (if any)
            if (current_profile_task) |ptask| {
                const pto_env = try allocator.alloc([2][]const u8, profile_task_env.items.len);
                var ptenv_duped: usize = 0;
                errdefer {
                    for (pto_env[0..ptenv_duped]) |pair| {
                        allocator.free(pair[0]);
                        allocator.free(pair[1]);
                    }
                    allocator.free(pto_env);
                }
                for (profile_task_env.items, 0..) |pair, i| {
                    pto_env[i][0] = try allocator.dupe(u8, pair[0]);
                    errdefer allocator.free(pto_env[i][0]);
                    pto_env[i][1] = try allocator.dupe(u8, pair[1]);
                    ptenv_duped += 1;
                }
                const pto = ProfileTaskOverride{
                    .cmd = if (profile_task_cmd) |c| try allocator.dupe(u8, c) else null,
                    .cwd = if (profile_task_cwd) |c| try allocator.dupe(u8, c) else null,
                    .env = pto_env,
                };
                const pto_key = try allocator.dupe(u8, ptask);
                errdefer allocator.free(pto_key);
                try profile_task_overrides.put(pto_key, pto);
            }
            profile_task_env.clearRetainingCapacity();
            profile_task_cmd = null;
            profile_task_cwd = null;

            // Parse task name: "[profiles.X.tasks.Y]" → Y
            const tasks_marker = ".tasks.";
            const tm_idx = std.mem.indexOf(u8, trimmed, tasks_marker) orelse continue;
            const after_tasks = trimmed[tm_idx + tasks_marker.len ..];
            const rbracket = std.mem.indexOf(u8, after_tasks, "]") orelse continue;
            current_profile_task = after_tasks[0..rbracket];
            // Entering a profile task context; clear task context
            current_task = null;
            current_workflow = null;
        } else if (std.mem.startsWith(u8, trimmed, "[profiles.") and !std.mem.startsWith(u8, trimmed, "[[")) {
            in_workspace = false;
            // Section: [profiles.X] — new profile header
            // Flush pending profile task override (if any)
            if (current_profile_task) |ptask| {
                const pto_env = try allocator.alloc([2][]const u8, profile_task_env.items.len);
                var ptenv_duped: usize = 0;
                errdefer {
                    for (pto_env[0..ptenv_duped]) |pair| {
                        allocator.free(pair[0]);
                        allocator.free(pair[1]);
                    }
                    allocator.free(pto_env);
                }
                for (profile_task_env.items, 0..) |pair, i| {
                    pto_env[i][0] = try allocator.dupe(u8, pair[0]);
                    errdefer allocator.free(pto_env[i][0]);
                    pto_env[i][1] = try allocator.dupe(u8, pair[1]);
                    ptenv_duped += 1;
                }
                const pto = ProfileTaskOverride{
                    .cmd = if (profile_task_cmd) |c| try allocator.dupe(u8, c) else null,
                    .cwd = if (profile_task_cwd) |c| try allocator.dupe(u8, c) else null,
                    .env = pto_env,
                };
                const pto_key = try allocator.dupe(u8, ptask);
                errdefer allocator.free(pto_key);
                try profile_task_overrides.put(pto_key, pto);
                current_profile_task = null;
                profile_task_env.clearRetainingCapacity();
                profile_task_cmd = null;
                profile_task_cwd = null;
            }
            // Flush pending profile (if any)
            if (current_profile) |pname| {
                try flushProfile(allocator, &config, pname, &profile_env, &profile_task_overrides);
                profile_env.clearRetainingCapacity();
                // profile_task_overrides already cleared by flushProfile
            }
            // Flush pending task (if any)
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    if (task_matrix_raw) |mraw| {
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache);
                    }
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null;
                task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false;
                task_condition = null; task_max_concurrent = 0; task_cache = false; task_matrix_raw = null; current_task = null;
            }
            // Flush pending workflow (if any)
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity();
                current_workflow = null;
                workflow_desc = null;
            }

            // Parse new profile name: "[profiles.X]" → X
            const pstart = "[profiles.".len;
            const pend = std.mem.indexOf(u8, trimmed[pstart..], "]") orelse continue;
            current_profile = trimmed[pstart..][0..pend];
        } else if (std.mem.eql(u8, trimmed, "[workspace]")) {
            // Flush pending task/workflow/profile contexts
            if (stage_name) |sn| {
                const s_tasks = try allocator.alloc([]const u8, stage_tasks.items.len);
                var tduped: usize = 0;
                errdefer { for (s_tasks[0..tduped]) |t| allocator.free(t); allocator.free(s_tasks); }
                for (stage_tasks.items, 0..) |t, i| { s_tasks[i] = try allocator.dupe(u8, t); tduped += 1; }
                const s_cond = if (stage_condition) |c| try allocator.dupe(u8, c) else null;
                errdefer if (s_cond) |c| allocator.free(c);
                try workflow_stages.append(allocator, Stage{ .name = try allocator.dupe(u8, sn), .tasks = s_tasks, .parallel = stage_parallel, .fail_fast = stage_fail_fast, .condition = s_cond });
                stage_name = null; stage_tasks.clearRetainingCapacity(); stage_parallel = true; stage_fail_fast = false; stage_condition = null;
            }
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity(); current_workflow = null; workflow_desc = null;
            }
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    if (task_matrix_raw) |mraw| {
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false; task_condition = null; task_max_concurrent = 0; task_cache = false; task_matrix_raw = null; current_task = null;
            }
            if (current_profile) |pname| {
                if (current_profile_task) |ptask| {
                    const pto_env = try allocator.alloc([2][]const u8, profile_task_env.items.len);
                    var ptenv_duped: usize = 0;
                    errdefer { for (pto_env[0..ptenv_duped]) |pair| { allocator.free(pair[0]); allocator.free(pair[1]); } allocator.free(pto_env); }
                    for (profile_task_env.items, 0..) |pair, i| { pto_env[i][0] = try allocator.dupe(u8, pair[0]); errdefer allocator.free(pto_env[i][0]); pto_env[i][1] = try allocator.dupe(u8, pair[1]); ptenv_duped += 1; }
                    const pto = ProfileTaskOverride{ .cmd = if (profile_task_cmd) |c| try allocator.dupe(u8, c) else null, .cwd = if (profile_task_cwd) |c| try allocator.dupe(u8, c) else null, .env = pto_env };
                    const pto_key = try allocator.dupe(u8, ptask);
                    errdefer allocator.free(pto_key);
                    try profile_task_overrides.put(pto_key, pto);
                    current_profile_task = null; profile_task_env.clearRetainingCapacity(); profile_task_cmd = null; profile_task_cwd = null;
                }
                try flushProfile(allocator, &config, pname, &profile_env, &profile_task_overrides);
                profile_env.clearRetainingCapacity(); current_profile = null;
            }
            in_workspace = true;
        } else if (std.mem.startsWith(u8, trimmed, "[plugins.") and !std.mem.startsWith(u8, trimmed, "[[")) {
            in_workspace = false;
            // Flush pending task (if any)
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    if (task_matrix_raw) |mraw| {
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false; task_condition = null; task_max_concurrent = 0; task_cache = false; task_matrix_raw = null;
                current_task = null;
            }
            // Flush pending plugin (if any)
            if (current_plugin_name) |pn| {
                if (plugin_source) |src| {
                    const pc_pairs = try allocator.alloc([2][]const u8, plugin_cfg_pairs.items.len);
                    var pc_duped: usize = 0;
                    errdefer {
                        for (pc_pairs[0..pc_duped]) |pair| { allocator.free(pair[0]); allocator.free(pair[1]); }
                        allocator.free(pc_pairs);
                    }
                    for (plugin_cfg_pairs.items, 0..) |pair, i| {
                        pc_pairs[i][0] = try allocator.dupe(u8, pair[0]);
                        errdefer allocator.free(pc_pairs[i][0]);
                        pc_pairs[i][1] = try allocator.dupe(u8, pair[1]);
                        pc_duped += 1;
                    }
                    const pc = PluginConfig{
                        .name = try allocator.dupe(u8, pn),
                        .kind = plugin_kind,
                        .source = try allocator.dupe(u8, src),
                        .config = pc_pairs,
                    };
                    try plugin_list.append(allocator, pc);
                }
                plugin_cfg_pairs.clearRetainingCapacity();
                current_plugin_name = null;
                plugin_source = null;
                plugin_kind = .local;
            }
            // Parse new plugin name: "[plugins.X]" → X
            const plstart = "[plugins.".len;
            const plend = std.mem.indexOf(u8, trimmed[plstart..], "]") orelse continue;
            current_plugin_name = trimmed[plstart..][0..plend];
        } else if (std.mem.startsWith(u8, trimmed, "[tasks.")) {
            // Flush pending stage (if any)
            if (stage_name) |sn| {
                const s_tasks = try allocator.alloc([]const u8, stage_tasks.items.len);
                var tduped: usize = 0;
                errdefer {
                    for (s_tasks[0..tduped]) |t| allocator.free(t);
                    allocator.free(s_tasks);
                }
                for (stage_tasks.items, 0..) |t, i| {
                    s_tasks[i] = try allocator.dupe(u8, t);
                    tduped += 1;
                }
                const s_cond = if (stage_condition) |c| try allocator.dupe(u8, c) else null;
                errdefer if (s_cond) |c| allocator.free(c);
                const new_stage = Stage{
                    .name = try allocator.dupe(u8, sn),
                    .tasks = s_tasks,
                    .parallel = stage_parallel,
                    .fail_fast = stage_fail_fast,
                    .condition = s_cond,
                };
                try workflow_stages.append(allocator, new_stage);
                stage_name = null;
                stage_tasks.clearRetainingCapacity();
                stage_parallel = true;
                stage_fail_fast = false;
                stage_condition = null;
            }
            // Flush pending workflow (if any)
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity();
                current_workflow = null;
                workflow_desc = null;
            }
            // Flush pending profile (if any)
            if (current_profile) |pname| {
                if (current_profile_task) |ptask| {
                    const pto_env = try allocator.alloc([2][]const u8, profile_task_env.items.len);
                    var ptenv_duped: usize = 0;
                    errdefer {
                        for (pto_env[0..ptenv_duped]) |pair| {
                            allocator.free(pair[0]);
                            allocator.free(pair[1]);
                        }
                        allocator.free(pto_env);
                    }
                    for (profile_task_env.items, 0..) |pair, i| {
                        pto_env[i][0] = try allocator.dupe(u8, pair[0]);
                        errdefer allocator.free(pto_env[i][0]);
                        pto_env[i][1] = try allocator.dupe(u8, pair[1]);
                        ptenv_duped += 1;
                    }
                    const pto = ProfileTaskOverride{
                        .cmd = if (profile_task_cmd) |c| try allocator.dupe(u8, c) else null,
                        .cwd = if (profile_task_cwd) |c| try allocator.dupe(u8, c) else null,
                        .env = pto_env,
                    };
                    const pto_key = try allocator.dupe(u8, ptask);
                    errdefer allocator.free(pto_key);
                    try profile_task_overrides.put(pto_key, pto);
                    current_profile_task = null;
                    profile_task_env.clearRetainingCapacity();
                    profile_task_cmd = null;
                    profile_task_cwd = null;
                }
                try flushProfile(allocator, &config, pname, &profile_env, &profile_task_overrides);
                profile_env.clearRetainingCapacity();
                current_profile = null;
            }
            // Flush pending plugin (if any)
            if (current_plugin_name) |pn| {
                if (plugin_source) |src| {
                    const pc_pairs = try allocator.alloc([2][]const u8, plugin_cfg_pairs.items.len);
                    var pc_duped: usize = 0;
                    errdefer {
                        for (pc_pairs[0..pc_duped]) |pair| { allocator.free(pair[0]); allocator.free(pair[1]); }
                        allocator.free(pc_pairs);
                    }
                    for (plugin_cfg_pairs.items, 0..) |pair, i| {
                        pc_pairs[i][0] = try allocator.dupe(u8, pair[0]);
                        errdefer allocator.free(pc_pairs[i][0]);
                        pc_pairs[i][1] = try allocator.dupe(u8, pair[1]);
                        pc_duped += 1;
                    }
                    const pc = PluginConfig{ .name = try allocator.dupe(u8, pn), .kind = plugin_kind, .source = try allocator.dupe(u8, src), .config = pc_pairs };
                    try plugin_list.append(allocator, pc);
                }
                plugin_cfg_pairs.clearRetainingCapacity();
                current_plugin_name = null;
                plugin_source = null;
                plugin_kind = .local;
            }
            // Flush pending task before starting new one
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    if (task_matrix_raw) |mraw| {
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache);
                    }
                }
            }

            // Reset state — no freeing needed since these are non-owning slices
            task_deps.clearRetainingCapacity();
            task_deps_serial.clearRetainingCapacity();
            task_env.clearRetainingCapacity();
            task_cmd = null;
            task_cwd = null;
            task_desc = null;
            task_timeout_ms = null;
            task_allow_failure = false;
            task_retry_max = 0;
            task_retry_delay_ms = 0;
            task_retry_backoff = false;
            task_condition = null;
            task_max_concurrent = 0;
            task_cache = false;
            task_matrix_raw = null;

            in_workspace = false;
            const start = "[tasks.".len;
            const end = std.mem.indexOf(u8, trimmed[start..], "]") orelse continue;
            // Non-owning slice into content
            current_task = trimmed[start..][0..end];
        } else if (std.mem.indexOf(u8, trimmed, "=")) |eq_idx| {
            const key = std.mem.trim(u8, trimmed[0..eq_idx], " \t");
            var value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            if (current_profile_task != null) {
                // Inside [profiles.X.tasks.Y] — parse task override fields
                if (std.mem.eql(u8, key, "cmd")) {
                    profile_task_cmd = value;
                } else if (std.mem.eql(u8, key, "cwd")) {
                    profile_task_cwd = value;
                } else if (std.mem.eql(u8, key, "env")) {
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq2 = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const env_key = std.mem.trim(u8, pair_str[0..eq2], " \t\"");
                            const env_val = std.mem.trim(u8, pair_str[eq2 + 1 ..], " \t\"");
                            if (env_key.len > 0) try profile_task_env.append(allocator, .{ env_key, env_val });
                        }
                    }
                }
            } else if (current_profile != null and current_task == null and current_workflow == null) {
                // Inside [profiles.X] (global profile level) — parse global env
                if (std.mem.eql(u8, key, "env")) {
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq2 = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const env_key = std.mem.trim(u8, pair_str[0..eq2], " \t\"");
                            const env_val = std.mem.trim(u8, pair_str[eq2 + 1 ..], " \t\"");
                            if (env_key.len > 0) try profile_env.append(allocator, .{ env_key, env_val });
                        }
                    }
                }
            } else if (current_workflow != null and current_task == null) {
                // We are inside a workflow or stage context
                if (std.mem.eql(u8, key, "name") and stage_name == null) {
                    // Stage name (first name= after [[workflows.X.stages]])
                    stage_name = value;
                } else if (std.mem.eql(u8, key, "tasks")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        stage_tasks.clearRetainingCapacity();
                        const tasks_str = value[1 .. value.len - 1];
                        var tasks_it = std.mem.splitScalar(u8, tasks_str, ',');
                        while (tasks_it.next()) |t| {
                            const trimmed_t = std.mem.trim(u8, t, " \t\"");
                            if (trimmed_t.len > 0) try stage_tasks.append(allocator, trimmed_t);
                        }
                    }
                } else if (std.mem.eql(u8, key, "parallel")) {
                    stage_parallel = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "fail_fast")) {
                    stage_fail_fast = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "condition") and stage_name != null) {
                    stage_condition = value;
                } else if (std.mem.eql(u8, key, "description") and stage_name == null) {
                    // Workflow-level description (not inside a stage)
                    workflow_desc = value;
                }
            } else if (current_plugin_name != null and current_task == null and current_workflow == null and current_profile == null and !in_workspace) {
                // Inside [plugins.X] — parse source and config fields
                if (std.mem.eql(u8, key, "source")) {
                    // Detect source kind from prefix: "registry:", "git:", else local
                    if (std.mem.startsWith(u8, value, "registry:")) {
                        plugin_kind = .registry;
                        plugin_source = value["registry:".len..];
                    } else if (std.mem.startsWith(u8, value, "git:")) {
                        plugin_kind = .git;
                        plugin_source = value["git:".len..];
                    } else if (std.mem.startsWith(u8, value, "local:")) {
                        plugin_kind = .local;
                        plugin_source = value["local:".len..];
                    } else {
                        plugin_kind = .local;
                        plugin_source = value;
                    }
                } else if (std.mem.eql(u8, key, "config")) {
                    // Inline table: config = { key = "val", ... }
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq2 = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const cfg_key = std.mem.trim(u8, pair_str[0..eq2], " \t\"");
                            const cfg_val = std.mem.trim(u8, pair_str[eq2 + 1 ..], " \t\"");
                            if (cfg_key.len > 0) try plugin_cfg_pairs.append(allocator, .{ cfg_key, cfg_val });
                        }
                    }
                }
            } else if (in_workspace) {
                // Inside [workspace] — parse members and ignore arrays
                if (std.mem.eql(u8, key, "members")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const items_str = value[1 .. value.len - 1];
                        var items_it = std.mem.splitScalar(u8, items_str, ',');
                        while (items_it.next()) |item| {
                            const t = std.mem.trim(u8, item, " \t\"");
                            if (t.len > 0) try ws_members.append(allocator, t);
                        }
                    }
                } else if (std.mem.eql(u8, key, "ignore")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const items_str = value[1 .. value.len - 1];
                        var items_it = std.mem.splitScalar(u8, items_str, ',');
                        while (items_it.next()) |item| {
                            const t = std.mem.trim(u8, item, " \t\"");
                            if (t.len > 0) try ws_ignore.append(allocator, t);
                        }
                    }
                }
            } else if (current_task != null) {
                // Task-level key=value parsing
                if (std.mem.eql(u8, key, "cmd")) {
                    task_cmd = value;
                } else if (std.mem.eql(u8, key, "cwd")) {
                    task_cwd = value;
                } else if (std.mem.eql(u8, key, "description")) {
                    task_desc = value;
                } else if (std.mem.eql(u8, key, "condition")) {
                    task_condition = value;
                } else if (std.mem.eql(u8, key, "timeout")) {
                    task_timeout_ms = parseDurationMs(value);
                } else if (std.mem.eql(u8, key, "allow_failure")) {
                    task_allow_failure = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "deps")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const deps_str = value[1 .. value.len - 1];
                        var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                        while (deps_it.next()) |dep| {
                            const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                            if (trimmed_dep.len > 0) {
                                // Non-owning slice — addTask will dupe
                                try task_deps.append(allocator, trimmed_dep);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "deps_serial")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const deps_str = value[1 .. value.len - 1];
                        var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                        while (deps_it.next()) |dep| {
                            const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                            if (trimmed_dep.len > 0) {
                                // Non-owning slice — addTask will dupe
                                try task_deps_serial.append(allocator, trimmed_dep);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "env")) {
                    // Parse inline table: { KEY = "value", FOO = "bar" }
                    // value has already had outer quotes stripped; strip braces now.
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const env_key = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const env_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (env_key.len > 0) {
                                // Non-owning slices into content — addTask will dupe
                                try task_env.append(allocator, .{ env_key, env_val });
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "retry")) {
                    // Parse inline table: { max = 3, delay = "5s", backoff = "exponential" }
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const rkey = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const rval = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (std.mem.eql(u8, rkey, "max")) {
                                task_retry_max = std.fmt.parseInt(u32, rval, 10) catch 0;
                            } else if (std.mem.eql(u8, rkey, "delay")) {
                                task_retry_delay_ms = parseDurationMs(rval) orelse 0;
                            } else if (std.mem.eql(u8, rkey, "backoff")) {
                                task_retry_backoff = std.mem.eql(u8, rval, "exponential");
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "max_concurrent")) {
                    task_max_concurrent = std.fmt.parseInt(u32, value, 10) catch 0;
                } else if (std.mem.eql(u8, key, "cache")) {
                    task_cache = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "matrix")) {
                    // Store raw inline table for matrix expansion at flush time.
                    // value has already had outer quotes stripped; re-use trimmed rhs.
                    const raw = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");
                    task_matrix_raw = raw;
                }
            }
        }
    }

    // Flush final pending stage
    if (stage_name) |sn| {
        const s_tasks = try allocator.alloc([]const u8, stage_tasks.items.len);
        var tduped: usize = 0;
        errdefer {
            for (s_tasks[0..tduped]) |t| allocator.free(t);
            allocator.free(s_tasks);
        }
        for (stage_tasks.items, 0..) |t, i| {
            s_tasks[i] = try allocator.dupe(u8, t);
            tduped += 1;
        }
        const s_cond = if (stage_condition) |c| try allocator.dupe(u8, c) else null;
        errdefer if (s_cond) |c| allocator.free(c);
        const new_stage = Stage{
            .name = try allocator.dupe(u8, sn),
            .tasks = s_tasks,
            .parallel = stage_parallel,
            .fail_fast = stage_fail_fast,
            .condition = s_cond,
        };
        try workflow_stages.append(allocator, new_stage);
    }

    // Flush final pending workflow
    if (current_workflow) |wf_name_slice| {
        try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items);
        for (workflow_stages.items) |*s| s.deinit(allocator);
        workflow_stages.clearRetainingCapacity();
    }

    // Flush final pending task
    if (current_task) |task_name| {
        if (task_cmd) |cmd| {
            if (task_matrix_raw) |mraw| {
                try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, mraw);
            } else {
                try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache);
            }
        }
    }

    // Flush final pending profile task override
    if (current_profile_task) |ptask| {
        const pto_env = try allocator.alloc([2][]const u8, profile_task_env.items.len);
        var ptenv_duped: usize = 0;
        errdefer {
            for (pto_env[0..ptenv_duped]) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            allocator.free(pto_env);
        }
        for (profile_task_env.items, 0..) |pair, i| {
            pto_env[i][0] = try allocator.dupe(u8, pair[0]);
            errdefer allocator.free(pto_env[i][0]);
            pto_env[i][1] = try allocator.dupe(u8, pair[1]);
            ptenv_duped += 1;
        }
        const pto = ProfileTaskOverride{
            .cmd = if (profile_task_cmd) |c| try allocator.dupe(u8, c) else null,
            .cwd = if (profile_task_cwd) |c| try allocator.dupe(u8, c) else null,
            .env = pto_env,
        };
        const pto_key = try allocator.dupe(u8, ptask);
        errdefer allocator.free(pto_key);
        try profile_task_overrides.put(pto_key, pto);
    }

    // Flush final pending profile
    if (current_profile) |pname| {
        try flushProfile(allocator, &config, pname, &profile_env, &profile_task_overrides);
        profile_env.clearRetainingCapacity();
    }

    // Flush workspace if present
    if (in_workspace or ws_members.items.len > 0) {
        const members = try allocator.alloc([]const u8, ws_members.items.len);
        var mduped: usize = 0;
        errdefer {
            for (members[0..mduped]) |m| allocator.free(m);
            allocator.free(members);
        }
        for (ws_members.items, 0..) |m, i| {
            members[i] = try allocator.dupe(u8, m);
            mduped += 1;
        }
        const ignore = try allocator.alloc([]const u8, ws_ignore.items.len);
        var iduped: usize = 0;
        errdefer {
            for (ignore[0..iduped]) |ig| allocator.free(ig);
            allocator.free(ignore);
        }
        for (ws_ignore.items, 0..) |ig, i| {
            ignore[i] = try allocator.dupe(u8, ig);
            iduped += 1;
        }
        config.workspace = Workspace{ .members = members, .ignore = ignore };
    }

    // Flush final pending plugin (if any)
    if (current_plugin_name) |pn| {
        if (plugin_source) |src| {
            const pc_pairs = try allocator.alloc([2][]const u8, plugin_cfg_pairs.items.len);
            var pc_duped: usize = 0;
            errdefer {
                for (pc_pairs[0..pc_duped]) |pair| { allocator.free(pair[0]); allocator.free(pair[1]); }
                allocator.free(pc_pairs);
            }
            for (plugin_cfg_pairs.items, 0..) |pair, i| {
                pc_pairs[i][0] = try allocator.dupe(u8, pair[0]);
                errdefer allocator.free(pc_pairs[i][0]);
                pc_pairs[i][1] = try allocator.dupe(u8, pair[1]);
                pc_duped += 1;
            }
            const pc = PluginConfig{
                .name = try allocator.dupe(u8, pn),
                .kind = plugin_kind,
                .source = try allocator.dupe(u8, src),
                .config = pc_pairs,
            };
            try plugin_list.append(allocator, pc);
        }
    }

    // Transfer owned plugin list to config
    if (plugin_list.items.len > 0) {
        const owned = try allocator.alloc(PluginConfig, plugin_list.items.len);
        @memcpy(owned, plugin_list.items);
        // Clear plugin_list so defer doesn't double-free
        plugin_list.clearRetainingCapacity();
        config.plugins = owned;
    }

    return config;
}

/// Helper: flush accumulated profile state into config.profiles.
/// Clears profile_task_overrides after transferring ownership to the Profile.
fn flushProfile(
    allocator: std.mem.Allocator,
    config: *Config,
    pname: []const u8,
    profile_env: *std.ArrayList([2][]const u8),
    profile_task_overrides: *std.StringHashMap(ProfileTaskOverride),
) !void {
    const p_name = try allocator.dupe(u8, pname);
    errdefer allocator.free(p_name);

    const p_env = try allocator.alloc([2][]const u8, profile_env.items.len);
    var env_duped: usize = 0;
    errdefer {
        for (p_env[0..env_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(p_env);
    }
    for (profile_env.items, 0..) |pair, i| {
        p_env[i][0] = try allocator.dupe(u8, pair[0]);
        errdefer allocator.free(p_env[i][0]);
        p_env[i][1] = try allocator.dupe(u8, pair[1]);
        env_duped += 1;
    }

    // Transfer ownership of task_overrides map
    var new_overrides = std.StringHashMap(ProfileTaskOverride).init(allocator);
    errdefer {
        var oit = new_overrides.iterator();
        while (oit.next()) |e| {
            allocator.free(e.key_ptr.*);
            e.value_ptr.deinit(allocator);
        }
        new_overrides.deinit();
    }
    var src_it = profile_task_overrides.iterator();
    while (src_it.next()) |entry| {
        // Move key and value into new_overrides (steal ownership)
        try new_overrides.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    // Clear source map without freeing (ownership transferred)
    profile_task_overrides.clearRetainingCapacity();

    const profile = Profile{
        .name = p_name,
        .env = p_env,
        .task_overrides = new_overrides,
    };
    try config.profiles.put(p_name, profile);
}

fn addTaskImpl(
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

/// Parse a TOML inline table of arrays: { key1 = ["v1", "v2"], key2 = ["a", "b"] }
/// Appends MatrixDim entries (with owned memory) to dims_out.
fn parseMatrixTable(allocator: std.mem.Allocator, raw: []const u8, dims_out: *std.ArrayList(MatrixDim)) !void {
    const inner_full = std.mem.trim(u8, raw, " \t");
    if (!std.mem.startsWith(u8, inner_full, "{") or !std.mem.endsWith(u8, inner_full, "}")) return;
    const inner = inner_full[1 .. inner_full.len - 1];

    var i: usize = 0;
    while (i < inner.len) {
        // Skip whitespace and commas between key=value pairs
        while (i < inner.len and (inner[i] == ' ' or inner[i] == '\t' or inner[i] == ',')) i += 1;
        if (i >= inner.len) break;

        // Read key until '='
        const key_start = i;
        while (i < inner.len and inner[i] != '=') i += 1;
        const key = std.mem.trim(u8, inner[key_start..i], " \t\"");
        if (i >= inner.len or key.len == 0) break;
        i += 1; // skip '='

        // Skip whitespace before '['
        while (i < inner.len and (inner[i] == ' ' or inner[i] == '\t')) i += 1;
        if (i >= inner.len or inner[i] != '[') break;
        i += 1; // skip '['

        // Find matching ']', tracking bracket depth and string quotes
        const arr_start = i;
        var depth: usize = 1;
        var in_str: bool = false;
        while (i < inner.len and depth > 0) {
            const ch = inner[i];
            if (ch == '"' and (i == 0 or inner[i - 1] != '\\')) in_str = !in_str;
            if (!in_str) {
                if (ch == '[') depth += 1 else if (ch == ']') depth -= 1;
            }
            if (depth > 0) i += 1;
        }
        const arr_content = inner[arr_start..i];
        i += 1; // skip ']'

        // Parse comma-separated quoted values inside the array
        var values: std.ArrayListUnmanaged([]const u8) = .{};
        errdefer {
            for (values.items) |v| allocator.free(v);
            values.deinit(allocator);
        }
        var val_it = std.mem.splitScalar(u8, arr_content, ',');
        while (val_it.next()) |item| {
            const trimmed_item = std.mem.trim(u8, item, " \t\"");
            if (trimmed_item.len > 0) {
                try values.append(allocator, try allocator.dupe(u8, trimmed_item));
            }
        }
        if (values.items.len == 0) {
            values.deinit(allocator);
            continue;
        }

        const duped_key = try allocator.dupe(u8, key);
        errdefer allocator.free(duped_key);
        try dims_out.append(allocator, MatrixDim{
            .key = duped_key,
            .values = try values.toOwnedSlice(allocator),
        });
    }
}

/// Replace all occurrences of ${matrix.KEY} in template with the value
/// at dims[i].values[combo[i]] for each dimension i.
fn interpolateMatrixVars(allocator: std.mem.Allocator, template: []const u8, dims: []const MatrixDim, combo: []const usize) ![]const u8 {
    var result = try allocator.dupe(u8, template);
    errdefer allocator.free(result);
    for (dims, 0..) |dim, i| {
        const val = dim.values[combo[i]];
        const placeholder = try std.fmt.allocPrint(allocator, "${{matrix.{s}}}", .{dim.key});
        defer allocator.free(placeholder);
        const new_result = try std.mem.replaceOwned(u8, allocator, result, placeholder, val);
        allocator.free(result);
        result = new_result;
    }
    return result;
}

/// Expand a matrix task into variant tasks and a meta-task.
/// Computes the Cartesian product of all matrix dimensions, creates one variant
/// task per combination (with ${matrix.KEY} substituted), and adds a meta-task
/// with the original name that deps on all variants.
fn addMatrixTask(
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
    matrix_raw: []const u8,
) !void {
    // Parse the matrix inline table into dims
    var dims: std.ArrayListUnmanaged(MatrixDim) = .{};
    defer {
        for (dims.items) |*d| d.deinit(allocator);
        dims.deinit(allocator);
    }
    try parseMatrixTable(allocator, matrix_raw, &dims);

    if (dims.items.len == 0) {
        // No matrix dims parsed; fall back to plain task
        return addTaskImpl(config, allocator, name, cmd, cwd, description, deps, deps_serial, env, timeout_ms, allow_failure, retry_max, retry_delay_ms, retry_backoff, condition, max_concurrent, cache);
    }

    // Build sorted key list for deterministic variant name ordering
    // Sort dims by key alphabetically
    const n_dims = dims.items.len;
    // Simple insertion sort (n_dims is typically very small)
    for (1..n_dims) |si| {
        var j = si;
        while (j > 0 and std.mem.lessThan(u8, dims.items[j].key, dims.items[j - 1].key)) : (j -= 1) {
            const tmp = dims.items[j];
            dims.items[j] = dims.items[j - 1];
            dims.items[j - 1] = tmp;
        }
    }

    // Compute total combinations = product of all dim value counts
    var total: usize = 1;
    for (dims.items) |dim| total *= dim.values.len;

    // combo[i] = current index into dims[i].values
    const combo = try allocator.alloc(usize, n_dims);
    defer allocator.free(combo);
    @memset(combo, 0);

    // Collect variant names for the meta-task's deps
    var variant_names: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (variant_names.items) |vn| allocator.free(vn);
        variant_names.deinit(allocator);
    }

    var variant_idx: usize = 0;
    while (variant_idx < total) : (variant_idx += 1) {
        // Build variant name: basename:key1=val1:key2=val2 (keys sorted)
        var vname_buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer vname_buf.deinit(allocator);
        try vname_buf.appendSlice(allocator, name);
        for (dims.items, 0..) |dim, di| {
            try vname_buf.append(allocator, ':');
            try vname_buf.appendSlice(allocator, dim.key);
            try vname_buf.append(allocator, '=');
            try vname_buf.appendSlice(allocator, dim.values[combo[di]]);
        }
        const vname = try vname_buf.toOwnedSlice(allocator);
        errdefer allocator.free(vname);

        // Interpolate cmd, cwd, description, env values
        const v_cmd = try interpolateMatrixVars(allocator, cmd, dims.items, combo);
        errdefer allocator.free(v_cmd);

        const v_cwd: ?[]const u8 = if (cwd) |c| try interpolateMatrixVars(allocator, c, dims.items, combo) else null;
        errdefer if (v_cwd) |c| allocator.free(c);

        const v_desc: ?[]const u8 = if (description) |d| try interpolateMatrixVars(allocator, d, dims.items, combo) else null;
        errdefer if (v_desc) |d| allocator.free(d);

        // Interpolate env values
        var v_env_list: std.ArrayListUnmanaged([2][]const u8) = .{};
        defer {
            for (v_env_list.items) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            v_env_list.deinit(allocator);
        }
        for (env) |pair| {
            const ek = try allocator.dupe(u8, pair[0]);
            errdefer allocator.free(ek);
            const ev = try interpolateMatrixVars(allocator, pair[1], dims.items, combo);
            errdefer allocator.free(ev);
            try v_env_list.append(allocator, .{ ek, ev });
        }

        // Add the variant task (addTaskImpl dupes everything, so our locals can be freed)
        try addTaskImpl(config, allocator, vname, v_cmd, v_cwd, v_desc, deps, deps_serial, v_env_list.items, timeout_ms, allow_failure, retry_max, retry_delay_ms, retry_backoff, condition, max_concurrent, cache);

        // Free our allocations (addTaskImpl duped them)
        allocator.free(v_cmd);
        if (v_cwd) |c| allocator.free(c);
        if (v_desc) |d| allocator.free(d);
        for (v_env_list.items) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        v_env_list.clearRetainingCapacity(); // prevent double-free in defer

        // Track variant name (keep ownership; addTaskImpl duped its own copy)
        try variant_names.append(allocator, vname);
        // vname is now owned by variant_names; remove from errdefer scope by re-assigning
        // (the errdefer on vname fires only if an error occurs before this line)

        // Advance combo (little-endian: last dim increments fastest)
        var di = n_dims;
        while (di > 0) {
            di -= 1;
            combo[di] += 1;
            if (combo[di] < dims.items[di].values.len) break;
            combo[di] = 0;
        }
    }

    // Create meta-task: same name as original, no cmd (use echo), deps = all variants
    const meta_cmd = try std.fmt.allocPrint(allocator, "echo \"Matrix task: {s}\"", .{name});
    defer allocator.free(meta_cmd);

    try addTaskImpl(config, allocator, name, meta_cmd, null, description, variant_names.items, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, null, 0, false);
}

test "parseDurationMs: various units" {
    try std.testing.expectEqual(@as(?u64, 500), parseDurationMs("500ms"));
    try std.testing.expectEqual(@as(?u64, 30_000), parseDurationMs("30s"));
    try std.testing.expectEqual(@as(?u64, 5 * 60_000), parseDurationMs("5m"));
    try std.testing.expectEqual(@as(?u64, 2 * 3_600_000), parseDurationMs("2h"));
    try std.testing.expectEqual(@as(?u64, null), parseDurationMs(""));
    try std.testing.expectEqual(@as(?u64, null), parseDurationMs("xyz"));
}

test "parse timeout and allow_failure from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\timeout = "5m"
        \\allow_failure = true
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(?u64, 5 * 60_000), task.timeout_ms);
    try std.testing.expect(task.allow_failure);
}

test "parse simple toml config" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\description = "Build the project"
        \\
        \\[tasks.test]
        \\cmd = "zig build test"
        \\deps = ["build"]
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expect(config.tasks.count() == 2);

    const build_task = config.tasks.get("build").?;
    try std.testing.expectEqualStrings("zig build", build_task.cmd);
    try std.testing.expectEqualStrings("Build the project", build_task.description.?);

    const test_task = config.tasks.get("test").?;
    try std.testing.expectEqualStrings("zig build test", test_task.cmd);
    try std.testing.expect(test_task.deps.len == 1);
    try std.testing.expectEqualStrings("build", test_task.deps[0]);
}

test "parse deps_serial from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.backup]
        \\cmd = "echo backup"
        \\
        \\[tasks.migrate]
        \\cmd = "echo migrate"
        \\
        \\[tasks.verify]
        \\cmd = "echo verify"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps_serial = ["backup", "migrate", "verify"]
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const deploy = config.tasks.get("deploy").?;
    try std.testing.expectEqual(@as(usize, 3), deploy.deps_serial.len);
    try std.testing.expectEqualStrings("backup", deploy.deps_serial[0]);
    try std.testing.expectEqualStrings("migrate", deploy.deps_serial[1]);
    try std.testing.expectEqualStrings("verify", deploy.deps_serial[2]);
    try std.testing.expectEqual(@as(usize, 0), deploy.deps.len);
}

test "parse env from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\env = { NODE_ENV = "production", DEBUG = "false" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(usize, 2), task.env.len);

    // Find each key-value pair (order may vary since we split by comma)
    var found_node_env = false;
    var found_debug = false;
    for (task.env) |pair| {
        if (std.mem.eql(u8, pair[0], "NODE_ENV")) {
            try std.testing.expectEqualStrings("production", pair[1]);
            found_node_env = true;
        } else if (std.mem.eql(u8, pair[0], "DEBUG")) {
            try std.testing.expectEqualStrings("false", pair[1]);
            found_debug = true;
        }
    }
    try std.testing.expect(found_node_env);
    try std.testing.expect(found_debug);
}

test "addTaskWithEnv: programmatic env construction" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    const env_pairs = [_][2][]const u8{
        .{ "MY_VAR", "hello" },
        .{ "OTHER", "world" },
    };
    try config.addTaskWithEnv("env-task", "echo $MY_VAR", null, null, &[_][]const u8{}, &env_pairs);

    const task = config.tasks.get("env-task").?;
    try std.testing.expectEqual(@as(usize, 2), task.env.len);
    try std.testing.expectEqualStrings("MY_VAR", task.env[0][0]);
    try std.testing.expectEqualStrings("hello", task.env[0][1]);
    try std.testing.expectEqualStrings("OTHER", task.env[1][0]);
    try std.testing.expectEqualStrings("world", task.env[1][1]);
}

test "parse retry from toml inline table" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\retry = { max = 3, delay = "5s", backoff = "exponential" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("deploy").?;
    try std.testing.expectEqual(@as(u32, 3), task.retry_max);
    try std.testing.expectEqual(@as(u64, 5_000), task.retry_delay_ms);
    try std.testing.expect(task.retry_backoff);
}

test "parse retry with no backoff" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.fetch]
        \\cmd = "curl https://example.com"
        \\retry = { max = 2, delay = "1s" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("fetch").?;
    try std.testing.expectEqual(@as(u32, 2), task.retry_max);
    try std.testing.expectEqual(@as(u64, 1_000), task.retry_delay_ms);
    try std.testing.expect(!task.retry_backoff);
}

test "addTaskWithRetry: programmatic retry construction" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTaskWithRetry("retry-task", "flaky.sh", null, null, &[_][]const u8{}, 3, 500, true);

    const task = config.tasks.get("retry-task").?;
    try std.testing.expectEqual(@as(u32, 3), task.retry_max);
    try std.testing.expectEqual(@as(u64, 500), task.retry_delay_ms);
    try std.testing.expect(task.retry_backoff);
}

test "task defaults: retry fields are zero/false by default" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTask("plain", "echo hi", null, null, &[_][]const u8{});

    const task = config.tasks.get("plain").?;
    try std.testing.expectEqual(@as(u32, 0), task.retry_max);
    try std.testing.expectEqual(@as(u64, 0), task.retry_delay_ms);
    try std.testing.expect(!task.retry_backoff);
}

test "parse condition from toml" {
    const allocator = std.testing.allocator;

    // Use single-quoted style to avoid escape complexity: condition = "true"
    const toml_content =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\condition = "env.CI"
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("deploy").?;
    try std.testing.expect(task.condition != null);
    try std.testing.expectEqualStrings("env.CI", task.condition.?);
}

test "addTaskWithCondition: programmatic condition" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTaskWithCondition("cond-task", "echo hi", "true");
    const task = config.tasks.get("cond-task").?;
    try std.testing.expect(task.condition != null);
    try std.testing.expectEqualStrings("true", task.condition.?);
}

test "task defaults: condition is null by default" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTask("no-cond", "echo hi", null, null, &[_][]const u8{});
    const task = config.tasks.get("no-cond").?;
    try std.testing.expect(task.condition == null);
}

test "parse workflow from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.clean]
        \\cmd = "echo clean"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[workflows.release]
        \\description = "Full release pipeline"
        \\
        \\[[workflows.release.stages]]
        \\name = "prepare"
        \\tasks = ["clean"]
        \\parallel = true
        \\
        \\[[workflows.release.stages]]
        \\name = "build"
        \\tasks = ["build"]
        \\parallel = false
        \\fail_fast = true
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 2), config.tasks.count());
    try std.testing.expectEqual(@as(usize, 1), config.workflows.count());

    const wf = config.workflows.get("release").?;
    try std.testing.expectEqualStrings("Full release pipeline", wf.description.?);
    try std.testing.expectEqual(@as(usize, 2), wf.stages.len);

    const s0 = wf.stages[0];
    try std.testing.expectEqualStrings("prepare", s0.name);
    try std.testing.expectEqual(@as(usize, 1), s0.tasks.len);
    try std.testing.expectEqualStrings("clean", s0.tasks[0]);
    try std.testing.expect(s0.parallel);
    try std.testing.expect(!s0.fail_fast);

    const s1 = wf.stages[1];
    try std.testing.expectEqualStrings("build", s1.name);
    try std.testing.expect(!s1.parallel);
    try std.testing.expect(s1.fail_fast);
}

test "addWorkflow: programmatic workflow construction" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var stages = [_]Stage{
        .{
            .name = "s1",
            .tasks = @constCast(&[_][]const u8{"task-a"}),
            .parallel = true,
            .fail_fast = false,
            .condition = null,
        },
    };
    try config.addWorkflow("my-workflow", "desc", &stages);

    const wf = config.workflows.get("my-workflow").?;
    try std.testing.expectEqualStrings("desc", wf.description.?);
    try std.testing.expectEqual(@as(usize, 1), wf.stages.len);
    try std.testing.expectEqualStrings("s1", wf.stages[0].name);
}

test "parse profile with global env from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\
        \\[profiles.dev]
        \\env = { NODE_ENV = "development", DEBUG = "true" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.profiles.count());

    const prof = config.profiles.get("dev").?;
    try std.testing.expectEqualStrings("dev", prof.name);
    try std.testing.expectEqual(@as(usize, 2), prof.env.len);

    var found_node_env = false;
    var found_debug = false;
    for (prof.env) |pair| {
        if (std.mem.eql(u8, pair[0], "NODE_ENV")) {
            try std.testing.expectEqualStrings("development", pair[1]);
            found_node_env = true;
        } else if (std.mem.eql(u8, pair[0], "DEBUG")) {
            try std.testing.expectEqualStrings("true", pair[1]);
            found_debug = true;
        }
    }
    try std.testing.expect(found_node_env);
    try std.testing.expect(found_debug);
}

test "parse profile with task override from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\
        \\[profiles.ci]
        \\env = { CI = "true" }
        \\
        \\[profiles.ci.tasks.build]
        \\cmd = "zig build -Doptimize=ReleaseSafe"
        \\env = { RELEASE = "1" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const prof = config.profiles.get("ci").?;
    try std.testing.expectEqualStrings("ci", prof.name);
    try std.testing.expectEqual(@as(usize, 1), prof.env.len);
    try std.testing.expectEqualStrings("CI", prof.env[0][0]);
    try std.testing.expectEqualStrings("true", prof.env[0][1]);

    const ov = prof.task_overrides.get("build").?;
    try std.testing.expect(ov.cmd != null);
    try std.testing.expectEqualStrings("zig build -Doptimize=ReleaseSafe", ov.cmd.?);
    try std.testing.expectEqual(@as(usize, 1), ov.env.len);
    try std.testing.expectEqualStrings("RELEASE", ov.env[0][0]);
    try std.testing.expectEqualStrings("1", ov.env[0][1]);
}

test "applyProfile: global env added to all tasks" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\
        \\[tasks.test]
        \\cmd = "zig build test"
        \\
        \\[profiles.dev]
        \\env = { DEBUG = "1" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try config.applyProfile("dev");

    // Both tasks should now have DEBUG=1 in their env
    const build = config.tasks.get("build").?;
    var found = false;
    for (build.env) |pair| {
        if (std.mem.eql(u8, pair[0], "DEBUG") and std.mem.eql(u8, pair[1], "1")) found = true;
    }
    try std.testing.expect(found);

    const tst = config.tasks.get("test").?;
    found = false;
    for (tst.env) |pair| {
        if (std.mem.eql(u8, pair[0], "DEBUG") and std.mem.eql(u8, pair[1], "1")) found = true;
    }
    try std.testing.expect(found);
}

test "applyProfile: task-level cmd override" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\
        \\[profiles.release]
        \\env = {}
        \\
        \\[profiles.release.tasks.build]
        \\cmd = "zig build -Doptimize=ReleaseFast"
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try config.applyProfile("release");

    const build = config.tasks.get("build").?;
    try std.testing.expectEqualStrings("zig build -Doptimize=ReleaseFast", build.cmd);
}

test "applyProfile: error on unknown profile" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const result = config.applyProfile("nonexistent");
    try std.testing.expectError(error.ProfileNotFound, result);
}

test "parse multiple profiles from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\
        \\[profiles.dev]
        \\env = { DEBUG = "true" }
        \\
        \\[profiles.prod]
        \\env = { OPTIMIZE = "true" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 2), config.profiles.count());
    try std.testing.expect(config.profiles.get("dev") != null);
    try std.testing.expect(config.profiles.get("prod") != null);
}

test "parse max_concurrent from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
        \\max_concurrent = 3
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(u32, 3), task.max_concurrent);
}

test "max_concurrent defaults to 0" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(u32, 0), task.max_concurrent);
}

test "parse workspace section from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
        \\
        \\[workspace]
        \\members = ["packages/*", "apps/*"]
        \\ignore = ["**/node_modules"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expect(config.workspace != null);
    const ws = config.workspace.?;
    try std.testing.expectEqual(@as(usize, 2), ws.members.len);
    try std.testing.expectEqualStrings("packages/*", ws.members[0]);
    try std.testing.expectEqualStrings("apps/*", ws.members[1]);
    try std.testing.expectEqual(@as(usize, 1), ws.ignore.len);
    try std.testing.expectEqualStrings("**/node_modules", ws.ignore[0]);
}

test "workspace null when no workspace section" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expect(config.workspace == null);
}

test "matrix: simple expansion single dimension" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.test]
        \\cmd = "cargo test --target ${matrix.arch}"
        \\matrix = { arch = ["x86_64", "aarch64"] }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    // Should have: meta-task "test" + 2 variants
    try std.testing.expectEqual(@as(usize, 3), config.tasks.count());

    // Meta-task exists
    const meta = config.tasks.get("test").?;
    try std.testing.expectEqual(@as(usize, 2), meta.deps.len);

    // Variants exist with correct names
    try std.testing.expect(config.tasks.get("test:arch=x86_64") != null);
    try std.testing.expect(config.tasks.get("test:arch=aarch64") != null);

    // Variant cmd has substituted value
    const v1 = config.tasks.get("test:arch=x86_64").?;
    try std.testing.expectEqualStrings("cargo test --target x86_64", v1.cmd);
    const v2 = config.tasks.get("test:arch=aarch64").?;
    try std.testing.expectEqualStrings("cargo test --target aarch64", v2.cmd);
}

test "matrix: cartesian product 2x2" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.test]
        \\cmd = "test ${matrix.arch} ${matrix.os}"
        \\matrix = { arch = ["x86_64", "aarch64"], os = ["linux", "macos"] }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    // 4 variants + 1 meta-task = 5 total
    try std.testing.expectEqual(@as(usize, 5), config.tasks.count());

    const meta = config.tasks.get("test").?;
    try std.testing.expectEqual(@as(usize, 4), meta.deps.len);

    // All variant combinations must exist
    try std.testing.expect(config.tasks.get("test:arch=x86_64:os=linux") != null);
    try std.testing.expect(config.tasks.get("test:arch=x86_64:os=macos") != null);
    try std.testing.expect(config.tasks.get("test:arch=aarch64:os=linux") != null);
    try std.testing.expect(config.tasks.get("test:arch=aarch64:os=macos") != null);

    // Check cmd substitution
    const v = config.tasks.get("test:arch=x86_64:os=linux").?;
    try std.testing.expectEqualStrings("test x86_64 linux", v.cmd);
}

test "matrix: keys sorted alphabetically in variant name" {
    const allocator = std.testing.allocator;
    // Define dimensions in reverse alphabetical order: os before arch
    const toml_content =
        \\[tasks.build]
        \\cmd = "build"
        \\matrix = { os = ["linux"], arch = ["x86_64"] }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    // Keys sorted alphabetically: arch < os, so name is build:arch=x86_64:os=linux
    try std.testing.expect(config.tasks.get("build:arch=x86_64:os=linux") != null);
}

test "matrix: meta-task has no-op cmd" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.lint]
        \\cmd = "lint ${matrix.target}"
        \\matrix = { target = ["js", "ts"] }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const meta = config.tasks.get("lint").?;
    // Meta cmd starts with "echo"
    try std.testing.expect(std.mem.startsWith(u8, meta.cmd, "echo"));
    // Variants have substituted cmds
    const v1 = config.tasks.get("lint:target=js").?;
    try std.testing.expectEqualStrings("lint js", v1.cmd);
}

test "parse cache = true from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
        \\cache = true
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    const task = config.tasks.get("build").?;
    try std.testing.expect(task.cache);
}

test "cache defaults to false" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    const task = config.tasks.get("build").?;
    try std.testing.expect(!task.cache);
}

test "parse local plugin from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
        \\
        \\[plugins.myplugin]
        \\source = "local:./plugins/myplugin"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 1), config.plugins.len);
    const p = config.plugins[0];
    try std.testing.expectEqualStrings("myplugin", p.name);
    try std.testing.expectEqual(PluginSourceKind.local, p.kind);
    try std.testing.expectEqualStrings("./plugins/myplugin", p.source);
    try std.testing.expectEqual(@as(usize, 0), p.config.len);
}

test "parse registry plugin from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[plugins.docker]
        \\source = "registry:zr/docker@1.2.0"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 1), config.plugins.len);
    const p = config.plugins[0];
    try std.testing.expectEqualStrings("docker", p.name);
    try std.testing.expectEqual(PluginSourceKind.registry, p.kind);
    try std.testing.expectEqualStrings("zr/docker@1.2.0", p.source);
}

test "parse git plugin from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[plugins.custom]
        \\source = "git:https://github.com/user/plugin"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 1), config.plugins.len);
    const p = config.plugins[0];
    try std.testing.expectEqualStrings("custom", p.name);
    try std.testing.expectEqual(PluginSourceKind.git, p.kind);
    try std.testing.expectEqualStrings("https://github.com/user/plugin", p.source);
}

test "parse plugin with config inline table" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[plugins.notify]
        \\source = "local:./plugins/notify"
        \\config = { webhook_url = "https://hooks.example.com/abc", channel = "#alerts" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 1), config.plugins.len);
    const p = config.plugins[0];
    try std.testing.expectEqual(@as(usize, 2), p.config.len);
    // Order not guaranteed, find by key
    var found_webhook = false;
    for (p.config) |pair| {
        if (std.mem.eql(u8, pair[0], "webhook_url")) {
            try std.testing.expectEqualStrings("https://hooks.example.com/abc", pair[1]);
            found_webhook = true;
        }
    }
    try std.testing.expect(found_webhook);
}

test "multiple plugins parsed correctly" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[plugins.docker]
        \\source = "registry:zr/docker@1.0.0"
        \\
        \\[plugins.notify]
        \\source = "local:./notify"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 2), config.plugins.len);
}

test "no plugins section gives empty plugins slice" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 0), config.plugins.len);
}

test "plugin without source is ignored" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[plugins.broken]
        \\config = { key = "value" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    // Plugin with no source should be ignored (source is required).
    try std.testing.expectEqual(@as(usize, 0), config.plugins.len);
}
