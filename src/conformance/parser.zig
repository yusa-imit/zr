const std = @import("std");
const types = @import("types.zig");

const ConformanceConfig = types.ConformanceConfig;
const ConformanceRule = types.ConformanceRule;
const RuleType = types.RuleType;
const Severity = types.Severity;

/// Parse conformance config from TOML table.
pub fn parseConformanceConfig(allocator: std.mem.Allocator, table: anytype) !ConformanceConfig {
    var config = ConformanceConfig.init(allocator);
    errdefer config.deinit(allocator);

    // Parse fail_on_warning
    if (table.get("fail_on_warning")) |value| {
        if (value == .boolean) {
            config.fail_on_warning = value.boolean;
        }
    }

    // Parse ignore patterns
    if (table.get("ignore")) |value| {
        if (value == .array) {
            var ignore_list = std.ArrayList([]const u8){};
            errdefer {
                for (ignore_list.items) |item| allocator.free(item);
                ignore_list.deinit(allocator);
            }

            for (value.array.items) |item| {
                if (item == .string) {
                    const pattern = try allocator.dupe(u8, item.string);
                    try ignore_list.append(allocator, pattern);
                }
            }

            config.ignore = try ignore_list.toOwnedSlice(allocator);
        }
    }

    // Parse rules array
    if (table.get("rules")) |value| {
        if (value == .array) {
            var rules_list = std.ArrayList(ConformanceRule){};
            errdefer {
                for (rules_list.items) |*rule| rule.deinit();
                rules_list.deinit(allocator);
            }

            for (value.array.items) |rule_value| {
                if (rule_value == .table) {
                    const rule = try parseRule(allocator, rule_value.table);
                    try rules_list.append(allocator, rule);
                }
            }

            config.rules = try rules_list.toOwnedSlice(allocator);
        }
    }

    return config;
}

/// Parse a single conformance rule from TOML.
fn parseRule(allocator: std.mem.Allocator, table: anytype) !ConformanceRule {
    // Required fields
    const id = if (table.get("id")) |v| blk: {
        if (v == .string) break :blk v.string else return error.MissingRuleId;
    } else return error.MissingRuleId;

    const type_str = if (table.get("type")) |v| blk: {
        if (v == .string) break :blk v.string else return error.MissingRuleType;
    } else return error.MissingRuleType;

    const scope = if (table.get("scope")) |v| blk: {
        if (v == .string) break :blk v.string else return error.MissingRuleScope;
    } else return error.MissingRuleScope;

    const message = if (table.get("message")) |v| blk: {
        if (v == .string) break :blk v.string else return error.MissingRuleMessage;
    } else return error.MissingRuleMessage;

    // Parse rule type
    const rule_type = parseRuleType(type_str) orelse return error.InvalidRuleType;

    // Parse severity (default: err)
    var severity = Severity.err;
    if (table.get("severity")) |v| {
        if (v == .string) {
            severity = parseSeverity(v.string) orelse .err;
        }
    }

    var rule = ConformanceRule.init(allocator, id, rule_type, severity, scope, message);
    errdefer rule.deinit();

    // Optional pattern field
    if (table.get("pattern")) |v| {
        if (v == .string) {
            rule.pattern = v.string;
        }
    }

    // Optional fixable field
    if (table.get("fixable")) |v| {
        if (v == .boolean) {
            rule.fixable = v.boolean;
        }
    }

    // Parse config object (key-value pairs)
    if (table.get("config")) |config_value| {
        if (config_value == .table) {
            var it = config_value.table.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                errdefer allocator.free(key);

                const val_str = if (entry.value_ptr.* == .string)
                    entry.value_ptr.*.string
                else if (entry.value_ptr.* == .integer)
                    try std.fmt.allocPrint(allocator, "{d}", .{entry.value_ptr.*.integer})
                else
                    continue;

                const val = try allocator.dupe(u8, val_str);
                errdefer allocator.free(val);

                try rule.config.put(key, val);
            }
        }
    }

    return rule;
}

/// Parse rule type from string.
fn parseRuleType(s: []const u8) ?RuleType {
    if (std.mem.eql(u8, s, "import_pattern")) return .import_pattern;
    if (std.mem.eql(u8, s, "file_naming")) return .file_naming;
    if (std.mem.eql(u8, s, "file_size")) return .file_size;
    if (std.mem.eql(u8, s, "directory_depth")) return .directory_depth;
    if (std.mem.eql(u8, s, "file_extension")) return .file_extension;
    return null;
}

/// Parse severity from string.
fn parseSeverity(s: []const u8) ?Severity {
    if (std.mem.eql(u8, s, "error")) return .err;
    if (std.mem.eql(u8, s, "warning")) return .warning;
    if (std.mem.eql(u8, s, "info")) return .info;
    return null;
}

test "parseRuleType" {
    try std.testing.expectEqual(RuleType.import_pattern, parseRuleType("import_pattern").?);
    try std.testing.expectEqual(RuleType.file_naming, parseRuleType("file_naming").?);
    try std.testing.expectEqual(@as(?RuleType, null), parseRuleType("invalid"));
}

test "parseSeverity" {
    try std.testing.expectEqual(Severity.err, parseSeverity("error").?);
    try std.testing.expectEqual(Severity.warning, parseSeverity("warning").?);
    try std.testing.expectEqual(Severity.info, parseSeverity("info").?);
    try std.testing.expectEqual(@as(?Severity, null), parseSeverity("invalid"));
}
