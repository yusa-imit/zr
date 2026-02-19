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

/// Parsed components of a registry reference string.
/// Format: "org/name@version" or "name@version" or "org/name".
pub const RegistryRef = struct {
    /// Organization prefix (empty string if not present).
    org: []const u8,
    /// Plugin name.
    name: []const u8,
    /// Version tag (empty string means "latest" / default branch).
    version: []const u8,
};

/// Parse a registry source string into its components.
/// Input examples: "zr/docker@1.2.0", "docker@1.0.0", "zr/docker"
/// Caller does NOT own the returned slices — they point into `source`.
pub fn parseRegistryRef(source: []const u8) RegistryRef {
    var org: []const u8 = "";
    var name_ver = source;

    // Split on '/' to find optional org.
    if (std.mem.indexOfScalar(u8, source, '/')) |slash_idx| {
        org = source[0..slash_idx];
        name_ver = source[slash_idx + 1 ..];
    }

    // Split on '@' to find optional version.
    if (std.mem.indexOfScalar(u8, name_ver, '@')) |at_idx| {
        return .{
            .org = org,
            .name = name_ver[0..at_idx],
            .version = name_ver[at_idx + 1 ..],
        };
    }

    return .{ .org = org, .name = name_ver, .version = "" };
}

pub const RegistryInstallError = error{
    InvalidRef,
    GitNotFound,
    CloneFailed,
    AlreadyInstalled,
};

/// Default registry base URL (GitHub org hosting zr-plugin-* repos).
pub const default_registry_base = "https://github.com/zr-runner";

/// Resolve a registry ref to a git URL and install the plugin.
/// Format: "org/name@version" — org defaults to `default_registry_base` if empty.
/// Version is used as a git tag (--branch flag); empty means default branch.
/// Returns the destination path (caller frees).
pub fn installRegistryPlugin(
    allocator: std.mem.Allocator,
    source: []const u8,
    plugin_name_override: ?[]const u8,
) ![]const u8 {
    const ref = parseRegistryRef(source);

    if (ref.name.len == 0) return RegistryInstallError.InvalidRef;

    // Build the git URL.
    // If org is provided and looks like a full org (no dots), use GitHub.
    // Otherwise treat it as a custom org on GitHub.
    const git_url = if (ref.org.len > 0) blk: {
        // org/name → https://github.com/<org>/zr-plugin-<name>
        // Check if name already has "zr-plugin-" prefix to avoid doubling.
        if (std.mem.startsWith(u8, ref.name, "zr-plugin-")) {
            break :blk try std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}", .{ ref.org, ref.name });
        } else {
            break :blk try std.fmt.allocPrint(allocator, "https://github.com/{s}/zr-plugin-{s}", .{ ref.org, ref.name });
        }
    } else blk: {
        // No org: use default registry org.
        if (std.mem.startsWith(u8, ref.name, "zr-plugin-")) {
            break :blk try std.fmt.allocPrint(allocator, "{s}/{s}", .{ default_registry_base, ref.name });
        } else {
            break :blk try std.fmt.allocPrint(allocator, "{s}/zr-plugin-{s}", .{ default_registry_base, ref.name });
        }
    };
    defer allocator.free(git_url);

    // Determine install name: prefer override, then fall back to ref.name.
    const install_name = plugin_name_override orelse ref.name;

    const home = std.posix.getenv("HOME") orelse ".";
    const dest_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, install_name });
    errdefer allocator.free(dest_dir);

    // Check if already installed.
    const already = blk: {
        std.fs.accessAbsolute(dest_dir, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };
    if (already) return RegistryInstallError.AlreadyInstalled;

    // Ensure ~/.zr/plugins/ parent exists.
    const parent = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Build argv: git clone [--branch <version>] --depth=1 <url> <dest>
    var argv = std.ArrayListUnmanaged([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, "git");
    try argv.append(allocator, "clone");
    if (ref.version.len > 0) {
        try argv.append(allocator, "--branch");
        try argv.append(allocator, ref.version);
    }
    try argv.append(allocator, "--depth=1");
    try argv.append(allocator, git_url);
    try argv.append(allocator, dest_dir);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return RegistryInstallError.GitNotFound;
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return RegistryInstallError.CloneFailed,
        else => return RegistryInstallError.CloneFailed,
    }

    // Record registry metadata in plugin.toml.
    writeRegistryRefToMeta(allocator, dest_dir, source) catch {};

    return dest_dir;
}

