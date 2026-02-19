const std = @import("std");
const build_options = @import("build_options");

const ZR_BIN: []const u8 = build_options.zr_bin_path;

// ── TOML Fixtures ──────────────────────────────────────────────────────

const HELLO_TOML =
    \\[tasks.hello]
    \\description = "Say hello"
    \\cmd = "echo hello"
    \\
;

const FAIL_TOML =
    \\[tasks.hello]
    \\description = "Fail"
    \\cmd = "false"
    \\
;

const DEPS_TOML =
    \\[tasks.hello]
    \\cmd = "echo hello"
    \\
    \\[tasks.build]
    \\cmd = "echo building"
    \\deps = ["hello"]
    \\
;

const ENV_TOML =
    \\[tasks.hello]
    \\cmd = "echo $GREETING"
    \\env = { GREETING = "howdy" }
    \\
;

// ── Helpers ────────────────────────────────────────────────────────────

const ZrResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ZrResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

/// Spawn the `zr` binary with the given arguments and optional cwd.
/// Returns captured stdout, stderr, and exit code.
fn runZr(allocator: std.mem.Allocator, args: []const []const u8, cwd: ?[]const u8) !ZrResult {
    // Resolve binary to absolute path so it works even with a different child cwd
    const resolved_bin = try std.fs.cwd().realpathAlloc(allocator, ZR_BIN);
    defer allocator.free(resolved_bin);

    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);
    try argv.append(allocator, resolved_bin);
    for (args) |arg| {
        try argv.append(allocator, arg);
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.stdin_behavior = .Close;
    child.cwd = cwd;

    try child.spawn();

    // Read stdout/stderr BEFORE wait() — Zig 0.15 closes pipes in wait()
    var stdout_list = std.ArrayList(u8){};
    errdefer stdout_list.deinit(allocator);
    var stderr_list = std.ArrayList(u8){};
    errdefer stderr_list.deinit(allocator);

    if (child.stdout) |pipe| {
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = pipe.read(&buf) catch break;
            if (n == 0) break;
            try stdout_list.appendSlice(allocator, buf[0..n]);
        }
    }
    if (child.stderr) |pipe| {
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = pipe.read(&buf) catch break;
            if (n == 0) break;
            try stderr_list.appendSlice(allocator, buf[0..n]);
        }
    }

    const term = try child.wait();
    const exit_code: u8 = switch (term) {
        .Exited => |code| code,
        .Signal => |_| 255,
        .Stopped => |_| 255,
        .Unknown => |_| 255,
    };

    return ZrResult{
        .exit_code = exit_code,
        .stdout = try stdout_list.toOwnedSlice(allocator),
        .stderr = try stderr_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Write a zr.toml into the given directory and return its absolute path.
/// Caller must free the returned path.
fn writeTmpConfig(allocator: std.mem.Allocator, dir: std.fs.Dir, toml: []const u8) ![]const u8 {
    try dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });
    const tmp_path = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    return std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
}

// ── Test Cases ─────────────────────────────────────────────────────────

test "1: no args shows help" {
    const allocator = std.testing.allocator;
    var result = try runZr(allocator, &.{}, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage:") != null);
}

test "2: unknown command exits 1" {
    const allocator = std.testing.allocator;
    var result = try runZr(allocator, &.{"badcmd"}, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "3: init creates zr.toml" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"init"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify zr.toml was created
    tmp.dir.access("zr.toml", .{}) catch {
        return error.TestUnexpectedResult;
    };
}

test "4: init refuses overwrite" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create existing zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "existing" });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"init"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "5: run success" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "6: run failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, FAIL_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "7: run nonexistent task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "nope" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "8: run --dry-run does not execute" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Task creates a marker file — dry-run should NOT create it
    const dry_toml = try std.fmt.allocPrint(
        allocator,
        "[tasks.hello]\ncmd = \"touch {s}/dry_marker\"\n",
        .{tmp_path},
    );
    defer allocator.free(dry_toml);

    const config = try writeTmpConfig(allocator, tmp.dir, dry_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--dry-run", "--config", config, "run", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Marker file should NOT exist (dry-run skips execution)
    tmp.dir.access("dry_marker", .{}) catch |err| {
        if (err == error.FileNotFound) return; // expected — test passes
        return error.TestUnexpectedResult;
    };
    // If we reach here, the file exists — command was executed despite --dry-run
    return error.TestUnexpectedResult;
}

test "9: list shows tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "10: list --format json" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--format", "json", "--config", config, "list" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"tasks\"") != null);
}

test "11: graph shows levels" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, DEPS_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Level") != null);
}

test "12: completion bash" {
    const allocator = std.testing.allocator;
    var result = try runZr(allocator, &.{ "completion", "bash" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
}

test "13: run with deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, DEPS_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "14: run with env config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "howdy") != null);
}

test "15: --no-color disables ANSI" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--no-color", "--config", config, "run", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // No ANSI escape sequences in output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\x1b") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "\x1b") == null);
}
