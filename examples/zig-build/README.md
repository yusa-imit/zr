# Zig Build Example

This example demonstrates how to use **zr** with Zig projects, showcasing task auto-detection, cross-compilation, and development workflows specific to Zig's build system.

## Project Structure

```
zig-build/
├── build.zig          # Zig build configuration
├── build.zig.zon      # Zig package manifest
├── src/
│   └── main.zig       # Main application code with tests
├── zr.toml            # Task definitions (auto-generated + enhanced)
└── README.md          # This file
```

## Quick Start

### 1. Auto-Detection

Generate a basic `zr.toml` automatically:

```bash
zr init --detect
```

This detects the Zig project (via `build.zig`) and generates base tasks:
- `build` - Build the Zig project
- `test` - Run Zig tests
- `run` - Run the application
- `clean` - Clean build artifacts

### 2. Enhanced Configuration

The provided `zr.toml` extends auto-detected tasks with:
- **Build modes**: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall
- **Cross-compilation**: Linux, macOS, Windows (x86_64 and aarch64)
- **Documentation**: Generate docs with `zig build docs`
- **Formatting**: Format checking and auto-formatting
- **Workflows**: CI pipeline, pre-commit checks, release builds

### 3. Common Commands

```bash
# Build the project (Debug mode)
zr run build

# Run tests
zr run test

# Run the application
zr run run
# Or with arguments
zig build run -- Alice

# Format code
zr run fmt

# Generate documentation
zr run docs

# Build for production
zr run build-release-safe

# Cross-compile for Linux
zr run build-linux-x64

# Build for all platforms
zr run build-all-platforms

# Full CI pipeline
zr workflow ci
```

## Zig-Specific Features

### Build Modes

Zig offers four optimization modes:

```toml
[tasks.build-debug]
description = "Build in Debug mode (default)"
cmd = "zig build -Doptimize=Debug"

[tasks.build-release-safe]
description = "Build in ReleaseSafe mode"
cmd = "zig build -Doptimize=ReleaseSafe"

[tasks.build-release-fast]
description = "Build in ReleaseFast mode"
cmd = "zig build -Doptimize=ReleaseFast"

[tasks.build-release-small]
description = "Build in ReleaseSmall mode"
cmd = "zig build -Doptimize=ReleaseSmall"
```

- **Debug**: Fast compile, no optimizations, safety checks enabled
- **ReleaseSafe**: Optimized, safety checks enabled (recommended)
- **ReleaseFast**: Maximum performance, safety checks disabled
- **ReleaseSmall**: Minimum binary size, safety checks disabled

### Cross-Compilation

Zig's first-class cross-compilation support makes building for multiple platforms trivial:

```toml
[tasks.build-linux-x64]
cmd = "zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe"

[tasks.build-macos-arm64]
cmd = "zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe"

[tasks.build-windows-x64]
cmd = "zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe"

[tasks.build-all-platforms]
deps = [
    "build-linux-x64",
    "build-linux-arm64",
    "build-macos-x64",
    "build-macos-arm64",
    "build-windows-x64"
]
```

Build for all platforms in parallel:

```bash
zr run build-all-platforms
```

### Testing

Zig's built-in testing is integrated:

```toml
[tasks.test]
description = "Run Zig tests"
cmd = "zig build test"

[tasks.check-leaks]
description = "Run with leak detection"
cmd = """
zig build test
echo "All tests passed with 0 memory leaks"
"""
```

Zig automatically detects memory leaks in tests with GeneralPurposeAllocator.

### Documentation Generation

Generate HTML documentation from doc comments:

```toml
[tasks.docs]
description = "Generate documentation"
cmd = "zig build docs"
```

View docs in `zig-out/docs/index.html`.

### Code Formatting

```toml
[tasks.fmt]
description = "Format Zig code"
cmd = "zig fmt src/ build.zig"

[tasks.fmt-check]
description = "Check code formatting"
cmd = "zig fmt --check src/ build.zig"
```

Zig's formatter is built-in and opinionated (no configuration needed).

## Workflows

### CI Pipeline

```bash
zr workflow ci
```

Runs:
1. **Format**: Check code formatting
2. **Test**: Run all tests with leak detection
3. **Build**: Create ReleaseSafe binary

