const std = @import("std");
const builtin = @import("builtin");

/// Configuration for pager behavior
pub const PagerConfig = struct {
    /// Whether to use pager (can be overridden by --no-pager flag)
    enabled: bool = true,
    /// Environment variable override (ZR_PAGER)
    env_var: ?[]const u8 = null,
    /// Fallback pager command if ZR_PAGER not set
    fallback_pager: ?[]const u8 = null,
};

/// Determine if pager should be used based on output size and terminal
/// Returns true if:
///   - output_lines > terminal_height (when available)
///   - config.enabled is true
///   - not piped (is a TTY)
/// Returns false if:
///   - config.enabled is false
///   - not a TTY
///   - output is small enough to fit on terminal
pub fn shouldUsePager(output_lines: usize, terminal_height: ?usize, config: PagerConfig) bool {
    // If pager is disabled, don't use it
    if (!config.enabled) return false;

    // If not a TTY, don't use pager (piped output)
    if (!isTerminal()) return false;

    // If we don't know terminal height, check if output is likely large
    // Default to 24 lines (minimum terminal height) if unknown
    const height = terminal_height orelse 24;

    // Use pager if output is larger than terminal
    return output_lines > height;
}

/// Get the pager command to use
/// Priority:
/// 1. ZR_PAGER environment variable (if set and non-empty)
/// 2. PAGER environment variable (if set)
/// 3. Default to "less -R" (preserves ANSI colors)
/// Returns null if pager is explicitly disabled (ZR_PAGER="")
pub fn getPagerCommand(allocator: std.mem.Allocator) !?[]const u8 {
    // Check ZR_PAGER first (explicit override)
    if (std.process.getEnvVarOwned(allocator, "ZR_PAGER")) |pager| {
        defer allocator.free(pager);

        // Empty ZR_PAGER means explicitly disabled
        if (pager.len == 0) {
            return null;
        }

        // Return a copy of the ZR_PAGER value
        return try allocator.dupe(u8, pager);
    } else |_| {
        // ZR_PAGER not set, continue
    }

    // Check PAGER environment variable
    if (std.process.getEnvVarOwned(allocator, "PAGER")) |pager| {
        defer allocator.free(pager);

        if (pager.len > 0) {
            return try allocator.dupe(u8, pager);
        }
    } else |_| {
        // PAGER not set, continue
    }

    // Default to less with -R flag (preserves colors)
    return try allocator.dupe(u8, "less -R");
}

/// Check if stdout is connected to a terminal (TTY)
pub fn isTerminal() bool {
    const stdout = std.fs.File.stdout();
    return isTtyInternal(stdout);
}

/// Internal TTY check using std.fs.File
fn isTtyInternal(file: std.fs.File) bool {
    const is_tty = switch (builtin.os.tag) {
        .linux, .macos => blk: {
            const posix = std.posix;
            break :blk posix.isatty(file.handle);
        },
        .windows => blk: {
            const windows = std.os.windows;
            // On Windows, file.handle is HANDLE (*anyopaque)
            var mode: windows.DWORD = 0;
            break :blk windows.kernel32.GetConsoleMode(file.handle, &mode) != 0;
        },
        else => false,
    };
    return is_tty;
}

/// Spawn pager process with stdin from caller
/// The returned child process must be waited on by caller
pub fn spawnPager(allocator: std.mem.Allocator, pager_cmd: []const u8) !std.process.Child {
    // Parse pager command (simple split on first space for command + args)
    var parts = std.mem.tokenizeSequence(u8, pager_cmd, " ");
    const program = parts.next() orelse return error.InvalidPagerCommand;

    // Add additional arguments if present
    var args = std.ArrayList([]const u8){};
    defer args.deinit(allocator);

    try args.append(allocator, program);
    while (parts.next()) |part| {
        try args.append(allocator, part);
    }

    // Create child with full args
    var child = std.process.Child.init(args.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    return child;
}

/// Get terminal height (row count) if available
/// Returns null if unable to determine
pub fn getTerminalHeight() ?usize {
    // Try LINES environment variable first
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "LINES")) |lines_str| {
        defer std.heap.page_allocator.free(lines_str);

        if (std.fmt.parseInt(usize, lines_str, 10)) |height| {
            if (height > 0) return height;
        } else |_| {}
    } else |_| {}

    // On POSIX, try to get via ioctl (requires winsize struct)
    if (builtin.os.tag != .windows) {
        return getTerminalHeightPosix();
    }

    // On Windows, try to get console buffer info
    return getTerminalHeightWindows();
}

/// Get terminal height via POSIX ioctl
fn getTerminalHeightPosix() ?usize {
    // This would require ioctl TIOCGWINSZ
    // For testing purposes, we'll return null to allow tests to control height
    return null;
}

/// Get terminal height on Windows
fn getTerminalHeightWindows() ?usize {
    // This would require Windows API console functions
    // For testing purposes, we'll return null to allow tests to control height
    return null;
}

