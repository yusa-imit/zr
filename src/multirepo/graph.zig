const std = @import("std");
const types = @import("../config/types.zig");
const RepoConfig = types.RepoConfig;
const RepoWorkspaceConfig = types.RepoWorkspaceConfig;

/// Node in the cross-repo dependency graph.
pub const RepoGraphNode = struct {
    /// Repository name.
    name: []const u8,
    /// Direct dependencies (other repo names).
    dependencies: [][]const u8,
    /// Repositories that depend on this one (reverse dependencies).
    dependents: [][]const u8,
    /// Repository tags for filtering.
    tags: [][]const u8,
    /// Local path to the repository.
    path: []const u8,

    pub fn deinit(self: *RepoGraphNode, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.dependencies) |dep| allocator.free(dep);
        allocator.free(self.dependencies);
        for (self.dependents) |dep| allocator.free(dep);
        allocator.free(self.dependents);
        for (self.tags) |tag| allocator.free(tag);
        allocator.free(self.tags);
        allocator.free(self.path);
    }
};

/// Cross-repo dependency graph.
pub const RepoGraph = struct {
    /// Map of repo name -> graph node.
    nodes: std.StringHashMap(RepoGraphNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RepoGraph {
        return .{
            .nodes = std.StringHashMap(RepoGraphNode).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RepoGraph) void {
        var it = self.nodes.valueIterator();
        while (it.next()) |node| {
            var mutable_node = node.*;
            mutable_node.deinit(self.allocator);
        }
        self.nodes.deinit();
    }
};

/// Build a cross-repo dependency graph from workspace configuration.
pub fn buildRepoGraph(allocator: std.mem.Allocator, config: *const RepoWorkspaceConfig) !RepoGraph {
    var graph = RepoGraph.init(allocator);
    errdefer graph.deinit();

    // First pass: create nodes for all repositories
    for (config.repos) |repo| {
        const name = try allocator.dupe(u8, repo.name);
        errdefer allocator.free(name);

        const path = try allocator.dupe(u8, repo.path);
        errdefer allocator.free(path);

        var tags = try allocator.alloc([]const u8, repo.tags.len);
        errdefer allocator.free(tags);
        for (repo.tags, 0..) |tag, i| {
            tags[i] = try allocator.dupe(u8, tag);
        }

        const node = RepoGraphNode{
            .name = name,
            .dependencies = &.{},
            .dependents = &.{},
            .tags = tags,
            .path = path,
        };

        try graph.nodes.put(name, node);
    }

    // Second pass: populate dependencies from config.dependencies
    var dep_it = config.dependencies.iterator();
    while (dep_it.next()) |entry| {
        const repo_name = entry.key_ptr.*;
        const deps = entry.value_ptr.*;

        if (graph.nodes.getPtr(repo_name)) |node| {
            var deps_list = std.ArrayList([]const u8){};
            defer deps_list.deinit(allocator);

            for (deps) |dep| {
                const dep_name = try allocator.dupe(u8, dep);
                try deps_list.append(allocator, dep_name);
            }

            node.dependencies = try deps_list.toOwnedSlice(allocator);
        }
    }

    // Third pass: compute reverse dependencies (dependents)
    var node_it = graph.nodes.iterator();
    while (node_it.next()) |entry| {
        const repo_name = entry.key_ptr.*;
        const node = entry.value_ptr;

        for (node.dependencies) |dep_name| {
            if (graph.nodes.getPtr(dep_name)) |dep_node| {
                // Add repo_name to dep_node's dependents
                var dependents_list = std.ArrayList([]const u8){};
                defer dependents_list.deinit(allocator);

                for (dep_node.dependents) |existing| {
                    const dup = try allocator.dupe(u8, existing);
                    try dependents_list.append(allocator, dup);
                }

                const new_dependent = try allocator.dupe(u8, repo_name);
                try dependents_list.append(allocator, new_dependent);

                // Free old dependents
                for (dep_node.dependents) |old| {
                    allocator.free(old);
                }
                allocator.free(dep_node.dependents);

                dep_node.dependents = try dependents_list.toOwnedSlice(allocator);
            }
        }
    }

    return graph;
}

/// Detect cycles in the cross-repo dependency graph.
pub fn detectCycles(graph: *const RepoGraph, allocator: std.mem.Allocator) !?[][]const u8 {
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    var rec_stack = std.StringHashMap(void).init(allocator);
    defer rec_stack.deinit();

    var path = std.ArrayList([]const u8){};
    defer path.deinit(allocator);

    var it = graph.nodes.keyIterator();
    while (it.next()) |name| {
        if (visited.contains(name.*)) continue;

        if (try detectCyclesDFS(graph, name.*, &visited, &rec_stack, &path, allocator)) {
            return try path.toOwnedSlice(allocator);
        }
    }

    return null;
}

fn detectCyclesDFS(
    graph: *const RepoGraph,
    node_name: []const u8,
    visited: *std.StringHashMap(void),
    rec_stack: *std.StringHashMap(void),
    path: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !bool {
    try visited.put(node_name, {});
    try rec_stack.put(node_name, {});
    try path.append(allocator, node_name);

    if (graph.nodes.get(node_name)) |node| {
        for (node.dependencies) |dep| {
            if (!visited.contains(dep)) {
                if (try detectCyclesDFS(graph, dep, visited, rec_stack, path, allocator)) {
                    return true;
                }
            } else if (rec_stack.contains(dep)) {
                // Cycle detected
                try path.append(allocator, dep);
                return true;
            }
        }
    }

    _ = rec_stack.remove(node_name);
    _ = path.pop();
    return false;
}

/// Get topological sort of repositories (respecting dependencies).
pub fn topologicalSort(graph: *const RepoGraph, allocator: std.mem.Allocator) ![][]const u8 {
    var in_degree = std.StringHashMap(usize).init(allocator);
    defer in_degree.deinit();

    var queue = std.ArrayList([]const u8){};
    defer queue.deinit(allocator);

    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    // Calculate in-degrees
    var it = graph.nodes.iterator();
    while (it.next()) |entry| {
        try in_degree.put(entry.key_ptr.*, entry.value_ptr.dependencies.len);
        if (entry.value_ptr.dependencies.len == 0) {
            try queue.append(allocator, entry.key_ptr.*);
        }
    }

    // Kahn's algorithm
    while (queue.items.len > 0) {
        const node_name = queue.orderedRemove(0);
        const name_dup = try allocator.dupe(u8, node_name);
        try result.append(allocator, name_dup);

        if (graph.nodes.get(node_name)) |node| {
            for (node.dependents) |dependent| {
                if (in_degree.getPtr(dependent)) |deg| {
                    deg.* -= 1;
                    if (deg.* == 0) {
                        try queue.append(allocator, dependent);
                    }
                }
            }
        }
    }

    // Check if all nodes were processed (cycle detection)
    if (result.items.len != graph.nodes.count()) {
        result.deinit(allocator);
        return error.CycleDetected;
    }

    return try result.toOwnedSlice(allocator);
}

/// Filter repositories by tags.
pub fn filterByTags(graph: *const RepoGraph, tags: []const []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var filtered = std.ArrayList([]const u8){};
    errdefer filtered.deinit(allocator);

    var it = graph.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.value_ptr;
        const node_name = entry.key_ptr.*;

        // Check if node has any of the requested tags
        var has_tag = false;
        for (tags) |tag| {
            for (node.tags) |node_tag| {
                if (std.mem.eql(u8, tag, node_tag)) {
                    has_tag = true;
                    break;
                }
            }
            if (has_tag) break;
        }

        if (has_tag) {
            const name = try allocator.dupe(u8, node_name);
            try filtered.append(allocator, name);
        }
    }

    return try filtered.toOwnedSlice(allocator);
}

// ========== Tests ==========

test "buildRepoGraph - empty config" {
    const allocator = std.testing.allocator;

    var config = RepoWorkspaceConfig.init(allocator);
    defer config.deinit(allocator);

    var graph = try buildRepoGraph(allocator, &config);
    defer graph.deinit();

    try std.testing.expectEqual(@as(usize, 0), graph.nodes.count());
}

test "buildRepoGraph - single repo no deps" {
    const allocator = std.testing.allocator;

    var config = RepoWorkspaceConfig.init(allocator);
    defer config.dependencies.deinit();

    const api_name = try allocator.dupe(u8, "api");
    const api_url = try allocator.dupe(u8, "https://github.com/org/api");
    const api_path = try allocator.dupe(u8, "./repos/api");
    const api_branch = try allocator.dupe(u8, "main");

    var repos = [_]RepoConfig{
        .{
            .name = api_name,
            .url = api_url,
            .path = api_path,
            .branch = api_branch,
            .tags = &.{},
        },
    };
    config.repos = &repos;

    var graph = try buildRepoGraph(allocator, &config);
    defer graph.deinit();

    try std.testing.expectEqual(@as(usize, 1), graph.nodes.count());
    const node = graph.nodes.get("api").?;
    try std.testing.expectEqualStrings("api", node.name);
    try std.testing.expectEqual(@as(usize, 0), node.dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), node.dependents.len);

    // Cleanup
    allocator.free(api_name);
    allocator.free(api_url);
    allocator.free(api_path);
    allocator.free(api_branch);
}

test "buildRepoGraph - multiple repos with deps" {
    const allocator = std.testing.allocator;

    var config = RepoWorkspaceConfig.init(allocator);
    defer config.dependencies.deinit();

    const api_name = try allocator.dupe(u8, "api");
    const api_url = try allocator.dupe(u8, "https://github.com/org/api");
    const api_path = try allocator.dupe(u8, "./repos/api");
    const api_branch = try allocator.dupe(u8, "main");
    const web_name = try allocator.dupe(u8, "web");
    const web_url = try allocator.dupe(u8, "https://github.com/org/web");
    const web_path = try allocator.dupe(u8, "./repos/web");
    const web_branch = try allocator.dupe(u8, "main");

    var repos = [_]RepoConfig{
        .{
            .name = api_name,
            .url = api_url,
            .path = api_path,
            .branch = api_branch,
            .tags = &.{},
        },
        .{
            .name = web_name,
            .url = web_url,
            .path = web_path,
            .branch = web_branch,
            .tags = &.{},
        },
    };
    config.repos = &repos;

    // web depends on api
    var api_deps = [_][]const u8{};
    var web_deps = [_][]const u8{try allocator.dupe(u8, "api")};
    defer allocator.free(web_deps[0]);

    try config.dependencies.put("api", &api_deps);
    try config.dependencies.put("web", &web_deps);

    var graph = try buildRepoGraph(allocator, &config);
    defer graph.deinit();

    try std.testing.expectEqual(@as(usize, 2), graph.nodes.count());

    const api_node = graph.nodes.get("api").?;
    try std.testing.expectEqual(@as(usize, 0), api_node.dependencies.len);
    try std.testing.expectEqual(@as(usize, 1), api_node.dependents.len);
    try std.testing.expectEqualStrings("web", api_node.dependents[0]);

    const web_node = graph.nodes.get("web").?;
    try std.testing.expectEqual(@as(usize, 1), web_node.dependencies.len);
    try std.testing.expectEqualStrings("api", web_node.dependencies[0]);
    try std.testing.expectEqual(@as(usize, 0), web_node.dependents.len);

    // Cleanup
    allocator.free(api_name);
    allocator.free(api_url);
    allocator.free(api_path);
    allocator.free(api_branch);
    allocator.free(web_name);
    allocator.free(web_url);
    allocator.free(web_path);
    allocator.free(web_branch);
}

test "detectCycles - no cycle" {
    const allocator = std.testing.allocator;

    var config = RepoWorkspaceConfig.init(allocator);
    defer config.dependencies.deinit();

    const api_name = try allocator.dupe(u8, "api");
    const api_url = try allocator.dupe(u8, "https://github.com/org/api");
    const api_path = try allocator.dupe(u8, "./repos/api");
    const api_branch = try allocator.dupe(u8, "main");
    const web_name = try allocator.dupe(u8, "web");
    const web_url = try allocator.dupe(u8, "https://github.com/org/web");
    const web_path = try allocator.dupe(u8, "./repos/web");
    const web_branch = try allocator.dupe(u8, "main");

    var repos = [_]RepoConfig{
        .{
            .name = api_name,
            .url = api_url,
            .path = api_path,
            .branch = api_branch,
            .tags = &.{},
        },
        .{
            .name = web_name,
            .url = web_url,
            .path = web_path,
            .branch = web_branch,
            .tags = &.{},
        },
    };
    config.repos = &repos;

    var api_deps = [_][]const u8{};
    var web_deps = [_][]const u8{try allocator.dupe(u8, "api")};
    defer allocator.free(web_deps[0]);

    try config.dependencies.put("api", &api_deps);
    try config.dependencies.put("web", &web_deps);

    var graph = try buildRepoGraph(allocator, &config);
    defer graph.deinit();

    const cycle = try detectCycles(&graph, allocator);
    try std.testing.expect(cycle == null);

    // Cleanup
    allocator.free(api_name);
    allocator.free(api_url);
    allocator.free(api_path);
    allocator.free(api_branch);
    allocator.free(web_name);
    allocator.free(web_url);
    allocator.free(web_path);
    allocator.free(web_branch);
}

test "topologicalSort - simple chain" {
    const allocator = std.testing.allocator;

    var config = RepoWorkspaceConfig.init(allocator);
    defer config.dependencies.deinit();

    const api_name = try allocator.dupe(u8, "api");
    const api_url = try allocator.dupe(u8, "https://github.com/org/api");
    const api_path = try allocator.dupe(u8, "./repos/api");
    const api_branch = try allocator.dupe(u8, "main");
    const web_name = try allocator.dupe(u8, "web");
    const web_url = try allocator.dupe(u8, "https://github.com/org/web");
    const web_path = try allocator.dupe(u8, "./repos/web");
    const web_branch = try allocator.dupe(u8, "main");

    var repos = [_]RepoConfig{
        .{
            .name = api_name,
            .url = api_url,
            .path = api_path,
            .branch = api_branch,
            .tags = &.{},
        },
        .{
            .name = web_name,
            .url = web_url,
            .path = web_path,
            .branch = web_branch,
            .tags = &.{},
        },
    };
    config.repos = &repos;

    var api_deps = [_][]const u8{};
    var web_deps = [_][]const u8{try allocator.dupe(u8, "api")};
    defer allocator.free(web_deps[0]);

    try config.dependencies.put("api", &api_deps);
    try config.dependencies.put("web", &web_deps);

    var graph = try buildRepoGraph(allocator, &config);
    defer graph.deinit();

    const sorted = try topologicalSort(&graph, allocator);
    defer {
        for (sorted) |name| allocator.free(name);
        allocator.free(sorted);
    }

    try std.testing.expectEqual(@as(usize, 2), sorted.len);
    try std.testing.expectEqualStrings("api", sorted[0]);
    try std.testing.expectEqualStrings("web", sorted[1]);

    // Cleanup
    allocator.free(api_name);
    allocator.free(api_url);
    allocator.free(api_path);
    allocator.free(api_branch);
    allocator.free(web_name);
    allocator.free(web_url);
    allocator.free(web_path);
    allocator.free(web_branch);
}

test "filterByTags - single tag match" {
    const allocator = std.testing.allocator;

    var config = RepoWorkspaceConfig.init(allocator);
    defer config.dependencies.deinit();

    const backend_tag = try allocator.dupe(u8, "backend");
    defer allocator.free(backend_tag);

    var api_tags = [_][]const u8{backend_tag};

    const api_name = try allocator.dupe(u8, "api");
    const api_url = try allocator.dupe(u8, "https://github.com/org/api");
    const api_path = try allocator.dupe(u8, "./repos/api");
    const api_branch = try allocator.dupe(u8, "main");
    const web_name = try allocator.dupe(u8, "web");
    const web_url = try allocator.dupe(u8, "https://github.com/org/web");
    const web_path = try allocator.dupe(u8, "./repos/web");
    const web_branch = try allocator.dupe(u8, "main");

    var repos = [_]RepoConfig{
        .{
            .name = api_name,
            .url = api_url,
            .path = api_path,
            .branch = api_branch,
            .tags = &api_tags,
        },
        .{
            .name = web_name,
            .url = web_url,
            .path = web_path,
            .branch = web_branch,
            .tags = &.{},
        },
    };
    config.repos = &repos;

    var graph = try buildRepoGraph(allocator, &config);
    defer graph.deinit();

    var filter_tags = [_][]const u8{"backend"};
    const filtered = try filterByTags(&graph, &filter_tags, allocator);
    defer {
        for (filtered) |name| allocator.free(name);
        allocator.free(filtered);
    }

    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("api", filtered[0]);

    // Cleanup
    allocator.free(api_name);
    allocator.free(api_url);
    allocator.free(api_path);
    allocator.free(api_branch);
    allocator.free(web_name);
    allocator.free(web_url);
    allocator.free(web_path);
    allocator.free(web_branch);
}
