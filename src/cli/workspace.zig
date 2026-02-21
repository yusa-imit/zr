const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const scheduler = @import("../exec/scheduler.zig");
const glob = @import("../util/glob.zig");

/// Resolve workspace member directories from glob patterns.
/// Supports wildcards in patterns (e.g., "packages/*", "tools/*/src", "apps/*/backend").
/// Returns a caller-owned slice of owned paths (absolute or relative to cwd).
pub fn resolveWorkspaceMembers(
    allocator: std.mem.Allocator,
    ws: loader.Workspace,
    config_filename: []const u8,
) ![][]const u8 {
    var members = std.ArrayList([]const u8){};
    errdefer {
        for (members.items) |m| allocator.free(m);
        members.deinit(allocator);
    }

    for (ws.members) |pattern| {
        // Check if pattern contains wildcards
        const has_wildcards = std.mem.indexOfAny(u8, pattern, "*?") != null;

        if (has_wildcards) {
            // Determine base directory and relative pattern
            // If pattern is absolute, extract the base dir
            var base_dir: std.fs.Dir = blk: {
                if (pattern.len > 0 and pattern[0] == '/') {
                    // Absolute path - find the first component with wildcard
                    var i: usize = 0;
                    while (i < pattern.len) : (i += 1) {
                        if (pattern[i] == '*' or pattern[i] == '?') break;
                    }
                    // Find last '/' before the wildcard
                    const last_slash = std.mem.lastIndexOfScalar(u8, pattern[0..i], '/');
                    if (last_slash) |idx| {
                        const base_path = pattern[0..idx];
                        break :blk std.fs.openDirAbsolute(base_path, .{ .iterate = true }) catch {
                            continue;
                        };
                    }
                }
                break :blk std.fs.cwd();
            };
            const is_absolute = (pattern.len > 0 and pattern[0] == '/');
            defer if (is_absolute) base_dir.close();

            // Extract relative pattern
            const relative_pattern: []const u8 = blk: {
                if (pattern.len > 0 and pattern[0] == '/') {
                    var i: usize = 0;
                    while (i < pattern.len) : (i += 1) {
                        if (pattern[i] == '*' or pattern[i] == '?') break;
                    }
                    const last_slash = std.mem.lastIndexOfScalar(u8, pattern[0..i], '/');
                    if (last_slash) |idx| {
                        break :blk pattern[idx + 1 ..];
                    }
                }
                break :blk pattern;
            };

            // Use glob.findDirs to resolve directories matching the pattern
            const matching_dirs = glob.findDirs(allocator, base_dir, relative_pattern) catch continue;
            defer {
                for (matching_dirs) |d| allocator.free(d);
                allocator.free(matching_dirs);
            }

            for (matching_dirs) |dir_path| {
                // Reconstruct full path
                const full_path: []const u8 = blk: {
                    if (pattern.len > 0 and pattern[0] == '/') {
                        // Find the base part of the absolute pattern
                        var i: usize = 0;
                        while (i < pattern.len) : (i += 1) {
                            if (pattern[i] == '*' or pattern[i] == '?') break;
                        }
                        const last_slash = std.mem.lastIndexOfScalar(u8, pattern[0..i], '/');
                        if (last_slash) |idx| {
                            const base_path = pattern[0..idx];
                            break :blk try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, dir_path });
                        }
                    }
                    break :blk try allocator.dupe(u8, dir_path);
                };
                defer allocator.free(full_path);

                // Only include if it has a config file
                const cfg_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ full_path, config_filename });
                defer allocator.free(cfg_path);
                const has_config: bool = blk: {
                    std.fs.cwd().access(cfg_path, .{}) catch break :blk false;
                    break :blk true;
                };
                if (!has_config) continue;

                const member_path = try allocator.dupe(u8, full_path);
                try members.append(allocator, member_path);
            }
        } else {
            // Treat as a literal directory path
            const cfg_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ pattern, config_filename });
            defer allocator.free(cfg_path);
            const has_config: bool = blk: {
                std.fs.cwd().access(cfg_path, .{}) catch break :blk false;
                break :blk true;
            };
            if (!has_config) continue;
            const member_path = try allocator.dupe(u8, pattern);
            try members.append(allocator, member_path);
        }
    }

    // Sort for deterministic output
    std.mem.sort([]const u8, members.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    return members.toOwnedSlice(allocator);
}

pub fn cmdWorkspaceList(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    const ws = config.workspace orelse {
        try color.printError(ew, use_color,
            "workspace: no [workspace] section in {s}\n\n  Hint: Add [workspace] members = [\"packages/*\"] to your zr.toml\n",
            .{config_path});
        return 1;
    };

    const members = try resolveWorkspaceMembers(allocator, ws, common.CONFIG_FILE);
    defer {
        for (members) |m| allocator.free(m);
        allocator.free(members);
    }

    if (json_output) {
        try w.writeAll("{\"members\":[");
        for (members, 0..) |m, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeAll("{\"path\":");
            try common.writeJsonString(w, m);
            try w.writeAll("}");
        }
        try w.writeAll("]}\n");
    } else {
        try color.printBold(w, use_color, "Workspace Members ({d}):\n", .{members.len});
        if (members.len == 0) {
            try color.printDim(w, use_color, "  (no members found — check your glob patterns)\n", .{});
        } else {
            for (members) |m| {
                try w.print("  {s}\n", .{m});
            }
        }
    }

    return 0;
}

