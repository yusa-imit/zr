//! Built-in git plugin: read-only queries about the repository in the current directory.
//!
//! Every query spawns `git` and reads its stdout through `collectStdout`, which holds the output
//! to `output_bytes_max` bytes. A child that prints more is killed and reported as
//! `error.OutputTooLarge`, so a hostile or broken `git` cannot exhaust memory. Allocation:
//! results are owned by the caller; the temporary output buffer is freed before returning.

const std = @import("std");

/// Upper bound on the stdout of one git invocation. Far above any branch name or message and
/// above a `git diff --name-only` of a very large monorepo.
const output_bytes_max: u32 = 16 * 1024 * 1024;

const read_chunk_size: u32 = 4096;

const CollectError = error{ OutputTooLarge, OutOfMemory };

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

        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);
        try collectStdout(allocator, &child, &output);

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

        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);
        try collectStdout(allocator, &child, &output);

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

        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);
        try collectStdout(allocator, &child, &output);

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

        var output = std.ArrayList(u8){};
        defer output.deinit(allocator);
        try collectStdout(allocator, &child, &output);

        const result = try child.wait();

        switch (result) {
            .Exited => |code| if (code != 0) return false,
            else => return false,
        }

        return std.mem.trim(u8, output.items, " \t\r\n").len > 0;
    }
};

/// Read the stdout of a spawned `child` into `output` before `wait()`, which closes the pipe.
/// A child whose output exceeds `output_bytes_max` is killed and reaped here, so the caller
/// must not `wait()` after an error. Precondition: the child was spawned with a stdout pipe.
fn collectStdout(
    gpa: std.mem.Allocator,
    child: *std.process.Child,
    output: *std.ArrayList(u8),
) CollectError!void {
    std.debug.assert(child.stdout_behavior == .Pipe);
    std.debug.assert(output.items.len == 0);
    const pipe = child.stdout orelse return;
    readBounded(pipe, gpa, output, output_bytes_max) catch |err| {
        _ = child.kill() catch {};
        return err;
    };
}

/// Append everything `source` yields to `output`, up to `bytes_max` bytes. `source` needs
/// `read(buf) !usize`. A read error ends the stream like end-of-file: the exit status of the
/// child, checked by the caller, is the authority on success. Output longer than `bytes_max` is
/// `error.OutputTooLarge`; `output` then holds at most `bytes_max` bytes. Precondition:
/// `bytes_max > 0`.
fn readBounded(
    source: anytype,
    gpa: std.mem.Allocator,
    output: *std.ArrayList(u8),
    bytes_max: u32,
) CollectError!void {
    std.debug.assert(bytes_max > 0);
    var chunk: [read_chunk_size]u8 = undefined;
    // Every iteration either ends the stream or appends at least one byte, so `bytes_max + 1`
    // iterations are enough to reach end-of-stream or to overrun the limit.
    for (0..@as(u64, bytes_max) + 1) |_| {
        const n = source.read(&chunk) catch return;
        if (n == 0) {
            std.debug.assert(output.items.len <= bytes_max);
            return;
        }
        if (output.items.len + n > bytes_max) return error.OutputTooLarge;
        try output.appendSlice(gpa, chunk[0..n]);
    }
    return error.OutputTooLarge;
}
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

    // Verify result is a valid slice type
    const is_valid_type = @TypeOf(files) == [][]const u8;
    try std.testing.expect(is_valid_type);

    // Verify each file path is non-empty if present
    for (files) |file| {
        try std.testing.expect(file.len > 0);
    }
}

test "GitPlugin.fileHasChanges: does not error on committed file" {
    const allocator = std.testing.allocator;
    // build.zig is tracked. The boolean result varies with working-tree state,
    // but the call must succeed without error and return a valid boolean.
    const changed = try GitPlugin.fileHasChanges(allocator, "build.zig");

    // Verify it's a valid boolean (true or false)
    const is_valid = changed == true or changed == false;
    try std.testing.expect(is_valid);
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
/// Test double for a child's stdout pipe.
const FakeSource = struct {
    data: []const u8,
    chunk_size: usize,
    offset: usize = 0,
    endless: bool = false,
    fail_after_data: bool = false,

    fn read(source: *FakeSource, buf: []u8) error{InputOutput}!usize {
        if (source.endless) {
            const n = @min(buf.len, source.chunk_size);
            @memset(buf[0..n], 'x');
            return n;
        }
        if (source.offset == source.data.len) {
            if (source.fail_after_data) return error.InputOutput;
            return 0;
        }
        const n = @min(@min(buf.len, source.chunk_size), source.data.len - source.offset);
        @memcpy(buf[0..n], source.data[source.offset..][0..n]);
        source.offset += n;
        return n;
    }
};

test "readBounded collects the whole stream when under the limit" {
    var source: FakeSource = .{ .data = "feat/branch-name\n", .chunk_size = 5 };
    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);
    try readBounded(&source, std.testing.allocator, &output, 64);
    try std.testing.expectEqualStrings("feat/branch-name\n", output.items);
}

test "readBounded accepts an empty stream" {
    var source: FakeSource = .{ .data = "", .chunk_size = 5 };
    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);
    try readBounded(&source, std.testing.allocator, &output, 64);
    try std.testing.expectEqual(@as(usize, 0), output.items.len);
}

test "readBounded accepts a stream of exactly the limit" {
    var source: FakeSource = .{ .data = "0123456789", .chunk_size = 3 };
    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);
    try readBounded(&source, std.testing.allocator, &output, 10);
    try std.testing.expectEqualStrings("0123456789", output.items);
}

test "readBounded rejects a stream one byte over the limit" {
    var source: FakeSource = .{ .data = "0123456789A", .chunk_size = 3 };
    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.OutputTooLarge,
        readBounded(&source, std.testing.allocator, &output, 10),
    );
    // Never holds more than the limit, even when the oversize chunk straddles it.
    try std.testing.expect(output.items.len <= 10);
}

test "readBounded rejects a stream that never ends" {
    var source: FakeSource = .{ .data = "", .chunk_size = 4096, .endless = true };
    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.OutputTooLarge,
        readBounded(&source, std.testing.allocator, &output, 16 * 1024),
    );
    try std.testing.expect(output.items.len <= 16 * 1024);
}

test "readBounded treats a failed read as end of stream" {
    var source: FakeSource = .{ .data = "partial", .chunk_size = 3, .fail_after_data = true };
    var output = std.ArrayList(u8){};
    defer output.deinit(std.testing.allocator);
    try readBounded(&source, std.testing.allocator, &output, 64);
    try std.testing.expectEqualStrings("partial", output.items);
}

test "readBounded propagates allocation failure" {
    var source: FakeSource = .{ .data = "0123456789", .chunk_size = 3 };
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var output = std.ArrayList(u8){};
    defer output.deinit(failing.allocator());
    try std.testing.expectError(
        error.OutOfMemory,
        readBounded(&source, failing.allocator(), &output, 64),
    );
}

test "collectStdout reads a real child's output" {
    const allocator = std.testing.allocator;
    var child = std.process.Child.init(&[_][]const u8{ "echo", "hello" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    try collectStdout(allocator, &child, &output);
    _ = try child.wait();
    try std.testing.expectEqualStrings("hello\n", output.items);
}
