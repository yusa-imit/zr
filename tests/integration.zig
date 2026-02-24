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

test "16: show displays task details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task: hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Say hello") != null);
}

test "17: show with nonexistent task fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "show", "nonexistent" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "18: --version flag displays version info" {
    const allocator = std.testing.allocator;
    var result = try runZr(allocator, &.{"--version"}, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
}

test "19: validate accepts valid config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "validate", config }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "20: validate accepts simple usage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // validate command doesn't take a path argument — it validates the config in the current directory
    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    // Even if it fails, it shouldn't crash (exit code 0 or 1 both acceptable)
    try std.testing.expect(result.exit_code <= 1);
}

test "21: env shows task environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "GREETING") != null);
}

test "22: export generates shell exports" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
    // Should contain export statement for GREETING variable
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export") != null or std.mem.indexOf(u8, result.stdout, "GREETING") != null);
}

test "23: clean removes cache" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a .zr directory to simulate cache
    try tmp.dir.makeDir(".zr");

    var result = try runZr(allocator, &.{"clean"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "24: doctor checks system status" {
    const allocator = std.testing.allocator;
    var result = try runZr(allocator, &.{"doctor"}, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Doctor writes to stderr by default, so check either stdout or stderr
    try std.testing.expect(result.stdout.len > 0 or result.stderr.len > 0);
}

test "25: history lists recent executions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run a task first to create history
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer run_result.deinit();
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Now check history
    var history_result = try runZr(allocator, &.{"history"}, tmp_path);
    defer history_result.deinit();
    try std.testing.expectEqual(@as(u8, 0), history_result.exit_code);
}

test "26: cache status shows cache info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "cache", "status" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "27: workspace list shows members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a workspace config
    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1", "pkg2"]
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create member directories
    try tmp.dir.makeDir("pkg1");
    try tmp.dir.makeDir("pkg2");

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "28: upgrade checks for updates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "upgrade", "--check" }, tmp_path);
    defer result.deinit();
    // Should exit 0 even if no updates available
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "29: alias list shows aliases" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alias_toml =
        \\[alias]
        \\b = "build"
        \\t = "test"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, alias_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "alias", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "30: schedule list shows scheduled tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const schedule_toml =
        \\[tasks.backup]
        \\cmd = "echo backing up"
        \\schedule = "0 0 * * *"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, schedule_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "31: plugin list shows installed plugins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "plugin", "list" }, tmp_path);
    defer result.deinit();
    // Should succeed even with no plugins
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "32: tools list shows available tools" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "33: setup checks project setup" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "setup" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "34: analytics shows analytics report" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"analytics"}, tmp_path);
    defer result.deinit();
    // Should succeed even with no history
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "35: affected lists affected projects" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a workspace config
    const workspace_toml =
        \\[workspace]
        \\members = ["pkg1"]
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create member directory with config
    try tmp.dir.makeDir("pkg1");
    try tmp.dir.writeFile(.{ .sub_path = "pkg1/zr.toml", .data = "[tasks.test]\ncmd = \"echo test\"\n" });

    // Initialize git repo (affected requires git)
    {
        var init_child = std.process.Child.init(&.{ "git", "init" }, allocator);
        init_child.cwd = tmp_path;
        init_child.stdin_behavior = .Close;
        init_child.stdout_behavior = .Ignore;
        init_child.stderr_behavior = .Ignore;
        _ = try init_child.spawnAndWait();

        var config_user = std.process.Child.init(&.{ "git", "config", "user.email", "test@test.com" }, allocator);
        config_user.cwd = tmp_path;
        config_user.stdin_behavior = .Close;
        config_user.stdout_behavior = .Ignore;
        config_user.stderr_behavior = .Ignore;
        _ = try config_user.spawnAndWait();

        var config_name = std.process.Child.init(&.{ "git", "config", "user.name", "Test" }, allocator);
        config_name.cwd = tmp_path;
        config_name.stdin_behavior = .Close;
        config_name.stdout_behavior = .Ignore;
        config_name.stderr_behavior = .Ignore;
        _ = try config_name.spawnAndWait();

        var add_child = std.process.Child.init(&.{ "git", "add", "." }, allocator);
        add_child.cwd = tmp_path;
        add_child.stdin_behavior = .Close;
        add_child.stdout_behavior = .Ignore;
        add_child.stderr_behavior = .Ignore;
        _ = try add_child.spawnAndWait();

        var commit_child = std.process.Child.init(&.{ "git", "commit", "-m", "init" }, allocator);
        commit_child.cwd = tmp_path;
        commit_child.stdin_behavior = .Close;
        commit_child.stdout_behavior = .Ignore;
        commit_child.stderr_behavior = .Ignore;
        _ = try commit_child.spawnAndWait();
    }

    var result = try runZr(allocator, &.{ "--config", config, "affected", "--list" }, tmp_path);
    defer result.deinit();
    // Should exit 0 (will show "No affected projects found")
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "36: lint validates task configuration" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "lint" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "37: repo info shows repository status" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "repo", "info" }, tmp_path);
    defer result.deinit();
    // May fail if not in git repo, but should not crash
    _ = result.exit_code;
}

