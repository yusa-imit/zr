const std = @import("std");
const color = @import("../output/color.zig");
const config_loader = @import("../config/loader.zig");
const codeowners_generator = @import("../codeowners/generator.zig");
const codeowners_types = @import("../codeowners/types.zig");
const common = @import("common.zig");

pub fn cmdCodeowners(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (args.len == 0) {
        try printHelp(w, use_color);
        return 1;
    }

    const subcommand = args[0];
    if (std.mem.eql(u8, subcommand, "generate")) {
        return try cmdCodeownersGenerate(allocator, args[1..], w, ew, use_color);
    } else if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printHelp(w, use_color);
        return 0;
    } else {
        try color.printError(ew, use_color, "Unknown subcommand: {s}\n", .{subcommand});
        try printHelp(w, use_color);
        return 1;
    }
}

fn cmdCodeownersGenerate(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config_path: []const u8 = "zr.toml";
    var output_path: ?[]const u8 = null;
    var dry_run = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--config")) {
            if (i + 1 >= args.len) {
                try color.printError(ew, use_color, "--config requires a value\n", .{});
                return 1;
            }
            i += 1;
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            if (i + 1 >= args.len) {
                try color.printError(ew, use_color, "--output requires a value\n", .{});
                return 1;
            }
            i += 1;
            output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printGenerateHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "Unknown option: {s}\n", .{arg});
            return 1;
        }
    }

    // Load config
    var config = config_loader.loadFromFile(allocator, config_path) catch |err| {
        try color.printError(ew, use_color, "Failed to load config: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer config.deinit();

    // Get workspace members
    var member_paths = std.ArrayList([]const u8){};
    defer {
        for (member_paths.items) |path| allocator.free(path);
        member_paths.deinit(allocator);
    }

    if (config.workspace) |ws| {
        // Discover workspace members for all patterns
        for (ws.members) |pattern| {
            const members = config_loader.discoverWorkspaceMembers(allocator, pattern) catch |err| {
                try color.printError(ew, use_color, "Failed to discover workspace members for pattern '{s}': {s}\n", .{ pattern, @errorName(err) });
                return 1;
            };
            defer {
                for (members) |m| allocator.free(m);
                allocator.free(members);
            }

            for (members) |member| {
                try member_paths.append(allocator, try allocator.dupe(u8, member));
            }
        }
    }

    // Create CODEOWNERS config (for now, use defaults since we haven't added [codeowners] section to config yet)
    var codeowners_config = codeowners_types.CodeownersConfig.init(allocator);
    defer codeowners_config.deinit(allocator);

    // Initialize generator
    var gen = codeowners_generator.Generator.init(allocator, &codeowners_config);
    defer gen.deinit();

    // Auto-detect from workspace
    if (member_paths.items.len > 0) {
        try gen.detectFromWorkspace(member_paths.items);
    }

    // Generate content
    const content = try gen.generate();
    defer allocator.free(content);

    const final_output_path = output_path orelse "CODEOWNERS";

    if (dry_run) {
        try color.printBold(w, use_color, "Output: ", .{});
        try w.print("{s}\n\n", .{final_output_path});
        try w.print("{s}", .{content});
        return 0;
    }

    // Write to file
    const file = std.fs.cwd().createFile(final_output_path, .{}) catch |err| {
        try color.printError(ew, use_color, "Failed to create {s}: {s}\n", .{ final_output_path, @errorName(err) });
        return 1;
    };
    defer file.close();

    file.writeAll(content) catch |err| {
        try color.printError(ew, use_color, "Failed to write {s}: {s}\n", .{ final_output_path, @errorName(err) });
        return 1;
    };

    try color.printSuccess(w, use_color, "✓ Generated {s}\n", .{final_output_path});

    return 0;
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "Usage: ", .{});
    try w.print("zr codeowners <subcommand> [options]\n\n", .{});
    try color.printBold(w, use_color, "Subcommands:\n", .{});
    try w.print("  generate    Generate CODEOWNERS file from workspace configuration\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  -h, --help  Show this help message\n\n", .{});
    try w.print("Run 'zr codeowners <subcommand> --help' for more information on a subcommand.\n", .{});
}

fn printGenerateHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "Usage: ", .{});
    try w.print("zr codeowners generate [options]\n\n", .{});
    try w.print("Generate CODEOWNERS file from workspace configuration.\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --config <path>       Path to zr.toml (default: zr.toml)\n", .{});
    try w.print("  -o, --output <path>   Output path (default: CODEOWNERS)\n", .{});
    try w.print("  -n, --dry-run         Print output without writing file\n", .{});
    try w.print("  -h, --help            Show this help message\n\n", .{});
    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.print("  zr codeowners generate\n", .{});
    try w.print("  zr codeowners generate --output .github/CODEOWNERS\n", .{});
    try w.print("  zr codeowners generate --dry-run\n", .{});
}

test "codeowners help" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var out_file = std.fs.File.stdout();
    var out_writer = out_file.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_file = std.fs.File.stderr();
    var err_writer = err_file.writer(&err_buf);

    const args = [_][]const u8{"--help"};
    const exit_code = try cmdCodeowners(allocator, &args, &out_writer.interface, &err_writer.interface, false);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
