const std = @import("std");

const Allocator = std.mem.Allocator;

/// Token types for TOML syntax highlighting
pub const TokenType = enum {
    // Structural
    @"table_header", // [table_name] or [[array_of_tables]]
    @"inline_table_open", // {
    @"inline_table_close", // }
    @"array_open", // [
    @"array_close", // ]
    @"equals", // =
    @"comma", // ,
    @"dot", // .

    // Literals
    @"key",
    @"string", // "..." or '...' or """..."""
    @"integer",
    @"float",
    @"boolean", // true / false
    @"datetime", // ISO 8601 timestamp
    @"null",

    // Special
    @"comment",
    @"whitespace",
    @"error",
};

/// A single token in TOML
pub const Token = struct {
    type: TokenType,
    text: []const u8,
    line: usize,
    column: usize,
};

/// TOML Lexer — tokenizes TOML input for syntax highlighting
pub const TomlLexer = struct {
    input: []const u8,
    pos: usize = 0,
    line: usize = 1,
    column: usize = 1,
    allocator: Allocator,
    tokens: std.ArrayList(Token),

    pub fn init(allocator: Allocator, input: []const u8) TomlLexer {
        return TomlLexer{
            .allocator = allocator,
            .input = input,
            .tokens = std.ArrayList(Token){},
        };
    }

    pub fn deinit(self: *TomlLexer) void {
        self.tokens.deinit(self.allocator);
    }

    /// Tokenize the entire input
    pub fn tokenize(self: *TomlLexer) !void {
        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];

            // Comments
            if (ch == '#') {
                try self.scanComment();
                continue;
            }

            // Whitespace
            if (std.ascii.isWhitespace(ch)) {
                try self.scanWhitespace();
                continue;
            }

            // Table headers: [name] or [[array]]
            // Check if this is a table header (starts at beginning of line or after whitespace)
            if (ch == '[') {
                // Look back to see if we're at line start
                var is_line_start = self.pos == 0;
                if (!is_line_start and self.pos > 0) {
                    var check_pos = self.pos - 1;
                    while (check_pos > 0 and (self.input[check_pos] == ' ' or self.input[check_pos] == '\t')) {
                        check_pos -= 1;
                    }
                    is_line_start = self.input[check_pos] == '\n' or check_pos == 0;
                }

                if (is_line_start or self.pos == 0) {
                    try self.scanTableHeader();
                    continue;
                }
            }

            // Inline table open
            if (ch == '{') {
                try self.addToken(.@"inline_table_open", "{");
                self.advance();
                continue;
            }

            // Inline table close
            if (ch == '}') {
                try self.addToken(.@"inline_table_close", "}");
                self.advance();
                continue;
            }

            // Array open
            if (ch == '[') {
                try self.addToken(.@"array_open", "[");
                self.advance();
                continue;
            }

            if (ch == ']') {
                try self.addToken(.@"array_close", "]");
                self.advance();
                continue;
            }

            // Operators
            if (ch == '=') {
                try self.addToken(.@"equals", "=");
                self.advance();
                continue;
            }

            if (ch == ',') {
                try self.addToken(.@"comma", ",");
                self.advance();
                continue;
            }

            if (ch == '.') {
                try self.addToken(.@"dot", ".");
                self.advance();
                continue;
            }

            // Strings: "...", '...', """...""", '''...'''
            if (ch == '"' or ch == '\'') {
                try self.scanString();
                continue;
            }

            // Numbers: -123, 123.45, 1e-3, 0x1F, 0o755, 0b1010
            if (std.ascii.isDigit(ch) or (ch == '-' and self.pos + 1 < self.input.len and std.ascii.isDigit(self.input[self.pos + 1]))) {
                try self.scanNumber();
                continue;
            }

            // Booleans and keys (identifiers)
            if (std.ascii.isAlphabetic(ch) or ch == '_' or ch == '-') {
                try self.scanKeyOrKeyword();
                continue;
            }

            // Unknown character
            try self.addToken(.@"error", &[_]u8{ch});
            self.advance();
        }
    }

    fn scanComment(self: *TomlLexer) !void {
        const start = self.pos;
        while (self.pos < self.input.len and self.input[self.pos] != '\n') {
            self.advance();
        }
        try self.addTokenRange(.@"comment", start);
    }

    fn scanWhitespace(self: *TomlLexer) !void {
        const start = self.pos;
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) {
            if (self.input[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
        try self.addTokenRange(.@"whitespace", start);
    }

    fn scanTableHeader(self: *TomlLexer) !void {
        const start = self.pos;

        // Check for [[array_of_tables]]
        const is_array = self.pos + 1 < self.input.len and self.input[self.pos + 1] == '[';

        self.advance(); // consume '['
        if (is_array) self.advance(); // consume second '['

        // Skip whitespace
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos]) and self.input[self.pos] != '\n') {
            self.advance();
        }

        // Scan table name
        while (self.pos < self.input.len and self.input[self.pos] != ']' and self.input[self.pos] != '\n') {
            self.advance();
        }

        // Consume closing ]
        if (self.pos < self.input.len and self.input[self.pos] == ']') {
            self.advance();
            if (is_array and self.pos < self.input.len and self.input[self.pos] == ']') {
                self.advance();
            }
        }

        try self.addTokenRange(.@"table_header", start);
    }

    fn scanString(self: *TomlLexer) !void {
        const start = self.pos;
        const quote = self.input[self.pos];

        self.advance(); // consume opening quote

        // Check for triple quotes
        const is_triple = self.pos + 1 < self.input.len and
            self.input[self.pos] == quote and
            self.input[self.pos + 1] == quote;

        if (is_triple) {
            self.advance();
            self.advance();
            // Scan until we find the closing triple quote
            while (self.pos < self.input.len) {
                if (self.input[self.pos] == quote and
                    self.pos + 2 < self.input.len and
                    self.input[self.pos + 1] == quote and
                    self.input[self.pos + 2] == quote)
                {
                    self.advance();
                    self.advance();
                    self.advance();
                    break;
                }
                if (self.input[self.pos] == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
                self.pos += 1;
            }
        } else {
            // Regular single-line string
            var escape = false;
            while (self.pos < self.input.len) {
                const ch = self.input[self.pos];

                if (ch == '\n') {
                    self.line += 1;
                    self.column = 1;
                    break; // Unterminated string on single line
                }

                if (escape) {
                    escape = false;
                } else if (ch == '\\' and quote == '"') {
                    escape = true;
                } else if (ch == quote) {
                    self.advance();
                    break;
                }

                self.column += 1;
                self.pos += 1;
            }
        }

        try self.addTokenRange(.@"string", start);
    }

    fn scanNumber(self: *TomlLexer) !void {
        const start = self.pos;

        // Handle negative sign
        if (self.input[self.pos] == '-') {
            self.advance();
        }

        // Check for hex, octal, binary
        if (self.input[self.pos] == '0' and self.pos + 1 < self.input.len) {
            const next = self.input[self.pos + 1];
            if (next == 'x' or next == 'X') {
                // Hex number
                self.advance(); // 0
                self.advance(); // x
                while (self.pos < self.input.len and (std.ascii.isDigit(self.input[self.pos]) or
                    (self.input[self.pos] >= 'a' and self.input[self.pos] <= 'f') or
                    (self.input[self.pos] >= 'A' and self.input[self.pos] <= 'F')))
                {
                    self.advance();
                }
                try self.addTokenRange(.@"integer", start);
                return;
            } else if (next == 'o' or next == 'O') {
                // Octal
                self.advance(); // 0
                self.advance(); // o
                while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '7') {
                    self.advance();
                }
                try self.addTokenRange(.@"integer", start);
                return;
            } else if (next == 'b' or next == 'B') {
                // Binary
                self.advance(); // 0
                self.advance(); // b
                while (self.pos < self.input.len and (self.input[self.pos] == '0' or self.input[self.pos] == '1')) {
                    self.advance();
                }
                try self.addTokenRange(.@"integer", start);
                return;
            }
        }

        // Scan digits
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
            self.advance();
        }

        // Check for float or datetime
        var is_float = false;
        var is_datetime = false;

        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            is_float = true;
            self.advance();
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                self.advance();
            }
        }

        // Check for exponent
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            is_float = true;
            self.advance();
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) {
                self.advance();
            }
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                self.advance();
            }
        }

        // Check for ISO 8601 datetime
        if (self.pos < self.input.len and (self.input[self.pos] == 'T' or self.input[self.pos] == 't' or self.input[self.pos] == ' ')) {
            is_datetime = true;
            self.advance();
            // Skip time portion validation for simplicity
            while (self.pos < self.input.len and self.input[self.pos] != ',' and
                self.input[self.pos] != '}' and self.input[self.pos] != '\n' and
                self.input[self.pos] != '#')
            {
                self.advance();
            }
        }

        const token_type: TokenType = if (is_datetime) TokenType.@"datetime" else if (is_float) TokenType.@"float" else TokenType.@"integer";
        try self.addTokenRange(token_type, start);
    }

    fn scanKeyOrKeyword(self: *TomlLexer) !void {
        const start = self.pos;

        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-') {
                self.advance();
            } else {
                break;
            }
        }

        const text = self.input[start..self.pos];

        // Check if it's a keyword (boolean or null)
        const token_type: TokenType = if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false"))
            TokenType.@"boolean"
        else if (std.mem.eql(u8, text, "null"))
            TokenType.@"null"
        else
            TokenType.@"key";

        try self.addToken(token_type, text);
    }

    fn advance(self: *TomlLexer) void {
        if (self.pos < self.input.len) {
            if (self.input[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }

    fn addToken(self: *TomlLexer, token_type: TokenType, text: []const u8) !void {
        try self.tokens.append(self.allocator, Token{
            .type = token_type,
            .text = text,
            .line = self.line,
            .column = self.column,
        });
    }

    fn addTokenRange(self: *TomlLexer, token_type: TokenType, start: usize) !void {
        const text = self.input[start..self.pos];
        try self.addToken(token_type, text);
    }
};

/// Syntax highlighted TOML representation
pub const HighlightedToml = struct {
    allocator: Allocator,
    tokens: []Token,

    pub fn deinit(self: *HighlightedToml) void {
        self.allocator.free(self.tokens);
    }
};

/// Colorize a token based on its type (ANSI escape codes)
pub fn colorizeToken(token: Token) struct {
    prefix: []const u8,
    suffix: []const u8,
} {
    return switch (token.type) {
        .@"table_header" => .{ .prefix = "\x1b[1;33m", .suffix = "\x1b[0m" }, // Bold yellow
        .@"key" => .{ .prefix = "\x1b[1;35m", .suffix = "\x1b[0m" }, // Bold magenta
        .@"string" => .{ .prefix = "\x1b[1;32m", .suffix = "\x1b[0m" }, // Bold green
        .@"integer", .@"float" => .{ .prefix = "\x1b[1;36m", .suffix = "\x1b[0m" }, // Bold cyan
        .@"boolean" => .{ .prefix = "\x1b[1;31m", .suffix = "\x1b[0m" }, // Bold red
        .@"comment" => .{ .prefix = "\x1b[0;90m", .suffix = "\x1b[0m" }, // Dark gray
        .@"datetime" => .{ .prefix = "\x1b[1;34m", .suffix = "\x1b[0m" }, // Bold blue
        .@"error" => .{ .prefix = "\x1b[1;41m", .suffix = "\x1b[0m" }, // Bold red background
        else => .{ .prefix = "", .suffix = "" },
    };
}

/// Highlight TOML content and return a formatted string with ANSI colors
pub fn highlightToml(allocator: Allocator, input: []const u8) ![]const u8 {
    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (lexer.tokens.items) |token| {
        const colors = colorizeToken(token);
        try result.appendSlice(allocator, colors.prefix);
        try result.appendSlice(allocator, token.text);
        try result.appendSlice(allocator, colors.suffix);
    }

    return result.toOwnedSlice(allocator);
}

test "TomlLexer tokenizes simple key-value pair" {
    const allocator = std.testing.allocator;
    const input = "name = \"hello\"";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    // Expect: key "name", whitespace, equals, whitespace, string "hello"
    try std.testing.expectEqual(@as(usize, 5), lexer.tokens.items.len);
    try std.testing.expectEqual(TokenType.@"key", lexer.tokens.items[0].type);
    try std.testing.expectEqualStrings("name", lexer.tokens.items[0].text);

    try std.testing.expectEqual(TokenType.@"equals", lexer.tokens.items[2].type);
    try std.testing.expectEqual(TokenType.@"string", lexer.tokens.items[4].type);
}

test "TomlLexer tokenizes table header" {
    const allocator = std.testing.allocator;
    const input = "[tasks.build]";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    try std.testing.expectEqual(@as(usize, 1), lexer.tokens.items.len);
    try std.testing.expectEqual(TokenType.@"table_header", lexer.tokens.items[0].type);
    try std.testing.expectEqualStrings("[tasks.build]", lexer.tokens.items[0].text);
}

test "TomlLexer tokenizes array of tables" {
    const allocator = std.testing.allocator;
    const input = "[[workflows.stages]]";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    try std.testing.expectEqual(@as(usize, 1), lexer.tokens.items.len);
    try std.testing.expectEqual(TokenType.@"table_header", lexer.tokens.items[0].type);
}

test "TomlLexer tokenizes comment" {
    const allocator = std.testing.allocator;
    const input = "# This is a comment";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var found_comment = false;
    for (lexer.tokens.items) |token| {
        if (token.type == .@"comment") {
            found_comment = true;
        }
    }
    try std.testing.expect(found_comment);
}

test "TomlLexer tokenizes numbers (integer, float, hex, octal, binary)" {
    const allocator = std.testing.allocator;
    const input = "int = 42\nfloat = 3.14\nhex = 0xFF\noctal = 0o755\nbinary = 0b1010";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var integer_found = false;
    var float_found = false;
    var hex_found = false;
    var octal_found = false;
    var binary_found = false;

    for (lexer.tokens.items) |token| {
        if (token.type == .@"integer" and std.mem.eql(u8, token.text, "42")) integer_found = true;
        if (token.type == .@"float" and std.mem.eql(u8, token.text, "3.14")) float_found = true;
        if (token.type == .@"integer" and std.mem.eql(u8, token.text, "0xFF")) hex_found = true;
        if (token.type == .@"integer" and std.mem.eql(u8, token.text, "0o755")) octal_found = true;
        if (token.type == .@"integer" and std.mem.eql(u8, token.text, "0b1010")) binary_found = true;
    }

    try std.testing.expect(integer_found);
    try std.testing.expect(float_found);
    try std.testing.expect(hex_found);
    try std.testing.expect(octal_found);
    try std.testing.expect(binary_found);
}

test "TomlLexer tokenizes boolean and null" {
    const allocator = std.testing.allocator;
    const input = "enabled = true\ndisabled = false\nempty = null";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var true_found = false;
    var false_found = false;
    var null_found = false;

    for (lexer.tokens.items) |token| {
        if (token.type == .@"boolean" and std.mem.eql(u8, token.text, "true")) true_found = true;
        if (token.type == .@"boolean" and std.mem.eql(u8, token.text, "false")) false_found = true;
        if (token.type == .@"null") null_found = true;
    }

    try std.testing.expect(true_found);
    try std.testing.expect(false_found);
    try std.testing.expect(null_found);
}

test "TomlLexer tokenizes inline tables" {
    const allocator = std.testing.allocator;
    const input = "point = { x = 1, y = 2 }";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var open_found = false;
    var close_found = false;

    for (lexer.tokens.items) |token| {
        if (token.type == .@"inline_table_open") open_found = true;
        if (token.type == .@"inline_table_close") close_found = true;
    }

    try std.testing.expect(open_found);
    try std.testing.expect(close_found);
}

test "TomlLexer tokenizes arrays" {
    const allocator = std.testing.allocator;
    const input = "items = [1, 2, 3]";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var array_open_found = false;
    var array_close_found = false;

    for (lexer.tokens.items) |token| {
        if (token.type == .@"array_open") array_open_found = true;
        if (token.type == .@"array_close") array_close_found = true;
    }

    try std.testing.expect(array_open_found);
    try std.testing.expect(array_close_found);
}

test "TomlLexer handles multiline strings (triple quotes)" {
    const allocator = std.testing.allocator;
    const input =
        \\desc = """
        \\This is a
        \\multiline string
        \\"""
    ;

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var multiline_found = false;
    for (lexer.tokens.items) |token| {
        if (token.type == .@"string" and std.mem.indexOf(u8, token.text, "\n") != null) {
            multiline_found = true;
        }
    }
    try std.testing.expect(multiline_found);
}

test "TomlLexer handles escape sequences in strings" {
    const allocator = std.testing.allocator;
    const input = "message = \"Hello\\nWorld\"";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var string_found = false;
    for (lexer.tokens.items) |token| {
        if (token.type == .@"string") {
            string_found = true;
        }
    }
    try std.testing.expect(string_found);
}

test "TomlLexer tokenizes datetime values" {
    const allocator = std.testing.allocator;
    const input = "created = 2026-03-17T10:30:00Z";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var datetime_found = false;
    for (lexer.tokens.items) |token| {
        if (token.type == .@"datetime") {
            datetime_found = true;
        }
    }
    try std.testing.expect(datetime_found);
}

test "TomlLexer tracks line and column numbers" {
    const allocator = std.testing.allocator;
    const input = "key = 1\nvalue = 2";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    // First token on line 1
    try std.testing.expectEqual(@as(usize, 1), lexer.tokens.items[0].line);
    // Token on line 2 should exist
    var second_line_found = false;
    for (lexer.tokens.items) |token| {
        if (token.line == 2) {
            second_line_found = true;
        }
    }
    try std.testing.expect(second_line_found);
}

test "highlightToml produces colored output" {
    const allocator = std.testing.allocator;
    const input = "key = \"value\"";

    const highlighted = try highlightToml(allocator, input);
    defer allocator.free(highlighted);

    // Expect ANSI escape codes in output
    try std.testing.expect(std.mem.indexOf(u8, highlighted, "\x1b[") != null);
}

test "TomlLexer handles complex TOML config" {
    const allocator = std.testing.allocator;
    const input =
        \\# zr configuration
        \\[tasks.build]
        \\cmd = "npm run build"
        \\description = "Build the project"
        \\
        \\[[workflows.stages]]
        \\name = "compile"
        \\tasks = ["build"]
        \\parallel = true
    ;

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    // Must have at least one token of each major type
    var has_comment = false;
    var has_table = false;
    var has_key = false;
    var has_string = false;
    var has_array = false;

    for (lexer.tokens.items) |token| {
        if (token.type == .@"comment") has_comment = true;
        if (token.type == .@"table_header") has_table = true;
        if (token.type == .@"key") has_key = true;
        if (token.type == .@"string") has_string = true;
        if (token.type == .@"array_open" or token.type == .@"array_close") has_array = true;
    }

    try std.testing.expect(has_comment);
    try std.testing.expect(has_table);
    try std.testing.expect(has_key);
    try std.testing.expect(has_string);
    try std.testing.expect(has_array);
}

test "TomlLexer distinguishes single and double quotes" {
    const allocator = std.testing.allocator;
    const input = "single = 'value'\ndouble = \"value\"";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var string_count: usize = 0;
    for (lexer.tokens.items) |token| {
        if (token.type == .@"string") {
            string_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 2), string_count);
}

test "TomlLexer handles negative numbers" {
    const allocator = std.testing.allocator;
    const input = "value = -42";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var negative_found = false;
    for (lexer.tokens.items) |token| {
        if (token.type == .@"integer" and std.mem.eql(u8, token.text, "-42")) {
            negative_found = true;
        }
    }
    try std.testing.expect(negative_found);
}

test "TomlLexer handles dotted keys" {
    const allocator = std.testing.allocator;
    const input = "server.host = \"localhost\"";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();

    var dot_found = false;
    for (lexer.tokens.items) |token| {
        if (token.type == .@"dot") {
            dot_found = true;
        }
    }
    try std.testing.expect(dot_found);
}

test "TomlLexer no memory leaks during tokenization" {
    const allocator = std.testing.allocator;
    const input = "[section]\nkey = \"value\"\n# comment";

    var lexer = TomlLexer.init(allocator, input);
    defer lexer.deinit();

    try lexer.tokenize();
    // deinit() called in defer — test framework detects leaks
}
