const std = @import("std");
const plugin_loader = @import("../plugin/loader.zig");
pub const PluginConfig = plugin_loader.PluginConfig;
pub const PluginSourceKind = plugin_loader.SourceKind;
const toolchain_types = @import("../toolchain/types.zig");
pub const ToolchainConfig = toolchain_types.ToolchainConfig;
pub const ToolSpec = toolchain_types.ToolSpec;
const versioning_types = @import("../versioning/types.zig");
pub const VersioningConfig = versioning_types.VersioningConfig;
pub const VersioningMode = versioning_types.VersioningMode;
pub const VersioningConvention = versioning_types.VersioningConvention;
const conformance_types = @import("../conformance/types.zig");
pub const ConformanceConfig = conformance_types.ConformanceConfig;
const hooks_mod = @import("../exec/hooks.zig");
pub const HookPoint = hooks_mod.HookPoint;
pub const HookFailureStrategy = hooks_mod.HookFailureStrategy;

/// Project metadata from [metadata] section (for constraint validation).
pub const Metadata = struct {
    /// Project tags for constraint matching (e.g., ["app"], ["lib"], ["feature"]).
    tags: [][]const u8 = &.{},
    /// Workspace member dependencies (same as workspace.member_dependencies).
    dependencies: [][]const u8 = &.{},

    pub fn deinit(self: *Metadata, allocator: std.mem.Allocator) void {
        for (self.tags) |tag| allocator.free(tag);
        if (self.tags.len > 0) allocator.free(self.tags);
        for (self.dependencies) |dep| allocator.free(dep);
        if (self.dependencies.len > 0) allocator.free(self.dependencies);
    }
};

/// Workspace (monorepo) configuration from [workspace] section.
pub const Workspace = struct {
    /// Glob patterns for member directories (e.g. "packages/*", "apps/*").
    /// Only present in root workspace config.
    members: [][]const u8,
    /// Patterns to ignore when discovering members.
    /// Only present in root workspace config.
    ignore: [][]const u8,
    /// Optional: list of workspace member paths this member depends on.
    /// Only present in member configs (e.g., ["packages/core", "packages/utils"]).
    member_dependencies: [][]const u8,

    pub fn deinit(self: *Workspace, allocator: std.mem.Allocator) void {
        for (self.members) |m| allocator.free(m);
        allocator.free(self.members);
        for (self.ignore) |ig| allocator.free(ig);
        allocator.free(self.ignore);
        for (self.member_dependencies) |dep| allocator.free(dep);
        allocator.free(self.member_dependencies);
    }
};

/// Global resource limits for task execution.
pub const GlobalResourceConfig = struct {
    /// Maximum number of concurrent worker threads (null = CPU count).
    max_workers: ?u32 = null,
    /// Maximum total memory usage across all tasks in bytes (null = unlimited).
    max_total_memory: ?u64 = null,
    /// Maximum CPU usage percent (0-100, null = unlimited).
    max_cpu_percent: ?u8 = null,
};

/// Remote cache backend type (PRD §5.7.3 Phase 7).
pub const RemoteCacheType = enum {
    s3,
    gcs,
    azure,
    http,

    pub fn parse(s: []const u8) !RemoteCacheType {
        if (std.mem.eql(u8, s, "s3")) return .s3;
        if (std.mem.eql(u8, s, "gcs")) return .gcs;
        if (std.mem.eql(u8, s, "azure")) return .azure;
        if (std.mem.eql(u8, s, "http")) return .http;
        return error.InvalidRemoteCacheType;
    }
};

/// Remote cache configuration from [cache.remote] section (Phase 7).
pub const RemoteCacheConfig = struct {
    /// Backend type (s3, gcs, azure, http).
    type: RemoteCacheType,
    /// S3/GCS bucket name or Azure container (owned).
    bucket: ?[]const u8 = null,
    /// S3 region (owned).
    region: ?[]const u8 = null,
    /// Prefix path within bucket (owned).
    prefix: ?[]const u8 = null,
    /// HTTP base URL (owned).
    url: ?[]const u8 = null,
    /// HTTP auth header (e.g., "bearer:$TOKEN") (owned).
    auth: ?[]const u8 = null,
    /// Enable gzip compression for cache entries (default: true, v1.5.0).
    compression: bool = true,
    /// Enable incremental sync with chunking (default: false, v1.5.0).
    incremental_sync: bool = false,

    pub fn deinit(self: *RemoteCacheConfig, allocator: std.mem.Allocator) void {
        if (self.bucket) |b| allocator.free(b);
        if (self.region) |r| allocator.free(r);
        if (self.prefix) |p| allocator.free(p);
        if (self.url) |u| allocator.free(u);
        if (self.auth) |a| allocator.free(a);
    }
};

/// Cache configuration from [cache] section (Phase 2 local + Phase 7 remote).
pub const CacheConfig = struct {
    /// Enable caching (default: false).
    enabled: bool = false,
    /// Local cache directory (default: "$HOME/.zr/cache", owned).
    local_dir: ?[]const u8 = null,
    /// Remote cache configuration (Phase 7).
    remote: ?RemoteCacheConfig = null,

    pub fn deinit(self: *CacheConfig, allocator: std.mem.Allocator) void {
        if (self.local_dir) |ld| allocator.free(ld);
        if (self.remote) |*r| {
            var remote_mut = r.*;
            remote_mut.deinit(allocator);
        }
    }
};

/// Constraint rule types for architecture governance (PRD §5.7.6).
pub const ConstraintRule = enum {
    /// Prohibit circular dependencies in the workspace.
    no_circular,
    /// Tag-based dependency control (e.g., app → lib allowed).
    tag_based,
    /// Explicitly ban specific dependencies.
    banned_dependency,

    pub fn parse(s: []const u8) !ConstraintRule {
        if (std.mem.eql(u8, s, "no-circular")) return .no_circular;
        if (std.mem.eql(u8, s, "tag-based")) return .tag_based;
        if (std.mem.eql(u8, s, "banned-dependency")) return .banned_dependency;
        return error.InvalidConstraintRule;
    }
};

/// Constraint scope selector (e.g., { tag = "app" } or specific project path).
pub const ConstraintScope = union(enum) {
    /// All workspace members.
    all,
    /// Projects with a specific tag.
    tag: []const u8,
    /// Specific project path.
    path: []const u8,

    pub fn deinit(self: *ConstraintScope, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .tag => |t| allocator.free(t),
            .path => |p| allocator.free(p),
            .all => {},
        }
    }
};

/// A single architecture constraint (from [[constraints]] section).
pub const Constraint = struct {
    /// Constraint rule type.
    rule: ConstraintRule,
    /// Scope of projects this constraint applies to (for no-circular: "all").
    scope: ConstraintScope = .all,
    /// Source scope for directional constraints (tag-based, banned-dependency).
    from: ?ConstraintScope = null,
    /// Target scope for directional constraints (tag-based, banned-dependency).
    to: ?ConstraintScope = null,
    /// Whether the dependency is allowed (true) or banned (false).
    allow: bool = true,
    /// Optional custom error message for violations.
    message: ?[]const u8 = null,

    pub fn deinit(self: *Constraint, allocator: std.mem.Allocator) void {
        var scope_mut = self.scope;
        scope_mut.deinit(allocator);
        if (self.from) |f| {
            var from_mut = f;
            from_mut.deinit(allocator);
        }
        if (self.to) |t| {
            var to_mut = t;
            to_mut.deinit(allocator);
        }
        if (self.message) |m| allocator.free(m);
    }
};

/// Repository configuration from [repos.NAME] section (PRD §5.9 Phase 7).
pub const RepoConfig = struct {
    /// Repository name (section key).
    name: []const u8,
    /// Git URL for cloning.
    url: []const u8,
    /// Local checkout path (relative or absolute).
    path: []const u8,
    /// Target branch for operations.
    branch: []const u8 = "main",
    /// Repository tags for filtering.
    tags: [][]const u8 = &.{},

    pub fn deinit(self: *RepoConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.url);
        allocator.free(self.path);
        allocator.free(self.branch);
        for (self.tags) |tag| allocator.free(tag);
        if (self.tags.len > 0) allocator.free(self.tags);
    }
};

