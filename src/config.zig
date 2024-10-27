const std = @import("std");
const testing = std.testing;
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
                if (current_repo) |repo| {
                    try self.repos.append(repo);
                }

                // Extract name correctly
                const name = std.mem.trim(u8, trimmed["- name:".len..], " \t\r");
                var repo = try Repository.create(self.allocator, name, "");
                errdefer repo.deinit();
                current_repo = repo;

                // Process next lines for path and tasks
                var next_i = i + 1;
                while (next_i < lines.len) : (next_i += 1) {
                    const next_line = lines[next_i];
                    const next_trimmed = std.mem.trim(u8, next_line, " \t\r");
                    const next_indent = countLeadingSpaces(next_line);

                    if (next_indent == base_indent + 4) {
                        if (std.mem.startsWith(u8, next_trimmed, "path:")) {
                            const path = std.mem.trim(u8, next_trimmed["path:".len..], " \t\r");
                            // Update repository path
                            if (repo.path.len > 0) {
                                self.allocator.free(repo.path);
                            }
                            repo.path = try self.allocator.dupe(u8, path);
                        } else if (std.mem.startsWith(u8, next_trimmed, "tasks:")) {
                            i = try parseTasksSection(self, repo, lines, next_i + 1, next_indent);
                            break;
                        }
                    } else if (next_indent <= base_indent + 2) {
                        i = next_i - 1;
                        break;
                    }
                }
                i = next_i;
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

        std.debug.print("Parsing tasks section starting at line {d}\n", .{start_index});

        while (i < lines.len) {
            const line = lines[i];
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) {
                i += 1;
                continue;
            }

            const indent = countLeadingSpaces(line);
            std.debug.print("Processing line {d}: '{s}' (indent: {d})\n", .{ i, trimmed, indent });

            if (indent <= base_indent - 2) break;

            if (indent == base_indent + 2 and std.mem.startsWith(u8, trimmed, "- ")) {
                // Handle previous task
                if (current_task) |task| {
                    if (task.groups.items.len > 0) {
                        try repo.addTask(task);
                        std.debug.print("Added task '{s}' with {d} groups\n", .{ task.name, task.groups.items.len });
                    } else {
                        task.deinit();
                        std.debug.print("Discarded empty task\n", .{});
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
                std.debug.print("Added final task '{s}' with {d} groups\n", .{ task.name, task.groups.items.len });
            } else {
                task.deinit();
                std.debug.print("Discarded final empty task\n", .{});
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
        _ = repo;

        std.debug.print("Parsing task definition: '{s}'\n", .{line});

        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const name = std.mem.trim(u8, line[0..colon_pos], " ");
            const value = if (colon_pos + 1 < line.len)
                std.mem.trim(u8, line[colon_pos + 1 ..], " :")
            else
                "";

            std.debug.print("Found task name: '{s}', value: '{s}'\n", .{ name, value });

            var task = try Task.create(config.allocator, name);
            errdefer task.deinit();

            if (value.len > 0) {
                // Simple task
                var group = try task.addGroup();
                try group.addCommand(value);
                current_task.* = task;
                current_group.* = null;
                std.debug.print("Created simple task with command: '{s}'\n", .{value});
                return start_index - 1;
            }

            // Complex task
            var i = start_index;
            const task_base_indent = base_indent + 4;

            while (i < lines.len) : (i += 1) {
                const task_line = lines[i];
                const task_trimmed = std.mem.trim(u8, task_line, " \t\r");
                if (task_trimmed.len == 0) continue;

                const task_indent = countLeadingSpaces(task_line);
                std.debug.print("Processing task line {d}: '{s}' (indent: {d}, base: {d})\n", .{ i, task_trimmed, task_indent, task_base_indent });

                // 들여쓰기 레벨이 현재 태스크를 벗어나면 종료
                if (task_indent < task_base_indent - 4) break;

                // 새로운 태스크 그룹 시작
                if (task_indent == task_base_indent and std.mem.startsWith(u8, task_trimmed, "- task:")) {
                    std.debug.print("Found new task group\n", .{});
                    const group = try task.addGroup();
                    current_group.* = group;
                    continue;
                }

                // 현재 그룹에 명령어 추가
                if (current_group.* != null and task_indent > task_base_indent and std.mem.startsWith(u8, task_trimmed, "- ")) {
                    const cmd = std.mem.trim(u8, task_trimmed[2..], " ");
                    try current_group.*.?.addCommand(cmd);
                    std.debug.print("Added command to group: '{s}'\n", .{cmd});
                }
            }

            if (task.groups.items.len > 0) {
                current_task.* = task;
                current_group.* = null;
                std.debug.print("Completed complex task '{s}' with {d} groups\n", .{ task.name, task.groups.items.len });
                return i - 1;
            } else {
                std.debug.print("Discarding empty task '{s}'\n", .{task.name});
                task.deinit();
                return start_index - 1;
            }
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

    pub fn printRepositories(self: *const Config) void {
        std.debug.print("Repositories:\n", .{});
        for (self.repos.items) |repo| {
            std.debug.print("  {s}      {s}\n", .{ repo.name, repo.path });
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

pub fn printConfig(config: *const Config) void {
    std.debug.print("\nCurrent config contents:\n", .{});
    for (config.repos.items) |repo| {
        std.debug.print("Repository: {s} ({s})\n", .{ repo.name, repo.path });
        std.debug.print("Tasks:\n", .{});
        for (repo.tasks.items) |task| {
            if (task.groups.items.len == 1 and task.groups.items[0].commands.items.len == 1) {
                std.debug.print("  {s}: {s}\n", .{
                    task.name,
                    task.groups.items[0].commands.items[0].command,
                });
            } else {
                std.debug.print("  {s}:\n", .{task.name});
                for (task.groups.items, 0..) |group, group_idx| {
                    std.debug.print("    Group {d}:\n", .{group_idx + 1});
                    for (group.commands.items) |cmd| {
                        std.debug.print("      - {s}\n", .{cmd.command});
                    }
                }
            }
        }
    }
}

test "Config parser - complex tasks" {
    const test_config =
        \\# zr configuration file
        \\repositories:
        \\  - name: pnpm-default
        \\    path: ./repositories/pnpm-default
        \\    tasks:
        \\      - dev: pnpm run dev
        \\      - manual-task:
        \\          - task:
        \\            - pnpm run dev
        \\            - pnpm run dev
        \\          - task:
        \\            - pnpm run dev
        \\            - pnpm run dev
        \\            - pnpm run dev
        \\          - task:
        \\            - pnpm run dev
    ;

    const allocator = testing.allocator;

    // Config 파일 생성
    const test_file = try std.fs.cwd().createFile(".zr.config.yaml", .{});
    defer test_file.close();
    try test_file.writeAll(test_config);
    defer std.fs.cwd().deleteFile(".zr.config.yaml") catch {};

    // Config 로드 및 파싱
    var config = try Config.load(allocator);
    defer config.deinit();

    // Repository 검증
    try testing.expectEqual(@as(usize, 1), config.repos.items.len);
    const repo = config.repos.items[0];
    try testing.expectEqualStrings("pnpm-default", repo.name);
    try testing.expectEqualStrings("./repositories/pnpm-default", repo.path);

    // Tasks 검증
    try testing.expectEqual(@as(usize, 2), repo.tasks.items.len);

    // dev task 검증
    const dev_task = repo.findTask("dev").?;
    try testing.expectEqual(@as(usize, 1), dev_task.groups.items.len);
    try testing.expectEqual(@as(usize, 1), dev_task.groups.items[0].commands.items.len);
    try testing.expectEqualStrings("pnpm run dev", dev_task.groups.items[0].commands.items[0].command);

    // manual-task 검증
    const manual_task = repo.findTask("manual-task").?;
    try testing.expectEqual(@as(usize, 3), manual_task.groups.items.len);

    // 첫 번째 그룹 검증 (2개 명령어)
    try testing.expectEqual(@as(usize, 2), manual_task.groups.items[0].commands.items.len);
    try testing.expectEqualStrings("pnpm run dev", manual_task.groups.items[0].commands.items[0].command);
    try testing.expectEqualStrings("pnpm run dev", manual_task.groups.items[0].commands.items[1].command);

    // 두 번째 그룹 검증 (3개 명령어)
    try testing.expectEqual(@as(usize, 3), manual_task.groups.items[1].commands.items.len);
    try testing.expectEqualStrings("pnpm run dev", manual_task.groups.items[1].commands.items[0].command);
    try testing.expectEqualStrings("pnpm run dev", manual_task.groups.items[1].commands.items[1].command);
    try testing.expectEqualStrings("pnpm run dev", manual_task.groups.items[1].commands.items[2].command);

    // 세 번째 그룹 검증 (1개 명령어)
    try testing.expectEqual(@as(usize, 1), manual_task.groups.items[2].commands.items.len);
    try testing.expectEqualStrings("pnpm run dev", manual_task.groups.items[2].commands.items[0].command);
}