pub fn cmdWorkspaceRun(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    profile_name: ?[]const u8,
    dry_run: bool,
    max_jobs: u32,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var root_config = (try common.loadConfig(allocator, config_path, profile_name, ew, use_color)) orelse return 1;
    defer root_config.deinit();

    const ws = root_config.workspace orelse {
        try color.printError(ew, use_color,
            "workspace: no [workspace] section in {s}\n\n  Hint: Add [workspace] members = [\"packages/*\"] to your zr.toml\n",
            .{config_path});
        return 1;
    };

    const members = try resolveWorkspaceMembers(allocator, ws, common.CONFIG_FILE);
    defer {
        for (members) |m| allocator.free(m);
        allocator.free(members);
    }

    if (members.len == 0) {
        try color.printError(ew, use_color,
            "workspace: no member directories found\n\n  Hint: Check your [workspace] members patterns\n", .{});
        return 1;
    }

    var overall_success: bool = true;
    var ran_count: usize = 0;
    var skip_count: usize = 0;
    // json_emitted tracks how many members have been emitted to the JSON array
    // (separate from ran_count which also counts dry-run members)
    var json_emitted: usize = 0;

    // For dry-run mode, always use text output regardless of json_output flag
    // (dry-run produces plan text that can't be nested inside JSON)
    const effective_json = json_output and !dry_run;

    if (effective_json) {
        try w.writeAll("{\"task\":");
        try common.writeJsonString(w, task_name);
        try w.writeAll(",\"members\":[");
    }

    for (members) |member_path| {
        // Build path to member config
        const member_cfg = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ member_path, common.CONFIG_FILE });
        defer allocator.free(member_cfg);

        var member_config = loader.loadFromFile(allocator, member_cfg) catch |err| {
            if (err == error.FileNotFound) continue;
            try color.printError(ew, use_color,
                "workspace: failed to load {s}: {s}\n", .{ member_cfg, @errorName(err) });
            overall_success = false;
            continue;
        };
        defer member_config.deinit();

        // Skip members that don't define this task
        if (member_config.tasks.get(task_name) == null) {
            skip_count += 1;
            continue;
        }

        ran_count += 1;

        if (dry_run) {
            try color.printBold(w, use_color, "\n── {s} (dry-run) ──\n", .{member_path});
            var plan = try scheduler.planDryRun(allocator, &member_config, &[_][]const u8{task_name});
            defer plan.deinit();
            for (plan.levels, 0..) |level, li| {
                try w.print("  Level {d}: ", .{li});
                for (level.tasks, 0..) |t, ti| {
                    if (ti > 0) try w.writeAll(", ");
                    try w.writeAll(t);
                }
                try w.writeAll("\n");
            }
            continue;
        }

        if (effective_json) {
            if (json_emitted > 0) try w.writeAll(",");
        } else {
            try color.printBold(w, use_color, "\n── {s} ──\n", .{member_path});
        }

        const sched_cfg = scheduler.SchedulerConfig{
            .max_jobs = max_jobs,
            .inherit_stdio = true,
            .dry_run = false,
        };
        const task_names = [_][]const u8{task_name};
        var result = scheduler.run(allocator, &member_config, &task_names, sched_cfg) catch |err| {
            try color.printError(ew, use_color,
                "workspace: {s}: failed: {s}\n", .{ member_path, @errorName(err) });
            overall_success = false;
            if (effective_json) {
                try w.writeAll("{\"path\":");
                try common.writeJsonString(w, member_path);
                try w.writeAll(",\"success\":false}");
                json_emitted += 1;
            }
            continue;
        };
        defer result.deinit(allocator);

        if (!result.total_success) overall_success = false;

        if (effective_json) {
            try w.writeAll("{\"path\":");
            try common.writeJsonString(w, member_path);
            try w.print(",\"success\":{s}", .{if (result.total_success) "true" else "false"});
            try w.writeAll("}");
            json_emitted += 1;
        } else {
            if (result.total_success) {
                try color.printSuccess(w, use_color, "  ✓ {s}\n", .{member_path});
            } else {
                try color.printError(ew, use_color, "  ✗ {s}: task failed\n", .{member_path});
            }
        }
    }

    // Check if no member ran the task (consistent behavior for both text and JSON)
    if (ran_count == 0 and !dry_run) {
        if (effective_json) {
            try w.print("],\"ran\":0,\"skipped\":{d},\"success\":false}}\n", .{skip_count});
        } else {
            try color.printError(ew, use_color,
                "workspace: no members define task '{s}'\n", .{task_name});
        }
        return 1;
    }

    if (effective_json) {
        try w.print("],\"ran\":{d},\"skipped\":{d},\"success\":{s}}}\n",
            .{ ran_count, skip_count, if (overall_success) "true" else "false" });
    } else {
        try w.print("\n", .{});
        if (skip_count > 0) {
            try color.printDim(w, use_color, "  ({d} member(s) skipped — task '{s}' not defined)\n",
                .{ skip_count, task_name });
        }
        if (overall_success) {
            try color.printSuccess(w, use_color, "All {d} member(s) succeeded\n", .{ran_count});
        } else {
            try color.printError(ew, use_color,
                "workspace: one or more members failed\n", .{});
            return 1;
        }
    }

    return if (overall_success) 0 else 1;
}

