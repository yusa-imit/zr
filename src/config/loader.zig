const std = @import("std");
pub const types = @import("types.zig");
pub const Config = types.Config;
pub const Task = types.Task;
pub const Stage = types.Stage;
pub const Workflow = types.Workflow;
pub const Profile = types.Profile;
pub const ProfileTaskOverride = types.ProfileTaskOverride;
pub const MatrixDim = types.MatrixDim;
pub const Workspace = types.Workspace;
pub const PluginConfig = types.PluginConfig;
pub const PluginSourceKind = types.PluginSourceKind;
pub const ToolSpec = types.ToolSpec;
pub const RemoteCacheConfig = types.RemoteCacheConfig;
pub const TaskHook = types.TaskHook;
pub const HookPoint = types.HookPoint;
pub const HookFailureStrategy = types.HookFailureStrategy;
pub const parseDurationMs = types.parseDurationMs;
pub const addTaskImpl = types.addTaskImpl;
const matrix_mod = @import("matrix.zig");
pub const addMatrixTask = matrix_mod.addMatrixTask;
const parser_mod = @import("parser.zig");
pub const parseToml = parser_mod.parseToml;

pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
    var visited_files = std.StringHashMap(void).init(allocator);
    defer {
        var it = visited_files.keyIterator();
        while (it.next()) |key| allocator.free(key.*);
        visited_files.deinit();
    }

    return loadFromFileInternal(allocator, path, &visited_files);
}

fn loadFromFileInternal(allocator: std.mem.Allocator, path: []const u8, visited: *std.StringHashMap(void)) !Config {
    // Get absolute path for cycle detection
    const abs_path = try std.fs.cwd().realpathAlloc(allocator, path);
    defer allocator.free(abs_path);

    // Check for circular imports
    if (visited.contains(abs_path)) {
        return error.CircularImport;
    }
    try visited.put(try allocator.dupe(u8, abs_path), {});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var config = try parseToml(allocator, content);
    errdefer config.deinit();

    // Process imports first (imported configs are merged before main config)
    if (config.imports.len > 0) {
        var import_error: ?anyerror = null;
        var loaded_imports = std.ArrayList(Config){};
        defer {
            for (loaded_imports.items) |*cfg| cfg.deinit();
            loaded_imports.deinit(allocator);
        }

        // Get directory of main config file for resolving relative paths
        const main_dir = std.fs.path.dirname(path) orelse ".";

        // Load each imported file
        for (config.imports) |import_rel_path| {
            // Resolve relative path from main config's directory
            const import_path = try std.fs.path.join(allocator, &[_][]const u8{ main_dir, import_rel_path });
            defer allocator.free(import_path);

            // Load imported config recursively
            if (loadFromFileInternal(allocator, import_path, visited)) |imported_config| {
                try loaded_imports.append(allocator, imported_config);
            } else |err| {
                import_error = err;
                break;
            }
        }

        if (import_error) |err| {
            return err;
        }

        // Merge all loaded imports into main config (main config takes precedence)
        for (loaded_imports.items) |*imported_config| {
            try mergeConfigs(allocator, &config, imported_config);
        }
    }

    // Auto-load .env file if enabled (v1.55.0)
    if (config.load_dotenv) {
        try loadDotenvIntoConfig(allocator, &config);
    }

    // Apply variable substitution to all task fields (v1.55.0)
    try applyVariableSubstitution(allocator, &config);

    // Resolve task mixins (v1.67.0) — apply mixin fields to tasks
    try resolveMixins(allocator, &config);

    // Validate task aliases (v1.72.0) — detect conflicts
    try validateTaskAliases(allocator, &config);

    return config;
}

