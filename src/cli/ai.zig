const std = @import("std");
const color = @import("../output/color.zig");

/// Natural language interface for zr commands
/// Translates simple human language to zr CLI commands
pub fn cmdAi(
    allocator: std.mem.Allocator,
    input: []const u8,
    w: *std.io.Writer,
    ew: *std.io.Writer,
    use_color: bool,
) !u8 {
    const normalized = try normalizeInput(allocator, input);
    defer allocator.free(normalized);

    const command = try matchPattern(allocator, normalized) orelse {
        try color.printError(ew, use_color, "Could not understand: {s}\n\n", .{input});
        try ew.writeAll("  Hint: Try one of these patterns:\n");
        try ew.writeAll("    - \"build and test\"\n");
        try ew.writeAll("    - \"deploy frontend\"\n");
        try ew.writeAll("    - \"show failed tasks from yesterday\"\n");
        try ew.writeAll("    - \"run all tests\"\n");
        return 1;
    };
    defer allocator.free(command);

    try color.printDim(w, use_color, "→ {s}\n", .{command});

    // In a real implementation, we would execute the command here
    // For now, just print what would be executed
    try w.writeAll("\n");
    try color.printSuccess(w, use_color, "✓ Command translated\n", .{});
    try color.printDim(w, use_color, "  (Execution not yet implemented)\n", .{});

    return 0;
}

/// Normalize input: lowercase, trim, collapse whitespace
fn normalizeInput(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var in_space = true;
    for (input) |c| {
        const lower = std.ascii.toLower(c);
        if (lower == ' ' or lower == '\t' or lower == '\n' or lower == '\r') {
            if (!in_space) {
                try result.append(allocator, ' ');
                in_space = true;
            }
        } else {
            try result.append(allocator, lower);
            in_space = false;
        }
    }

    // Trim trailing space
    if (result.items.len > 0 and result.items[result.items.len - 1] == ' ') {
        _ = result.pop();
    }

    return result.toOwnedSlice(allocator);
}

/// Pattern matching engine
fn matchPattern(allocator: std.mem.Allocator, input: []const u8) !?[]const u8 {
    // Pattern: "watch" or "live" - check FIRST before "build"/"test" to prioritize watch commands
    if (containsAny(input, &[_][]const u8{ "watch", "live", "auto", "automatically" })) {
        if (containsAny(input, &[_][]const u8{ "test" })) {
            return try allocator.dupe(u8, "zr watch test");
        }
        if (containsAny(input, &[_][]const u8{ "build" })) {
            return try allocator.dupe(u8, "zr watch build");
        }
    }

    // Pattern: "build" or "compile"
    if (containsAny(input, &[_][]const u8{ "build", "compile", "make" })) {
        if (containsAny(input, &[_][]const u8{ "test", "check" })) {
            return try allocator.dupe(u8, "zr run build && zr run test");
        }
        return try allocator.dupe(u8, "zr run build");
    }

    // Pattern: "test"
    if (containsAny(input, &[_][]const u8{ "test", "testing" })) {
        if (containsAny(input, &[_][]const u8{ "unit" })) {
            return try allocator.dupe(u8, "zr run test-unit");
        }
        if (containsAny(input, &[_][]const u8{ "integration", "integ" })) {
            return try allocator.dupe(u8, "zr run test-integration");
        }
        if (containsAny(input, &[_][]const u8{ "e2e", "end to end", "end-to-end" })) {
            return try allocator.dupe(u8, "zr run test-e2e");
        }
        if (containsAny(input, &[_][]const u8{ "all" })) {
            return try allocator.dupe(u8, "zr run test");
        }
        return try allocator.dupe(u8, "zr run test");
    }

    // Pattern: "deploy"
    if (containsAny(input, &[_][]const u8{ "deploy", "deployment", "release" })) {
        if (containsAny(input, &[_][]const u8{ "frontend", "front-end", "client", "ui" })) {
            return try allocator.dupe(u8, "zr run deploy-frontend");
        }
        if (containsAny(input, &[_][]const u8{ "backend", "back-end", "server", "api" })) {
            return try allocator.dupe(u8, "zr run deploy-backend");
        }
        if (containsAny(input, &[_][]const u8{ "prod", "production" })) {
            return try allocator.dupe(u8, "zr run deploy-prod");
        }
        return try allocator.dupe(u8, "zr run deploy");
    }

    // Pattern: "run"
    if (containsAny(input, &[_][]const u8{ "run", "start", "execute", "launch" })) {
        if (containsAny(input, &[_][]const u8{ "dev", "development", "locally" })) {
            return try allocator.dupe(u8, "zr run dev");
        }
        if (containsAny(input, &[_][]const u8{ "server" })) {
            return try allocator.dupe(u8, "zr run server");
        }
    }

    // Pattern: "clean" or "clear"
    if (containsAny(input, &[_][]const u8{ "clean", "clear", "remove cache", "delete cache" })) {
        return try allocator.dupe(u8, "zr clean");
    }

    // Pattern: "history" - check this before general "list" to prioritize history-related queries
    if (containsAny(input, &[_][]const u8{ "history", "past", "previous", "recent" }) or
        containsAny(input, &[_][]const u8{ "failed", "yesterday" }))
    {
        // Check for time-based filters first (more specific than status filters)
        if (containsAny(input, &[_][]const u8{ "yesterday", "1d", "24h" })) {
            return try allocator.dupe(u8, "zr history --since=1d");
        }
        if (containsAny(input, &[_][]const u8{ "fail", "failed", "error" })) {
            return try allocator.dupe(u8, "zr history --status=failed");
        }
        return try allocator.dupe(u8, "zr history");
    }

    // Pattern: "list" or "show"
    if (containsAny(input, &[_][]const u8{ "list", "show", "display" })) {
        if (containsAny(input, &[_][]const u8{ "task", "tasks" })) {
            if (containsAny(input, &[_][]const u8{ "tree", "dependency", "dependencies", "graph" })) {
                return try allocator.dupe(u8, "zr list --tree");
            }
            return try allocator.dupe(u8, "zr list");
        }
        if (containsAny(input, &[_][]const u8{ "graph" })) {
            return try allocator.dupe(u8, "zr graph");
        }
    }

    // Pattern: "validate" or "check config"
    if (containsAny(input, &[_][]const u8{ "validate", "check", "verify" })) {
        if (containsAny(input, &[_][]const u8{ "config", "configuration", "toml", "zr.toml" })) {
            return try allocator.dupe(u8, "zr validate");
        }
    }

    // Pattern: "install" or "setup"
    if (containsAny(input, &[_][]const u8{ "install", "setup", "add" })) {
        if (containsAny(input, &[_][]const u8{ "tool", "tools", "toolchain" })) {
            return try allocator.dupe(u8, "zr tools install");
        }
        if (containsAny(input, &[_][]const u8{ "plugin", "plugins" })) {
            return try allocator.dupe(u8, "zr plugin install");
        }
    }

    // No pattern matched
    return null;
}

