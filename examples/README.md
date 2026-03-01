# zr Examples

This directory contains example configurations demonstrating various zr features and use cases.

## Available Examples

### [Basic](./basic/)
**Start here!** Demonstrates fundamental zr features for single-project setups.

- Simple task definitions
- Task dependencies
- Environment variables
- Matrix expansion
- Cache control

**When to use:** Small projects, learning zr basics, quick task automation

---

### [Workspace/Monorepo](./workspace/)
Demonstrates monorepo management with multiple packages.

- Workspace definition with glob patterns
- Affected detection (build only what changed)
- Content-based caching
- Dependency graph visualization
- Workspace-wide task execution

**When to use:** Monorepos, multiple related packages, large codebases

---

### [Multi-Language](./multi-lang/)
Shows how to orchestrate builds across different programming languages.

- TypeScript/Node.js frontend
- Python backend
- Go infrastructure tooling
- Rust CLI utilities
- Unified build pipeline

**When to use:** Polyglot projects, microservices, full-stack applications

---

### [Plugin System](./plugin/)
Explores zr's plugin ecosystem.

- Built-in plugins (env, git)
- Custom plugin loading
- Plugin configuration
- Creating new plugins

**When to use:** Extending zr functionality, custom workflows, integrations

---

### [Toolchain Management](./toolchain/)
Demonstrates built-in toolchain version management.

- Declarative version specification
- Automatic installation
- Per-project isolation
- Matrix testing across versions

**When to use:** Teams needing reproducible builds, multiple Node/Python/Go versions

---

### [Java Maven](./java-maven/)
Shows integration with Java/Maven projects using auto-detection.

- Auto-generated tasks via `zr init --detect`
- Maven lifecycle integration (build, test, package)
- Custom workflows (CI pipeline, coverage reporting)
- Build profiles for different environments
- Wrapper script preference (mvnw)

**When to use:** Java projects using Maven, migrating from Maven to zr, adding task orchestration to existing Maven builds

---

### [Python Poetry](./python-poetry/)
Demonstrates Python development with Poetry and quality tools.

- Auto-generated tasks via `zr init --detect`
- Poetry integration (install, run, test, build)
- Quality tools (pytest, black, ruff, mypy)
- Coverage reporting (HTML and terminal)
- CI workflow with parallel checks

**When to use:** Python projects with Poetry, adding task orchestration to existing Python projects, unified tooling across languages

---

### [Rust Cargo](./rust-cargo/)
Shows Rust development with Cargo and the Rust toolchain.

- Auto-generated tasks via `zr init --detect`
- Cargo integration (build, test, check, clippy, fmt, doc)
- Release builds with LTO and stripping
- Benchmarks with criterion
- Security audit and dependency checks

**When to use:** Rust projects with Cargo, cross-compilation, performance-critical builds, monorepo Cargo workspaces

---

### [Go Modules](./go-modules/)
Demonstrates Go development with modules, testing, and cross-compilation.

- Auto-generated tasks via `zr init --detect`
- Go modules integration (build, test, vet, fmt, mod-tidy)
- Coverage reports with HTML output
- Cross-platform builds (Linux, macOS, Windows)
- golangci-lint integration
- CI workflows with parallel checks

**When to use:** Go projects with modules, CLI applications with Cobra, microservices, cross-platform tools

---

## Quick Start

1. **Clone an example:**
   ```bash
   cp -r examples/basic my-project
   cd my-project
   ```

2. **Run tasks:**
   ```bash
   zr list           # See available tasks
   zr run build      # Run a task
   zr graph          # Visualize dependencies
   ```

3. **Modify for your needs:**
   Edit `zr.toml` to match your project structure and commands.

## Learning Path

```
┌──────────┐
│  Basic   │  ← Start here (30 min)
└────┬─────┘
     │
     ├─────────────┐
     │             │
┌────▼─────┐  ┌───▼──────────┐
│Workspace │  │ Multi-lang   │  ← Choose based on project type
└────┬─────┘  └───┬──────────┘
     │            │
     └─────┬──────┘
           │
      ┌────▼────┐
      │ Plugin  │  ← Advanced customization
      └────┬────┘
           │
      ┌────▼──────┐
      │ Toolchain │  ← Team reproducibility
      └───────────┘
```

## Feature Matrix

| Example       | Tasks | Deps | Matrix | Cache | Workspace | Plugins | Toolchains | Auto-detect |
|---------------|-------|------|--------|-------|-----------|---------|------------|-------------|
| Basic         | ✓     | ✓    | ✓      | ✓     | -         | -       | -          | -           |
| Workspace     | ✓     | ✓    | -      | ✓     | ✓         | -       | -          | -           |
| Multi-lang    | ✓     | ✓    | -      | ✓     | -         | -       | -          | -           |
| Plugin        | ✓     | ✓    | -      | -     | -         | ✓       | -          | -           |
| Toolchain     | ✓     | ✓    | ✓      | -     | -         | -       | ✓          | -           |
| Java Maven    | ✓     | ✓    | -      | ✓     | -         | -       | -          | ✓           |
| Python Poetry | ✓     | ✓    | -      | ✓     | -         | -       | -          | ✓           |
| Rust Cargo    | ✓     | ✓    | -      | ✓     | -         | -       | -          | ✓           |
| Go Modules    | ✓     | ✓    | -      | ✓     | -         | -       | -          | ✓           |

## Common Patterns

### Pattern: Aggregate Tasks

Create meta-tasks that run multiple sub-tasks:

```toml
[tasks.ci]
description = "Full CI pipeline"
deps = ["lint", "test", "build"]
```

### Pattern: Environment-Specific Tasks

Use environment variables for different environments:

```toml
[tasks.deploy-dev]
command = "deploy.sh"
env = { ENV = "development" }

[tasks.deploy-prod]
command = "deploy.sh"
env = { ENV = "production" }
```

### Pattern: Conditional Execution

Use matrix for conditional logic:

```toml
[tasks.test]
command = "npm test"
matrix.os = ["linux", "macos", "windows"]
```

### Pattern: Incremental Builds

Leverage input/output tracking:

```toml
[tasks.build]
command = "build.sh"
inputs = ["src/**/*.ts"]
outputs = ["dist/"]
```

Only rebuilds when `src/` changes.

## Tips

1. **Start small** - Begin with the basic example and add features as needed
2. **Use caching** - Enable caching for expensive tasks (builds, tests)
3. **Visualize** - Run `zr graph` to understand task dependencies
4. **Watch mode** - Use `zr watch build` for rapid development
5. **Dry run** - Test with `--dry-run` before running destructive tasks

## More Resources

- [PRD](../docs/PRD.md) - Full product requirements and feature specifications
- [Plugin Guide](../docs/PLUGIN_GUIDE.md) - How to use plugins
- [Plugin Dev Guide](../docs/PLUGIN_DEV_GUIDE.md) - How to create plugins

## Contributing Examples

Have a useful example? We welcome contributions!

1. Create a new directory under `examples/`
2. Add `zr.toml` and `README.md`
3. Document the use case and features demonstrated
4. Submit a pull request

Good examples to add:
- Docker/Kubernetes workflows
- CI/CD integration examples
- Remote cache setup
- Complex dependency graphs
- Real-world project conversions (from Make, npm scripts, etc.)
