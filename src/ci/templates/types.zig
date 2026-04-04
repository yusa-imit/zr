const std = @import("std");
const Allocator = std.mem.Allocator;

/// CI/CD platform types
pub const Platform = enum {
    github_actions,
    gitlab_ci,
    circleci,

    pub fn fromString(s: []const u8) ?Platform {
        if (std.mem.eql(u8, s, "github-actions")) return .github_actions;
        if (std.mem.eql(u8, s, "gitlab")) return .gitlab_ci;
        if (std.mem.eql(u8, s, "circleci")) return .circleci;
        return null;
    }

    pub fn toString(self: Platform) []const u8 {
        return switch (self) {
            .github_actions => "github-actions",
            .gitlab_ci => "gitlab",
            .circleci => "circleci",
        };
    }
};

/// Template type categories
pub const TemplateType = enum {
    basic_ci,
    monorepo,
    release,

    pub fn fromString(s: []const u8) ?TemplateType {
        if (std.mem.eql(u8, s, "basic")) return .basic_ci;
        if (std.mem.eql(u8, s, "monorepo")) return .monorepo;
        if (std.mem.eql(u8, s, "release")) return .release;
        return null;
    }

    pub fn toString(self: TemplateType) []const u8 {
        return switch (self) {
            .basic_ci => "basic",
            .monorepo => "monorepo",
            .release => "release",
        };
    }
};

/// Template variable for substitution
pub const TemplateVariable = struct {
    name: []const u8,
    description: []const u8,
    default_value: ?[]const u8,
    required: bool,

    pub fn init(name: []const u8, description: []const u8, default_value: ?[]const u8, required: bool) TemplateVariable {
        return .{
            .name = name,
            .description = description,
            .default_value = default_value,
            .required = required,
        };
    }
};

/// CI/CD template definition
pub const Template = struct {
    platform: Platform,
    template_type: TemplateType,
    name: []const u8,
    description: []const u8,
    content: []const u8,
    variables: []const TemplateVariable,

    pub fn init(
        platform: Platform,
        template_type: TemplateType,
        name: []const u8,
        description: []const u8,
        content: []const u8,
        variables: []const TemplateVariable,
    ) Template {
        return .{
            .platform = platform,
            .template_type = template_type,
            .name = name,
            .description = description,
            .content = content,
            .variables = variables,
        };
    }

    /// Check if template matches platform and type filters
    pub fn matches(self: Template, platform: ?Platform, template_type: ?TemplateType) bool {
        if (platform) |p| {
            if (self.platform != p) return false;
        }
        if (template_type) |t| {
            if (self.template_type != t) return false;
        }
        return true;
    }
};

test "Platform.fromString valid inputs" {
    const testing = std.testing;
    try testing.expectEqual(Platform.github_actions, Platform.fromString("github-actions").?);
    try testing.expectEqual(Platform.gitlab_ci, Platform.fromString("gitlab").?);
    try testing.expectEqual(Platform.circleci, Platform.fromString("circleci").?);
}

test "Platform.fromString invalid input" {
    const testing = std.testing;
    try testing.expectEqual(@as(?Platform, null), Platform.fromString("invalid"));
}

test "TemplateType.fromString valid inputs" {
    const testing = std.testing;
    try testing.expectEqual(TemplateType.basic_ci, TemplateType.fromString("basic").?);
    try testing.expectEqual(TemplateType.monorepo, TemplateType.fromString("monorepo").?);
    try testing.expectEqual(TemplateType.release, TemplateType.fromString("release").?);
}

test "Template.matches filters correctly" {
    const testing = std.testing;
    const template = Template.init(
        .github_actions,
        .basic_ci,
        "test",
        "Test template",
        "content",
        &[_]TemplateVariable{},
    );

    // Match with no filters
    try testing.expect(template.matches(null, null));

    // Match with platform filter
    try testing.expect(template.matches(.github_actions, null));
    try testing.expect(!template.matches(.gitlab_ci, null));

    // Match with type filter
    try testing.expect(template.matches(null, .basic_ci));
    try testing.expect(!template.matches(null, .monorepo));

    // Match with both filters
    try testing.expect(template.matches(.github_actions, .basic_ci));
    try testing.expect(!template.matches(.github_actions, .monorepo));
    try testing.expect(!template.matches(.gitlab_ci, .basic_ci));
}
