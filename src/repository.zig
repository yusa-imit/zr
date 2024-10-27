const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Task = struct {
    name: []const u8,
    command: []const u8,

    pub fn create(allocator: Allocator, name: []const u8, command: []const u8) !Task {
        return Task{
            .name = try allocator.dupe(u8, name),
            .command = try allocator.dupe(u8, command),
        };
    }

    pub fn deinit(self: Task, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.command);
    }

    pub fn clone(self: Task, allocator: Allocator) !Task {
        return try Task.create(allocator, self.name, self.command);
    }
};

pub const Repository = struct {
    name: []const u8,
    path: []const u8,
    tasks: ArrayList(Task),
    allocator: Allocator,

    pub fn create(allocator: Allocator, name: []const u8, path: []const u8) !Repository {
        return Repository{
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .tasks = ArrayList(Task).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Repository, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
        for (self.tasks.items) |task| {
            task.deinit(allocator);
        }
        self.tasks.deinit();
    }

    pub fn findTask(self: *const Repository, task_name: []const u8) !?Task {
        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, task_name)) {
                return try task.clone(self.allocator);
            }
        }
        return null;
    }

    pub fn addTask(self: *Repository, name: []const u8, command: []const u8) !void {
        const task = try Task.create(self.allocator, name, command);
        try self.tasks.append(task);
    }
};
