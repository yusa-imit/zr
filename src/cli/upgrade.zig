const std = @import("std");
const output = @import("../output/color.zig");
const checker = @import("../upgrade/checker.zig");
const installer = @import("../upgrade/installer.zig");
const types = @import("../upgrade/types.zig");

pub fn cmdUpgrade(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    var options = types.UpgradeOptions{};

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(ew);
            return 0;
        } else if (std.mem.eql(u8, arg, "--check")) {
            options.check_only = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            if (i + 1 >= args.len) {
                try ew.print("✗ [Upgrade]: --version requires a value\n", .{});
                return 1;
            }
            i += 1;
            options.version = args[i];
        } else if (std.mem.eql(u8, arg, "--prerelease")) {
            options.include_prerelease = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else {
            try ew.print("✗ [Upgrade]: Unknown option '{s}'\n\n  Hint: Run 'zr upgrade --help' to see valid options\n", .{arg});
            return 1;
        }
    }

    return try runUpgrade(allocator, options, w, ew);
}

fn runUpgrade(allocator: std.mem.Allocator, options: types.UpgradeOptions, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    _ = ew; // Not used in runUpgrade
    // Check for updates
    try w.print("Checking for updates...\n", .{});

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

        try w.print("{s}{s}Update available:{s}\n", .{ green, bold, reset });
        try w.print("  Current: {s}\n", .{checker.CURRENT_VERSION});
        try w.print("  Latest:  {s}\n", .{release.version});
        try w.print("  Released: {s}\n\n", .{release.created_at});

        if (options.check_only) {
            try w.print("Run 'zr upgrade' to install the update.\n", .{});
            return 0;
        }

        // Confirm before installing
        try w.print("Do you want to upgrade? [y/N]: ", .{});

        const stdin_file = std.fs.File.stdin();
        var buf: [256]u8 = undefined;
        const bytes_read = try stdin_file.read(&buf);
        const input = std.mem.trim(u8, buf[0..bytes_read], " \t\r\n");

        if (!std.mem.eql(u8, input, "y") and !std.mem.eql(u8, input, "Y")) {
            try w.print("Upgrade cancelled.\n", .{});
            return 0;
        }

        // Install the update
        try installer.installRelease(allocator, release, options.verbose);

        try w.print("\n{s}{s}✓ Upgrade complete!{s}\n", .{ green, bold, reset });
        try w.print("Run 'zr --version' to verify.\n", .{});

        return 0;
    } else {
        const green = output.Code.green;
        const bold = output.Code.bold;
        const reset = output.Code.reset;

        try w.print("{s}{s}✓ You are already on the latest version ({s}){s}\n", .{
            green,
            bold,
            checker.CURRENT_VERSION,
            reset,
        });
        return 0;
    }
}

fn printHelp(ew: *std.Io.Writer) !void {
    try ew.print(
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
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    const args = [_][]const u8{"--help"};
    const exit_code = try cmdUpgrade(allocator, &args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "UpgradeOptions defaults" {
    const options = types.UpgradeOptions{};
    try std.testing.expect(!options.check_only);
    try std.testing.expect(!options.include_prerelease);
    try std.testing.expect(!options.verbose);
    try std.testing.expect(options.version == null);
}

test "cmdUpgrade writes help to writer when --help provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = &[_][]const u8{"--help"};

    // This should FAIL until cmdUpgrade is refactored to accept writers
    const code = try cmdUpgrade(allocator, args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdUpgrade writes error to ew when unknown option provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = &[_][]const u8{"--unknown-option"};

    // This should FAIL until cmdUpgrade is refactored to accept writers
    const code = try cmdUpgrade(allocator, args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 1), code);
}
