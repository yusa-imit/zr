const std = @import("std");
const config_mod = @import("../config/types.zig");
const loader = @import("../config/loader.zig");
const types = @import("../versioning/types.zig");
const bump = @import("../versioning/bump.zig");
const conventional = @import("../versioning/conventional.zig");
const changelog = @import("../versioning/changelog.zig");
const common = @import("common.zig");
const color = @import("../output/color.zig");

pub fn cmdPublish(allocator: std.mem.Allocator, args: []const []const u8) !void {
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
                std.debug.print("Error: --bump requires a value (major|minor|patch)\n", .{});
                return;
            }
            i += 1;
            bump_type = types.BumpType.fromString(args[i]) orelse {
                std.debug.print("Error: Invalid bump type. Use: major, minor, or patch\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--package")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --package requires a value\n", .{});
                return;
            }
            i += 1;
            package_name = args[i];
        } else if (std.mem.eql(u8, arg, "--config")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --config requires a value\n", .{});
                return;
            }
            i += 1;
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--changelog")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --changelog requires a value\n", .{});
                return;
            }
            i += 1;
            changelog_path = args[i];
        } else if (std.mem.eql(u8, arg, "--since")) {
            if (i + 1 >= args.len) {
                std.debug.print("Error: --since requires a value\n", .{});
                return;
            }
            i += 1;
            since_ref = args[i];
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printPublishHelp();
            return;
        } else {
            std.debug.print("Error: Unknown option: {s}\n", .{arg});
            return;
        }
    }

    // Load config
    const cfg = loader.loadFromFile(allocator, config_path) catch |err| {
        std.debug.print("Error: Failed to load config: {s}\n", .{@errorName(err)});
        return;
    };
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit();
    }

    // Get versioning config
    const versioning_cfg = cfg.versioning orelse {
        std.debug.print("Error: No [versioning] section found in config\n", .{});
        std.debug.print("Add a [versioning] section to your zr.toml:\n", .{});
        std.debug.print("  [versioning]\n", .{});
        std.debug.print("  mode = \"independent\"  # or \"fixed\"\n", .{});
        std.debug.print("  convention = \"conventional\"  # or \"manual\"\n", .{});
        return;
    };

    // Determine package.json path
    const pkg_json_path = if (package_name) |name|
        try std.fmt.allocPrint(allocator, "packages/{s}/package.json", .{name})
    else
        "package.json";
    defer if (package_name != null) allocator.free(pkg_json_path);

    // Read current version
    const current_version = bump.readPackageJsonVersion(allocator, pkg_json_path) catch |err| {
        std.debug.print("Error: Failed to read package.json: {s}\n", .{@errorName(err)});
        return;
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
                std.debug.print("Error: No commits found since last version\n", .{});
                return;
            }

            std.debug.print("Found {d} commits since {s}\n", .{ commits.items.len, ref });
            break :blk conventional.determineBumpType(commits.items);
        } else {
            std.debug.print("Error: --bump is required when convention is 'manual'\n", .{});
            return;
        }
    };

    // Calculate new version
    const new_version = try bump.bumpVersion(allocator, current_version, actual_bump_type);
    defer allocator.free(new_version);

    // Show what will be done
    std.debug.print("\n", .{});
    std.debug.print("Current version: {s}\n", .{current_version});
    std.debug.print("Bump type:       {s}\n", .{@tagName(actual_bump_type)});
    std.debug.print("New version:     {s}\n", .{new_version});
    std.debug.print("Package:         {s}\n", .{pkg_json_path});
    std.debug.print("\n", .{});

    if (dry_run) {
        std.debug.print("(Dry run - no changes made)\n", .{});
        return;
    }

    // Update package.json
    try bump.writePackageJsonVersion(allocator, pkg_json_path, new_version);
    std.debug.print("✓ Updated {s}\n", .{pkg_json_path});

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
            std.debug.print("✓ Updated {s}\n", .{changelog_path});
        }
    }

    // Create git tag
    const tag_name = try std.fmt.allocPrint(allocator, "v{s}", .{new_version});
    defer allocator.free(tag_name);

    const tag_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "tag", tag_name },
    }) catch |err| {
        std.debug.print("Error: Failed to create git tag: {s}\n", .{@errorName(err)});
        return;
    };
    defer {
        allocator.free(tag_result.stdout);
        allocator.free(tag_result.stderr);
    }

    if (tag_result.term.Exited != 0) {
        std.debug.print("Warning: Failed to create git tag: {s}\n", .{tag_result.stderr});
    } else {
        std.debug.print("✓ Created git tag {s}\n", .{tag_name});
    }

    std.debug.print("\n", .{});
    std.debug.print("Next steps:\n", .{});
    std.debug.print("  git add {s} {s}\n", .{ pkg_json_path, changelog_path });
    std.debug.print("  git commit -m \"chore: release {s}\"\n", .{new_version});
    std.debug.print("  git push --follow-tags\n", .{});
    std.debug.print("\n", .{});
}

fn printPublishHelp() !void {
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
    std.debug.print("{s}\n", .{help});
}

test "cmdPublish help" {
    const args = [_][]const u8{"--help"};
    try cmdPublish(std.testing.allocator, &args);
}
