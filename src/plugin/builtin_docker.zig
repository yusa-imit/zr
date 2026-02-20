/// Docker builtin plugin — Docker build/push operations with layer cache optimization
///
/// Provides:
/// - Docker image build with configurable build args
/// - Docker push to registries (configurable default registry)
/// - Layer cache management (buildkit cache)
/// - Multi-platform builds
/// - Build context optimization
const std = @import("std");
const platform = @import("../util/platform.zig");

/// Docker plugin configuration.
pub const DockerPlugin = struct {
    /// Default Docker registry (e.g., "ghcr.io", "docker.io")
    default_registry: []const u8 = "docker.io",

    /// Enable BuildKit cache (inline cache)
    enable_cache: bool = true,

    /// Default platforms for multi-platform builds
    default_platforms: ?[]const []const u8 = null,

    /// Verify Docker daemon is available on initialization.
    /// Returns true if Docker is running and accessible.
    pub fn onInit(allocator: std.mem.Allocator, config: ?DockerPlugin) !bool {
        _ = config; // Config validation happens during parsing

        // Check if Docker daemon is available by running `docker version`
        const argv = [_][]const u8{ "docker", "version", "--format", "{{.Server.Version}}" };
        var child = std.process.Child.init(&argv, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch {
            // Docker CLI not available or daemon not running
            return false;
        };

        // Read and discard output (we just care if the command succeeds)
        var stdout_buf: [256]u8 = undefined;
        _ = (child.stdout orelse return false).readAll(&stdout_buf) catch return false;

        const term = child.wait() catch return false;
        return switch (term) {
            .Exited => |code| code == 0,
            else => false,
        };
    }

    /// Build a Docker image.
    ///
    /// Options (via task config JSON):
    /// - `dockerfile`: Path to Dockerfile (default: "Dockerfile")
    /// - `context`: Build context path (default: ".")
    /// - `tag`: Image tag (required)
    /// - `build_args`: Map of build arguments
    /// - `target`: Build target stage
    /// - `platforms`: List of platforms (e.g., ["linux/amd64", "linux/arm64"])
    /// - `cache_from`: Cache source image
    /// - `cache_to`: Cache destination
    /// - `no_cache`: Disable cache (default: false)
    ///
    /// Returns command line for `docker build`.
    pub fn buildCommand(
        allocator: std.mem.Allocator,
        cfg: DockerPlugin,
        options: BuildOptions,
    ) ![]const u8 {
        var cmd: std.ArrayListUnmanaged(u8) = .empty;
        errdefer cmd.deinit(allocator);

        try cmd.appendSlice(allocator, "docker build");

        // Dockerfile
        if (options.dockerfile) |df| {
            try cmd.appendSlice(allocator, " -f ");
            try cmd.appendSlice(allocator, df);
        }

        // Tag
        try cmd.appendSlice(allocator, " -t ");
        try cmd.appendSlice(allocator, options.tag);

        // Build args
        if (options.build_args) |args| {
            var it = args.iterator();
            while (it.next()) |entry| {
                try cmd.appendSlice(allocator, " --build-arg ");
                try cmd.appendSlice(allocator, entry.key_ptr.*);
                try cmd.appendSlice(allocator, "=");
                try cmd.appendSlice(allocator, entry.value_ptr.*);
            }
        }

        // Target stage
        if (options.target) |t| {
            try cmd.appendSlice(allocator, " --target ");
            try cmd.appendSlice(allocator, t);
        }

        // Platforms
        if (options.platforms) |platforms| {
            try cmd.appendSlice(allocator, " --platform ");
            for (platforms, 0..) |p, i| {
                if (i > 0) try cmd.append(allocator, ',');
                try cmd.appendSlice(allocator, p);
            }
        } else if (cfg.default_platforms) |platforms| {
            try cmd.appendSlice(allocator, " --platform ");
            for (platforms, 0..) |p, i| {
                if (i > 0) try cmd.append(allocator, ',');
                try cmd.appendSlice(allocator, p);
            }
        }

        // Cache
        if (options.no_cache orelse false) {
            try cmd.appendSlice(allocator, " --no-cache");
        } else if (cfg.enable_cache) {
            if (options.cache_from) |cf| {
                try cmd.appendSlice(allocator, " --cache-from ");
                try cmd.appendSlice(allocator, cf);
            }
            if (options.cache_to) |ct| {
                try cmd.appendSlice(allocator, " --cache-to ");
                try cmd.appendSlice(allocator, ct);
            } else {
                // Default inline cache
                try cmd.appendSlice(allocator, " --cache-to type=inline");
            }
        }

        // Context (last argument)
        try cmd.append(allocator, ' ');
        try cmd.appendSlice(allocator, options.context orelse ".");

        return cmd.toOwnedSlice(allocator);
    }

    /// Push a Docker image to a registry.
    ///
    /// Options:
    /// - `tag`: Image tag to push (required)
    /// - `registry`: Override default registry
    ///
    /// Returns command line for `docker push`.
    pub fn pushCommand(
        allocator: std.mem.Allocator,
        cfg: DockerPlugin,
        options: PushOptions,
    ) ![]const u8 {
        var cmd: std.ArrayListUnmanaged(u8) = .empty;
        errdefer cmd.deinit(allocator);

        try cmd.appendSlice(allocator, "docker push ");

        // If tag doesn't contain a registry, prepend default
        const tag = options.tag;
        const registry = options.registry orelse cfg.default_registry;

        if (std.mem.indexOf(u8, tag, "/") == null) {
            // No registry in tag, use default
            try cmd.appendSlice(allocator, registry);
            try cmd.append(allocator, '/');
            try cmd.appendSlice(allocator, tag);
        } else if (std.mem.startsWith(u8, tag, "localhost/") or
            std.mem.indexOf(u8, tag, ".") == null)
        {
            // Local or single-word registry, use as-is
            try cmd.appendSlice(allocator, tag);
        } else {
            // Tag already includes registry
            try cmd.appendSlice(allocator, tag);
        }

        return cmd.toOwnedSlice(allocator);
    }

    /// Tag a Docker image.
    ///
    /// Options:
    /// - `source`: Source image tag (required)
    /// - `target`: Target image tag (required)
    ///
    /// Returns command line for `docker tag`.
    pub fn tagCommand(
        allocator: std.mem.Allocator,
        options: TagOptions,
    ) ![]const u8 {
        return std.fmt.allocPrint(
            allocator,
            "docker tag {s} {s}",
            .{ options.source, options.target },
        );
    }

    /// Clean up Docker build cache.
    ///
    /// Options:
    /// - `all`: Remove all cache (default: false)
    /// - `filter`: Filter pattern (e.g., "until=24h")
    ///
    /// Returns command line for `docker builder prune`.
    pub fn pruneCommand(
        allocator: std.mem.Allocator,
        options: PruneOptions,
    ) ![]const u8 {
        var cmd: std.ArrayListUnmanaged(u8) = .empty;
        errdefer cmd.deinit(allocator);

        try cmd.appendSlice(allocator, "docker builder prune -f");

        if (options.all orelse false) {
            try cmd.appendSlice(allocator, " --all");
        }

        if (options.filter) |f| {
            try cmd.appendSlice(allocator, " --filter ");
            try cmd.appendSlice(allocator, f);
        }

        return cmd.toOwnedSlice(allocator);
    }
};

// ---------------------------------------------------------------------------
// Option types
// ---------------------------------------------------------------------------

pub const BuildOptions = struct {
    tag: []const u8, // Required
    dockerfile: ?[]const u8 = null,
    context: ?[]const u8 = null,
    build_args: ?std.StringHashMap([]const u8) = null,
    target: ?[]const u8 = null,
    platforms: ?[]const []const u8 = null,
    cache_from: ?[]const u8 = null,
    cache_to: ?[]const u8 = null,
    no_cache: ?bool = null,
};

pub const PushOptions = struct {
    tag: []const u8, // Required
    registry: ?[]const u8 = null,
};

pub const TagOptions = struct {
    source: []const u8, // Required
    target: []const u8, // Required
};

pub const PruneOptions = struct {
    all: ?bool = null,
    filter: ?[]const u8 = null,
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "DockerPlugin: onInit with Docker available" {
    const allocator = std.testing.allocator;

    // This test will pass if Docker daemon is running, skip otherwise
    const available = DockerPlugin.onInit(allocator, null) catch false;
    if (!available) {
        return error.SkipZigTest; // Skip if Docker not available
    }

    try std.testing.expect(available);
}

test "DockerPlugin: buildCommand with minimal options" {
    const allocator = std.testing.allocator;
    const cfg = DockerPlugin{};

    const options = BuildOptions{ .tag = "myapp:latest" };
    const cmd = try DockerPlugin.buildCommand(allocator, cfg, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings(
        "docker build -t myapp:latest --cache-to type=inline .",
        cmd,
    );
}

test "DockerPlugin: buildCommand with full options" {
    const allocator = std.testing.allocator;
    const cfg = DockerPlugin{ .enable_cache = true };

    var build_args = std.StringHashMap([]const u8).init(allocator);
    defer build_args.deinit();
    try build_args.put("VERSION", "1.0.0");
    try build_args.put("ENV", "production");

    const platforms = [_][]const u8{ "linux/amd64", "linux/arm64" };

    const options = BuildOptions{
        .tag = "myapp:v1.0.0",
        .dockerfile = "Dockerfile.prod",
        .context = "./app",
        .build_args = build_args,
        .target = "production",
        .platforms = &platforms,
        .cache_from = "myapp:cache",
    };

    const cmd = try DockerPlugin.buildCommand(allocator, cfg, options);
    defer allocator.free(cmd);

    // Verify all parts are present (order of build args may vary)
    try std.testing.expect(std.mem.indexOf(u8, cmd, "docker build") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "-f Dockerfile.prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "-t myapp:v1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "--build-arg VERSION=1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "--build-arg ENV=production") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "--target production") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "--platform linux/amd64,linux/arm64") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "--cache-from myapp:cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "./app") != null);
}

test "DockerPlugin: buildCommand with no_cache" {
    const allocator = std.testing.allocator;
    const cfg = DockerPlugin{};

    const options = BuildOptions{
        .tag = "myapp:nocache",
        .no_cache = true,
    };

    const cmd = try DockerPlugin.buildCommand(allocator, cfg, options);
    defer allocator.free(cmd);

    try std.testing.expect(std.mem.indexOf(u8, cmd, "--no-cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "--cache-to") == null);
}

test "DockerPlugin: pushCommand with default registry" {
    const allocator = std.testing.allocator;
    const cfg = DockerPlugin{ .default_registry = "ghcr.io" };

    const options = PushOptions{ .tag = "myapp:latest" };
    const cmd = try DockerPlugin.pushCommand(allocator, cfg, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker push ghcr.io/myapp:latest", cmd);
}

test "DockerPlugin: pushCommand with full tag" {
    const allocator = std.testing.allocator;
    const cfg = DockerPlugin{};

    const options = PushOptions{ .tag = "ghcr.io/user/myapp:v1.0.0" };
    const cmd = try DockerPlugin.pushCommand(allocator, cfg, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker push ghcr.io/user/myapp:v1.0.0", cmd);
}

test "DockerPlugin: pushCommand with registry override" {
    const allocator = std.testing.allocator;
    const cfg = DockerPlugin{ .default_registry = "docker.io" };

    const options = PushOptions{
        .tag = "myapp:latest",
        .registry = "gcr.io",
    };
    const cmd = try DockerPlugin.pushCommand(allocator, cfg, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker push gcr.io/myapp:latest", cmd);
}

test "DockerPlugin: tagCommand" {
    const allocator = std.testing.allocator;

    const options = TagOptions{
        .source = "myapp:latest",
        .target = "myapp:v1.0.0",
    };
    const cmd = try DockerPlugin.tagCommand(allocator, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker tag myapp:latest myapp:v1.0.0", cmd);
}

test "DockerPlugin: pruneCommand minimal" {
    const allocator = std.testing.allocator;

    const options = PruneOptions{};
    const cmd = try DockerPlugin.pruneCommand(allocator, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker builder prune -f", cmd);
}

test "DockerPlugin: pruneCommand with all" {
    const allocator = std.testing.allocator;

    const options = PruneOptions{ .all = true };
    const cmd = try DockerPlugin.pruneCommand(allocator, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker builder prune -f --all", cmd);
}

test "DockerPlugin: pruneCommand with filter" {
    const allocator = std.testing.allocator;

    const options = PruneOptions{ .filter = "until=24h" };
    const cmd = try DockerPlugin.pruneCommand(allocator, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker builder prune -f --filter until=24h", cmd);
}

test "DockerPlugin: pruneCommand with all and filter" {
    const allocator = std.testing.allocator;

    const options = PruneOptions{
        .all = true,
        .filter = "until=72h",
    };
    const cmd = try DockerPlugin.pruneCommand(allocator, options);
    defer allocator.free(cmd);

    try std.testing.expectEqualStrings("docker builder prune -f --all --filter until=72h", cmd);
}
