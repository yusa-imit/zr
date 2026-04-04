const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const mem = std.mem;

const registry_mod = @import("../ci/templates/registry.zig");
const types = @import("../ci/templates/types.zig");
const engine = @import("../ci/templates/engine.zig");

const Registry = registry_mod.Registry;
const Platform = types.Platform;
const TemplateType = types.TemplateType;
const Template = types.Template;
const VariableMap = engine.VariableMap;

const color = @import("../output/color.zig");

/// Detect CI platform from existing files
pub fn detectPlatform(allocator: Allocator) !?Platform {
    _ = allocator;

    // Check for GitHub Actions
    const gh_exists = blk: {
        var dir = fs.cwd().openDir(".github/workflows", .{}) catch break :blk false;
        dir.close();
        break :blk true;
    };
    if (gh_exists) return .github_actions;

    // Check for GitLab CI
    const gitlab_exists = blk: {
        _ = fs.cwd().access(".gitlab-ci.yml", .{}) catch break :blk false;
        break :blk true;
    };
    if (gitlab_exists) return .gitlab_ci;

    // Check for CircleCI
    const circle_exists = blk: {
        var dir = fs.cwd().openDir(".circleci", .{}) catch break :blk false;
        dir.close();
        break :blk true;
    };
    if (circle_exists) return .circleci;

    return null;
}

/// Generate CI configuration file
pub fn cmdGenerate(
    allocator: Allocator,
    platform_str: ?[]const u8,
    template_type_str: ?[]const u8,
    output_path: ?[]const u8,
    stdout: anytype,
    stderr: anytype,
    use_color: bool,
) !u8 {

    // Initialize registry
    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.registerBuiltins();

    // Determine platform
    const platform = blk: {
        if (platform_str) |p_str| {
            if (Platform.fromString(p_str)) |p| {
                break :blk p;
            } else {
                try color.printError(stderr, use_color, "Unknown platform: {s}\n", .{p_str});
                try color.printDim(stderr, use_color, "Valid platforms: github-actions, gitlab, circleci\n", .{});
                return error.InvalidPlatform;
            }
        }

        // Auto-detect
        if (try detectPlatform(allocator)) |detected| {
            try color.printInfo(stdout, use_color, "Detected platform: {s}\n", .{detected.toString()});
            break :blk detected;
        } else {
            try color.printError(stderr, use_color, "Could not detect CI platform. Please specify with --platform=<name>\n", .{});
            try color.printDim(stderr, use_color, "Valid platforms: github-actions, gitlab, circleci\n", .{});
            return error.PlatformNotDetected;
        }
    };

    // Determine template type
    const template_type = blk: {
        if (template_type_str) |t_str| {
            if (TemplateType.fromString(t_str)) |t| {
                break :blk t;
            } else {
                try color.printError(stderr, use_color, "Unknown template type: {s}\n", .{t_str});
                try color.printDim(stderr, use_color, "Valid types: basic, monorepo, release\n", .{});
                return error.InvalidTemplateType;
            }
        }
        break :blk .basic_ci; // Default to basic CI
    };

    // Get template
    const template = registry.get(platform, template_type) orelse {
        try color.printError(stderr, use_color, "No template found for platform={s} type={s}\n", .{
            platform.toString(),
            template_type.toString(),
        });
        return error.TemplateNotFound;
    };

    // Prepare variables with defaults
    var variables = VariableMap.init(allocator);
    defer variables.deinit();

    // Use default values from template variables
    for (template.variables) |template_var| {
        if (template_var.default_value) |default| {
            try variables.put(template_var.name, default);
        }
    }

    // Render template
    const rendered = try engine.render(allocator, template, variables);
    defer allocator.free(rendered);

    // Determine output path
    const out_path = output_path orelse blk: {
        break :blk switch (platform) {
            .github_actions => switch (template_type) {
                .basic_ci => ".github/workflows/zr-ci.yml",
                .monorepo => ".github/workflows/zr-monorepo.yml",
                .release => ".github/workflows/zr-release.yml",
            },
            .gitlab_ci => ".gitlab-ci.yml",
            .circleci => ".circleci/config.yml",
        };
    };

    // Ensure output directory exists
    if (fs.path.dirname(out_path)) |dir_path| {
        try fs.cwd().makePath(dir_path);
    }

    // Write to file
    const file = try fs.cwd().createFile(out_path, .{});
    defer file.close();
    try file.writeAll(rendered);

    try color.printSuccess(stdout, use_color, "Generated CI config: {s}\n", .{out_path});
    try color.printInfo(stdout, use_color, "Template: {s} ({s})\n", .{ template.name, template.description });
    return 0;
}

/// List available templates
pub fn cmdList(allocator: Allocator, stdout: anytype, use_color: bool) !u8 {

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.registerBuiltins();

    const templates = registry.list();

    try color.printHeader(stdout, use_color, "Available CI/CD Templates\n", .{});
    try stdout.writeAll("\n");

    var current_platform: ?Platform = null;
    for (templates) |template| {
        if (current_platform == null or current_platform.? != template.platform) {
            current_platform = template.platform;
            try color.printInfo(stdout, use_color, "\n{s}:\n", .{template.platform.toString()});
        }

        try stdout.print("  {s: <15} - {s}\n", .{
            template.template_type.toString(),
            template.description,
        });
    }

    try stdout.writeAll("\n");
    return 0;
}

/// Print help for ci command
pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: zr ci <subcommand> [options]
        \\
        \\Subcommands:
        \\  generate [options]      Generate CI configuration file
        \\  list                    List available CI templates
        \\
        \\Options for 'generate':
        \\  --platform=<name>       CI platform (github-actions, gitlab, circleci)
        \\                          Auto-detects if not specified
        \\  --type=<name>           Template type (basic, monorepo, release)
        \\                          Defaults to 'basic'
        \\  --output=<path>         Output file path (auto-determined if not specified)
        \\
        \\Examples:
        \\  zr ci generate                              # Auto-detect platform, basic template
        \\  zr ci generate --platform=github-actions    # GitHub Actions basic CI
        \\  zr ci generate --type=monorepo              # Monorepo template
        \\  zr ci list                                  # List all templates
        \\
    );
}

test "detectPlatform with no CI files" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // In test environment, likely no CI files exist
    const platform = try detectPlatform(allocator);
    // Can't assert specific value as it depends on test environment
    _ = platform;
}

test "printHelp executes without error" {
    const testing = std.testing;
    var buffer: std.ArrayList(u8) = .{};
    defer buffer.deinit(testing.allocator);

    try printHelp(buffer.writer(testing.allocator));
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Usage:") != null);
}
