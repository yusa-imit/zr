# zr Documentation

Welcome to the **zr** documentation! This guide will help you get started with zr and master its features.

## 📚 Documentation Index

### Getting Started
- **[Quick Start](guides/getting-started.md)** — Install zr and run your first task in 5 minutes
- **[Migration Guides](guides/migration.md)** — Migrate from make, just, task, or npm scripts
- **[Shell Integration](guides/shell-setup.md)** — Set up shell aliases and productivity shortcuts

### Configuration
- **[Configuration Guide](guides/configuration.md)** — Complete zr.toml reference with examples
- **[Configuration Reference](guides/config-reference.md)** — Field-by-field schema documentation
- **[Best Practices](guides/best-practices.md)** — Patterns for large projects and monorepos

### Commands
- **[Commands Guide](guides/commands.md)** — All CLI commands with examples
- **[Command Reference](guides/command-reference.md)** — Quick reference for all subcommands

### Advanced Topics
- **[LSP Setup](guides/lsp-setup.md)** — Configure editor integration (VS Code, Neovim, etc.)
- **[MCP Integration](guides/mcp-integration.md)** — Use zr with AI agents via Model Context Protocol
- **[TUI Performance](guides/tui-performance.md)** — Optimize terminal UI for large task graphs
- **[Adding Languages](guides/adding-language.md)** — Extend zr with new language toolchains
- **[Plugin Development](../PLUGIN_DEV_GUIDE.md)** — Write native or WASM plugins
- **[Plugin Guide](../PLUGIN_GUIDE.md)** — Use community plugins

### Reference
- **[Error Codes](guides/error-codes.md)** — Complete error code reference
- **[Benchmarks](guides/benchmarks.md)** — Performance comparison vs make/just/task
- **[Troubleshooting](guides/troubleshooting.md)** — FAQ and common issues

---

## 🚀 Quick Links

### First-Time Users
1. **[Install zr](guides/getting-started.md#installation)** — Get zr on your system
2. **[Initialize a project](guides/getting-started.md#your-first-project)** — Create your first `zr.toml`
3. **[Run a task](guides/getting-started.md#running-tasks)** — Execute tasks with `zr run`
4. **[Set up shell integration](guides/shell-setup.md)** — Productivity shortcuts

### Migrating from Other Tools
- **From make** → [Migration guide](guides/migration.md#migrating-from-make)
- **From just** → [Migration guide](guides/migration.md#migrating-from-just)
- **From task** → [Migration guide](guides/migration.md#migrating-from-task)
- **From npm scripts** → [Migration guide](guides/migration.md#migrating-from-npm)

### Common Tasks
- **[Define tasks](guides/configuration.md#tasks)** — Basic task configuration
- **[Task dependencies](guides/configuration.md#dependencies)** — Build dependency graphs
- **[Parallel execution](guides/configuration.md#concurrency-groups)** — Control parallelism
- **[Workspace/monorepo](guides/configuration.md#workspaces)** — Multi-project setups
- **[Caching](guides/configuration.md#caching)** — Local and remote cache
- **[Environment variables](guides/configuration.md#environment-variables)** — Env configuration
- **[Workflows](guides/configuration.md#workflows)** — Orchestrate multi-task flows

---

## 💡 What is zr?

**zr** (zig-runner) is a universal developer platform that combines:
- **Task runner** (like make, just, task, npm scripts)
- **Toolchain manager** (like nvm, pyenv, asdf)
- **Monorepo tool** (like Nx, Turborepo)
- **AI integration** (MCP server for agents, LSP for editors)

### Key Features
- **No runtime dependencies** — Single ~1.2MB binary
- **Blazing fast** — <10ms cold start, C-level performance
- **Language-agnostic** — Works with any language or build system
- **Smart caching** — Content-based caching with S3/GCS/HTTP backends
- **Parallel execution** — Intelligent task scheduling with dependency graphs
- **Editor integration** — LSP server for autocomplete, hover, goto-definition
- **AI-friendly** — MCP server for seamless AI agent integration

---

## 📖 Documentation Structure

This documentation is organized into five main sections:

### 1. Getting Started
Guides for new users to install zr, create their first project, and learn the basics. Start here if you're new to zr.

### 2. Configuration
Comprehensive guides on `zr.toml` syntax, task definitions, workspace setup, and configuration best practices.

### 3. Commands
Reference for all CLI commands (`run`, `list`, `init`, `workspace`, etc.) with usage examples and options.

### 4. Advanced Topics
Deep dives into editor integration, performance optimization, plugin development, and extending zr.

### 5. Reference
Technical reference materials including error codes, benchmarks, API docs, and troubleshooting.

---

## 🆘 Getting Help

- **Troubleshooting guide** — [guides/troubleshooting.md](guides/troubleshooting.md)
- **GitHub Issues** — [Report bugs or request features](https://github.com/yusa-imit/zr/issues)
- **Discord community** — (Coming soon)

---

## 🤝 Contributing

Want to improve the docs? Contributions are welcome!

1. Fork the repository
2. Edit files in `docs/`
3. Submit a pull request

Documentation improvements are always appreciated, especially:
- Fixing typos and broken links
- Adding examples and use cases
- Improving clarity and readability
- Translating to other languages

---

## 📝 License

zr is licensed under the MIT License. See [LICENSE](../LICENSE) for details.
