const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

/// Substitute environment variables in ${VAR} syntax within a string.
///
/// Returns an owned string with variables expanded using the provided environment map.
/// Falls back to std.process.getEnvVarOwned if variable not in map.
///
/// Variables:
/// - ${HOME} → expanded to HOME env var value
/// - ${VAR1}${VAR2} → adjacent variables expanded
/// - \${VAR} → escaped, returns literal "${VAR}" (no expansion)
/// - ${} → empty variable name, kept as-is
/// - $VAR → without braces, not expanded (partial match)
/// - Undefined variables → expand to empty string
///
/// Caller owns the returned string and must free it.
pub fn substitute(
    allocator: Allocator,
    input: []const u8,
    env: *std.StringHashMap([]const u8),
) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len and input[i + 1] == '$') {
            // Escaped $ — output literal $
            try result.append(allocator, '$');
            i += 2;
        } else if (input[i] == '$' and i + 1 < input.len and input[i + 1] == '{') {
            // Found ${...} pattern
            i += 2; // Skip ${

            // Find closing }
            var close_idx: ?usize = null;
            for (i..input.len) |idx| {
                if (input[idx] == '}') {
                    close_idx = idx;
                    break;
                }
            }

            if (close_idx) |close| {
                const var_name = input[i..close];

                if (var_name.len == 0) {
                    // Empty variable name ${} — keep as-is
                    try result.appendSlice(allocator, "${}");
                } else {
                    // Look up in map first, then fall back to process env
                    const var_value = if (env.get(var_name)) |v|
                        v
                    else
                        (std.process.getEnvVarOwned(allocator, var_name) catch null) orelse "";

                    // If we got the value from process env, we need to free it
                    const from_process_env = env.get(var_name) == null and var_value.len > 0;
                    defer if (from_process_env) allocator.free(var_value);

                    try result.appendSlice(allocator, var_value);
                }

                i = close + 1;
            } else {
                // No closing } found — output as literal and continue from start of attempted var name
                try result.append(allocator, '$');
                try result.append(allocator, '{');
                // i is already at the position after {, so continue normally
            }
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "varsubst basic substitution with map" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("HOME", "/home/user");
    const result = try substitute(allocator, "${HOME}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/home/user", result);
}

test "varsubst multiple variables in one string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("USER", "alice");
    try env.put("HOST", "localhost");

    const result = try substitute(allocator, "${USER}@${HOST}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("alice@localhost", result);
}

test "varsubst text before and after variable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("USER", "bob");

    const result = try substitute(allocator, "Welcome ${USER}!", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Welcome bob!", result);
}

test "varsubst escaped dollar sign prevents expansion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("VAR", "value");

    const result = try substitute(allocator, "\\${VAR}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("${VAR}", result);
}

test "varsubst partial match without braces not expanded" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("HOME", "/home/user");

    const result = try substitute(allocator, "$HOME/.config", &env);
    defer allocator.free(result);

    // Should not expand without braces
    try std.testing.expectEqualStrings("$HOME/.config", result);
}

test "varsubst undefined variable expands to empty string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "prefix_${NONEXISTENT}_suffix", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("prefix__suffix", result);
}

test "varsubst empty variable name kept as-is" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "before${}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("before${}", result);
}

test "varsubst adjacent variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("A", "hello");
    try env.put("B", "world");

    const result = try substitute(allocator, "${A}${B}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("helloworld", result);
}

test "varsubst special characters in variable names (underscores)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("MY_VAR", "underscore_value");

    const result = try substitute(allocator, "${MY_VAR}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("underscore_value", result);
}

test "varsubst special characters in variable names (numbers)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("VAR1", "numeric_name");

    const result = try substitute(allocator, "${VAR1}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("numeric_name", result);
}

test "varsubst no closing brace outputs literal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "${UNCLOSED", &env);
    defer allocator.free(result);

    // No closing } — outputs literal ${ and then the rest as normal text
    try std.testing.expectEqualStrings("${UNCLOSED", result);
}

test "varsubst multiple escapes in sequence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("VAR", "value");

    const result = try substitute(allocator, "\\${VAR}\\${VAR}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("${VAR}${VAR}", result);
}

