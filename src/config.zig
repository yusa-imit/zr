const std = @import("std");
const Repository = @import("repository.zig").Repository;
const Task = @import("repository.zig").Task;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const fs = std.fs;

pub const ConfigError = error{
    ConfigNotInitialized,
    TaskNotFound,
    InvalidTaskDefinition,
} || std.fs.File.OpenError || std.fs.File.ReadError || std.mem.Allocator.Error;

pub const CONFIG_FILENAME = ".zr.config.yaml";

pub const Config = struct {
    repos: ArrayList(Repository),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Config {
        return .{
            .repos = ArrayList(Repository).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        for (self.repos.items) |repo| {
            repo.deinit(self.allocator);
        }
        self.repos.deinit();
    }

    pub fn findRepository(self: *Config, name: []const u8) ?*Repository {
        for (self.repos.items) |*repo| {
            if (std.mem.eql(u8, repo.name, name)) {
                return repo;
            }
        }
        return null;
    }

    pub fn load(allocator: Allocator) !Config {
        var config = Config.init(allocator);
        errdefer config.deinit();

        const content = readFile(allocator, CONFIG_FILENAME) catch |err| {
            if (err == error.FileNotFound) {
                return error.ConfigNotInitialized;
            }
            return err;
        };
        defer allocator.free(content);

        try parseConfig(&config, content);

        return config;
    }

    pub fn save(self: *const Config) !void {
        var buffer = ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.writeConfig(&buffer);

        const file = try fs.cwd().createFile(CONFIG_FILENAME, .{});
        defer file.close();
        try file.writeAll(buffer.items);
    }

    fn parseConfig(config: *Config, content: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");
        var current_repo: ?*Repository = null;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            if (std.mem.eql(u8, trimmed, "repositories:")) {
                continue;
            }

            if (std.mem.startsWith(u8, trimmed, "- name:")) {
                const name = std.mem.trim(u8, trimmed["- name:".len..], " ");
                if (lines.next()) |path_line| {
                    const path_trimmed = std.mem.trim(u8, path_line, " \t\r");
                    if (std.mem.startsWith(u8, path_trimmed, "path:")) {
                        const path = std.mem.trim(u8, path_trimmed["path:".len..], " ");
                        const repo = try Repository.create(config.allocator, name, path);
                        try config.repos.append(repo);
                        current_repo = &config.repos.items[config.repos.items.len - 1];
                    }
                }
            } else if (std.mem.startsWith(u8, trimmed, "tasks:") and current_repo != null) {
                while (lines.next()) |task_line| {
                    const task_trimmed = std.mem.trim(u8, task_line, " \t\r");
                    if (!std.mem.startsWith(u8, task_trimmed, "- ")) break;
                    try parseTask(config.allocator, task_trimmed, &current_repo.?.tasks);
                }
            }
        }
    }

    fn parseTask(allocator: Allocator, line: []const u8, tasks: *ArrayList(Task)) !void {
        var parts = std.mem.split(u8, line[2..], ":");
        if (parts.next()) |name| {
            const task_name = std.mem.trim(u8, name, " ");
            if (parts.next()) |command| {
                const task_command = std.mem.trim(u8, command, " ");
                const task = try Task.create(allocator, task_name, task_command);
                try tasks.append(task);
            }
        }
    }

    fn writeConfig(self: *const Config, buffer: *ArrayList(u8)) !void {
        const writer = buffer.writer();
        try writer.writeAll("# zr configuration file\n");
        try writer.writeAll("repositories:\n");

        for (self.repos.items) |repo| {
            try writer.print("  - name: {s}\n", .{repo.name});
            try writer.print("    path: {s}\n", .{repo.path});
            if (repo.tasks.items.len > 0) {
                try writer.writeAll("    tasks:\n");
                for (repo.tasks.items) |task| {
                    try writer.print("      - {s}: {s}\n", .{ task.name, task.command });
                }
            }
        }
    }
};

fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}
