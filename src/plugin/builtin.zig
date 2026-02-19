const std = @import("std");

/// Built-in plugin names recognized by zr.
pub const BUILTIN_NAMES = [_][]const u8{ "env", "git", "notify", "cache", "docker" };

/// Check if a source string refers to a built-in plugin.
/// Format: "builtin:<name>" e.g. "builtin:env"
pub fn isBuiltin(source: []const u8) bool {
    return std.mem.startsWith(u8, source, "builtin:");
}

/// Extract the built-in name from a source string.
/// Returns empty string if not a builtin source.
pub fn builtinName(source: []const u8) []const u8 {
    if (!isBuiltin(source)) return "";
    return source["builtin:".len..];
}

/// Check if a name is a known built-in plugin.
pub fn isKnownBuiltin(name: []const u8) bool {
    for (BUILTIN_NAMES) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// env plugin — .env file loading and environment variable management
// ---------------------------------------------------------------------------

pub const builtin_env = @import("builtin_env.zig");
pub const EnvPlugin = builtin_env.EnvPlugin;

// ---------------------------------------------------------------------------
// git plugin — changed file detection, branch info, commit message parsing
// ---------------------------------------------------------------------------

pub const builtin_git = @import("builtin_git.zig");
pub const GitPlugin = builtin_git.GitPlugin;

// ---------------------------------------------------------------------------
// notify plugin — webhook notifications (Slack, Discord, generic)
// ---------------------------------------------------------------------------

pub const NotifyPlugin = struct {
    pub const WebhookKind = enum { slack, discord, generic };

    /// Detect the webhook kind from a URL.
    pub fn detectKind(url: []const u8) WebhookKind {
        if (std.mem.indexOf(u8, url, "hooks.slack.com") != null) return .slack;
        if (std.mem.indexOf(u8, url, "discord.com/api/webhooks") != null) return .discord;
        return .generic;
    }

    /// Build the JSON payload for a webhook notification.
    /// Caller owns the returned slice.
    pub fn buildPayload(
        allocator: std.mem.Allocator,
        kind: WebhookKind,
        message: []const u8,
        username: ?[]const u8,
    ) ![]const u8 {
        return switch (kind) {
            .slack => blk: {
                const name = username orelse "zr";
                break :blk std.fmt.allocPrint(allocator,
                    "{{\"username\":\"{s}\",\"text\":\"{s}\"}}",
                    .{ name, message });
            },
            .discord => blk: {
                const name = username orelse "zr";
                break :blk std.fmt.allocPrint(allocator,
                    "{{\"username\":\"{s}\",\"content\":\"{s}\"}}",
                    .{ name, message });
            },
            .generic => blk: {
                break :blk std.fmt.allocPrint(allocator,
                    "{{\"text\":\"{s}\"}}",
                    .{message});
            },
        };
    }

    /// Send a webhook notification by executing `curl` as a subprocess.
    /// Returns true on success (curl exit code 0).
    pub fn sendWebhook(
        allocator: std.mem.Allocator,
        url: []const u8,
        message: []const u8,
        username: ?[]const u8,
    ) !bool {
        const kind = detectKind(url);
        const payload = try buildPayload(allocator, kind, message, username);
        defer allocator.free(payload);

        const argv = [_][]const u8{
            "curl",
            "-s",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", payload,
            url,
        };

        var child = std.process.Child.init(&argv, allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return false;
        const result = try child.wait();
        return switch (result) {
            .Exited => |code| code == 0,
            else => false,
        };
    }
};

// ---------------------------------------------------------------------------
// BuiltinHandle — unified interface for built-in plugin hooks
// ---------------------------------------------------------------------------

/// A loaded built-in plugin that implements the same hook interface as native plugins.
pub const BuiltinHandle = struct {
    name: []const u8,
    kind: BuiltinKind,
    allocator: std.mem.Allocator,

    /// Optional config pairs passed from the [plugins.NAME] config block.
    config: [][2][]const u8,

    pub const BuiltinKind = enum { env, git, notify, cache, docker };

    pub fn deinit(self: *BuiltinHandle) void {
        self.allocator.free(self.name);
        for (self.config) |pair| {
            self.allocator.free(pair[0]);
            self.allocator.free(pair[1]);
        }
        self.allocator.free(self.config);
    }

    /// Called when the plugin is initialized (after config is loaded).
    /// The env plugin auto-loads .env files specified in config.
    pub fn onInit(self: *BuiltinHandle) void {
        switch (self.kind) {
            .env => {
                // Look for env_file config key; load it if present.
                for (self.config) |pair| {
                    if (std.mem.eql(u8, pair[0], "env_file")) {
                        var arena = std.heap.ArenaAllocator.init(self.allocator);
                        defer arena.deinit();
                        const overwrite = self.configBool("overwrite", false);
                        EnvPlugin.loadDotEnv(arena.allocator(), pair[1], overwrite) catch {};
                    }
                }
            },
            else => {},
        }
    }

    /// Called before a task runs.
    pub fn onBeforeTask(self: *BuiltinHandle, task_name: []const u8) void {
        switch (self.kind) {
            .git => {
                // Log branch info to stdout if verbose config is set.
                _ = task_name;
            },
            else => {},
        }
    }

    /// Called after a task completes with its exit code.
    pub fn onAfterTask(self: *BuiltinHandle, task_name: []const u8, exit_code: i32) void {
        switch (self.kind) {
            .notify => {
                // Send webhook if configured and (optionally) only on failure.
                const on_failure_only = self.configBool("on_failure_only", false);
                if (on_failure_only and exit_code == 0) return;

                const url = self.configValue("webhook_url") orelse return;
                // Use a fixed format: prepend optional custom prefix, then "task '<name>' exit <code>".
                const prefix = self.configValue("message") orelse "zr";

                var arena = std.heap.ArenaAllocator.init(self.allocator);
                defer arena.deinit();

                const msg = std.fmt.allocPrint(
                    arena.allocator(),
                    "{s}: task '{s}' finished (exit {d})",
                    .{ prefix, task_name, exit_code },
                ) catch return;
                const username = self.configValue("username");
                _ = NotifyPlugin.sendWebhook(arena.allocator(), url, msg, username) catch {};
            },
            else => {},
        }
    }

    // --- config helpers ---

    fn configValue(self: *const BuiltinHandle, key: []const u8) ?[]const u8 {
        for (self.config) |pair| {
            if (std.mem.eql(u8, pair[0], key)) return pair[1];
        }
        return null;
    }

    fn configBool(self: *const BuiltinHandle, key: []const u8, default: bool) bool {
        const val = self.configValue(key) orelse return default;
        return std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "yes");
    }
};

/// Create a BuiltinHandle for the given name and config.
/// Returns null if the name is not a known built-in.
/// Caller must call deinit() on the returned handle.
pub fn loadBuiltin(
    allocator: std.mem.Allocator,
    name: []const u8,
    config: [][2][]const u8,
) !?BuiltinHandle {
    const kind: BuiltinHandle.BuiltinKind = blk: {
        if (std.mem.eql(u8, name, "env")) break :blk .env;
        if (std.mem.eql(u8, name, "git")) break :blk .git;
        if (std.mem.eql(u8, name, "notify")) break :blk .notify;
        if (std.mem.eql(u8, name, "cache")) break :blk .cache;
        if (std.mem.eql(u8, name, "docker")) break :blk .docker;
        return null;
    };

    // Dupe the config pairs.
    const duped_config = try allocator.alloc([2][]const u8, config.len);
    var duped_count: usize = 0;
    errdefer {
        for (duped_config[0..duped_count]) |p| {
            allocator.free(p[0]);
            allocator.free(p[1]);
        }
        allocator.free(duped_config);
    }
    for (config, 0..) |pair, i| {
        duped_config[i][0] = try allocator.dupe(u8, pair[0]);
        duped_config[i][1] = try allocator.dupe(u8, pair[1]);
        duped_count = i + 1;
    }

    return BuiltinHandle{
        .name = try allocator.dupe(u8, name),
        .kind = kind,
        .allocator = allocator,
        .config = duped_config,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "isBuiltin: recognizes builtin: prefix" {
    try std.testing.expect(isBuiltin("builtin:env"));
    try std.testing.expect(isBuiltin("builtin:git"));
    try std.testing.expect(!isBuiltin("local:./plugin"));
    try std.testing.expect(!isBuiltin("git:https://example.com"));
    try std.testing.expect(!isBuiltin("env"));
}

test "builtinName: extracts name after prefix" {
    try std.testing.expectEqualStrings("env", builtinName("builtin:env"));
    try std.testing.expectEqualStrings("notify", builtinName("builtin:notify"));
    try std.testing.expectEqualStrings("", builtinName("local:env"));
}

test "isKnownBuiltin: all expected names recognized" {
    try std.testing.expect(isKnownBuiltin("env"));
    try std.testing.expect(isKnownBuiltin("git"));
    try std.testing.expect(isKnownBuiltin("notify"));
    try std.testing.expect(isKnownBuiltin("cache"));
    try std.testing.expect(isKnownBuiltin("docker"));
    try std.testing.expect(!isKnownBuiltin("slack"));
    try std.testing.expect(!isKnownBuiltin("unknown"));
}

test "NotifyPlugin.detectKind: identifies slack and discord URLs" {
    try std.testing.expectEqual(NotifyPlugin.WebhookKind.slack, NotifyPlugin.detectKind("https://hooks.slack.com/services/T0/B0/abc"));
    try std.testing.expectEqual(NotifyPlugin.WebhookKind.discord, NotifyPlugin.detectKind("https://discord.com/api/webhooks/123/token"));
    try std.testing.expectEqual(NotifyPlugin.WebhookKind.generic, NotifyPlugin.detectKind("https://example.com/webhook"));
}

test "NotifyPlugin.buildPayload: slack format" {
    const allocator = std.testing.allocator;
    const payload = try NotifyPlugin.buildPayload(allocator, .slack, "hello world", "zr-bot");
    defer allocator.free(payload);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"username\":\"zr-bot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"text\":\"hello world\"") != null);
}

test "NotifyPlugin.buildPayload: discord format" {
    const allocator = std.testing.allocator;
    const payload = try NotifyPlugin.buildPayload(allocator, .discord, "build done", null);
    defer allocator.free(payload);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"content\":\"build done\"") != null);
}

