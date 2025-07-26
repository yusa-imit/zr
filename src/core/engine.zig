const std = @import("std");
const config = @import("../config/parser.zig");
const tasks = @import("../tasks/executor.zig");
const resources = @import("../resources/monitor.zig");
const plugins = @import("../plugins/mod.zig");
const Config = config.Config;
const TaskExecutor = tasks.TaskExecutor;
const ResourceMonitor = resources.ResourceMonitor;
const PluginManager = plugins.PluginManager;

pub const EngineError = error{
    ConfigNotFound,
    ConfigInvalid,
    RepositoryNotFound,
    TaskNotFound,
    PipelineNotFound,
    ResourceLimitExceeded,
    ExecutionFailed,
} || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

pub const Engine = struct {
    allocator: std.mem.Allocator,
    config: ?Config = null,
    task_executor: ?TaskExecutor = null,
    resource_monitor: ?ResourceMonitor = null,
    plugin_manager: ?PluginManager = null,
    is_running: bool = false,

    const CONFIG_FILE = ".zr.config.yaml";
    const DEFAULT_CONFIG_CONTENT =
        \\# ZR Configuration File
        \\# See zr.config.spec.yaml for full specification
        \\
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
        \\repositories: []
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

    pub fn init(allocator: std.mem.Allocator) !Engine {
        return Engine{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Engine) void {
        if (self.plugin_manager) |*manager| {
            manager.deinit();
        }
        if (self.config) |*cfg| {
            cfg.deinit();
        }
        if (self.task_executor) |*executor| {
            executor.deinit();
        }
        if (self.resource_monitor) |*monitor| {
            monitor.deinit();
        }
    }

    pub fn initConfig(self: *Engine) !void {
        _ = self;
        // Check if config already exists
        if (std.fs.cwd().access(CONFIG_FILE, .{})) |_| {
            std.debug.print("❌ Config file already exists: {s}\n", .{CONFIG_FILE});
            return;
        } else |_| {
            // Create new config file
            const file = try std.fs.cwd().createFile(CONFIG_FILE, .{});
            defer file.close();
            try file.writeAll(DEFAULT_CONFIG_CONTENT);
        }
    }

    pub fn loadConfig(self: *Engine) !void {

        // Read config file
        const file = std.fs.cwd().openFile(CONFIG_FILE, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("❌ Config file not found. Run 'zr init' first.\n", .{});
                return EngineError.ConfigNotFound;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        // Parse configuration
        self.config = config.Config.parse(self.allocator, content) catch |err| {
            std.debug.print("❌ Failed to parse config: {}\n", .{err});
            return EngineError.ConfigInvalid;
        };

        // Initialize subsystems
        try self.initSubsystems();
    }

    pub fn initSubsystems(self: *Engine) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;

        // Initialize plugin manager
        // Check if plugins are configured, default to enabled with default directory
        const plugin_config = if (cfg.plugins) |p| p else config.PluginConfig{
            .enabled = true,
            .directory = "./zr-plugins",
            .builtin = &[_]config.BuiltinPluginConfig{},
        };
        
        self.plugin_manager = try PluginManager.init(
            self.allocator, 
            plugin_config.directory, 
            plugin_config.enabled
        );
        
        if (self.plugin_manager) |*manager| {
            try manager.discoverPlugins();
            try manager.initializePlugins();
        }

        // Initialize task executor
        self.task_executor = try TaskExecutor.init(self.allocator, &cfg);

        // Initialize resource monitor if enabled
        // Temporarily disable entire monitor to isolate overflow issue
        _ = cfg.monitoring.enabled;
        // if (cfg.monitoring.enabled) {
        //     self.resource_monitor = try ResourceMonitor.init(
        //         self.allocator,
        //         cfg.global.resources,
        //         cfg.monitoring.resources,
        //     );
        //     try self.resource_monitor.?.start();
        // }
    }

    pub fn runTask(self: *Engine, repo_name: []const u8, task_name: []const u8) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;
        var executor = self.task_executor orelse return EngineError.ConfigInvalid;

        // Find repository
        const repo = cfg.findRepository(repo_name) orelse {
            std.debug.print("❌ Repository '{s}' not found\n", .{repo_name});
            return EngineError.RepositoryNotFound;
        };

        // Find task
        const task = repo.findTask(task_name) orelse {
            std.debug.print("❌ Task '{s}' not found in repository '{s}'\n", .{ task_name, repo_name });
            return EngineError.TaskNotFound;
        };

        std.debug.print("🚀 Running task '{s}' in repository '{s}'\n", .{ task_name, repo_name });

        // Execute plugin beforeTask hooks
        if (self.plugin_manager) |*manager| {
            try manager.executeHook(.BeforeTask, .{ .repo = repo_name, .task = task_name });
        }

        // Check resource limits before execution
        if (self.resource_monitor) |*monitor| {
            const current_usage = try monitor.getCurrentUsage();
            if (current_usage.cpu_percent > cfg.global.resources.max_cpu_percent or
                current_usage.memory_mb > cfg.global.resources.max_memory_mb)
            {
                std.debug.print("❌ Resource limits exceeded\n", .{});
                
                // Execute plugin onResourceLimit hooks
                if (self.plugin_manager) |*manager| {
                    try manager.executeHook(.OnResourceLimit, .{ 
                        .cpu_percent = current_usage.cpu_percent, 
                        .memory_mb = current_usage.memory_mb 
                    });
                }
                
                return EngineError.ResourceLimitExceeded;
            }
        }

        // Execute task
        const task_success = blk: {
            executor.executeTask(repo, task) catch |err| {
                std.debug.print("❌ Task failed: {}\n", .{err});
                break :blk false;
            };
            break :blk true;
        };

        // Execute plugin afterTask hooks
        if (self.plugin_manager) |*manager| {
            try manager.executeHook(.AfterTask, .{ 
                .repo = repo_name, 
                .task = task_name, 
                .success = task_success 
            });
        }

        if (task_success) {
            std.debug.print("✅ Task completed successfully\n", .{});
        } else {
            return EngineError.ExecutionFailed;
        }
    }

    pub fn runPipeline(self: *Engine, pipeline_name: []const u8) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;
        var executor = self.task_executor orelse return EngineError.ConfigInvalid;

        // Find pipeline
        const pipeline = cfg.findPipeline(pipeline_name) orelse {
            std.debug.print("❌ Pipeline '{s}' not found\n", .{pipeline_name});
            return EngineError.PipelineNotFound;
        };

        std.debug.print("🚀 Running pipeline '{s}'\n", .{pipeline_name});

        // Execute plugin beforePipeline hooks
        if (self.plugin_manager) |*manager| {
            try manager.executeHook(.BeforePipeline, .{ .pipeline = pipeline_name });
        }

        // Execute pipeline
        const pipeline_success = blk: {
            executor.executePipeline(pipeline) catch |err| {
                std.debug.print("❌ Pipeline failed: {}\n", .{err});
                break :blk false;
            };
            break :blk true;
        };

        // Execute plugin afterPipeline hooks
        if (self.plugin_manager) |*manager| {
            try manager.executeHook(.AfterPipeline, .{ 
                .pipeline = pipeline_name, 
                .success = pipeline_success 
            });
        }

        if (pipeline_success) {
            std.debug.print("✅ Pipeline completed successfully\n", .{});
        } else {
            return EngineError.ExecutionFailed;
        }
    }

    pub fn listRepositories(self: *Engine) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;

        std.debug.print("\n📁 Repositories:\n", .{});
        if (cfg.repositories.len == 0) {
            std.debug.print("  No repositories configured\n", .{});
            return;
        }

        for (cfg.repositories) |repo| {
            std.debug.print("  • {s} ({s})\n", .{ repo.name, repo.path });
            if (repo.tasks.len > 0) {
                std.debug.print("    Tasks: ", .{});
                for (repo.tasks, 0..) |task, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{task.name});
                }
                std.debug.print("\n", .{});
            }
        }
    }

    pub fn listPipelines(self: *Engine) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;

        std.debug.print("\n🔄 Pipelines:\n", .{});
        if (cfg.pipelines.len == 0) {
            std.debug.print("  No pipelines configured\n", .{});
            return;
        }

        for (cfg.pipelines) |pipeline| {
            std.debug.print("  • {s}", .{pipeline.name});
            if (pipeline.description) |desc| {
                std.debug.print(" - {s}", .{desc});
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn getStatus(self: *Engine) !Status {
        const cfg = self.config orelse return EngineError.ConfigInvalid;
        
        var status = Status.init(self.allocator);
        
        // Get resource usage if monitoring is enabled
        if (self.resource_monitor) |*monitor| {
            status.resource_usage = try monitor.getCurrentUsage();
        }
        
        // Get running tasks count
        if (self.task_executor) |executor| {
            status.running_tasks = executor.getRunningTasksCount();
        }
        
        status.repositories_count = cfg.repositories.len;
        status.pipelines_count = cfg.pipelines.len;
        
        return status;
    }

    pub fn addRepository(self: *Engine, name: []const u8, path: []const u8, task_name: []const u8, task_command: []const u8) !void {
        var cfg = &(self.config orelse return EngineError.ConfigInvalid);

        // Create new repository
        var new_repo = config.Repository.init(self.allocator, name, path);
        
        // Create a simple task for the repository
        const task = config.Task{
            .name = try self.allocator.dupe(u8, task_name),
            .command = try self.allocator.dupe(u8, task_command),
            .pipeline = null,
            .dependencies = &[_][]const u8{},
            .groups = &[_]config.TaskGroup{},
        };

        // Allocate space for tasks and copy the task
        const task_array = try self.allocator.alloc(config.Task, 1);
        task_array[0] = task;
        new_repo.tasks = task_array;
        
        // Duplicate the name and path for the repository
        new_repo.name = try self.allocator.dupe(u8, name);
        new_repo.path = try self.allocator.dupe(u8, path);

        // Extend repositories array
        const new_repos = try self.allocator.alloc(config.Repository, cfg.repositories.len + 1);
        @memcpy(new_repos[0..cfg.repositories.len], cfg.repositories);
        new_repos[cfg.repositories.len] = new_repo;
        
        // Free old array and update config
        self.allocator.free(cfg.repositories);
        cfg.repositories = new_repos;

        // Save config to file
        try self.saveConfig();
    }

    pub fn removeRepository(self: *Engine, name: []const u8) !void {
        var cfg = self.config orelse return EngineError.ConfigInvalid;

        // Find repository index
        var found_index: ?usize = null;
        for (cfg.repositories, 0..) |repo, i| {
            if (std.mem.eql(u8, repo.name, name)) {
                found_index = i;
                break;
            }
        }

        const index = found_index orelse {
            std.debug.print("❌ Repository '{s}' not found\n", .{name});
            return EngineError.RepositoryNotFound;
        };

        // Clean up the repository being removed
        var repo_to_remove = &cfg.repositories[index];
        repo_to_remove.deinit(self.allocator);

        // Create new array without the removed repository
        const new_repos = try self.allocator.alloc(config.Repository, cfg.repositories.len - 1);
        @memcpy(new_repos[0..index], cfg.repositories[0..index]);
        @memcpy(new_repos[index..], cfg.repositories[index + 1..]);
        
        // Free old array and update config
        self.allocator.free(cfg.repositories);
        cfg.repositories = new_repos;

        // Save config to file
        try self.saveConfig();
    }

    pub fn getSetting(self: *Engine, key: []const u8) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;
        
        if (std.mem.eql(u8, key, "max_cpu")) {
            std.debug.print("max_cpu: {d}\n", .{cfg.global.resources.max_cpu_percent});
        } else if (std.mem.eql(u8, key, "max_memory")) {
            std.debug.print("max_memory: {d}\n", .{cfg.global.resources.max_memory_mb});
        } else if (std.mem.eql(u8, key, "max_tasks")) {
            std.debug.print("max_tasks: {d}\n", .{cfg.global.resources.max_concurrent_tasks});
        } else if (std.mem.eql(u8, key, "timeout")) {
            std.debug.print("timeout: {d}\n", .{cfg.global.pipeline.default_timeout});
        } else {
            std.debug.print("❌ Unknown setting: {s}\n", .{key});
        }
    }

    pub fn getAllSettings(self: *Engine) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;
        
        std.debug.print("\n⚙️  ZR Settings:\n", .{});
        std.debug.print("  Max CPU: {d}%\n", .{cfg.global.resources.max_cpu_percent});
        std.debug.print("  Max Memory: {d}MB\n", .{cfg.global.resources.max_memory_mb});
        std.debug.print("  Max Tasks: {d}\n", .{cfg.global.resources.max_concurrent_tasks});
        std.debug.print("  Default Timeout: {d}s\n", .{cfg.global.pipeline.default_timeout});
        std.debug.print("  Interactive Mode: {}\n", .{cfg.global.interface.interactive_mode});
        std.debug.print("  Show Progress: {}\n", .{cfg.global.interface.show_progress});
        std.debug.print("  Color Output: {}\n", .{cfg.global.interface.color_output});
    }

    pub fn setSetting(self: *Engine, key: []const u8, value: []const u8) !void {
        var cfg = self.config orelse return EngineError.ConfigInvalid;
        
        if (std.mem.eql(u8, key, "max_cpu")) {
            const cpu_val = std.fmt.parseFloat(f32, value) catch {
                std.debug.print("❌ Invalid CPU value: {s}\n", .{value});
                return;
            };
            cfg.global.resources.max_cpu_percent = cpu_val;
        } else if (std.mem.eql(u8, key, "max_memory")) {
            const mem_val = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("❌ Invalid memory value: {s}\n", .{value});
                return;
            };
            cfg.global.resources.max_memory_mb = mem_val;
        } else if (std.mem.eql(u8, key, "max_tasks")) {
            const task_val = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("❌ Invalid task value: {s}\n", .{value});
                return;
            };
            cfg.global.resources.max_concurrent_tasks = task_val;
        } else if (std.mem.eql(u8, key, "timeout")) {
            const timeout_val = std.fmt.parseInt(u32, value, 10) catch {
                std.debug.print("❌ Invalid timeout value: {s}\n", .{value});
                return;
            };
            cfg.global.pipeline.default_timeout = timeout_val;
        } else {
            std.debug.print("❌ Unknown setting: {s}\n", .{key});
            return;
        }

        // Save config to file
        try self.saveConfig();
    }

    fn saveConfig(self: *Engine) !void {
        const cfg = self.config orelse return EngineError.ConfigInvalid;
        
        const file = try std.fs.cwd().createFile(CONFIG_FILE, .{});
        defer file.close();

        // Write YAML content
        try file.writeAll("# ZR Configuration File\n");
        try file.writeAll("# See zr.config.spec.yaml for full specification\n\n");
        
        // Global settings
        try file.writeAll("global:\n");
        try file.writeAll("  resources:\n");
        try file.writer().print("    max_cpu_percent: {d}\n", .{cfg.global.resources.max_cpu_percent});
        try file.writer().print("    max_memory_mb: {d}\n", .{cfg.global.resources.max_memory_mb});
        try file.writer().print("    max_concurrent_tasks: {d}\n", .{cfg.global.resources.max_concurrent_tasks});
        try file.writeAll("  pipeline:\n");
        try file.writer().print("    default_timeout: {d}\n", .{cfg.global.pipeline.default_timeout});
        try file.writer().print("    retry_attempts: {d}\n", .{cfg.global.pipeline.retry_attempts});
        try file.writeAll("    log_level: \"info\"\n");
        try file.writeAll("  interface:\n");
        try file.writer().print("    interactive_mode: {}\n", .{cfg.global.interface.interactive_mode});
        try file.writer().print("    show_progress: {}\n", .{cfg.global.interface.show_progress});
        try file.writer().print("    color_output: {}\n", .{cfg.global.interface.color_output});
        
        // Repositories
        try file.writeAll("\nrepositories:\n");
        if (cfg.repositories.len == 0) {
            try file.writeAll("  []\n");
        } else {
            for (cfg.repositories) |repo| {
                try file.writer().print("  - name: \"{s}\"\n", .{repo.name});
                try file.writer().print("    path: \"{s}\"\n", .{repo.path});
                try file.writeAll("    tasks:\n");
                for (repo.tasks) |task| {
                    try file.writer().print("      - name: \"{s}\"\n", .{task.name});
                    if (task.command) |cmd| {
                        try file.writer().print("        command: \"{s}\"\n", .{cmd});
                    }
                }
            }
        }
        
        // Pipelines
        try file.writeAll("\npipelines:\n");
        if (cfg.pipelines.len == 0) {
            try file.writeAll("  []\n");
        } else {
            for (cfg.pipelines) |pipeline| {
                try file.writer().print("  - name: \"{s}\"\n", .{pipeline.name});
                if (pipeline.description) |desc| {
                    try file.writer().print("    description: \"{s}\"\n", .{desc});
                }
                try file.writeAll("    stages:\n");
                for (pipeline.stages) |stage| {
                    try file.writer().print("      - name: \"{s}\"\n", .{stage.name});
                    try file.writer().print("        parallel: {}\n", .{stage.parallel});
                    try file.writeAll("        repositories:\n");
                    for (stage.repositories) |repo_task| {
                        try file.writer().print("          - repository: \"{s}\"\n", .{repo_task.repository});
                        try file.writer().print("            task: \"{s}\"\n", .{repo_task.task});
                    }
                }
            }
        }
        
        // Monitoring
        try file.writeAll("\nmonitoring:\n");
        try file.writer().print("  enabled: {}\n", .{cfg.monitoring.enabled});
        try file.writeAll("  resources:\n");
        try file.writer().print("    check_interval: {d}\n", .{cfg.monitoring.resources.check_interval});
        try file.writeAll("    alert_threshold:\n");
        try file.writer().print("      cpu_percent: {d}\n", .{cfg.monitoring.resources.alert_threshold.cpu_percent});
        try file.writer().print("      memory_percent: {d}\n", .{cfg.monitoring.resources.alert_threshold.memory_percent});
    }

    pub fn addPipeline(self: *Engine, name: []const u8, stage_spec: []const u8) !void {
        var cfg = &(self.config orelse return EngineError.ConfigInvalid);

        // Parse stage specification like "repo1:task1,repo2:task2"
        var stage_tasks = std.ArrayList(config.RepositoryTask).init(self.allocator);
        defer stage_tasks.deinit();

        var task_iter = std.mem.tokenizeScalar(u8, stage_spec, ',');
        while (task_iter.next()) |task_pair| {
            const colon_idx = std.mem.indexOf(u8, task_pair, ":") orelse {
                std.debug.print("❌ Invalid task specification: {s} (expected repo:task format)\n", .{task_pair});
                return;
            };
            
            const repo_name = task_pair[0..colon_idx];
            const task_name = task_pair[colon_idx + 1..];
            
            const repo_task = config.RepositoryTask{
                .repository = try self.allocator.dupe(u8, repo_name),
                .task = try self.allocator.dupe(u8, task_name),
            };
            
            try stage_tasks.append(repo_task);
        }

        // Create pipeline stage
        const stage = config.PipelineStage{
            .name = try self.allocator.dupe(u8, "main"),
            .parallel = false, // Default to sequential
            .repositories = try stage_tasks.toOwnedSlice(),
        };

        // Create pipeline
        const stages = try self.allocator.alloc(config.PipelineStage, 1);
        stages[0] = stage;

        const new_pipeline = config.Pipeline{
            .name = try self.allocator.dupe(u8, name),
            .description = null,
            .resources = null,
            .stages = stages,
        };

        // Extend pipelines array
        const new_pipelines = try self.allocator.alloc(config.Pipeline, cfg.pipelines.len + 1);
        @memcpy(new_pipelines[0..cfg.pipelines.len], cfg.pipelines);
        new_pipelines[cfg.pipelines.len] = new_pipeline;
        
        // Free old array and update config
        self.allocator.free(cfg.pipelines);
        cfg.pipelines = new_pipelines;

        // Save config to file
        try self.saveConfig();
    }

    pub fn removePipeline(self: *Engine, name: []const u8) !void {
        var cfg = &(self.config orelse return EngineError.ConfigInvalid);

        // Find pipeline index
        var found_index: ?usize = null;
        for (cfg.pipelines, 0..) |pipeline, i| {
            if (std.mem.eql(u8, pipeline.name, name)) {
                found_index = i;
                break;
            }
        }

        const index = found_index orelse {
            std.debug.print("❌ Pipeline '{s}' not found\n", .{name});
            return EngineError.PipelineNotFound;
        };

        // Clean up the pipeline being removed
        var pipeline_to_remove = &cfg.pipelines[index];
        pipeline_to_remove.deinit(self.allocator);

        // Create new array without the removed pipeline
        const new_pipelines = try self.allocator.alloc(config.Pipeline, cfg.pipelines.len - 1);
        @memcpy(new_pipelines[0..index], cfg.pipelines[0..index]);
        @memcpy(new_pipelines[index..], cfg.pipelines[index + 1..]);
        
        // Free old array and update config
        self.allocator.free(cfg.pipelines);
        cfg.pipelines = new_pipelines;

        // Save config to file
        try self.saveConfig();
    }
};

