const std = @import("std");
const config = @import("../config/parser.zig");
const Config = config.Config;
const Repository = config.Repository;
const Task = config.Task;
const Pipeline = config.Pipeline;

pub const TaskExecutor = struct {
    allocator: std.mem.Allocator,
    config: *const Config,
    running_tasks: std.atomic.Value(u32),
    task_pool: std.Thread.Pool,

    pub fn init(allocator: std.mem.Allocator, cfg: *const Config) !TaskExecutor {
        // Temporarily create a simplified executor without Thread.Pool
        return TaskExecutor{
            .allocator = allocator,
            .config = cfg,
            .running_tasks = std.atomic.Value(u32).init(0),
            .task_pool = undefined, // We'll handle this differently
        };
    }

    pub fn deinit(self: *TaskExecutor) void {
        _ = self;
        // self.task_pool.deinit();
    }

    pub fn executeTask(self: *TaskExecutor, repository: *const Repository, task: *const Task) !void {
        if (task.isSimple()) {
            try self.executeSimpleTask(repository, task);
        } else {
            try self.executeComplexTask(repository, task);
        }
    }

    fn executeSimpleTask(self: *TaskExecutor, repository: *const Repository, task: *const Task) !void {
        const command = task.command.?;
        
        std.debug.print("  🔧 Executing: {s}\n", .{command});
        
        const result = try self.runCommand(repository.path, command);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            std.debug.print("  ❌ Command failed with exit code {d}\n", .{result.exit_code});
            if (result.stderr.len > 0) {
                std.debug.print("  Error: {s}\n", .{result.stderr});
            }
            return error.CommandFailed;
        }

        if (result.stdout.len > 0) {
            std.debug.print("  📝 Output: {s}\n", .{result.stdout});
        }
    }

    fn executeComplexTask(self: *TaskExecutor, repository: *const Repository, task: *const Task) !void {
        std.debug.print("  🔧 Executing complex task with {d} groups\n", .{task.groups.len});

        for (task.groups) |group| {
            std.debug.print("    📂 Group: {s} (parallel: {})\n", .{ group.name, group.parallel });
            
            if (group.parallel) {
                try self.executeGroupParallel(repository, &group);
            } else {
                try self.executeGroupSequential(repository, &group);
            }
        }
    }

    fn executeGroupSequential(self: *TaskExecutor, repository: *const Repository, group: *const config.TaskGroup) !void {
        for (group.commands) |command| {
            std.debug.print("    🔧 Executing: {s}\n", .{command});
            
            const result = try self.runCommand(repository.path, command);
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);

            if (result.exit_code != 0) {
                std.debug.print("    ❌ Command failed with exit code {d}\n", .{result.exit_code});
                if (result.stderr.len > 0) {
                    std.debug.print("    Error: {s}\n", .{result.stderr});
                }
                return error.CommandFailed;
            }

            if (result.stdout.len > 0) {
                std.debug.print("    📝 Output: {s}\n", .{result.stdout});
            }
        }
    }

    fn executeGroupParallel(self: *TaskExecutor, repository: *const Repository, group: *const config.TaskGroup) !void {
        // For now, implement a simple parallel execution using threads
        // This can be improved later with proper thread pool management
        
        var threads = std.ArrayList(std.Thread).init(self.allocator);
        defer threads.deinit();

        var results = std.ArrayList(CommandResult).init(self.allocator);
        defer {
            for (results.items) |result| {
                self.allocator.free(result.stdout);
                self.allocator.free(result.stderr);
            }
            results.deinit();
        }

        // Create a result slot for each command
        try results.resize(group.commands.len);

        // Spawn threads for each command
        for (group.commands, 0..) |command, i| {
            const thread = try std.Thread.spawn(.{}, executeCommandThread, .{ self, repository.path, command, &results.items[i] });
            try threads.append(thread);
        }

        // Wait for all threads to complete
        for (threads.items) |thread| {
            thread.join();
        }

        // Check results
        for (group.commands, 0..) |command, i| {
            const result = results.items[i];
            std.debug.print("    🔧 Completed: {s}\n", .{command});
            
            if (result.exit_code != 0) {
                std.debug.print("    ❌ Command failed with exit code {d}\n", .{result.exit_code});
                if (result.stderr.len > 0) {
                    std.debug.print("    Error: {s}\n", .{result.stderr});
                }
                return error.CommandFailed;
            }

            if (result.stdout.len > 0) {
                std.debug.print("    📝 Output: {s}\n", .{result.stdout});
            }
        }
    }

    pub fn executePipeline(self: *TaskExecutor, pipeline: *const Pipeline) !void {
        std.debug.print("  🚀 Executing pipeline with {d} stages\n", .{pipeline.stages.len});

        for (pipeline.stages) |stage| {
            std.debug.print("    🎯 Stage: {s} (parallel: {})\n", .{ stage.name, stage.parallel });
            
            if (stage.parallel) {
                try self.executeStageParallel(&stage);
            } else {
                try self.executeStageSequential(&stage);
            }
        }
    }

    fn executeStageSequential(self: *TaskExecutor, stage: *const config.PipelineStage) !void {
        for (stage.repositories) |repo_task| {
            const repository = self.config.findRepository(repo_task.repository) orelse {
                std.debug.print("    ❌ Repository '{s}' not found\n", .{repo_task.repository});
                return error.RepositoryNotFound;
            };

            const task = repository.findTask(repo_task.task) orelse {
                std.debug.print("    ❌ Task '{s}' not found in repository '{s}'\n", .{ repo_task.task, repo_task.repository });
                return error.TaskNotFound;
            };

            std.debug.print("    🔧 Running {s}:{s}\n", .{ repo_task.repository, repo_task.task });
            try self.executeTask(repository, task);
        }
    }

    fn executeStageParallel(self: *TaskExecutor, stage: *const config.PipelineStage) !void {
        // Similar to executeGroupParallel but for pipeline stage
        // Implementation would be similar but for repository tasks
        _ = self;
        _ = stage;
        std.debug.print("    🔧 Parallel stage execution not yet implemented\n", .{});
    }

    pub fn getRunningTasksCount(self: *const TaskExecutor) u32 {
        return self.running_tasks.load(.acquire);
    }

    const CommandResult = struct {
        exit_code: u8,
        stdout: []u8,
        stderr: []u8,
    };

    fn executeCommandThread(self: *TaskExecutor, working_dir: []const u8, command: []const u8, result: *CommandResult) void {
        result.* = self.runCommand(working_dir, command) catch CommandResult{
            .exit_code = 1,
            .stdout = self.allocator.dupe(u8, "") catch &[_]u8{},
            .stderr = self.allocator.dupe(u8, "Failed to execute command") catch &[_]u8{},
        };
    }

    fn runCommand(self: *TaskExecutor, working_dir: []const u8, command: []const u8) !CommandResult {
        _ = self.running_tasks.fetchAdd(1, .acq_rel);
        defer _ = self.running_tasks.fetchSub(1, .acq_rel);

        // Parse command into arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        var it = std.mem.tokenizeScalar(u8, command, ' ');
        while (it.next()) |arg| {
            try args.append(arg);
        }

        if (args.items.len == 0) {
            return error.EmptyCommand;
        }

        // Execute command
        var child = std.process.Child.init(args.items, self.allocator);
        child.cwd = working_dir;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB limit
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB limit

        const term = try child.wait();
        const exit_code: u8 = switch (term) {
            .Exited => |code| @intCast(code),
            .Signal => |sig| @intCast(128 + sig),
            .Stopped => |sig| @intCast(128 + sig),
            .Unknown => |code| @intCast(code),
        };

        return CommandResult{
            .exit_code = exit_code,
            .stdout = stdout,
            .stderr = stderr,
        };
    }
};


