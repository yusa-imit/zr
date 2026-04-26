const std = @import("std");

/// Load environment variables from a .env file.
/// Format: KEY=value, KEY="quoted value", # comments, empty lines ignored.
/// Returns a StringHashMap of loaded variables (caller owns).
pub fn loadEnvFile(allocator: std.mem.Allocator, file_path: []const u8) !std.StringHashMap([]const u8) {
    var env_map = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    // Handle both absolute and relative paths
    const file: std.fs.File = blk: {
        // Check if path is absolute (starts with / on Unix, or has drive letter on Windows)
        const is_abs = std.fs.path.isAbsolute(file_path);
        const result = if (is_abs)
            std.fs.openFileAbsolute(file_path, .{})
        else
            std.fs.cwd().openFile(file_path, .{});

        break :blk result catch |err| {
            // Missing .env file is not an error — return empty map
            if (err == error.FileNotFound) {
                return env_map;
            }
            return err;
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB limit
    defer allocator.free(content);

    var line_it = std.mem.splitScalar(u8, content, '\n');
    while (line_it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Find the first '=' separator
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_idx| {
            const key = std.mem.trim(u8, trimmed[0..eq_idx], &std.ascii.whitespace);
            if (key.len == 0) continue; // Invalid: no key

            var value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], &std.ascii.whitespace);

            // Handle quoted values: "value" or 'value'
            if (value.len >= 2) {
                if ((value[0] == '"' and value[value.len - 1] == '"') or
                    (value[0] == '\'' and value[value.len - 1] == '\''))
                {
                    value = value[1 .. value.len - 1];
                }
            }

            // Store (dupe both key and value)
            const key_owned = try allocator.dupe(u8, key);
            errdefer allocator.free(key_owned);
            const value_owned = try allocator.dupe(u8, value);
            errdefer allocator.free(value_owned);

            // If key already exists, free old value and replace
            if (try env_map.fetchPut(key_owned, value_owned)) |old_entry| {
                allocator.free(old_entry.key);
                allocator.free(old_entry.value);
            }
        }
        // Lines without '=' are ignored (invalid format)
    }

    return env_map;
}

/// Load multiple .env files with override semantics (later files override earlier).
/// Returns a merged StringHashMap (caller owns).
pub fn loadEnvFiles(allocator: std.mem.Allocator, file_paths: []const []const u8) !std.StringHashMap([]const u8) {
    var merged = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = merged.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        merged.deinit();
    }

    for (file_paths) |file_path| {
        var file_map = try loadEnvFile(allocator, file_path);
        defer {
            var it = file_map.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            file_map.deinit();
        }

        // Merge into result (later values override earlier)
        var it = file_map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Check if key already exists before we dupe
            if (merged.get(key)) |_| {
                // Key exists, so we'll override it
                // First, get and free the old value (but keep the key pointer for now)
                if (merged.getPtr(key)) |old_entry_ptr| {
                    allocator.free(old_entry_ptr.*);
                    old_entry_ptr.* = try allocator.dupe(u8, value);
                }
            } else {
                // Key doesn't exist, insert it
                const key_owned = try allocator.dupe(u8, key);
                errdefer allocator.free(key_owned);
                const value_owned = try allocator.dupe(u8, value);
                errdefer allocator.free(value_owned);
                try merged.put(key_owned, value_owned);
            }
        }
    }

    return merged;
}

test "loadEnvFile: basic KEY=value" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create .env file
    const env_content = "KEY1=value1\nKEY2=value2\n";
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    const allocator = testing.allocator;
    const path = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path);

    var env_map = try loadEnvFile(allocator, path);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqual(@as(usize, 2), env_map.count());
    try testing.expectEqualStrings("value1", env_map.get("KEY1").?);
    try testing.expectEqualStrings("value2", env_map.get("KEY2").?);
}

test "loadEnvFile: quoted values" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env_content = "KEY1=\"value with spaces\"\nKEY2='single quoted'\n";
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    const allocator = testing.allocator;
    const path = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path);

    var env_map = try loadEnvFile(allocator, path);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqualStrings("value with spaces", env_map.get("KEY1").?);
    try testing.expectEqualStrings("single quoted", env_map.get("KEY2").?);
}

test "loadEnvFile: comments and empty lines" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const env_content = "# Comment line\nKEY1=value1\n\nKEY2=value2\n# Another comment\n";
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    const allocator = testing.allocator;
    const path = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path);

    var env_map = try loadEnvFile(allocator, path);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqual(@as(usize, 2), env_map.count());
}

test "loadEnvFile: missing file returns empty map" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = try loadEnvFile(allocator, "/nonexistent/file.env");
    defer env_map.deinit();

    try testing.expectEqual(@as(usize, 0), env_map.count());
}

