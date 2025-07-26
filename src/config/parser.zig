const std = @import("std");

pub const Config = struct {
    allocator: std.mem.Allocator,
    global: GlobalConfig,
    repositories: []Repository,
    pipelines: []Pipeline,
    monitoring: MonitoringConfig,
    plugins: ?PluginConfig = null,

    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !Config {
        // Simple YAML-like parser for repositories section
        var repos_list = std.ArrayList(Repository).init(allocator);
        defer repos_list.deinit();
        
        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_repositories = false;
        var current_repo: ?Repository = null;
        var current_tasks = std.ArrayList(Task).init(allocator);
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            
            if (std.mem.startsWith(u8, trimmed, "repositories:")) {
                in_repositories = true;
                continue;
            }
            
            if (in_repositories) {
                if (std.mem.startsWith(u8, trimmed, "pipelines:") or 
                    std.mem.startsWith(u8, trimmed, "monitoring:")) {
                    // Save current repo if exists
                    if (current_repo) |*repo| {
                        repo.tasks = try current_tasks.toOwnedSlice();
                        try repos_list.append(repo.*);
                        current_repo = null;
                        current_tasks = std.ArrayList(Task).init(allocator);
                    }
                    in_repositories = false;
                    continue;
                }
                
                // Check indentation to distinguish between repo and task entries
                const line_indent = line.len - trimmed.len;
                
                if (std.mem.startsWith(u8, trimmed, "- name:") and line_indent <= 2) {
                    // This is a repository entry (top level, 0-2 spaces indent)
                    // Save previous repo if exists
                    if (current_repo) |*repo| {
                        repo.tasks = try current_tasks.toOwnedSlice();
                        try repos_list.append(repo.*);
                        current_tasks = std.ArrayList(Task).init(allocator);
                    }
                    
                    // Parse name
                    const name_start = std.mem.indexOf(u8, trimmed, "\"") orelse continue;
                    const name_end = std.mem.indexOfPos(u8, trimmed, name_start + 1, "\"") orelse continue;
                    const name = trimmed[name_start + 1..name_end];
                    
                    current_repo = Repository{
                        .name = try allocator.dupe(u8, name),
                        .path = "",
                        .resources = null,
                        .environment = std.StringHashMap([]const u8).init(allocator),
                        .tasks = &[_]Task{},
                    };
                } else if (std.mem.startsWith(u8, trimmed, "path:") and current_repo != null) {
                    // Parse path
                    const path_start = std.mem.indexOf(u8, trimmed, "\"") orelse continue;
                    const path_end = std.mem.indexOfPos(u8, trimmed, path_start + 1, "\"") orelse continue;
                    const path = trimmed[path_start + 1..path_end];
                    current_repo.?.path = try allocator.dupe(u8, path);
                } else if (std.mem.startsWith(u8, trimmed, "- name:") and line_indent > 4) {
                    // This is a task entry (nested under tasks:, more than 4 spaces indent)
                    const name_start = std.mem.indexOf(u8, trimmed, "\"") orelse continue;
                    const name_end = std.mem.indexOfPos(u8, trimmed, name_start + 1, "\"") orelse continue;
                    const task_name = trimmed[name_start + 1..name_end];
                    
                    const task = Task{
                        .name = try allocator.dupe(u8, task_name),
                        .command = null,
                        .pipeline = null,
                        .dependencies = &[_][]const u8{},
                        .groups = &[_]TaskGroup{},
                    };
                    
                    try current_tasks.append(task);
                } else if (std.mem.startsWith(u8, trimmed, "command:") and current_tasks.items.len > 0) {
                    // Parse command for last task
                    const cmd_start = std.mem.indexOf(u8, trimmed, "\"") orelse continue;
                    const cmd_end = std.mem.indexOfPos(u8, trimmed, cmd_start + 1, "\"") orelse continue;
                    const command = trimmed[cmd_start + 1..cmd_end];
                    
                    const last_idx = current_tasks.items.len - 1;
                    current_tasks.items[last_idx].command = try allocator.dupe(u8, command);
                }
            }
        }
        
        // Save final repo if exists
        if (current_repo) |*repo| {
            repo.tasks = try current_tasks.toOwnedSlice();
            try repos_list.append(repo.*);
        } else {
            current_tasks.deinit();
        }
        
        const repos = try repos_list.toOwnedSlice();
        const pipelines = try allocator.alloc(Pipeline, 0);
        
        const config = Config{
            .allocator = allocator,
            .global = GlobalConfig.default(),
            .repositories = repos,
            .pipelines = pipelines,
            .monitoring = MonitoringConfig.default(),
        };

        return config;
    }

    pub fn deinit(self: *Config) void {
        // Free all allocated memory
        for (self.repositories) |*repo| {
            repo.deinit(self.allocator);
        }
        self.allocator.free(self.repositories);

        for (self.pipelines) |*pipeline| {
            pipeline.deinit(self.allocator);
        }
        self.allocator.free(self.pipelines);
    }

    pub fn findRepository(self: *const Config, name: []const u8) ?*const Repository {
        for (self.repositories) |*repo| {
            if (std.mem.eql(u8, repo.name, name)) {
                return repo;
            }
        }
        return null;
    }

    pub fn findPipeline(self: *const Config, name: []const u8) ?*const Pipeline {
        for (self.pipelines) |*pipeline| {
            if (std.mem.eql(u8, pipeline.name, name)) {
                return pipeline;
            }
        }
        return null;
    }
};

