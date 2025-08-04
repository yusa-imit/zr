# ZR TODO - Future Features and Improvements

This document outlines potential future features, improvements, and fixes for ZR based on code analysis and testing results.

## ✅ Recently Completed

### Pipeline System
- [x] **Fix pipeline parsing from YAML config** - ✅ **COMPLETED (2025-01-08)**
  - Location: `src/config/parser.zig` - pipeline parsing fully implemented
  - Fix: Added complete YAML pipeline parsing with multi-pipeline support, stages, parallel execution, and repository task assignments
  - Impact: Pipeline execution now fully functional
  - Tests: Added comprehensive test coverage for simple/complex/multiple pipeline scenarios

### Repository Management
- [x] **Fix repository removal memory crash** - ✅ **COMPLETED (2025-01-08)**
  - Location: `src/core/engine.zig:removeRepository()` and `src/config/parser.zig` memory management
  - Fix: Fixed inconsistent memory management by ensuring all Repository strings are properly duplicated and freed
  - Impact: Repository removal no longer crashes the application
  - Tests: Added comprehensive test coverage for repository addition/removal cycles

### Settings Management
- [x] **Fix settings persistence** - ✅ **COMPLETED (2025-01-08)**
  - Location: `src/core/engine.zig:setSetting()/getSetting()` and `src/config/parser.zig:parse()`
  - Fix: Fixed settings parsing and persistence by implementing proper global configuration parsing and fixing pointer usage
  - Impact: Settings now save to file and reload correctly between sessions
  - Tests: Verified settings change persistence through complete save/load cycles

## 🔥 Critical Fixes (High Priority)

### Resource Monitoring
- [x] **Enable resource monitoring system** - ✅ **COMPLETED (2025-01-08)**
  - Location: `src/resources/monitor.zig` and `src/core/engine.zig:initSubsystems()`
  - Fix: Fixed integer overflow in sleep calculation and re-enabled resource monitoring
  - Impact: Resource monitoring now fully functional with CPU/memory usage tracking and alerts
  - Tests: Verified resource monitoring works in status, task execution, and interactive console

## 🚧 Infrastructure Improvements (High Priority)

### Task Execution
- [ ] **Implement proper thread pool for parallel execution**
  - Location: `src/tasks/executor.zig:executeGroupParallel()`
  - Current: Basic threading with manual thread management
  - Improvement: Use `std.Thread.Pool` for better resource management
  - Benefits: Better performance, resource control, error handling

- [ ] **Add task timeout support**
  - Location: `src/tasks/executor.zig:runCommand()`
  - Feature: Implement configurable timeouts per task/repository
  - Integration: Use `pipeline.timeout` and `global.pipeline.default_timeout`

- [ ] **Add task retry mechanism**
  - Location: `src/tasks/executor.zig:executeTask()`
  - Feature: Retry failed tasks based on `retry_attempts` configuration
  - Include: Exponential backoff, configurable retry conditions

### Configuration System
- [ ] **Implement proper YAML parser**
  - Location: `src/config/parser.zig`
  - Current: Basic string parsing with limited YAML support
  - Improvement: Use proper YAML library or implement full parser
  - Benefits: Support complex configurations, better error messages

- [ ] **Add configuration validation**
  - Feature: Validate configuration against schema on load
  - Include: Type checking, required fields, value ranges
  - Integration: Use `zr.config.spec.yaml` as validation schema

- [ ] **Add configuration migration system**
  - Feature: Handle config format changes between versions
  - Include: Automatic migration, backup creation, version tracking

## 🔌 Plugin System Enhancements (Medium Priority)

### External Plugin Support
- [ ] **Implement dynamic plugin loading from filesystem**
  - Location: `src/plugins/mod.zig:loadExternalPlugin()`
  - Current: Only discovers external plugins, doesn't load them
  - Feature: Load and execute external Zig plugins at runtime
  - Challenges: Dynamic loading in Zig, sandboxing, security

- [ ] **Add plugin configuration validation**
  - Feature: Validate plugin configs before loading
  - Integration: Use plugin's `validateConfig` function
  - Include: Schema validation, type checking

- [ ] **Plugin dependency management**
  - Feature: Handle plugin dependencies and load order
  - Include: Dependency resolution, circular dependency detection
  - Format: Plugin manifest with dependency declarations

### Built-in Plugin Improvements
- [ ] **Complete Docker Runner plugin implementation**
  - Location: `src/plugins/builtin/docker_runner.zig`
  - Current: Basic structure, missing core functionality
  - Features to implement:
    - Container creation and management
    - Volume mounting and networking
    - Image caching and optimization
    - Multi-platform support

