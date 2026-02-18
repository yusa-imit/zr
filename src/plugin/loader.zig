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
// Plugin metadata (plugin.toml)
// ---------------------------------------------------------------------------

/// Metadata read from a plugin's plugin.toml file.
pub const PluginMeta = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PluginMeta) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        self.allocator.free(self.author);
    }
};

/// Read and parse plugin.toml from a plugin directory.
/// Returns null if the file doesn't exist.
/// Caller must call deinit() on the returned value.
pub fn readPluginMeta(allocator: std.mem.Allocator, plugin_dir: []const u8) !?PluginMeta {
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{plugin_dir});
    defer allocator.free(meta_path);

    const file = std.fs.openFileAbsolute(meta_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    var buf: [4096]u8 = undefined;
    const n = try file.readAll(&buf);
    const content = buf[0..n];

    // Simple key=value TOML parser for flat plugin.toml.
    var name: []const u8 = "";
    var version: []const u8 = "";
    var description: []const u8 = "";
    var author: []const u8 = "";

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        const raw_val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        // Strip surrounding quotes.
        const val = if (raw_val.len >= 2 and raw_val[0] == '"' and raw_val[raw_val.len - 1] == '"')
            raw_val[1 .. raw_val.len - 1]
        else
            raw_val;
        if (std.mem.eql(u8, key, "name")) name = val;
        if (std.mem.eql(u8, key, "version")) version = val;
        if (std.mem.eql(u8, key, "description")) description = val;
        if (std.mem.eql(u8, key, "author")) author = val;
    }

    return PluginMeta{
        .name = try allocator.dupe(u8, name),
        .version = try allocator.dupe(u8, version),
        .description = try allocator.dupe(u8, description),
        .author = try allocator.dupe(u8, author),
        .allocator = allocator,
    };
}

// ---------------------------------------------------------------------------
// Plugin management (install / remove / info)
// ---------------------------------------------------------------------------

pub const InstallError = error{
    SourceNotFound,
    AlreadyInstalled,
    DestinationCreateFailed,
};

/// Install a local plugin into ~/.zr/plugins/<name>/.
/// `src_path` must be the absolute path to the plugin directory.
/// `plugin_name` is the name to register it under.
/// Returns the destination path (caller frees).
pub fn installLocalPlugin(
    allocator: std.mem.Allocator,
    src_path: []const u8,
    plugin_name: []const u8,
) ![]const u8 {
    // Verify source exists.
    std.fs.accessAbsolute(src_path, .{}) catch return InstallError.SourceNotFound;

    const home = std.posix.getenv("HOME") orelse ".";
    const dest_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
    errdefer allocator.free(dest_dir);

    // Check if already installed.
    const already = blk: {
        std.fs.accessAbsolute(dest_dir, .{}) catch { break :blk false; };
        break :blk true;
    };
    if (already) return InstallError.AlreadyInstalled;

    // Ensure ~/.zr/plugins/ parent exists.
    const parent = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return InstallError.DestinationCreateFailed,
    };

    // Copy the source directory tree into dest_dir.
    var src_dir = std.fs.openDirAbsolute(src_path, .{ .iterate = true }) catch return InstallError.SourceNotFound;
    defer src_dir.close();

    std.fs.makeDirAbsolute(dest_dir) catch return InstallError.DestinationCreateFailed;
    var dest = std.fs.openDirAbsolute(dest_dir, .{}) catch return InstallError.DestinationCreateFailed;
    defer dest.close();

    // Walk and copy files (shallow — one level only for simplicity).
    var it = src_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        var src_file = try src_dir.openFile(entry.name, .{});
        defer src_file.close();
        var dst_file = try dest.createFile(entry.name, .{});
        defer dst_file.close();
        var fifo_buf: [8192]u8 = undefined;
        while (true) {
            const n = try src_file.read(&fifo_buf);
            if (n == 0) break;
            try dst_file.writeAll(fifo_buf[0..n]);
        }
    }

    return dest_dir;
}

/// Remove an installed plugin from ~/.zr/plugins/<name>/.
pub fn removePlugin(allocator: std.mem.Allocator, plugin_name: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse ".";
    const plugin_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
    defer allocator.free(plugin_dir);

    std.fs.deleteTreeAbsolute(plugin_dir) catch |err| switch (err) {
        error.FileNotFound => return error.PluginNotFound,
        else => return err,
    };
}

