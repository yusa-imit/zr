const std = @import("std");
const builtin_mod = @import("builtin.zig");
pub const install = @import("install.zig");
pub const registry = @import("registry.zig");
pub const search = @import("search.zig");

/// Plugin source type as parsed from TOML.
pub const SourceKind = enum { local, registry, git, builtin };

/// Plugin configuration entry from [plugins.NAME] in zr.toml.
pub const PluginConfig = struct {
    /// Plugin identifier (the TOML key under [plugins.*]).
    name: []const u8,
    /// Source kind: local path, registry ref, or git URL.
    kind: SourceKind,
    /// Source value: path, "name@version", or git URL.
    source: []const u8,
    /// Optional key=value config entries passed to the plugin.
    config: [][2][]const u8,

    pub fn deinit(self: *PluginConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.source);
        for (self.config) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.config);
    }
};

/// The C-ABI hook function types that a native plugin must export.
pub const OnInitFn = *const fn () callconv(.c) void;
pub const OnBeforeTaskFn = *const fn ([*c]const u8, usize) callconv(.c) void;
pub const OnAfterTaskFn = *const fn ([*c]const u8, usize, c_int) callconv(.c) void;

/// Metadata and lifecycle hooks loaded from a native shared library.
pub const Plugin = struct {
    /// Plugin name (from PluginConfig).
    name: []const u8,
    /// Underlying dynamic library handle.
    lib: std.DynLib,
    /// Optional lifecycle hooks resolved from the library.
    on_init: ?OnInitFn,
    on_before_task: ?OnBeforeTaskFn,
    on_after_task: ?OnAfterTaskFn,

    /// Unload the shared library and release the name slice.
    pub fn deinit(self: *Plugin, allocator: std.mem.Allocator) void {
        self.lib.close();
        allocator.free(self.name);
    }
};

pub const LoadError = error{
    LibraryNotFound,
    InvalidPlugin,
};

// ---------------------------------------------------------------------------
// Re-exports from registry.zig for backward compatibility
// ---------------------------------------------------------------------------

pub const RegistryRef = registry.RegistryRef;
pub const parseRegistryRef = registry.parseRegistryRef;
pub const RegistryInstallError = registry.RegistryInstallError;
pub const default_registry_base = registry.default_registry_base;
pub const installRegistryPlugin = registry.installRegistryPlugin;
pub const readRegistryRef = registry.readRegistryRef;

/// Load a single native plugin from a local path.
/// `cfg` must outlive the returned Plugin (name slice is duped).
pub fn loadNative(allocator: std.mem.Allocator, cfg: *const PluginConfig) !Plugin {
    const base_path = try install.resolveLocalPath(allocator, cfg.source);
    defer allocator.free(base_path);

    // Check if base_path itself is a shared library file.
    const lib_path = blk: {
        const is_lib = std.mem.endsWith(u8, base_path, ".so") or
            std.mem.endsWith(u8, base_path, ".dylib") or
            std.mem.endsWith(u8, base_path, ".dll");
        if (is_lib) {
            break :blk try allocator.dupe(u8, base_path);
        } else {
            break :blk try install.findLibInDir(allocator, base_path);
        }
    };
    defer allocator.free(lib_path);

    var lib = std.DynLib.open(lib_path) catch return LoadError.LibraryNotFound;
    errdefer lib.close();

    // Resolve optional hooks — plugins are not required to implement all.
    const on_init = lib.lookup(OnInitFn, "zr_on_init");
    const on_before = lib.lookup(OnBeforeTaskFn, "zr_on_before_task");
    const on_after = lib.lookup(OnAfterTaskFn, "zr_on_after_task");

    return .{
        .name = try allocator.dupe(u8, cfg.name),
        .lib = lib,
        .on_init = on_init,
        .on_before_task = on_before,
        .on_after_task = on_after,
    };
}

