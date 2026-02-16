# Claude Code Memory System

This directory stores persistent knowledge across Claude Code sessions for the `zr` project.

## How It Works

Agents write topic-specific markdown files here to preserve knowledge that should survive across conversations. The contents of this directory are consulted at the start of each session.

## Writing Memories

- Create topic-specific files: `architecture.md`, `decisions.md`, `debugging.md`, `patterns.md`, etc.
- Use clear headings and concise bullet points.
- Each file should focus on a single topic or domain.
- Update or remove entries when they become outdated.

## File Naming Conventions

- Use lowercase kebab-case: `project-context.md`, `build-system.md`
- Name files by topic, not by date or session
- Prefix with domain if needed: `zig-patterns.md`, `toml-parsing.md`

## What to Store

- Project architecture and key design decisions
- Important file paths and module responsibilities
- Confirmed patterns and conventions
- Solutions to recurring problems
- Build/test/run commands and workflows
- User preferences for tools and communication

## What NOT to Store

- Session-specific or in-progress work details
- Speculative or unverified conclusions
- Anything that duplicates CLAUDE.md instructions
- Large code snippets (reference file paths instead)
- Temporary debugging state

## Compressing Old Memories

When a topic file grows beyond ~200 lines:
1. Summarize older entries into a condensed section at the top
2. Remove entries that are no longer relevant
3. Archive truly old content to `archive/` subdirectory if needed
