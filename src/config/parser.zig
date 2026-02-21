const std = @import("std");
const types = @import("types.zig");
const matrix = @import("matrix.zig");

const Config = types.Config;
const Task = types.Task;
const Stage = types.Stage;
const Workflow = types.Workflow;
const Profile = types.Profile;
const ProfileTaskOverride = types.ProfileTaskOverride;
const MatrixDim = types.MatrixDim;
const Workspace = types.Workspace;
const PluginConfig = types.PluginConfig;
const PluginSourceKind = types.PluginSourceKind;
const parseDurationMs = types.parseDurationMs;
const parseMemoryBytes = types.parseMemoryBytes;
const addTaskImpl = types.addTaskImpl;
const addMatrixTask = matrix.addMatrixTask;
const toolchain_types = @import("../toolchain/types.zig");

/// Parse a constraint scope value from TOML (e.g., { tag = "app" } or "path/to/project").
/// Returns non-owning slices into the value string.
fn parseScopeValue(value: []const u8) !?types.ConstraintScope {
    if (std.mem.eql(u8, value, "all")) return .all;

    // Check for inline table: { tag = "value" } or { path = "value" }
    if (std.mem.startsWith(u8, value, "{") and std.mem.endsWith(u8, value, "}")) {
        const inner = std.mem.trim(u8, value[1 .. value.len - 1], " \t");
        const eq_idx = std.mem.indexOf(u8, inner, "=") orelse return null;
        const k = std.mem.trim(u8, inner[0..eq_idx], " \t");
        var v = std.mem.trim(u8, inner[eq_idx + 1 ..], " \t");

        // Strip quotes
        if (v.len >= 2 and v[0] == '"' and v[v.len - 1] == '"') {
            v = v[1 .. v.len - 1];
        }

        if (std.mem.eql(u8, k, "tag")) {
            return types.ConstraintScope{ .tag = v };
        } else if (std.mem.eql(u8, k, "path")) {
            return types.ConstraintScope{ .path = v };
        }
    }

    // Plain string is treated as a path
    return types.ConstraintScope{ .path = value };
}

/// Dupe a ConstraintScope, allocating owned copies of strings.
fn dupeConstraintScope(allocator: std.mem.Allocator, scope: types.ConstraintScope) !types.ConstraintScope {
    return switch (scope) {
        .all => .all,
        .tag => |t| types.ConstraintScope{ .tag = try allocator.dupe(u8, t) },
        .path => |p| types.ConstraintScope{ .path = try allocator.dupe(u8, p) },
    };
}