- [ ] **Enhance Turbo Compatibility plugin**
  - Location: `src/plugins/builtin/turbo_compat.zig`
  - Current: Basic cache simulation
  - Improvements:
    - Real file-based caching
    - Dependency graph analysis
    - Cache invalidation strategies
    - Remote cache support

- [ ] **Cross-platform notification improvements**
  - Location: `src/plugins/builtin/notification.zig`
  - Current: Basic platform detection
  - Improvements:
    - Windows Toast notifications
    - Rich notifications with actions
    - Notification history
    - Custom notification templates

### New Built-in Plugins
- [ ] **Git Integration Plugin**
  - Features: Pre/post commit hooks, branch-aware tasks, git status integration
  - Hooks: OnCommit, OnPush, OnBranchChange
  - Use cases: Run tests before commit, deploy on push

- [ ] **CI/CD Integration Plugin** 
  - Features: GitHub Actions, GitLab CI, Jenkins integration
  - Hooks: OnPullRequest, OnRelease, OnDeploy
  - Use cases: Trigger ZR pipelines from CI, report status back

- [ ] **File Watcher Plugin**
  - Features: Watch file changes, trigger tasks automatically
  - Integration: File system events, glob patterns
  - Use cases: Auto-rebuild on code changes, hot reload

- [ ] **Metrics and Analytics Plugin**
  - Features: Task execution metrics, performance tracking
  - Data: Execution time, success rates, resource usage
  - Output: Prometheus metrics, custom dashboards

## ✨ New Features (Medium Priority)

### CLI Enhancements
- [ ] **Add shell completion support**
  - Platforms: Bash, Zsh, Fish, PowerShell
  - Features: Command completion, repository/task completion
  - Integration: Generate completion scripts

- [ ] **Implement `zr watch` command**
  - Feature: Watch file changes and auto-execute tasks
  - Options: Glob patterns, debouncing, exclude patterns
  - Integration: File system events, plugin hooks

- [ ] **Add `zr templates` system**
  - Feature: Pre-defined repository templates
  - Templates: React app, Node.js service, Rust CLI, etc.
  - Commands: `zr template list`, `zr template apply <name>`

- [ ] **Environment management**
  - Feature: Multiple environment configs (dev, staging, prod)
  - Commands: `zr env switch <name>`, `zr env list`
  - Integration: Environment-specific repositories and tasks

### Interactive Console Improvements
- [ ] **Add command completion in interactive mode**
  - Feature: Tab completion for commands, repositories, tasks
  - Libraries: Use readline-like functionality
  - UX: Similar to modern shell experiences

- [ ] **Real-time task output streaming**
  - Feature: Show task output in real-time during execution
  - UI: Progress bars, live updates, colored output
  - Integration: Background task execution with UI updates

- [ ] **Interactive task debugging**
  - Feature: Step through task execution, inspect variables
  - Commands: `debug <repo> <task>`, breakpoints, variable inspection
  - Use cases: Debug complex pipeline failures

- [ ] **Dashboard view in interactive mode**
  - Feature: Real-time dashboard with repository status
  - UI: ASCII charts, resource usage graphs, task queue
  - Updates: Live refresh, notification integration

### Advanced Pipeline Features
- [ ] **Pipeline visualization**
  - Feature: Generate dependency graphs, execution flow charts
  - Output: ASCII art, SVG, HTML interactive graphs
  - Integration: Mermaid diagrams, Graphviz

- [ ] **Conditional pipeline execution**
  - Feature: Execute stages based on conditions
  - Conditions: File changes, environment variables, previous results
  - Syntax: YAML conditionals, expression evaluation

- [ ] **Pipeline templates and inheritance**
  - Feature: Reusable pipeline templates
  - Inheritance: Base pipelines, overrides, composition
  - Use cases: Standard workflows across projects

- [ ] **Pipeline scheduling**
  - Feature: Cron-like scheduling for pipeline execution
  - Integration: System scheduler, background daemon
  - Use cases: Nightly builds, periodic maintenance

### Repository Management
- [ ] **Repository discovery and auto-configuration**
  - Feature: Scan directory tree for known project types
  - Detection: package.json, Cargo.toml, go.mod, etc.
  - Commands: `zr discover`, `zr auto-add`

- [ ] **Repository groups and tags**
  - Feature: Organize repositories with tags/groups
  - Commands: `zr group create <name>`, `zr tag add <repo> <tag>`
  - Use cases: Environment-specific grouping, bulk operations

- [ ] **Remote repository support**
  - Feature: Work with remote repositories via SSH/HTTP
  - Integration: Git integration, credential management
  - Use cases: Manage repositories across multiple machines

