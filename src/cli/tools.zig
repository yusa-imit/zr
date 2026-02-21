const std = @import("std");
const color = @import("../output/color.zig");
const toolchain_types = @import("../toolchain/types.zig");
const toolchain_installer = @import("../toolchain/installer.zig");
const ToolKind = toolchain_types.ToolKind;
const ToolVersion = toolchain_types.ToolVersion;
const InstalledTool = toolchain_types.InstalledTool;

/// Main entry point for `zr tools <subcommand>` commands
pub fn cmdTools(
    allocator: std.mem.Allocator,
    sub: []const u8,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (std.mem.eql(u8, sub, "list")) {
        return cmdToolsList(allocator, args, w, ew, use_color);
    } else if (std.mem.eql(u8, sub, "install")) {
        return cmdToolsInstall(allocator, args, w, ew, use_color);
    } else if (std.mem.eql(u8, sub, "outdated")) {
        return cmdToolsOutdated(allocator, args, w, ew, use_color);
    } else if (std.mem.eql(u8, sub, "")) {
        try printToolsHelp(w, ew, use_color);
        return 0;
    } else {
        try color.printError(ew, use_color,
            "tools: unknown subcommand '{s}'\n\n  Hint: zr tools list | install | outdated\n",
            .{sub});
        return 1;
    }
}

/// `zr tools list [kind]` - List all installed toolchain versions
/// If kind is omitted, list all tools. If specified, list only that tool kind.
fn cmdToolsList(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // args[0] is the program name
    // args[1] is "tools"
    // args[2] is "list"
    // args[3] (optional) is the tool kind

    var filter_kind: ?ToolKind = null;

    // Parse optional tool kind filter
    if (args.len >= 4) {
        const kind_str = args[3];
        filter_kind = ToolKind.fromString(kind_str) orelse {
            try color.printError(ew, use_color,
                "tools list: unknown tool kind '{s}'\n\n  Hint: supported kinds: node, python, zig, go, rust, deno, bun, java\n",
                .{kind_str});
            return 1;
        };
    }

    var total_found: usize = 0;

    // If filter specified, list only that kind. Otherwise, list all.
    const tool_kinds = if (filter_kind) |kind|
        &[_]ToolKind{kind}
    else
        &[_]ToolKind{ .node, .python, .zig, .go, .rust, .deno, .bun, .java };

    for (tool_kinds) |kind| {
        const installed = try toolchain_installer.listInstalled(allocator, kind);
        defer {
            for (installed) |*tool| tool.deinit(allocator);
            allocator.free(installed);
        }

        if (installed.len > 0) {
            if (total_found > 0) try w.print("\n", .{});

            try color.printBold(w, use_color, "{s}:\n", .{kind.toString()});
            for (installed) |tool| {
                const version_str = try tool.version.toString(allocator);
                defer allocator.free(version_str);
                try color.printDim(w, use_color, "  {s}", .{version_str});
                try w.print(" → {s}\n", .{tool.install_path});
            }
            total_found += installed.len;
        }
    }

    if (total_found == 0) {
        try color.printDim(w, use_color, "No toolchains installed.\n", .{});
        try w.print("\n  Hint: zr tools install <kind>@<version>\n", .{});
    } else {
        try w.print("\n", .{});
        try color.printDim(w, use_color, "Total: {d} toolchain(s)\n", .{total_found});
    }

    return 0;
}

