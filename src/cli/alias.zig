const std = @import("std");
const Allocator = std.mem.Allocator;
const AliasConfig = @import("../config/aliases.zig").AliasConfig;
const color = @import("../output/color.zig");

pub fn cmdAlias(
    allocator: Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (args.len == 0) {
        try printHelp(w, use_color);
        return 0;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        return try cmdAliasList(allocator, w, ew, use_color);
    } else if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "set")) {
        if (args.len < 3) {
            try color.printError(ew, use_color, "Usage: zr alias add <name> <command>\n", .{});
            return 1;
        }
        return try cmdAliasAdd(allocator, args[1], args[2], w, ew, use_color);
    } else if (std.mem.eql(u8, subcmd, "remove") or std.mem.eql(u8, subcmd, "rm") or std.mem.eql(u8, subcmd, "delete")) {
        if (args.len < 2) {
            try color.printError(ew, use_color, "Usage: zr alias remove <name>\n", .{});
            return 1;
        }
        return try cmdAliasRemove(allocator, args[1], w, ew, use_color);
    } else if (std.mem.eql(u8, subcmd, "show") or std.mem.eql(u8, subcmd, "get")) {
        if (args.len < 2) {
            try color.printError(ew, use_color, "Usage: zr alias show <name>\n", .{});
            return 1;
        }
        return try cmdAliasShow(allocator, args[1], w, ew, use_color);
    } else if (std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "-h")) {
        try printHelp(w, use_color);
        return 0;
    } else {
        try color.printError(ew, use_color, "Unknown subcommand. Use 'zr alias --help' for usage.\n", .{});
        return 1;
    }
}

fn cmdAliasList(allocator: Allocator, w: *std.Io.Writer, ew: *std.Io.Writer, use_color: bool) !u8 {
    _ = ew;
    var config = try AliasConfig.load(allocator);
    defer config.deinit();

    if (config.aliases.count() == 0) {
        try color.printWarning(w, use_color, "No aliases defined. Use 'zr alias add <name> <command>' to create one.\n", .{});
        return 0;
    }

    try color.printSuccess(w, use_color, "Defined aliases:\n", .{});

    // Sort aliases by name for consistent output
    var names = std.ArrayList([]const u8){};
    defer names.deinit(allocator);
    var it = config.aliases.keyIterator();
    while (it.next()) |name| {
        try names.append(allocator, name.*);
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (names.items) |name| {
        const cmd = config.aliases.get(name).?;
        if (use_color) {
            try w.print("  \x1b[36m{s}\x1b[0m -> {s}\n", .{ name, cmd });
        } else {
            try w.print("  {s} -> {s}\n", .{ name, cmd });
        }
    }

    return 0;
}

fn cmdAliasAdd(allocator: Allocator, name: []const u8, command: []const u8, w: *std.Io.Writer, ew: *std.Io.Writer, use_color: bool) !u8 {
    // Validate name (no spaces, special chars)
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') {
            try color.printError(ew, use_color, "Alias name must contain only alphanumeric characters, hyphens, and underscores\n", .{});
            return 1;
        }
    }

    var config = try AliasConfig.load(allocator);
    defer config.deinit();

    const existed = config.get(name) != null;
    try config.set(name, command);
    try config.save();

    if (existed) {
        try color.printSuccess(w, use_color, "Updated alias '{s}' -> '{s}'\n", .{ name, command });
    } else {
        try color.printSuccess(w, use_color, "Created alias '{s}' -> '{s}'\n", .{ name, command });
    }

    return 0;
}

fn cmdAliasRemove(allocator: Allocator, name: []const u8, w: *std.Io.Writer, ew: *std.Io.Writer, use_color: bool) !u8 {
    var config = try AliasConfig.load(allocator);
    defer config.deinit();

    if (config.remove(name)) {
        try config.save();
        try color.printSuccess(w, use_color, "Removed alias '{s}'\n", .{name});
        return 0;
    } else {
        try color.printError(ew, use_color, "Alias '{s}' not found\n", .{name});
        return 1;
    }
}

fn cmdAliasShow(allocator: Allocator, name: []const u8, w: *std.Io.Writer, ew: *std.Io.Writer, use_color: bool) !u8 {
    var config = try AliasConfig.load(allocator);
    defer config.deinit();

    if (config.get(name)) |cmd| {
        if (use_color) {
            try w.print("\x1b[36m{s}\x1b[0m -> {s}\n", .{ name, cmd });
        } else {
            try w.print("{s} -> {s}\n", .{ name, cmd });
        }
        return 0;
    } else {
        try color.printError(ew, use_color, "Alias '{s}' not found\n", .{name});
        return 1;
    }
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr alias <subcommand> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Subcommands:\n", .{});
    try w.print("  list, ls                List all defined aliases\n", .{});
    try w.print("  add, set <name> <cmd>   Create or update an alias\n", .{});
    try w.print("  remove, rm <name>       Remove an alias\n", .{});
    try w.print("  show, get <name>        Show a specific alias\n", .{});
    try w.print("  --help, -h              Show this help message\n\n", .{});
    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.print("  zr alias add dev \"run build && run test\"\n", .{});
    try w.print("  zr alias add prod \"run build --profile=production\"\n", .{});
    try w.print("  zr alias list\n", .{});
    try w.print("  zr alias show dev\n", .{});
    try w.print("  zr alias remove dev\n", .{});
}

// Tests
test "cmdAlias help" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{"--help"};
    const exit_code = try cmdAlias(allocator, &args, &out_w.interface, &err_w.interface, false);
    try std.testing.expect(exit_code == 0);
}

test "cmdAlias invalid subcommand" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = [_][]const u8{"invalid"};
    const exit_code = try cmdAlias(allocator, &args, &out_w.interface, &err_w.interface, false);
    try std.testing.expect(exit_code == 1);
}

test "cmdAliasAdd validation" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // Invalid name with spaces
    const args_invalid = [_][]const u8{ "add", "my alias", "run test" };
    const exit_code = try cmdAlias(allocator, &args_invalid, &out_w.interface, &err_w.interface, false);
    try std.testing.expect(exit_code == 1);
}
