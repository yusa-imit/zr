const std = @import("std");

/// Plugin metadata returned from registry search/list.
pub const PluginEntry = struct {
    name: []const u8,
    org: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    repository: []const u8,
    tags: []const []const u8,
    downloads: u64,
    updated_at: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PluginEntry) void {
        self.allocator.free(self.name);
        self.allocator.free(self.org);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        self.allocator.free(self.author);
        self.allocator.free(self.repository);
        for (self.tags) |tag| self.allocator.free(tag);
        self.allocator.free(self.tags);
        self.allocator.free(self.updated_at);
    }
};

/// Search result from registry API.
pub const SearchResult = struct {
    total: usize,
    offset: usize,
    limit: usize,
    plugins: []PluginEntry,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SearchResult) void {
        for (self.plugins) |*p| p.deinit();
        self.allocator.free(self.plugins);
    }
};

/// Detailed plugin information.
pub const PluginDetails = struct {
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
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PluginDetails) void {
        self.allocator.free(self.name);
        self.allocator.free(self.org);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        self.allocator.free(self.author);
        self.allocator.free(self.repository);
        for (self.tags) |tag| self.allocator.free(tag);
        self.allocator.free(self.tags);
        for (self.versions) |v| self.allocator.free(v);
        self.allocator.free(self.versions);
        self.allocator.free(self.readme);
        self.allocator.free(self.created_at);
        self.allocator.free(self.updated_at);
    }
};

pub const RegistryClientError = error{
    NetworkError,
    InvalidResponse,
    NotFound,
    RateLimited,
    ServerError,
};

/// Default registry base URL.
pub const default_registry_url = "https://registry.zr.dev";

/// Configuration for registry client.
pub const Config = struct {
    base_url: []const u8 = default_registry_url,
    timeout_ms: u32 = 10000,
    user_agent: []const u8 = "zr/1.4.0",
};