/// Apply task mixins - compose mixin fields into tasks (v1.67.0).
/// Resolves nested mixins with DAG cycle detection.
/// Call this after parseToml(), before inheritWorkspaceSharedTasks().
pub fn resolveMixins(allocator: std.mem.Allocator, config: *Config) !void {
    // Iterate over all tasks and resolve their mixins
    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task_name = entry.key_ptr.*;
        const task = entry.value_ptr;

        if (task.mixins.len == 0) continue;

        // Resolve mixins left-to-right
        for (task.mixins) |mixin_name| {
            // Validate mixin exists
            var mixin_it = config.mixins.iterator();
            var found_mixin: ?*types.Mixin = null;
            while (mixin_it.next()) |mentry| {
                if (std.mem.eql(u8, mentry.key_ptr.*, mixin_name)) {
                    found_mixin = mentry.value_ptr;
                    break;
                }
            }

            if (found_mixin == null) {
                std.debug.print("error: Mixin '{s}' referenced by task '{s}' not found\n", .{ mixin_name, task_name });
                return error.UndefinedMixin;
            }
            const mixin = found_mixin.?;

            // Check for circular dependencies (cycle detection)
            var visited = std.StringHashMap(void).init(allocator);
            defer visited.deinit();
            if (try detectMixinCycle(allocator, config, mixin_name, &visited)) {
                std.debug.print("error: Circular mixin reference detected involving '{s}'\n", .{mixin_name});
                return error.CircularMixin;
            }

            // Apply mixin fields to task
            try applyMixinToTask(allocator, task, mixin);
        }
    }
}

/// Detect cyclic mixin dependencies using DFS (v1.67.0).
fn detectMixinCycle(
    allocator: std.mem.Allocator,
    config: *const Config,
    mixin_name: []const u8,
    visited: *std.StringHashMap(void),
) !bool {
    // Check if already visited (cycle detected)
    if (visited.contains(mixin_name)) {
        return true;
    }

    // Mark as visited
    try visited.put(try allocator.dupe(u8, mixin_name), {});
    defer {
        var it = visited.iterator();
        while (it.next()) |e| {
            if (!std.mem.eql(u8, e.key_ptr.*, mixin_name)) {
                allocator.free(e.key_ptr.*);
            }
        }
    }

    // Get the mixin
    const mixin = config.mixins.get(mixin_name) orelse return false;

    // Check nested mixins
    for (mixin.mixins) |nested_name| {
        if (try detectMixinCycle(allocator, config, nested_name, visited)) {
            return true;
        }
    }

    return false;
}