test "NotifyPlugin.buildPayload: generic format" {
    const allocator = std.testing.allocator;
    const payload = try NotifyPlugin.buildPayload(allocator, .generic, "ping", null);
    defer allocator.free(payload);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"text\":\"ping\"") != null);
}

test "loadBuiltin: known names return handles" {
    const allocator = std.testing.allocator;
    const config: [][2][]const u8 = &.{};

    var env_handle = (try loadBuiltin(allocator, "env", config)) orelse return error.TestExpectedHandle;
    defer env_handle.deinit();
    try std.testing.expectEqual(BuiltinHandle.BuiltinKind.env, env_handle.kind);

    var git_handle = (try loadBuiltin(allocator, "git", config)) orelse return error.TestExpectedHandle;
    defer git_handle.deinit();
    try std.testing.expectEqual(BuiltinHandle.BuiltinKind.git, git_handle.kind);

    var notify_handle = (try loadBuiltin(allocator, "notify", config)) orelse return error.TestExpectedHandle;
    defer notify_handle.deinit();
    try std.testing.expectEqual(BuiltinHandle.BuiltinKind.notify, notify_handle.kind);
}

test "loadBuiltin: unknown name returns null" {
    const allocator = std.testing.allocator;
    const config: [][2][]const u8 = &.{};
    const result = try loadBuiltin(allocator, "unknown-plugin-xyz", config);
    try std.testing.expectEqual(@as(?BuiltinHandle, null), result);
}

