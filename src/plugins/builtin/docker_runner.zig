const std = @import("std");
const PluginInterface = @import("../mod.zig").PluginInterface;
const PluginError = @import("../mod.zig").PluginError;

// Docker container task runner plugin
// Allows running tasks inside Docker containers for consistent environments

pub const plugin_interface = PluginInterface{
    .name = "docker-runner",
    .version = "1.0.0", 
    .description = "Docker container task runner for ZR",
    .author = "ZR Core Team",
    
    .init = init,
    .deinit = deinit,
    
    .beforeTask = beforeTask,
    .afterTask = afterTask,
    .beforePipeline = null,
    .afterPipeline = null,
    .onResourceLimit = null,
    
    .validateConfig = validateConfig,
};

var allocator: ?std.mem.Allocator = null;
var docker_enabled: bool = false;
var default_image: ?[]const u8 = null;
var auto_pull: bool = true;
var network_mode: ?[]const u8 = null;
var mount_workspace: bool = true;

fn init(alloc: std.mem.Allocator, config: []const u8) PluginError!void {
    allocator = alloc;
    
    // Parse plugin configuration
    if (config.len > 0) {
        if (std.mem.indexOf(u8, config, "enabled: true")) |_| {
            docker_enabled = true;
        }
        if (std.mem.indexOf(u8, config, "auto_pull: false")) |_| {
            auto_pull = false;
        }
        if (std.mem.indexOf(u8, config, "mount_workspace: false")) |_| {
            mount_workspace = false;
        }
        
        // Parse default image
        if (std.mem.indexOf(u8, config, "default_image:")) |start| {
            const line_start = start;
            const line_end = std.mem.indexOf(u8, config[line_start..], "\n") orelse config.len;
            const line = config[line_start..line_start + line_end];
            
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const value_start = colon_pos + 2;
                if (value_start < line.len) {
                    const value = std.mem.trim(u8, line[value_start..], " \t\"'");
                    default_image = try alloc.dupe(u8, value);
                }
            }
        }
        
        // Parse network mode
        if (std.mem.indexOf(u8, config, "network_mode:")) |start| {
            const line_start = start;
            const line_end = std.mem.indexOf(u8, config[line_start..], "\n") orelse config.len;
            const line = config[line_start..line_start + line_end];
            
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const value_start = colon_pos + 2;
                if (value_start < line.len) {
                    const value = std.mem.trim(u8, line[value_start..], " \t\"'");
                    network_mode = try alloc.dupe(u8, value);
                }
            }
        }
    }
    
    // Check if Docker is available
    if (docker_enabled) {
        if (try checkDockerAvailable()) {
            std.debug.print("🐳 Docker runner plugin initialized\n", .{});
            if (default_image) |image| {
                std.debug.print("  📦 Default image: {s}\n", .{image});
            }
            if (auto_pull) {
                std.debug.print("  🔄 Auto-pull enabled\n", .{});
            }
        } else {
            std.debug.print("⚠️ Docker not available, plugin disabled\n", .{});
            docker_enabled = false;
        }
    } else {
        std.debug.print("🐳 Docker runner plugin initialized (disabled)\n", .{});
    }
}

fn deinit() void {
    if (default_image) |image| {
        if (allocator) |alloc| {
            alloc.free(image);
        }
    }
    if (network_mode) |network| {
        if (allocator) |alloc| {
            alloc.free(network);
        }
    }
    std.debug.print("🐳 Docker runner plugin deinitialized\n", .{});
}

fn beforeTask(repo: []const u8, task: []const u8) PluginError!void {
    if (!docker_enabled) return;
    
    // Check if task should run in Docker
    const should_dockerize = try shouldRunInDocker(repo, task);
    if (!should_dockerize) return;
    
    const image = try getImageForTask(repo, task);
    defer if (allocator) |alloc| alloc.free(image);
    
    std.debug.print("  🐳 Preparing Docker container for {s}:{s}\n", .{ repo, task });
    std.debug.print("  📦 Using image: {s}\n", .{image});
    
    // Pull image if auto_pull is enabled
    if (auto_pull) {
        pullDockerImage(image) catch |err| {
            std.debug.print("  ⚠️ Failed to pull Docker image: {}\n", .{err});
        };
    }
    
    // Validate image exists
    if (!(try imageExists(image))) {
        std.debug.print("  ❌ Docker image {s} not found\n", .{image});
        return PluginError.PluginConfigInvalid;
    }
}

fn afterTask(repo: []const u8, task: []const u8, success: bool) PluginError!void {
    if (!docker_enabled) return;
    
    const should_dockerize = try shouldRunInDocker(repo, task);
    if (!should_dockerize) return;
    
    const status = if (success) "✅ completed" else "❌ failed";
    std.debug.print("  🐳 Docker task {s}:{s} {s}\n", .{ repo, task, status });
    
    // Cleanup containers if needed
    try cleanupContainers(repo, task);
}

fn validateConfig(config: []const u8) PluginError!bool {
    // Validate docker-runner plugin configuration
    _ = config;
    // In real implementation, would validate YAML structure and Docker settings
    return true;
}

