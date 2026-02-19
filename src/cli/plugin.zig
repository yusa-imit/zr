const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const plugin_loader = @import("../plugin/loader.zig");

pub fn cmdPlugin(
    allocator: std.mem.Allocator,
    sub: []const u8,
    args: []const []const u8,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (std.mem.eql(u8, sub, "list")) {
        var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
        defer config.deinit();

        if (json_output) {
            try w.print("[", .{});
            for (config.plugins, 0..) |p, i| {
                if (i > 0) try w.print(",", .{});
                try w.print("{{\"name\":", .{});
                try common.writeJsonString(w, p.name);
                try w.print(",\"source\":", .{});
                try common.writeJsonString(w, p.source);
                try w.print(",\"kind\":\"{s}\"}}", .{@tagName(p.kind)});
            }
            try w.print("]\n", .{});
        } else {
            if (config.plugins.len == 0) {
                try color.printDim(w, use_color, "No plugins configured in {s}\n\n  Hint: Add [plugins.NAME] sections to declare plugins\n", .{config_path});
                return 0;
            }
            try color.printBold(w, use_color, "Plugins ({d})\n", .{config.plugins.len});
            for (config.plugins) |p| {
                try w.print("  ", .{});
                try color.printBold(w, use_color, "{s}", .{p.name});
                try w.print("  [{s}]  {s}\n", .{ @tagName(p.kind), p.source });
                if (p.config.len > 0) {
                    for (p.config) |pair| {
                        try color.printDim(w, use_color, "    {s} = {s}\n", .{ pair[0], pair[1] });
                    }
                }
            }
        }
        return 0;
    } else if (std.mem.eql(u8, sub, "install")) {
        // zr plugin install <path|git-url> [<name>]
        // args: [zr, plugin, install, <source>, [<name>]]
        if (args.len < 4) {
            try color.printError(ew, use_color,
                "plugin install: missing <path|url>\n\n  Hint: zr plugin install ./my-plugin [name]\n        zr plugin install https://github.com/user/plugin [name]\n", .{});
            return 1;
        }
        const src_path = args[3];

        // Detect source type.
        const is_registry = std.mem.startsWith(u8, src_path, "registry:");
        const is_git_url = !is_registry and (std.mem.startsWith(u8, src_path, "https://") or
            std.mem.startsWith(u8, src_path, "http://") or
            std.mem.startsWith(u8, src_path, "git://") or
            std.mem.startsWith(u8, src_path, "git@"));

        // Derive name from last path component (strip trailing .git) if not provided.
        const plugin_name: []const u8 = if (args.len >= 5)
            args[4]
        else if (is_registry) blk: {
            // For registry refs, use the plugin name portion: "org/name@ver" → "name"
            const registry_source = src_path["registry:".len..];
            const ref = plugin_loader.parseRegistryRef(registry_source);
            break :blk ref.name;
        } else blk: {
            const last = std.mem.lastIndexOfScalar(u8, src_path, '/');
            var raw = if (last) |idx| src_path[idx + 1 ..] else src_path;
            // Strip .git suffix for git URLs.
            if (std.mem.endsWith(u8, raw, ".git")) raw = raw[0 .. raw.len - 4];
            break :blk raw;
        };

        if (is_registry) {
            // Registry install path: "registry:org/name@version"
            const registry_source = src_path["registry:".len..];
            const name_override: ?[]const u8 = if (args.len >= 5) args[4] else null;
            const dest = plugin_loader.installRegistryPlugin(allocator, registry_source, name_override) catch |err| switch (err) {
                plugin_loader.RegistryInstallError.AlreadyInstalled => {
                    try color.printError(ew, use_color,
                        "plugin install: '{s}' is already installed\n\n  Hint: Run 'zr plugin remove {s}' first\n",
                        .{ plugin_name, plugin_name });
                    return 1;
                },
                plugin_loader.RegistryInstallError.GitNotFound => {
                    try color.printError(ew, use_color,
                        "plugin install: 'git' not found in PATH\n\n  Hint: Install git to use registry installs\n", .{});
                    return 1;
                },
                plugin_loader.RegistryInstallError.CloneFailed => {
                    try color.printError(ew, use_color,
                        "plugin install: registry install failed for '{s}'\n\n  Hint: Check the registry ref and your network connection\n        Format: registry:org/name@version\n", .{src_path});
                    return 1;
                },
                plugin_loader.RegistryInstallError.InvalidRef => {
                    try color.printError(ew, use_color,
                        "plugin install: invalid registry ref '{s}'\n\n  Hint: Format: registry:org/name@version or registry:name@version\n", .{src_path});
                    return 1;
                },
                else => return err,
            };
            defer allocator.free(dest);
            try color.printSuccess(w, use_color, "Installed plugin '{s}' → {s}\n", .{ plugin_name, dest });
            return 0;
        }

        if (is_git_url) {
            // Git install path.
            const dest = plugin_loader.installGitPlugin(allocator, src_path, plugin_name) catch |err| switch (err) {
                plugin_loader.GitInstallError.AlreadyInstalled => {
                    try color.printError(ew, use_color,
                        "plugin install: '{s}' is already installed\n\n  Hint: Run 'zr plugin remove {s}' first\n",
                        .{ plugin_name, plugin_name });
                    return 1;
                },
                plugin_loader.GitInstallError.GitNotFound => {
                    try color.printError(ew, use_color,
                        "plugin install: 'git' not found in PATH\n\n  Hint: Install git to use git URL installs\n", .{});
                    return 1;
                },
                plugin_loader.GitInstallError.CloneFailed => {
                    try color.printError(ew, use_color,
                        "plugin install: git clone failed for '{s}'\n\n  Hint: Check the URL and your network connection\n", .{src_path});
                    return 1;
                },
                else => return err,
            };
            defer allocator.free(dest);
            try color.printSuccess(w, use_color, "Installed plugin '{s}' → {s}\n", .{ plugin_name, dest });
            return 0;
        }

        // Local install path.

        // Resolve src_path to absolute if needed.
        const abs_src = if (std.fs.path.isAbsolute(src_path))
            try allocator.dupe(u8, src_path)
        else blk: {
            const cwd = try std.fs.cwd().realpathAlloc(allocator, src_path);
            break :blk cwd;
        };
        defer allocator.free(abs_src);

        const dest = plugin_loader.installLocalPlugin(allocator, abs_src, plugin_name) catch |err| switch (err) {
            plugin_loader.InstallError.SourceNotFound => {
                try color.printError(ew, use_color,
                    "plugin install: path not found: {s}\n", .{src_path});
                return 1;
            },
            plugin_loader.InstallError.AlreadyInstalled => {
                try color.printError(ew, use_color,
                    "plugin install: '{s}' is already installed\n\n  Hint: Run 'zr plugin remove {s}' first\n",
                    .{ plugin_name, plugin_name });
                return 1;
            },
            else => return err,
        };
        defer allocator.free(dest);

        try color.printSuccess(w, use_color, "Installed plugin '{s}' → {s}\n", .{ plugin_name, dest });
        return 0;
    } else if (std.mem.eql(u8, sub, "remove")) {
        // args: [zr, plugin, remove, <name>]
        if (args.len < 4) {
            try color.printError(ew, use_color,
                "plugin remove: missing <name>\n\n  Hint: zr plugin remove <name>\n", .{});
            return 1;
        }
        const plugin_name = args[3];
        plugin_loader.removePlugin(allocator, plugin_name) catch |err| switch (err) {
            error.PluginNotFound => {
                try color.printError(ew, use_color,
                    "plugin remove: plugin '{s}' is not installed\n", .{plugin_name});
                return 1;
            },
            else => return err,
        };
        try color.printSuccess(w, use_color, "Removed plugin '{s}'\n", .{plugin_name});
        return 0;
    } else if (std.mem.eql(u8, sub, "info")) {
        // args: [zr, plugin, info, <name>]
        if (args.len < 4) {
            try color.printError(ew, use_color,
                "plugin info: missing <name>\n\n  Hint: zr plugin info <name>\n", .{});
            return 1;
        }
        const plugin_name = args[3];
        const home = std.posix.getenv("HOME") orelse ".";
        const plugin_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/plugins/{s}", .{ home, plugin_name });
        defer allocator.free(plugin_dir);

        // Check the plugin dir exists.
        std.fs.accessAbsolute(plugin_dir, .{}) catch {
            try color.printError(ew, use_color,
                "plugin info: plugin '{s}' is not installed\n\n  Hint: Install it with 'zr plugin install <path> {s}'\n",
                .{ plugin_name, plugin_name });
            return 1;
        };

        const meta_opt = try plugin_loader.readPluginMeta(allocator, plugin_dir);
        if (meta_opt) |meta_val| {
            var meta = meta_val;
            defer meta.deinit();
            if (json_output) {
                try w.print("{{\"name\":", .{});
                try common.writeJsonString(w, meta.name);
                try w.print(",\"version\":", .{});
                try common.writeJsonString(w, meta.version);
                try w.print(",\"description\":", .{});
                try common.writeJsonString(w, meta.description);
                try w.print(",\"author\":", .{});
                try common.writeJsonString(w, meta.author);
                try w.print(",\"path\":", .{});
                try common.writeJsonString(w, plugin_dir);
                try w.print("}}\n", .{});
            } else {
                try color.printBold(w, use_color, "{s}", .{if (meta.name.len > 0) meta.name else plugin_name});
                if (meta.version.len > 0) try w.print(" v{s}", .{meta.version});
                try w.print("\n", .{});
                if (meta.description.len > 0) try w.print("  {s}\n", .{meta.description});
                if (meta.author.len > 0) try color.printDim(w, use_color, "  Author: {s}\n", .{meta.author});
                try color.printDim(w, use_color, "  Path:   {s}\n", .{plugin_dir});
            }
        } else {
            // No plugin.toml — show basic info.
            if (json_output) {
                try w.print("{{\"name\":", .{});
                try common.writeJsonString(w, plugin_name);
                try w.print(",\"path\":", .{});
                try common.writeJsonString(w, plugin_dir);
                try w.print("}}\n", .{});
            } else {
                try color.printBold(w, use_color, "{s}\n", .{plugin_name});
                try color.printDim(w, use_color, "  Path:   {s}\n", .{plugin_dir});
                try color.printDim(w, use_color, "  (no plugin.toml found)\n", .{});
            }
        }
        return 0;
    } else if (std.mem.eql(u8, sub, "update")) {
        // zr plugin update <name> [<path>]
        // args: [zr, plugin, update, <name>, [<path>]]
        // If no path given, try git pull (git-installed plugins).
        if (args.len < 4) {
            try color.printError(ew, use_color,
                "plugin update: usage: zr plugin update <name> [<path>]\n", .{});
            return 1;
        }
        const plugin_name = args[3];

        if (args.len < 5) {
            // No source path — attempt git pull for git-installed plugins.
            plugin_loader.updateGitPlugin(allocator, plugin_name) catch |err| switch (err) {
                plugin_loader.GitUpdateError.PluginNotFound => {
                    try color.printError(ew, use_color,
                        "plugin update: plugin '{s}' is not installed\n\n  Hint: Install it first with 'zr plugin install <url> {s}'\n",
                        .{ plugin_name, plugin_name });
                    return 1;
                },
                plugin_loader.GitUpdateError.NotAGitPlugin => {
                    try color.printError(ew, use_color,
                        "plugin update: '{s}' was not installed from a git URL\n\n  Hint: Provide a source path: zr plugin update {s} <path>\n",
                        .{ plugin_name, plugin_name });
                    return 1;
                },
                plugin_loader.GitUpdateError.GitNotFound => {
                    try color.printError(ew, use_color,
                        "plugin update: 'git' not found in PATH\n\n  Hint: Install git to update git plugins\n", .{});
                    return 1;
                },
                plugin_loader.GitUpdateError.PullFailed => {
                    try color.printError(ew, use_color,
                        "plugin update: git pull failed for '{s}'\n\n  Hint: Check your network connection\n", .{plugin_name});
                    return 1;
                },
                else => return err,
            };
            try color.printSuccess(w, use_color, "Updated plugin '{s}' (git pull)\n", .{plugin_name});
            return 0;
        }

        const src_path = args[4];

        // Resolve to absolute path.
        var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
        const abs_src = std.fs.realpath(src_path, &abs_buf) catch {
            try color.printError(ew, use_color,
                "plugin update: path not found: {s}\n", .{src_path});
            return 1;
        };

        const dest = plugin_loader.updateLocalPlugin(allocator, plugin_name, abs_src) catch |err| switch (err) {
            error.PluginNotFound => {
                try color.printError(ew, use_color,
                    "plugin update: plugin '{s}' is not installed\n\n  Hint: Install it first with 'zr plugin install {s} {s}'\n",
                    .{ plugin_name, src_path, plugin_name });
                return 1;
            },
            plugin_loader.InstallError.SourceNotFound => {
                try color.printError(ew, use_color,
                    "plugin update: path not found: {s}\n", .{src_path});
                return 1;
            },
            else => return err,
        };
        defer allocator.free(dest);
        try color.printSuccess(w, use_color, "Updated plugin '{s}' → {s}\n", .{ plugin_name, dest });
        return 0;
    } else if (std.mem.eql(u8, sub, "search")) {
        // zr plugin search [<query>]
        // Searches installed plugins by name/description (case-insensitive substring).
        const query: []const u8 = if (args.len >= 4) args[3] else "";

        const results = try plugin_loader.searchInstalledPlugins(allocator, query);
        defer {
            for (results) |*r| {
                var rc = r.*;
                rc.deinit();
            }
            allocator.free(results);
        }

        if (json_output) {
            try w.print("[", .{});
            for (results, 0..) |r, i| {
                if (i > 0) try w.print(",", .{});
                try w.print("{{\"name\":", .{});
                try common.writeJsonString(w, r.name);
                try w.print(",\"version\":", .{});
                try common.writeJsonString(w, r.version);
                try w.print(",\"description\":", .{});
                try common.writeJsonString(w, r.description);
                try w.print(",\"author\":", .{});
                try common.writeJsonString(w, r.author);
                try w.print("}}", .{});
            }
            try w.print("]\n", .{});
        } else {
            if (results.len == 0) {
                if (query.len > 0) {
                    try color.printDim(w, use_color, "No installed plugins matching '{s}'\n\n  Hint: Run 'zr plugin list' to see all installed plugins\n", .{query});
                } else {
                    try color.printDim(w, use_color, "No plugins installed\n\n  Hint: Install plugins with 'zr plugin install <path|url>'\n", .{});
                }
                return 0;
            }
            if (query.len > 0) {
                try color.printBold(w, use_color, "Search results for '{s}' ({d})\n", .{ query, results.len });
            } else {
                try color.printBold(w, use_color, "Installed plugins ({d})\n", .{results.len});
            }
            for (results) |r| {
                try w.print("  ", .{});
                try color.printBold(w, use_color, "{s}", .{r.name});
                if (r.version.len > 0) try w.print(" v{s}", .{r.version});
                if (r.description.len > 0) try color.printDim(w, use_color, " — {s}", .{r.description});
                try w.print("\n", .{});
                if (r.author.len > 0) try color.printDim(w, use_color, "    Author: {s}\n", .{r.author});
            }
        }
        return 0;
    } else if (std.mem.eql(u8, sub, "builtins")) {
        // zr plugin builtins — list all available built-in plugins
        try color.printBold(w, use_color, "Built-in plugins\n", .{});
        try w.print("  Use source = \"builtin:<name>\" in your zr.toml [plugins.X] section.\n\n", .{});
        const entries = [_][3][]const u8{
            .{ "env",    "Environment variable management; loads .env files automatically.",      "env_file, overwrite" },
            .{ "git",    "Git integration: branch info, changed files, commit message access.",  "n/a" },
            .{ "notify", "Webhook notifications (Slack, Discord, Teams) after task completion.", "webhook_url, message, username, on_failure_only" },
            .{ "cache",  "Task output caching on local filesystem (built-in cache store).",      "n/a" },
            .{ "docker", "Docker integration: build/push helpers, layer cache optimization.",    "n/a" },
        };
        for (entries) |e| {
            try color.printBold(w, use_color, "  {s}\n", .{e[0]});
            try color.printDim(w, use_color, "    {s}\n", .{e[1]});
            try color.printDim(w, use_color, "    Config keys: {s}\n\n", .{e[2]});
        }
        return 0;
    } else if (sub.len == 0) {
        try color.printError(ew, use_color,
            "plugin: missing subcommand\n\n  Hint: zr plugin list | search | install | remove | update | info | builtins\n", .{});
        return 1;
    } else {
        try color.printError(ew, use_color,
            "plugin: unknown subcommand '{s}'\n\n  Hint: zr plugin list | search | install | remove | update | info | builtins\n", .{sub});
        return 1;
    }
}

