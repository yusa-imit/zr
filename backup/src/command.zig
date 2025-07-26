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
        inline for (@typeInfo(Command).@"enum".fields) |field| {
            if (std.mem.eql(u8, cmd, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

test "Command.parse - valid commands" {
    const testing = @import("std").testing;
    
    try testing.expect(Command.parse("run") == .run);
    try testing.expect(Command.parse("list") == .list);
    try testing.expect(Command.parse("add") == .add);
    try testing.expect(Command.parse("remove") == .remove);
    try testing.expect(Command.parse("init") == .init);
    try testing.expect(Command.parse("help") == .help);
    try testing.expect(Command.parse("version") == .version);
}

test "Command.parse - invalid commands" {
    const testing = @import("std").testing;
    
    try testing.expect(Command.parse("invalid") == null);
    try testing.expect(Command.parse("") == null);
    try testing.expect(Command.parse("RUN") == null);
    try testing.expect(Command.parse("runs") == null);
}