test "loadEnvFiles: multiple files with override" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = "KEY1=base\nKEY2=base2\n" });
    try tmp.dir.writeFile(.{ .sub_path = ".env.local", .data = "KEY1=override\n" });

    const allocator = testing.allocator;
    const path1 = try tmp.dir.realpathAlloc(allocator, ".env");
    defer allocator.free(path1);
    const path2 = try tmp.dir.realpathAlloc(allocator, ".env.local");
    defer allocator.free(path2);

    const paths = [_][]const u8{ path1, path2 };
    var env_map = try loadEnvFiles(allocator, &paths);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    try testing.expectEqualStrings("override", env_map.get("KEY1").?);
    try testing.expectEqualStrings("base2", env_map.get("KEY2").?);
}

/// Expand environment variable references in a value string.
/// Supports:
/// - ${VAR_NAME} syntax (variable in braces)
/// - $VAR_NAME syntax (simple variable without braces)
/// - $$ escape sequence (expands to single $)
/// - Recursive expansion (VAR1=${VAR2}, VAR2 is expanded first)
/// - Circular reference detection (VAR1=${VAR2}, VAR2=${VAR1} returns error)
/// - Undefined variables are preserved as-is: ${UNDEFINED} stays ${UNDEFINED}
///
/// Returns an owned string (caller must free).
/// Errors: OutOfMemory, CircularReference
pub fn interpolateEnvValue(
    allocator: std.mem.Allocator,
    value: []const u8,
    env_map: std.StringHashMap([]const u8),
) ![]const u8 {
    // Track visited variables to detect circular references
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    return try interpolateEnvValueRecursive(allocator, value, env_map, &visited);
}

const InterpolateError = error{ CircularReference, OutOfMemory };

fn interpolateEnvValueRecursive(
    allocator: std.mem.Allocator,
    value: []const u8,
    env_map: std.StringHashMap([]const u8),
    visited: *std.StringHashMap(void),
) InterpolateError![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, value.len);
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < value.len) {
        if (value[i] == '$') {
            // Check for $$ escape sequence
            if (i + 1 < value.len and value[i + 1] == '$') {
                try result.appendSlice(allocator, "$");
                i += 2;
                continue;
            }

            // Check for ${VAR} syntax
            if (i + 1 < value.len and value[i + 1] == '{') {
                // Find closing brace
                const start = i + 2;
                var end: ?usize = null;
                for (start..value.len) |j| {
                    if (value[j] == '}') {
                        end = j;
                        break;
                    }
                }

                if (end) |close_idx| {
                    const var_name = value[start..close_idx];

                    // Check if variable exists in env_map
                    if (env_map.get(var_name)) |var_value| {
                        // Check for circular reference
                        if (visited.contains(var_name)) {
                            return error.CircularReference;
                        }

                        // Mark as visited before recursing
                        try visited.put(var_name, {});
                        defer _ = visited.remove(var_name);

                        // Recursively expand the variable value
                        const expanded = try interpolateEnvValueRecursive(allocator, var_value, env_map, visited);
                        defer allocator.free(expanded);

                        try result.appendSlice(allocator, expanded);
                    } else {
                        // Undefined variable - preserve as-is
                        try result.appendSlice(allocator, value[i..close_idx + 1]);
                    }

                    i = close_idx + 1;
                    continue;
                } else {
                    // No closing brace - treat as literal
                    try result.appendSlice(allocator, "$");
                    i += 1;
                    continue;
                }
            }

            // Check for $VAR syntax (no braces)
            if (i + 1 < value.len) {
                const start = i + 1;
                var end = start;

                // Parse variable name (alphanumeric, underscore)
                while (end < value.len) {
                    const c = value[end];
                    if ((c >= 'A' and c <= 'Z') or
                        (c >= 'a' and c <= 'z') or
                        (c >= '0' and c <= '9') or
                        c == '_') {
                        end += 1;
                    } else {
                        break;
                    }
                }

                if (end > start) {
                    const var_name = value[start..end];

                    if (env_map.get(var_name)) |var_value| {
                        // Check for circular reference
                        if (visited.contains(var_name)) {
                            return error.CircularReference;
                        }

                        // Mark as visited before recursing
                        try visited.put(var_name, {});
                        defer _ = visited.remove(var_name);

                        // Recursively expand the variable value
                        const expanded = try interpolateEnvValueRecursive(allocator, var_value, env_map, visited);
                        defer allocator.free(expanded);

                        try result.appendSlice(allocator, expanded);
                    } else {
                        // Undefined variable - preserve as-is
                        try result.appendSlice(allocator, value[i..end]);
                    }

                    i = end;
                    continue;
                } else {
                    // $ not followed by valid variable name - preserve literal
                    try result.appendSlice(allocator, "$");
                    i += 1;
                    continue;
                }
            }

            // $ at end of string - preserve literal
            try result.appendSlice(allocator, "$");
            i += 1;
        } else {
            // Regular character
            try result.appendSlice(allocator, value[i..i + 1]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

test "interpolateEnvValue: basic ${VAR} expansion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("NAME", "World");
    const result = try interpolateEnvValue(allocator, "Hello ${NAME}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello World", result);
}

test "interpolateEnvValue: simple $VAR expansion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("HOME", "/home/user");
    const result = try interpolateEnvValue(allocator, "Path: $HOME", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Path: /home/user", result);
}

test "interpolateEnvValue: $$ escape sequence" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "Price: $$100", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Price: $100", result);
}

test "interpolateEnvValue: multiple $$ escapes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "Cost: $$50 + $$30 = $$80", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Cost: $50 + $30 = $80", result);
}

