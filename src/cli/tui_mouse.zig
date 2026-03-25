/// Mouse input integration for TUI modes.
///
/// Provides utilities to enable/disable mouse tracking and parse mouse events
/// from stdin alongside keyboard input. Integrates sailor.tui.mouse with existing
/// TUI implementations.

const std = @import("std");
const builtin = @import("builtin");
const sailor = @import("sailor");
const mouse = sailor.tui.mouse;

const IS_POSIX = builtin.os.tag != .windows;

// Windows-specific imports for console API
const windows = if (!IS_POSIX) std.os.windows else struct {};
const HANDLE = if (!IS_POSIX) windows.HANDLE else void;
const DWORD = if (!IS_POSIX) windows.DWORD else void;

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

/// Event batcher for reducing UI redraws during rapid mouse movement.
/// Accumulates multiple mouse move events and only reports the latest position.
pub const EventBatcher = struct {
    last_move: ?mouse.MouseEvent = null,
    last_move_time: i64 = 0,
    batch_interval_ms: u64,

    const Self = @This();

    pub fn init(batch_interval_ms: u64) Self {
        return .{
            .batch_interval_ms = batch_interval_ms,
        };
    }

    /// Add an event to the batcher. Returns true if the event should be processed immediately.
    /// For mouse move events, batches them and only returns true when batch interval expires.
    pub fn addEvent(self: *Self, event: InputEvent, current_time_ms: i64) bool {
        switch (event) {
            .mouse => |m| {
                // Batch mouse move events
                if (m.event_type == .move or m.event_type == .drag) {
                    const time_since_last = current_time_ms - self.last_move_time;
                    self.last_move = m;

                    if (time_since_last >= self.batch_interval_ms) {
                        self.last_move_time = current_time_ms;
                        return true; // Emit batched event
                    }
                    return false; // Buffer this event
                }
                // Other mouse events (click, scroll) are not batched
                return true;
            },
            else => return true, // Keyboard and other events are not batched
        }
    }

    /// Get the last batched move event if any.
    pub fn getLastMove(self: *Self) ?mouse.MouseEvent {
        defer self.last_move = null;
        return self.last_move;
    }
};

/// Double-click detector with configurable timeout.
pub const DoubleClickDetector = struct {
    last_click: ?ClickInfo = null,
    max_interval_ms: u64,
    max_distance: u16,

    const ClickInfo = struct {
        x: u16,
        y: u16,
        button: mouse.MouseButton,
        time_ms: i64,
    };

    const Self = @This();

    pub fn init(max_interval_ms: u64, max_distance: u16) Self {
        return .{
            .max_interval_ms = max_interval_ms,
            .max_distance = max_distance,
        };
    }

    /// Check if a click event is a double-click.
    /// Returns true if this click is the second click of a double-click.
    pub fn isDoubleClick(self: *Self, event: mouse.MouseEvent, current_time_ms: i64) bool {
        if (event.event_type != .press) return false;

        if (self.last_click) |last| {
            const time_diff = current_time_ms - last.time_ms;
            const dx = if (event.x > last.x) event.x - last.x else last.x - event.x;
            const dy = if (event.y > last.y) event.y - last.y else last.y - event.y;
            const distance = @max(dx, dy);

            const is_double = time_diff <= self.max_interval_ms and
                distance <= self.max_distance and
                event.button == last.button;

            if (is_double) {
                self.last_click = null; // Reset after double-click
                return true;
            }
        }

        // Record this click for next comparison
        self.last_click = .{
            .x = event.x,
            .y = event.y,
            .button = event.button,
            .time_ms = current_time_ms,
        };
        return false;
    }

    /// Reset the detector (e.g., when changing views).
    pub fn reset(self: *Self) void {
        self.last_click = null;
    }
};

/// Terminal state for non-blocking input
const TerminalState = if (IS_POSIX) struct {
    original: std.posix.termios,
    stdin: std.fs.File,
} else struct {
    stdin: std.fs.File,
    original_mode: DWORD,
    timeout_ms: u64,
};