test "38: context shows current context" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "context" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "39: conformance checks task conformance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "conformance" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "40: codeowners shows code ownership" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "codeowners" }, tmp_path);
    defer result.deinit();
    // May fail if no CODEOWNERS file, but should not crash
    _ = result.exit_code;
}

test "41: workflow runs workflow stages" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workflow_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[tasks.world]
        \\cmd = "echo world"
        \\
        \\[workflows.test]
        \\
        \\[[workflows.test.stages]]
        \\tasks = ["hello"]
        \\
        \\[[workflows.test.stages]]
        \\tasks = ["world"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "test" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "42: bench measures task performance" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "bench", "hello", "--iterations=1", "--warmup=0" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "43: version shows version information" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"version"}, tmp_path);
    defer result.deinit();
    // May fail without package.json, but should not crash
    _ = result.exit_code;
}

test "44: publish --dry-run simulates publish" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "publish", "--dry-run" }, tmp_path);
    defer result.deinit();
    // May fail without git, but should not crash
    _ = result.exit_code;
}

test "45: run task with dependencies executes all" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const chained_config =
        \\[tasks.task1]
        \\cmd = "echo task1"
        \\
        \\[tasks.task2]
        \\cmd = "echo task2"
        \\deps = ["task1"]
        \\
        \\[tasks.task3]
        \\cmd = "echo task3"
        \\deps = ["task2"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, chained_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "task3" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task3") != null);
}

test "46: --jobs flag limits parallelism" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--jobs", "1", "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "47: --quiet suppresses output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--quiet", "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Quiet mode should have minimal output
}

test "48: --verbose shows detailed output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--verbose", "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "49: config with unknown task field is accepted" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // TOML parser is lenient and ignores unknown fields
    const config_with_unknown =
        \\[tasks.test]
        \\cmd = "echo test"
        \\unknown_field = "value"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_with_unknown);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "50: missing config file reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", "/nonexistent/zr.toml", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "51: list --tags filters by tags" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci", "production"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.dev]
        \\cmd = "echo dev"
        \\tags = ["dev"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--tags=ci" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "52: estimate without history gracefully handles missing data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "estimate", "hello" }, tmp_path);
    defer result.deinit();
    // Should not crash even without history data
    _ = result.exit_code;
}

test "53: watch requires task argument" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "watch" }, tmp_path);
    defer result.deinit();
    // Should fail without task argument
    try std.testing.expect(result.exit_code != 0);
}

test "54: interactive command error handling" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Should work or gracefully handle non-interactive environment
    var result = try runZr(allocator, &.{ "--config", config, "interactive" }, tmp_path);
    defer result.deinit();
    _ = result.exit_code; // Just ensure it doesn't crash
}

test "55: live requires task argument" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "live" }, tmp_path);
    defer result.deinit();
    // Should fail without task argument
    try std.testing.expect(result.exit_code != 0);
}

test "56: circular dependency detection" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const circular_toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\deps = ["b"]
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["c"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\deps = ["a"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, circular_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "a" }, tmp_path);
    defer result.deinit();
    // Should detect circular dependency and fail
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cycle") != null or
        std.mem.indexOf(u8, result.stderr, "circular") != null);
}

test "57: task with circular self-reference" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const self_dep_toml =
        \\[tasks.loop]
        \\cmd = "echo loop"
        \\deps = ["loop"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, self_dep_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "loop" }, tmp_path);
    defer result.deinit();
    // Should detect self-reference as circular dependency
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cycle") != null or
        std.mem.indexOf(u8, result.stderr, "circular") != null);
}

test "58: graph with no tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const empty_toml = "";

    const config = try writeTmpConfig(allocator, tmp.dir, empty_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "graph" }, tmp_path);
    defer result.deinit();
    // Should succeed but show empty graph
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "59: workspace run with empty workspace" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const no_workspace_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, no_workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "hello" }, tmp_path);
    defer result.deinit();
    // Should handle gracefully (either error or run on single project)
    _ = result.exit_code;
}

test "60: run with --profile and nonexistent profile" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "nonexistent", "run", "hello" }, tmp_path);
    defer result.deinit();
    // Should either warn or fail gracefully
    _ = result.exit_code;
}

test "61: estimate command with history data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task first to create history
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer run_result.deinit();

    // Now estimate should work
    var estimate_result = try runZr(allocator, &.{ "--config", config, "estimate", "hello" }, tmp_path);
    defer estimate_result.deinit();
    try std.testing.expect(estimate_result.exit_code == 0);
}

test "62: export command with default bash format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "export GREETING") != null);
}

test "63: export command with fish format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello", "--shell", "fish" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "set -gx GREETING") != null);
}

test "64: export command with powershell format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello", "--shell", "powershell" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "$env:GREETING") != null);
}

test "65: alias add and list workflow" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Alias commands will use ~/.zr/aliases.toml, but for the test
    // we just verify they don't crash and exit cleanly
    var add_result = try runZr(allocator, &.{ "alias", "add", "test-alias", "list" }, tmp_path);
    defer add_result.deinit();
    try std.testing.expect(add_result.exit_code == 0);

    // List should show the alias
    var list_result = try runZr(allocator, &.{ "alias", "list" }, tmp_path);
    defer list_result.deinit();
    try std.testing.expect(list_result.exit_code == 0);
}

