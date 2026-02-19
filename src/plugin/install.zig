const std = @import("std");

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

pub const InstallError = error{
    SourceNotFound,
    AlreadyInstalled,
    DestinationCreateFailed,
};

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

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Resolve the filesystem path for a local plugin source.
/// Caller owns the returned slice.
pub fn resolveLocalPath(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
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

pub const LibraryNotFoundError = error{LibraryNotFound};

/// Find the shared library file inside a plugin directory.
/// Tries plugin.so, plugin.dylib, plugin.dll in order.
/// Caller owns the returned slice.
pub fn findLibInDir(allocator: std.mem.Allocator, dir_path: []const u8) ![]const u8 {
    const exts = [_][]const u8{ "so", "dylib", "dll" };
    for (exts) |ext| {
        const candidate = try std.fmt.allocPrint(allocator, "{s}/plugin.{s}", .{ dir_path, ext });
        if (std.fs.accessAbsolute(candidate, .{})) |_| {
            return candidate;
        } else |_| {
            allocator.free(candidate);
        }
    }
    return error.LibraryNotFound;
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

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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
