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

/// Copy a ConditionalDep, allocating owned copies of strings.
fn copyConditionalDep(allocator: std.mem.Allocator, dep: *const types.ConditionalDep) !types.ConditionalDep {
    const task_owned = try allocator.dupe(u8, dep.task);
    errdefer allocator.free(task_owned);
    const condition_owned = try allocator.dupe(u8, dep.condition);
    errdefer allocator.free(condition_owned);
    return types.ConditionalDep{
        .task = task_owned,
        .condition = condition_owned,
    };
}

/// Copy a TaskHook, allocating owned copies of strings and nested structures.
fn copyTaskHook(allocator: std.mem.Allocator, hook: *const types.TaskHook) !types.TaskHook {
    const cmd_owned = try allocator.dupe(u8, hook.cmd);
    errdefer allocator.free(cmd_owned);
    const working_dir_owned = if (hook.working_dir) |wd| try allocator.dupe(u8, wd) else null;
    errdefer if (working_dir_owned) |wd| allocator.free(wd);

    // Copy env pairs
    const env_owned = try allocator.alloc([2][]const u8, hook.env.len);
    var env_duped: usize = 0;
    errdefer {
        for (env_owned[0..env_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(env_owned);
    }
    for (hook.env, 0..) |pair, i| {
        env_owned[i][0] = try allocator.dupe(u8, pair[0]);
        env_owned[i][1] = try allocator.dupe(u8, pair[1]);
        env_duped += 1;
    }

    return types.TaskHook{
        .cmd = cmd_owned,
        .point = hook.point,  // enum, no need to dupe
        .failure_strategy = hook.failure_strategy,  // enum, no need to dupe
        .working_dir = working_dir_owned,
        .env = env_owned,
    };
}

/// Helper function to flush a pending stage into workflow_stages.
/// If stage_name is null but there are tasks, auto-generates a stage name.
/// Returns true if a stage was flushed, false otherwise.
fn flushPendingStage(
    allocator: std.mem.Allocator,
    workflow_stages: *std.ArrayList(Stage),
    stage_name: ?[]const u8,
    stage_tasks: *std.ArrayList([]const u8),
    stage_parallel: bool,
    stage_fail_fast: bool,
    stage_condition: ?[]const u8,
    stage_approval: bool,
    stage_on_failure: ?[]const u8,
) !bool {
    // Only flush if we have a name OR if we have tasks (which need an auto-generated name)
    const should_flush = stage_name != null or stage_tasks.items.len > 0;
    if (!should_flush) return false;

    // Auto-generate name if missing
    const name_to_use = if (stage_name) |sn|
        sn
    else
        // This will be allocated and freed by the caller after use
        try std.fmt.allocPrint(allocator, "stage-{d}", .{workflow_stages.items.len + 1});

    // Allocate and dupe task names
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

    // Dupe optional fields
    const s_cond = if (stage_condition) |c| try allocator.dupe(u8, c) else null;
    errdefer if (s_cond) |c| allocator.free(c);
    const s_on_failure = if (stage_on_failure) |f| try allocator.dupe(u8, f) else null;
    errdefer if (s_on_failure) |f| allocator.free(f);

    const new_stage = Stage{
        .name = try allocator.dupe(u8, name_to_use),
        .tasks = s_tasks,
        .parallel = stage_parallel,
        .fail_fast = stage_fail_fast,
        .condition = s_cond,
        .approval = stage_approval,
        .on_failure = s_on_failure,
    };
    try workflow_stages.append(allocator, new_stage);

    // If we auto-generated the name, free it now (it was duped into the Stage)
    if (stage_name == null) {
        allocator.free(name_to_use);
    }

    return true;
}

/// Parse inline stages syntax: stages = [{ name = "...", tasks = [...] }, {...}]
/// Returns the number of stages parsed (0 if format is invalid).
fn parseInlineStages(
    allocator: std.mem.Allocator,
    workflow_stages: *std.ArrayList(Stage),
    value: []const u8,
) !usize {
    const trimmed = std.mem.trim(u8, value, " \t");
    if (!std.mem.startsWith(u8, trimmed, "[") or !std.mem.endsWith(u8, trimmed, "]")) {
        return 0; // Not an array
    }

    const inner = trimmed[1 .. trimmed.len - 1];
    var stage_count: usize = 0;

    // Parse array of inline tables: [{ ... }, { ... }]
    // We need to handle nested braces in tasks arrays
    var pos: usize = 0;
    while (pos < inner.len) {
        // Skip whitespace
        while (pos < inner.len and (inner[pos] == ' ' or inner[pos] == '\t' or inner[pos] == '\n' or inner[pos] == '\r')) {
            pos += 1;
        }
        if (pos >= inner.len) break;

        // Expect opening brace
        if (inner[pos] != '{') {
            if (inner[pos] == ',') {
                pos += 1;
                continue;
            }
            break; // Invalid format
        }

        // Find matching closing brace (handle nested braces in arrays)
        const start = pos;
        pos += 1;
        var depth: i32 = 1;
        while (pos < inner.len and depth > 0) {
            if (inner[pos] == '{') depth += 1;
            if (inner[pos] == '}') depth -= 1;
            pos += 1;
        }

        if (depth != 0) break; // Unmatched braces

        // Extract inline table: { name = "...", tasks = [...], ... }
        const table_str = inner[start + 1 .. pos - 1];

        // Parse fields from inline table
        var stage_name: ?[]const u8 = null;
        var stage_tasks = std.ArrayList([]const u8){};
        defer stage_tasks.deinit(allocator);
        var stage_parallel: bool = true;
        var stage_fail_fast: bool = false;
        var stage_condition: ?[]const u8 = null;
        var stage_approval: bool = false;
        var stage_on_failure: ?[]const u8 = null;

        // Split by comma, but respect nested brackets
        var field_start: usize = 0;
        var field_pos: usize = 0;
        var bracket_depth: i32 = 0;

        while (field_pos <= table_str.len) {
            const is_end = field_pos == table_str.len;
            const is_delimiter = !is_end and table_str[field_pos] == ',' and bracket_depth == 0;

            if (!is_end) {
                if (table_str[field_pos] == '[') bracket_depth += 1;
                if (table_str[field_pos] == ']') bracket_depth -= 1;
            }

            if (is_delimiter or is_end) {
                const field = std.mem.trim(u8, table_str[field_start..field_pos], " \t");
                if (field.len > 0) {
                    const eq_idx = std.mem.indexOf(u8, field, "=") orelse {
                        field_start = field_pos + 1;
                        field_pos += 1;
                        continue;
                    };
                    const field_key = std.mem.trim(u8, field[0..eq_idx], " \t");
                    const field_value = std.mem.trim(u8, field[eq_idx + 1 ..], " \t\"");

                    if (std.mem.eql(u8, field_key, "name")) {
                        stage_name = field_value;
                    } else if (std.mem.eql(u8, field_key, "tasks")) {
                        // Parse tasks array: ["task1", "task2"]
                        if (std.mem.startsWith(u8, field_value, "[") and std.mem.endsWith(u8, field_value, "]")) {
                            const tasks_str = field_value[1 .. field_value.len - 1];
                            var tasks_it = std.mem.splitScalar(u8, tasks_str, ',');
                            while (tasks_it.next()) |t| {
                                const trimmed_t = std.mem.trim(u8, t, " \t\"");
                                if (trimmed_t.len > 0) try stage_tasks.append(allocator, trimmed_t);
                            }
                        }
                    } else if (std.mem.eql(u8, field_key, "parallel")) {
                        stage_parallel = std.mem.eql(u8, field_value, "true");
                    } else if (std.mem.eql(u8, field_key, "fail_fast")) {
                        stage_fail_fast = std.mem.eql(u8, field_value, "true");
                    } else if (std.mem.eql(u8, field_key, "condition")) {
                        stage_condition = field_value;
                    } else if (std.mem.eql(u8, field_key, "approval")) {
                        stage_approval = std.mem.eql(u8, field_value, "true");
                    } else if (std.mem.eql(u8, field_key, "on_failure")) {
                        stage_on_failure = field_value;
                    }
                }
                field_start = field_pos + 1;
            }
            field_pos += 1;
        }

        // Flush this stage
        _ = try flushPendingStage(
            allocator,
            workflow_stages,
            stage_name,
            &stage_tasks,
            stage_parallel,
            stage_fail_fast,
            stage_condition,
            stage_approval,
            stage_on_failure,
        );
        stage_count += 1;
    }

    return stage_count;
}

pub const ParseError = error{
    MalformedSectionHeader,
    OutOfMemory,
};

/// Validate that a TOML section header is well-formed (has closing bracket).
/// Returns the content between start and the closing bracket.
/// Returns error.MalformedSectionHeader if closing bracket is missing.
fn validateSectionHeader(line: []const u8, prefix: []const u8) ParseError![]const u8 {
    if (!std.mem.startsWith(u8, line, prefix)) {
        return error.MalformedSectionHeader;
    }
    const start = prefix.len;
    const end = std.mem.indexOf(u8, line[start..], "]") orelse {
        // Missing closing bracket - return helpful error
        std.debug.print("Error: Malformed TOML section header: '{s}'\n", .{line});
        std.debug.print("  Expected closing bracket ']' after '{s}'\n", .{prefix});
        return error.MalformedSectionHeader;
    };
    return line[start..][0..end];
}

/// Duplicate dependency slice array (for workspace shared tasks, v1.63.0)
fn dupeDeps(allocator: std.mem.Allocator, deps: []const []const u8) ![][]const u8 {
    const result = try allocator.alloc([]const u8, deps.len);
    var duped: usize = 0;
    errdefer {
        for (result[0..duped]) |d| allocator.free(d);
        allocator.free(result);
    }
    for (deps, 0..) |dep, i| {
        result[i] = try allocator.dupe(u8, dep);
        duped += 1;
    }
    return result;
}

/// Duplicate environment variable pairs (for workspace shared tasks, v1.63.0)
fn dupeEnv(allocator: std.mem.Allocator, env: []const [2][]const u8) ![][2][]const u8 {
    const result = try allocator.alloc([2][]const u8, env.len);
    var duped: usize = 0;
    errdefer {
        for (result[0..duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(result);
    }
    for (env, 0..) |pair, i| {
        result[i][0] = try allocator.dupe(u8, pair[0]);
        errdefer allocator.free(result[i][0]);
        result[i][1] = try allocator.dupe(u8, pair[1]);
        duped += 1;
    }
    return result;
}

/// Add a workspace shared task to the HashMap (v1.63.0)
fn addWorkspaceSharedTask(
    shared_tasks: *std.StringHashMap(Task),
    allocator: std.mem.Allocator,
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: []const []const u8,
    deps_serial: []const []const u8,
    deps_optional: []const []const u8,
    env: []const [2][]const u8,
    timeout_ms: ?u64,
    allow_failure: bool,
) !void {
    const task_name = try allocator.dupe(u8, name);
    errdefer allocator.free(task_name);

    const task = Task{
        .name = task_name,
        .cmd = try allocator.dupe(u8, cmd),
        .cwd = if (cwd) |c| try allocator.dupe(u8, c) else null,
        .description = if (description) |d| desc_val: {
            const duped = try allocator.dupe(u8, d);
            break :desc_val types.TaskDescription{ .string = duped };
        } else null,
        .deps = try dupeDeps(allocator, deps),
        .deps_serial = try dupeDeps(allocator, deps_serial),
        .deps_optional = try dupeDeps(allocator, deps_optional),
        .env = try dupeEnv(allocator, env),
        .timeout_ms = timeout_ms,
        .allow_failure = allow_failure,
        // Use defaults for fields not typically set in shared tasks
        .deps_if = &.{},
        .retry_max = 0,
        .retry_delay_ms = 0,
        .retry_backoff = false,
        .retry_backoff_multiplier = null,
        .retry_jitter = false,
        .max_backoff_ms = null,
        .retry_on_codes = &.{},
        .retry_on_patterns = &.{},
        .condition = null,
        .skip_if = null,
        .output_if = null,
        .max_concurrent = 0,
        .cache = false,
        .max_cpu = null,
        .max_memory = null,
        .toolchain = &.{},
        .tags = &.{},
        .cpu_affinity = null,
        .numa_node = null,
        .watch = null,
        .hooks = &.{},
        .template = null,
        .params = &.{},
        .output_file = null,
        .output_mode = null,
        .remote = null,
        .remote_cwd = null,
        .remote_env = &.{},
        .concurrency_group = null,
    };

    try shared_tasks.put(task_name, task);
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
    // v1.47.0 retry strategy fields
    var task_retry_backoff_multiplier: ?f64 = null;
    var task_retry_jitter: bool = false;
    var task_max_backoff_ms: ?u64 = null;
    var task_retry_on_codes = std.ArrayList(u8){};
    defer task_retry_on_codes.deinit(allocator);
    var task_retry_on_patterns = std.ArrayList([]const u8){};
    defer task_retry_on_patterns.deinit(allocator);
    var task_condition: ?[]const u8 = null;
    var task_skip_if: ?[]const u8 = null;
    var task_output_if: ?[]const u8 = null;
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
    // Conditional dependencies (task + condition pairs) — non-owning slices
    var task_deps_if = std.ArrayList(types.ConditionalDep){};
    defer task_deps_if.deinit(allocator);
    // Optional dependencies (non-owning slices into content)
    var task_deps_optional = std.ArrayList([]const u8){};
    defer task_deps_optional.deinit(allocator);
    // Toolchain requirements (non-owning slices into content)
    var task_toolchain = std.ArrayList([]const u8){};
    defer task_toolchain.deinit(allocator);
    // Task tags (non-owning slices into content)
    var task_tags = std.ArrayList([]const u8){};
    defer task_tags.deinit(allocator);
    // CPU affinity (v1.13.0)
    var task_cpu_affinity = std.ArrayList(u32){};
    defer task_cpu_affinity.deinit(allocator);
    // NUMA node hint (v1.13.0)
    var task_numa_node: ?u32 = null;
    // Watch configuration (v1.17.0) — non-owning slices into content
    var task_watch_debounce_ms: ?u64 = null;
    var task_watch_patterns = std.ArrayList([]const u8){};
    defer task_watch_patterns.deinit(allocator);
    var task_watch_exclude_patterns = std.ArrayList([]const u8){};
    defer task_watch_exclude_patterns.deinit(allocator);
    var task_watch_mode: ?[]const u8 = null;
    var in_task_watch: bool = false;  // true when inside [tasks.X.watch] section
    // Non-owning slices into content for env pairs — addTask dupes them
    var task_env = std.ArrayList([2][]const u8){};
    defer task_env.deinit(allocator);
    // Template usage (v1.29.0) — non-owning slice for template name
    var task_template: ?[]const u8 = null;
    // Template parameters (v1.29.0) — non-owning slices into content for param pairs
    var task_params = std.ArrayList([2][]const u8){};
    defer task_params.deinit(allocator);
    // Output capture (v1.37.0) — non-owning slices for output file and mode
    var task_output_file: ?[]const u8 = null;
    var task_output_mode: ?[]const u8 = null;
    // Remote execution (v1.45.0) — non-owning slices for remote target and cwd
    var task_remote: ?[]const u8 = null;
    var task_remote_cwd: ?[]const u8 = null;
    var task_remote_env = std.ArrayList([2][]const u8){};
    defer task_remote_env.deinit(allocator);
    // Concurrency group (v1.62.0) — non-owning slice for group name
    var task_concurrency_group: ?[]const u8 = null;
    // Task mixins (v1.67.0) — non-owning slices for mixin names
    var task_mixins = std.ArrayList([]const u8){};
    defer task_mixins.deinit(allocator);
    // Task aliases (v1.73.0) — non-owning slices for alias names
    var task_aliases = std.ArrayList([]const u8){};
    defer task_aliases.deinit(allocator);
    // Task silent mode (v1.73.0)
    var task_silent: bool = false;
    // Task sources and generates (v1.74.0) — non-owning slices for patterns
    var task_sources = std.ArrayList([]const u8){};
    defer task_sources.deinit(allocator);
    var task_generates = std.ArrayList([]const u8){};
    defer task_generates.deinit(allocator);
    // Task env_file (v1.78.0) — non-owning slices for file paths
    var task_env_file = std.ArrayList([]const u8){};
    defer task_env_file.deinit(allocator);
    // Runtime task parameters (v1.75.0) — parsed from task_params array
    var task_task_params = std.ArrayList(types.TaskParam){};
    defer {
        for (task_task_params.items) |*param| param.deinit(allocator);
        task_task_params.deinit(allocator);
    }

    // Subsection state (v1.19.0) — for handling subsections appearing before main task
    var in_task_matrix: bool = false;  // true when inside [tasks.X.matrix] section
    var in_task_env: bool = false;     // true when inside [tasks.X.env] section
    var in_task_toolchain: bool = false; // true when inside [tasks.X.toolchain] section
    var in_task_hooks: bool = false;    // true when inside [[tasks.X.hooks]] section (v1.24.0)
    var in_task_retry: bool = false;    // true when inside [tasks.X.retry] section (v1.48.0)
    var pending_task_name: ?[]const u8 = null; // task name from subsection
    // Buffer for matrix TOML (will be content for task_matrix_raw when main task appears)
    var pending_matrix_buffer = std.ArrayList(u8){};
    defer pending_matrix_buffer.deinit(allocator);
    // Pending env/toolchain from subsections (non-owning slices for env, owned slices for toolchain)
    var pending_env = std.ArrayList([2][]const u8){};
    defer pending_env.deinit(allocator);
    var pending_toolchain = std.ArrayList([]const u8){};
    defer {
        // Free owned toolchain strings
        for (pending_toolchain.items) |tc| allocator.free(tc);
        pending_toolchain.deinit(allocator);
    }
    // Hooks parsing (v1.24.0) — owned data for task hooks
    var task_hooks = std.ArrayList(types.TaskHook){};
    defer {
        for (task_hooks.items) |*h| h.deinit(allocator);
        task_hooks.deinit(allocator);
    }
    var pending_hooks = std.ArrayList(types.TaskHook){};
    defer {
        for (pending_hooks.items) |*h| h.deinit(allocator);
        pending_hooks.deinit(allocator);
    }
    // Current hook being parsed in [[tasks.X.hooks]] section
    var current_hook_cmd: ?[]const u8 = null;
    var current_hook_point: ?[]const u8 = null;
    var current_hook_failure_strategy: ?[]const u8 = null;
    var current_hook_working_dir: ?[]const u8 = null;
    var current_hook_env = std.ArrayList([2][]const u8){};
    defer current_hook_env.deinit(allocator);


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
    // v1.47.0 retry strategy fields
    var template_retry_backoff_multiplier: ?f64 = null;
    var template_retry_jitter: bool = false;
    var template_max_backoff_ms: ?u64 = null;
    var template_retry_on_codes = std.ArrayList(u8){};
    defer template_retry_on_codes.deinit(allocator);
    var template_retry_on_patterns = std.ArrayList([]const u8){};
    defer template_retry_on_patterns.deinit(allocator);
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

    // Mixin parsing state (v1.67.0) — [mixins.NAME]
    var current_mixin: ?[]const u8 = null;
    var mixin_env = std.ArrayList([2][]const u8){};
    defer mixin_env.deinit(allocator);
    var mixin_deps = std.ArrayList([]const u8){};
    defer mixin_deps.deinit(allocator);
    var mixin_deps_serial = std.ArrayList([]const u8){};
    defer mixin_deps_serial.deinit(allocator);
    var mixin_deps_optional = std.ArrayList([]const u8){};
    defer mixin_deps_optional.deinit(allocator);
    var mixin_deps_if = std.ArrayList(types.ConditionalDep){};
    defer {
        for (mixin_deps_if.items) |*dep| dep.deinit(allocator);
        mixin_deps_if.deinit(allocator);
    }
    var mixin_tags = std.ArrayList([]const u8){};
    defer mixin_tags.deinit(allocator);
    var mixin_cmd: ?[]const u8 = null;
    var mixin_cwd: ?[]const u8 = null;
    var mixin_description: ?[]const u8 = null;
    var mixin_timeout_ms: ?u64 = null;
    var mixin_retry_max: u32 = 0;
    var mixin_retry_delay_ms: u64 = 0;
    var mixin_retry_backoff_multiplier: ?f64 = null;
    var mixin_retry_jitter: bool = false;
    var mixin_max_backoff_ms: ?u64 = null;
    var mixin_hooks = std.ArrayList(types.TaskHook){};
    defer {
        for (mixin_hooks.items) |*h| h.deinit(allocator);
        mixin_hooks.deinit(allocator);
    }
    var mixin_template: ?[]const u8 = null;
    var mixin_mixins = std.ArrayList([]const u8){};
    defer mixin_mixins.deinit(allocator);
    var in_mixin_env: bool = false;
    var in_mixin_hooks: bool = false;

    // Workflow parsing state — non-owning slices into content
    var current_workflow: ?[]const u8 = null;
    var workflow_desc: ?[]const u8 = null;
    var workflow_retry_budget: ?u32 = null;
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
    // Workspace shared tasks (v1.63.0) — [workspace.shared_tasks.NAME]
    var ws_shared_tasks = std.StringHashMap(Task).init(allocator);
    defer {
        var task_it = ws_shared_tasks.iterator();
        while (task_it.next()) |entry| {
            var task = entry.value_ptr.*;
            task.deinit(allocator);
        }
        ws_shared_tasks.deinit();
    }
    var ws_shared_task_name: ?[]const u8 = null; // Current shared task being parsed

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

    // Concurrency group parsing state (v1.62.0) — [concurrency_groups.X]
    var current_concurrency_group: ?[]const u8 = null;
    var cgroup_max_workers: ?u32 = null;

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

    // Imports parsing state (v1.55.0) — [imports]
    var in_imports: bool = false;
    var import_files = std.ArrayList([]const u8){};
    defer import_files.deinit(allocator);

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
    var cache_remote_compression: bool = true; // default true
    var cache_remote_incremental_sync: bool = false; // default false

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
            // Flush pending stage into workflow_stages (with auto-generated name if needed)
            _ = try flushPendingStage(
                allocator,
                &workflow_stages,
                stage_name,
                &stage_tasks,
                stage_parallel,
                stage_fail_fast,
                stage_condition,
                stage_approval,
                stage_on_failure,
            );
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
            // Flush pending stage (if any, with auto-generated name if needed)
            _ = try flushPendingStage(
                allocator,
                &workflow_stages,
                stage_name,
                &stage_tasks,
                stage_parallel,
                stage_fail_fast,
                stage_condition,
                stage_approval,
                stage_on_failure,
            );
            // Reset stage state
            stage_name = null;
            stage_tasks.clearRetainingCapacity();
            stage_parallel = true;
            stage_fail_fast = false;
            stage_condition = null;
            stage_approval = false;
            stage_on_failure = null;
            // Flush pending workflow (if any)
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items, workflow_retry_budget);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity();
            }
            // Flush pending task (if any — tasks may precede workflow sections)
            if (current_task) |task_name| {
                // Allow tasks without cmd if they have dependencies (dependency-only tasks)
                const cmd = task_cmd orelse "";
                if (task_matrix_raw) |mraw| {
                    try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                } else {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_deps_if.items, task_deps_optional.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_skip_if, task_output_if, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items, task_cpu_affinity.items, task_numa_node, task_watch_debounce_ms, task_watch_patterns.items, task_watch_exclude_patterns.items, task_watch_mode, task_hooks.items, task_template, task_params.items, task_output_file, task_output_mode, task_remote, task_remote_cwd, task_remote_env.items, task_mixins.items, task_aliases.items, task_silent, task_sources.items, task_generates.items, task_task_params.items, task_env_file.items);
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_deps_if.clearRetainingCapacity();
                task_deps_optional.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_toolchain.clearRetainingCapacity();
                task_tags.clearRetainingCapacity();
                task_params.clearRetainingCapacity();
                task_cmd = null;
                task_cwd = null;
                task_desc = null;
                task_timeout_ms = null;
                task_allow_failure = false;
                task_retry_max = 0;
                task_retry_delay_ms = 0;
                task_retry_backoff = false;
                task_retry_backoff_multiplier = null;
                task_retry_jitter = false;
                task_max_backoff_ms = null;
                task_retry_on_codes.clearRetainingCapacity();
                task_retry_on_patterns.clearRetainingCapacity();
                task_condition = null; task_skip_if = null; task_output_if = null;
                task_max_concurrent = 0;
                task_cache = false;
                task_max_cpu = null;
                task_max_memory = null;
                task_matrix_raw = null;
                task_template = null;
                task_output_file = null;
                task_output_mode = null;
                task_remote = null;
                task_remote_cwd = null;
                task_remote_env.clearRetainingCapacity();
                current_task = null;
            }
            // Parse new workflow name from "[workflows.X]"
            current_workflow = validateSectionHeader(trimmed, "[workflows.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };
            workflow_desc = null; workflow_retry_budget = null;
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
            const tm_idx = std.mem.indexOf(u8, trimmed, tasks_marker) orelse {
                std.debug.print("Error: Malformed profile task section: '{s}'\n", .{trimmed});
                std.debug.print("  Expected '.tasks.' in section header\n", .{});
                return error.MalformedSectionHeader;
            };
            const after_tasks = trimmed[tm_idx + tasks_marker.len ..];
            const rbracket = std.mem.indexOf(u8, after_tasks, "]") orelse {
                std.debug.print("Error: Malformed profile task section: '{s}'\n", .{trimmed});
                std.debug.print("  Expected closing bracket ']'\n", .{});
                return error.MalformedSectionHeader;
            };
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
                // Allow tasks without cmd if they have dependencies (dependency-only tasks)
                const cmd = task_cmd orelse "";
                if (task_matrix_raw) |mraw| {
                    try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                } else {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_deps_if.items, task_deps_optional.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_skip_if, task_output_if, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items, task_cpu_affinity.items, task_numa_node, task_watch_debounce_ms, task_watch_patterns.items, task_watch_exclude_patterns.items, task_watch_mode, task_hooks.items, task_template, task_params.items, task_output_file, task_output_mode, task_remote, task_remote_cwd, task_remote_env.items, task_mixins.items, task_aliases.items, task_silent, task_sources.items, task_generates.items, task_task_params.items, task_env_file.items);
                }
                task_deps.clearRetainingCapacity();
                task_deps_serial.clearRetainingCapacity();
                task_deps_if.clearRetainingCapacity();
                task_deps_optional.clearRetainingCapacity();
                task_env.clearRetainingCapacity();
                task_toolchain.clearRetainingCapacity();
                task_tags.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null;
                task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false;
                task_retry_backoff_multiplier = null; task_retry_jitter = false; task_max_backoff_ms = null;
                task_retry_on_codes.clearRetainingCapacity(); task_retry_on_patterns.clearRetainingCapacity();
                task_condition = null; task_skip_if = null; task_output_if = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null;
                task_output_file = null; task_output_mode = null; task_remote = null; task_remote_cwd = null; task_remote_env.clearRetainingCapacity();
                current_task = null;
            }
            // Flush pending workflow (if any)
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items, workflow_retry_budget);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity();
                current_workflow = null;
                workflow_desc = null; workflow_retry_budget = null;
            }

            // Parse new profile name: "[profiles.X]" → X
            current_profile = validateSectionHeader(trimmed, "[profiles.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };
        } else if (std.mem.eql(u8, trimmed, "[workspace]")) {
            // Flush pending task/workflow/profile contexts
            _ = try flushPendingStage(
                allocator,
                &workflow_stages,
                stage_name,
                &stage_tasks,
                stage_parallel,
                stage_fail_fast,
                stage_condition,
                stage_approval,
                stage_on_failure,
            );
            stage_name = null;
            stage_tasks.clearRetainingCapacity();
            stage_parallel = true;
            stage_fail_fast = false;
            stage_condition = null;
            stage_approval = false;
            stage_on_failure = null;
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items, workflow_retry_budget);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity(); current_workflow = null; workflow_desc = null; workflow_retry_budget = null;
            }
            if (current_task) |task_name| {
                // Allow tasks without cmd if they have dependencies (dependency-only tasks)
                const cmd = task_cmd orelse "";
                if (task_matrix_raw) |mraw| {
                    try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                } else {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_deps_if.items, task_deps_optional.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_skip_if, task_output_if, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items, task_cpu_affinity.items, task_numa_node, task_watch_debounce_ms, task_watch_patterns.items, task_watch_exclude_patterns.items, task_watch_mode, task_hooks.items, task_template, task_params.items, task_output_file, task_output_mode, task_remote, task_remote_cwd, task_remote_env.items, task_mixins.items, task_aliases.items, task_silent, task_sources.items, task_generates.items, task_task_params.items, task_env_file.items);
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_deps_if.clearRetainingCapacity(); task_deps_optional.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity(); task_tags.clearRetainingCapacity(); task_sources.clearRetainingCapacity(); task_generates.clearRetainingCapacity(); for (task_task_params.items) |*p| p.deinit(allocator); task_task_params.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false;
                task_retry_backoff_multiplier = null; task_retry_jitter = false; task_max_backoff_ms = null;
                task_retry_on_codes.clearRetainingCapacity(); task_retry_on_patterns.clearRetainingCapacity();
                task_condition = null; task_skip_if = null; task_output_if = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null;
                task_output_file = null; task_output_mode = null; task_remote = null; task_remote_cwd = null; task_remote_env.clearRetainingCapacity();
                current_task = null;
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
        } else if (std.mem.startsWith(u8, trimmed, "[workspace.shared_tasks.")) {
            // Flush pending workspace shared task before starting new one (v1.63.0)
            if (ws_shared_task_name) |task_name| {
                const cmd = task_cmd orelse "";
                try addWorkspaceSharedTask(
                    &ws_shared_tasks,
                    allocator,
                    task_name,
                    cmd,
                    task_cwd,
                    task_desc,
                    task_deps.items,
                    task_deps_serial.items,
                    task_deps_optional.items,
                    task_env.items,
                    task_timeout_ms,
                    task_allow_failure,
                );
            }
            // Reset task state
            task_deps.clearRetainingCapacity();
            task_deps_serial.clearRetainingCapacity();
            task_deps_optional.clearRetainingCapacity();
            task_env.clearRetainingCapacity();
            task_cmd = null;
            task_cwd = null;
            task_desc = null;
            task_timeout_ms = null;
            task_allow_failure = false;

            // Extract task name: "[workspace.shared_tasks.NAME]" → NAME
            ws_shared_task_name = validateSectionHeader(trimmed, "[workspace.shared_tasks.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };
            in_workspace = false; // Not parsing workspace top-level fields
        } else if (std.mem.eql(u8, trimmed, "[tools]")) {
            // Flush pending sections
            if (current_task) |task_name| {
                // Allow tasks without cmd if they have dependencies (dependency-only tasks)
                const cmd = task_cmd orelse "";
                if (task_matrix_raw) |mraw| {
                    try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                } else {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_deps_if.items, task_deps_optional.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_skip_if, task_output_if, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items, task_cpu_affinity.items, task_numa_node, task_watch_debounce_ms, task_watch_patterns.items, task_watch_exclude_patterns.items, task_watch_mode, task_hooks.items, task_template, task_params.items, task_output_file, task_output_mode, task_remote, task_remote_cwd, task_remote_env.items, task_mixins.items, task_aliases.items, task_silent, task_sources.items, task_generates.items, task_task_params.items, task_env_file.items);
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_deps_if.clearRetainingCapacity(); task_deps_optional.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity(); task_tags.clearRetainingCapacity(); task_sources.clearRetainingCapacity(); task_generates.clearRetainingCapacity(); for (task_task_params.items) |*p| p.deinit(allocator); task_task_params.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false;
                task_retry_backoff_multiplier = null; task_retry_jitter = false; task_max_backoff_ms = null;
                task_retry_on_codes.clearRetainingCapacity(); task_retry_on_patterns.clearRetainingCapacity();
                task_condition = null; task_skip_if = null; task_output_if = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null;
                task_output_file = null; task_output_mode = null; task_remote = null; task_remote_cwd = null; task_remote_env.clearRetainingCapacity();
                current_task = null;
            }
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items, workflow_retry_budget);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity(); current_workflow = null; workflow_desc = null; workflow_retry_budget = null;
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
            in_imports = false;
            in_cache = false;
            in_cache_remote = false;
            in_versioning = false;
        } else if (std.mem.eql(u8, trimmed, "[imports]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_imports = true;
            in_cache = false;
            in_cache_remote = false;
            in_versioning = false;
            in_conformance = false;
        } else if (std.mem.eql(u8, trimmed, "[cache]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_imports = false;
            in_cache = true;
            in_cache_remote = false;
            in_versioning = false;
            in_conformance = false;
        } else if (std.mem.eql(u8, trimmed, "[cache.remote]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_imports = false;
            in_cache = false;
            in_cache_remote = true;
            in_versioning = false;
            in_conformance = false;
        } else if (std.mem.eql(u8, trimmed, "[versioning]")) {
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            in_metadata = false;
            in_imports = false;
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
            in_imports = false;
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
                // Allow tasks without cmd if they have dependencies (dependency-only tasks)
                const cmd = task_cmd orelse "";
                if (task_matrix_raw) |mraw| {
                    try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                } else {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_deps_if.items, task_deps_optional.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_skip_if, task_output_if, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items, task_cpu_affinity.items, task_numa_node, task_watch_debounce_ms, task_watch_patterns.items, task_watch_exclude_patterns.items, task_watch_mode, task_hooks.items, task_template, task_params.items, task_output_file, task_output_mode, task_remote, task_remote_cwd, task_remote_env.items, task_mixins.items, task_aliases.items, task_silent, task_sources.items, task_generates.items, task_task_params.items, task_env_file.items);
                }
                task_deps.clearRetainingCapacity(); task_deps_serial.clearRetainingCapacity(); task_deps_if.clearRetainingCapacity(); task_deps_optional.clearRetainingCapacity(); task_env.clearRetainingCapacity(); task_toolchain.clearRetainingCapacity(); task_tags.clearRetainingCapacity(); task_sources.clearRetainingCapacity(); task_generates.clearRetainingCapacity(); for (task_task_params.items) |*p| p.deinit(allocator); task_task_params.clearRetainingCapacity();
                task_cmd = null; task_cwd = null; task_desc = null; task_timeout_ms = null; task_allow_failure = false;
                task_retry_max = 0; task_retry_delay_ms = 0; task_retry_backoff = false;
                task_retry_backoff_multiplier = null; task_retry_jitter = false; task_max_backoff_ms = null;
                task_retry_on_codes.clearRetainingCapacity(); task_retry_on_patterns.clearRetainingCapacity();
                task_condition = null; task_skip_if = null; task_output_if = null; task_max_concurrent = 0; task_cache = false; task_max_cpu = null; task_max_memory = null; task_matrix_raw = null;
                task_output_file = null; task_output_mode = null; task_remote = null; task_remote_cwd = null; task_remote_env.clearRetainingCapacity();
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
            current_plugin_name = validateSectionHeader(trimmed, "[plugins.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };
        } else if (std.mem.startsWith(u8, trimmed, "[concurrency_groups.") and !std.mem.startsWith(u8, trimmed, "[[")) {
            // Section: [concurrency_groups.X] — v1.62.0 concurrency group definition
            in_workspace = false;
            in_tools = false;
            in_constraint = false;
            // Flush pending concurrency group (if any)
            if (current_concurrency_group) |cgn| {
                const cg = types.ConcurrencyGroup{
                    .name = try allocator.dupe(u8, cgn),
                    .max_workers = cgroup_max_workers,
                };
                try config.concurrency_groups.put(try allocator.dupe(u8, cgn), cg);
                current_concurrency_group = null;
                cgroup_max_workers = null;
            }
            // Parse new concurrency group name: "[concurrency_groups.X]" → X
            current_concurrency_group = validateSectionHeader(trimmed, "[concurrency_groups.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };
        } else if (std.mem.startsWith(u8, trimmed, "[tasks.") and std.mem.indexOf(u8, trimmed, ".watch]") != null) {
            // Section: [tasks.X.watch] — watch configuration for task X (v1.17.0)
            in_workspace = false;
            in_cache = false;
            in_cache_remote = false;

            // Extract task name: "[tasks.X.watch]" → X
            const watch_marker = ".watch]";
            const watch_idx = std.mem.indexOf(u8, trimmed, watch_marker) orelse return error.MalformedSectionHeader;

            // Check if task name would be empty (e.g., [tasks.watch])
            if (watch_idx <= "[tasks.".len) {
                std.debug.print("Error: Invalid section header. Tasks cannot be named 'watch', 'env', 'matrix', 'toolchain', or 'hooks' as these are reserved for subsections.\n", .{});
                return error.ReservedTaskName;
            }

            const before_watch = trimmed["[tasks.".len .. watch_idx];

            // Verify we're currently in this task's context
            if (current_task) |task_name| {
                if (!std.mem.eql(u8, task_name, before_watch)) {
                    std.debug.print("Error: [tasks.{s}.watch] must follow [tasks.{s}]\n", .{ before_watch, before_watch });
                    return error.MalformedSectionHeader;
                }
            } else {
                std.debug.print("Error: [tasks.{s}.watch] must follow [tasks.{s}]\n", .{ before_watch, before_watch });
                return error.MalformedSectionHeader;
            }

            in_task_watch = true;
        } else if (std.mem.startsWith(u8, trimmed, "[tasks.") and std.mem.indexOf(u8, trimmed, ".retry]") != null) {
            // Section: [tasks.X.retry] — retry configuration for task X (v1.48.0)
            in_workspace = false;
            in_cache = false;
            in_cache_remote = false;
            in_task_watch = false;

            // Extract task name: "[tasks.X.retry]" → X
            const retry_marker = ".retry]";
            const retry_idx = std.mem.indexOf(u8, trimmed, retry_marker) orelse return error.MalformedSectionHeader;

            // Check if task name would be empty (e.g., [tasks.retry])
            if (retry_idx <= "[tasks.".len) {
                std.debug.print("Error: Invalid section header. Tasks cannot be named 'watch', 'env', 'matrix', 'toolchain', 'hooks', or 'retry' as these are reserved for subsections.\n", .{});
                return error.ReservedTaskName;
            }

            const before_retry = trimmed["[tasks.".len .. retry_idx];

            // Verify we're currently in this task's context
            if (current_task) |task_name| {
                if (!std.mem.eql(u8, task_name, before_retry)) {
                    std.debug.print("Error: [tasks.{s}.retry] must follow [tasks.{s}]\n", .{ before_retry, before_retry });
                    return error.MalformedSectionHeader;
                }
            } else {
                std.debug.print("Error: [tasks.{s}.retry] must follow [tasks.{s}]\n", .{ before_retry, before_retry });
                return error.MalformedSectionHeader;
            }

            in_task_retry = true;
        } else if (std.mem.startsWith(u8, trimmed, "[tasks.") and std.mem.indexOf(u8, trimmed, ".matrix]") != null) {
            // Section: [tasks.X.matrix] — matrix configuration for task X (v1.19.0)
            in_workspace = false;
            in_cache = false;
            in_cache_remote = false;
            in_task_watch = false;
            in_task_retry = false;

            // Extract task name: "[tasks.X.matrix]" → X
            const matrix_marker = ".matrix]";
            const matrix_idx = std.mem.indexOf(u8, trimmed, matrix_marker) orelse return error.MalformedSectionHeader;

            // Check if task name would be empty (e.g., [tasks.matrix])
            if (matrix_idx <= "[tasks.".len) {
                std.debug.print("Error: Invalid section header. Tasks cannot be named 'watch', 'env', 'matrix', 'toolchain', or 'hooks' as these are reserved for subsections.\n", .{});
                return error.ReservedTaskName;
            }

            const before_matrix = trimmed["[tasks.".len .. matrix_idx];

            // Store the task name for when we see the main [tasks.X] section
            pending_task_name = before_matrix;
            in_task_matrix = true;
            in_task_env = false;
            in_task_toolchain = false;
            in_task_retry = false;
        } else if (std.mem.startsWith(u8, trimmed, "[tasks.") and std.mem.indexOf(u8, trimmed, ".env]") != null) {
            // Section: [tasks.X.env] — env configuration for task X (v1.19.0)
            in_workspace = false;
            in_cache = false;
            in_cache_remote = false;
            in_task_watch = false;

            // Extract task name: "[tasks.X.env]" → X
            const env_marker = ".env]";
            const env_idx = std.mem.indexOf(u8, trimmed, env_marker) orelse return error.MalformedSectionHeader;

            // Check if task name would be empty (e.g., [tasks.env])
            if (env_idx <= "[tasks.".len) {
                std.debug.print("Error: Invalid section header. Tasks cannot be named 'watch', 'env', 'matrix', 'toolchain', or 'hooks' as these are reserved for subsections.\n", .{});
                return error.ReservedTaskName;
            }

            const before_env = trimmed["[tasks.".len .. env_idx];

            // Store the task name for when we see the main [tasks.X] section
            pending_task_name = before_env;
            in_task_env = true;
            in_task_matrix = false;
            in_task_toolchain = false;
            in_task_retry = false;
        } else if (std.mem.startsWith(u8, trimmed, "[tasks.") and std.mem.indexOf(u8, trimmed, ".toolchain]") != null) {
            // Section: [tasks.X.toolchain] — toolchain configuration for task X (v1.19.0)
            in_workspace = false;
            in_cache = false;
            in_cache_remote = false;
            in_task_watch = false;

            // Extract task name: "[tasks.X.toolchain]" → X
            const toolchain_marker = ".toolchain]";
            const toolchain_idx = std.mem.indexOf(u8, trimmed, toolchain_marker) orelse return error.MalformedSectionHeader;

            // Check if task name would be empty (e.g., [tasks.toolchain])
            if (toolchain_idx <= "[tasks.".len) {
                std.debug.print("Error: Invalid section header. Tasks cannot be named 'watch', 'env', 'matrix', 'toolchain', or 'hooks' as these are reserved for subsections.\n", .{});
                return error.ReservedTaskName;
            }

            const before_toolchain = trimmed["[tasks.".len .. toolchain_idx];

            // Store the task name for when we see the main [tasks.X] section
            pending_task_name = before_toolchain;
            in_task_toolchain = true;
            in_task_matrix = false;
            in_task_env = false;
            in_task_hooks = false;
            in_task_retry = false;
        } else if (std.mem.startsWith(u8, trimmed, "[[tasks.") and std.mem.indexOf(u8, trimmed, ".hooks]]") != null) {
            // Section: [[tasks.X.hooks]] — hook configuration for task X (v1.24.0)
            // This is an array-of-tables section, each entry is a hook

            // Flush previous hook if any
            // If we were in a hook section for the current task, flush to task_hooks
            // Otherwise, flush to pending_hooks for a future task
            const prev_hook_dest = if (in_task_hooks and current_task != null and pending_task_name == null) &task_hooks else &pending_hooks;
            try flushCurrentHook(
                allocator,
                prev_hook_dest,
                current_hook_cmd,
                current_hook_point,
                current_hook_failure_strategy,
                current_hook_working_dir,
                &current_hook_env,
            );

            in_workspace = false;
            in_cache = false;
            in_cache_remote = false;
            in_task_watch = false;

            // Extract task name: "[[tasks.X.hooks]]" → X
            const hooks_marker = ".hooks]]";
            const hooks_idx = std.mem.indexOf(u8, trimmed, hooks_marker) orelse return error.MalformedSectionHeader;

            // Check if task name would be empty (e.g., [[tasks.hooks]])
            if (hooks_idx <= "[[tasks.".len) {
                std.debug.print("Error: Invalid section header. Tasks cannot be named 'watch', 'env', 'matrix', 'toolchain', or 'hooks' as these are reserved for subsections.\n", .{});
                return error.ReservedTaskName;
            }

            const before_hooks = trimmed["[[tasks.".len .. hooks_idx];

            // Store the task name for when we see the main [tasks.X] section
            // UNLESS we're already in that task (hooks after task definition)
            if (current_task == null or !std.mem.eql(u8, current_task.?, before_hooks)) {
                pending_task_name = before_hooks;
            }
            in_task_hooks = true;
            in_task_matrix = false;
            in_task_env = false;
            in_task_toolchain = false;
            in_task_retry = false;

            // Reset current hook state for new hook entry
            current_hook_cmd = null;
            current_hook_point = null;
            current_hook_failure_strategy = null;
            current_hook_working_dir = null;
            current_hook_env.clearRetainingCapacity();
        } else if (std.mem.startsWith(u8, trimmed, "[tasks.")) {
            // Flush pending hook (if any) before transitioning to main task section (v1.24.0)
            try flushCurrentHook(
                allocator,
                &pending_hooks,
                current_hook_cmd,
                current_hook_point,
                current_hook_failure_strategy,
                current_hook_working_dir,
                &current_hook_env,
            );
            // Flush pending stage (if any, with auto-generated name if needed)
            _ = try flushPendingStage(
                allocator,
                &workflow_stages,
                stage_name,
                &stage_tasks,
                stage_parallel,
                stage_fail_fast,
                stage_condition,
                stage_approval,
                stage_on_failure,
            );
            stage_name = null;
            stage_tasks.clearRetainingCapacity();
            stage_parallel = true;
            stage_fail_fast = false;
            stage_condition = null;
            stage_approval = false;
            stage_on_failure = null;
            // Flush pending workflow (if any)
            if (current_workflow) |wf_name_slice| {
                try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items, workflow_retry_budget);
                for (workflow_stages.items) |*s| s.deinit(allocator);
                workflow_stages.clearRetainingCapacity();
                current_workflow = null;
                workflow_desc = null; workflow_retry_budget = null;
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
                // Allow tasks without cmd if they have dependencies (dependency-only tasks)
                const cmd = task_cmd orelse "";
                if (task_matrix_raw) |mraw| {
                    try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
                } else {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_deps_if.items, task_deps_optional.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_skip_if, task_output_if, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items, task_cpu_affinity.items, task_numa_node, task_watch_debounce_ms, task_watch_patterns.items, task_watch_exclude_patterns.items, task_watch_mode, task_hooks.items, task_template, task_params.items, task_output_file, task_output_mode, task_remote, task_remote_cwd, task_remote_env.items, task_mixins.items, task_aliases.items, task_silent, task_sources.items, task_generates.items, task_task_params.items, task_env_file.items);
                }
            }

            // Reset state — no freeing needed since these are non-owning slices
            task_deps.clearRetainingCapacity();
            task_deps_serial.clearRetainingCapacity();
            task_deps_if.clearRetainingCapacity();
            task_deps_optional.clearRetainingCapacity();
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
            task_retry_backoff_multiplier = null;
            task_retry_jitter = false;
            task_max_backoff_ms = null;
            task_retry_on_codes.clearRetainingCapacity();
            task_retry_on_patterns.clearRetainingCapacity();
            task_condition = null;
            task_skip_if = null;
            task_output_if = null;
            task_max_concurrent = 0;
            task_cache = false;
            task_max_cpu = null;
            task_max_memory = null;
            task_matrix_raw = null;
            task_cpu_affinity.clearRetainingCapacity();
            task_numa_node = null;
            task_watch_debounce_ms = null;
            task_watch_patterns.clearRetainingCapacity();
            task_watch_exclude_patterns.clearRetainingCapacity();
            task_watch_mode = null;

            in_workspace = false;
            in_cache = false;
            in_task_watch = false;
            in_task_matrix = false;
            in_task_env = false;
            in_task_toolchain = false;
            in_task_hooks = false;
            in_task_retry = false;
            in_cache_remote = false;
            // Validate section header has closing bracket
            current_task = validateSectionHeader(trimmed, "[tasks.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };

            // If we have pending subsection data for this task, apply it now (v1.19.0)
            if (pending_task_name) |ptask| {
                if (std.mem.eql(u8, current_task.?, ptask)) {
                    // Apply pending matrix data if any
                    if (pending_matrix_buffer.items.len > 0) {
                        // Close the inline table
                        const writer = pending_matrix_buffer.writer(allocator);
                        try writer.writeAll(" }");
                        task_matrix_raw = pending_matrix_buffer.items;
                    }
                    // Apply pending env data
                    for (pending_env.items) |env_pair| {
                        try task_env.append(allocator, env_pair);
                    }
                    // Apply pending toolchain data (owned strings, will be freed by deferred cleanup)
                    for (pending_toolchain.items) |tc| {
                        try task_toolchain.append(allocator, tc);
                    }
                    // Apply pending hooks data (v1.24.0)
                    for (pending_hooks.items) |hook| {
                        try task_hooks.append(allocator, hook);
                    }
                    // Clear pending state (don't clear pending_toolchain, let defer free those strings)
                    pending_task_name = null;
                    pending_matrix_buffer.clearRetainingCapacity();
                    pending_env.clearRetainingCapacity();
                    pending_hooks.clearRetainingCapacity(); // hooks are moved, don't need to deinit
                    // Note: pending_toolchain items stay alive until parseToml returns, so task_toolchain references stay valid
                }
            }
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
            template_retry_backoff_multiplier = null;
            template_retry_jitter = false;
            template_max_backoff_ms = null;
            template_retry_on_codes.clearRetainingCapacity();
            template_retry_on_patterns.clearRetainingCapacity();
            template_condition = null;
            template_max_concurrent = 0;
            template_cache = false;
            template_max_cpu = null;
            template_max_memory = null;

            current_template = validateSectionHeader(trimmed, "[templates.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };
        } else if (std.mem.startsWith(u8, trimmed, "[mixins.")) {
            // Flush pending mixin before starting a new one
            if (current_mixin) |mixin_name| {
                const mixin_name_owned = try allocator.dupe(u8, mixin_name);
                errdefer allocator.free(mixin_name_owned);

                // Dupe env
                const mixin_env_owned = try allocator.alloc([2][]const u8, mixin_env.items.len);
                var env_duped: usize = 0;
                errdefer {
                    for (mixin_env_owned[0..env_duped]) |pair| {
                        allocator.free(pair[0]);
                        allocator.free(pair[1]);
                    }
                    allocator.free(mixin_env_owned);
                }
                for (mixin_env.items, 0..) |pair, i| {
                    mixin_env_owned[i][0] = try allocator.dupe(u8, pair[0]);
                    mixin_env_owned[i][1] = try allocator.dupe(u8, pair[1]);
                    env_duped += 1;
                }

                // Dupe deps
                const mixin_deps_owned = try allocator.alloc([]const u8, mixin_deps.items.len);
                var deps_duped: usize = 0;
                errdefer {
                    for (mixin_deps_owned[0..deps_duped]) |d| allocator.free(d);
                    allocator.free(mixin_deps_owned);
                }
                for (mixin_deps.items, 0..) |d, i| {
                    mixin_deps_owned[i] = try allocator.dupe(u8, d);
                    deps_duped += 1;
                }

                // Dupe deps_serial
                const mixin_deps_serial_owned = try allocator.alloc([]const u8, mixin_deps_serial.items.len);
                var deps_serial_duped: usize = 0;
                errdefer {
                    for (mixin_deps_serial_owned[0..deps_serial_duped]) |d| allocator.free(d);
                    allocator.free(mixin_deps_serial_owned);
                }
                for (mixin_deps_serial.items, 0..) |d, i| {
                    mixin_deps_serial_owned[i] = try allocator.dupe(u8, d);
                    deps_serial_duped += 1;
                }

                // Dupe deps_optional
                const mixin_deps_optional_owned = try allocator.alloc([]const u8, mixin_deps_optional.items.len);
                var deps_optional_duped: usize = 0;
                errdefer {
                    for (mixin_deps_optional_owned[0..deps_optional_duped]) |d| allocator.free(d);
                    allocator.free(mixin_deps_optional_owned);
                }
                for (mixin_deps_optional.items, 0..) |d, i| {
                    mixin_deps_optional_owned[i] = try allocator.dupe(u8, d);
                    deps_optional_duped += 1;
                }

                // Copy deps_if
                const mixin_deps_if_owned = try allocator.alloc(types.ConditionalDep, mixin_deps_if.items.len);
                var deps_if_duped: usize = 0;
                errdefer {
                    for (mixin_deps_if_owned[0..deps_if_duped]) |*d| d.deinit(allocator);
                    allocator.free(mixin_deps_if_owned);
                }
                for (mixin_deps_if.items, 0..) |dep, i| {
                    mixin_deps_if_owned[i] = try copyConditionalDep(allocator, &dep);
                    deps_if_duped += 1;
                }

                // Dupe tags
                const mixin_tags_owned = try allocator.alloc([]const u8, mixin_tags.items.len);
                var tags_duped: usize = 0;
                errdefer {
                    for (mixin_tags_owned[0..tags_duped]) |t| allocator.free(t);
                    allocator.free(mixin_tags_owned);
                }
                for (mixin_tags.items, 0..) |t, i| {
                    mixin_tags_owned[i] = try allocator.dupe(u8, t);
                    tags_duped += 1;
                }

                // Dupe optional string fields
                const mixin_cmd_owned = if (mixin_cmd) |cmd| try allocator.dupe(u8, cmd) else null;
                errdefer if (mixin_cmd_owned) |c| allocator.free(c);
                const mixin_cwd_owned = if (mixin_cwd) |cwd| try allocator.dupe(u8, cwd) else null;
                errdefer if (mixin_cwd_owned) |cwd| allocator.free(cwd);
                const mixin_desc_owned = if (mixin_description) |desc| try allocator.dupe(u8, desc) else null;
                errdefer if (mixin_desc_owned) |d| allocator.free(d);

                // Copy hooks
                const mixin_hooks_owned = try allocator.alloc(types.TaskHook, mixin_hooks.items.len);
                var hooks_duped: usize = 0;
                errdefer {
                    for (mixin_hooks_owned[0..hooks_duped]) |*h| h.deinit(allocator);
                    allocator.free(mixin_hooks_owned);
                }
                for (mixin_hooks.items, 0..) |hook, i| {
                    mixin_hooks_owned[i] = try copyTaskHook(allocator, &hook);
                    hooks_duped += 1;
                }

                // Dupe template
                const mixin_template_owned = if (mixin_template) |t| try allocator.dupe(u8, t) else null;
                errdefer if (mixin_template_owned) |t| allocator.free(t);

                // Dupe mixin names (nested mixins)
                const mixin_mixins_owned = try allocator.alloc([]const u8, mixin_mixins.items.len);
                var mixins_duped: usize = 0;
                errdefer {
                    for (mixin_mixins_owned[0..mixins_duped]) |m| allocator.free(m);
                    allocator.free(mixin_mixins_owned);
                }
                for (mixin_mixins.items, 0..) |m, i| {
                    mixin_mixins_owned[i] = try allocator.dupe(u8, m);
                    mixins_duped += 1;
                }

                const mixin = types.Mixin{
                    .name = mixin_name_owned,
                    .env = mixin_env_owned,
                    .deps = mixin_deps_owned,
                    .deps_serial = mixin_deps_serial_owned,
                    .deps_optional = mixin_deps_optional_owned,
                    .deps_if = mixin_deps_if_owned,
                    .tags = mixin_tags_owned,
                    .cmd = mixin_cmd_owned,
                    .cwd = mixin_cwd_owned,
                    .description = mixin_desc_owned,
                    .timeout_ms = mixin_timeout_ms,
                    .retry_max = mixin_retry_max,
                    .retry_delay_ms = mixin_retry_delay_ms,
                    .retry_backoff_multiplier = mixin_retry_backoff_multiplier,
                    .retry_jitter = mixin_retry_jitter,
                    .max_backoff_ms = mixin_max_backoff_ms,
                    .hooks = mixin_hooks_owned,
                    .template = mixin_template_owned,
                    .mixins = mixin_mixins_owned,
                };

                try config.mixins.put(mixin_name_owned, mixin);
            }

            // Reset mixin state
            mixin_env.clearRetainingCapacity();
            mixin_deps.clearRetainingCapacity();
            mixin_deps_serial.clearRetainingCapacity();
            mixin_deps_optional.clearRetainingCapacity();
            mixin_deps_if.clearRetainingCapacity();
            mixin_tags.clearRetainingCapacity();
            mixin_cmd = null;
            mixin_cwd = null;
            mixin_description = null;
            mixin_timeout_ms = null;
            mixin_retry_max = 0;
            mixin_retry_delay_ms = 0;
            mixin_retry_backoff_multiplier = null;
            mixin_retry_jitter = false;
            mixin_max_backoff_ms = null;
            mixin_hooks.clearRetainingCapacity();
            mixin_template = null;
            mixin_mixins.clearRetainingCapacity();
            in_mixin_env = false;
            in_mixin_hooks = false;

            current_mixin = validateSectionHeader(trimmed, "[mixins.") catch |err| {
                if (err == error.MalformedSectionHeader) return err;
                return err;
            };
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
                } else if (std.mem.eql(u8, key, "stages")) {
                    // Inline stages syntax: stages = [{ name = "...", tasks = [...] }, ...]
                    const parsed_count = try parseInlineStages(allocator, &workflow_stages, value);
                    if (parsed_count > 0) {
                        // Inline stages were parsed successfully
                        // No need to track stage state since stages are complete
                    }
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
                } else if (std.mem.eql(u8, key, "retry_budget") and stage_name == null) {
                    // Workflow-level retry budget (v1.30.0)
                    workflow_retry_budget = std.fmt.parseInt(u32, value, 10) catch null;
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
            } else if (current_concurrency_group != null and current_task == null and current_workflow == null and current_profile == null and current_plugin_name == null and !in_workspace) {
                // Inside [concurrency_groups.X] — parse max_workers (v1.62.0)
                if (std.mem.eql(u8, key, "max_workers")) {
                    cgroup_max_workers = std.fmt.parseInt(u32, value, 10) catch |err| {
                        std.debug.print("Error: Invalid max_workers value: {s}\n", .{value});
                        return err;
                    };
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
            } else if (in_imports) {
                // Inside [imports] — parse files array
                if (std.mem.eql(u8, key, "files")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const items_str = value[1 .. value.len - 1];
                        var items_it = std.mem.splitScalar(u8, items_str, ',');
                        while (items_it.next()) |item| {
                            const f = std.mem.trim(u8, item, " \t\"");
                            if (f.len > 0) try import_files.append(allocator, f);
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
                // Inside [cache.remote] — parse type, bucket, region, prefix, url, auth, compression, incremental_sync
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
                } else if (std.mem.eql(u8, key, "compression")) {
                    cache_remote_compression = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "incremental_sync")) {
                    cache_remote_incremental_sync = std.mem.eql(u8, value, "true");
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
            } else if (in_task_watch) {
                // Inside [tasks.X.watch] section (v1.17.0)
                if (std.mem.eql(u8, key, "debounce_ms")) {
                    const trimmed_val = std.mem.trim(u8, value, " \t\"");
                    task_watch_debounce_ms = std.fmt.parseInt(u64, trimmed_val, 10) catch null;
                } else if (std.mem.eql(u8, key, "debounce")) {
                    // Alternative: parse as duration (e.g., "300ms")
                    task_watch_debounce_ms = parseDurationMs(value);
                } else if (std.mem.eql(u8, key, "patterns")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const patterns_str = value[1 .. value.len - 1];
                        var patterns_it = std.mem.splitScalar(u8, patterns_str, ',');
                        while (patterns_it.next()) |pattern| {
                            const trimmed_pattern = std.mem.trim(u8, pattern, " \t\"");
                            if (trimmed_pattern.len > 0) {
                                try task_watch_patterns.append(allocator, trimmed_pattern);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "exclude_patterns")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const patterns_str = value[1 .. value.len - 1];
                        var patterns_it = std.mem.splitScalar(u8, patterns_str, ',');
                        while (patterns_it.next()) |pattern| {
                            const trimmed_pattern = std.mem.trim(u8, pattern, " \t\"");
                            if (trimmed_pattern.len > 0) {
                                try task_watch_exclude_patterns.append(allocator, trimmed_pattern);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "mode")) {
                    task_watch_mode = value;
                }
            } else if (in_task_matrix) {
                // Inside [tasks.X.matrix] section (v1.19.0)
                // Accumulate key=value pairs into pending_matrix_buffer as TOML inline table
                const writer = pending_matrix_buffer.writer(allocator);
                if (pending_matrix_buffer.items.len == 0) {
                    try writer.writeAll("{ ");
                } else {
                    try writer.writeAll(", ");
                }
                try writer.print("{s} = {s}", .{ key, trimmed[eq_idx + 1 ..] });
            } else if (in_task_env) {
                // Inside [tasks.X.env] section (v1.19.0)
                // Accumulate env key=value pairs into pending_env (non-owning slices into content)
                const env_key = key;
                const env_val = value;
                try pending_env.append(allocator, .{ env_key, env_val });
            } else if (in_task_toolchain) {
                // Inside [tasks.X.toolchain] section (v1.19.0)
                // Accumulate toolchain entries: key = "version" format
                // e.g., node = "20.11.1" → "node@20.11.1"
                const toolchain_kind = key;
                const toolchain_version = value;
                // Allocate owned string since we're constructing a new string not in original content
                var buf: [256]u8 = undefined;
                const formatted = try std.fmt.bufPrint(&buf, "{s}@{s}", .{ toolchain_kind, toolchain_version });
                const toolchain_entry = try allocator.dupe(u8, formatted);
                try pending_toolchain.append(allocator, toolchain_entry);
            } else if (in_task_hooks) {
                // Inside [[tasks.X.hooks]] section (v1.24.0)
                // Parse hook fields: cmd, point, failure_strategy, working_dir, env
                if (std.mem.eql(u8, key, "cmd")) {
                    current_hook_cmd = value;
                } else if (std.mem.eql(u8, key, "point")) {
                    current_hook_point = value;
                } else if (std.mem.eql(u8, key, "failure_strategy")) {
                    current_hook_failure_strategy = value;
                } else if (std.mem.eql(u8, key, "working_dir")) {
                    current_hook_working_dir = value;
                } else if (std.mem.eql(u8, key, "env")) {
                    // Parse inline table: env = { KEY = "value", FOO = "bar" }
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const env_key = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const env_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (env_key.len > 0) {
                                try current_hook_env.append(allocator, .{ env_key, env_val });
                            }
                        }
                    }
                } else {
                    // Unknown field, ignore
                }
            } else if (in_task_retry) {
                // Inside [tasks.X.retry] section (v1.48.0)
                if (std.mem.eql(u8, key, "max")) {
                    const trimmed_val = std.mem.trim(u8, value, " \t\"");
                    task_retry_max = std.fmt.parseInt(u32, trimmed_val, 10) catch 0;
                } else if (std.mem.eql(u8, key, "delay_ms")) {
                    const trimmed_val = std.mem.trim(u8, value, " \t\"");
                    task_retry_delay_ms = std.fmt.parseInt(u64, trimmed_val, 10) catch 0;
                } else if (std.mem.eql(u8, key, "delay")) {
                    // Alternative: parse as duration (e.g., "100ms")
                    task_retry_delay_ms = parseDurationMs(value) orelse 0;
                } else if (std.mem.eql(u8, key, "backoff")) {
                    task_retry_backoff = std.mem.eql(u8, value, "exponential");
                } else if (std.mem.eql(u8, key, "backoff_multiplier")) {
                    const trimmed_val = std.mem.trim(u8, value, " \t\"");
                    task_retry_backoff_multiplier = std.fmt.parseFloat(f64, trimmed_val) catch null;
                } else if (std.mem.eql(u8, key, "jitter")) {
                    task_retry_jitter = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "max_backoff_ms")) {
                    const trimmed_val = std.mem.trim(u8, value, " \t\"");
                    task_max_backoff_ms = std.fmt.parseInt(u64, trimmed_val, 10) catch null;
                } else if (std.mem.eql(u8, key, "max_backoff")) {
                    // Alternative: parse as duration (e.g., "1000ms")
                    task_max_backoff_ms = parseDurationMs(value);
                } else if (std.mem.eql(u8, key, "on_codes")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const codes_str = value[1 .. value.len - 1];
                        var codes_it = std.mem.splitScalar(u8, codes_str, ',');
                        while (codes_it.next()) |code| {
                            const trimmed_code = std.mem.trim(u8, code, " \t");
                            if (trimmed_code.len > 0) {
                                const code_val = std.fmt.parseInt(u8, trimmed_code, 10) catch continue;
                                try task_retry_on_codes.append(allocator, code_val);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "on_patterns")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const patterns_str = value[1 .. value.len - 1];
                        var patterns_it = std.mem.splitScalar(u8, patterns_str, ',');
                        while (patterns_it.next()) |pattern| {
                            const trimmed_pattern = std.mem.trim(u8, pattern, " \t\"");
                            if (trimmed_pattern.len > 0) {
                                try task_retry_on_patterns.append(allocator, trimmed_pattern);
                            }
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
                } else if (std.mem.eql(u8, key, "skip_if")) {
                    task_skip_if = value;
                } else if (std.mem.eql(u8, key, "output_if")) {
                    task_output_if = value;
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
                } else if (std.mem.eql(u8, key, "deps_if")) {
                    // Parse array of inline tables: [{ task = "build", condition = "platform.is_linux" }, ...]
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "[") and std.mem.endsWith(u8, inner, "]")) {
                        const array_str = inner[1 .. inner.len - 1];
                        var depth: usize = 0;
                        var table_start: usize = 0;
                        var in_quotes = false;
                        for (array_str, 0..) |c, i| {
                            if (c == '"') in_quotes = !in_quotes;
                            if (in_quotes) continue;
                            if (c == '{') {
                                if (depth == 0) table_start = i + 1;
                                depth += 1;
                            } else if (c == '}' and depth > 0) {
                                depth -= 1;
                                if (depth == 0) {
                                    const table_str = array_str[table_start..i];
                                    // Parse inline table fields
                                    var task_name: ?[]const u8 = null;
                                    var cond_expr: ?[]const u8 = null;
                                    var pairs_it = std.mem.splitScalar(u8, table_str, ',');
                                    while (pairs_it.next()) |pair_str| {
                                        const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                                        const field_key = std.mem.trim(u8, pair_str[0..eq], " \t");
                                        const field_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                                        if (std.mem.eql(u8, field_key, "task")) {
                                            task_name = field_val;
                                        } else if (std.mem.eql(u8, field_key, "condition")) {
                                            cond_expr = field_val;
                                        }
                                    }
                                    if (task_name != null and cond_expr != null) {
                                        // Non-owning slices — addTask will dupe
                                        try task_deps_if.append(allocator, .{
                                            .task = task_name.?,
                                            .condition = cond_expr.?,
                                        });
                                    }
                                }
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "deps_optional")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const deps_str = value[1 .. value.len - 1];
                        var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                        while (deps_it.next()) |dep| {
                            const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                            if (trimmed_dep.len > 0) {
                                // Non-owning slice — addTask will dupe
                                try task_deps_optional.append(allocator, trimmed_dep);
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
                            } else if (std.mem.eql(u8, rkey, "backoff_multiplier")) {
                                task_retry_backoff_multiplier = std.fmt.parseFloat(f64, rval) catch null;
                            } else if (std.mem.eql(u8, rkey, "jitter")) {
                                task_retry_jitter = std.mem.eql(u8, rval, "true");
                            } else if (std.mem.eql(u8, rkey, "max_backoff")) {
                                task_max_backoff_ms = parseDurationMs(rval);
                            } else if (std.mem.eql(u8, rkey, "on_codes")) {
                                // Parse array: [1, 2, 255]
                                if (std.mem.startsWith(u8, rval, "[") and std.mem.endsWith(u8, rval, "]")) {
                                    const codes_str = rval[1 .. rval.len - 1];
                                    var codes_it = std.mem.splitScalar(u8, codes_str, ',');
                                    while (codes_it.next()) |code_str| {
                                        const trimmed_code = std.mem.trim(u8, code_str, " \t");
                                        if (trimmed_code.len > 0) {
                                            const code = std.fmt.parseInt(u8, trimmed_code, 10) catch continue;
                                            try task_retry_on_codes.append(allocator, code);
                                        }
                                    }
                                }
                            } else if (std.mem.eql(u8, rkey, "on_patterns")) {
                                // Parse array: ["Connection refused", "Timeout"]
                                if (std.mem.startsWith(u8, rval, "[") and std.mem.endsWith(u8, rval, "]")) {
                                    const patterns_str = rval[1 .. rval.len - 1];
                                    var patterns_it = std.mem.splitScalar(u8, patterns_str, ',');
                                    while (patterns_it.next()) |pattern_str| {
                                        const trimmed_pattern = std.mem.trim(u8, pattern_str, " \t\"");
                                        if (trimmed_pattern.len > 0) {
                                            try task_retry_on_patterns.append(allocator, trimmed_pattern);
                                        }
                                    }
                                }
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
                } else if (std.mem.eql(u8, key, "cpu_affinity")) {
                    // Parse array: [0, 1, 2] (v1.13.0)
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const affinity_str = value[1 .. value.len - 1];
                        var affinity_it = std.mem.splitScalar(u8, affinity_str, ',');
                        while (affinity_it.next()) |cpu_str| {
                            const trimmed_cpu = std.mem.trim(u8, cpu_str, " \t\"");
                            if (trimmed_cpu.len > 0) {
                                const cpu_id = std.fmt.parseInt(u32, trimmed_cpu, 10) catch continue;
                                try task_cpu_affinity.append(allocator, cpu_id);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "numa_node")) {
                    // Parse single integer: numa_node = 0 (v1.13.0)
                    const trimmed_numa = std.mem.trim(u8, value, " \t\"");
                    task_numa_node = std.fmt.parseInt(u32, trimmed_numa, 10) catch null;
                } else if (std.mem.eql(u8, key, "template")) {
                    // Task template reference (v1.29.0)
                    task_template = value;
                } else if (std.mem.eql(u8, key, "params")) {
                    // Task template parameters (v1.29.0)
                    // Parse inline table: { port = "3000", host = "localhost" }
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const param_key = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const param_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (param_key.len > 0) {
                                // Non-owning slices into content — addTaskImpl will dupe
                                try task_params.append(allocator, .{ param_key, param_val });
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "output_file")) {
                    // Output file path for streaming task output (v1.37.0)
                    task_output_file = value;
                } else if (std.mem.eql(u8, key, "output_mode")) {
                    // Output mode: stream, buffer, or discard (v1.37.0)
                    task_output_mode = value;
                } else if (std.mem.eql(u8, key, "remote")) {
                    // Remote execution target: SSH (user@host:port or ssh://user@host:port) or HTTP/HTTPS (v1.45.0)
                    task_remote = value;
                } else if (std.mem.eql(u8, key, "remote_cwd")) {
                    // Remote working directory (v1.45.0)
                    task_remote_cwd = value;
                } else if (std.mem.eql(u8, key, "remote_env")) {
                    // Remote environment variables: { KEY = "value", FOO = "bar" } (v1.45.0)
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const env_key = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const env_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (env_key.len > 0) {
                                // Non-owning slices into content — addTaskImpl will dupe
                                try task_remote_env.append(allocator, .{ env_key, env_val });
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "concurrency_group")) {
                    // Concurrency group name for this task (v1.62.0)
                    task_concurrency_group = value;
                } else if (std.mem.eql(u8, key, "mixins")) {
                    // Mixin names for this task (v1.67.0)
                    // Parse array: ["mixin1", "mixin2"]
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const mixins_str = value[1 .. value.len - 1];
                        var mixins_it = std.mem.splitScalar(u8, mixins_str, ',');
                        while (mixins_it.next()) |mixin_name| {
                            const trimmed_mixin = std.mem.trim(u8, mixin_name, " \t\"");
                            if (trimmed_mixin.len > 0) {
                                // Non-owning slice — will be duped when task is added
                                try task_mixins.append(allocator, trimmed_mixin);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "aliases")) {
                    // Task aliases (v1.73.0)
                    // Parse array: ["b", "compile"]
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const aliases_str = value[1 .. value.len - 1];
                        var aliases_it = std.mem.splitScalar(u8, aliases_str, ',');
                        while (aliases_it.next()) |alias_name| {
                            const trimmed_alias = std.mem.trim(u8, alias_name, " \t\"");
                            if (trimmed_alias.len > 0) {
                                // Non-owning slice — will be duped when task is added
                                try task_aliases.append(allocator, trimmed_alias);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "silent")) {
                    // Silent mode for this task (v1.73.0)
                    task_silent = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "env_file")) {
                    // .env file paths for environment variable loading (v1.78.0)
                    // Parse single string: env_file = ".env" or array: env_file = [".env", ".env.local"]
                    const trimmed_value = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, trimmed_value, "[") and std.mem.endsWith(u8, trimmed_value, "]")) {
                        // Array syntax
                        const files_str = trimmed_value[1 .. trimmed_value.len - 1];
                        var files_it = std.mem.splitScalar(u8, files_str, ',');
                        while (files_it.next()) |file_path| {
                            const trimmed_path = std.mem.trim(u8, file_path, " \t\"");
                            if (trimmed_path.len > 0) {
                                try task_env_file.append(allocator, trimmed_path);
                            }
                        }
                    } else {
                        // Single string syntax (strip quotes if present)
                        const unquoted = std.mem.trim(u8, trimmed_value, "\"");
                        if (unquoted.len > 0) {
                            try task_env_file.append(allocator, unquoted);
                        }
                    }
                } else if (std.mem.eql(u8, key, "sources")) {
                    // Source file patterns for up-to-date detection (v1.74.0)
                    // Parse array: ["src/**/*.ts", "config.json"]
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const sources_str = value[1 .. value.len - 1];
                        var sources_it = std.mem.splitScalar(u8, sources_str, ',');
                        while (sources_it.next()) |source_pattern| {
                            const trimmed_src = std.mem.trim(u8, source_pattern, " \t\"");
                            if (trimmed_src.len > 0) {
                                try task_sources.append(allocator, trimmed_src);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "generates")) {
                    // Generated file patterns for up-to-date detection (v1.74.0)
                    // Parse array: ["dist/bundle.js", "dist/**/*.css"]
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const generates_str = value[1 .. value.len - 1];
                        var generates_it = std.mem.splitScalar(u8, generates_str, ',');
                        while (generates_it.next()) |gen_pattern| {
                            const trimmed_gen = std.mem.trim(u8, gen_pattern, " \t\"");
                            if (trimmed_gen.len > 0) {
                                try task_generates.append(allocator, trimmed_gen);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "task_params")) {
                    // Runtime task parameters (v1.75.0)
                    // Parse array: [{ name = "env", default = "dev", description = "..." }, ...]
                    // Simplified inline table array parser (supports basic inline tables)
                    const params_trimmed = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, params_trimmed, "[") and std.mem.endsWith(u8, params_trimmed, "]")) {
                        const params_str = params_trimmed[1 .. params_trimmed.len - 1];
                        // Split by },{ to get individual inline tables
                        var param_tables = std.ArrayList([]const u8){};
                        defer param_tables.deinit(allocator);

                        var depth: u32 = 0;
                        var start: usize = 0;
                        for (params_str, 0..) |ch, i| {
                            if (ch == '{') depth += 1;
                            if (ch == '}') {
                                depth -= 1;
                                if (depth == 0) {
                                    const table_str = std.mem.trim(u8, params_str[start..i + 1], " \t,");
                                    try param_tables.append(allocator, table_str);
                                    start = i + 1;
                                }
                            }
                        }

                        // Parse each inline table
                        for (param_tables.items) |table_str| {
                            if (!std.mem.startsWith(u8, table_str, "{") or !std.mem.endsWith(u8, table_str, "}")) continue;
                            const inner = table_str[1 .. table_str.len - 1];

                            var param_name: ?[]const u8 = null;
                            var param_type: []const u8 = "string";
                            var param_default: ?[]const u8 = null;
                            var param_description: ?[]const u8 = null;

                            // Parse key=value pairs
                            var pairs = std.mem.splitScalar(u8, inner, ',');
                            while (pairs.next()) |pair_str| {
                                const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                                const k = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                                const v = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");

                                if (std.mem.eql(u8, k, "name")) {
                                    param_name = v;
                                } else if (std.mem.eql(u8, k, "type")) {
                                    param_type = v;
                                } else if (std.mem.eql(u8, k, "default")) {
                                    param_default = v;
                                } else if (std.mem.eql(u8, k, "description")) {
                                    param_description = v;
                                }
                            }

                            if (param_name) |name| {
                                const param = types.TaskParam{
                                    .name = try allocator.dupe(u8, name),
                                    .type = try allocator.dupe(u8, param_type),
                                    .default = if (param_default) |d| try allocator.dupe(u8, d) else null,
                                    .description = if (param_description) |desc| try allocator.dupe(u8, desc) else null,
                                };
                                try task_task_params.append(allocator, param);
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
                            } else if (std.mem.eql(u8, rkey, "backoff_multiplier")) {
                                template_retry_backoff_multiplier = std.fmt.parseFloat(f64, rval) catch null;
                            } else if (std.mem.eql(u8, rkey, "jitter")) {
                                template_retry_jitter = std.mem.eql(u8, rval, "true");
                            } else if (std.mem.eql(u8, rkey, "max_backoff")) {
                                template_max_backoff_ms = parseDurationMs(rval);
                            } else if (std.mem.eql(u8, rkey, "on_codes")) {
                                if (std.mem.startsWith(u8, rval, "[") and std.mem.endsWith(u8, rval, "]")) {
                                    const codes_str = rval[1 .. rval.len - 1];
                                    var codes_it = std.mem.splitScalar(u8, codes_str, ',');
                                    while (codes_it.next()) |code_str| {
                                        const trimmed_code = std.mem.trim(u8, code_str, " \t");
                                        if (trimmed_code.len > 0) {
                                            const code = std.fmt.parseInt(u8, trimmed_code, 10) catch continue;
                                            try template_retry_on_codes.append(allocator, code);
                                        }
                                    }
                                }
                            } else if (std.mem.eql(u8, rkey, "on_patterns")) {
                                if (std.mem.startsWith(u8, rval, "[") and std.mem.endsWith(u8, rval, "]")) {
                                    const patterns_str = rval[1 .. rval.len - 1];
                                    var patterns_it = std.mem.splitScalar(u8, patterns_str, ',');
                                    while (patterns_it.next()) |pattern_str| {
                                        const trimmed_pattern = std.mem.trim(u8, pattern_str, " \t\"");
                                        if (trimmed_pattern.len > 0) {
                                            try template_retry_on_patterns.append(allocator, trimmed_pattern);
                                        }
                                    }
                                }
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
            } else if (current_mixin != null) {
                // Mixin-level key=value parsing (v1.67.0)
                if (std.mem.eql(u8, key, "env")) {
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                        const pairs_str = inner[1 .. inner.len - 1];
                        var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                        while (pairs_it.next()) |pair_str| {
                            const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                            const env_key = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                            const env_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                            if (env_key.len > 0) {
                                try mixin_env.append(allocator, .{ env_key, env_val });
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "cmd")) {
                    mixin_cmd = value;
                } else if (std.mem.eql(u8, key, "cwd")) {
                    mixin_cwd = value;
                } else if (std.mem.eql(u8, key, "description")) {
                    mixin_description = value;
                } else if (std.mem.eql(u8, key, "deps")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const deps_str = value[1 .. value.len - 1];
                        var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                        while (deps_it.next()) |dep| {
                            const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                            if (trimmed_dep.len > 0) {
                                try mixin_deps.append(allocator, trimmed_dep);
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
                                try mixin_deps_serial.append(allocator, trimmed_dep);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "deps_optional")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const deps_str = value[1 .. value.len - 1];
                        var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                        while (deps_it.next()) |dep| {
                            const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                            if (trimmed_dep.len > 0) {
                                try mixin_deps_optional.append(allocator, trimmed_dep);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "deps_if")) {
                    const inner = std.mem.trim(u8, value, " \t");
                    if (std.mem.startsWith(u8, inner, "[") and std.mem.endsWith(u8, inner, "]")) {
                        const array_str = inner[1 .. inner.len - 1];
                        var depth: usize = 0;
                        var table_start: usize = 0;
                        var in_quotes = false;
                        for (array_str, 0..) |c, i| {
                            if (c == '"') in_quotes = !in_quotes;
                            if (in_quotes) continue;
                            if (c == '{') {
                                if (depth == 0) table_start = i + 1;
                                depth += 1;
                            } else if (c == '}' and depth > 0) {
                                depth -= 1;
                                if (depth == 0) {
                                    const table_str = array_str[table_start..i];
                                    var task_name: ?[]const u8 = null;
                                    var cond_expr: ?[]const u8 = null;
                                    var pairs_it = std.mem.splitScalar(u8, table_str, ',');
                                    while (pairs_it.next()) |pair_str| {
                                        const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                                        const field_key = std.mem.trim(u8, pair_str[0..eq], " \t");
                                        const field_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                                        if (std.mem.eql(u8, field_key, "task")) {
                                            task_name = field_val;
                                        } else if (std.mem.eql(u8, field_key, "condition")) {
                                            cond_expr = field_val;
                                        }
                                    }
                                    if (task_name != null and cond_expr != null) {
                                        try mixin_deps_if.append(allocator, .{
                                            .task = task_name.?,
                                            .condition = cond_expr.?,
                                        });
                                    }
                                }
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "tags")) {
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const tags_str = value[1 .. value.len - 1];
                        var tags_it = std.mem.splitScalar(u8, tags_str, ',');
                        while (tags_it.next()) |tag| {
                            const trimmed_tag = std.mem.trim(u8, tag, " \t\"");
                            if (trimmed_tag.len > 0) {
                                try mixin_tags.append(allocator, trimmed_tag);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "timeout")) {
                    mixin_timeout_ms = parseDurationMs(value);
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
                                mixin_retry_max = std.fmt.parseInt(u32, rval, 10) catch 0;
                            } else if (std.mem.eql(u8, rkey, "delay")) {
                                mixin_retry_delay_ms = parseDurationMs(rval) orelse 0;
                            } else if (std.mem.eql(u8, rkey, "backoff_multiplier")) {
                                mixin_retry_backoff_multiplier = std.fmt.parseFloat(f64, rval) catch null;
                            } else if (std.mem.eql(u8, rkey, "jitter")) {
                                mixin_retry_jitter = std.mem.eql(u8, rval, "true");
                            } else if (std.mem.eql(u8, rkey, "max_backoff")) {
                                mixin_max_backoff_ms = parseDurationMs(rval);
                            }
                        }
                    }
                } else if (std.mem.eql(u8, key, "template")) {
                    mixin_template = value;
                } else if (std.mem.eql(u8, key, "mixins")) {
                    // Nested mixins (v1.67.0)
                    if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                        const mixins_str = value[1 .. value.len - 1];
                        var mixins_it = std.mem.splitScalar(u8, mixins_str, ',');
                        while (mixins_it.next()) |mixin_name| {
                            const trimmed_mixin = std.mem.trim(u8, mixin_name, " \t\"");
                            if (trimmed_mixin.len > 0) {
                                try mixin_mixins.append(allocator, trimmed_mixin);
                            }
                        }
                    }
                }
            }
        }
    }

    // Flush final pending mixin (v1.67.0)
    if (current_mixin) |mixin_name| {
        const mixin_name_owned = try allocator.dupe(u8, mixin_name);
        errdefer allocator.free(mixin_name_owned);

        // Dupe env
        const mixin_env_owned = try allocator.alloc([2][]const u8, mixin_env.items.len);
        var env_duped: usize = 0;
        errdefer {
            for (mixin_env_owned[0..env_duped]) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            allocator.free(mixin_env_owned);
        }
        for (mixin_env.items, 0..) |pair, i| {
            mixin_env_owned[i][0] = try allocator.dupe(u8, pair[0]);
            mixin_env_owned[i][1] = try allocator.dupe(u8, pair[1]);
            env_duped += 1;
        }

        // Dupe deps
        const mixin_deps_owned = try allocator.alloc([]const u8, mixin_deps.items.len);
        var deps_duped: usize = 0;
        errdefer {
            for (mixin_deps_owned[0..deps_duped]) |d| allocator.free(d);
            allocator.free(mixin_deps_owned);
        }
        for (mixin_deps.items, 0..) |d, i| {
            mixin_deps_owned[i] = try allocator.dupe(u8, d);
            deps_duped += 1;
        }

        // Dupe deps_serial
        const mixin_deps_serial_owned = try allocator.alloc([]const u8, mixin_deps_serial.items.len);
        var deps_serial_duped: usize = 0;
        errdefer {
            for (mixin_deps_serial_owned[0..deps_serial_duped]) |d| allocator.free(d);
            allocator.free(mixin_deps_serial_owned);
        }
        for (mixin_deps_serial.items, 0..) |d, i| {
            mixin_deps_serial_owned[i] = try allocator.dupe(u8, d);
            deps_serial_duped += 1;
        }

        // Dupe deps_optional
        const mixin_deps_optional_owned = try allocator.alloc([]const u8, mixin_deps_optional.items.len);
        var deps_optional_duped: usize = 0;
        errdefer {
            for (mixin_deps_optional_owned[0..deps_optional_duped]) |d| allocator.free(d);
            allocator.free(mixin_deps_optional_owned);
        }
        for (mixin_deps_optional.items, 0..) |d, i| {
            mixin_deps_optional_owned[i] = try allocator.dupe(u8, d);
            deps_optional_duped += 1;
        }

        // Copy deps_if
        const mixin_deps_if_owned = try allocator.alloc(types.ConditionalDep, mixin_deps_if.items.len);
        var deps_if_duped: usize = 0;
        errdefer {
            for (mixin_deps_if_owned[0..deps_if_duped]) |*d| d.deinit(allocator);
            allocator.free(mixin_deps_if_owned);
        }
        for (mixin_deps_if.items, 0..) |dep, i| {
            mixin_deps_if_owned[i] = try copyConditionalDep(allocator, &dep);
            deps_if_duped += 1;
        }

        // Dupe tags
        const mixin_tags_owned = try allocator.alloc([]const u8, mixin_tags.items.len);
        var tags_duped: usize = 0;
        errdefer {
            for (mixin_tags_owned[0..tags_duped]) |t| allocator.free(t);
            allocator.free(mixin_tags_owned);
        }
        for (mixin_tags.items, 0..) |t, i| {
            mixin_tags_owned[i] = try allocator.dupe(u8, t);
            tags_duped += 1;
        }

        // Dupe optional string fields
        const mixin_cmd_owned = if (mixin_cmd) |cmd| try allocator.dupe(u8, cmd) else null;
        errdefer if (mixin_cmd_owned) |c| allocator.free(c);
        const mixin_cwd_owned = if (mixin_cwd) |cwd| try allocator.dupe(u8, cwd) else null;
        errdefer if (mixin_cwd_owned) |cwd| allocator.free(cwd);
        const mixin_desc_owned = if (mixin_description) |desc| try allocator.dupe(u8, desc) else null;
        errdefer if (mixin_desc_owned) |d| allocator.free(d);

        // Copy hooks
        const mixin_hooks_owned = try allocator.alloc(types.TaskHook, mixin_hooks.items.len);
        var hooks_duped: usize = 0;
        errdefer {
            for (mixin_hooks_owned[0..hooks_duped]) |*h| h.deinit(allocator);
            allocator.free(mixin_hooks_owned);
        }
        for (mixin_hooks.items, 0..) |hook, i| {
            mixin_hooks_owned[i] = try copyTaskHook(allocator, &hook);
            hooks_duped += 1;
        }

        // Dupe template
        const mixin_template_owned = if (mixin_template) |t| try allocator.dupe(u8, t) else null;
        errdefer if (mixin_template_owned) |t| allocator.free(t);

        // Dupe mixin names (nested mixins)
        const mixin_mixins_owned = try allocator.alloc([]const u8, mixin_mixins.items.len);
        var mixins_duped: usize = 0;
        errdefer {
            for (mixin_mixins_owned[0..mixins_duped]) |m| allocator.free(m);
            allocator.free(mixin_mixins_owned);
        }
        for (mixin_mixins.items, 0..) |m, i| {
            mixin_mixins_owned[i] = try allocator.dupe(u8, m);
            mixins_duped += 1;
        }

        const mixin = types.Mixin{
            .name = mixin_name_owned,
            .env = mixin_env_owned,
            .deps = mixin_deps_owned,
            .deps_serial = mixin_deps_serial_owned,
            .deps_optional = mixin_deps_optional_owned,
            .deps_if = mixin_deps_if_owned,
            .tags = mixin_tags_owned,
            .cmd = mixin_cmd_owned,
            .cwd = mixin_cwd_owned,
            .description = mixin_desc_owned,
            .timeout_ms = mixin_timeout_ms,
            .retry_max = mixin_retry_max,
            .retry_delay_ms = mixin_retry_delay_ms,
            .retry_backoff_multiplier = mixin_retry_backoff_multiplier,
            .retry_jitter = mixin_retry_jitter,
            .max_backoff_ms = mixin_max_backoff_ms,
            .hooks = mixin_hooks_owned,
            .template = mixin_template_owned,
            .mixins = mixin_mixins_owned,
        };

        try config.mixins.put(mixin_name_owned, mixin);
    }

    // Flush final pending stage (including approval and on_failure fields, with auto-generated name if needed)
    _ = try flushPendingStage(
        allocator,
        &workflow_stages,
        stage_name,
        &stage_tasks,
        stage_parallel,
        stage_fail_fast,
        stage_condition,
        stage_approval,
        stage_on_failure,
    );

    // Flush final pending workflow
    if (current_workflow) |wf_name_slice| {
        try config.addWorkflow(wf_name_slice, workflow_desc, workflow_stages.items, workflow_retry_budget);
        for (workflow_stages.items) |*s| s.deinit(allocator);
        workflow_stages.clearRetainingCapacity();
    }

    // Flush final pending hook (v1.24.0)
    // If we're in a hook section for the current task, flush to task_hooks
    // Otherwise, flush to pending_hooks for a future task
    const final_hook_dest = if (in_task_hooks and current_task != null and pending_task_name == null) &task_hooks else &pending_hooks;
    try flushCurrentHook(
        allocator,
        final_hook_dest,
        current_hook_cmd,
        current_hook_point,
        current_hook_failure_strategy,
        current_hook_working_dir,
        &current_hook_env,
    );

    // Flush final pending task
    if (current_task) |task_name| {
        // Allow tasks without cmd if they have dependencies (dependency-only tasks)
        const cmd = task_cmd orelse "";
        if (task_matrix_raw) |mraw| {
            try addMatrixTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, mraw);
        } else {
            try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_deps_if.items, task_deps_optional.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff, task_condition, task_skip_if, task_output_if, task_max_concurrent, task_cache, task_max_cpu, task_max_memory, task_toolchain.items, task_tags.items, task_cpu_affinity.items, task_numa_node, task_watch_debounce_ms, task_watch_patterns.items, task_watch_exclude_patterns.items, task_watch_mode, task_hooks.items, task_template, task_params.items, task_output_file, task_output_mode, task_remote, task_remote_cwd, task_remote_env.items, task_mixins.items, task_aliases.items, task_silent, task_sources.items, task_generates.items, task_task_params.items, task_env_file.items);
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

    // Flush final workspace shared task (v1.63.0)
    if (ws_shared_task_name) |task_name| {
        const cmd = task_cmd orelse "";
        try addWorkspaceSharedTask(
            &ws_shared_tasks,
            allocator,
            task_name,
            cmd,
            task_cwd,
            task_desc,
            task_deps.items,
            task_deps_serial.items,
            task_deps_optional.items,
            task_env.items,
            task_timeout_ms,
            task_allow_failure,
        );
    }

    // Flush workspace if present
    if (in_workspace or ws_members.items.len > 0 or ws_shared_tasks.count() > 0) {
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

        // Transfer shared_tasks HashMap ownership
        var shared_tasks_map = std.StringHashMap(Task).init(allocator);
        var task_it = ws_shared_tasks.iterator();
        while (task_it.next()) |entry| {
            try shared_tasks_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        config.workspace = Workspace{
            .members = members,
            .ignore = ignore,
            .member_dependencies = member_deps,
            .shared_tasks = shared_tasks_map,
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

    // Flush final pending concurrency group (v1.62.0)
    if (current_concurrency_group) |cgn| {
        const cg = types.ConcurrencyGroup{
            .name = try allocator.dupe(u8, cgn),
            .max_workers = cgroup_max_workers,
        };
        try config.concurrency_groups.put(try allocator.dupe(u8, cgn), cg);
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
            .compression = cache_remote_compression,
            .incremental_sync = cache_remote_incremental_sync,
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

    // Transfer imports (v1.55.0)
    if (import_files.items.len > 0) {
        const owned_imports = try allocator.alloc([]const u8, import_files.items.len);
        var imp_duped: usize = 0;
        errdefer {
            for (owned_imports[0..imp_duped]) |s| allocator.free(s);
            allocator.free(owned_imports);
        }
        for (import_files.items, 0..) |s, i| {
            owned_imports[i] = try allocator.dupe(u8, s);
            imp_duped += 1;
        }
        config.imports = owned_imports;
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

/// Flush current hook into the destination list (v1.24.0)
fn flushCurrentHook(
    allocator: std.mem.Allocator,
    dest_hooks: *std.ArrayList(types.TaskHook),
    cmd: ?[]const u8,
    point: ?[]const u8,
    failure_strategy: ?[]const u8,
    working_dir: ?[]const u8,
    env: *std.ArrayList([2][]const u8),
) !void {
    // Hook requires cmd and point
    if (cmd == null or point == null) return;

    // Parse hook point
    const hook_point = if (std.mem.eql(u8, point.?, "before"))
        types.HookPoint.before
    else if (std.mem.eql(u8, point.?, "after"))
        types.HookPoint.after
    else if (std.mem.eql(u8, point.?, "success"))
        types.HookPoint.success
    else if (std.mem.eql(u8, point.?, "failure"))
        types.HookPoint.failure
    else if (std.mem.eql(u8, point.?, "timeout"))
        types.HookPoint.timeout
    else
        return; // Invalid point, skip this hook

    // Parse failure strategy
    const hook_failure_strategy = if (failure_strategy) |fs| blk: {
        if (std.mem.eql(u8, fs, "abort_task")) break :blk types.HookFailureStrategy.abort_task else break :blk types.HookFailureStrategy.continue_task;
    } else types.HookFailureStrategy.continue_task;

    // Duplicate hook data (owned by TaskHook)
    const hook_cmd = try allocator.dupe(u8, cmd.?);
    errdefer allocator.free(hook_cmd);

    const hook_working_dir = if (working_dir) |wd| try allocator.dupe(u8, wd) else null;
    errdefer if (hook_working_dir) |wd| allocator.free(wd);

    // Duplicate env pairs
    const hook_env = try allocator.alloc([2][]const u8, env.items.len);
    var env_duped: usize = 0;
    errdefer {
        for (hook_env[0..env_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(hook_env);
    }
    for (env.items, 0..) |pair, i| {
        hook_env[i][0] = try allocator.dupe(u8, pair[0]);
        errdefer allocator.free(hook_env[i][0]);
        hook_env[i][1] = try allocator.dupe(u8, pair[1]);
        env_duped += 1;
    }

    const hook = types.TaskHook{
        .cmd = hook_cmd,
        .point = hook_point,
        .failure_strategy = hook_failure_strategy,
        .working_dir = hook_working_dir,
        .env = hook_env,
    };

    try dest_hooks.append(allocator, hook);
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
    try std.testing.expectEqualStrings("Build the project", build_task.description.?.getShort());

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

test "parse workflow with anonymous stages (auto-generated names)" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.clean]
        \\cmd = "echo clean"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[workflows.pipeline]
        \\description = "Pipeline with anonymous stages"
        \\
        \\[[workflows.pipeline.stages]]
        \\tasks = ["clean"]
        \\
        \\[[workflows.pipeline.stages]]
        \\tasks = ["build", "test"]
        \\parallel = true
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const wf = config.workflows.get("pipeline").?;
    try std.testing.expectEqualStrings("pipeline", wf.name);
    try std.testing.expectEqual(@as(usize, 2), wf.stages.len);

    // First anonymous stage should get auto-generated name "stage-1"
    const stage1 = wf.stages[0];
    try std.testing.expectEqualStrings("stage-1", stage1.name);
    try std.testing.expectEqual(@as(usize, 1), stage1.tasks.len);
    try std.testing.expectEqualStrings("clean", stage1.tasks[0]);

    // Second anonymous stage should get auto-generated name "stage-2"
    const stage2 = wf.stages[1];
    try std.testing.expectEqualStrings("stage-2", stage2.name);
    try std.testing.expectEqual(@as(usize, 2), stage2.tasks.len);
    try std.testing.expectEqualStrings("build", stage2.tasks[0]);
    try std.testing.expectEqualStrings("test", stage2.tasks[1]);
    try std.testing.expect(stage2.parallel);
}

test "parse workflow with mixed named and anonymous stages" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.clean]
        \\cmd = "echo clean"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[workflows.mixed]
        \\
        \\[[workflows.mixed.stages]]
        \\name = "prepare"
        \\tasks = ["clean"]
        \\
        \\[[workflows.mixed.stages]]
        \\tasks = ["build"]
        \\
        \\[[workflows.mixed.stages]]
        \\name = "verify"
        \\tasks = ["test"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const wf = config.workflows.get("mixed").?;
    try std.testing.expectEqual(@as(usize, 3), wf.stages.len);

    // First stage has explicit name
    try std.testing.expectEqualStrings("prepare", wf.stages[0].name);
    try std.testing.expectEqualStrings("clean", wf.stages[0].tasks[0]);

    // Second stage is anonymous, should get "stage-2" (counting from existing stages)
    try std.testing.expectEqualStrings("stage-2", wf.stages[1].name);
    try std.testing.expectEqualStrings("build", wf.stages[1].tasks[0]);

    // Third stage has explicit name
    try std.testing.expectEqualStrings("verify", wf.stages[2].name);
    try std.testing.expectEqualStrings("test", wf.stages[2].tasks[0]);
}

test "parse workflow with only anonymous stages preserves all stages" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\
        \\[workflows.simple]
        \\
        \\[[workflows.simple.stages]]
        \\tasks = ["a"]
        \\
        \\[[workflows.simple.stages]]
        \\tasks = ["b"]
        \\
        \\[[workflows.simple.stages]]
        \\tasks = ["c"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const wf = config.workflows.get("simple").?;
    try std.testing.expectEqual(@as(usize, 3), wf.stages.len);

    // All three stages should be preserved with auto-generated names
    try std.testing.expectEqualStrings("stage-1", wf.stages[0].name);
    try std.testing.expectEqualStrings("a", wf.stages[0].tasks[0]);

    try std.testing.expectEqualStrings("stage-2", wf.stages[1].name);
    try std.testing.expectEqualStrings("b", wf.stages[1].tasks[0]);

    try std.testing.expectEqualStrings("stage-3", wf.stages[2].name);
    try std.testing.expectEqualStrings("c", wf.stages[2].tasks[0]);
}

test "parse deps_if from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = [{ task = "lint", condition = "platform.is_linux" }, { task = "test", condition = "env.CI == 'true'" }]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 3), config.tasks.count());

    const task = config.tasks.get("build").?;
    try std.testing.expectEqualStrings("build", task.name);
    try std.testing.expectEqual(@as(usize, 2), task.deps_if.len);

    // First conditional dep
    try std.testing.expectEqualStrings("lint", task.deps_if[0].task);
    try std.testing.expectEqualStrings("platform.is_linux", task.deps_if[0].condition);

    // Second conditional dep
    try std.testing.expectEqualStrings("test", task.deps_if[1].task);
    try std.testing.expectEqualStrings("env.CI == 'true'", task.deps_if[1].condition);
}

test "parse deps_optional from toml" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.format]
        \\cmd = "echo format"
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_optional = ["format", "lint"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 3), config.tasks.count());

    const task = config.tasks.get("build").?;
    try std.testing.expectEqualStrings("build", task.name);
    try std.testing.expectEqual(@as(usize, 2), task.deps_optional.len);

    try std.testing.expectEqualStrings("format", task.deps_optional[0]);
    try std.testing.expectEqualStrings("lint", task.deps_optional[1]);
}

test "parse combined deps, deps_serial, deps_if, deps_optional" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.install]
        \\cmd = "echo install"
        \\
        \\[tasks.generate]
        \\cmd = "echo generate"
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.format]
        \\cmd = "echo format"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps = ["install"]
        \\deps_serial = ["generate"]
        \\deps_if = [{ task = "lint", condition = "platform.is_linux" }]
        \\deps_optional = ["format", "test"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 6), config.tasks.count());

    const task = config.tasks.get("build").?;
    try std.testing.expectEqualStrings("build", task.name);

    // Check parallel deps
    try std.testing.expectEqual(@as(usize, 1), task.deps.len);
    try std.testing.expectEqualStrings("install", task.deps[0]);

    // Check serial deps
    try std.testing.expectEqual(@as(usize, 1), task.deps_serial.len);
    try std.testing.expectEqualStrings("generate", task.deps_serial[0]);

    // Check conditional deps
    try std.testing.expectEqual(@as(usize, 1), task.deps_if.len);
    try std.testing.expectEqualStrings("lint", task.deps_if[0].task);
    try std.testing.expectEqualStrings("platform.is_linux", task.deps_if[0].condition);

    // Check optional deps
    try std.testing.expectEqual(@as(usize, 2), task.deps_optional.len);
    try std.testing.expectEqualStrings("format", task.deps_optional[0]);
    try std.testing.expectEqualStrings("test", task.deps_optional[1]);
}

test "parse deps_if with complex condition expressions" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.deploy_staging]
        \\cmd = "echo deploy staging"
        \\
        \\[tasks.deploy_prod]
        \\cmd = "echo deploy prod"
        \\
        \\[tasks.release]
        \\cmd = "echo release"
        \\deps_if = [{ task = "deploy_staging", condition = "env.BRANCH == 'staging' && platform.is_linux" }, { task = "deploy_prod", condition = "env.BRANCH == 'main' || env.FORCE_PROD == '1'" }]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("release").?;
    try std.testing.expectEqual(@as(usize, 2), task.deps_if.len);

    try std.testing.expectEqualStrings("deploy_staging", task.deps_if[0].task);
    try std.testing.expectEqualStrings("env.BRANCH == 'staging' && platform.is_linux", task.deps_if[0].condition);

    try std.testing.expectEqualStrings("deploy_prod", task.deps_if[1].task);
    try std.testing.expectEqualStrings("env.BRANCH == 'main' || env.FORCE_PROD == '1'", task.deps_if[1].condition);
}

test "empty deps_if and deps_optional arrays" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = []
        \\deps_optional = []
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(usize, 0), task.deps_if.len);
    try std.testing.expectEqual(@as(usize, 0), task.deps_optional.len);
}
// Additional tests for v1.19.0 features (inline stages and cmd-less tasks)
// These should be appended to parser.zig

test "parse inline workflow stages syntax" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.docker]
        \\cmd = "echo docker"
        \\
        \\[workflows.pipeline]
        \\description = "Build pipeline with inline stages"
        \\stages = [{ name = "compile", tasks = ["build", "test"] }, { name = "package", tasks = ["docker"] }]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.workflows.count());

    const wf = config.workflows.get("pipeline").?;
    try std.testing.expectEqualStrings("pipeline", wf.name);
    try std.testing.expectEqualStrings("Build pipeline with inline stages", wf.description.?);
    try std.testing.expectEqual(@as(usize, 2), wf.stages.len);

    // First stage
    try std.testing.expectEqualStrings("compile", wf.stages[0].name);
    try std.testing.expectEqual(@as(usize, 2), wf.stages[0].tasks.len);
    try std.testing.expectEqualStrings("build", wf.stages[0].tasks[0]);
    try std.testing.expectEqualStrings("test", wf.stages[0].tasks[1]);

    // Second stage
    try std.testing.expectEqualStrings("package", wf.stages[1].name);
    try std.testing.expectEqual(@as(usize, 1), wf.stages[1].tasks.len);
    try std.testing.expectEqualStrings("docker", wf.stages[1].tasks[0]);
}

test "parse inline workflow stages with all stage options" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[workflows.ci]
        \\stages = [{ name = "checks", tasks = ["lint", "test"], parallel = false, fail_fast = true, condition = "platform.is_linux", approval = true, on_failure = "continue" }]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const wf = config.workflows.get("ci").?;
    try std.testing.expectEqual(@as(usize, 1), wf.stages.len);

    const stage = wf.stages[0];
    try std.testing.expectEqualStrings("checks", stage.name);
    try std.testing.expectEqual(false, stage.parallel);
    try std.testing.expectEqual(true, stage.fail_fast);
    try std.testing.expectEqualStrings("platform.is_linux", stage.condition.?);
    try std.testing.expectEqual(true, stage.approval);
    try std.testing.expectEqualStrings("continue", stage.on_failure.?);
}

test "parse cmd-less dependency-only task" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.all]
        \\description = "Run all checks"
        \\deps = ["lint", "test", "build"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 4), config.tasks.count());

    const task = config.tasks.get("all").?;
    try std.testing.expectEqualStrings("all", task.name);
    try std.testing.expectEqualStrings("Run all checks", task.description.?.getShort());
    try std.testing.expectEqualStrings("", task.cmd); // Empty cmd
    try std.testing.expectEqual(@as(usize, 3), task.deps.len);
    try std.testing.expectEqualStrings("lint", task.deps[0]);
    try std.testing.expectEqualStrings("test", task.deps[1]);
    try std.testing.expectEqualStrings("build", task.deps[2]);
}