pub const GlobalConfig = struct {
    resources: ResourceConfig,
    pipeline: PipelineConfig,
    interface: InterfaceConfig,

    pub fn default() GlobalConfig {
        return GlobalConfig{
            .resources = ResourceConfig.default(),
            .pipeline = PipelineConfig.default(),
            .interface = InterfaceConfig.default(),
        };
    }
};

pub const ResourceConfig = struct {
    max_cpu_percent: f32,
    max_memory_mb: u32,
    max_concurrent_tasks: u32,

    pub fn default() ResourceConfig {
        return ResourceConfig{
            .max_cpu_percent = 80.0,
            .max_memory_mb = 4096,
            .max_concurrent_tasks = 10,
        };
    }
};

pub const PipelineConfig = struct {
    default_timeout: u32,
    retry_attempts: u32,
    log_level: LogLevel,

    pub fn default() PipelineConfig {
        return PipelineConfig{
            .default_timeout = 300,
            .retry_attempts = 3,
            .log_level = .info,
        };
    }
};

pub const InterfaceConfig = struct {
    interactive_mode: bool,
    show_progress: bool,
    color_output: bool,

    pub fn default() InterfaceConfig {
        return InterfaceConfig{
            .interactive_mode = true,
            .show_progress = true,
            .color_output = true,
        };
    }
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    @"error",
};

pub const Repository = struct {
    name: []const u8,
    path: []const u8,
    resources: ?ResourceConfig,
    environment: std.StringHashMap([]const u8),
    tasks: []Task,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8) Repository {
        return Repository{
            .name = name,
            .path = path,
            .resources = null,
            .environment = std.StringHashMap([]const u8).init(allocator),
            .tasks = &[_]Task{},
        };
    }

    pub fn deinit(self: *Repository, allocator: std.mem.Allocator) void {
        self.environment.deinit();
        for (self.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(self.tasks);
    }

    pub fn findTask(self: *const Repository, name: []const u8) ?*const Task {
        for (self.tasks) |*task| {
            if (std.mem.eql(u8, task.name, name)) {
                return task;
            }
        }
        return null;
    }
};

pub const Task = struct {
    name: []const u8,
    command: ?[]const u8, // For simple tasks
    pipeline: ?TaskPipeline, // For complex tasks
    dependencies: [][]const u8,
    groups: []TaskGroup,

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.dependencies);
        for (self.groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(self.groups);
    }

    pub fn isSimple(self: *const Task) bool {
        return self.command != null;
    }
};

pub const TaskPipeline = struct {
    timeout: ?u32,
    retry_attempts: ?u32,
    parallel: bool,
};

