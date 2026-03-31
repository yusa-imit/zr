const std = @import("std");
const config_types = @import("../config/types.zig");
const MatrixConfig = config_types.MatrixConfig;
const MatrixDim = config_types.MatrixDim;
const MatrixExclusion = config_types.MatrixExclusion;

/// A single matrix combination: variable name -> value mapping.
pub const MatrixCombination = struct {
    variables: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) MatrixCombination {
        return .{ .variables = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *MatrixCombination) void {
        var it = self.variables.iterator();
        while (it.next()) |entry| {
            self.variables.allocator.free(entry.key_ptr.*);
            self.variables.allocator.free(entry.value_ptr.*);
        }
        self.variables.deinit();
    }

    pub fn clone(self: *const MatrixCombination, allocator: std.mem.Allocator) !MatrixCombination {
        var new_combo = MatrixCombination.init(allocator);
        var it = self.variables.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = try allocator.dupe(u8, entry.value_ptr.*);
            try new_combo.variables.put(key, value);
        }
        return new_combo;
    }
};

/// Expand a matrix configuration into all possible combinations.
/// Returns a list of MatrixCombination instances (caller owns memory).
pub fn expandMatrix(
    allocator: std.mem.Allocator,
    matrix: *const MatrixConfig,
) ![]MatrixCombination {
    if (matrix.dimensions.len == 0) {
        return &[_]MatrixCombination{};
    }

    // Start with empty combinations
    var combinations = std.ArrayList(MatrixCombination).init(allocator);
    errdefer {
        for (combinations.items) |*combo| combo.deinit();
        combinations.deinit();
    }

    // Add initial empty combination
    try combinations.append(MatrixCombination.init(allocator));

    // For each dimension, multiply current combinations by dimension values
    for (matrix.dimensions) |dim| {
        var new_combinations = std.ArrayList(MatrixCombination).init(allocator);
        errdefer {
            for (new_combinations.items) |*combo| combo.deinit();
            new_combinations.deinit();
        }

        for (combinations.items) |*existing_combo| {
            for (dim.values) |value| {
                var new_combo = try existing_combo.clone(allocator);
                errdefer new_combo.deinit();

                const key = try allocator.dupe(u8, dim.key);
                const val = try allocator.dupe(u8, value);
                try new_combo.variables.put(key, val);

                try new_combinations.append(new_combo);
            }
        }

        // Free old combinations
        for (combinations.items) |*combo| combo.deinit();
        combinations.deinit();

        combinations = new_combinations;
    }

    // Apply exclusions
    var filtered = std.ArrayList(MatrixCombination).init(allocator);
    errdefer {
        for (filtered.items) |*combo| combo.deinit();
        filtered.deinit();
    }

    for (combinations.items) |*combo| {
        if (isExcluded(combo, matrix.exclude)) {
            combo.deinit();
        } else {
            try filtered.append(combo.*);
        }
    }
    combinations.deinit();

    return filtered.toOwnedSlice();
}