/// Enter non-blocking mode with timeout.
/// Returns state that must be restored with leaveNonBlockingMode().
fn enterNonBlockingMode(stdin: std.fs.File, timeout_ms: u64) !TerminalState {
    if (comptime IS_POSIX) {
        const original = try std.posix.tcgetattr(stdin.handle);
        var raw = original;

        // Non-blocking read with timeout
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0; // Don't wait for any characters
        raw.cc[@intFromEnum(std.posix.V.TIME)] = @intCast(@min(255, (timeout_ms + 99) / 100)); // Convert ms to deciseconds (tenths of a second)

        try std.posix.tcsetattr(stdin.handle, .NOW, raw);
        return .{ .original = original, .stdin = stdin };
    } else {
        // Windows: Get current console mode to restore later
        var original_mode: DWORD = 0;
        const handle = stdin.handle;

        const kernel32 = windows.kernel32;
        if (kernel32.GetConsoleMode(handle, &original_mode) == 0) {
            return error.GetConsoleModeFailure;
        }

        // Enable mouse input for Windows console
        const ENABLE_MOUSE_INPUT: DWORD = 0x0010;
        const ENABLE_EXTENDED_FLAGS: DWORD = 0x0080;
        const new_mode = original_mode | ENABLE_MOUSE_INPUT | ENABLE_EXTENDED_FLAGS;

        if (kernel32.SetConsoleMode(handle, new_mode) == 0) {
            return error.SetConsoleModeFailure;
        }

        return .{ .stdin = stdin, .original_mode = original_mode, .timeout_ms = timeout_ms };
    }
}

/// Restore terminal to original mode.
fn leaveNonBlockingMode(state: TerminalState) void {
    if (comptime IS_POSIX) {
        std.posix.tcsetattr(state.stdin.handle, .NOW, state.original) catch {};
    } else {
        const kernel32 = windows.kernel32;
        _ = kernel32.SetConsoleMode(state.stdin.handle, state.original_mode);
    }
}

/// Read a single byte from stdin without blocking (POSIX version).
/// Returns null on timeout, EOF, or error.
fn readBytePosix(stdin: std.fs.File) ?u8 {
    var buf: [1]u8 = undefined;
    const n = stdin.read(&buf) catch return null;
    if (n == 0) return null;
    return buf[0];
}

/// Read a single byte from stdin with timeout (Windows version).
/// Returns null on timeout, EOF, or error.
fn readByteWindows(stdin: std.fs.File, timeout_ms: u64) ?u8 {
    const handle = stdin.handle;
    const kernel32 = windows.kernel32;

    // Wait for input with timeout
    const WAIT_OBJECT_0: DWORD = 0;
    const WAIT_TIMEOUT: DWORD = 0x00000102;
    const wait_result = kernel32.WaitForSingleObject(handle, @intCast(timeout_ms));

    if (wait_result == WAIT_TIMEOUT) {
        return null; // Timeout
    }

    if (wait_result != WAIT_OBJECT_0) {
        return null; // Error
    }

    // Check if input is available
    var events_read: DWORD = 0;
    var input_record: windows.INPUT_RECORD = undefined;

    if (kernel32.PeekConsoleInputW(handle, @ptrCast(&input_record), 1, &events_read) == 0) {
        return null;
    }

    if (events_read == 0) {
        return null;
    }

    // Read the input record
    if (kernel32.ReadConsoleInputW(handle, @ptrCast(&input_record), 1, &events_read) == 0) {
        return null;
    }

    // Only handle keyboard events for now (mouse events require different handling)
    const KEY_EVENT: u16 = 0x0001;
    if (input_record.EventType == KEY_EVENT) {
        const key_event = input_record.Event.KeyEvent;
        if (key_event.bKeyDown != 0 and key_event.uChar.AsciiChar != 0) {
            return @intCast(key_event.uChar.AsciiChar);
        }
    }

    // Not a valid character event
    return null;
}

