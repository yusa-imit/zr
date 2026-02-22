const std = @import("std");
const color = @import("../output/color.zig");
const toolchain_types = @import("../toolchain/types.zig");
const toolchain_installer = @import("../toolchain/installer.zig");
const toolchain_registry = @import("../toolchain/registry.zig");
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
fn cmdToolsOutdated(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Parse optional kind filter
    var filter_kind: ?ToolKind = null;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printOutdatedHelp(w, use_color);
            return 0;
        }
        if (ToolKind.fromString(arg)) |kind| {
            filter_kind = kind;
        }
    }

    // Get list of all installed tools
    const all_kinds = [_]ToolKind{ .node, .python, .zig, .go, .rust, .deno, .bun, .java };

    var has_outdated = false;
    var checked_count: usize = 0;

    for (all_kinds) |kind| {
        // Skip if filtered by kind
        if (filter_kind) |fk| {
            if (fk != kind) continue;
        }

        // List installed versions for this kind
        const installed = try toolchain_installer.listInstalled(allocator, kind);
        defer {
            for (installed) |*tool| {
                tool.deinit(allocator);
            }
            allocator.free(installed);
        }

        if (installed.len == 0) continue;

        checked_count += 1;

        // Fetch latest version from registry
        const latest = toolchain_registry.fetchLatestVersion(allocator, kind) catch |err| {
            if (checked_count == 1) {
                try color.printDim(w, use_color, "Checking for outdated toolchains...\n\n", .{});
            }
            try color.printDim(w, use_color, "  {s}: ", .{kind.toString()});
            try color.printError(ew, use_color, "failed to fetch latest version ({s})\n", .{@errorName(err)});
            continue;
        };

        if (checked_count == 1) {
            try color.printDim(w, use_color, "Checking for outdated toolchains...\n\n", .{});
        }

        // Find highest installed version
        var highest_installed: ?ToolVersion = null;
        for (installed) |tool| {
            if (highest_installed == null) {
                highest_installed = tool.version;
            } else {
                const curr = highest_installed.?;
                if (isNewer(tool.version, curr)) {
                    highest_installed = tool.version;
                }
            }
        }

        const curr_version = highest_installed.?;
        const is_outdated = isNewer(latest, curr_version);

        // Print comparison
        const curr_str = try curr_version.toString(allocator);
        defer allocator.free(curr_str);
        const latest_str = try latest.toString(allocator);
        defer allocator.free(latest_str);

        if (is_outdated) {
            has_outdated = true;
            try color.printInfo(w, use_color, "  {s: <10}", .{kind.toString()});
            try w.print(" {s: <12} → ", .{curr_str});
            try color.printSuccess(w, use_color, "{s: <12}", .{latest_str});
            try color.printDim(w, use_color, " (update available)\n", .{});
        } else {
            try color.printSuccess(w, use_color, "✓ ", .{});
            try color.printDim(w, use_color, "{s: <10} {s: <12}", .{ kind.toString(), curr_str });
            try color.printDim(w, use_color, " (up to date)\n", .{});
        }
    }

    if (checked_count == 0) {
        try color.printDim(w, use_color, "No toolchains installed.\n\n", .{});
        try w.print("  Hint: Install a toolchain with: zr tools install <kind>@<version>\n", .{});
        return 0;
    }

    if (has_outdated) {
        try w.writeAll("\n");
        try color.printDim(w, use_color, "  Run ", .{});
        try color.printBold(w, use_color, "zr tools install <kind>@<version>", .{});
        try color.printDim(w, use_color, " to update.\n", .{});
        return 1; // Exit code 1 to indicate updates available
    } else {
        try w.writeAll("\n");
        try color.printSuccess(w, use_color, "  All installed toolchains are up to date!\n", .{});
        return 0;
    }
}

/// Helper: check if v1 is newer than v2
fn isNewer(v1: ToolVersion, v2: ToolVersion) bool {
    if (v1.major > v2.major) return true;
    if (v1.major < v2.major) return false;
    if (v1.minor > v2.minor) return true;
    if (v1.minor < v2.minor) return false;

    const p1 = v1.patch orelse 0;
    const p2 = v2.patch orelse 0;
    return p1 > p2;
}

fn printOutdatedHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr tools outdated", .{});
    try w.print(" - Check for outdated toolchains\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr tools outdated [kind]\n\n", .{});
    try color.printBold(w, use_color, "Description:\n", .{});
    try w.print("  Checks installed toolchains against their official registries\n", .{});
    try w.print("  and reports which ones have newer versions available.\n\n", .{});
    try color.printBold(w, use_color, "Arguments:\n", .{});
    try w.print("  kind    Optional filter (node|python|zig|go|rust|deno|bun|java)\n\n", .{});
    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.print("  zr tools outdated        # Check all installed toolchains\n", .{});
    try w.print("  zr tools outdated node   # Check only Node.js installations\n", .{});
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
    try w.print("  outdated [kind]       Check for outdated toolchains\n\n", .{});
    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.print("  zr tools list                  # List all installed toolchains\n", .{});
    try w.print("  zr tools list node             # List installed Node.js versions\n", .{});
    try w.print("  zr tools install node@20.11.1  # Install Node.js 20.11.1\n", .{});
    try w.print("  zr tools install python@3.12   # Install Python 3.12\n", .{});
    try w.print("  zr tools outdated              # Check all for updates\n", .{});
    try w.print("  zr tools outdated node         # Check only Node.js\n\n", .{});
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

test "isNewer version comparison" {
    const v1 = ToolVersion{ .major = 20, .minor = 11, .patch = 1 };
    const v2 = ToolVersion{ .major = 20, .minor = 12, .patch = 0 };
    const v3 = ToolVersion{ .major = 21, .minor = 0, .patch = 0 };
    const v4 = ToolVersion{ .major = 20, .minor = 11, .patch = 2 };

    // v2 is newer than v1 (minor version bump)
    try std.testing.expect(isNewer(v2, v1));
    try std.testing.expect(!isNewer(v1, v2));

    // v3 is newer than v1 (major version bump)
    try std.testing.expect(isNewer(v3, v1));
    try std.testing.expect(!isNewer(v1, v3));

    // v4 is newer than v1 (patch version bump)
    try std.testing.expect(isNewer(v4, v1));
    try std.testing.expect(!isNewer(v1, v4));

    // Same version
    try std.testing.expect(!isNewer(v1, v1));
}

test "cmdToolsOutdated with --help shows help" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "outdated", "--help" };
    const exit_code = try cmdToolsOutdated(allocator, args, &out_w.interface, &err_w.interface, false);

    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "cmdToolsOutdated with no installed tools" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = &[_][]const u8{ "zr", "tools", "outdated" };
    const exit_code = try cmdToolsOutdated(allocator, args, &out_w.interface, &err_w.interface, false);

    // Should return 0 when no tools installed (not an error condition)
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
