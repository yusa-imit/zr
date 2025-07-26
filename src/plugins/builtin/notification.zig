const std = @import("std");
const PluginInterface = @import("../mod.zig").PluginInterface;
const PluginError = @import("../mod.zig").PluginError;

// Desktop notification plugin
// Provides desktop notifications for task completion and system events

pub const plugin_interface = PluginInterface{
    .name = "notification",
    .version = "1.0.0",
    .description = "Desktop notifications for ZR events",
    .author = "ZR Core Team",
    
    .init = init,
    .deinit = deinit,
    
    .beforeTask = null,
    .afterTask = afterTask,
    .beforePipeline = null,
    .afterPipeline = afterPipeline,
    .onResourceLimit = onResourceLimit,
    
    .validateConfig = validateConfig,
};

var allocator: ?std.mem.Allocator = null;
var notifications_enabled: bool = true;
var notify_on_success: bool = true;
var notify_on_failure: bool = true;
var notify_on_resource_limit: bool = true;
var notification_sound: bool = false;

fn init(alloc: std.mem.Allocator, config: []const u8) PluginError!void {
    allocator = alloc;
    
    // Parse plugin configuration
    if (config.len > 0) {
        if (std.mem.indexOf(u8, config, "enabled: false")) |_| {
            notifications_enabled = false;
        }
        if (std.mem.indexOf(u8, config, "success: false")) |_| {
            notify_on_success = false;
        }
        if (std.mem.indexOf(u8, config, "failure: false")) |_| {
            notify_on_failure = false;
        }
        if (std.mem.indexOf(u8, config, "resource_limit: false")) |_| {
            notify_on_resource_limit = false;
        }
        if (std.mem.indexOf(u8, config, "sound: true")) |_| {
            notification_sound = true;
        }
    }
    
    std.debug.print("🔔 Notification plugin initialized\n", .{});
    if (notifications_enabled) {
        std.debug.print("  📢 Notifications enabled\n", .{});
        if (notification_sound) {
            std.debug.print("  🔊 Sound notifications enabled\n", .{});
        }
    } else {
        std.debug.print("  🔇 Notifications disabled\n", .{});
    }
}

fn deinit() void {
    std.debug.print("🔔 Notification plugin deinitialized\n", .{});
}

fn afterTask(repo: []const u8, task: []const u8, success: bool) PluginError!void {
    if (!notifications_enabled) return;
    
    if (success and notify_on_success) {
        const success_msg = try formatMessage("Task {s}:{s} completed successfully", .{ repo, task });
        defer if (allocator) |alloc| alloc.free(success_msg);
        try sendNotification(
            "ZR Task Completed",
            success_msg,
            NotificationType.success
        );
    } else if (!success and notify_on_failure) {
        const fail_msg = try formatMessage("Task {s}:{s} failed", .{ repo, task });
        defer if (allocator) |alloc| alloc.free(fail_msg);
        try sendNotification(
            "ZR Task Failed",
            fail_msg,
            NotificationType.failure
        );
    }
}

fn afterPipeline(pipeline: []const u8, success: bool) PluginError!void {
    if (!notifications_enabled) return;
    
    if (success and notify_on_success) {
        const success_msg = try formatMessage("Pipeline {s} completed successfully", .{pipeline});
        defer if (allocator) |alloc| alloc.free(success_msg);
        try sendNotification(
            "ZR Pipeline Completed",
            success_msg,
            NotificationType.success
        );
    } else if (!success and notify_on_failure) {
        const fail_msg = try formatMessage("Pipeline {s} failed", .{pipeline});
        defer if (allocator) |alloc| alloc.free(fail_msg);
        try sendNotification(
            "ZR Pipeline Failed", 
            fail_msg,
            NotificationType.failure
        );
    }
}

fn onResourceLimit(cpu_percent: f32, memory_mb: u32) PluginError!void {
    if (!notifications_enabled or !notify_on_resource_limit) return;
    
    const resource_msg = try formatMessage("Resource limit reached: CPU {d:.1}%, Memory {d}MB", .{ cpu_percent, memory_mb });
    defer if (allocator) |alloc| alloc.free(resource_msg);
    try sendNotification(
        "ZR Resource Limit",
        resource_msg,
        NotificationType.warning
    );
}

fn validateConfig(config: []const u8) PluginError!bool {
    // Validate notification plugin configuration
    _ = config;
    // In real implementation, would validate YAML structure
    return true;
}

const NotificationType = enum {
    success,
    failure,
    warning,
    info,
};

