const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const TaskCommand = struct {
    command: []const u8,
    allocator: Allocator,

    pub fn create(allocator: Allocator, command: []const u8) !*TaskCommand {
        const cmd = try allocator.create(TaskCommand);
        errdefer allocator.destroy(cmd);
        const cmd_str = try allocator.dupe(u8, command);
        errdefer allocator.free(cmd_str);

        cmd.* = .{
            .command = cmd_str,
            .allocator = allocator,
        };
        return cmd;
    }

    pub fn deinit(self: *TaskCommand) void {
        self.allocator.free(self.command);
        self.allocator.destroy(self);
    }
};

pub const TaskGroup = struct {
    commands: ArrayList(*TaskCommand),
    allocator: Allocator,

    pub fn create(allocator: Allocator) !*TaskGroup {
        const group = try allocator.create(TaskGroup);
        errdefer allocator.destroy(group);

        group.* = .{
            .commands = ArrayList(*TaskCommand).init(allocator),
            .allocator = allocator,
        };
        return group;
    }

    pub fn deinit(self: *TaskGroup) void {
        for (self.commands.items) |cmd| {
            cmd.deinit(); // TaskCommand의 deinit 호출
        }
        self.commands.deinit();
        self.allocator.destroy(self);
    }

    pub fn addCommand(self: *TaskGroup, command: []const u8) !void {
        const cmd = try TaskCommand.create(self.allocator, command);
        errdefer cmd.deinit();
        try self.commands.append(cmd);
    }
};

pub const Task = struct {
    name: []const u8,
    groups: ArrayList(*TaskGroup),
    allocator: Allocator,

    pub fn create(allocator: Allocator, name: []const u8) !*Task {
        const task = try allocator.create(Task);
        errdefer allocator.destroy(task);

        const task_name = try allocator.dupe(u8, name);
        errdefer allocator.free(task_name);

        task.* = .{
            .name = task_name,
            .groups = ArrayList(*TaskGroup).init(allocator),
            .allocator = allocator,
        };
        return task;
    }

    pub fn deinit(self: *Task) void {
        for (self.groups.items) |group| {
            group.deinit(); // TaskGroup의 deinit 호출
        }
        self.groups.deinit();
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    pub fn addGroup(self: *Task) !*TaskGroup {
        const group = try TaskGroup.create(self.allocator);
        errdefer group.deinit();
        try self.groups.append(group);
        return group;
    }
};

pub const Repository = struct {
    name: []const u8,
    path: []const u8,
    tasks: ArrayList(*Task),
    allocator: Allocator,

    pub fn create(allocator: Allocator, name: []const u8, path: []const u8) !*Repository {
        const repo = try allocator.create(Repository);
        errdefer allocator.destroy(repo);

        const repo_name = try allocator.dupe(u8, name);
        errdefer allocator.free(repo_name);

        const repo_path = try allocator.dupe(u8, path);
        errdefer allocator.free(repo_path);

        repo.* = .{
            .name = repo_name,
            .path = repo_path,
            .tasks = ArrayList(*Task).init(allocator),
            .allocator = allocator,
        };
        return repo;
    }

    pub fn deinit(self: *Repository) void {
        // 모든 Task들의 deinit을 호출
        for (self.tasks.items) |task| {
            task.deinit();
        }
        // ArrayList 자체를 해제
        self.tasks.deinit();
        // 문자열 메모리 해제
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        // Repository 구조체 자체를 해제
        self.allocator.destroy(self);
    }

    pub fn addTask(self: *Repository, task: *Task) !void {
        errdefer task.deinit();
        try self.tasks.append(task);
    }

    pub fn findTask(self: *Repository, task_name: []const u8) ?*Task {
        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, task_name)) {
                return task;
            }
        }
        return null;
    }

    pub fn printTasks(self: *const Repository) void {
        if (self.tasks.items.len == 0) {
            std.debug.print("No tasks defined\n", .{});
            return;
        }

        std.debug.print("\nAvailable tasks:\n", .{});
        for (self.tasks.items) |task| {
            if (task.groups.items.len == 1 and task.groups.items[0].commands.items.len == 1) {
                // Simple task
                std.debug.print("  {s}: {s}\n", .{
                    task.name,
                    task.groups.items[0].commands.items[0].command,
                });
            } else {
                // Complex task
                std.debug.print("  {s}:\n", .{task.name});
                for (task.groups.items, 0..) |group, i| {
                    std.debug.print("    group {d}:\n", .{i + 1});
                    for (group.commands.items) |cmd| {
                        std.debug.print("      - {s}\n", .{cmd.command});
                    }
                }
            }
        }
    }
};

test "Repository creation and task management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var repo = try Repository.create(allocator, "test-repo", "./test/path");
    defer repo.deinit();

    try testing.expectEqualStrings("test-repo", repo.name);
    try testing.expectEqualStrings("./test/path", repo.path);
    try testing.expectEqual(@as(usize, 0), repo.tasks.items.len);

    // Test adding a task
    var task = try Task.create(allocator, "build");
    var group = try task.addGroup();
    try group.addCommand("npm run build");
    
    try repo.addTask(task);
    try testing.expectEqual(@as(usize, 1), repo.tasks.items.len);

    // Test finding task
    const found_task = repo.findTask("build");
    try testing.expect(found_task != null);
    try testing.expectEqualStrings("build", found_task.?.name);

    // Test task not found
    const not_found = repo.findTask("nonexistent");
    try testing.expect(not_found == null);
}

test "Task and TaskGroup functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task = try Task.create(allocator, "test-task");
    defer task.deinit();

    try testing.expectEqualStrings("test-task", task.name);
    try testing.expectEqual(@as(usize, 0), task.groups.items.len);

    // Add first group
    var group1 = try task.addGroup();
    try group1.addCommand("echo hello");
    try group1.addCommand("echo world");

    // Add second group
    var group2 = try task.addGroup();
    try group2.addCommand("npm run test");

    try testing.expectEqual(@as(usize, 2), task.groups.items.len);
    try testing.expectEqual(@as(usize, 2), task.groups.items[0].commands.items.len);
    try testing.expectEqual(@as(usize, 1), task.groups.items[1].commands.items.len);
    
    try testing.expectEqualStrings("echo hello", task.groups.items[0].commands.items[0].command);
    try testing.expectEqualStrings("echo world", task.groups.items[0].commands.items[1].command);
    try testing.expectEqualStrings("npm run test", task.groups.items[1].commands.items[0].command);
}