test "workspace: Workspace struct deinit is safe" {
    const allocator = std.testing.allocator;
    // Build a Workspace manually and deinit it
    const members = try allocator.alloc([]const u8, 2);
    members[0] = try allocator.dupe(u8, "packages/*");
    members[1] = try allocator.dupe(u8, "apps/*");
    const ignore = try allocator.alloc([]const u8, 1);
    ignore[0] = try allocator.dupe(u8, "**/node_modules");
    var ws = loader.Workspace{ .members = members, .ignore = ignore };
    ws.deinit(allocator);
    // If we get here without crash/leak, the test passes
}

test "resolveWorkspaceMembers: glob pattern finds dirs with config" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Get absolute path to the tmp directory
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create packages/foo/, packages/bar/, packages/baz/
    try tmp.dir.makePath("packages/foo");
    try tmp.dir.makePath("packages/bar");
    try tmp.dir.makePath("packages/baz");

    // Write zr.toml in foo and bar but NOT baz
    try tmp.dir.writeFile(.{ .sub_path = "packages/foo/zr.toml", .data = "[tasks.build]\ncmd = \"echo foo\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "packages/bar/zr.toml", .data = "[tasks.build]\ncmd = \"echo bar\"\n" });

    // Build the glob pattern as absolute path
    const pattern = try std.fmt.allocPrint(allocator, "{s}/packages/*", .{tmp_path});
    defer allocator.free(pattern);

    var patterns = [_][]const u8{pattern};
    const ws = loader.Workspace{ .members = patterns[0..], .ignore = &.{} };

    const result = try resolveWorkspaceMembers(allocator, ws, "zr.toml");
    defer {
        for (result) |m| allocator.free(m);
        allocator.free(result);
    }

    // foo and bar should be included; baz excluded
    try std.testing.expectEqual(@as(usize, 2), result.len);

    // Results are sorted, so bar comes before foo
    const bar_path = try std.fmt.allocPrint(allocator, "{s}/packages/bar", .{tmp_path});
    defer allocator.free(bar_path);
    const foo_path = try std.fmt.allocPrint(allocator, "{s}/packages/foo", .{tmp_path});
    defer allocator.free(foo_path);

    try std.testing.expectEqualStrings(bar_path, result[0]);
    try std.testing.expectEqualStrings(foo_path, result[1]);
}

test "resolveWorkspaceMembers: literal path with config" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create myapp/ with a zr.toml
    try tmp.dir.makePath("myapp");
    try tmp.dir.writeFile(.{ .sub_path = "myapp/zr.toml", .data = "[tasks.start]\ncmd = \"echo myapp\"\n" });

    const pattern = try std.fmt.allocPrint(allocator, "{s}/myapp", .{tmp_path});
    defer allocator.free(pattern);

    var patterns = [_][]const u8{pattern};
    const ws = loader.Workspace{ .members = patterns[0..], .ignore = &.{} };

    const result = try resolveWorkspaceMembers(allocator, ws, "zr.toml");
    defer {
        for (result) |m| allocator.free(m);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings(pattern, result[0]);
}

test "resolveWorkspaceMembers: literal path without config returns empty" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create myapp/ but do NOT write a zr.toml inside
    try tmp.dir.makePath("myapp");

    const pattern = try std.fmt.allocPrint(allocator, "{s}/myapp", .{tmp_path});
    defer allocator.free(pattern);

    var patterns = [_][]const u8{pattern};
    const ws = loader.Workspace{ .members = patterns[0..], .ignore = &.{} };

    const result = try resolveWorkspaceMembers(allocator, ws, "zr.toml");
    defer {
        for (result) |m| allocator.free(m);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "resolveWorkspaceMembers: empty members list" {
    const allocator = std.testing.allocator;

    const ws = loader.Workspace{ .members = &.{}, .ignore = &.{} };

    const result = try resolveWorkspaceMembers(allocator, ws, "zr.toml");
    defer {
        for (result) |m| allocator.free(m);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "cmdWorkspaceList: no workspace section returns error" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write a zr.toml with tasks but no [workspace] section
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "[tasks.build]\ncmd = \"make\"\n" });

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdWorkspaceList(allocator, config_path, false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "cmdWorkspaceList: missing config returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdWorkspaceList(allocator, "/nonexistent/path/to/zr.toml", false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}
