const std = @import("std");
const core = @import("../core/engine.zig");
const Engine = core.Engine;

pub const Console = struct {
    allocator: std.mem.Allocator,
    engine: *Engine,
    is_running: bool,
    command_history: std.ArrayList([]u8),

    const PROMPT = "zr> ";
    const BANNER =
        \\╔══════════════════════════════════════════════════════════════╗
        \\║                     ZR Interactive Console                   ║
        \\║          Ultimate Language Agnostic Command Runner          ║
        \\║                                                              ║
        \\║  Type 'help' for available commands or 'exit' to quit       ║
        \\╚══════════════════════════════════════════════════════════════╝
    ;

    pub fn init(allocator: std.mem.Allocator, engine: *Engine) !Console {
        return Console{
            .allocator = allocator,
            .engine = engine,
            .is_running = false,
            .command_history = std.ArrayList([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *Console) void {
        for (self.command_history.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.command_history.deinit();
    }

    pub fn run(self: *Console) !void {
        self.is_running = true;
        defer self.is_running = false;

        // Show banner
        if (self.engine.config.?.global.interface.color_output) {
            std.debug.print("\x1b[36m{s}\x1b[0m\n\n", .{BANNER});
        } else {
            std.debug.print("{s}\n\n", .{BANNER});
        }

        // Show initial status
        try self.showStatus();

        const stdin = std.io.getStdIn().reader();

        while (self.is_running) {
            // Show prompt
            if (self.engine.config.?.global.interface.color_output) {
                std.debug.print("\x1b[32m{s}\x1b[0m", .{PROMPT});
            } else {
                std.debug.print("{s}", .{PROMPT});
            }

            // Read input
            var buffer: [1024]u8 = undefined;
            if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
                const trimmed = std.mem.trim(u8, input, " \t\r\n");
                
                if (trimmed.len == 0) continue;

                // Store in history
                const cmd_copy = try self.allocator.dupe(u8, trimmed);
                try self.command_history.append(cmd_copy);

                // Process command
                try self.processCommand(trimmed);
            } else {
                // EOF reached, exit gracefully
                self.is_running = false;
                std.debug.print("\n👋 Goodbye!\n", .{});
                break;
            }
        }
    }

    fn processCommand(self: *Console, input: []const u8) !void {
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        // Split command into arguments
        var it = std.mem.tokenizeScalar(u8, input, ' ');
        while (it.next()) |arg| {
            try args.append(arg);
        }

        if (args.items.len == 0) return;

        const command = args.items[0];

        if (std.mem.eql(u8, command, "help")) {
            try self.showHelp();
        } else if (std.mem.eql(u8, command, "exit") or std.mem.eql(u8, command, "quit")) {
            self.is_running = false;
            std.debug.print("👋 Goodbye!\n", .{});
        } else if (std.mem.eql(u8, command, "status")) {
            try self.showStatus();
        } else if (std.mem.eql(u8, command, "list")) {
            try self.engine.listRepositories();
            try self.engine.listPipelines();
        } else if (std.mem.eql(u8, command, "repos")) {
            try self.engine.listRepositories();
        } else if (std.mem.eql(u8, command, "pipelines")) {
            try self.engine.listPipelines();
        } else if (std.mem.eql(u8, command, "run")) {
            if (args.items.len < 3) {
                std.debug.print("❌ Usage: run <repository> <task>\n", .{});
                return;
            }
            try self.handleRun(args.items[1], args.items[2]);
        } else if (std.mem.eql(u8, command, "pipeline")) {
            if (args.items.len < 2) {
                std.debug.print("❌ Usage: pipeline <pipeline-name>\n", .{});
                return;
            }
            try self.handlePipeline(args.items[1]);
        } else if (std.mem.eql(u8, command, "monitor")) {
            try self.toggleMonitoring();
        } else if (std.mem.eql(u8, command, "history")) {
            try self.showHistory();
        } else if (std.mem.eql(u8, command, "clear")) {
            try self.clearScreen();
        } else if (std.mem.eql(u8, command, "reload")) {
            try self.reloadConfig();
        } else {
            std.debug.print("❌ Unknown command: {s}. Type 'help' for available commands.\n", .{command});
        }
    }

    fn showHelp(self: *Console) !void {
        const color = self.engine.config.?.global.interface.color_output;
        
        const help_text = if (color)
            \\
            \\\x1b[33m📋 Available Commands:\x1b[0m
            \\
            \\  \x1b[36mGeneral:\x1b[0m
            \\    help                     Show this help message
            \\    exit, quit               Exit the interactive console
            \\    clear                    Clear the screen
            \\    status                   Show current status and resource usage
            \\    reload                   Reload configuration from file
            \\
            \\  \x1b[36mRepository & Pipeline Management:\x1b[0m
            \\    list                     List all repositories and pipelines
            \\    repos                    List repositories only
            \\    pipelines                List pipelines only
            \\    run <repo> <task>        Run a task in a repository
            \\    pipeline <name>          Execute a cross-repository pipeline
            \\
            \\  \x1b[36mMonitoring:\x1b[0m
            \\    monitor                  Toggle resource monitoring display
            \\    history                  Show command history
            \\
            \\  \x1b[36mExamples:\x1b[0m
            \\    run frontend dev
            \\    pipeline full-dev
            \\    status
            \\
        else
            \\
            \\📋 Available Commands:
            \\
            \\  General:
            \\    help                     Show this help message
            \\    exit, quit               Exit the interactive console
            \\    clear                    Clear the screen
            \\    status                   Show current status and resource usage
            \\    reload                   Reload configuration from file
            \\
            \\  Repository & Pipeline Management:
            \\    list                     List all repositories and pipelines
            \\    repos                    List repositories only
            \\    pipelines                List pipelines only
            \\    run <repo> <task>        Run a task in a repository
            \\    pipeline <name>          Execute a cross-repository pipeline
            \\
            \\  Monitoring:
            \\    monitor                  Toggle resource monitoring display
            \\    history                  Show command history
            \\
            \\  Examples:
            \\    run frontend dev
            \\    pipeline full-dev
            \\    status
            \\
        ;
        
        std.debug.print("{s}\n", .{help_text});
    }

    fn showStatus(self: *Console) !void {
        var status = try self.engine.getStatus();
        defer status.deinit();

        const color = self.engine.config.?.global.interface.color_output;
        
        if (color) {
            std.debug.print("\n\x1b[36m📊 ZR Status:\x1b[0m\n", .{});
            std.debug.print("  \x1b[32m📁 Repositories:\x1b[0m {d}\n", .{status.repositories_count});
            std.debug.print("  \x1b[32m🔄 Pipelines:\x1b[0m {d}\n", .{status.pipelines_count});
            std.debug.print("  \x1b[32m⚡ Running tasks:\x1b[0m {d}\n", .{status.running_tasks});
            
            if (status.resource_usage) |usage| {
                const cpu_color = if (usage.cpu_percent > 80) "\x1b[31m" else if (usage.cpu_percent > 60) "\x1b[33m" else "\x1b[32m";
                const mem_color = if (usage.memory_mb > 3000) "\x1b[31m" else if (usage.memory_mb > 2000) "\x1b[33m" else "\x1b[32m";
                
                std.debug.print("  {s}💻 CPU Usage:\x1b[0m {d:.1}%\n", .{ cpu_color, usage.cpu_percent });
                std.debug.print("  {s}🧠 Memory Usage:\x1b[0m {d}MB\n", .{ mem_color, usage.memory_mb });
            }
        } else {
            try status.print();
        }
        
        std.debug.print("\n", .{});
    }

    fn handleRun(self: *Console, repo_name: []const u8, task_name: []const u8) !void {
        std.debug.print("\n", .{});
        self.engine.runTask(repo_name, task_name) catch |err| {
            const color = self.engine.config.?.global.interface.color_output;
            if (color) {
                std.debug.print("\x1b[31m❌ Task execution failed: {}\x1b[0m\n", .{err});
            } else {
                std.debug.print("❌ Task execution failed: {}\n", .{err});
            }
        };
        std.debug.print("\n", .{});
    }

    fn handlePipeline(self: *Console, pipeline_name: []const u8) !void {
        std.debug.print("\n", .{});
        self.engine.runPipeline(pipeline_name) catch |err| {
            const color = self.engine.config.?.global.interface.color_output;
            if (color) {
                std.debug.print("\x1b[31m❌ Pipeline execution failed: {}\x1b[0m\n", .{err});
            } else {
                std.debug.print("❌ Pipeline execution failed: {}\n", .{err});
            }
        };
        std.debug.print("\n", .{});
    }

    fn toggleMonitoring(self: *Console) !void {
        _ = self;
        std.debug.print("🔧 Resource monitoring toggle not yet implemented\n", .{});
    }

    fn showHistory(self: *Console) !void {
        std.debug.print("\n📜 Command History:\n", .{});
        if (self.command_history.items.len == 0) {
            std.debug.print("  (no commands in history)\n", .{});
        } else {
            for (self.command_history.items, 0..) |cmd, i| {
                std.debug.print("  {d:2}: {s}\n", .{ i + 1, cmd });
            }
        }
        std.debug.print("\n", .{});
    }

    fn clearScreen(self: *Console) !void {
        _ = self;
        std.debug.print("\x1b[2J\x1b[H", .{}); // ANSI escape codes to clear screen and move cursor to top
    }

    fn reloadConfig(self: *Console) !void {
        std.debug.print("🔄 Reloading configuration...\n", .{});
        self.engine.loadConfig() catch |err| {
            std.debug.print("❌ Failed to reload config: {}\n", .{err});
            return;
        };
        std.debug.print("✅ Configuration reloaded successfully\n", .{});
    }
};

const test_utils = @import("../test_utils.zig");

test "Console initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    try testing.expect(!console.is_running);
    try testing.expect(console.command_history.items.len == 0);
}

test "Console - command parsing and history" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // Set up test config
    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;
    try engine.initSubsystems();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    // Test command processing (without actual execution for testability)
    // Test history functionality by directly calling processCommand
    try console.processCommand("help");
    try console.processCommand("status");
    try console.processCommand("list");

    // Verify commands were added to history
    try testing.expect(console.command_history.items.len == 3);
    try testing.expect(std.mem.eql(u8, console.command_history.items[0], "help"));
    try testing.expect(std.mem.eql(u8, console.command_history.items[1], "status"));
    try testing.expect(std.mem.eql(u8, console.command_history.items[2], "list"));
}

test "Console - task execution commands" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;
    try engine.initSubsystems();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    // Test successful task execution command
    try console.processCommand("run simple echo");
    
    // Verify command was recorded
    try testing.expect(console.command_history.items.len == 1);
    try testing.expect(std.mem.eql(u8, console.command_history.items[0], "run simple echo"));
}

test "Console - error handling for invalid commands" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;
    try engine.initSubsystems();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    // Test invalid command (should not crash)
    try console.processCommand("invalid-command");
    try console.processCommand("run");  // Missing arguments
    try console.processCommand("run nonexistent task");  // Missing repo
    
    // Verify all commands were recorded despite being invalid
    try testing.expect(console.command_history.items.len == 3);
}

test "Console - multi-command workflow simulation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createComplexConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;
    try engine.initSubsystems();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    // Simulate a typical interactive session
    try console.processCommand("help");
    try console.processCommand("list");
    try console.processCommand("status");
    try console.processCommand("run frontend dev");
    try console.processCommand("run backend dev");
    try console.processCommand("run frontend build");
    try console.processCommand("history");

    // Verify complete workflow was recorded
    try testing.expect(console.command_history.items.len == 7);
    try testing.expect(std.mem.eql(u8, console.command_history.items[3], "run frontend dev"));
    try testing.expect(std.mem.eql(u8, console.command_history.items[4], "run backend dev"));
}

test "Console - command argument parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;
    try engine.initSubsystems();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    // Test commands with various argument patterns
    try console.processCommand("help");                    // No args
    try console.processCommand("list");                    // No args
    try console.processCommand("run simple echo");        // Two args
    try console.processCommand("run simple echo extra");  // Too many args (should work)
    try console.processCommand("   run   simple   echo   ");  // Extra whitespace

    try testing.expect(console.command_history.items.len == 5);
}

test "Console - state management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    // Test initial state
    try testing.expect(!console.is_running);
    try testing.expect(console.command_history.items.len == 0);

    // Test state after initialization
    console.is_running = true;
    try testing.expect(console.is_running);

    // Test cleanup state
    console.is_running = false;
    try testing.expect(!console.is_running);
}

test "Console - memory management with long session" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var config_obj = try test_utils.TestUtils.createMinimalConfig(allocator);
    defer config_obj.deinit();
    engine.config = config_obj;
    try engine.initSubsystems();

    var console = try Console.init(allocator, &engine);
    defer console.deinit();

    // Simulate a long interactive session with many commands
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try console.processCommand("status");
    }

    // Verify all commands were recorded and memory is properly managed
    try testing.expect(console.command_history.items.len == 100);
    
    // All commands should be identical
    for (console.command_history.items) |cmd| {
        try testing.expect(std.mem.eql(u8, cmd, "status"));
    }
}