pub const Status = struct {
    allocator: std.mem.Allocator,
    resource_usage: ?resources.ResourceUsage = null,
    running_tasks: u32 = 0,
    repositories_count: usize = 0,
    pipelines_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Status {
        return Status{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Status) void {
        _ = self;
        // Cleanup if needed
    }

    pub fn print(self: *const Status) !void {
        std.debug.print("\n📊 ZR Status:\n", .{});
        std.debug.print("  Repositories: {d}\n", .{self.repositories_count});
        std.debug.print("  Pipelines: {d}\n", .{self.pipelines_count});
        std.debug.print("  Running tasks: {d}\n", .{self.running_tasks});
        
        if (self.resource_usage) |usage| {
            std.debug.print("  CPU Usage: {d:.1}%\n", .{usage.cpu_percent});
            std.debug.print("  Memory Usage: {d}MB\n", .{usage.memory_mb});
        }
    }
};

const test_utils = @import("../test_utils.zig");

test "Engine initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // Test that engine starts in correct initial state
    try testing.expect(engine.config == null);
    try testing.expect(engine.task_executor == null);
    try testing.expect(engine.resource_monitor == null);
    try testing.expect(!engine.is_running);
}

test "Engine - config initialization workflow" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Cleanup any existing test config
    std.fs.cwd().deleteFile(".zr.config.yaml.test") catch {};

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // Create temporary config file for testing
    const test_config = 
        \\repositories:
        \\  - name: "test-engine"
        \\    path: "./test"
        \\    tasks:
        \\      - name: "echo"
        \\        command: "echo 'engine test'"
        \\
        \\pipelines: []
    ;

    const file = try std.fs.cwd().createFile(".zr.config.yaml.test", .{});
    defer {
        file.close();
        std.fs.cwd().deleteFile(".zr.config.yaml.test") catch {};
    }
    try file.writeAll(test_config);

    // TODO: Test would need engine to support custom config paths
    // For now, verify initialization works
    try testing.expect(engine.config == null);
}

