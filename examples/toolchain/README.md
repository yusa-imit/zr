# Toolchain Management Example

This example demonstrates zr's built-in toolchain management capabilities (Phase 6 feature).

## What is Toolchain Management?

Instead of manually installing and managing:
- nvm for Node.js
- pyenv for Python
- gvm for Go
- rbenv for Ruby

zr provides **unified toolchain management** for all languages.

## Features Demonstrated

- **Declarative toolchain versions** in zr.toml
- **Automatic installation** of required versions
- **Per-project isolation** (different projects = different versions)
- **Toolchain switching** based on task requirements
- **Version locking** for reproducible builds
- **Matrix testing** across multiple versions

## Usage

### Install Required Toolchains

```bash
# Install all toolchains declared in zr.toml
zr setup

# List installed toolchains
zr tools list

# Install a specific version manually
zr tools install node@20.11.1
zr tools install python@3.12.0
zr tools install go@1.22
```

### Run Tasks with Managed Toolchains

```bash
# These automatically use the declared versions
zr run node-version    # Uses node@20.11.1
zr run python-version  # Uses python@3.12.0
zr run go-build        # Uses go@1.22

# Build with correct Node version
zr run build
```

### Check Toolchain Status

```bash
# List all installed toolchains
zr tools list

# Show versions by type
zr tools list node
zr tools list python

# Check for outdated versions
zr tools outdated
```

## Toolchain Configuration

### Basic Declaration

```toml
[toolchains]
node = "20.11.1"
python = "3.12.0"
go = "1.22"
```

### Advanced Options

```toml
[toolchains.config]
auto_install = true      # Install missing versions automatically
prefer_system = false    # Don't fall back to system versions
cache_dir = "~/.zr/toolchains"  # Where to store toolchains
```

## Matrix Testing Across Versions

Test your code against multiple toolchain versions:

```toml
[tasks.test-matrix]
command = "npm test"
matrix.toolchain = [
    { node = "18.19.0" },
    { node = "20.11.1" },
    { node = "21.6.0" }
]
```

```bash
# Runs tests on all three Node versions
zr run test-matrix
```

## Benefits

### Before (with nvm/pyenv/etc)

```bash
# Install version managers
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
curl https://pyenv.run | bash

# Install versions
nvm install 20.11.1
pyenv install 3.12.0

# Switch versions per project
cd project-a && nvm use 18.19.0
cd project-b && nvm use 20.11.1
```

### After (with zr)

```bash
# Install zr (one time)
brew install zr

# All projects automatically use correct versions
cd project-a && zr run build  # Uses node@18.19.0
cd project-b && zr run build  # Uses node@20.11.1
```

## How It Works

1. **Toolchain Declaration** - You declare versions in `zr.toml`
2. **Automatic Download** - zr downloads and caches toolchains in `~/.zr/toolchains/`
3. **PATH Injection** - When running tasks, zr injects the correct version into PATH
4. **Version Locking** - Each project uses its declared versions, no conflicts

## Supported Toolchains

Currently supported:
- Node.js
- Python
- Go
- (More coming in future releases)

## Environment Variables

zr sets these environment variables for tasks:

```bash
ZR_NODE_VERSION=20.11.1
ZR_PYTHON_VERSION=3.12.0
ZR_GO_VERSION=1.22
```

## Updating Versions

```bash
# Update Node version in zr.toml
[toolchains]
node = "20.12.0"  # Changed from 20.11.1

# Install new version
zr setup

# Old version still cached for other projects
zr tools list node
# Output:
#   20.11.1 (used by: project-a)
#   20.12.0 (used by: project-b)
```

## Reproducible Builds

Team members and CI/CD get identical environments:

```bash
# Developer A
git clone repo && zr setup && zr run build

# Developer B (gets same versions)
git clone repo && zr setup && zr run build

# CI/CD (gets same versions)
- run: zr setup
- run: zr run build
```

No more "works on my machine" issues!
