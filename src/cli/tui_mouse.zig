/// Mouse input integration for TUI modes.
///
/// Provides utilities to enable/disable mouse tracking and parse mouse events
/// from stdin alongside keyboard input. Integrates sailor.tui.mouse with existing
/// TUI implementations.

const std = @import("std");
const sailor = @import("sailor");
const mouse = sailor.tui.mouse;

/// Input event type - either keyboard or mouse
pub const InputEvent = union(enum) {
    keyboard: KeyEvent,
    mouse: mouse.MouseEvent,
    quit, // Special signal to quit
    none, // No event / timeout

    pub const KeyEvent = struct {
        code: u8,
        is_escape_seq: bool = false,
        escape_code: []const u8 = &.{}, // For arrow keys, etc.
    };
};

/// Read a single byte from stdin without blocking.
/// Returns null on EOF or error.
fn readByte(stdin: std.fs.File) ?u8 {
    var buf: [1]u8 = undefined;
    const n = stdin.read(&buf) catch return null;
    if (n == 0) return null;
    return buf[0];
}

/// Try to parse a mouse event from an escape sequence.
/// seq should start AFTER the ESC [ characters (i.e., at the '<' or digit).
fn tryParseMouse(seq: []const u8) ?mouse.MouseEvent {
    return mouse.parseSGR(seq);
}

/// Read and parse the next input event from stdin.
/// Handles both keyboard input and mouse events (SGR format).
/// Blocks until an event is available or returns .none on timeout.
pub fn pollInput(allocator: std.mem.Allocator, stdin: std.fs.File, timeout_ms: u64) !InputEvent {
    _ = timeout_ms; // TODO: Implement non-blocking read with timeout
    _ = allocator;

    const byte = readByte(stdin) orelse return .none;

    // Check for escape sequence (both keyboard and mouse)
    if (byte == 0x1b) {
        const b2 = readByte(stdin) orelse return .{ .keyboard = .{ .code = 0x1b } };

        if (b2 == '[') {
            const b3 = readByte(stdin) orelse return .{ .keyboard = .{ .code = 0x1b } };

            // Check if this might be a mouse event (SGR format starts with '<')
            if (b3 == '<') {
                // Read the rest of the mouse sequence
                var seq_buf: [32]u8 = undefined;
                seq_buf[0] = '<';
                var seq_len: usize = 1;

                while (seq_len < seq_buf.len) {
                    const next_byte = readByte(stdin) orelse break;
                    seq_buf[seq_len] = next_byte;
                    seq_len += 1;

                    // Mouse sequences end with 'M' (press) or 'm' (release)
                    if (next_byte == 'M' or next_byte == 'm') {
                        if (tryParseMouse(seq_buf[0..seq_len])) |mouse_event| {
                            return .{ .mouse = mouse_event };
                        }
                        break;
                    }
                }

                // Not a valid mouse event, treat as keyboard escape
                return .{ .keyboard = .{ .code = 0x1b } };
            }

            // Regular escape sequence (arrow keys, etc.)
            // Return as escape sequence for backward compatibility
            return .{ .keyboard = .{
                .code = 0x1b,
                .is_escape_seq = true,
                .escape_code = &.{ '[', b3 },
            } };
        }
    }

    // Regular keyboard input
    return .{ .keyboard = .{ .code = byte } };
}

/// Enable mouse tracking mode.
/// Must call this before mouse events will be sent by the terminal.
pub fn enableMouseTracking(writer: anytype, mode: mouse.TrackingMode) !void {
    try mouse.enableTracking(writer, mode);
    try writer.flush();
}

/// Disable mouse tracking mode.
pub fn disableMouseTracking(writer: anytype) !void {
    try mouse.disableTracking(writer);
    try writer.flush();
}

// ============================================================================
// Tests
// ============================================================================

test "InputEvent basic keyboard" {
    const event = InputEvent{ .keyboard = .{ .code = 'a' } };
    try std.testing.expectEqual(std.meta.Tag(InputEvent).keyboard, @as(std.meta.Tag(InputEvent), event));
}

test "InputEvent basic mouse" {
    const event = InputEvent{
        .mouse = .{
            .event_type = .press,
            .button = .left,
            .x = 10,
            .y = 5,
        },
    };
    try std.testing.expectEqual(std.meta.Tag(InputEvent).mouse, @as(std.meta.Tag(InputEvent), event));
}

test "tryParseMouse valid SGR sequence" {
    // "<0;15;8M" - left button press at (15, 8)
    const seq = "<0;15;8M";
    const event = tryParseMouse(seq);
    try std.testing.expect(event != null);
    try std.testing.expectEqual(mouse.MouseEventType.press, event.?.event_type);
    try std.testing.expectEqual(mouse.MouseButton.left, event.?.button);
    // SGR coordinates are 1-based, parseSGR converts to 0-based
    try std.testing.expectEqual(@as(u16, 14), event.?.x);
    try std.testing.expectEqual(@as(u16, 7), event.?.y);
}

test "tryParseMouse invalid sequence" {
    const seq = "invalid";
    const event = tryParseMouse(seq);
    try std.testing.expect(event == null);
}

test "tryParseMouse scroll event" {
    // "<64;15;8M" - scroll up at (15, 8)
    const seq = "<64;15;8M";
    const event = tryParseMouse(seq);
    try std.testing.expect(event != null);
    try std.testing.expectEqual(mouse.MouseEventType.scroll_up, event.?.event_type);
}