/// HTTP registry client for querying plugin metadata.
pub const Client = struct {
    allocator: std.mem.Allocator,
    config: Config,

    pub fn init(allocator: std.mem.Allocator, config: Config) Client {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Search for plugins in the registry.
    pub fn search(
        self: *Client,
        query: []const u8,
        limit: ?usize,
        offset: ?usize,
    ) !SearchResult {
        // Build query parameters.
        const limit_str = try std.fmt.allocPrint(
            self.allocator,
            "{d}",
            .{limit orelse 50},
        );
        defer self.allocator.free(limit_str);

        const offset_str = try std.fmt.allocPrint(
            self.allocator,
            "{d}",
            .{offset orelse 0},
        );
        defer self.allocator.free(offset_str);

        // URL-encode the query.
        const encoded_query = try urlEncode(self.allocator, query);
        defer self.allocator.free(encoded_query);

        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1/plugins/search?q={s}&limit={s}&offset={s}",
            .{ self.config.base_url, encoded_query, limit_str, offset_str },
        );
        defer self.allocator.free(url);

        const response = try self.get(url);
        defer self.allocator.free(response);

        return try parseSearchResponse(self.allocator, response);
    }

    /// Get detailed information about a specific plugin.
    pub fn getPlugin(
        self: *Client,
        org: []const u8,
        name: []const u8,
    ) !PluginDetails {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1/plugins/{s}/{s}",
            .{ self.config.base_url, org, name },
        );
        defer self.allocator.free(url);

        const response = try self.get(url);
        defer self.allocator.free(response);

        return try parsePluginDetails(self.allocator, response);
    }

    /// List all plugins with pagination.
    pub fn list(
        self: *Client,
        limit: ?usize,
        offset: ?usize,
    ) !SearchResult {
        const limit_str = try std.fmt.allocPrint(
            self.allocator,
            "{d}",
            .{limit orelse 50},
        );
        defer self.allocator.free(limit_str);

        const offset_str = try std.fmt.allocPrint(
            self.allocator,
            "{d}",
            .{offset orelse 0},
        );
        defer self.allocator.free(offset_str);

        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1/plugins?limit={s}&offset={s}",
            .{ self.config.base_url, limit_str, offset_str },
        );
        defer self.allocator.free(url);

        const response = try self.get(url);
        defer self.allocator.free(response);

        return try parseSearchResponse(self.allocator, response);
    }

    /// Perform a GET request to the registry.
    fn get(self: *Client, url: []const u8) ![]const u8 {
        // Parse URL to extract host and path.
        const uri = std.Uri.parse(url) catch return RegistryClientError.InvalidResponse;

        // Connect to the server.
        const host = uri.host orelse return RegistryClientError.NetworkError;
        const port: u16 = uri.port orelse if (std.mem.eql(u8, uri.scheme, "https")) 443 else 80;

        // For now, we'll use a simple HTTP/1.1 implementation.
        // In production, this would use std.http.Client or a dedicated HTTP library.
        const address_list = std.net.getAddressList(self.allocator, host.percent_encoded, port) catch
            return RegistryClientError.NetworkError;
        defer address_list.deinit();

        if (address_list.addrs.len == 0) return RegistryClientError.NetworkError;

        const stream = std.net.tcpConnectToAddress(address_list.addrs[0]) catch
            return RegistryClientError.NetworkError;
        defer stream.close();

        // Build HTTP request.
        const path = uri.path.percent_encoded;
        const query_str = if (uri.query) |q| q.percent_encoded else "";
        const request_path = if (query_str.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}?{s}", .{ path, query_str })
        else
            try self.allocator.dupe(u8, path);
        defer self.allocator.free(request_path);

        const request = try std.fmt.allocPrint(
            self.allocator,
            "GET {s} HTTP/1.1\r\n" ++
                "Host: {s}\r\n" ++
                "User-Agent: {s}\r\n" ++
                "Accept: application/json\r\n" ++
                "Connection: close\r\n" ++
                "\r\n",
            .{ request_path, host.percent_encoded, self.config.user_agent },
        );
        defer self.allocator.free(request);

        // Send request.
        _ = stream.writeAll(request) catch return RegistryClientError.NetworkError;

        // Read response.
        var response_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer response_buf.deinit(self.allocator);

        var buf: [4096]u8 = undefined;
        while (true) {
            const n = stream.read(&buf) catch return RegistryClientError.NetworkError;
            if (n == 0) break;
            try response_buf.appendSlice(self.allocator, buf[0..n]);
        }

        const response = response_buf.items;

        // Parse HTTP response.
        const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse
            return RegistryClientError.InvalidResponse;
        const body = response[header_end + 4 ..];

        // Check status code.
        const status_line_end = std.mem.indexOf(u8, response, "\r\n") orelse
            return RegistryClientError.InvalidResponse;
        const status_line = response[0..status_line_end];

        if (std.mem.indexOf(u8, status_line, "404") != null) {
            return RegistryClientError.NotFound;
        }
        if (std.mem.indexOf(u8, status_line, "429") != null) {
            return RegistryClientError.RateLimited;
        }
        if (std.mem.indexOf(u8, status_line, "500") != null or
            std.mem.indexOf(u8, status_line, "502") != null or
            std.mem.indexOf(u8, status_line, "503") != null)
        {
            return RegistryClientError.ServerError;
        }
        if (std.mem.indexOf(u8, status_line, "200") == null) {
            return RegistryClientError.InvalidResponse;
        }

        return try self.allocator.dupe(u8, body);
    }
};

