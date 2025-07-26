const std = @import("std");
const fs = std.fs;
const CONFIG_FILENAME = @import("../../config.zig").CONFIG_FILENAME;

pub fn execute() !void {
    const default_config =
        \\# zr configuration file
        \\repositories:
        \\  # Add your repositories here:
        \\  # - name: frontend
        \\  #   path: ./packages/frontend
        \\  # - name: backend
        \\  #   path: ./packages/backend
        \\
    ;

    if (fs.cwd().access(CONFIG_FILENAME, .{})) |_| {
        std.debug.print("Config file already exists at ./{s}\n", .{CONFIG_FILENAME});
        return;
    } else |_| {
        const file = try fs.cwd().createFile(CONFIG_FILENAME, .{});
        defer file.close();
        try file.writeAll(default_config);
        std.debug.print("Created config file at ./{s}\n", .{CONFIG_FILENAME});
    }
}

test "init creates config file" {
    const testing = std.testing;

    // Clean up any existing config
    fs.cwd().deleteFile(CONFIG_FILENAME) catch {};

    // Create new config
    try execute();
    defer fs.cwd().deleteFile(CONFIG_FILENAME) catch {};

    // Verify file exists and contains expected content
    const file = try fs.cwd().openFile(CONFIG_FILENAME, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const content = buffer[0..bytes_read];

    try testing.expect(std.mem.indexOf(u8, content, "# zr configuration file") != null);
    try testing.expect(std.mem.indexOf(u8, content, "repositories:") != null);
}
