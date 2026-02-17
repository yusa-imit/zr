const std = @import("std");

pub const Config = struct {
    tasks: std.StringHashMap(Task),
    workflows: std.StringHashMap(Workflow),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .tasks = std.StringHashMap(Task).init(allocator),
            .workflows = std.StringHashMap(Workflow).init(allocator),
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
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, null);
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
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, timeout_ms, allow_failure, 0, 0, false, null);
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
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, deps_serial, &[_][2][]const u8{}, null, false, 0, 0, false, null);
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
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, env, null, false, 0, 0, false, null);
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
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, null, false, retry_max, retry_delay_ms, retry_backoff, null);
    }

    /// Add a task with a condition expression (for tests or programmatic use).
    pub fn addTaskWithCondition(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        condition: ?[]const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, condition);
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

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "[[workflows.") and std.mem.endsWith(u8, trimmed, ".stages]]")) {
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
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition);
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
                current_task = null;
            }
            // Parse new workflow name from "[workflows.X]"
            const wf_start = "[workflows.".len;
            const wf_end = std.mem.indexOf(u8, trimmed[wf_start..], "]") orelse continue;
            current_workflow = trimmed[wf_start..][0..wf_end];
            workflow_desc = null;
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
            // Flush pending task before starting new one
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition);
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

            if (current_workflow != null and current_task == null) {
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
            try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition);
        }
    }

    return config;
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
    };

    try config.tasks.put(task_name, task);
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