pub const TaskGroup = struct {
    name: []const u8,
    parallel: bool,
    commands: [][]const u8,

    pub fn deinit(self: *TaskGroup, allocator: std.mem.Allocator) void {
        for (self.commands) |cmd| {
            allocator.free(cmd);
        }
        allocator.free(self.commands);
    }
};

pub const Pipeline = struct {
    name: []const u8,
    description: ?[]const u8,
    resources: ?ResourceConfig,
    stages: []PipelineStage,

    pub fn deinit(self: *Pipeline, allocator: std.mem.Allocator) void {
        for (self.stages) |*stage| {
            stage.deinit(allocator);
        }
        allocator.free(self.stages);
    }
};

pub const PipelineStage = struct {
    name: []const u8,
    parallel: bool,
    repositories: []RepositoryTask,

    pub fn deinit(self: *PipelineStage, allocator: std.mem.Allocator) void {
        allocator.free(self.repositories);
    }
};

pub const RepositoryTask = struct {
    repository: []const u8,
    task: []const u8,
};

pub const MonitoringConfig = struct {
    enabled: bool,
    resources: ResourceMonitoringConfig,
    logging: LoggingConfig,

    pub fn default() MonitoringConfig {
        return MonitoringConfig{
            .enabled = true,
            .resources = ResourceMonitoringConfig.default(),
            .logging = LoggingConfig.default(),
        };
    }
};

pub const ResourceMonitoringConfig = struct {
    check_interval: u32,
    alert_threshold: AlertThreshold,

    pub fn default() ResourceMonitoringConfig {
        return ResourceMonitoringConfig{
            .check_interval = 5,
            .alert_threshold = AlertThreshold.default(),
        };
    }
};

pub const AlertThreshold = struct {
    cpu_percent: f32,
    memory_percent: f32,

    pub fn default() AlertThreshold {
        return AlertThreshold{
            .cpu_percent = 95.0,
            .memory_percent = 90.0,
        };
    }
};

pub const LoggingConfig = struct {
    file_path: []const u8,
    max_file_size_mb: u32,
    max_files: u32,
    format: LogFormat,

    pub fn default() LoggingConfig {
        return LoggingConfig{
            .file_path = "./zr.log",
            .max_file_size_mb = 100,
            .max_files = 5,
            .format = .json,
        };
    }
};

pub const LogFormat = enum {
    json,
    text,
};

// Import test utilities
const test_utils = @import("../test_utils.zig");

test "Config parsing - minimal configuration" {
    const testing = std.testing;
    const allocator = testing.allocator;

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

    var config = try Config.parse(allocator, minimal_yaml);
    defer config.deinit();

    try testing.expect(config.repositories.len == 1);
    try testing.expect(std.mem.eql(u8, config.repositories[0].name, "simple"));
    try testing.expect(std.mem.eql(u8, config.repositories[0].path, "./simple"));
    try testing.expect(config.repositories[0].tasks.len == 1);
    try testing.expect(std.mem.eql(u8, config.repositories[0].tasks[0].name, "echo"));
    try testing.expect(std.mem.eql(u8, config.repositories[0].tasks[0].command.?, "echo 'test'"));
}

test "Config parsing - multiple repositories with multiple tasks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const multi_repo_yaml =
        \\repositories:
        \\  - name: "frontend"
        \\    path: "./frontend"
        \\    tasks:
        \\      - name: "dev"
        \\        command: "npm run dev"
        \\      - name: "build"
        \\        command: "npm run build"
        \\      - name: "test"
        \\        command: "npm test"
        \\  - name: "backend"
        \\    path: "./backend"
        \\    tasks:
        \\      - name: "dev"
        \\        command: "cargo run"
        \\      - name: "build"
        \\        command: "cargo build --release"
        \\
        \\pipelines: []
    ;

    var config = try Config.parse(allocator, multi_repo_yaml);
    defer config.deinit();

    try testing.expect(config.repositories.len == 2);
    
    // Test frontend repository
    const frontend = &config.repositories[0];
    try testing.expect(std.mem.eql(u8, frontend.name, "frontend"));
    try testing.expect(std.mem.eql(u8, frontend.path, "./frontend"));
    try testing.expect(frontend.tasks.len == 3);
    try testing.expect(std.mem.eql(u8, frontend.tasks[0].name, "dev"));
    try testing.expect(std.mem.eql(u8, frontend.tasks[0].command.?, "npm run dev"));
    
    // Test backend repository
    const backend = &config.repositories[1];
    try testing.expect(std.mem.eql(u8, backend.name, "backend"));
    try testing.expect(std.mem.eql(u8, backend.path, "./backend"));
    try testing.expect(backend.tasks.len == 2);
    try testing.expect(std.mem.eql(u8, backend.tasks[1].name, "build"));
    try testing.expect(std.mem.eql(u8, backend.tasks[1].command.?, "cargo build --release"));
}

