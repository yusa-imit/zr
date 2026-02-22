const std = @import("std");
const color = @import("../output/color.zig");
const platform = @import("../util/platform.zig");
const cache_store = @import("../cache/store.zig");
const history = @import("../history/store.zig");
const toolchain_installer = @import("../toolchain/installer.zig");
const multirepo_synthetic = @import("../multirepo/synthetic.zig");

pub const CleanOptions = struct {
    all: bool = false,
    cache: bool = false,
    history: bool = false,
    toolchains: bool = false,
    plugins: bool = false,
    synthetic: bool = false,
    dry_run: bool = false,
};

pub fn cmdClean(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var opts = CleanOptions{};

    // Parse args
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--all") or std.mem.eql(u8, arg, "-a")) {
            opts.all = true;
        } else if (std.mem.eql(u8, arg, "--cache")) {
            opts.cache = true;
        } else if (std.mem.eql(u8, arg, "--history")) {
            opts.history = true;
        } else if (std.mem.eql(u8, arg, "--toolchains")) {
            opts.toolchains = true;
        } else if (std.mem.eql(u8, arg, "--plugins")) {
            opts.plugins = true;
        } else if (std.mem.eql(u8, arg, "--synthetic")) {
            opts.synthetic = true;
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            opts.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "Unknown option: {s}\n\n", .{arg});
            try printHelp(w, use_color);
            return 1;
        }
    }

    // If --all is specified, enable all clean targets
    if (opts.all) {
        opts.cache = true;
        opts.history = true;
        opts.toolchains = true;
        opts.plugins = true;
        opts.synthetic = true;
    }

    // If no specific targets, show help
    if (!opts.cache and !opts.history and !opts.toolchains and !opts.plugins and !opts.synthetic) {
        try printHelp(w, use_color);
        return 0;
    }

    if (opts.dry_run) {
        try color.printDim(w, use_color, "[DRY RUN MODE - No files will be deleted]\n\n", .{});
    }

    var total_removed: usize = 0;
    var total_size: usize = 0;

    // Clean cache
    if (opts.cache) {
        try color.printBold(w, use_color, "Cleaning cache...\n", .{});

        if (opts.dry_run) {
            var store = cache_store.CacheStore.init(allocator) catch |err| {
                try color.printError(ew, use_color, "  Failed to access cache: {}\n", .{err});
                return 1;
            };
            defer store.deinit();

            const stats = store.getStats() catch |err| {
                try color.printError(ew, use_color, "  Failed to read cache stats: {}\n", .{err});
                return 1;
            };

            try color.printDim(w, use_color, "  Would remove {d} cache entries ({d} bytes)\n", .{stats.total_entries, stats.total_size_bytes});
            total_removed += stats.total_entries;
            total_size += stats.total_size_bytes;
        } else {
            var store = cache_store.CacheStore.init(allocator) catch |err| {
                try color.printError(ew, use_color, "  Failed to open cache: {}\n", .{err});
                return 1;
            };
            defer store.deinit();

            const removed = store.clearAll() catch |err| {
                try color.printError(ew, use_color, "  Error clearing cache: {}\n", .{err});
                return 1;
            };

            try color.printSuccess(w, use_color, "  Removed {d} cache entries\n", .{removed});
            total_removed += removed;
        }
    }

    // Clean history
    if (opts.history) {
        try color.printBold(w, use_color, "Cleaning execution history...\n", .{});

        const home = platform.getenv("HOME") orelse platform.getenv("USERPROFILE") orelse {
            try color.printError(ew, use_color, "  Failed to get home directory\n", .{});
            return 1;
        };

        const history_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zr_history" });
        defer allocator.free(history_path);

        if (opts.dry_run) {
            std.fs.cwd().access(history_path, .{}) catch {
                try color.printDim(w, use_color, "  No history file found\n", .{});
                return 0;
            };

            const file = try std.fs.cwd().openFile(history_path, .{});
            defer file.close();
            const size = try file.getEndPos();

            try color.printDim(w, use_color, "  Would remove history file ({d} bytes)\n", .{size});
            total_size += size;
        } else {
            std.fs.cwd().deleteFile(history_path) catch |err| switch (err) {
                error.FileNotFound => {
                    try color.printDim(w, use_color, "  No history file found\n", .{});
                },
                else => {
                    try color.printError(ew, use_color, "  Failed to delete history: {}\n", .{err});
                    return 1;
                },
            };

            try color.printSuccess(w, use_color, "  Removed history file\n", .{});
        }
    }

    // Clean toolchains
    if (opts.toolchains) {
        try color.printBold(w, use_color, "Cleaning toolchains...\n", .{});

        const home = platform.getenv("HOME") orelse platform.getenv("USERPROFILE") orelse {
            try color.printError(ew, use_color, "  Failed to get home directory\n", .{});
            return 1;
        };

        const toolchains_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zr", "toolchains" });
        defer allocator.free(toolchains_path);

        if (opts.dry_run) {
            var dir = std.fs.cwd().openDir(toolchains_path, .{ .iterate = true }) catch {
                try color.printDim(w, use_color, "  No toolchains directory found\n", .{});
                return 0;
            };
            defer dir.close();

            var count: usize = 0;
            var size_total: usize = 0;
            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind == .directory) {
                    count += 1;
                    // Estimate size by walking the directory
                    var subdir = try dir.openDir(entry.name, .{ .iterate = true });
                    defer subdir.close();
                    size_total += try estimateDirSize(subdir);
                }
            }

            try color.printDim(w, use_color, "  Would remove {d} toolchain(s) (~{d} bytes)\n", .{count, size_total});
            total_size += size_total;
        } else {
            std.fs.cwd().deleteTree(toolchains_path) catch |err| {
                try color.printError(ew, use_color, "  Failed to delete toolchains: {}\n", .{err});
                return 1;
            };

            try color.printSuccess(w, use_color, "  Removed all toolchains\n", .{});
        }
    }

    // Clean plugins
    if (opts.plugins) {
        try color.printBold(w, use_color, "Cleaning plugins...\n", .{});

        const home = platform.getenv("HOME") orelse platform.getenv("USERPROFILE") orelse {
            try color.printError(ew, use_color, "  Failed to get home directory\n", .{});
            return 1;
        };

        const plugins_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zr", "plugins" });
        defer allocator.free(plugins_path);

        if (opts.dry_run) {
            var dir = std.fs.cwd().openDir(plugins_path, .{ .iterate = true }) catch {
                try color.printDim(w, use_color, "  No plugins directory found\n", .{});
                return 0;
            };
            defer dir.close();

            var count: usize = 0;
            var size_total: usize = 0;
            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind == .directory) {
                    count += 1;
                    var subdir = try dir.openDir(entry.name, .{ .iterate = true });
                    defer subdir.close();
                    size_total += try estimateDirSize(subdir);
                }
            }

            try color.printDim(w, use_color, "  Would remove {d} plugin(s) (~{d} bytes)\n", .{count, size_total});
            total_size += size_total;
        } else {
            std.fs.cwd().deleteTree(plugins_path) catch |err| {
                try color.printError(ew, use_color, "  Failed to delete plugins: {}\n", .{err});
                return 1;
            };

            try color.printSuccess(w, use_color, "  Removed all plugins\n", .{});
        }
    }

    // Clean synthetic workspace
    if (opts.synthetic) {
        try color.printBold(w, use_color, "Cleaning synthetic workspace...\n", .{});

        if (opts.dry_run) {
            if (try multirepo_synthetic.isSyntheticWorkspaceActive(allocator)) {
                try color.printDim(w, use_color, "  Would clear synthetic workspace metadata\n", .{});
            } else {
                try color.printDim(w, use_color, "  No synthetic workspace active\n", .{});
            }
        } else {
            if (try multirepo_synthetic.isSyntheticWorkspaceActive(allocator)) {
                multirepo_synthetic.clearSyntheticWorkspace(allocator) catch |err| {
                    try color.printError(ew, use_color, "  Failed to clear synthetic workspace: {}\n", .{err});
                    return 1;
                };
                try color.printSuccess(w, use_color, "  Cleared synthetic workspace metadata\n", .{});
            } else {
                try color.printDim(w, use_color, "  No synthetic workspace active\n", .{});
            }
        }
    }

    // Print summary
    if (opts.dry_run and (total_removed > 0 or total_size > 0)) {
        try color.printBold(w, use_color, "\nSummary:\n", .{});
        if (total_removed > 0) {
            try color.printDim(w, use_color, "  Would remove {d} item(s)\n", .{total_removed});
        }
        if (total_size > 0) {
            try color.printDim(w, use_color, "  Would free ~{d} bytes\n", .{total_size});
        }
        try color.printDim(w, use_color, "\nRun without --dry-run to actually delete files.\n", .{});
    }

    return 0;
}