test "parse cmd-less task with deps_serial" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.install]
        \\cmd = "npm install"
        \\
        \\[tasks.build]
        \\cmd = "npm run build"
        \\
        \\[tasks.setup]
        \\description = "Setup and build"
        \\deps_serial = ["install", "build"]
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("setup").?;
    try std.testing.expectEqualStrings("", task.cmd);
    try std.testing.expectEqual(@as(usize, 2), task.deps_serial.len);
    try std.testing.expectEqualStrings("install", task.deps_serial[0]);
    try std.testing.expectEqualStrings("build", task.deps_serial[1]);
}

test "parse task with before hook" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\
        \\[[tasks.build.hooks]]
        \\cmd = "echo 'Starting build...'"
        \\point = "before"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(usize, 1), task.hooks.len);

    const hook = task.hooks[0];
    try std.testing.expectEqualStrings("echo 'Starting build...'", hook.cmd);
    try std.testing.expectEqual(types.HookPoint.before, hook.point);
    try std.testing.expectEqual(types.HookFailureStrategy.continue_task, hook.failure_strategy);
}

test "parse task with multiple hooks" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.deploy]
        \\cmd = "kubectl apply -f deployment.yaml"
        \\
        \\[[tasks.deploy.hooks]]
        \\cmd = "echo 'Pre-deployment check'"
        \\point = "before"
        \\
        \\[[tasks.deploy.hooks]]
        \\cmd = "echo 'Deployment successful!'"
        \\point = "success"
        \\
        \\[[tasks.deploy.hooks]]
        \\cmd = "echo 'Deployment failed!' && exit 1"
        \\point = "failure"
        \\failure_strategy = "abort_task"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("deploy").?;
    try std.testing.expectEqual(@as(usize, 3), task.hooks.len);

    // Before hook
    try std.testing.expectEqualStrings("echo 'Pre-deployment check'", task.hooks[0].cmd);
    try std.testing.expectEqual(types.HookPoint.before, task.hooks[0].point);
    try std.testing.expectEqual(types.HookFailureStrategy.continue_task, task.hooks[0].failure_strategy);

    // Success hook
    try std.testing.expectEqualStrings("echo 'Deployment successful!'", task.hooks[1].cmd);
    try std.testing.expectEqual(types.HookPoint.success, task.hooks[1].point);

    // Failure hook
    try std.testing.expectEqualStrings("echo 'Deployment failed!' && exit 1", task.hooks[2].cmd);
    try std.testing.expectEqual(types.HookPoint.failure, task.hooks[2].point);
    try std.testing.expectEqual(types.HookFailureStrategy.abort_task, task.hooks[2].failure_strategy);
}

