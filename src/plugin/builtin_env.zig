const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

// POSIX setenv(3) — only available on non-Windows targets.
// The extern declaration is behind a comptime branch so it doesn't
// generate a linker reference on Windows.
fn posixSetenv(name_z: [*:0]const u8, val_z: [*:0]const u8, overwrite: bool) void {
    if (comptime native_os == .windows) return;
    const c_setenv = @extern(*const fn ([*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "setenv" });
    _ = c_setenv(name_z, val_z, if (overwrite) 1 else 0);
}

pub const EnvPlugin = struct {
    /// Load a .env file and merge variables into the process environment via setenv(3).
    /// Skips comments (#), blank lines, and lines without '='.
    /// Variables already set in the environment are NOT overwritten by default.
    /// Set `overwrite = true` to force overwrite.
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

        var buf: [65536]u8 = undefined;
        const n = try file.readAll(&buf);
        const content = buf[0..n];

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
    pub fn readDotEnv(
        allocator: std.mem.Allocator,
        env_path: []const u8,
    ) ![][2][]const u8 {
        const file = std.fs.openFileAbsolute(env_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return &.{},
            else => return err,
        };
        defer file.close();

        var buf: [65536]u8 = undefined;
        const n = try file.readAll(&buf);
        const content = buf[0..n];

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
