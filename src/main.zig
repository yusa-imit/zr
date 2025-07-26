const std = @import("std");
const core = @import("core/engine.zig");
const config = @import("config/parser.zig");
const ui = @import("ui/console.zig");
const resources = @import("resources/monitor.zig");

pub fn main() !void {
    const builtin = @import("builtin");
    
    // Use C allocator in debug mode to avoid leak reporting spam
    // for short-lived CLI tools where memory is reclaimed by OS
    if (builtin.mode == .Debug) {
        try mainWithAllocator(std.heap.c_allocator);
    } else {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        try mainWithAllocator(gpa.allocator());
    }
}

fn mainWithAllocator(allocator: std.mem.Allocator) !void {
    // Initialize the ZR engine
    var engine = try core.Engine.init(allocator);
    defer engine.deinit();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try showHelp();
        return;
    }

    const command = args[1];

    // Handle commands
    if (std.mem.eql(u8, command, "init")) {
        try handleInit(&engine);
    } else if (std.mem.eql(u8, command, "interactive")) {
        try handleInteractive(&engine);
    } else if (std.mem.eql(u8, command, "run")) {
        if (args.len < 4) {
            std.debug.print("Usage: zr run <repository> <task>\n", .{});
            return;
        }
        try handleRun(&engine, args[2], args[3]);
    } else if (std.mem.eql(u8, command, "pipeline")) {
        if (args.len < 3) {
            std.debug.print("Usage: zr pipeline <run|add|remove|list> [name] [args...]\n", .{});
            return;
        }
        try handlePipelineCommand(&engine, args);
    } else if (std.mem.eql(u8, command, "repo")) {
        try handleRepoCommand(&engine, args);
    } else if (std.mem.eql(u8, command, "settings")) {
        try handleSettingsCommand(&engine, args);
    } else if (std.mem.eql(u8, command, "list")) {
        try handleList(&engine);
    } else if (std.mem.eql(u8, command, "status")) {
        try handleStatus(&engine);
    } else if (std.mem.eql(u8, command, "help")) {
        try showHelp();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try showHelp();
    }
}

fn handleInit(engine: *core.Engine) !void {
    try engine.initConfig();
    std.debug.print("✅ ZR configuration initialized\n", .{});
}

fn handleInteractive(engine: *core.Engine) !void {
    try engine.loadConfig();
    var console = try ui.Console.init(engine.allocator, engine);
    defer console.deinit();
    try console.run();
}

fn handleRun(engine: *core.Engine, repo_name: []const u8, task_name: []const u8) !void {
    try engine.loadConfig();
    try engine.runTask(repo_name, task_name);
}

fn handlePipelineCommand(engine: *core.Engine, args: [][:0]u8) !void {
    if (args.len < 3) {
        std.debug.print("Usage: zr pipeline <run|add|remove|list> [args...]\n", .{});
        return;
    }

    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "run")) {
        if (args.len < 4) {
            std.debug.print("Usage: zr pipeline run <pipeline-name>\n", .{});
            return;
        }
        try engine.loadConfig();
        try engine.runPipeline(args[3]);
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 5) {
            std.debug.print("Usage: zr pipeline add <name> <repo1:task1,repo2:task2,...>\n", .{});
            return;
        }
        try engine.loadConfig();
        
        const name = args[3];
        const stage_spec = args[4];
        try engine.addPipeline(name, stage_spec);
        std.debug.print("✅ Pipeline '{s}' added\n", .{name});
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 4) {
            std.debug.print("Usage: zr pipeline remove <name>\n", .{});
            return;
        }
        try engine.loadConfig();
        
        const name = args[3];
        try engine.removePipeline(name);
        std.debug.print("✅ Pipeline '{s}' removed\n", .{name});
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try engine.loadConfig();
        try engine.listPipelines();
    } else {
        std.debug.print("Unknown pipeline subcommand: {s}\n", .{subcommand});
    }
}

fn handleList(engine: *core.Engine) !void {
    try engine.loadConfig();
    try engine.listRepositories();
    try engine.listPipelines();
}

fn handleStatus(engine: *core.Engine) !void {
    try engine.loadConfig();
    var status = try engine.getStatus();
    defer status.deinit();
    try status.print();
}

