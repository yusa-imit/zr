const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Represents a user-defined command alias
pub const Alias = struct {
    name: []const u8,
    command: []const u8,

    pub fn deinit(self: *Alias, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.command);
    }
};

/// Alias configuration stored in ~/.zr/aliases.toml
pub const AliasConfig = struct {
    aliases: std.StringHashMap([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) AliasConfig {
        return .{
            .aliases = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AliasConfig) void {
        var it = self.aliases.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.aliases.deinit();
    }

    /// Load aliases from ~/.zr/aliases.toml
    pub fn load(allocator: Allocator) !AliasConfig {
        var config = AliasConfig.init(allocator);
        errdefer config.deinit();

        const path = try getAliasFilePath(allocator);
        defer allocator.free(path);

        const file = fs.openFileAbsolute(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No aliases file yet, return empty config
                return config;
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        try parseAliasToml(&config, content);
        return config;
    }

    /// Save aliases to ~/.zr/aliases.toml
    pub fn save(self: *AliasConfig) !void {
        const path = try getAliasFilePath(self.allocator);
        defer self.allocator.free(path);

        // Ensure ~/.zr/ directory exists
        const home = try getHomeDir(self.allocator);
        defer self.allocator.free(home);
        const zr_dir = try fs.path.join(self.allocator, &[_][]const u8{ home, ".zr" });
        defer self.allocator.free(zr_dir);
        fs.makeDirAbsolute(zr_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const file = try fs.createFileAbsolute(path, .{});
        defer file.close();

        try file.writeAll("# zr aliases - auto-generated\n");
        try file.writeAll("# Format: name = \"command\"\n\n");

        var it = self.aliases.iterator();
        while (it.next()) |entry| {
            const line = try std.fmt.allocPrint(self.allocator, "{s} = \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            defer self.allocator.free(line);
            try file.writeAll(line);
        }
    }

    /// Add or update an alias
    pub fn set(self: *AliasConfig, name: []const u8, command: []const u8) !void {
        // Remove existing alias if present
        if (self.aliases.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }

        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);
        const cmd_owned = try self.allocator.dupe(u8, command);
        errdefer self.allocator.free(cmd_owned);

        try self.aliases.put(name_owned, cmd_owned);
    }

    /// Remove an alias
    pub fn remove(self: *AliasConfig, name: []const u8) bool {
        if (self.aliases.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }

    /// Get an alias command by name
    pub fn get(self: *AliasConfig, name: []const u8) ?[]const u8 {
        return self.aliases.get(name);
    }

    /// Expand an alias into a list of arguments
    /// Returns null if the alias is not found
    /// Caller owns the returned ArrayList
    pub fn expand(self: *AliasConfig, allocator: Allocator, name: []const u8) !?std.ArrayList([]const u8) {
        const alias_command = self.aliases.get(name) orelse return null;

        var args = std.ArrayList([]const u8){};
        errdefer {
            for (args.items) |arg| allocator.free(arg);
            args.deinit(allocator);
        }

        // Simple tokenization by spaces
        var tokens = mem.tokenizeScalar(u8, alias_command, ' ');
        while (tokens.next()) |token| {
            try args.append(allocator, try allocator.dupe(u8, token));
        }

        return args;
    }
};

/// Get the path to the aliases file (~/.zr/aliases.toml)
fn getAliasFilePath(allocator: Allocator) ![]const u8 {
    const home = try getHomeDir(allocator);
    defer allocator.free(home);
    return fs.path.join(allocator, &[_][]const u8{ home, ".zr", "aliases.toml" });
}

/// Get the user's home directory
fn getHomeDir(allocator: Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        return home;
    } else |_| {}

    // Windows fallback
    if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |profile| {
        return profile;
    } else |_| {}

    return error.HomeNotFound;
}

/// Parse the aliases.toml file (simple format: name = "command")
fn parseAliasToml(config: *AliasConfig, content: []const u8) !void {
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Find the '=' separator
        const eq_idx = mem.indexOf(u8, trimmed, "=") orelse continue;
        const name = mem.trim(u8, trimmed[0..eq_idx], " \t");
        const value_part = mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

        // Remove quotes from value
        const value = if (value_part.len >= 2 and value_part[0] == '"' and value_part[value_part.len - 1] == '"')
            value_part[1 .. value_part.len - 1]
        else
            value_part;

        if (name.len > 0 and value.len > 0) {
            try config.set(name, value);
        }
    }
}

// Tests
test "AliasConfig init/deinit" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();
    try std.testing.expect(config.aliases.count() == 0);
}

test "AliasConfig set/get" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    try config.set("dev", "run build && run test");
    const cmd = config.get("dev");
    try std.testing.expect(cmd != null);
    try std.testing.expectEqualStrings("run build && run test", cmd.?);
}

test "AliasConfig set overwrites existing" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    try config.set("dev", "run build");
    try config.set("dev", "run test");
    const cmd = config.get("dev");
    try std.testing.expect(cmd != null);
    try std.testing.expectEqualStrings("run test", cmd.?);
    try std.testing.expect(config.aliases.count() == 1);
}

test "AliasConfig remove" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    try config.set("dev", "run build");
    try std.testing.expect(config.remove("dev") == true);
    try std.testing.expect(config.get("dev") == null);
    try std.testing.expect(config.remove("nonexistent") == false);
}

test "parseAliasToml" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    const content =
        \\# Comment
        \\dev = "run build && run test"
        \\prod = "run build --profile=production"
        \\
        \\# Another comment
        \\check = "run lint && run fmt"
    ;

    try parseAliasToml(&config, content);
    try std.testing.expect(config.aliases.count() == 3);
    try std.testing.expectEqualStrings("run build && run test", config.get("dev").?);
    try std.testing.expectEqualStrings("run build --profile=production", config.get("prod").?);
    try std.testing.expectEqualStrings("run lint && run fmt", config.get("check").?);
}

test "AliasConfig expand - simple command" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    try config.set("dev", "run build");
    var args = (try config.expand(allocator, "dev")).?;
    defer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit(allocator);
    }

    try std.testing.expect(args.items.len == 2);
    try std.testing.expectEqualStrings("run", args.items[0]);
    try std.testing.expectEqualStrings("build", args.items[1]);
}

test "AliasConfig expand - command with flags" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    try config.set("prod", "run build --profile=production");
    var args = (try config.expand(allocator, "prod")).?;
    defer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit(allocator);
    }

    try std.testing.expect(args.items.len == 3);
    try std.testing.expectEqualStrings("run", args.items[0]);
    try std.testing.expectEqualStrings("build", args.items[1]);
    try std.testing.expectEqualStrings("--profile=production", args.items[2]);
}

test "AliasConfig expand - complex command" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    try config.set("check", "list --tree");
    var args = (try config.expand(allocator, "check")).?;
    defer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit(allocator);
    }

    try std.testing.expect(args.items.len == 2);
    try std.testing.expectEqualStrings("list", args.items[0]);
    try std.testing.expectEqualStrings("--tree", args.items[1]);
}

test "AliasConfig expand - nonexistent alias" {
    const allocator = std.testing.allocator;
    var config = AliasConfig.init(allocator);
    defer config.deinit();

    const result = try config.expand(allocator, "nonexistent");
    try std.testing.expect(result == null);
}
