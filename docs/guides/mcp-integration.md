# MCP Integration Guide

**MCP (Model Context Protocol)** is a standard protocol for AI agents to interact with external tools and services. zr provides a full MCP server that allows AI agents like Claude Code and Cursor to manage tasks directly.

## Table of Contents

- [What is MCP?](#what-is-mcp)
- [Setup](#setup)
- [Available Tools](#available-tools)
- [Usage Examples](#usage-examples)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## What is MCP?

MCP (Model Context Protocol) enables AI coding assistants to:
- Discover and run tasks in your project
- Inspect task configurations and dependencies
- Generate task configurations automatically
- Access execution history and performance metrics
- Validate configurations in real-time

zr's MCP server exposes project tasks as tools that AI agents can invoke via JSON-RPC.

---

## Setup

### Claude Code

Add zr MCP server to your Claude Code configuration:

**~/.claude/mcp.json**:
```json
{
  "servers": {
    "zr": {
      "command": "zr",
      "args": ["mcp", "serve"]
    }
  }
}
```

Restart Claude Code to load the MCP server.

### Cursor

Add to Cursor's MCP configuration:

**~/.cursor/mcp.json**:
```json
{
  "mcpServers": {
    "zr": {
      "command": "zr",
      "args": ["mcp", "serve"]
    }
  }
}
```

Restart Cursor.

### Verify Setup

After configuration, the AI agent should see zr tools in its available tools list. Ask the agent:

```
"What zr tools are available?"
```

Expected response:
```
I have access to the following zr tools:
- run_task: Run a task and its dependencies
- list_tasks: List all available tasks
- show_task: Show detailed task information
- validate_config: Validate zr.toml configuration
- show_graph: Display task dependency graph
- run_workflow: Execute a workflow
- task_history: Show execution history
- estimate_duration: Estimate task duration
- generate_config: Auto-generate zr.toml from project
```

---

## Available Tools

### 1. `run_task`

Run a task and its dependencies.

**Parameters:**
- `task` (string, required): Task name to execute
- `profile` (string, optional): Profile name
- `dry_run` (boolean, optional): Show plan without executing

**Example:**
```json
{
  "task": "build",
  "profile": "prod"
}
```

**Agent usage:**
```
"Run the build task using the production profile"
```

---

### 2. `list_tasks`

List all available tasks.

**Parameters:**
- `pattern` (string, optional): Filter pattern
- `tags` (string, optional): Comma-separated tags

**Example:**
```json
{
  "tags": "ci,test"
}
```

**Agent usage:**
```
"Show me all CI and test tasks"
```

---

### 3. `show_task`

Show detailed information about a task.

**Parameters:**
- `task` (string, required): Task name

**Example:**
```json
{
  "task": "build"
}
```

**Agent usage:**
```
"What does the build task do?"
```

---

### 4. `validate_config`

Validate `zr.toml` configuration.

**Parameters:** None

**Agent usage:**
```
"Check if the zr configuration is valid"
```

---

### 5. `show_graph`

Display task dependency graph.

**Parameters:**
- `format` (string, optional): Output format (`dot`, `json`, `ascii`)

**Example:**
```json
{
  "format": "ascii"
}
```

**Agent usage:**
```
"Show me the task dependency graph in ASCII format"
```

---

### 6. `run_workflow`

Execute a workflow.

**Parameters:**
- `workflow` (string, required): Workflow name
- `dry_run` (boolean, optional): Show plan without executing

**Example:**
```json
{
  "workflow": "ci",
  "dry_run": false
}
```

**Agent usage:**
```
"Run the CI workflow"
```

---

### 7. `task_history`

Show execution history.

**Parameters:**
- `task` (string, optional): Filter by task name
- `status` (string, optional): Filter by status (`success`, `failed`)
- `since` (string, optional): Time filter (`1h`, `1d`, `1w`)

**Example:**
```json
{
  "status": "failed",
  "since": "1d"
}
```

**Agent usage:**
```
"Show me failed tasks from the last day"
```

---

### 8. `estimate_duration`

Estimate task duration based on history.

**Parameters:**
- `task` (string, required): Task name

**Example:**
```json
{
  "task": "test"
}
```

**Agent usage:**
```
"How long will the test task take?"
```

---

### 9. `generate_config`

Auto-generate `zr.toml` from project.

**Parameters:**
- `detect` (boolean, optional): Auto-detect project language

**Example:**
```json
{
  "detect": true
}
```

**Agent usage:**
```
"Generate a zr configuration for this project"
```

---

## Usage Examples

### Example 1: Run Build and Test

**Prompt to agent:**
```
"Build and test the project"
```

**Agent actions:**
1. Calls `list_tasks` to find build and test tasks
2. Calls `show_task` on each to check dependencies
3. Calls `run_task` with `task: "build"`
4. Calls `run_task` with `task: "test"`

---

### Example 2: Debug Failed Tests

**Prompt:**
```
"Why are my tests failing?"
```

**Agent actions:**
1. Calls `task_history` with `status: "failed"` and `task: "test"`
2. Analyzes error logs
3. Calls `show_task` to review test configuration
4. Suggests fixes (e.g., missing dependencies, environment issues)

---

### Example 3: Create New Task

**Prompt:**
```
"Add a new task to deploy to staging"
```

**Agent actions:**
1. Calls `show_task` on similar tasks (e.g., `deploy-prod`)
2. Suggests new TOML configuration:
   ```toml
   [tasks.deploy-staging]
   description = "Deploy to staging environment"
   cmd = "./deploy.sh staging"
   deps = ["build", "test"]
   env = { ENV = "staging" }
   ```
3. User adds to `zr.toml`
4. Agent calls `validate_config` to confirm

---

### Example 4: Optimize CI Pipeline

**Prompt:**
```
"How can I make my CI faster?"
```

**Agent actions:**
1. Calls `show_graph` to visualize dependencies
2. Calls `task_history` to find slowest tasks
3. Calls `estimate_duration` on each task
4. Suggests:
   - Parallelize independent tasks
   - Enable caching for expensive builds
   - Use `--affected` to skip unchanged packages

---

### Example 5: Generate Configuration

**Prompt:**
```
"Set up zr for my Node.js project"
```

**Agent actions:**
1. Calls `generate_config` with `detect: true`
2. Detects `package.json` and extracts npm scripts
3. Generates `zr.toml`:
   ```toml
   [tasks.install]
   cmd = "npm install"

   [tasks.build]
   cmd = "npm run build"
   deps = ["install"]

   [tasks.test]
   cmd = "npm test"
   deps = ["build"]
   ```
4. User reviews and saves

---

## Configuration

### Custom MCP Server Path

If zr is not in PATH, specify the full path:

```json
{
  "servers": {
    "zr": {
      "command": "/usr/local/bin/zr",
      "args": ["mcp", "serve"]
    }
  }
}
```

### Multiple Projects

Configure separate MCP servers for different projects:

```json
{
  "servers": {
    "zr-frontend": {
      "command": "zr",
      "args": ["mcp", "serve"],
      "cwd": "/path/to/frontend"
    },
    "zr-backend": {
      "command": "zr",
      "args": ["mcp", "serve"],
      "cwd": "/path/to/backend"
    }
  }
}
```

### Environment Variables

Pass environment variables to MCP server:

```json
{
  "servers": {
    "zr": {
      "command": "zr",
      "args": ["mcp", "serve"],
      "env": {
        "ZR_PROFILE": "dev"
      }
    }
  }
}
```

---

## Troubleshooting

### MCP Server Not Starting

**Symptom:** Agent says "zr tools not available"

**Solutions:**
1. Verify zr is installed: `which zr`
2. Test MCP server manually:
   ```bash
   echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | zr mcp serve
   ```
   Should return a JSON-RPC response with tool list.
3. Check MCP config path and syntax
4. Restart the AI agent

---

### Tool Calls Failing

**Symptom:** Agent says "tool call failed"

**Solutions:**
1. Check `zr.toml` exists in project directory
2. Validate configuration: `zr validate`
3. Check agent's working directory matches project root
4. Review MCP server logs (check agent's debug output)

---

### Slow Responses

**Symptom:** MCP tool calls take a long time

**Causes:**
- Large workspace with many tasks
- Slow filesystem (network drives)
- Complex dependency graphs

**Solutions:**
- Use `--quiet` flag to reduce output: `"args": ["mcp", "serve", "--quiet"]`
- Split large monorepos into separate MCP servers
- Cache task metadata (zr does this automatically)

---

### Configuration Validation Errors

**Symptom:** Agent reports "invalid configuration"

**Solution:**
Run `zr validate` locally to see detailed error messages:
```bash
zr validate
# ✗ Dependency cycle detected: build → test → build
# ✗ Missing dependency: "deploy" requires "build" (not found)
```

Fix errors and re-run validation until clean.

---

## Advanced Usage

### Combining with LSP

Use both MCP (for AI agents) and LSP (for editor integration) simultaneously:

**MCP configuration** (for Claude Code):
```json
{
  "servers": {
    "zr": {
      "command": "zr",
      "args": ["mcp", "serve"]
    }
  }
}
```

**LSP configuration** (for VS Code):
```json
{
  "zr.lsp.enable": true,
  "zr.lsp.command": "zr",
  "zr.lsp.args": ["lsp"]
}
```

Now you have:
- Real-time TOML validation in editor (LSP)
- AI-assisted task management (MCP)

---

### Custom Prompts

Create reusable prompts for common workflows:

**Prompt library:**
```
# Prompt: "zr-ci"
Run CI pipeline: validate config, run build and test tasks,
show execution time, and report any failures.

# Prompt: "zr-deploy"
Deploy to staging: check git status, ensure on main branch,
run build and test, then deploy-staging task.

# Prompt: "zr-optimize"
Analyze task performance: show task history for last week,
identify slowest tasks, suggest caching and parallelization.
```

Save in project `.ai-prompts/` and reference in conversations.

---

## See Also

- [LSP Setup Guide](lsp-setup.md) — editor integration
- [Commands Reference](commands.md) — all zr commands
- [Configuration Reference](configuration.md) — `zr.toml` schema
- [MCP Specification](https://spec.modelcontextprotocol.io/) — official MCP docs
