# ZR (t͡ɕiɾa̠ɭ)

Ultimate Language Agnostic Command Running Solution written in Zig

ZR is a powerful command runner designed to manage repositories efficiently like Turborepo, with advanced features for managing multiple pipelines, resource monitoring, and an extensible plugin system. It provides a user-friendly interface similar to Minecraft Java server management for handling complex development workflows.

## ✨ Features

- **🚀 Multi-Repository Management**: Add, remove, and manage multiple repositories with different package managers
- **⚡ Task Execution**: Run tasks across repositories with proper working directory handling
- **🔧 Pipeline System**: Create and execute cross-repository pipelines for complex workflows
- **🎮 Interactive Console**: Minecraft-like interactive console for real-time repository management
- **🔌 Plugin System**: Extensible plugin architecture with built-in plugins:
  - **Turbo Compatibility**: Turborepo-compatible caching and logging
  - **Desktop Notifications**: Cross-platform notifications for task completion
  - **Docker Runner**: Run tasks in containerized environments
- **📊 Resource Monitoring**: Monitor CPU and memory usage with configurable limits
- **⚙️ Configuration Management**: YAML-based configuration with live settings updates
- **🎨 Beautiful UI**: Colored output with progress indicators and status displays
- **🛡️ Error Handling**: Robust error handling with clear user feedback

## 🚀 Quick Start

### Installation

For alpha period, only command line install will be provided.

#### Windows
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1'))
```

#### Posix (Linux/macOS)
```bash
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash
# or
wget -qO- https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash
```

### Basic Usage

```bash
# Initialize ZR configuration
zr init

# Add repositories
zr repo add frontend ./packages/frontend dev "npm run dev"
zr repo add backend ./packages/backend dev "cargo run"

# Run tasks
zr run frontend dev
zr run backend dev

# Create and run pipelines
zr pipeline add full-dev frontend:dev,backend:dev
zr pipeline run full-dev

# Interactive mode
zr interactive

# List repositories and pipelines
zr list

# Check status
zr status

# Manage settings
zr settings get max_cpu
zr settings set max_cpu 90
```

## 📋 Commands

### General Commands
- `zr init` - Initialize ZR configuration
- `zr interactive` - Start interactive console mode
- `zr status` - Show current status and resource usage
- `zr help` - Show help message

### Repository Management
- `zr repo add <name> <path> [task] [command]` - Add a new repository
- `zr repo remove <name>` - Remove a repository
- `zr repo list` - List all repositories
- `zr run <repo> <task>` - Run a task in a repository

### Pipeline Management
- `zr pipeline add <name> <repo1:task1,repo2:task2,...>` - Create a pipeline
- `zr pipeline remove <name>` - Remove a pipeline
- `zr pipeline run <name>` - Execute a pipeline
- `zr pipeline list` - List all pipelines

### Settings Management
- `zr settings get [key]` - Get current settings
- `zr settings set <key> <value>` - Update a setting

## 🔧 Configuration

ZR uses YAML configuration files (`.zr.config.yaml`). See the complete specification in [zr.config.spec.yaml](./zr.config.spec.yaml).

### Example Configuration

```yaml
# Global settings
global:
  resources:
    max_cpu_percent: 80
    max_memory_mb: 4096
    max_concurrent_tasks: 10
  interface:
    interactive_mode: true
    show_progress: true
    color_output: true

# Repository definitions
repositories:
  - name: "frontend"
    path: "./packages/frontend"
    tasks:
      - name: "dev"
        command: "npm run dev"
      - name: "build"
        command: "npm run build"

  - name: "backend"
    path: "./packages/backend"
    tasks:
      - name: "dev"
        command: "cargo run"
      - name: "test"
        command: "cargo test"

# Cross-repository pipelines
pipelines:
  - name: "full-dev"
    description: "Start full development environment"
    stages:
      - name: "development"
        parallel: true
        repositories:
          - repository: "backend"
            task: "dev"
          - repository: "frontend"
            task: "dev"

# Plugin configuration
plugins:
  enabled: true
  directory: "./zr-plugins"
  builtin:
    - name: "turbo-compat"
      enabled: true
    - name: "notification"
      enabled: true
    - name: "docker-runner"
      enabled: false
```

## 🔌 Plugin System

ZR features a powerful plugin system that allows extending functionality:

### Built-in Plugins

- **Turbo Compatibility** (`turbo-compat`): Provides Turborepo-compatible caching and logging
- **Notifications** (`notification`): Desktop notifications for task completion/failure
- **Docker Runner** (`docker-runner`): Run tasks in Docker containers

### Plugin Development

Plugins implement the `PluginInterface` with lifecycle hooks:

```zig
pub const PluginInterface = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    
    // Lifecycle callbacks
    init: ?*const fn(allocator: std.mem.Allocator, config: []const u8) PluginError!void,
    deinit: ?*const fn() void,
    
    // Hook implementations
    beforeTask: ?*const fn(repo: []const u8, task: []const u8) PluginError!void,
    afterTask: ?*const fn(repo: []const u8, task: []const u8, success: bool) PluginError!void,
    beforePipeline: ?*const fn(pipeline: []const u8) PluginError!void,
    afterPipeline: ?*const fn(pipeline: []const u8, success: bool) PluginError!void,
    onResourceLimit: ?*const fn(cpu_percent: f32, memory_mb: u32) PluginError!void,
};
```

## 🎮 Interactive Mode

ZR provides a beautiful interactive console for real-time management:

```
╔══════════════════════════════════════════════════════════════╗
║                     ZR Interactive Console                   ║
║          Ultimate Language Agnostic Command Runner          ║
║                                                              ║
║  Type 'help' for available commands or 'exit' to quit       ║
╚══════════════════════════════════════════════════════════════╝

📊 ZR Status:
  📁 Repositories: 5
  🔄 Pipelines: 2
  ⚡ Running tasks: 0

zr> run frontend dev
🚀 Running task 'dev' in repository 'frontend'
  🔄 [turbo] frontend:dev starting
  🔧 Executing: npm run dev
  📝 Output: Server running on http://localhost:3000
  🔄 [turbo] frontend:dev ✅ completed
  🔔 [✅] ZR Task Completed: Task frontend:dev completed successfully
✅ Task completed successfully

zr> exit
👋 Goodbye!
```

## 🛠️ Development

### Prerequisites
- Zig 0.14.1+

### Building from Source
```bash
git clone https://github.com/yusa-imit/zr
cd zr
zig build
```

### Running Tests
```bash
zig build test
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Inspired by [Turborepo](https://turbo.build/) for monorepo management
- Built with [Zig](https://ziglang.org/) for performance and reliability
- Designed with developer experience in mind