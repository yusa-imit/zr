const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const template_types = @import("../template/types.zig");
const template_registry = @import("../template/registry.zig");
const template_engine = @import("../template/engine.zig");
const Template = template_types.Template;
const Category = template_types.Category;
const Registry = template_registry.Registry;
const Engine = template_engine.Engine;

pub const TemplateCommand = enum {
    list,
    show,
    add,
};

pub const TemplateOptions = struct {
    command: TemplateCommand,
    template_name: ?[]const u8 = null,
    category: ?Category = null,
    output_path: ?[]const u8 = null,
    variables: std.StringHashMap([]const u8),

    pub fn init(allocator: mem.Allocator) TemplateOptions {
        return .{
            .command = .list,
            .variables = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *TemplateOptions) void {
        self.variables.deinit();
    }
};

/// List all available templates, optionally filtered by category
pub fn listTemplates(writer: anytype, category: ?Category) !void {
    const registry = Registry.init();

    if (category) |cat| {
        try writer.print("Templates in category '{s}':\n\n", .{cat.toString()});
        var count: usize = 0;
        for (registry.getAll()) |template| {
            if (template.category == cat) {
                try printTemplateSummary(writer, template);
                count += 1;
            }
        }
        if (count == 0) {
            try writer.print("  (no templates in this category)\n", .{});
        }
    } else {
        try writer.print("Available templates ({d} total):\n\n", .{registry.count()});

        // Group by category
        inline for (@typeInfo(Category).@"enum".fields) |field| {
            const cat = @field(Category, field.name);
            try writer.print("[{s}]\n", .{cat.toString()});

            var found = false;
            for (registry.getAll()) |template| {
                if (template.category == cat) {
                    try writer.print("  • {s: <20} {s}\n", .{ template.name, template.description });
                    found = true;
                }
            }
            if (!found) {
                try writer.print("  (none)\n", .{});
            }
            try writer.print("\n", .{});
        }

        try writer.print("Use 'zr template show <name>' to see template details\n", .{});
    }
}

fn printTemplateSummary(writer: anytype, template: Template) !void {
    try writer.print("  • {s: <20} {s}\n", .{ template.name, template.description });
}

/// Show detailed information about a specific template
pub fn showTemplate(writer: anytype, name: []const u8) !void {
    const registry = Registry.init();
    const template = registry.findByName(name) orelse {
        try writer.print("Error: Template '{s}' not found\n", .{name});
        try writer.print("Run 'zr template list' to see available templates\n", .{});
        return error.TemplateNotFound;
    };

    try writer.print("Template: {s}\n", .{template.name});
    try writer.print("Category: {s}\n", .{template.category.toString()});
    try writer.print("Description: {s}\n\n", .{template.description});

    if (template.variables.len > 0) {
        try writer.print("Variables:\n", .{});
        for (template.variables) |v| {
            try writer.print("  ${{{s}}}", .{v.name});
            if (v.required) {
                try writer.print(" (required)", .{});
            } else if (v.default) |default| {
                try writer.print(" [default: {s}]", .{default});
            }
            try writer.print("\n    {s}\n", .{v.description});
        }
        try writer.print("\n", .{});
    }

    try writer.print("Template content:\n", .{});
    try writer.print("─────────────────────\n", .{});
    try writer.print("{s}\n", .{template.content});
    try writer.print("─────────────────────\n\n", .{});
    try writer.print("Usage: zr template add {s} [--var KEY=VALUE ...]\n", .{template.name});
}

/// Apply template to create task configuration
pub fn addTemplate(
    allocator: mem.Allocator,
    writer: anytype,
    name: []const u8,
    variables: std.StringHashMap([]const u8),
    output_path: ?[]const u8,
) !void {
    const registry = Registry.init();
    const template = registry.findByName(name) orelse {
        try writer.print("Error: Template '{s}' not found\n", .{name});
        return error.TemplateNotFound;
    };

    // Validate required variables
    for (template.variables) |v| {
        if (v.required and !variables.contains(v.name)) {
            try writer.print("Error: Required variable '{s}' not provided\n", .{v.name});
            try writer.print("Use --var {s}=VALUE to set it\n", .{v.name});
            return error.MissingRequiredVariable;
        }
    }

    // Render template with variable substitution
    var engine = Engine.init(allocator);
    defer engine.deinit();

    // Set user-provided variables
    var it = variables.iterator();
    while (it.next()) |entry| {
        try engine.setVar(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Set default values for variables not provided
    for (template.variables) |v| {
        if (!variables.contains(v.name)) {
            if (v.default) |default| {
                try engine.setVar(v.name, default);
            }
        }
    }

    const rendered = try engine.render(template.content);
    defer allocator.free(rendered);

    // Output to file or stdout
    if (output_path) |path| {
        const file = try fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(rendered);
        try writer.print("Template '{s}' written to {s}\n", .{ template.name, path });
    } else {
        // Print to stdout with header
        try writer.print("# Template: {s}\n", .{template.name});
        try writer.print("# To append to zr.toml:\n", .{});
        try writer.print("#   zr template add {s} >> zr.toml\n\n", .{template.name});
        try writer.print("{s}\n", .{rendered});
    }
}

test "listTemplates with all categories" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try listTemplates(buf.writer(allocator), null);

    const output = buf.items;
    try testing.expect(mem.indexOf(u8, output, "Available templates") != null);
    try testing.expect(mem.indexOf(u8, output, "[build]") != null);
    try testing.expect(mem.indexOf(u8, output, "[test]") != null);
    try testing.expect(mem.indexOf(u8, output, "[lint]") != null);
}

test "listTemplates with specific category" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try listTemplates(buf.writer(allocator), .build);

    const output = buf.items;
    try testing.expect(mem.indexOf(u8, output, "category 'build'") != null);
    try testing.expect(mem.indexOf(u8, output, "go-build") != null);
}

test "showTemplate existing template" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try showTemplate(buf.writer(allocator), "go-build");

    const output = buf.items;
    try testing.expect(mem.indexOf(u8, output, "Template: go-build") != null);
    try testing.expect(mem.indexOf(u8, output, "Category: build") != null);
    try testing.expect(mem.indexOf(u8, output, "Variables:") != null);
}

test "showTemplate non-existent template" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const result = showTemplate(buf.writer(allocator), "nonexistent");
    try testing.expectError(error.TemplateNotFound, result);
}

test "addTemplate with all variables" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    var variables = std.StringHashMap([]const u8).init(allocator);
    defer variables.deinit();

    try variables.put("PROJECT_NAME", "myapp");
    try variables.put("OUTPUT_DIR", "./dist");

    try addTemplate(allocator, buf.writer(allocator), "go-build", variables, null);

    const output = buf.items;
    try testing.expect(mem.indexOf(u8, output, "myapp") != null);
    try testing.expect(mem.indexOf(u8, output, "./dist") != null);
}

test "addTemplate missing required variable" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    var variables = std.StringHashMap([]const u8).init(allocator);
    defer variables.deinit();
    // Not providing PROJECT_NAME which is required

    const result = addTemplate(allocator, buf.writer(allocator), "go-build", variables, null);
    try testing.expectError(error.MissingRequiredVariable, result);
}
