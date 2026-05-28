const std = @import("std");
const conformance_types = @import("../conformance/types.zig");
const conformance_engine = @import("../conformance/engine.zig");
const conformance_fixer = @import("../conformance/fixer.zig");
const config_loader = @import("../config/loader.zig");
const output = @import("../output/color.zig");

pub fn cmdConformance(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
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
                try output.printError(ew, use_color,
                    "✗ [Conformance]: --config requires a path argument\n\n  Hint: zr conformance --config path/to/zr.toml\n",
                    .{});
                return 1;
            }
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w, ew, use_color);
            return 0;
        } else {
            try output.printError(ew, use_color,
                "✗ [Conformance]: Unknown argument '{s}'\n\n  Hint: zr conformance --help\n",
                .{arg});
            return 1;
        }
    }

    // Get workspace root
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.posix.getcwd(&cwd_buf);

    // Load config
    const cfg_path = config_path orelse "zr.toml";
    var config = config_loader.loadFromFile(allocator, cfg_path) catch |err| {
        try output.printError(ew, use_color,
            "✗ [Conformance]: Failed to load config from {s}\n\n  Error: {s}\n  Hint: Check that {s} exists and is valid TOML\n",
            .{ cfg_path, @errorName(err), cfg_path });
        return 1;
    };
    defer config.deinit();

    // Check if conformance is configured
    if (config.conformance.rules.len == 0) {
        try output.printInfo(w, use_color, "Info: No conformance rules configured in {s}\n", .{cfg_path});
        try w.print("Add [[conformance.rules]] section to enable conformance checking.\n", .{});
        return 0;
    }

    try w.print("Running conformance checks...\n", .{});
    if (verbose) {
        try output.printDim(w, use_color, "Workspace: {s}\n", .{cwd});
        try output.printDim(w, use_color, "Rules: {d}\n", .{config.conformance.rules.len});
    }

    // Run conformance checks
    var result = try conformance_engine.checkConformance(allocator, &config.conformance, cwd);
    defer result.deinit();

    // Print results
    if (result.violations.len == 0) {
        try w.print("\n", .{});
        try output.printSuccess(w, use_color, "All conformance checks passed!\n", .{});
        return 0;
    }

    try w.print("\nConformance violations found:\n\n", .{});

    for (result.violations) |violation| {
        try printViolation(violation, verbose, w, ew, use_color);
    }

    // Print summary
    try w.print("\n", .{});
    try output.printBold(w, use_color, "Summary:\n", .{});
    if (result.error_count > 0) {
        try output.printError(w, use_color, "  Errors: {d}\n", .{result.error_count});
    }
    if (result.warning_count > 0) {
        try output.printWarning(w, use_color, "  Warnings: {d}\n", .{result.warning_count});
    }
    if (result.info_count > 0) {
        try output.printInfo(w, use_color, "  Info: {d}\n", .{result.info_count});
    }

    if (fix_mode) {
        try w.print("\nAttempting to auto-fix violations...\n", .{});

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

        try w.print("\n", .{});
        try output.printBold(w, use_color, "Fix results:\n", .{});
        try w.print("  Fixed: {d}\n", .{fix_result.fixed_count});
        try output.printDim(w, use_color, "  Skipped (not auto-fixable): {d}\n", .{fix_result.skipped_count});
        if (fix_result.failed_count > 0) {
            try output.printError(w, use_color, "  Failed: {d}\n", .{fix_result.failed_count});
        }

        if (fix_result.fixed_count > 0) {
            try w.print("\n", .{});
            try output.printSuccess(w, use_color, "Successfully fixed {d} violation(s).\n", .{fix_result.fixed_count});
            return 0;
        }
    }

    // Return non-zero if there are errors or (fail_on_warning and warnings)
    if (!result.passed(config.conformance.fail_on_warning)) {
        return 1;
    }

    return 0;
}

fn printViolation(
    violation: conformance_types.ConformanceViolation,
    verbose: bool,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !void {
    _ = ew; // Error writer not needed here but kept for consistency

    const severity_str = violation.severity.toString();
    if (std.mem.eql(u8, severity_str, "error")) {
        try output.printError(w, use_color, "{s}: ", .{severity_str});
    } else if (std.mem.eql(u8, severity_str, "warning")) {
        try output.printWarning(w, use_color, "{s}: ", .{severity_str});
    } else {
        try output.printInfo(w, use_color, "{s}: ", .{severity_str});
    }
    try w.print("{s}\n", .{violation.message});
    try output.printDim(w, use_color, "  File: {s}\n", .{violation.file_path});

    if (violation.line) |line| {
        try output.printDim(w, use_color, "  Line: {d}\n", .{line});
    }

    if (verbose) {
        try output.printDim(w, use_color, "  Rule: {s}\n", .{violation.rule_id});

        if (violation.suggested_fix) |fix| {
            try output.printInfo(w, use_color, "  Suggested fix: {s}\n", .{fix});
        }
    }

    try w.print("\n", .{});
}

fn printHelp(w: *std.Io.Writer, ew: *std.Io.Writer, use_color: bool) !void {
    _ = ew; // Error writer not needed for help
    _ = use_color; // Color not needed for help text (plain output)

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
    try w.print("{s}", .{help});
}

test "cmdConformance help" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.Writer.fixed(&err_buf);

    const args = [_][]const u8{"--help"};
    const exit_code = try cmdConformance(allocator, &args, &out_w, &err_w, false);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
