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
        const result = try child.wait();

        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        if (child.stdout) |pipe| {
            var read_buf: [256]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(read_buf[0..bytes_read]);
            }
        }

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
        const result = try child.wait();

        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        if (child.stdout) |pipe| {
            var read_buf: [16384]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(read_buf[0..bytes_read]);
            }
        }

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
        const result = try child.wait();

        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        if (child.stdout) |pipe| {
            var read_buf: [1024]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(read_buf[0..bytes_read]);
            }
        }

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
        const result = try child.wait();

        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        if (child.stdout) |pipe| {
            var read_buf: [256]u8 = undefined;
            while (true) {
                const bytes_read = pipe.read(&read_buf) catch break;
                if (bytes_read == 0) break;
                try output.appendSlice(read_buf[0..bytes_read]);
            }
        }

        switch (result) {
            .Exited => |code| if (code != 0) return false,
            else => return false,
        }

        return std.mem.trim(u8, output.items, " \t\r\n").len > 0;
    }
};
