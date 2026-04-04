const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const Template = types.Template;
const Platform = types.Platform;
const TemplateType = types.TemplateType;
const github_actions = @import("github_actions.zig");
const gitlab = @import("gitlab.zig");

/// Template registry for discovering and accessing templates
pub const Registry = struct {
    allocator: Allocator,
    templates: std.ArrayList(Template),

    pub fn init(allocator: Allocator) Registry {
        return .{
            .allocator = allocator,
            .templates = .{},
        };
    }

    pub fn deinit(self: *Registry) void {
        self.templates.deinit(self.allocator);
    }

    /// Register all built-in templates
    pub fn registerBuiltins(self: *Registry) !void {
        // Register GitHub Actions templates
        for (github_actions.templates) |template| {
            try self.templates.append(self.allocator, template);
        }

        // Register GitLab CI templates
        for (gitlab.templates) |template| {
            try self.templates.append(self.allocator, template);
        }
    }

    /// Find templates matching optional filters
    pub fn find(
        self: *Registry,
        platform: ?Platform,
        template_type: ?TemplateType,
    ) ![]Template {
        var result: std.ArrayList(Template) = .{};
        errdefer result.deinit(self.allocator);

        for (self.templates.items) |template| {
            if (template.matches(platform, template_type)) {
                try result.append(self.allocator, template);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Get template by exact platform and type match
    pub fn get(
        self: *Registry,
        platform: Platform,
        template_type: TemplateType,
    ) ?Template {
        for (self.templates.items) |template| {
            if (template.platform == platform and template.template_type == template_type) {
                return template;
            }
        }
        return null;
    }

    /// List all templates (for CLI display)
    pub fn list(self: *Registry) []Template {
        return self.templates.items;
    }
};

test "Registry.init and deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try testing.expectEqual(@as(usize, 0), registry.templates.items.len);
}

test "Registry.registerBuiltins loads templates" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerBuiltins();

    // Should have GitHub Actions templates (3) + GitLab CI templates (3) = 6
    try testing.expect(registry.templates.items.len >= 6);
}

test "Registry.find with no filters returns all" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerBuiltins();

    const all_templates = try registry.find(null, null);
    defer allocator.free(all_templates);

    try testing.expectEqual(registry.templates.items.len, all_templates.len);
}

test "Registry.find with platform filter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerBuiltins();

    const gh_templates = try registry.find(.github_actions, null);
    defer allocator.free(gh_templates);

    // All returned templates should be GitHub Actions
    for (gh_templates) |template| {
        try testing.expectEqual(Platform.github_actions, template.platform);
    }
}

test "Registry.find with type filter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerBuiltins();

    const basic_templates = try registry.find(null, .basic_ci);
    defer allocator.free(basic_templates);

    // All returned templates should be basic_ci type
    for (basic_templates) |template| {
        try testing.expectEqual(TemplateType.basic_ci, template.template_type);
    }
}

test "Registry.get finds exact match" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerBuiltins();

    const template = registry.get(.github_actions, .basic_ci);
    try testing.expect(template != null);
    try testing.expectEqual(Platform.github_actions, template.?.platform);
    try testing.expectEqual(TemplateType.basic_ci, template.?.template_type);
}

test "Registry.get returns null for non-existent" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerBuiltins();

    // CircleCI templates not implemented yet
    const template = registry.get(.circleci, .basic_ci);
    try testing.expectEqual(@as(?Template, null), template);
}
