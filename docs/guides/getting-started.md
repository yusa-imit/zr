# Getting Started with zr

**zr** is a fast, cross-platform task runner and workflow manager written in Zig. It combines the simplicity of Make with modern features like parallel execution, expressions, and AI integration.

## Installation

### Pre-built Binaries

Download the latest release for your platform:

```bash
# macOS (Apple Silicon)
curl -L https://github.com/yusa-imit/zr/releases/latest/download/zr-aarch64-macos -o zr
chmod +x zr
sudo mv zr /usr/local/bin/

# macOS (Intel)
curl -L https://github.com/yusa-imit/zr/releases/latest/download/zr-x86_64-macos -o zr
chmod +x zr
sudo mv zr /usr/local/bin/

# Linux (x86_64)
curl -L https://github.com/yusa-imit/zr/releases/latest/download/zr-x86_64-linux -o zr
chmod +x zr
sudo mv zr /usr/local/bin/

# Windows (x86_64)
# Download zr-x86_64-windows.exe from releases page
# Add to PATH
```

### Build from Source

Requires [Zig 0.15.2](https://ziglang.org/download/):

```bash
git clone https://github.com/yusa-imit/zr.git
cd zr
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/zr /usr/local/bin/
```

### Verify Installation

```bash
zr --version
# zr version 1.0.0
```

## Quick Start

### 1. Initialize a Project

Create a `zr.toml` configuration file:

```bash
zr init
```

This generates a basic configuration:

```toml
[tasks.build]
description = "Build the project"
cmd = "echo 'Build step here'"

[tasks.test]
description = "Run tests"
cmd = "echo 'Test step here'"
deps = ["build"]
```

### 2. Auto-detect Project

If you have an existing project with package.json, Makefile, or other build files, use `--detect`:

```bash
zr init --detect
```

This automatically extracts tasks from your existing build configuration.

### 3. Run Tasks

```bash
# Run a single task
zr run build

# Run with dependencies
zr run test  # automatically runs 'build' first

# Run multiple tasks in parallel
zr run build test lint
```

### 4. List Available Tasks

```bash
zr list

# Show as a tree with dependencies
zr list --tree

# Filter by tags
zr list --tags ci
```

### 5. View Task Graph

```bash
# ASCII visualization
zr graph

# DOT format for graphviz
zr graph --format dot > graph.dot
dot -Tpng graph.dot -o graph.png
```

## Basic Configuration

### Task Definition

```toml
[tasks.build]
description = "Build the application"
cmd = "npm run build"
deps = ["install"]
dir = "./frontend"
env = { NODE_ENV = "production" }

[tasks.install]
description = "Install dependencies"
cmd = "npm install"
```

### Task Dependencies

```toml
[tasks.deploy]
cmd = "./deploy.sh"
deps = ["build", "test", "lint"]  # runs in parallel, then deploy
```

### Conditional Execution

```toml
[tasks.deploy-prod]
cmd = "kubectl apply -f prod.yaml"
condition = "${platform.is_linux} && ${env.CI == 'true'}"
```

### Environment Variables

```toml
[tasks.server]
cmd = "node server.js"
env = { PORT = "3000", HOST = "0.0.0.0" }
```

### Working Directory

```toml
[tasks.frontend-build]
cmd = "npm run build"
dir = "./packages/frontend"
```

## Next Steps

- [Configuration Reference](configuration.md) — full TOML schema
- [Commands Reference](commands.md) — all CLI commands
- [Expressions Guide](expressions.md) — dynamic expressions and conditions
- [MCP Integration](mcp-integration.md) — AI agent integration
- [LSP Setup](lsp-setup.md) — editor integration
- [Adding a Language](adding-language.md) — extend toolchain support

## Examples

### Node.js Project

```toml
[tasks.install]
cmd = "npm install"

[tasks.build]
cmd = "npm run build"
deps = ["install"]

[tasks.test]
cmd = "npm test"
deps = ["build"]

[tasks.dev]
cmd = "npm run dev"
deps = ["install"]
```

### Rust Project

```toml
[tasks.build]
cmd = "cargo build --release"

[tasks.test]
cmd = "cargo test"

[tasks.bench]
cmd = "cargo bench"
deps = ["build"]

[tasks.fmt]
cmd = "cargo fmt --check"
```

### Monorepo

```toml
[tasks.build-frontend]
cmd = "npm run build"
dir = "./packages/frontend"

[tasks.build-backend]
cmd = "cargo build --release"
dir = "./packages/backend"

[tasks.build-all]
deps = ["build-frontend", "build-backend"]

[tasks.test-all]
cmd = "zr run test"
tags = ["ci"]
```

## Tips

- Use `zr validate` to check your configuration for errors
- Use `zr show <task>` to see detailed task metadata
- Use `zr ai "build and test"` for natural language task execution
- Enable shell completion: `zr completion bash > /etc/bash_completion.d/zr`

## Troubleshooting

### Task not found

```bash
zr run biuld
# ✗ Unknown task: biuld
#
#   Did you mean: build?
```

Use `zr list` to see all available tasks.

### Dependency cycle

```bash
zr validate
# ✗ Dependency cycle detected: build → test → build
```

Check your `deps` arrays for circular references.

### Command failed

```bash
zr run test
# ✗ Task 'test' failed with exit code 1
```

Use `zr history` to see recent task executions and their outputs.

## Support

- GitHub Issues: https://github.com/yusa-imit/zr/issues
- Documentation: https://github.com/yusa-imit/zr/docs
