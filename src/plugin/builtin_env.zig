//! Built-in `.env` plugin: reads dotenv files into the process environment or into pairs.
//!
//! Contract: a file larger than `file_bytes_max` is rejected with `error.FileTooLarge`
//! instead of being silently truncated. Returned pairs are owned by the caller; the file is read
//! into a stack buffer, so nothing is allocated beyond the pairs and the setenv(3) copies.

const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("../stdx.zig");
const assert = stdx.assert;
const native_os = builtin.os.tag;

/// Largest `.env` file accepted, in bytes. A larger file is an error, never a partial read.
pub const file_bytes_max: u32 = 65536;

// POSIX setenv(3) — only available on non-Windows targets.
// The extern declaration is behind a comptime branch so it doesn't
// generate a linker reference on Windows.
fn posixSetenv(name_z: [*:0]const u8, val_z: [*:0]const u8, overwrite: bool) void {
    if (comptime native_os == .windows) return;
    const SetenvFn = *const fn ([*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int;
    const c_setenv = @extern(SetenvFn, .{ .name = "setenv" });
    _ = c_setenv(name_z, val_z, if (overwrite) 1 else 0);
}

pub const EnvPlugin = struct {
    /// Load a .env file and merge variables into the process environment via setenv(3).
    /// Skips comments (#), blank lines, and lines without '='.
    /// Variables already set in the environment are NOT overwritten by default.
    /// Set `overwrite = true` to force overwrite.
    /// Returns `error.FileTooLarge` when the file exceeds `file_bytes_max`.
    pub fn loadDotEnv(
        allocator: std.mem.Allocator,
        env_path: []const u8,
        overwrite: bool,
    ) !void {
        const file = std.fs.openFileAbsolute(env_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        var buf: [file_bytes_max + 1]u8 = undefined;
        const content = try readBounded(file, &buf);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const key = std.mem.trim(u8, trimmed[0..eq], " \t");
            if (key.len == 0) continue;
            var val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
            // Strip surrounding quotes (single or double).
            if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
                val = val[1 .. val.len - 1];
            } else if (val.len >= 2 and val[0] == '\'' and val[val.len - 1] == '\'') {
                val = val[1 .. val.len - 1];
            }
            // Set the env var via POSIX setenv(3). No-op on Windows.
            if (comptime native_os == .windows) continue;
            const key_z = try allocator.dupeZ(u8, key);
            defer allocator.free(key_z);
            const val_z = try allocator.dupeZ(u8, val);
            defer allocator.free(val_z);
            posixSetenv(key_z, val_z, overwrite);
        }
    }

    /// Read key=value pairs from a .env file into a slice of [2]string pairs.
    /// Caller owns the returned slice and all strings within.
    /// Returns `error.FileTooLarge` when the file exceeds `file_bytes_max`.
    pub fn readDotEnv(
        allocator: std.mem.Allocator,
        env_path: []const u8,
    ) ![][2][]const u8 {
        const file = std.fs.openFileAbsolute(env_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return &.{},
            else => return err,
        };
        defer file.close();

        var buf: [file_bytes_max + 1]u8 = undefined;
        const content = try readBounded(file, &buf);

        var pairs: std.ArrayListUnmanaged([2][]const u8) = .empty;
        errdefer {
            for (pairs.items) |p| {
                allocator.free(p[0]);
                allocator.free(p[1]);
            }
            pairs.deinit(allocator);
        }

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const key = std.mem.trim(u8, trimmed[0..eq], " \t");
            if (key.len == 0) continue;
            var val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
            if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
                val = val[1 .. val.len - 1];
            } else if (val.len >= 2 and val[0] == '\'' and val[val.len - 1] == '\'') {
                val = val[1 .. val.len - 1];
            }
            const pair: [2][]const u8 = .{
                try allocator.dupe(u8, key),
                try allocator.dupe(u8, val),
            };
            try pairs.append(allocator, pair);
        }

        return pairs.toOwnedSlice(allocator);
    }
};

