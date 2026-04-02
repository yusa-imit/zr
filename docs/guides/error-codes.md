# Error Codes Reference

zr uses standardized error codes to help you quickly identify and resolve issues. Each error code follows the format `EXXX` where `XXX` is a unique identifier.

## Error Code Categories

### Configuration Errors (E001-E099)

| Code | Error | Common Causes | Solution |
|------|-------|---------------|----------|
| E001 | Config parse error | Invalid TOML syntax, malformed configuration | Check TOML syntax, validate with `zr validate` |
| E002 | Config not found | No zr.toml file in current directory or parent directories | Run `zr init` to create a configuration file |
| E003 | Config syntax error | Unexpected token, missing quotes, invalid characters | Review TOML syntax at the indicated line |
| E004 | Invalid field | Unknown configuration field or misspelled key | Check against documentation, use autocomplete |
| E005 | Missing required field | Required configuration field not present | Add the missing field (usually `cmd` or `deps`) |
| E006 | Circular dependency | Task dependency cycle detected | Remove one dependency to break the cycle |
| E007 | Duplicate task | Task name appears multiple times | Rename duplicate tasks to unique names |
| E008 | Invalid expression | Malformed condition or expression syntax | Check expression syntax: `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `||` |
| E009 | Import failed | Imported configuration file not found or invalid | Verify import path, check file permissions |
| E010 | Invalid task name | Task name contains spaces or exceeds 64 characters | Use underscores/hyphens, keep names under 64 chars |

### Task Errors (E100-E199)

| Code | Error | Common Causes | Solution |
|------|-------|---------------|----------|
| E100 | Task not found | Task name doesn't exist or is misspelled | Run `zr list` to see available tasks, check spelling |
| E101 | Task failed | Command exited with non-zero status | Check task output, review command errors |
| E102 | Task timeout | Task exceeded configured timeout | Increase timeout value or optimize task |
| E103 | Missing dependency | Required dependency task doesn't exist | Add missing task or fix dependency name |
| E104 | Invalid command | Empty or whitespace-only command | Provide a valid command string |
| E105 | Execution error | Task could not be executed (permissions, not found) | Check file permissions, verify command path |

### Workflow Errors (E200-E299)

| Code | Error | Common Causes | Solution |
|------|-------|---------------|----------|
| E200 | Workflow not found | Workflow name doesn't exist or is misspelled | Run `zr list --workflows` to see available workflows |
| E201 | Invalid stage | Workflow stage configuration is malformed | Review workflow stages syntax |
| E202 | Matrix error | Workflow matrix configuration is invalid or produces no combinations | Check matrix dimensions and exclusion rules |

### Plugin Errors (E300-E399)

| Code | Error | Common Causes | Solution |
|------|-------|---------------|----------|
| E300 | Plugin not found | Plugin name doesn't exist in registry | Search with `zr plugin search`, check spelling |
| E301 | Plugin load failed | Plugin binary is corrupted or incompatible | Reinstall plugin with `zr plugin install` |
| E302 | Invalid plugin config | Plugin configuration is malformed | Check plugin documentation for required fields |

### Toolchain Errors (E400-E499)

| Code | Error | Common Causes | Solution |
|------|-------|---------------|----------|
| E400 | Toolchain not found | Language toolchain not installed | Install with `zr tools install <language> <version>` |
| E401 | Download failed | Network error or invalid toolchain version | Check network connection, verify version exists |
| E402 | Invalid version | Version specifier is malformed | Use semver format: `1.2.3` or `^1.0.0` |

### System Errors (E500-E599)

| Code | Error | Common Causes | Solution |
|------|-------|---------------|----------|
| E500 | I/O error | File read/write failed, disk full | Check disk space, verify file permissions |
| E501 | Permission denied | Insufficient permissions to access file/directory | Check file permissions, use `sudo` if appropriate |
| E502 | Out of memory | System ran out of memory during execution | Close other applications, increase system memory |

## Error Message Format

All zr error messages follow this consistent format:

```
✗ [EXXX]: Error description

  at file_path:line:column (if applicable)

  Context information (if applicable)

  Hint: Actionable suggestion to resolve the issue
```

### Example: Task Not Found

```bash
$ zr run buidl
✗ [E100]: Unknown command: buidl

  Hint: Did you mean one of these?
    zr run build
    zr run rebuild

Or run 'zr --help' to see all available commands.
```

### Example: Circular Dependency

```bash
$ zr run deploy
✗ [E006]: Circular dependency detected

  deploy -> build -> compile -> deploy

  Hint: Remove one of the dependencies to break the cycle
```

### Example: Config Syntax Error

```bash
$ zr validate
✗ [E003]: Expected '=' after key

  at zr.toml:42:10

  tasks.build

  Hint: Add '=' between the key and value
```

## Getting Help

When you encounter an error:

1. **Read the error code**: Use this reference to understand the category and common causes
2. **Check the hint**: Error messages include actionable suggestions
3. **Run diagnostics**: Use `zr validate` to check configuration
4. **Search documentation**: Reference this guide for specific error codes
5. **Check examples**: See `examples/` directory for working configurations

## Color Coding

Errors are color-coded when terminal supports ANSI colors:

- **Red (✗)**: Errors that prevent execution
- **Yellow (⚠)**: Warnings that should be addressed
- **Cyan (→)**: Informational messages
- **Green (✓)**: Success messages

Use `--no-color` flag to disable color output for CI/scripting.

## Related Commands

- `zr validate` — Check configuration for errors before running
- `zr doctor` — Diagnose common configuration issues
- `zr --help` — Show available commands and flags
- `zr <command> --help` — Show help for specific command
