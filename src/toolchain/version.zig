const std = @import("std");
const semver = @import("../util/semver.zig");
const constraint_mod = @import("../config/constraint.zig");

const Version = semver.Version;
const VersionConstraint = constraint_mod.VersionConstraint;

/// Configuration for detecting tool version
pub const VersionDetectionConfig = struct {
    /// Tool name (e.g., "node", "python", "zig")
    tool_name: []const u8,
    /// Version command to run (e.g., "--version", "-v", "version")
    version_command: []const u8 = "--version",
    /// Whether to use a subcommand (e.g., "tool version" vs "tool --version")
    use_subcommand: bool = false,
};

/// Detect installed tool version by running version command
/// Caller owns the returned Version
pub fn detectVersion(allocator: std.mem.Allocator, config: VersionDetectionConfig) !Version {
    var child_process = std.process.Child.init(
        if (config.use_subcommand)
            &[_][]const u8{ config.tool_name, config.version_command }
        else
            &[_][]const u8{ config.tool_name, config.version_command },
        allocator,
    );

    child_process.stdout_behavior = .Pipe;
    child_process.stderr_behavior = .Pipe;

    try child_process.spawn();
    defer _ = child_process.wait() catch {};

    const stdout = try child_process.stdout.?.readToEndAlloc(allocator, 8192);
    defer allocator.free(stdout);

    return parseVersionOutput(allocator, stdout);
}

/// Parse version string from tool output
/// Supported formats:
///   - "node v18.17.0" → 18.17.0
///   - "python 3.11.4" → 3.11.4
///   - "zig 0.15.2" → 0.15.2
///   - "rustc 1.71.0 (8ede3aae2 2023-07-12)" → 1.71.0
pub fn parseVersionOutput(allocator: std.mem.Allocator, output: []const u8) !Version {
    _ = allocator; // May be needed for future string processing

    const trimmed = std.mem.trim(u8, output, " \t\n\r");

    // Split by whitespace and look for semantic version pattern
    var parts = std.mem.splitScalar(u8, trimmed, ' ');

    while (parts.next()) |part| {
        // Try to parse each part as a version
        // Handle leading 'v' prefix
        const version_str = if (std.mem.startsWith(u8, part, "v"))
            part[1..]
        else
            part;

        if (Version.parse(version_str)) |version| {
            return version;
        } else |_| {
            // Not a version, continue searching
            continue;
        }
    }

    return error.NoVersionFound;
}

/// Check if installed tool version satisfies constraint
pub fn checkConstraint(allocator: std.mem.Allocator, config: VersionDetectionConfig, constraint_str: []const u8) !bool {
    const version = try detectVersion(allocator, config);
    var constraint = try constraint_mod.parseConstraint(allocator, constraint_str);
    defer constraint.deinit(allocator);

    return constraint_mod.satisfies(version, constraint);
}

/// Error types for version operations
pub const VersionError = error{
    NoVersionFound,
    InvalidVersionFormat,
    ToolNotFound,
    CommandFailed,
};

// ───────────────────────────────────────────────────────────────────────────
// Tests
// ───────────────────────────────────────────────────────────────────────────

test "parseVersionOutput: extract version from node output" {
    const output = "v18.17.0";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 18), version.major);
    try std.testing.expectEqual(@as(u32, 17), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: node output with whitespace" {
    const output = "v18.17.0\n";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 18), version.major);
}

test "parseVersionOutput: python output format" {
    const output = "Python 3.11.4";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 3), version.major);
    try std.testing.expectEqual(@as(u32, 11), version.minor);
    try std.testing.expectEqual(@as(u32, 4), version.patch);
}

test "parseVersionOutput: zig output format" {
    const output = "zig 0.15.2";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 0), version.major);
    try std.testing.expectEqual(@as(u32, 15), version.minor);
    try std.testing.expectEqual(@as(u32, 2), version.patch);
}

test "parseVersionOutput: rustc output with git hash" {
    const output = "rustc 1.71.0 (8ede3aae2 2023-07-12)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 71), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: exact version without prefix" {
    const output = "1.2.3";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 2), version.minor);
    try std.testing.expectEqual(@as(u32, 3), version.patch);
}

test "parseVersionOutput: version with leading 'v'" {
    const output = "v1.2.3";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
}

test "parseVersionOutput: go output format" {
    const output = "go version go1.21.0 linux/amd64";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 21), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: java output format" {
    const output = "openjdk version \"17.0.2\" 2022-01-18";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 17), version.major);
    try std.testing.expectEqual(@as(u32, 0), version.minor);
    try std.testing.expectEqual(@as(u32, 2), version.patch);
}

test "parseVersionOutput: ruby output format" {
    const output = "ruby 3.2.1 (2023-02-08 revision 31819e82d8) [x86_64-linux]";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 3), version.major);
    try std.testing.expectEqual(@as(u32, 2), version.minor);
    try std.testing.expectEqual(@as(u32, 1), version.patch);
}

test "parseVersionOutput: with leading whitespace" {
    const output = "   v2.0.0   ";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 2), version.major);
}

test "parseVersionOutput: first version in multiline output" {
    const output = "Node.js v18.17.0\nBuilt for x64\nWith OpenSSL 3.0.0";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 18), version.major);
}

test "parseVersionOutput: version with rc suffix is not parsed" {
    const output = "1.0.0-rc1 development";
    const result = parseVersionOutput(std.testing.allocator, output);

    // Should fail because 1.0.0-rc1 is not a valid semver for our parser
    try std.testing.expectError(error.NoVersionFound, result);
}