test "parse task hook with working directory and env" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.test]
        \\cmd = "npm test"
        \\
        \\[[tasks.test.hooks]]
        \\cmd = "echo 'Running in ${WORKING_DIR}'"
        \\point = "before"
        \\working_dir = "/tmp/test"
        \\env = { TEST_ENV = "production", DEBUG = "true" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("test").?;
    try std.testing.expectEqual(@as(usize, 1), task.hooks.len);

    const hook = task.hooks[0];
    try std.testing.expectEqualStrings("echo 'Running in ${WORKING_DIR}'", hook.cmd);
    try std.testing.expectEqual(types.HookPoint.before, hook.point);
    try std.testing.expectEqualStrings("/tmp/test", hook.working_dir.?);
    try std.testing.expectEqual(@as(usize, 2), hook.env.len);
}

test "parse task hook with timeout and after points" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.long_task]
        \\cmd = "sleep 100"
        \\timeout = "10s"
        \\
        \\[[tasks.long_task.hooks]]
        \\cmd = "echo 'Task timed out!'"
        \\point = "timeout"
        \\
        \\[[tasks.long_task.hooks]]
        \\cmd = "echo 'Task completed'"
        \\point = "after"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("long_task").?;
    try std.testing.expectEqual(@as(usize, 2), task.hooks.len);

    // Timeout hook
    try std.testing.expectEqualStrings("echo 'Task timed out!'", task.hooks[0].cmd);
    try std.testing.expectEqual(types.HookPoint.timeout, task.hooks[0].point);

    // After hook
    try std.testing.expectEqualStrings("echo 'Task completed'", task.hooks[1].cmd);
    try std.testing.expectEqual(types.HookPoint.after, task.hooks[1].point);
}