const test_utils = @import("../test_utils.zig");

test "TaskExecutor initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cfg = config.Config{
        .allocator = allocator,
        .global = config.GlobalConfig.default(),
        .repositories = &[_]config.Repository{},
        .pipelines = &[_]config.Pipeline{},
        .monitoring = config.MonitoringConfig.default(),
    };

    var executor = try TaskExecutor.init(allocator, &cfg);
    defer executor.deinit();

    try testing.expect(executor.getRunningTasksCount() == 0);
}

test "TaskExecutor - simple command execution" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a test repository with a simple echo task
    var repo = config.Repository{
        .name = "test-repo",
        .path = ".",
        .resources = null,
        .environment = std.StringHashMap([]const u8).init(allocator),
        .tasks = try allocator.alloc(config.Task, 1),
    };
    defer {
        repo.environment.deinit();
        allocator.free(repo.tasks);
    }

    repo.tasks[0] = config.Task{
        .name = "echo-test",
        .command = "echo 'Hello from ZR test'",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    var cfg = config.Config{
        .allocator = allocator,
        .global = config.GlobalConfig.default(),
        .repositories = try allocator.alloc(config.Repository, 1),
        .pipelines = &[_]config.Pipeline{},
        .monitoring = config.MonitoringConfig.default(),
    };
    defer allocator.free(cfg.repositories);
    cfg.repositories[0] = repo;

    var executor = try TaskExecutor.init(allocator, &cfg);
    defer executor.deinit();

    // Execute the task
    try executor.executeTask(&repo, &repo.tasks[0]);
    
    // Verify running tasks count returns to 0
    try testing.expect(executor.getRunningTasksCount() == 0);
}

