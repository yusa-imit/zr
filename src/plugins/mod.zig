const std = @import("std");
const config = @import("../config/parser.zig");

// Plugin system core module
// Provides plugin discovery, loading, and lifecycle management

pub const PluginError = error{
    PluginNotFound,
    PluginLoadFailed,
    PluginInitFailed,
    PluginConfigInvalid,
    PluginDisabled,
} || std.mem.Allocator.Error || std.fs.File.OpenError;

// Plugin lifecycle hooks
pub const PluginHook = enum {
    BeforeTask,    // Called before task execution
    AfterTask,     // Called after task execution
    BeforePipeline, // Called before pipeline execution
    AfterPipeline,  // Called after pipeline execution
    OnResourceLimit, // Called when resource limits are hit
    OnInit,        // Called during ZR initialization
    OnShutdown,    // Called during ZR shutdown
};

// Plugin interface that all plugins must implement
pub const PluginInterface = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    
    // Plugin lifecycle callbacks
    init: ?*const fn(allocator: std.mem.Allocator, config: []const u8) PluginError!void,
    deinit: ?*const fn() void,
    
    // Hook implementations
    beforeTask: ?*const fn(repo: []const u8, task: []const u8) PluginError!void,
    afterTask: ?*const fn(repo: []const u8, task: []const u8, success: bool) PluginError!void,
    beforePipeline: ?*const fn(pipeline: []const u8) PluginError!void,
    afterPipeline: ?*const fn(pipeline: []const u8, success: bool) PluginError!void,
    onResourceLimit: ?*const fn(cpu_percent: f32, memory_mb: u32) PluginError!void,
    
    // Configuration validation
    validateConfig: ?*const fn(config: []const u8) PluginError!bool,
};

// Plugin metadata for discovery and management
pub const PluginMetadata = struct {
    name: []const u8,
    path: []const u8,
    enabled: bool,
    config: ?[]const u8,
    interface: ?PluginInterface,
    is_builtin: bool,
};

