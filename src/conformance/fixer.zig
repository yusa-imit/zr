const std = @import("std");
const types = @import("types.zig");

const ConformanceViolation = types.ConformanceViolation;
const RuleType = types.RuleType;

/// Result of applying fixes to violations.
pub const FixResult = struct {
    fixed_count: usize,
    failed_count: usize,
    skipped_count: usize, // Not fixable
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FixResult {
        return .{
            .fixed_count = 0,
            .failed_count = 0,
            .skipped_count = 0,
            .allocator = allocator,
        };
    }
};

/// Apply fixes to conformance violations where possible.
pub fn applyFixes(
    allocator: std.mem.Allocator,
    violations: []const ConformanceViolation,
    rule_types: []const RuleType,
) !FixResult {
    var result = FixResult.init(allocator);

    // Group violations by file for efficient fixing
    var file_violations = std.StringHashMap(std.ArrayList(ConformanceViolation)).init(allocator);
    defer {
        var it = file_violations.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        file_violations.deinit();
    }

    // Group by file path
    for (violations) |violation| {
        const file_path = try allocator.dupe(u8, violation.file_path);
        errdefer allocator.free(file_path);

        if (file_violations.getPtr(file_path)) |list| {
            allocator.free(file_path); // Already have this key
            try list.append(allocator, violation);
        } else {
            var list = std.ArrayList(ConformanceViolation){};
            try list.append(allocator, violation);
            try file_violations.put(file_path, list);
        }
    }

    // Find rule type for each violation and fix
    var it = file_violations.iterator();
    while (it.next()) |entry| {
        const file_path = entry.key_ptr.*;
        const file_violations_list = entry.value_ptr.items;

        // Determine what kind of fixes to apply based on violation types
        var has_import_pattern = false;
        for (file_violations_list) |_| {
            // Find corresponding rule type
            for (rule_types) |rule_type| {
                if (rule_type == .import_pattern) {
                    has_import_pattern = true;
                    break;
                }
            }
        }

        if (has_import_pattern) {
            const fixed = fixImportPatternViolations(allocator, file_path, file_violations_list) catch |err| {
                std.debug.print("Warning: Failed to fix {s}: {s}\n", .{ file_path, @errorName(err) });
                result.failed_count += file_violations_list.len;
                continue;
            };
            if (fixed) {
                result.fixed_count += file_violations_list.len;
            } else {
                result.skipped_count += file_violations_list.len;
            }
        } else {
            // Other rule types not yet auto-fixable
            result.skipped_count += file_violations_list.len;
        }
    }

    return result;
}

/// Fix import pattern violations by removing lines with banned imports.
fn fixImportPatternViolations(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    violations: []const ConformanceViolation,
) !bool {
    // Read the file
    const file = std.fs.openFileAbsolute(file_path, .{}) catch return false;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return false;
    defer allocator.free(content);

    // Build a set of line numbers to remove
    var lines_to_remove = std.AutoHashMap(usize, void).init(allocator);
    defer lines_to_remove.deinit();

    for (violations) |violation| {
        if (violation.line) |line_num| {
            try lines_to_remove.put(line_num, {});
        }
    }

    if (lines_to_remove.count() == 0) {
        return false; // Nothing to fix
    }

    // Filter out the offending lines
    var new_lines = std.ArrayList([]const u8){};
    defer new_lines.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_line: usize = 0;

    while (lines.next()) |line| {
        current_line += 1;

        if (lines_to_remove.contains(current_line)) {
            // Skip this line (it has a banned import)
            continue;
        }

        // Keep this line
        try new_lines.append(allocator, line);
    }

    // Reconstruct the file content
    var new_content = std.ArrayList(u8){};
    defer new_content.deinit(allocator);

    for (new_lines.items, 0..) |line, i| {
        if (i > 0) {
            try new_content.append(allocator, '\n');
        }
        try new_content.appendSlice(allocator, line);
    }

    // If the original content ended with a newline and we have lines,
    // the last "line" from split will be empty - we already included it
    // So we don't need to add an extra newline

    // Write back to file
    const out_file = try std.fs.createFileAbsolute(file_path, .{});
    defer out_file.close();

    try out_file.writeAll(new_content.items);

    return true;
}

test "FixResult init" {
    const allocator = std.testing.allocator;
    const result = FixResult.init(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.fixed_count);
    try std.testing.expectEqual(@as(usize, 0), result.failed_count);
    try std.testing.expectEqual(@as(usize, 0), result.skipped_count);
}

test "fixImportPatternViolations removes banned import lines" {
    const allocator = std.testing.allocator;

    // Create a temporary file with imports
    const tmp = std.testing.tmpDir(.{});
    var dir = tmp.dir;
    const test_file = try dir.createFile("test.js", .{});
    try test_file.writeAll(
        \\import { foo } from './foo';
        \\import React from 'react';
        \\import { bar } from './bar';
        \\
    );
    test_file.close();

    var buf: [1024]u8 = undefined;
    const file_path = try dir.realpath("test.js", &buf);

    // Create a violation for line 2 (React import)
    const violations = [_]ConformanceViolation{
        .{
            .rule_id = "no-react",
            .file_path = file_path,
            .line = 2,
            .column = null,
            .severity = .err,
            .message = "React import not allowed",
            .suggested_fix = null,
        },
    };

    const fixed = try fixImportPatternViolations(allocator, file_path, &violations);
    try std.testing.expect(fixed);

    // Verify the file was modified
    const result_file = try dir.openFile("test.js", .{});
    defer result_file.close();

    const new_content = try result_file.readToEndAlloc(allocator, 1024);
    defer allocator.free(new_content);

    const expected =
        \\import { foo } from './foo';
        \\import { bar } from './bar';
        \\
    ;

    try std.testing.expectEqualStrings(expected, new_content);
}

test "fixImportPatternViolations handles multiple violations" {
    const allocator = std.testing.allocator;

    const tmp = std.testing.tmpDir(.{});
    var dir = tmp.dir;
    const test_file = try dir.createFile("multi.js", .{});
    try test_file.writeAll(
        \\import { foo } from './foo';
        \\import React from 'react';
        \\import { useState } from 'react';
        \\import { bar } from './bar';
        \\
    );
    test_file.close();

    var buf: [1024]u8 = undefined;
    const file_path = try dir.realpath("multi.js", &buf);

    const violations = [_]ConformanceViolation{
        .{
            .rule_id = "no-react",
            .file_path = file_path,
            .line = 2,
            .column = null,
            .severity = .err,
            .message = "React import not allowed",
            .suggested_fix = null,
        },
        .{
            .rule_id = "no-react",
            .file_path = file_path,
            .line = 3,
            .column = null,
            .severity = .err,
            .message = "React import not allowed",
            .suggested_fix = null,
        },
    };

    const fixed = try fixImportPatternViolations(allocator, file_path, &violations);
    try std.testing.expect(fixed);

    const result_file = try dir.openFile("multi.js", .{});
    defer result_file.close();

    const new_content = try result_file.readToEndAlloc(allocator, 1024);
    defer allocator.free(new_content);

    const expected =
        \\import { foo } from './foo';
        \\import { bar } from './bar';
        \\
    ;

    try std.testing.expectEqualStrings(expected, new_content);
}
