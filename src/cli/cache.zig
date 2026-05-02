const std = @import("std");
const cache_store = @import("../exec/cache_store.zig");

/// Handle `zr cache` subcommands
pub fn handle(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        try printUsage();
        return error.MissingSubcommand;
    }

    const subcommand = args[1];

    if (std.mem.eql(u8, subcommand, "clean")) {
        try handleClean(allocator);
    } else if (std.mem.eql(u8, subcommand, "status")) {
        try handleStatus(allocator);
    } else if (std.mem.eql(u8, subcommand, "clear")) {
        try handleClear(allocator, args[2..]);
    } else if (std.mem.eql(u8, subcommand, "help")) {
        try printUsage();
    } else {
        std.debug.print("error: unknown subcommand '{s}'\n", .{subcommand});
        return error.UnknownSubcommand;
    }
}

/// Handle `zr cache clean` - clear all cache entries
fn handleClean(allocator: std.mem.Allocator) !void {
    var store = cache_store.CacheStore.init(allocator);
    defer store.deinit();

    try store.clearAll();
    std.debug.print("Cache cleaned successfully\n", .{});
}

/// Handle `zr cache status` - show cache statistics
fn handleStatus(allocator: std.mem.Allocator) !void {
    const cache_dir_path = ".zr/cache";

    // Check if cache directory exists
    var cache_dir = std.fs.cwd().openDir(cache_dir_path, .{ .iterate = true }) catch {
        std.debug.print("Cache is empty (no .zr/cache directory)\n", .{});
        return;
    };
    defer cache_dir.close();

    // Collect cache statistics
    var total_entries: usize = 0;
    var total_size: u64 = 0;
    var task_counts = std.StringHashMap(usize).init(allocator);
    defer task_counts.deinit();

    var iter = cache_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        total_entries += 1;

        // Read manifest to get task name and compute size
        const manifest_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}/manifest.json",
            .{ cache_dir_path, entry.name },
        );
        defer allocator.free(manifest_path);

        const manifest_data = std.fs.cwd().readFileAlloc(
            allocator,
            manifest_path,
            1024 * 1024,
        ) catch continue;
        defer allocator.free(manifest_data);

        // Parse task name from manifest JSON (simple extraction)
        if (std.mem.indexOf(u8, manifest_data, "\"task_name\":")) |idx| {
            const task_start = idx + "\"task_name\":".len;
            if (std.mem.indexOfPos(u8, manifest_data, task_start, "\"")) |quote1| {
                const name_start = quote1 + 1;
                if (std.mem.indexOfPos(u8, manifest_data, name_start, "\"")) |quote2| {
                    const task_name = manifest_data[name_start..quote2];
                    const count = task_counts.get(task_name) orelse 0;
                    try task_counts.put(try allocator.dupe(u8, task_name), count + 1);
                }
            }
        }

        // Compute directory size
        const entry_dir_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ cache_dir_path, entry.name },
        );
        defer allocator.free(entry_dir_path);

        var entry_dir = std.fs.cwd().openDir(entry_dir_path, .{ .iterate = true }) catch continue;
        defer entry_dir.close();

        var entry_iter = entry_dir.iterate();
        while (try entry_iter.next()) |file| {
            if (file.kind == .file) {
                const file_path = try std.fmt.allocPrint(
                    allocator,
                    "{s}/{s}",
                    .{ entry_dir_path, file.name },
                );
                defer allocator.free(file_path);

                const stat = std.fs.cwd().statFile(file_path) catch continue;
                total_size += stat.size;
            }
        }
    }

    // Print statistics
    std.debug.print("Cache Statistics:\n", .{});
    std.debug.print("  Total entries: {d}\n", .{total_entries});
    std.debug.print("  Total size: {d} bytes ({d:.2} MB)\n", .{
        total_size,
        @as(f64, @floatFromInt(total_size)) / (1024.0 * 1024.0),
    });

    if (task_counts.count() > 0) {
        std.debug.print("  Entries by task:\n", .{});
        var task_iter = task_counts.iterator();
        while (task_iter.next()) |kv| {
            std.debug.print("    {s}: {d}\n", .{ kv.key_ptr.*, kv.value_ptr.* });
            allocator.free(kv.key_ptr.*);
        }
    }
}

/// Handle `zr cache clear <task>` - clear cache for specific task
fn handleClear(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("error: clear requires a task name or cache key\n", .{});
        std.debug.print("usage: zr cache clear <task-name-or-key>\n", .{});
        return error.MissingTaskName;
    }

    const target = args[0];
    var store = cache_store.CacheStore.init(allocator);
    defer store.deinit();

    // Try to invalidate by cache key first
    store.invalidate(target) catch {
        // If that fails, try to find cache entries for task name
        const cache_dir_path = ".zr/cache";
        var cache_dir = std.fs.cwd().openDir(cache_dir_path, .{ .iterate = true }) catch {
            std.debug.print("Cache is empty (no .zr/cache directory)\n", .{});
            return;
        };
        defer cache_dir.close();

        var cleared_count: usize = 0;
        var iter = cache_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .directory) continue;

            // Read manifest to check task name
            const manifest_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}/manifest.json",
                .{ cache_dir_path, entry.name },
            );
            defer allocator.free(manifest_path);

            const manifest_data = std.fs.cwd().readFileAlloc(
                allocator,
                manifest_path,
                1024 * 1024,
            ) catch continue;
            defer allocator.free(manifest_data);

            // Check if manifest contains target task name
            const search_pattern = try std.fmt.allocPrint(
                allocator,
                "\"task_name\":\"{s}\"",
                .{target},
            );
            defer allocator.free(search_pattern);

            if (std.mem.indexOf(u8, manifest_data, search_pattern)) |_| {
                // This cache entry is for the target task
                store.invalidate(entry.name) catch continue;
                cleared_count += 1;
            }
        }

        if (cleared_count == 0) {
            std.debug.print("No cache entries found for task '{s}'\n", .{target});
        } else {
            std.debug.print("Cleared {d} cache entries for task '{s}'\n", .{ cleared_count, target });
        }
        return;
    };

    std.debug.print("Cache entry '{s}' cleared\n", .{target});
}

fn printUsage() !void {
    const usage =
        \\Usage: zr cache <command> [options]
        \\
        \\Commands:
        \\  clean              Clear all cache entries
        \\  status             Show cache statistics (entries, size, per-task breakdown)
        \\  clear <task>       Clear cache entries for specific task or cache key
        \\  help               Show this help message
        \\
        \\Examples:
        \\  zr cache status                 # Show cache statistics
        \\  zr cache clean                  # Clear all cache
        \\  zr cache clear build            # Clear cache for 'build' task
        \\  zr cache clear abc123...        # Clear specific cache entry by key
        \\
    ;
    std.debug.print("{s}", .{usage});
}