/// Apply a single mixin's fields to a task (v1.67.0).
fn applyMixinToTask(allocator: std.mem.Allocator, task: *Task, mixin: *const types.Mixin) !void {
    // Merge env: task overrides mixin
    if (mixin.env.len > 0) {
        var merged_env = std.StringHashMap([]const u8).init(allocator);
        defer merged_env.deinit();

        // First, add mixin env to map
        for (mixin.env) |pair| {
            try merged_env.put(pair[0], pair[1]);
        }

        // Then overlay task env (overriding mixin values)
        for (task.env) |pair| {
            try merged_env.put(pair[0], pair[1]);
        }

        // Rebuild task.env from merged map
        if (merged_env.count() > task.env.len) {
            const new_env = try allocator.alloc([2][]const u8, merged_env.count());
            var idx: usize = 0;
            var it = merged_env.iterator();
            while (it.next()) |e| {
                new_env[idx][0] = try allocator.dupe(u8, e.key_ptr.*);
                new_env[idx][1] = try allocator.dupe(u8, e.value_ptr.*);
                idx += 1;
            }

            // Free old env
            for (task.env) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            if (task.env.len > 0) allocator.free(task.env);

            task.env = new_env;
        }
    }

    // Concatenate deps: mixin first, then task
    if (mixin.deps.len > 0) {
        const new_deps = try allocator.alloc([]const u8, mixin.deps.len + task.deps.len);
        var idx: usize = 0;

        for (mixin.deps) |dep| {
            new_deps[idx] = try allocator.dupe(u8, dep);
            idx += 1;
        }
        for (task.deps) |dep| {
            new_deps[idx] = try allocator.dupe(u8, dep);
            idx += 1;
        }

        // Free old deps
        for (task.deps) |dep| {
            allocator.free(dep);
        }
        if (task.deps.len > 0) allocator.free(task.deps);

        task.deps = new_deps;
    }

    // Concatenate deps_serial
    if (mixin.deps_serial.len > 0) {
        const new_deps = try allocator.alloc([]const u8, mixin.deps_serial.len + task.deps_serial.len);
        var idx: usize = 0;

        for (mixin.deps_serial) |dep| {
            new_deps[idx] = try allocator.dupe(u8, dep);
            idx += 1;
        }
        for (task.deps_serial) |dep| {
            new_deps[idx] = try allocator.dupe(u8, dep);
            idx += 1;
        }

        // Free old deps_serial
        for (task.deps_serial) |dep| {
            allocator.free(dep);
        }
        if (task.deps_serial.len > 0) allocator.free(task.deps_serial);

        task.deps_serial = new_deps;
    }

    // Concatenate deps_optional
    if (mixin.deps_optional.len > 0) {
        const new_deps = try allocator.alloc([]const u8, mixin.deps_optional.len + task.deps_optional.len);
        var idx: usize = 0;

        for (mixin.deps_optional) |dep| {
            new_deps[idx] = try allocator.dupe(u8, dep);
            idx += 1;
        }
        for (task.deps_optional) |dep| {
            new_deps[idx] = try allocator.dupe(u8, dep);
            idx += 1;
        }

        // Free old deps_optional
        for (task.deps_optional) |dep| {
            allocator.free(dep);
        }
        if (task.deps_optional.len > 0) allocator.free(task.deps_optional);

        task.deps_optional = new_deps;
    }

    // Concatenate deps_if
    if (mixin.deps_if.len > 0) {
        const new_deps_if = try allocator.alloc(types.ConditionalDep, mixin.deps_if.len + task.deps_if.len);
        var idx: usize = 0;

        for (mixin.deps_if) |dep| {
            new_deps_if[idx].task = try allocator.dupe(u8, dep.task);
            new_deps_if[idx].condition = try allocator.dupe(u8, dep.condition);
            idx += 1;
        }
        for (task.deps_if) |dep| {
            new_deps_if[idx].task = try allocator.dupe(u8, dep.task);
            new_deps_if[idx].condition = try allocator.dupe(u8, dep.condition);
            idx += 1;
        }

        // Free old deps_if
        for (task.deps_if) |*dep| {
            dep.deinit(allocator);
        }
        if (task.deps_if.len > 0) allocator.free(task.deps_if);

        task.deps_if = new_deps_if;
    }

    // Union tags: combine and deduplicate
    if (mixin.tags.len > 0) {
        var tag_map = std.StringHashMap(void).init(allocator);
        defer tag_map.deinit();

        // Add mixin tags
        for (mixin.tags) |tag| {
            try tag_map.put(tag, {});
        }
        // Add task tags
        for (task.tags) |tag| {
            try tag_map.put(tag, {});
        }

        if (tag_map.count() > task.tags.len) {
            const new_tags = try allocator.alloc([]const u8, tag_map.count());
            var idx: usize = 0;
            var it = tag_map.iterator();
            while (it.next()) |e| {
                new_tags[idx] = try allocator.dupe(u8, e.key_ptr.*);
                idx += 1;
            }

            // Free old tags
            for (task.tags) |tag| {
                allocator.free(tag);
            }
            if (task.tags.len > 0) allocator.free(task.tags);

            task.tags = new_tags;
        }
    }

    // Concatenate hooks: mixin first, then task
    if (mixin.hooks.len > 0) {
        const new_hooks = try allocator.alloc(types.TaskHook, mixin.hooks.len + task.hooks.len);
        var idx: usize = 0;

        for (mixin.hooks) |hook| {
            new_hooks[idx] = try copyTaskHookImpl(allocator, &hook);
            idx += 1;
        }
        for (task.hooks) |hook| {
            new_hooks[idx] = try copyTaskHookImpl(allocator, &hook);
            idx += 1;
        }

        // Free old hooks
        for (task.hooks) |*hook| {
            hook.deinit(allocator);
        }
        if (task.hooks.len > 0) allocator.free(task.hooks);

        task.hooks = new_hooks;
    }

    // Override fields: task wins if set
    if (mixin.cmd != null and task.cmd.len == 0) {
        task.cmd = try allocator.dupe(u8, mixin.cmd.?);
    }
    if (mixin.cwd != null and task.cwd == null) {
        task.cwd = try allocator.dupe(u8, mixin.cwd.?);
    }
    if (mixin.description != null and task.description == null) {
        task.description = try allocator.dupe(u8, mixin.description.?);
    }
    if (mixin.timeout_ms != null and task.timeout_ms == null) {
        task.timeout_ms = mixin.timeout_ms;
    }
    if (mixin.retry_max > 0 and task.retry_max == 0) {
        task.retry_max = mixin.retry_max;
    }
    if (mixin.retry_delay_ms > 0 and task.retry_delay_ms == 0) {
        task.retry_delay_ms = mixin.retry_delay_ms;
    }
    if (mixin.retry_backoff_multiplier != null and task.retry_backoff_multiplier == null) {
        task.retry_backoff_multiplier = mixin.retry_backoff_multiplier;
    }
    if (mixin.retry_jitter and !task.retry_jitter) {
        task.retry_jitter = true;
    }
    if (mixin.max_backoff_ms != null and task.max_backoff_ms == null) {
        task.max_backoff_ms = mixin.max_backoff_ms;
    }
    if (mixin.template != null and task.template == null) {
        task.template = try allocator.dupe(u8, mixin.template.?);
    }
}

