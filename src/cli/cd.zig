const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");

/// Handle `zr cd <member>` command — print path to workspace member for shell integration
pub fn cmdCd(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    member_name: []const u8,
    w: anytype,
    err_writer: anytype,
    use_color: bool,
) !u8 {
    // Load config to get workspace members
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const config_path = dir.realpath(common.CONFIG_FILE, &path_buf) catch |err| {
        try color.printError(err_writer, use_color,
            "[CD]: Failed to find {s}: {s}\n\n  Hint: Run this command from a directory with {s}\n",
            .{ common.CONFIG_FILE, @errorName(err), common.CONFIG_FILE });
        return 1;
    };

    var cfg = loader.loadFromFile(allocator, config_path) catch |err| {
        try color.printError(err_writer, use_color,
            "[CD]: Failed to load config: {s}\n\n  Hint: Check {s} for syntax errors\n",
            .{ @errorName(err), common.CONFIG_FILE });
        return 1;
    };
    defer cfg.deinit();

    // Check if workspace is configured
    if (cfg.workspace == null) {
        try color.printError(err_writer, use_color,
            "[CD]: No workspace configured\n\n  Hint: Add [workspace] section to {s} with 'members' patterns\n",
            .{common.CONFIG_FILE});
        return 1;
    }

    const workspace = cfg.workspace.?;

    // Discover workspace members by expanding glob patterns
    var members = std.ArrayList([]const u8){};
    defer {
        for (members.items) |path| allocator.free(path);
        members.deinit(allocator);
    }

    const cwd_path = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    for (workspace.members) |pattern| {
        // Use glob to expand patterns (e.g., "packages/*")
        const Glob = @import("../util/glob.zig");
        const matches = try Glob.findDirs(allocator, dir, pattern);
        defer {
            for (matches) |match| allocator.free(match);
            allocator.free(matches);
        }

        for (matches) |match| {
            // Check if this is a directory with zr.toml
            var match_dir = dir.openDir(match, .{}) catch continue;
            defer match_dir.close();

            match_dir.access(common.CONFIG_FILE, .{}) catch continue;

            // This is a valid workspace member
            const member_path = try allocator.dupe(u8, match);
            try members.append(allocator, member_path);
        }
    }

    if (members.items.len == 0) {
        try color.printError(err_writer, use_color,
            "[CD]: No workspace members found\n\n  Hint: Check 'members' patterns in [workspace] section\n", .{});
        return 1;
    }

    // Find member by name (basename match or full path match)
    var target_path: ?[]const u8 = null;

    for (members.items) |path| {
        const basename = std.fs.path.basename(path);
        if (std.mem.eql(u8, basename, member_name) or std.mem.eql(u8, path, member_name)) {
            target_path = path;
            break;
        }
    }

    if (target_path == null) {
        // Fuzzy match: find similar names
        const levenshtein = @import("../util/levenshtein.zig");
        var suggestions = std.ArrayList([]const u8){};
        defer suggestions.deinit(allocator);

        for (members.items) |path| {
            const basename = std.fs.path.basename(path);
            const dist = try levenshtein.distance(allocator, member_name, basename);
            if (dist <= 3) { // Allow up to 3 character edits
                try suggestions.append(allocator, basename);
            }
        }

        try color.printError(err_writer, use_color,
            "[CD]: Workspace member '{s}' not found\n\n", .{member_name});

        if (suggestions.items.len > 0) {
            try color.printInfo(err_writer, use_color, "Did you mean?\n", .{});
            for (suggestions.items) |suggestion| {
                try err_writer.print("  - {s}\n", .{suggestion});
            }
            try err_writer.writeByte('\n');
        }

        try color.printDim(err_writer, use_color, "Available members:\n", .{});
        for (members.items) |path| {
            const basename = std.fs.path.basename(path);
            try err_writer.print("  - {s} ({s})\n", .{ basename, path });
        }

        return 1;
    }

    // Print the absolute path for shell integration
    // The shell wrapper will use this to cd
    try w.print("{s}\n", .{target_path.?});

    return 0;
}

test "cmdCd: no config file returns 1 with error message" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdCd(allocator, tmp.dir, "frontend", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);

    const err_output = err_buf[0..];
    try std.testing.expect(std.mem.indexOf(u8, err_output, "Failed to find") != null);
}

test "cmdCd: no workspace configured returns 1" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create zr.toml without [workspace] section
    const toml = "[tasks.build]\ncmd = \"echo build\"\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdCd(allocator, tmp.dir, "frontend", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);

    const err_output = err_buf[0..];
    try std.testing.expect(std.mem.indexOf(u8, err_output, "No workspace configured") != null);
}

test "cmdCd: no workspace members found returns 1" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create zr.toml with [workspace] but pattern matches no directories
    const toml = "[workspace]\nmembers = [\"nonexistent/*\"]\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdCd(allocator, tmp.dir, "frontend", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);

    const err_output = err_buf[0..];
    try std.testing.expect(std.mem.indexOf(u8, err_output, "No workspace members found") != null);
}

test "cmdCd: member found prints absolute path" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create workspace structure
    try tmp.dir.makePath("packages/frontend");
    try tmp.dir.makePath("packages/backend");

    // Create zr.toml in root
    const toml = "[workspace]\nmembers = [\"packages/*\"]\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    // Create zr.toml in each member
    try tmp.dir.writeFile(.{ .sub_path = "packages/frontend/zr.toml", .data = "[tasks.dev]\ncmd = \"npm run dev\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "packages/backend/zr.toml", .data = "[tasks.dev]\ncmd = \"npm run dev\"\n" });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdCd(allocator, tmp.dir, "frontend", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);

    const written = out_buf[0..];
    try std.testing.expect(std.mem.indexOf(u8, written, "packages/frontend") != null);
}

test "cmdCd: member not found returns 1 with available members" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create workspace structure
    try tmp.dir.makePath("packages/frontend");
    try tmp.dir.makePath("packages/backend");

    // Create zr.toml in root
    const toml = "[workspace]\nmembers = [\"packages/*\"]\n";
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    // Create zr.toml in each member
    try tmp.dir.writeFile(.{ .sub_path = "packages/frontend/zr.toml", .data = "[tasks.dev]\ncmd = \"npm run dev\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "packages/backend/zr.toml", .data = "[tasks.dev]\ncmd = \"npm run dev\"\n" });

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const code = try cmdCd(allocator, tmp.dir, "nonexistent", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);

    const err_output = err_buf[0..];
    try std.testing.expect(std.mem.indexOf(u8, err_output, "not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, err_output, "Available members") != null);
}
