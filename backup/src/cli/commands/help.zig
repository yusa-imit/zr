const std = @import("std");
const CONFIG_FILENAME = @import("../../config.zig").CONFIG_FILENAME;

pub fn execute() !void {
    std.debug.print(
        \\zr - Zig-based Repository Runner
        \\
        \\Usage:
        \\  zr <command> [arguments]
        \\
        \\Commands:
        \\  init                  Create initial config file
        \\  run <repo> <command>  Run command in specified repository
        \\  list                  List all repositories
        \\  add <name> <path>     Add a new repository
        \\  remove <name>         Remove a repository
        \\  help                  Show this help message
        \\
        \\Config:
        \\  Repositories can be managed through ./{s}
        \\
        \\Examples:
        \\  zr init
        \\  zr add frontend ./packages/frontend
        \\  zr run frontend npm start
        \\
    , .{CONFIG_FILENAME});
}

test "help shows usage information" {
    try execute();
}
