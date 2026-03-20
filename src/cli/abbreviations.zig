const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Parse abbreviations from ~/.zrconfig TOML file.
/// Returns a map of abbreviation -> expanded command.
pub fn parseAbbreviationConfig(allocator: Allocator, config_path: []const u8) !std.StringHashMap([]const u8) {
    var abbrevs = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = abbrevs.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        abbrevs.deinit();
    }

    const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) return error.FileNotFound;
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    // Simple TOML parser for [alias] section
    var in_alias_section = false;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for section headers
        if (std.mem.startsWith(u8, trimmed, "[")) {
            if (!std.mem.endsWith(u8, trimmed, "]")) {
                return error.InvalidToml; // Unclosed section header
            }
            const section_name = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t");
            in_alias_section = std.mem.eql(u8, section_name, "alias");
            continue;
        }

        // Parse key = value in [alias] section
        if (in_alias_section) {
            const eq_idx = std.mem.indexOf(u8, trimmed, "=") orelse {
                return error.InvalidToml; // Missing =
            };

            const key = std.mem.trim(u8, trimmed[0..eq_idx], " \t");
            var value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

            // Strip quotes from value
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            } else {
                return error.InvalidToml; // Value must be quoted
            }

            // Store owned copies
            const owned_key = try allocator.dupe(u8, key);
            errdefer allocator.free(owned_key);
            const owned_value = try allocator.dupe(u8, value);
            errdefer allocator.free(owned_value);

            try abbrevs.put(owned_key, owned_value);
        }
    }

    return abbrevs;
}

/// Expand a single abbreviation to full command arguments.
/// Returns null if abbreviation not found.
/// Caller owns the returned ArrayList.
pub fn expandAbbreviation(
    allocator: Allocator,
    abbreviations: *const std.StringHashMap([]const u8),
    abbrev: []const u8,
) !?std.ArrayList([]const u8) {
    const expansion = abbreviations.get(abbrev) orelse return null;

    var tokens = std.ArrayList([]const u8){};
    errdefer {
        for (tokens.items) |t| allocator.free(t);
        tokens.deinit(allocator);
    }

    // Simple tokenization on whitespace
    var iter = std.mem.tokenizeAny(u8, expansion, " \t");
    while (iter.next()) |token| {
        const owned_token = try allocator.dupe(u8, token);
        try tokens.append(allocator, owned_token);
    }

    return tokens;
}

/// Check if a command name conflicts with known builtin commands.
/// Returns true if there's a conflict.
pub fn conflictsWithBuiltin(cmd: []const u8, builtins: []const []const u8) bool {
    for (builtins) |builtin| {
        if (std.mem.eql(u8, cmd, builtin)) return true;
    }
    return false;
}

/// Get the path to ~/.zrconfig
pub fn getConfigPath(allocator: Allocator) ![]const u8 {
    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    return std.fs.path.join(allocator, &[_][]const u8{ home, ".zrconfig" });
}

/// Get the user's home directory
fn getHomeDir(allocator: Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        return home;
    } else |_| {}

    // Windows fallback
    if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |profile| {
        return profile;
    } else |_| {}

    return error.HomeNotFound;
}

// ============================================================================
// TESTS
// ============================================================================