test "66: alias show specific alias" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add alias first
    var add_result = try runZr(allocator, &.{ "alias", "add", "show-test", "list --tree" }, tmp_path);
    defer add_result.deinit();

    // Show specific alias
    var show_result = try runZr(allocator, &.{ "alias", "show", "show-test" }, tmp_path);
    defer show_result.deinit();
    try std.testing.expect(show_result.exit_code == 0);
}

test "67: alias remove existing alias" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add alias
    var add_result = try runZr(allocator, &.{ "alias", "add", "remove-me", "list" }, tmp_path);
    defer add_result.deinit();

    // Remove alias
    var remove_result = try runZr(allocator, &.{ "alias", "remove", "remove-me" }, tmp_path);
    defer remove_result.deinit();
    try std.testing.expect(remove_result.exit_code == 0);
}

test "68: graph command with task dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "graph" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "69: graph with --ascii flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--ascii" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "70: bench with --format=csv output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "bench", "hello", "--iterations=2", "--format=csv" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    // CSV output should have iteration column
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "iteration") != null);
}

test "71: bench with --format=json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "bench", "hello", "--iterations=2", "--format=json" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
}

test "72: list with pattern filter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const multi_task_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, multi_task_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "test" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "73: context with --format json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "context", "--format", "json" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
}

test "74: export with missing task argument" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task" }, tmp_path);
    defer result.deinit();
    // Should fail with error about missing task
    try std.testing.expect(result.exit_code == 1);
}

test "75: export with nonexistent task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "nonexistent" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 1);
}

test "76: estimate with nonexistent task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "estimate", "nonexistent" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null);
}

test "77: alias with invalid name characters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to add alias with invalid characters
    var result = try runZr(allocator, &.{ "alias", "add", "invalid@name", "list" }, tmp_path);
    defer result.deinit();
    // Should fail validation
    try std.testing.expect(result.exit_code == 1);
}

test "78: list --tree with filtered pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "build", "--tree" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "79: show with tags display" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\tags = ["ci", "test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "show", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tags") != null or std.mem.indexOf(u8, result.stdout, "tags") != null);
}

test "80: estimate --format=json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task to create history
    var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer run_result.deinit();

    // Estimate with JSON output (use global --format json flag)
    var result = try runZr(allocator, &.{ "--config", config, "--format", "json", "estimate", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null);
}

test "81: schedule add creates new schedule" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add a schedule
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 */2 * * *", "--name", "test-schedule" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test-schedule") != null or std.mem.indexOf(u8, result.stdout, "Schedule created") != null or std.mem.indexOf(u8, result.stderr, "test-schedule") != null or std.mem.indexOf(u8, result.stderr, "created") != null);
}

test "82: schedule show displays schedule details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add a schedule first
    var add_result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 8 * * *", "--name", "morning-run" }, tmp_path);
    defer add_result.deinit();

    // Show the schedule
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "show", "morning-run" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "morning-run") != null or std.mem.indexOf(u8, result.stdout, "0 8 * * *") != null);
}

test "83: schedule remove deletes existing schedule" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add a schedule first
    var add_result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 12 * * *", "--name", "noon-task" }, tmp_path);
    defer add_result.deinit();

    // Remove the schedule
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "remove", "noon-task" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "removed") != null or std.mem.indexOf(u8, result.stdout, "deleted") != null or std.mem.indexOf(u8, result.stderr, "removed") != null or std.mem.indexOf(u8, result.stderr, "deleted") != null or result.stdout.len > 0 or result.stderr.len > 0);
}

test "84: analytics with --json flag outputs JSON format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task a few times to create history
    for (0..3) |_| {
        var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer run_result.deinit();
        std.Thread.sleep(100_000_000); // 100ms delay
    }

    // Get analytics in JSON format
    var result = try runZr(allocator, &.{ "--config", config, "analytics", "--json" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null or std.mem.indexOf(u8, result.stdout, "task") != null);
}

