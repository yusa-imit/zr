const std = @import("std");

pub const Config = struct {
    tasks: std.StringHashMap(Task),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .tasks = std.StringHashMap(Task).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        var it = self.tasks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.tasks.deinit();
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        return try parseToml(allocator, content);
    }

    /// Add a task directly (useful for tests and programmatic construction).
    pub fn addTask(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false);
    }

    /// Add a task with all fields (for tests or programmatic use with full options).
    pub fn addTaskFull(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        timeout_ms: ?u64,
        allow_failure: bool,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, timeout_ms, allow_failure, 0, 0, false);
    }

    /// Add a task with deps_serial (for tests or programmatic use).
    pub fn addTaskWithSerial(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        deps_serial: []const []const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, deps_serial, &[_][2][]const u8{}, null, false, 0, 0, false);
    }

    /// Add a task with env pairs (for tests or programmatic use with env overrides).
    pub fn addTaskWithEnv(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        env: []const [2][]const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, env, null, false, 0, 0, false);
    }

    /// Add a task with retry settings (for tests or programmatic use).
    pub fn addTaskWithRetry(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        retry_max: u32,
        retry_delay_ms: u64,
        retry_backoff: bool,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_][2][]const u8{}, null, false, retry_max, retry_delay_ms, retry_backoff);
    }
};

pub const Task = struct {
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: [][]const u8,
    /// Sequential dependencies: run in array order before this task, one at a time.
    deps_serial: [][]const u8,
    /// Environment variable overrides. Each entry is [key, value] (owned, duped).
    env: [][2][]const u8,
    /// Timeout in milliseconds. null means no timeout.
    timeout_ms: ?u64 = null,
    /// If true, a non-zero exit code is treated as success for dependency purposes.
    allow_failure: bool = false,
    /// Maximum number of retry attempts after the first failure (0 = no retry).
    retry_max: u32 = 0,
    /// Delay between retry attempts in milliseconds.
    retry_delay_ms: u64 = 0,
    /// If true, delay doubles on each retry attempt (exponential backoff).
    retry_backoff: bool = false,

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.cmd);
        if (self.cwd) |cwd| allocator.free(cwd);
        if (self.description) |desc| allocator.free(desc);
        for (self.deps) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.deps);
        for (self.deps_serial) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.deps_serial);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.env);
    }
};

/// Parse a duration string like "5m", "30s", "1h", "500ms" into milliseconds.
/// Returns null if the format is unrecognized.
pub fn parseDurationMs(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    if (std.mem.endsWith(u8, s, "ms")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 2], 10) catch return null;
        return n;
    } else if (std.mem.endsWith(u8, s, "h")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 3_600_000;
    } else if (std.mem.endsWith(u8, s, "m")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 60_000;
    } else if (std.mem.endsWith(u8, s, "s")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 1_000;
    }
    return null;
}

