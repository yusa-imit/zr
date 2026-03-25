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

    return config;
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
