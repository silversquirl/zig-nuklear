pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        .core = true,
    });

    const nuk_dep = b.dependency("nuklear", .{
        .target = target,
        .optimize = optimize,

        .link_libc = true,
        .vertex_backend = true,
        .font_baking = true,
        .default_font = true,
    });
    const nuk_mod = nuk_dep.module("nuklear");
    // This is a little bit cheeky, but it allows the nuklear bindings to work with a variety of mach versions
    nuk_mod.addImport("mach", mach_dep.module("mach"));

    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "nuklear-example",
        .src = "main.zig",
        .target = target,
        .optimize = optimize,
        .deps = &.{
            .{ .name = "nuklear", .module = nuk_mod },
        },
        .mach_mod = mach_dep.module("mach"),
    });
    if (b.args) |args| app.run.addArgs(args);
    b.step("run", "Run the example").dependOn(&app.run.step);
}

const std = @import("std");
const mach = @import("mach");
