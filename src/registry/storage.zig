const std = @import("std");

/// Plugin metadata entry in the registry.
pub const PluginEntry = struct {
    name: []const u8,
    org: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    repository: []const u8,
    tags: []const []const u8,
    downloads: u64,
    versions: []const []const u8,
    readme: []const u8,
    created_at: []const u8,
    updated_at: []const u8,

    pub fn deinit(self: *PluginEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.org);
        allocator.free(self.version);
        allocator.free(self.description);
        allocator.free(self.author);
        allocator.free(self.repository);
        for (self.tags) |tag| allocator.free(tag);
        allocator.free(self.tags);
        for (self.versions) |v| allocator.free(v);
        allocator.free(self.versions);
        allocator.free(self.readme);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

/// File-based storage for plugin registry metadata.
pub const Storage = struct {
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    plugins: std.StringHashMapUnmanaged(PluginEntry),

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !Storage {
        // Create data directory if it doesn't exist.
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        var storage = Storage{
            .allocator = allocator,
            .data_dir = try allocator.dupe(u8, data_dir),
            .plugins = .empty,
        };

        // Load plugins from disk.
        try storage.load();

        return storage;
    }

    pub fn deinit(self: *Storage) void {
        // Free keys and values.
        var it = self.plugins.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            var mut_entry = kv.value_ptr.*;
            mut_entry.deinit(self.allocator);
        }
        self.plugins.deinit(self.allocator);
        self.allocator.free(self.data_dir);
    }

    /// Load plugins from JSON file.
    fn load(self: *Storage) !void {
        const json_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/plugins.json",
            .{self.data_dir},
        );
        defer self.allocator.free(json_path);

        const file = std.fs.cwd().openFile(json_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // No plugins yet, start with empty registry.
                return;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        // Parse JSON array of plugins.
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            content,
            .{},
        );
        defer parsed.deinit();

        if (parsed.value != .array) return error.InvalidFormat;

        for (parsed.value.array.items) |item| {
            if (item != .object) continue;

            const plugin = try self.parsePluginEntry(item.object);
            const key = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}",
                .{ plugin.org, plugin.name },
            );
            try self.plugins.put(self.allocator, key, plugin);
        }
    }

    /// Parse a single plugin entry from JSON object.
    fn parsePluginEntry(self: *Storage, obj: std.json.ObjectMap) !PluginEntry {
        const name = if (obj.get("name")) |v| try self.allocator.dupe(u8, v.string) else "";
        const org = if (obj.get("org")) |v| try self.allocator.dupe(u8, v.string) else "";
        const version = if (obj.get("version")) |v| try self.allocator.dupe(u8, v.string) else "";
        const description = if (obj.get("description")) |v| try self.allocator.dupe(u8, v.string) else "";
        const author = if (obj.get("author")) |v| try self.allocator.dupe(u8, v.string) else "";
        const repository = if (obj.get("repository")) |v| try self.allocator.dupe(u8, v.string) else "";
        const readme = if (obj.get("readme")) |v| try self.allocator.dupe(u8, v.string) else "";
        const created_at = if (obj.get("created_at")) |v| try self.allocator.dupe(u8, v.string) else "";
        const updated_at = if (obj.get("updated_at")) |v| try self.allocator.dupe(u8, v.string) else "";
        const downloads = if (obj.get("downloads")) |v| @as(u64, @intCast(v.integer)) else 0;

        // Parse tags array.
        var tags_list: std.ArrayListUnmanaged([]const u8) = .empty;
        if (obj.get("tags")) |tags_val| {
            if (tags_val == .array) {
                for (tags_val.array.items) |tag| {
                    if (tag == .string) {
                        try tags_list.append(self.allocator, try self.allocator.dupe(u8, tag.string));
                    }
                }
            }
        }
        const tags = try tags_list.toOwnedSlice(self.allocator);

        // Parse versions array.
        var versions_list: std.ArrayListUnmanaged([]const u8) = .empty;
        if (obj.get("versions")) |versions_val| {
            if (versions_val == .array) {
                for (versions_val.array.items) |ver| {
                    if (ver == .string) {
                        try versions_list.append(self.allocator, try self.allocator.dupe(u8, ver.string));
                    }
                }
            }
        }
        const versions = try versions_list.toOwnedSlice(self.allocator);

        return PluginEntry{
            .name = name,
            .org = org,
            .version = version,
            .description = description,
            .author = author,
            .repository = repository,
            .tags = tags,
            .downloads = downloads,
            .versions = versions,
            .readme = readme,
            .created_at = created_at,
            .updated_at = updated_at,
        };
    }

    /// Search plugins by query string (name, description, tags).
    pub fn search(
        self: *Storage,
        query: []const u8,
        limit: usize,
        offset: usize,
    ) ![]const PluginEntry {
        var results: std.ArrayListUnmanaged(PluginEntry) = .empty;
        errdefer results.deinit(self.allocator);

        // Lowercase query for case-insensitive search.
        var lower_query_buf: [256]u8 = undefined;
        const lq = if (query.len > lower_query_buf.len)
            query[0..lower_query_buf.len]
        else
            query;
        for (lower_query_buf[0..lq.len], lq) |*dst, c| dst.* = std.ascii.toLower(c);
        const lower_query = lower_query_buf[0..lq.len];

        var it = self.plugins.valueIterator();
        while (it.next()) |entry| {
            if (query.len == 0 or self.matchesQuery(entry, lower_query)) {
                // Return a shallow copy (pointers are shared).
                try results.append(self.allocator, entry.*);
            }
        }

        // Apply pagination.
        const start = @min(offset, results.items.len);
        const end = @min(start + limit, results.items.len);
        const page = results.items[start..end];

        // Duplicate page for return.
        const owned_slice = try self.allocator.dupe(PluginEntry, page);
        results.deinit(self.allocator);

        return owned_slice;
    }

    /// Check if a plugin matches the search query.
    fn matchesQuery(self: *Storage, entry: *const PluginEntry, lower_query: []const u8) bool {
        _ = self;

        // Check name.
        var name_buf: [256]u8 = undefined;
        const name_slice = if (entry.name.len > name_buf.len)
            entry.name[0..name_buf.len]
        else
            entry.name;
        for (name_buf[0..name_slice.len], name_slice) |*dst, c| dst.* = std.ascii.toLower(c);
        if (std.mem.indexOf(u8, name_buf[0..name_slice.len], lower_query) != null)
            return true;

        // Check description.
        var desc_buf: [512]u8 = undefined;
        const desc_slice = if (entry.description.len > desc_buf.len)
            entry.description[0..desc_buf.len]
        else
            entry.description;
        for (desc_buf[0..desc_slice.len], desc_slice) |*dst, c| dst.* = std.ascii.toLower(c);
        if (std.mem.indexOf(u8, desc_buf[0..desc_slice.len], lower_query) != null)
            return true;

        // Check tags.
        for (entry.tags) |tag| {
            var tag_buf: [128]u8 = undefined;
            const tag_slice = if (tag.len > tag_buf.len) tag[0..tag_buf.len] else tag;
            for (tag_buf[0..tag_slice.len], tag_slice) |*dst, c| dst.* = std.ascii.toLower(c);
            if (std.mem.indexOf(u8, tag_buf[0..tag_slice.len], lower_query) != null)
                return true;
        }

        return false;
    }

    /// Get a plugin by org and name.
    pub fn get(self: *Storage, org: []const u8, name: []const u8) ?*const PluginEntry {
        const key_buf = std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ org, name },
        ) catch return null;
        defer self.allocator.free(key_buf);

        return self.plugins.getPtr(key_buf);
    }

    /// List all plugins with pagination.
    pub fn list(self: *Storage, limit: usize, offset: usize) ![]const PluginEntry {
        var all: std.ArrayListUnmanaged(PluginEntry) = .empty;
        defer all.deinit(self.allocator);

        var it = self.plugins.valueIterator();
        while (it.next()) |entry| {
            try all.append(self.allocator, entry.*);
        }

        const start = @min(offset, all.items.len);
        const end = @min(start + limit, all.items.len);

        return try self.allocator.dupe(PluginEntry, all.items[start..end]);
    }

    /// Get total count of plugins.
    pub fn count(self: *Storage) usize {
        return self.plugins.count();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Storage: init and deinit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_dir);

    var storage = try Storage.init(allocator, data_dir);
    defer storage.deinit();

    try std.testing.expectEqual(@as(usize, 0), storage.count());
}

