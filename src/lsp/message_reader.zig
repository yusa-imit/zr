//! Bounded reader for `Content-Length` framed LSP messages.
//!
//! The header block lives in a fixed array of `header_bytes_max` bytes and the body is allocated
//! once, after its declared length has been checked against `content_bytes_max`. A peer can
//! therefore not grow memory with a header that never ends or a length that is never delivered.
//! Over-long headers and over-large lengths are operating errors: the bytes come from a pipe.
//!
//! Sketch: input is staged through an 8 KiB buffer (one `read` syscall per 8 KiB), the header
//! scan is one pass over at most `header_bytes_max` bytes, the body costs one allocation and one
//! copy. Ownership: the returned body belongs to the caller, who frees it with the same `gpa`.

const std = @import("std");
const assert = @import("../stdx.zig").assert;
const maybe = @import("../stdx.zig").maybe;

/// Upper bound on one header block, terminator included.
pub const header_bytes_max: u32 = 8192;

/// Upper bound on one message body, in bytes.
pub const content_bytes_max: u32 = 64 * 1024 * 1024;

pub const ReadError = error{
    /// The header block exceeded `header_bytes_max` before its terminator arrived.
    HeaderTooLarge,
    /// The header block carried no usable `Content-Length` value.
    MissingContentLength,
    /// The declared length exceeded `content_bytes_max`.
    MessageTooLarge,
};

pub const MessageReader = struct {
    stage: [8192]u8 = undefined,
    stage_start: u32 = 0,
    stage_end: u32 = 0,

    /// Reads the next message from `source`, a pointer to any value with `read([]u8) !usize`.
    /// Returns the owned body, or null once `source` is exhausted, also mid-message. After
    /// `MissingContentLength` the header block is consumed and the next call starts a new message.
    pub fn next(reader: *MessageReader, gpa: std.mem.Allocator, source: anytype) !?[]u8 {
        assert(reader.stage_start <= reader.stage_end);
        assert(reader.stage_end <= reader.stage.len);

        var header: [header_bytes_max]u8 = undefined;
        const header_length = try reader.read_header(source, &header) orelse return null;
        const body_length = try parse_content_length(header[0..header_length]);
        assert(body_length <= content_bytes_max);
        maybe(body_length == 0);

        const body = try gpa.alloc(u8, body_length);
        errdefer gpa.free(body);

        if (!try reader.read_body(source, body)) {
            gpa.free(body);
            return null;
        }
        return body;
    }

    fn read_header(reader: *MessageReader, source: anytype, header: *[header_bytes_max]u8) !?u32 {
        var length: u32 = 0;
        var line_ends: u8 = 0;
        var previous: u8 = 0;
        for (0..header_bytes_max) |_| {
            const byte = try reader.next_byte(source) orelse return null;
            header[length] = byte;
            length += 1;

            if (byte == '\n' and previous == '\r') {
                line_ends += 1;
                if (line_ends == 2) return length;
            } else if (byte != '\r' and byte != '\n') {
                line_ends = 0;
            }
            previous = byte;
        }
        return error.HeaderTooLarge;
    }

    fn read_body(reader: *MessageReader, source: anytype, body: []u8) !bool {
        var filled: usize = 0;
        for (0..body.len + 1) |_| {
            if (filled == body.len) return true;
            if (reader.stage_start == reader.stage_end) {
                if (!try reader.refill(source)) return false;
            }
            const available = reader.stage_end - reader.stage_start;
            const copy_length = @min(available, body.len - filled);
            const stage_slice = reader.stage[reader.stage_start..][0..copy_length];
            @memcpy(body[filled..][0..copy_length], stage_slice);
            reader.stage_start += @intCast(copy_length);
            filled += copy_length;
        }
        unreachable; // Each pass copies at least one byte, so `body.len` passes finish the body.
    }

    fn next_byte(reader: *MessageReader, source: anytype) !?u8 {
        if (reader.stage_start == reader.stage_end) {
            if (!try reader.refill(source)) return null;
        }
        const byte = reader.stage[reader.stage_start];
        reader.stage_start += 1;
        return byte;
    }

    /// Returns false at end of input. Precondition: the stage is empty.
    fn refill(reader: *MessageReader, source: anytype) !bool {
        assert(reader.stage_start == reader.stage_end);
        const count = try source.read(&reader.stage);
        reader.stage_start = 0;
        reader.stage_end = @intCast(count);
        return count > 0;
    }
};

/// Extracts the `Content-Length` value from a header block.
fn parse_content_length(header: []const u8) ReadError!u32 {
    const name = "Content-Length: ";
    const name_index = std.mem.indexOf(u8, header, name) orelse return error.MissingContentLength;
    const digits_start = name_index + name.len;

    var digits_end = digits_start;
    while (digits_end < header.len and std.ascii.isDigit(header[digits_end])) digits_end += 1;
    const digits = header[digits_start..digits_end];
    if (digits.len == 0) return error.MissingContentLength;

    const value = std.fmt.parseInt(u32, digits, 10) catch |err| switch (err) {
        error.Overflow => return error.MessageTooLarge,
        error.InvalidCharacter => unreachable, // `digits` holds only ASCII digits, and some.
    };
    if (value > content_bytes_max) return error.MessageTooLarge;
    return value;
}

const testing = std.testing;

/// Hands out `data` in `chunk_size`-byte reads, so tests cross the stage boundary.
const ChunkSource = struct {
    data: []const u8,
    chunk_size: usize,
    position: usize = 0,

    fn read(source: *ChunkSource, out: []u8) error{}!usize {
        const count = @min(@min(out.len, source.chunk_size), source.data.len - source.position);
        @memcpy(out[0..count], source.data[source.position..][0..count]);
        source.position += count;
        return count;
    }
};

