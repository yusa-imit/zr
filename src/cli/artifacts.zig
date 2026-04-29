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

    // Collect all artifact directories
    var artifact_list = std.ArrayList(struct {
        name: []const u8,
        timestamp: i64,
    }){};
    defer {
        for (artifact_list.items) |item| {
            allocator.free(item.name);
        }
        artifact_list.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const timestamp = std.fmt.parseInt(i64, entry.name, 10) catch continue;
            const name = try allocator.dupe(u8, entry.name);
            try artifact_list.append(allocator, .{ .name = name, .timestamp = timestamp });
        }
    }

    // Sort by timestamp (newest first)
    std.mem.sort(@TypeOf(artifact_list.items[0]), artifact_list.items, {}, struct {
        fn lessThan(_: void, a: @TypeOf(artifact_list.items[0]), b: @TypeOf(artifact_list.items[0])) bool {
            return a.timestamp > b.timestamp;
        }
    }.lessThan);

    if (show_latest) {
        // Show only the latest artifact with detailed info
        if (artifact_list.items.len == 0) {
            _ = std.debug.print("No artifacts found for task '{s}'\n", .{task_name});
            return;
        }

        const latest = artifact_list.items[0];
        const manifest_path = try std.fmt.allocPrint(allocator, "{s}/{s}/manifest.json", .{ artifacts_base, latest.name });
        defer allocator.free(manifest_path);

        // Read and display manifest
        const manifest_data = std.fs.cwd().readFileAlloc(allocator, manifest_path, 1024 * 1024) catch |err| {
            _ = std.debug.print("Latest artifact: {s} (no manifest: {})\n", .{ latest.name, err });
            return;
        };
        defer allocator.free(manifest_data);

        _ = std.debug.print("Latest artifact for task '{s}':\n", .{task_name});
        _ = std.debug.print("  Timestamp: {d}\n", .{latest.timestamp});
        _ = std.debug.print("  Manifest:\n{s}\n", .{manifest_data});
    } else {
        // List all artifacts
        if (artifact_list.items.len == 0) {
            _ = std.debug.print("No artifacts found for task '{s}'\n", .{task_name});
            return;
        }

        _ = std.debug.print("Artifacts for task '{s}' ({d} total):\n", .{ task_name, artifact_list.items.len });
        for (artifact_list.items) |item| {
            _ = std.debug.print("  - {s}\n", .{item.name});
        }
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

    if (older_than) |time_str| {
        // Parse time string (e.g., "30d")
        if (time_str.len < 2 or time_str[time_str.len - 1] != 'd') {
            _ = std.debug.print("error: --older-than format must be like '30d' (days)\n", .{});
            return error.InvalidTimeFormat;
        }

        const days_str = time_str[0 .. time_str.len - 1];
        const days = try std.fmt.parseInt(i64, days_str, 10);
        const now = std.time.milliTimestamp();
        const cutoff = now - (days * 24 * 60 * 60 * 1000);

        var deleted_count: usize = 0;

        // If task_name is specified, clean only that task's old artifacts
        // Otherwise, clean old artifacts for all tasks
        if (task_name) |tn| {
            deleted_count = try cleanTaskArtifacts(allocator, tn, cutoff);
        } else {
            // Clean all tasks
            var artifacts_dir = std.fs.cwd().openDir(".zr/artifacts", .{ .iterate = true }) catch {
                _ = std.debug.print("No artifacts directory found\n", .{});
                return;
            };
            defer artifacts_dir.close();

            var iter = artifacts_dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind == .directory) {
                    deleted_count += try cleanTaskArtifacts(allocator, entry.name, cutoff);
                }
            }
        }

        _ = std.debug.print("Cleaned {d} artifacts older than {s}\n", .{ deleted_count, time_str });
    } else if (task_name) |tn| {
        const artifacts_base = try std.fmt.allocPrint(allocator, ".zr/artifacts/{s}", .{tn});
        defer allocator.free(artifacts_base);

        _ = std.fs.cwd().deleteTree(artifacts_base) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };
        _ = std.debug.print("Cleaned all artifacts for task '{s}'\n", .{tn});
    }
}

/// Clean artifacts for a specific task older than the given cutoff timestamp
/// Returns the number of artifacts deleted
fn cleanTaskArtifacts(allocator: std.mem.Allocator, task_name: []const u8, cutoff: i64) !usize {
    const artifacts_base = try std.fmt.allocPrint(allocator, ".zr/artifacts/{s}", .{task_name});
    defer allocator.free(artifacts_base);

    var dir = std.fs.cwd().openDir(artifacts_base, .{ .iterate = true }) catch {
        return 0; // No artifacts for this task
    };
    defer dir.close();

    var deleted: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const timestamp = std.fmt.parseInt(i64, entry.name, 10) catch continue;
            if (timestamp < cutoff) {
                const dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ artifacts_base, entry.name });
                defer allocator.free(dir_path);
                std.fs.cwd().deleteTree(dir_path) catch continue;
                deleted += 1;
            }
        }
    }

    return deleted;
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
