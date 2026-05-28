const std = @import("std");

/// Project metadata context for AI agents
pub const ProjectContext = struct {
    allocator: std.mem.Allocator,
    project_graph: ProjectGraph,
    task_catalog: std.ArrayList(PackageTaskInfo),
    ownership_mapping: std.ArrayList(OwnershipEntry),
    recent_changes: RecentChanges,
    toolchains: std.ArrayList(ToolchainInfo),

    pub fn init(allocator: std.mem.Allocator) ProjectContext {
        return .{
            .allocator = allocator,
            .project_graph = ProjectGraph.init(allocator),
            .task_catalog = std.ArrayList(PackageTaskInfo){},
            .ownership_mapping = std.ArrayList(OwnershipEntry){},
            .recent_changes = RecentChanges.init(allocator),
            .toolchains = std.ArrayList(ToolchainInfo){},
        };
    }

    pub fn deinit(self: *ProjectContext) void {
        self.project_graph.deinit();

        for (self.task_catalog.items) |*item| {
            item.deinit();
        }
        self.task_catalog.deinit(self.allocator);

        for (self.ownership_mapping.items) |*item| {
            self.allocator.free(item.path);
            for (item.owners.items) |owner| {
                self.allocator.free(owner);
            }
            item.owners.deinit(self.allocator);
        }
        self.ownership_mapping.deinit(self.allocator);

        self.recent_changes.deinit();

        for (self.toolchains.items) |*tc| {
            self.allocator.free(tc.name);
            self.allocator.free(tc.version);
            if (tc.install_path) |path| {
                self.allocator.free(path);
            }
        }
        self.toolchains.deinit(self.allocator);
    }
};

/// Project dependency graph
pub const ProjectGraph = struct {
    allocator: std.mem.Allocator,
    packages: std.ArrayList(PackageNode),

    pub fn init(allocator: std.mem.Allocator) ProjectGraph {
        return .{
            .allocator = allocator,
            .packages = std.ArrayList(PackageNode){},
        };
    }

    pub fn deinit(self: *ProjectGraph) void {
        for (self.packages.items) |*pkg| {
            pkg.deinit();
        }
        self.packages.deinit(self.allocator);
    }
};

/// A package/project node in the dependency graph
pub const PackageNode = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    path: []const u8,
    dependencies: std.ArrayList([]const u8),
    tags: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8) !PackageNode {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .dependencies = std.ArrayList([]const u8){},
            .tags = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *PackageNode) void {
        self.allocator.free(self.name);
        self.allocator.free(self.path);

        for (self.dependencies.items) |dep| {
            self.allocator.free(dep);
        }
        self.dependencies.deinit(self.allocator);

        for (self.tags.items) |tag| {
            self.allocator.free(tag);
        }
        self.tags.deinit(self.allocator);
    }
};

/// Task information for a package
pub const PackageTaskInfo = struct {
    allocator: std.mem.Allocator,
    package_name: []const u8,
    tasks: std.ArrayList(TaskInfo),

    pub fn init(allocator: std.mem.Allocator, package_name: []const u8) !PackageTaskInfo {
        return .{
            .allocator = allocator,
            .package_name = try allocator.dupe(u8, package_name),
            .tasks = std.ArrayList(TaskInfo){},
        };
    }

    pub fn deinit(self: *PackageTaskInfo) void {
        self.allocator.free(self.package_name);

        for (self.tasks.items) |*task| {
            task.deinit();
        }
        self.tasks.deinit(self.allocator);
    }
};

/// Individual task information
pub const TaskInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: ?[]const u8,
    cmd: []const u8,
    dependencies: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, cmd: []const u8, description: ?[]const u8) !TaskInfo {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .cmd = try allocator.dupe(u8, cmd),
            .description = if (description) |desc| try allocator.dupe(u8, desc) else null,
            .dependencies = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *TaskInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.cmd);
        if (self.description) |desc| {
            self.allocator.free(desc);
        }

        for (self.dependencies.items) |dep| {
            self.allocator.free(dep);
        }
        self.dependencies.deinit(self.allocator);
    }
};