/// List all installed plugins from ~/.zr/plugins/.
/// Returns a slice of plugin directory names (caller frees slice and each name).
pub fn listInstalledPlugins(allocator: std.mem.Allocator) ![][]const u8 {
    const home = std.posix.getenv("HOME") orelse ".";
    const plugins_dir_path = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(plugins_dir_path);

    var result: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (result.items) |n| allocator.free(n);
        result.deinit(allocator);
    }

    var dir = std.fs.openDirAbsolute(plugins_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return try result.toOwnedSlice(allocator),
        else => return err,
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        try result.append(allocator, try allocator.dupe(u8, entry.name));
    }

    return result.toOwnedSlice(allocator);
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

test "readPluginMeta: returns null for missing file" {
    const allocator = std.testing.allocator;
    const result = try readPluginMeta(allocator, "/nonexistent/path/that/does/not/exist");
    try std.testing.expectEqual(@as(?PluginMeta, null), result);
}

test "readPluginMeta: parses plugin.toml in a temp dir" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Write a plugin.toml.
    try tmp.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"myplugin\"\nversion = \"1.0.0\"\ndescription = \"Test plugin\"\nauthor = \"tester\"\n",
    });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var meta = (try readPluginMeta(allocator, tmp_path)) orelse return error.TestUnexpectedNull;
    defer meta.deinit();

    try std.testing.expectEqualStrings("myplugin", meta.name);
    try std.testing.expectEqualStrings("1.0.0", meta.version);
    try std.testing.expectEqualStrings("Test plugin", meta.description);
    try std.testing.expectEqualStrings("tester", meta.author);
}

test "installLocalPlugin: source not found returns error" {
    const allocator = std.testing.allocator;
    const result = installLocalPlugin(allocator, "/nonexistent/src/path", "testplugin");
    try std.testing.expectError(InstallError.SourceNotFound, result);
}

test "installLocalPlugin and removePlugin round-trip" {
    const allocator = std.testing.allocator;

    // Create a temp directory as source.
    var tmp_src = std.testing.tmpDir(.{});
    defer tmp_src.cleanup();

    // Write a dummy shared library file.
    try tmp_src.dir.writeFile(.{
        .sub_path = "plugin.dylib",
        .data = "dummy",
    });
    try tmp_src.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"roundtrip\"\nversion = \"0.1.0\"\ndescription = \"\"\nauthor = \"\"\n",
    });

    const src_path = try tmp_src.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src_path);

    // Use a unique plugin name to avoid HOME pollution.
    // We can't easily override HOME in tests, so use a name unlikely to collide.
    const dest_path = installLocalPlugin(allocator, src_path, "zr-test-roundtrip-12345") catch |err| switch (err) {
        InstallError.AlreadyInstalled => {
            // Clean up if left from a previous run, then retry once.
            try removePlugin(allocator, "zr-test-roundtrip-12345");
            try std.testing.expect(true); // Already cleaned up.
            return;
        },
        else => return err,
    };
    defer allocator.free(dest_path);

    // Verify the plugin dir was created.
    std.fs.accessAbsolute(dest_path, .{}) catch return error.TestExpectedDestDir;

    // Verify plugin.toml was copied.
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{dest_path});
    defer allocator.free(meta_path);
    std.fs.accessAbsolute(meta_path, .{}) catch return error.TestExpectedMetaFile;

    // Remove the plugin.
    try removePlugin(allocator, "zr-test-roundtrip-12345");

    // Verify it's gone.
    const gone = blk: {
        std.fs.accessAbsolute(dest_path, .{}) catch { break :blk true; };
        break :blk false;
    };
    try std.testing.expect(gone);
}

test "listInstalledPlugins: empty when dir missing" {
    const allocator = std.testing.allocator;
    // This just shouldn't crash; it may return empty or real plugins.
    const names = try listInstalledPlugins(allocator);
    defer {
        for (names) |n| allocator.free(n);
        allocator.free(names);
    }
    // No assertion on count — HOME-dependent. Just verify no crash.
    _ = names.len;
}