## 🔧 Technical Improvements (Low Priority)

### Performance Optimizations
- [ ] **Implement configuration caching**
  - Feature: Cache parsed config to avoid re-parsing
  - Invalidation: File modification time, checksum-based
  - Benefits: Faster startup, reduced I/O

- [ ] **Add parallel repository operations**
  - Feature: Execute repository commands in parallel
  - Implementation: Worker pool, dependency-aware scheduling
  - Use cases: Bulk repository updates, parallel builds

- [ ] **Optimize plugin system performance**
  - Features: Plugin lazy loading, hot reloading
  - Benefits: Faster startup, dynamic plugin updates
  - Implementation: Plugin state management, reload hooks

### Code Quality
- [ ] **Add comprehensive error types and messages**
  - Feature: Structured error types with context
  - Benefits: Better debugging, user-friendly messages
  - Implementation: Error chain, error codes, help suggestions

- [ ] **Implement logging system**
  - Feature: Structured logging with configurable levels
  - Output: File logs, structured JSON, log rotation
  - Integration: Plugin logs, audit trails

- [ ] **Add configuration schema documentation**
  - Feature: Generate docs from `zr.config.spec.yaml`
  - Output: Markdown, HTML, interactive docs
  - Integration: JSON Schema, validation examples

### Testing and Documentation
- [ ] **Add integration test suite**
  - Feature: Full end-to-end testing with real repositories
  - Scenarios: Multi-repo workflows, plugin interactions
  - CI: Automated testing on multiple platforms

- [ ] **Add benchmark suite**
  - Feature: Performance benchmarks for core operations
  - Metrics: Task execution time, memory usage, throughput
  - Tracking: Performance regression detection

- [ ] **Create plugin development guide**
  - Documentation: Plugin API, best practices, examples
  - Templates: Plugin starter templates
  - Tools: Plugin development utilities

## 🌐 Platform and Ecosystem

### Cross-platform Support
- [ ] **Windows-specific improvements**
  - Features: PowerShell integration, Windows paths
  - Notifications: Windows Toast, Action Center
  - Performance: Windows-specific optimizations

- [ ] **macOS-specific improvements**
  - Features: Notification Center integration, Spotlight
  - Integration: macOS services, system preferences
  - Performance: macOS-specific optimizations

### Integration and Ecosystem
- [ ] **VS Code extension**
  - Features: ZR command palette, task running, pipeline visualization
  - Integration: VS Code tasks, terminal integration
  - UI: Repository explorer, task management

- [ ] **Package manager integration**
  - Support: Homebrew, APT, Chocolatey, Scoop
  - Distribution: Pre-built binaries, package metadata
  - Updates: Automatic update checking and installation

- [ ] **Cloud integration**
  - Features: Cloud-based configuration sync
  - Platforms: GitHub, GitLab, cloud storage
  - Use cases: Team configuration sharing, backup

## 📊 Monitoring and Observability

### Metrics and Monitoring
- [ ] **Add telemetry and analytics**
  - Metrics: Task execution stats, error rates, performance
  - Privacy: Opt-in, anonymized data collection
  - Benefits: Product improvement, usage insights

- [ ] **Health check system**
  - Feature: Monitor ZR and repository health
  - Checks: Configuration validity, dependency status
  - Alerts: Proactive issue detection

- [ ] **Audit logging**
  - Feature: Log all configuration changes and task executions
  - Format: Structured logs, audit trails
  - Use cases: Compliance, debugging, security

---

## Implementation Priority Guide

### Phase 1 (Critical - Next Release) ✅ **FULLY COMPLETED**
1. ~~Fix pipeline parsing~~ ✅ **COMPLETED**
2. ~~Fix repository removal crash~~ ✅ **COMPLETED**
3. ~~Fix settings persistence~~ ✅ **COMPLETED**
4. ~~Enable resource monitoring~~ ✅ **COMPLETED**

### Phase 2 (Core Features)
1. Proper YAML parser
2. Thread pool implementation
3. Configuration validation
4. External plugin loading

### Phase 3 (User Experience)
1. Shell completion
2. Watch command
3. Interactive console improvements
4. Template system

### Phase 4 (Advanced Features)
1. Pipeline visualization
2. Repository discovery
3. CI/CD integration
4. Monitoring and metrics

### Phase 5 (Ecosystem)
1. VS Code extension
2. Package manager distribution
3. Cloud integration
4. Advanced analytics

---

*This TODO list is based on code analysis, testing results, and feature gaps identified during development. Priorities may shift based on user feedback and community needs.*