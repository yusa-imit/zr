# LSP Setup Guide

**LSP (Language Server Protocol)** integration provides real-time editor support for `zr.toml` files, including diagnostics, autocomplete, hover documentation, and go-to-definition.

## Table of Contents

- [What is LSP?](#what-is-lsp)
- [Features](#features)
- [Editor Setup](#editor-setup)
- [Usage](#usage)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## What is LSP?

LSP (Language Server Protocol) is a standard protocol between editors and language servers. zr's LSP server provides:

- **Real-time diagnostics** — TOML parse errors, missing dependencies, circular references
- **Autocomplete** — task names, field names, expressions, toolchains
- **Hover documentation** — inline help for fields and expressions
- **Go-to-definition** — jump to task definitions from references

---

## Features

### 1. Real-time Diagnostics

zr validates your configuration as you type and shows errors inline:

```toml
[tasks.build]
cmd = "npm run build"
deps = ["tets"]  # ← Error: Task 'tets' not found. Did you mean: test?
```

**Diagnostic types:**
- TOML syntax errors
- Missing task dependencies
- Circular dependency cycles
- Invalid expressions
- Unknown toolchains
- Duplicate task names

---

### 2. Autocomplete

Context-aware completions for:

**Task names** (in `deps` and workflow `tasks` arrays):
```toml
[tasks.deploy]
deps = ["b_"]  # ← suggests: build, bench
```

**Field names** (in `[tasks.*]` sections):
```toml
[tasks.test]
cmd = "npm test"
d_  # ← suggests: deps, description, dir, deps_serial
```

**Expression keywords** (in `condition`, `${...}` expressions):
```toml
[tasks.deploy-prod]
condition = "${p_"  # ← suggests: platform.os, platform.is_linux, platform.is_macos
```

**Toolchain names** (in `toolchain` arrays):
```toml
[tasks.build]
toolchain = ["n_"]  # ← suggests: node, npm
```

**Matrix values** (in `[matrix.*]` sections):
```toml
[matrix.test-matrix]
_  # ← suggests: os, arch, version, env
```

---

### 3. Hover Documentation

Hover over any field or expression to see inline documentation:

**Task field hover:**
```toml
[tasks.build]
timeout_ms = 60000  # ← Hover shows: "Timeout in milliseconds. null means no timeout."
```

**Expression keyword hover:**
```toml
condition = "${platform.is_linux}"  # ← Hover shows: "Returns true if running on Linux, false otherwise."
```

**Task reference hover:**
```toml
[tasks.deploy]
deps = ["build"]  # ← Hover over "build" shows: task description, command, dependencies
```

---

### 4. Go-to-Definition

Jump to task definitions from references:

```toml
[tasks.build]
cmd = "npm run build"

[tasks.test]
deps = ["build"]  # ← Ctrl+Click "build" → jumps to [tasks.build]
```

---

## Editor Setup

### VS Code

Install the zr LSP extension (coming soon) or configure manually:

**settings.json**:
```json
{
  "zr.lsp.enable": true,
  "zr.lsp.command": "zr",
  "zr.lsp.args": ["lsp"],
  "zr.lsp.filetypes": ["toml"],
  "zr.lsp.rootPatterns": ["zr.toml"]
}
```

Or use the generic LSP client:

1. Install **vscode-langservers-extracted** or **vscode-custom-language-server**
2. Add to `settings.json`:
   ```json
   {
     "languageServerExample.trace.server": "verbose",
     "languageserver": {
       "zr": {
         "command": "zr",
         "args": ["lsp"],
         "filetypes": ["toml"],
         "rootPatterns": ["zr.toml"],
         "initializationOptions": {}
       }
     }
   }
   ```

---

### Neovim

Using **nvim-lspconfig**:

**init.lua**:
```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

-- Define zr LSP
if not configs.zr then
  configs.zr = {
    default_config = {
      cmd = { 'zr', 'lsp' },
      filetypes = { 'toml' },
      root_dir = lspconfig.util.root_pattern('zr.toml'),
      settings = {},
    },
  }
end

-- Attach to zr.toml files
lspconfig.zr.setup{
  on_attach = function(client, bufnr)
    -- Enable completion triggered by <c-x><c-o>
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Keybindings
    local bufopts = { noremap=true, silent=true, buffer=bufnr }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
  end,
}

-- Auto-start LSP for zr.toml
vim.api.nvim_create_autocmd("BufRead", {
  pattern = "zr.toml",
  callback = function()
    vim.cmd("LspStart zr")
  end,
})
```

---

### Helix

**languages.toml**:
```toml
[[language]]
name = "toml"
scope = "source.toml"
injection-regex = "toml"
file-types = ["toml"]
roots = ["zr.toml"]
language-servers = ["zr-lsp"]

[language-server.zr-lsp]
command = "zr"
args = ["lsp"]
```

Restart Helix and open `zr.toml` to activate LSP.

---

### Emacs

Using **lsp-mode**:

**init.el**:
```elisp
(require 'lsp-mode)

(add-to-list 'lsp-language-id-configuration '(toml-mode . "toml"))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection '("zr" "lsp"))
  :major-modes '(toml-mode)
  :server-id 'zr-lsp
  :root-dir (lambda () (locate-dominating-file default-directory "zr.toml"))))

(add-hook 'toml-mode-hook
          (lambda ()
            (when (string-match-p "zr\\.toml$" (buffer-file-name))
              (lsp))))
```

---

### Sublime Text

Using **LSP** package:

1. Install **LSP** via Package Control
2. Add to `LSP.sublime-settings`:
   ```json
   {
     "clients": {
       "zr": {
         "enabled": true,
         "command": ["zr", "lsp"],
         "selector": "source.toml",
         "initializationOptions": {}
       }
     }
   }
   ```

---

## Usage

### 1. Open zr.toml

Open any `zr.toml` file in your editor. The LSP should activate automatically (check status bar or logs).

---

### 2. Diagnostics

Errors appear inline as you type:

```toml
[tasks.test]
cmd = "npm test"
deps = ["biuld"]  # ← Squiggly underline with message: "Task 'biuld' not found. Did you mean: build?"
```

---

### 3. Autocomplete

Trigger completions (usually `Ctrl+Space`):

```toml
[tasks.deploy]
d|  # ← Press Ctrl+Space → shows: deps, description, dir, deps_serial
```

Completions include:
- Field names with type hints
- Task names from your configuration
- Expression keywords with documentation
- Common matrix values

---

### 4. Hover

Hover over any symbol to see documentation:

```toml
[tasks.build]
retry_max = 3  # ← Hover here → "Maximum number of retry attempts after the first failure (0 = no retry)."
```

---

### 5. Go-to-Definition

Jump to task definitions:

1. Place cursor on a task name in `deps` or workflow
2. Press `Ctrl+Click` (VS Code) or `gd` (Neovim)
3. Editor jumps to `[tasks.<name>]` definition

---

## Configuration

### LSP Server Options

The LSP server accepts no special configuration. It uses the `zr.toml` in the workspace root.

### Client-Side Settings

**VS Code** (`settings.json`):
```json
{
  "zr.lsp.trace.server": "verbose",  // Enable debug logging
  "zr.lsp.validate": true,            // Enable validation
  "zr.lsp.completion": true,          // Enable autocomplete
  "zr.lsp.hover": true,               // Enable hover docs
  "zr.lsp.definition": true           // Enable go-to-definition
}
```

**Neovim** (init.lua):
```lua
lspconfig.zr.setup{
  settings = {
    zr = {
      validate = true,
      completion = true,
      hover = true,
      definition = true,
    }
  },
  -- Enable trace logging
  flags = {
    debounce_text_changes = 150,
  },
  on_attach = on_attach,
}
```

---

## Troubleshooting

### LSP Not Starting

**Symptom:** No diagnostics, no autocomplete

**Solutions:**
1. Verify zr is installed: `which zr`
2. Test LSP server manually:
   ```bash
   echo 'Content-Length: 123\r\n\r\n{"jsonrpc":"2.0","method":"initialize","id":1}' | zr lsp
   ```
   Should return a JSON-RPC response.
3. Check editor LSP logs:
   - **VS Code**: Output panel → "zr LSP"
   - **Neovim**: `:LspLog`
   - **Helix**: `~/.cache/helix/helix.log`
4. Ensure `zr.toml` exists in project root

---

### Completions Not Working

**Symptom:** No suggestions appear

**Causes:**
- Completion disabled in editor settings
- Wrong file type (must be `.toml`)
- Cursor not in a valid completion context

**Solutions:**
1. Manually trigger completions: `Ctrl+Space`
2. Verify file type: `:set filetype?` (Neovim) or check status bar (VS Code)
3. Check LSP capabilities:
   - **VS Code**: Command Palette → "Developer: Show Running Extensions" → zr LSP
   - **Neovim**: `:lua print(vim.inspect(vim.lsp.get_active_clients()))`

---

### Diagnostics Not Updating

**Symptom:** Errors remain after fixing

**Solutions:**
1. Save the file (diagnostics update on save)
2. Manually trigger validation: `zr validate`
3. Restart LSP:
   - **VS Code**: Command Palette → "Reload Window"
   - **Neovim**: `:LspRestart`

---

### Go-to-Definition Not Working

**Symptom:** Jump doesn't work

**Solutions:**
1. Ensure task exists: `zr list | grep <task>`
2. Check that task reference is in `deps` or workflow `tasks` array
3. Verify LSP supports `textDocument/definition`:
   - **Neovim**: `:lua =vim.lsp.get_active_clients()[1].server_capabilities.definitionProvider`
   - Should return `true`

---

### Slow Performance

**Symptom:** LSP is slow or freezes editor

**Causes:**
- Very large `zr.toml` (thousands of tasks)
- Slow filesystem (network drives)
- Complex dependency graphs

**Solutions:**
1. Split configuration into multiple files (use `[workspace]`)
2. Disable features you don't need:
   ```json
   {
     "zr.lsp.completion": false,
     "zr.lsp.hover": false
   }
   ```
3. Increase debounce time (Neovim):
   ```lua
   flags = { debounce_text_changes = 500 }
   ```

---

## Advanced Features

### Custom Snippets

Add zr-specific snippets to your editor:

**VS Code** (`.vscode/zr.code-snippets`):
```json
{
  "Task Definition": {
    "prefix": "task",
    "body": [
      "[tasks.$1]",
      "description = \"$2\"",
      "cmd = \"$3\"",
      "deps = [$4]"
    ],
    "description": "Create a new task"
  },
  "Workflow Stage": {
    "prefix": "stage",
    "body": [
      "[[workflow.$1.stages]]",
      "name = \"$2\"",
      "tasks = [$3]",
      "parallel = true"
    ],
    "description": "Add a workflow stage"
  }
}
```

**Neovim** (using LuaSnip):
```lua
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

ls.add_snippets("toml", {
  s("task", {
    t("[tasks."), i(1, "name"), t("]"),
    t({"", "description = \""}), i(2, "Description"), t("\""),
    t({"", "cmd = \""}), i(3, "command"), t("\""),
    t({"", "deps = ["}), i(4), t("]"),
  }),
})
```

---

### Linting Integration

Combine LSP with external linters:

**VS Code** (with `markdownlint` for TOML):
```json
{
  "editor.codeActionsOnSave": {
    "source.fixAll": true
  },
  "zr.lsp.lint": true
}
```

---

### Multi-Workspace Support

For monorepos with multiple `zr.toml` files:

**VS Code** (workspace settings):
```json
{
  "folders": [
    { "path": "packages/frontend" },
    { "path": "packages/backend" }
  ],
  "settings": {
    "zr.lsp.rootPatterns": ["zr.toml", "package.json"]
  }
}
```

Each folder gets its own LSP instance.

---

## See Also

- [MCP Integration Guide](mcp-integration.md) — AI agent integration
- [Configuration Reference](configuration.md) — `zr.toml` schema
- [Commands Reference](commands.md) — all zr commands
- [LSP Specification](https://microsoft.github.io/language-server-protocol/) — official LSP docs