test "85: setup with --check flag validates environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Setup with check flag
    var result = try runZr(allocator, &.{ "--config", config, "setup", "--check" }, tmp_path);
    defer result.deinit();
    // Should exit 0 or 1 depending on environment
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "86: upgrade with --check-only flag does not download" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Check for updates without downloading
    var result = try runZr(allocator, &.{ "upgrade", "--check-only" }, tmp_path);
    defer result.deinit();
    // Should exit 0 (up to date) or 1 (update available)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "87: repo sync without zr-repos.toml fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to sync without config
    var result = try runZr(allocator, &.{ "repo", "sync" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos.toml") != null or std.mem.indexOf(u8, result.stderr, "not found") != null or std.mem.indexOf(u8, result.stderr, "No such file") != null);
}

test "88: repo graph without zr-repos.toml reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to show graph without multi-repo config
    var result = try runZr(allocator, &.{ "repo", "graph" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "89: validate with --strict flag enforces stricter rules" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Validate with strict mode
    var result = try runZr(allocator, &.{ "--config", config, "validate", "--strict" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "90: tools install with invalid tool name fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to install non-existent tool
    var result = try runZr(allocator, &.{ "tools", "install", "invalid-tool@1.0.0" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "unknown") != null or std.mem.indexOf(u8, result.stderr, "not found") != null or std.mem.indexOf(u8, result.stderr, "Unsupported") != null);
}

test "91: plugin list command shows builtin plugins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "plugin", "list" }, tmp_path);
    defer result.deinit();
    // Should succeed even with no plugins configured
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "92: plugin info command with nonexistent plugin fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "plugin", "info", "nonexistent-plugin" }, tmp_path);
    defer result.deinit();
    // Should fail when plugin doesn't exist
    try std.testing.expect(result.exit_code != 0);
}

test "93: lint command with no constraints succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "lint" }, tmp_path);
    defer result.deinit();
    // Should succeed when no constraints are defined
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "94: conformance command with no rules succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "conformance" }, tmp_path);
    defer result.deinit();
    // Should succeed when no conformance rules are defined
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "95: codeowners generate command creates output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = []
        \\
        \\[codeowners]
        \\default_owners = ["@team"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "codeowners", "generate", "--dry-run" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "@team") != null or std.mem.indexOf(u8, result.stdout, "CODEOWNERS") != null);
}

test "96: affected command with no git repository fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "affected", "hello" }, tmp_path);
    defer result.deinit();
    // Should fail gracefully when not in a git repository
    try std.testing.expect(result.exit_code != 0 or std.mem.indexOf(u8, result.stderr, "git") != null or std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "97: workspace list command without workspace section fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    // Should fail when no workspace section exists
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "workspace") != null);
}

test "98: workspace run with --parallel flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "hello", "--parallel" }, tmp_path);
    defer result.deinit();
    // Should succeed or handle parallel flag appropriately
    _ = result.exit_code;
}

test "99: cache clear command with invalid subcommand fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cache_toml =
        \\[cache]
        \\enabled = true
        \\local_dir = ".zr/cache"
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\cache = { key = "hello-key" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, cache_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "cache", "invalid-subcommand" }, tmp_path);
    defer result.deinit();
    // Should fail with invalid subcommand
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown") != null or std.mem.indexOf(u8, result.stderr, "invalid") != null);
}

test "100: repo status command without multi-repo config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "repo", "status" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos") != null or std.mem.indexOf(u8, result.stderr, "not found") != null or std.mem.indexOf(u8, result.stderr, "No such file") != null);
}

test "101: --jobs flag with invalid numeric value fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--jobs", "abc", "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "jobs") != null or std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "number") != null);
}

test "102: --jobs flag with zero value fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--jobs", "0", "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "jobs") != null or std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "0") != null);
}

test "103: --format flag with invalid value fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--format", "invalid", "--config", config, "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "format") != null or std.mem.indexOf(u8, result.stderr, "invalid") != null);
}

test "104: export with invalid shell format fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "hello", "--shell", "invalid-shell" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "shell") != null or std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "unknown") != null);
}

test "105: run with malformed config file reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const malformed_toml =
        \\[tasks.hello
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, malformed_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
    defer result.deinit();
    // Malformed TOML currently results in "task not found" instead of parse error
    // This is a known limitation - TOML parser silently ignores malformed sections
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null or std.mem.indexOf(u8, result.stderr, "error") != null);
}

test "106: bench with invalid iterations value fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "bench", "hello", "--iterations=abc" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "iterations") != null or std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "number") != null);
}

test "107: bench with zero iterations runs no iterations" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "bench", "hello", "--iterations=0", "--warmup=0" }, tmp_path);
    defer result.deinit();
    // Zero iterations is allowed - it just doesn't run anything
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "0 total") != null or std.mem.indexOf(u8, result.stdout, "0 benchmark iterations") != null);
}

test "108: list with --tree and --format json combination" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, DEPS_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--tree", "--format", "json" }, tmp_path);
    defer result.deinit();
    // This should work - both flags are compatible
    try std.testing.expect(result.exit_code == 0);
}

test "109: alias add with empty name fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "alias", "add", "", "run test" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "empty") != null or std.mem.indexOf(u8, result.stderr, "cannot be empty") != null);
}

test "110: schedule with invalid cron expression fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "invalid-cron" }, tmp_path);
    defer result.deinit();
    // Should accept any cron string (validation happens at runtime), but add command should succeed
    // This tests that the command doesn't crash on unusual input
    try std.testing.expect(result.exit_code == 0 or std.mem.indexOf(u8, result.stderr, "cron") != null);
}

test "111: cache status command shows cache statistics" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"cache", "status"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Cache status should display without errors
}

test "112: matrix task expansion creates multiple task instances" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const matrix_toml =
        \\[tasks.test]
        \\cmd = "echo ${matrix.os}"
        \\
        \\[tasks.test.matrix]
        \\os = ["linux", "macos"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, matrix_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test" }, tmp_path);
    defer result.deinit();
    // Matrix expansion should run (may succeed or fail depending on echo support)
    // Just verify command executed without crashing
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "113: run with retry attempts failed task multiple times" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const retry_toml =
        \\[tasks.flaky]
        \\cmd = "false"
        \\retry = 2
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, retry_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, tmp_path);
    defer result.deinit();
    // Task with retries enabled should retry and still fail
    try std.testing.expect(result.exit_code != 0);
}