/// Read a single byte from stdin without blocking.
/// Returns null on timeout, EOF, or error.
fn readByte(stdin: std.fs.File, timeout_ms: u64) ?u8 {
    if (comptime IS_POSIX) {
        return readBytePosix(stdin);
    } else {
        return readByteWindows(stdin, timeout_ms);
    }
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
    _ = allocator;

    // Enter non-blocking mode with timeout
    const state = try enterNonBlockingMode(stdin, timeout_ms);
    defer leaveNonBlockingMode(state);

    const byte = readByte(stdin, timeout_ms) orelse return .none;

    // Check for escape sequence (both keyboard and mouse)
    if (byte == 0x1b) {
        const b2 = readByte(stdin, timeout_ms) orelse return .{ .keyboard = .{ .code = 0x1b } };

        if (b2 == '[') {
            const b3 = readByte(stdin, timeout_ms) orelse return .{ .keyboard = .{ .code = 0x1b } };

            // Check if this might be a mouse event (SGR format starts with '<')
            if (b3 == '<') {
                // Read the rest of the mouse sequence
                var seq_buf: [32]u8 = undefined;
                seq_buf[0] = '<';
                var seq_len: usize = 1;

                while (seq_len < seq_buf.len) {
                    const next_byte = readByte(stdin, timeout_ms) orelse break;
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

test "EventBatcher: mouse move events batched" {
    var batcher = EventBatcher.init(100); // 100ms batch interval

    const move_event1 = InputEvent{ .mouse = .{
        .event_type = .move,
        .button = .left,
        .x = 10,
        .y = 10,
    } };

    const move_event2 = InputEvent{ .mouse = .{
        .event_type = .move,
        .button = .left,
        .x = 15,
        .y = 15,
    } };

    // First event should be buffered
    const should_process1 = batcher.addEvent(move_event1, 0);
    try std.testing.expect(!should_process1);

    // Second event within batch interval should also be buffered
    const should_process2 = batcher.addEvent(move_event2, 50);
    try std.testing.expect(!should_process2);

    // Event after batch interval should be processed
    const should_process3 = batcher.addEvent(move_event2, 150);
    try std.testing.expect(should_process3);

    // Last move should be available
    const last_move = batcher.getLastMove();
    try std.testing.expect(last_move != null);
    try std.testing.expectEqual(@as(u16, 15), last_move.?.x);
    try std.testing.expectEqual(@as(u16, 15), last_move.?.y);
}

test "EventBatcher: click events not batched" {
    var batcher = EventBatcher.init(100);

    const click_event = InputEvent{ .mouse = .{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 10,
    } };

    // Click events should always be processed immediately
    const should_process = batcher.addEvent(click_event, 0);
    try std.testing.expect(should_process);
}

test "EventBatcher: keyboard events not batched" {
    var batcher = EventBatcher.init(100);

    const key_event = InputEvent{ .keyboard = .{ .code = 'a' } };

    // Keyboard events should always be processed immediately
    const should_process = batcher.addEvent(key_event, 0);
    try std.testing.expect(should_process);
}

test "DoubleClickDetector: detects double-click" {
    var detector = DoubleClickDetector.init(300, 5); // 300ms, 5px distance

    const click1 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 10,
    };

    const click2 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 11,
        .y = 11,
    };

    // First click is not a double-click
    const is_double1 = detector.isDoubleClick(click1, 0);
    try std.testing.expect(!is_double1);

    // Second click within interval and distance is a double-click
    const is_double2 = detector.isDoubleClick(click2, 200);
    try std.testing.expect(is_double2);

    // After double-click, state is reset
    const last_click = detector.last_click;
    try std.testing.expect(last_click == null);
}

test "DoubleClickDetector: rejects clicks too far apart in time" {
    var detector = DoubleClickDetector.init(300, 5);

    const click1 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 10,
    };

    const click2 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 11,
        .y = 11,
    };

    _ = detector.isDoubleClick(click1, 0);

    // Second click too late (400ms > 300ms)
    const is_double = detector.isDoubleClick(click2, 400);
    try std.testing.expect(!is_double);

    // State should be updated to click2
    const last_click = detector.last_click;
    try std.testing.expect(last_click != null);
    try std.testing.expectEqual(@as(u16, 11), last_click.?.x);
}

test "DoubleClickDetector: rejects clicks too far apart in distance" {
    var detector = DoubleClickDetector.init(300, 5);

    const click1 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 10,
    };

    const click2 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 20,
        .y = 20,
    };

    _ = detector.isDoubleClick(click1, 0);

    // Second click too far (10px > 5px)
    const is_double = detector.isDoubleClick(click2, 200);
    try std.testing.expect(!is_double);
}

test "DoubleClickDetector: rejects different buttons" {
    var detector = DoubleClickDetector.init(300, 5);

    const click1 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 10,
    };

    const click2 = mouse.MouseEvent{
        .event_type = .press,
        .button = .right,
        .x = 11,
        .y = 11,
    };

    _ = detector.isDoubleClick(click1, 0);

    // Second click with different button
    const is_double = detector.isDoubleClick(click2, 200);
    try std.testing.expect(!is_double);
}

test "DoubleClickDetector: reset clears state" {
    var detector = DoubleClickDetector.init(300, 5);

    const click1 = mouse.MouseEvent{
        .event_type = .press,
        .button = .left,
        .x = 10,
        .y = 10,
    };

    _ = detector.isDoubleClick(click1, 0);
    try std.testing.expect(detector.last_click != null);

    detector.reset();
    try std.testing.expect(detector.last_click == null);
}
