const std = @import("std");
const generator = @import("../context/generator.zig");
const json_gen = @import("../context/json.zig");
const yaml_gen = @import("../context/yaml.zig");

pub fn cmdContext(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    var format: enum { json, yaml } = .json;
    var scope: ?[]const u8 = null;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("✗ --format requires a value (json or yaml)\n", .{});
                return 1;
            }
            const format_str = args[i];
            if (std.mem.eql(u8, format_str, "json")) {
                format = .json;
            } else if (std.mem.eql(u8, format_str, "yaml")) {
                format = .yaml;
            } else {
                try ew.print("✗ [Context]: unknown format '{s}'\n\n  Hint: Use json or yaml\n", .{format_str});
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const format_str = arg["--format=".len..];
            if (std.mem.eql(u8, format_str, "json")) {
                format = .json;
            } else if (std.mem.eql(u8, format_str, "yaml")) {
                format = .yaml;
            } else {
                try ew.print("✗ [Context]: unknown format '{s}'\n\n  Hint: Use json or yaml\n", .{format_str});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--scope")) {
            i += 1;
            if (i >= args.len) {
                try ew.print("✗ [Context]: --scope requires a path\n", .{});
                return 1;
            }
            scope = args[i];
        } else if (std.mem.startsWith(u8, arg, "--scope=")) {
            scope = arg["--scope=".len..];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(ew);
            return 0;
        } else {
            try ew.print("✗ [Context]: unknown flag: {s}\n", .{arg});
            try printHelp(ew);
            return 1;
        }
    }

    // Generate context
    var ctx = generator.generateContext(allocator, scope) catch |err| {
        try ew.print("✗ [Context]: failed to generate context: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer ctx.deinit();

    // Generate output
    const output = switch (format) {
        .json => json_gen.generateJsonOutput(allocator, &ctx) catch |err| {
            try ew.print("✗ [Context]: failed to generate JSON output: {s}\n", .{@errorName(err)});
            return 1;
        },
        .yaml => yaml_gen.generateYamlOutput(allocator, &ctx) catch |err| {
            try ew.print("✗ [Context]: failed to generate YAML output: {s}\n", .{@errorName(err)});
            return 1;
        },
    };
    defer allocator.free(output);

    // Print to writer
    try w.print("{s}", .{output});

    return 0;
}

fn printHelp(ew: *std.Io.Writer) !void {
    try ew.print(
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
    , .{});
}

test "cmdContext help" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    const args = [_][]const u8{"--help"};
    const result = try cmdContext(allocator, &args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "cmdContext writes help to writer when --help provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = &[_][]const u8{"--help"};

    // This should FAIL until cmdContext is refactored to accept writers
    const code = try cmdContext(allocator, args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "cmdContext writes error to ew when unknown flag provided" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const args = &[_][]const u8{"--unknown-flag"};

    // This should FAIL until cmdContext is refactored to accept writers
    const code = try cmdContext(allocator, args, &out_w.interface, &err_w.interface);
    try std.testing.expectEqual(@as(u8, 1), code);
}