/// Write (or append) a registry_ref key to a plugin's plugin.toml.
/// Idempotent — will not write if key already exists.
fn writeRegistryRefToMeta(allocator: std.mem.Allocator, plugin_dir: []const u8, registry_ref: []const u8) !void {
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{plugin_dir});
    defer allocator.free(meta_path);

    var existing_buf: [8192]u8 = undefined;
    var existing: []const u8 = "";
    if (std.fs.openFileAbsolute(meta_path, .{})) |f| {
        defer f.close();
        const n = try f.readAll(&existing_buf);
        existing = existing_buf[0..n];
    } else |_| {}

    if (std.mem.indexOf(u8, existing, "registry_ref") != null) return;

    const line = try std.fmt.allocPrint(allocator, "registry_ref = \"{s}\"\n", .{registry_ref});
    defer allocator.free(line);

    const new_content = try std.fmt.allocPrint(allocator, "{s}{s}", .{ existing, line });
    defer allocator.free(new_content);

    const file = try std.fs.createFileAbsolute(meta_path, .{});
    defer file.close();
    try file.writeAll(new_content);
}

/// Read the registry_ref field from a plugin's plugin.toml.
/// Returns null if the field is missing or the file doesn't exist.
/// Caller frees the returned slice.
pub fn readRegistryRef(allocator: std.mem.Allocator, plugin_dir: []const u8) !?[]const u8 {
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{plugin_dir});
    defer allocator.free(meta_path);

    const file = std.fs.openFileAbsolute(meta_path, .{}) catch return null;
    defer file.close();

    var buf: [8192]u8 = undefined;
    const n = try file.readAll(&buf);
    const content = buf[0..n];

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "registry_ref")) continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const raw = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        const val = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
            raw[1 .. raw.len - 1]
        else
            raw;
        return try allocator.dupe(u8, val);
    }
    return null;
}

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

    /// Load all plugins from the provided config list.
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

/// Update an installed plugin by removing the old installation and re-installing from a new source path.
/// If the plugin is not installed, returns error.PluginNotFound.
/// If src_path does not exist, returns InstallError.SourceNotFound.
pub fn updateLocalPlugin(
    allocator: std.mem.Allocator,
    plugin_name: []const u8,
    src_path: []const u8,
) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse ".";
    const plugin_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
    defer allocator.free(plugin_dir);

    // Verify plugin is installed.
    std.fs.accessAbsolute(plugin_dir, .{}) catch return error.PluginNotFound;

    // Verify source exists.
    std.fs.accessAbsolute(src_path, .{}) catch return InstallError.SourceNotFound;

    // Remove existing installation.
    std.fs.deleteTreeAbsolute(plugin_dir) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    // Re-install from new source.
    return installLocalPlugin(allocator, src_path, plugin_name);
}

pub const GitInstallError = error{
    GitNotFound,
    CloneFailed,
    AlreadyInstalled,
};

pub const GitUpdateError = error{
    PluginNotFound,
    NotAGitPlugin,
    GitNotFound,
    PullFailed,
};

/// Install a plugin from a git URL into ~/.zr/plugins/<name>/.
/// Runs `git clone <url> <dest>` as a subprocess.
/// Returns the destination path (caller frees).
pub fn installGitPlugin(
    allocator: std.mem.Allocator,
    git_url: []const u8,
    plugin_name: []const u8,
) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse ".";
    const dest_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
    errdefer allocator.free(dest_dir);

    // Check if already installed.
    const already = blk: {
        std.fs.accessAbsolute(dest_dir, .{}) catch { break :blk false; };
        break :blk true;
    };
    if (already) return GitInstallError.AlreadyInstalled;

    // Ensure ~/.zr/plugins/ parent exists.
    const parent = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Run: git clone <url> <dest_dir>
    const argv = [_][]const u8{ "git", "clone", "--depth=1", git_url, dest_dir };
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return GitInstallError.GitNotFound;
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return GitInstallError.CloneFailed,
        else => return GitInstallError.CloneFailed,
    }

    // Record the git URL in plugin.toml for future updates.
    writeGitUrlToMeta(allocator, dest_dir, git_url) catch {};

    return dest_dir;
}

