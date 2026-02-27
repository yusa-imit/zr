const std = @import("std");
const position = @import("position.zig");

/// LSP DiagnosticSeverity
pub const DiagnosticSeverity = enum(u8) {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,
};

/// LSP Diagnostic message
pub const Diagnostic = struct {
    range: position.Range,
    severity: DiagnosticSeverity,
    message: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, range: position.Range, severity: DiagnosticSeverity, message: []const u8) !Diagnostic {
        return Diagnostic{
            .range = range,
            .severity = severity,
            .message = try allocator.dupe(u8, message),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Diagnostic) void {
        self.allocator.free(self.message);
    }

    /// Format as LSP JSON diagnostic
    pub fn toJson(self: Diagnostic, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator,
            \\{{"range":{{"start":{{"line":{d},"character":{d}}},"end":{{"line":{d},"character":{d}}}}},"severity":{d},"message":"{s}"}}
        , .{
            self.range.start.line,
            self.range.start.character,
            self.range.end.line,
            self.range.end.character,
            @intFromEnum(self.severity),
            self.message,
        });
    }
};

/// Create diagnostic from TOML parse error
pub fn fromTomlError(allocator: std.mem.Allocator, text: []const u8, err: anyerror, byte_offset: ?usize) !Diagnostic {
    const offset = byte_offset orelse 0;
    const pos = position.byteOffsetToPosition(text, offset);

    // Create range spanning the error position
    const range = position.Range{
        .start = pos,
        .end = position.Position{
            .line = pos.line,
            .character = pos.character + 1, // Highlight one character
        },
    };

    const message = switch (err) {
        error.UnexpectedCharacter => "Unexpected character",
        error.InvalidSection => "Invalid section name",
        error.InvalidKey => "Invalid key name",
        error.InvalidValue => "Invalid value",
        error.MissingValue => "Missing value",
        error.UnterminatedString => "Unterminated string",
        error.InvalidEscape => "Invalid escape sequence",
        error.DuplicateKey => "Duplicate key",
        error.UnknownTask => "Unknown task reference",
        error.CircularDependency => "Circular dependency detected",
        else => "Parse error",
    };

    return Diagnostic.init(allocator, range, .Error, message);
}

/// Create diagnostic for missing required field
pub fn missingRequiredField(allocator: std.mem.Allocator, text: []const u8, section_name: []const u8, field_name: []const u8) !Diagnostic {
    // Find the section header in the text
    const section_marker = try std.fmt.allocPrint(allocator, "[{s}]", .{section_name});
    defer allocator.free(section_marker);

    var byte_offset: usize = 0;
    if (std.mem.indexOf(u8, text, section_marker)) |idx| {
        byte_offset = idx;
    }

    const pos = position.byteOffsetToPosition(text, byte_offset);
    const range = position.Range{
        .start = pos,
        .end = position.Position{
            .line = pos.line,
            .character = pos.character + @as(u32, @intCast(section_marker.len)),
        },
    };

    const message = try std.fmt.allocPrint(allocator, "Missing required field: {s}", .{field_name});
    defer allocator.free(message);

    return Diagnostic.init(allocator, range, .Error, message);
}

/// Create diagnostic for unknown field
pub fn unknownField(allocator: std.mem.Allocator, text: []const u8, field_name: []const u8, byte_offset: usize) !Diagnostic {
    const pos = position.byteOffsetToPosition(text, byte_offset);
    const range = position.Range{
        .start = pos,
        .end = position.Position{
            .line = pos.line,
            .character = pos.character + @as(u32, @intCast(field_name.len)),
        },
    };

    const message = try std.fmt.allocPrint(allocator, "Unknown field: {s}", .{field_name});
    defer allocator.free(message);

    return Diagnostic.init(allocator, range, .Warning, message);
}

test "Diagnostic - init and deinit" {
    const allocator = std.testing.allocator;
    const range = position.Range{
        .start = position.Position{ .line = 0, .character = 0 },
        .end = position.Position{ .line = 0, .character = 5 },
    };

    var diag = try Diagnostic.init(allocator, range, .Error, "test error");
    defer diag.deinit();

    try std.testing.expectEqual(DiagnosticSeverity.Error, diag.severity);
    try std.testing.expectEqualStrings("test error", diag.message);
}

test "Diagnostic - toJson" {
    const allocator = std.testing.allocator;
    const range = position.Range{
        .start = position.Position{ .line = 0, .character = 5 },
        .end = position.Position{ .line = 0, .character = 10 },
    };

    var diag = try Diagnostic.init(allocator, range, .Error, "test");
    defer diag.deinit();

    const json = try diag.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"line\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"character\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"severity\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"message\":\"test\"") != null);
}

test "fromTomlError" {
    const allocator = std.testing.allocator;
    const text = "invalid toml\n[section]";

    var diag = try fromTomlError(allocator, text, error.InvalidSection, 13);
    defer diag.deinit();

    try std.testing.expectEqual(DiagnosticSeverity.Error, diag.severity);
    try std.testing.expectEqual(@as(u32, 1), diag.range.start.line);
}