/// Helper to copy a TaskHook in mixin resolution (v1.67.0).
fn copyTaskHookImpl(allocator: std.mem.Allocator, hook: *const types.TaskHook) !types.TaskHook {
    const cmd = try allocator.dupe(u8, hook.cmd);
    errdefer allocator.free(cmd);
    const wd = if (hook.working_dir) |w| try allocator.dupe(u8, w) else null;
    errdefer if (wd) |w| allocator.free(w);

    const env = try allocator.alloc([2][]const u8, hook.env.len);
    var env_duped: usize = 0;
    errdefer {
        for (env[0..env_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(env);
    }
    for (hook.env, 0..) |pair, i| {
        env[i][0] = try allocator.dupe(u8, pair[0]);
        env[i][1] = try allocator.dupe(u8, pair[1]);
        env_duped += 1;
    }

    return types.TaskHook{
        .cmd = cmd,
        .point = hook.point,
        .failure_strategy = hook.failure_strategy,
        .working_dir = wd,
        .env = env,
    };
}

/// Merge workspace shared tasks into a member config (v1.63.0).
/// Shared tasks are inherited unless the member defines a task with the same name (override).
/// Call this after loading both workspace root and member configs.
pub fn inheritWorkspaceSharedTasks(
    allocator: std.mem.Allocator,
    member_config: *Config,
    workspace_config: *const Config,
) !void {
    // If workspace has no shared tasks, nothing to inherit
    if (workspace_config.workspace == null) return;
    const workspace = workspace_config.workspace.?;

    // Iterate over workspace shared tasks
    var shared_it = workspace.shared_tasks.iterator();
    while (shared_it.next()) |entry| {
        const task_name = entry.key_ptr.*;
        const shared_task = entry.value_ptr.*;

        // Skip if member already defines this task (member overrides workspace)
        if (member_config.tasks.contains(task_name)) {
            continue;
        }

        // Deep copy the shared task into member's task map
        const task_name_copy = try allocator.dupe(u8, task_name);
        errdefer allocator.free(task_name_copy);

        var task_copy = try copyTask(allocator, &shared_task);
        errdefer task_copy.deinit(allocator);

        // Mark as inherited for display in `zr list`
        task_copy.inherited = true;

        try member_config.tasks.put(task_name_copy, task_copy);
    }
}

/// Deep copy a task (v1.63.0 helper for shared task inheritance).
fn copyTask(allocator: std.mem.Allocator, task: *const Task) !Task {
    var result = task.*;

    // Deep copy all owned strings and slices
    result.name = try allocator.dupe(u8, task.name);
    result.cmd = try allocator.dupe(u8, task.cmd);
    result.cwd = if (task.cwd) |c| try allocator.dupe(u8, c) else null;
    result.description = if (task.description) |d| try allocator.dupe(u8, d) else null;

    // Copy dependency arrays
    result.deps = try allocator.alloc([]const u8, task.deps.len);
    for (task.deps, 0..) |dep, i| {
        result.deps[i] = try allocator.dupe(u8, dep);
    }

    result.deps_serial = try allocator.alloc([]const u8, task.deps_serial.len);
    for (task.deps_serial, 0..) |dep, i| {
        result.deps_serial[i] = try allocator.dupe(u8, dep);
    }

    result.deps_optional = try allocator.alloc([]const u8, task.deps_optional.len);
    for (task.deps_optional, 0..) |dep, i| {
        result.deps_optional[i] = try allocator.dupe(u8, dep);
    }

    // Copy environment variables
    result.env = try allocator.alloc([2][]const u8, task.env.len);
    for (task.env, 0..) |pair, i| {
        result.env[i][0] = try allocator.dupe(u8, pair[0]);
        result.env[i][1] = try allocator.dupe(u8, pair[1]);
    }

    return result;
}

/// Load .env file from project root and merge into all task environments.
/// Silently ignores if .env file doesn't exist.
fn loadDotenvIntoConfig(allocator: std.mem.Allocator, config: *Config) !void {
    const dotenv_mod = @import("dotenv.zig");

    // Try to read .env file (project root)
    const dotenv_file = std.fs.cwd().openFile(".env", .{}) catch |err| {
        if (err == error.FileNotFound) return; // Silently ignore if .env doesn't exist
        return err;
    };
    defer dotenv_file.close();

    const dotenv_content = dotenv_file.readToEndAlloc(allocator, 1024 * 1024) catch {
        // If read fails, just skip .env loading
        return;
    };
    defer allocator.free(dotenv_content);

    var env_map = dotenv_mod.parseDotenv(allocator, dotenv_content) catch {
        // If parse fails, skip .env loading (malformed .env)
        return;
    };
    defer dotenv_mod.deinitDotenv(&env_map, allocator);

    // Merge .env variables into all task environments
    var task_it = config.tasks.valueIterator();
    while (task_it.next()) |task_ptr| {
        try mergeEnvIntoTask(allocator, task_ptr, &env_map);
    }
}

/// Apply variable substitution (${VAR} expansion) to all task fields.
/// Expands cmd, cwd, and env value fields using task's environment + process env.
fn applyVariableSubstitution(allocator: std.mem.Allocator, config: *Config) !void {
    const varsubst_mod = @import("varsubst.zig");

    var task_it = config.tasks.valueIterator();
    while (task_it.next()) |task_ptr| {
        // Build environment map from task.env + process env
        var env_map = std.StringHashMap([]const u8).init(allocator);
        defer env_map.deinit();

        // Add task-specific env (takes precedence)
        for (task_ptr.env) |kv| {
            try env_map.put(kv[0], kv[1]);
        }

        // Substitute in cmd
        const new_cmd = try varsubst_mod.substitute(allocator, task_ptr.cmd, &env_map);
        allocator.free(task_ptr.cmd);
        task_ptr.cmd = new_cmd;

        // Substitute in cwd
        if (task_ptr.cwd) |cwd| {
            const new_cwd = try varsubst_mod.substitute(allocator, cwd, &env_map);
            allocator.free(cwd);
            task_ptr.cwd = new_cwd;
        }

        // Substitute in env values (keys stay the same)
        for (task_ptr.env) |*kv| {
            const new_value = try varsubst_mod.substitute(allocator, kv[1], &env_map);
            allocator.free(kv[1]);
            kv[1] = new_value;
        }
    }
}

/// Merge environment variables from .env into a task's env.
/// Task-specific env takes precedence over .env values.
fn mergeEnvIntoTask(allocator: std.mem.Allocator, task: *Task, env_map: *std.StringHashMap([]const u8)) !void {
    // Build set of existing keys in task.env
    var existing_keys = std.StringHashMap(void).init(allocator);
    defer existing_keys.deinit();

    for (task.env) |kv| {
        try existing_keys.put(kv[0], {});
    }

    // Count new keys from .env that aren't in task.env
    var new_count: usize = 0;
    var env_it = env_map.iterator();
    while (env_it.next()) |entry| {
        if (!existing_keys.contains(entry.key_ptr.*)) {
            new_count += 1;
        }
    }

    if (new_count == 0) return; // No new keys to add

    // Allocate new env array with space for existing + new
    const new_env = try allocator.alloc([2][]const u8, task.env.len + new_count);

    // Copy existing env
    @memcpy(new_env[0..task.env.len], task.env);

    // Free old env array (but not the strings, they're still referenced)
    if (task.env.len > 0) allocator.free(task.env);

    // Add new keys from .env
    var idx = task.env.len;
    env_it = env_map.iterator();
    while (env_it.next()) |entry| {
        if (!existing_keys.contains(entry.key_ptr.*)) {
            new_env[idx] = .{
                try allocator.dupe(u8, entry.key_ptr.*),
                try allocator.dupe(u8, entry.value_ptr.*),
            };
            idx += 1;
        }
    }

    task.env = new_env;
}

/// Merge imported config into main config.
/// Main config's definitions override imported ones (no overwriting).
/// Transfers ownership from imported to main (imported will be left empty).
fn mergeConfigs(allocator: std.mem.Allocator, main: *Config, imported: *Config) !void {
    _ = allocator;

    // Merge tasks (transfer ownership if not in main)
    var task_it = imported.tasks.iterator();
    while (task_it.next()) |entry| {
        if (!main.tasks.contains(entry.key_ptr.*)) {
            // Transfer ownership: remove from imported, put into main
            const result = imported.tasks.fetchRemove(entry.key_ptr.*);
            if (result) |kv| {
                try main.tasks.put(kv.key, kv.value);
            }
        }
    }

    // Merge workflows (transfer ownership if not in main)
    var workflow_it = imported.workflows.iterator();
    while (workflow_it.next()) |entry| {
        if (!main.workflows.contains(entry.key_ptr.*)) {
            const result = imported.workflows.fetchRemove(entry.key_ptr.*);
            if (result) |kv| {
                try main.workflows.put(kv.key, kv.value);
            }
        }
    }

    // Merge profiles (transfer ownership if not in main)
    var profile_it = imported.profiles.iterator();
    while (profile_it.next()) |entry| {
        if (!main.profiles.contains(entry.key_ptr.*)) {
            const result = imported.profiles.fetchRemove(entry.key_ptr.*);
            if (result) |kv| {
                try main.profiles.put(kv.key, kv.value);
            }
        }
    }

    // Merge templates (transfer ownership if not in main)
    var template_it = imported.templates.iterator();
    while (template_it.next()) |entry| {
        if (!main.templates.contains(entry.key_ptr.*)) {
            const result = imported.templates.fetchRemove(entry.key_ptr.*);
            if (result) |kv| {
                try main.templates.put(kv.key, kv.value);
            }
        }
    }
}

/// Discover workspace members from a glob pattern.
/// Returns owned slice of discovered member paths.
pub fn discoverWorkspaceMembers(allocator: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
    const glob_mod = @import("../util/glob.zig");

    var members = std.ArrayList([]const u8){};
    errdefer {
        for (members.items) |m| allocator.free(m);
        members.deinit(allocator);
    }

    // Build pattern for finding zr.toml files in member directories
    var pattern_buf: [std.fs.max_path_bytes]u8 = undefined;
    const toml_pattern = try std.fmt.bufPrint(&pattern_buf, "{s}/zr.toml", .{pattern});

    // Use glob to find matching zr.toml files
    const cwd = std.fs.cwd();
    const matches = try glob_mod.find(allocator, cwd, toml_pattern);
    defer {
        for (matches) |m| allocator.free(m);
        allocator.free(matches);
    }

    // Extract directory paths from zr.toml paths
    for (matches) |match_path| {
        // Remove "/zr.toml" suffix to get member directory
        if (std.mem.endsWith(u8, match_path, "/zr.toml")) {
            const dir_path = match_path[0 .. match_path.len - "/zr.toml".len];
            const owned_path = try allocator.dupe(u8, dir_path);
            try members.append(allocator, owned_path);
        }
    }

    const owned = try allocator.alloc([]const u8, members.items.len);
    @memcpy(owned, members.items);
    members.clearRetainingCapacity();
    return owned;
}

test "parseDurationMs: various units" {
    try std.testing.expectEqual(@as(?u64, 500), parseDurationMs("500ms"));
    try std.testing.expectEqual(@as(?u64, 30_000), parseDurationMs("30s"));
    try std.testing.expectEqual(@as(?u64, 5 * 60_000), parseDurationMs("5m"));
    try std.testing.expectEqual(@as(?u64, 2 * 3_600_000), parseDurationMs("2h"));
    try std.testing.expectEqual(@as(?u64, null), parseDurationMs(""));
    try std.testing.expectEqual(@as(?u64, null), parseDurationMs("xyz"));
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

/// Validate task aliases for conflicts (v1.72.0).
/// Checks that no alias conflicts with:
/// - An existing task name
/// - Another alias in the same task
/// - An alias in a different task
fn validateTaskAliases(allocator: std.mem.Allocator, config: *Config) !void {
    // Build a map of all task names and aliases
    var name_map = std.StringHashMap([]const u8).init(allocator);
    defer name_map.deinit();

    // First pass: register all task names
    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task_name = entry.key_ptr.*;
        try name_map.put(task_name, task_name);
    }

    // Second pass: check aliases for conflicts
    task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task_name = entry.key_ptr.*;
        const task = entry.value_ptr;

        if (task.aliases.len == 0) continue;

        // Check each alias
        for (task.aliases) |alias| {
            // Check if alias conflicts with a task name
            if (name_map.get(alias)) |conflicting_task| {
                std.debug.print("error: Alias '{s}' in task '{s}' conflicts with existing task '{s}'\n", .{ alias, task_name, conflicting_task });
                return error.AliasConflict;
            }

            // Check if alias already used by this validation pass (duplicate within task or across tasks)
            if (name_map.contains(alias)) {
                const existing_owner = name_map.get(alias).?;
                std.debug.print("error: Alias '{s}' in task '{s}' conflicts with alias in task '{s}'\n", .{ alias, task_name, existing_owner });
                return error.AliasConflict;
            }

            // Register this alias
            try name_map.put(alias, task_name);
        }
    }
}

test "validateTaskAliases: no conflicts with valid aliases" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Task with aliases that don't conflict
    try config.addTask("build", "zig build", null, null, &[_][]const u8{});
    var build_task = config.tasks.getPtr("build").?;
    var build_aliases = std.ArrayList([]const u8){};
    defer build_aliases.deinit(allocator);
    try build_aliases.append(allocator, try allocator.dupe(u8, "b"));
    try build_aliases.append(allocator, try allocator.dupe(u8, "compile"));
    build_task.aliases = try build_aliases.toOwnedSlice(allocator);

    try config.addTask("test", "zig build test", null, null, &[_][]const u8{});
    var test_task = config.tasks.getPtr("test").?;
    var test_aliases = std.ArrayList([]const u8){};
    defer test_aliases.deinit(allocator);
    try test_aliases.append(allocator, try allocator.dupe(u8, "t"));
    try test_aliases.append(allocator, try allocator.dupe(u8, "check"));
    test_task.aliases = try test_aliases.toOwnedSlice(allocator);

    // Should not error
    try validateTaskAliases(allocator, &config);
}