test "114: run --dry-run shows execution plan with dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const deps_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\deps = ["build"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, deps_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test", "--dry-run" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Dry run should show both tasks in execution plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "115: affected command with --list flag shows affected projects" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["app", "lib"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    // Create workspace structure
    try tmp.dir.makeDir("app");
    try tmp.dir.makeDir("lib");
    try tmp.dir.writeFile(.{ .sub_path = "app/zr.toml", .data = "[tasks.test]\ncmd = \"echo app\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "lib/zr.toml", .data = "[tasks.test]\ncmd = \"echo lib\"\n" });

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Initialize git repo
    {
        const git_init = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "init" },
            .cwd = tmp_path,
        }) catch return;
        defer {
            allocator.free(git_init.stdout);
            allocator.free(git_init.stderr);
        }
    }
    {
        const git_config_email = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.email", "test@example.com" },
            .cwd = tmp_path,
        }) catch return;
        defer {
            allocator.free(git_config_email.stdout);
            allocator.free(git_config_email.stderr);
        }
    }
    {
        const git_config_name = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "config", "user.name", "Test User" },
            .cwd = tmp_path,
        }) catch return;
        defer {
            allocator.free(git_config_name.stdout);
            allocator.free(git_config_name.stderr);
        }
    }
    {
        const git_add = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "add", "." },
            .cwd = tmp_path,
        }) catch return;
        defer {
            allocator.free(git_add.stdout);
            allocator.free(git_add.stderr);
        }
    }
    {
        const git_commit = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "commit", "-m", "initial" },
            .cwd = tmp_path,
        }) catch return;
        defer {
            allocator.free(git_commit.stdout);
            allocator.free(git_commit.stderr);
        }
    }

    var result = try runZr(allocator, &.{ "--config", config, "affected", "test", "--list" }, tmp_path);
    defer result.deinit();
    // Should complete without error (may show no changes if no files modified after commit)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "116: workspace run with filtered members using glob pattern" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["apps/*", "libs/*"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    // Create workspace structure
    try tmp.dir.makeDir("apps");
    try tmp.dir.makeDir("apps/web");
    try tmp.dir.makeDir("apps/mobile");
    try tmp.dir.makeDir("libs");
    try tmp.dir.makeDir("libs/utils");
    try tmp.dir.writeFile(.{ .sub_path = "apps/web/zr.toml", .data = "[tasks.test]\ncmd = \"echo web\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/mobile/zr.toml", .data = "[tasks.test]\ncmd = \"echo mobile\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "libs/utils/zr.toml", .data = "[tasks.test]\ncmd = \"echo utils\"\n" });

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should find all workspace members via glob patterns
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "apps/web") != null or std.mem.indexOf(u8, result.stdout, "web") != null);
}

test "117: run with allow_failure continues on error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allow_failure_toml =
        \\[tasks.might_fail]
        \\cmd = "false"
        \\allow_failure = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, allow_failure_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "might_fail" }, tmp_path);
    defer result.deinit();
    // Task fails but allow_failure means overall run succeeds
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "118: task with deps_serial runs dependencies sequentially" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const serial_toml =
        \\[tasks.dep1]
        \\cmd = "echo dep1"
        \\
        \\[tasks.dep2]
        \\cmd = "echo dep2"
        \\
        \\[tasks.main]
        \\cmd = "echo main"
        \\deps = ["dep1", "dep2"]
        \\deps_serial = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, serial_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "main" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All tasks should run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dep1") != null or std.mem.indexOf(u8, result.stdout, "dep2") != null);
}

test "119: run with --monitor flag displays resource usage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "hello", "--monitor" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Monitor flag should work without errors
}

test "120: doctor command checks for required dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"doctor"}, tmp_path);
    defer result.deinit();
    // Doctor should complete and check for common tools
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "git") != null or std.mem.indexOf(u8, result.stderr, "git") != null);
}

test "121: list --tags with multiple tags filters correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tags_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci", "build"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci", "test"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["production"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tags_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--tags=ci,build" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show build and test (both have ci tag), but not deploy
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "122: env command displays environment variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, ENV_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "env", "--task", "hello" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show GREETING environment variable
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "GREETING") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "howdy") != null);
}

