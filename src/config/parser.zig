const std = @import("std");
const types = @import("types.zig");
const matrix = @import("matrix.zig");
const conformance_types = @import("../conformance/types.zig");

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
    // Task tags (non-owning slices into content)
    var task_tags = std.ArrayList([]const u8){};
    defer task_tags.deinit(allocator);
    // Non-owning slices into content for env pairs — addTask dupes them
    var task_env = std.ArrayList([2][]const u8){};
    defer task_env.deinit(allocator);

    // Template parsing state — non-owning slices into content
    var current_template: ?[]const u8 = null;
    var template_cmd: ?[]const u8 = null;
    var template_cwd: ?[]const u8 = null;
    var template_desc: ?[]const u8 = null;
    var template_timeout_ms: ?u64 = null;
    var template_allow_failure: bool = false;
    var template_retry_max: u32 = 0;
    var template_retry_delay_ms: u64 = 0;
    var template_retry_backoff: bool = false;
    var template_condition: ?[]const u8 = null;
    var template_max_concurrent: u32 = 0;
    var template_cache: bool = false;
    var template_max_cpu: ?u32 = null;
    var template_max_memory: ?u64 = null;
    var template_deps = std.ArrayList([]const u8){};
    defer template_deps.deinit(allocator);
    var template_deps_serial = std.ArrayList([]const u8){};
    defer template_deps_serial.deinit(allocator);
    var template_env = std.ArrayList([2][]const u8){};
    defer template_env.deinit(allocator);
    var template_toolchain = std.ArrayList([]const u8){};
    defer template_toolchain.deinit(allocator);
    var template_params = std.ArrayList([]const u8){};
    defer template_params.deinit(allocator);

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
    var stage_approval: bool = false;
    var stage_on_failure: ?[]const u8 = null;

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

    // Metadata parsing state (Phase 6) — [metadata]
    var in_metadata: bool = false;
    var metadata_tags = std.ArrayList([]const u8){};
    defer metadata_tags.deinit(allocator);
    var metadata_deps = std.ArrayList([]const u8){};
    defer metadata_deps.deinit(allocator);

    // Cache parsing state (Phase 7) — [cache] and [cache.remote]
    var in_cache: bool = false;
    var in_cache_remote: bool = false;
    var cache_enabled: bool = false;
    var cache_local_dir: ?[]const u8 = null;
    var cache_remote_type: ?types.RemoteCacheType = null;
    var cache_remote_bucket: ?[]const u8 = null;
    var cache_remote_region: ?[]const u8 = null;
    var cache_remote_prefix: ?[]const u8 = null;
    var cache_remote_url: ?[]const u8 = null;
    var cache_remote_auth: ?[]const u8 = null;

    // Versioning parsing state (Phase 8) — [versioning]
    var in_versioning: bool = false;
    var versioning_mode: ?types.VersioningMode = null;
    var versioning_convention: ?types.VersioningConvention = null;

    // Conformance parsing state (Phase 8) — [conformance] and [[conformance.rules]]
    var in_conformance: bool = false;
    var in_conformance_rule: bool = false;
    var conformance_fail_on_warning: bool = false;
    var conformance_ignore = std.ArrayList([]const u8){};
    defer {
        for (conformance_ignore.items) |item| allocator.free(item);
        conformance_ignore.deinit(allocator);
    }
    var conformance_rules = std.ArrayList(conformance_types.ConformanceRule){};
    defer {
        for (conformance_rules.items) |*rule| rule.deinit();
        conformance_rules.deinit(allocator);
    }
    // Current conformance rule being parsed
    var current_rule_id: ?[]const u8 = null;
    var current_rule_type: ?conformance_types.RuleType = null;
    var current_rule_severity: conformance_types.Severity = .err;
    var current_rule_scope: ?[]const u8 = null;
    var current_rule_pattern: ?[]const u8 = null;
    var current_rule_message: ?[]const u8 = null;
    var current_rule_fixable: bool = false;
    var current_rule_config = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = current_rule_config.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        current_rule_config.deinit();
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
                const s_on_failure = if (stage_on_failure) |f| try allocator.dupe(u8, f) else null;
                errdefer if (s_on_failure) |f| allocator.free(f);
                const new_stage = Stage{
                    .name = try allocator.dupe(u8, sn),
                    .tasks = s_tasks,
                    .parallel = stage_parallel,
                    .fail_fast = stage_fail_fast,
                    .condition = s_cond,
                    .approval = stage_approval,
                    .on_failure = s_on_failure,
                };
                try workflow_stages.append(allocator, new_stage);
            }
            // Reset stage state
            stage_name = null;
            stage_tasks.clearRetainingCapacity();
            stage_parallel = true;
            stage_fail_fast = false;
            stage_approval = false;
            stage_on_failure = null;
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
                const s_on_failure = if (stage_on_failure) |f| try allocator.dupe(u8, f) else null;
                errdefer if (s_on_failure) |f| allocator.free(f);
                const new_stage = Stage{
                    .name = try allocator.dupe(u8, sn),
                    .tasks = s_tasks,
                    .parallel = stage_parallel,
                    .fail_fast = stage_fail_fast,
                    .condition = s_cond,
                    .approval = stage_approval,
                    .on_failure = s_on_failure,
                };
                try workflow_stages.append(allocator, new_stage);
                stage_name = null;
                stage_tasks.clearRetainingCapacity();
                stage_parallel = true;
                stage_fail_fast = false;
                stage_condition = null;
                stage_approval = false;
                stage_on_failure = null;
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
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items);
                    }
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_toolchain.clearRetainingCapacity();
                task_tags.clearRetainingCapacity();
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
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items);
                    }
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_toolchain.clearRetainingCapacity();
                task_tags.clearRetainingCapacity();
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
                const s_on_failure = if (stage_on_failure) |f| try allocator.dupe(u8, f) else null;
                errdefer if (s_on_failure) |f| allocator.free(f);
                try workflow_stages.append(allocator, Stage{ .name = try allocator.dupe(u8, sn), .tasks = s_tasks, .parallel = stage_parallel, .fail_fast = stage_fail_fast, .condition = s_cond, .approval = stage_approval, .on_failure = s_on_failure });
                stage_name = null; stage_tasks.clearRetainingCapacity(); stage_parallel = true; stage_fail_fast = false; stage_condition = null; stage_approval = false; stage_on_failure = null;
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
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity(); task_tags.clearRetainingCapacity();
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
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity(); task_tags.clearRetainingCapacity();
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
            in_metadata = false;
        } else if (std.mem.eql(u8, trimmed, "[metadata]")) {
            // Flush pending sections
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
            in_constraint = false;
            in_metadata = true;
            in_cache = false;
            in_cache_remote = false;
            in_versioning = false;
        } else if (std.mem.eql(u8, trimmed, "[cache]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_cache = true;
            in_cache_remote = false;
            in_versioning = false;
        } else if (std.mem.eql(u8, trimmed, "[cache.remote]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_cache = false;
            in_cache_remote = true;
            in_versioning = false;
        } else if (std.mem.eql(u8, trimmed, "[versioning]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_cache = false;
            in_cache_remote = false;
            in_versioning = true;
            in_conformance = false;
            in_conformance_rule = false;
        } else if (std.mem.eql(u8, trimmed, "[conformance]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_cache = false;
            in_cache_remote = false;
            in_versioning = false;
            in_conformance = true;
            in_conformance_rule = false;
        } else if (std.mem.eql(u8, trimmed, "[[conformance.rules]]")) {
            // Flush pending conformance rule
            if (in_conformance_rule) {
                if (current_rule_id) |id| {
                    if (current_rule_type) |rule_type| {
                        if (current_rule_scope) |scope| {
                            if (current_rule_message) |message| {
                                var rule = conformance_types.ConformanceRule.init(
                                    allocator,
                                    id,
                                    rule_type,
                                    current_rule_severity,
                                    scope,
                                    message,
                                );
                                rule.pattern = current_rule_pattern;
                                rule.fixable = current_rule_fixable;
                                rule.config = current_rule_config;
                                try conformance_rules.append(allocator, rule);
                                // Reset config for next rule
                                current_rule_config = std.StringHashMap([]const u8).init(allocator);
                            }
                        }
                    }
                }
            }
            // Start new conformance rule
            in_conformance = false;
            in_conformance_rule = true;
            current_rule_id = null;
            current_rule_type = null;
            current_rule_severity = .err;
            current_rule_scope = null;
            current_rule_pattern = null;
            current_rule_message = null;
            current_rule_fixable = false;
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
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items);
                    }
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity(); task_tags.clearRetainingCapacity();
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
                const s_on_failure = if (stage_on_failure) |f| try allocator.dupe(u8, f) else null;
                errdefer if (s_on_failure) |f| allocator.free(f);
                const new_stage = Stage{
                    .name = try allocator.dupe(u8, sn),
                    .tasks = s_tasks,
                    .parallel = stage_parallel,
                    .fail_fast = stage_fail_fast,
                    .condition = s_cond,
                    .approval = stage_approval,
                    .on_failure = s_on_failure,
                };
                try workflow_stages.append(allocator, new_stage);
                stage_name = null;
                stage_tasks.clearRetainingCapacity();
                stage_parallel = true;
                stage_fail_fast = false;
                stage_condition = null;
                stage_approval = false;
                stage_on_failure = null;
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
                        try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items);
                    }
                }
            }

            // Reset state — no freeing needed since these are non-owning slices
            task_deps.clearRetainingCapacity();
            task_deps_serial.clearRetainingCapacity();
            task_env.clearRetainingCapacity();
            task_toolchain.clearRetainingCapacity();
            task_tags.clearRetainingCapacity();
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
        } else if (std.mem.startsWith(u8, trimmed, "[templates.")) {
            // Flush pending template before starting a new one
            if (current_template) |tmpl_name| {
                if (template_cmd) |cmd| {
                    const tmpl_name_owned = try allocator.dupe(u8, tmpl_name);
                    errdefer allocator.free(tmpl_name_owned);

                    const tmpl_cmd_owned = try allocator.dupe(u8, cmd);
                    errdefer allocator.free(tmpl_cmd_owned);

                    const tmpl_cwd_owned = if (template_cwd) |cwd| try allocator.dupe(u8, cwd) else null;
                    errdefer if (tmpl_cwd_owned) |c| allocator.free(c);

                    const tmpl_desc_owned = if (template_desc) |desc| try allocator.dupe(u8, desc) else null;
                    errdefer if (tmpl_desc_owned) |d| allocator.free(d);

                    const tmpl_condition_owned = if (template_condition) |cond| try allocator.dupe(u8, cond) else null;
                    errdefer if (tmpl_condition_owned) |c| allocator.free(c);

                    // Dupe deps
                    const tmpl_deps_owned = try allocator.alloc([]const u8, template_deps.items.len);
                    var deps_duped: usize = 0;
                    errdefer {
                        for (tmpl_deps_owned[0..deps_duped]) |d| allocator.free(d);
                        allocator.free(tmpl_deps_owned);
                    }
                    for (template_deps.items, 0..) |d, i| {
                        tmpl_deps_owned[i] = try allocator.dupe(u8, d);
                        deps_duped += 1;
                    }

                    // Dupe deps_serial
                    const tmpl_deps_serial_owned = try allocator.alloc([]const u8, template_deps_serial.items.len);
                    var deps_serial_duped: usize = 0;
                    errdefer {
                        for (tmpl_deps_serial_owned[0..deps_serial_duped]) |d| allocator.free(d);
                        allocator.free(tmpl_deps_serial_owned);
                    }
                    for (template_deps_serial.items, 0..) |d, i| {
                        tmpl_deps_serial_owned[i] = try allocator.dupe(u8, d);
                        deps_serial_duped += 1;
                    }

                    // Dupe env
                    const tmpl_env_owned = try allocator.alloc([2][]const u8, template_env.items.len);
                    var env_duped: usize = 0;
                    errdefer {
                        for (tmpl_env_owned[0..env_duped]) |pair| {
                            allocator.free(pair[0]);
                            allocator.free(pair[1]);
                        }
                        allocator.free(tmpl_env_owned);
                    }
                    for (template_env.items, 0..) |pair, i| {
                        tmpl_env_owned[i][0] = try allocator.dupe(u8, pair[0]);
                        tmpl_env_owned[i][1] = try allocator.dupe(u8, pair[1]);
                        env_duped += 1;
                    }

                    // Dupe toolchain
                    const tmpl_toolchain_owned = try allocator.alloc([]const u8, template_toolchain.items.len);
                    var toolchain_duped: usize = 0;
                    errdefer {
                        for (tmpl_toolchain_owned[0..toolchain_duped]) |t| allocator.free(t);
                        allocator.free(tmpl_toolchain_owned);
                    }
                    for (template_toolchain.items, 0..) |t, i| {
                        tmpl_toolchain_owned[i] = try allocator.dupe(u8, t);
                        toolchain_duped += 1;
                    }

                    // Dupe params
                    const tmpl_params_owned = try allocator.alloc([]const u8, template_params.items.len);
                    var params_duped: usize = 0;
                    errdefer {
                        for (tmpl_params_owned[0..params_duped]) |p| allocator.free(p);
                        allocator.free(tmpl_params_owned);
                    }
                    for (template_params.items, 0..) |p, i| {
                        tmpl_params_owned[i] = try allocator.dupe(u8, p);
                        params_duped += 1;
                    }

                    const template = types.TaskTemplate{
                        .name = tmpl_name_owned,
                        .cmd = tmpl_cmd_owned,
                        .cwd = tmpl_cwd_owned,
                        .description = tmpl_desc_owned,
                        .deps = tmpl_deps_owned,
                        .deps_serial = tmpl_deps_serial_owned,
                        .env = tmpl_env_owned,
                        .timeout_ms = template_timeout_ms,
                        .allow_failure = template_allow_failure,
                        .retry_max = template_retry_max,
                        .retry_delay_ms = template_retry_delay_ms,
                        .retry_backoff = template_retry_backoff,
                        .condition = tmpl_condition_owned,
                        .max_concurrent = template_max_concurrent,
                        .cache = template_cache,
                        .max_cpu = template_max_cpu,
                        .max_memory = template_max_memory,
                        .toolchain = tmpl_toolchain_owned,
                        .params = tmpl_params_owned,
                    };

                    try config.templates.put(tmpl_name_owned, template);
                }
            }

            // Reset template state
            template_deps.clearRetainingCapacity();
            template_deps_serial.clearRetainingCapacity();
            template_env.clearRetainingCapacity();
            template_toolchain.clearRetainingCapacity();
            template_params.clearRetainingCapacity();
            template_cmd = null;
            template_cwd = null;
            template_desc = null;
            template_timeout_ms = null;
            template_allow_failure = false;
            template_retry_max = 0;
            template_retry_delay_ms = 0;
            template_retry_backoff = false;
            template_condition = null;
            template_max_concurrent = 0;
            template_cache = false;
            template_max_cpu = null;
            template_max_memory = null;

            const tmpl_start = "[templates.".len;
            const tmpl_end = std.mem.indexOf(u8, trimmed[tmpl_start..], "]") orelse continue;
            current_template = trimmed[tmpl_start..][0..tmpl_end];
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
                } else if (std.mem.eql(u8, key, "condition")) {
                    stage_condition = value;
                } else if (std.mem.eql(u8, key, "approval")) {
                    stage_approval = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "on_failure")) {
                    stage_on_failure = std.mem.trim(u8, value, " \t\"");
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
            } else if (in_metadata) {
                // Inside [metadata] — parse tags and dependencies arrays
                if (std.mem.eql(u8, key, "tags")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const items_str = value[1 .. value.len - 1];
                        var items_it = std.mem.splitScalar(u8, items_str, ',');
                        while (items_it.next()) |item| {
                            const t = std.mem.trim(u8, item, " \t\"");
                            if (t.len > 0) try metadata_tags.append(allocator, t);
                        }
                    }
                } else if (std.mem.eql(u8, key, "dependencies")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const items_str = value[1 .. value.len - 1];
                        var items_it = std.mem.splitScalar(u8, items_str, ',');
                        while (items_it.next()) |item| {
                            const t = std.mem.trim(u8, item, " \t\"");
                            if (t.len > 0) try metadata_deps.append(allocator, t);
                        }
                    }
                }
            } else if (in_cache) {
                // Inside [cache] — parse enabled and local_dir
                if (std.mem.eql(u8, key, "enabled")) {
                    cache_enabled = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "local_dir")) {
                    cache_local_dir = value;
                }
            } else if (in_cache_remote) {
                // Inside [cache.remote] — parse type, bucket, region, prefix, url, auth
                if (std.mem.eql(u8, key, "type")) {
                    cache_remote_type = types.RemoteCacheType.parse(value) catch null;
                } else if (std.mem.eql(u8, key, "bucket")) {
                    cache_remote_bucket = value;
                } else if (std.mem.eql(u8, key, "region")) {
                    cache_remote_region = value;
                } else if (std.mem.eql(u8, key, "prefix")) {
                    cache_remote_prefix = value;
                } else if (std.mem.eql(u8, key, "url")) {
                    cache_remote_url = value;
                } else if (std.mem.eql(u8, key, "auth")) {
                    cache_remote_auth = value;
                }
            } else if (in_versioning) {
                // Inside [versioning] — parse mode and convention
                if (std.mem.eql(u8, key, "mode")) {
                    versioning_mode = types.VersioningMode.fromString(value);
                } else if (std.mem.eql(u8, key, "convention")) {
                    versioning_convention = types.VersioningConvention.fromString(value);
                }
            } else if (in_conformance) {
                // Inside [conformance] — parse fail_on_warning and ignore
                if (std.mem.eql(u8, key, "fail_on_warning")) {
                    conformance_fail_on_warning = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "ignore")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const items_str = value[1 .. value.len - 1];
                        var items_it = std.mem.splitScalar(u8, items_str, ',');
                        while (items_it.next()) |item| {
                            const t = std.mem.trim(u8, item, " \t\"");
                            if (t.len > 0) {
                                const duped = try allocator.dupe(u8, t);
                                try conformance_ignore.append(allocator, duped);
                            }
                        }
                    }
                }
            } else if (in_conformance_rule) {
                // Inside [[conformance.rules]] — parse rule fields
                if (std.mem.eql(u8, key, "id")) {
                    current_rule_id = value;
                } else if (std.mem.eql(u8, key, "type")) {
                    if (std.mem.eql(u8, value, "import_pattern")) {
                        current_rule_type = .import_pattern;
                    } else if (std.mem.eql(u8, value, "file_naming")) {
                        current_rule_type = .file_naming;
                    } else if (std.mem.eql(u8, value, "file_size")) {
                        current_rule_type = .file_size;
                    } else if (std.mem.eql(u8, value, "directory_depth")) {
                        current_rule_type = .directory_depth;
                    } else if (std.mem.eql(u8, value, "file_extension")) {
                        current_rule_type = .file_extension;
                    }
                } else if (std.mem.eql(u8, key, "severity")) {
                    if (std.mem.eql(u8, value, "error")) {
                        current_rule_severity = .err;
                    } else if (std.mem.eql(u8, value, "warning")) {
                        current_rule_severity = .warning;
                    } else if (std.mem.eql(u8, value, "info")) {
                        current_rule_severity = .info;
                    }
                } else if (std.mem.eql(u8, key, "scope")) {
                    current_rule_scope = value;
                } else if (std.mem.eql(u8, key, "pattern")) {
                    current_rule_pattern = value;
                } else if (std.mem.eql(u8, key, "message")) {
                    current_rule_message = value;
                } else if (std.mem.eql(u8, key, "fixable")) {
                    current_rule_fixable = std.mem.eql(u8, value, "true");
                } else if (std.mem.startsWith(u8, key, "config.")) {
                    // Parse config.KEY = VALUE
                    const config_key = key[7..]; // Skip "config."
                    const config_key_duped = try allocator.dupe(u8, config_key);
                    const config_value_duped = try allocator.dupe(u8, value);
                    try current_rule_config.put(config_key_duped, config_value_duped);
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
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        // Parse inline table: { KEY = "value", FOO = "bar" }
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
                    } else if (std.mem.startsWith(u8, inner, "[") and std.mem.endsWith(u8, inner, "]")) {
                        // Parse array of pairs: [["KEY", "value"], ["FOO", "bar"]]
                        const array_str = inner[1 .. inner.len - 1];
                        var depth: usize = 0;
                        var pair_start: usize = 0;
                        var in_quotes = false;
                        for (array_str, 0..) |c, i| {
                            if (c == '"') in_quotes = !in_quotes;
                            if (in_quotes) continue;
                            if (c == '[') {
                                if (depth == 0) pair_start = i + 1;
                                depth += 1;
                            } else if (c == ']' and depth > 0) {
                                depth -= 1;
                                if (depth == 0) {
                                    const pair_str = array_str[pair_start..i];
                                    var parts_it = std.mem.splitScalar(u8, pair_str, ',');
                                    const key_part = parts_it.next() orelse continue;
                                    const val_part = parts_it.next() orelse continue;
                                    const env_key = std.mem.trim(u8, key_part, " \t\"");
                                    const env_val = std.mem.trim(u8, val_part, " \t\"");
                                    if (env_key.len > 0) {
                                        try task_env.append(allocator, .{ env_key, env_val });
                                    }
                                }
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
                } else if (std.mem.eql(u8, key, "tags")) {
                    // Parse array: ["build", "test", "ci"]
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const tags_str = value[1 .. value.len - 1];
                        var tags_it = std.mem.splitScalar(u8, tags_str, ',');
                        while (tags_it.next()) |tag| {
                            const trimmed_tag = std.mem.trim(u8, tag, " \t\"");
                            if (trimmed_tag.len > 0) {
                                // Non-owning slice — addTaskImpl will dupe
                                try task_tags.append(allocator, trimmed_tag);
                            }
                        }
                    }
                }
            } else if (current_template != null) {
                // Template-level key=value parsing (same as task but with params support)
                if (std.mem.eql(u8, key, "cmd")) {
                    template_cmd = value;
                } else if (std.mem.eql(u8, key, "cwd")) {
                    template_cwd = value;
                } else if (std.mem.eql(u8, key, "description")) {
                    template_desc = value;
                } else if (std.mem.eql(u8, key, "condition")) {
                    template_condition = value;
                } else if (std.mem.eql(u8, key, "timeout")) {
                    template_timeout_ms = parseDurationMs(value);
                } else if (std.mem.eql(u8, key, "allow_failure")) {
                    template_allow_failure = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "deps")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const deps_str = value[1 .. value.len - 1];
                        var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                        while (deps_it.next()) |dep| {
                            const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                            if (trimmed_dep.len > 0) {
                                try template_deps.append(allocator, trimmed_dep);
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
                                try template_deps_serial.append(allocator, trimmed_dep);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "env")) {
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const env_key = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const env_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (env_key.len > 0) {
                                try template_env.append(allocator, .{ env_key, env_val });
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "retry")) {
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const rkey = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const rval = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (std.mem.eql(u8, rkey, "max")) {
                                template_retry_max = std.fmt.parseInt(u32, rval, 10) catch 0;
                            } else if (std.mem.eql(u8, rkey, "delay")) {
                                template_retry_delay_ms = parseDurationMs(rval) orelse 0;
                            } else if (std.mem.eql(u8, rkey, "backoff")) {
                                template_retry_backoff = std.mem.eql(u8, rval, "exponential");
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "max_concurrent")) {
                    template_max_concurrent = std.fmt.parseInt(u32, value, 10) catch 0;
                } else if (std.mem.eql(u8, key, "cache")) {
                    template_cache = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "max_cpu")) {
                    template_max_cpu = std.fmt.parseInt(u32, value, 10) catch null;
                } else if (std.mem.eql(u8, key, "max_memory")) {
                    template_max_memory = types.parseMemoryBytes(value);
                } else if (std.mem.eql(u8, key, "toolchain")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const tc_str = value[1 .. value.len - 1];
                        var tc_it = std.mem.splitScalar(u8, tc_str, ',');
                        while (tc_it.next()) |tc| {
                            const trimmed_tc = std.mem.trim(u8, tc, " \t\"");
                            if (trimmed_tc.len > 0) {
                                try template_toolchain.append(allocator, trimmed_tc);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "params")) {
                    // Template-specific: required parameter names
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const params_str = value[1 .. value.len - 1];
                        var params_it = std.mem.splitScalar(u8, params_str, ',');
                        while (params_it.next()) |param| {
                            const trimmed_param = std.mem.trim(u8, param, " \t\"");
                            if (trimmed_param.len > 0) {
                                try template_params.append(allocator, trimmed_param);
                            }
                        }
                    }
                }
            }
        }
    }

    // Flush final pending stage (including approval and on_failure fields)
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
        const s_on_failure = if (stage_on_failure) |f| try allocator.dupe(u8, f) else null;
        errdefer if (s_on_failure) |f| allocator.free(f);
        const new_stage = Stage{
            .name = try allocator.dupe(u8, sn),
            .tasks = s_tasks,
            .parallel = stage_parallel,
            .fail_fast = stage_fail_fast,
            .condition = s_cond,
            .approval = stage_approval,
            .on_failure = s_on_failure,
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
                try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items);
            }
        }
    }

    // Flush final pending template
    if (current_template) |tmpl_name| {
        if (template_cmd) |cmd| {
            const tmpl_name_owned = try allocator.dupe(u8, tmpl_name);
            errdefer allocator.free(tmpl_name_owned);

            const tmpl_cmd_owned = try allocator.dupe(u8, cmd);
            errdefer allocator.free(tmpl_cmd_owned);

            const tmpl_cwd_owned = if (template_cwd) |cwd| try allocator.dupe(u8, cwd) else null;
            errdefer if (tmpl_cwd_owned) |c| allocator.free(c);

            const tmpl_desc_owned = if (template_desc) |desc| try allocator.dupe(u8, desc) else null;
            errdefer if (tmpl_desc_owned) |d| allocator.free(d);

            const tmpl_condition_owned = if (template_condition) |cond| try allocator.dupe(u8, cond) else null;
            errdefer if (tmpl_condition_owned) |c| allocator.free(c);

            const tmpl_deps_owned = try allocator.alloc([]const u8, template_deps.items.len);
            var deps_duped: usize = 0;
            errdefer {
                for (tmpl_deps_owned[0..deps_duped]) |d| allocator.free(d);
                allocator.free(tmpl_deps_owned);
            }
            for (template_deps.items, 0..) |d, i| {
                tmpl_deps_owned[i] = try allocator.dupe(u8, d);
                deps_duped += 1;
            }

            const tmpl_deps_serial_owned = try allocator.alloc([]const u8, template_deps_serial.items.len);
            var deps_serial_duped: usize = 0;
            errdefer {
                for (tmpl_deps_serial_owned[0..deps_serial_duped]) |d| allocator.free(d);
                allocator.free(tmpl_deps_serial_owned);
            }
            for (template_deps_serial.items, 0..) |d, i| {
                tmpl_deps_serial_owned[i] = try allocator.dupe(u8, d);
                deps_serial_duped += 1;
            }

            const tmpl_env_owned = try allocator.alloc([2][]const u8, template_env.items.len);
            var env_duped: usize = 0;
            errdefer {
                for (tmpl_env_owned[0..env_duped]) |pair| {
                    allocator.free(pair[0]);
                    allocator.free(pair[1]);
                }
                allocator.free(tmpl_env_owned);
            }
            for (template_env.items, 0..) |pair, i| {
                tmpl_env_owned[i][0] = try allocator.dupe(u8, pair[0]);
                tmpl_env_owned[i][1] = try allocator.dupe(u8, pair[1]);
                env_duped += 1;
            }

            const tmpl_toolchain_owned = try allocator.alloc([]const u8, template_toolchain.items.len);
            var toolchain_duped: usize = 0;
            errdefer {
                for (tmpl_toolchain_owned[0..toolchain_duped]) |t| allocator.free(t);
                allocator.free(tmpl_toolchain_owned);
            }
            for (template_toolchain.items, 0..) |t, i| {
                tmpl_toolchain_owned[i] = try allocator.dupe(u8, t);
                toolchain_duped += 1;
            }

            const tmpl_params_owned = try allocator.alloc([]const u8, template_params.items.len);
            var params_duped: usize = 0;
            errdefer {
                for (tmpl_params_owned[0..params_duped]) |p| allocator.free(p);
                allocator.free(tmpl_params_owned);
            }
            for (template_params.items, 0..) |p, i| {
                tmpl_params_owned[i] = try allocator.dupe(u8, p);
                params_duped += 1;
            }

            const template = types.TaskTemplate{
                .name = tmpl_name_owned,
                .cmd = tmpl_cmd_owned,
                .cwd = tmpl_cwd_owned,
                .description = tmpl_desc_owned,
                .deps = tmpl_deps_owned,
                .deps_serial = tmpl_deps_serial_owned,
                .env = tmpl_env_owned,
                .timeout_ms = template_timeout_ms,
                .allow_failure = template_allow_failure,
                .retry_max = template_retry_max,
                .retry_delay_ms = template_retry_delay_ms,
                .retry_backoff = template_retry_backoff,
                .condition = tmpl_condition_owned,
                .max_concurrent = template_max_concurrent,
                .cache = template_cache,
                .max_cpu = template_max_cpu,
                .max_memory = template_max_memory,
                .toolchain = tmpl_toolchain_owned,
                .params = tmpl_params_owned,
            };

            try config.templates.put(tmpl_name_owned, template);
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

    // Flush metadata if present
    if (in_metadata or metadata_tags.items.len > 0 or metadata_deps.items.len > 0) {
        const tags = try allocator.alloc([]const u8, metadata_tags.items.len);
        var tduped: usize = 0;
        errdefer {
            for (tags[0..tduped]) |t| allocator.free(t);
            if (tags.len > 0) allocator.free(tags);
        }
        for (metadata_tags.items, 0..) |t, i| {
            tags[i] = try allocator.dupe(u8, t);
            tduped += 1;
        }

        const deps = try allocator.alloc([]const u8, metadata_deps.items.len);
        var dduped: usize = 0;
        errdefer {
            for (deps[0..dduped]) |d| allocator.free(d);
            if (deps.len > 0) allocator.free(deps);
        }
        for (metadata_deps.items, 0..) |d, i| {
            deps[i] = try allocator.dupe(u8, d);
            dduped += 1;
        }

        config.metadata = types.Metadata{
            .tags = tags,
            .dependencies = deps,
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

    // Assemble cache config (Phase 7)
    config.cache.enabled = cache_enabled;
    config.cache.local_dir = if (cache_local_dir) |ld| try allocator.dupe(u8, ld) else null;
    if (cache_remote_type) |crt| {
        config.cache.remote = types.RemoteCacheConfig{
            .type = crt,
            .bucket = if (cache_remote_bucket) |b| try allocator.dupe(u8, b) else null,
            .region = if (cache_remote_region) |r| try allocator.dupe(u8, r) else null,
            .prefix = if (cache_remote_prefix) |p| try allocator.dupe(u8, p) else null,
            .url = if (cache_remote_url) |u| try allocator.dupe(u8, u) else null,
            .auth = if (cache_remote_auth) |a| try allocator.dupe(u8, a) else null,
        };
    }

    // Assign versioning config if parsed (Phase 8)
    if (versioning_mode != null and versioning_convention != null) {
        config.versioning = types.VersioningConfig.init(versioning_mode.?, versioning_convention.?);
    }

    // Flush pending conformance rule (if any)
    if (in_conformance_rule) {
        if (current_rule_id) |id| {
            if (current_rule_type) |rule_type| {
                if (current_rule_scope) |scope| {
                    if (current_rule_message) |message| {
                        var rule = conformance_types.ConformanceRule.init(
                            allocator,
                            id,
                            rule_type,
                            current_rule_severity,
                            scope,
                            message,
                        );
                        rule.pattern = current_rule_pattern;
                        rule.fixable = current_rule_fixable;
                        rule.config = current_rule_config;
                        try conformance_rules.append(allocator, rule);
                    }
                }
            }
        }
    }

    // Build conformance config
    if (conformance_rules.items.len > 0 or conformance_ignore.items.len > 0 or conformance_fail_on_warning) {
        config.conformance.fail_on_warning = conformance_fail_on_warning;
        config.conformance.ignore = try allocator.alloc([]const u8, conformance_ignore.items.len);
        @memcpy(config.conformance.ignore, conformance_ignore.items);
        config.conformance.rules = try allocator.alloc(conformance_types.ConformanceRule, conformance_rules.items.len);
        @memcpy(config.conformance.rules, conformance_rules.items);
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

test "parse tags from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\tags = ["build", "ci", "production"]
        \\
        \\[tasks.test]
        \\cmd = "zig build test"
        \\tags = ["test", "ci"]
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const build_task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(usize, 3), build_task.tags.len);
    try std.testing.expectEqualStrings("build", build_task.tags[0]);
    try std.testing.expectEqualStrings("ci", build_task.tags[1]);
    try std.testing.expectEqualStrings("production", build_task.tags[2]);

    const test_task = config.tasks.get("test").?;
    try std.testing.expectEqual(@as(usize, 2), test_task.tags.len);
    try std.testing.expectEqualStrings("test", test_task.tags[0]);
    try std.testing.expectEqualStrings("ci", test_task.tags[1]);
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

test "parse metadata section from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.test]
        \\cmd = "npm test"
        \\
        \\[metadata]
        \\tags = ["app", "frontend"]
        \\dependencies = ["packages/core", "packages/utils"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expect(config.metadata != null);
    const meta = config.metadata.?;
    try std.testing.expectEqual(@as(usize, 2), meta.tags.len);
    try std.testing.expectEqualStrings("app", meta.tags[0]);
    try std.testing.expectEqualStrings("frontend", meta.tags[1]);
    try std.testing.expectEqual(@as(usize, 2), meta.dependencies.len);
    try std.testing.expectEqualStrings("packages/core", meta.dependencies[0]);
    try std.testing.expectEqualStrings("packages/utils", meta.dependencies[1]);
}

test "metadata null when no metadata section" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "make"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expect(config.metadata == null);
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

test "parse cache config with local only" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[cache]
        \\enabled = true
        \\local_dir = ".cache"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expect(config.cache.enabled);
    try std.testing.expect(config.cache.local_dir != null);
    try std.testing.expectEqualStrings(".cache", config.cache.local_dir.?);
    try std.testing.expect(config.cache.remote == null);
}

test "parse cache config with S3 remote" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[cache]
        \\enabled = true
        \\local_dir = ".cache"
        \\
        \\[cache.remote]
        \\type = "s3"
        \\bucket = "my-cache-bucket"
        \\region = "us-east-1"
        \\prefix = "zr/"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expect(config.cache.enabled);
    try std.testing.expect(config.cache.local_dir != null);
    try std.testing.expectEqualStrings(".cache", config.cache.local_dir.?);
    try std.testing.expect(config.cache.remote != null);
    const remote = config.cache.remote.?;
    try std.testing.expectEqual(types.RemoteCacheType.s3, remote.type);
    try std.testing.expect(remote.bucket != null);
    try std.testing.expectEqualStrings("my-cache-bucket", remote.bucket.?);
    try std.testing.expect(remote.region != null);
    try std.testing.expectEqualStrings("us-east-1", remote.region.?);
    try std.testing.expect(remote.prefix != null);
    try std.testing.expectEqualStrings("zr/", remote.prefix.?);
}

test "parse cache config with HTTP remote" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[cache]
        \\enabled = true
        \\
        \\[cache.remote]
        \\type = "http"
        \\url = "https://cache.example.com"
        \\auth = "bearer:SECRET"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expect(config.cache.enabled);
    try std.testing.expect(config.cache.remote != null);
    const remote = config.cache.remote.?;
    try std.testing.expectEqual(types.RemoteCacheType.http, remote.type);
    try std.testing.expect(remote.url != null);
    try std.testing.expectEqualStrings("https://cache.example.com", remote.url.?);
    try std.testing.expect(remote.auth != null);
    try std.testing.expectEqualStrings("bearer:SECRET", remote.auth.?);
}

test "parse versioning config" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[versioning]
        \\mode = "independent"
        \\convention = "conventional"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expect(config.versioning != null);
    const versioning = config.versioning.?;
    try std.testing.expectEqual(types.VersioningMode.independent, versioning.mode);
    try std.testing.expectEqual(types.VersioningConvention.conventional, versioning.convention);
}

