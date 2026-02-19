const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // Link libc on non-Windows targets for setenv(3) in builtin_env.zig.
            // Windows targets don't have bundled MSVC libc in Zig's cross-compiler.
            .link_libc = if (target.result.os.tag != .windows) true else null,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);

    // --- Integration Tests ---
    // Build options: inject binary path for integration tests
    const opts = b.addOptions();
    opts.addOption([]const u8, "zr_bin_path", "zig-out/bin/zr");

    const int_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    int_tests.root_module.addOptions("build_options", opts);

    const run_int_tests = b.addRunArtifact(int_tests);
    run_int_tests.step.dependOn(b.getInstallStep()); // ensures zr binary is built first

    const integration_step = b.step("integration-test", "Run integration tests");
    integration_step.dependOn(&run_int_tests.step);
}
