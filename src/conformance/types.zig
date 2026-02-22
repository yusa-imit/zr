const std = @import("std");

/// Severity level for conformance violations.
pub const Severity = enum {
    err,
    warning,
    info,

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warning => "warning",
            .info => "info",
        };
    }
};

/// Type of conformance rule.
pub const RuleType = enum {
    /// File import pattern restriction (e.g., "no React imports in backend")
    import_pattern,
    /// File naming convention (e.g., "*.test.ts for tests")
    file_naming,
    /// Maximum file size limit
    file_size,
    /// Maximum directory depth
    directory_depth,
    /// Allowed/banned file extensions in specific directories
    file_extension,

    pub fn toString(self: RuleType) []const u8 {
        return switch (self) {
            .import_pattern => "import_pattern",
            .file_naming => "file_naming",
            .file_size => "file_size",
            .directory_depth => "directory_depth",
            .file_extension => "file_extension",
        };
    }
};

/// A conformance rule definition.
pub const ConformanceRule = struct {
    /// Unique identifier for this rule.
    id: []const u8,
    /// Type of rule.
    type: RuleType,
    /// Severity level (error, warning, info).
    severity: Severity,
    /// Scope pattern (glob) where this rule applies.
    scope: []const u8,
    /// Pattern to match against (depends on rule type).
    pattern: ?[]const u8,
    /// Message to display on violation.
    message: []const u8,
    /// Whether this rule can be auto-fixed.
    fixable: bool,
    /// Configuration parameters (JSON-like key-value pairs).
    config: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, id: []const u8, rule_type: RuleType, severity: Severity, scope: []const u8, message: []const u8) ConformanceRule {
        return .{
            .id = id,
            .type = rule_type,
            .severity = severity,
            .scope = scope,
            .pattern = null,
            .message = message,
            .fixable = false,
            .config = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ConformanceRule) void {
        var it = self.config.iterator();
        while (it.next()) |entry| {
            self.config.allocator.free(entry.key_ptr.*);
            self.config.allocator.free(entry.value_ptr.*);
        }
        self.config.deinit();
    }
};

/// A conformance violation (file-level or project-level).
pub const ConformanceViolation = struct {
    /// Rule that was violated.
    rule_id: []const u8,
    /// File path where violation occurred.
    file_path: []const u8,
    /// Line number (if applicable).
    line: ?usize,
    /// Column number (if applicable).
    column: ?usize,
    /// Severity level.
    severity: Severity,
    /// Description of the violation.
    message: []const u8,
    /// Suggested fix (if auto-fixable).
    suggested_fix: ?[]const u8,
};

/// Configuration for conformance engine.
pub const ConformanceConfig = struct {
    /// List of conformance rules.
    rules: []ConformanceRule,
    /// Whether to fail on warnings (default: false).
    fail_on_warning: bool,
    /// Paths to ignore (glob patterns).
    ignore: [][]const u8,

    pub fn init(_: std.mem.Allocator) ConformanceConfig {
        return .{
            .rules = &[_]ConformanceRule{},
            .fail_on_warning = false,
            .ignore = &[_][]const u8{},
        };
    }

    pub fn deinit(self: *ConformanceConfig, allocator: std.mem.Allocator) void {
        for (self.rules) |*rule| {
            rule.deinit();
        }
        if (self.rules.len > 0) allocator.free(self.rules);
        for (self.ignore) |item| {
            allocator.free(item);
        }
        if (self.ignore.len > 0) allocator.free(self.ignore);
    }
};

/// Result of conformance check.
pub const ConformanceResult = struct {
    violations: []ConformanceViolation,
    error_count: usize,
    warning_count: usize,
    info_count: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConformanceResult {
        return .{
            .violations = &[_]ConformanceViolation{},
            .error_count = 0,
            .warning_count = 0,
            .info_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConformanceResult) void {
        for (self.violations) |*v| {
            self.allocator.free(v.rule_id);
            self.allocator.free(v.file_path);
            self.allocator.free(v.message);
            if (v.suggested_fix) |fix| {
                self.allocator.free(fix);
            }
        }
        if (self.violations.len > 0) {
            self.allocator.free(self.violations);
        }
    }

    pub fn passed(self: *const ConformanceResult, fail_on_warning: bool) bool {
        if (self.error_count > 0) return false;
        if (fail_on_warning and self.warning_count > 0) return false;
        return true;
    }
};

test "ConformanceRule init and deinit" {
    var rule = ConformanceRule.init(
        std.testing.allocator,
        "test-rule",
        .import_pattern,
        .err,
        "src/**/*.ts",
        "Test rule message",
    );
    defer rule.deinit();

    try std.testing.expectEqualStrings("test-rule", rule.id);
    try std.testing.expectEqual(RuleType.import_pattern, rule.type);
    try std.testing.expectEqual(Severity.err, rule.severity);
}

test "ConformanceResult init and passed" {
    var result = ConformanceResult.init(std.testing.allocator);
    defer result.deinit();

    try std.testing.expect(result.passed(false));
    try std.testing.expect(result.passed(true));

    result.warning_count = 1;
    try std.testing.expect(result.passed(false));
    try std.testing.expect(!result.passed(true));

    result.error_count = 1;
    try std.testing.expect(!result.passed(false));
    try std.testing.expect(!result.passed(true));
}

test "Severity toString" {
    try std.testing.expectEqualStrings("error", Severity.err.toString());
    try std.testing.expectEqualStrings("warning", Severity.warning.toString());
    try std.testing.expectEqualStrings("info", Severity.info.toString());
}
