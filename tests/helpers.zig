const std = @import("std");
const build_options = @import("build_options");

pub const ZR_BIN: []const u8 = build_options.zr_bin_path;

// ── TOML Fixtures ──────────────────────────────────────────────────────

pub const HELLO_TOML =
    \\[tasks.hello]
    \\description = "Say hello"
    \\cmd = "echo hello"
    \\
;

pub const FAIL_TOML =
    \\[tasks.hello]
    \\description = "Fail"
    \\cmd = "false"
    \\
;

pub const DEPS_TOML =
    \\[tasks.hello]
    \\cmd = "echo hello"
    \\
    \\[tasks.build]
    \\cmd = "echo building"
    \\deps = ["hello"]
    \\
;

pub const ENV_TOML =
    \\[tasks.hello]
    \\cmd = "echo $GREETING"
    \\env = { GREETING = "howdy" }
    \\
;

// ── Helpers ────────────────────────────────────────────────────────────

pub const ZrResult = struct {
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
pub fn runZr(allocator: std.mem.Allocator, args: []const []const u8, cwd: ?[]const u8) !ZrResult {
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

/// Spawn the `zr` binary with stdin input.
/// Returns captured stdout, stderr, and exit code.
pub fn runZrWithStdin(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    args: []const []const u8,
    stdin_content: []const u8,
) !ZrResult {
    // Get directory path for cwd
    const cwd_path = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    // Resolve binary to absolute path
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
    child.stdin_behavior = .Pipe;
    child.cwd = cwd_path;

    try child.spawn();

    // Write stdin content
    if (child.stdin) |stdin_pipe| {
        _ = try stdin_pipe.writeAll(stdin_content);
        stdin_pipe.close();
        child.stdin = null; // Mark as closed
    }

    // Read stdout/stderr BEFORE wait()
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
pub fn writeTmpConfig(allocator: std.mem.Allocator, dir: std.fs.Dir, toml: []const u8) ![]const u8 {
    try dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });
    const tmp_path = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    return std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
}

pub fn writeTmpConfigPath(allocator: std.mem.Allocator, dir: std.fs.Dir, toml: []const u8, path: []const u8) ![]const u8 {
    try dir.writeFile(.{ .sub_path = path, .data = toml });
    const tmp_path = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ tmp_path, path });
}