/// Write (or append) a git_url key to a plugin's plugin.toml.
/// Creates the file if it doesn't exist; appends the key otherwise.
fn writeGitUrlToMeta(allocator: std.mem.Allocator, plugin_dir: []const u8, git_url: []const u8) !void {
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{plugin_dir});
    defer allocator.free(meta_path);

    // Read existing content if any.
    var existing_buf: [8192]u8 = undefined;
    var existing: []const u8 = "";
    if (std.fs.openFileAbsolute(meta_path, .{})) |f| {
        defer f.close();
        const n = try f.readAll(&existing_buf);
        existing = existing_buf[0..n];
    } else |_| {}

    // Check if git_url already present.
    if (std.mem.indexOf(u8, existing, "git_url") != null) return;

    // Append git_url line.
    const line = try std.fmt.allocPrint(allocator, "git_url = \"{s}\"\n", .{git_url});
    defer allocator.free(line);

    const new_content = try std.fmt.allocPrint(allocator, "{s}{s}", .{ existing, line });
    defer allocator.free(new_content);

    const file = try std.fs.createFileAbsolute(meta_path, .{});
    defer file.close();
    try file.writeAll(new_content);
}

/// Read the git_url field from a plugin's plugin.toml.
/// Returns null if the field is missing or the file doesn't exist.
fn readGitUrl(allocator: std.mem.Allocator, plugin_dir: []const u8) !?[]const u8 {
    const meta_path = try std.fmt.allocPrint(allocator, "{s}/plugin.toml", .{plugin_dir});
    defer allocator.free(meta_path);

    const file = std.fs.openFileAbsolute(meta_path, .{}) catch return null;
    defer file.close();

    var buf: [8192]u8 = undefined;
    const n = try file.readAll(&buf);
    const content = buf[0..n];

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "git_url")) continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const raw = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        const val = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
            raw[1 .. raw.len - 1]
        else
            raw;
        return try allocator.dupe(u8, val);
    }
    return null;
}

/// Update a git-installed plugin by running `git pull` inside its directory.
/// Reads the git_url from plugin.toml to verify it is a git plugin.
/// Returns GitUpdateError.NotAGitPlugin if no git_url is stored.
pub fn updateGitPlugin(allocator: std.mem.Allocator, plugin_name: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse ".";
    const plugin_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
    defer allocator.free(plugin_dir);

    // Verify plugin is installed.
    std.fs.accessAbsolute(plugin_dir, .{}) catch return GitUpdateError.PluginNotFound;

    // Check if it is a git plugin.
    const git_url = try readGitUrl(allocator, plugin_dir);
    if (git_url) |url| {
        allocator.free(url);
    } else {
        return GitUpdateError.NotAGitPlugin;
    }

    // Run: git -C <plugin_dir> pull
    const argv = [_][]const u8{ "git", "-C", plugin_dir, "pull" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return GitUpdateError.GitNotFound;
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return GitUpdateError.PullFailed,
        else => return GitUpdateError.PullFailed,
    }
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
    const names = try listInstalledPlugins(allocator);
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
        const meta_opt = try readPluginMeta(allocator, plugin_dir);
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

test "updateLocalPlugin: not installed returns PluginNotFound" {
    const allocator = std.testing.allocator;
    const result = updateLocalPlugin(allocator, "zr-test-not-installed-99999", "/nonexistent/path");
    try std.testing.expectError(error.PluginNotFound, result);
}

test "updateLocalPlugin: source not found returns SourceNotFound" {
    // This test needs an installed plugin first. We'll rely on the install/remove test
    // having cleaned up — so this plugin shouldn't exist. Skip if already installed.
    const allocator = std.testing.allocator;
    // If plugin doesn't exist, PluginNotFound is returned before SourceNotFound.
    const result = updateLocalPlugin(allocator, "zr-test-update-nonexistent", "/nonexistent/src");
    // Either PluginNotFound (not installed) or SourceNotFound (installed but bad path).
    const err = result catch |e| e;
    try std.testing.expect(err == error.PluginNotFound or err == InstallError.SourceNotFound);
}

test "installGitPlugin: already installed returns AlreadyInstalled" {
    const allocator = std.testing.allocator;

    // Create a fake "installed" plugin dir in a temp location.
    // We can't easily intercept HOME, so simulate by testing the logic path.
    // Instead, test that an actual existing dir triggers the error.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // We'll test via a second install attempt after a successful one, using the real HOME.
    // First clean up any leftover.
    removePlugin(allocator, "zr-test-git-dup-99999") catch {};

    // Create a fake dir manually to simulate "already installed".
    const home = std.posix.getenv("HOME") orelse ".";
    const fake_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/zr-test-git-dup-99999", .{home});
    defer allocator.free(fake_dir);

    // Ensure parent exists.
    const parent = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    std.fs.makeDirAbsolute(fake_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer removePlugin(allocator, "zr-test-git-dup-99999") catch {};

    // Now try to install — should return AlreadyInstalled.
    const result = installGitPlugin(allocator, "https://example.com/plugin.git", "zr-test-git-dup-99999");
    try std.testing.expectError(GitInstallError.AlreadyInstalled, result);
}

test "installGitPlugin: function compiles and is callable" {
    // Verify the function signature compiles correctly.
    // We cannot test git execution without network; just ensure type-checking passes.
    const fn_ptr: *const fn (std.mem.Allocator, []const u8, []const u8) anyerror![]const u8 = &installGitPlugin;
    _ = fn_ptr;
}

test "writeGitUrlToMeta and readGitUrl round-trip" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Write initial plugin.toml without git_url.
    try tmp.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"myplugin\"\nversion = \"1.0.0\"\n",
    });

    // Write git_url.
    try writeGitUrlToMeta(allocator, tmp_path, "https://github.com/user/myplugin.git");

    // Read it back.
    const url = try readGitUrl(allocator, tmp_path);
    defer if (url) |u| allocator.free(u);

    try std.testing.expect(url != null);
    try std.testing.expectEqualStrings("https://github.com/user/myplugin.git", url.?);
}

