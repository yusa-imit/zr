const std = @import("std");
const types = @import("types.zig");
const glob_util = @import("../util/glob.zig");

const ConformanceRule = types.ConformanceRule;
const ConformanceViolation = types.ConformanceViolation;
const ConformanceResult = types.ConformanceResult;
const ConformanceConfig = types.ConformanceConfig;
const Severity = types.Severity;
const RuleType = types.RuleType;

/// Check all conformance rules against files in the workspace.
pub fn checkConformance(
    allocator: std.mem.Allocator,
    config: *const ConformanceConfig,
    workspace_root: []const u8,
) !ConformanceResult {
    var result = ConformanceResult.init(allocator);
    var violations_list = std.ArrayList(ConformanceViolation){};
    errdefer {
        for (violations_list.items) |*v| {
            allocator.free(v.rule_id);
            allocator.free(v.file_path);
            allocator.free(v.message);
            if (v.suggested_fix) |fix| allocator.free(fix);
        }
        violations_list.deinit(allocator);
    }

    // For each rule, find matching files and check them
    for (config.rules) |*rule| {
        // Find files matching the scope pattern
        const matching_files = try findMatchingFiles(allocator, workspace_root, rule.scope, config.ignore);
        defer {
            for (matching_files) |file| allocator.free(file);
            allocator.free(matching_files);
        }

        // Check each file against the rule
        for (matching_files) |file_path| {
            const violation = try checkFileAgainstRule(allocator, file_path, rule, workspace_root);
            if (violation) |v| {
                try violations_list.append(allocator, v);

                // Update counts based on severity
                switch (v.severity) {
                    .err => result.error_count += 1,
                    .warning => result.warning_count += 1,
                    .info => result.info_count += 1,
                }
            }
        }
    }

    result.violations = try allocator.alloc(ConformanceViolation, violations_list.items.len);
    @memcpy(result.violations, violations_list.items);
    violations_list.deinit(allocator);

    return result;
}

/// Find files matching a glob pattern, excluding ignored paths.
fn findMatchingFiles(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    pattern: []const u8,
    ignore_patterns: []const []const u8,
) ![]const []const u8 {
    var files = std.ArrayList([]const u8){};
    errdefer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    // Walk the workspace directory
    var dir = try std.fs.openDirAbsolute(workspace_root, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        // Build full path
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ workspace_root, entry.path });
        errdefer allocator.free(full_path);

        // Check if matches pattern
        if (!glob_util.match(pattern, entry.path)) {
            allocator.free(full_path);
            continue;
        }

        // Check if should be ignored
        var should_ignore = false;
        for (ignore_patterns) |ignore_pattern| {
            if (glob_util.match(ignore_pattern, entry.path)) {
                should_ignore = true;
                break;
            }
        }

        if (should_ignore) {
            allocator.free(full_path);
            continue;
        }

        try files.append(allocator, full_path);
    }

    return try files.toOwnedSlice(allocator);
}

/// Check a single file against a rule, returning a violation if any.
fn checkFileAgainstRule(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    rule: *const ConformanceRule,
    workspace_root: []const u8,
) !?ConformanceViolation {
    switch (rule.type) {
        .import_pattern => return try checkImportPattern(allocator, file_path, rule),
        .file_naming => return try checkFileNaming(allocator, file_path, rule),
        .file_size => return try checkFileSize(allocator, file_path, rule),
        .directory_depth => return try checkDirectoryDepth(allocator, file_path, rule, workspace_root),
        .file_extension => return try checkFileExtension(allocator, file_path, rule),
    }
}

