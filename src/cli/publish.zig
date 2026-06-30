const std = @import("std");
const config_mod = @import("../config/types.zig");
const loader = @import("../config/loader.zig");
const types = @import("../versioning/types.zig");
const bump = @import("../versioning/bump.zig");
const conventional = @import("../versioning/conventional.zig");
const changelog = @import("../versioning/changelog.zig");
const common = @import("common.zig");
const output = @import("../output/color.zig");

pub fn cmdPublish(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.io.Writer,
    ew: *std.io.Writer,
    use_color: bool,
) !u8 {
    var bump_type: ?types.BumpType = null;
    var package_name: ?[]const u8 = null;
    var config_path: []const u8 = "zr.toml";
    var changelog_path: []const u8 = "CHANGELOG.md";
    var dry_run = false;
    var since_ref: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--bump")) {
            if (i + 1 >= args.len) {
                try output.printError(ew, use_color, "[Publish]: --bump requires a value\n\n  Hint: Use --bump major, --bump minor, or --bump patch\n", .{});
                return 1;
            }
            i += 1;
            bump_type = types.BumpType.fromString(args[i]) orelse {
                try output.printError(ew, use_color, "[Publish]: Invalid bump type '{s}'\n\n  Hint: Use major, minor, or patch\n", .{args[i]});
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "--package")) {
            if (i + 1 >= args.len) {
                try output.printError(ew, use_color, "[Publish]: --package requires a value\n\n  Hint: zr publish --package my-package\n", .{});
                return 1;
            }
            i += 1;
            package_name = args[i];
        } else if (std.mem.eql(u8, arg, "--config")) {
            if (i + 1 >= args.len) {
                try output.printError(ew, use_color, "[Publish]: --config requires a path argument\n\n  Hint: zr publish --config path/to/zr.toml\n", .{});
                return 1;
            }
            i += 1;
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--changelog")) {
            if (i + 1 >= args.len) {
                try output.printError(ew, use_color, "[Publish]: --changelog requires a path argument\n\n  Hint: zr publish --changelog CHANGELOG.md\n", .{});
                return 1;
            }
            i += 1;
            changelog_path = args[i];
        } else if (std.mem.eql(u8, arg, "--since")) {
            if (i + 1 >= args.len) {
                try output.printError(ew, use_color, "[Publish]: --since requires a git reference\n\n  Hint: zr publish --since v1.0.0\n", .{});
                return 1;
            }
            i += 1;
            since_ref = args[i];
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printPublishHelp(w, ew, use_color);
            return 0;
        } else {
            try output.printError(ew, use_color, "[Publish]: Unknown option '{s}'\n\n  Hint: zr publish --help\n", .{arg});
            return 1;
        }
    }

    // Load config
    const cfg = loader.loadFromFile(allocator, config_path) catch |err| {
        try output.printError(ew, use_color, "[Publish]: Failed to load config from {s}\n\n  Error: {s}\n  Hint: Check that {s} exists and is valid TOML\n", .{ config_path, @errorName(err), config_path });
        return 1;
    };
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit();
    }

    // Get versioning config
    const versioning_cfg = cfg.versioning orelse {
        try output.printError(ew, use_color, "[Publish]: No [versioning] section found in config. Cannot publish.\n\n", .{});
        try ew.print("  Add a [versioning] section to your zr.toml:\n", .{});
        try ew.print("  [versioning]\n", .{});
        try ew.print("  mode = \"independent\"  # or \"fixed\"\n", .{});
        try ew.print("  convention = \"conventional\"  # or \"manual\"\n\n", .{});
        return 1;
    };

    // Determine package.json path
    const pkg_json_path = if (package_name) |name|
        try std.fmt.allocPrint(allocator, "packages/{s}/package.json", .{name})
    else
        "package.json";
    defer if (package_name != null) allocator.free(pkg_json_path);

    // Read current version
    const current_version = bump.readPackageJsonVersion(allocator, pkg_json_path) catch |err| {
        try output.printError(ew, use_color, "[Publish]: Failed to read {s}\n\n  Error: {s}\n  Hint: Ensure {s} exists and contains a valid version field\n", .{ pkg_json_path, @errorName(err), pkg_json_path });
        return 1;
    };
    defer allocator.free(current_version);

    // Determine bump type
    const actual_bump_type = blk: {
        if (bump_type) |bt| {
            break :blk bt;
        }

        if (versioning_cfg.convention == .conventional) {
            // Get commits since last version tag
            const ref = since_ref orelse try std.fmt.allocPrint(allocator, "v{s}", .{current_version});
            defer if (since_ref == null) allocator.free(ref);

            var commits = try conventional.getCommitsSince(allocator, ref);
            defer {
                for (commits.items) |*c| c.deinit();
                commits.deinit(allocator);
            }

            if (commits.items.len == 0) {
                try output.printError(ew, use_color, "[Publish]: No commits found since {s}\n\n  Hint: Ensure there are new commits to release\n", .{ref});
                return 1;
            }

            try output.printInfo(w, use_color, "Found {d} commits since {s}\n", .{ commits.items.len, ref });
            break :blk conventional.determineBumpType(commits.items);
        } else {
            try output.printError(ew, use_color, "[Publish]: --bump is required when convention is 'manual'\n\n  Hint: zr publish --bump patch\n", .{});
            return 1;
        }
    };

    // Calculate new version
    const new_version = try bump.bumpVersion(allocator, current_version, actual_bump_type);
    defer allocator.free(new_version);

    // Show what will be done
    try w.print("\n", .{});
    try output.printInfo(w, use_color, "Current version: {s}\n", .{current_version});
    try output.printInfo(w, use_color, "Bump type:       {s}\n", .{@tagName(actual_bump_type)});
    try output.printInfo(w, use_color, "New version:     {s}\n", .{new_version});
    try output.printInfo(w, use_color, "Package:         {s}\n", .{pkg_json_path});
    try w.print("\n", .{});

    if (dry_run) {
        try output.printInfo(w, use_color, "(Dry run - no changes made)\n", .{});
        return 0;
    }

    // Update package.json
    try bump.writePackageJsonVersion(allocator, pkg_json_path, new_version);
    try output.printSuccess(w, use_color, "Updated {s}\n", .{pkg_json_path});

    // Generate and update CHANGELOG.md
    if (versioning_cfg.convention == .conventional) {
        const ref = since_ref orelse try std.fmt.allocPrint(allocator, "v{s}", .{current_version});
        defer if (since_ref == null) allocator.free(ref);

        var commits = try conventional.getCommitsSince(allocator, ref);
        defer {
            for (commits.items) |*c| c.deinit();
            commits.deinit(allocator);
        }

        if (commits.items.len > 0) {
            const changelog_section = try changelog.generateChangelog(allocator, new_version, commits.items, null);
            defer allocator.free(changelog_section);

            try changelog.prependToChangelog(allocator, changelog_path, changelog_section);
            try output.printSuccess(w, use_color, "Updated {s}\n", .{changelog_path});
        }
    }

    // Create git tag
    const tag_name = try std.fmt.allocPrint(allocator, "v{s}", .{new_version});
    defer allocator.free(tag_name);

    const tag_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "tag", tag_name },
    }) catch |err| {
        try output.printError(ew, use_color, "[Publish]: Failed to create git tag\n\n  Error: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer {
        allocator.free(tag_result.stdout);
        allocator.free(tag_result.stderr);
    }

    if (tag_result.term.Exited != 0) {
        try output.printWarning(w, use_color, "Failed to create git tag: {s}\n", .{tag_result.stderr});
    } else {
        try output.printSuccess(w, use_color, "Created git tag {s}\n", .{tag_name});
    }

    try w.print("\n", .{});
    try output.printInfo(w, use_color, "Next steps:\n", .{});
    try w.print("  git add {s} {s}\n", .{ pkg_json_path, changelog_path });
    try w.print("  git commit -m \"chore: release {s}\"\n", .{new_version});
    try w.print("  git push --follow-tags\n", .{});
    try w.print("\n", .{});

    return 0;
}

