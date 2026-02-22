const std = @import("std");
const types = @import("../config/types.zig");
const versioning_types = @import("../versioning/types.zig");
const bump = @import("../versioning/bump.zig");
const config_loader = @import("../config/loader.zig");

pub fn cmdVersion(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var out_buf: [4096]u8 = undefined;
    const stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&out_buf);
    defer stdout_writer.interface.flush() catch {};

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var stderr_writer = stderr_file.writer(&err_buf);
    defer stderr_writer.interface.flush() catch {};

    // Parse command-line arguments
    var bump_type: ?versioning_types.BumpType = null;
    var package_path: ?[]const u8 = null;
    var config_path: []const u8 = "zr.toml";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--bump") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                try stderr_writer.interface.print("Error: --bump requires a value (major|minor|patch)\n", .{});
                std.process.exit(1);
            }
            i += 1;
            bump_type = versioning_types.BumpType.fromString(args[i]);
            if (bump_type == null) {
                try stderr_writer.interface.print("Error: invalid bump type '{s}' (must be major|minor|patch)\n", .{args[i]});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--package") or std.mem.eql(u8, arg, "-p")) {
            if (i + 1 >= args.len) {
                try stderr_writer.interface.print("Error: --package requires a path\n", .{});
                std.process.exit(1);
            }
            i += 1;
            package_path = args[i];
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 >= args.len) {
                try stderr_writer.interface.print("Error: --config requires a path\n", .{});
                std.process.exit(1);
            }
            i += 1;
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(&stdout_writer.interface);
            return;
        } else {
            try stderr_writer.interface.print("Error: unknown argument '{s}'\n", .{arg});
            try printHelp(&stderr_writer.interface);
            std.process.exit(1);
        }
    }

    // Load config
    var config = config_loader.loadFromFile(allocator, config_path) catch |err| {
        try stderr_writer.interface.print("Error loading config: {}\n", .{err});
        std.process.exit(1);
    };
    defer config.deinit();

    // Check if versioning is configured
    if (config.versioning == null) {
        try stderr_writer.interface.print("Error: [versioning] section not found in zr.toml\n", .{});
        try stderr_writer.interface.print("Add the following to your zr.toml:\n\n", .{});
        try stderr_writer.interface.print("[versioning]\n", .{});
        try stderr_writer.interface.print("mode = \"independent\"  # or \"fixed\"\n", .{});
        try stderr_writer.interface.print("convention = \"conventional\"  # or \"manual\"\n", .{});
        std.process.exit(1);
    }

    const versioning = config.versioning.?;

    // For now, implement simple package.json version bumping
    // In the future, this will handle workspace packages based on mode
    const pkg_path = package_path orelse "package.json";

    // Check if package.json exists
    const pkg_file = std.fs.cwd().openFile(pkg_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try stderr_writer.interface.print("Error: {s} not found\n", .{pkg_path});
            try stderr_writer.interface.print("Hint: Use --package to specify a different file\n", .{});
            std.process.exit(1);
        }
        return err;
    };
    pkg_file.close();

    // Read current version
    const current_version = try bump.readPackageJsonVersion(allocator, pkg_path);
    defer allocator.free(current_version);

    if (bump_type == null) {
        // Just display current version and mode
        try stdout_writer.interface.print("Current version: {s}\n", .{current_version});
        try stdout_writer.interface.print("Versioning mode: {s}\n", .{@tagName(versioning.mode)});
        try stdout_writer.interface.print("Convention: {s}\n", .{@tagName(versioning.convention)});
        try stdout_writer.interface.print("\nTo bump version, use:\n", .{});
        try stdout_writer.interface.print("  zr version --bump=patch   # {s} → ", .{current_version});
        const example_patch = try bump.bumpVersion(allocator, current_version, .patch);
        defer allocator.free(example_patch);
        try stdout_writer.interface.print("{s}\n", .{example_patch});
        try stdout_writer.interface.print("  zr version --bump=minor   # {s} → ", .{current_version});
        const example_minor = try bump.bumpVersion(allocator, current_version, .minor);
        defer allocator.free(example_minor);
        try stdout_writer.interface.print("{s}\n", .{example_minor});
        try stdout_writer.interface.print("  zr version --bump=major   # {s} → ", .{current_version});
        const example_major = try bump.bumpVersion(allocator, current_version, .major);
        defer allocator.free(example_major);
        try stdout_writer.interface.print("{s}\n", .{example_major});
        return;
    }

    // Bump the version
    const new_version = try bump.bumpVersion(allocator, current_version, bump_type.?);
    defer allocator.free(new_version);

    // Write back to package.json
    try bump.writePackageJsonVersion(allocator, pkg_path, new_version);

    try stdout_writer.interface.print("✓ Version bumped: {s} → {s}\n", .{ current_version, new_version });
    try stdout_writer.interface.print("  Updated: {s}\n", .{pkg_path});
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.print(
        \\Usage: zr version [options]
        \\
        \\Manage package versions in a workspace.
        \\
        \\Options:
        \\  --bump, -b <type>       Bump version (major|minor|patch)
        \\  --package, -p <path>    Package file to update (default: package.json)
        \\  --help, -h              Show this help message
        \\
        \\Examples:
        \\  zr version                    # Show current version
        \\  zr version --bump=patch       # Bump patch version (1.2.3 → 1.2.4)
        \\  zr version --bump=minor       # Bump minor version (1.2.3 → 1.3.0)
        \\  zr version --bump=major       # Bump major version (1.2.3 → 2.0.0)
        \\  zr version -p pkg/package.json -b patch  # Bump specific package
        \\
    ,
        .{},
    );
}

test "cmdVersion help" {
    const allocator = std.testing.allocator;

    const args = [_][]const u8{"--help"};
    // This should print help and exit normally - we just check it doesn't crash
    try cmdVersion(allocator, &args);
}
