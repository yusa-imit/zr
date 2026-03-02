const std = @import("std");
const color = @import("../output/color.zig");
const registry_server = @import("../registry/server.zig");

/// Handle `zr registry` command.
pub fn cmdRegistry(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    use_color: bool,
    w: anytype,
    ew: anytype,
) !void {
    if (args.len < 3) {
        try printHelp(w, use_color);
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "serve")) {
        return cmdServe(allocator, args, use_color, w, ew);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
        try printHelp(w, use_color);
    } else {
        try color.printError(ew, use_color, "Unknown registry subcommand: {s}\n\n", .{subcommand});
        try printHelp(w, use_color);
        return error.UnknownSubcommand;
    }
}

fn cmdServe(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    use_color: bool,
    w: anytype,
    ew: anytype,
) !void {
    // Parse options.
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 8080;
    var data_dir: []const u8 = ".zr-registry";

    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--host")) {
            if (i + 1 >= args.len) {
                try color.printError(ew, use_color, "Missing value for --host\n", .{});
                return error.MissingArgument;
            }
            i += 1;
            host = args[i];
        } else if (std.mem.eql(u8, arg, "--port")) {
            if (i + 1 >= args.len) {
                try color.printError(ew, use_color, "Missing value for --port\n", .{});
                return error.MissingArgument;
            }
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch {
                try color.printError(ew, use_color, "Invalid port number: {s}\n", .{args[i]});
                return error.InvalidPort;
            };
        } else if (std.mem.eql(u8, arg, "--data-dir")) {
            if (i + 1 >= args.len) {
                try color.printError(ew, use_color, "Missing value for --data-dir\n", .{});
                return error.MissingArgument;
            }
            i += 1;
            data_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printServeHelp(w, use_color);
            return;
        } else {
            try color.printError(ew, use_color, "Unknown option: {s}\n\n", .{arg});
            try printServeHelp(w, use_color);
            return error.UnknownOption;
        }
    }

    // Start the server.
    const config = registry_server.ServerConfig{
        .host = host,
        .port = port,
        .data_dir = data_dir,
    };

    try color.printSuccess(w, use_color, "Starting zr registry server...\n", .{});
    try color.printDim(w, use_color, "  Host: {s}\n", .{host});
    try color.printDim(w, use_color, "  Port: {d}\n", .{port});
    try color.printDim(w, use_color, "  Data directory: {s}\n\n", .{data_dir});

    var server = try registry_server.Server.init(allocator, config);
    defer server.deinit();

    try server.serve();
}

fn printHelp(w: anytype, use_color: bool) !void {
    try color.printBold(w, use_color, "zr registry\n\n", .{});
    try w.writeAll("Manage plugin registry server\n\n");
    try color.printBold(w, use_color, "USAGE:\n", .{});
    try w.writeAll("  zr registry <subcommand> [OPTIONS]\n\n");
    try color.printBold(w, use_color, "SUBCOMMANDS:\n", .{});
    try w.writeAll("  serve              Start the registry HTTP server\n");
    try w.writeAll("  help               Show this help message\n\n");
    try color.printBold(w, use_color, "EXAMPLES:\n", .{});
    try w.writeAll("  zr registry serve                    # Start server on 127.0.0.1:8080\n");
    try w.writeAll("  zr registry serve --port 3000        # Start server on custom port\n");
    try w.writeAll("  zr registry serve --host 0.0.0.0     # Listen on all interfaces\n");
}

fn printServeHelp(w: anytype, use_color: bool) !void {
    try color.printBold(w, use_color, "zr registry serve\n\n", .{});
    try w.writeAll("Start the plugin registry HTTP server\n\n");
    try color.printBold(w, use_color, "USAGE:\n", .{});
    try w.writeAll("  zr registry serve [OPTIONS]\n\n");
    try color.printBold(w, use_color, "OPTIONS:\n", .{});
    try w.writeAll("  --host <host>         Host to bind to (default: 127.0.0.1)\n");
    try w.writeAll("  --port <port>         Port to listen on (default: 8080)\n");
    try w.writeAll("  --data-dir <path>     Data directory for plugin metadata (default: .zr-registry)\n");
    try w.writeAll("  --help, -h            Show this help message\n\n");
    try color.printBold(w, use_color, "EXAMPLES:\n", .{});
    try w.writeAll("  zr registry serve\n");
    try w.writeAll("  zr registry serve --port 3000 --host 0.0.0.0\n");
    try w.writeAll("  zr registry serve --data-dir /var/lib/zr-registry\n");
}
