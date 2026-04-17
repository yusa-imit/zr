const std = @import("std");

const TaskMetadata = struct {
    tags: std.ArrayList([]const u8),
    env: std.StringHashMap([]const u8),
    parallel: bool,

    fn init(allocator: std.mem.Allocator) TaskMetadata {
        return .{
            .tags = std.ArrayList([]const u8){},
            .env = std.StringHashMap([]const u8).init(allocator),
            .parallel = false,
        };
    }

    fn deinit(self: *TaskMetadata, allocator: std.mem.Allocator) void {
        for (self.tags.items) |tag| allocator.free(tag);
        self.tags.deinit(allocator);
        var env_iter = self.env.iterator();
        while (env_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();
    }
};

/// Parse a justfile and extract recipe definitions
/// Handles common just patterns:
/// - recipe-name arg1 arg2: dependencies
///     command1
///     command2
/// Enhanced with semantic analysis:
/// - Tag inference from recipe names
/// - Environment variable extraction
/// - Parallel/sequential pattern detection
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
    var current_metadata = TaskMetadata.init(allocator);
    defer current_metadata.deinit(allocator);

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
                try writeTaskWithMetadata(allocator, &writer, recipe, current_deps.items, current_commands.items, &current_metadata);
                allocator.free(recipe);
                for (current_deps.items) |dep| allocator.free(dep);
                current_deps.clearRetainingCapacity();
                for (current_commands.items) |cmd| allocator.free(cmd);
                current_commands.clearRetainingCapacity();
                current_metadata.deinit(allocator);
                current_metadata = TaskMetadata.init(allocator);
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

            // Infer tags from recipe name
            try inferTags(allocator, recipe_name, &current_metadata.tags);

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
            // Analyze command for semantic patterns
            try analyzeCommand(allocator, trimmed, &current_metadata);
        }
    }

    // Write last recipe
    if (current_recipe) |recipe| {
        try writeTaskWithMetadata(allocator, &writer, recipe, current_deps.items, current_commands.items, &current_metadata);
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

fn writeTaskWithMetadata(
    allocator: std.mem.Allocator,
    writer: anytype,
    recipe: []const u8,
    deps: []const []const u8,
    commands: []const []const u8,
    metadata: *TaskMetadata,
) !void {
    try writer.print("[tasks.{s}]\n", .{recipe});

    // Write tags if any
    if (metadata.tags.items.len > 0) {
        try writer.writeAll("tags = [");
        for (metadata.tags.items, 0..) |tag, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{tag});
        }
        try writer.writeAll("]\n");
    }

    // Write environment variables if any
    if (metadata.env.count() > 0) {
        try writer.writeAll("[tasks.");
        try writer.writeAll(recipe);
        try writer.writeAll(".env]\n");
        var env_iter = metadata.env.iterator();
        while (env_iter.next()) |entry| {
            try writer.print("{s} = \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.writeAll("\n[tasks.");
        try writer.writeAll(recipe);
        try writer.writeAll("]\n");
    }

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
            // Multiple commands: check if parallel
            const joiner = if (metadata.parallel) " & " else " && ";
            var joined = std.ArrayList(u8){};
            defer joined.deinit(allocator);
            const j_writer = joined.writer(allocator);
            for (commands, 0..) |cmd, idx| {
                if (idx > 0) try j_writer.writeAll(joiner);
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

/// Infer task tags from recipe name patterns
fn inferTags(allocator: std.mem.Allocator, recipe_name: []const u8, tags: *std.ArrayList([]const u8)) !void {
    const lower_name = try std.ascii.allocLowerString(allocator, recipe_name);
    defer allocator.free(lower_name);

    const tag_patterns = [_]struct { pattern: []const u8, tag: []const u8 }{
        .{ .pattern = "test", .tag = "test" },
        .{ .pattern = "check", .tag = "test" },
        .{ .pattern = "build", .tag = "build" },
        .{ .pattern = "compile", .tag = "build" },
        .{ .pattern = "deploy", .tag = "deploy" },
        .{ .pattern = "publish", .tag = "deploy" },
        .{ .pattern = "release", .tag = "deploy" },
        .{ .pattern = "clean", .tag = "cleanup" },
        .{ .pattern = "install", .tag = "setup" },
        .{ .pattern = "setup", .tag = "setup" },
        .{ .pattern = "dev", .tag = "dev" },
        .{ .pattern = "watch", .tag = "dev" },
        .{ .pattern = "serve", .tag = "dev" },
        .{ .pattern = "start", .tag = "dev" },
        .{ .pattern = "lint", .tag = "lint" },
        .{ .pattern = "format", .tag = "lint" },
        .{ .pattern = "fmt", .tag = "lint" },
        .{ .pattern = "ci", .tag = "ci" },
        .{ .pattern = "docker", .tag = "docker" },
        .{ .pattern = "container", .tag = "docker" },
    };

    var added_tags = std.StringHashMap(void).init(allocator);
    defer added_tags.deinit();

    for (tag_patterns) |pattern_entry| {
        if (std.mem.indexOf(u8, lower_name, pattern_entry.pattern) != null) {
            if (!added_tags.contains(pattern_entry.tag)) {
                try tags.append(allocator, try allocator.dupe(u8, pattern_entry.tag));
                try added_tags.put(pattern_entry.tag, {});
            }
        }
    }
}

/// Analyze command for semantic patterns
fn analyzeCommand(allocator: std.mem.Allocator, cmd: []const u8, metadata: *TaskMetadata) !void {
    // Detect parallel execution patterns (commands ending with &)
    if (std.mem.endsWith(u8, std.mem.trim(u8, cmd, " \t"), "&")) {
        metadata.parallel = true;
    }

    // Extract environment variable assignments (VAR=value)
    var i: usize = 0;
    while (i < cmd.len) : (i += 1) {
        if (cmd[i] == '=' and i > 0) {
            // Find start of variable name
            var start = i;
            while (start > 0 and (std.ascii.isAlphanumeric(cmd[start - 1]) or cmd[start - 1] == '_')) {
                start -= 1;
            }
            // Check if this looks like an env var (all caps or starts with uppercase)
            const var_name = cmd[start..i];
            if (var_name.len > 0 and std.ascii.isUpper(var_name[0])) {
                // Find end of value (space or &&)
                var end = i + 1;
                var in_quote = false;
                while (end < cmd.len) : (end += 1) {
                    if (cmd[end] == '"' or cmd[end] == '\'') {
                        in_quote = !in_quote;
                    } else if (!in_quote and (cmd[end] == ' ' or cmd[end] == '\t')) {
                        break;
                    } else if (!in_quote and end + 1 < cmd.len and cmd[end] == '&' and cmd[end + 1] == '&') {
                        break;
                    }
                }
                const var_value = std.mem.trim(u8, cmd[i + 1 .. end], " \t\"'");
                if (var_value.len > 0) {
                    const key = try allocator.dupe(u8, var_name);
                    const value = try allocator.dupe(u8, var_value);
                    try metadata.env.put(key, value);
                }
            }
        }
    }
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
