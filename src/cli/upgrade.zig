const std = @import("std");
const output = @import("../output/color.zig");
const checker = @import("../upgrade/checker.zig");
const installer = @import("../upgrade/installer.zig");
const types = @import("../upgrade/types.zig");

pub fn cmdUpgrade(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var options = types.UpgradeOptions{};

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return 0;
        } else if (std.mem.eql(u8, arg, "--check")) {
            options.check_only = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --version requires a value\n", .{});
                return 1;
            }
            i += 1;
            options.version = args[i];
        } else if (std.mem.eql(u8, arg, "--prerelease")) {
            options.include_prerelease = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else {
            std.debug.print("Unknown option: {s}\n", .{arg});
            std.debug.print("Use --help for usage information\n", .{});
            return 1;
        }
    }

    return try runUpgrade(allocator, options);
}

fn runUpgrade(allocator: std.mem.Allocator, options: types.UpgradeOptions) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    const stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&stdout_buf);
    defer stdout_writer.interface.flush() catch {};

    // Check for updates
    try stdout_writer.interface.print("Checking for updates...\n", .{});

    const maybe_release = try checker.checkForUpdate(
        allocator,
        options.include_prerelease,
    );

    if (maybe_release) |release| {
        defer {
            var mutable_release = release;
            mutable_release.deinit();
        }

        const green = output.Code.green;
        const bold = output.Code.bold;
        const reset = output.Code.reset;

        try stdout_writer.interface.print("{s}{s}Update available:{s}\n", .{ green, bold, reset });
        try stdout_writer.interface.print("  Current: {s}\n", .{checker.CURRENT_VERSION});
        try stdout_writer.interface.print("  Latest:  {s}\n", .{release.version});
        try stdout_writer.interface.print("  Released: {s}\n\n", .{release.created_at});

        if (options.check_only) {
            try stdout_writer.interface.print("Run 'zr upgrade' to install the update.\n", .{});
            return 0;
        }

        // Confirm before installing
        try stdout_writer.interface.print("Do you want to upgrade? [y/N]: ", .{});
        stdout_writer.interface.flush() catch {};

        const stdin_file = std.fs.File.stdin();
        var buf: [256]u8 = undefined;
        const bytes_read = try stdin_file.read(&buf);
        const input = std.mem.trim(u8, buf[0..bytes_read], " \t\r\n");

        if (!std.mem.eql(u8, input, "y") and !std.mem.eql(u8, input, "Y")) {
            try stdout_writer.interface.print("Upgrade cancelled.\n", .{});
            return 0;
        }

        // Install the update
        try installer.installRelease(allocator, release, options.verbose);

        try stdout_writer.interface.print("\n{s}{s}✓ Upgrade complete!{s}\n", .{ green, bold, reset });
        try stdout_writer.interface.print("Run 'zr --version' to verify.\n", .{});

        return 0;
    } else {
        const green = output.Code.green;
        const bold = output.Code.bold;
        const reset = output.Code.reset;

        try stdout_writer.interface.print("{s}{s}✓ You are already on the latest version ({s}){s}\n", .{
            green,
            bold,
            checker.CURRENT_VERSION,
            reset,
        });
        return 0;
    }
}

fn printHelp() void {
    std.debug.print(
        \\Usage: zr upgrade [OPTIONS]
        \\
        \\Upgrade zr to the latest version.
        \\
        \\Options:
        \\  --help, -h         Show this help message
        \\  --check            Check for updates without installing
        \\  --version <ver>    Upgrade to specific version (e.g., 0.0.5)
        \\  --prerelease       Include prerelease versions
        \\  --verbose, -v      Show detailed progress
        \\
        \\Examples:
        \\  zr upgrade                    # Upgrade to latest stable version
        \\  zr upgrade --check            # Check for updates only
        \\  zr upgrade --version 0.0.5    # Upgrade to specific version
        \\  zr upgrade --prerelease       # Include beta/rc versions
        \\
    , .{});
}

test "cmdUpgrade help" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"--help"};
    const exit_code = try cmdUpgrade(allocator, &args);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "UpgradeOptions defaults" {
    const options = types.UpgradeOptions{};
    try std.testing.expect(!options.check_only);
    try std.testing.expect(!options.include_prerelease);
    try std.testing.expect(!options.verbose);
    try std.testing.expect(options.version == null);
}