test "loadBuiltin: config pairs are duped" {
    const allocator = std.testing.allocator;
    var config_arr = [_][2][]const u8{
        .{ "webhook_url", "https://example.com/hook" },
        .{ "on_failure_only", "true" },
    };
    const config: [][2][]const u8 = &config_arr;

    var handle = (try loadBuiltin(allocator, "notify", config)) orelse return error.TestExpectedHandle;
    defer handle.deinit();

    try std.testing.expectEqual(@as(usize, 2), handle.config.len);
    try std.testing.expectEqualStrings("webhook_url", handle.config[0][0]);
    try std.testing.expectEqualStrings("https://example.com/hook", handle.config[0][1]);
    try std.testing.expectEqualStrings("on_failure_only", handle.config[1][0]);
    try std.testing.expectEqualStrings("true", handle.config[1][1]);
}

test "BuiltinHandle.onInit: env plugin loads .env file" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = ".env",
        .data = "ZR_TEST_BUILTIN_ENV_VAR=hello_builtin\n",
    });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const env_file_path = try std.fmt.allocPrint(allocator, "{s}/.env", .{tmp_path});
    defer allocator.free(env_file_path);

    var config_arr = [_][2][]const u8{
        .{ "env_file", env_file_path },
    };
    const config: [][2][]const u8 = &config_arr;

    var handle = (try loadBuiltin(allocator, "env", config)) orelse return error.TestExpectedHandle;
    defer handle.deinit();

    handle.onInit();

    // The variable should now be set in the environment.
    const val = std.posix.getenv("ZR_TEST_BUILTIN_ENV_VAR");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("hello_builtin", val.?);
}