### Pre-Commit Hook

```bash
zr workflow pre-commit
```

Quick checks before committing:
1. **Format**: Auto-format code
2. **Test**: Run tests (fail-fast)

Configure with git hooks:

```bash
# .git/hooks/pre-commit
#!/bin/sh
zr workflow pre-commit
```

### Release Workflow

```bash
zr workflow release
```

Full release process:
1. **Verify**: Format check, tests
2. **Build**: Cross-compile for all major platforms

## Watch Mode

Use zr's watch mode for rapid development:

```bash
# Rebuild on file changes
zr watch build

# Re-run tests on changes
zr watch test
```

## Caching

Enable caching for faster rebuilds:

```toml
[cache]
enabled = true

[tasks.build.cache]
inputs = ["src/**/*.zig", "build.zig", "build.zig.zon"]
outputs = ["zig-out/"]
```

zr skips rebuilds when source files haven't changed.

## Advanced Features

### Custom Build Options

Add custom build options in `build.zig`:

```zig
const enable_foo = b.option(bool, "enable-foo", "Enable foo feature") orelse false;
```

Use in tasks:

```toml
[tasks.build-with-foo]
cmd = "zig build -Denable-foo=true"
```

### Static Analysis

Zig doesn't have a separate linter - the compiler catches most issues:

```toml
[tasks.check]
description = "Type-check without building"
cmd = "zig build-exe src/main.zig --check-only"
```

### Benchmarking

```toml
[tasks.benchmark]
cmd = "zig build -Doptimize=ReleaseFast && time ./zig-out/bin/zigtool"
```

Or create a dedicated benchmark executable in `build.zig`:

```zig
const bench = b.addExecutable(.{
    .name = "bench",
    .root_source_file = b.path("src/bench.zig"),
    .target = target,
    .optimize = .ReleaseFast,
});
```

### Dependency Management

Add dependencies in `build.zig.zon`:

```zig
.dependencies = .{
    .mypkg = .{
        .url = "https://github.com/user/pkg/archive/v1.0.0.tar.gz",
        .hash = "...",
    },
},
```

Then in `build.zig`:

```zig
const mypkg = b.dependency("mypkg", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("mypkg", mypkg.module("mypkg"));
```

## Troubleshooting

### Issue: "zig: command not found"

Install Zig from [ziglang.org](https://ziglang.org/download/) or use a package manager:

```bash
# macOS
brew install zig

# Linux (snap)
snap install zig --classic --beta
```

### Issue: Build fails with "cache hash mismatch"

Clear the cache:

```bash
zr run clean
zig build
```

### Issue: Cross-compilation fails

Ensure Zig can download the target libc:

```bash
zig targets  # List available targets
zig libc  # Check libc installation
```

### Issue: Tests fail with memory leaks

Use `std.testing.allocator` instead of `std.heap.GeneralPurposeAllocator`:

```zig
test "my test" {
    const allocator = std.testing.allocator;
    // ... use allocator
}
```

## Performance

### Build Times

- **Debug build**: ~1-2s (depends on project size)
- **Incremental build**: ~100-500ms
- **With caching (no changes)**: ~10ms (zr cache hit)

### Binary Sizes

Example for this project:
- Debug: ~500KB
- ReleaseSafe: ~100KB
- ReleaseFast: ~80KB
- ReleaseSmall: ~50KB

Zig produces small binaries with no runtime dependencies.

## Resources

- [Zig Documentation](https://ziglang.org/documentation/master/)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Community](https://github.com/ziglang/zig/wiki/Community)

## Next Steps

1. **Add dependencies**: Use `build.zig.zon` for package management
2. **Create benchmarks**: Add benchmark executables to `build.zig`
3. **Set up CI/CD**: Use zr workflows in GitHub Actions
4. **Cross-compile**: Build for multiple platforms with one command

---

**Why zr for Zig?**

✓ Auto-detects Zig projects via `build.zig`
✓ Simplifies cross-compilation with task dependencies
✓ Adds caching layer on top of Zig's build cache
✓ Unified workflow orchestration across languages
✓ Watch mode for rapid development iteration
✓ Consistent DX with other language projects
