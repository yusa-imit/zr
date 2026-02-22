const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const Release = types.Release;

/// Install a new version of zr
pub fn installRelease(
    allocator: std.mem.Allocator,
    release: Release,
    verbose: bool,
) !void {
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    if (verbose) {
        std.debug.print("Current executable: {s}\n", .{exe_path});
        std.debug.print("Downloading version {s}...\n", .{release.version});
    }

    // Download the new binary
    const tmp_path = try downloadBinary(allocator, release.download_url, verbose);
    defer {
        std.fs.cwd().deleteFile(tmp_path) catch {};
        allocator.free(tmp_path);
    }

    // Backup current binary
    const backup_path = try std.fmt.allocPrint(allocator, "{s}.backup", .{exe_path});
    defer allocator.free(backup_path);

    if (verbose) {
        std.debug.print("Creating backup: {s}\n", .{backup_path});
    }

    try std.fs.cwd().copyFile(exe_path, std.fs.cwd(), backup_path, .{});

    // Replace current binary with new one
    if (verbose) {
        std.debug.print("Installing new version...\n", .{});
    }

    try replaceBinary(exe_path, tmp_path);

    if (verbose) {
        std.debug.print("✓ Successfully upgraded to version {s}\n", .{release.version});
        std.debug.print("  Backup saved to: {s}\n", .{backup_path});
    }
}

/// Download binary from URL to temporary file
fn downloadBinary(
    allocator: std.mem.Allocator,
    url: []const u8,
    verbose: bool,
) ![]const u8 {
    // Create temporary file
    const tmp_dir = std.fs.cwd();
    const tmp_filename = "zr-download.tmp";

    if (verbose) {
        std.debug.print("Downloading from: {s}\n", .{url});
    }

    // Use curl to download (similar to toolchain downloader)
    const curl_args = [_][]const u8{
        "curl",
        "-fsSL",
        "-o",
        tmp_filename,
        url,
    };

    var child = std.process.Child.init(&curl_args, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(stderr);

    const result = try child.wait();
    if (result != .Exited or result.Exited != 0) {
        std.debug.print("curl stderr: {s}\n", .{stderr});
        return error.DownloadFailed;
    }

    // Verify file was downloaded
    const stat = try tmp_dir.statFile(tmp_filename);
    if (stat.size == 0) {
        return error.DownloadFailed;
    }

    return try allocator.dupe(u8, tmp_filename);
}

/// Replace the current binary with the new one
fn replaceBinary(current_path: []const u8, new_path: []const u8) !void {
    if (builtin.os.tag == .windows) {
        // On Windows, we can't replace a running executable directly
        // Need to rename current, copy new, then delete old on next boot
        const temp_path = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "{s}.old",
            .{current_path},
        );
        defer std.heap.page_allocator.free(temp_path);

        // Move current to .old
        try std.fs.cwd().rename(current_path, temp_path);

        // Copy new to current location
        try std.fs.cwd().copyFile(new_path, std.fs.cwd(), current_path, .{});

        // Schedule deletion of .old file (best effort)
        std.fs.cwd().deleteFile(temp_path) catch {};
    } else {
        // On Unix, we can replace directly
        try std.fs.cwd().copyFile(new_path, std.fs.cwd(), current_path, .{});

        // Make executable
        const file = try std.fs.cwd().openFile(current_path, .{});
        defer file.close();

        if (builtin.os.tag != .windows) {
            try file.chmod(0o755);
        }
    }
}

test "replaceBinary creates backup" {
    // This would require mocking file system operations
    // Skip for now as it's integration-level testing
}
