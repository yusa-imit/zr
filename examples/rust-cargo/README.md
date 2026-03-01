# Rust Cargo Example

This example demonstrates using **zr** with a Rust project managed by [Cargo](https://doc.rust-lang.org/cargo/). It showcases auto-detection capabilities and integration with Rust development tools.

## Features Demonstrated

- ✅ **Auto-detection** via `zr init --detect` — detects Cargo.toml and generates tasks
- ✅ **Cargo integration** — build, test, check, clippy, fmt, doc
- ✅ **Release builds** — optimized builds with LTO and stripping
- ✅ **Benchmarks** — criterion-based performance testing
- ✅ **Workflows** — CI pipeline, pre-commit checks, full quality audit

## Project Structure

```
rust-cargo/
├── Cargo.toml           # Cargo package configuration
├── zr.toml              # Task definitions (auto-generated + enhanced)
├── src/
│   ├── main.rs          # CLI application with clap
│   └── calculator.rs    # Library module
└── benches/
    └── calculator_bench.rs  # Criterion benchmarks
```

## Quick Start

### 1. Auto-generate zr.toml

If you have an existing Rust/Cargo project, you can generate `zr.toml` automatically:

```bash
cd your-rust-project/
zr init --detect
```

This will:
- Detect `Cargo.toml` (Cargo configuration)
- Generate standard Rust tasks (build, test, check, clippy, fmt, doc, run, clean)
- Add release variants (build-release)
- Include benchmark tasks if `benches/` directory exists

### 2. View Available Tasks

```bash
$ zr list
Tasks:
  → build          Build the project in debug mode
  → build-release  Build the project with optimizations
  → test           Run tests
  → test-verbose   Run tests with verbose output
  → check          Check code without building
  → clippy         Run Clippy lints
  → fmt            Format code with rustfmt
  → fmt-check      Check code formatting
  → doc            Generate documentation
  → run            Run the application
  → clean          Clean build artifacts
  → bench          Run benchmarks
  → coverage       Generate code coverage report
  → audit          Check dependencies for security vulnerabilities
  → outdated       Check for outdated dependencies

Workflows:
  → ci             Complete CI pipeline
  → pre-commit     Run before committing
  → full-check     Comprehensive quality checks
```

### 3. Run Tasks

```bash
# Quick check (no build)
zr run check

# Run tests
zr run test

# Format and lint
zr run fmt
zr run clippy

# Build release binary
zr run build-release

# Run CI pipeline
zr workflow ci
```

## Enhanced Tasks Beyond Auto-detection

While `zr init --detect` generates basic tasks, this example includes enhanced versions:

### Benchmarking

```toml
[tasks.bench]
description = "Run benchmarks"
cmd = "cargo bench"
deps = ["build-release"]
```

Uses [criterion](https://github.com/bheisler/criterion.rs) for statistical benchmarking.

### Code Coverage

```toml
[tasks.coverage]
description = "Generate code coverage report"
cmd = "cargo tarpaulin --out Html --output-dir coverage"
```

Requires [cargo-tarpaulin](https://github.com/xd009642/tarpaulin):
```bash
cargo install cargo-tarpaulin
```

### Security Audit

```toml
[tasks.audit]
description = "Check dependencies for security vulnerabilities"
cmd = "cargo audit"
```

Requires [cargo-audit](https://github.com/rustsec/rustsec):
```bash
cargo install cargo-audit
```

### CI Workflow

```toml
[workflows.ci]
description = "Complete CI pipeline"
stages = [
  { tasks = ["fmt-check", "clippy"], parallel = true },
  { tasks = ["check"] },
  { tasks = ["test"] },
  { tasks = ["build-release"] }
]
```

Runs:
1. Parallel format and lint checks
2. Type checking
3. Tests
4. Release build

## Comparison: Before and After zr

### Before (traditional approach)

```bash
# Run all checks manually
cargo fmt --check
cargo clippy -- -D warnings
cargo test
cargo build --release

# Remember order, no parallelization
```

### After (with zr)

```bash
# Single command, correct order, parallelization
zr workflow ci

# Or run pre-commit checks
zr workflow pre-commit
```

## Testing the Example

1. **Setup** (requires Rust 1.70+):
   ```bash
   cd examples/rust-cargo
   zr run build
   ```

2. **Run tests**:
   ```bash
   zr run test
   ```

3. **Run the app**:
   ```bash
   zr run run -- --a 5 --b 3 --operation add
   # Output: 8

   zr run run -- --a 5 --b 3 --operation multiply
   # Output: 15
   ```

4. **Run benchmarks**:
   ```bash
   zr run bench
   ```

5. **Full CI pipeline**:
   ```bash
   zr workflow ci
   ```

## Why Use zr with Rust?

1. **Unified tooling** — One command for all languages (Rust, Python, Node, etc.)
2. **Dependency management** — Tasks automatically run in correct order
3. **Parallelization** — Run independent checks concurrently (fmt + clippy)
4. **Caching** — Skip unchanged builds with input/output tracking
5. **Consistency** — Same workflow across all projects and languages
6. **Fast** — ~5ms startup overhead (negligible compared to cargo build)

## Common Rust Patterns

### Matrix Testing (Multiple Rust Versions)

```toml
[tasks.test-matrix]
cmd = "cargo test"
matrix.rust = ["1.70.0", "1.75.0", "stable", "nightly"]
toolchain.rust = "${rust}"
```

### Cross-compilation

```toml
[tasks.build-linux]
cmd = "cargo build --release --target x86_64-unknown-linux-gnu"

[tasks.build-windows]
cmd = "cargo build --release --target x86_64-pc-windows-gnu"

[tasks.build-macos]
cmd = "cargo build --release --target x86_64-apple-darwin"
```

### Feature Matrix Testing

```toml
[tasks.test-features]
cmd = "cargo test --features ${features}"
matrix.features = ["default", "full", "minimal"]
```

### Conditional Tasks

```toml
[tasks.deploy]
cmd = "cargo build --release && ./deploy.sh"
condition = "platform.is_linux && env.CI == 'true'"
```

## Performance Optimization

The `Cargo.toml` includes optimized release settings:

```toml
[profile.release]
opt-level = 3        # Maximum optimization
lto = true           # Link-time optimization
codegen-units = 1    # Better optimization, slower build
strip = true         # Strip symbols from binary
```

This produces a ~200KB binary (vs ~2-3MB without strip).

## Next Steps

- Read the [Configuration Guide](../../docs/guides/configuration.md) for advanced features
- See [Workflows](../../docs/guides/getting-started.md#workflows) for complex pipelines
- Explore [Matrix Expansion](../../docs/guides/configuration.md#matrix) for multi-target builds
- Check [Monorepo Support](../workspace/) for Cargo workspaces

## Troubleshooting

**Q: zr doesn't detect my Rust project**

A: Ensure you have `Cargo.toml` in the project root.

**Q: Tasks fail with "cargo: command not found"**

A: Install Rust via [rustup](https://rustup.rs/):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

**Q: Want to use different Rust toolchain?**

A: Add toolchain specification:
```toml
[tasks.test-nightly]
cmd = "cargo +nightly test"
```

Or use zr's toolchain management (future feature):
```bash
zr tools install rust@nightly
```

**Q: Benchmark task fails**

A: Install criterion as a dev dependency (already in `Cargo.toml`), then:
```bash
zr run bench
```

## Additional Tools

### cargo-watch (auto-rebuild on changes)

```bash
cargo install cargo-watch
```

Add task:
```toml
[tasks.watch]
cmd = "cargo watch -x check -x test"
```

### cargo-edit (manage dependencies)

```bash
cargo install cargo-edit
```

Add tasks:
```toml
[tasks.add-dep]
cmd = "cargo add ${dep}"
template.dep = "String"

[tasks.update-deps]
cmd = "cargo upgrade"
```

## Integration with Cargo Workspace

For multi-crate workspaces, combine with zr's workspace features:

```toml
# Root zr.toml
[workspace]
members = ["crates/*"]

[tasks.test-all]
workspace = true
cmd = "cargo test"
```

This runs tests across all workspace members with smart caching and affected detection.
