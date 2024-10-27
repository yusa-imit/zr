const std = @import("std");
const Command = @import("command.zig").Command;
const Config = @import("config.zig").Config;
const runner = @import("cli/runner.zig");
const Arguments = @import("cli/args.zig").Arguments;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak detected");
    }

    var args = try Arguments.init(allocator);
    defer args.deinit();

    try args.parseCommand();

    const cmd_str = args.command orelse {
        std.debug.print("Error: Command required\n", .{});
        std.debug.print("Usage: zr <command> [arguments]\n", .{});
        return;
    };

    // First try to parse as a built-in command
    if (Command.parse(cmd_str)) |cmd| {
        // Commands that don't need config
        switch (cmd) {
            .init => {
                try args.parseRemaining();
                const iter = try args.iterator();
                defer allocator.destroy(iter);
                try runner.executeCommand(.init, null, iter, allocator);
                return;
            },
            .help, .version => {
                try runner.executeCommand(cmd, null, undefined, allocator);
                return;
            },
            else => {
                var config = try Config.load(allocator);
                defer config.deinit();

                try args.parseRemaining();
                const iter = try args.iterator();
                defer allocator.destroy(iter);
                try runner.executeCommand(cmd, config, iter, allocator);

                // Save config if needed
                if (cmd == .add or cmd == .remove) {
                    try config.save();
                }
            },
        }
    } else {
        const repo_name = cmd_str;

        const task_name = args.next() orelse {
            std.debug.print("Error: Task name required\n", .{});
            std.debug.print("Usage: zr <repository> <task>\n", .{});
            std.debug.print("\nAvailable commands:\n", .{});
            inline for (@typeInfo(Command).Enum.fields) |field| {
                std.debug.print("  {s}\n", .{field.name});
            }
            return;
        };

        var config = try Config.load(allocator);

        defer config.deinit();

        // Parse remaining arguments
        try args.parseRemaining();

        runner.executeTask(config, repo_name, task_name, &args, allocator) catch |err| {
            switch (err) {
                error.ProcessTerminated => {
                    // Process terminated abnormally
                    std.debug.print("Task execution failed\n", .{});
                    return err;
                },
                error.TaskNotFound => {
                    // Task not found error message is already printed
                    return;
                },
                else => return err,
            }
        };
    }
}
