const std = @import("std");

/// Plugin source type as parsed from TOML.
pub const SourceKind = enum { local, registry, git };

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

/// Resolve the filesystem path for a local plugin source.
/// Caller owns the returned slice.
fn resolveLocalPath(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    // If source starts with "./" or "/" treat as-is; otherwise look in ~/.zr/plugins/<source>/
    if (std.mem.startsWith(u8, source, "./") or
        std.mem.startsWith(u8, source, "/") or
        std.mem.startsWith(u8, source, "../"))
    {
        return allocator.dupe(u8, source);
    }
    const home = std.posix.getenv("HOME") orelse ".";
    return std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, source });
}

/// Find the shared library file inside a plugin directory.
/// Tries plugin.so, plugin.dylib, plugin.dll in order.
/// Caller owns the returned slice.
fn findLibInDir(allocator: std.mem.Allocator, dir_path: []const u8) ![]const u8 {
    const exts = [_][]const u8{ "so", "dylib", "dll" };
    for (exts) |ext| {
        const candidate = try std.fmt.allocPrint(allocator, "{s}/plugin.{s}", .{ dir_path, ext });
        if (std.fs.accessAbsolute(candidate, .{})) |_| {
            return candidate;
        } else |_| {
            allocator.free(candidate);
        }
    }
    return LoadError.LibraryNotFound;
}

/// Load a single native plugin from a local path.
/// `cfg` must outlive the returned Plugin (name slice is duped).
pub fn loadNative(allocator: std.mem.Allocator, cfg: *const PluginConfig) !Plugin {
    const base_path = try resolveLocalPath(allocator, cfg.source);
    defer allocator.free(base_path);

    // Check if base_path itself is a shared library file.
    const lib_path = blk: {
        const is_lib = std.mem.endsWith(u8, base_path, ".so") or
            std.mem.endsWith(u8, base_path, ".dylib") or
            std.mem.endsWith(u8, base_path, ".dll");
        if (is_lib) {
            break :blk try allocator.dupe(u8, base_path);
        } else {
            break :blk try findLibInDir(allocator, base_path);
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
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PluginRegistry {
        return .{
            .plugins = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginRegistry) void {
        for (self.plugins.items) |*p| p.deinit(self.allocator);
        self.plugins.deinit(self.allocator);
    }

    /// Load all local-source plugins from the provided config list.
    /// Non-local sources (registry, git) are skipped with a warning printed to `w`.
    pub fn loadAll(
        self: *PluginRegistry,
        configs: []const PluginConfig,
        w: *std.Io.Writer,
    ) !void {
        for (configs) |*cfg| {
            switch (cfg.kind) {
                .local => {
                    const plugin = loadNative(self.allocator, cfg) catch |err| {
                        try w.print("[plugin] warning: failed to load '{s}': {s}\n", .{
                            cfg.name, @errorName(err),
                        });
                        continue;
                    };
                    try self.plugins.append(self.allocator, plugin);
                },
                .registry, .git => {
                    try w.print("[plugin] info: '{s}' source kind '{s}' not yet supported — skipping\n", .{
                        cfg.name, @tagName(cfg.kind),
                    });
                },
            }
        }
    }

    /// Call on_init for all loaded plugins.
    pub fn callInit(self: *PluginRegistry) void {
        for (self.plugins.items) |*p| {
            if (p.on_init) |f| f();
        }
    }

    /// Call on_before_task for all loaded plugins.
    pub fn callBeforeTask(self: *PluginRegistry, task_name: []const u8) void {
        for (self.plugins.items) |*p| {
            if (p.on_before_task) |f| f(task_name.ptr, task_name.len);
        }
    }

    /// Call on_after_task for all loaded plugins.
    pub fn callAfterTask(self: *PluginRegistry, task_name: []const u8, exit_code: c_int) void {
        for (self.plugins.items) |*p| {
            if (p.on_after_task) |f| f(task_name.ptr, task_name.len, exit_code);
        }
    }

    /// Number of successfully loaded plugins.
    pub fn count(self: *const PluginRegistry) usize {
        return self.plugins.items.len;
    }
};

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

test "PluginRegistry.loadAll skips registry/git sources" {
    const allocator = std.testing.allocator;
    var reg = PluginRegistry.init(allocator);
    defer reg.deinit();

    const configs = [_]PluginConfig{
        .{
            .name = "myreg",
            .kind = .registry,
            .source = "zr/docker@1.0.0",
            .config = &.{},
        },
        .{
            .name = "mygit",
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
    try std.testing.expectEqual(@as(usize, 0), reg.count());
}

test "resolveLocalPath: absolute path returned as-is" {
    const allocator = std.testing.allocator;
    const path = try resolveLocalPath(allocator, "/usr/lib/plugin.so");
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/usr/lib/plugin.so", path);
}

test "resolveLocalPath: relative ./ path returned as-is" {
    const allocator = std.testing.allocator;
    const path = try resolveLocalPath(allocator, "./plugins/myplugin");
    defer allocator.free(path);
    try std.testing.expectEqualStrings("./plugins/myplugin", path);
}

test "resolveLocalPath: bare name expands to ~/.zr/plugins/<name>" {
    const allocator = std.testing.allocator;
    const home = std.posix.getenv("HOME") orelse ".";
    const path = try resolveLocalPath(allocator, "myplugin");
    defer allocator.free(path);
    const expected = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/myplugin", .{home});
    defer allocator.free(expected);
    try std.testing.expectEqualStrings(expected, path);
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
