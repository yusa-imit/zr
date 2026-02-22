const std = @import("std");
const conformance_types = @import("../conformance/types.zig");
const conformance_engine = @import("../conformance/engine.zig");
const conformance_fixer = @import("../conformance/fixer.zig");
const config_loader = @import("../config/loader.zig");
const output = @import("../output/color.zig");

pub fn cmdConformance(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var fix_mode = false;
    var verbose = false;
    var config_path: ?[]const u8 = null;

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--fix")) {
            fix_mode = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --config requires a path argument\n", .{});
                return 1;
            }
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return 0;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            printHelp();
            return 1;
        }
    }

    // Get workspace root
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.posix.getcwd(&cwd_buf);

    // Load config
    const cfg_path = config_path orelse "zr.toml";
    var config = config_loader.loadFromFile(allocator, cfg_path) catch |err| {
        std.debug.print("Error: Failed to load config from {s}: {s}\n", .{ cfg_path, @errorName(err) });
        return 1;
    };
    defer config.deinit();

    // Check if conformance is configured
    if (config.conformance.rules.len == 0) {
        std.debug.print("Info: No conformance rules configured in {s}\n", .{cfg_path});
        std.debug.print("Add [[conformance.rules]] section to enable conformance checking.\n", .{});
        return 0;
    }

    std.debug.print("Running conformance checks...\n", .{});
    if (verbose) {
        std.debug.print("Workspace: {s}\n", .{cwd});
        std.debug.print("Rules: {d}\n", .{config.conformance.rules.len});
    }

    // Run conformance checks
    var result = try conformance_engine.checkConformance(allocator, &config.conformance, cwd);
    defer result.deinit();

    // Print results
    if (result.violations.len == 0) {
        std.debug.print("\n✓ All conformance checks passed!\n", .{});
        return 0;
    }

    std.debug.print("\nConformance violations found:\n\n", .{});

    for (result.violations) |violation| {
        printViolation(violation, verbose);
    }

    // Print summary
    std.debug.print("\nSummary:\n", .{});
    if (result.error_count > 0) {
        std.debug.print("  Errors: {d}\n", .{result.error_count});
    }
    if (result.warning_count > 0) {
        std.debug.print("  Warnings: {d}\n", .{result.warning_count});
    }
    if (result.info_count > 0) {
        std.debug.print("  Info: {d}\n", .{result.info_count});
    }

    if (fix_mode) {
        std.debug.print("\nAttempting to auto-fix violations...\n", .{});

        // Build list of rule types for each violation
        var rule_types = std.ArrayList(conformance_types.RuleType){};
        defer rule_types.deinit(allocator);

        for (result.violations) |violation| {
            // Find the rule type for this violation
            for (config.conformance.rules) |rule| {
                if (std.mem.eql(u8, rule.id, violation.rule_id)) {
                    try rule_types.append(allocator, rule.type);
                    break;
                }
            }
        }

        const fix_result = try conformance_fixer.applyFixes(allocator, result.violations, rule_types.items);

        std.debug.print("\nFix results:\n", .{});
        std.debug.print("  Fixed: {d}\n", .{fix_result.fixed_count});
        std.debug.print("  Skipped (not auto-fixable): {d}\n", .{fix_result.skipped_count});
        if (fix_result.failed_count > 0) {
            std.debug.print("  Failed: {d}\n", .{fix_result.failed_count});
        }

        if (fix_result.fixed_count > 0) {
            std.debug.print("\n✓ Successfully fixed {d} violation(s).\n", .{fix_result.fixed_count});
            return 0;
        }
    }

    // Return non-zero if there are errors or (fail_on_warning and warnings)
    if (!result.passed(config.conformance.fail_on_warning)) {
        return 1;
    }

    return 0;
}

fn printViolation(violation: conformance_types.ConformanceViolation, verbose: bool) void {
    std.debug.print("{s}: {s}\n", .{ violation.severity.toString(), violation.message });
    std.debug.print("  File: {s}\n", .{violation.file_path});

    if (violation.line) |line| {
        std.debug.print("  Line: {d}\n", .{line});
    }

    if (verbose) {
        std.debug.print("  Rule: {s}\n", .{violation.rule_id});

        if (violation.suggested_fix) |fix| {
            std.debug.print("  Suggested fix: {s}\n", .{fix});
        }
    }

    std.debug.print("\n", .{});
}

fn printHelp() void {
    const help =
        \\Usage: zr conformance [OPTIONS]
        \\
        \\Check code conformance against configured rules.
        \\
        \\Options:
        \\  --fix              Auto-fix violations where possible
        \\  -v, --verbose      Show detailed violation information
        \\  -c, --config PATH  Path to config file (default: zr.toml)
        \\  -h, --help         Show this help message
        \\
        \\Examples:
        \\  zr conformance              # Run all conformance checks
        \\  zr conformance --verbose    # Show detailed rule information
        \\  zr conformance --fix        # Auto-fix violations
        \\
        \\Configuration:
        \\  Add conformance rules to zr.toml:
        \\
        \\  [conformance]
        \\  fail_on_warning = false
        \\  ignore = ["node_modules/**", "dist/**"]
        \\
        \\  [[conformance.rules]]
        \\  id = "no-react-in-backend"
        \\  type = "import_pattern"
        \\  severity = "error"
        \\  scope = "packages/backend/**/*.ts"
        \\  pattern = "react"
        \\  message = "React imports not allowed in backend code"
        \\
        \\  [[conformance.rules]]
        \\  id = "test-file-naming"
        \\  type = "file_naming"
        \\  severity = "warning"
        \\  scope = "**/*.test.ts"
        \\  pattern = "*.test.ts"
        \\  message = "Test files must follow *.test.ts naming convention"
        \\
        \\  [[conformance.rules]]
        \\  id = "file-size-limit"
        \\  type = "file_size"
        \\  severity = "warning"
        \\  scope = "src/**/*.ts"
        \\  message = "File too large"
        \\
        \\  [conformance.rules.config]
        \\  max_bytes = "10000"
        \\
    ;
    std.debug.print("{s}", .{help});
}

test "cmdConformance help" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"--help"};
    const exit_code = try cmdConformance(allocator, &args);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