/// Reads the whole file into `buf` (capacity `file_bytes_max + 1`); a file that fills the extra
/// byte is over the cap.
fn readBounded(file: std.fs.File, buf: []u8) ![]const u8 {
    assert(buf.len == file_bytes_max + 1);
    const n = try file.readAll(buf);
    if (n > file_bytes_max) return error.FileTooLarge;
    assert(n <= file_bytes_max);
    return buf[0..n];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "EnvPlugin.readDotEnv: parses key=value pairs" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = ".env",
        .data = "# comment\nFOO=bar\nBAZ=\"quoted value\"\nEMPTY=\nSKIP\n",
    });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const env_path = try std.fmt.allocPrint(allocator, "{s}/.env", .{tmp_path});
    defer allocator.free(env_path);

    const pairs = try EnvPlugin.readDotEnv(allocator, env_path);
    defer {
        for (pairs) |p| {
            allocator.free(p[0]);
            allocator.free(p[1]);
        }
        allocator.free(pairs);
    }

    // Should have FOO, BAZ, EMPTY (SKIP has no '=' so skipped; comment skipped).
    try std.testing.expectEqual(@as(usize, 3), pairs.len);
    try std.testing.expectEqualStrings("FOO", pairs[0][0]);
    try std.testing.expectEqualStrings("bar", pairs[0][1]);
    try std.testing.expectEqualStrings("BAZ", pairs[1][0]);
    try std.testing.expectEqualStrings("quoted value", pairs[1][1]);
    try std.testing.expectEqualStrings("EMPTY", pairs[2][0]);
    try std.testing.expectEqualStrings("", pairs[2][1]);
}

test "EnvPlugin.readDotEnv: file not found returns empty slice" {
    const allocator = std.testing.allocator;
    const pairs = try EnvPlugin.readDotEnv(allocator, "/nonexistent/path/.env");
    try std.testing.expectEqual(@as(usize, 0), pairs.len);
}

test "EnvPlugin.readDotEnv: single-quoted values stripped" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = ".env",
        .data = "KEY='hello world'\n",
    });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const env_path = try std.fmt.allocPrint(allocator, "{s}/.env", .{tmp_path});
    defer allocator.free(env_path);

    const pairs = try EnvPlugin.readDotEnv(allocator, env_path);
    defer {
        for (pairs) |p| {
            allocator.free(p[0]);
            allocator.free(p[1]);
        }
        allocator.free(pairs);
    }

    try std.testing.expectEqual(@as(usize, 1), pairs.len);
    try std.testing.expectEqualStrings("hello world", pairs[0][1]);
}

test "EnvPlugin.readDotEnv: file at the size cap is read in full" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // "K=" plus padding, exactly file_bytes_max bytes, no trailing newline.
    const data = try allocator.alloc(u8, file_bytes_max);
    defer allocator.free(data);
    @memset(data, 'v');
    data[0] = 'K';
    data[1] = '=';
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = data });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const env_path = try std.fmt.allocPrint(allocator, "{s}/.env", .{tmp_path});
    defer allocator.free(env_path);

    const pairs = try EnvPlugin.readDotEnv(allocator, env_path);
    defer {
        for (pairs) |p| {
            allocator.free(p[0]);
            allocator.free(p[1]);
        }
        allocator.free(pairs);
    }

    try std.testing.expectEqual(@as(usize, 1), pairs.len);
    try std.testing.expectEqual(@as(usize, file_bytes_max - 2), pairs[0][1].len);
}

test "EnvPlugin.readDotEnv: file over the size cap is an error" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data = try allocator.alloc(u8, file_bytes_max + 1);
    defer allocator.free(data);
    @memset(data, 'v');
    data[0] = 'K';
    data[1] = '=';
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = data });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const env_path = try std.fmt.allocPrint(allocator, "{s}/.env", .{tmp_path});
    defer allocator.free(env_path);

    try std.testing.expectError(error.FileTooLarge, EnvPlugin.readDotEnv(allocator, env_path));
    const loaded = EnvPlugin.loadDotEnv(allocator, env_path, false);
    try std.testing.expectError(error.FileTooLarge, loaded);
}
