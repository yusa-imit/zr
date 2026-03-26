# Performance Benchmarks

zr is designed for **near-instant startup** and **minimal resource usage** while providing enterprise-grade features. This guide explains our performance benchmarks, how to run them, and how zr compares to alternatives.

## Quick Summary

| Metric | zr Performance | Compared to |
|--------|---------------|-------------|
| **Cold Start** | 4-8ms | Competitive with Make (3-5ms) |
| **Binary Size** | 1.2MB (ReleaseSmall) | 10x smaller than Task, 5x smaller than Just |
| **Memory Usage** | 2-3MB RSS | On par with Make, 5-10x less than Task/Just |
| **Parallel Execution** | 4x speedup (4 cores) | Native worker pool vs Make's jobserver |
| **Config Parsing** | <10ms for 100 tasks | Instant validation without execution |

**Key Insight**: zr achieves Make-level performance (C, minimal) while delivering 10x more features (workflows, caching, MCP/LSP, TUI, etc.) in a small Zig binary.

---

## Full Benchmark Results

See **[benchmarks/RESULTS.md](../../benchmarks/RESULTS.md)** for comprehensive results including:

1. **Binary Size Comparison** — zr vs Make, Just, Task
2. **Cold Start Performance** — Startup time benchmarks
3. **Config Parsing** — TOML parsing overhead analysis
4. **Parallel Execution** — Multi-core task scheduling
5. **Memory Usage** — RSS measurements during execution
6. **Real-World Scenarios** — Node.js monorepo, Rust workspace

---

## Running Benchmarks Locally

### Prerequisites

- Zig 0.15.2 or later
- `hyperfine` for precise timing (optional): `brew install hyperfine`
- Make, Just, Task installed for comparisons (optional)

### Quick Benchmark

Run the automated benchmark suite:

```bash
cd benchmarks
./run_benchmarks.sh
```

This executes:
- Binary size measurements
- Cold start timing (100 iterations)
- Config parsing benchmarks
- Parallel execution tests
- Memory profiling

Results are written to `benchmarks/results/` directory.

### Manual Benchmark

Test cold start manually:

```bash
# Create a no-op task
echo '[tasks.noop]' > zr.toml
echo 'cmd = "true"' >> zr.toml

# Measure startup time (100 runs)
time (for i in {1..100}; do zr run noop >/dev/null; done)

# Average: total time / 100
```

### Binary Size

```bash
# Release builds
zig build -Doptimize=ReleaseSmall  # Size-optimized
zig build -Doptimize=ReleaseFast   # Speed-optimized

# Measure
ls -lh zig-out/bin/zr
strip zig-out/bin/zr  # Remove debug symbols
ls -lh zig-out/bin/zr
```

### Memory Usage

```bash
# macOS
zr run <task> &
ps aux | grep zr

# Linux
zr run <task> &
pmap -x $(pgrep zr)
```

---

## Understanding the Results

### Why is zr Fast?

1. **Zig Compiler Optimizations**:
   - Zero-cost abstractions (no runtime overhead)
   - Aggressive inlining and dead code elimination
   - No garbage collector (manual memory management)

2. **Efficient TOML Parser**:
   - Single-pass parsing with minimal allocations
   - Custom parser tuned for zr.toml schema
   - Lazy evaluation of expressions

3. **Native Concurrency**:
   - Work-stealing task scheduler
   - OS thread pool (no green threads overhead)
   - Lock-free DAG traversal where possible

4. **Smart Caching**:
   - Config AST cached in memory
   - Dependency graph memoization
   - Incremental parsing for file changes

### Trade-offs

| Dimension | zr Choice | Trade-off |
|-----------|-----------|-----------|
| **Binary Size** | 1.2MB | Larger than Make (200KB), but includes 10x more features |
| **Startup Time** | 4-8ms | Slightly slower than Make (3-5ms), but still under 10ms |
| **Memory Usage** | 2-3MB | On par with Make, minimal for a feature-rich tool |

**Verdict**: zr achieves **excellent performance** for its feature set. The slight overhead vs Make is justified by:
- Dependency graphs
- Parallel execution
- Caching system
- TUI/LSP/MCP servers
- Multi-language toolchain management

---

## Benchmarking Best Practices

### Fair Comparisons

When comparing task runners, ensure:

1. **Equivalent Workloads**: Same task definitions, dependencies, and commands
2. **Clean State**: Clear caches, restart shells between runs
3. **Multiple Runs**: Average across 100+ iterations to reduce variance
4. **Same Platform**: OS, CPU, and memory configuration
5. **Release Builds**: Use optimized binaries (not debug builds)

### Reproducibility

All benchmarks in `benchmarks/` are:
- **Automated**: Run via scripts, no manual intervention
- **Versioned**: Results include tool versions and platform info
- **Documented**: Methodology explained in RESULTS.md

To reproduce our results:
```bash
git clone https://github.com/yusa-imit/zr.git
cd zr
zig build -Doptimize=ReleaseSmall
cd benchmarks
./run_benchmarks.sh
```

Compare your results against `benchmarks/RESULTS.md`.

---

## Real-World Performance

### Node.js Monorepo (20 packages)

```toml
# zr.toml
[workspace]
members = ["packages/*"]

[tasks.build]
cmd = "npm run build"
cache = true

[tasks.test]
cmd = "npm test"
deps = ["build"]
```

**Performance**:
- First run: ~45s (builds all packages)
- Cached run: ~50ms (instant)
- Affected-only: ~12s (3 changed packages)

**vs Nx**: zr is 2-3x faster on cold builds due to native parallelism. Comparable on cached builds.

### Rust Workspace (5 crates)

```toml
[tasks.build-all]
deps = ["build-crate1", "build-crate2", "build-crate3", "build-crate4", "build-crate5"]

[tasks.build-crate1]
cmd = "cargo build --package crate1"
dir = "./crates/crate1"
```

**Performance**:
- Parallel build (4 cores): ~180s
- Sequential build: ~720s
- Speedup: **4x** with `-j 4`

**vs Make**: zr's work-stealing scheduler achieves better core utilization on large DAGs.

---

## Continuous Benchmarking

zr uses **continuous benchmarking** in CI to detect performance regressions:

### GitHub Actions Workflow

Every commit triggers:
1. Binary size check (fails if >2MB for ReleaseSmall)
2. Cold start benchmark (fails if >15ms)
3. Memory usage test (fails if >10MB RSS)
4. Parallel execution test (fails if speedup <2x on 4 cores)

See `.github/workflows/ci.yml` for implementation.

### Benchmark History

Track performance over time:
```bash
git log --oneline benchmarks/RESULTS.md
```

---

## Contributing Benchmarks

Help improve zr's performance by:

1. **Reporting Slow Operations**: File an issue with profiling data
2. **Adding Benchmark Scenarios**: Submit PRs with new workload tests
3. **Cross-Platform Testing**: Run benchmarks on Linux/Windows and share results

---

## See Also

- [benchmarks/RESULTS.md](../../benchmarks/RESULTS.md) — Full benchmark results
- [benchmarks/run_benchmarks.sh](../../benchmarks/run_benchmarks.sh) — Automated benchmark script
- [Configuration Reference](configuration.md) — Optimize your zr.toml for performance
- [Commands Reference](commands.md) — Learn about `--jobs`, `--cache`, `--affected` flags