test "parseAbbreviationConfig: empty file" {
    const allocator = std.testing.allocator;

    // Create temp directory and file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const config_content = "";
    const config_file = try tmp_dir.dir.createFile("test_config.toml", .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    const config_path = try tmp_dir.dir.realpathAlloc(allocator, "test_config.toml");
    defer allocator.free(config_path);

    var abbrevs = try parseAbbreviationConfig(allocator, config_path);
    defer {
        var it = abbrevs.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        abbrevs.deinit();
    }

    try std.testing.expectEqual(@as(usize, 0), abbrevs.count());
}

test "parseAbbreviationConfig: simple abbreviations" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const config_content =
        \\[alias]
        \\b = "run build"
        \\t = "run test"
        \\d = "run dev"
    ;
    const config_file = try tmp_dir.dir.createFile("test_config.toml", .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    const config_path = try tmp_dir.dir.realpathAlloc(allocator, "test_config.toml");
    defer allocator.free(config_path);

    var abbrevs = try parseAbbreviationConfig(allocator, config_path);
    defer {
        var it = abbrevs.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        abbrevs.deinit();
    }

    try std.testing.expectEqual(@as(usize, 3), abbrevs.count());
    try std.testing.expectEqualStrings("run build", abbrevs.get("b").?);
    try std.testing.expectEqualStrings("run test", abbrevs.get("t").?);
    try std.testing.expectEqualStrings("run dev", abbrevs.get("d").?);
}

test "parseAbbreviationConfig: file not found" {
    const allocator = std.testing.allocator;

    const result = parseAbbreviationConfig(allocator, "/nonexistent/path/config.toml");
    try std.testing.expectError(error.FileNotFound, result);
}

test "parseAbbreviationConfig: malformed TOML" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const config_content = "[alias\nb = \"run build"; // Malformed
    const config_file = try tmp_dir.dir.createFile("test_config.toml", .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    const config_path = try tmp_dir.dir.realpathAlloc(allocator, "test_config.toml");
    defer allocator.free(config_path);

    const result = parseAbbreviationConfig(allocator, config_path);
    // Should return an error for malformed TOML
    try std.testing.expectError(error.InvalidToml, result);
}

test "parseAbbreviationConfig: no alias section" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const config_content =
        \\[other]
        \\foo = "bar"
    ;
    const config_file = try tmp_dir.dir.createFile("test_config.toml", .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    const config_path = try tmp_dir.dir.realpathAlloc(allocator, "test_config.toml");
    defer allocator.free(config_path);

    var abbrevs = try parseAbbreviationConfig(allocator, config_path);
    defer {
        var it = abbrevs.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        abbrevs.deinit();
    }

    try std.testing.expectEqual(@as(usize, 0), abbrevs.count());
}

test "expandAbbreviation: simple expansion" {
    const allocator = std.testing.allocator;

    var abbrevs = std.StringHashMap([]const u8).init(allocator);
    defer abbrevs.deinit();
    try abbrevs.put("b", "run build");

    var expanded = (try expandAbbreviation(allocator, &abbrevs, "b")).?;
    defer {
        for (expanded.items) |item| allocator.free(item);
        expanded.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), expanded.items.len);
    try std.testing.expectEqualStrings("run", expanded.items[0]);
    try std.testing.expectEqualStrings("build", expanded.items[1]);
}

test "expandAbbreviation: not found" {
    const allocator = std.testing.allocator;

    var abbrevs = std.StringHashMap([]const u8).init(allocator);
    defer abbrevs.deinit();
    try abbrevs.put("b", "run build");

    const result = try expandAbbreviation(allocator, &abbrevs, "xyz");
    try std.testing.expect(result == null);
}

test "expandAbbreviation: multi-word expansion" {
    const allocator = std.testing.allocator;

    var abbrevs = std.StringHashMap([]const u8).init(allocator);
    defer abbrevs.deinit();
    try abbrevs.put("d", "run dev --watch");

    var expanded = (try expandAbbreviation(allocator, &abbrevs, "d")).?;
    defer {
        for (expanded.items) |item| allocator.free(item);
        expanded.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), expanded.items.len);
    try std.testing.expectEqualStrings("run", expanded.items[0]);
    try std.testing.expectEqualStrings("dev", expanded.items[1]);
    try std.testing.expectEqualStrings("--watch", expanded.items[2]);
}

test "conflictsWithBuiltin: detects conflict" {
    const builtins = [_][]const u8{ "run", "build", "test", "watch" };

    try std.testing.expect(conflictsWithBuiltin("run", &builtins) == true);
    try std.testing.expect(conflictsWithBuiltin("build", &builtins) == true);
}

test "conflictsWithBuiltin: no conflict" {
    const builtins = [_][]const u8{ "run", "build", "test", "watch" };

    try std.testing.expect(conflictsWithBuiltin("b", &builtins) == false);
    try std.testing.expect(conflictsWithBuiltin("t", &builtins) == false);
    try std.testing.expect(conflictsWithBuiltin("xyz", &builtins) == false);
}

test "getConfigPath: returns ~/.zrconfig" {
    const allocator = std.testing.allocator;

    const path = try getConfigPath(allocator);
    defer allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, ".zrconfig"));
}

test "getHomeDir: returns home directory" {
    const allocator = std.testing.allocator;

    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    // Should return a non-empty path
    try std.testing.expect(home.len > 0);
}
