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
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var config = try parseToml(allocator, content);
    errdefer config.deinit();

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