// Remote execution tests (Phase 1.1: Config Schema Extension)

test "parse task with SSH remote target (short format: user@host:port)" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.deploy]
        \\cmd = "npm run deploy"
        \\remote = "user@example.com:22"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("deploy").?;
    try std.testing.expectEqualStrings("npm run deploy", task.cmd);
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("user@example.com:22", task.remote.?);
}

test "parse task with SSH remote target (URI format: ssh://user@host:port)" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.build]
        \\cmd = "cargo build --release"
        \\remote = "ssh://builder@10.0.1.5:2222"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("build").?;
    try std.testing.expectEqualStrings("cargo build --release", task.cmd);
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("ssh://builder@10.0.1.5:2222", task.remote.?);
}

test "parse task with HTTP remote target (http://host:port)" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.run-job]
        \\cmd = "python train.py"
        \\remote = "http://gpu-cluster:8080"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("run-job").?;
    try std.testing.expectEqualStrings("python train.py", task.cmd);
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("http://gpu-cluster:8080", task.remote.?);
}

test "parse task with HTTPS remote target (https://host:port)" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.sync]
        \\cmd = "rsync -av data/"
        \\remote = "https://secure-server:9443"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("sync").?;
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("https://secure-server:9443", task.remote.?);
}

test "parse task with remote_cwd field" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.test-remote]
        \\cmd = "pytest tests/"
        \\remote = "ssh://ci@test-vm:22"
        \\remote_cwd = "/home/ci/project"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("test-remote").?;
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("ssh://ci@test-vm:22", task.remote.?);
    try std.testing.expect(task.remote_cwd != null);
    try std.testing.expectEqualStrings("/home/ci/project", task.remote_cwd.?);
}