test "varsubst empty input string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "varsubst no variables in input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "plain text without variables", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("plain text without variables", result);
}

test "varsubst variable at start" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("PREFIX", "start");

    const result = try substitute(allocator, "${PREFIX}_rest", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("start_rest", result);
}

test "varsubst variable at end" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("SUFFIX", "end");

    const result = try substitute(allocator, "prefix_${SUFFIX}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("prefix_end", result);
}

test "varsubst map takes precedence over process env" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    // Set a value in the map that may also be in process env
    try env.put("USER", "map_user");

    const result = try substitute(allocator, "${USER}", &env);
    defer allocator.free(result);

    // Should use the map value
    try std.testing.expectEqualStrings("map_user", result);
}

test "varsubst paths with variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("HOME", "/home/user");
    try env.put("PROJECT", "myapp");

    const result = try substitute(allocator, "${HOME}/projects/${PROJECT}/src", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/home/user/projects/myapp/src", result);
}

test "varsubst escaped at end of string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "text\\$", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("text$", result);
}

test "varsubst only variable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("ONLY", "just_value");

    const result = try substitute(allocator, "${ONLY}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("just_value", result);
}

test "varsubst variable name with hyphen treated as part of literal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    // Hyphens in variable names are valid in the lookup
    try env.put("VAR-NAME", "hyphen_value");

    const result = try substitute(allocator, "${VAR-NAME}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hyphen_value", result);
}

test "varsubst consecutive escape sequences" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "\\$\\$", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("$$", result);
}

test "varsubst mixed escaped and unescaped" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("VAR", "expanded");

    const result = try substitute(allocator, "\\${VAR} and ${VAR}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("${VAR} and expanded", result);
}

test "varsubst long variable name" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("VERY_LONG_VARIABLE_NAME_WITH_MANY_UNDERSCORES", "long_value");

    const result = try substitute(allocator, "${VERY_LONG_VARIABLE_NAME_WITH_MANY_UNDERSCORES}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("long_value", result);
}

test "varsubst variable value is empty string in map" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("EMPTY", "");

    const result = try substitute(allocator, "before${EMPTY}after", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("beforeafter", result);
}

test "varsubst variable value with spaces" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("SPACED", "value with spaces");

    const result = try substitute(allocator, "${SPACED}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("value with spaces", result);
}

test "varsubst variable value with special characters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("SPECIAL", "!@#$%^&*()");

    const result = try substitute(allocator, "${SPECIAL}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("!@#$%^&*()", result);
}

test "varsubst three consecutive variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("A", "one");
    try env.put("B", "two");
    try env.put("C", "three");

    const result = try substitute(allocator, "${A}-${B}-${C}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("one-two-three", result);
}

test "varsubst escaped escape sequence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "\\\\${VAR}", &env);
    defer allocator.free(result);

    // \\$ should produce backslash followed by literal $
    try std.testing.expectEqualStrings("\\${VAR}", result);
}

test "varsubst case sensitive variable names" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("VAR", "uppercase");
    // var (lowercase) is not in map, should expand to empty

    const result = try substitute(allocator, "${var}", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "varsubst dollar at very end" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "price$", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("price$", result);
}

test "varsubst escaped at very end" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    const result = try substitute(allocator, "escaped\\$", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("escaped$", result);
}

test "varsubst memory cleanup with allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("A", "first");
    try env.put("B", "second");
    try env.put("C", "third");

    const result = try substitute(allocator, "${A}+${B}+${C}=${RESULT}", &env);
    defer allocator.free(result);

    // RESULT is not in env, so expands to empty string
    try std.testing.expectEqualStrings("first+second+third=", result);
}

test "varsubst malformed patterns don't crash" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("VAR", "value");

    // Malformed: ${$VAR} should be treated as variable named "$VAR"
    const result = try substitute(allocator, "${$VAR}", &env);
    defer allocator.free(result);

    // Should expand to empty (undefined variable "$VAR")
    try std.testing.expectEqualStrings("", result);
}

test "varsubst whitespace preservation in values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();

    try env.put("INDENT", "    4 spaces");

    const result = try substitute(allocator, "prefix${INDENT}suffix", &env);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("prefix    4 spacessuffix", result);
}