test "interpolateEnvValue: recursive expansion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("VAR2", "value2");
    try env_map.put("VAR1", "${VAR2}");
    const result = try interpolateEnvValue(allocator, "Result: ${VAR1}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Result: value2", result);
}

test "interpolateEnvValue: circular reference detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("VAR1", "${VAR2}");
    try env_map.put("VAR2", "${VAR1}");

    const result = interpolateEnvValue(allocator, "Value: ${VAR1}", env_map);
    try testing.expectError(error.CircularReference, result);
}

test "interpolateEnvValue: circular reference with $VAR syntax" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("A", "$B");
    try env_map.put("B", "$A");

    const result = interpolateEnvValue(allocator, "Value: $A", env_map);
    try testing.expectError(error.CircularReference, result);
}

test "interpolateEnvValue: undefined variable preservation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "Value: ${UNDEFINED}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Value: ${UNDEFINED}", result);
}

test "interpolateEnvValue: undefined variable with $VAR syntax" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "Path: $UNDEFINED", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Path: $UNDEFINED", result);
}

test "interpolateEnvValue: mixed literal and variable content" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("USER", "alice");
    try env_map.put("HOST", "server.com");
    const result = try interpolateEnvValue(allocator, "Email: ${USER}@${HOST}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Email: alice@server.com", result);
}

test "interpolateEnvValue: empty value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("", result);
}

test "interpolateEnvValue: multiple variables in one value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("FIRST", "Hello");
    try env_map.put("SECOND", "World");
    try env_map.put("THIRD", "!");
    const result = try interpolateEnvValue(allocator, "$FIRST $SECOND$THIRD", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello World!", result);
}

test "interpolateEnvValue: variable with underscores and numbers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("VAR_NAME_1", "test_value");
    const result = try interpolateEnvValue(allocator, "Value: ${VAR_NAME_1}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Value: test_value", result);
}

test "interpolateEnvValue: three-level recursive expansion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("VAR3", "final");
    try env_map.put("VAR2", "${VAR3}");
    try env_map.put("VAR1", "${VAR2}");
    const result = try interpolateEnvValue(allocator, "Result: ${VAR1}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Result: final", result);
}

test "interpolateEnvValue: $$ escape prevents variable expansion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("PRICE", "50");
    // $$ is an escape sequence that becomes a literal $, so {PRICE} is not a variable reference
    const result = try interpolateEnvValue(allocator, "Cost: $${PRICE}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Cost: ${PRICE}", result);
}

test "interpolateEnvValue: no closing brace treated as literal" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "Value: ${UNCLOSED", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Value: ${UNCLOSED", result);
}

test "interpolateEnvValue: $ at end of string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "Value: $", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Value: $", result);
}

test "interpolateEnvValue: variable with empty value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("EMPTY", "");
    const result = try interpolateEnvValue(allocator, "Before${EMPTY}After", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("BeforeAfter", result);
}

test "interpolateEnvValue: only variable reference" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("VALUE", "complete");
    const result = try interpolateEnvValue(allocator, "${VALUE}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("complete", result);
}

test "interpolateEnvValue: variable expands to another ${...} pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("INNER", "expanded");
    try env_map.put("OUTER", "${INNER}");
    const result = try interpolateEnvValue(allocator, "Result: ${OUTER}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Result: expanded", result);
}

test "interpolateEnvValue: recursive with three-way cycle detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("A", "${B}");
    try env_map.put("B", "${C}");
    try env_map.put("C", "${A}");

    const result = interpolateEnvValue(allocator, "Value: ${A}", env_map);
    try testing.expectError(error.CircularReference, result);
}

test "interpolateEnvValue: ${ with number (invalid variable name)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "Value: ${123}", env_map);
    defer allocator.free(result);

    // Variable names starting with numbers are invalid, treated as undefined
    try testing.expectEqualStrings("Value: ${123}", result);
}

test "interpolateEnvValue: mixed ${} and $ syntaxes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("FIRST", "hello");
    try env_map.put("SECOND", "world");
    const result = try interpolateEnvValue(allocator, "${FIRST} $SECOND", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("hello world", result);
}

test "interpolateEnvValue: consecutive $$ escapes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    const result = try interpolateEnvValue(allocator, "$$$$", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("$$", result);
}

test "interpolateEnvValue: variable name with leading underscore" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("_PRIVATE", "secret");
    const result = try interpolateEnvValue(allocator, "Value: ${_PRIVATE}", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("Value: secret", result);
}

test "interpolateEnvValue: whitespace preservation in expanded value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var env_map = std.StringHashMap([]const u8).init(allocator);
    defer env_map.deinit();

    try env_map.put("SPACES", "  spaced  ");
    const result = try interpolateEnvValue(allocator, "[${SPACES}]", env_map);
    defer allocator.free(result);

    try testing.expectEqualStrings("[  spaced  ]", result);
}
