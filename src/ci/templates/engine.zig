const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;

/// Variable values for template rendering
pub const VariableMap = std.StringHashMap([]const u8);

/// Render template with variable substitution
pub fn render(allocator: Allocator, template: Template, variables: VariableMap) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < template.content.len) {
        // Look for ${VAR} pattern
        if (i + 2 < template.content.len and template.content[i] == '$' and template.content[i + 1] == '{') {
            // Find closing }
            const start = i + 2;
            var end: ?usize = null;
            var j = start;
            while (j < template.content.len) : (j += 1) {
                if (template.content[j] == '}') {
                    end = j;
                    break;
                }
            }

            if (end) |e| {
                const var_name = template.content[start..e];

                // Look up variable value
                if (variables.get(var_name)) |value| {
                    try result.appendSlice(allocator, value);
                } else {
                    // Check if variable has default value
                    var has_default = false;
                    for (template.variables) |template_var| {
                        if (std.mem.eql(u8, template_var.name, var_name)) {
                            if (template_var.default_value) |default| {
                                try result.appendSlice(allocator, default);
                                has_default = true;
                            }
                            break;
                        }
                    }

                    // If no value and no default, keep placeholder
                    if (!has_default) {
                        try result.appendSlice(allocator, "${");
                        try result.appendSlice(allocator, var_name);
                        try result.append(allocator, '}');
                    }
                }

                i = e + 1;
                continue;
            }
        }

        // No variable pattern, append character as-is
        try result.append(allocator, template.content[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

/// Validate that all required variables are provided
pub fn validateVariables(template: Template, variables: VariableMap) !void {
    for (template.variables) |template_var| {
        if (template_var.required) {
            if (!variables.contains(template_var.name) and template_var.default_value == null) {
                return error.MissingRequiredVariable;
            }
        }
    }
}

test "render with simple variable" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const vars_array = [_]TemplateVariable{
        TemplateVariable.init("PROJECT", "Project name", null, true),
    };

    const template = Template.init(
        .github_actions,
        .basic_ci,
        "test",
        "Test template",
        "name: ${PROJECT}",
        &vars_array,
    );

    var variables = VariableMap.init(allocator);
    defer variables.deinit();
    try variables.put("PROJECT", "zr");

    const result = try render(allocator, template, variables);
    defer allocator.free(result);

    try testing.expectEqualStrings("name: zr", result);
}

test "render with multiple variables" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const vars_array = [_]TemplateVariable{
        TemplateVariable.init("PROJECT", "Project name", null, true),
        TemplateVariable.init("VERSION", "Version", null, true),
    };

    const template = Template.init(
        .github_actions,
        .basic_ci,
        "test",
        "Test template",
        "${PROJECT} v${VERSION}",
        &vars_array,
    );

    var variables = VariableMap.init(allocator);
    defer variables.deinit();
    try variables.put("PROJECT", "zr");
    try variables.put("VERSION", "1.0.0");

    const result = try render(allocator, template, variables);
    defer allocator.free(result);

    try testing.expectEqualStrings("zr v1.0.0", result);
}

test "render with default value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const vars_array = [_]TemplateVariable{
        TemplateVariable.init("PROJECT", "Project name", "my-project", false),
    };

    const template = Template.init(
        .github_actions,
        .basic_ci,
        "test",
        "Test template",
        "name: ${PROJECT}",
        &vars_array,
    );

    var variables = VariableMap.init(allocator);
    defer variables.deinit();
    // Don't provide PROJECT, should use default

    const result = try render(allocator, template, variables);
    defer allocator.free(result);

    try testing.expectEqualStrings("name: my-project", result);
}

test "render preserves unknown variables" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const template = Template.init(
        .github_actions,
        .basic_ci,
        "test",
        "Test template",
        "unknown: ${UNKNOWN}",
        &[_]TemplateVariable{},
    );

    var variables = VariableMap.init(allocator);
    defer variables.deinit();

    const result = try render(allocator, template, variables);
    defer allocator.free(result);

    try testing.expectEqualStrings("unknown: ${UNKNOWN}", result);
}

test "validateVariables succeeds with all required" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const vars_array = [_]TemplateVariable{
        TemplateVariable.init("PROJECT", "Project name", null, true),
        TemplateVariable.init("OPTIONAL", "Optional var", "default", false),
    };

    const template = Template.init(
        .github_actions,
        .basic_ci,
        "test",
        "Test",
        "content",
        &vars_array,
    );

    var variables = VariableMap.init(allocator);
    defer variables.deinit();
    try variables.put("PROJECT", "zr");

    try validateVariables(template, variables);
}

test "validateVariables fails with missing required" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const vars_array = [_]TemplateVariable{
        TemplateVariable.init("PROJECT", "Project name", null, true),
    };

    const template = Template.init(
        .github_actions,
        .basic_ci,
        "test",
        "Test",
        "content",
        &vars_array,
    );

    var variables = VariableMap.init(allocator);
    defer variables.deinit();

    try testing.expectError(error.MissingRequiredVariable, validateVariables(template, variables));
}