/// Multi-repo workspace configuration (PRD §5.9 Phase 7).
pub const RepoWorkspaceConfig = struct {
    /// Workspace name from [workspace] section.
    name: ?[]const u8 = null,
    /// Repository configurations from [repos.NAME] sections.
    repos: []RepoConfig = &.{},
    /// Cross-repo dependencies from [deps] section (repo_name -> [dependencies]).
    dependencies: std.StringHashMap([][]const u8),

    pub fn init(allocator: std.mem.Allocator) RepoWorkspaceConfig {
        return .{
            .name = null,
            .repos = &.{},
            .dependencies = std.StringHashMap([][]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *RepoWorkspaceConfig, allocator: std.mem.Allocator) void {
        if (self.name) |n| allocator.free(n);
        for (self.repos) |*repo| {
            var repo_mut = repo.*;
            repo_mut.deinit(allocator);
        }
        if (self.repos.len > 0) allocator.free(self.repos);

        // Free dependencies
        var it = self.dependencies.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            if (entry.value_ptr.len > 0) allocator.free(entry.value_ptr.*);
        }
        self.dependencies.deinit();
    }
};

pub const Config = struct {
    tasks: std.StringHashMap(Task),
    workflows: std.StringHashMap(Workflow),
    profiles: std.StringHashMap(Profile),
    /// Task templates from [templates.NAME] sections.
    templates: std.StringHashMap(TaskTemplate),
    /// Workspace config from [workspace] section, or null if not present.
    workspace: ?Workspace = null,
    /// Plugin configs from [plugins.NAME] sections (owned).
    plugins: []PluginConfig = &.{},
    /// Global resource limits from [global.resources] section.
    global_resources: GlobalResourceConfig = .{},
    /// Toolchain config from [tools] section (Phase 5).
    toolchains: ToolchainConfig = .{ .tools = &.{} },
    /// Architecture constraints from [[constraints]] sections (Phase 6).
    constraints: []Constraint = &.{},
    /// Project metadata from [metadata] section (Phase 6).
    metadata: ?Metadata = null,
    /// Cache configuration from [cache] section (Phase 2 local + Phase 7 remote).
    cache: CacheConfig = .{},
    /// Versioning configuration from [versioning] section (Phase 8).
    versioning: ?VersioningConfig = null,
    /// Conformance configuration from [conformance] section (Phase 8).
    conformance: ConformanceConfig = .{ .rules = &.{}, .fail_on_warning = false, .ignore = &.{} },
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .tasks = std.StringHashMap(Task).init(allocator),
            .workflows = std.StringHashMap(Workflow).init(allocator),
            .profiles = std.StringHashMap(Profile).init(allocator),
            .templates = std.StringHashMap(TaskTemplate).init(allocator),
            .workspace = null,
            .plugins = &.{},
            .toolchains = ToolchainConfig.init(allocator),
            .conformance = ConformanceConfig.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        var it = self.tasks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.tasks.deinit();
        var wit = self.workflows.iterator();
        while (wit.next()) |entry| {
            // Workflow.deinit frees entry.value_ptr.name, which is the same
            // allocation as entry.key_ptr.* — do NOT free the key separately.
            entry.value_ptr.deinit(self.allocator);
        }
        self.workflows.deinit();
        var pit = self.profiles.iterator();
        while (pit.next()) |entry| {
            // Profile.deinit frees entry.value_ptr.name (same allocation as key)
            entry.value_ptr.deinit(self.allocator);
        }
        self.profiles.deinit();
        var tit = self.templates.iterator();
        while (tit.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.templates.deinit();
        if (self.workspace) |*ws| ws.deinit(self.allocator);
        for (self.plugins) |*p| {
            var pc = p.*;
            pc.deinit(self.allocator);
        }
        if (self.plugins.len > 0) self.allocator.free(self.plugins);
        self.toolchains.deinit(self.allocator);
        for (self.constraints) |*c| {
            c.deinit(self.allocator);
        }
        if (self.constraints.len > 0) self.allocator.free(self.constraints);
        if (self.metadata) |*m| m.deinit(self.allocator);
        self.cache.deinit(self.allocator);
        if (self.versioning) |*v| v.deinit();
        self.conformance.deinit(self.allocator);
    }

    /// Apply a named profile to this config. Merges profile env vars into all tasks
    /// and applies any task-level overrides (cmd, cwd, env additions).
    /// Returns error.ProfileNotFound if the profile doesn't exist.
    pub fn applyProfile(self: *Config, profile_name: []const u8) !void {
        const profile = self.profiles.get(profile_name) orelse return error.ProfileNotFound;

        var task_it = self.tasks.iterator();
        while (task_it.next()) |entry| {
            const task = entry.value_ptr;

            // Build merged env: existing task env + profile global env (profile wins)
            // First find if there's a task-level override in the profile
            const task_override: ?ProfileTaskOverride = if (profile.task_overrides.get(task.name)) |ov| ov else null;

            // Count extra env entries: profile global + task-override env
            const extra_global = profile.env.len;
            const extra_task = if (task_override) |ov| ov.env.len else 0;
            const total_env = task.env.len + extra_global + extra_task;

            if (total_env > task.env.len) {
                // Allocate new env slice
                const new_env = try self.allocator.alloc([2][]const u8, total_env);
                var env_duped: usize = 0;
                errdefer {
                    for (new_env[0..env_duped]) |pair| {
                        self.allocator.free(pair[0]);
                        self.allocator.free(pair[1]);
                    }
                    self.allocator.free(new_env);
                }

                // Copy existing task env
                for (task.env, 0..) |pair, i| {
                    new_env[i][0] = try self.allocator.dupe(u8, pair[0]);
                    errdefer self.allocator.free(new_env[i][0]);
                    new_env[i][1] = try self.allocator.dupe(u8, pair[1]);
                    env_duped += 1;
                }

                // Append profile global env
                for (profile.env, 0..) |pair, i| {
                    const idx = task.env.len + i;
                    new_env[idx][0] = try self.allocator.dupe(u8, pair[0]);
                    errdefer self.allocator.free(new_env[idx][0]);
                    new_env[idx][1] = try self.allocator.dupe(u8, pair[1]);
                    env_duped += 1;
                }

                // Append profile task-level env overrides
                if (task_override) |ov| {
                    for (ov.env, 0..) |pair, i| {
                        const idx = task.env.len + extra_global + i;
                        new_env[idx][0] = try self.allocator.dupe(u8, pair[0]);
                        errdefer self.allocator.free(new_env[idx][0]);
                        new_env[idx][1] = try self.allocator.dupe(u8, pair[1]);
                        env_duped += 1;
                    }
                }

                // Free old env and replace
                for (task.env) |pair| {
                    self.allocator.free(pair[0]);
                    self.allocator.free(pair[1]);
                }
                self.allocator.free(task.env);
                task.env = new_env;
            }

            // Apply task-level cmd/cwd overrides
            if (task_override) |ov| {
                if (ov.cmd) |new_cmd| {
                    self.allocator.free(task.cmd);
                    task.cmd = try self.allocator.dupe(u8, new_cmd);
                }
                if (ov.cwd) |new_cwd| {
                    if (task.cwd) |old_cwd| self.allocator.free(old_cwd);
                    task.cwd = try self.allocator.dupe(u8, new_cwd);
                }
            }
        }
    }

    /// Add a task directly (useful for tests and programmatic construction).
    pub fn addTask(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_]ConditionalDep{}, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, null, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a task with all fields (for tests or programmatic use with full options).
    pub fn addTaskFull(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        timeout_ms: ?u64,
        allow_failure: bool,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_]ConditionalDep{}, &[_][]const u8{}, &[_][2][]const u8{}, timeout_ms, allow_failure, 0, 0, false, null, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a task with deps_serial (for tests or programmatic use).
    pub fn addTaskWithSerial(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        deps_serial: []const []const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, deps_serial, &[_]ConditionalDep{}, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, null, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a task with env pairs (for tests or programmatic use with env overrides).
    pub fn addTaskWithEnv(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        env: []const [2][]const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_]ConditionalDep{}, &[_][]const u8{}, env, null, false, 0, 0, false, null, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a task with retry settings (for tests or programmatic use).
    pub fn addTaskWithRetry(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        cwd: ?[]const u8,
        description: ?[]const u8,
        deps: []const []const u8,
        retry_max: u32,
        retry_delay_ms: u64,
        retry_backoff: bool,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, cwd, description, deps, &[_][]const u8{}, &[_]ConditionalDep{}, &[_][]const u8{}, &[_][2][]const u8{}, null, false, retry_max, retry_delay_ms, retry_backoff, null, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a task with a condition expression (for tests or programmatic use).
    pub fn addTaskWithCondition(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        condition: ?[]const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]ConditionalDep{}, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, condition, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a task with conditional dependencies (for tests or programmatic use).
    pub fn addTaskWithDepsIf(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        deps_if: []const ConditionalDep,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, null, null, &[_][]const u8{}, &[_][]const u8{}, deps_if, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, null, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a task with optional dependencies (for tests or programmatic use).
    pub fn addTaskWithDepsOptional(
        self: *Config,
        name: []const u8,
        cmd: []const u8,
        deps_optional: []const []const u8,
    ) !void {
        return addTaskImpl(self, self.allocator, name, cmd, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]ConditionalDep{}, deps_optional, &[_][2][]const u8{}, null, false, 0, 0, false, null, null, null, 0, false, null, null, &[_][]const u8{}, &[_][]const u8{}, &[_]u32{}, null, null, &[_][]const u8{}, &[_][]const u8{}, null, &[_]TaskHook{}, null, &[_][2][]const u8{}, null, null, null, null, &[_][2][]const u8{});
    }

    /// Add a workflow (for tests or programmatic use).
    pub fn addWorkflow(
        self: *Config,
        name: []const u8,
        description: ?[]const u8,
        stages: []const Stage,
        retry_budget: ?u32,
    ) !void {
        const wf_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(wf_name);

        const wf_desc = if (description) |d| try self.allocator.dupe(u8, d) else null;
        errdefer if (wf_desc) |d| self.allocator.free(d);

        const wf_stages = try self.allocator.alloc(Stage, stages.len);
        var stages_duped: usize = 0;
        errdefer {
            for (wf_stages[0..stages_duped]) |*s| s.deinit(self.allocator);
            self.allocator.free(wf_stages);
        }
        for (stages, 0..) |stage, i| {
            const s_name = try self.allocator.dupe(u8, stage.name);
            errdefer self.allocator.free(s_name);

            const s_tasks = try self.allocator.alloc([]const u8, stage.tasks.len);
            var tasks_duped: usize = 0;
            errdefer {
                for (s_tasks[0..tasks_duped]) |t| self.allocator.free(t);
                self.allocator.free(s_tasks);
            }
            for (stage.tasks, 0..) |t, j| {
                s_tasks[j] = try self.allocator.dupe(u8, t);
                tasks_duped += 1;
            }

            const s_cond = if (stage.condition) |c| try self.allocator.dupe(u8, c) else null;
            errdefer if (s_cond) |c| self.allocator.free(c);

            const s_on_failure = if (stage.on_failure) |f| try self.allocator.dupe(u8, f) else null;
            errdefer if (s_on_failure) |f| self.allocator.free(f);

            wf_stages[i] = Stage{
                .name = s_name,
                .tasks = s_tasks,
                .parallel = stage.parallel,
                .fail_fast = stage.fail_fast,
                .condition = s_cond,
                .approval = stage.approval,
                .on_failure = s_on_failure,
            };
            stages_duped += 1;
        }

        const wf = Workflow{
            .name = wf_name,
            .description = wf_desc,
            .stages = wf_stages,
            .retry_budget = retry_budget,
        };

        try self.workflows.put(wf_name, wf);
    }

    /// Expand a template into a task with parameter substitution.
    /// Parameters are provided as key-value pairs, and ${key} placeholders
    /// in the template are replaced with the corresponding values.
    pub fn expandTemplate(
        self: *Config,
        task_name: []const u8,
        template_name: []const u8,
        params: std.StringHashMap([]const u8),
    ) !void {
        const template = self.templates.get(template_name) orelse return error.TemplateNotFound;

        // Validate that all required parameters are provided
        for (template.params) |param| {
            if (!params.contains(param)) {
                return error.MissingTemplateParameter;
            }
        }

        // Substitute parameters in cmd
        const expanded_cmd = try substituteParams(self.allocator, template.cmd, params);
        errdefer self.allocator.free(expanded_cmd);

        // Substitute parameters in cwd
        const expanded_cwd = if (template.cwd) |cwd|
            try substituteParams(self.allocator, cwd, params)
        else
            null;
        errdefer if (expanded_cwd) |c| self.allocator.free(c);

        // Substitute parameters in description
        const expanded_desc = if (template.description) |desc|
            try substituteParams(self.allocator, desc, params)
        else
            null;
        errdefer if (expanded_desc) |d| self.allocator.free(d);

        // Substitute parameters in condition
        const expanded_condition = if (template.condition) |cond|
            try substituteParams(self.allocator, cond, params)
        else
            null;
        errdefer if (expanded_condition) |c| self.allocator.free(c);

        // Create task using addTaskImpl with template defaults
        try addTaskImpl(
            self,
            self.allocator,
            task_name,
            expanded_cmd,
            expanded_cwd,
            expanded_desc,
            template.deps,
            template.deps_serial,
            &[_]ConditionalDep{}, // deps_if not supported in templates yet
            &[_][]const u8{}, // deps_optional not supported in templates yet
            template.env,
            template.timeout_ms,
            template.allow_failure,
            template.retry_max,
            template.retry_delay_ms,
            template.retry_backoff,
            expanded_condition,
            null, // skip_if not supported in templates yet
            null, // output_if not supported in templates yet
            template.max_concurrent,
            template.cache,
            template.max_cpu,
            template.max_memory,
            template.toolchain,
            &[_][]const u8{}, // tags not supported in templates yet
            &[_]u32{}, // cpu_affinity not supported in templates yet
            null, // numa_node not supported in templates yet
            null, // watch_debounce_ms not supported in templates yet
            &[_][]const u8{}, // watch_patterns not supported in templates yet
            &[_][]const u8{}, // watch_exclude_patterns not supported in templates yet
            null, // watch_mode not supported in templates yet
            &[_]TaskHook{}, // hooks not supported in templates yet
            null, // template - already being applied
            &[_][2][]const u8{}, // params - already used for substitution, no need to store
            null, // output_file not supported in templates yet
            null, // output_mode not supported in templates yet
            null, // remote not supported in templates yet
            null, // remote_cwd not supported in templates yet
            &[_][2][]const u8{}, // remote_env not supported in templates yet
        );

        // Free the allocated strings (addTaskImpl dupes them)
        self.allocator.free(expanded_cmd);
        if (expanded_cwd) |c| self.allocator.free(c);
        if (expanded_desc) |d| self.allocator.free(d);
        if (expanded_condition) |c| self.allocator.free(c);
    }

    /// Substitute ${param} placeholders in a string with values from the params map.
    fn substituteParams(
        allocator: std.mem.Allocator,
        template_str: []const u8,
        params: std.StringHashMap([]const u8),
    ) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        var i: usize = 0;
        while (i < template_str.len) {
            if (i + 2 < template_str.len and template_str[i] == '$' and template_str[i + 1] == '{') {
                // Find the closing brace
                const start = i + 2;
                var end = start;
                while (end < template_str.len and template_str[end] != '}') : (end += 1) {}
                if (end >= template_str.len) {
                    return error.UnclosedPlaceholder;
                }

                const param_name = template_str[start..end];
                const value = params.get(param_name) orelse return error.UnknownParameter;
                try result.appendSlice(allocator, value);
                i = end + 1;
            } else {
                try result.append(allocator, template_str[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(allocator);
    }
};

/// Task template definition for reusable task configurations.
/// Templates can be expanded with parameter substitution (e.g., ${param}).
pub const TaskTemplate = struct {
    /// Template name (unique identifier).
    name: []const u8,
    /// Command template with parameter placeholders.
    cmd: []const u8,
    /// Optional working directory template.
    cwd: ?[]const u8 = null,
    /// Optional description template.
    description: ?[]const u8 = null,
    /// Default dependencies (can be overridden).
    deps: [][]const u8 = &.{},
    /// Default sequential dependencies.
    deps_serial: [][]const u8 = &.{},
    /// Default environment variables.
    env: [][2][]const u8 = &.{},
    /// Default timeout.
    timeout_ms: ?u64 = null,
    /// Default allow_failure flag.
    allow_failure: bool = false,
    /// Default retry configuration.
    retry_max: u32 = 0,
    retry_delay_ms: u64 = 0,
    retry_backoff: bool = false,
    /// Default condition expression.
    condition: ?[]const u8 = null,
    /// Default max_concurrent.
    max_concurrent: u32 = 0,
    /// Default cache flag.
    cache: bool = false,
    /// Default resource limits.
    max_cpu: ?u32 = null,
    max_memory: ?u64 = null,
    /// Default toolchain requirements.
    toolchain: [][]const u8 = &.{},
    /// Required template parameters (parameter names to be substituted).
    params: [][]const u8 = &.{},

    pub fn deinit(self: *TaskTemplate, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.cmd);
        if (self.cwd) |cwd| allocator.free(cwd);
        if (self.description) |desc| allocator.free(desc);
        for (self.deps) |dep| allocator.free(dep);
        if (self.deps.len > 0) allocator.free(self.deps);
        for (self.deps_serial) |dep| allocator.free(dep);
        if (self.deps_serial.len > 0) allocator.free(self.deps_serial);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        if (self.env.len > 0) allocator.free(self.env);
        if (self.condition) |c| allocator.free(c);
        for (self.toolchain) |tc| allocator.free(tc);
        if (self.toolchain.len > 0) allocator.free(self.toolchain);
        for (self.params) |p| allocator.free(p);
        if (self.params.len > 0) allocator.free(self.params);
    }
};

/// Conditional dependency: a dependency that only runs if a condition is met.
pub const ConditionalDep = struct {
    /// Task name to depend on.
    task: []const u8,
    /// Condition expression (evaluates to boolean).
    condition: []const u8,

    pub fn deinit(self: *ConditionalDep, allocator: std.mem.Allocator) void {
        allocator.free(self.task);
        allocator.free(self.condition);
    }
};

/// Watch mode configuration for a task ([tasks.*.watch] section).
/// v1.17.0 feature for advanced watch mode.
/// Circuit breaker configuration for task retries.
/// Automatically stops retrying if failure rate exceeds threshold.
/// v1.30.0 feature for enhanced error recovery.
pub const CircuitBreakerConfig = struct {
    /// Failure threshold: if failure_count / (failure_count + success_count) > threshold, circuit opens.
    /// Range: 0.0 to 1.0 (e.g., 0.5 = 50% failure rate trips the breaker).
    failure_threshold: f64 = 0.5,
    /// Time window in milliseconds to track failures (default: 60 seconds).
    /// Failures older than this are not counted toward the threshold.
    window_ms: u64 = 60_000,
    /// Minimum number of attempts before circuit breaker can trip (prevents tripping on first failure).
    /// Default: 3 attempts.
    min_attempts: u32 = 3,
    /// How long the circuit stays open before attempting to retry again (half-open state).
    /// Default: 30 seconds.
    reset_timeout_ms: u64 = 30_000,
};

/// Checkpoint configuration for long-running tasks.
/// Enables saving progress and resuming from last checkpoint on failure.
/// v1.30.0 feature for enhanced error recovery.
pub const CheckpointConfig = struct {
    /// Enable checkpointing for this task.
    enabled: bool = false,
    /// Interval in milliseconds between checkpoint saves (default: 5 minutes).
    /// The task must emit a checkpoint marker to stdout for this to work.
    /// Format: "CHECKPOINT: <state_data>" where state_data is task-specific.
    interval_ms: u64 = 300_000,
    /// Storage backend for checkpoints: "file" (default), "memory", "redis", "s3".
    /// Only "file" is implemented in v1.30.0, others planned for future versions.
    storage: []const u8 = "file",
    /// Directory to store checkpoint files (default: .zr/checkpoints/).
    /// Only used when storage = "file".
    checkpoint_dir: []const u8 = ".zr/checkpoints",

    pub fn deinit(self: *CheckpointConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.storage);
        allocator.free(self.checkpoint_dir);
    }
};

pub const WatchConfig = struct {
    /// Debounce delay in milliseconds before triggering task execution.
    /// Multiple rapid changes within this window are coalesced into one execution.
    /// Default: 300ms
    debounce_ms: u64 = 300,
    /// Glob patterns for file inclusion (e.g., ["**/*.zig", "*.toml"]).
    /// Empty list means watch all files in the paths.
    patterns: [][]const u8 = &.{},
    /// Glob patterns for file exclusion (e.g., ["**/*.test.zig", "node_modules/**"]).
    /// Takes precedence over include patterns.
    exclude_patterns: [][]const u8 = &.{},
    /// Watch mode: "native" (inotify/kqueue/ReadDirectoryChangesW) or "polling"
    /// If null, auto-selects native if available, fallback to polling.
    mode: ?[]const u8 = null,

    pub fn deinit(self: *WatchConfig, allocator: std.mem.Allocator) void {
        for (self.patterns) |p| allocator.free(p);
        if (self.patterns.len > 0) allocator.free(self.patterns);
        for (self.exclude_patterns) |p| allocator.free(p);
        if (self.exclude_patterns.len > 0) allocator.free(self.exclude_patterns);
        if (self.mode) |m| allocator.free(m);
    }
};

/// Task hook definition for setup/teardown operations.
/// v1.24.0 feature for execution hooks.
pub const TaskHook = struct {
    /// Command to execute (shell command).
    cmd: []const u8,
    /// Hook execution point (before, after, success, failure, timeout).
    point: HookPoint,
    /// Failure handling strategy (continue_task or abort_task).
    failure_strategy: HookFailureStrategy = .continue_task,
    /// Optional working directory override (null = use task cwd).
    working_dir: ?[]const u8 = null,
    /// Optional environment variables for the hook.
    env: [][2][]const u8 = &.{},

    pub fn deinit(self: *TaskHook, allocator: std.mem.Allocator) void {
        allocator.free(self.cmd);
        if (self.working_dir) |wd| allocator.free(wd);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        if (self.env.len > 0) allocator.free(self.env);
    }
};

pub const Task = struct {
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: [][]const u8,
    /// Sequential dependencies: run in array order before this task, one at a time.
    deps_serial: [][]const u8,
    /// Conditional dependencies: run only if condition evaluates to true.
    deps_if: []ConditionalDep = &.{},
    /// Optional dependencies: ignore if task doesn't exist, but respect if it does.
    deps_optional: [][]const u8 = &.{},
    /// Environment variable overrides. Each entry is [key, value] (owned, duped).
    env: [][2][]const u8,
    /// Timeout in milliseconds. null means no timeout.
    timeout_ms: ?u64 = null,
    /// If true, a non-zero exit code is treated as success for dependency purposes.
    allow_failure: bool = false,
    /// Maximum number of retry attempts after the first failure (0 = no retry).
    retry_max: u32 = 0,
    /// Delay between retry attempts in milliseconds.
    retry_delay_ms: u64 = 0,
    /// If true, delay doubles on each retry attempt (exponential backoff).
    /// DEPRECATED in v1.47.0: use retry_backoff_multiplier instead.
    retry_backoff: bool = false,
    /// Backoff multiplier for retry delays (v1.47.0).
    /// 1.0 = linear (constant delay), 2.0 = exponential (double each time), 1.5 = moderate growth.
    /// If null, uses legacy retry_backoff behavior (multiplier = 2.0 if true, 1.0 if false).
    retry_backoff_multiplier: ?f64 = null,
    /// If true, add random jitter (±25%) to retry delays to prevent thundering herd (v1.47.0).
    retry_jitter: bool = false,
    /// Maximum delay between retries in milliseconds (ceiling for backoff calculation) (v1.47.0).
    max_backoff_ms: ?u64 = null,
    /// If non-empty, only retry when exit code matches one of these codes (v1.47.0).
    retry_on_codes: []const u8 = &[_]u8{},
    /// If non-empty, only retry when stdout/stderr contains one of these patterns (v1.47.0).
    retry_on_patterns: []const []const u8 = &[_][]const u8{},
    /// Optional condition expression. If null, task always runs.
    /// If set, evaluated before the task runs; task is skipped if false.
    condition: ?[]const u8 = null,
    /// Optional skip condition expression (inverse of condition).
    /// If set, task is skipped if the expression evaluates to true.
    /// More intuitive than negating a condition (e.g., skip_if = "git.dirty" vs condition = "!git.dirty").
    /// v1.18.0 feature.
    skip_if: ?[]const u8 = null,
    /// Optional output condition expression.
    /// If set, task output is only shown if the expression evaluates to true.
    /// Useful for hiding verbose output in certain conditions (e.g., output_if = "env.DEBUG == 'true'").
    /// v1.18.0 feature.
    output_if: ?[]const u8 = null,
    /// Maximum number of concurrent instances of this task (0 = unlimited).
    max_concurrent: u32 = 0,
    /// If true, cache successful runs and skip on subsequent runs with same cmd+env.
    cache: bool = false,
    /// Maximum CPU cores this task can use (null = unlimited).
    max_cpu: ?u32 = null,
    /// Maximum memory this task can use in bytes (null = unlimited).
    max_memory: ?u64 = null,
    /// Optional toolchain requirements for this task (e.g., ["node@20.11", "python@3.12"]).
    /// If specified and not installed, will be auto-installed before running the task.
    toolchain: [][]const u8 = &.{},
    /// Task categorization tags (e.g., ["build", "test", "ci"]).
    /// Used for filtering and grouping tasks.
    tags: [][]const u8 = &.{},
    /// CPU affinity: list of CPU IDs this task should be pinned to (null = no affinity).
    /// Example: [0, 1] means the task can only run on CPU 0 or CPU 1.
    /// v1.13.0 feature for parallel execution optimizations.
    cpu_affinity: ?[]u32 = null,
    /// NUMA node hint: preferred NUMA node for this task (null = no preference).
    /// The scheduler will try to run this task on a worker thread in the specified NUMA node.
    /// v1.13.0 feature for NUMA-aware scheduling.
    numa_node: ?u32 = null,
    /// Watch mode configuration for this task (null = use default watch behavior).
    /// v1.17.0 feature for advanced watch mode.
    watch: ?WatchConfig = null,
    /// Hooks for task lifecycle events (before, after, success, failure, timeout).
    /// v1.24.0 feature for execution hooks.
    hooks: []TaskHook = &.{},
    /// Template to use for this task (references a [templates.NAME] section).
    /// If set, the task inherits all fields from the template, with task-specific
    /// fields overriding template defaults.
    /// v1.29.0 feature for task templates.
    template: ?[]const u8 = null,
    /// Parameters to substitute in the template command and fields.
    /// Each entry is [param_name, param_value] (e.g., [["port", "3000"], ["host", "localhost"]]).
    /// Template placeholders use ${param_name} syntax.
    /// v1.29.0 feature for task templates.
    params: [][2][]const u8 = &.{},
    /// Circuit breaker configuration for automatic retry failure rate limiting.
    /// If null, circuit breaker is disabled (retries will continue up to retry_max).
    /// v1.30.0 feature for enhanced error recovery.
    circuit_breaker: ?CircuitBreakerConfig = null,
    /// Checkpoint configuration for long-running tasks.
    /// Enables saving progress and resuming from last checkpoint on failure.
    /// v1.30.0 feature for enhanced error recovery.
    checkpoint: ?CheckpointConfig = null,
    /// Output file path for streaming task stdout/stderr to a file.
    /// If null, output is inherited (displayed in terminal or captured by TUI).
    /// v1.37.0 feature for enhanced task output capture.
    output_file: ?[]const u8 = null,
    /// Output mode: "stream" (file), "buffer" (memory), "discard" (drop output).
    /// Default is null (use inherit mode based on context).
    /// v1.37.0 feature for enhanced task output capture.
    output_mode: ?[]const u8 = null,
    /// Remote execution target: SSH (user@host:port or ssh://user@host:port) or HTTP/HTTPS endpoint.
    /// If null, task runs locally.
    /// v1.45.0 feature for remote execution.
    remote: ?[]const u8 = null,
    /// Remote working directory for execution (null = remote home or default).
    /// v1.45.0 feature for remote execution.
    remote_cwd: ?[]const u8 = null,
    /// Remote environment variables (separate from local env).
    /// Each entry is [key, value] (owned, duped).
    /// v1.45.0 feature for remote execution.
    remote_env: ?[][2][]const u8 = null,

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.cmd);
        if (self.cwd) |cwd| allocator.free(cwd);
        if (self.description) |desc| allocator.free(desc);
        for (self.deps) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.deps);
        for (self.deps_serial) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.deps_serial);
        for (self.deps_if) |*dep| {
            dep.deinit(allocator);
        }
        if (self.deps_if.len > 0) allocator.free(self.deps_if);
        for (self.deps_optional) |dep| {
            allocator.free(dep);
        }
        if (self.deps_optional.len > 0) allocator.free(self.deps_optional);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.env);
        if (self.condition) |c| allocator.free(c);
        if (self.skip_if) |s| allocator.free(s);
        if (self.output_if) |o| allocator.free(o);
        for (self.toolchain) |tc| allocator.free(tc);
        if (self.toolchain.len > 0) allocator.free(self.toolchain);
        for (self.tags) |tag| allocator.free(tag);
        if (self.tags.len > 0) allocator.free(self.tags);
        if (self.cpu_affinity) |affinity| allocator.free(affinity);
        if (self.watch) |*w| w.deinit(allocator);
        for (self.hooks) |*h| h.deinit(allocator);
        if (self.hooks.len > 0) allocator.free(self.hooks);
        if (self.template) |t| allocator.free(t);
        for (self.params) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        if (self.params.len > 0) allocator.free(self.params);
        if (self.checkpoint) |*cp| cp.deinit(allocator);
        if (self.output_file) |of| allocator.free(of);
        if (self.output_mode) |om| allocator.free(om);
        if (self.remote) |r| allocator.free(r);
        if (self.remote_cwd) |rc| allocator.free(rc);
        if (self.remote_env) |re| {
            for (re) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            allocator.free(re);
        }
        // v1.47.0 retry strategy fields
        if (self.retry_on_codes.len > 0) allocator.free(self.retry_on_codes);
        for (self.retry_on_patterns) |pattern| allocator.free(pattern);
        if (self.retry_on_patterns.len > 0) allocator.free(self.retry_on_patterns);
    }
};