/// File ownership mapping entry
pub const OwnershipEntry = struct {
    path: []const u8,
    owners: std.ArrayList([]const u8),
};

/// Recent changes summary
pub const RecentChanges = struct {
    allocator: std.mem.Allocator,
    affected_packages: std.ArrayList([]const u8),
    commit_count: usize,
    files_changed: usize,
    time_range_days: usize,

    pub fn init(allocator: std.mem.Allocator) RecentChanges {
        return .{
            .allocator = allocator,
            .affected_packages = std.ArrayList([]const u8){},
            .commit_count = 0,
            .files_changed = 0,
            .time_range_days = 7, // Default: last 7 days
        };
    }

    pub fn deinit(self: *RecentChanges) void {
        for (self.affected_packages.items) |pkg| {
            self.allocator.free(pkg);
        }
        self.affected_packages.deinit(self.allocator);
    }
};

/// Toolchain information
pub const ToolchainInfo = struct {
    name: []const u8, // e.g., "node", "python", "zig"
    version: []const u8, // e.g., "20.10.0"
    install_path: ?[]const u8,
};

test "ProjectContext init/deinit" {
    const allocator = std.testing.allocator;
    var ctx = ProjectContext.init(allocator);
    defer ctx.deinit();

    // Verify initial state is empty
    try std.testing.expectEqual(@as(usize, 0), ctx.task_catalog.items.len);
    try std.testing.expectEqual(@as(usize, 0), ctx.ownership_mapping.items.len);
    try std.testing.expectEqual(@as(usize, 0), ctx.toolchains.items.len);

    // Add a task to the catalog and verify it's stored
    var task_info = try PackageTaskInfo.init(allocator, "mypackage");
    const task = try TaskInfo.init(allocator, "build", "npm run build", "Build task");
    try task_info.tasks.append(allocator, task);
    try ctx.task_catalog.append(allocator, task_info);

    try std.testing.expectEqual(@as(usize, 1), ctx.task_catalog.items.len);
    try std.testing.expectEqualStrings("mypackage", ctx.task_catalog.items[0].package_name);

    // Add ownership entry and verify
    var owners = std.ArrayList([]const u8){};
    try owners.append(allocator, try allocator.dupe(u8, "alice"));
    try ctx.ownership_mapping.append(allocator, .{
        .path = try allocator.dupe(u8, "src/main.ts"),
        .owners = owners,
    });

    try std.testing.expectEqual(@as(usize, 1), ctx.ownership_mapping.items.len);
    try std.testing.expectEqualStrings("src/main.ts", ctx.ownership_mapping.items[0].path);

    // Add toolchain and verify (using allocated strings)
    try ctx.toolchains.append(allocator, .{
        .name = try allocator.dupe(u8, "node"),
        .version = try allocator.dupe(u8, "20.10.0"),
        .install_path = null,
    });

    try std.testing.expectEqual(@as(usize, 1), ctx.toolchains.items.len);
    try std.testing.expectEqualStrings("node", ctx.toolchains.items[0].name);
}

test "PackageNode init/deinit" {
    const allocator = std.testing.allocator;
    var node = try PackageNode.init(allocator, "my-package", "packages/my-package");
    defer node.deinit();

    try std.testing.expectEqualStrings("my-package", node.name);
    try std.testing.expectEqualStrings("packages/my-package", node.path);
}

test "TaskInfo init/deinit" {
    const allocator = std.testing.allocator;
    var task = try TaskInfo.init(allocator, "build", "npm run build", "Build the project");
    defer task.deinit();

    try std.testing.expectEqualStrings("build", task.name);
    try std.testing.expectEqualStrings("npm run build", task.cmd);
    try std.testing.expect(task.description != null);
    try std.testing.expectEqualStrings("Build the project", task.description.?);
}