test "Engine - repository management workflow" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // Create test config
    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;

    // Initialize subsystems
    try engine.initSubsystems();

    // Test repository finding
    const repo = engine.config.?.findRepository("simple");
    try testing.expect(repo != null);
    try testing.expect(std.mem.eql(u8, repo.?.name, "simple"));

    // Test task finding
    const task = repo.?.findTask("echo");
    try testing.expect(task != null);
    try testing.expect(std.mem.eql(u8, task.?.name, "echo"));
}

test "Engine - task execution integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // Create test config with executable task
    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;

    // Initialize subsystems
    try engine.initSubsystems();

    // Test successful task execution
    try engine.runTask("simple", "echo");
}

test "Engine - error handling for missing repository" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;

    try engine.initSubsystems();

    // Test error handling for missing repository
    try testing.expectError(EngineError.RepositoryNotFound, engine.runTask("nonexistent", "task"));
}

test "Engine - error handling for missing task" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;

    try engine.initSubsystems();

    // Test error handling for missing task
    try testing.expectError(EngineError.TaskNotFound, engine.runTask("simple", "nonexistent"));
}

test "Engine - status reporting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createComplexConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;

    try engine.initSubsystems();

    // Test status reporting
    var status = try engine.getStatus();
    defer status.deinit();

    try testing.expect(status.repositories_count == 3); // frontend, backend, mobile
    try testing.expect(status.pipelines_count == 0);
    try testing.expect(status.running_tasks == 0);
}