pub const Stage = struct {
    name: []const u8,
    tasks: [][]const u8,
    parallel: bool = true,
    fail_fast: bool = false,
    condition: ?[]const u8 = null,
    /// Require manual approval before executing this stage (interactive mode).
    approval: bool = false,
    /// Task to run on stage failure (e.g., "notify-slack").
    on_failure: ?[]const u8 = null,

    pub fn deinit(self: *Stage, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.tasks) |t| allocator.free(t);
        allocator.free(self.tasks);
        if (self.condition) |c| allocator.free(c);
        if (self.on_failure) |f| allocator.free(f);
    }
};

pub const Workflow = struct {
    name: []const u8,
    description: ?[]const u8,
    stages: []Stage,
    /// Maximum total retry attempts allowed across all tasks in this workflow (null = unlimited).
    /// This prevents retry storms where many tasks fail and retry simultaneously.
    /// v1.30.0 feature for enhanced error recovery.
    retry_budget: ?u32 = null,

    pub fn deinit(self: *Workflow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |d| allocator.free(d);
        for (self.stages) |*stage| stage.deinit(allocator);
        allocator.free(self.stages);
    }
};

/// Per-task overrides within a profile.
pub const ProfileTaskOverride = struct {
    /// Optional command override (replaces task cmd).
    cmd: ?[]const u8 = null,
    /// Optional working directory override.
    cwd: ?[]const u8 = null,
    /// Additional env vars merged into task env (profile wins over task defaults).
    env: [][2][]const u8,

    pub fn deinit(self: *ProfileTaskOverride, allocator: std.mem.Allocator) void {
        if (self.cmd) |c| allocator.free(c);
        if (self.cwd) |c| allocator.free(c);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.env);
    }
};