fn parseToml(allocator: std.mem.Allocator, content: []const u8) !Config {
    var config = Config.init(allocator);
    errdefer config.deinit();

    var lines = std.mem.splitScalar(u8, content, '\n');

    // These are non-owning slices into `content` — addTask dupes them
    var current_task: ?[]const u8 = null;
    var task_cmd: ?[]const u8 = null;
    var task_cwd: ?[]const u8 = null;
    var task_desc: ?[]const u8 = null;
    var task_timeout_ms: ?u64 = null;
    var task_allow_failure: bool = false;
    var task_retry_max: u32 = 0;
    var task_retry_delay_ms: u64 = 0;
    var task_retry_backoff: bool = false;

    // Non-owning slices into content — addTask dupes them
    var task_deps = std.ArrayList([]const u8){};
    defer task_deps.deinit(allocator);
    var task_deps_serial = std.ArrayList([]const u8){};
    defer task_deps_serial.deinit(allocator);
    // Non-owning slices into content for env pairs — addTask dupes them
    var task_env = std.ArrayList([2][]const u8){};
    defer task_env.deinit(allocator);

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "[tasks.")) {
            // Flush pending task before starting new one
            if (current_task) |task_name| {
                if (task_cmd) |cmd| {
                    try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff);
                }
            }

            // Reset state — no freeing needed since these are non-owning slices
            task_deps.clearRetainingCapacity();
            task_deps_serial.clearRetainingCapacity();
            task_env.clearRetainingCapacity();
            task_cmd = null;
            task_cwd = null;
            task_desc = null;
            task_timeout_ms = null;
            task_allow_failure = false;
            task_retry_max = 0;
            task_retry_delay_ms = 0;
            task_retry_backoff = false;

            const start = "[tasks.".len;
            const end = std.mem.indexOf(u8, trimmed[start..], "]") orelse continue;
            // Non-owning slice into content
            current_task = trimmed[start..][0..end];
        } else if (std.mem.indexOf(u8, trimmed, "=")) |eq_idx| {
            const key = std.mem.trim(u8, trimmed[0..eq_idx], " \t");
            var value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            if (std.mem.eql(u8, key, "cmd")) {
                task_cmd = value;
            } else if (std.mem.eql(u8, key, "cwd")) {
                task_cwd = value;
            } else if (std.mem.eql(u8, key, "description")) {
                task_desc = value;
            } else if (std.mem.eql(u8, key, "timeout")) {
                task_timeout_ms = parseDurationMs(value);
            } else if (std.mem.eql(u8, key, "allow_failure")) {
                task_allow_failure = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, key, "deps")) {
                if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                    const deps_str = value[1 .. value.len - 1];
                    var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                    while (deps_it.next()) |dep| {
                        const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                        if (trimmed_dep.len > 0) {
                            // Non-owning slice — addTask will dupe
                            try task_deps.append(allocator, trimmed_dep);
                        }
                    }
                }
            } else if (std.mem.eql(u8, key, "deps_serial")) {
                if (std.mem.startsWith(u8, value, "[") and std.mem.endsWith(u8, value, "]")) {
                    const deps_str = value[1 .. value.len - 1];
                    var deps_it = std.mem.splitScalar(u8, deps_str, ',');
                    while (deps_it.next()) |dep| {
                        const trimmed_dep = std.mem.trim(u8, dep, " \t\"");
                        if (trimmed_dep.len > 0) {
                            // Non-owning slice — addTask will dupe
                            try task_deps_serial.append(allocator, trimmed_dep);
                        }
                    }
                }
            } else if (std.mem.eql(u8, key, "env")) {
                // Parse inline table: { KEY = "value", FOO = "bar" }
                // value has already had outer quotes stripped; strip braces now.
                const inner = std.mem.trim(u8, value, " \t");
                if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                    const pairs_str = inner[1 .. inner.len - 1];
                    var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                    while (pairs_it.next()) |pair_str| {
                        const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                        const env_key = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                        const env_val = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                        if (env_key.len > 0) {
                            // Non-owning slices into content — addTask will dupe
                            try task_env.append(allocator, .{ env_key, env_val });
                        }
                    }
                }
            } else if (std.mem.eql(u8, key, "retry")) {
                // Parse inline table: { max = 3, delay = "5s", backoff = "exponential" }
                const inner = std.mem.trim(u8, value, " \t");
                if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
                    const pairs_str = inner[1 .. inner.len - 1];
                    var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
                    while (pairs_it.next()) |pair_str| {
                        const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
                        const rkey = std.mem.trim(u8, pair_str[0..eq], " \t\"");
                        const rval = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
                        if (std.mem.eql(u8, rkey, "max")) {
                            task_retry_max = std.fmt.parseInt(u32, rval, 10) catch 0;
                        } else if (std.mem.eql(u8, rkey, "delay")) {
                            task_retry_delay_ms = parseDurationMs(rval) orelse 0;
                        } else if (std.mem.eql(u8, rkey, "backoff")) {
                            task_retry_backoff = std.mem.eql(u8, rval, "exponential");
                        }
                    }
                }
            }
        }
    }

    if (current_task) |task_name| {
        if (task_cmd) |cmd| {
            try addTaskImpl(&config, allocator, task_name, cmd, task_cwd, task_desc, task_deps.items, task_deps_serial.items, task_env.items, task_timeout_ms, task_allow_failure, task_retry_max, task_retry_delay_ms, task_retry_backoff);
        }
    }

    return config;
}

