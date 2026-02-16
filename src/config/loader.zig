const std = @import("std");

pub const Config = struct {
    tasks: std.StringHashMap(Task),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .tasks = std.StringHashMap(Task).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        var it = self.tasks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.tasks.deinit();
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        return try parseToml(allocator, content);
    }
};

pub const Task = struct {
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: [][]const u8,

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.cmd);
        if (self.cwd) |cwd| allocator.free(cwd);
        if (self.description) |desc| allocator.free(desc);
        for (self.deps) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.deps);
    }
};

fn parseToml(allocator: std.mem.Allocator, content: []const u8) !Config {
    var config = Config.init(allocator);
    errdefer config.deinit();

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_task: ?[]const u8 = null;
    var task_cmd: ?[]const u8 = null;
    var task_cwd: ?[]const u8 = null;
    var task_desc: ?[]const u8 = null;
    var task_deps = std.ArrayList([]const u8).init(allocator);
    defer task_deps.deinit();

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "[tasks.")) {
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    try addTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items);
                }
            }

            task_deps.clearRetainingCapacity();
            task_cmd = null;
            task_cwd = null;
            task_desc = null;

            const start = "[tasks.".len;
            const end = std.mem.indexOf(u8, trimmed[start..], "]") orelse continue;
            current_task = try allocator.dupe(u8, trimmed[start..][0..end]);
        } else if (std.mem.indexOf(u8, trimmed, "=")) |eq_idx| {
            const key = std.mem.trim(u8, trimmed[0..eq_idx], " \t");
            var value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            if (std.mem.eql(u8, key, "cmd")) {
                task_cmd = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "cwd")) {
                task_cwd = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "description")) {
                task_desc = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "deps")) {
                if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                    const deps_str = value[1 .. value.len - 1];
                    var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                    while (deps_it.next()) |dep| {
                        const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                        if (trimmed_dep.len > 0) {
                            try task_deps.append(try allocator.dupe(u8, trimmed_dep));
                        }
                    }
                }
            }
        }
    }

    if (current_task) |task_name| {
        if (task_cmd) |cmd| {
            try addTask(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items);
        }
    }

    return config;
}

fn addTask(
    config: *Config,
    allocator: std.mem.Allocator,
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: [][]const u8,
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
    errdefer allocator.free(task_deps);

    for (deps, 0..) |dep, i| {
        task_deps[i] = try allocator.dupe(u8, dep);
    }

    const task = Task{
        .name = task_name,
        .cmd = task_cmd,
        .cwd = task_cwd,
        .description = task_desc,
        .deps = task_deps,
    };

    try config.tasks.put(task_name, task);
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
