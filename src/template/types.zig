const std = @import("std");

/// Template category for organizing built-in templates
pub const Category = enum {
    build,
    testing,
    lint,
    deploy,
    ci,
    release,

    pub fn toString(self: Category) []const u8 {
        return switch (self) {
            .build => "build",
            .testing => "test",
            .lint => "lint",
            .deploy => "deploy",
            .ci => "ci",
            .release => "release",
        };
    }
};

/// Template variable definition with default value and validation
pub const TemplateVariable = struct {
    name: []const u8,
    description: []const u8,
    default: ?[]const u8 = null,
    required: bool = false,
};

/// Task template with TOML content and metadata
pub const Template = struct {
    name: []const u8,
    category: Category,
    description: []const u8,
    variables: []const TemplateVariable = &.{},
    content: []const u8,
};

test "Category.toString" {
    const testing = std.testing;
    try testing.expectEqualStrings("build", Category.build.toString());
    try testing.expectEqualStrings("test", Category.testing.toString());
    try testing.expectEqualStrings("lint", Category.lint.toString());
}

test "Template creation" {
    const testing = std.testing;
    const template = Template{
        .name = "go-build",
        .category = .build,
        .description = "Build Go project",
        .content = "[tasks.build]\ncmd = \"go build\"",
    };

    try testing.expectEqualStrings("go-build", template.name);
    try testing.expectEqualStrings("build", template.category.toString());
    try testing.expectEqualStrings("Build Go project", template.description);
}
