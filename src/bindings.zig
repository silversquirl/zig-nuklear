//! Zig bindings for Nuklear

pub const feature = struct {
    pub const default_allocator = @hasDecl(c, "NK_INCLUDE_DEFAULT_ALLOCATOR");
    pub const vertex_backend = @hasDecl(c, "NK_VERTEX_BUFFER_OUTPUT");
    pub const font_baking = @hasDecl(c, "NK_INCLUDE_FONT_BAKING");
    pub const default_font = @hasDecl(c, "NK_INCLUDE_DEFAULT_FONT");
    pub const userdata = @hasDecl(c, "NK_INCLUDE_COMMAND_USERDATA");
    pub const button_trigger_on_release = @hasDecl(c, "NK_BUTTON_TRIGGER_ON_RELEASE");
    pub const zero_command_memory = @hasDecl(c, "NK_ZERO_COMMAND_MEMORY");
    pub const draw_index_32bit = @hasDecl(c, "NK_UINT_DRAW_INDEX");
    pub const keystate_based_input = @hasDecl(c, "NK_KEYSTATE_BASED_INPUT");
};

const std = @import("std");
pub const c = @cImport({
    @cInclude("nuklear.h");
});
