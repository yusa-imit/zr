# zr Plugin Development Guide

> **Target Audience**: Plugin developers who want to extend zr's functionality

---

## Table of Contents

1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Plugin Architecture](#plugin-architecture)
4. [C ABI Interface](#c-abi-interface)
5. [Plugin Lifecycle](#plugin-lifecycle)
6. [Configuration](#configuration)
7. [Built-in Plugins](#built-in-plugins)
8. [Publishing](#publishing)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

---

## Introduction

zr's plugin system allows you to extend task execution with custom logic. Plugins can:

- Hook into task lifecycle events (before/after task execution)
- Modify environment variables
- Integrate with external services (webhooks, notifications, Docker, etc.)
- Implement custom caching strategies
- Track execution metrics

Plugins are **shared libraries** (`.so` on Linux, `.dylib` on macOS, `.dll` on Windows) loaded dynamically at runtime via zr's native loader.

---

## Quick Start

### Create a Plugin

```bash
# Scaffold a new plugin
zr plugin create my-plugin

# Navigate to the generated directory
cd my-plugin/

# Build the plugin (generates my-plugin.dylib or my-plugin.so)
make

# Install locally
make install
```

### Use the Plugin

Add to your `zr.toml`:

```toml
[plugins.my-plugin]
source = "my-plugin.dylib"  # or "my-plugin.so" on Linux
```

Run any task:

```bash
zr run build
# Output:
# [my-plugin] plugin initialized
# [my-plugin] before task: build
# ... task runs ...
# [my-plugin] after task: build (exit 0)
```

---

## Plugin Architecture

### Directory Structure

A plugin is a directory containing:

```
my-plugin/
├── plugin.toml          # Metadata (name, version, description, author)
├── plugin.h             # C ABI interface (optional, for reference)
├── plugin_impl.c        # Your implementation (C/C++/Rust/Zig/etc.)
├── Makefile             # Build script
└── README.md            # Documentation
```

### Plugin Metadata (`plugin.toml`)

```toml
name = "my-plugin"
version = "0.1.0"
description = "A zr plugin that does X"
author = "Your Name <your@email.com>"
```

This file is read by `zr plugin info <name>` and displayed in `zr plugin list`.

---

## C ABI Interface

Plugins communicate with zr via a **C ABI** (compatible with any language that can export C symbols).

### Hook Functions

Your plugin **may** export any or all of these functions:

```c
void zr_on_init(void);
void zr_on_before_task(const char *task_name);
void zr_on_after_task(const char *task_name, int exit_code);
```

All hooks are **optional**. If zr doesn't find a symbol, it skips the hook.

### Function Signatures

#### `zr_on_init`

```c
void zr_on_init(void);
```

- **When**: Called once when zr loads the plugin (before any tasks run)
- **Use**: Initialize state, read config from environment, allocate resources
- **Example**:

```c
void zr_on_init(void) {
    fprintf(stderr, "[my-plugin] initialized\n");
}
```

#### `zr_on_before_task`

```c
void zr_on_before_task(const char *task_name);
```

- **When**: Called immediately before each task starts
- **Parameters**:
  - `task_name`: Null-terminated string (UTF-8)
- **Use**: Set environment vars, start timers, log task start
- **Example**:

```c
void zr_on_before_task(const char *task_name) {
    time_t now = time(NULL);
    fprintf(stderr, "[my-plugin] starting task '%s' at %ld\n", task_name, now);
}
```

#### `zr_on_after_task`

```c
void zr_on_after_task(const char *task_name, int exit_code);
```

- **When**: Called immediately after each task completes
- **Parameters**:
  - `task_name`: Null-terminated string (UTF-8)
  - `exit_code`: Task's exit code (0 = success, non-zero = failure)
- **Use**: Send notifications, record metrics, cleanup
- **Example**:

```c
void zr_on_after_task(const char *task_name, int exit_code) {
    if (exit_code != 0) {
        fprintf(stderr, "[my-plugin] task '%s' failed with code %d\n",
                task_name, exit_code);
    }
}
```

---

## Plugin Lifecycle

### Load Order

1. **Parse zr.toml** → zr reads `[plugins.X]` sections
2. **Load plugins** → `std.DynLib.open()` loads each shared library
3. **Call `zr_on_init`** → Each plugin initializes (if hook exists)
4. **Run tasks** → For each task:
   - Call `zr_on_before_task(task_name)`
   - Execute task
   - Call `zr_on_after_task(task_name, exit_code)`

### Memory Management

- **Stateless hooks**: zr doesn't manage plugin memory; you must free your own allocations
- **Global state**: Use `static` or `global` variables if you need state between hooks
- **Thread safety**: Hooks may be called from **multiple threads** concurrently (if parallel tasks run). Use locks if needed.

---

## Configuration

### Passing Config to Plugins

In `zr.toml`:

```toml
[plugins.notify]
source = "notify.dylib"
config = { webhook = "https://hooks.slack.com/...", channel = "#deploys" }
```

**Current limitation**: zr doesn't pass `config` to plugin hooks yet. To access config:

1. Use **environment variables**:
   ```toml
   [plugins.notify]
   source = "notify.dylib"

   [tasks.deploy]
   cmd = "deploy.sh"
   env = { WEBHOOK_URL = "https://..." }
   ```

2. Read from plugin's own config file (e.g., `~/.zr/plugins/notify/config.json`)

Future versions will pass config as JSON string to `zr_on_init`.

---

## Built-in Plugins

zr ships with 5 built-in plugins (compiled into the binary, no installation needed):

### 1. **env** — Environment Variables

```toml
[plugins.env]
source = "builtin:env"
config = { dotenv = ".env.production" }
```

**Features**:
- `loadDotEnv(path)`: Load `.env` file into process environment
- Used automatically if task has `dotenv = true`

### 2. **git** — Git Integration

```toml
[plugins.git]
source = "builtin:git"
```

**Features**:
- `currentBranch()`: Get current branch name
- `changedFiles()`: List changed files since last commit
- `lastCommitMessage()`: Get last commit message
- `fileHasChanges(path)`: Check if file has uncommitted changes

### 3. **notify** — Webhook Notifications

```toml
[plugins.notify]
source = "builtin:notify"
config = { webhook = "https://hooks.slack.com/..." }
```

**Features**:
- `sendWebhook(url, json_payload)`: Send HTTP POST with JSON body
- Supports Slack, Discord, generic webhooks

### 4. **cache** — Task Output Caching

```toml
[plugins.cache]
source = "builtin:cache"
config = { max_age_seconds = 3600, clear_on_start = false }
```

**Features**:
- Integrates with zr's cache system (`~/.zr/cache/`)
- `evictStaleEntries()`: Remove cache entries older than `max_age_seconds`
- `clear_on_start = true`: Clear all cache on `zr_on_init`

### 5. **docker** — Docker Integration (Stub)

```toml
[plugins.docker]
source = "builtin:docker"
```

**Status**: Not yet implemented (reserved for future).

---

## Publishing

### 1. Local Installation

```bash
# Install from local directory
zr plugin install ./my-plugin my-plugin
```

Your plugin is copied to `~/.zr/plugins/my-plugin/`.

### 2. Git Installation

```bash
# Install from git URL (https, http, git://, git@)
zr plugin install https://github.com/user/zr-plugin-example my-plugin
```

zr clones the repo with `git clone --depth=1`.

### 3. Registry Installation

```bash
# Install from GitHub registry (shorthand)
zr plugin install registry:user/example@v1.0.0
```

Resolves to `https://github.com/user/zr-plugin-example` and clones tag `v1.0.0`.

**Naming convention**: Registry plugins must be named `zr-plugin-<name>` on GitHub.

### Update Plugins

```bash
# Update a git-installed plugin (runs git pull)
zr plugin update my-plugin

# Update from new local path
zr plugin update my-plugin ./new-path
```

---

## Best Practices

### 1. Error Handling

- **Fail gracefully**: Don't crash zr with `abort()` or `exit()`
- **Log errors**: Use `stderr` for diagnostics
- **Return early**: If initialization fails, skip work in other hooks

```c
static bool initialized = false;

void zr_on_init(void) {
    if (setup_fails()) {
        fprintf(stderr, "[plugin] init failed, plugin disabled\n");
        return;  // Don't set initialized
    }
    initialized = true;
}

void zr_on_before_task(const char *task_name) {
    if (!initialized) return;  // Skip work if init failed
    // ...
}
```

### 2. Thread Safety

If your plugin uses global state, protect it with mutexes:

```c
#include <pthread.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int counter = 0;

void zr_on_before_task(const char *task_name) {
    pthread_mutex_lock(&lock);
    counter++;
    pthread_mutex_unlock(&lock);
}
```

### 3. Performance

- **Minimize blocking**: Hooks block task execution; avoid long-running work
- **Async notifications**: If sending webhooks, consider non-blocking HTTP calls
- **Lazy initialization**: Only allocate resources when needed

### 4. Cross-Platform

- **Test on Linux + macOS**: zr targets both platforms
- **Use portable APIs**: Avoid platform-specific syscalls
- **Makefile OS detection**: See generated Makefile for reference

```makefile
UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    LIB = plugin.dylib
    LDFLAGS = -dynamiclib
else
    LIB = plugin.so
    LDFLAGS = -shared
endif
```

### 5. Documentation

Include a `README.md` with:

- What the plugin does
- Configuration options (env vars, config keys)
- Example `zr.toml` snippet
- Build/install instructions

---

## Troubleshooting

### Plugin Not Loading

**Symptom**: `zr plugin list` doesn't show your plugin, or hooks don't fire.

**Solutions**:

1. **Check `plugin.toml` exists**:
   ```bash
   ls ~/.zr/plugins/my-plugin/plugin.toml
   ```

2. **Verify shared library exists**:
   ```bash
   # macOS:
   ls ~/.zr/plugins/my-plugin/*.dylib
   # Linux:
   ls ~/.zr/plugins/my-plugin/*.so
   ```

3. **Check zr.toml syntax**:
   ```toml
   [plugins.my-plugin]
   source = "my-plugin.dylib"  # Must match library name
   ```

4. **Check for symbol export**:
   ```bash
   # macOS:
   nm -g my-plugin.dylib | grep zr_on
   # Linux:
   nm -D my-plugin.so | grep zr_on
   ```

   Should show:
   ```
   T _zr_on_init
   T _zr_on_before_task
   T _zr_on_after_task
   ```

### Hooks Not Called

**Symptom**: Plugin loads but hooks never fire.

**Solutions**:

1. **Check symbol names** (no typos, correct case):
   - ✅ `zr_on_init`
   - ❌ `zr_oninit`, `ZR_ON_INIT`, `zr_init`

2. **Ensure C linkage** (if using C++):
   ```cpp
   extern "C" {
       void zr_on_init(void) { /* ... */ }
   }
   ```

3. **Check visibility** (if using Rust/Zig):
   ```rust
   #[no_mangle]
   pub extern "C" fn zr_on_init() { /* ... */ }
   ```

### Segfault or Crash

**Symptom**: zr crashes when loading plugin.

**Solutions**:

1. **Buffer overflows**: Check string handling (use `strncpy`, not `strcpy`)
2. **Null pointers**: Validate `task_name` before use
3. **Memory corruption**: Run with sanitizers:
   ```bash
   # Build plugin with AddressSanitizer:
   cc -shared -fPIC -fsanitize=address plugin_impl.c -o plugin.so
   ```

4. **ABI mismatch**: Ensure plugin is compiled for same architecture as zr:
   ```bash
   file plugin.dylib  # Should match `zig build` target
   ```

---

## Advanced Topics

### Multi-Language Plugins

You can write plugins in **any language** that exports C symbols:

#### **Rust**

```rust
#[no_mangle]
pub extern "C" fn zr_on_init() {
    eprintln!("[rust-plugin] initialized");
}

#[no_mangle]
pub extern "C" fn zr_on_before_task(task_name: *const std::os::raw::c_char) {
    let name = unsafe { std::ffi::CStr::from_ptr(task_name) };
    eprintln!("[rust-plugin] before: {:?}", name);
}
```

Build:
```bash
cargo build --release --crate-type=cdylib
# Output: target/release/libmy_plugin.so (Linux) or .dylib (macOS)
```

#### **Zig**

```zig
export fn zr_on_init() callconv(.C) void {
    std.debug.print("[zig-plugin] initialized\n", .{});
}

export fn zr_on_before_task(task_name: [*:0]const u8) callconv(.C) void {
    std.debug.print("[zig-plugin] before: {s}\n", .{task_name});
}
```

Build:
```bash
zig build-lib plugin.zig -dynamic -lc
```

#### **Go** (with cgo)

```go
package main

import "C"
import "fmt"

//export zr_on_init
func zr_on_init() {
    fmt.Println("[go-plugin] initialized")
}

//export zr_on_before_task
func zr_on_before_task(task_name *C.char) {
    name := C.GoString(task_name)
    fmt.Printf("[go-plugin] before: %s\n", name)
}

func main() {}
```

Build:
```bash
go build -buildmode=c-shared -o plugin.so plugin.go
```

---

## Example: Notification Plugin

Complete example of a Slack notification plugin:

```c
// notify_slack.c
#include "plugin.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char webhook_url[512] = {0};

void zr_on_init(void) {
    const char *url = getenv("SLACK_WEBHOOK");
    if (url) {
        strncpy(webhook_url, url, sizeof(webhook_url) - 1);
        fprintf(stderr, "[notify-slack] webhook configured\n");
    } else {
        fprintf(stderr, "[notify-slack] SLACK_WEBHOOK not set, plugin disabled\n");
    }
}

void zr_on_after_task(const char *task_name, int exit_code) {
    if (webhook_url[0] == '\0') return;  // Not configured

    char cmd[1024];
    const char *emoji = (exit_code == 0) ? ":white_check_mark:" : ":x:";
    snprintf(cmd, sizeof(cmd),
        "curl -X POST -H 'Content-Type: application/json' "
        "-d '{\"text\":\"%s Task `%s` %s (exit %d)\"}' '%s' 2>/dev/null",
        emoji, task_name, (exit_code == 0) ? "succeeded" : "failed",
        exit_code, webhook_url);

    system(cmd);  // Fire and forget
}
```

Usage in `zr.toml`:

```toml
[plugins.notify-slack]
source = "notify_slack.dylib"

[tasks.deploy]
cmd = "deploy.sh"
env = { SLACK_WEBHOOK = "https://hooks.slack.com/services/..." }
```

---

## Future Enhancements

Planned features (not yet implemented):

1. **WASM sandbox**: Load plugins as WebAssembly modules for better security
2. **Config passing**: Pass `[plugins.X.config]` as JSON to `zr_on_init`
3. **Registry index**: Central plugin directory at `zr.dev/plugins`
4. **Plugin templates**: More scaffolds (`zr plugin create --template rust`)
5. **Hook return values**: Plugins can abort tasks by returning non-zero

---

## Resources

- **zr GitHub**: [https://github.com/yusa-imit/zr](https://github.com/yusa-imit/zr)
- **Example Plugins**: See `examples/plugin/` directory
- **Report Issues**: [https://github.com/yusa-imit/zr/issues](https://github.com/yusa-imit/zr/issues)

---

## License

This documentation is part of the zr project and is licensed under the same terms as zr itself.