test "TaskExecutor - command with output capture" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a repository with a task that produces output
    var repo = config.Repository{
        .name = "output-test",
        .path = ".",
        .resources = null,
        .environment = std.StringHashMap([]const u8).init(allocator),
        .tasks = try allocator.alloc(config.Task, 1),
    };
    defer {
        repo.environment.deinit();
        allocator.free(repo.tasks);
    }

    repo.tasks[0] = config.Task{
        .name = "date",
        .command = "date",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    var cfg = config.Config{
        .allocator = allocator,
        .global = config.GlobalConfig.default(),
        .repositories = try allocator.alloc(config.Repository, 1),
        .pipelines = &[_]config.Pipeline{},
        .monitoring = config.MonitoringConfig.default(),
    };
    defer allocator.free(cfg.repositories);
    cfg.repositories[0] = repo;

    var executor = try TaskExecutor.init(allocator, &cfg);
    defer executor.deinit();

    // This should execute successfully and capture output
    try executor.executeTask(&repo, &repo.tasks[0]);
}

test "TaskExecutor - command failure handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var repo = config.Repository{
        .name = "fail-test",
        .path = ".",
        .resources = null,
        .environment = std.StringHashMap([]const u8).init(allocator),
        .tasks = try allocator.alloc(config.Task, 1),
    };
    defer {
        repo.environment.deinit();
        allocator.free(repo.tasks);
    }

    repo.tasks[0] = config.Task{
        .name = "fail",
        .command = "false", // Command that always fails
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    var cfg = config.Config{
        .allocator = allocator,
        .global = config.GlobalConfig.default(),
        .repositories = try allocator.alloc(config.Repository, 1),
        .pipelines = &[_]config.Pipeline{},
        .monitoring = config.MonitoringConfig.default(),
    };
    defer allocator.free(cfg.repositories);
    cfg.repositories[0] = repo;

    var executor = try TaskExecutor.init(allocator, &cfg);
    defer executor.deinit();

    // This should fail with CommandFailed error
    try testing.expectError(error.CommandFailed, executor.executeTask(&repo, &repo.tasks[0]));
}

