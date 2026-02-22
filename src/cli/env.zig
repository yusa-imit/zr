const std = @import("std");
const color = @import("../output/color.zig");
const platform = @import("../util/platform.zig");

/// Display environment variables from the system
pub fn cmdEnv(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    _: []const u8, // config_path - not used in this simple version
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    // Parse arguments
    var resolve_var: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--resolve")) {
            if (i + 1 < args.len) {
                resolve_var = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "env: --resolve requires a variable name\n\n  Hint: zr env --resolve VAR_NAME\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "env: unknown argument '{s}'\n\n  Hint: zr env --help\n", .{arg});
            return 1;
        }
    }

    // Get system environment
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // Handle --resolve flag (show single variable)
    if (resolve_var) |var_name| {
        if (env_map.get(var_name)) |value| {
            try color.printBold(w, use_color, "{s}", .{var_name});
            try w.writeAll("=");
            try color.printSuccess(w, use_color, "{s}\n", .{value});
        } else {
            try color.printError(ew, use_color, "Variable '{s}' not found in environment\n", .{var_name});
            return 1;
        }
        return 0;
    }

    // Display all environment variables
    try displayEnv(allocator, &env_map, w, use_color);
    return 0;
}

fn displayEnv(
    allocator: std.mem.Allocator,
    env_map: *std.process.EnvMap,
    w: anytype,
    use_color: bool,
) !void {
    try color.printBold(w, use_color, "Environment:\n\n", .{});

    // Collect and sort keys
    var keys = std.ArrayList([]const u8){};
    defer keys.deinit(allocator);

    var it = env_map.iterator();
    while (it.next()) |entry| {
        try keys.append(allocator, entry.key_ptr.*);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Print variables
    for (keys.items) |key| {
        const value = env_map.get(key).?;
        try color.printSuccess(w, use_color, "  {s}", .{key});
        try w.writeAll("=");
        try color.printDim(w, use_color, "{s}\n", .{value});
    }
}

fn printHelp(w: anytype, use_color: bool) !void {
    try color.printBold(w, use_color, "zr env - Display environment variables\n\n", .{});
    try w.writeAll(
        \\Usage:
        \\  zr env [options]
        \\
        \\Options:
        \\  --resolve <VAR>    Show value of a specific variable
        \\  --help, -h         Show this help message
        \\
        \\Description:
        \\  Shows all environment variables currently available in the shell.
        \\
        \\Examples:
        \\  zr env                # Show all environment variables
        \\  zr env --resolve PATH # Show value of PATH variable
        \\
    );
}

test "env command help" {
    const testing = std.testing;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var w = stdout.writer(&out_buf);

    try printHelp(&w.interface, false);

    try testing.expect(true); // Just ensure it compiles
}
