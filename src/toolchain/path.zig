const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const installer = @import("installer.zig");
const ToolKind = types.ToolKind;
const ToolVersion = types.ToolVersion;
const ToolSpec = types.ToolSpec;

/// Build the PATH environment variable with toolchain bin directories prepended.
/// Returns an owned string that must be freed by the caller.
/// Format: toolchain_bins:current_PATH
pub fn buildPathWithToolchains(
    allocator: std.mem.Allocator,
    toolchains: []const ToolSpec,
    current_path: ?[]const u8,
) ![]u8 {
    if (toolchains.len == 0) {
        // No toolchains, return current PATH or empty
        if (current_path) |path| {
            return allocator.dupe(u8, path);
        }
        return allocator.dupe(u8, "");
    }

    // Build list of bin directories for each toolchain
    var bin_dirs = std.ArrayList([]const u8){};
    defer {
        for (bin_dirs.items) |dir| allocator.free(dir);
        bin_dirs.deinit(allocator);
    }

    for (toolchains) |spec| {
        const bin_dir = try getToolchainBinDir(allocator, spec.kind, spec.version);
        try bin_dirs.append(allocator, bin_dir);
    }

    // Calculate total length needed
    const path_separator = if (builtin.os.tag == .windows) ";" else ":";
    var total_len: usize = 0;
    for (bin_dirs.items) |dir| {
        total_len += dir.len + path_separator.len;
    }
    if (current_path) |path| {
        total_len += path.len;
    } else {
        // Remove trailing separator if no current path
        if (total_len > 0) total_len -= path_separator.len;
    }

    // Build the final PATH string
    var result = try std.ArrayList(u8).initCapacity(allocator, total_len);
    errdefer result.deinit(allocator);

    for (bin_dirs.items) |dir| {
        try result.appendSlice(allocator, dir);
        try result.appendSlice(allocator, path_separator);
    }

    if (current_path) |path| {
        try result.appendSlice(allocator, path);
    } else if (result.items.len > 0) {
        // Remove trailing separator
        _ = result.pop();
    }

    return result.toOwnedSlice(allocator);
}

/// Get the bin directory for a specific toolchain installation.
/// Returns an owned string that must be freed by the caller.
fn getToolchainBinDir(allocator: std.mem.Allocator, kind: ToolKind, version: ToolVersion) ![]u8 {
    const install_dir = try installer.getToolDir(allocator, kind, version);
    defer allocator.free(install_dir);

    // Different toolchains have different bin directory structures
    return switch (kind) {
        .node => try std.fmt.allocPrint(allocator, "{s}/bin", .{install_dir}),
        .python => try std.fmt.allocPrint(allocator, "{s}/bin", .{install_dir}),
        .zig => allocator.dupe(u8, install_dir), // Zig binaries are in root
        .go => try std.fmt.allocPrint(allocator, "{s}/bin", .{install_dir}),
        .rust => try std.fmt.allocPrint(allocator, "{s}/bin", .{install_dir}),
        .deno => allocator.dupe(u8, install_dir), // Deno binary is in root
        .bun => allocator.dupe(u8, install_dir), // Bun binary is in root
        .java => try std.fmt.allocPrint(allocator, "{s}/bin", .{install_dir}),
    };
}