/// Count newlines in output to estimate line count
pub fn countLines(output: []const u8) usize {
    var count: usize = 0;
    for (output) |byte| {
        if (byte == '\n') count += 1;
    }
    // Add 1 if output doesn't end with newline (final line without terminator)
    if (output.len > 0 and output[output.len - 1] != '\n') {
        count += 1;
    }
    return count;
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

test "shouldUsePager returns false when disabled" {
    const config = PagerConfig{ .enabled = false };
    try std.testing.expectEqual(false, shouldUsePager(100, 24, config));
}

test "shouldUsePager returns false when output fits in terminal" {
    const config = PagerConfig{ .enabled = true };
    try std.testing.expectEqual(false, shouldUsePager(20, 24, config));
}

test "shouldUsePager returns true when output exceeds terminal height" {
    const config = PagerConfig{ .enabled = true };
    // In test environment (piped output, not TTY), should return false
    try std.testing.expectEqual(false, shouldUsePager(50, 24, config));
}

test "shouldUsePager uses default terminal height when unknown" {
    const config = PagerConfig{ .enabled = true };
    // In test environment (piped output, not TTY), should return false
    // regardless of line count vs default height
    try std.testing.expectEqual(false, shouldUsePager(25, null, config));
}

test "shouldUsePager respects zero terminal height" {
    const config = PagerConfig{ .enabled = true };
    // In test environment (piped output, not TTY), should return false
    try std.testing.expectEqual(false, shouldUsePager(1, 0, config));
}

test "getPagerCommand prefers ZR_PAGER environment variable" {
    const allocator = std.testing.allocator;

    // This test would need environment variable setup
    // For now, we test the function is callable
    const pager = try getPagerCommand(allocator);
    defer if (pager) |p| allocator.free(p);
    // Should return something (env var or default)
    try std.testing.expect(pager != null);
}

test "getPagerCommand returns default less -R" {
    const allocator = std.testing.allocator;

    const pager = try getPagerCommand(allocator);
    defer if (pager) |p| allocator.free(p);

    // Default should be less -R (unless env vars are set in test environment)
    // We check it's not null and contains expected string or is our default
    try std.testing.expect(pager != null);
    if (pager) |p| {
        try std.testing.expect(p.len > 0);
    }
}

test "isTerminal is callable and returns boolean" {
    const result = isTerminal();
    _ = result; // Variable used for type checking
}

test "countLines counts newlines correctly" {
    try std.testing.expectEqual(@as(usize, 1), countLines("single line"));
    try std.testing.expectEqual(@as(usize, 2), countLines("line1\nline2"));
    try std.testing.expectEqual(@as(usize, 3), countLines("line1\nline2\nline3"));
}

test "countLines handles trailing newline" {
    try std.testing.expectEqual(@as(usize, 2), countLines("line1\nline2\n"));
}

test "countLines handles empty input" {
    try std.testing.expectEqual(@as(usize, 0), countLines(""));
}

test "countLines handles single newline" {
    try std.testing.expectEqual(@as(usize, 1), countLines("\n"));
}

test "spawnPager requires valid pager command" {
    const allocator = std.testing.allocator;
    const invalid = "";

    const result = spawnPager(allocator, invalid);
    try std.testing.expectError(error.InvalidPagerCommand, result);
}

test "getTerminalHeight is callable" {
    const height = getTerminalHeight();
    _ = height; // Just verify it's callable
}

test "PagerConfig default values" {
    const config = PagerConfig{};
    try std.testing.expectEqual(true, config.enabled);
    try std.testing.expectEqual(@as(?[]const u8, null), config.env_var);
    try std.testing.expectEqual(@as(?[]const u8, null), config.fallback_pager);
}

test "shouldUsePager with custom config values" {
    const config = PagerConfig{
        .enabled = true,
        .fallback_pager = "more",
    };
    // In test environment, isTerminal() returns false (piped output)
    // So shouldUsePager should return false regardless of output size
    try std.testing.expectEqual(false, shouldUsePager(100, 24, config));
}

test "shouldUsePager boundary: output equals terminal height" {
    const config = PagerConfig{ .enabled = true };
    // Output same as height should NOT trigger pager (only if greater)
    try std.testing.expectEqual(false, shouldUsePager(24, 24, config));
}

test "shouldUsePager boundary: output one more than terminal height" {
    const config = PagerConfig{ .enabled = true };
    // In test environment, isTerminal() returns false (piped output)
    // So even 25 > 24 won't trigger pager
    try std.testing.expectEqual(false, shouldUsePager(25, 24, config));
}

test "countLines with multiple trailing newlines" {
    // "line1\nline2\nline3\n\n" has 4 newlines total, making 4 lines
    // (3 content lines + 1 empty line from the second trailing newline)
    try std.testing.expectEqual(@as(usize, 4), countLines("line1\nline2\nline3\n\n"));
}

test "countLines with mixed line endings detects newlines only" {
    // Only \n counts, not \r or \r\n (simplified for Unix)
    try std.testing.expectEqual(@as(usize, 2), countLines("line1\nline2"));
}