fn handleRepoCommand(engine: *core.Engine, args: [][:0]u8) !void {
    if (args.len < 3) {
        std.debug.print("Usage: zr repo <add|remove|list>\n", .{});
        std.debug.print("  zr repo add <name> <path> [task-name] [task-command]\n", .{});
        std.debug.print("  zr repo remove <name>\n", .{});
        std.debug.print("  zr repo list\n", .{});
        return;
    }

    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 5) {
            std.debug.print("Usage: zr repo add <name> <path> [task-name] [task-command]\n", .{});
            return;
        }
        try engine.loadConfig();
        
        const name = args[3];
        const path = args[4];
        const task_name = if (args.len > 5) args[5] else "build";
        const task_command = if (args.len > 6) args[6] else "echo 'No command specified'";
        
        try engine.addRepository(name, path, task_name, task_command);
        std.debug.print("✅ Repository '{s}' added at '{s}'\n", .{ name, path });
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 4) {
            std.debug.print("Usage: zr repo remove <name>\n", .{});
            return;
        }
        try engine.loadConfig();
        
        const name = args[3];
        try engine.removeRepository(name);
        std.debug.print("✅ Repository '{s}' removed\n", .{name});
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try engine.loadConfig();
        try engine.listRepositories();
    } else {
        std.debug.print("Unknown repo subcommand: {s}\n", .{subcommand});
    }
}

fn handleSettingsCommand(engine: *core.Engine, args: [][:0]u8) !void {
    if (args.len < 3) {
        std.debug.print("Usage: zr settings <get|set>\n", .{});
        std.debug.print("  zr settings get [key]\n", .{});
        std.debug.print("  zr settings set <key> <value>\n", .{});
        std.debug.print("Available keys: max_cpu, max_memory, max_tasks, timeout\n", .{});
        return;
    }

    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "get")) {
        try engine.loadConfig();
        if (args.len > 3) {
            try engine.getSetting(args[3]);
        } else {
            try engine.getAllSettings();
        }
    } else if (std.mem.eql(u8, subcommand, "set")) {
        if (args.len < 5) {
            std.debug.print("Usage: zr settings set <key> <value>\n", .{});
            return;
        }
        try engine.loadConfig();
        
        const key = args[3];
        const value = args[4];
        try engine.setSetting(key, value);
        std.debug.print("✅ Setting '{s}' updated to '{s}'\n", .{ key, value });
    } else {
        std.debug.print("Unknown settings subcommand: {s}\n", .{subcommand});
    }
}

fn showHelp() !void {
    const help_text =
        \\ZR - Ultimate Language Agnostic Command Running Solution
        \\
        \\Usage:
        \\  zr <command> [arguments]
        \\
        \\Commands:
        \\  init                     Initialize ZR configuration
        \\  interactive              Start interactive console mode
        \\  run <repo> <task>        Run a task in a repository
        \\  pipeline <run|add|remove|list>  Manage and execute pipelines
        \\  list                     List repositories and pipelines
        \\  status                   Show current status and resource usage
        \\  repo <add|remove|list>   Manage repositories
        \\  settings <get|set>       Configure global settings
        \\  help                     Show this help message
        \\
        \\Configuration Commands:
        \\  zr repo add <name> <path> [task] [command]
        \\  zr repo remove <name>
        \\  zr repo list
        \\  zr pipeline add <name> <repo1:task1,repo2:task2,...>
        \\  zr pipeline remove <name>
        \\  zr pipeline run <name>
        \\  zr pipeline list
        \\  zr settings get [key]
        \\  zr settings set <key> <value>
        \\
        \\Examples:
        \\  zr init
        \\  zr repo add frontend ./apps/web build "npm run build"
        \\  zr repo add backend ./apps/api test "npm test"
        \\  zr pipeline add dev-build frontend:build,backend:test
        \\  zr settings set max_cpu 90
        \\  zr interactive
        \\  zr run frontend build
        \\  zr pipeline run dev-build
        \\
        \\For more information, see the documentation.
    ;
    std.debug.print("{s}\n", .{help_text});
}

test "main functionality" {
    const testing = std.testing;
    
    // Test help function doesn't crash
    try showHelp();
    
    // More tests would go here for each command handler
    _ = testing;
}