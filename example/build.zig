pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nuk_dep = b.dependency("nuklear", .{
        .target = target,
        .optimize = optimize,

        .link_libc = true,
        .vertex_backend = true,
        .font_baking = true,
        .default_font = true,
    });

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        .core = true,
    });
    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "nuklear-example",
        .src = "main.zig",
        .target = target,
        .optimize = optimize,
        .deps = &.{
            .{ .name = "nuklear", .module = nuk_dep.module("nuklear") },
        },
    });
    if (b.args) |args| app.run.addArgs(args);
    b.step("run", "Run the example").dependOn(&app.run.step);
}

const std = @import("std");
const mach = @import("mach");
