pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const link_libc = b.option(bool, "link_libc", "Use libc for memory allocation, string formatting, and loading files") orelse false;

    const config = b.addConfigHeader(.{}, .{
        // These are always available, regardless of whether libc is linked
        .NK_INCLUDE_FIXED_TYPES = {},
        .NK_INCLUDE_STANDARD_VARARGS = {},
        .NK_INCLUDE_STANDARD_BOOL = {},

        // These require libc
        .NK_INCLUDE_DEFAULT_ALLOCATOR = if (link_libc) {} else null,
        .NK_INCLUDE_STANDARD_IO = if (link_libc) {} else null,

        // Configurable features
        .NK_INCLUDE_VERTEX_BUFFER_OUTPUT = boolOption(b, "vertex_backend", "Enable the vertex draw command list backend"),
        .NK_INCLUDE_FONT_BAKING = boolOption(b, "font_baking", "Enable font baking and rendering"),
        .NK_INCLUDE_DEFAULT_FONT = boolOption(b, "default_font", "Include the default font (ProggyClean.ttf)"),
        .NK_INCLUDE_COMMAND_USERDATA = boolOption(b, "userdata", "Add a userdata pointer into each command"),
        .NK_BUTTON_TRIGGER_ON_RELEASE = boolOption(b, "button_trigger_on_release", "Trigger buttons when released, instead of pressed"),
        .NK_ZERO_COMMAND_MEMORY = boolOption(b, "zero_command_memory", "Zero out memory for each drawing command added to a drawing queue"),
        .NK_UINT_DRAW_INDEX = boolOption(b, "draw_index_32bit", "Use 32-bit vertex index elements, instead of 16-bit (requires vertex_backend)"),
        .NK_KEYSTATE_BASED_INPUT = boolOption(b, "keystate_based_input", "Use key state for each frame rather than key press/release events"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "nuklear",
        .root_source_file = .{ .path = "src/nuklear.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addConfigHeader(config);
    lib.addIncludePath(.{ .path = "src" });
    lib.addCSourceFile(.{
        .file = .{ .path = "src/nuklear.c" },
        .flags = &.{ "-std=c11", "-Wall", "-Werror", "-Wno-unused-function" },
    });
    if (link_libc) lib.linkLibC();
    b.installArtifact(lib);

    const mod = b.addModule("nuklear", .{
        .root_source_file = .{ .path = "src/bindings.zig" },
    });
    mod.addConfigHeader(config);
    mod.addIncludePath(.{ .path = "src" });
    mod.linkLibrary(lib);

    const test_step = b.addTest(.{
        .root_source_file = .{ .path = "src/bindings.zig" },
    });
    test_step.linkLibrary(lib);
    b.getInstallStep().dependOn(&b.addRunArtifact(test_step).step);
}

// Returns ?void rather than bool because ConfigHeader is silly
fn boolOption(b: *std.Build, name: []const u8, desc: []const u8) ?void {
    const value = b.option(bool, name, desc) orelse false;
    return if (value) {} else null;
}

const std = @import("std");