test "parseVersionOutput: empty output returns error" {
    const output = "";
    const result = parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectError(error.NoVersionFound, result);
}

test "parseVersionOutput: whitespace only returns error" {
    const output = "   \n\t  ";
    const result = parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectError(error.NoVersionFound, result);
}

test "parseVersionOutput: no version string in output" {
    const output = "This tool has no version information";
    const result = parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectError(error.NoVersionFound, result);
}

test "parseVersionOutput: multiple versions picks first" {
    const output = "1.2.3 or later, compatible with 2.0.0";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 2), version.minor);
    try std.testing.expectEqual(@as(u32, 3), version.patch);
}

test "parseVersionOutput: version after tool name" {
    const output = "gcc 11.2.0 (Ubuntu 11.2.0-19ubuntu1)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 11), version.major);
}

test "parseVersionOutput: lowercase 'v' prefix" {
    const output = "v0.15.2";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 0), version.major);
    try std.testing.expectEqual(@as(u32, 15), version.minor);
}

test "parseVersionOutput: large version numbers" {
    const output = "999.888.777";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 999), version.major);
    try std.testing.expectEqual(@as(u32, 888), version.minor);
    try std.testing.expectEqual(@as(u32, 777), version.patch);
}

test "parseVersionOutput: zero version" {
    const output = "0.0.0";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 0), version.major);
    try std.testing.expectEqual(@as(u32, 0), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: version with tabs and newlines" {
    const output = "v1.2.3\t\n";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
}

test "VersionDetectionConfig: default values" {
    const config = VersionDetectionConfig{
        .tool_name = "node",
    };

    try std.testing.expectEqualStrings("--version", config.version_command);
    try std.testing.expectEqual(false, config.use_subcommand);
}

test "VersionDetectionConfig: custom version command" {
    const config = VersionDetectionConfig{
        .tool_name = "python",
        .version_command = "-V",
    };

    try std.testing.expectEqualStrings("-V", config.version_command);
}

test "VersionDetectionConfig: subcommand mode" {
    const config = VersionDetectionConfig{
        .tool_name = "git",
        .version_command = "version",
        .use_subcommand = true,
    };

    try std.testing.expect(config.use_subcommand);
}

test "parseVersionOutput: npm output format" {
    const output = "8.19.4";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 8), version.major);
    try std.testing.expectEqual(@as(u32, 19), version.minor);
    try std.testing.expectEqual(@as(u32, 4), version.patch);
}

test "parseVersionOutput: dotnet output" {
    const output = ".NET 7.0.0";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 7), version.major);
    try std.testing.expectEqual(@as(u32, 0), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: perl output" {
    const output = "This is perl 5, version 36, subversion 0 (v5.36.0) built for x86_64";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 5), version.major);
    try std.testing.expectEqual(@as(u32, 36), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: php output" {
    const output = "PHP 8.2.0 (cli) (built: Dec 22 2022 20:39:50)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 8), version.major);
    try std.testing.expectEqual(@as(u32, 2), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: cmake output" {
    const output = "cmake version 3.24.1";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 3), version.major);
    try std.testing.expectEqual(@as(u32, 24), version.minor);
    try std.testing.expectEqual(@as(u32, 1), version.patch);
}

test "parseVersionOutput: swift output" {
    const output = "swift-driver version: 1.75.0 Apple Swift version 5.8.0 (swiftlang- clang-1403.0.22.11.100)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 75), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: with tabs between tool and version" {
    const output = "node\tv18.17.0";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 18), version.major);
}

test "parseVersionOutput: version with parentheses" {
    const output = "version (1.2.3)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 2), version.minor);
    try std.testing.expectEqual(@as(u32, 3), version.patch);
}

test "parseVersionOutput: version after equals sign" {
    const output = "GCC version = 11.3.0";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 11), version.major);
    try std.testing.expectEqual(@as(u32, 3), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}

test "parseVersionOutput: invalid version format in output" {
    const output = "1.2.3.4.5";
    const result = parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectError(error.NoVersionFound, result);
}

test "parseVersionOutput: version with non-numeric components fails" {
    const output = "v1.2.x";
    const result = parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectError(error.NoVersionFound, result);
}

test "parseVersionOutput: multiple whitespace between parts" {
    const output = "python    3.11.4    (main)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 3), version.major);
}

test "parseVersionOutput: quoted version string" {
    const output = "version: \"2.5.1\" (latest)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 2), version.major);
    try std.testing.expectEqual(@as(u32, 5), version.minor);
    try std.testing.expectEqual(@as(u32, 1), version.patch);
}

test "parseVersionOutput: complex rustc output with date" {
    const output = "rustc 1.72.1 (d5c2e9c34 2023-09-13)";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 72), version.minor);
    try std.testing.expectEqual(@as(u32, 1), version.patch);
}

test "parseVersionOutput: docker-style version" {
    const output = "Docker version 20.10.12, build e91ed57";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 20), version.major);
    try std.testing.expectEqual(@as(u32, 10), version.minor);
    try std.testing.expectEqual(@as(u32, 12), version.patch);
}

test "parseVersionOutput: kubernetes version" {
    const output = "Client Version: version.Info{Major:\"1\", Minor:\"27\", GitVersion:\"v1.27.0\"}";
    const version = try parseVersionOutput(std.testing.allocator, output);

    try std.testing.expectEqual(@as(u32, 1), version.major);
    try std.testing.expectEqual(@as(u32, 27), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
}
