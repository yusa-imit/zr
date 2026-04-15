# Shell Integration & Ergonomics

zr provides several shell integration features to streamline your workflow and reduce typing. This guide covers quick shortcuts, smart defaults, and shell-specific setup.

---

## Table of Contents

- [Smart Default Behavior](#smart-default-behavior)
- [History Shortcuts](#history-shortcuts)
- [Workflow Shorthand](#workflow-shorthand)
- [Shell Completion](#shell-completion)
- [Aliases & Abbreviations](#aliases--abbreviations)
- [Directory Navigation](#directory-navigation)
- [Environment Loading](#environment-loading)

---

## Smart Default Behavior

Running `zr` without arguments intelligently picks what to do based on your config:

### 1. Default Task

If you define a task named `default`, it runs automatically:

```toml
[task.default]
script = "npm run dev"
depends = ["install"]
```

```bash
zr  # Runs 'default' task
```

### 2. Single Task Auto-Run

If only one task exists, zr runs it without prompting:

```toml
[task.start]
script = "docker-compose up"
```

```bash
zr  # Auto-runs 'start' task
```

### 3. Interactive Picker

If multiple tasks exist (and no `default`), zr launches a fuzzy picker:

```bash
zr  # Opens interactive task picker
# Use arrow keys, type to filter, Enter to run
```

### 4. Help Fallback

If no config exists or no tasks are defined, shows help:

```bash
zr  # Shows usage and commands
```

---

## History Shortcuts

Re-run tasks from history without typing the full name:

### Last Task

```bash
zr !!  # Re-runs the most recently executed task
```

### Nth-to-Last Task

```bash
zr !-1  # Last task (same as !!)
zr !-2  # 2nd-to-last task
zr !-5  # 5th-to-last task
```

**Example workflow:**

```bash
zr run build    # Build the project
zr run test     # Run tests
zr !!           # Re-runs 'test' (last task)
zr !-2          # Re-runs 'build' (2nd-to-last)
```

**Notes:**

- History is stored in `~/.zr_history` (shared across all projects)
- `!-0` is invalid (use `!!` for last task)
- If index exceeds history size, zr reports an error

---

## Workflow Shorthand

Use `w/<workflow>` as shorthand for `zr workflow <workflow>`:

```toml
[workflow.ci]
tasks = ["lint", "test", "build"]

[workflow.deploy]
tasks = ["build", "push"]
```

```bash
# Traditional syntax
zr workflow ci

# Shorthand syntax
zr w/ci

# Works with flags
zr --dry-run w/deploy
zr --profile prod w/ci
```

---

## Shell Completion

zr provides completion for bash, zsh, and fish shells.

### Bash

Add to your `~/.bashrc`:

```bash
eval "$(zr completion --shell=bash)"
```

### Zsh

Add to your `~/.zshrc`:

```zsh
eval "$(zr completion --shell=zsh)"
```

### Fish

Add to your `~/.config/fish/config.fish`:

```fish
zr completion --shell=fish | source
```

**What gets completed:**

- Commands: `run`, `workflow`, `list`, `watch`, etc.
- Task names (dynamic, based on current `zr.toml`)
- Workflow names
- Global flags: `--profile`, `--dry-run`, `--jobs`, etc.

---

## Aliases & Abbreviations

Define custom abbreviations in `~/.zrconfig`:

```toml
[alias]
b = "run build"
t = "run test"
d = "run dev --watch"
l = "list --json"
```

Usage:

```bash
zr b      # Expands to 'zr run build'
zr t      # Expands to 'zr run test'
zr d      # Expands to 'zr run dev --watch'
```

**Rules:**

- Abbreviations cannot conflict with built-in commands
- Alias expansion happens before command dispatch
- Abbreviations are global (apply to all projects)

---

## Directory Navigation

Use `zr cd <member>` to print workspace member paths for shell integration:

```toml
[workspace]
members = ["apps/*", "libs/*"]
```

```bash
# Navigate to a workspace member
cd $(zr cd api)

# Or use pushd/popd for stack-based navigation
pushd $(zr cd ui)
# ... work in ui/
popd

# List all members
zr cd --list
```

---

## Environment Loading

Load task environment variables and generate shell functions for seamless integration.

### Environment Variable Export

Export task environment variables into your current shell session:

```toml
[tasks.dev]
cmd = "npm run dev"
env = [["NODE_ENV", "development"], ["PORT", "3000"], ["DEBUG", "app:*"]]

[tasks.prod]
cmd = "npm start"
env = [["NODE_ENV", "production"], ["PORT", "8080"]]
```

**Basic usage:**

```bash
# Export specific task's environment
eval $(zr env --task dev --export)
echo $NODE_ENV  # development
echo $PORT      # 3000

# Auto-detect shell (bash/zsh/fish)
eval $(zr env --task dev --export)

# Explicit shell type
eval $(zr env --task prod --export bash)
eval $(zr env --task prod --export fish)
```

**Shell-specific output:**

```bash
# Bash/Zsh (export statements)
$ zr env --task dev --export bash
export NODE_ENV="development"
export PORT="3000"
export DEBUG="app:*"

# Fish (set -x statements)
$ zr env --task dev --export fish
set -x NODE_ENV "development"
set -x PORT "3000"
set -x DEBUG "app:*"
```

**Special character handling:**

```toml
[tasks.special]
env = [["PATH", "/bin:$HOME/custom"], ["MSG", "hello \"world\""]]
```

```bash
# Automatically escapes $, ", and other special characters
eval $(zr env --task special --export)
```

### Shell Function Generation

Generate convenience functions for all tasks in your config:

```bash
# Generate functions for current shell
eval $(zr env --functions)

# Now you can call tasks directly:
zr_dev              # Runs 'zr run dev'
zr_test --watch     # Runs 'zr run test --watch'
zr_build --release  # Runs 'zr run build --release'
```

**Shell-specific function syntax:**

```bash
# Bash/Zsh functions
$ zr env --functions bash
zr_dev() { zr run dev "$@"; }
zr_test() { zr run test "$@"; }
zr_build() { zr run build "$@"; }

# Fish functions
$ zr env --functions fish
function zr_dev; zr run dev $argv; end
function zr_test; zr run test $argv; end
function zr_build; zr run build $argv; end
```

**Usage patterns:**

```bash
# Add to your shell startup file
# ~/.bashrc or ~/.zshrc
eval $(zr env --functions)

# ~/.config/fish/config.fish
zr env --functions fish | source

# Now use generated functions anywhere:
zr_build           # Runs build task
zr_test            # Runs test task
zr_dev --hot       # Runs dev task with --hot flag
```

**Benefits:**

- **Tab completion**: Shell functions get completion for free (task names become commands)
- **Shorter typing**: `zr_build` instead of `zr run build`
- **Flag forwarding**: All arguments pass through (`"$@"` / `$argv`)
- **Context-aware**: Functions use current directory's `zr.toml`

**Combined workflow:**

```bash
# Load environment + generate functions
eval $(zr env --task dev --export)
eval $(zr env --functions)

# Now you have both env vars and convenience functions
echo $NODE_ENV    # development
zr_test           # Runs test task in dev environment
```

**Profile support:**

```bash
# Environment export respects profiles
eval $(zr env --task build --export --profile production)

# Functions always use base config (apply profile when calling)
zr_build --profile production
```

**Notes:**

- `zr env --export` is useful for quick debugging and CI environments
- For complex environment management, consider tools like direnv or dotenv
- Generated functions are ephemeral (shell session only) - add to shell RC for persistence
- Function names follow `zr_<taskname>` convention (hyphenated task names use underscores: `deploy-prod` → `zr_deploy_prod`)

---

## Complete Shell Setup Example

For maximum productivity, add all features to your shell config:

### Bash (~/.bashrc)

```bash
# zr completion
eval "$(zr completion --shell=bash)"

# zr shortcuts (optional)
alias zrr='zr !!'                # Quick re-run
alias zrl='zr list --tags'       # List with tags
alias zrw='zr watch'             # Quick watch

# zr helper functions
zr_cd() {
    local member_path=$(zr cd "$1" 2>/dev/null)
    if [ $? -eq 0 ]; then
        cd "$member_path"
    else
        echo "Member not found: $1"
    fi
}
```

### Zsh (~/.zshrc)

```zsh
# zr completion
eval "$(zr completion --shell=zsh)"

# zr shortcuts
alias zrr='zr !!'
alias zrl='zr list --tags'
alias zrw='zr watch'

# zr helper functions
zr_cd() {
    local member_path=$(zr cd "$1" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        cd "$member_path"
    else
        echo "Member not found: $1"
    fi
}
```

### Fish (~/.config/fish/config.fish)

```fish
# zr completion
zr completion --shell=fish | source

# zr shortcuts
alias zrr 'zr !!'
alias zrl 'zr list --tags'
alias zrw 'zr watch'

# zr helper functions
function zr_cd
    set member_path (zr cd $argv[1] 2>/dev/null)
    if test $status -eq 0
        cd $member_path
    else
        echo "Member not found: $argv[1]"
    end
end
```

---

## Tips & Best Practices

### 1. Name Your Default Task

If you have a primary development task, name it `default`:

```toml
[task.default]
script = "npm run dev"
depends = ["install", "db:migrate"]
```

### 2. Use Descriptive Abbreviations

Keep abbreviations short but memorable:

```toml
[alias]
b = "run build"         # Good: b for build
bld = "run build"       # Okay: but redundant
build = "run build"     # Bad: conflicts with potential task name
```

### 3. Combine Features

Use multiple shortcuts together:

```bash
zr w/ci --dry-run  # Test CI workflow without running
zr !!              # Re-run the dry-run (for debugging)
```

### 4. History Inspection

Check your history before using shortcuts:

```bash
zr history --limit 10  # See last 10 tasks
zr !-3                 # Re-run 3rd-to-last
```

### 5. Profile-Aware Workflows

Use profiles with shortcuts:

```bash
zr --profile prod w/deploy
zr !-1  # Re-runs 'deploy' with prod profile (profile is remembered in history)
```

---

## Troubleshooting

### Completion Not Working

- **Bash/Zsh:** Ensure `eval "$(zr completion ...)"` runs **after** profile initialization
- **Fish:** Run `zr completion --shell=fish | source` manually to test
- Restart your shell after adding completion commands

### History Shortcuts Fail

- Check `~/.zr_history` exists and is readable
- Run a task first: `zr run <task>` to populate history
- History is global; switching projects doesn't clear it

### Abbreviations Not Expanding

- Verify `~/.zrconfig` syntax with `zr validate ~/.zrconfig`
- Ensure abbreviation names don't conflict with built-in commands
- Check file permissions: `~/.zrconfig` must be readable

### `zr cd` Returns Wrong Path

- Ensure workspace config exists in `zr.toml`
- Run `zr workspace list` to see all members
- Member names are case-sensitive

---

## See Also

- [Configuration Guide](configuration.md) — Task and workflow syntax
- [Commands Reference](commands.md) — Complete command documentation
- [Workspace Management](workspace.md) — Multi-project orchestration
- [History & Analytics](../PRD.md#phase-6-history-and-analytics) — Execution tracking