test "Config parsing - real-world monorepo scenario" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const monorepo_yaml =
        \\repositories:
        \\  - name: "npm-monorepo"
        \\    path: "./packages/npm-turbo"
        \\    tasks:
        \\      - name: "dev"
        \\        command: "npm run dev"
        \\      - name: "build"
        \\        command: "npm run build"
        \\      - name: "lint"
        \\        command: "npm run lint"
        \\      - name: "test"
        \\        command: "npm test"
        \\  - name: "pnpm-monorepo"
        \\    path: "./packages/pnpm-turbo"
        \\    tasks:
        \\      - name: "dev"
        \\        command: "pnpm dev"
        \\      - name: "build"
        \\        command: "pnpm build"
        \\      - name: "web-dev"
        \\        command: "cd apps/web && pnpm dev"
        \\
        \\pipelines: []
    ;

    var config = try Config.parse(allocator, monorepo_yaml);
    defer config.deinit();

    try testing.expect(config.repositories.len == 2);
    
    // Verify npm monorepo
    try test_utils.TestUtils.expectTaskCount(config.repositories, "npm-monorepo", 4);
    try test_utils.TestUtils.expectTaskExists(config.repositories, "npm-monorepo", "lint");
    
    // Verify pnpm monorepo
    try test_utils.TestUtils.expectTaskCount(config.repositories, "pnpm-monorepo", 3);
    try test_utils.TestUtils.expectTaskExists(config.repositories, "pnpm-monorepo", "web-dev");
    
    // Test complex command parsing
    const pnpm_repo = &config.repositories[1];
    try testing.expect(std.mem.eql(u8, pnpm_repo.tasks[2].command.?, "cd apps/web && pnpm dev"));
}

test "Config parsing - empty repositories" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const empty_yaml =
        \\repositories: []
        \\pipelines: []
    ;

    var config = try Config.parse(allocator, empty_yaml);
    defer config.deinit();

    try testing.expect(config.repositories.len == 0);
    try testing.expect(config.pipelines.len == 0);
}

test "Config parsing - indentation handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const indented_yaml =
        \\repositories:
        \\  - name: "test-repo"
        \\    path: "./test"
        \\    tasks:
        \\      - name: "task1"
        \\        command: "echo 'first'"
        \\      - name: "task2"
        \\        command: "echo 'second'"
        \\
        \\pipelines: []
    ;

    var config = try Config.parse(allocator, indented_yaml);
    defer config.deinit();

    try testing.expect(config.repositories.len == 1);
    try testing.expect(config.repositories[0].tasks.len == 2);
    try testing.expect(std.mem.eql(u8, config.repositories[0].tasks[0].name, "task1"));
    try testing.expect(std.mem.eql(u8, config.repositories[0].tasks[1].name, "task2"));
    try testing.expect(std.mem.eql(u8, config.repositories[0].tasks[0].command.?, "echo 'first'"));
    try testing.expect(std.mem.eql(u8, config.repositories[0].tasks[1].command.?, "echo 'second'"));
}

// Plugin configuration structures
pub const PluginConfig = struct {
    enabled: bool,
    directory: []const u8,
    builtin: []const BuiltinPluginConfig,
};

pub const BuiltinPluginConfig = struct {
    name: []const u8,
    enabled: bool,
    config: ?[]const u8 = null,
};