test "validateTaskAliases: alias conflicts with task name" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTask("build", "zig build", null, null, &[_][]const u8{});
    try config.addTask("test", "zig build test", null, null, &[_][]const u8{});

    // Alias "test" conflicts with task name "test"
    var build_task = config.tasks.getPtr("build").?;
    var aliases = std.ArrayList([]const u8){};
    defer aliases.deinit(allocator);
    try aliases.append(allocator, try allocator.dupe(u8, "test"));
    build_task.aliases = try aliases.toOwnedSlice(allocator);

    const result = validateTaskAliases(allocator, &config);
    try std.testing.expectError(error.AliasConflict, result);
}

test "validateTaskAliases: duplicate alias across tasks" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTask("build", "zig build", null, null, &[_][]const u8{});
    var build_task = config.tasks.getPtr("build").?;
    var build_aliases = std.ArrayList([]const u8){};
    defer build_aliases.deinit(allocator);
    try build_aliases.append(allocator, try allocator.dupe(u8, "b"));
    build_task.aliases = try build_aliases.toOwnedSlice(allocator);

    try config.addTask("benchmark", "zig build benchmark", null, null, &[_][]const u8{});
    var bench_task = config.tasks.getPtr("benchmark").?;
    var bench_aliases = std.ArrayList([]const u8){};
    defer bench_aliases.deinit(allocator);
    try bench_aliases.append(allocator, try allocator.dupe(u8, "b")); // duplicate!
    bench_task.aliases = try bench_aliases.toOwnedSlice(allocator);

    const result = validateTaskAliases(allocator, &config);
    try std.testing.expectError(error.AliasConflict, result);
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
    try config.addWorkflow("my-workflow", "desc", &stages, null);

    const wf = config.workflows.get("my-workflow").?;
    try std.testing.expectEqualStrings("desc", wf.description.?);
    try std.testing.expectEqual(@as(usize, 1), wf.stages.len);
    try std.testing.expectEqualStrings("s1", wf.stages[0].name);
}