/// Build environment variable overrides for toolchains.
/// Returns an array of [key, value] pairs that must be freed by the caller.
/// Includes PATH and any toolchain-specific env vars (e.g., JAVA_HOME).
pub fn buildToolchainEnv(
    allocator: std.mem.Allocator,
    toolchains: []const ToolSpec,
    base_env: ?[]const [2][]const u8,
) ![][2][]u8 {
    var result = std.ArrayList([2][]u8){};
    errdefer {
        for (result.items) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        result.deinit(allocator);
    }

    // Copy base env vars
    if (base_env) |env_pairs| {
        for (env_pairs) |pair| {
            const key = try allocator.dupe(u8, pair[0]);
            errdefer allocator.free(key);
            const val = try allocator.dupe(u8, pair[1]);
            errdefer allocator.free(val);
            try result.append(allocator, .{ key, val });
        }
    }

    // Get current PATH from environment
    const current_path = std.posix.getenv("PATH");

    // Build new PATH with toolchain bins prepended
    const new_path = try buildPathWithToolchains(allocator, toolchains, current_path);
    errdefer allocator.free(new_path);

    const path_key = try allocator.dupe(u8, "PATH");
    errdefer allocator.free(path_key);
    try result.append(allocator, .{ path_key, new_path });

    // Add toolchain-specific environment variables
    for (toolchains) |spec| {
        switch (spec.kind) {
            .java => {
                // Set JAVA_HOME for Java toolchain
                const install_dir = try installer.getToolDir(allocator, spec.kind, spec.version);
                errdefer allocator.free(install_dir);

                const java_home_key = try allocator.dupe(u8, "JAVA_HOME");
                errdefer allocator.free(java_home_key);
                try result.append(allocator, .{ java_home_key, install_dir });
            },
            .go => {
                // Set GOROOT for Go toolchain
                const install_dir = try installer.getToolDir(allocator, spec.kind, spec.version);
                errdefer allocator.free(install_dir);

                const goroot_key = try allocator.dupe(u8, "GOROOT");
                errdefer allocator.free(goroot_key);
                try result.append(allocator, .{ goroot_key, install_dir });
            },
            else => {
                // Other toolchains don't need special env vars
            },
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Free environment variable array returned by buildToolchainEnv.
pub fn freeToolchainEnv(allocator: std.mem.Allocator, env: [][2][]u8) void {
    for (env) |pair| {
        allocator.free(pair[0]);
        allocator.free(pair[1]);
    }
    allocator.free(env);
}

test "buildPathWithToolchains with no toolchains" {
    const allocator = std.testing.allocator;
    const toolchains: []const ToolSpec = &.{};

    const path = try buildPathWithToolchains(allocator, toolchains, "/usr/bin:/bin");
    defer allocator.free(path);

    try std.testing.expectEqualStrings("/usr/bin:/bin", path);
}

test "buildPathWithToolchains with single toolchain" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("20.11.1");
    const toolchains = &[_]ToolSpec{.{
        .kind = .node,
        .version = version,
    }};

    const path = try buildPathWithToolchains(allocator, toolchains, "/usr/bin:/bin");
    defer allocator.free(path);

    // Should prepend node bin dir
    try std.testing.expect(std.mem.indexOf(u8, path, "node/20.11.1/bin") != null);
    try std.testing.expect(std.mem.endsWith(u8, path, "/usr/bin:/bin"));
}

test "buildPathWithToolchains with multiple toolchains" {
    const allocator = std.testing.allocator;
    const node_version = try ToolVersion.parse("20.11.1");
    const python_version = try ToolVersion.parse("3.12.1");
    const toolchains = &[_]ToolSpec{
        .{ .kind = .node, .version = node_version },
        .{ .kind = .python, .version = python_version },
    };

    const path = try buildPathWithToolchains(allocator, toolchains, "/usr/bin");
    defer allocator.free(path);

    // Should have both toolchain bin dirs before system PATH
    try std.testing.expect(std.mem.indexOf(u8, path, "node/20.11.1/bin") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "python/3.12.1/bin") != null);
    try std.testing.expect(std.mem.endsWith(u8, path, "/usr/bin"));
}

test "buildPathWithToolchains with null current path" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("20.11.1");
    const toolchains = &[_]ToolSpec{.{
        .kind = .node,
        .version = version,
    }};

    const path = try buildPathWithToolchains(allocator, toolchains, null);
    defer allocator.free(path);

    // Should only have node bin dir, no trailing separator
    try std.testing.expect(std.mem.indexOf(u8, path, "node/20.11.1/bin") != null);
    try std.testing.expect(!std.mem.endsWith(u8, path, ":"));
}