test "Storage: load empty plugins.json" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create empty array.
    try tmp.dir.writeFile(.{ .sub_path = "plugins.json", .data = "[]" });

    const data_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_dir);

    var storage = try Storage.init(allocator, data_dir);
    defer storage.deinit();

    try std.testing.expectEqual(@as(usize, 0), storage.count());
}

test "Storage: load single plugin" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const json =
        \\[{
        \\  "name": "docker",
        \\  "org": "zr-plugins",
        \\  "version": "1.0.0",
        \\  "description": "Docker integration",
        \\  "author": "zr-team",
        \\  "repository": "https://github.com/zr-plugins/docker",
        \\  "tags": ["docker", "containers"],
        \\  "downloads": 100,
        \\  "versions": ["1.0.0", "0.9.0"],
        \\  "readme": "# Docker Plugin",
        \\  "created_at": "2024-01-01",
        \\  "updated_at": "2024-02-01"
        \\}]
    ;

    try tmp.dir.writeFile(.{ .sub_path = "plugins.json", .data = json });

    const data_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_dir);

    var storage = try Storage.init(allocator, data_dir);
    defer storage.deinit();

    try std.testing.expectEqual(@as(usize, 1), storage.count());

    const entry = storage.get("zr-plugins", "docker");
    try std.testing.expect(entry != null);
    try std.testing.expectEqualStrings("docker", entry.?.name);
    try std.testing.expectEqualStrings("1.0.0", entry.?.version);
}

