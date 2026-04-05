const std = @import("std");
const types = @import("types.zig");
const Template = types.Template;
const Category = types.Category;

const build_templates = @import("builtin/build.zig");
const test_templates = @import("builtin/test.zig");
const lint_templates = @import("builtin/lint.zig");
const deploy_templates = @import("builtin/deploy.zig");
const ci_templates = @import("builtin/ci.zig");
const release_templates = @import("builtin/release.zig");

/// Global template registry with all built-in templates
pub const Registry = struct {
    templates: []const Template,

    pub fn init() Registry {
        // Concatenate all template arrays
        const all_templates = build_templates.all ++ test_templates.all ++ lint_templates.all ++ deploy_templates.all ++ ci_templates.all ++ release_templates.all;
        return .{ .templates = &all_templates };
    }

    /// Get all templates
    pub fn getAll(self: Registry) []const Template {
        return self.templates;
    }

    /// Get templates by category
    pub fn getByCategory(self: Registry, allocator: std.mem.Allocator, category: Category) ![]const Template {
        var result = std.ArrayList(Template){};
        errdefer result.deinit(allocator);

        for (self.templates) |template| {
            if (template.category == category) {
                try result.append(allocator, template);
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Find template by name
    pub fn findByName(self: Registry, name: []const u8) ?Template {
        for (self.templates) |template| {
            if (std.mem.eql(u8, template.name, name)) {
                return template;
            }
        }
        return null;
    }

    /// Get total number of templates
    pub fn count(self: Registry) usize {
        return self.templates.len;
    }
};

test "Registry.init" {
    const registry = Registry.init();
    const testing = std.testing;

    // Should have templates from all categories
    try testing.expect(registry.count() > 0);
    try testing.expect(registry.count() >= 6); // At least one per category
}

test "Registry.findByName" {
    const registry = Registry.init();
    const testing = std.testing;

    const template = registry.findByName("go-build");
    try testing.expect(template != null);
    try testing.expectEqualStrings("go-build", template.?.name);
    try testing.expectEqual(Category.build, template.?.category);

    const not_found = registry.findByName("nonexistent");
    try testing.expect(not_found == null);
}

test "Registry.getByCategory" {
    const registry = Registry.init();
    const testing = std.testing;
    const allocator = testing.allocator;

    const build = try registry.getByCategory(allocator, .build);
    defer allocator.free(build);
    try testing.expect(build.len > 0);

    for (build) |template| {
        try testing.expectEqual(Category.build, template.category);
    }

    const lint = try registry.getByCategory(allocator, .lint);
    defer allocator.free(lint);
    try testing.expect(lint.len > 0);
}