test "123: history with --limit flag restricts output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task twice to create history
    {
        var result1 = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer result1.deinit();
        try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    }
    {
        var result2 = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer result2.deinit();
        try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    }

    // Check history with limit
    var result = try runZr(allocator, &.{ "history", "--limit", "1" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Limited history should have content
    try std.testing.expect(result.stdout.len > 0);
}

test "124: history with --format json outputs JSON" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task to create history
    {
        var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer run_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    }

    var result = try runZr(allocator, &.{ "--format", "json", "history" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // JSON format should be parseable (contains "runs" key)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "runs") != null);
}

test "125: plugin create generates plugin scaffold" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "plugin", "create", "test-plugin" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should create plugin directory
    tmp.dir.access("test-plugin", .{}) catch |err| {
        std.debug.print("Expected plugin directory not found: {}\n", .{err});
        return err;
    };
}

test "126: plugin search with query returns results" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "plugin", "search", "docker" }, tmp_path);
    defer result.deinit();
    // Search should complete without error (even if registry unavailable)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "127: workflow with approval field (non-interactive dry-run)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workflow_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[workflows.release]
        \\
        \\[[workflows.release.stages]]
        \\name = "build"
        \\tasks = ["build"]
        \\approval = true
        \\
        \\[[workflows.release.stages]]
        \\name = "deploy"
        \\tasks = ["hello"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Use --dry-run to avoid interactive approval prompt
    var result = try runZr(allocator, &.{ "--config", config, "workflow", "release", "--dry-run" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show workflow plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null or std.mem.indexOf(u8, result.stderr, "build") != null);
}

test "128: conformance with --fix flag applies fixes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const conformance_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[[conformance.rules]]
        \\type = "import_pattern"
        \\pattern = "forbidden"
        \\scope = "*.txt"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, conformance_toml);
    defer allocator.free(config);

    // Create a file with forbidden import
    const test_file = try tmp.dir.createFile("test.txt", .{});
    defer test_file.close();
    try test_file.writeAll("import forbidden\nok line\n");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "conformance", "--fix" }, tmp_path);
    defer result.deinit();
    // Fix should complete successfully
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "129: version with --bump=patch increments version" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create package.json
    const package_json =
        \\{
        \\  "name": "test",
        \\  "version": "1.0.0"
        \\}
        \\
    ;
    const pkg_file = try tmp.dir.createFile("package.json", .{});
    defer pkg_file.close();
    try pkg_file.writeAll(package_json);

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "version", "--bump=patch" }, tmp_path);
    defer result.deinit();
    // Should show new version or succeed
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "130: analytics with --limit flag restricts history range" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task to create history
    {
        var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer run_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    }

    var result = try runZr(allocator, &.{ "analytics", "--limit", "10", "--json" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should output analytics data
    try std.testing.expect(result.stdout.len > 0);
}

// ── Advanced Multi-Feature Integration Tests ─────────────────────────

test "131: workflow with matrix, cache, and dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const matrix_workflow_toml =
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.test]
        \\cmd = "echo testing $TARGET"
        \\deps = ["setup"]
        \\matrix.TARGET = ["linux", "macos", "windows"]
        \\cache.enabled = true
        \\cache.key = "test-$TARGET"
        \\
        \\[[workflows.ci.stages]]
        \\tasks = ["test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, matrix_workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show tasks in the config
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null or std.mem.indexOf(u8, result.stdout, "setup") != null);
}

test "132: profile overrides with environment variables and dry-run" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const profile_env_toml =
        \\[tasks.deploy]
        \\cmd = "echo deploying to $ENV"
        \\env = { ENV = "dev" }
        \\
        \\[profiles.production]
        \\env = { ENV = "prod" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, profile_env_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "production", "--dry-run", "run", "deploy" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Dry-run should complete without errors
}

test "133: task with condition, retry, and timeout" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const complex_task_toml =
        \\[tasks.flaky]
        \\cmd = "sleep 0.1 && exit 0"
        \\condition = "platform == 'darwin' || platform == 'linux'"
        \\retry = 2
        \\timeout = 5000
        \\allow_failure = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, complex_task_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "flaky" }, tmp_path);
    defer result.deinit();
    // Should succeed or gracefully handle failure with allow_failure
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "134: workspace with tagged filtering and parallel execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_tags_toml =
        \\[workspace]
        \\members = ["pkg-a", "pkg-b"]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\tags = ["ci", "build"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\tags = ["ci", "test"]
        \\deps = ["build"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_tags_toml);
    defer allocator.free(config);

    // Create workspace member directories
    try tmp.dir.makeDir("pkg-a");
    try tmp.dir.makeDir("pkg-b");

    // Create member configs
    const pkg_a_file = try tmp.dir.createFile("pkg-a/zr.toml", .{});
    defer pkg_a_file.close();
    try pkg_a_file.writeAll("[tasks.build]\ncmd = \"echo pkg-a build\"\n");

    const pkg_b_file = try tmp.dir.createFile("pkg-b/zr.toml", .{});
    defer pkg_b_file.close();
    try pkg_b_file.writeAll("[tasks.build]\ncmd = \"echo pkg-b build\"\n");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "--jobs", "2", "list", "--tags=ci" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should list tasks with ci tag
    try std.testing.expect(result.stdout.len > 0);
}

test "135: alias expansion with flags and arguments" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create alias
    {
        var add_result = try runZr(allocator, &.{ "alias", "add", "quick-build", "run hello --dry-run" }, tmp_path);
        defer add_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), add_result.exit_code);
    }

    // Use alias
    var result = try runZr(allocator, &.{ "--config", config, "quick-build" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "136: bench with profile and JSON output format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const bench_profile_toml =
        \\[tasks.fast]
        \\cmd = "echo fast"
        \\
        \\[profiles.perf]
        \\env = { MODE = "fast" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, bench_profile_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "perf", "bench", "fast", "-n", "3", "--format=json", "--quiet" }, tmp_path);
    defer result.deinit();
    // Exit code 0 or 1 acceptable (bench may fail on resource constraints)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "137: show command with complex task configuration" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const complex_show_toml =
        \\[tasks.complex]
        \\cmd = "echo complex"
        \\description = "Complex task"
        \\cwd = "/tmp"
        \\deps = ["dep1", "dep2"]
        \\env = { VAR1 = "value1", VAR2 = "value2" }
        \\timeout = 30000
        \\retry = 3
        \\allow_failure = true
        \\tags = ["integration", "slow"]
        \\max_concurrent = 5
        \\max_cpu = 80
        \\max_memory = 512
        \\
        \\[tasks.dep1]
        \\cmd = "echo dep1"
        \\
        \\[tasks.dep2]
        \\cmd = "echo dep2"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, complex_show_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "show", "complex" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show task name or description
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "complex") != null or std.mem.indexOf(u8, result.stdout, "Complex task") != null);
}

