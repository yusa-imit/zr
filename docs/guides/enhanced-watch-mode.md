# Enhanced Watch Mode & Live Reload

Guide to zr's file watching capabilities with adaptive debouncing and browser live reload.

## Table of Contents

- [Overview](#overview)
- [Basic Watch Mode](#basic-watch-mode)
- [Adaptive Debouncing](#adaptive-debouncing)
- [Live Reload Server](#live-reload-server)
- [Watch Configuration](#watch-configuration)
- [Pattern Filtering](#pattern-filtering)
- [Real-World Examples](#real-world-examples)
- [Best Practices](#best-practices)
- [Comparison with Other Tools](#comparison-with-other-tools)
- [Troubleshooting](#troubleshooting)

---

## Overview

zr's watch mode automatically re-runs tasks when files change, with intelligent debouncing and optional browser live reload. This guide covers:

- **Adaptive debouncing**: Automatically adjusts delay based on change frequency
- **Live reload server**: Built-in WebSocket server for browser auto-refresh
- **Pattern filtering**: Watch only relevant files using glob patterns
- **Native file watching**: Uses inotify (Linux), kqueue (macOS), ReadDirectoryChangesW (Windows)

---

## Basic Watch Mode

### Running a Task on File Changes

```bash
# Watch current directory, re-run 'build' on any change
zr watch build

# Watch specific directories
zr watch build src/ tests/

# Watch with custom debounce delay (default: 300ms)
zr watch build --debounce=500ms
```

### How It Works

1. **Initial run**: Task runs immediately when watch starts
2. **File monitoring**: Watches specified paths (or current directory) for changes
3. **Debouncing**: Groups rapid file changes into single execution
4. **Re-execution**: Re-runs task when debounce period expires
5. **Loop**: Continues until Ctrl+C

---

## Adaptive Debouncing

Adaptive debouncing automatically adjusts the delay based on change frequency, preventing re-run spam during heavy file activity while staying responsive for isolated changes.

### Enabling Adaptive Debouncing

**In zr.toml**:
```toml
[tasks.dev]
cmd = "npm run dev"

[tasks.dev.watch]
debounce_ms = 300           # Initial/min delay (default: 300ms)
adaptive_debounce = true     # Enable adaptive adjustment
```

**CLI override**:
```bash
zr watch dev --adaptive-debounce
```

### How It Works

- **Burst detection**: When >5 changes occur in 5 seconds, delay increases
- **Sporadic detection**: When <2 changes occur in 60 seconds, delay decreases
- **Smooth ramping**: Gradual adjustment (no sudden jumps)
- **Bounds**: Min = configured `debounce_ms`, Max = 10x min (e.g., 300ms → 3000ms)

### Example Behavior

```
# Initial state
debounce_ms = 300           # Min: 300ms, Max: 3000ms

# Rapid edits (6 changes in 5s) → burst detected
Change 1:    300ms delay
Change 2:    450ms delay   ↑ ramping up
Change 3:    600ms delay   ↑
Change 4:    900ms delay   ↑
Change 5:   1200ms delay   ↑
Change 6:   1500ms delay   ↑ (prevents spam during active editing)

# Pause editing (90s, <2 changes) → sporadic detected
Change 7:   1200ms delay   ↓ ramping down
Change 8:    900ms delay   ↓
Change 9:    600ms delay   ↓
Change 10:   300ms delay   ↓ (back to min for quick response)
```

### Use Cases

- **Web development**: Editing multiple files simultaneously (CSS, JS, HTML)
- **Generated code**: Watching files that trigger code generators
- **Large projects**: Many files changing during operations (git checkout, npm install)
- **Live demos**: Quick response for isolated tweaks, stability during refactoring

---

## Live Reload Server

The built-in WebSocket server automatically refreshes browser tabs when tasks succeed, eliminating manual browser refresh during development.

### Enabling Live Reload

**In zr.toml**:
```toml
[tasks.dev]
cmd = "npm run dev"

[tasks.dev.watch]
live_reload = true
live_reload_port = 35729    # Optional, default: 35729
```

**CLI override**:
```bash
zr watch dev --live-reload
zr watch dev --live-reload --live-reload-port=8080
```

### Browser Integration

Add this snippet to your HTML (development only):

```html
<script>
  // Connect to zr live reload server
  const ws = new WebSocket('ws://localhost:35729');
  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    if (msg.command === 'reload') {
      console.log(`[zr] Reloading due to change: ${msg.path}`);
      window.location.reload();
    }
  };
  ws.onerror = () => console.warn('[zr] Live reload server not connected');
</script>
```

Or use a development server that injects the script automatically (Vite, webpack-dev-server support custom ports).

### Protocol

Live reload uses the standard LiveReload protocol over WebSocket:

```json
// Message sent to all connected clients on task success
{
  "command": "reload",
  "path": "/path/to/changed/file"
}
```

### Server Lifecycle

```
Task start → Live reload server starts → Listens on port 35729
  ↓
File change detected → Task runs → Success
  ↓
Send reload message to all connected clients
  ↓
Browser receives message → window.location.reload()
  ↓
Ctrl+C → Server stops → Connections closed
```

---

## Watch Configuration

### WatchConfig Fields

```toml
[tasks.build.watch]
# Debounce delay (ms) before running task after changes
debounce_ms = 300

# Glob patterns to watch (if empty, watches all files)
patterns = ["src/**/*.ts", "package.json"]

# Glob patterns to exclude
exclude_patterns = ["node_modules/**", "dist/**", ".git/**"]

# Adaptive debouncing (adjust delay based on change frequency)
adaptive_debounce = true

# Live reload server
live_reload = true
live_reload_port = 35729
```

### Configuration Precedence

1. **CLI flags**: `--debounce=500ms`, `--adaptive-debounce`, `--live-reload`
2. **Task-level WatchConfig**: `[tasks.build.watch]`
3. **Defaults**: debounce_ms=300, adaptive_debounce=false, live_reload=false

---

## Pattern Filtering

### Watch Specific File Types

```toml
[tasks.build.watch]
# Watch only TypeScript and JSON files
patterns = ["**/*.ts", "**/*.json"]

# Watch frontend source files (exclude backend)
patterns = ["src/client/**/*"]
exclude_patterns = ["src/server/**/*"]
```

### Multiple Patterns

```toml
[tasks.test.watch]
# Watch source files and test files
patterns = [
    "src/**/*.ts",     # Source files
    "tests/**/*.ts",   # Test files
    "*.config.js"      # Config files
]

# Exclude build outputs and dependencies
exclude_patterns = [
    "dist/**",
    "node_modules/**",
    "coverage/**"
]
```

### Pattern Syntax

- `*`: Match any characters except `/` (e.g., `*.ts` = all .ts files in current dir)
- `**`: Match any characters including `/` (e.g., `**/*.ts` = all .ts files recursively)
- `?`: Match single character (e.g., `test?.ts` = test1.ts, testA.ts)

---

## Real-World Examples

### Web Development with Live Reload

```toml
[tasks.dev]
cmd = "npm run dev"     # Start development server
deps = ["build:css"]    # Build CSS first

[tasks.dev.watch]
patterns = [
    "src/**/*.tsx",     # React components
    "src/**/*.css",     # Stylesheets
    "public/**/*"       # Static assets
]
exclude_patterns = [
    "dist/**",          # Build output
    "node_modules/**"
]
adaptive_debounce = true
live_reload = true
live_reload_port = 35729

[tasks.build:css]
cmd = "tailwindcss -i src/input.css -o dist/output.css"
```

**Usage**:
```bash
# Start dev server with live reload
zr watch dev

# Browser auto-refreshes on file save
# Adaptive debounce prevents spam during multi-file edits
```

### Test Runner with Smart Debouncing

```toml
[tasks.test]
cmd = "vitest run"

[tasks.test.watch]
patterns = ["src/**/*.ts", "tests/**/*.test.ts"]
exclude_patterns = ["coverage/**", "**/*.d.ts"]
debounce_ms = 500        # Higher delay (tests are slower)
adaptive_debounce = true # Adjust during heavy refactoring
```

**Usage**:
```bash
zr watch test

# Tests re-run on file save
# Delay increases during heavy refactoring (many files changing)
# Delay decreases during normal editing (isolated changes)
```

### Backend API Development

```toml
[tasks.api]
cmd = "go run cmd/api/main.go"

[tasks.api.watch]
patterns = [
    "**/*.go",          # Go source files
    "api/**/*.yaml",    # OpenAPI specs
    "migrations/**/*.sql"
]
exclude_patterns = [
    "vendor/**",
    "**/*_test.go"      # Don't restart server on test file changes
]
debounce_ms = 1000      # Higher delay (server restart is expensive)
```

**Usage**:
```bash
zr watch api

# Server restarts on source changes
# Longer debounce prevents rapid restarts
```

### Documentation Site

```toml
[tasks.docs]
cmd = "mkdocs serve"

[tasks.docs.watch]
patterns = [
    "docs/**/*.md",
    "mkdocs.yml"
]
live_reload = true
live_reload_port = 8001  # Custom port (mkdocs uses 8000)
```

**Usage**:
```bash
zr watch docs

# Docs rebuild on markdown changes
# Browser auto-refreshes with live reload
```

---

## Best Practices

### 1. Use Adaptive Debouncing for Interactive Workflows

Enable adaptive debouncing when:
- Editing multiple files simultaneously (refactoring)
- Using code generators (protobuf, GraphQL)
- Working in monorepos (one change may affect many files)

```toml
[tasks.dev.watch]
adaptive_debounce = true   # ✅ Prevents spam during bursts
```

### 2. Configure Higher Base Debounce for Expensive Tasks

Set `debounce_ms` higher for tasks that take longer to run:

```toml
# Fast task (type checking)
[tasks.typecheck.watch]
debounce_ms = 200

# Slow task (full build)
[tasks.build.watch]
debounce_ms = 1000
```

### 3. Use Exclude Patterns Liberally

Prevent watch loops by excluding output directories:

```toml
[tasks.build.watch]
patterns = ["src/**/*"]
exclude_patterns = [
    "dist/**",           # ✅ Build output
    "node_modules/**",   # ✅ Dependencies
    ".git/**",           # ✅ Version control
    "**/*.log"           # ✅ Log files
]
```

### 4. Live Reload Only for Frontend Tasks

Enable live reload only for tasks that output web content:

```toml
# ✅ Good: Frontend dev server
[tasks.frontend.watch]
live_reload = true

# ❌ Bad: Backend API (no browser to reload)
[tasks.api.watch]
live_reload = false
```

### 5. Combine with Up-to-Date Detection

Use `sources`/`generates` to skip watch runs when outputs are already fresh:

```toml
[tasks.build]
cmd = "tsc"
sources = ["src/**/*.ts", "tsconfig.json"]
generates = ["dist/**/*.js"]

[tasks.build.watch]
patterns = ["src/**/*.ts"]
# Task skips if dist/ is already up-to-date
```

### 6. Multiple Watch Processes for Different Contexts

Run separate watch processes for frontend/backend:

```bash
# Terminal 1: Watch frontend
zr watch frontend

# Terminal 2: Watch backend
zr watch backend

# Both run independently with different debounce/patterns
```

---

## Comparison with Other Tools

### vs nodemon

| Feature | zr watch | nodemon |
|---------|----------|---------|
| Adaptive debounce | ✅ Automatic | ❌ Manual tuning |
| Live reload | ✅ Built-in | ❌ Requires browser-sync |
| Pattern filtering | ✅ Glob patterns | ✅ Glob patterns |
| Cross-platform | ✅ Native (inotify/kqueue) | ✅ chokidar |
| Config | ✅ TOML | ✅ JSON/CLI |

### vs watchexec

| Feature | zr watch | watchexec |
|---------|----------|-----------|
| Adaptive debounce | ✅ Automatic | ❌ Fixed delay |
| Live reload | ✅ Built-in | ❌ None |
| Task integration | ✅ Full task system | ❌ CLI-only |
| Exclude patterns | ✅ Via config | ✅ Via CLI |

### vs Vite/webpack-dev-server

| Feature | zr watch | Vite |
|---------|----------|------|
| Live reload | ✅ Any task | ✅ Frontend only |
| Adaptive debounce | ✅ Yes | ❌ Fixed |
| General purpose | ✅ Any command | ❌ JS/TS only |
| HMR | ❌ Full reload | ✅ Module replacement |

**When to use zr watch**:
- Non-JS projects (Go, Rust, Python, etc.)
- Backend development (APIs, services)
- Custom build pipelines
- Multi-language projects

**When to use Vite**:
- Pure frontend development
- Need HMR (Hot Module Replacement)
- Complex webpack-like bundling

---

## Troubleshooting

### "Live reload server not connected" in browser

**Symptom**: Browser console shows WebSocket connection error.

**Causes**:
1. Live reload server not started (check `live_reload = true` in config)
2. Port mismatch (check `live_reload_port` in config matches browser script)
3. Firewall blocking port 35729

**Fix**:
```toml
# Verify config
[tasks.dev.watch]
live_reload = true
live_reload_port = 35729
```

```bash
# Check if port is in use
lsof -i :35729

# Try different port
zr watch dev --live-reload-port=8080
```

### Task runs too frequently (spam)

**Symptom**: Task re-runs rapidly during file edits.

**Causes**:
1. Debounce delay too low
2. Output directory not excluded (watch loop)
3. Many files changing simultaneously

**Fix**:
```toml
[tasks.build.watch]
debounce_ms = 500           # Increase delay
adaptive_debounce = true     # Enable adaptive adjustment
exclude_patterns = [
    "dist/**",              # Exclude output directory
    "node_modules/**"
]
```

### Task doesn't re-run on file changes

**Symptom**: File changes detected but task doesn't run.

**Causes**:
1. Changed file doesn't match `patterns`
2. Changed file matches `exclude_patterns`
3. Watcher mode fell back to polling (slower detection)

**Fix**:
```bash
# Check watch mode in output
zr watch build
# Look for: "(using native mode" or "(using polling mode"

# Verify patterns match your files
zr watch build --verbose

# Try explicit pattern
zr watch build src/**/*.ts
```

### "Too many open files" error (Linux)

**Symptom**: Watch fails with EMFILE error.

**Cause**: inotify limit too low for large projects.

**Fix**:
```bash
# Check current limit
cat /proc/sys/fs/inotify/max_user_watches

# Increase limit (temporary)
sudo sysctl fs.inotify.max_user_watches=524288

# Increase limit (permanent)
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Adaptive debounce stuck at high delay

**Symptom**: Delay stays at 2-3 seconds even after editing slows down.

**Cause**: Sporadic detection window (60s) hasn't passed yet.

**Fix**: Wait 60 seconds without editing, or restart watch:
```bash
# Ctrl+C to stop, then restart
zr watch build
```

---

## See Also

- [Task Up-to-Date Detection](incremental-builds.md) — Skip watch runs when outputs are fresh
- [Task Parameters](parameterized-tasks.md) — Pass parameters to watched tasks
- [Environment Management](environment-management.md) — Env vars for watch mode
- [Task Configuration Reference](../reference/task-config.md) — Full WatchConfig schema
