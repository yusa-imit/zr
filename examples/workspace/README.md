# Workspace/Monorepo Example

This example demonstrates zr's capabilities for managing monorepos with multiple packages.

## Structure

```
my-monorepo/
├── zr.toml                 # Root configuration
├── packages/
│   ├── core/
│   │   ├── zr.toml         # Package-specific tasks
│   │   ├── package.json
│   │   └── src/
│   ├── ui/
│   │   ├── zr.toml
│   │   ├── package.json
│   │   └── src/
│   └── utils/
│       ├── zr.toml
│       ├── package.json
│       └── src/
└── apps/
    ├── web/
    │   ├── zr.toml
    │   ├── package.json
    │   └── src/
    └── mobile/
        ├── zr.toml
        ├── package.json
        └── src/
```

## Features Demonstrated

- **Workspace definition** with glob patterns
- **Workspace-wide tasks** that run across all members
- **Affected detection** to build only changed packages
- **Input/output tracking** for accurate caching
- **Content-based hashing** for cache invalidation
- **Dependency graph** across workspace members

## Usage

```bash
# List all workspace members
zr workspace list

# Build all packages
zr workspace run build

# Run tests in all packages
zr workspace run test

# Build only affected packages (based on git changes)
zr affected build

# Visualize the workspace dependency graph
zr graph

# Build a specific package (from root)
cd packages/core && zr run build

# Clean all packages
zr workspace run clean
```

## Affected Detection

The `affected` command compares your current branch against `origin/main` and determines which packages have changed. It then:

1. Identifies changed files
2. Maps files to packages
3. Builds dependency graph
4. Runs the task on affected packages + their dependents

```bash
# Build only what changed
zr affected build

# Test only affected packages
zr affected test

# See what would be affected (dry run)
zr affected build --dry-run
```

## Cache Benefits

With content-based caching enabled:
- Tasks skip if inputs unchanged
- Shared cache across workspace
- Significant speedup for large monorepos

```bash
# First run: builds everything
zr workspace run build

# Second run: instant (all cached)
zr workspace run build

# Modify one file: only affected package rebuilds
echo "// change" >> packages/core/src/index.ts
zr affected build  # Only rebuilds core + dependents
```