fn addTaskImpl(
    config: *Config,
    allocator: std.mem.Allocator,
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: []const []const u8,
    deps_serial: []const []const u8,
    env: []const [2][]const u8,
    timeout_ms: ?u64,
    allow_failure: bool,
    retry_max: u32,
    retry_delay_ms: u64,
    retry_backoff: bool,
) !void {
    const task_name = try allocator.dupe(u8, name);
    errdefer allocator.free(task_name);

    const task_cmd = try allocator.dupe(u8, cmd);
    errdefer allocator.free(task_cmd);

    const task_cwd = if (cwd) |c| try allocator.dupe(u8, c) else null;
    errdefer if (task_cwd) |c| allocator.free(c);

    const task_desc = if (description) |d| try allocator.dupe(u8, d) else null;
    errdefer if (task_desc) |d| allocator.free(d);

    const task_deps = try allocator.alloc([]const u8, deps.len);
    var deps_duped: usize = 0;
    errdefer {
        for (task_deps[0..deps_duped]) |d| allocator.free(d);
        allocator.free(task_deps);
    }
    for (deps, 0..) |dep, i| {
        task_deps[i] = try allocator.dupe(u8, dep);
        deps_duped += 1;
    }

    const task_deps_serial = try allocator.alloc([]const u8, deps_serial.len);
    var serial_duped: usize = 0;
    errdefer {
        for (task_deps_serial[0..serial_duped]) |d| allocator.free(d);
        allocator.free(task_deps_serial);
    }
    for (deps_serial, 0..) |dep, i| {
        task_deps_serial[i] = try allocator.dupe(u8, dep);
        serial_duped += 1;
    }

    // Dupe each env pair ([key, value]) independently for safe partial cleanup.
    const task_env = try allocator.alloc([2][]const u8, env.len);
    var env_duped: usize = 0;
    errdefer {
        for (task_env[0..env_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(task_env);
    }
    for (env, 0..) |pair, i| {
        task_env[i][0] = try allocator.dupe(u8, pair[0]);
        // If key dupe succeeds but value dupe fails, free the key we just duped.
        errdefer allocator.free(task_env[i][0]);
        task_env[i][1] = try allocator.dupe(u8, pair[1]);
        env_duped += 1;
    }

    const task = Task{
        .name = task_name,
        .cmd = task_cmd,
        .cwd = task_cwd,
        .description = task_desc,
        .deps = task_deps,
        .deps_serial = task_deps_serial,
        .env = task_env,
        .timeout_ms = timeout_ms,
        .allow_failure = allow_failure,
        .retry_max = retry_max,
        .retry_delay_ms = retry_delay_ms,
        .retry_backoff = retry_backoff,
    };

    try config.tasks.put(task_name, task);
}

test "parseDurationMs: various units" {
    try std.testing.expectEqual(@as(?u64, 500), parseDurationMs("500ms"));
    try std.testing.expectEqual(@as(?u64, 30_000), parseDurationMs("30s"));
    try std.testing.expectEqual(@as(?u64, 5 * 60_000), parseDurationMs("5m"));
    try std.testing.expectEqual(@as(?u64, 2 * 3_600_000), parseDurationMs("2h"));
    try std.testing.expectEqual(@as(?u64, null), parseDurationMs(""));
    try std.testing.expectEqual(@as(?u64, null), parseDurationMs("xyz"));
}

test "parse timeout and allow_failure from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\timeout = "5m"
        \\allow_failure = true
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(?u64, 5 * 60_000), task.timeout_ms);
    try std.testing.expect(task.allow_failure);
}

test "parse simple toml config" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\description = "Build the project"
        \\
        \\[tasks.test]
        \\cmd = "zig build test"
        \\deps = ["build"]
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    try std.testing.expect(config.tasks.count() == 2);

    const build_task = config.tasks.get("build").?;
    try std.testing.expectEqualStrings("zig build", build_task.cmd);
    try std.testing.expectEqualStrings("Build the project", build_task.description.?);

    const test_task = config.tasks.get("test").?;
    try std.testing.expectEqualStrings("zig build test", test_task.cmd);
    try std.testing.expect(test_task.deps.len == 1);
    try std.testing.expectEqualStrings("build", test_task.deps[0]);
}