/// A named profile that overrides config at runtime.
pub const Profile = struct {
    name: []const u8,
    /// Global env vars added to all tasks when this profile is active.
    env: [][2][]const u8,
    /// Per-task overrides keyed by task name.
    task_overrides: std.StringHashMap(ProfileTaskOverride),

    pub fn deinit(self: *Profile, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(self.env);
        var it = self.task_overrides.iterator();
        while (it.next()) |entry| {
            // key is same allocation as ProfileTaskOverride name stored inside
            // the map; we manage keys separately.
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.task_overrides.deinit();
    }
};

/// One dimension of a matrix definition: a named variable and its possible values.
pub const MatrixDim = struct {
    key: []const u8,
    values: [][]const u8,

    pub fn deinit(self: *MatrixDim, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        for (self.values) |v| allocator.free(v);
        allocator.free(self.values);
    }
};

/// Parse a duration string like "5m", "30s", "1h", "500ms" into milliseconds.
/// Returns null if the format is unrecognized.
pub fn parseDurationMs(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    if (std.mem.endsWith(u8, s, "ms")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 2], 10) catch return null;
        return n;
    } else if (std.mem.endsWith(u8, s, "h")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 3_600_000;
    } else if (std.mem.endsWith(u8, s, "m")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 60_000;
    } else if (std.mem.endsWith(u8, s, "s")) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n * 1_000;
    }
    return null;
}

