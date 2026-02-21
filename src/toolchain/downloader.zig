const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const ToolKind = types.ToolKind;
const ToolVersion = types.ToolVersion;

/// Download URL resolver for different toolchains
pub const DownloadSpec = struct {
    url: []const u8,
    archive_type: ArchiveType,

    pub const ArchiveType = enum {
        tar_gz,
        tar_xz,
        zip,
    };
};

/// Determine the appropriate download URL and archive type for a tool version
pub fn resolveDownloadUrl(allocator: std.mem.Allocator, kind: ToolKind, version: ToolVersion) !DownloadSpec {
    const os_tag = builtin.os.tag;
    const arch_tag = builtin.cpu.arch;

    // Map platform to download platform strings
    const platform_str = switch (os_tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "win",
        else => return error.UnsupportedPlatform,
    };

    const arch_str = switch (arch_tag) {
        .x86_64 => "x64",
        .aarch64 => "arm64",
        else => return error.UnsupportedArchitecture,
    };

    return switch (kind) {
        .node => resolveNodeUrl(allocator, version, platform_str, arch_str),
        .python => resolvePythonUrl(allocator, version, platform_str, arch_str),
        .zig => resolveZigUrl(allocator, version, platform_str, arch_str),
        .go => resolveGoUrl(allocator, version, platform_str, arch_str),
        .rust => resolveRustUrl(allocator, version, platform_str, arch_str),
        .deno => resolveDenoUrl(allocator, version, platform_str, arch_str),
        .bun => resolveBunUrl(allocator, version, platform_str, arch_str),
        .java => resolveJavaUrl(allocator, version, platform_str, arch_str),
    };
}

/// Node.js download URLs
/// Format: https://nodejs.org/dist/v{version}/node-v{version}-{platform}-{arch}.tar.gz
fn resolveNodeUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const archive_ext = if (std.mem.eql(u8, platform, "win")) "zip" else "tar.gz";
    const archive_type: DownloadSpec.ArchiveType = if (std.mem.eql(u8, platform, "win")) .zip else .tar_gz;

    const url = try std.fmt.allocPrint(allocator, "https://nodejs.org/dist/v{s}/node-v{s}-{s}-{s}.{s}", .{
        version_str,
        version_str,
        platform,
        arch,
        archive_ext,
    });

    return .{
        .url = url,
        .archive_type = archive_type,
    };
}

