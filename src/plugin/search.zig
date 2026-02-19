const std = @import("std");
const install = @import("install.zig");
const platform = @import("../util/platform.zig");

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

    const home = platform.getHome();

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