pub fn parseToml(allocator: std.mem.Allocator, content: []const u8) !Config {
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
    var task_max_cpu: ?u32 = null;
    var task_max_memory: ?u64 = null;
    // Matrix raw inline table string (non-owning slice into content)
    var task_matrix_raw: ?[]const u8 = null;

    // Non-owning slices into content — addTask dupes them
    var task_deps = std.ArrayList([]const u8){};
    defer task_deps.deinit(allocator);
    var task_deps_serial = std.ArrayList([]const u8){};
    defer task_deps_serial.deinit(allocator);
    // Toolchain requirements (non-owning slices into content)
    var task_toolchain = std.ArrayList([]const u8){};
    defer task_toolchain.deinit(allocator);
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
    var ws_member_deps = std.ArrayList([]const u8){};
    defer ws_member_deps.deinit(allocator);

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

    // Toolchain parsing state (Phase 5)
    var in_tools: bool = false;
    var tools_specs = std.ArrayList(toolchain_types.ToolSpec){};
    defer {
        for (tools_specs.items) |*ts| ts.deinit(allocator);
        tools_specs.deinit(allocator);
    }

    // Constraint parsing state (Phase 6) — [[constraints]]
    var in_constraint: bool = false;
    var constraint_rule: ?types.ConstraintRule = null;
    var constraint_scope: ?types.ConstraintScope = null;
    var constraint_from: ?types.ConstraintScope = null;
    var constraint_to: ?types.ConstraintScope = null;
    var constraint_allow: bool = true;
    var constraint_message: ?[]const u8 = null;
    // Collected constraints (owned)
    var constraint_list = std.ArrayList(types.Constraint){};
    defer {
        for (constraint_list.items) |*c| c.deinit(allocator);
        constraint_list.deinit(allocator);
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
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items);
                    }
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_toolchain.clearRetainingCapacity();
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
                task_max_cpu = null;
                task_max_memory = null;
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
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items);
                    }
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_toolchain.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null;
                task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false;
                task_condition = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null; current_task = null;
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
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false; task_condition = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null; current_task = null;
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
        } else if (std.mem.eql(u8, trimmed, "[tools]")) {
            // Flush pending sections
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    if (task_matrix_raw) |mraw| {
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false; task_condition = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null; current_task = null;
            }
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity(); current_workflow = null; workflow_desc = null;
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
            in_workspace = false;
            in_tools = true;
            in_constraint = false;
        } else if (std.mem.eql(u8, trimmed, "[[constraints]]")) {
            // Flush pending constraint (if any)
            if (constraint_rule) |rule| {
                const owned_from = if (constraint_from) |f| try dupeConstraintScope(allocator, f) else null;
                errdefer if (owned_from) |*f| {
                    var scope_copy = f.*;
                    scope_copy.deinit(allocator);
                };
                const owned_to = if (constraint_to) |t| try dupeConstraintScope(allocator, t) else null;
                errdefer if (owned_to) |*t| {
                    var scope_copy = t.*;
                    scope_copy.deinit(allocator);
                };

                try constraint_list.append(allocator, types.Constraint{
                    .rule = rule,
                    .scope = if (constraint_scope) |s| try dupeConstraintScope(allocator, s) else .all,
                    .from = owned_from,
                    .to = owned_to,
                    .allow = constraint_allow,
                    .message = if (constraint_message) |m| try allocator.dupe(u8, m) else null,
                });
                constraint_rule = null;
                constraint_scope = null;
                constraint_from = null;
                constraint_to = null;
                constraint_allow = true;
                constraint_message = null;
            }
            in_workspace = false;
            in_tools = false;
            in_constraint = true;
        } else if (std.mem.startsWith(u8, trimmed, "[plugins.") and !std.mem.startsWith(u8, trimmed, "[[")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            // Flush pending task (if any)
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    if (task_matrix_raw) |mraw| {
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false; task_condition = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null;
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
                        try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                    } else {
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items);
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
            task_max_cpu = null;
            task_max_memory = null;
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
            } else if (in_tools) {
                // Inside [tools] section — parse tool = "version" pairs
                const tool_kind = toolchain_types.ToolKind.fromString(key) orelse continue;
                const tool_version = toolchain_types.ToolVersion.parse(value) catch continue;
                try tools_specs.append(allocator, toolchain_types.ToolSpec{
                    .kind = tool_kind,
                    .version = tool_version,
                });
            } else if (in_constraint) {
                // Inside [[constraints]] — parse constraint fields
                if (std.mem.eql(u8, key, "rule")) {
                    constraint_rule = types.ConstraintRule.parse(value) catch null;
                } else if (std.mem.eql(u8, key, "scope")) {
                    constraint_scope = if (std.mem.eql(u8, value, "all")) .all else null;
                } else if (std.mem.eql(u8, key, "from")) {
                    constraint_from = try parseScopeValue(value);
                } else if (std.mem.eql(u8, key, "to")) {
                    constraint_to = try parseScopeValue(value);
                } else if (std.mem.eql(u8, key, "allow")) {
                    constraint_allow = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "message")) {
                    constraint_message = value;
                }
            } else if (current_plugin_name != null and current_task == null and current_workflow == null and current_profile == null and !in_workspace) {
                // Inside [plugins.X] — parse source and config fields
                if (std.mem.eql(u8, key, "source")) {
                    // Detect source kind from prefix: "builtin:", "registry:", "git:", else local
                    if (std.mem.startsWith(u8, value, "builtin:")) {
                        plugin_kind = .builtin;
                        plugin_source = value["builtin:".len..];
                    } else if (std.mem.startsWith(u8, value, "registry:")) {
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
                } else if (std.mem.eql(u8, key, "dependencies")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const items_str = value[1 .. value.len - 1];
                        var items_it = std.mem.splitScalar(u8, items_str, ',');
                        while (items_it.next()) |item| {
                            const t = std.mem.trim(u8, item, " \t\"");
                            if (t.len > 0) try ws_member_deps.append(allocator, t);
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
                } else if (std.mem.eql(u8, key, "max_cpu")) {
                    task_max_cpu = std.fmt.parseInt(u32, value, 10) catch null;
                } else if (std.mem.eql(u8, key, "max_memory")) {
                    task_max_memory = types.parseMemoryBytes(value);
                } else if (std.mem.eql(u8, key, "matrix")) {
                    // Store raw inline table for matrix expansion at flush time.
                    // value has already had outer quotes stripped; re-use trimmed rhs.
                    const raw = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");
                    task_matrix_raw = raw;
                } else if (std.mem.eql(u8, key, "toolchain")) {
                    // Parse array: ["node@20.11", "python@3.12"]
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const tc_str = value[1 .. value.len - 1];
                        var tc_it = std.mem.splitScalar(u8, tc_str, ',');
                        while (tc_it.next()) |tc| {
                            const trimmed_tc = std.mem.trim(u8, tc, " \t\"");
                            if (trimmed_tc.len > 0) {
                                // Non-owning slice — addTaskImpl will dupe
                                try task_toolchain.append(allocator, trimmed_tc);
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
            if (task_matrix_raw) |mraw| {
                try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
            } else {
                try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items);
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
        const member_deps = try allocator.alloc([]const u8, ws_member_deps.items.len);
        var mdduped: usize = 0;
        errdefer {
            for (member_deps[0..mdduped]) |md| allocator.free(md);
            allocator.free(member_deps);
        }
        for (ws_member_deps.items, 0..) |md, i| {
            member_deps[i] = try allocator.dupe(u8, md);
            mdduped += 1;
        }
        config.workspace = Workspace{
            .members = members,
            .ignore = ignore,
            .member_dependencies = member_deps,
        };
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

    // Flush toolchain specs (Phase 5)
    if (tools_specs.items.len > 0) {
        const owned_tools = try allocator.alloc(toolchain_types.ToolSpec, tools_specs.items.len);
        @memcpy(owned_tools, tools_specs.items);
        tools_specs.clearRetainingCapacity();
        config.toolchains.tools = owned_tools;
    }

    // Flush final constraint (Phase 6)
    if (constraint_rule) |rule| {
        const owned_from = if (constraint_from) |f| try dupeConstraintScope(allocator, f) else null;
        errdefer if (owned_from) |*f| {
            var scope_copy = f.*;
            scope_copy.deinit(allocator);
        };
        const owned_to = if (constraint_to) |t| try dupeConstraintScope(allocator, t) else null;
        errdefer if (owned_to) |*t| {
            var scope_copy = t.*;
            scope_copy.deinit(allocator);
        };

        try constraint_list.append(allocator, types.Constraint{
            .rule = rule,
            .scope = if (constraint_scope) |s| try dupeConstraintScope(allocator, s) else .all,
            .from = owned_from,
            .to = owned_to,
            .allow = constraint_allow,
            .message = if (constraint_message) |m| try allocator.dupe(u8, m) else null,
        });
    }

    // Transfer constraints to config
    if (constraint_list.items.len > 0) {
        const owned_constraints = try allocator.alloc(types.Constraint, constraint_list.items.len);
        @memcpy(owned_constraints, constraint_list.items);
        constraint_list.clearRetainingCapacity();
        config.constraints = owned_constraints;
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

test "parse toolchain from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.dev]
        \\cmd = "npm run dev"
        \\toolchain = ["node@20.11.1", "python@3.12"]
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("dev").?;
    try std.testing.expectEqual(@as(usize, 2), task.toolchain.len);
    try std.testing.expectEqualStrings("node@20.11.1", task.toolchain[0]);
    try std.testing.expectEqualStrings("python@3.12", task.toolchain[1]);
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

test "parse builtin plugin from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[plugins.env]
        \\source = "builtin:env"
        \\config = { env_file = ".env" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 1), config.plugins.len);
    const p = config.plugins[0];
    try std.testing.expectEqualStrings("env", p.name);
    try std.testing.expectEqual(PluginSourceKind.builtin, p.kind);
    try std.testing.expectEqualStrings("env", p.source);
    try std.testing.expectEqual(@as(usize, 1), p.config.len);
    try std.testing.expectEqualStrings("env_file", p.config[0][0]);
    try std.testing.expectEqualStrings(".env", p.config[0][1]);
}

test "parse builtin notify plugin from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[plugins.notify]
        \\source = "builtin:notify"
        \\config = { webhook_url = "https://hooks.slack.com/abc", on_failure_only = "true" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 1), config.plugins.len);
    const p = config.plugins[0];
    try std.testing.expectEqual(PluginSourceKind.builtin, p.kind);
    try std.testing.expectEqualStrings("notify", p.source);
    try std.testing.expectEqual(@as(usize, 2), p.config.len);
}
