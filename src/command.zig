const std = @import("std");

pub const Command = enum {
    run, // Run command in repository: zr run <repo> <command>
    list, // List repositories: zr list
    add, // Add repository: zr add <name> <path>
    remove, // Remove repository: zr remove <name>
    init, // Initialize config file: zr init
    help, // Show help: zr help
    version,

    pub fn parse(cmd: []const u8) ?Command {
        inline for (@typeInfo(Command).Enum.fields) |field| {
            if (std.mem.eql(u8, cmd, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};
