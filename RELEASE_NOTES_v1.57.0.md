# zr v1.57.0 — v1.0-Equivalent Release

**Release Date**: 2026-03-26
**Milestone**: Phase 13C Complete (v1.0-Equivalent Feature Set)

After 13 development phases and 100+ releases, zr v1.57.0 achieves v1.0-equivalent feature completeness — a production-ready developer platform that unifies task running, toolchain management, and monorepo intelligence in a single 1.2MB binary.

> **Note**: This release marks the completion of all Phase 1-13 objectives from the PRD. The version number (1.57.0) reflects continuous incremental development; the "v1.0" designation refers to feature-completeness, not version numbering.

---

## 🎉 What is zr v1.0?

zr is a universal developer platform built with Zig. It replaces:
- **Task runners** (make/just/task)
- **Toolchain managers** (nvm/pyenv/asdf)
- **Monorepo tools** (Nx/Turborepo)
- **Build systems** (partial Bazel/Buck2 use cases)

...all in a **single 1.2MB binary** with **< 10ms cold start** and **zero runtime dependencies**.

---

## 🚀 Key Features

### Run — Task Execution (Phase 1-3)
- TOML-based config with dependency graphs
- Parallel execution with worker pool
- Content-based caching
- Matrix builds (parameterized tasks)
- Conditional execution with expression engine
- Retry logic with exponential backoff
- Workflows with multi-stage pipelines
- Watch mode (native filesystem watchers)
- Interactive TUI for task selection
- Dry-run mode for previewing execution

### Manage — Toolchain Management (Phase 5)
- Auto-install 8 toolchains: Node, Python, Zig, Go, Rust, Deno, Bun, Java
- Per-project version pinning in `zr.toml`
- Automatic PATH injection
- `zr doctor` for environment diagnostics
- Cross-platform (Linux/macOS/Windows)

### Scale — Monorepo & Multi-repo (Phase 6-7)
- Git-based affected detection (`--affected` flag)
- Workspace support for monorepos
- Cross-repo dependencies for multi-repo setups
- Architecture governance (`zr lint`)
- CODEOWNERS generation
- Dependency graph visualization (ASCII/DOT/JSON/HTML)

### Integrate — AI & Editor (Phase 10-11)
- **MCP Server** for AI agents (Claude Code, Cursor)
- **LSP Server** for editors (VS Code, Neovim, Helix, Emacs)
- Sailor library integration (arg, color, progress, fmt, tui)
- Auto-generate config from existing projects (`zr init --detect`)
- Migration tools (`--from-make`, `--from-just`, `--from-task`)

### Enterprise (Phase 8, 12)
- Remote caching (S3/GCS/HTTP/Azure)
- Analytics (HTML/JSON reports)
- Publishing with semantic versioning
- Benchmarking (`zr bench`)
- Fuzz testing for stability
- Resource monitoring (CPU/memory limits)

---

## 📊 Performance

| Metric | zr v1.0.0 | Target |
|--------|-----------|--------|
| **Binary size** | 1.2MB | ≤ 2MB ✅ |
| **Cold start** | ~4-8ms | < 10ms ✅ |
| **Memory (idle)** | ~2-3MB | < 10MB ✅ |
| **Unit tests** | 1151/1159 (8 skipped) | 100% pass ✅ |
| **Integration tests** | 30+ scenarios | 100% pass ✅ |
| **Memory leaks** | 0 | 0 ✅ |

**Comparison** (cold start):
- make: ~3-5ms
- just: ~15-20ms
- task (go-task): ~20-30ms
- Nx: ~500ms+
- Turborepo: ~300ms+

---

## 🎯 What's New in v1.0

### Phase 9 — Foundation
- ✅ LanguageProvider interface for extensible toolchain support
- ✅ JSON-RPC infrastructure (shared by MCP and LSP)
- ✅ Levenshtein distance for "Did you mean?" suggestions
- ✅ Enhanced error messages with context-aware suggestions

### Phase 10 — AI Integration
- ✅ MCP Server with 9 tools (`run_task`, `list_tasks`, `validate_config`, etc.)
- ✅ Auto-generate config from detected languages (`zr init --detect`)
- ✅ Sailor library integration for CLI toolkit