fn estimateDirSize(dir: std.fs.Dir) !usize {
    var total: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const file = try dir.openFile(entry.name, .{});
            defer file.close();
            total += try file.getEndPos();
        } else if (entry.kind == .directory) {
            var subdir = try dir.openDir(entry.name, .{ .iterate = true });
            defer subdir.close();
            total += try estimateDirSize(subdir);
        }
    }
    return total;
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "Usage: ", .{});
    try w.writeAll("zr clean [options]\n\n");

    try color.printBold(w, use_color, "Options:\n", .{});
    try w.writeAll("  --all, -a          Clean all zr data (cache, history, toolchains, plugins, synthetic)\n");
    try w.writeAll("  --cache            Clean task cache (~/.zr/cache/)\n");
    try w.writeAll("  --history          Clean execution history (~/.zr_history)\n");
    try w.writeAll("  --toolchains       Clean all installed toolchains (~/.zr/toolchains/)\n");
    try w.writeAll("  --plugins          Clean all installed plugins (~/.zr/plugins/)\n");
    try w.writeAll("  --synthetic        Clear synthetic workspace metadata\n");
    try w.writeAll("  --dry-run, -n      Show what would be deleted without actually deleting\n");
    try w.writeAll("  --help, -h         Show this help message\n\n");

    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.writeAll("  zr clean --cache           # Clean only task cache\n");
    try w.writeAll("  zr clean --all --dry-run   # Preview what would be deleted\n");
    try w.writeAll("  zr clean --cache --history # Clean cache and history\n");
}

test "clean help" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    const args = [_][]const u8{"--help"};
    const code = try cmdClean(allocator, &args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "clean dry run" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    const args = [_][]const u8{ "--cache", "--dry-run" };
    const code = try cmdClean(allocator, &args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "clean options parsing" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;

    // Test --all flag
    {
        const stdout = std.fs.File.stdout();
        var out_w = stdout.writer(&out_buf);
        const stderr_f = std.fs.File.stderr();
        var err_w = stderr_f.writer(&err_buf);
        const args = [_][]const u8{ "--all", "--dry-run" };
        const code = try cmdClean(allocator, &args, &out_w.interface, &err_w.interface, false);
        try std.testing.expectEqual(@as(u8, 0), code);
    }

    // Test individual flags
    {
        const stdout = std.fs.File.stdout();
        var out_w = stdout.writer(&out_buf);
        const stderr_f = std.fs.File.stderr();
        var err_w = stderr_f.writer(&err_buf);
        const args = [_][]const u8{ "--cache", "--history", "--dry-run" };
        const code = try cmdClean(allocator, &args, &out_w.interface, &err_w.interface, false);
        try std.testing.expectEqual(@as(u8, 0), code);
    }
}