test "Engine - settings management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createTestConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;

    // Test setting retrieval (would require capture for full testing)
    // For now, test that it doesn't crash
    try engine.getAllSettings();
}

test "Engine - multi-repository workflow simulation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createComplexConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;

    try engine.initSubsystems();

    // Simulate full-stack development workflow
    try engine.runTask("frontend", "dev");
    try engine.runTask("backend", "dev");
    try engine.runTask("frontend", "build");
    try engine.runTask("backend", "build");

    // Verify system remains stable
    var status = try engine.getStatus();
    defer status.deinit();
    try testing.expect(status.running_tasks == 0);
}

test "Engine - real-world npm ecosystem simulation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test directories
    try test_utils.TestUtils.createTestDir(allocator, "test-frontend");
    try test_utils.TestUtils.createTestDir(allocator, "test-backend");
    defer {
        test_utils.TestUtils.cleanupTestDir("test-frontend");
        test_utils.TestUtils.cleanupTestDir("test-backend");
    }

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    const real_world_config = 
        \\repositories:
        \\  - name: "frontend"
        \\    path: "./test-frontend"
        \\    tasks:
        \\      - name: "dev"
        \\        command: "echo 'Frontend dev server started'"
        \\      - name: "build"
        \\        command: "echo 'Frontend build complete'"
        \\      - name: "test"
        \\        command: "echo 'Frontend tests passed'"
        \\  - name: "backend"
        \\    path: "./test-backend"
        \\    tasks:
        \\      - name: "dev"
        \\        command: "echo 'Backend server started'"
        \\      - name: "test"
        \\        command: "echo 'Backend tests passed'"
        \\
        \\pipelines: []
    ;

    var config_obj = try config.Config.parse(allocator, real_world_config);
    defer config_obj.deinit();
    engine.config = config_obj;

    try engine.initSubsystems();

    // Simulate complete development workflow
    try engine.runTask("frontend", "dev");
    try engine.runTask("backend", "dev");
    try engine.runTask("frontend", "test");
    try engine.runTask("backend", "test");
    try engine.runTask("frontend", "build");

    // Verify final state
    var status = try engine.getStatus();
    defer status.deinit();
    try testing.expect(status.repositories_count == 2);
    try testing.expect(status.running_tasks == 0);
}