test "parse deps_serial from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.backup]
        \\cmd = "echo backup"
        \\
        \\[tasks.migrate]
        \\cmd = "echo migrate"
        \\
        \\[tasks.verify]
        \\cmd = "echo verify"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\deps_serial = ["backup", "migrate", "verify"]
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const deploy = config.tasks.get("deploy").?;
    try std.testing.expectEqual(@as(usize, 3), deploy.deps_serial.len);
    try std.testing.expectEqualStrings("backup", deploy.deps_serial[0]);
    try std.testing.expectEqualStrings("migrate", deploy.deps_serial[1]);
    try std.testing.expectEqualStrings("verify", deploy.deps_serial[2]);
    try std.testing.expectEqual(@as(usize, 0), deploy.deps.len);
}

test "parse env from toml" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.build]
        \\cmd = "zig build"
        \\env = { NODE_ENV = "production", DEBUG = "false" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(usize, 2), task.env.len);

    // Find each key-value pair (order may vary since we split by comma)
    var found_node_env = false;
    var found_debug = false;
    for (task.env) |pair| {
        if (std.mem.eql(u8, pair[0], "NODE_ENV")) {
            try std.testing.expectEqualStrings("production", pair[1]);
            found_node_env = true;
        } else if (std.mem.eql(u8, pair[0], "DEBUG")) {
            try std.testing.expectEqualStrings("false", pair[1]);
            found_debug = true;
        }
    }
    try std.testing.expect(found_node_env);
    try std.testing.expect(found_debug);
}

test "addTaskWithEnv: programmatic env construction" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    const env_pairs = [_][2][]const u8{
        .{ "MY_VAR", "hello" },
        .{ "OTHER", "world" },
    };
    try config.addTaskWithEnv("env-task", "echo $MY_VAR", null, null, &[_][]const u8{}, &env_pairs);

    const task = config.tasks.get("env-task").?;
    try std.testing.expectEqual(@as(usize, 2), task.env.len);
    try std.testing.expectEqualStrings("MY_VAR", task.env[0][0]);
    try std.testing.expectEqualStrings("hello", task.env[0][1]);
    try std.testing.expectEqualStrings("OTHER", task.env[1][0]);
    try std.testing.expectEqualStrings("world", task.env[1][1]);
}

test "parse retry from toml inline table" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\retry = { max = 3, delay = "5s", backoff = "exponential" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("deploy").?;
    try std.testing.expectEqual(@as(u32, 3), task.retry_max);
    try std.testing.expectEqual(@as(u64, 5_000), task.retry_delay_ms);
    try std.testing.expect(task.retry_backoff);
}

test "parse retry with no backoff" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[tasks.fetch]
        \\cmd = "curl https://example.com"
        \\retry = { max = 2, delay = "1s" }
    ;

    var config = try parseToml(allocator, toml_content);
    defer config.deinit();

    const task = config.tasks.get("fetch").?;
    try std.testing.expectEqual(@as(u32, 2), task.retry_max);
    try std.testing.expectEqual(@as(u64, 1_000), task.retry_delay_ms);
    try std.testing.expect(!task.retry_backoff);
}

test "addTaskWithRetry: programmatic retry construction" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTaskWithRetry("retry-task", "flaky.sh", null, null, &[_][]const u8{}, 3, 500, true);

    const task = config.tasks.get("retry-task").?;
    try std.testing.expectEqual(@as(u32, 3), task.retry_max);
    try std.testing.expectEqual(@as(u64, 500), task.retry_delay_ms);
    try std.testing.expect(task.retry_backoff);
}

test "task defaults: retry fields are zero/false by default" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTask("plain", "echo hi", null, null, &[_][]const u8{});

    const task = config.tasks.get("plain").?;
    try std.testing.expectEqual(@as(u32, 0), task.retry_max);
    try std.testing.expectEqual(@as(u64, 0), task.retry_delay_ms);
    try std.testing.expect(!task.retry_backoff);
}