/// Python download URLs (using python-build-standalone)
/// Format: https://github.com/indygreg/python-build-standalone/releases/download/{tag}/cpython-{version}+{tag}-{platform}-{...}.tar.gz
fn resolvePythonUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    // Map to python-build-standalone platform strings
    const pbs_platform = if (std.mem.eql(u8, platform, "darwin"))
        "apple-darwin"
    else if (std.mem.eql(u8, platform, "linux"))
        "unknown-linux-gnu"
    else if (std.mem.eql(u8, platform, "win"))
        "pc-windows-msvc-shared"
    else
        return error.UnsupportedPlatform;

    const pbs_arch = if (std.mem.eql(u8, arch, "x64"))
        "x86_64"
    else if (std.mem.eql(u8, arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    // Using python-build-standalone release tag "20240107"
    const tag = "20240107";

    const url = try std.fmt.allocPrint(allocator, "https://github.com/indygreg/python-build-standalone/releases/download/{s}/cpython-{s}+{s}-{s}-{s}.tar.gz", .{
        tag,
        version_str,
        tag,
        pbs_arch,
        pbs_platform,
    });

    return .{
        .url = url,
        .archive_type = .tar_gz,
    };
}

/// Zig download URLs
/// Format: https://ziglang.org/download/{version}/zig-{platform}-{arch}-{version}.tar.xz
fn resolveZigUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const zig_platform = if (std.mem.eql(u8, platform, "darwin"))
        "macos"
    else if (std.mem.eql(u8, platform, "win"))
        "windows"
    else
        platform;

    const zig_arch = if (std.mem.eql(u8, arch, "x64"))
        "x86_64"
    else if (std.mem.eql(u8, arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    const archive_ext = if (std.mem.eql(u8, platform, "win")) "zip" else "tar.xz";
    const archive_type: DownloadSpec.ArchiveType = if (std.mem.eql(u8, platform, "win")) .zip else .tar_xz;

    const url = try std.fmt.allocPrint(allocator, "https://ziglang.org/download/{s}/zig-{s}-{s}-{s}.{s}", .{
        version_str,
        zig_platform,
        zig_arch,
        version_str,
        archive_ext,
    });

    return .{
        .url = url,
        .archive_type = archive_type,
    };
}

/// Go download URLs
/// Format: https://go.dev/dl/go{version}.{platform}-{arch}.tar.gz
fn resolveGoUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const go_arch = if (std.mem.eql(u8, arch, "x64"))
        "amd64"
    else if (std.mem.eql(u8, arch, "arm64"))
        "arm64"
    else
        return error.UnsupportedArchitecture;

    const archive_ext = if (std.mem.eql(u8, platform, "win")) "zip" else "tar.gz";
    const archive_type: DownloadSpec.ArchiveType = if (std.mem.eql(u8, platform, "win")) .zip else .tar_gz;

    const url = try std.fmt.allocPrint(allocator, "https://go.dev/dl/go{s}.{s}-{s}.{s}", .{
        version_str,
        platform,
        go_arch,
        archive_ext,
    });

    return .{
        .url = url,
        .archive_type = archive_type,
    };
}

/// Rust download URLs (using rustup standalone installers)
/// Format: https://static.rust-lang.org/dist/rust-{version}-{arch}-{platform}.tar.gz
fn resolveRustUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const rust_platform = if (std.mem.eql(u8, platform, "darwin"))
        "apple-darwin"
    else if (std.mem.eql(u8, platform, "linux"))
        "unknown-linux-gnu"
    else if (std.mem.eql(u8, platform, "win"))
        "pc-windows-msvc"
    else
        return error.UnsupportedPlatform;

    const rust_arch = if (std.mem.eql(u8, arch, "x64"))
        "x86_64"
    else if (std.mem.eql(u8, arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    const archive_ext = if (std.mem.eql(u8, platform, "win")) "zip" else "tar.gz";
    const archive_type: DownloadSpec.ArchiveType = if (std.mem.eql(u8, platform, "win")) .zip else .tar_gz;

    const url = try std.fmt.allocPrint(allocator, "https://static.rust-lang.org/dist/rust-{s}-{s}-{s}.{s}", .{
        version_str,
        rust_arch,
        rust_platform,
        archive_ext,
    });

    return .{
        .url = url,
        .archive_type = archive_type,
    };
}

/// Deno download URLs
/// Format: https://github.com/denoland/deno/releases/download/v{version}/deno-{arch}-{platform}.zip
fn resolveDenoUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const deno_platform = if (std.mem.eql(u8, platform, "darwin"))
        "apple-darwin"
    else if (std.mem.eql(u8, platform, "linux"))
        "unknown-linux-gnu"
    else if (std.mem.eql(u8, platform, "win"))
        "pc-windows-msvc"
    else
        return error.UnsupportedPlatform;

    const deno_arch = if (std.mem.eql(u8, arch, "x64"))
        "x86_64"
    else if (std.mem.eql(u8, arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    const url = try std.fmt.allocPrint(allocator, "https://github.com/denoland/deno/releases/download/v{s}/deno-{s}-{s}.zip", .{
        version_str,
        deno_arch,
        deno_platform,
    });

    return .{
        .url = url,
        .archive_type = .zip,
    };
}

/// Bun download URLs
/// Format: https://github.com/oven-sh/bun/releases/download/bun-v{version}/bun-{platform}-{arch}.zip
fn resolveBunUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const bun_arch = if (std.mem.eql(u8, arch, "x64"))
        "x64"
    else if (std.mem.eql(u8, arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    const url = try std.fmt.allocPrint(allocator, "https://github.com/oven-sh/bun/releases/download/bun-v{s}/bun-{s}-{s}.zip", .{
        version_str,
        platform,
        bun_arch,
    });

    return .{
        .url = url,
        .archive_type = .zip,
    };
}

/// Java download URLs (using Adoptium/Temurin)
/// Format: https://api.adoptium.net/v3/binary/version/jdk-{version}/linux/x64/jdk/hotspot/normal/eclipse?project=jdk
fn resolveJavaUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: []const u8, arch: []const u8) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const adoptium_arch = if (std.mem.eql(u8, arch, "x64"))
        "x64"
    else if (std.mem.eql(u8, arch, "arm64"))
        "aarch64"
    else
        return error.UnsupportedArchitecture;

    const archive_type: DownloadSpec.ArchiveType = if (std.mem.eql(u8, platform, "win")) .zip else .tar_gz;

    // Using Adoptium API for latest patch version of the major.minor
    const url = try std.fmt.allocPrint(allocator, "https://api.adoptium.net/v3/binary/version/jdk-{s}/{s}/{s}/jdk/hotspot/normal/eclipse?project=jdk", .{
        version_str,
        platform,
        adoptium_arch,
    });

    return .{
        .url = url,
        .archive_type = archive_type,
    };
}

/// Download a file from a URL to a destination path
pub fn downloadFile(allocator: std.mem.Allocator, url: []const u8, dest_path: []const u8) !void {
    // Use curl via std.process.Child for now
    // Zig std.http.Client would be ideal but has limitations in 0.15
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "curl", "-L", "-f", "-o", dest_path, url },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("Download failed: {s}\n", .{result.stderr});
        return error.DownloadFailed;
    }
}

