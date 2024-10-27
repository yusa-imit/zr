const std = @import("std");
const Command = @import("command.zig").Command;
const Config = @import("config.zig").Config;
const runner = @import("cli/runner.zig");
const Arguments = @import("cli/args.zig").Arguments;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try Arguments.init(allocator);
    defer args.deinit();

    try args.parseCommand();

    const cmd_str = args.command.?;
    if (Command.parse(cmd_str)) |cmd| {
        // Commands that don't need config
        switch (cmd) {
            .init => {
                try args.parseRemaining();
                var iter = try args.iterator();
                defer iter.deinit();
                try runner.executeCommand(.init, null, iter, allocator);
                return;
            },
            .help, .version => {
                try runner.executeCommand(cmd, null, undefined, allocator);
                return;
            },
            else => {},
        }

        // Load config for commands that need it
        var config = Config.load(allocator) catch |err| {
            if (err == error.ConfigNotInitialized) {
                std.debug.print("Config file not found. Run 'zr init' first.\n", .{});
                return;
            }
            return err;
        };
        defer config.deinit();

        try args.parseRemaining();
        var iter = try args.iterator();
        defer iter.deinit();
        try runner.executeCommand(cmd, &config, iter, allocator);

        // Save config if needed
        if (cmd == .add or cmd == .remove) {
            try config.save();
        }
    } else {
        // If not a command, treat as repository task
        var config = Config.load(allocator) catch |err| {
            if (err == error.ConfigNotInitialized) {
                std.debug.print("Config file not found. Run 'zr init' first.\n", .{});
                return;
            }
            return err;
        };
        defer config.deinit();

        const repo_name = cmd_str; // first arg is repo name
        const task_name = args.next() orelse {
            std.debug.print("Error: Task name required\n", .{});
            std.debug.print("Usage: zr <repository> <task>\n", .{});
            return;
        };

        try runner.executeTask(&config, repo_name, task_name, &args, allocator);
    }
}
