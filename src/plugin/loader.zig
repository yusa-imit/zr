const std = @import("std");
const builtin_mod = @import("builtin.zig");
pub const install = @import("install.zig");
pub const registry = @import("registry.zig");

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

/// Result entry from searchInstalledPlugins.
pub const SearchResult = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SearchResult) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        self.allocator.free(self.author);
    }
};

/// Search installed plugins by name or description substring (case-insensitive).
/// Returns matching SearchResult entries (caller must deinit each and free the slice).
pub fn searchInstalledPlugins(allocator: std.mem.Allocator, query: []const u8) ![]SearchResult {
    const names = try install.listInstalledPlugins(allocator);
    defer {
        for (names) |n| allocator.free(n);
        allocator.free(names);
    }

    var results: std.ArrayListUnmanaged(SearchResult) = .empty;
    errdefer {
        for (results.items) |*r| r.deinit();
        results.deinit(allocator);
    }

    const home = std.posix.getenv("HOME") orelse ".";

    for (names) |name| {
        const plugin_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, name });
        defer allocator.free(plugin_dir);

        // Read metadata (name, version, description, author).
        const meta_opt = try install.readPluginMeta(allocator, plugin_dir);
        const display_name = if (meta_opt) |m| m.name else "";
        const version = if (meta_opt) |m| m.version else "";
        const description = if (meta_opt) |m| m.description else "";
        const author = if (meta_opt) |m| m.author else "";

        // Match query (case-insensitive) against plugin dir name, display name, and description.
        const matches = blk: {
            if (query.len == 0) break :blk true;
            // Simple case-insensitive substring check by lowercasing both sides.
            var lower_query_buf: [256]u8 = undefined;
            const lq = lower_query_buf[0..@min(query.len, lower_query_buf.len)];
            for (lq, query[0..lq.len]) |*dst, c| dst.* = std.ascii.toLower(c);

            // Check dir name.
            var name_buf: [256]u8 = undefined;
            const ln = name_buf[0..@min(name.len, name_buf.len)];
            for (ln, name[0..ln.len]) |*dst, c| dst.* = std.ascii.toLower(c);
            if (std.mem.indexOf(u8, ln, lq) != null) break :blk true;

            // Check display name.
            if (display_name.len > 0) {
                var dn_buf: [256]u8 = undefined;
                const ldn = dn_buf[0..@min(display_name.len, dn_buf.len)];
                for (ldn, display_name[0..ldn.len]) |*dst, c| dst.* = std.ascii.toLower(c);
                if (std.mem.indexOf(u8, ldn, lq) != null) break :blk true;
            }

            // Check description.
            if (description.len > 0) {
                var desc_buf: [512]u8 = undefined;
                const ldesc = desc_buf[0..@min(description.len, desc_buf.len)];
                for (ldesc, description[0..ldesc.len]) |*dst, c| dst.* = std.ascii.toLower(c);
                if (std.mem.indexOf(u8, ldesc, lq) != null) break :blk true;
            }

            break :blk false;
        };

        if (matches) {
            const result_name = try allocator.dupe(u8, if (display_name.len > 0) display_name else name);
            const result_version = try allocator.dupe(u8, version);
            const result_description = try allocator.dupe(u8, description);
            const result_author = try allocator.dupe(u8, author);
            // Free meta after duplication.
            var meta_copy = meta_opt;
            if (meta_copy) |*m| m.deinit();
            try results.append(allocator, SearchResult{
                .name = result_name,
                .version = result_version,
                .description = result_description,
                .author = result_author,
                .allocator = allocator,
            });
        } else {
            var meta_copy = meta_opt;
            if (meta_copy) |*m| m.deinit();
        }
    }

    return results.toOwnedSlice(allocator);
}

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

// ---------------------------------------------------------------------------
// searchInstalledPlugins tests
// ---------------------------------------------------------------------------

test "searchInstalledPlugins: empty query returns all (or empty if none installed)" {
    const allocator = std.testing.allocator;
    const results = try searchInstalledPlugins(allocator, "");
    defer {
        for (results) |*r| {
            var rc = r.*;
            rc.deinit();
        }
        allocator.free(results);
    }
    // No assertion on count — HOME-dependent. Just verify no crash and valid structs.
    for (results) |r| {
        _ = r.name.len;
    }
}

test "searchInstalledPlugins: unlikely query returns empty slice" {
    const allocator = std.testing.allocator;
    const results = try searchInstalledPlugins(allocator, "zr-test-no-match-zzz999xyzxyz");
    defer {
        for (results) |*r| {
            var rc = r.*;
            rc.deinit();
        }
        allocator.free(results);
    }
    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "searchInstalledPlugins: finds installed plugin by name" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-search-loader-88882";

    // Create and install a test plugin.
    var tmp_src = std.testing.tmpDir(.{});
    defer tmp_src.cleanup();
    try tmp_src.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"findable\"\nversion = \"2.0.0\"\ndescription = \"Find me plugin\"\nauthor = \"test\"\n",
    });
    try tmp_src.dir.writeFile(.{ .sub_path = "plugin.dylib", .data = "dummy" });
    const src = try tmp_src.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src);

    install.removePlugin(allocator, plugin_name) catch {};
    const dest = try install.installLocalPlugin(allocator, src, plugin_name);
    allocator.free(dest);
    defer install.removePlugin(allocator, plugin_name) catch {};

    // Search by dir name substring.
    const results = try searchInstalledPlugins(allocator, "search-loader");
    defer {
        for (results) |*r| {
            var rc = r.*;
            rc.deinit();
        }
        allocator.free(results);
    }

    try std.testing.expect(results.len >= 1);
    // The first matching result should have the display name from plugin.toml.
    var found = false;
    for (results) |r| {
        if (std.mem.eql(u8, r.name, "findable")) {
            found = true;
            try std.testing.expectEqualStrings("2.0.0", r.version);
            try std.testing.expectEqualStrings("Find me plugin", r.description);
            break;
        }
    }
    try std.testing.expect(found);
}

test "searchInstalledPlugins: case-insensitive match on description" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-search-case-88883";

    var tmp_src = std.testing.tmpDir(.{});
    defer tmp_src.cleanup();
    try tmp_src.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"cased\"\nversion = \"1.0.0\"\ndescription = \"Docker Integration Helper\"\nauthor = \"\"\n",
    });
    try tmp_src.dir.writeFile(.{ .sub_path = "plugin.dylib", .data = "dummy" });
    const src = try tmp_src.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src);

    install.removePlugin(allocator, plugin_name) catch {};
    const dest = try install.installLocalPlugin(allocator, src, plugin_name);
    allocator.free(dest);
    defer install.removePlugin(allocator, plugin_name) catch {};

    // Search using lowercase query against uppercase description word.
    const results = try searchInstalledPlugins(allocator, "docker");
    defer {
        for (results) |*r| {
            var rc = r.*;
            rc.deinit();
        }
        allocator.free(results);
    }

    var found = false;
    for (results) |r| {
        if (std.mem.eql(u8, r.name, "cased")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}