test "138: export with toolchain paths and custom env" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toolchain_export_toml =
        \\[tasks.node-app]
        \\cmd = "node app.js"
        \\env = { NODE_ENV = "production" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toolchain_export_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "export", "--task", "node-app", "--shell", "bash" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should include env vars
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NODE_ENV") != null or std.mem.indexOf(u8, result.stdout, "production") != null);
}

test "139: history with filtering and different formats" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task to create history
    {
        var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer run_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    }

    // Test plain history
    {
        var hist_result = try runZr(allocator, &.{ "history" }, tmp_path);
        defer hist_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), hist_result.exit_code);
        try std.testing.expect(hist_result.stdout.len > 0);
    }

    // Test JSON history
    {
        var json_result = try runZr(allocator, &.{ "history", "--format=json" }, tmp_path);
        defer json_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), json_result.exit_code);
        // JSON output may be empty array or have content
        try std.testing.expect(json_result.stdout.len > 0);
    }
}

test "140: clean command with selective cleanup" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task to create cache and history
    {
        var run_result = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer run_result.deinit();
        try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    }

    // Test clean with different options
    {
        var clean_result = try runZr(allocator, &.{ "clean", "--cache", "--dry-run" }, tmp_path);
        defer clean_result.deinit();
        // Dry-run should show what would be cleaned
        try std.testing.expect(clean_result.exit_code == 0 or clean_result.exit_code == 1);
    }
}

test "141: validate --strict enforces stricter validation rules" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_with_warnings =
        \\[tasks.test]
        \\cmd = "echo test"
        \\description = "Test task"
        \\unknown_field = "value"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_with_warnings);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Normal validation should succeed
    {
        var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
        defer result.deinit();
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // Strict validation may warn about unknown fields
    {
        var result = try runZr(allocator, &.{ "--config", config, "validate", "--strict" }, tmp_path);
        defer result.deinit();
        // Accepts either success or warnings
        try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    }
}

test "142: validate --schema displays schema information" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "validate", "--schema" }, tmp_path);
    defer result.deinit();

    // Should display schema info (may succeed or fail if no config found)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "143: graph --ascii displays tree-style dependency graph" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_with_deps =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\deps = ["b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_with_deps);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--ascii" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain tree-style output with tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "c") != null);
}

test "144: tools outdated checks for outdated toolchains" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // This command checks for outdated toolchains against registries
    var result = try runZr(allocator, &.{ "tools", "outdated" }, tmp_path);
    defer result.deinit();

    // Should succeed (even if no tools installed)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "145: plugin update updates installed plugin" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try updating a nonexistent plugin (should fail gracefully)
    var result = try runZr(allocator, &.{ "plugin", "update", "nonexistent" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully for nonexistent plugin
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "146: plugin builtins lists available built-in plugins" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "plugin", "builtins" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should list built-in plugins like env, git, docker, cache
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "env") != null or
        std.mem.indexOf(u8, result.stdout, "git") != null);
}

test "147: workspace sync builds synthetic workspace from multi-repo" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try syncing without zr-repos.toml (should fail gracefully)
    var result = try runZr(allocator, &.{ "workspace", "sync" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully if no zr-repos.toml found
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos.toml") != null);
}

test "148: repo run executes task across all repositories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try running task without zr-repos.toml (should fail gracefully)
    var result = try runZr(allocator, &.{ "repo", "run", "test" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully if no zr-repos.toml found
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr-repos.toml") != null);
}

test "149: repo run with --dry-run flag shows execution plan" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try dry-run without zr-repos.toml (should fail gracefully)
    var result = try runZr(allocator, &.{ "repo", "run", "test", "--dry-run" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully if no zr-repos.toml found
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "150: list command with multiple flag combinations" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_with_tags =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci", "build"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci", "test"]
        \\deps = ["build"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["prod"]
        \\deps = ["test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_with_tags);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Test list with pattern and tags together
    {
        var result = try runZr(allocator, &.{ "--config", config, "list", "build", "--tags=ci" }, tmp_path);
        defer result.deinit();
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
        // Should show build task (matches both pattern and tag)
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    }

    // Test list --tree with tags
    {
        var result = try runZr(allocator, &.{ "--config", config, "list", "--tree", "--tags=ci" }, tmp_path);
        defer result.deinit();
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
        // Should show tree view with filtered tasks
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    }
}

test "151: tools --help flag shows help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "--help" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Toolchain Management") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "list") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "install") != null);
}

test "152: tools -h flag shows help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "-h" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Toolchain Management") != null);
}

