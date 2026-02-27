// src/util/levenshtein.zig
//
// Levenshtein distance calculation for "Did you mean?" suggestions
// Phase 9C — Used for command/task name typo detection

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Calculate the Levenshtein distance between two strings.
/// Uses Wagner-Fischer algorithm with O(min(m,n)) space optimization.
///
/// Returns the minimum number of single-character edits (insertions, deletions, substitutions)
/// required to transform `source` into `target`.
pub fn distance(allocator: Allocator, source: []const u8, target: []const u8) !usize {
    const m = source.len;
    const n = target.len;

    // Edge cases
    if (m == 0) return n;
    if (n == 0) return m;

    // Ensure we iterate over the shorter string for space optimization
    const should_swap = m > n;
    const shorter = if (should_swap) target else source;
    const longer = if (should_swap) source else target;
    const short_len = shorter.len;

    // Use two rows instead of full matrix for O(min(m,n)) space
    var prev_row = try allocator.alloc(usize, short_len + 1);
    defer allocator.free(prev_row);
    var curr_row = try allocator.alloc(usize, short_len + 1);
    defer allocator.free(curr_row);

    // Initialize first row: [0, 1, 2, ..., short_len]
    for (prev_row, 0..) |*cell, i| {
        cell.* = i;
    }

    // Wagner-Fischer algorithm with space optimization
    for (longer, 0..) |long_char, i| {
        curr_row[0] = i + 1;

        for (shorter, 0..) |short_char, j| {
            const cost: usize = if (long_char == short_char) 0 else 1;
            const deletion = prev_row[j + 1] + 1;
            const insertion = curr_row[j] + 1;
            const substitution = prev_row[j] + cost;

            curr_row[j + 1] = @min(@min(deletion, insertion), substitution);
        }

        // Swap rows
        const tmp = prev_row;
        prev_row = curr_row;
        curr_row = tmp;
    }

    return prev_row[short_len];
}

/// Suggestion with its Levenshtein distance from the input
pub const Suggestion = struct {
    name: []const u8,
    distance: usize,
};

/// Find the closest matches for a given input string from a list of candidates.
/// Returns up to `max_suggestions` items, sorted by distance (closest first).
/// Only includes suggestions with distance <= `max_distance`.
pub fn findClosestMatches(
    allocator: Allocator,
    input: []const u8,
    candidates: []const []const u8,
    max_distance: usize,
    max_suggestions: usize,
) ![]Suggestion {
    var suggestions = std.ArrayList(Suggestion){};
    defer suggestions.deinit(allocator);

    // Calculate distances for all candidates
    for (candidates) |candidate| {
        const dist = try distance(allocator, input, candidate);
        if (dist <= max_distance and dist > 0) {
            try suggestions.append(allocator, .{
                .name = candidate,
                .distance = dist,
            });
        }
    }

    // Sort by distance (ascending)
    const items = try suggestions.toOwnedSlice(allocator);
    std.mem.sort(Suggestion, items, {}, struct {
        fn lessThan(_: void, a: Suggestion, b: Suggestion) bool {
            return a.distance < b.distance;
        }
    }.lessThan);

    // Return at most max_suggestions items
    const result_len = @min(items.len, max_suggestions);
    const result = try allocator.alloc(Suggestion, result_len);
    @memcpy(result, items[0..result_len]);
    allocator.free(items);

    return result;
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

test "distance: identical strings" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(0, try distance(allocator, "hello", "hello"));
}

test "distance: empty strings" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(5, try distance(allocator, "", "hello"));
    try std.testing.expectEqual(5, try distance(allocator, "hello", ""));
    try std.testing.expectEqual(0, try distance(allocator, "", ""));
}

test "distance: single character difference" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(1, try distance(allocator, "hello", "hallo")); // substitution
    try std.testing.expectEqual(1, try distance(allocator, "hello", "helo")); // deletion
    try std.testing.expectEqual(1, try distance(allocator, "hello", "helloo")); // insertion
}

test "distance: multiple operations" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(3, try distance(allocator, "kitten", "sitting")); // k→s, e→i, +g
    try std.testing.expectEqual(3, try distance(allocator, "saturday", "sunday")); // tur→un, a→∅
}

test "distance: command typos" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(2, try distance(allocator, "rnu", "run")); // r→r, n→u, u→n (2 subst)
    try std.testing.expectEqual(1, try distance(allocator, "listt", "list")); // extra t
    try std.testing.expectEqual(1, try distance(allocator, "grap", "graph")); // missing h
    try std.testing.expectEqual(2, try distance(allocator, "verison", "version")); // missing s + wrong i
}

test "findClosestMatches: basic" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "run", "list", "graph", "watch", "workflow" };

    const matches = try findClosestMatches(allocator, "rnu", &candidates, 3, 3);
    defer allocator.free(matches);

    try std.testing.expectEqual(1, matches.len);
    try std.testing.expectEqualStrings("run", matches[0].name);
    try std.testing.expectEqual(2, matches[0].distance);
}

test "findClosestMatches: multiple suggestions" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "build", "rebuild", "test", "retest", "bench" };

    const matches = try findClosestMatches(allocator, "biuld", &candidates, 3, 5);
    defer allocator.free(matches);

    try std.testing.expect(matches.len >= 1);
    try std.testing.expectEqualStrings("build", matches[0].name);
    try std.testing.expectEqual(2, matches[0].distance); // i↔u swap
}

test "findClosestMatches: max_distance filter" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "run", "list", "completely_different" };

    const matches = try findClosestMatches(allocator, "rnu", &candidates, 2, 5);
    defer allocator.free(matches);

    // Should only include "run" (distance 1), not "completely_different" (distance > 2)
    try std.testing.expectEqual(1, matches.len);
    try std.testing.expectEqualStrings("run", matches[0].name);
}

test "findClosestMatches: max_suggestions limit" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "aaa", "aab", "aac", "aad", "aae" };

    const matches = try findClosestMatches(allocator, "aaa", &candidates, 2, 2);
    defer allocator.free(matches);

    // Should return at most 2 suggestions, even though more candidates are within distance
    try std.testing.expectEqual(2, matches.len);
}

test "findClosestMatches: no matches within max_distance" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "very_long_command_name", "another_long_one" };

    const matches = try findClosestMatches(allocator, "x", &candidates, 2, 5);
    defer allocator.free(matches);

    try std.testing.expectEqual(0, matches.len);
}

test "findClosestMatches: sorting by distance" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "xaaa", "xaa", "xa", "x" };

    const matches = try findClosestMatches(allocator, "xx", &candidates, 3, 10);
    defer allocator.free(matches);

    // Should be sorted by distance: x(1), xa(1), xaa(2), xaaa(3)
    try std.testing.expect(matches.len >= 2);
    try std.testing.expectEqual(1, matches[0].distance);
    try std.testing.expectEqual(1, matches[1].distance);
}