/// Check import pattern rule (basic implementation - checks for pattern in file content).
fn checkImportPattern(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    rule: *const ConformanceRule,
) !?ConformanceViolation {
    const pattern = rule.pattern orelse return null;

    // Read file content
    const file = std.fs.openFileAbsolute(file_path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return null;
    defer allocator.free(content);

    // Check if banned pattern appears in imports
    // Simple heuristic: look for "import" or "require" lines containing the pattern
    var lines = std.mem.splitScalar(u8, content, '\n');
    var line_num: usize = 0;
    while (lines.next()) |line| {
        line_num += 1;

        // Check if this is an import/require line
        const trimmed = std.mem.trim(u8, line, " \t");
        const is_import = std.mem.startsWith(u8, trimmed, "import ") or
            std.mem.startsWith(u8, trimmed, "import{") or
            std.mem.startsWith(u8, trimmed, "const ") and std.mem.indexOf(u8, trimmed, "require(") != null;

        if (is_import and std.mem.indexOf(u8, line, pattern) != null) {
            const message = try std.fmt.allocPrint(allocator, "{s} (found '{s}' in import)", .{ rule.message, pattern });
            return ConformanceViolation{
                .rule_id = try allocator.dupe(u8, rule.id),
                .file_path = try allocator.dupe(u8, file_path),
                .line = line_num,
                .column = null,
                .severity = rule.severity,
                .message = message,
                .suggested_fix = null,
            };
        }
    }

    return null;
}

/// Check file naming convention.
fn checkFileNaming(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    rule: *const ConformanceRule,
) !?ConformanceViolation {
    const pattern = rule.pattern orelse return null;

    const basename = std.fs.path.basename(file_path);

    // Check if filename matches the required pattern
    if (!glob_util.match(pattern, basename)) {
        const message = try std.fmt.allocPrint(
            allocator,
            "{s} (expected pattern: {s}, got: {s})",
            .{ rule.message, pattern, basename },
        );
        return ConformanceViolation{
            .rule_id = try allocator.dupe(u8, rule.id),
            .file_path = try allocator.dupe(u8, file_path),
            .line = null,
            .column = null,
            .severity = rule.severity,
            .message = message,
            .suggested_fix = null,
        };
    }

    return null;
}

/// Check file size limit.
fn checkFileSize(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    rule: *const ConformanceRule,
) !?ConformanceViolation {
    // Get max_bytes from config
    const max_bytes_str = rule.config.get("max_bytes") orelse return null;
    const max_bytes = std.fmt.parseInt(usize, max_bytes_str, 10) catch return null;

    const file = std.fs.openFileAbsolute(file_path, .{}) catch return null;
    defer file.close();

    const stat = file.stat() catch return null;

    if (stat.size > max_bytes) {
        const message = try std.fmt.allocPrint(
            allocator,
            "{s} ({d} bytes > {d} bytes limit)",
            .{ rule.message, stat.size, max_bytes },
        );
        return ConformanceViolation{
            .rule_id = try allocator.dupe(u8, rule.id),
            .file_path = try allocator.dupe(u8, file_path),
            .line = null,
            .column = null,
            .severity = rule.severity,
            .message = message,
            .suggested_fix = null,
        };
    }

    return null;
}

/// Check directory depth limit.
fn checkDirectoryDepth(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    rule: *const ConformanceRule,
    workspace_root: []const u8,
) !?ConformanceViolation {
    // Get max_depth from config
    const max_depth_str = rule.config.get("max_depth") orelse return null;
    const max_depth = std.fmt.parseInt(usize, max_depth_str, 10) catch return null;

    // Calculate relative path depth
    const rel_path = if (std.mem.startsWith(u8, file_path, workspace_root))
        file_path[workspace_root.len..]
    else
        file_path;

    var depth: usize = 0;
    var it = std.mem.splitScalar(u8, rel_path, std.fs.path.sep);
    while (it.next()) |component| {
        if (component.len > 0) depth += 1;
    }

    if (depth > max_depth) {
        const message = try std.fmt.allocPrint(
            allocator,
            "{s} (depth {d} > {d} limit)",
            .{ rule.message, depth, max_depth },
        );
        return ConformanceViolation{
            .rule_id = try allocator.dupe(u8, rule.id),
            .file_path = try allocator.dupe(u8, file_path),
            .line = null,
            .column = null,
            .severity = rule.severity,
            .message = message,
            .suggested_fix = null,
        };
    }

    return null;
}

/// Check file extension restriction.
fn checkFileExtension(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    rule: *const ConformanceRule,
) !?ConformanceViolation {
    // Get allowed or banned extensions from config
    const allowed_str = rule.config.get("allowed");
    const banned_str = rule.config.get("banned");

    const extension = std.fs.path.extension(file_path);
    if (extension.len == 0) return null; // No extension

    if (allowed_str) |allowed| {
        // Check if extension is in allowed list
        var allowed_iter = std.mem.splitScalar(u8, allowed, ',');
        var is_allowed = false;
        while (allowed_iter.next()) |ext| {
            const trimmed = std.mem.trim(u8, ext, " ");
            if (std.mem.eql(u8, extension, trimmed)) {
                is_allowed = true;
                break;
            }
        }

        if (!is_allowed) {
            const message = try std.fmt.allocPrint(
                allocator,
                "{s} (extension '{s}' not in allowed list: {s})",
                .{ rule.message, extension, allowed },
            );
            return ConformanceViolation{
                .rule_id = try allocator.dupe(u8, rule.id),
                .file_path = try allocator.dupe(u8, file_path),
                .line = null,
                .column = null,
                .severity = rule.severity,
                .message = message,
                .suggested_fix = null,
            };
        }
    }

    if (banned_str) |banned| {
        // Check if extension is in banned list
        var banned_iter = std.mem.splitScalar(u8, banned, ',');
        while (banned_iter.next()) |ext| {
            const trimmed = std.mem.trim(u8, ext, " ");
            if (std.mem.eql(u8, extension, trimmed)) {
                const message = try std.fmt.allocPrint(
                    allocator,
                    "{s} (extension '{s}' is banned)",
                    .{ rule.message, extension },
                );
                return ConformanceViolation{
                    .rule_id = try allocator.dupe(u8, rule.id),
                    .file_path = try allocator.dupe(u8, file_path),
                    .line = null,
                    .column = null,
                    .severity = rule.severity,
                    .message = message,
                    .suggested_fix = null,
                };
            }
        }
    }

    return null;
}

test "checkImportPattern - no violation" {
    const allocator = std.testing.allocator;

    // Create a test file with clean imports
    const tmp = std.testing.tmpDir(.{});
    var dir = tmp.dir;
    const test_file = try dir.createFile("test.js", .{});
    defer test_file.close();
    try test_file.writeAll("import { foo } from './bar';\n");

    var buf: [1024]u8 = undefined;
    const file_path = try dir.realpath("test.js", &buf);

    var rule = ConformanceRule.init(
        allocator,
        "no-react",
        .import_pattern,
        .err,
        "**/*.js",
        "React imports not allowed in backend",
    );
    rule.pattern = "react";
    defer rule.deinit();

    const violation = try checkImportPattern(allocator, file_path, &rule);
    try std.testing.expectEqual(@as(?ConformanceViolation, null), violation);
}

test "checkFileNaming - violation" {
    const allocator = std.testing.allocator;

    const tmp = std.testing.tmpDir(.{});
    var dir = tmp.dir;
    const test_file = try dir.createFile("badname.js", .{});
    defer test_file.close();

    var buf: [1024]u8 = undefined;
    const file_path = try dir.realpath("badname.js", &buf);

    var rule = ConformanceRule.init(
        allocator,
        "test-naming",
        .file_naming,
        .warning,
        "**/*.test.js",
        "Test files must end with .test.js",
    );
    rule.pattern = "*.test.js";
    defer rule.deinit();

    const violation = try checkFileNaming(allocator, file_path, &rule);
    try std.testing.expect(violation != null);
    if (violation) |v| {
        allocator.free(v.rule_id);
        allocator.free(v.file_path);
        allocator.free(v.message);
    }
}

test "checkDirectoryDepth - violation" {
    const allocator = std.testing.allocator;

    var rule = ConformanceRule.init(
        allocator,
        "depth-limit",
        .directory_depth,
        .warning,
        "**/*",
        "Directory depth too deep",
    );
    defer rule.deinit();

    const key = try allocator.dupe(u8, "max_depth");
    errdefer allocator.free(key);
    const value = try allocator.dupe(u8, "3");
    errdefer allocator.free(value);
    try rule.config.put(key, value);

    const file_path = "/workspace/a/b/c/d/file.txt";
    const workspace_root = "/workspace";

    const violation = try checkDirectoryDepth(allocator, file_path, &rule, workspace_root);
    try std.testing.expect(violation != null);
    if (violation) |v| {
        allocator.free(v.rule_id);
        allocator.free(v.file_path);
        allocator.free(v.message);
    }
}
