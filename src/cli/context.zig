const std = @import("std");
const generator = @import("../context/generator.zig");
const json_gen = @import("../context/json.zig");
const yaml_gen = @import("../context/yaml.zig");

pub fn cmdContext(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var format: enum { json, yaml } = .json;
    var scope: ?[]const u8 = null;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: --format requires a value (json or yaml)\n", .{});
                return 1;
            }
            const format_str = args[i];
            if (std.mem.eql(u8, format_str, "json")) {
                format = .json;
            } else if (std.mem.eql(u8, format_str, "yaml")) {
                format = .yaml;
            } else {
                std.debug.print("error: unknown format '{s}' (use json or yaml)\n", .{format_str});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--scope")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: --scope requires a path\n", .{});
                return 1;
            }
            scope = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return 0;
        } else {
            std.debug.print("error: unknown flag: {s}\n", .{arg});
            try printHelp();
            return 1;
        }
    }

    // Generate context
    var ctx = generator.generateContext(allocator, scope) catch |err| {
        std.debug.print("error: failed to generate context: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer ctx.deinit();

    // Generate output
    const output = switch (format) {
        .json => json_gen.generateJsonOutput(allocator, &ctx) catch |err| {
            std.debug.print("error: failed to generate JSON output: {s}\n", .{@errorName(err)});
            return 1;
        },
        .yaml => yaml_gen.generateYamlOutput(allocator, &ctx) catch |err| {
            std.debug.print("error: failed to generate YAML output: {s}\n", .{@errorName(err)});
            return 1;
        },
    };
    defer allocator.free(output);

    // Print to stdout
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(output);

    return 0;
}

fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\zr context - Generate AI-friendly project metadata
        \\
        \\Usage:
        \\  zr context [options]
        \\
        \\Options:
        \\  --format <fmt>    Output format: json (default) or yaml
        \\  --scope <path>    Filter to specific package/directory scope
        \\  -h, --help        Show this help message
        \\
        \\Description:
        \\  Generates structured metadata about the project for AI coding agents.
        \\  Output includes:
        \\    - Project dependency graph (packages and their dependencies)
        \\    - Task catalog (all available tasks per package)
        \\    - File ownership mapping (from CODEOWNERS)
        \\    - Recent changes summary (git commit history)
        \\    - Toolchain information (configured tools and versions)
        \\
        \\Examples:
        \\  zr context                       # Output as JSON
        \\  zr context --format=yaml         # Output as YAML
        \\  zr context --scope=packages/api  # Only show packages/api scope
        \\
        \\
    );
}

test "cmdContext help" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"--help"};
    const result = try cmdContext(allocator, &args);
    try std.testing.expectEqual(@as(u8, 0), result);
}
