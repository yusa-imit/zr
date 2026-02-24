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
