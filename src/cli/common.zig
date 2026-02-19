const std = @import("std");
const loader = @import("../config/loader.zig");
const dag_mod = @import("../graph/dag.zig");
const color = @import("../output/color.zig");

pub const CONFIG_FILE = "zr.toml";

/// Load config from file, applying profile overrides if requested.
/// Returns null and prints an error message if loading fails.
pub fn loadConfig(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    profile_name_opt: ?[]const u8,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !?loader.Config {
    var config = loader.loadFromFile(allocator, config_path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try color.printError(err_writer, use_color,
                    "Config: {s} not found\n\n  Hint: Create a zr.toml file in the current directory\n",
                    .{config_path},
                );
            },
            else => {
                try color.printError(err_writer, use_color,
                    "Config: Failed to load {s}: {s}\n",
                    .{ config_path, @errorName(err) },
                );
            },
        }
        return null;
    };

    // Resolve effective profile: --profile flag, then ZR_PROFILE env var.
    var effective_profile: ?[]const u8 = profile_name_opt;
    var env_profile_buf: [256]u8 = undefined;
    if (effective_profile == null) {
        if (std.process.getEnvVarOwned(allocator, "ZR_PROFILE")) |pname| {
            defer allocator.free(pname);
            if (pname.len > 0 and pname.len <= env_profile_buf.len) {
                @memcpy(env_profile_buf[0..pname.len], pname);
                effective_profile = env_profile_buf[0..pname.len];
            }
        } else |_| {}
    }

    if (effective_profile) |pname| {
        config.applyProfile(pname) catch |err| switch (err) {
            error.ProfileNotFound => {
                try color.printError(err_writer, use_color,
                    "profile: '{s}' not found in {s}\n\n  Hint: Add [profiles.{s}] to your zr.toml\n",
                    .{ pname, config_path, pname },
                );
                config.deinit();
                return null;
            },
            else => {
                try color.printError(err_writer, use_color,
                    "profile: Failed to apply '{s}': {s}\n", .{ pname, @errorName(err) });
                config.deinit();
                return null;
            },
        };
    }

    return config;
}

/// Construct a DAG from all tasks in the config.
pub fn buildDag(allocator: std.mem.Allocator, config: *const loader.Config) !dag_mod.DAG {
    var dag = dag_mod.DAG.init(allocator);
    errdefer dag.deinit();

    var it = config.tasks.iterator();
    while (it.next()) |entry| {
        const task = entry.value_ptr;
        try dag.addNode(task.name);
        for (task.deps) |dep| {
            try dag.addEdge(task.name, dep);
        }
    }

    return dag;
}

/// Write a JSON-encoded string (with surrounding quotes and escape sequences).
pub fn writeJsonString(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => try w.print("\\u{x:0>4}", .{c}),
            else => try w.writeByte(c),
        }
    }
    try w.writeAll("\"");
}

test "writeJsonString escapes special characters" {
    var buf: [256]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var w = stdout.writer(&buf);

    try writeJsonString(&w.interface, "hello world");
    try writeJsonString(&w.interface, "with \"quotes\"");
    try writeJsonString(&w.interface, "with\nnewline");
    try writeJsonString(&w.interface, "with\\backslash");
}