test "Storage: search by name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const json =
        \\[
        \\  {"name": "docker", "org": "zr", "version": "1.0.0", "description": "Docker integration", "author": "zr", "repository": "", "tags": [], "downloads": 0, "versions": [], "readme": "", "created_at": "", "updated_at": ""},
        \\  {"name": "git", "org": "zr", "version": "1.0.0", "description": "Git helpers", "author": "zr", "repository": "", "tags": [], "downloads": 0, "versions": [], "readme": "", "created_at": "", "updated_at": ""}
        \\]
    ;

    try tmp.dir.writeFile(.{ .sub_path = "plugins.json", .data = json });

    const data_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_dir);

    var storage = try Storage.init(allocator, data_dir);
    defer storage.deinit();

    const results = try storage.search("dock", 10, 0);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("docker", results[0].name);
}

test "Storage: list with pagination" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const json =
        \\[
        \\  {"name": "a", "org": "zr", "version": "1.0.0", "description": "", "author": "", "repository": "", "tags": [], "downloads": 0, "versions": [], "readme": "", "created_at": "", "updated_at": ""},
        \\  {"name": "b", "org": "zr", "version": "1.0.0", "description": "", "author": "", "repository": "", "tags": [], "downloads": 0, "versions": [], "readme": "", "created_at": "", "updated_at": ""},
        \\  {"name": "c", "org": "zr", "version": "1.0.0", "description": "", "author": "", "repository": "", "tags": [], "downloads": 0, "versions": [], "readme": "", "created_at": "", "updated_at": ""}
        \\]
    ;

    try tmp.dir.writeFile(.{ .sub_path = "plugins.json", .data = json });

    const data_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(data_dir);

    var storage = try Storage.init(allocator, data_dir);
    defer storage.deinit();

    // First page.
    const page1 = try storage.list(2, 0);
    defer allocator.free(page1);
    try std.testing.expectEqual(@as(usize, 2), page1.len);

    // Second page.
    const page2 = try storage.list(2, 2);
    defer allocator.free(page2);
    try std.testing.expectEqual(@as(usize, 1), page2.len);
}
