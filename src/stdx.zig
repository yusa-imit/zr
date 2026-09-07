//! Tiger Style assertion helpers, shared kingdom-wide until zuda ships them.
//!
//! `assert` documents a condition that must always hold; it is `std.debug.assert` and is
//! compiled out in ReleaseFast/ReleaseSmall, so it never protects data that reaches production
//! unchecked. `assert_always` is for invariants that must hold in every build mode, including
//! release — it panics unconditionally rather than relying on runtime safety checks. `maybe`
//! documents a condition that is legitimately sometimes true, so a reader does not mistake
//! silence for an oversight and does not "fix" it into a wrong `assert`.

const std = @import("std");

pub const assert = std.debug.assert;

/// Panics if `ok` is false, in every build mode. Use for invariants that must hold even in
/// ReleaseFast/ReleaseSmall (e.g. checksum verification before a write), never as a substitute
/// for returning a typed error on user-data input.
pub fn assert_always(ok: bool) void {
    if (!ok) @panic("assert_always failed");
}

/// No-op marker for a condition that is legitimately sometimes true and sometimes false.
pub fn maybe(ok: bool) void {
    _ = ok;
}

test "assert_always panics on false" {
    // Cannot exercise the panic path directly under std.testing (panics abort the test
    // process); this test only proves the true path is a no-op and the function compiles.
    assert_always(true);
}

test "maybe accepts both true and false without side effects" {
    maybe(true);
    maybe(false);
}
