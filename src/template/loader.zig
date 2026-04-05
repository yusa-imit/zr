const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const types = @import("types.zig");
const Template = types.Template;
const TemplateVariable = types.TemplateVariable;
const Category = types.Category;

/// Load custom templates from a directory
pub fn loadFromDirectory(allocator: mem.Allocator, dir_path: []const u8) !std.ArrayList(Template) {
    var templates = std.ArrayList(Template).init(allocator);
    errdefer templates.deinit();

    var dir = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            return templates; // Directory doesn't exist, return empty list
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!mem.endsWith(u8, entry.name, ".toml")) continue;

        const file_path = try fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(file_path);

        const template = loadFromFile(allocator, file_path) catch |err| {
            std.debug.print("Warning: Failed to load template '{s}': {}\n", .{ entry.name, err });
            continue;
        };

        try templates.append(template);
    }

    return templates;
}

/// Load a single template from a TOML file
pub fn loadFromFile(allocator: mem.Allocator, file_path: []const u8) !Template {
    const file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // Max 1MB
    defer allocator.free(content);

    return parseTemplate(allocator, file_path, content);
}

/// Parse template metadata and content from TOML
fn parseTemplate(allocator: mem.Allocator, file_path: []const u8, content: []const u8) !Template {
    // Simple TOML parser for template metadata
    // Expected format:
    // name = "my-template"
    // category = "build"
    // description = "My custom template"
    // variables = [
    //   { name = "VAR1", description = "...", required = true },
    //   { name = "VAR2", description = "...", default = "value" }
    // ]
    // [content]
    // ...TOML content...

    var name: ?[]const u8 = null;
    var category: Category = .build;
    var description: ?[]const u8 = null;
    var variables = std.ArrayList(TemplateVariable).init(allocator);
    errdefer variables.deinit();

    var lines = mem.split(u8, content, "\n");
    var in_content_section = false;
    var content_buf = std.ArrayList(u8).init(allocator);
    errdefer content_buf.deinit();

    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (mem.eql(u8, trimmed, "[content]")) {
            in_content_section = true;
            continue;
        }

        if (in_content_section) {
            try content_buf.appendSlice(line);
            try content_buf.append('\n');
            continue;
        }

        // Parse metadata
        if (mem.indexOf(u8, trimmed, "name = ")) |_| {
            name = try parseStringValue(allocator, trimmed);
        } else if (mem.indexOf(u8, trimmed, "category = ")) |_| {
            const cat_str = try parseStringValue(allocator, trimmed);
            defer allocator.free(cat_str);
            category = parseCategoryString(cat_str);
        } else if (mem.indexOf(u8, trimmed, "description = ")) |_| {
            description = try parseStringValue(allocator, trimmed);
        }
        // Note: Variable parsing would require a full TOML parser
        // For now, we skip variable definitions in custom templates
    }

    const template_name = name orelse {
        // Extract name from filename (e.g., "my-template.toml" -> "my-template")
        const basename = fs.path.basename(file_path);
        const dot_idx = mem.indexOf(u8, basename, ".") orelse basename.len;
        return error.MissingTemplateName;
    };

    return Template{
        .name = template_name,
        .category = category,
        .description = description orelse try allocator.dupe(u8, "Custom template"),
        .variables = try variables.toOwnedSlice(),
        .content = try content_buf.toOwnedSlice(),
    };
}

fn parseStringValue(allocator: mem.Allocator, line: []const u8) ![]const u8 {
    const eq_idx = mem.indexOf(u8, line, "=") orelse return error.InvalidFormat;
    const value_part = mem.trim(u8, line[eq_idx + 1 ..], " \t\r\"");
    return allocator.dupe(u8, value_part);
}

fn parseCategoryString(str: []const u8) Category {
    if (mem.eql(u8, str, "build")) return .build;
    if (mem.eql(u8, str, "test") or mem.eql(u8, str, "testing")) return .testing;
    if (mem.eql(u8, str, "lint")) return .lint;
    if (mem.eql(u8, str, "deploy")) return .deploy;
    if (mem.eql(u8, str, "ci")) return .ci;
    if (mem.eql(u8, str, "release")) return .release;
    return .build; // default
}

test "loadFromDirectory empty directory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const templates = try loadFromDirectory(allocator, tmp_path);
    defer templates.deinit();

    try testing.expectEqual(@as(usize, 0), templates.items.len);
}

test "loadFromDirectory nonexistent directory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const templates = try loadFromDirectory(allocator, "/nonexistent/path/12345");
    defer templates.deinit();

    try testing.expectEqual(@as(usize, 0), templates.items.len);
}

test "parseTemplate with basic metadata" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const content =
        \\name = "custom-build"
        \\category = "build"
        \\description = "Custom build template"
        \\[content]
        \\[tasks.build]
        \\cmd = "make build"
    ;

    const template = try parseTemplate(allocator, "custom-build.toml", content);
    defer allocator.free(template.name);
    defer allocator.free(template.description);
    defer allocator.free(template.content);

    try testing.expectEqualStrings("custom-build", template.name);
    try testing.expectEqual(Category.build, template.category);
    try testing.expectEqualStrings("Custom build template", template.description);
    try testing.expect(mem.indexOf(u8, template.content, "[tasks.build]") != null);
}

test "parseCategoryString" {
    const testing = std.testing;
    try testing.expectEqual(Category.build, parseCategoryString("build"));
    try testing.expectEqual(Category.testing, parseCategoryString("test"));
    try testing.expectEqual(Category.lint, parseCategoryString("lint"));
    try testing.expectEqual(Category.deploy, parseCategoryString("deploy"));
    try testing.expectEqual(Category.ci, parseCategoryString("ci"));
    try testing.expectEqual(Category.release, parseCategoryString("release"));
    try testing.expectEqual(Category.build, parseCategoryString("unknown")); // default
}
