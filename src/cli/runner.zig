const std = @import("std");
const Command = @import("../command.zig").Command;
const Config = @import("../config.zig").Config;
const run_command = @import("commands/run.zig");
const add_command = @import("commands/add.zig");
const remove_command = @import("commands/remove.zig");
const list_command = @import("commands/list.zig");
const init_command = @import("commands/init.zig");
const help_command = @import("commands/help.zig");

const VERSION = "v0.0.2";

pub fn executeCommand(cmd: Command, config: ?*Config, args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
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

fn showVersion() void {
    if (std.mem.eql(u8, VERSION, "unknown")) {
        std.debug.print("zr version unknown (build.zig.zon not found or version not specified)\n", .{});
    } else {
        std.debug.print("zr version {s}\n", .{VERSION});
    }
}

test "executeCommand dispatches commands correctly" {
    // Add tests for command dispatching
}
