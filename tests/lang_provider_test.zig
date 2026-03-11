const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test 912: C# language provider detection
test "912: init detects C# projects" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a minimal .csproj file
    const csproj_content =
        \\<Project Sdk="Microsoft.NET.Sdk">
        \\  <PropertyGroup>
        \\    <OutputType>Exe</OutputType>
        \\    <TargetFramework>net9.0</TargetFramework>
        \\  </PropertyGroup>
        \\</Project>
    ;

    try tmp.dir.writeFile(.{ .sub_path = "App.csproj", .data = csproj_content });

    // Run init --detect
    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();

    // Should succeed and generate zr.toml
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that zr.toml was created
    const toml_exists = blk: {
        tmp.dir.access("zr.toml", .{}) catch break :blk false;
        break :blk true;
    };
    try std.testing.expect(toml_exists);

    // Read generated zr.toml and verify C# tasks were added
    const toml_content = try tmp.dir.readFileAlloc(allocator, "zr.toml", 10000);
    defer allocator.free(toml_content);

    // Should contain common .NET tasks
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "dotnet build") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "dotnet test") != null);
}

// Test 913: Ruby language provider detection
test "913: init detects Ruby projects" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a minimal Gemfile
    const gemfile_content =
        \\source "https://rubygems.org"
        \\
        \\ruby "3.3.0"
        \\
        \\gem "rails", "~> 8.0"
    ;

    try tmp.dir.writeFile(.{ .sub_path = "Gemfile", .data = gemfile_content });

    // Run init --detect
    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();

    // Should succeed and generate zr.toml
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that zr.toml was created
    const toml_exists = blk: {
        tmp.dir.access("zr.toml", .{}) catch break :blk false;
        break :blk true;
    };
    try std.testing.expect(toml_exists);

    // Read generated zr.toml and verify Ruby tasks were added
    const toml_content = try tmp.dir.readFileAlloc(allocator, "zr.toml", 10000);
    defer allocator.free(toml_content);

    // Should contain common Ruby/bundler tasks
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "bundle install") != null);
}

// Test 914: C# task extraction includes all common tasks
test "914: C# provider extracts comprehensive task list" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .csproj and solution file
    const csproj_content =
        \\<Project Sdk="Microsoft.NET.Sdk">
        \\  <PropertyGroup>
        \\    <TargetFramework>net9.0</TargetFramework>
        \\  </PropertyGroup>
        \\</Project>
    ;

    const sln_content =
        \\Microsoft Visual Studio Solution File, Format Version 12.00
    ;

    try tmp.dir.writeFile(.{ .sub_path = "App.csproj", .data = csproj_content });
    try tmp.dir.writeFile(.{ .sub_path = "App.sln", .data = sln_content });

    // Run init --detect
    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify comprehensive task coverage
    const toml_content = try tmp.dir.readFileAlloc(allocator, "zr.toml", 10000);
    defer allocator.free(toml_content);

    // Core tasks
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "restore") != null);
}

// Test 915: Ruby Rails detection includes Rails-specific tasks
test "915: Ruby provider detects Rails and adds server tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create Gemfile and bin/rails
    const gemfile_content =
        \\source "https://rubygems.org"
        \\gem "rails"
    ;

    try tmp.dir.writeFile(.{ .sub_path = "Gemfile", .data = gemfile_content });
    try tmp.dir.makeDir("bin");
    try tmp.dir.writeFile(.{ .sub_path = "bin/rails", .data = "#!/usr/bin/env ruby\n" });

    // Run init --detect
    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify Rails-specific tasks
    const toml_content = try tmp.dir.readFileAlloc(allocator, "zr.toml", 10000);
    defer allocator.free(toml_content);

    // Should include Rails server task
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "rails server") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml_content, "rails console") != null);
}
