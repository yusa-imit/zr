# Adding a Language Provider

This guide shows how to add support for a new programming language toolchain to zr.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step-by-Step Guide](#step-by-step-guide)
- [LanguageProvider Interface](#languageprovider-interface)
- [Example: Ruby Provider](#example-ruby-provider)
- [Testing](#testing)
- [Registration](#registration)
- [Best Practices](#best-practices)

---

## Overview

zr's language provider system allows automatic toolchain management for different programming languages. Each language provider implements a standard interface that handles:

1. **Download resolution** — where to download the toolchain
2. **Version fetching** — latest stable version detection
3. **Binary paths** — OS-specific binary locations
4. **Environment setup** — PATH and environment variables
5. **Project detection** — identifying projects using this language
6. **Task extraction** — auto-generating tasks from build files

Adding a new language requires creating **one file** in `src/lang/<language>.zig`.

---

## Prerequisites

- Zig 0.15.2 or later
- Basic understanding of Zig structs and error handling
- Knowledge of the target language's:
  - Download URLs and versioning scheme
  - Binary structure (directories, executables)
  - Project markers (e.g., `Gemfile` for Ruby, `Cargo.toml` for Rust)
  - Build tools (e.g., `bundle`, `cargo`)

---

## Step-by-Step Guide

### 1. Create Provider File

Create `src/lang/<language>.zig` (e.g., `src/lang/ruby.zig`).

**Template:**
```zig
const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

/// Ruby toolchain provider
pub const RubyProvider: LanguageProvider = .{
    .name = "ruby",
    .resolveDownloadUrl = resolveDownloadUrl,
    .fetchLatestVersion = fetchLatestVersion,
    .getBinaryPath = getBinaryPath,
    .getEnvironmentVars = getEnvironmentVars,  // or null if not needed
    .detectProject = detectProject,
    .extractTasks = extractTasks,
};

// Implement 6 required functions below...
```

---

### 2. Implement `resolveDownloadUrl`

Map version and platform to a download URL.

**Signature:**
```zig
fn resolveDownloadUrl(
    allocator: std.mem.Allocator,
    version: ToolVersion,
    platform: PlatformInfo
) !DownloadSpec
```

**Example (Ruby):**
```zig
fn resolveDownloadUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: PlatformInfo) !DownloadSpec {
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    // Ruby uses tar.gz on all platforms
    const url = try std.fmt.allocPrint(allocator,
        "https://cache.ruby-lang.org/pub/ruby/{d}.{d}/ruby-{s}.tar.gz",
        .{ version.major, version.minor, version_str }
    );

    return .{
        .url = url,
        .archive_type = .tar_gz,
    };
}
```

**Notes:**
- `PlatformInfo.os` values: `"linux"`, `"macos"`, `"win"`
- `PlatformInfo.arch` values: `"x86_64"`, `"aarch64"`, `"arm"`, `"i386"`
- `ArchiveType`: `.tar_gz`, `.zip`, `.tar_xz`, `.tar_bz2`
- Returned URL is owned by caller (allocated with `allocator`)

---

### 3. Implement `fetchLatestVersion`

Fetch the latest stable version from an official source.

**Signature:**
```zig
fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion
```

**Example (Ruby):**
```zig
fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    // Ruby publishes versions at https://www.ruby-lang.org/en/downloads/releases/
    // For simplicity, use a known-good API or static list
    const url = "https://cache.ruby-lang.org/pub/ruby/index.txt";
    const data = try provider.fetchUrl(allocator, url);
    defer allocator.free(data);

    // Parse the index file to find latest stable version
    var lines = std.mem.split(u8, data, "\n");
    var latest: ?ToolVersion = null;

    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "ruby-") != null) {
            // Extract version (e.g., "ruby-3.2.2.tar.gz" -> "3.2.2")
            var parts = std.mem.split(u8, line, "-");
            _ = parts.next(); // skip "ruby"
            if (parts.next()) |ver_part| {
                const ver_str = std.mem.trim(u8, ver_part, ".tar.gz");
                if (ToolVersion.parse(ver_str)) |ver| {
                    if (latest == null or ver.compare(latest.?) == .greater) {
                        latest = ver;
                    }
                } else |_| {}
            }
        }
    }

    return latest orelse error.VersionNotFound;
}
```

**Helper:**
- Use `provider.fetchUrl(allocator, url)` for HTTP GET
- Returns owned slice (caller must free)

---

### 4. Implement `getBinaryPath`

Return the relative path to the main binary within the extracted archive.

**Signature:**
```zig
fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8
```

**Example (Ruby):**
```zig
fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "bin/ruby.exe");
    } else {
        return try allocator.dupe(u8, "bin/ruby");
    }
}
```

**Notes:**
- Return owned slice (caller frees)
- Path is relative to toolchain install directory (e.g., `~/.zr/toolchains/ruby-3.2.2/`)

---

### 5. Implement `getEnvironmentVars` (Optional)

Return environment variables to inject when using this toolchain.

**Signature:**
```zig
fn getEnvironmentVars(
    allocator: std.mem.Allocator,
    toolchain_path: []const u8,
    platform: PlatformInfo
) ![][2][]const u8
```

**Example (Ruby — add GEM_HOME):**
```zig
fn getEnvironmentVars(allocator: std.mem.Allocator, toolchain_path: []const u8, platform: PlatformInfo) ![][2][]const u8 {
    _ = platform; // unused

    const gem_home = try std.fmt.allocPrint(allocator, "{s}/gems", .{toolchain_path});

    var env_vars = try allocator.alloc([2][]const u8, 1);
    env_vars[0] = .{ try allocator.dupe(u8, "GEM_HOME"), gem_home };

    return env_vars;
}
```

**If not needed:**
```zig
pub const RubyProvider: LanguageProvider = .{
    // ...
    .getEnvironmentVars = null,  // No custom env vars
    // ...
};
```

---

### 6. Implement `detectProject`

Detect if a project uses this language by checking for marker files.

**Signature:**
```zig
fn detectProject(allocator: std.mem.Allocator, dir_path: []const u8) !ProjectInfo
```

**Example (Ruby — check for Gemfile):**
```zig
fn detectProject(allocator: std.mem.Allocator, dir_path: []const u8) !ProjectInfo {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch {
        return .{ .detected = false, .confidence = 0, .files_found = &.{} };
    };
    defer dir.close();

    var confidence: u8 = 0;
    var files = std.ArrayList([]const u8){};
    defer files.deinit(allocator);

    // Check for Gemfile
    if (dir.access("Gemfile", .{})) |_| {
        confidence += 60;
        try files.append(allocator, "Gemfile");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for Rakefile
    if (dir.access("Rakefile", .{})) |_| {
        confidence += 20;
        try files.append(allocator, "Rakefile");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Check for .ruby-version
    if (dir.access(".ruby-version", .{})) |_| {
        confidence += 10;
        try files.append(allocator, ".ruby-version");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    return .{
        .detected = confidence > 0,
        .confidence = @min(confidence, 100),
        .files_found = try files.toOwnedSlice(allocator),
    };
}
```

**Guidelines:**
- Higher weight for primary markers (e.g., `Gemfile` → 50-60%)
- Medium weight for common files (e.g., `Rakefile` → 20%)
- Low weight for optional markers (e.g., `.ruby-version` → 10%)
- Total confidence capped at 100

---

### 7. Implement `extractTasks`

Parse build files to suggest tasks for `zr init --detect`.

**Signature:**
```zig
fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion
```

**Example (Ruby — extract Rake tasks):**
```zig
fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch return &.{};
    defer dir.close();

    // Check for Rakefile
    const file = dir.openFile("Rakefile", .{}) catch return &.{};
    defer file.close();

    // Simple extraction: look for task definitions
    // More sophisticated parsing can be done with a full Rakefile parser
    var tasks = std.ArrayList(LanguageProvider.TaskSuggestion){};
    errdefer tasks.deinit(allocator);

    // Common Ruby/Rails tasks
    const common_tasks = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "test", .desc = "Run tests" },
        .{ .name = "spec", .desc = "Run RSpec tests" },
        .{ .name = "db:migrate", .desc = "Run database migrations" },
        .{ .name = "assets:precompile", .desc = "Precompile assets" },
    };

    for (common_tasks) |task_info| {
        const name = try allocator.dupe(u8, task_info.name);
        const cmd = try std.fmt.allocPrint(allocator, "bundle exec rake {s}", .{task_info.name});
        const desc = try allocator.dupe(u8, task_info.desc);

        try tasks.append(allocator, .{
            .name = name,
            .command = cmd,
            .description = desc,
        });
    }

    return try tasks.toOwnedSlice(allocator);
}
```

**Notes:**
- Return empty slice `&.{}` if no tasks found
- Each `TaskSuggestion` has:
  - `name`: Task identifier (e.g., `"test"`)
  - `command`: Shell command (e.g., `"bundle exec rake test"`)
  - `description`: Human-readable description
- All fields are owned (caller frees)

---

### 8. Add Tests

Add unit tests at the bottom of your provider file:

```zig
test "resolveDownloadUrl" {
    const allocator = std.testing.allocator;
    const version = ToolVersion{ .major = 3, .minor = 2, .patch = 2 };
    const platform = PlatformInfo{ .os = "linux", .arch = "x86_64" };

    const spec = try resolveDownloadUrl(allocator, version, platform);
    defer allocator.free(spec.url);

    try std.testing.expect(std.mem.indexOf(u8, spec.url, "ruby-3.2.2") != null);
    try std.testing.expectEqual(provider.ArchiveType.tar_gz, spec.archive_type);
}

test "getBinaryPath" {
    const allocator = std.testing.allocator;
    const linux = PlatformInfo{ .os = "linux", .arch = "x86_64" };
    const windows = PlatformInfo{ .os = "win", .arch = "x86_64" };

    const linux_path = try getBinaryPath(allocator, linux);
    defer allocator.free(linux_path);
    try std.testing.expectEqualStrings("bin/ruby", linux_path);

    const win_path = try getBinaryPath(allocator, windows);
    defer allocator.free(win_path);
    try std.testing.expectEqualStrings("bin/ruby.exe", win_path);
}

test "detectProject" {
    // Test with a temporary directory containing a Gemfile
    // (More complex test setup needed for real projects)
}
```

Run tests:
```bash
zig build test
```

---

## LanguageProvider Interface

Full interface definition from `src/lang/provider.zig`:

```zig
pub const LanguageProvider = struct {
    name: []const u8,
    resolveDownloadUrl: *const fn (std.mem.Allocator, ToolVersion, PlatformInfo) anyerror!DownloadSpec,
    fetchLatestVersion: *const fn (std.mem.Allocator) anyerror!ToolVersion,
    getBinaryPath: *const fn (std.mem.Allocator, PlatformInfo) anyerror![]const u8,
    getEnvironmentVars: ?*const fn (std.mem.Allocator, []const u8, PlatformInfo) anyerror![][2][]const u8,
    detectProject: *const fn (std.mem.Allocator, []const u8) anyerror!ProjectInfo,
    extractTasks: *const fn (std.mem.Allocator, []const u8) anyerror![]TaskSuggestion,
};

pub const DownloadSpec = struct {
    url: []const u8,  // Owned by caller
    archive_type: ArchiveType,
};

pub const ArchiveType = enum {
    tar_gz,
    tar_xz,
    tar_bz2,
    zip,
};

pub const PlatformInfo = struct {
    os: []const u8,    // "linux", "macos", "win"
    arch: []const u8,  // "x86_64", "aarch64", "arm", "i386"
};

pub const ProjectInfo = struct {
    detected: bool,
    confidence: u8,      // 0-100
    files_found: []const []const u8,  // Owned by caller
};

pub const TaskSuggestion = struct {
    name: []const u8,         // Owned
    command: []const u8,      // Owned
    description: []const u8,  // Owned
};
```

---

## Example: Ruby Provider

Complete example in `src/lang/ruby.zig`:

```zig
const std = @import("std");
const provider = @import("provider.zig");
const types = @import("../toolchain/types.zig");
const ToolVersion = types.ToolVersion;
const LanguageProvider = provider.LanguageProvider;
const DownloadSpec = provider.DownloadSpec;
const PlatformInfo = provider.PlatformInfo;
const ProjectInfo = provider.ProjectInfo;

pub const RubyProvider: LanguageProvider = .{
    .name = "ruby",
    .resolveDownloadUrl = resolveDownloadUrl,
    .fetchLatestVersion = fetchLatestVersion,
    .getBinaryPath = getBinaryPath,
    .getEnvironmentVars = getEnvironmentVars,
    .detectProject = detectProject,
    .extractTasks = extractTasks,
};

fn resolveDownloadUrl(allocator: std.mem.Allocator, version: ToolVersion, platform: PlatformInfo) !DownloadSpec {
    _ = platform; // Ruby uses same URL for all platforms
    const version_str = try version.toString(allocator);
    defer allocator.free(version_str);

    const url = try std.fmt.allocPrint(allocator,
        "https://cache.ruby-lang.org/pub/ruby/{d}.{d}/ruby-{s}.tar.gz",
        .{ version.major, version.minor, version_str }
    );

    return .{ .url = url, .archive_type = .tar_gz };
}

fn fetchLatestVersion(allocator: std.mem.Allocator) !ToolVersion {
    // Simplified: return known latest stable version
    // In production, fetch from https://www.ruby-lang.org/en/downloads/
    _ = allocator;
    return ToolVersion{ .major = 3, .minor = 2, .patch = 2 };
}

fn getBinaryPath(allocator: std.mem.Allocator, platform: PlatformInfo) ![]const u8 {
    if (std.mem.eql(u8, platform.os, "win")) {
        return try allocator.dupe(u8, "bin/ruby.exe");
    } else {
        return try allocator.dupe(u8, "bin/ruby");
    }
}

fn getEnvironmentVars(allocator: std.mem.Allocator, toolchain_path: []const u8, platform: PlatformInfo) ![][2][]const u8 {
    _ = platform;
    const gem_home = try std.fmt.allocPrint(allocator, "{s}/gems", .{toolchain_path});
    var env_vars = try allocator.alloc([2][]const u8, 1);
    env_vars[0] = .{ try allocator.dupe(u8, "GEM_HOME"), gem_home };
    return env_vars;
}

fn detectProject(allocator: std.mem.Allocator, dir_path: []const u8) !ProjectInfo {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch {
        return .{ .detected = false, .confidence = 0, .files_found = &.{} };
    };
    defer dir.close();

    var confidence: u8 = 0;
    var files = std.ArrayList([]const u8){};
    defer files.deinit(allocator);

    if (dir.access("Gemfile", .{})) |_| {
        confidence += 60;
        try files.append(allocator, "Gemfile");
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    return .{
        .detected = confidence > 0,
        .confidence = @min(confidence, 100),
        .files_found = try files.toOwnedSlice(allocator),
    };
}

fn extractTasks(allocator: std.mem.Allocator, dir_path: []const u8) ![]LanguageProvider.TaskSuggestion {
    _ = dir_path;
    var tasks = std.ArrayList(LanguageProvider.TaskSuggestion){};
    errdefer tasks.deinit(allocator);

    try tasks.append(allocator, .{
        .name = try allocator.dupe(u8, "test"),
        .command = try allocator.dupe(u8, "bundle exec rake test"),
        .description = try allocator.dupe(u8, "Run tests"),
    });

    return try tasks.toOwnedSlice(allocator);
}
```

---

## Registration

After creating your provider, register it in `src/lang/registry.zig`:

```zig
const ruby = @import("ruby.zig");

pub fn getProvider(name: []const u8) ?LanguageProvider {
    if (std.mem.eql(u8, name, "node")) return node.NodeProvider;
    if (std.mem.eql(u8, name, "python")) return python.PythonProvider;
    // ... existing providers
    if (std.mem.eql(u8, name, "ruby")) return ruby.RubyProvider;  // ← Add this
    return null;
}

pub fn getAllProviders() []const LanguageProvider {
    return &[_]LanguageProvider{
        node.NodeProvider,
        python.PythonProvider,
        // ... existing providers
        ruby.RubyProvider,  // ← Add this
    };
}
```

---

## Testing

### Unit Tests

Run unit tests for your provider:

```bash
zig build test | grep ruby
```

### Integration Test

Test the full workflow:

```bash
# Create a test project
mkdir /tmp/ruby-test && cd /tmp/ruby-test
echo 'source "https://rubygems.org"' > Gemfile

# Initialize with detection
zr init --detect

# Verify generated zr.toml
cat zr.toml

# Install toolchain
zr tools install ruby@3.2.2

# Run task
zr run test
```

---

## Best Practices

1. **Error Handling**: Always use `try` or `catch` for fallible operations
2. **Memory Management**: Use `defer allocator.free()` immediately after allocation
3. **Platform Support**: Test on Linux, macOS, and Windows
4. **Version Parsing**: Use `ToolVersion.parse()` for consistency
5. **HTTP Fetching**: Use `provider.fetchUrl()` helper
6. **Confidence Scores**:
   - Primary marker (e.g., `Gemfile`): 50-70%
   - Secondary markers (e.g., `Rakefile`): 20-30%
   - Optional markers (e.g., `.ruby-version`): 10%
7. **Task Extraction**: Prefer parsing build files over hardcoded lists
8. **Testing**: Add at least 3 tests (download URL, binary path, detection)

---

## Checklist

- [ ] Created `src/lang/<language>.zig`
- [ ] Implemented all 6 required functions
- [ ] Added unit tests
- [ ] Registered in `src/lang/registry.zig`
- [ ] Tested `zr init --detect` in a sample project
- [ ] Tested `zr tools install <language>@<version>`
- [ ] Tested cross-platform (Linux, macOS, Windows)
- [ ] Documented language-specific quirks (if any)

---

## See Also

- [Configuration Reference](configuration.md) — `[toolchains]` section
- [Commands Reference](commands.md) — `tools` and `init` commands
- Existing providers: `src/lang/node.zig`, `src/lang/python.zig`, `src/lang/rust.zig`
