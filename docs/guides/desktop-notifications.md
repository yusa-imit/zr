# Desktop Notifications

> **Since**: v1.83.0 (macOS and Linux)

zr can send desktop notifications when tasks complete, helping you stay informed during long-running builds without watching the terminal.

## Quick Start

Add `notify = true` to any task in `zr.toml`:

```toml
[tasks.build]
cmd = "cargo build --release"
notify = true
```

When `zr run build` finishes, you'll receive a notification:
- **macOS**: `osascript display notification` (no extra tools needed)
- **Linux**: `notify-send` (requires `libnotify-bin` or equivalent)

## Configuration

### Task-Level Notification

```toml
[tasks.test]
cmd = "cargo test"
notify = true                    # notify on completion (default: always)
notify_on = "failure"            # only notify on failure
notify_title = "Test Suite"      # custom notification title
```

**Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notify` | bool | `false` | Enable notifications for this task |
| `notify_on` | string | `"always"` | When to notify: `"success"`, `"failure"`, or `"always"` |
| `notify_title` | string | Task name | Title shown in the notification |

### CLI Override

Use `--notify` to enable notifications for all tasks in a run, regardless of per-task `notify` settings:

```bash
zr --notify run build
zr --notify run test
```

This is useful for one-off runs where you want to be notified without modifying `zr.toml`.

## Examples

### Notify only on failure

```toml
[tasks.deploy]
cmd = "./scripts/deploy.sh"
notify = true
notify_on = "failure"
notify_title = "Deploy Failed!"
```

### Notify only on success

```toml
[tasks.ci]
cmd = "make all-checks"
notify = true
notify_on = "success"
notify_title = "CI Passed"
```

### Long-running task with custom title

```toml
[tasks.build-release]
cmd = "zig build -Doptimize=ReleaseFast"
notify = true
notify_title = "Release Build"
```

### Multiple tasks with different notification strategies

```toml
[tasks.lint]
cmd = "eslint src/"
notify = true
notify_on = "failure"   # only alert when linting fails

[tasks.test]
cmd = "jest"
notify = true
notify_on = "always"    # always know when tests complete

[tasks.deploy]
cmd = "./deploy.sh"
notify = true
notify_title = "Production Deploy"
```

## Platform Notes

### macOS

Uses `osascript` with the `display notification` API. No additional installation required. Notifications appear in the macOS Notification Center.

### Linux

Requires `notify-send` (provided by `libnotify`):

```bash
# Debian/Ubuntu
sudo apt install libnotify-bin

# Fedora/RHEL
sudo dnf install libnotify

# Arch Linux
sudo pacman -S libnotify
```

If `notify-send` is not installed, notifications are silently skipped (no error).

### Windows

Not yet supported. `notify = true` is parsed without error but no notification is sent.

## Global Notification Flag

Enable notifications for all tasks without modifying `zr.toml`:

```bash
zr --notify run build test deploy
```

The `--notify` flag activates `notify = true` behavior for every task executed in that run, using the default `notify_on = "always"` strategy.

## Troubleshooting

**Notifications not appearing on macOS**: Check that your terminal application has notification permissions in **System Preferences → Notifications**.

**Notifications not appearing on Linux**: Verify `notify-send` is installed and your desktop environment supports it:
```bash
notify-send "test" "zr notifications work"
```

**Silent failures**: If notification delivery fails, zr logs a warning but the task itself is unaffected.
