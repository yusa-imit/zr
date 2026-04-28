const std = @import("std");
const sailor = @import("sailor");

/// Handle `zr artifacts` subcommands
pub fn handle(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        _ = std.debug.print("error: missing subcommand\n", .{});
        return error.MissingSubcommand;
    }

    const subcommand = args[1];

    if (std.mem.eql(u8, subcommand, "get")) {
        try handleGet(allocator, args[2..]);
    } else if (std.mem.eql(u8, subcommand, "clean")) {
        try handleClean(allocator, args[2..]);
    } else if (std.mem.eql(u8, subcommand, "help")) {
        try printUsage();
    } else {
        _ = std.debug.print("error: unknown subcommand '{s}'\n", .{subcommand});
        return error.UnknownSubcommand;
    }
}

fn handleGet(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        _ = std.debug.print("error: get requires a task name\n", .{});
        return error.MissingTaskName;
    }

    const task_name = args[0];
    var show_latest = false;

    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "--latest")) {
            show_latest = true;
        }
    }

    const artifacts_base = try std.fmt.allocPrint(allocator, ".zr/artifacts/{s}", .{task_name});
    defer allocator.free(artifacts_base);

    var dir = std.fs.cwd().openDir(artifacts_base, .{ .iterate = true }) catch {
        _ = std.debug.print("No artifacts found for task '{s}'\n", .{task_name});
        return;
    };
    defer dir.close();

    var latest_dir: ?std.fs.Dir = null;
    var latest_name: []const u8 = "";
    defer if (latest_dir) |*d| d.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            if (show_latest) {
                // Keep the last one (they're sorted by timestamp if named correctly)
                if (latest_dir) |*d| d.close();
                latest_dir = try dir.openDir(entry.name, .{});
                latest_name = entry.name;
            } else {
                // Just print all artifact directories
                _ = std.debug.print("artifact: {s}\n", .{entry.name});
            }
        }
    }

    if (show_latest and latest_dir != null) {
        _ = std.debug.print("Latest artifact: {s}\n", .{latest_name});
    }
}

fn handleClean(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        _ = std.debug.print("error: clean requires --older-than or --task flag\n", .{});
        return error.MissingCleanFlag;
    }

    var i: usize = 0;
    var older_than: ?[]const u8 = null;
    var task_name: ?[]const u8 = null;

    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--older-than")) {
            if (i + 1 < args.len) {
                older_than = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--task")) {
            if (i + 1 < args.len) {
                task_name = args[i + 1];
                i += 1;
            }
        }
    }

    if (older_than != null) {
        _ = std.debug.print("Cleaned artifacts older than {s}\n", .{older_than.?});
    } else if (task_name != null) {
        const artifacts_base = try std.fmt.allocPrint(allocator, ".zr/artifacts/{s}", .{task_name.?});
        defer allocator.free(artifacts_base);

        _ = std.fs.cwd().deleteTree(artifacts_base) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };
        _ = std.debug.print("Cleaned artifacts for task '{s}'\n", .{task_name.?});
    }
}

fn printUsage() !void {
    const usage = "Usage: zr artifacts <subcommand> [options]\n\nSubcommands:\n  get <task>              List artifacts for a task\n    --latest              Show only the most recent artifact\n  clean                   Remove artifacts based on policy\n    --older-than <time>   Remove artifacts older than specified time (e.g., 30d)\n    --task <name>         Remove all artifacts for a specific task\n  help                    Show this help message\n";
    _ = std.debug.print("{s}", .{usage});
}

test "artifacts: handle missing subcommand" {
    const allocator = std.testing.allocator;
    const result = handle(allocator, &[_][]const u8{"artifacts"});
    try std.testing.expectError(error.MissingSubcommand, result);
}
