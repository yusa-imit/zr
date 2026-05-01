const std = @import("std");
const glob_mod = @import("../util/glob.zig");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");

/// Manifest metadata stored with each artifact collection
pub const ArtifactManifest = struct {
    timestamp: i64,
    task_name: []const u8,
    exit_code: u8,
    duration_ms: u64,
    files: [][]const u8,
    git_commit: ?[]const u8 = null,

    pub fn deinit(self: *ArtifactManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.task_name);
        for (self.files) |file| {
            allocator.free(file);
        }
        allocator.free(self.files);
        if (self.git_commit) |commit| {
            allocator.free(commit);
        }
    }
};

/// Enforce retention policy for task artifacts
/// Removes old artifacts based on the retention policy
pub fn enforceRetentionPolicy(
    allocator: std.mem.Allocator,
    task: loader.Task,
) !void {
    if (task.artifact_retention == null) {
        return;
    }

    const retention = task.artifact_retention.?;
    const artifacts_base = try std.fmt.allocPrint(allocator, ".zr/artifacts/{s}", .{task.name});
    defer allocator.free(artifacts_base);

    var dir = std.fs.cwd().openDir(artifacts_base, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return; // No artifacts directory
        return err;
    };
    defer dir.close();

    // Collect all artifact directories with their timestamps
    var artifact_dirs = std.ArrayList(struct {
        name: []const u8,
        timestamp: i64,
    }){};
    defer {
        for (artifact_dirs.items) |item| {
            allocator.free(item.name);
        }
        artifact_dirs.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const timestamp = std.fmt.parseInt(i64, entry.name, 10) catch continue;
            const name = try allocator.dupe(u8, entry.name);
            try artifact_dirs.append(allocator, .{ .name = name, .timestamp = timestamp });
        }
    }

    // Sort by timestamp (oldest first)
    std.mem.sort(@TypeOf(artifact_dirs.items[0]), artifact_dirs.items, {}, struct {
        fn lessThan(_: void, a: @TypeOf(artifact_dirs.items[0]), b: @TypeOf(artifact_dirs.items[0])) bool {
            return a.timestamp < b.timestamp;
        }
    }.lessThan);

    const now = std.time.milliTimestamp();

    // Apply retention policy
    switch (retention) {
        .time_based => |time_str| {
            // Parse time string (e.g., "7d", "30d", "manual")
            if (std.mem.eql(u8, time_str, "manual")) {
                return; // Don't auto-delete
            }

            // Parse days from string like "7d"
            const days = blk: {
                if (time_str.len < 2 or time_str[time_str.len - 1] != 'd') {
                    return; // Invalid format, skip
                }
                const days_str = time_str[0 .. time_str.len - 1];
                break :blk std.fmt.parseInt(i64, days_str, 10) catch return;
            };

            // Delete artifacts older than N days
            const cutoff = now - (days * 24 * 60 * 60 * 1000);
            for (artifact_dirs.items) |item| {
                if (item.timestamp < cutoff) {
                    const dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ artifacts_base, item.name });
                    defer allocator.free(dir_path);
                    std.fs.cwd().deleteTree(dir_path) catch {}; // Ignore errors
                }
            }
        },
        .count_based => |policy| {
            // Keep only the N most recent builds
            if (artifact_dirs.items.len > policy.count) {
                const to_delete = artifact_dirs.items.len - policy.count;
                for (artifact_dirs.items[0..to_delete]) |item| {
                    const dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ artifacts_base, item.name });
                    defer allocator.free(dir_path);
                    std.fs.cwd().deleteTree(dir_path) catch {}; // Ignore errors
                }
            }
        },
    }
}