fn sendNotification(title: []const u8, message: []const u8, notification_type: NotificationType) !void {
    const icon = switch (notification_type) {
        .success => "✅",
        .failure => "❌", 
        .warning => "⚠️",
        .info => "ℹ️",
    };
    
    // For now, just print to console
    // In real implementation, would use system notification APIs
    std.debug.print("  🔔 [{s}] {s}: {s}\n", .{ icon, title, message });
    
    if (notification_sound) {
        try playNotificationSound(notification_type);
    }
    
    // Platform-specific notification implementation would go here:
    // - macOS: Use osascript to call Notification Center
    // - Linux: Use notify-send or D-Bus
    // - Windows: Use Windows Toast notifications
    
    try sendPlatformNotification(title, message, notification_type);
}

fn sendPlatformNotification(title: []const u8, message: []const u8, notification_type: NotificationType) !void {
    const alloc = allocator orelse return;
    
    // Detect platform and send appropriate notification
    const builtin = @import("builtin");
    
    switch (builtin.os.tag) {
        .macos => {
            // Use osascript for macOS notifications
            const script = try std.fmt.allocPrint(alloc, 
                "osascript -e 'display notification \"{s}\" with title \"{s}\"'", 
                .{ message, title }
            );
            defer alloc.free(script);
            
            var child = std.process.Child.init(&[_][]const u8{ "sh", "-c", script }, alloc);
            _ = child.spawnAndWait() catch |err| {
                std.debug.print("  ⚠️ Failed to send macOS notification: {}\n", .{err});
            };
        },
        .linux => {
            // Use notify-send for Linux notifications
            const urgency = switch (notification_type) {
                .failure => "critical",
                .warning => "normal", 
                .success, .info => "low",
            };
            
            var child = std.process.Child.init(&[_][]const u8{ 
                "notify-send", 
                "--urgency", urgency,
                title, 
                message 
            }, alloc);
            _ = child.spawnAndWait() catch |err| {
                std.debug.print("  ⚠️ Failed to send Linux notification: {}\n", .{err});
            };
        },
        .windows => {
            // Windows notifications would require more complex implementation
            std.debug.print("  ℹ️ Windows notifications not yet implemented\n", .{});
        },
        else => {
            std.debug.print("  ℹ️ Platform notifications not supported on this OS\n", .{});
        },
    }
}

fn playNotificationSound(notification_type: NotificationType) !void {
    // Play system sound based on notification type
    const builtin = @import("builtin");
    const alloc = allocator orelse return;
    
    switch (builtin.os.tag) {
        .macos => {
            const sound = switch (notification_type) {
                .success => "Glass",
                .failure => "Basso",
                .warning => "Ping",
                .info => "Tink",
            };
            
            var child = std.process.Child.init(&[_][]const u8{ "afplay", 
                try std.fmt.allocPrint(alloc, "/System/Library/Sounds/{s}.aiff", .{sound})
            }, alloc);
            _ = child.spawnAndWait() catch {}; // Ignore errors for sound
        },
        .linux => {
            // Use paplay or aplay for Linux sound
            var child = std.process.Child.init(&[_][]const u8{ "paplay", "/usr/share/sounds/alsa/Front_Left.wav" }, alloc);
            _ = child.spawnAndWait() catch {}; // Ignore errors for sound
        },
        else => {},
    }
}

fn formatMessage(comptime fmt: []const u8, args: anytype) ![]u8 {
    const alloc = allocator orelse return PluginError.PluginInitFailed;
    return try std.fmt.allocPrint(alloc, fmt, args);
}

test "Notification plugin initialization" {
    const testing = std.testing;
    const test_allocator = testing.allocator;
    
    try init(test_allocator, "");
    defer deinit();
    
    // Test basic initialization
    try testing.expect(notifications_enabled == true);
    try testing.expect(notify_on_success == true);
    try testing.expect(notify_on_failure == true);
}

test "Notification plugin with config" {
    const testing = std.testing;
    const test_allocator = testing.allocator;
    
    const config = "enabled: true\nsuccess: false\nsound: true";
    try init(test_allocator, config);
    defer deinit();
    
    // Test configuration parsing
    try testing.expect(notifications_enabled == true);
    try testing.expect(notify_on_success == false);
    try testing.expect(notification_sound == true);
}

test "Notification plugin task notifications" {
    const testing = std.testing;
    const test_allocator = testing.allocator;
    
    try init(test_allocator, "");
    defer deinit();
    
    // Test task completion notifications
    try afterTask("frontend", "build", true);
    try afterTask("backend", "test", false);
    
    // Test pipeline notifications
    try afterPipeline("full-dev", true);
    try afterPipeline("test-all", false);
}

test "Notification plugin resource limit alert" {
    const testing = std.testing;
    const test_allocator = testing.allocator;
    
    try init(test_allocator, "");
    defer deinit();
    
    // Test resource limit notification
    try onResourceLimit(95.5, 8192);
}