// Main plugin manager
pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(PluginMetadata),
    plugin_directory: []const u8,
    enabled: bool,
    builtin_plugins: std.ArrayList(BuiltinPlugin),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, plugin_dir: []const u8, enabled: bool) !Self {
        return Self{
            .allocator = allocator,
            .plugins = std.ArrayList(PluginMetadata).init(allocator),
            .plugin_directory = try allocator.dupe(u8, plugin_dir),
            .enabled = enabled,
            .builtin_plugins = std.ArrayList(BuiltinPlugin).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Cleanup all plugins
        for (self.plugins.items) |*plugin| {
            if (plugin.interface) |interface| {
                if (interface.deinit) |deinit_fn| {
                    deinit_fn();
                }
            }
            if (plugin.config) |cfg| {
                self.allocator.free(cfg);
            }
            self.allocator.free(plugin.name);
            self.allocator.free(plugin.path);
        }
        self.plugins.deinit();
        
        self.builtin_plugins.deinit();
        self.allocator.free(self.plugin_directory);
    }
    
    // Discovery and loading
    pub fn discoverPlugins(self: *Self) !void {
        if (!self.enabled) return;
        
        // Discover external plugins
        try self.discoverExternalPlugins();
        
        // Register built-in plugins
        try self.registerBuiltinPlugins();
    }
    
    fn discoverExternalPlugins(self: *Self) !void {
        // Check if plugin directory exists
        var dir = std.fs.cwd().openDir(self.plugin_directory, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("📦 Plugin directory '{s}' not found, skipping external plugins\n", .{self.plugin_directory});
                return;
            },
            else => return err,
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                try self.loadExternalPlugin(entry.name);
            }
        }
    }
    
    fn loadExternalPlugin(self: *Self, filename: []const u8) !void {
        const plugin_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.plugin_directory, filename });
        defer self.allocator.free(plugin_path);
        
        // Extract plugin name from filename
        const name_end = std.mem.lastIndexOf(u8, filename, ".") orelse filename.len;
        const plugin_name = try self.allocator.dupe(u8, filename[0..name_end]);
        
        const metadata = PluginMetadata{
            .name = plugin_name,
            .path = try self.allocator.dupe(u8, plugin_path),
            .enabled = true, // Default enabled, can be configured
            .config = null,
            .interface = null, // Would be loaded dynamically in a full implementation
            .is_builtin = false,
        };
        
        try self.plugins.append(metadata);
        std.debug.print("📦 Discovered external plugin: {s}\n", .{plugin_name});
    }
    
    fn registerBuiltinPlugins(self: *Self) !void {
        // Register built-in plugins
        try self.registerBuiltinPlugin("turbo-compat", &TurboCompatPlugin);
        try self.registerBuiltinPlugin("notification", &NotificationPlugin);
        try self.registerBuiltinPlugin("docker-runner", &DockerRunnerPlugin);
    }
    
    fn registerBuiltinPlugin(self: *Self, name: []const u8, plugin: *const BuiltinPlugin) !void {
        const metadata = PluginMetadata{
            .name = try self.allocator.dupe(u8, name),
            .path = try self.allocator.dupe(u8, "builtin"),
            .enabled = plugin.enabled_by_default,
            .config = null,
            .interface = plugin.interface,
            .is_builtin = true,
        };
        
        try self.plugins.append(metadata);
        try self.builtin_plugins.append(plugin.*);
        
        std.debug.print("📦 Registered builtin plugin: {s}\n", .{name});
    }
    
    // Plugin lifecycle management
    pub fn initializePlugins(self: *Self) !void {
        for (self.plugins.items) |*plugin| {
            if (!plugin.enabled) continue;
            
            if (plugin.interface) |interface| {
                if (interface.init) |init_fn| {
                    const config_str = plugin.config orelse "";
                    init_fn(self.allocator, config_str) catch |err| {
                        std.debug.print("⚠️  Plugin '{s}' initialization failed: {}\n", .{ plugin.name, err });
                        plugin.enabled = false; // Disable failed plugins
                    };
                }
            }
        }
    }
    
    // Hook execution
    pub fn executeHook(self: *Self, hook: PluginHook, args: anytype) !void {
        if (!self.enabled) return;
        
        for (self.plugins.items) |plugin| {
            if (!plugin.enabled) continue;
            
            if (plugin.interface) |interface| {
                switch (hook) {
                    .BeforeTask => {
                        if (interface.beforeTask) |hook_fn| {
                            if (@hasField(@TypeOf(args), "repo") and @hasField(@TypeOf(args), "task")) {
                                hook_fn(args.repo, args.task) catch |err| {
                                    std.debug.print("⚠️  Plugin '{s}' BeforeTask hook failed: {}\n", .{ plugin.name, err });
                                };
                            }
                        }
                    },
                    .AfterTask => {
                        if (interface.afterTask) |hook_fn| {
                            if (@hasField(@TypeOf(args), "repo") and @hasField(@TypeOf(args), "task") and @hasField(@TypeOf(args), "success")) {
                                hook_fn(args.repo, args.task, args.success) catch |err| {
                                    std.debug.print("⚠️  Plugin '{s}' AfterTask hook failed: {}\n", .{ plugin.name, err });
                                };
                            }
                        }
                    },
                    .BeforePipeline => {
                        if (interface.beforePipeline) |hook_fn| {
                            if (@hasField(@TypeOf(args), "pipeline")) {
                                hook_fn(args.pipeline) catch |err| {
                                    std.debug.print("⚠️  Plugin '{s}' BeforePipeline hook failed: {}\n", .{ plugin.name, err });
                                };
                            }
                        }
                    },
                    .AfterPipeline => {
                        if (interface.afterPipeline) |hook_fn| {
                            if (@hasField(@TypeOf(args), "pipeline") and @hasField(@TypeOf(args), "success")) {
                                hook_fn(args.pipeline, args.success) catch |err| {
                                    std.debug.print("⚠️  Plugin '{s}' AfterPipeline hook failed: {}\n", .{ plugin.name, err });
                                };
                            }
                        }
                    },
                    .OnResourceLimit => {
                        if (interface.onResourceLimit) |hook_fn| {
                            if (@hasField(@TypeOf(args), "cpu_percent") and @hasField(@TypeOf(args), "memory_mb")) {
                                hook_fn(args.cpu_percent, args.memory_mb) catch |err| {
                                    std.debug.print("⚠️  Plugin '{s}' OnResourceLimit hook failed: {}\n", .{ plugin.name, err });
                                };
                            }
                        }
                    },
                    .OnInit, .OnShutdown => {
                        // These are handled by initializePlugins and deinit
                    },
                }
            }
        }
    }
    
    // Plugin management
    pub fn enablePlugin(self: *Self, name: []const u8) !void {
        for (self.plugins.items) |*plugin| {
            if (std.mem.eql(u8, plugin.name, name)) {
                plugin.enabled = true;
                std.debug.print("✅ Enabled plugin: {s}\n", .{name});
                return;
            }
        }
        return PluginError.PluginNotFound;
    }
    
    pub fn disablePlugin(self: *Self, name: []const u8) !void {
        for (self.plugins.items) |*plugin| {
            if (std.mem.eql(u8, plugin.name, name)) {
                plugin.enabled = false;
                std.debug.print("❌ Disabled plugin: {s}\n", .{name});
                return;
            }
        }
        return PluginError.PluginNotFound;
    }
    
    pub fn listPlugins(self: *Self) void {
        std.debug.print("\n📦 ZR Plugins:\n", .{});
        if (self.plugins.items.len == 0) {
            std.debug.print("  No plugins loaded\n", .{});
            return;
        }
        
        for (self.plugins.items) |plugin| {
            const status = if (plugin.enabled) "✅" else "❌";
            const type_str = if (plugin.is_builtin) "builtin" else "external";
            std.debug.print("  {s} {s} ({s})\n", .{ status, plugin.name, type_str });
        }
    }
};

// Built-in plugin definition
pub const BuiltinPlugin = struct {
    interface: PluginInterface,
    enabled_by_default: bool,
};

// Forward declarations for built-in plugins
pub const TurboCompatPlugin: BuiltinPlugin = .{
    .interface = @import("builtin/turbo_compat.zig").plugin_interface,
    .enabled_by_default = true,
};

pub const NotificationPlugin: BuiltinPlugin = .{
    .interface = @import("builtin/notification.zig").plugin_interface,
    .enabled_by_default = true,
};

pub const DockerRunnerPlugin: BuiltinPlugin = .{
    .interface = @import("builtin/docker_runner.zig").plugin_interface,
    .enabled_by_default = false,
};

test "Plugin manager initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var manager = try PluginManager.init(allocator, "./test-plugins", true);
    defer manager.deinit();
    
    try testing.expect(manager.enabled);
    try testing.expect(std.mem.eql(u8, manager.plugin_directory, "./test-plugins"));
    try testing.expect(manager.plugins.items.len == 0);
}