/// Collect artifacts for a task after successful execution
/// Creates .zr/artifacts/<task>/<timestamp>/ directory structure
/// Copies files matching artifact patterns and generates manifest.json
pub fn collectArtifacts(
    allocator: std.mem.Allocator,
    task: loader.Task,
    exit_code: u8,
    duration_ms: u64,
) !void {
    // Skip if task has no artifacts configured
    if (task.artifacts == null or task.artifacts.?.len == 0) {
        return;
    }

    const artifacts = task.artifacts.?;

    // Create timestamp for this collection
    const timestamp = std.time.milliTimestamp();

    // Create artifacts directory: .zr/artifacts/<task>/<timestamp>/
    const artifact_dir = try std.fmt.allocPrint(
        allocator,
        ".zr/artifacts/{s}/{d}",
        .{ task.name, timestamp }
    );
    defer allocator.free(artifact_dir);

    // Ensure parent directories exist
    try std.fs.cwd().makePath(artifact_dir);

    var collected_files = std.ArrayList([]const u8){};
    defer {
        for (collected_files.items) |file| {
            allocator.free(file);
        }
        collected_files.deinit(allocator);
    }

    // Get working directory for the task
    const cwd = if (task.cwd) |c| c else ".";

    // Open the working directory
    var base_dir = try std.fs.cwd().openDir(cwd, .{ .iterate = true });
    defer base_dir.close();

    // Process each artifact pattern
    for (artifacts) |pattern| {
        // Use glob matcher to find files
        const matches = try glob_mod.find(allocator, base_dir, pattern);
        defer {
            for (matches) |match| {
                allocator.free(match);
            }
            allocator.free(matches);
        }

        // Copy each matched file to artifact directory
        for (matches) |source_path| {
            // Compute relative path for storage
            const dest_name = try allocator.dupe(u8, source_path);
            errdefer allocator.free(dest_name);

            const dest_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ artifact_dir, dest_name }
            );
            defer allocator.free(dest_path);

            // Ensure parent directory exists for nested files
            if (std.fs.path.dirname(dest_path)) |parent| {
                try std.fs.cwd().makePath(parent);
            }

            // Copy file
            const source_full = if (std.mem.eql(u8, cwd, "."))
                source_path
            else
                try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cwd, source_path });
            defer if (!std.mem.eql(u8, cwd, ".")) allocator.free(source_full);

            try std.fs.cwd().copyFile(source_full, std.fs.cwd(), dest_path, .{});

            // Compress if enabled
            const final_name = if (task.compress_artifacts) blk: {
                const compressed = try compressFile(allocator, dest_path);
                defer allocator.free(compressed);

                // Extract just the filename from the compressed path
                const compressed_filename = try allocator.dupe(u8, std.fs.path.basename(compressed));

                allocator.free(dest_name);
                break :blk compressed_filename;
            } else dest_name;

            // Track collected file (compressed or not)
            try collected_files.append(allocator, final_name);
        }
    }

    // Get git commit if in a repo
    const git_commit = getGitCommit(allocator) catch null;
    defer if (git_commit) |commit| allocator.free(commit);

    // Generate manifest
    var manifest = ArtifactManifest{
        .timestamp = timestamp,
        .task_name = try allocator.dupe(u8, task.name),
        .exit_code = exit_code,
        .duration_ms = duration_ms,
        .files = try allocator.alloc([]const u8, collected_files.items.len),
        .git_commit = if (git_commit) |c| try allocator.dupe(u8, c) else null,
    };

    for (collected_files.items, 0..) |file, i| {
        manifest.files[i] = try allocator.dupe(u8, file);
    }

    // Write manifest.json
    const manifest_path = try std.fmt.allocPrint(
        allocator,
        "{s}/manifest.json",
        .{artifact_dir}
    );
    defer allocator.free(manifest_path);

    try writeManifest(allocator, &manifest, manifest_path);

    manifest.deinit(allocator);
}

/// Compress a file using gzip CLI
/// Returns the path to the compressed file (.gz extension)
fn compressFile(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    // Run: gzip -f -9 <source_path>
    // This creates <source_path>.gz and deletes the original
    const argv = [_][]const u8{ "gzip", "-f", "-9", source_path };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) {
        return error.CompressionFailed;
    }

    // Return the compressed path
    return try std.fmt.allocPrint(allocator, "{s}.gz", .{source_path});
}

/// Get current git commit hash if in a repository
fn getGitCommit(allocator: std.mem.Allocator) ![]const u8 {
    var argv = [_][]const u8{ "git", "rev-parse", "HEAD" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024);
    errdefer allocator.free(stdout);

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) {
        allocator.free(stdout);
        return error.NotInGitRepo;
    }

    // Trim newline
    return std.mem.trim(u8, stdout, &std.ascii.whitespace);
}

