//! Bounded single-line reads for the interactive prompts of `zr add` and the config editor.
//!
//! A line is stored in a caller-supplied buffer, so a reader never allocates and never grows
//! with the input. A line longer than the buffer is an operating error (`error.LineTooLong`),
//! not a programmer error: the stream is data from a user or a pipe. The rest of an over-long
//! line is discarded, up to `discard_bytes_max`, so the next read starts on a line boundary.
//!
//! Sketch: one `read` syscall per byte (interactive input is a few dozen bytes, a terminal
//! delivers whole lines anyway); zero allocations; memory is the caller's `line_bytes_max`.

const std = @import("std");
const assert = @import("../stdx.zig").assert;

/// Default capacity for an interactive prompt line, in bytes.
pub const line_bytes_max: u32 = 4096;

/// Upper bound on bytes discarded while skipping the tail of an over-long line.
pub const discard_bytes_max: u32 = 1024 * 1024;

/// Message for the user when a line exceeds `line_bytes_max`.
pub const too_long_message = std.fmt.comptimePrint(
    "\nInput line too long (limit {d} bytes)\n",
    .{line_bytes_max},
);

pub const LineError = error{LineTooLong};

pub const Line = union(enum) {
    /// A complete line without its `\n` terminator and without any `\r`; borrows `buffer`.
    text: []const u8,
    /// The source ended, or was closed, before a `\n` arrived.
    eof,
};

/// Reads one line from `source`, a pointer to any value with `read([]u8) !usize` whose error set
/// contains `NotOpenForReading` (a `std.fs.File` qualifies); a closed source reads as `.eof`.
/// `buffer.len` is the line limit in bytes and must be non-zero. Carriage returns are dropped
/// and do not count against the limit. At most `buffer.len + discard_bytes_max` bytes are
/// consumed per call, so a source that never sends a newline cannot hang the caller.
pub fn readLine(source: anytype, buffer: []u8) !Line {
    assert(buffer.len > 0);
    assert(buffer.len <= line_bytes_max);

    var length: usize = 0;
    var overflowed = false;
    var byte: [1]u8 = undefined;
    for (0..buffer.len + discard_bytes_max) |_| {
        const count = source.read(&byte) catch |err| switch (err) {
            error.NotOpenForReading => return .eof,
            else => return err,
        };
        if (count == 0) return .eof;

        switch (byte[0]) {
            '\n' => {
                if (overflowed) return error.LineTooLong;
                assert(length <= buffer.len);
                return .{ .text = buffer[0..length] };
            },
            '\r' => {},
            else => {
                if (length < buffer.len) {
                    buffer[length] = byte[0];
                    length += 1;
                } else {
                    overflowed = true;
                }
            },
        }
    }
    return error.LineTooLong;
}

const SliceSource = struct {
    data: []const u8,
    position: usize = 0,

    fn read(self: *SliceSource, out: []u8) error{NotOpenForReading}!usize {
        if (self.position >= self.data.len) return 0;
        out[0] = self.data[self.position];
        self.position += 1;
        return 1;
    }
};

const ClosedSource = struct {
    fn read(_: *ClosedSource, _: []u8) error{NotOpenForReading}!usize {
        return error.NotOpenForReading;
    }
};

const BrokenSource = struct {
    fn read(_: *BrokenSource, _: []u8) error{ NotOpenForReading, InputOutput }!usize {
        return error.InputOutput;
    }
};

fn expectText(expected: []const u8, actual: Line) !void {
    switch (actual) {
        .text => |text| try std.testing.expectEqualStrings(expected, text),
        .eof => return error.TestUnexpectedResult,
    }
}

test "readLine returns a line without its newline" {
    var source = SliceSource{ .data = "hello\nworld\n" };
    var buffer: [16]u8 = undefined;

    try expectText("hello", try readLine(&source, &buffer));
    try expectText("world", try readLine(&source, &buffer));
    try std.testing.expectEqual(Line.eof, try readLine(&source, &buffer));
}

test "readLine strips carriage returns" {
    var source = SliceSource{ .data = "a\r\nb\r\n" };
    var buffer: [8]u8 = undefined;

    try expectText("a", try readLine(&source, &buffer));
    try expectText("b", try readLine(&source, &buffer));
}

test "readLine returns an empty line for a bare newline" {
    var source = SliceSource{ .data = "\nx\n" };
    var buffer: [8]u8 = undefined;

    try expectText("", try readLine(&source, &buffer));
    try expectText("x", try readLine(&source, &buffer));
}

test "readLine reports eof for an empty source and for an unterminated line" {
    var empty = SliceSource{ .data = "" };
    var partial = SliceSource{ .data = "no newline" };
    var buffer: [32]u8 = undefined;

    try std.testing.expectEqual(Line.eof, try readLine(&empty, &buffer));
    try std.testing.expectEqual(Line.eof, try readLine(&partial, &buffer));
}

test "readLine reports eof for a closed source" {
    var source = ClosedSource{};
    var buffer: [8]u8 = undefined;

    try std.testing.expectEqual(Line.eof, try readLine(&source, &buffer));
}

test "readLine propagates other read errors" {
    var source = BrokenSource{};
    var buffer: [8]u8 = undefined;

    try std.testing.expectError(error.InputOutput, readLine(&source, &buffer));
}

test "readLine accepts a line of exactly the limit" {
    var source = SliceSource{ .data = "abcd\nz\n" };
    var buffer: [4]u8 = undefined;

    try expectText("abcd", try readLine(&source, &buffer));
    try expectText("z", try readLine(&source, &buffer));
}

test "readLine rejects a line one byte over the limit and resyncs" {
    var source = SliceSource{ .data = "abcde\nz\n" };
    var buffer: [4]u8 = undefined;

    try std.testing.expectError(error.LineTooLong, readLine(&source, &buffer));
    try expectText("z", try readLine(&source, &buffer));
}

test "readLine stops discarding at discard_bytes_max on an endless line" {
    const Endless = struct {
        count: usize = 0,

        fn read(self: *@This(), out: []u8) error{NotOpenForReading}!usize {
            out[0] = 'x';
            self.count += 1;
            return 1;
        }
    };
    var source = Endless{};
    var buffer: [4]u8 = undefined;

    try std.testing.expectError(error.LineTooLong, readLine(&source, &buffer));
    try std.testing.expect(source.count <= buffer.len + discard_bytes_max + 1);
}

test "readLine does not count carriage returns against the limit" {
    var source = SliceSource{ .data = "ab\r\r\rcd\n" };
    var buffer: [4]u8 = undefined;

    try expectText("abcd", try readLine(&source, &buffer));
}