/// Parse a memory size string like "2GB", "512MB", "1024KB" into bytes.
/// Returns null if the format is unrecognized.
pub fn parseMemoryBytes(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    // Case-insensitive suffix matching
    if (s.len >= 2) {
        const last2 = s[s.len - 2 ..];
        if (std.ascii.eqlIgnoreCase(last2, "GB")) {
            const n = std.fmt.parseInt(u64, s[0 .. s.len - 2], 10) catch return null;
            return n * 1_073_741_824; // 1024^3
        } else if (std.ascii.eqlIgnoreCase(last2, "MB")) {
            const n = std.fmt.parseInt(u64, s[0 .. s.len - 2], 10) catch return null;
            return n * 1_048_576; // 1024^2
        } else if (std.ascii.eqlIgnoreCase(last2, "KB")) {
            const n = std.fmt.parseInt(u64, s[0 .. s.len - 2], 10) catch return null;
            return n * 1024;
        }
    }
    if (s.len >= 1 and (s[s.len - 1] == 'B' or s[s.len - 1] == 'b')) {
        const n = std.fmt.parseInt(u64, s[0 .. s.len - 1], 10) catch return null;
        return n;
    }
    // Try parsing as plain bytes
    return std.fmt.parseInt(u64, s, 10) catch null;
}

test "applyProfile: unknown profile returns ProfileNotFound" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    try config.addTask("build", "zig build", null, null, &[_][]const u8{});

    const result = config.applyProfile("nonexistent");
    try std.testing.expectError(error.ProfileNotFound, result);
}

test "applyProfile: profile global env is merged into tasks" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Add a task with no env vars.
    try config.addTask("build", "zig build", null, null, &[_][]const u8{});

    // Build a Profile with global env [["NODE_ENV", "production"]] and no task overrides.
    const p_name = try allocator.dupe(u8, "staging");
    errdefer allocator.free(p_name);

    const p_env = try allocator.alloc([2][]const u8, 1);
    p_env[0][0] = try allocator.dupe(u8, "NODE_ENV");
    p_env[0][1] = try allocator.dupe(u8, "production");

    const profile = Profile{
        .name = p_name,
        .env = p_env,
        .task_overrides = std.StringHashMap(ProfileTaskOverride).init(allocator),
    };

    try config.profiles.put(p_name, profile);

    try config.applyProfile("staging");

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(usize, 1), task.env.len);
    try std.testing.expectEqualStrings("NODE_ENV", task.env[0][0]);
    try std.testing.expectEqualStrings("production", task.env[0][1]);
}

test "applyProfile: task-level cmd override" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Add a task with cmd = "original".
    try config.addTask("deploy", "original", null, null, &[_][]const u8{});

    // Build a Profile with a task_override for "deploy" that overrides cmd.
    const p_name = try allocator.dupe(u8, "release");
    errdefer allocator.free(p_name);

    const p_env = try allocator.alloc([2][]const u8, 0);

    var task_overrides = std.StringHashMap(ProfileTaskOverride).init(allocator);
    errdefer {
        var it = task_overrides.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        task_overrides.deinit();
    }

    const ov_key = try allocator.dupe(u8, "deploy");
    const ov_cmd = try allocator.dupe(u8, "overridden");
    const ov_env = try allocator.alloc([2][]const u8, 0);

    const ov = ProfileTaskOverride{
        .cmd = ov_cmd,
        .cwd = null,
        .env = ov_env,
    };
    try task_overrides.put(ov_key, ov);

    const profile = Profile{
        .name = p_name,
        .env = p_env,
        .task_overrides = task_overrides,
    };
    try config.profiles.put(p_name, profile);

    try config.applyProfile("release");

    const task = config.tasks.get("deploy").?;
    try std.testing.expectEqualStrings("overridden", task.cmd);
}

test "applyProfile: task-level env override merges with global" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Add a task with no env vars.
    try config.addTask("build", "zig build", null, null, &[_][]const u8{});

    // Build a Profile with global env [["A", "1"]] and a task override with env [["B", "2"]].
    const p_name = try allocator.dupe(u8, "mixed");
    errdefer allocator.free(p_name);

    const p_env = try allocator.alloc([2][]const u8, 1);
    p_env[0][0] = try allocator.dupe(u8, "A");
    p_env[0][1] = try allocator.dupe(u8, "1");

    var task_overrides = std.StringHashMap(ProfileTaskOverride).init(allocator);
    errdefer {
        var it = task_overrides.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        task_overrides.deinit();
    }

    const ov_key = try allocator.dupe(u8, "build");
    const ov_env = try allocator.alloc([2][]const u8, 1);
    ov_env[0][0] = try allocator.dupe(u8, "B");
    ov_env[0][1] = try allocator.dupe(u8, "2");

    const ov = ProfileTaskOverride{
        .cmd = null,
        .cwd = null,
        .env = ov_env,
    };
    try task_overrides.put(ov_key, ov);

    const profile = Profile{
        .name = p_name,
        .env = p_env,
        .task_overrides = task_overrides,
    };
    try config.profiles.put(p_name, profile);

    try config.applyProfile("mixed");

    const task = config.tasks.get("build").?;
    try std.testing.expectEqual(@as(usize, 2), task.env.len);

    var found_a = false;
    var found_b = false;
    for (task.env) |pair| {
        if (std.mem.eql(u8, pair[0], "A") and std.mem.eql(u8, pair[1], "1")) found_a = true;
        if (std.mem.eql(u8, pair[0], "B") and std.mem.eql(u8, pair[1], "2")) found_b = true;
    }
    try std.testing.expect(found_a);
    try std.testing.expect(found_b);
}

