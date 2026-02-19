# zr Plugin Guide

> **Target Audience**: zr users who want to use and manage plugins

---

## What Are Plugins?

Plugins extend zr's functionality by hooking into task execution. They can:

- Send notifications when tasks complete (Slack, Discord, email)
- Track execution metrics and timings
- Integrate with Docker, Git, cloud services
- Implement custom caching strategies
- Modify environment variables dynamically

---

## Quick Start

### Install a Plugin

```bash
# From local directory:
zr plugin install ./my-plugin my-plugin

# From git URL:
zr plugin install https://github.com/user/zr-plugin-example example

# From registry (GitHub shorthand):
zr plugin install registry:user/example@v1.0.0
```

### Use a Plugin

Add to your `zr.toml`:

```toml
[plugins.my-plugin]
source = "my-plugin.dylib"  # or "my-plugin.so" on Linux
config = { key = "value" }  # Optional configuration
```

That's it! The plugin now runs automatically when you execute tasks.

---

## Managing Plugins

### List Installed Plugins

```bash
# Text output:
zr plugin list

# JSON output:
zr plugin list --format json
```

Example output:

```
Installed plugins:

  my-plugin
    Version: 0.1.0
    Description: A sample plugin
    Source: /Users/you/.zr/plugins/my-plugin

  slack-notify
    Version: 1.2.0
    Description: Send Slack notifications on task completion
    Source: https://github.com/user/zr-plugin-slack
```

### Search Plugins

```bash
# Search all installed plugins by name/description:
zr plugin search notify

# List all:
zr plugin search
```

### View Plugin Details

```bash
zr plugin info my-plugin
```

Output:

```
Plugin: my-plugin

  Version:     0.1.0
  Description: A sample plugin
  Author:      Your Name <your@email.com>
  Location:    /Users/you/.zr/plugins/my-plugin
```

### Update a Plugin

```bash
# Update from git (runs git pull):
zr plugin update my-plugin

# Update from new local path:
zr plugin update my-plugin ./new-path
```

### Remove a Plugin

```bash
zr plugin remove my-plugin
```

---

## Built-in Plugins

zr ships with 5 built-in plugins (no installation needed):

### 1. **env** — Environment Variables

Load environment variables from `.env` files.

**Example**:

```toml
[plugins.env]
source = "builtin:env"

[tasks.deploy]
cmd = "deploy.sh"
dotenv = true  # Automatically loads .env
```

Or manually load a specific file:

```toml
[plugins.env]
source = "builtin:env"
config = { dotenv = ".env.production" }
```

### 2. **git** — Git Integration

Query Git repository information.

**Example**:

```toml
[plugins.git]
source = "builtin:git"

[tasks.show-branch]
cmd = "echo Current branch: $(git branch --show-current)"
```

**Available functions** (from plugin code):
- Current branch name
- Changed files since last commit
- Last commit message
- Check if file has uncommitted changes

### 3. **notify** — Webhook Notifications

Send HTTP webhooks (Slack, Discord, etc.) when tasks complete.

**Example**:

```toml
[plugins.notify]
source = "builtin:notify"
config = { webhook = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" }

[tasks.deploy]
cmd = "deploy.sh"
# Plugin automatically sends notification after task completes
```

**Supported services**:
- Slack (via incoming webhooks)
- Discord (via webhooks)
- Generic HTTP POST endpoints

### 4. **cache** — Advanced Caching

Manage task output cache with expiration and cleanup.

**Example**:

```toml
[plugins.cache]
source = "builtin:cache"
config = { max_age_seconds = 3600, clear_on_start = false }

[tasks.build]
cmd = "cargo build"
cache = true  # Enable caching for this task
```

**Config options**:
- `max_age_seconds`: Auto-delete cache entries older than this (default: no limit)
- `clear_on_start`: Clear all cache when zr starts (default: false)

### 5. **docker** — Docker Integration

*(Reserved for future implementation)*

---

## Plugin Configuration

### Basic Configuration

Plugins accept configuration via the `config` key:

```toml
[plugins.my-plugin]
source = "my-plugin.dylib"
config = { key1 = "value1", key2 = 42 }
```

**Note**: Currently, plugin config is stored but not passed to plugins. Use environment variables as a workaround:

```toml
[plugins.my-plugin]
source = "my-plugin.dylib"

[tasks.my-task]
cmd = "my-command"
env = { PLUGIN_KEY = "value" }  # Plugin reads from environment
```

### Environment Variables

Many plugins read configuration from environment variables:

```toml
[tasks.deploy]
cmd = "deploy.sh"
env = {
  SLACK_WEBHOOK = "https://hooks.slack.com/...",
  DISCORD_WEBHOOK = "https://discord.com/api/webhooks/..."
}
```

Check each plugin's README for supported variables.

---

## Plugin Sources

### Local Path

```toml
[plugins.my-plugin]
source = "./path/to/plugin.dylib"  # Relative to zr.toml
# or
source = "/absolute/path/to/plugin.dylib"
```

### Installed Plugin

```toml
[plugins.my-plugin]
source = "my-plugin.dylib"  # Looks in ~/.zr/plugins/my-plugin/
```

### Built-in Plugin

```toml
[plugins.cache]
source = "builtin:cache"
```

Available built-ins: `env`, `git`, `notify`, `cache`, `docker` (stub)

---

## Creating Your Own Plugin

See **[Plugin Development Guide](./PLUGIN_DEV_GUIDE.md)** for detailed instructions.