fn checkDockerAvailable() !bool {
    const alloc = allocator orelse return false;
    
    var child = std.process.Child.init(&[_][]const u8{ "docker", "version" }, alloc);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    
    const result = child.spawnAndWait() catch return false;
    return switch (result) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn shouldRunInDocker(repo: []const u8, task: []const u8) !bool {
    // Check if this specific task should run in Docker
    // In real implementation, would check task configuration
    _ = repo;
    _ = task;
    
    // For now, return true if Docker is enabled and we have a default image
    return docker_enabled and default_image != null;
}

fn getImageForTask(repo: []const u8, task: []const u8) ![]u8 {
    const alloc = allocator orelse return PluginError.PluginInitFailed;
    
    // In real implementation, would check task-specific image configuration
    _ = repo;
    _ = task;
    
    // Return default image or a task-specific one
    if (default_image) |image| {
        return try alloc.dupe(u8, image);
    }
    
    // Fallback to a reasonable default
    return try alloc.dupe(u8, "node:18-alpine");
}

fn pullDockerImage(image: []const u8) !void {
    const alloc = allocator orelse return;
    
    std.debug.print("  🔄 Pulling Docker image: {s}\n", .{image});
    
    var child = std.process.Child.init(&[_][]const u8{ "docker", "pull", image }, alloc);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    const stderr = try child.stderr.?.readToEndAlloc(alloc, 1024 * 1024);
    defer alloc.free(stderr);
    
    const result = try child.wait();
    switch (result) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("  ⚠️ Failed to pull image {s}: {s}\n", .{ image, stderr });
            } else {
                std.debug.print("  ✅ Successfully pulled image: {s}\n", .{image});
            }
        },
        else => {
            std.debug.print("  ⚠️ Docker pull terminated unexpectedly\n", .{});
        },
    }
}

fn imageExists(image: []const u8) !bool {
    const alloc = allocator orelse return false;
    
    var child = std.process.Child.init(&[_][]const u8{ "docker", "image", "inspect", image }, alloc);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    
    const result = child.spawnAndWait() catch return false;
    return switch (result) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn cleanupContainers(repo: []const u8, task: []const u8) !void {
    // Clean up any leftover containers for this task
    const alloc = allocator orelse return;
    
    // Remove stopped containers with our naming pattern
    const container_name_pattern = try std.fmt.allocPrint(alloc, "zr-{s}-{s}-*", .{ repo, task });
    defer alloc.free(container_name_pattern);
    
    // In real implementation, would use docker API or commands to cleanup
    std.debug.print("  🧹 Cleaning up Docker containers for {s}:{s}\n", .{ repo, task });
}

fn buildDockerCommand(repo: []const u8, task: []const u8, command: []const u8, image: []const u8) ![][]const u8 {
    const alloc = allocator orelse return PluginError.PluginInitFailed;
    
    var docker_args = std.ArrayList([]const u8).init(alloc);
    
    try docker_args.append("docker");
    try docker_args.append("run");
    try docker_args.append("--rm"); // Remove container after execution
    
    // Add container name
    const container_name = try std.fmt.allocPrint(alloc, "zr-{s}-{s}-{d}", .{ repo, task, std.time.timestamp() });
    try docker_args.append("--name");
    try docker_args.append(container_name);
    
    // Mount workspace if enabled
    if (mount_workspace) {
        try docker_args.append("-v");
        const mount = try std.fmt.allocPrint(alloc, "{s}:/workspace", .{std.fs.cwd()});
        try docker_args.append(mount);
        try docker_args.append("-w");
        try docker_args.append("/workspace");
    }
    
    // Add network mode if specified
    if (network_mode) |network| {
        try docker_args.append("--network");
        try docker_args.append(network);
    }
    
    // Add image
    try docker_args.append(image);
    
    // Add command to execute
    try docker_args.append("sh");
    try docker_args.append("-c");
    try docker_args.append(command);
    
    return docker_args.toOwnedSlice();
}

test "Docker runner plugin initialization" {
    const testing = std.testing;
    const test_allocator = testing.allocator;
    
    try init(test_allocator, "");
    defer deinit();
    
    // Test basic initialization (Docker disabled by default)
    try testing.expect(docker_enabled == false);
    try testing.expect(auto_pull == true);
    try testing.expect(mount_workspace == true);
}

test "Docker runner plugin with config" {
    const testing = std.testing;
    const test_allocator = testing.allocator;
    
    const config = "enabled: true\ndefault_image: node:18\nauto_pull: false";
    try init(test_allocator, config);
    defer deinit();
    
    // Test configuration parsing (will be disabled if Docker not available)
    try testing.expect(auto_pull == false);
    if (default_image) |image| {
        try testing.expect(std.mem.eql(u8, image, "node:18"));
    }
}

test "Docker runner plugin task hooks" {
    const testing = std.testing;
    const test_allocator = testing.allocator;
    
    try init(test_allocator, "enabled: true\ndefault_image: alpine:latest");
    defer deinit();
    
    // Test task lifecycle hooks (will only run if Docker is available)
    if (docker_enabled) {
        try beforeTask("frontend", "build");
        try afterTask("frontend", "build", true);
    }
}