test "parseMemoryBytes: various formats" {
    try std.testing.expectEqual(@as(?u64, 2 * 1_073_741_824), parseMemoryBytes("2GB"));
    try std.testing.expectEqual(@as(?u64, 2 * 1_073_741_824), parseMemoryBytes("2gb"));
    try std.testing.expectEqual(@as(?u64, 512 * 1_048_576), parseMemoryBytes("512MB"));
    try std.testing.expectEqual(@as(?u64, 512 * 1_048_576), parseMemoryBytes("512mb"));
    try std.testing.expectEqual(@as(?u64, 1024 * 1024), parseMemoryBytes("1024KB"));
    try std.testing.expectEqual(@as(?u64, 1024 * 1024), parseMemoryBytes("1024kb"));
    try std.testing.expectEqual(@as(?u64, 100), parseMemoryBytes("100B"));
    try std.testing.expectEqual(@as(?u64, 100), parseMemoryBytes("100b"));
    try std.testing.expectEqual(@as(?u64, 1234), parseMemoryBytes("1234"));
    try std.testing.expectEqual(@as(?u64, null), parseMemoryBytes(""));
    try std.testing.expectEqual(@as(?u64, null), parseMemoryBytes("invalid"));
}

/// Apply template fields to an existing task with parameter substitution.
/// This function modifies the task in-place by:
/// 1. Looking up the template from config.templates
/// 2. Converting params array to HashMap
/// 3. Substituting parameters in template fields
/// 4. Freeing original task fields and replacing with template-expanded values
/// Task-specific fields (non-empty cmd, non-null description, etc.) override template defaults.
fn applyTemplateToTask(
    config: *Config,
    allocator: std.mem.Allocator,
    task: *Task,
    template_name: []const u8,
    params: []const [2][]const u8,
) !void {
    // Look up template
    const template = config.templates.get(template_name) orelse return error.TemplateNotFound;

    // Convert params array to HashMap
    var params_map = std.StringHashMap([]const u8).init(allocator);
    defer params_map.deinit();
    for (params) |pair| {
        try params_map.put(pair[0], pair[1]);
    }

    // Validate that all required parameters are provided
    for (template.params) |param| {
        if (!params_map.contains(param)) {
            return error.MissingTemplateParameter;
        }
    }

    // Substitute parameters in cmd (only if task cmd is empty or still default)
    if (task.cmd.len == 0 or std.mem.eql(u8, task.cmd, "")) {
        const expanded_cmd = try Config.substituteParams(allocator, template.cmd, params_map);
        allocator.free(task.cmd);
        task.cmd = expanded_cmd;
    }

    // Substitute parameters in cwd (only if task cwd is null and template has one)
    if (task.cwd == null and template.cwd != null) {
        task.cwd = try Config.substituteParams(allocator, template.cwd.?, params_map);
    }

    // Substitute parameters in description (only if task description is null and template has one)
    if (task.description == null and template.description != null) {
        task.description = try Config.substituteParams(allocator, template.description.?, params_map);
    }

    // Apply template defaults for fields not explicitly set in the task
    if (task.timeout_ms == null and template.timeout_ms != null) {
        task.timeout_ms = template.timeout_ms;
    }

    if (!task.allow_failure and template.allow_failure) {
        task.allow_failure = template.allow_failure;
    }

    if (task.retry_max == 0 and template.retry_max > 0) {
        task.retry_max = template.retry_max;
        task.retry_delay_ms = template.retry_delay_ms;
        task.retry_backoff = template.retry_backoff;
    }

    if (task.condition == null and template.condition != null) {
        task.condition = try Config.substituteParams(allocator, template.condition.?, params_map);
    }

    if (task.max_concurrent == 0 and template.max_concurrent > 0) {
        task.max_concurrent = template.max_concurrent;
    }

    if (!task.cache and template.cache) {
        task.cache = template.cache;
    }

    if (task.max_cpu == null and template.max_cpu != null) {
        task.max_cpu = template.max_cpu;
    }

    if (task.max_memory == null and template.max_memory != null) {
        task.max_memory = template.max_memory;
    }

    // Merge dependencies (template deps + task deps)
    if (template.deps.len > 0) {
        const total_deps = task.deps.len + template.deps.len;
        const merged_deps = try allocator.alloc([]const u8, total_deps);
        @memcpy(merged_deps[0..task.deps.len], task.deps);
        for (template.deps, 0..) |dep, i| {
            merged_deps[task.deps.len + i] = try allocator.dupe(u8, dep);
        }
        allocator.free(task.deps);
        task.deps = merged_deps;
    }

    // Merge serial dependencies
    if (template.deps_serial.len > 0) {
        const total_serial = task.deps_serial.len + template.deps_serial.len;
        const merged_serial = try allocator.alloc([]const u8, total_serial);
        @memcpy(merged_serial[0..task.deps_serial.len], task.deps_serial);
        for (template.deps_serial, 0..) |dep, i| {
            merged_serial[task.deps_serial.len + i] = try allocator.dupe(u8, dep);
        }
        allocator.free(task.deps_serial);
        task.deps_serial = merged_serial;
    }

    // Merge environment variables (template env + task env, task takes precedence)
    if (template.env.len > 0) {
        const total_env = task.env.len + template.env.len;
        const merged_env = try allocator.alloc([2][]const u8, total_env);
        @memcpy(merged_env[0..task.env.len], task.env);
        for (template.env, 0..) |pair, i| {
            merged_env[task.env.len + i] = .{
                try allocator.dupe(u8, pair[0]),
                try allocator.dupe(u8, pair[1]),
            };
        }
        allocator.free(task.env);
        task.env = merged_env;
    }

    // Merge toolchain
    if (template.toolchain.len > 0 and task.toolchain.len == 0) {
        const toolchain_copy = try allocator.alloc([]const u8, template.toolchain.len);
        for (template.toolchain, 0..) |tool, i| {
            toolchain_copy[i] = try allocator.dupe(u8, tool);
        }
        task.toolchain = toolchain_copy;
    }
}