/// Write manifest to JSON file
fn writeManifest(
    allocator: std.mem.Allocator,
    manifest: *const ArtifactManifest,
    path: []const u8,
) !void {
    // Build JSON content in memory
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const writer = buf.writer(allocator);

    // Write JSON manually (simple format)
    try writer.writeAll("{\n");
    try writer.print("  \"timestamp\": {d},\n", .{manifest.timestamp});
    try writer.print("  \"task_name\": \"{s}\",\n", .{manifest.task_name});
    try writer.print("  \"exit_code\": {d},\n", .{manifest.exit_code});
    try writer.print("  \"duration_ms\": {d},\n", .{manifest.duration_ms});

    if (manifest.git_commit) |commit| {
        try writer.print("  \"git_commit\": \"{s}\",\n", .{commit});
    }

    try writer.writeAll("  \"files\": [\n");
    for (manifest.files, 0..) |file_name, i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("    \"{s}\"", .{file_name});
    }
    try writer.writeAll("\n  ]\n");
    try writer.writeAll("}\n");

    // Write to file
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = buf.items,
    });
}

test "ArtifactManifest: fields initialized correctly and cleaned up by deinit" {
    const allocator = std.testing.allocator;

    var manifest = ArtifactManifest{
        .timestamp = 1234567890,
        .task_name = try allocator.dupe(u8, "build"),
        .exit_code = 0,
        .duration_ms = 1000,
        .files = try allocator.alloc([]const u8, 2),
        .git_commit = try allocator.dupe(u8, "abc123"),
    };

    manifest.files[0] = try allocator.dupe(u8, "dist/app.js");
    manifest.files[1] = try allocator.dupe(u8, "dist/app.css");

    // Verify fields are set correctly before cleanup
    try std.testing.expectEqual(@as(i64, 1234567890), manifest.timestamp);
    try std.testing.expectEqualStrings("build", manifest.task_name);
    try std.testing.expectEqual(@as(u8, 0), manifest.exit_code);
    try std.testing.expectEqual(@as(u64, 1000), manifest.duration_ms);
    try std.testing.expectEqual(@as(usize, 2), manifest.files.len);
    try std.testing.expectEqualStrings("dist/app.js", manifest.files[0]);
    try std.testing.expectEqualStrings("dist/app.css", manifest.files[1]);
    try std.testing.expect(manifest.git_commit != null);
    try std.testing.expectEqualStrings("abc123", manifest.git_commit.?);

    // deinit should free all allocated memory (leak check via testing allocator)
    manifest.deinit(allocator);
}

test "collectArtifacts: early return when no artifacts configured" {
    const allocator = std.testing.allocator;

    const task = loader.Task{
        .name = "test",
        .cmd = "echo hello",
        .cwd = null,
        .env = &[_][2][]const u8{},
        .deps = &[_][]const u8{},
        .deps_serial = &[_][]const u8{},
        .deps_if = &[_]types.ConditionalDep{},
        .deps_optional = &[_][]const u8{},
        .toolchain = &[_][]const u8{},
        .timeout_ms = null,
        .allow_failure = false,
        .retry_max = 0,
        .retry_delay_ms = 0,
        .retry_backoff = false,
        .hooks = &[_]types.TaskHook{},
        .artifacts = null, // No artifacts configured
        .artifact_retention = null,
        .compress_artifacts = false,
    };

    // Should complete without error and without creating any directories
    try collectArtifacts(allocator, task, 0, 100);

    // Verify .zr/artifacts directory was NOT created (early return in collectArtifacts)
    var cwd = std.fs.cwd();
    var artifact_dir = cwd.openDir(".zr/artifacts", .{}) catch |err| {
        // Expected: directory should not exist since no artifacts were collected
        try std.testing.expectEqual(error.FileNotFound, err);
        return;
    };
    defer artifact_dir.close();

    // If we reach here, the directory exists - this is unexpected
    return error.TestUnexpectedBehavior;
}
