const std = @import("std");
const platform = @import("../util/platform.zig");
const cache_store = @import("../cache/store.zig");

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
// docker plugin — Docker build/push operations with layer cache optimization
// ---------------------------------------------------------------------------

pub const builtin_docker = @import("builtin_docker.zig");
pub const DockerPlugin = builtin_docker.DockerPlugin;

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

/// Kind-specific runtime state for built-in plugins.
const BuiltinState = union(enum) {
    none: void,
    cache: struct {
        store: cache_store.CacheStore,
        /// Maximum age in seconds before a cache entry is considered stale (0 = no expiry).
        max_age_seconds: u64,
    },
};

/// A loaded built-in plugin that implements the same hook interface as native plugins.
pub const BuiltinHandle = struct {
    name: []const u8,
    kind: BuiltinKind,
    allocator: std.mem.Allocator,
    /// Kind-specific runtime state (initialized in onInit).
    state: BuiltinState = .none,

    /// Optional config pairs passed from the [plugins.NAME] config block.
    config: [][2][]const u8,

    pub const BuiltinKind = enum { env, git, notify, cache, docker };

    pub fn deinit(self: *BuiltinHandle) void {
        // Clean up kind-specific state.
        switch (self.state) {
            .cache => |*s| s.store.deinit(),
            .none => {},
        }
        self.allocator.free(self.name);
        for (self.config) |pair| {
            self.allocator.free(pair[0]);
            self.allocator.free(pair[1]);
        }
        self.allocator.free(self.config);
    }

    /// Called when the plugin is initialized (after config is loaded).
    /// The env plugin auto-loads .env files specified in config.
    /// The cache plugin initializes the cache store and optionally clears stale entries.
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
            .cache => {
                // Initialize the CacheStore.
                // Config keys:
                //   dir            — custom cache directory path (optional)
                //   max_age_seconds — evict entries older than this (0 = no eviction)
                //   clear_on_start  — if "true", wipe all cache entries on init
                var store = cache_store.CacheStore.init(self.allocator) catch return;

                const clear_on_start = self.configBool("clear_on_start", false);
                if (clear_on_start) {
                    _ = store.clearAll() catch {};
                }

                const max_age: u64 = blk: {
                    const val = self.configValue("max_age_seconds") orelse break :blk 0;
                    break :blk std.fmt.parseInt(u64, val, 10) catch 0;
                };

                self.state = .{ .cache = .{ .store = store, .max_age_seconds = max_age } };
            },
            .docker => {
                // Verify Docker daemon is available
                const available = DockerPlugin.onInit(self.allocator, null) catch false;
                if (!available) {
                    // Docker not available - silently continue (user will get error when trying to run docker commands)
                }
            },
            else => {},
        }
    }

    /// Called before a task runs.
    /// The cache plugin evicts stale entries if max_age_seconds is configured.
    pub fn onBeforeTask(self: *BuiltinHandle, task_name: []const u8) void {
        _ = task_name;
        switch (self.kind) {
            .cache => {
                // Evict expired cache entries if max_age_seconds > 0.
                if (self.state != .cache) return;
                const cs = &self.state.cache;
                if (cs.max_age_seconds == 0) return;
                evictStaleEntries(&cs.store, self.allocator, cs.max_age_seconds) catch {};
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

/// Evict cache entries older than max_age_seconds by checking file modification time.
fn evictStaleEntries(store: *cache_store.CacheStore, allocator: std.mem.Allocator, max_age_seconds: u64) !void {
    var dir = std.fs.cwd().openDir(store.dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    // Collect stale file names first to avoid iterator invalidation.
    var stale = std.ArrayList([]u8){};
    defer {
        for (stale.items) |n| allocator.free(n);
        stale.deinit(allocator);
    }

    const now_ns: i128 = std.time.nanoTimestamp();
    const max_age_ns: i128 = @as(i128, max_age_seconds) * std.time.ns_per_s;

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".ok")) continue;

        const stat = dir.statFile(entry.name) catch continue;
        const age_ns = now_ns - stat.mtime;
        if (age_ns > max_age_ns) {
            const name_copy = try allocator.dupe(u8, entry.name);
            try stale.append(allocator, name_copy);
        }
    }

    for (stale.items) |name| {
        dir.deleteFile(name) catch {};
    }
}

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
    const val = platform.getenv("ZR_TEST_BUILTIN_ENV_VAR");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("hello_builtin", val.?);
}

test "cache plugin: onInit initializes CacheStore" {
    const allocator = std.testing.allocator;
    const config: [][2][]const u8 = &.{};

    var handle = (try loadBuiltin(allocator, "cache", config)) orelse return error.TestExpectedHandle;
    defer handle.deinit();

    try std.testing.expectEqual(BuiltinHandle.BuiltinKind.cache, handle.kind);
    // Before onInit, state should be .none
    try std.testing.expect(handle.state == .none);

    handle.onInit();

    // After onInit, state should be .cache with a valid store
    try std.testing.expect(handle.state == .cache);
    try std.testing.expectEqual(@as(u64, 0), handle.state.cache.max_age_seconds);
}

test "cache plugin: onInit with max_age_seconds config" {
    const allocator = std.testing.allocator;
    var config_arr = [_][2][]const u8{
        .{ "max_age_seconds", "3600" },
    };
    const config: [][2][]const u8 = &config_arr;

    var handle = (try loadBuiltin(allocator, "cache", config)) orelse return error.TestExpectedHandle;
    defer handle.deinit();

    handle.onInit();

    try std.testing.expect(handle.state == .cache);
    try std.testing.expectEqual(@as(u64, 3600), handle.state.cache.max_age_seconds);
}

test "cache plugin: onInit with clear_on_start removes entries" {
    const allocator = std.testing.allocator;

    // First, create a cache entry to be cleared.
    {
        var store = try cache_store.CacheStore.init(allocator);
        defer store.deinit();
        const key = try cache_store.CacheStore.computeKey(allocator, "zr-cache-plugin-clear-test", null);
        defer allocator.free(key);
        try store.recordHit(key);
        try std.testing.expect(store.hasHit(key));
    }

    var config_arr = [_][2][]const u8{
        .{ "clear_on_start", "true" },
    };
    const config: [][2][]const u8 = &config_arr;

    var handle = (try loadBuiltin(allocator, "cache", config)) orelse return error.TestExpectedHandle;
    defer handle.deinit();

    handle.onInit();

    // After clear_on_start, the previously recorded entry should be gone.
    try std.testing.expect(handle.state == .cache);
    const store = &handle.state.cache.store;
    const key = try cache_store.CacheStore.computeKey(allocator, "zr-cache-plugin-clear-test", null);
    defer allocator.free(key);
    try std.testing.expect(!store.hasHit(key));
}

test "cache plugin: onBeforeTask with no max_age is a no-op" {
    const allocator = std.testing.allocator;
    const config: [][2][]const u8 = &.{};

    var handle = (try loadBuiltin(allocator, "cache", config)) orelse return error.TestExpectedHandle;
    defer handle.deinit();

    handle.onInit();
    // Should not panic or error — max_age_seconds == 0 means no eviction.
    handle.onBeforeTask("my-task");
}