test "next returns each framed body in order" {
    const input = "Content-Length: 5\r\n\r\nhelloContent-Length: 3\r\nX: y\r\n\r\nabc";
    var source: ChunkSource = .{ .data = input, .chunk_size = 7 };
    var reader: MessageReader = .{};

    const first = (try reader.next(testing.allocator, &source)).?;
    defer testing.allocator.free(first);

    const second = (try reader.next(testing.allocator, &source)).?;
    defer testing.allocator.free(second);

    try testing.expectEqualStrings("hello", first);
    try testing.expectEqualStrings("abc", second);
    try testing.expectEqual(@as(?[]u8, null), try reader.next(testing.allocator, &source));
}

test "next treats a body spanning many stages as one message" {
    const body_length = 3 * 8192 + 11;
    const body = try testing.allocator.alloc(u8, body_length);
    defer testing.allocator.free(body);

    for (body, 0..) |*byte, index| byte.* = @intCast('a' + index % 26);
    const input = try std.fmt.allocPrint(
        testing.allocator,
        "Content-Length: {d}\r\n\r\n{s}",
        .{ body_length, body },
    );
    defer testing.allocator.free(input);

    var source: ChunkSource = .{ .data = input, .chunk_size = 8192 };
    var reader: MessageReader = .{};
    const got = (try reader.next(testing.allocator, &source)).?;
    defer testing.allocator.free(got);

    try testing.expectEqualSlices(u8, body, got);
}

test "next ends on empty input and on input cut inside header or body" {
    const cases = [_][]const u8{ "", "Content-Length: 5\r\n", "Content-Length: 5\r\n\r\nhel" };
    for (cases) |input| {
        var source: ChunkSource = .{ .data = input, .chunk_size = 4 };
        var reader: MessageReader = .{};
        try testing.expectEqual(@as(?[]u8, null), try reader.next(testing.allocator, &source));
    }
}

test "next reports a header block without Content-Length and recovers" {
    const input = "X-Other: 1\r\n\r\nContent-Length: 2\r\n\r\nok";
    var source: ChunkSource = .{ .data = input, .chunk_size = 5 };
    var reader: MessageReader = .{};

    try testing.expectError(error.MissingContentLength, reader.next(testing.allocator, &source));
    const body = (try reader.next(testing.allocator, &source)).?;
    defer testing.allocator.free(body);

    try testing.expectEqualStrings("ok", body);
}

test "next reports a Content-Length without digits" {
    var source: ChunkSource = .{ .data = "Content-Length: x\r\n\r\n", .chunk_size = 64 };
    var reader: MessageReader = .{};

    try testing.expectError(error.MissingContentLength, reader.next(testing.allocator, &source));
}

test "next accepts a header block of exactly header_bytes_max bytes" {
    const prefix = "Content-Length: 2\r\nX-Pad: ";
    const suffix = "\r\n\r\n";
    var input: [header_bytes_max + 2]u8 = undefined;
    @memset(&input, 'p');
    @memcpy(input[0..prefix.len], prefix);
    @memcpy(input[header_bytes_max - suffix.len ..][0..suffix.len], suffix);
    @memcpy(input[header_bytes_max..], "ok");

    var source: ChunkSource = .{ .data = &input, .chunk_size = 8192 };
    var reader: MessageReader = .{};
    const body = (try reader.next(testing.allocator, &source)).?;
    defer testing.allocator.free(body);

    try testing.expectEqualStrings("ok", body);
}

test "next rejects a header block one byte past header_bytes_max" {
    const prefix = "Content-Length: 2\r\nX-Pad: ";
    const suffix = "\r\n\r\n";
    var input: [header_bytes_max + 1]u8 = undefined;
    @memset(&input, 'p');
    @memcpy(input[0..prefix.len], prefix);
    @memcpy(input[header_bytes_max + 1 - suffix.len ..][0..suffix.len], suffix);

    var source: ChunkSource = .{ .data = &input, .chunk_size = 8192 };
    var reader: MessageReader = .{};

    try testing.expectError(error.HeaderTooLarge, reader.next(testing.allocator, &source));
}

test "next rejects a header that never ends without growing" {
    const input = "a" ** (4 * header_bytes_max);
    var source: ChunkSource = .{ .data = input, .chunk_size = 8192 };
    var reader: MessageReader = .{};

    try testing.expectError(error.HeaderTooLarge, reader.next(testing.allocator, &source));
    try testing.expect(source.position <= 2 * header_bytes_max);
}

test "next rejects lengths beyond content_bytes_max before allocating" {
    const cases = [_][]const u8{
        "Content-Length: 67108865\r\n\r\n",
        "Content-Length: 99999999999999999999\r\n\r\n",
    };
    for (cases) |input| {
        var source: ChunkSource = .{ .data = input, .chunk_size = 64 };
        var reader: MessageReader = .{};
        const result = reader.next(testing.failing_allocator, &source);
        try testing.expectError(error.MessageTooLarge, result);
    }
}

test "next returns an empty body for Content-Length 0" {
    var source: ChunkSource = .{ .data = "Content-Length: 0\r\n\r\n", .chunk_size = 64 };
    var reader: MessageReader = .{};
    const body = (try reader.next(testing.allocator, &source)).?;
    defer testing.allocator.free(body);

    try testing.expectEqual(@as(usize, 0), body.len);
}

test "next propagates allocation failure and leaks nothing" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var source: ChunkSource = .{ .data = "Content-Length: 5\r\n\r\nhello", .chunk_size = 64 };
    var reader: MessageReader = .{};

    try testing.expectError(error.OutOfMemory, reader.next(failing.allocator(), &source));
}