/// Check if input contains any of the given keywords
fn containsAny(input: []const u8, keywords: []const []const u8) bool {
    for (keywords) |keyword| {
        if (std.mem.indexOf(u8, input, keyword) != null) {
            return true;
        }
    }
    return false;
}

// ─── Tests ───

test "normalizeInput" {
    const allocator = std.testing.allocator;

    {
        const result = try normalizeInput(allocator, "  Build   and   Test  ");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("build and test", result);
    }

    {
        const result = try normalizeInput(allocator, "Deploy\tFrontend\n");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("deploy frontend", result);
    }

    {
        const result = try normalizeInput(allocator, "RUN");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("run", result);
    }
}

test "matchPattern - build" {
    const allocator = std.testing.allocator;

    {
        const result = try matchPattern(allocator, "build");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr run build", result.?);
    }

    {
        const result = try matchPattern(allocator, "build and test");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr run build && zr run test", result.?);
    }
}

test "matchPattern - test" {
    const allocator = std.testing.allocator;

    {
        const result = try matchPattern(allocator, "run tests");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr run test", result.?);
    }

    {
        const result = try matchPattern(allocator, "run unit tests");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr run test-unit", result.?);
    }

    {
        const result = try matchPattern(allocator, "run integration tests");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr run test-integration", result.?);
    }
}

test "matchPattern - deploy" {
    const allocator = std.testing.allocator;

    {
        const result = try matchPattern(allocator, "deploy frontend");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr run deploy-frontend", result.?);
    }

    {
        const result = try matchPattern(allocator, "deploy to production");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr run deploy-prod", result.?);
    }
}

test "matchPattern - list and history" {
    const allocator = std.testing.allocator;

    {
        const result = try matchPattern(allocator, "list tasks");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr list", result.?);
    }

    {
        const result = try matchPattern(allocator, "show task tree");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr list --tree", result.?);
    }

    {
        const result = try matchPattern(allocator, "show failed tasks from yesterday");
        try std.testing.expect(result != null);
        defer allocator.free(result.?);
        try std.testing.expectEqualStrings("zr history --since=1d", result.?);
    }
}

test "matchPattern - no match" {
    const allocator = std.testing.allocator;

    const result = try matchPattern(allocator, "xyzabc unknown command");
    try std.testing.expect(result == null);
}

test "containsAny" {
    try std.testing.expect(containsAny("build the project", &[_][]const u8{ "build", "compile" }));
    try std.testing.expect(containsAny("compile now", &[_][]const u8{ "build", "compile" }));
    try std.testing.expect(!containsAny("test only", &[_][]const u8{ "build", "compile" }));
}