/// Registry of loaded plugins for a session.
pub const PluginRegistry = struct {
    plugins: std.ArrayListUnmanaged(Plugin),
    builtins: std.ArrayListUnmanaged(builtin_mod.BuiltinHandle),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PluginRegistry {
        return .{
            .plugins = .empty,
            .builtins = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginRegistry) void {
        for (self.plugins.items) |*p| p.deinit(self.allocator);
        self.plugins.deinit(self.allocator);
        for (self.builtins.items) |*b| b.deinit();
        self.builtins.deinit(self.allocator);
    }

    /// Load all plugins from the provided config list.
    /// - builtin: loaded from the built-in plugin registry.
    /// - local: loaded directly from the source path.
    /// - git: loaded from ~/.zr/plugins/<name> if installed; warning if not.
    /// - registry: loaded from ~/.zr/plugins/<name> if installed; warning if not.
    pub fn loadAll(
        self: *PluginRegistry,
        configs: []const PluginConfig,
        w: *std.Io.Writer,
    ) !void {
        for (configs) |*cfg| {
            switch (cfg.kind) {
                .builtin => {
                    const handle = builtin_mod.loadBuiltin(self.allocator, cfg.source, cfg.config) catch |err| {
                        try w.print("[plugin] warning: failed to load builtin '{s}': {s}\n", .{
                            cfg.name, @errorName(err),
                        });
                        continue;
                    };
                    if (handle) |h| {
                        try self.builtins.append(self.allocator, h);
                    } else {
                        try w.print("[plugin] warning: unknown built-in plugin '{s}'\n  Hint: available built-ins: env, git, notify, cache, docker\n", .{cfg.source});
                    }
                },
                .local => {
                    const plugin = loadNative(self.allocator, cfg) catch |err| {
                        try w.print("[plugin] warning: failed to load '{s}': {s}\n", .{
                            cfg.name, @errorName(err),
                        });
                        continue;
                    };
                    try self.plugins.append(self.allocator, plugin);
                },
                .git, .registry => {
                    // For git/registry plugins, check if already installed in ~/.zr/plugins/<name>.
                    // If installed, load from there. Otherwise warn the user to install first.
                    const home = std.posix.getenv("HOME") orelse ".";
                    const installed_path = try std.fmt.allocPrint(self.allocator, "{s}/.zr/plugins/{s}", .{ home, cfg.name });
                    defer self.allocator.free(installed_path);

                    const is_installed = blk: {
                        std.fs.accessAbsolute(installed_path, .{}) catch {
                            break :blk false;
                        };
                        break :blk true;
                    };

                    if (is_installed) {
                        // Create a synthetic local config pointing at the installed path.
                        const synthetic = PluginConfig{
                            .name = cfg.name,
                            .kind = .local,
                            .source = installed_path,
                            .config = cfg.config,
                        };
                        const plugin = loadNative(self.allocator, &synthetic) catch |err| {
                            try w.print("[plugin] warning: failed to load installed '{s}': {s}\n", .{
                                cfg.name, @errorName(err),
                            });
                            continue;
                        };
                        try self.plugins.append(self.allocator, plugin);
                    } else {
                        const kind_str = if (cfg.kind == .registry) "registry" else "git";
                        try w.print("[plugin] info: '{s}' ({s}) is not installed — run 'zr plugin install {s}' first\n", .{
                            cfg.name, kind_str, cfg.source,
                        });
                    }
                },
            }
        }
    }

    /// Call on_init for all loaded plugins (native + built-in).
    pub fn callInit(self: *PluginRegistry) void {
        for (self.plugins.items) |*p| {
            if (p.on_init) |f| f();
        }
        for (self.builtins.items) |*b| b.onInit();
    }

    /// Call on_before_task for all loaded plugins (native + built-in).
    pub fn callBeforeTask(self: *PluginRegistry, task_name: []const u8) void {
        for (self.plugins.items) |*p| {
            if (p.on_before_task) |f| f(task_name.ptr, task_name.len);
        }
        for (self.builtins.items) |*b| b.onBeforeTask(task_name);
    }

    /// Call on_after_task for all loaded plugins (native + built-in).
    pub fn callAfterTask(self: *PluginRegistry, task_name: []const u8, exit_code: c_int) void {
        for (self.plugins.items) |*p| {
            if (p.on_after_task) |f| f(task_name.ptr, task_name.len, exit_code);
        }
        for (self.builtins.items) |*b| b.onAfterTask(task_name, @intCast(exit_code));
    }

    /// Number of successfully loaded plugins (native + built-in).
    pub fn count(self: *const PluginRegistry) usize {
        return self.plugins.items.len + self.builtins.items.len;
    }
};

// ---------------------------------------------------------------------------
// Plugin metadata (plugin.toml) — type defined in install.zig, re-exported here
// ---------------------------------------------------------------------------

pub const PluginMeta = install.PluginMeta;

// ---------------------------------------------------------------------------
// Re-exports from install.zig for backward compatibility
// ---------------------------------------------------------------------------

pub const InstallError = install.InstallError;
pub const GitInstallError = install.GitInstallError;
pub const GitUpdateError = install.GitUpdateError;
pub const installLocalPlugin = install.installLocalPlugin;
pub const installGitPlugin = install.installGitPlugin;
pub const removePlugin = install.removePlugin;
pub const updateLocalPlugin = install.updateLocalPlugin;
pub const updateGitPlugin = install.updateGitPlugin;
pub const listInstalledPlugins = install.listInstalledPlugins;
pub const readPluginMeta = install.readPluginMeta;

// ---------------------------------------------------------------------------
// Re-exports from search.zig for backward compatibility
// ---------------------------------------------------------------------------

pub const SearchResult = search.SearchResult;
pub const searchInstalledPlugins = search.searchInstalledPlugins;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "PluginConfig.deinit frees all memory" {
    const allocator = std.testing.allocator;

    var cfg = PluginConfig{
        .name = try allocator.dupe(u8, "myplugin"),
        .kind = .local,
        .source = try allocator.dupe(u8, "./plugins/myplugin"),
        .config = blk: {
            const pairs = try allocator.alloc([2][]const u8, 1);
            pairs[0][0] = try allocator.dupe(u8, "key");
            pairs[0][1] = try allocator.dupe(u8, "val");
            break :blk pairs;
        },
    };
    cfg.deinit(allocator);
    // If no memory is leaked, test allocator will pass.
}

test "PluginRegistry.init and deinit (empty)" {
    const allocator = std.testing.allocator;
    var reg = PluginRegistry.init(allocator);
    defer reg.deinit();
    try std.testing.expectEqual(@as(usize, 0), reg.count());
}

test "PluginRegistry.loadAll: uninstalled registry/git sources produce info message" {
    const allocator = std.testing.allocator;
    var reg = PluginRegistry.init(allocator);
    defer reg.deinit();

    // Use names unlikely to be installed on any test machine.
    const configs = [_]PluginConfig{
        .{
            .name = "zr-test-registry-notinstalled-77777",
            .kind = .registry,
            .source = "zr/docker@1.0.0",
            .config = &.{},
        },
        .{
            .name = "zr-test-git-notinstalled-77777",
            .kind = .git,
            .source = "https://github.com/user/plugin",
            .config = &.{},
        },
    };

    var buf: [4096]u8 = undefined;
    const devnull = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer devnull.close();
    var w = devnull.writer(&buf);

    try reg.loadAll(&configs, &w.interface);
    // Neither is installed, so neither should be loaded.
    try std.testing.expectEqual(@as(usize, 0), reg.count());
}

test "PluginRegistry.callInit, callBeforeTask, callAfterTask on empty registry" {
    const allocator = std.testing.allocator;
    var reg = PluginRegistry.init(allocator);
    defer reg.deinit();
    // Should be no-ops without panicking.
    reg.callInit();
    reg.callBeforeTask("build");
    reg.callAfterTask("build", 0);
}