/// Check if a combination matches any exclusion rule.
fn isExcluded(combo: *const MatrixCombination, exclusions: []const MatrixExclusion) bool {
    for (exclusions) |excl| {
        var matches = true;
        var it = excl.conditions.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const expected_value = entry.value_ptr.*;
            const actual_value = combo.variables.get(key) orelse {
                matches = false;
                break;
            };
            if (!std.mem.eql(u8, expected_value, actual_value)) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

// ============ Unit Tests ============

test "MatrixCombination init and deinit" {
    var combo = MatrixCombination.init(std.testing.allocator);
    defer combo.deinit();

    try std.testing.expectEqual(@as(usize, 0), combo.variables.count());
}

test "MatrixCombination clone" {
    var combo = MatrixCombination.init(std.testing.allocator);
    defer combo.deinit();

    const key = try std.testing.allocator.dupe(u8, "os");
    const value = try std.testing.allocator.dupe(u8, "linux");
    try combo.variables.put(key, value);

    var cloned = try combo.clone(std.testing.allocator);
    defer cloned.deinit();

    try std.testing.expectEqual(@as(usize, 1), cloned.variables.count());
    const cloned_value = cloned.variables.get("os").?;
    try std.testing.expectEqualStrings("linux", cloned_value);
}

test "expandMatrix with no dimensions" {
    const matrix = MatrixConfig{
        .dimensions = &[_]MatrixDim{},
        .exclude = &[_]MatrixExclusion{},
    };

    const combinations = try expandMatrix(std.testing.allocator, &matrix);
    defer std.testing.allocator.free(combinations);

    try std.testing.expectEqual(@as(usize, 0), combinations.len);
}

test "expandMatrix with single dimension" {
    const dim_values = [_][]const u8{ "linux", "macos", "windows" };
    const dim = MatrixDim{
        .key = "os",
        .values = &dim_values,
    };
    const dimensions = [_]MatrixDim{dim};

    const matrix = MatrixConfig{
        .dimensions = &dimensions,
        .exclude = &[_]MatrixExclusion{},
    };

    const combinations = try expandMatrix(std.testing.allocator, &matrix);
    defer {
        for (combinations) |*combo| combo.deinit();
        std.testing.allocator.free(combinations);
    }

    try std.testing.expectEqual(@as(usize, 3), combinations.len);
    try std.testing.expectEqualStrings("linux", combinations[0].variables.get("os").?);
    try std.testing.expectEqualStrings("macos", combinations[1].variables.get("os").?);
    try std.testing.expectEqualStrings("windows", combinations[2].variables.get("os").?);
}

test "expandMatrix with two dimensions (2x3 = 6 combinations)" {
    const os_values = [_][]const u8{ "linux", "macos" };
    const os_dim = MatrixDim{
        .key = "os",
        .values = &os_values,
    };
    const version_values = [_][]const u8{ "1.0", "2.0", "3.0" };
    const version_dim = MatrixDim{
        .key = "version",
        .values = &version_values,
    };
    const dimensions = [_]MatrixDim{ os_dim, version_dim };

    const matrix = MatrixConfig{
        .dimensions = &dimensions,
        .exclude = &[_]MatrixExclusion{},
    };

    const combinations = try expandMatrix(std.testing.allocator, &matrix);
    defer {
        for (combinations) |*combo| combo.deinit();
        std.testing.allocator.free(combinations);
    }

    try std.testing.expectEqual(@as(usize, 6), combinations.len);
    // Verify first combination (linux + 1.0)
    try std.testing.expectEqualStrings("linux", combinations[0].variables.get("os").?);
    try std.testing.expectEqualStrings("1.0", combinations[0].variables.get("version").?);
}

test "expandMatrix with exclusions" {
    const os_values = [_][]const u8{ "linux", "macos" };
    const os_dim = MatrixDim{
        .key = "os",
        .values = &os_values,
    };
    const version_values = [_][]const u8{ "1.0", "2.0" };
    const version_dim = MatrixDim{
        .key = "version",
        .values = &version_values,
    };
    const dimensions = [_]MatrixDim{ os_dim, version_dim };

    // Exclude macos + 1.0
    var excl_conditions = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer excl_conditions.deinit();
    try excl_conditions.put("os", "macos");
    try excl_conditions.put("version", "1.0");

    const exclusion = MatrixExclusion{ .conditions = excl_conditions };
    const exclusions = [_]MatrixExclusion{exclusion};

    const matrix = MatrixConfig{
        .dimensions = &dimensions,
        .exclude = &exclusions,
    };

    const combinations = try expandMatrix(std.testing.allocator, &matrix);
    defer {
        for (combinations) |*combo| combo.deinit();
        std.testing.allocator.free(combinations);
    }

    // Should have 3 combinations (4 total - 1 excluded)
    try std.testing.expectEqual(@as(usize, 3), combinations.len);

    // Verify macos+1.0 is excluded
    for (combinations) |combo| {
        const os = combo.variables.get("os").?;
        const version = combo.variables.get("version").?;
        const is_excluded = std.mem.eql(u8, os, "macos") and std.mem.eql(u8, version, "1.0");
        try std.testing.expect(!is_excluded);
    }
}

test "isExcluded with matching conditions" {
    var combo = MatrixCombination.init(std.testing.allocator);
    defer combo.deinit();

    const os_key = try std.testing.allocator.dupe(u8, "os");
    const os_val = try std.testing.allocator.dupe(u8, "macos");
    try combo.variables.put(os_key, os_val);

    const ver_key = try std.testing.allocator.dupe(u8, "version");
    const ver_val = try std.testing.allocator.dupe(u8, "1.0");
    try combo.variables.put(ver_key, ver_val);

    var excl_conditions = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer excl_conditions.deinit();
    try excl_conditions.put("os", "macos");
    try excl_conditions.put("version", "1.0");

    const exclusion = MatrixExclusion{ .conditions = excl_conditions };
    const exclusions = [_]MatrixExclusion{exclusion};

    try std.testing.expect(isExcluded(&combo, &exclusions));
}

test "isExcluded with non-matching conditions" {
    var combo = MatrixCombination.init(std.testing.allocator);
    defer combo.deinit();

    const os_key = try std.testing.allocator.dupe(u8, "os");
    const os_val = try std.testing.allocator.dupe(u8, "linux");
    try combo.variables.put(os_key, os_val);

    const ver_key = try std.testing.allocator.dupe(u8, "version");
    const ver_val = try std.testing.allocator.dupe(u8, "1.0");
    try combo.variables.put(ver_key, ver_val);

    var excl_conditions = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer excl_conditions.deinit();
    try excl_conditions.put("os", "macos");
    try excl_conditions.put("version", "1.0");

    const exclusion = MatrixExclusion{ .conditions = excl_conditions };
    const exclusions = [_]MatrixExclusion{exclusion};

    try std.testing.expect(!isExcluded(&combo, &exclusions));
}
