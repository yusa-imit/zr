# Plugin Usage Example

This example demonstrates zr's plugin system, including built-in plugins and custom plugins.

## Plugin Types

### Built-in Plugins
zr includes several built-in plugins:

- **env** - Load environment variables from .env files
- **git** - Provide git repository information to tasks

### Custom Plugins
You can create custom plugins in:
- **Local directories** - `path = "./plugins/my-plugin"`
- **Git repositories** - `url = "https://github.com/user/zr-plugin-name.git"`

## Features Demonstrated

- **Loading built-in plugins** (`env`, `git`)
- **Installing plugins from local paths**
- **Installing plugins from git repositories**
- **Configuring plugin behavior**
- **Using plugin-provided environment variables**
- **Plugin lifecycle hooks** (on_init, on_before_task, on_after_task)

## Usage

```bash
# List all plugins
zr plugin list

# List available built-in plugins
zr plugin builtins

# Search for installed plugins
zr plugin search notifier

# Install a plugin from a local path
zr plugin install ./plugins/my-plugin

# Install a plugin from git
zr plugin install https://github.com/example/zr-plugin-slack.git

# Remove a plugin
zr plugin remove slack-notifier

# Update a plugin
zr plugin update slack-notifier

# Show plugin info
zr plugin info env

# Create a new plugin template
zr plugin create my-plugin
```

## Built-in Plugin: env

The `env` plugin loads environment variables from files:

```toml
[plugins.env]
enabled = true

[plugins.env.config]
files = [".env", ".env.local"]  # Files to load
override = true                  # Override existing vars
```

Files are loaded in order, later files override earlier ones.

```bash
# .env file
DATABASE_URL=postgresql://localhost/mydb
API_KEY=secret123

# Task using env vars
zr run deploy  # Has access to DATABASE_URL, API_KEY
```

## Built-in Plugin: git

The `git` plugin provides git repository information:

```toml
[plugins.git]
enabled = true

[plugins.git.config]
include_commit = true   # Set GIT_COMMIT
include_branch = true   # Set GIT_BRANCH
include_dirty = true    # Set GIT_DIRTY (true if uncommitted changes)
```

Available environment variables:
- `GIT_COMMIT` - Current commit SHA
- `GIT_BRANCH` - Current branch name
- `GIT_DIRTY` - "true" if working tree is dirty
- `GIT_TAG` - Current tag (if on a tag)

```bash
# Use in tasks
zr run git-info
# Output: Branch: main, Commit: abc123...
```

## Creating Custom Plugins

### Plugin Structure

```
plugins/my-plugin/
├── plugin.toml         # Plugin metadata
├── plugin.so           # Compiled plugin (C/C++/Rust)
└── README.md           # Documentation
```

### plugin.toml

```toml
[plugin]
name = "my-plugin"
version = "1.0.0"
description = "Custom plugin for notifications"
author = "Your Name"

[hooks]
on_init = true
on_before_task = true
on_after_task = true
```

### Creating from Template

```bash
zr plugin create my-plugin
cd plugins/my-plugin
# Edit plugin_impl.c
make
```

This creates a plugin template with C hooks:
- `zr_on_init()` - Called when plugin loads
- `zr_on_before_task(task_name)` - Called before each task
- `zr_on_after_task(task_name, exit_code)` - Called after each task

## Plugin Configuration

Pass configuration to plugins:

```toml
[plugins.slack-notifier.config]
webhook_url = "${SLACK_WEBHOOK}"
channel = "#builds"
notify_on = ["success", "failure"]
```

The plugin receives these as environment variables:
- `PLUGIN_CONFIG_WEBHOOK_URL`
- `PLUGIN_CONFIG_CHANNEL`
- `PLUGIN_CONFIG_NOTIFY_ON`

## Plugin Discovery

```bash
# Find plugins
zr plugin search notification
zr plugin search slack

# Get detailed info
zr plugin info slack-notifier
```

## See Also

- [Plugin Development Guide](../../docs/PLUGIN_DEV_GUIDE.md) - How to write plugins
- [Plugin Guide](../../docs/PLUGIN_GUIDE.md) - Plugin API reference