test "parse task with remote_env field" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.deploy-prod]
        \\cmd = "npm run deploy"
        \\remote = "user@prod-server:22"
        \\remote_env = { ENVIRONMENT = "production", LOG_LEVEL = "info" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("deploy-prod").?;
    try std.testing.expect(task.remote != null);
    try std.testing.expect(task.remote_env != null);
    try std.testing.expectEqual(@as(usize, 2), task.remote_env.?.len);

    // Check that the environment variables are parsed
    var found_env = false;
    var found_log = false;
    for (task.remote_env.?) |pair| {
        if (std.mem.eql(u8, pair[0], "ENVIRONMENT")) {
            try std.testing.expectEqualStrings("production", pair[1]);
            found_env = true;
        }
        if (std.mem.eql(u8, pair[0], "LOG_LEVEL")) {
            try std.testing.expectEqualStrings("info", pair[1]);
            found_log = true;
        }
    }
    try std.testing.expect(found_env);
    try std.testing.expect(found_log);
}

test "parse task with remote_cwd and remote_env together" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.full-remote]
        \\cmd = "make clean && make test"
        \\remote = "ssh://dev@build-machine:22"
        \\remote_cwd = "/workspace/project"
        \\remote_env = { BUILD_TYPE = "debug", JOBS = "8" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("full-remote").?;
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("ssh://dev@build-machine:22", task.remote.?);
    try std.testing.expect(task.remote_cwd != null);
    try std.testing.expectEqualStrings("/workspace/project", task.remote_cwd.?);
    try std.testing.expect(task.remote_env != null);
    try std.testing.expectEqual(@as(usize, 2), task.remote_env.?.len);
}