test "plugin update: missing name returns error" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = [_][]const u8{ "zr", "plugin", "update" };
    const code = try cmdPlugin(allocator, "update", &args, "zr.toml", false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "plugin update: not-installed plugin returns error (no-path form)" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = [_][]const u8{ "zr", "plugin", "update", "zr-test-noexist-gitupdate-12345" };
    const code = try cmdPlugin(allocator, "update", &args, "zr.toml", false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "plugin update: local plugin without git_url returns NotAGitPlugin error" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-plugin-gitupdate-local-77777";

    // Create and install a local plugin (no git_url).
    var tmp_src = std.testing.tmpDir(.{});
    defer tmp_src.cleanup();
    try tmp_src.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"local\"\nversion = \"1.0.0\"\n",
    });
    try tmp_src.dir.writeFile(.{ .sub_path = "plugin.dylib", .data = "dummy" });
    const src = try tmp_src.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src);

    plugin_loader.removePlugin(allocator, plugin_name) catch {};
    const dest = try plugin_loader.installLocalPlugin(allocator, src, plugin_name);
    allocator.free(dest);
    defer plugin_loader.removePlugin(allocator, plugin_name) catch {};

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = [_][]const u8{ "zr", "plugin", "update", plugin_name };
    const code = try cmdPlugin(allocator, "update", &args, "zr.toml", false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "plugin search: no query returns all installed or empty message" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = [_][]const u8{ "zr", "plugin", "search" };
    const code = try cmdPlugin(allocator, "search", &args, "zr.toml", false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "plugin search: query with no matches returns empty message" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = [_][]const u8{ "zr", "plugin", "search", "zr-test-unlikely-query-xyzxyz12345" };
    const code = try cmdPlugin(allocator, "search", &args, "zr.toml", false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "plugin search: installed plugin appears in results" {
    const allocator = std.testing.allocator;
    const plugin_name = "zr-test-search-99991";

    // Create a test plugin directory.
    var tmp_src = std.testing.tmpDir(.{});
    defer tmp_src.cleanup();
    try tmp_src.dir.writeFile(.{
        .sub_path = "plugin.toml",
        .data = "name = \"searchable\"\nversion = \"1.0.0\"\ndescription = \"A searchable plugin\"\nauthor = \"tester\"\n",
    });
    try tmp_src.dir.writeFile(.{ .sub_path = "plugin.dylib", .data = "dummy" });
    const src = try tmp_src.dir.realpathAlloc(allocator, ".");
    defer allocator.free(src);

    plugin_loader.removePlugin(allocator, plugin_name) catch {};
    const dest = try plugin_loader.installLocalPlugin(allocator, src, plugin_name);
    allocator.free(dest);
    defer plugin_loader.removePlugin(allocator, plugin_name) catch {};

    // Search for something that matches the description.
    const results = try plugin_loader.searchInstalledPlugins(allocator, "searchable");
    defer {
        for (results) |*r| {
            var rc = r.*;
            rc.deinit();
        }
        allocator.free(results);
    }

    // At least one result should match.
    var found = false;
    for (results) |r| {
        if (std.mem.eql(u8, r.name, "searchable")) {
            found = true;
            try std.testing.expectEqualStrings("1.0.0", r.version);
            break;
        }
    }
    try std.testing.expect(found);
}

test "plugin search: json output flag" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_w = stderr_file.writer(&err_buf);

    const args = [_][]const u8{ "zr", "plugin", "search", "zr-test-unlikely-xyzxyz99999" };
    const code = try cmdPlugin(allocator, "search", &args, "zr.toml", true, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "plugin builtins: lists all built-in plugins" {
    const allocator = std.testing.allocator;
    var out: [4096]u8 = undefined;
    var err: [512]u8 = undefined;
    const stdout = std.fs.File.stdout();
    const stderr_file = std.fs.File.stderr();
    var out_w = stdout.writer(&out);
    var err_w = stderr_file.writer(&err);

    const args = [_][]const u8{ "zr", "plugin", "builtins" };
    const code = try cmdPlugin(allocator, "builtins", &args, "zr.toml", false, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "plugin builtins: builtin source kind loads from PluginRegistry" {
    const allocator = std.testing.allocator;

    const configs = [_]plugin_loader.PluginConfig{
        .{
            .name = "env",
            .kind = .builtin,
            .source = "env",
            .config = &.{},
        },
        .{
            .name = "notify",
            .kind = .builtin,
            .source = "notify",
            .config = &.{},
        },
    };

    var registry = plugin_loader.PluginRegistry.init(allocator);
    defer registry.deinit();

    var buf: [512]u8 = undefined;
    const devnull = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer devnull.close();
    var w = devnull.writer(&buf);

    try registry.loadAll(&configs, &w.interface);
    try std.testing.expectEqual(@as(usize, 2), registry.count());
}
