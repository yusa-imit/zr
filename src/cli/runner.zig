const std = @import("std");
const Command = @import("../command.zig").Command;
const Config = @import("../config.zig").Config;
const Repository = @import("../repository.zig").Repository;
const Task = @import("../repository.zig").Task;
const Arguments = @import("args.zig").Arguments;
const run_command = @import("commands/run.zig");
const add_command = @import("commands/add.zig");
const remove_command = @import("commands/remove.zig");
const list_command = @import("commands/list.zig");
const init_command = @import("commands/init.zig");
const help_command = @import("commands/help.zig");
const Allocator = std.mem.Allocator;

const VERSION = "v0.0.2";

pub fn executeCommand(cmd: Command, config: ?*Config, args: *Arguments, allocator: Allocator) !void {
    switch (cmd) {
        .run => try run_command.execute(config.?, args, allocator),
        .list => try list_command.execute(config.?),
        .add => try add_command.execute(config.?, args, allocator),
        .remove => try remove_command.execute(config.?, args),
        .init => try init_command.execute(),
        .help => try help_command.execute(),
        .version => showVersion(),
    }
}

pub fn executeTask(config: *Config, repo_name: []const u8, task_name: []const u8, args: *Arguments, allocator: Allocator) !void {
    _ = args; // autofix
    const repo = config.findRepository(repo_name) orelse {
        std.debug.print("Error: Repository not found: {s}\n", .{repo_name});
        return;
    };

    // task_name이 "tasks"인 경우 task 목록을 출력
    if (std.mem.eql(u8, task_name, "tasks")) {
        repo.printTasks();
        return;
    }

    const task = repo.findTask(task_name) orelse {
        std.debug.print("Error: Task '{s}' not found in repository '{s}'\n", .{ task_name, repo_name });
        repo.printTasks();
        return;
    };

    // task를 직접 실행
    try run_command.executeTask(task, repo, allocator, .{});
}

fn printTask(task: Task) void {
    std.debug.print("  {s}:", .{task.name});

    // 단순 task인 경우 (하나의 명령어만 있는 경우)
    if (task.groups.items.len == 1 and task.groups.items[0].commands.items.len == 1) {
        std.debug.print(" {s}\n", .{task.groups.items[0].commands.items[0].command});
        return;
    }

    // 복잡한 task인 경우
    std.debug.print("\n", .{});
    for (task.groups.items, 0..) |group, group_idx| {
        std.debug.print("    task group {d}:\n", .{group_idx + 1});
        for (group.commands.items) |cmd| {
            std.debug.print("      - {s}\n", .{cmd.command});
        }
    }
}

fn showVersion() void {
    if (std.mem.eql(u8, VERSION, "unknown")) {
        std.debug.print("zr version unknown (build.zig.zon not found or version not specified)\n", .{});
    } else {
        std.debug.print("zr version {s}\n", .{VERSION});
    }
}
