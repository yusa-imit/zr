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
    const repo = config.findRepository(repo_name) orelse {
        std.debug.print("Error: Repository not found: {s}\n", .{repo_name});
        return;
    };

    const task = (try repo.findTask(task_name)) orelse {
        std.debug.print("Error: Task '{s}' not found in repository '{s}'\n", .{ task_name, repo_name });
        if (repo.tasks.items.len > 0) {
            std.debug.print("\nAvailable tasks:\n", .{});
            for (repo.tasks.items) |t| {
                std.debug.print("  {s}: {s}\n", .{ t.name, t.command });
            }
        }
        return;
    };
    defer task.deinit(allocator);

    // task 실행을 위한 새로운 Arguments 생성
    var task_args = try args.taskIterator(repo_name, task.command);
    defer task_args.deinit();

    try run_command.execute(config, task_args, allocator);
}

fn showVersion() void {
    if (std.mem.eql(u8, VERSION, "unknown")) {
        std.debug.print("zr version unknown (build.zig.zon not found or version not specified)\n", .{});
    } else {
        std.debug.print("zr version {s}\n", .{VERSION});
    }
}