/// `zr tools install <kind>@<version>` - Install a specific toolchain version
fn cmdToolsInstall(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // args[0] is the program name
    // args[1] is "tools"
    // args[2] is "install"
    // args[3] is the spec (kind@version)

    if (args.len < 4) {
        try color.printError(ew, use_color,
            "tools install: missing tool specification\n\n  Hint: zr tools install <kind>@<version>\n  Example: zr tools install node@20.11.1\n",
            .{});
        return 1;
    }

    const spec_str = args[3];

    // Parse "kind@version" format
    var split = std.mem.splitScalar(u8, spec_str, '@');
    const kind_str = split.next() orelse {
        try color.printError(ew, use_color,
            "tools install: invalid spec '{s}'\n\n  Hint: use format <kind>@<version> (e.g., node@20.11.1)\n",
            .{spec_str});
        return 1;
    };
    const version_str = split.next() orelse {
        try color.printError(ew, use_color,
            "tools install: missing version in spec '{s}'\n\n  Hint: use format <kind>@<version> (e.g., node@20.11.1)\n",
            .{spec_str});
        return 1;
    };

    const kind = ToolKind.fromString(kind_str) orelse {
        try color.printError(ew, use_color,
            "tools install: unknown tool kind '{s}'\n\n  Hint: supported kinds: node, python, zig, go, rust, deno, bun, java\n",
            .{kind_str});
        return 1;
    };

    const version = ToolVersion.parse(version_str) catch |err| {
        try color.printError(ew, use_color,
            "tools install: invalid version '{s}': {s}\n\n  Hint: use semantic version format (e.g., 20.11.1 or 20.11)\n",
            .{ version_str, @errorName(err) });
        return 1;
    };

    // Check if already installed
    const already_installed = try toolchain_installer.isInstalled(allocator, kind, version);
    if (already_installed) {
        const version_display = try version.toString(allocator);
        defer allocator.free(version_display);
        try color.printDim(w, use_color, "✓ {s} {s} is already installed\n", .{ kind.toString(), version_display });
        return 0;
    }

    // Install the tool
    try color.printBold(w, use_color, "Installing {s} {s}...\n", .{ kind.toString(), version_str });

    toolchain_installer.install(allocator, kind, version) catch |err| {
        try color.printError(ew, use_color,
            "tools install: failed to install {s} {s}: {s}\n\n  Hint: check network connection and version availability\n",
            .{ kind.toString(), version_str, @errorName(err) });
        return 1;
    };

    const version_display = try version.toString(allocator);
    defer allocator.free(version_display);
    try color.printBold(w, use_color, "✓", .{});
    try w.print(" Successfully installed {s} {s}\n", .{ kind.toString(), version_display });

    return 0;
}

/// `zr tools outdated [kind]` - Check for installed tools that might have newer versions
/// NOTE: This is a stub implementation. Full implementation would require querying
/// official registries for latest versions, which is out of scope for Phase 5 MVP.
fn cmdToolsOutdated(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    _ = args;
    _ = allocator;
    _ = ew;

    try color.printDim(w, use_color, "tools outdated: not yet implemented\n", .{});
    try w.print("\n  Hint: this command will check for newer versions of installed toolchains\n", .{});
    try w.print("  in a future release.\n", .{});

    return 0;
}

fn printToolsHelp(w: *std.Io.Writer, ew: *std.Io.Writer, use_color: bool) !void {
    _ = ew;
    try color.printBold(w, use_color, "zr tools", .{});
    try w.print(" - Toolchain Management\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr tools <subcommand> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Subcommands:\n", .{});
    try w.print("  list [kind]           List installed toolchain versions\n", .{});
    try w.print("  install <kind>@<ver>  Install a specific toolchain version\n", .{});
    try w.print("  outdated [kind]       Check for outdated toolchains (not yet implemented)\n\n", .{});
    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.print("  zr tools list              # List all installed toolchains\n", .{});
    try w.print("  zr tools list node         # List installed Node.js versions\n", .{});
    try w.print("  zr tools install node@20.11.1  # Install Node.js 20.11.1\n", .{});
    try w.print("  zr tools install python@3.12   # Install Python 3.12\n\n", .{});
    try color.printBold(w, use_color, "Supported toolchains:\n", .{});
    try w.print("  node, python, zig, go, rust, deno, bun, java\n", .{});
}

test "cmdTools with empty subcommand shows help" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "" };
    const exit_code = try cmdTools(allocator, "", args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "cmdTools with unknown subcommand returns error" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "unknown" };
    const exit_code = try cmdTools(allocator, "unknown", args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

test "cmdToolsList returns 0 exit code" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "list" };
    const exit_code = try cmdToolsList(allocator, args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "cmdToolsInstall without spec returns error" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "install" };
    const exit_code = try cmdToolsInstall(allocator, args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

test "cmdToolsInstall with invalid spec returns error" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "install", "invalid-spec" };
    const exit_code = try cmdToolsInstall(allocator, args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

test "cmdToolsInstall with unknown kind returns error" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "install", "unknown@1.0.0" };
    const exit_code = try cmdToolsInstall(allocator, args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

test "cmdToolsOutdated stub implementation" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "outdated" };
    const exit_code = try cmdToolsOutdated(allocator, args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
