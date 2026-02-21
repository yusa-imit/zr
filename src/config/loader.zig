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

    return try parseToml(allocator, content);
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
    try config.addWorkflow("my-workflow", "desc", &stages);

    const wf = config.workflows.get("my-workflow").?;
    try std.testing.expectEqualStrings("desc", wf.description.?);
    try std.testing.expectEqual(@as(usize, 1), wf.stages.len);
    try std.testing.expectEqualStrings("s1", wf.stages[0].name);
}
