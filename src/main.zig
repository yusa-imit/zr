const std = @import("std");
const Command = @import("command.zig").Command;
const Config = @import("config.zig").Config;
const runner = @import("cli/runner.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip executable name
    _ = args.skip();

    const cmd_str = args.next() orelse {
        try runner.executeCommand(.help, null, undefined, allocator);
        return;
    };

    const cmd = Command.parse(cmd_str) orelse {
        std.debug.print("Unknown command: {s}\n", .{cmd_str});
        try runner.executeCommand(.help, null, undefined, allocator);
        return;
    };

    // Commands that don't need config
    switch (cmd) {
        .init => {
            try runner.executeCommand(.init, null, &args, allocator);
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

    try runner.executeCommand(cmd, &config, &args, allocator);

    // Save config if needed
    if (cmd == .add or cmd == .remove) {
        try config.save();
    }
}