pub fn addTaskImpl(
    config: *Config,
    allocator: std.mem.Allocator,
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: []const []const u8,
    deps_serial: []const []const u8,
    deps_if: []const ConditionalDep,
    deps_optional: []const []const u8,
    env: []const [2][]const u8,
    timeout_ms: ?u64,
    allow_failure: bool,
    retry_max: u32,
    retry_delay_ms: u64,
    retry_backoff: bool,
    condition: ?[]const u8,
    skip_if: ?[]const u8,
    output_if: ?[]const u8,
    max_concurrent: u32,
    cache: bool,
    max_cpu: ?u32,
    max_memory: ?u64,
    toolchain: []const []const u8,
    tags: []const []const u8,
    cpu_affinity: []const u32,
    numa_node: ?u32,
    watch_debounce_ms: ?u64,
    watch_patterns: []const []const u8,
    watch_exclude_patterns: []const []const u8,
    watch_mode: ?[]const u8,
    hooks: []const TaskHook,
    template: ?[]const u8,
    params: []const [2][]const u8,
    output_file: ?[]const u8,
    output_mode: ?[]const u8,
    remote: ?[]const u8,
    remote_cwd: ?[]const u8,
    remote_env: []const [2][]const u8,
) !void {
    const task_name = try allocator.dupe(u8, name);
    errdefer allocator.free(task_name);

    const task_cmd = try allocator.dupe(u8, cmd);
    errdefer allocator.free(task_cmd);

    const task_cwd = if (cwd) |c| try allocator.dupe(u8, c) else null;
    errdefer if (task_cwd) |c| allocator.free(c);

    const task_desc = if (description) |d| try allocator.dupe(u8, d) else null;
    errdefer if (task_desc) |d| allocator.free(d);

    const task_deps = try allocator.alloc([]const u8, deps.len);
    var deps_duped: usize = 0;
    errdefer {
        for (task_deps[0..deps_duped]) |d| allocator.free(d);
        allocator.free(task_deps);
    }
    for (deps, 0..) |dep, i| {
        task_deps[i] = try allocator.dupe(u8, dep);
        deps_duped += 1;
    }

    const task_deps_serial = try allocator.alloc([]const u8, deps_serial.len);
    var serial_duped: usize = 0;
    errdefer {
        for (task_deps_serial[0..serial_duped]) |d| allocator.free(d);
        allocator.free(task_deps_serial);
    }
    for (deps_serial, 0..) |dep, i| {
        task_deps_serial[i] = try allocator.dupe(u8, dep);
        serial_duped += 1;
    }

    // Dupe conditional dependencies
    const task_deps_if = try allocator.alloc(ConditionalDep, deps_if.len);
    var deps_if_duped: usize = 0;
    errdefer {
        for (task_deps_if[0..deps_if_duped]) |*dep| dep.deinit(allocator);
        if (task_deps_if.len > 0) allocator.free(task_deps_if);
    }
    for (deps_if, 0..) |dep, i| {
        task_deps_if[i].task = try allocator.dupe(u8, dep.task);
        errdefer allocator.free(task_deps_if[i].task);
        task_deps_if[i].condition = try allocator.dupe(u8, dep.condition);
        deps_if_duped += 1;
    }

    // Dupe optional dependencies
    const task_deps_optional = try allocator.alloc([]const u8, deps_optional.len);
    var optional_duped: usize = 0;
    errdefer {
        for (task_deps_optional[0..optional_duped]) |d| allocator.free(d);
        if (task_deps_optional.len > 0) allocator.free(task_deps_optional);
    }
    for (deps_optional, 0..) |dep, i| {
        task_deps_optional[i] = try allocator.dupe(u8, dep);
        optional_duped += 1;
    }

    // Dupe each env pair ([key, value]) independently for safe partial cleanup.
    const task_env = try allocator.alloc([2][]const u8, env.len);
    var env_duped: usize = 0;
    errdefer {
        for (task_env[0..env_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(task_env);
    }
    for (env, 0..) |pair, i| {
        task_env[i][0] = try allocator.dupe(u8, pair[0]);
        // If key dupe succeeds but value dupe fails, free the key we just duped.
        errdefer allocator.free(task_env[i][0]);
        task_env[i][1] = try allocator.dupe(u8, pair[1]);
        env_duped += 1;
    }

    const task_condition = if (condition) |c| try allocator.dupe(u8, c) else null;
    errdefer if (task_condition) |c| allocator.free(c);

    const task_skip_if = if (skip_if) |s| try allocator.dupe(u8, s) else null;
    errdefer if (task_skip_if) |s| allocator.free(s);

    const task_output_if = if (output_if) |o| try allocator.dupe(u8, o) else null;
    errdefer if (task_output_if) |o| allocator.free(o);

    // Dupe toolchain array
    const task_toolchain = try allocator.alloc([]const u8, toolchain.len);
    var tc_duped: usize = 0;
    errdefer {
        for (task_toolchain[0..tc_duped]) |tc| allocator.free(tc);
        if (task_toolchain.len > 0) allocator.free(task_toolchain);
    }
    for (toolchain, 0..) |tc, i| {
        task_toolchain[i] = try allocator.dupe(u8, tc);
        tc_duped += 1;
    }

    // Dupe tags array
    const task_tags = try allocator.alloc([]const u8, tags.len);
    var tags_duped: usize = 0;
    errdefer {
        for (task_tags[0..tags_duped]) |tag| allocator.free(tag);
        if (task_tags.len > 0) allocator.free(task_tags);
    }
    for (tags, 0..) |tag, i| {
        task_tags[i] = try allocator.dupe(u8, tag);
        tags_duped += 1;
    }

    // Dupe cpu_affinity array (v1.13.0)
    const task_cpu_affinity = if (cpu_affinity.len > 0) blk: {
        const affinity = try allocator.alloc(u32, cpu_affinity.len);
        @memcpy(affinity, cpu_affinity);
        break :blk affinity;
    } else null;
    errdefer if (task_cpu_affinity) |a| allocator.free(a);

    // Build watch config if any watch parameters are set (v1.17.0)
    const task_watch = if (watch_debounce_ms != null or watch_patterns.len > 0 or watch_exclude_patterns.len > 0 or watch_mode != null) blk: {
        const patterns_duped = try allocator.alloc([]const u8, watch_patterns.len);
        var patterns_duped_count: usize = 0;
        errdefer {
            for (patterns_duped[0..patterns_duped_count]) |p| allocator.free(p);
            if (patterns_duped.len > 0) allocator.free(patterns_duped);
        }
        for (watch_patterns, 0..) |pattern, i| {
            patterns_duped[i] = try allocator.dupe(u8, pattern);
            patterns_duped_count += 1;
        }

        const exclude_duped = try allocator.alloc([]const u8, watch_exclude_patterns.len);
        var exclude_duped_count: usize = 0;
        errdefer {
            for (exclude_duped[0..exclude_duped_count]) |p| allocator.free(p);
            if (exclude_duped.len > 0) allocator.free(exclude_duped);
        }
        for (watch_exclude_patterns, 0..) |pattern, i| {
            exclude_duped[i] = try allocator.dupe(u8, pattern);
            exclude_duped_count += 1;
        }

        const mode_duped = if (watch_mode) |m| try allocator.dupe(u8, m) else null;
        errdefer if (mode_duped) |m| allocator.free(m);

        break :blk WatchConfig{
            .debounce_ms = watch_debounce_ms orelse 300, // default 300ms
            .patterns = patterns_duped,
            .exclude_patterns = exclude_duped,
            .mode = mode_duped,
        };
    } else null;
    errdefer if (task_watch) |w| {
        var mutable_watch = w;
        mutable_watch.deinit(allocator);
    };

    // Dupe hooks (v1.24.0)
    const task_hooks = try allocator.alloc(TaskHook, hooks.len);
    var hooks_duped: usize = 0;
    errdefer {
        for (task_hooks[0..hooks_duped]) |*h| h.deinit(allocator);
        if (task_hooks.len > 0) allocator.free(task_hooks);
    }
    for (hooks, 0..) |hook, i| {
        const hook_cmd = try allocator.dupe(u8, hook.cmd);
        errdefer allocator.free(hook_cmd);

        const hook_wd = if (hook.working_dir) |wd| try allocator.dupe(u8, wd) else null;
        errdefer if (hook_wd) |wd| allocator.free(wd);

        const hook_env = try allocator.alloc([2][]const u8, hook.env.len);
        var env_duped_count: usize = 0;
        errdefer {
            for (hook_env[0..env_duped_count]) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            if (hook_env.len > 0) allocator.free(hook_env);
        }
        for (hook.env, 0..) |pair, j| {
            hook_env[j][0] = try allocator.dupe(u8, pair[0]);
            errdefer allocator.free(hook_env[j][0]);
            hook_env[j][1] = try allocator.dupe(u8, pair[1]);
            env_duped_count += 1;
        }

        task_hooks[i] = TaskHook{
            .cmd = hook_cmd,
            .point = hook.point,
            .failure_strategy = hook.failure_strategy,
            .working_dir = hook_wd,
            .env = hook_env,
        };
        hooks_duped += 1;
    }

    // Dupe template (v1.29.0)
    const task_template = if (template) |t| try allocator.dupe(u8, t) else null;
    errdefer if (task_template) |t| allocator.free(t);

    // Dupe params (v1.29.0)
    const task_params = try allocator.alloc([2][]const u8, params.len);
    var params_duped: usize = 0;
    errdefer {
        for (task_params[0..params_duped]) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        if (task_params.len > 0) allocator.free(task_params);
    }
    for (params, 0..) |pair, i| {
        task_params[i][0] = try allocator.dupe(u8, pair[0]);
        errdefer allocator.free(task_params[i][0]);
        task_params[i][1] = try allocator.dupe(u8, pair[1]);
        params_duped += 1;
    }

    // Dupe output capture fields (v1.37.0)
    const task_output_file = if (output_file) |of| try allocator.dupe(u8, of) else null;
    errdefer if (task_output_file) |of| allocator.free(of);

    const task_output_mode = if (output_mode) |om| try allocator.dupe(u8, om) else null;
    errdefer if (task_output_mode) |om| allocator.free(om);

    // Dupe remote execution fields (v1.45.0)
    const task_remote = if (remote) |r| try allocator.dupe(u8, r) else null;
    errdefer if (task_remote) |r| allocator.free(r);

    const task_remote_cwd = if (remote_cwd) |rc| try allocator.dupe(u8, rc) else null;
    errdefer if (task_remote_cwd) |rc| allocator.free(rc);

    // Dupe remote env pairs (v1.45.0)
    const task_remote_env = if (remote_env.len > 0) blk: {
        const re = try allocator.alloc([2][]const u8, remote_env.len);
        var re_duped: usize = 0;
        errdefer {
            for (re[0..re_duped]) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            allocator.free(re);
        }
        for (remote_env, 0..) |pair, i| {
            re[i][0] = try allocator.dupe(u8, pair[0]);
            errdefer allocator.free(re[i][0]);
            re[i][1] = try allocator.dupe(u8, pair[1]);
            re_duped += 1;
        }
        break :blk re;
    } else null;
    errdefer if (task_remote_env) |re| {
        for (re) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(re);
    };

    var task = Task{
        .name = task_name,
        .cmd = task_cmd,
        .cwd = task_cwd,
        .description = task_desc,
        .deps = task_deps,
        .deps_serial = task_deps_serial,
        .deps_if = task_deps_if,
        .deps_optional = task_deps_optional,
        .env = task_env,
        .timeout_ms = timeout_ms,
        .allow_failure = allow_failure,
        .retry_max = retry_max,
        .retry_delay_ms = retry_delay_ms,
        .retry_backoff = retry_backoff,
        .condition = task_condition,
        .skip_if = task_skip_if,
        .output_if = task_output_if,
        .max_concurrent = max_concurrent,
        .cache = cache,
        .max_cpu = max_cpu,
        .max_memory = max_memory,
        .toolchain = task_toolchain,
        .tags = task_tags,
        .cpu_affinity = task_cpu_affinity,
        .numa_node = numa_node,
        .watch = task_watch,
        .hooks = task_hooks,
        .template = task_template,
        .params = task_params,
        .output_file = task_output_file,
        .output_mode = task_output_mode,
        .remote = task_remote,
        .remote_cwd = task_remote_cwd,
        .remote_env = task_remote_env,
    };

    // Apply template if specified
    if (task_template) |tmpl_name| {
        try applyTemplateToTask(config, allocator, &task, tmpl_name, task_params);
    }

    // Check for duplicate task definition and reject it
    // The errdefer cleanup above will handle freeing all allocated memory
    if (config.tasks.contains(task_name)) {
        return error.DuplicateTask;
    }

    try config.tasks.put(task_name, task);
}

test "TaskTemplate: init and deinit" {
    const allocator = std.testing.allocator;

    const name = try allocator.dupe(u8, "test-template");
    const cmd = try allocator.dupe(u8, "echo ${message}");
    const params_list = try allocator.alloc([]const u8, 1);
    params_list[0] = try allocator.dupe(u8, "message");

    var template = TaskTemplate{
        .name = name,
        .cmd = cmd,
        .params = params_list,
    };

    template.deinit(allocator);
}

test "substituteParams: simple substitution" {
    const allocator = std.testing.allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    try params.put("name", "world");

    const result = try Config.substituteParams(allocator, "Hello ${name}!", params);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello world!", result);
}

test "substituteParams: multiple substitutions" {
    const allocator = std.testing.allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    try params.put("cmd", "build");
    try params.put("env", "production");

    const result = try Config.substituteParams(allocator, "npm run ${cmd} --env=${env}", params);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("npm run build --env=production", result);
}

test "substituteParams: no substitution" {
    const allocator = std.testing.allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    const result = try Config.substituteParams(allocator, "plain text", params);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("plain text", result);
}

test "substituteParams: unclosed placeholder" {
    const allocator = std.testing.allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    const result = Config.substituteParams(allocator, "invalid ${param", params);
    try std.testing.expectError(error.UnclosedPlaceholder, result);
}

test "substituteParams: unknown parameter" {
    const allocator = std.testing.allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    const result = Config.substituteParams(allocator, "Hello ${unknown}!", params);
    try std.testing.expectError(error.UnknownParameter, result);
}

test "expandTemplate: basic expansion" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    // Create a template
    const template_name = try allocator.dupe(u8, "node-script");
    const template_cmd = try allocator.dupe(u8, "node ${script}");
    const template_params = try allocator.alloc([]const u8, 1);
    template_params[0] = try allocator.dupe(u8, "script");

    const template = TaskTemplate{
        .name = template_name,
        .cmd = template_cmd,
        .params = template_params,
    };

    try config.templates.put(template_name, template);

    // Expand the template
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();
    try params.put("script", "build.js");

    try config.expandTemplate("my-build", "node-script", params);

    // Verify the task was created
    const task = config.tasks.get("my-build") orelse return error.TaskNotCreated;
    try std.testing.expectEqualStrings("node build.js", task.cmd);
}

test "expandTemplate: missing template" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    const result = config.expandTemplate("task", "nonexistent", params);
    try std.testing.expectError(error.TemplateNotFound, result);
}

