const std = @import("std");

pub const GitPlugin = struct {
    /// Get the current git branch name.
    /// Returns null if not in a git repo or git is unavailable.
    /// Caller frees the returned slice.
    pub fn currentBranch(allocator: std.mem.Allocator) !?[]const u8 {
        var child = std.process.Child.init(
            &[_][]const u8{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
            allocator,
        );
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return null;

        // Read stdout before wait(): wait() calls cleanupStreams() which closes the pipe.
        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);

        if (child.stdout) |pipe| {
            var read_buf: [256]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(allocator, read_buf[0..bytes_read]);
            }
        }

        const result = try child.wait();

        switch (result) {
            .Exited => |code| if (code != 0) return null,
            else => return null,
        }

        const trimmed = std.mem.trim(u8, output.items, " \t\r\n");
        if (trimmed.len == 0) return null;
        return try allocator.dupe(u8, trimmed);
    }

    /// Get a list of files changed since the given git ref (default: HEAD).
    /// Caller frees the returned slice and each string.
    pub fn changedFiles(
        allocator: std.mem.Allocator,
        since_ref: []const u8,
    ) ![][]const u8 {
        const argv = [_][]const u8{ "git", "diff", "--name-only", since_ref };
        var child = std.process.Child.init(&argv, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return &.{};

        // Read stdout before wait(): wait() calls cleanupStreams() which closes the pipe.
        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);

        if (child.stdout) |pipe| {
            var read_buf: [16384]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(allocator, read_buf[0..bytes_read]);
            }
        }

        const result = try child.wait();

        switch (result) {
            .Exited => |code| if (code != 0) return &.{},
            else => return &.{},
        }

        var files: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (files.items) |f| allocator.free(f);
            files.deinit(allocator);
        }

        var lines = std.mem.splitScalar(u8, output.items, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            try files.append(allocator, try allocator.dupe(u8, trimmed));
        }

        return files.toOwnedSlice(allocator);
    }

    /// Get the last commit message on the current branch.
    /// Returns null if not in a git repo or on an empty repo.
    /// Caller frees the returned slice.
    pub fn lastCommitMessage(allocator: std.mem.Allocator) !?[]const u8 {
        const argv = [_][]const u8{ "git", "log", "-1", "--pretty=%s" };
        var child = std.process.Child.init(&argv, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return null;

        // Read stdout before wait(): wait() calls cleanupStreams() which closes the pipe.
        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);

        if (child.stdout) |pipe| {
            var read_buf: [1024]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(allocator, read_buf[0..bytes_read]);
            }
        }

        const result = try child.wait();

        switch (result) {
            .Exited => |code| if (code != 0) return null,
            else => return null,
        }

        const trimmed = std.mem.trim(u8, output.items, " \t\r\n");
        if (trimmed.len == 0) return null;
        return try allocator.dupe(u8, trimmed);
    }

    /// Check if a specific file has changes (staged or unstaged).
    pub fn fileHasChanges(allocator: std.mem.Allocator, path: []const u8) !bool {
        const argv = [_][]const u8{ "git", "status", "--short", path };
        var child = std.process.Child.init(&argv, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return false;

        // Read stdout before wait(): wait() calls cleanupStreams() which closes the pipe.
        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);

        if (child.stdout) |pipe| {
            var read_buf: [256]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(allocator, read_buf[0..bytes_read]);
            }
        }

        const result = try child.wait();

        switch (result) {
            .Exited => |code| if (code != 0) return false,
            else => return false,
        }

        return std.mem.trim(u8, output.items, " \t\r\n").len > 0;
    }
};

test "GitPlugin.currentBranch: returns branch name in git repo" {
    const allocator = std.testing.allocator;
    const branch = try GitPlugin.currentBranch(allocator);
    // This project is a git repo, so a branch name must come back.
    try std.testing.expect(branch != null);
    const name = branch.?;
    defer allocator.free(name);
    try std.testing.expect(name.len > 0);
}

test "GitPlugin.lastCommitMessage: returns non-null in git repo" {
    const allocator = std.testing.allocator;
    const msg = try GitPlugin.lastCommitMessage(allocator);
    // The repo has commits, so a message must be returned.
    try std.testing.expect(msg != null);
    const m = msg.?;
    defer allocator.free(m);
    try std.testing.expect(m.len > 0);
}

test "GitPlugin.changedFiles: returns slice (possibly empty)" {
    const allocator = std.testing.allocator;
    const files = try GitPlugin.changedFiles(allocator, "HEAD");
    defer {
        for (files) |f| allocator.free(f);
        allocator.free(files);
    }
    // Result is valid whether empty or non-empty — just must not error.
    _ = files.len;
}

test "GitPlugin.fileHasChanges: does not error on committed file" {
    const allocator = std.testing.allocator;
    // build.zig is tracked. The boolean result varies with working-tree state,
    // but the call must succeed without error.
    const changed = try GitPlugin.fileHasChanges(allocator, "build.zig");
    _ = changed;
}

test "GitPlugin.changedFiles: invalid ref returns empty slice" {
    const allocator = std.testing.allocator;
    const files = try GitPlugin.changedFiles(allocator, "nonexistent_ref_12345");
    defer {
        for (files) |f| allocator.free(f);
        allocator.free(files);
    }
    try std.testing.expectEqual(@as(usize, 0), files.len);
}