/// Extract an archive to a destination directory
pub fn extractArchive(allocator: std.mem.Allocator, archive_path: []const u8, dest_dir: []const u8, archive_type: DownloadSpec.ArchiveType) !void {
    const os_tag = builtin.os.tag;

    switch (archive_type) {
        .tar_gz => {
            const result = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "tar", "-xzf", archive_path, "-C", dest_dir, "--strip-components=1" },
            });
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                std.debug.print("Extraction failed: {s}\n", .{result.stderr});
                return error.ExtractionFailed;
            }
        },
        .tar_xz => {
            const result = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "tar", "-xJf", archive_path, "-C", dest_dir, "--strip-components=1" },
            });
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                std.debug.print("Extraction failed: {s}\n", .{result.stderr});
                return error.ExtractionFailed;
            }
        },
        .zip => {
            if (os_tag == .windows) {
                // Use PowerShell on Windows
                const result = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &.{ "powershell", "-Command", "Expand-Archive", "-Path", archive_path, "-DestinationPath", dest_dir },
                });
                defer allocator.free(result.stdout);
                defer allocator.free(result.stderr);

                if (result.term.Exited != 0) {
                    return error.ExtractionFailed;
                }
            } else {
                // Use unzip on Unix-like systems
                const result = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &.{ "unzip", "-q", archive_path, "-d", dest_dir },
                });
                defer allocator.free(result.stdout);
                defer allocator.free(result.stderr);

                if (result.term.Exited != 0) {
                    return error.ExtractionFailed;
                }
            }
        },
    }
}

test "resolveDownloadUrl for Node.js" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("20.11.1");

    const spec = try resolveDownloadUrl(allocator, .node, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://nodejs.org/dist/v20.11.1/"));
}

test "resolveDownloadUrl for Python" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("3.12.1");

    const spec = try resolveDownloadUrl(allocator, .python, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://github.com/indygreg/python-build-standalone/"));
}

test "resolveDownloadUrl for Zig" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("0.15.2");

    const spec = try resolveDownloadUrl(allocator, .zig, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://ziglang.org/download/"));
}

test "resolveDownloadUrl for Go" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("1.21.5");

    const spec = try resolveDownloadUrl(allocator, .go, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://go.dev/dl/"));
}

test "resolveDownloadUrl for Rust" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("1.75.0");

    const spec = try resolveDownloadUrl(allocator, .rust, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://static.rust-lang.org/dist/"));
}

test "resolveDownloadUrl for Deno" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("1.40.0");

    const spec = try resolveDownloadUrl(allocator, .deno, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://github.com/denoland/deno/releases/"));
}

test "resolveDownloadUrl for Bun" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("1.0.21");

    const spec = try resolveDownloadUrl(allocator, .bun, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://github.com/oven-sh/bun/releases/"));
}

test "resolveDownloadUrl for Java" {
    const allocator = std.testing.allocator;
    const version = try ToolVersion.parse("21.0.1");

    const spec = try resolveDownloadUrl(allocator, .java, version);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://api.adoptium.net/v3/binary/"));
}