test "expandTemplate: missing parameter" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    // Create a template with required parameter
    const template_name = try allocator.dupe(u8, "test-template");
    const template_cmd = try allocator.dupe(u8, "echo ${message}");
    const template_params = try allocator.alloc([]const u8, 1);
    template_params[0] = try allocator.dupe(u8, "message");

    const template = TaskTemplate{
        .name = template_name,
        .cmd = template_cmd,
        .params = template_params,
    };

    try config.templates.put(template_name, template);

    // Try to expand without providing the required parameter
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    const result = config.expandTemplate("task", "test-template", params);
    try std.testing.expectError(error.MissingTemplateParameter, result);
}

test "expandTemplate: with all template fields" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    // Create a comprehensive template
    const template_name = try allocator.dupe(u8, "comprehensive");
    const template_cmd = try allocator.dupe(u8, "${tool} ${action}");
    const template_desc = try allocator.dupe(u8, "Run ${action} with ${tool}");
    const template_cwd = try allocator.dupe(u8, "./${dir}");
    const template_params = try allocator.alloc([]const u8, 3);
    template_params[0] = try allocator.dupe(u8, "tool");
    template_params[1] = try allocator.dupe(u8, "action");
    template_params[2] = try allocator.dupe(u8, "dir");

    const template = TaskTemplate{
        .name = template_name,
        .cmd = template_cmd,
        .description = template_desc,
        .cwd = template_cwd,
        .params = template_params,
        .timeout_ms = 5000,
        .allow_failure = true,
        .cache = true,
    };

    try config.templates.put(template_name, template);

    // Expand the template
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();
    try params.put("tool", "cargo");
    try params.put("action", "test");
    try params.put("dir", "packages/core");

    try config.expandTemplate("rust-test", "comprehensive", params);

    // Verify all fields were expanded correctly
    const task = config.tasks.get("rust-test") orelse return error.TaskNotCreated;
    try std.testing.expectEqualStrings("cargo test", task.cmd);
    try std.testing.expectEqualStrings("Run test with cargo", task.description.?);
    try std.testing.expectEqualStrings("./packages/core", task.cwd.?);
    try std.testing.expectEqual(@as(?u64, 5000), task.timeout_ms);
    try std.testing.expectEqual(true, task.allow_failure);
    try std.testing.expectEqual(true, task.cache);
}

test "applyTemplateToTask: automatic template application" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    // Create a template
    const template_name = try allocator.dupe(u8, "web-server");
    const template_cmd = try allocator.dupe(u8, "node server.js --port=${port} --host=${host}");
    const template_desc = try allocator.dupe(u8, "Start web server on ${host}:${port}");
    const template_params = try allocator.alloc([]const u8, 2);
    template_params[0] = try allocator.dupe(u8, "port");
    template_params[1] = try allocator.dupe(u8, "host");

    const template = TaskTemplate{
        .name = template_name,
        .cmd = template_cmd,
        .description = template_desc,
        .params = template_params,
        .timeout_ms = 60000,
        .allow_failure = false,
    };

    try config.templates.put(template_name, template);

    // Create a task with template reference using addTaskImpl
    const params_array = [_][2][]const u8{
        .{ "port", "3000" },
        .{ "host", "localhost" },
    };

    try addTaskImpl(
        &config,
        allocator,
        "dev-server",
        "", // empty cmd - will be filled by template
        null,
        null,
        &[_][]const u8{},
        &[_][]const u8{},
        &[_]ConditionalDep{},
        &[_][]const u8{},
        &[_][2][]const u8{},
        null,
        false,
        0,
        1000,
        false,
        null,
        null,
        null,
        0,
        false,
        null,
        null,
        &[_][]const u8{},
        &[_][]const u8{},
        &[_]u32{},
        null,
        null,
        &[_][]const u8{},
        &[_][]const u8{},
        null,
        &[_]TaskHook{},
        "web-server", // template name
        &params_array,
        null, // output_file
        null, // output_mode
        null, // remote
        null, // remote_cwd
        &[_][2][]const u8{}, // remote_env
    );

    // Verify the task was created with template-expanded fields
    const task = config.tasks.get("dev-server") orelse return error.TaskNotCreated;
    try std.testing.expectEqualStrings("node server.js --port=3000 --host=localhost", task.cmd);
    try std.testing.expectEqualStrings("Start web server on localhost:3000", task.description.?);
    try std.testing.expectEqual(@as(?u64, 60000), task.timeout_ms);
    try std.testing.expectEqual(false, task.allow_failure);
}

test "applyTemplateToTask: task overrides template defaults" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    // Create a template with defaults
    const template_name = try allocator.dupe(u8, "test-runner");
    const template_cmd = try allocator.dupe(u8, "npm test -- ${pattern}");
    const template_params = try allocator.alloc([]const u8, 1);
    template_params[0] = try allocator.dupe(u8, "pattern");

    const template_deps = try allocator.alloc([]const u8, 1);
    template_deps[0] = try allocator.dupe(u8, "build");

    const template = TaskTemplate{
        .name = template_name,
        .cmd = template_cmd,
        .params = template_params,
        .deps = template_deps,
        .timeout_ms = 30000,
        .allow_failure = false,
    };

    try config.templates.put(template_name, template);

    // Create a task with explicit cmd (should override template)
    const params_array = [_][2][]const u8{
        .{ "pattern", "**/*.test.js" },
    };

    try addTaskImpl(
        &config,
        allocator,
        "test-unit",
        "jest --coverage", // explicit cmd overrides template
        null,
        null,
        &[_][]const u8{},
        &[_][]const u8{},
        &[_]ConditionalDep{},
        &[_][]const u8{},
        &[_][2][]const u8{},
        120000, // explicit timeout overrides template
        false,
        0,
        1000,
        false,
        null,
        null,
        null,
        0,
        false,
        null,
        null,
        &[_][]const u8{},
        &[_][]const u8{},
        &[_]u32{},
        null,
        null,
        &[_][]const u8{},
        &[_][]const u8{},
        null,
        &[_]TaskHook{},
        "test-runner",
        &params_array,
        null, // output_file
        null, // output_mode
        null, // remote
        null, // remote_cwd
        &[_][2][]const u8{}, // remote_env
    );

    // Verify task uses explicit values, not template defaults
    const task = config.tasks.get("test-unit") orelse return error.TaskNotCreated;
    try std.testing.expectEqualStrings("jest --coverage", task.cmd); // explicit cmd wins
    try std.testing.expectEqual(@as(?u64, 120000), task.timeout_ms); // explicit timeout wins
    try std.testing.expectEqual(@as(usize, 1), task.deps.len); // template deps merged
    try std.testing.expectEqualStrings("build", task.deps[0]);
}
