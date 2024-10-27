const std = @import("std");
const Repository = @import("repository.zig").Repository;
const Task = @import("repository.zig").Task;
const TaskGroup = @import("repository.zig").TaskGroup;
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
    repos: ArrayList(*Repository),
    allocator: Allocator,

    pub fn init(allocator: Allocator) *Config {
        const config = allocator.create(Config) catch unreachable;
        config.* = .{
            .repos = ArrayList(*Repository).init(allocator),
            .allocator = allocator,
        };
        return config;
    }

    pub fn deinit(self: *Config) void {
        for (self.repos.items) |repo| {
            for (repo.tasks.items) |task| {
                for (task.groups.items) |group| {
                    for (group.commands.items) |cmd| {
                        self.allocator.free(cmd.command);
                        self.allocator.destroy(cmd);
                    }
                    group.commands.deinit();
                    self.allocator.destroy(group);
                }
                task.groups.deinit();
                self.allocator.free(task.name);
                self.allocator.destroy(task);
            }
            repo.tasks.deinit();
            self.allocator.free(repo.name);
            if (repo.path.len > 0) {
                self.allocator.free(repo.path);
            }
            self.allocator.destroy(repo);
        }
        self.repos.deinit();
        self.allocator.destroy(self);
    }

    pub fn parseConfig(self: *Config, lines: []const []const u8) !void {
        var current_repo: ?*Repository = null;

        var base_indent: usize = 0;
        var i: usize = 0;

        while (i < lines.len) : (i += 1) {
            const line = lines[i];
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            const indent = countLeadingSpaces(line);

            if (std.mem.eql(u8, trimmed, "repositories:")) {
                base_indent = indent;
                continue;
            }

            if (indent == base_indent + 2 and std.mem.startsWith(u8, trimmed, "- name:")) {
                // Handle previous repository
                if (current_repo) |repo| {
                    try self.repos.append(repo);
                }

                const name = std.mem.trim(u8, trimmed["- name:".len..], " ");
                const repo = try Repository.create(self.allocator, name, "");
                errdefer repo.deinit();
                current_repo = repo;

                i += 1;
                continue;
            }

            if (current_repo) |repo| {
                if (indent == base_indent + 4) {
                    if (std.mem.startsWith(u8, trimmed, "path:")) {
                        const path = std.mem.trim(u8, trimmed["path:".len..], " ");
                        repo.path = try self.allocator.dupe(u8, path);
                    } else if (std.mem.startsWith(u8, trimmed, "tasks:")) {
                        i = try parseTasksSection(self, repo, lines, i + 1, indent);
                    }
                }
            }
        }

        // Handle last repository
        if (current_repo) |repo| {
            try self.repos.append(repo);
        }
    }

    fn parseTasksSection(config: *Config, repo: *Repository, lines: []const []const u8, start_index: usize, base_indent: usize) !usize {
        var i = start_index;
        var current_task: ?*Task = null;
        var current_group: ?*TaskGroup = null;

        while (i < lines.len) {
            const line = lines[i];
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) {
                i += 1;
                continue;
            }

            const indent = countLeadingSpaces(line);
            if (indent <= base_indent - 2) break;

            if (indent == base_indent + 2 and std.mem.startsWith(u8, trimmed, "- ")) {
                // Handle previous task
                if (current_task) |task| {
                    if (task.groups.items.len > 0) {
                        try repo.addTask(task);
                    } else {
                        task.deinit();
                    }
                    current_task = null;
                }

                i = try parseTaskDefinition(config, repo, trimmed[2..], lines, i + 1, indent, &current_task, &current_group);
            }
            i += 1;
        }

        // Handle last task
        if (current_task) |task| {
            if (task.groups.items.len > 0) {
                try repo.addTask(task);
            } else {
                task.deinit();
            }
        }

        return i - 1;
    }

    fn parseTaskDefinition(
        config: *Config,
        repo: *Repository,
        line: []const u8,
        lines: []const []const u8,
        start_index: usize,
        base_indent: usize,
        current_task: *?*Task,
        current_group: *?*TaskGroup,
    ) !usize {
        _ = repo; // autofix
        if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
            const name = std.mem.trim(u8, line[0..colon_pos], " ");
            const task = try Task.create(config.allocator, name);
            errdefer task.deinit();

            var group = try task.addGroup();
            errdefer {
                if (task.groups.items.len > 0) {
                    group.deinit();
                }
                task.deinit();
            }

            current_task.* = task;
            current_group.* = group;

            const command = std.mem.trim(u8, line[colon_pos + 2 ..], " ");
            try group.addCommand(command);

            return start_index - 1;
        }

        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const name = std.mem.trim(u8, line[0..colon_pos], " ");
            const task = try Task.create(config.allocator, name);
            errdefer task.deinit();

            current_task.* = task;
            current_group.* = null;

            var i = start_index;
            while (i < lines.len) {
                const task_line = lines[i];
                const task_trimmed = std.mem.trim(u8, task_line, " \t\r");
                const task_indent = countLeadingSpaces(task_line);

                if (task_indent <= base_indent or task_trimmed.len == 0) break;

                if (std.mem.startsWith(u8, task_trimmed, "- task:")) {
                    if (current_group.*) |group| {
                        try task.groups.append(group);
                    }
                    current_group.* = try TaskGroup.create(config.allocator);
                } else if (current_group.* != null and std.mem.startsWith(u8, task_trimmed, "- ")) {
                    const cmd = std.mem.trim(u8, task_trimmed[2..], " ");
                    try current_group.*.?.addCommand(cmd);
                }

                i += 1;
            }

            // Handle last group
            if (current_group.*) |group| {
                try task.groups.append(group);
                current_group.* = null;
            }

            return i - 1;
        }

        return start_index;
    }

    fn countLeadingSpaces(line: []const u8) usize {
        var count: usize = 0;
        for (line) |c| {
            if (c == ' ') {
                count += 1;
            } else {
                break;
            }
        }
        return count;
    }

    pub fn load(allocator: Allocator) !*Config {
        var config = Config.init(allocator);
        errdefer config.deinit();

        const content = try readFile(allocator, CONFIG_FILENAME);
        defer allocator.free(content);

        var lines = ArrayList([]const u8).init(allocator);
        defer {
            for (lines.items) |line| {
                allocator.free(line);
            }
            lines.deinit();
        }

        var line_iter = std.mem.split(u8, content, "\n");
        while (line_iter.next()) |line| {
            const duped = try allocator.dupe(u8, line);
            errdefer allocator.free(duped);
            try lines.append(duped);
        }

        try config.parseConfig(lines.items);
        return config;
    }

    // 추가: findRepository 함수
    pub fn findRepository(self: *Config, name: []const u8) ?*Repository {
        for (self.repos.items) |repo| {
            if (std.mem.eql(u8, repo.name, name)) {
                return repo;
            }
        }
        return null;
    }

    // 추가: readFile 함수
    fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    }

    pub fn save(self: *const Config) !void {
        var buffer = ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.writeConfig(&buffer);

        const file = try std.fs.cwd().createFile(CONFIG_FILENAME, .{});
        defer file.close();
        try file.writeAll(buffer.items);
    }

    // 추가: findTask 함수
    pub fn findTask(self: *Repository, task_name: []const u8) ?*Task {
        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, task_name)) {
                return task;
            }
        }
        return null;
    }

    // 추가: printTasks 함수
    pub fn printTasks(self: *const Repository) void {
        if (self.tasks.items.len == 0) {
            std.debug.print("No tasks defined\n", .{});
            return;
        }

        std.debug.print("\nAvailable tasks:\n", .{});
        for (self.tasks.items) |task| {
            if (task.groups.items.len == 1 and task.groups.items[0].commands.items.len == 1) {
                // Simple task
                std.debug.print("  {s}: {s}\n", .{ task.name, task.groups.items[0].commands.items[0].command });
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
                    if (task.groups.items.len == 1 and task.groups.items[0].commands.items.len == 1) {
                        // Simple task
                        const command = task.groups.items[0].commands.items[0].command;
                        try writer.print("      - {s}: {s}\n", .{ task.name, command });
                    } else {
                        // Complex task
                        try writer.print("      - {s}:\n", .{task.name});
                        for (task.groups.items) |group| {
                            try writer.writeAll("          - task:\n");
                            for (group.commands.items) |cmd| {
                                try writer.print("            - {s}\n", .{cmd.command});
                            }
                        }
                    }
                }
            }
        }
    }
};
