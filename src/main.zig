const std = @import("std");

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll("zr v0.0.4 - Zig Task Runner\n");
}

test "basic functionality" {
    try std.testing.expect(true);
}
