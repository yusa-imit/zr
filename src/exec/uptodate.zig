const std = @import("std");
const glob_mod = @import("../util/glob.zig");

/// Check if task outputs are up-to-date relative to sources.
/// Returns true if task can be skipped (all generates exist and are newer than all sources).
pub fn isUpToDate(
    allocator: std.mem.Allocator,
    sources: []const []const u8,
    generates: []const []const u8,
    cwd: ?[]const u8,
) !bool {
    // If no generates specified, task always runs (can't verify up-to-date status)
    if (generates.len == 0) return false;

    // Expand globs for sources and generates
    const expanded_sources = try expandGlobs(allocator, sources, cwd);
    defer freeExpandedPaths(allocator, expanded_sources);

    const expanded_generates = try expandGlobs(allocator, generates, cwd);
    defer freeExpandedPaths(allocator, expanded_generates);

    // If any generate missing, not up-to-date
    for (expanded_generates) |gen_path| {
        const exists = try fileExists(gen_path);
        if (!exists) return false;
    }

    // If no sources specified but generates exist, task is up-to-date
    if (expanded_sources.len == 0) return true;

    // Find newest source mtime
    var newest_source_mtime: i128 = 0;
    for (expanded_sources) |src_path| {
        const mtime = try getFileMtime(src_path);
        if (mtime > newest_source_mtime) {
            newest_source_mtime = mtime;
        }
    }

    // All generates must be newer than newest source
    for (expanded_generates) |gen_path| {
        const gen_mtime = try getFileMtime(gen_path);
        if (gen_mtime < newest_source_mtime) {
            return false; // Generate is older than source
        }
    }

    return true; // All checks passed
}

fn expandGlobs(allocator: std.mem.Allocator, patterns: []const []const u8, cwd: ?[]const u8) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer {
        for (result.items) |path| allocator.free(path);
        result.deinit(allocator);
    }

    const base_dir_path = cwd orelse ".";
    const base_dir = try std.fs.cwd().openDir(base_dir_path, .{ .iterate = true });
    var base_dir_opened = true;
    defer if (base_dir_opened) base_dir.close();

    for (patterns) |pattern| {
        // Use glob.find to expand pattern
        var matches = glob_mod.find(allocator, base_dir, pattern) catch |err| {
            // If glob fails (e.g., directory doesn't exist), treat pattern as literal
            if (err == error.FileNotFound) {
                try result.append(allocator, try allocator.dupe(u8, pattern));
                continue;
            }
            return err;
        };
        defer {
            for (matches) |m| allocator.free(m);
            allocator.free(matches);
        }

        // If no matches found and pattern doesn't contain wildcards, treat as literal
        if (matches.len == 0 and std.mem.indexOfAny(u8, pattern, "*?[") == null) {
            try result.append(allocator, try allocator.dupe(u8, pattern));
        } else {
            // Add all matches
            for (matches) |match| {
                try result.append(allocator, try allocator.dupe(u8, match));
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

fn freeExpandedPaths(allocator: std.mem.Allocator, paths: [][]const u8) void {
    for (paths) |path| allocator.free(path);
    allocator.free(paths);
}

fn fileExists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return false;
        return err;
    };
    return true;
}

fn getFileMtime(path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.mtime;
}

// Tests
test "uptodate: all generates exist and newer than sources" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create source and output
    try tmp.dir.writeFile(.{ .sub_path = "input.txt", .data = "v1" });
    std.time.sleep(10_000_000); // 10ms to ensure mtime difference
    try tmp.dir.writeFile(.{ .sub_path = "output.txt", .data = "result" });

    const sources = [_][]const u8{"input.txt"};
    const generates = [_][]const u8{"output.txt"};

    // Change to tmp directory
    const orig_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(orig_cwd);
    try std.fs.cwd().setAsCwd();
    defer {
        std.fs.cwd().access(orig_cwd, .{}) catch return;
        var orig_dir = std.fs.openDirAbsolute(orig_cwd, .{}) catch return;
        defer orig_dir.close();
        orig_dir.setAsCwd() catch {};
    }
    try tmp.dir.setAsCwd();

    const up_to_date = try isUpToDate(allocator, &sources, &generates, null);
    try std.testing.expect(up_to_date);
}

test "uptodate: source newer than generate" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create output first, then source (source newer)
    try tmp.dir.writeFile(.{ .sub_path = "output.txt", .data = "old" });
    std.time.sleep(10_000_000); // 10ms
    try tmp.dir.writeFile(.{ .sub_path = "input.txt", .data = "v2" });

    const sources = [_][]const u8{"input.txt"};
    const generates = [_][]const u8{"output.txt"};

    const orig_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(orig_cwd);
    try tmp.dir.setAsCwd();
    defer {
        std.fs.cwd().access(orig_cwd, .{}) catch return;
        var orig_dir = std.fs.openDirAbsolute(orig_cwd, .{}) catch return;
        defer orig_dir.close();
        orig_dir.setAsCwd() catch {};
    }

    const up_to_date = try isUpToDate(allocator, &sources, &generates, null);
    try std.testing.expect(!up_to_date);
}

test "uptodate: missing generate" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "input.txt", .data = "v1" });

    const sources = [_][]const u8{"input.txt"};
    const generates = [_][]const u8{"output.txt"}; // doesn't exist

    const orig_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(orig_cwd);
    try tmp.dir.setAsCwd();
    defer {
        std.fs.cwd().access(orig_cwd, .{}) catch return;
        var orig_dir = std.fs.openDirAbsolute(orig_cwd, .{}) catch return;
        defer orig_dir.close();
        orig_dir.setAsCwd() catch {};
    }

    const up_to_date = try isUpToDate(allocator, &sources, &generates, null);
    try std.testing.expect(!up_to_date);
}

test "uptodate: no generates specified" {
    const allocator = std.testing.allocator;

    const sources = [_][]const u8{"input.txt"};
    const generates = [_][]const u8{};

    const up_to_date = try isUpToDate(allocator, &sources, &generates, null);
    try std.testing.expect(!up_to_date); // Always run if no generates
}