test "parse versioning config with fixed mode" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[versioning]
        \\mode = "fixed"
        \\convention = "manual"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();
    try std.testing.expect(config.versioning != null);
    const versioning = config.versioning.?;
    try std.testing.expectEqual(types.VersioningMode.fixed, versioning.mode);
    try std.testing.expectEqual(types.VersioningConvention.manual, versioning.convention);
}

test "parse workflow with approval and on_failure" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\
        \\[tasks.notify]
        \\cmd = "echo notify"
        \\
        \\[workflows.release]
        \\description = "Release with approval"
        \\
        \\[[workflows.release.stages]]
        \\name = "build"
        \\tasks = ["build"]
        \\parallel = true
        \\
        \\[[workflows.release.stages]]
        \\name = "deploy"
        \\tasks = ["deploy"]
        \\approval = true
        \\on_failure = "notify"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const wf = config.workflows.get("release").?;
    try std.testing.expectEqualStrings("release", wf.name);
    try std.testing.expectEqual(@as(usize, 2), wf.stages.len);

    // First stage: no approval, no on_failure
    const stage1 = wf.stages[0];
    try std.testing.expectEqualStrings("build", stage1.name);
    try std.testing.expectEqual(false, stage1.approval);
    try std.testing.expect(stage1.on_failure == null);

    // Second stage: approval=true, on_failure="notify"
    const stage2 = wf.stages[1];
    try std.testing.expectEqualStrings("deploy", stage2.name);
    try std.testing.expectEqual(true, stage2.approval);
    try std.testing.expect(stage2.on_failure != null);
    try std.testing.expectEqualStrings("notify", stage2.on_failure.?);
}
