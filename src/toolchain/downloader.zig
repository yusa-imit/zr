const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const ToolKind = types.ToolKind;
const ToolVersion = types.ToolVersion;
const lang_registry = @import("../lang/registry.zig");
const lang_provider = @import("../lang/provider.zig");

/// Re-export for backward compatibility
pub const DownloadSpec = lang_provider.DownloadSpec;
pub const ArchiveType = lang_provider.ArchiveType;

/// Determine the appropriate download URL and archive type for a tool version
/// Now delegates to the LanguageProvider system
pub fn resolveDownloadUrl(allocator: std.mem.Allocator, kind: ToolKind, version: ToolVersion) !DownloadSpec {
    const provider = lang_registry.getProvider(kind);
    const platform = lang_provider.PlatformInfo.current();
    return try provider.resolveDownloadUrl(allocator, version, platform);
}

// Note: Language-specific download URL resolution logic has been moved to src/lang/*.zig providers

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
pub fn extractArchive(allocator: std.mem.Allocator, archive_path: []const u8, dest_dir: []const u8, archive_type: ArchiveType) !void {
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

    // Now using GitHub releases from Adoptium
    try std.testing.expect(std.mem.startsWith(u8, spec.url, "https://github.com/adoptium/temurin"));
}
