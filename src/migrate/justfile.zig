const std = @import("std");

/// Parse a justfile and extract recipe definitions
/// Handles common just patterns:
/// - recipe-name arg1 arg2: dependencies
///     command1
///     command2
pub fn parseToZrToml(allocator: std.mem.Allocator, justfile_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(justfile_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // Max 10MB
    defer allocator.free(content);

    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);

    try writer.writeAll(
        \\# zr.toml — migrated from justfile by `zr init --from-just`
        \\# Docs: https://github.com/yusa-imit/zr
        \\
        \\[global]
        \\shell = "bash"
        \\
        \\
    );

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_recipe: ?[]const u8 = null;
    var current_deps = std.ArrayList([]const u8){};
    defer current_deps.deinit(allocator);
    var current_commands = std.ArrayList([]const u8){};
    defer current_commands.deinit(allocator);

    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, " \t\r\n");

        // Skip empty lines and comments
        if (line.len == 0) continue;
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (trimmed.len > 0 and trimmed[0] == '#') continue;

        // Detect recipe: dependencies pattern (recipe names don't start with whitespace)
        if (std.mem.indexOf(u8, line, ":") != null and line[0] != ' ' and line[0] != '\t') {
            // Save previous recipe if exists
            if (current_recipe) |recipe| {
                try writeTask(allocator, &writer, recipe, current_deps.items, current_commands.items);
                allocator.free(recipe);
                for (current_deps.items) |dep| allocator.free(dep);
                current_deps.clearRetainingCapacity();
                for (current_commands.items) |cmd| allocator.free(cmd);
                current_commands.clearRetainingCapacity();
            }

            // Parse new recipe
            const colon_idx = std.mem.indexOf(u8, line, ":").?;
            const recipe_part = std.mem.trim(u8, line[0..colon_idx], " \t");
            const deps_str = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");

            // Recipe name might have parameters (e.g., "build arg1 arg2")
            // For simplicity, take just the first word
            var recipe_iter = std.mem.splitScalar(u8, recipe_part, ' ');
            const recipe_name = recipe_iter.next() orelse continue;

            current_recipe = try allocator.dupe(u8, recipe_name);

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
        } else if ((line[0] == ' ' or line[0] == '\t') and current_recipe != null and trimmed.len > 0) {
            // Command for current recipe (indented lines)
            try current_commands.append(allocator, try allocator.dupe(u8, trimmed));
        }
    }

    // Write last recipe
    if (current_recipe) |recipe| {
        try writeTask(allocator, &writer, recipe, current_deps.items, current_commands.items);
        allocator.free(recipe);
        for (current_deps.items) |dep| allocator.free(dep);
        for (current_commands.items) |cmd| allocator.free(cmd);
    }

    return try buf.toOwnedSlice(allocator);
}

fn writeTask(
    allocator: std.mem.Allocator,
    writer: anytype,
    recipe: []const u8,
    deps: []const []const u8,
    commands: []const []const u8,
) !void {
    try writer.print("[tasks.{s}]\n", .{recipe});

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

test "parseToZrToml handles simple justfile" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const justfile_content =
        \\# Simple justfile
        \\
        \\build: deps
        \\    cargo build --release
        \\
        \\test: build
        \\    cargo test
        \\    cargo clippy
        \\
        \\clean:
        \\    rm -rf target/
        \\
    ;

    try tmp.dir.writeFile(.{
        .sub_path = "justfile",
        .data = justfile_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const justfile_path = try tmp.dir.realpath("justfile", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, justfile_path);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.clean]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "deps = [\"deps\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "cargo build") != null);
}
