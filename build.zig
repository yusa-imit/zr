const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options
    const target = b.standardTargetOptions(.{});

    // Standard optimization options
    const optimize = b.standardOptimizeOption(.{});

    // Create an executable for the default target
    const exe = b.addExecutable(.{
        .name = "zr",
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = "src/main.zig",
        } },
        .target = target,
        .optimize = optimize,
    });

    // Install step for default target
    const install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install.step);

    // Add test step
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = "src/main.zig",
        } },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Create release build step
    const release_step = b.step("release", "Create release builds for all targets");

    // Cross compilation target configurations
    const targets = [_]struct {
        query: std.Target.Query,
        name: []const u8,
    }{
        .{
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .msvc,
            },
            .name = "x86_64-windows",
        },
        .{
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .name = "x86_64-linux",
        },
        .{
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .macos,
                .abi = .none,
            },
            .name = "x86_64-macos",
        },
        .{
            .query = .{
                .cpu_arch = .aarch64,
                .os_tag = .macos,
                .abi = .none,
            },
            .name = "aarch64-macos",
        },
    };

    for (targets) |t| {
        // Resolve the target
        const resolved_target = b.resolveTargetQuery(t.query);

        const target_exe = b.addExecutable(.{
            .name = b.fmt("zr-{s}", .{t.name}),
            .root_source_file = .{ .src_path = .{
                .owner = b,
                .sub_path = "src/main.zig",
            } },
            .target = resolved_target,
            .optimize = .ReleaseSafe,
        });

        // Configure installation with custom path
        const target_install = b.addInstallArtifact(target_exe, .{});
        target_install.dest_sub_path = if (t.query.os_tag == .windows)
            b.fmt("bin/zr-{s}.exe", .{t.name})
        else
            b.fmt("bin/zr-{s}", .{t.name});

        release_step.dependOn(&target_install.step);
    }
}