/// URL-encode a string (simple implementation for query parameters).
fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);

    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(allocator, c);
        } else if (c == ' ') {
            try result.append(allocator, '+');
        } else {
            const encoded = try std.fmt.allocPrint(allocator, "%{X:0>2}", .{c});
            defer allocator.free(encoded);
            try result.appendSlice(allocator, encoded);
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Parse search response JSON.
fn parseSearchResponse(allocator: std.mem.Allocator, json: []const u8) !SearchResult {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;
    const total = @as(usize, @intCast(root.get("total").?.integer));
    const offset = @as(usize, @intCast(root.get("offset").?.integer));
    const limit = @as(usize, @intCast(root.get("limit").?.integer));

    const plugins_array = root.get("plugins").?.array;
    var plugins: std.ArrayListUnmanaged(PluginEntry) = .empty;
    errdefer {
        for (plugins.items) |*p| p.deinit();
        plugins.deinit(allocator);
    }

    for (plugins_array.items) |item| {
        const obj = item.object;
        const entry = PluginEntry{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .org = try allocator.dupe(u8, obj.get("org").?.string),
            .version = try allocator.dupe(u8, obj.get("version").?.string),
            .description = try allocator.dupe(u8, obj.get("description").?.string),
            .author = try allocator.dupe(u8, obj.get("author").?.string),
            .repository = try allocator.dupe(u8, obj.get("repository").?.string),
            .tags = blk: {
                const tags_arr = obj.get("tags").?.array;
                var tags = try allocator.alloc([]const u8, tags_arr.items.len);
                for (tags_arr.items, 0..) |tag, i| {
                    tags[i] = try allocator.dupe(u8, tag.string);
                }
                break :blk tags;
            },
            .downloads = @as(u64, @intCast(obj.get("downloads").?.integer)),
            .updated_at = try allocator.dupe(u8, obj.get("updated_at").?.string),
            .allocator = allocator,
        };
        try plugins.append(allocator, entry);
    }

    return SearchResult{
        .total = total,
        .offset = offset,
        .limit = limit,
        .plugins = try plugins.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Parse plugin details JSON.
fn parsePluginDetails(allocator: std.mem.Allocator, json: []const u8) !PluginDetails {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const obj = parsed.value.object;

    return PluginDetails{
        .name = try allocator.dupe(u8, obj.get("name").?.string),
        .org = try allocator.dupe(u8, obj.get("org").?.string),
        .version = try allocator.dupe(u8, obj.get("version").?.string),
        .description = try allocator.dupe(u8, obj.get("description").?.string),
        .author = try allocator.dupe(u8, obj.get("author").?.string),
        .repository = try allocator.dupe(u8, obj.get("repository").?.string),
        .tags = blk: {
            const tags_arr = obj.get("tags").?.array;
            var tags = try allocator.alloc([]const u8, tags_arr.items.len);
            for (tags_arr.items, 0..) |tag, i| {
                tags[i] = try allocator.dupe(u8, tag.string);
            }
            break :blk tags;
        },
        .downloads = @as(u64, @intCast(obj.get("downloads").?.integer)),
        .versions = blk: {
            const vers_arr = obj.get("versions").?.array;
            var vers = try allocator.alloc([]const u8, vers_arr.items.len);
            for (vers_arr.items, 0..) |v, i| {
                vers[i] = try allocator.dupe(u8, v.string);
            }
            break :blk vers;
        },
        .readme = try allocator.dupe(u8, obj.get("readme").?.string),
        .created_at = try allocator.dupe(u8, obj.get("created_at").?.string),
        .updated_at = try allocator.dupe(u8, obj.get("updated_at").?.string),
        .allocator = allocator,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "urlEncode: basic string" {
    const allocator = std.testing.allocator;
    const encoded = try urlEncode(allocator, "hello world");
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("hello+world", encoded);
}

test "urlEncode: special characters" {
    const allocator = std.testing.allocator;
    const encoded = try urlEncode(allocator, "foo@bar.com");
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("foo%40bar.com", encoded);
}

test "parseSearchResponse: valid JSON" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "total": 1,
        \\  "offset": 0,
        \\  "limit": 50,
        \\  "plugins": [
        \\    {
        \\      "name": "docker",
        \\      "org": "zr-runner",
        \\      "version": "1.2.0",
        \\      "description": "Docker plugin",
        \\      "author": "ZR Team",
        \\      "repository": "https://github.com/zr-runner/zr-plugin-docker",
        \\      "tags": ["docker", "ci"],
        \\      "downloads": 1234,
        \\      "updated_at": "2026-03-01T12:00:00Z"
        \\    }
        \\  ]
        \\}
    ;

    var result = try parseSearchResponse(allocator, json);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.total);
    try std.testing.expectEqual(@as(usize, 0), result.offset);
    try std.testing.expectEqual(@as(usize, 50), result.limit);
    try std.testing.expectEqual(@as(usize, 1), result.plugins.len);

    const plugin = result.plugins[0];
    try std.testing.expectEqualStrings("docker", plugin.name);
    try std.testing.expectEqualStrings("zr-runner", plugin.org);
    try std.testing.expectEqualStrings("1.2.0", plugin.version);
    try std.testing.expectEqual(@as(u64, 1234), plugin.downloads);
    try std.testing.expectEqual(@as(usize, 2), plugin.tags.len);
}

test "parsePluginDetails: valid JSON" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "name": "docker",
        \\  "org": "zr-runner",
        \\  "version": "1.2.0",
        \\  "description": "Docker plugin",
        \\  "author": "ZR Team",
        \\  "repository": "https://github.com/zr-runner/zr-plugin-docker",
        \\  "tags": ["docker"],
        \\  "downloads": 1234,
        \\  "versions": ["1.2.0", "1.1.0"],
        \\  "readme": "# Docker Plugin",
        \\  "created_at": "2025-12-15T10:00:00Z",
        \\  "updated_at": "2026-03-01T12:00:00Z"
        \\}
    ;

    var details = try parsePluginDetails(allocator, json);
    defer details.deinit();

    try std.testing.expectEqualStrings("docker", details.name);
    try std.testing.expectEqualStrings("zr-runner", details.org);
    try std.testing.expectEqual(@as(usize, 2), details.versions.len);
    try std.testing.expectEqualStrings("# Docker Plugin", details.readme);
}
