const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrWithStdin = helpers.runZrWithStdin;
const writeTmpConfig = helpers.writeTmpConfig;

test "lsp: responds to initialize request" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create minimal config for LSP server
    const config_content =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;
    _ = try writeTmpConfig(allocator, tmp.dir, config_content);

    // Send LSP initialize request with Content-Length header
    const initialize_json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}";
    const content_length = initialize_json.len;

    var request_buffer: [512]u8 = undefined;
    const initialize_request = try std.fmt.bufPrint(&request_buffer, "Content-Length: {d}\r\n\r\n{s}", .{ content_length, initialize_json });

    var result = try runZrWithStdin(allocator, tmp.dir, &.{"lsp"}, initialize_request);
    defer result.deinit();

    // LSP server should respond with Content-Length header and initialize response
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Content-Length:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"result\"") != null);

    // Should contain server capabilities
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "capabilities") != null);
}

test "lsp: provides diagnostics for invalid config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create invalid config (missing cmd field)
    const config_content =
        \\[tasks.broken]
        \\deps = ["nonexistent"]
        \\
    ;
    _ = try writeTmpConfig(allocator, tmp.dir, config_content);

    // Send initialize + didOpen
    const initialize_json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}";
    const initialized_json = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}";

    // Construct didOpen notification
    var uri_buf: [256]u8 = undefined;
    const file_uri = try std.fmt.bufPrint(&uri_buf, "file://zr.toml", .{});

    const didOpen_json_template = "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\",\"languageId\":\"toml\",\"version\":1,\"text\":\"{s}\"}}}}}}";
    var didOpen_buf: [1024]u8 = undefined;

    // Escape the config content for JSON
    var escaped_config: [512]u8 = undefined;
    var escaped_len: usize = 0;
    for (config_content) |c| {
        if (c == '\n') {
            escaped_config[escaped_len] = '\\';
            escaped_len += 1;
            escaped_config[escaped_len] = 'n';
            escaped_len += 1;
        } else if (c == '"') {
            escaped_config[escaped_len] = '\\';
            escaped_len += 1;
            escaped_config[escaped_len] = '"';
            escaped_len += 1;
        } else {
            escaped_config[escaped_len] = c;
            escaped_len += 1;
        }
    }

    const didOpen_json = try std.fmt.bufPrint(&didOpen_buf, didOpen_json_template, .{ file_uri, escaped_config[0..escaped_len] });

    var request_buffer: [2048]u8 = undefined;
    const full_request = try std.fmt.bufPrint(&request_buffer,
        "Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}",
        .{ initialize_json.len, initialize_json, initialized_json.len, initialized_json, didOpen_json.len, didOpen_json },
    );

    var result = try runZrWithStdin(allocator, tmp.dir, &.{"lsp"}, full_request);
    defer result.deinit();

    // Should receive diagnostics about the invalid config
    // The exact format depends on implementation, but it should contain diagnostic information
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "textDocument/publishDiagnostics") != null or
        std.mem.indexOf(u8, result.stdout, "diagnostics") != null);
}

test "lsp: provides completion for task names" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create config with tasks
    const config_content =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\deps = [""]
        \\
    ;
    _ = try writeTmpConfig(allocator, tmp.dir, config_content);

    // Send initialize + didOpen + completion request
    const initialize_json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{\"textDocument\":{\"completion\":{}}}}}";
    const initialized_json = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}";

    var uri_buf: [256]u8 = undefined;
    const file_uri = try std.fmt.bufPrint(&uri_buf, "file://zr.toml", .{});

    // Escape config for JSON
    var escaped_config: [512]u8 = undefined;
    var escaped_len: usize = 0;
    for (config_content) |c| {
        if (c == '\n') {
            escaped_config[escaped_len] = '\\';
            escaped_len += 1;
            escaped_config[escaped_len] = 'n';
            escaped_len += 1;
        } else if (c == '"') {
            escaped_config[escaped_len] = '\\';
            escaped_len += 1;
            escaped_config[escaped_len] = '"';
            escaped_len += 1;
        } else {
            escaped_config[escaped_len] = c;
            escaped_len += 1;
        }
    }

    var didOpen_buf: [1024]u8 = undefined;
    const didOpen_json = try std.fmt.bufPrint(&didOpen_buf,
        "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\",\"languageId\":\"toml\",\"version\":1,\"text\":\"{s}\"}}}}}}",
        .{ file_uri, escaped_config[0..escaped_len] },
    );

    // Request completion inside the deps array (after ["")
    // Line 4 is "deps = [""]", position at character 8 (inside the quotes)
    const completion_json = try std.fmt.bufPrint(&uri_buf,
        "{{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\"}},\"position\":{{\"line\":4,\"character\":8}}}}}}",
        .{file_uri},
    );

    var request_buffer: [3072]u8 = undefined;
    const full_request = try std.fmt.bufPrint(&request_buffer,
        "Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}",
        .{
            initialize_json.len, initialize_json,
            initialized_json.len, initialized_json,
            didOpen_json.len,    didOpen_json,
            completion_json.len, completion_json,
        },
    );

    var result = try runZrWithStdin(allocator, tmp.dir, &.{"lsp"}, full_request);
    defer result.deinit();

    // Should provide completion items for available task names
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"id\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null or
        std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "lsp: handles shutdown gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_content =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;
    _ = try writeTmpConfig(allocator, tmp.dir, config_content);

    // Send initialize + shutdown + exit
    const initialize_json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}";
    const shutdown_json = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":null}";
    const exit_json = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":null}";

    var request_buffer: [1024]u8 = undefined;
    const full_request = try std.fmt.bufPrint(&request_buffer,
        "Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}Content-Length: {d}\r\n\r\n{s}",
        .{ initialize_json.len, initialize_json, shutdown_json.len, shutdown_json, exit_json.len, exit_json },
    );

    var result = try runZrWithStdin(allocator, tmp.dir, &.{"lsp"}, full_request);
    defer result.deinit();

    // Should respond to shutdown and exit cleanly
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"id\":2") != null);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}