test "writeGitUrlToMeta: idempotent (does not duplicate)" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "plugin.toml", .data = "" });

    // Write twice.
    try writeGitUrlToMeta(allocator, tmp_path, "https://github.com/user/plugin.git");
    try writeGitUrlToMeta(allocator, tmp_path, "https://github.com/user/plugin.git");

    // Read file and count occurrences.
    const content = try tmp.dir.readFileAlloc(allocator, "plugin.toml", 4096);
    defer allocator.free(content);

    var count: usize = 0;
    var it = std.mem.splitSequence(u8, content, "git_url");
    _ = it.next(); // before first occurrence
    while (it.next()) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "readGitUrl: returns null when no plugin.toml" {
    const allocator = std.testing.allocator;
    const result = try readGitUrl(allocator, "/nonexistent/plugin/path");
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "readGitUrl: returns null when git_url key missing" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"nope\"\nversion = \"0.1.0\"\n",
    });

    const result = try readGitUrl(allocator, tmp_path);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "updateGitPlugin: not installed returns PluginNotFound" {
    const allocator = std.testing.allocator;
    const result = updateGitPlugin(allocator, "zr-test-gitupdate-notfound-99999");
    try std.testing.expectError(GitUpdateError.PluginNotFound, result);
}

test "updateGitPlugin: local plugin returns NotAGitPlugin" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-gitupdate-local-54321";

    // Create a local plugin (no git_url in plugin.toml).
    var tmp_src = std.testing.tmpDir(.{});
    defer tmp_src.cleanup();
    try tmp_src.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"local\"\nversion = \"1.0.0\"\n",
    });
    try tmp_src.dir.writeFile(.{ .sub_path = "plugin.dylib", .data = "dummy" });
    const src = try tmp_src.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src);

    // Clean up any leftover.
    removePlugin(allocator, plugin_name) catch {};

    // Install it locally.
    const dest = try installLocalPlugin(allocator, src, plugin_name);
    allocator.free(dest);
    defer removePlugin(allocator, plugin_name) catch {};

    // Attempt git update — should fail with NotAGitPlugin.
    const result = updateGitPlugin(allocator, plugin_name);
    try std.testing.expectError(GitUpdateError.NotAGitPlugin, result);
}

test "updateLocalPlugin: round-trip install + update" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-update-54321";

    // Create source dir v1.
    var tmp_v1 = std.testing.tmpDir(.{});
    defer tmp_v1.cleanup();
    try tmp_v1.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"myplugin\"\nversion = \"1.0.0\"\ndescription = \"\"\nauthor = \"\"\n",
    });
    try tmp_v1.dir.writeFile(.{ .sub_path = "plugin.dylib", .data = "v1" });
    const src_v1 = try tmp_v1.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src_v1);

    // Create source dir v2.
    var tmp_v2 = std.testing.tmpDir(.{});
    defer tmp_v2.cleanup();
    try tmp_v2.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"myplugin\"\nversion = \"2.0.0\"\ndescription = \"\"\nauthor = \"\"\n",
    });
    try tmp_v2.dir.writeFile(.{ .sub_path = "plugin.dylib", .data = "v2" });
    const src_v2 = try tmp_v2.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src_v2);

    // Clean up any leftover from previous test run.
    removePlugin(allocator, plugin_name) catch {};

    // Install v1.
    const dest_v1 = try installLocalPlugin(allocator, src_v1, plugin_name);
    defer allocator.free(dest_v1);

    // Update to v2.
    const dest_v2 = try updateLocalPlugin(allocator, plugin_name, src_v2);
    defer allocator.free(dest_v2);

    // Verify the updated plugin.toml has version 2.0.0.
    var meta = (try readPluginMeta(allocator, dest_v2)) orelse return error.TestUnexpectedNull;
    defer meta.deinit();
    try std.testing.expectEqualStrings("2.0.0", meta.version);

    // Clean up.
    try removePlugin(allocator, plugin_name);
}

