const std = @import("std");

pub const MigrationReport = struct {
    source_file: []const u8,
    tasks_converted: usize,
    warnings: std.ArrayList([]const u8),
    manual_steps: std.ArrayList([]const u8),
    unsupported_features: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, source_file: []const u8) !MigrationReport {
        return .{
            .source_file = try allocator.dupe(u8, source_file),
            .tasks_converted = 0,
            .warnings = std.ArrayList([]const u8){},
            .manual_steps = std.ArrayList([]const u8){},
            .unsupported_features = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *MigrationReport, allocator: std.mem.Allocator) void {
        allocator.free(self.source_file);
        for (self.warnings.items) |warning| allocator.free(warning);
        self.warnings.deinit(allocator);
        for (self.manual_steps.items) |step| allocator.free(step);
        self.manual_steps.deinit(allocator);
        for (self.unsupported_features.items) |feature| allocator.free(feature);
        self.unsupported_features.deinit(allocator);
    }

    pub fn addWarning(self: *MigrationReport, allocator: std.mem.Allocator, warning: []const u8) !void {
        try self.warnings.append(allocator, try allocator.dupe(u8, warning));
    }

    pub fn addManualStep(self: *MigrationReport, allocator: std.mem.Allocator, step: []const u8) !void {
        try self.manual_steps.append(allocator, try allocator.dupe(u8, step));
    }

    pub fn addUnsupportedFeature(self: *MigrationReport, allocator: std.mem.Allocator, feature: []const u8) !void {
        try self.unsupported_features.append(allocator, try allocator.dupe(u8, feature));
    }

    /// Format the report as a human-readable string
    pub fn format(self: MigrationReport, allocator: std.mem.Allocator, use_color: bool) ![]const u8 {
        var buf = std.ArrayList(u8){};
        const writer = buf.writer(allocator);

        // Header
        if (use_color) {
            try writer.writeAll("\x1b[1;32m✓ Migration Summary\x1b[0m\n\n");
        } else {
            try writer.writeAll("✓ Migration Summary\n\n");
        }

        // Stats
        try writer.print("Source:  {s}\n", .{self.source_file});
        try writer.print("Tasks converted: {d}\n\n", .{self.tasks_converted});

        // Warnings
        if (self.warnings.items.len > 0) {
            if (use_color) {
                try writer.writeAll("\x1b[1;33m⚠ Warnings\x1b[0m\n");
            } else {
                try writer.writeAll("⚠ Warnings\n");
            }
            for (self.warnings.items) |warning| {
                try writer.print("  • {s}\n", .{warning});
            }
            try writer.writeAll("\n");
        }

        // Unsupported features
        if (self.unsupported_features.items.len > 0) {
            if (use_color) {
                try writer.writeAll("\x1b[1;31m✗ Unsupported Features\x1b[0m\n");
            } else {
                try writer.writeAll("✗ Unsupported Features\n");
            }
            for (self.unsupported_features.items) |feature| {
                try writer.print("  • {s}\n", .{feature});
            }
            try writer.writeAll("\n");
        }

        // Manual steps
        if (self.manual_steps.items.len > 0) {
            if (use_color) {
                try writer.writeAll("\x1b[1;36mℹ Manual Steps Required\x1b[0m\n");
            } else {
                try writer.writeAll("ℹ Manual Steps Required\n");
            }
            for (self.manual_steps.items, 0..) |step, idx| {
                try writer.print("  {d}. {s}\n", .{ idx + 1, step });
            }
            try writer.writeAll("\n");
        }

        return try buf.toOwnedSlice(allocator);
    }
};

test "MigrationReport basic functionality" {
    var report = try MigrationReport.init(std.testing.allocator, "package.json");
    defer report.deinit(std.testing.allocator);

    report.tasks_converted = 5;
    try report.addWarning(std.testing.allocator, "Some scripts use environment variables that need manual configuration");
    try report.addManualStep(std.testing.allocator, "Add env section for DATABASE_URL");
    try report.addUnsupportedFeature(std.testing.allocator, "Workspaces field in package.json");

    try std.testing.expectEqual(@as(usize, 5), report.tasks_converted);
    try std.testing.expectEqual(@as(usize, 1), report.warnings.items.len);
    try std.testing.expectEqual(@as(usize, 1), report.manual_steps.items.len);
    try std.testing.expectEqual(@as(usize, 1), report.unsupported_features.items.len);
}

test "MigrationReport format output" {
    var report = try MigrationReport.init(std.testing.allocator, "Makefile");
    defer report.deinit(std.testing.allocator);

    report.tasks_converted = 3;
    try report.addWarning(std.testing.allocator, "Pattern rules not fully supported");
    try report.addManualStep(std.testing.allocator, "Review automatically generated dependencies");

    const formatted = try report.format(std.testing.allocator, false);
    defer std.testing.allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "Makefile") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Tasks converted: 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Pattern rules") != null);
}
