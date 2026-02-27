const std = @import("std");
const types = @import("../toolchain/types.zig");
const ToolKind = types.ToolKind;
const provider = @import("provider.zig");
const LanguageProvider = provider.LanguageProvider;

// Import all language providers
const node = @import("node.zig");
const python = @import("python.zig");
const zig_lang = @import("zig.zig");
const go = @import("go.zig");
const rust = @import("rust.zig");
const deno = @import("deno.zig");
const bun = @import("bun.zig");
const java = @import("java.zig");

/// Get the language provider for a given tool kind
pub fn getProvider(kind: ToolKind) *const LanguageProvider {
    return switch (kind) {
        .node => &node.NodeProvider,
        .python => &python.PythonProvider,
        .zig => &zig_lang.ZigProvider,
        .go => &go.GoProvider,
        .rust => &rust.RustProvider,
        .deno => &deno.DenoProvider,
        .bun => &bun.BunProvider,
        .java => &java.JavaProvider,
    };
}

/// Get all registered providers
pub fn getAllProviders() []const *const LanguageProvider {
    const providers = [_]*const LanguageProvider{
        &node.NodeProvider,
        &python.PythonProvider,
        &zig_lang.ZigProvider,
        &go.GoProvider,
        &rust.RustProvider,
        &deno.DenoProvider,
        &bun.BunProvider,
        &java.JavaProvider,
    };
    return &providers;
}

/// Detect which languages are used in a project directory
/// Returns a list of detected languages sorted by confidence
pub fn detectProjectLanguages(allocator: std.mem.Allocator, dir_path: []const u8) ![]DetectedLanguage {
    var detected = std.ArrayList(DetectedLanguage){};
    errdefer detected.deinit(allocator);

    const all_providers = getAllProviders();
    for (all_providers) |lang_provider| {
        const info = try lang_provider.detectProject(allocator, dir_path);
        if (info.detected) {
            try detected.append(allocator, .{
                .provider = lang_provider,
                .confidence = info.confidence,
                .files_found = info.files_found,
            });
        } else {
            // Free files_found if not detected
            allocator.free(info.files_found);
        }
    }

    // Sort by confidence (descending)
    const items = try detected.toOwnedSlice(allocator);
    std.mem.sort(DetectedLanguage, items, {}, compareByConfidence);

    return items;
}

pub const DetectedLanguage = struct {
    provider: *const LanguageProvider,
    confidence: u8,
    files_found: []const []const u8,

    pub fn deinit(self: *DetectedLanguage, allocator: std.mem.Allocator) void {
        allocator.free(self.files_found);
    }
};

fn compareByConfidence(_: void, a: DetectedLanguage, b: DetectedLanguage) bool {
    return a.confidence > b.confidence;
}

test "getProvider" {
    const node_provider = getProvider(.node);
    try std.testing.expectEqualStrings("node", node_provider.name);

    const python_provider = getProvider(.python);
    try std.testing.expectEqualStrings("python", python_provider.name);
}

test "getAllProviders" {
    const providers = getAllProviders();
    try std.testing.expectEqual(@as(usize, 8), providers.len);
}