test "remote field is optional (defaults to null for local execution)" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.local-task]
        \\cmd = "echo 'Running locally'"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("local-task").?;
    try std.testing.expect(task.remote == null);
    try std.testing.expect(task.remote_cwd == null);
    try std.testing.expect(task.remote_env == null);
}

test "parse task with remote and local cwd (both defined)" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.hybrid]
        \\cmd = "python script.py"
        \\remote = "http://worker:5000"
        \\cwd = "/local/path"
        \\remote_cwd = "/remote/path"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("hybrid").?;
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("http://worker:5000", task.remote.?);
    try std.testing.expect(task.cwd != null);
    try std.testing.expectEqualStrings("/local/path", task.cwd.?);
    try std.testing.expect(task.remote_cwd != null);
    try std.testing.expectEqualStrings("/remote/path", task.remote_cwd.?);
}

test "parse task with SSH URI without port defaults to 22" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.ssh-default]
        \\cmd = "ls -la"
        \\remote = "ssh://user@example.com"
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("ssh-default").?;
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("ssh://user@example.com", task.remote.?);
}

test "parse task with HTTP remote and env vars set" {
    const allocator = std.testing.allocator;
    const toml_content =
        \\[tasks.http-task]
        \\cmd = "java -jar app.jar"
        \\remote = "https://api-gateway:8443"
        \\remote_env = { JVM_OPTS = "-Xmx2g" }
        \\env = { LOCAL_VAR = "local_value" }
    ;
    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("http-task").?;
    try std.testing.expect(task.remote != null);
    try std.testing.expectEqualStrings("https://api-gateway:8443", task.remote.?);

    // Check local env vars
    try std.testing.expectEqual(@as(usize, 1), task.env.len);
    try std.testing.expectEqualStrings("LOCAL_VAR", task.env[0][0]);
    try std.testing.expectEqualStrings("local_value", task.env[0][1]);

    // Check remote env vars
    try std.testing.expect(task.remote_env != null);
    try std.testing.expectEqual(@as(usize, 1), task.remote_env.?.len);
    try std.testing.expectEqualStrings("JVM_OPTS", task.remote_env.?[0][0]);
    try std.testing.expectEqualStrings("-Xmx2g", task.remote_env.?[0][1]);
}