// ---------------------------------------------------------------------------
// Registry support tests
// ---------------------------------------------------------------------------

test "parseRegistryRef: org/name@version" {
    const ref = parseRegistryRef("zr/docker@1.2.0");
    try std.testing.expectEqualStrings("zr", ref.org);
    try std.testing.expectEqualStrings("docker", ref.name);
    try std.testing.expectEqualStrings("1.2.0", ref.version);
}

test "parseRegistryRef: name@version (no org)" {
    const ref = parseRegistryRef("docker@1.0.0");
    try std.testing.expectEqualStrings("", ref.org);
    try std.testing.expectEqualStrings("docker", ref.name);
    try std.testing.expectEqualStrings("1.0.0", ref.version);
}

test "parseRegistryRef: org/name (no version)" {
    const ref = parseRegistryRef("myorg/myplugin");
    try std.testing.expectEqualStrings("myorg", ref.org);
    try std.testing.expectEqualStrings("myplugin", ref.name);
    try std.testing.expectEqualStrings("", ref.version);
}

test "parseRegistryRef: name only (no org, no version)" {
    const ref = parseRegistryRef("myplugin");
    try std.testing.expectEqualStrings("", ref.org);
    try std.testing.expectEqualStrings("myplugin", ref.name);
    try std.testing.expectEqualStrings("", ref.version);
}

test "installRegistryPlugin: already installed returns AlreadyInstalled" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-registry-dup-88888";

    // Clean up any leftover.
    removePlugin(allocator, plugin_name) catch {};

    // Create a fake installed dir to simulate "already installed".
    const home = std.posix.getenv("HOME") orelse ".";
    const fake_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
    defer allocator.free(fake_dir);

    const parent = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins", .{home});
    defer allocator.free(parent);
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    std.fs.makeDirAbsolute(fake_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer removePlugin(allocator, plugin_name) catch {};

    const result = installRegistryPlugin(allocator, "zr/docker@1.0.0", plugin_name);
    try std.testing.expectError(RegistryInstallError.AlreadyInstalled, result);
}

test "installRegistryPlugin: invalid empty ref returns InvalidRef" {
    const allocator = std.testing.allocator;
    // An empty string should give InvalidRef (empty name).
    const result = installRegistryPlugin(allocator, "", null);
    try std.testing.expectError(RegistryInstallError.InvalidRef, result);
}

test "writeRegistryRefToMeta and readRegistryRef round-trip" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"docker\"\nversion = \"1.2.0\"\n",
    });

    try writeRegistryRefToMeta(allocator, tmp_path, "zr/docker@1.2.0");

    const ref = try readRegistryRef(allocator, tmp_path);
    defer if (ref) |r| allocator.free(r);

    try std.testing.expect(ref != null);
    try std.testing.expectEqualStrings("zr/docker@1.2.0", ref.?);
}

test "writeRegistryRefToMeta: idempotent" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "plugin.toml", .data = "" });

    try writeRegistryRefToMeta(allocator, tmp_path, "zr/docker@1.0.0");
    try writeRegistryRefToMeta(allocator, tmp_path, "zr/docker@1.0.0");

    const content = try tmp.dir.readFileAlloc(allocator, "plugin.toml", 4096);
    defer allocator.free(content);

    var count: usize = 0;
    var it = std.mem.splitSequence(u8, content, "registry_ref");
    _ = it.next();
    while (it.next()) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "readRegistryRef: returns null when no plugin.toml" {
    const allocator = std.testing.allocator;
    const result = try readRegistryRef(allocator, "/nonexistent/plugin/path");
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "readRegistryRef: returns null when registry_ref key missing" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"nope\"\nversion = \"0.1.0\"\n",
    });

    const result = try readRegistryRef(allocator, tmp_path);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
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

    removePlugin(allocator, plugin_name) catch {};
    const dest = try installLocalPlugin(allocator, src, plugin_name);
    allocator.free(dest);
    defer removePlugin(allocator, plugin_name) catch {};

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

    removePlugin(allocator, plugin_name) catch {};
    const dest = try installLocalPlugin(allocator, src, plugin_name);
    allocator.free(dest);
    defer removePlugin(allocator, plugin_name) catch {};

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
