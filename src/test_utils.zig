const std = @import("std");
const config = @import("config/parser.zig");

pub const TestUtils = struct {
    pub fn createTestConfig(allocator: std.mem.Allocator) !config.Config {
        const test_yaml =
            \\# Test configuration
            \\global:
            \\  resources:
            \\    max_cpu_percent: 80
            \\    max_memory_mb: 4096
            \\    max_concurrent_tasks: 10
            \\  pipeline:
            \\    default_timeout: 300
            \\    retry_attempts: 3
            \\    log_level: "info"
            \\  interface:
            \\    interactive_mode: true
            \\    show_progress: true
            \\    color_output: true
            \\
            \\repositories:
            \\  - name: "test-npm"
            \\    path: "./test/npm-project"
            \\    tasks:
            \\      - name: "dev"
            \\        command: "npm run dev"
            \\      - name: "build"
            \\        command: "npm run build"
            \\      - name: "test"
            \\        command: "npm test"
            \\  - name: "test-pnpm"
            \\    path: "./test/pnpm-project"
            \\    tasks:
            \\      - name: "dev"
            \\        command: "pnpm dev"
            \\      - name: "build"
            \\        command: "pnpm build"
            \\
            \\pipelines: []
            \\
            \\monitoring:
            \\  enabled: true
            \\  resources:
            \\    check_interval: 5
            \\    alert_threshold:
            \\      cpu_percent: 95
            \\      memory_percent: 90
        ;
        
        return config.Config.parse(allocator, test_yaml);
    }

    pub fn createMinimalConfig(allocator: std.mem.Allocator) !config.Config {
        const minimal_yaml =
            \\repositories:
            \\  - name: "simple"
            \\    path: "./simple"
            \\    tasks:
            \\      - name: "echo"
            \\        command: "echo 'test'"
            \\
            \\pipelines: []
        ;
        
        return config.Config.parse(allocator, minimal_yaml);
    }

    pub fn createComplexConfig(allocator: std.mem.Allocator) !config.Config {
        const complex_yaml =
            \\repositories:
            \\  - name: "frontend"
            \\    path: "./frontend"
            \\    tasks:
            \\      - name: "dev"
            \\        command: "npm run dev"
            \\      - name: "build"
            \\        command: "npm run build"
            \\      - name: "lint"
            \\        command: "npm run lint"
            \\  - name: "backend"
            \\    path: "./backend"
            \\    tasks:
            \\      - name: "dev"
            \\        command: "cargo run"
            \\      - name: "build"
            \\        command: "cargo build --release"
            \\      - name: "test"
            \\        command: "cargo test"
            \\  - name: "mobile"
            \\    path: "./mobile"
            \\    tasks:
            \\      - name: "ios"
            \\        command: "react-native run-ios"
            \\      - name: "android"
            \\        command: "react-native run-android"
            \\
            \\pipelines: []
        ;
        
        return config.Config.parse(allocator, complex_yaml);
    }

    pub fn createTestDir(allocator: std.mem.Allocator, path: []const u8) !void {
        std.fs.cwd().makeDir(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        
        // Create a package.json for npm projects
        if (std.mem.indexOf(u8, path, "npm") != null or std.mem.indexOf(u8, path, "frontend") != null) {
            const package_json =
                \\{
                \\  "name": "test-project",
                \\  "version": "1.0.0",
                \\  "scripts": {
                \\    "dev": "echo 'npm dev running'",
                \\    "build": "echo 'npm build complete'",
                \\    "test": "echo 'npm tests passed'"
                \\  }
                \\}
            ;
            
            const package_path = try std.fmt.allocPrint(allocator, "{s}/package.json", .{path});
            defer allocator.free(package_path);
            
            const file = try std.fs.cwd().createFile(package_path, .{});
            defer file.close();
            try file.writeAll(package_json);
        }
    }

    pub fn cleanupTestDir(path: []const u8) void {
        std.fs.cwd().deleteTree(path) catch {};
    }

    pub fn expectTaskCount(repos: []config.Repository, repo_name: []const u8, expected_count: usize) !void {
        for (repos) |repo| {
            if (std.mem.eql(u8, repo.name, repo_name)) {
                try std.testing.expect(repo.tasks.len == expected_count);
                return;
            }
        }
        return error.RepositoryNotFound;
    }

    pub fn expectTaskExists(repos: []config.Repository, repo_name: []const u8, task_name: []const u8) !void {
        for (repos) |repo| {
            if (std.mem.eql(u8, repo.name, repo_name)) {
                for (repo.tasks) |task| {
                    if (std.mem.eql(u8, task.name, task_name)) {
                        return;
                    }
                }
                return error.TaskNotFound;
            }
        }
        return error.RepositoryNotFound;
    }
};

test "TestUtils functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test minimal config creation
    var minimal_config = try TestUtils.createMinimalConfig(allocator);
    defer minimal_config.deinit();
    
    try testing.expect(minimal_config.repositories.len == 1);
    try testing.expect(std.mem.eql(u8, minimal_config.repositories[0].name, "simple"));
    
    // Test complex config creation
    var complex_config = try TestUtils.createComplexConfig(allocator);
    defer complex_config.deinit();
    
    try testing.expect(complex_config.repositories.len == 3);
    try TestUtils.expectTaskCount(complex_config.repositories, "frontend", 3);
    try TestUtils.expectTaskExists(complex_config.repositories, "backend", "test");
}