test "TaskExecutor - working directory handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test directory
    try test_utils.TestUtils.createTestDir(allocator, "test-workdir");
    defer test_utils.TestUtils.cleanupTestDir("test-workdir");

    var repo = config.Repository{
        .name = "workdir-test",
        .path = "./test-workdir",
        .resources = null,
        .environment = std.StringHashMap([]const u8).init(allocator),
        .tasks = try allocator.alloc(config.Task, 1),
    };
    defer {
        repo.environment.deinit();
        allocator.free(repo.tasks);
    }

    repo.tasks[0] = config.Task{
        .name = "pwd",
        .command = "pwd",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    var cfg = config.Config{
        .allocator = allocator,
        .global = config.GlobalConfig.default(),
        .repositories = try allocator.alloc(config.Repository, 1),
        .pipelines = &[_]config.Pipeline{},
        .monitoring = config.MonitoringConfig.default(),
    };
    defer allocator.free(cfg.repositories);
    cfg.repositories[0] = repo;

    var executor = try TaskExecutor.init(allocator, &cfg);
    defer executor.deinit();

    // Execute task in specific working directory
    try executor.executeTask(&repo, &repo.tasks[0]);
}

test "TaskExecutor - multiple sequential tasks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var repo = config.Repository{
        .name = "multi-test",
        .path = ".",
        .resources = null,
        .environment = std.StringHashMap([]const u8).init(allocator),
        .tasks = try allocator.alloc(config.Task, 3),
    };
    defer {
        repo.environment.deinit();
        allocator.free(repo.tasks);
    }

    repo.tasks[0] = config.Task{
        .name = "first",
        .command = "echo 'First task'",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    repo.tasks[1] = config.Task{
        .name = "second",
        .command = "echo 'Second task'",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    repo.tasks[2] = config.Task{
        .name = "third",
        .command = "echo 'Third task'",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    var cfg = config.Config{
        .allocator = allocator,
        .global = config.GlobalConfig.default(),
        .repositories = try allocator.alloc(config.Repository, 1),
        .pipelines = &[_]config.Pipeline{},
        .monitoring = config.MonitoringConfig.default(),
    };
    defer allocator.free(cfg.repositories);
    cfg.repositories[0] = repo;

    var executor = try TaskExecutor.init(allocator, &cfg);
    defer executor.deinit();

    // Execute tasks sequentially
    try executor.executeTask(&repo, &repo.tasks[0]);
    try executor.executeTask(&repo, &repo.tasks[1]);
    try executor.executeTask(&repo, &repo.tasks[2]);
    
    try testing.expect(executor.getRunningTasksCount() == 0);
}

test "TaskExecutor - npm/node ecosystem simulation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test npm project
    try test_utils.TestUtils.createTestDir(allocator, "test-npm");
    defer test_utils.TestUtils.cleanupTestDir("test-npm");

    var repo = config.Repository{
        .name = "npm-project",
        .path = "./test-npm",
        .resources = null,
        .environment = std.StringHashMap([]const u8).init(allocator),
        .tasks = try allocator.alloc(config.Task, 2),
    };
    defer {
        repo.environment.deinit();
        allocator.free(repo.tasks);
    }

    repo.tasks[0] = config.Task{
        .name = "dev",
        .command = "echo 'npm dev simulation'",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    repo.tasks[1] = config.Task{
        .name = "build",
        .command = "echo 'npm build simulation'",
        .pipeline = null,
        .dependencies = &[_][]const u8{},
        .groups = &[_]config.TaskGroup{},
    };

    var cfg = config.Config{
        .allocator = allocator,
        .global = config.GlobalConfig.default(),
        .repositories = try allocator.alloc(config.Repository, 1),
        .pipelines = &[_]config.Pipeline{},
        .monitoring = config.MonitoringConfig.default(),
    };
    defer allocator.free(cfg.repositories);
    cfg.repositories[0] = repo;

    var executor = try TaskExecutor.init(allocator, &cfg);
    defer executor.deinit();

    // Test npm-like development workflow
    try executor.executeTask(&repo, &repo.tasks[0]); // dev
    try executor.executeTask(&repo, &repo.tasks[1]); // build
}