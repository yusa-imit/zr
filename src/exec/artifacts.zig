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

            // Track collected file
            try collected_files.append(allocator, dest_name);
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

test "ArtifactManifest: deinit cleans up fields" {
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

    // Should not leak
    manifest.deinit(allocator);
}

test "collectArtifacts: skip when no artifacts configured" {
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
        .artifacts = null, // No artifacts
        .artifact_retention = null,
        .compress_artifacts = false,
    };

    // Should complete without error
    try collectArtifacts(allocator, task, 0, 100);
}