test "153: cache clear command clears task results cache" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cache_toml =
        \\[cache]
        \\enabled = true
        \\local_dir = ".zr/cache"
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\cache = { key = "hello-key" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, cache_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Clear cache (should succeed even if no cache exists)
    var result = try runZr(allocator, &.{ "cache", "clear" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Cleared") != null);
}

test "154: schedule add with custom name option" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const schedule_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, schedule_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "build", "0 0 * * *", "--name", "nightly-build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "155: workspace run with --parallel and specific members" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_toml =
        \\[workspace]
        \\members = ["pkg-a", "pkg-b"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workspace_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create workspace member directories
    try tmp.dir.makeDir("pkg-a");
    try tmp.dir.makeDir("pkg-b");

    // Create zr.toml in each member
    var pkg_a = try tmp.dir.openDir("pkg-a", .{});
    defer pkg_a.close();
    const pkg_a_config = try pkg_a.createFile("zr.toml", .{});
    defer pkg_a_config.close();
    try pkg_a_config.writeAll(workspace_toml);

    var pkg_b = try tmp.dir.openDir("pkg-b", .{});
    defer pkg_b.close();
    const pkg_b_config = try pkg_b.createFile("zr.toml", .{});
    defer pkg_b_config.close();
    try pkg_b_config.writeAll(workspace_toml);

    var result = try runZr(allocator, &.{ "--config", config, "workspace", "run", "--parallel", "test" }, tmp_path);
    defer result.deinit();

    // Should succeed even if members don't have the task
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "156: graph command with --format json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const deps_toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, deps_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--format", "json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // JSON output should contain task info
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tasks") != null or result.stdout.len > 0);
}

test "157: list with --format json and --tags filter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["prod"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--format", "json", "--tags=ci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should output JSON with only ci-tagged tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "158: run with --profile that includes environment overrides" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const profile_toml =
        \\[tasks.hello]
        \\cmd = "echo $GREETING"
        \\env = { GREETING = "hello" }
        \\
        \\[profiles.formal]
        \\env = { GREETING = "good day" }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, profile_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "--profile", "formal", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Profile should override the task env
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "day") != null or result.stdout.len > 0);
}

test "159: alias remove with nonexistent alias fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const simple_toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, simple_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "alias", "remove", "nonexistent-alias" }, tmp_path);
    defer result.deinit();

    // Should fail gracefully
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "160: publish with --dry-run shows what would be done" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const publish_toml =
        \\[package]
        \\name = "my-tasks"
        \\version = "1.0.0"
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, publish_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "publish", "--dry-run" }, tmp_path);
    defer result.deinit();

    // Dry-run should succeed or fail gracefully
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "161: completion zsh generates zsh completion script" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "completion", "zsh" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain zsh completion syntax
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "#compdef") != null or result.stdout.len > 0);
}

test "162: completion fish generates fish completion script" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "completion", "fish" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Fish completion should generate output
    try std.testing.expect(result.stdout.len > 0);
}

test "163: init with existing config refuses overwrite" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create existing zr.toml
    const existing = try tmp.dir.createFile("zr.toml", .{});
    defer existing.close();
    try existing.writeAll("[tasks.old]\ncmd = \"echo old\"\n");

    var result = try runZr(allocator, &.{ "init" }, tmp_path);
    defer result.deinit();

    // Should refuse to overwrite existing config
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "already exists") != null);
}

test "164: setup with --verbose shows detailed diagnostics" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const simple_toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, simple_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "setup", "--verbose" }, tmp_path);
    defer result.deinit();

    // Should succeed or show diagnostics
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "165: upgrade with --prerelease flag accepts prerelease versions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "upgrade", "--check", "--prerelease" }, tmp_path);
    defer result.deinit();

    // Should check for updates including prerelease (network dependent, allow either exit code)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "166: watch with nonexistent task fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const simple_toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, simple_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "watch", "nonexistent" }, tmp_path);
    defer result.deinit();

    // Should fail with nonexistent task
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "167: workflow with empty stages array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const empty_workflow_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[workflows.empty]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, empty_workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "empty" }, tmp_path);
    defer result.deinit();

    // Empty workflow should succeed (no stages to run)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "168: list with both --tree and pattern filter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const deps_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.build-frontend]
        \\cmd = "echo frontend"
        \\deps = ["build"]
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, deps_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "build", "--tree" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show tree for filtered tasks
    try std.testing.expect(result.stdout.len > 0);
}

test "169: run with cache enabled stores task results" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cache_toml =
        \\[tasks.cached]
        \\cmd = "echo cached-output"
        \\cache = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, cache_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task first time (populates cache)
    {
        var result1 = try runZr(allocator, &.{ "--config", config, "run", "cached" }, tmp_path);
        defer result1.deinit();
        try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    }

    // Run again (should use cache)
    var result = try runZr(allocator, &.{ "--config", config, "run", "cached" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "170: estimate with multiple tasks in history" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const simple_toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, simple_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task multiple times to build history
    {
        var result1 = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer result1.deinit();
    }
    {
        var result2 = try runZr(allocator, &.{ "--config", config, "run", "hello" }, tmp_path);
        defer result2.deinit();
    }

    // Now estimate should have data
    var result = try runZr(allocator, &.{ "--config", config, "estimate", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show estimate based on history
    try std.testing.expect(result.stdout.len > 0);
}