test "getToolchainBinDir for different toolchains" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("1.0.0");

    // Node: has /bin subdirectory
    {
        const bin_dir = try getToolchainBinDir(allocator, .node, version);
        defer allocator.free(bin_dir);
        try std.testing.expect(std.mem.endsWith(u8, bin_dir, "/node/1.0.0/bin"));
    }

    // Zig: binary in root directory
    {
        const bin_dir = try getToolchainBinDir(allocator, .zig, version);
        defer allocator.free(bin_dir);
        try std.testing.expect(std.mem.endsWith(u8, bin_dir, "/zig/1.0.0"));
    }

    // Deno: binary in root directory
    {
        const bin_dir = try getToolchainBinDir(allocator, .deno, version);
        defer allocator.free(bin_dir);
        try std.testing.expect(std.mem.endsWith(u8, bin_dir, "/deno/1.0.0"));
    }
}

test "buildToolchainEnv creates PATH override" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("20.11.1");
    const toolchains = &[_]ToolSpec{.{
        .kind = .node,
        .version = version,
    }};

    const env = try buildToolchainEnv(allocator, toolchains, null);
    defer freeToolchainEnv(allocator, env);

    // Should have at least PATH
    try std.testing.expect(env.len >= 1);

    // Find PATH entry
    var found_path = false;
    for (env) |pair| {
        if (std.mem.eql(u8, pair[0], "PATH")) {
            found_path = true;
            try std.testing.expect(std.mem.indexOf(u8, pair[1], "node/20.11.1/bin") != null);
            break;
        }
    }
    try std.testing.expect(found_path);
}

test "buildToolchainEnv with Java sets JAVA_HOME" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("21.0.1");
    const toolchains = &[_]ToolSpec{.{
        .kind = .java,
        .version = version,
    }};

    const env = try buildToolchainEnv(allocator, toolchains, null);
    defer freeToolchainEnv(allocator, env);

    // Should have PATH and JAVA_HOME
    var found_java_home = false;
    for (env) |pair| {
        if (std.mem.eql(u8, pair[0], "JAVA_HOME")) {
            found_java_home = true;
            try std.testing.expect(std.mem.indexOf(u8, pair[1], "java/21.0.1") != null);
            break;
        }
    }
    try std.testing.expect(found_java_home);
}

test "buildToolchainEnv with Go sets GOROOT" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("1.21.5");
    const toolchains = &[_]ToolSpec{.{
        .kind = .go,
        .version = version,
    }};

    const env = try buildToolchainEnv(allocator, toolchains, null);
    defer freeToolchainEnv(allocator, env);

    // Should have PATH and GOROOT
    var found_goroot = false;
    for (env) |pair| {
        if (std.mem.eql(u8, pair[0], "GOROOT")) {
            found_goroot = true;
            try std.testing.expect(std.mem.indexOf(u8, pair[1], "go/1.21.5") != null);
            break;
        }
    }
    try std.testing.expect(found_goroot);
}

test "buildToolchainEnv preserves base env vars" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("20.11.1");
    const toolchains = &[_]ToolSpec{.{
        .kind = .node,
        .version = version,
    }};

    const base_env = &[_][2][]const u8{
        .{ "FOO", "bar" },
        .{ "BAZ", "qux" },
    };

    const env = try buildToolchainEnv(allocator, toolchains, base_env);
    defer freeToolchainEnv(allocator, env);

    // Should preserve base env vars
    var found_foo = false;
    var found_baz = false;
    for (env) |pair| {
        if (std.mem.eql(u8, pair[0], "FOO")) {
            found_foo = true;
            try std.testing.expectEqualStrings("bar", pair[1]);
        }
        if (std.mem.eql(u8, pair[0], "BAZ")) {
            found_baz = true;
            try std.testing.expectEqualStrings("qux", pair[1]);
        }
    }
    try std.testing.expect(found_foo);
    try std.testing.expect(found_baz);
}