fn printPublishHelp(w: *std.io.Writer, ew: *std.io.Writer, use_color: bool) !void {
    _ = ew;
    _ = use_color;
    const help =
        \\Usage: zr publish [OPTIONS]
        \\
        \\Publish a new version of the package.
        \\
        \\OPTIONS:
        \\  --bump <type>       Bump type: major, minor, or patch
        \\                      (Required for manual convention, optional for conventional)
        \\  --package <name>    Package name (for monorepos)
        \\  --config <path>     Config file path (default: zr.toml)
        \\  --changelog <path>  Changelog file path (default: CHANGELOG.md)
        \\  --since <ref>       Git ref to find commits since (default: v<current-version>)
        \\  --dry-run, -n       Show what would be done without making changes
        \\  --help, -h          Show this help message
        \\
        \\EXAMPLES:
        \\  # Auto-detect bump type from conventional commits
        \\  zr publish
        \\
        \\  # Manually specify bump type
        \\  zr publish --bump minor
        \\
        \\  # Publish specific package in monorepo
        \\  zr publish --package my-app --bump patch
        \\
        \\  # Dry run to see what would happen
        \\  zr publish --dry-run
        \\
    ;
    try w.print("{s}\n", .{help});
}

test "cmdPublish help does not error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const args = [_][]const u8{"--help"};
    const exit_code = try cmdPublish(allocator, &args, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "cmdPublish handles invalid options gracefully" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const invalid_args = [_][]const u8{"--invalid-option"};
    const exit_code = try cmdPublish(allocator, &invalid_args, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

test "cmdPublish handles missing option values" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    // Test missing bump value (prints error and returns)
    const missing_bump = [_][]const u8{"--bump"};
    const exit_code1 = try cmdPublish(allocator, &missing_bump, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 1), exit_code1);

    // Test missing package value
    const missing_package = [_][]const u8{"--package"};
    const exit_code2 = try cmdPublish(allocator, &missing_package, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 1), exit_code2);

    // Test missing config value
    const missing_config = [_][]const u8{"--config"};
    const exit_code3 = try cmdPublish(allocator, &missing_config, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 1), exit_code3);

    // Test missing changelog value
    const missing_changelog = [_][]const u8{"--changelog"};
    const exit_code4 = try cmdPublish(allocator, &missing_changelog, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 1), exit_code4);

    // Test missing since value
    const missing_since = [_][]const u8{"--since"};
    const exit_code5 = try cmdPublish(allocator, &missing_since, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 1), exit_code5);
}

test "printPublishHelp does not crash" {
    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    try printPublishHelp(&out_w, &err_w, false);
}