**Quick start**:

```bash
# Scaffold a new plugin:
zr plugin create my-plugin

# Build and install:
cd my-plugin/
make
make install
```

Then add to `zr.toml`:

```toml
[plugins.my-plugin]
source = "my-plugin.dylib"
```

---

## Plugin Lifecycle

When you run `zr run <task>`, plugins execute in this order:

1. **Load plugins** from `zr.toml` `[plugins.*]` sections
2. **Call `zr_on_init()`** for each plugin (once at startup)
3. **For each task**:
   - Call `zr_on_before_task(task_name)` (all plugins)
   - **Execute task**
   - Call `zr_on_after_task(task_name, exit_code)` (all plugins)

**Example output**:

```bash
$ zr run build
[my-plugin] plugin initialized
[my-plugin] before task: build
Building project...
[my-plugin] after task: build (exit 0)
✓ build completed (2.3s)
```

---

## Troubleshooting

### Plugin Not Loading

**Check installation**:

```bash
zr plugin list
# Should show your plugin
```

If not listed:

```bash
# Install it:
zr plugin install ./path/to/plugin my-plugin
```

**Check zr.toml**:

```toml
[plugins.my-plugin]
source = "my-plugin.dylib"  # Must match installed name
```

### Plugin Hooks Not Running

1. **Verify plugin loaded**:
   ```bash
   zr plugin list | grep my-plugin
   ```

2. **Check plugin exports hooks**:
   ```bash
   # macOS:
   nm -g ~/.zr/plugins/my-plugin/*.dylib | grep zr_on

   # Linux:
   nm -D ~/.zr/plugins/my-plugin/*.so | grep zr_on
   ```

   Should show: `zr_on_init`, `zr_on_before_task`, `zr_on_after_task`

3. **Check plugin errors**:
   - Plugins log to stderr
   - Run with `zr run --verbose` to see all output

### Platform Issues

**macOS**: Plugin must be `.dylib`:

```bash
# Correct:
cc -shared -fPIC plugin.c -o plugin.dylib

# Wrong (won't load):
cc -shared -fPIC plugin.c -o plugin.so
```

**Linux**: Plugin must be `.so`:

```bash
cc -shared -fPIC plugin.c -o plugin.so
```

**Cross-platform Makefile** (auto-detects):

```makefile
UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    LIB = plugin.dylib
    LDFLAGS = -dynamiclib
else
    LIB = plugin.so
    LDFLAGS = -shared
endif

$(LIB): plugin.c
	$(CC) $(LDFLAGS) -fPIC -o $@ plugin.c
```

---

## Example: Slack Notifications

**Goal**: Send Slack notification when `deploy` task completes.

**Step 1**: Get Slack incoming webhook URL from https://api.slack.com/messaging/webhooks

**Step 2**: Add to `zr.toml`:

```toml
[plugins.notify]
source = "builtin:notify"

[tasks.deploy]
cmd = "./deploy.sh"
env = { SLACK_WEBHOOK = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" }
```

**Step 3**: Run:

```bash
zr run deploy
```

You'll get a Slack message after `deploy` completes (success or failure).

---

## Example: Git Branch in Task

**Goal**: Only run `deploy` task on `main` branch.

**Step 1**: Add built-in git plugin:

```toml
[plugins.git]
source = "builtin:git"

[tasks.deploy]
cmd = "./deploy.sh"
condition = "env.BRANCH == 'main'"  # Check BRANCH env var

[tasks.check-branch]
cmd = "git branch --show-current"
# Set BRANCH for other tasks to use
```

**Step 2**: Run:

```bash
# On main branch:
zr run deploy  # Runs

# On feature branch:
zr run deploy  # Skipped (condition false)
```

---

## Advanced: Multiple Plugins

Load multiple plugins for different purposes:

```toml
# Monitor metrics
[plugins.metrics]
source = "builtin:cache"
config = { max_age_seconds = 3600 }

# Send notifications
[plugins.slack]
source = "builtin:notify"

# Load environment
[plugins.env]
source = "builtin:env"

[tasks.deploy]
cmd = "./deploy.sh"
cache = true
dotenv = true
env = { SLACK_WEBHOOK = "https://..." }
```

All plugins run on every task, in the order defined in `zr.toml`.

---

## Plugin Registry

**Coming soon**: Central plugin registry at `zr.dev/plugins`.

For now, discover community plugins at:
- GitHub topic: `zr-plugin`
- Search: `https://github.com/topics/zr-plugin`

---

## Resources

- **Plugin Development Guide**: [PLUGIN_DEV_GUIDE.md](./PLUGIN_DEV_GUIDE.md)
- **zr GitHub**: https://github.com/yourorg/zr
- **Example Plugins**: https://github.com/yourorg/zr-plugins
- **Report Issues**: https://github.com/yourorg/zr/issues

---

## Summary of Commands

| Command | Description |
|---------|-------------|
| `zr plugin list` | List all installed plugins |
| `zr plugin search [query]` | Search plugins by name/description |
| `zr plugin install <source> [name]` | Install plugin from path/git/registry |
| `zr plugin remove <name>` | Uninstall plugin |
| `zr plugin update <name> [path]` | Update plugin (git pull or new path) |
| `zr plugin info <name>` | Show plugin metadata |
| `zr plugin builtins` | List built-in plugins |
| `zr plugin create <name>` | Scaffold new plugin template |

---

**Next**: [Create your own plugin](./PLUGIN_DEV_GUIDE.md) →
