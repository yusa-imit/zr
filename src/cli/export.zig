const std = @import("std");
const color = @import("../output/color.zig");
const platform = @import("../util/platform.zig");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");
const toolchain_path = @import("../toolchain/path.zig");
const toolchain_types = @import("../toolchain/types.zig");

/// Export environment variables in shell-sourceable format
pub fn cmdExport(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    // Parse arguments
    var task_name: ?[]const u8 = null;
    var shell_format: ShellFormat = .bash;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--task")) {
            if (i + 1 < args.len) {
                task_name = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "export: --task requires a task name\n\n  Hint: zr export --task TASK_NAME\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--shell")) {
            if (i + 1 < args.len) {
                const shell_str = args[i + 1];
                if (std.mem.eql(u8, shell_str, "bash")) {
                    shell_format = .bash;
                } else if (std.mem.eql(u8, shell_str, "zsh")) {
                    shell_format = .zsh;
                } else if (std.mem.eql(u8, shell_str, "fish")) {
                    shell_format = .fish;
                } else if (std.mem.eql(u8, shell_str, "powershell")) {
                    shell_format = .powershell;
                } else {
                    try color.printError(ew, use_color, "export: unknown shell '{s}'\n\n  Hint: supported shells: bash, zsh, fish, powershell\n", .{shell_str});
                    return 1;
                }
                i += 1;
            } else {
                try color.printError(ew, use_color, "export: --shell requires a shell name\n\n  Hint: zr export --shell bash\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "export: unknown argument '{s}'\n\n  Hint: zr export --help\n", .{arg});
            return 1;
        }
    }

    // Get system environment
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // If task specified, load config and merge task env
    if (task_name) |task| {
        var cfg = loader.loadFromFile(allocator, config_path) catch |err| {
            try color.printError(ew, use_color, "export: failed to load config: {}\n", .{err});
            return 1;
        };
        defer cfg.deinit();

        // Find task
        const task_def = cfg.tasks.get(task) orelse {
            try color.printError(ew, use_color, "export: task '{s}' not found\n", .{task});
            return 1;
        };

        // Merge task env (env is [][2][]const u8)
        for (task_def.env) |kv| {
            try env_map.put(kv[0], kv[1]);
        }

        // TODO: Add toolchain PATH if task has toolchain requirements
        // For now, just export task env - toolchain PATH injection can be added later
        _ = task_def.toolchain; // Acknowledge unused field
    }

    // Export in shell format
    try exportShellFormat(allocator, &env_map, shell_format, w);
    return 0;
}

const ShellFormat = enum {
    bash,
    zsh,
    fish,
    powershell,
};

fn exportShellFormat(
    allocator: std.mem.Allocator,
    env_map: *std.process.EnvMap,
    format: ShellFormat,
    w: anytype,
) !void {
    // Collect and sort keys
    var keys = std.ArrayList([]const u8){};
    defer keys.deinit(allocator);

    var it = env_map.iterator();
    while (it.next()) |entry| {
        try keys.append(allocator, entry.key_ptr.*);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Print in shell format
    for (keys.items) |key| {
        const value = env_map.get(key).?;
        switch (format) {
            .bash, .zsh => {
                // bash/zsh: export KEY="value"
                try w.print("export {s}=\"", .{key});
                try writeEscaped(value, w, .bash);
                try w.writeAll("\"\n");
            },
            .fish => {
                // fish: set -gx KEY "value"
                try w.print("set -gx {s} \"", .{key});
                try writeEscaped(value, w, .fish);
                try w.writeAll("\"\n");
            },
            .powershell => {
                // PowerShell: $env:KEY = "value"
                try w.print("$env:{s} = \"", .{key});
                try writeEscaped(value, w, .powershell);
                try w.writeAll("\"\n");
            },
        }
    }
}

fn writeEscaped(value: []const u8, w: anytype, format: ShellFormat) !void {
    for (value) |c| {
        switch (format) {
            .bash, .zsh => {
                // Escape $ " \ and backticks
                if (c == '$' or c == '"' or c == '\\' or c == '`') {
                    try w.writeByte('\\');
                }
                try w.writeByte(c);
            },
            .fish => {
                // Escape " \ and $
                if (c == '"' or c == '\\' or c == '$') {
                    try w.writeByte('\\');
                }
                try w.writeByte(c);
            },
            .powershell => {
                // Escape " and `
                if (c == '"') {
                    try w.writeByte('`');
                } else if (c == '`') {
                    try w.writeByte('`');
                }
                try w.writeByte(c);
            },
        }
    }
}

fn printHelp(w: anytype, use_color: bool) !void {
    try color.printBold(w, use_color, "Usage: ", .{});
    try w.writeAll("zr export [OPTIONS]\n\n");

    try color.printBold(w, use_color, "Description:\n", .{});
    try w.writeAll("  Export environment variables in shell-sourceable format.\n");
    try w.writeAll("  Useful for debugging or replicating zr's execution environment.\n\n");

    try color.printBold(w, use_color, "Options:\n", .{});
    try w.writeAll("  --task <name>        Export environment for specific task (includes task env vars)\n");
    try w.writeAll("  --shell <type>       Output format: bash, zsh, fish, powershell (default: bash)\n");
    try w.writeAll("  -h, --help           Show this help message\n\n");

    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.writeAll("  # Export current environment for bash\n");
    try w.writeAll("  zr export > env.sh\n");
    try w.writeAll("  source env.sh\n\n");
    try w.writeAll("  # Export environment for specific task\n");
    try w.writeAll("  zr export --task build --shell bash\n\n");
    try w.writeAll("  # Export for fish shell\n");
    try w.writeAll("  zr export --task test --shell fish > env.fish\n");
    try w.writeAll("  source env.fish\n\n");
    try w.writeAll("  # Export for PowerShell\n");
    try w.writeAll("  zr export --shell powershell > env.ps1\n");
    try w.writeAll("  . .\\env.ps1\n");
}

test "cmdExport: help output" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const result = try cmdExport(
        allocator,
        &[_][]const u8{"--help"},
        "zr.toml",
        &out_w.interface,
        &err_w.interface,
        false,
    );
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "cmdExport: bash format escaping" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const test_value = "hello $USER \"world\" `cmd`";
    try writeEscaped(test_value, buf.writer(allocator), .bash);

    const expected = "hello \\$USER \\\"world\\\" \\`cmd\\`";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "cmdExport: fish format escaping" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const test_value = "value with \"quotes\" and $var";
    try writeEscaped(test_value, buf.writer(allocator), .fish);

    const expected = "value with \\\"quotes\\\" and \\$var";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "cmdExport: powershell format escaping" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const test_value = "value with \"quotes\" and `backticks`";
    try writeEscaped(test_value, buf.writer(allocator), .powershell);

    const expected = "value with `\"quotes`\" and ``backticks``";
    try std.testing.expectEqualStrings(expected, buf.items);
}
