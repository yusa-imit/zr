const std = @import("std");
const mem = std.mem;

/// Variable substitution engine for template rendering
/// Supports ${VAR} syntax with default values via ${VAR:default}
pub const Engine = struct {
    allocator: mem.Allocator,
    variables: std.StringHashMap([]const u8),

    pub fn init(allocator: mem.Allocator) Engine {
        return .{
            .allocator = allocator,
            .variables = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.variables.deinit();
    }

    /// Set a variable value for substitution
    pub fn setVar(self: *Engine, key: []const u8, value: []const u8) !void {
        try self.variables.put(key, value);
    }

    /// Render template content with variable substitution
    /// Returns allocated string that caller must free
    pub fn render(self: *Engine, template: []const u8) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < template.len) {
            // Look for ${VAR} or ${VAR:default}
            if (i + 2 < template.len and template[i] == '$' and template[i + 1] == '{') {
                const start = i + 2;
                const end_brace = mem.indexOfScalarPos(u8, template, start, '}') orelse {
                    // No closing brace, treat as literal
                    try result.append(self.allocator, template[i]);
                    i += 1;
                    continue;
                };

                const var_expr = template[start..end_brace];

                // Check for default value syntax: VAR:default
                const colon_pos = mem.indexOfScalar(u8, var_expr, ':');
                const var_name = if (colon_pos) |pos| var_expr[0..pos] else var_expr;
                const default_value = if (colon_pos) |pos| var_expr[pos + 1 ..] else null;

                // Lookup variable value
                const value = self.variables.get(var_name) orelse default_value orelse {
                    // No value and no default, leave as-is
                    try result.appendSlice(self.allocator, template[i .. end_brace + 1]);
                    i = end_brace + 1;
                    continue;
                };

                try result.appendSlice(self.allocator, value);
                i = end_brace + 1;
            } else {
                try result.append(self.allocator, template[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

test "Engine: basic variable substitution" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = Engine.init(allocator);
    defer engine.deinit();

    try engine.setVar("NAME", "myproject");
    try engine.setVar("VERSION", "1.0.0");

    const template = "project = \"${NAME}\"\nversion = \"${VERSION}\"";
    const result = try engine.render(template);
    defer allocator.free(result);

    try testing.expectEqualStrings("project = \"myproject\"\nversion = \"1.0.0\"", result);
}

test "Engine: default value syntax" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = Engine.init(allocator);
    defer engine.deinit();

    try engine.setVar("NAME", "myproject");
    // VERSION not set, should use default

    const template = "project = \"${NAME}\"\nversion = \"${VERSION:0.1.0}\"";
    const result = try engine.render(template);
    defer allocator.free(result);

    try testing.expectEqualStrings("project = \"myproject\"\nversion = \"0.1.0\"", result);
}

test "Engine: no substitution for missing var without default" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = Engine.init(allocator);
    defer engine.deinit();

    const template = "value = \"${MISSING}\"";
    const result = try engine.render(template);
    defer allocator.free(result);

    try testing.expectEqualStrings("value = \"${MISSING}\"", result);
}

test "Engine: no substitution for incomplete syntax" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = Engine.init(allocator);
    defer engine.deinit();

    const template = "value = \"${NO_CLOSE\"";
    const result = try engine.render(template);
    defer allocator.free(result);

    try testing.expectEqualStrings("value = \"${NO_CLOSE\"", result);
}

test "Engine: multiple variables in same line" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = Engine.init(allocator);
    defer engine.deinit();

    try engine.setVar("A", "foo");
    try engine.setVar("B", "bar");

    const template = "${A} and ${B}";
    const result = try engine.render(template);
    defer allocator.free(result);

    try testing.expectEqualStrings("foo and bar", result);
}