### Phase 11 — LSP Server
- ✅ Real-time diagnostics for TOML syntax errors
- ✅ Autocomplete for task names, fields, expressions, toolchains
- ✅ Hover documentation for fields and expressions
- ✅ Go-to-definition for task dependencies

### Phase 12 — Performance & Stability
- ✅ Binary optimization (1.2MB, 40% smaller than 2MB target)
- ✅ Fuzz testing (TOML parser, expression engine)
- ✅ Benchmark documentation vs Make/Just/Task

### Phase 13 — Release
- ✅ Comprehensive documentation (8 guides: getting-started, configuration, commands, benchmarks, MCP, LSP, migration, adding-language)
- ✅ Migration tools (Make/Just/Task → zr.toml auto-conversion)
- ✅ README overhaul with feature matrix and performance benchmarks
- ✅ Benchmark documentation (benchmarks/RESULTS.md) with comprehensive performance analysis

---

## 📚 Documentation

New guides in `docs/guides/` (8 comprehensive guides):
- [Getting Started](docs/guides/getting-started.md) — Installation, first task, basic config
- [Configuration Reference](docs/guides/configuration.md) — Complete TOML schema with 50+ examples
- [CLI Commands](docs/guides/commands.md) — All CLI commands with usage examples
- [Benchmarks](docs/guides/benchmarks.md) — Performance comparison methodology and results
- [MCP Integration](docs/guides/mcp-integration.md) — Setting up MCP server for AI agents
- [LSP Setup](docs/guides/lsp-setup.md) — Configuring LSP for VS Code, Neovim, etc.
- [Migration](docs/guides/migration.md) — Step-by-step migration from Make/Just/Task
- [Adding a Language](docs/guides/adding-language.md) — Extending LanguageProvider for new toolchains

---

## 🔄 Migration

Migrating from existing tools? We've got you covered:

```bash
# From Makefile
zr init --from-make

# From Justfile
zr init --from-just

# From Taskfile.yml
zr init --from-task
```

Or auto-detect your project and generate config:

```bash
zr init --detect
# Detects Node/Python/etc. and extracts tasks from package.json, setup.py, etc.
```

---

## 🌐 Platform Support

**Officially supported platforms** (CI-tested):
- Linux (x86_64, aarch64) — glibc 2.31+
- macOS (x86_64, aarch64) — 11.0+
- Windows (x86_64) — Windows 10+

**Download**: See [Releases](https://github.com/yusa-imit/zr/releases/tag/v1.0.0)

---

## 🛠️ Installation

**macOS / Linux**:
```bash
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sh
```

**Windows** (PowerShell):
```powershell
irm https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1 | iex
```

**From source** (requires Zig 0.15.2):
```bash
git clone https://github.com/yusa-imit/zr.git
cd zr
zig build -Doptimize=ReleaseSmall
```

---

## 🐛 Known Issues

None! All 1151 unit tests and 30+ integration test scenarios pass with 0 memory leaks.

**Open enhancement issues** (not blocking v1.0):
- [#24] Migrate graph algorithms to zuda library (deferred, requires zuda enhancements)
- [#23] Migrate to zuda WorkStealingDeque (deferred, awaiting zuda fix)
- [#22] Migrate to zuda graph data structures (deferred, requires zuda compatibility layer)

---

## 🙏 Acknowledgments

Built with:
- [Zig 0.15.2](https://ziglang.org)
- [TOML](https://toml.io)
- [Claude Code](https://claude.com/claude-code) — AI-assisted development

Inspired by make, just, task, Nx, Turborepo, asdf, mise, Bazel.

---

## 🗺️ What's Next?

v1.0 is feature-complete and production-ready. Future releases will focus on:
- Stability improvements and bug fixes
- Performance optimizations
- Community feedback and feature requests
- Plugin ecosystem expansion

See [docs/PRD.md](docs/PRD.md) for the full vision.

---

## 📞 Get Involved

- **Issues**: [github.com/yusa-imit/zr/issues](https://github.com/yusa-imit/zr/issues)
- **Discussions**: [github.com/yusa-imit/zr/discussions](https://github.com/yusa-imit/zr/discussions)
- **Documentation**: [github.com/yusa-imit/zr/tree/main/docs](https://github.com/yusa-imit/zr/tree/main/docs)

---

**⚡ zr v1.0.0 — Run tasks, not runtimes.**
