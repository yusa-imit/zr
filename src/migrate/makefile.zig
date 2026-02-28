const std = @import("std");

/// Parse a Makefile and extract task definitions
/// Simple parser that handles common patterns:
/// - target: dependencies
///   command
/// - .PHONY: targets
pub fn parseToZrToml(allocator: std.mem.Allocator, makefile_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(makefile_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // Max 10MB
    defer allocator.free(content);

    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);

    try writer.writeAll(
        \\# zr.toml — migrated from Makefile by `zr init --from-make`
        \\# Docs: https://github.com/yusa-imit/zr
        \\
        \\[global]
        \\shell = "bash"
        \\
        \\
    );

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_target: ?[]const u8 = null;
    var current_deps = std.ArrayList([]const u8){};
    defer current_deps.deinit(allocator);
    var current_commands = std.ArrayList([]const u8){};
    defer current_commands.deinit(allocator);
    var phony_targets = std.StringHashMap(void).init(allocator);
    defer phony_targets.deinit();

    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, " \t\r\n");

        // Skip empty lines and comments
        if (line.len == 0) continue;
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (trimmed.len > 0 and trimmed[0] == '#') continue;

        // Parse .PHONY declarations
        if (std.mem.startsWith(u8, trimmed, ".PHONY:")) {
            const targets_str = std.mem.trim(u8, trimmed[7..], " \t");
            var target_iter = std.mem.splitScalar(u8, targets_str, ' ');
            while (target_iter.next()) |target| {
                const target_trimmed = std.mem.trim(u8, target, " \t");
                if (target_trimmed.len > 0) {
                    try phony_targets.put(try allocator.dupe(u8, target_trimmed), {});
                }
            }
            continue;
        }

        // Detect target: dependencies pattern (target lines don't start with whitespace)
        if (std.mem.indexOf(u8, line, ":") != null and line[0] != '\t' and line[0] != ' ') {
            // Save previous target if exists
            if (current_target) |target| {
                try writeTask(allocator, &writer, target, current_deps.items, current_commands.items);
                allocator.free(target);
                for (current_deps.items) |dep| allocator.free(dep);
                current_deps.clearRetainingCapacity();
                for (current_commands.items) |cmd| allocator.free(cmd);
                current_commands.clearRetainingCapacity();
            }

            // Parse new target
            const colon_idx = std.mem.indexOf(u8, line, ":").?;
            const target_name = std.mem.trim(u8, line[0..colon_idx], " \t");
            const deps_str = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");

            // Skip special targets (starting with .)
            if (target_name.len > 0 and target_name[0] == '.') continue;

            current_target = try allocator.dupe(u8, target_name);

            // Parse dependencies
            if (deps_str.len > 0) {
                var dep_iter = std.mem.splitScalar(u8, deps_str, ' ');
                while (dep_iter.next()) |dep| {
                    const dep_trimmed = std.mem.trim(u8, dep, " \t");
                    if (dep_trimmed.len > 0) {
                        try current_deps.append(allocator, try allocator.dupe(u8, dep_trimmed));
                    }
                }
            }
        } else if ((line[0] == '\t' or line[0] == ' ') and current_target != null) {
            // Command for current target (indented lines)
            const cmd = std.mem.trim(u8, line, " \t");
            if (cmd.len > 0) {
                try current_commands.append(allocator, try allocator.dupe(u8, cmd));
            }
        }
    }

    // Write last target
    if (current_target) |target| {
        try writeTask(allocator, &writer, target, current_deps.items, current_commands.items);
        allocator.free(target);
        for (current_deps.items) |dep| allocator.free(dep);
        for (current_commands.items) |cmd| allocator.free(cmd);
    }

    // Clean up phony_targets
    var key_iter = phony_targets.keyIterator();
    while (key_iter.next()) |key| {
        allocator.free(key.*);
    }

    return try buf.toOwnedSlice(allocator);
}

fn writeTask(
    allocator: std.mem.Allocator,
    writer: anytype,
    target: []const u8,
    deps: []const []const u8,
    commands: []const []const u8,
) !void {
    try writer.print("[tasks.{s}]\n", .{target});

    if (deps.len > 0) {
        try writer.writeAll("deps = [");
        for (deps, 0..) |dep, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{dep});
        }
        try writer.writeAll("]\n");
    }

    if (commands.len > 0) {
        if (commands.len == 1) {
            // Single command: use string format
            const escaped = try escapeString(allocator, commands[0]);
            defer allocator.free(escaped);
            try writer.print("cmd = \"{s}\"\n", .{escaped});
        } else {
            // Multiple commands: join with &&
            var joined = std.ArrayList(u8){};
            defer joined.deinit(allocator);
            const j_writer = joined.writer(allocator);
            for (commands, 0..) |cmd, idx| {
                if (idx > 0) try j_writer.writeAll(" && ");
                try j_writer.writeAll(cmd);
            }
            const escaped = try escapeString(allocator, joined.items);
            defer allocator.free(escaped);
            try writer.print("cmd = \"{s}\"\n", .{escaped});
        }
    } else {
        try writer.writeAll("cmd = \"true\"\n");
    }

    try writer.writeAll("\n");
}

fn escapeString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);
    for (s) |c| {
        if (c == '"') {
            try writer.writeAll("\\\"");
        } else if (c == '\\') {
            try writer.writeAll("\\\\");
        } else {
            try writer.writeByte(c);
        }
    }
    return try buf.toOwnedSlice(allocator);
}

test "parseToZrToml handles simple Makefile" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create test Makefile (tabs required in Makefile format)
    const makefile_content = ".PHONY: build test clean\n\n" ++
        "build: deps\n\tgo build -o app .\n\n" ++
        "test: build\n\tgo test ./...\n\n" ++
        "clean:\n\trm -rf app dist/\n";

    try tmp.dir.writeFile(.{
        .sub_path = "Makefile",
        .data = makefile_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const makefile_path = try tmp.dir.realpath("Makefile", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, makefile_path);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.clean]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "deps = [\"deps\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "go build") != null);
}
