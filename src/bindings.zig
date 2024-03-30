//! Zig bindings for Nuklear

// TODO: fully wrap the whole API

pub const Context = extern struct {
    c: c.nk_context,

    pub fn initDefault(font: *const UserFont) Context {
        if (!feature.default_allocator) {
            @compileError("`initDefault` requires default allocator. Pass `.link_libc = true` in nuklear build options");
        }

        var ctx: c.nk_context = undefined;
        // The "failure" that Nuklear's documentation talks about can only ever be due to invalid args
        std.debug.assert(c.nk_init_default(&ctx, font));
        return .{ .c = ctx };
    }

    // TODO: other init functions

    pub fn free(ctx: *Context) void {
        c.nk_free(&ctx.c);
    }

    pub fn clear(ctx: *Context) void {
        c.nk_clear(&ctx.c);
    }

    /// Begin processing input
    pub fn input(ctx: *Context) Input {
        c.nk_input_begin(&ctx.c);
        return .{ .ctx = &ctx.c };
    }

    pub const Input = struct {
        ctx: *c.nk_context,

        pub fn end(in: Input) void {
            c.nk_input_end(in.ctx);
        }

        pub fn motion(in: Input, x: u31, y: u31) void {
            c.nk_input_motion(in.ctx, x, y);
        }

        pub fn key(in: Input, k: Key, pressed: bool) void {
            c.nk_input_key(in.ctx, @intFromEnum(k), pressed);
        }

        pub fn button(in: Input, b: Button, x: u31, y: u31, pressed: bool) void {
            c.nk_input_button(in.ctx, @intFromEnum(b), x, y, pressed);
        }

        pub fn scroll(in: Input, val: Vec2) void {
            c.nk_input_scroll(in.ctx, val);
        }

        pub fn char(in: Input, ch: u8) void {
            c.nk_input_char(in.ctx, ch);
        }

        pub fn glyph(in: Input, g: [c.NK_UTF_SIZE]u8) void {
            c.nk_input_glyph(in.ctx, g);
        }

        pub fn unicode(in: Input, codepoint: u21) void {
            c.nk_input_unicode(in.ctx, codepoint);
        }
    };

    pub fn begin(ctx: *Context, name: [:0]const u8, rect: Rect, flags: Window.Flags) ?Window {
        if (c.nk_begin(&ctx.c, name.ptr, rect, @bitCast(flags))) {
            return .{ .ctx = &ctx.c };
        } else {
            c.nk_end(&ctx.c);
            return null;
        }
    }

    pub const Window = struct {
        pub const Flags = packed struct(c.nk_panel_flags) {
            border: bool = false,
            movable: bool = false,
            scalable: bool = false,
            closable: bool = false,
            minimizable: bool = false,
            no_scrollbar: bool = false,
            title: bool = false,
            scroll_auto_hide: bool = false,
            background: bool = false,
            scale_left: bool = false,
            no_input: bool = false,

            _pad: u21 = 0,
        };

        ctx: *c.nk_context,

        pub fn end(win: Window) void {
            c.nk_end(win.ctx);
        }

        // TODO: namespace layout functions so it's `win.layout.rowDynamic` etc instead of `win.layoutRowDynamic`?
        pub fn layoutRowDynamic(win: Window, height: f32, cols: u31) void {
            c.nk_layout_row_dynamic(win.ctx, height, cols);
        }
        pub fn layoutRowStatic(win: Window, height: f32, item_width: u31, cols: u31) void {
            c.nk_layout_row_static(win.ctx, height, item_width, cols);
        }
        // TODO: more layout functions

        pub fn buttonText(win: Window, text: []const u8) bool {
            return c.nk_button_text(win.ctx, text.ptr, @intCast(text.len));
        }
    };
};

pub const Font = extern struct {
    c: c.nk_font,

    pub fn handle(f: *const Font) *const UserFont {
        return &f.c.handle;
    }
};

pub const FontAtlas = extern struct {
    c: c.nk_font_atlas,

    pub fn initDefault() FontAtlas {
        if (!feature.default_allocator) {
            @compileError("`initDefault` requires default allocator. Pass `.link_libc = true` in nuklear build options.");
        }

        var atlas: c.nk_font_atlas = undefined;
        c.nk_font_atlas_init_default(&atlas);
        return .{ .c = atlas };
    }

    // TODO: other init functions

    pub fn clear(atlas: *FontAtlas) void {
        c.nk_font_atlas_clear(&atlas.c);
    }

    pub fn begin(atlas: *FontAtlas) void {
        c.nk_font_atlas_begin(&atlas.c);
    }

    pub fn end(atlas: *FontAtlas, tex: Handle, null_tex: ?*NullTexture) void {
        c.nk_font_atlas_end(&atlas.c, tex, null_tex);
    }

    pub fn addDefault(atlas: *FontAtlas, size: f32, config: ?*FontConfig) *Font {
        if (!feature.default_font) {
            @compileError("`addDefault` requires default font. Pass `.default_font = true` in nuklear build options.");
        }

        const font = c.nk_font_atlas_add_default(&atlas.c, size, config);
        return @fieldParentPtr(Font, "c", font);
    }

    pub fn bake(atlas: *FontAtlas, comptime format: Format) struct { []const format.Pixel(), u31, u31 } {
        var width: c_int = undefined;
        var height: c_int = undefined;
        const data = c.nk_font_atlas_bake(&atlas.c, &width, &height, @intFromEnum(format));

        const uwidth: u31 = @intCast(width);
        const uheight: u31 = @intCast(height);
        const pixels_ptr: [*]const format.Pixel() = @ptrCast(@alignCast(data));
        return .{ pixels_ptr[0 .. uwidth * uheight], uwidth, uheight };
    }

    pub const Format = enum(c.nk_font_atlas_format) {
        alpha8 = c.NK_FONT_ATLAS_ALPHA8,
        rgba32 = c.NK_FONT_ATLAS_RGBA32,

        pub fn Pixel(format: Format) type {
            return switch (format) {
                .alpha8 => u8,
                .rgba32 => [4]u8,
            };
        }
    };
};

pub const Buffer = struct {
    c: c.nk_buffer,

    pub fn initDefault() Buffer {
        if (!feature.default_allocator) {
            @compileError("`initDefault` requires default allocator. Pass `.link_libc = true` in nuklear build options.");
        }

        var buf: c.nk_buffer = undefined;
        c.nk_buffer_init_default(&buf);
        return .{ .c = buf };
    }

    // TODO: other init functions

    pub fn free(buf: *Buffer) void {
        c.nk_buffer_free(&buf.c);
    }

    pub fn clear(buf: *Buffer) void {
        c.nk_buffer_clear(&buf.c);
    }

    pub inline fn size(buf: Buffer) usize {
        return buf.c.size;
    }

    pub fn memory(buf: *const Buffer, comptime T: type) []T {
        const ptr: [*]align(@alignOf(T)) u8 = @ptrCast(@alignCast(c.nk_buffer_memory(&buf.c)));
        return std.mem.bytesAsSlice(T, ptr[0..buf.size()]);
    }
    pub fn memoryConst(buf: *const Buffer, comptime T: type) []const T {
        const ptr: [*]align(@alignOf(T)) const u8 = @ptrCast(@alignCast(c.nk_buffer_memory_const(&buf.c)));
        return std.mem.bytesAsSlice(T, ptr[0..buf.size()]);
    }
};

pub const Key = enum(c.nk_keys) {
    none = c.NK_KEY_NONE,
    shift = c.NK_KEY_SHIFT,
    ctrl = c.NK_KEY_CTRL,
    del = c.NK_KEY_DEL,
    enter = c.NK_KEY_ENTER,
    tab = c.NK_KEY_TAB,
    backspace = c.NK_KEY_BACKSPACE,
    copy = c.NK_KEY_COPY,
    cut = c.NK_KEY_CUT,
    paste = c.NK_KEY_PASTE,
    up = c.NK_KEY_UP,
    down = c.NK_KEY_DOWN,
    left = c.NK_KEY_LEFT,
    right = c.NK_KEY_RIGHT,

    // Shortcuts: text field
    text_insert_mode = c.NK_KEY_TEXT_INSERT_MODE,
    text_replace_mode = c.NK_KEY_TEXT_REPLACE_MODE,
    text_reset_mode = c.NK_KEY_TEXT_RESET_MODE,
    text_line_start = c.NK_KEY_TEXT_LINE_START,
    text_line_end = c.NK_KEY_TEXT_LINE_END,
    text_start = c.NK_KEY_TEXT_START,
    text_end = c.NK_KEY_TEXT_END,
    text_undo = c.NK_KEY_TEXT_UNDO,
    text_redo = c.NK_KEY_TEXT_REDO,
    text_select_all = c.NK_KEY_TEXT_SELECT_ALL,
    text_word_left = c.NK_KEY_TEXT_WORD_LEFT,
    text_word_right = c.NK_KEY_TEXT_WORD_RIGHT,

    // Shortcuts: scrollbar
    scroll_start = c.NK_KEY_SCROLL_START,
    scroll_end = c.NK_KEY_SCROLL_END,
    scroll_down = c.NK_KEY_SCROLL_DOWN,
    scroll_up = c.NK_KEY_SCROLL_UP,
};

pub const Button = enum(c.nk_buttons) {
    left = c.NK_BUTTON_LEFT,
    middle = c.NK_BUTTON_MIDDLE,
    right = c.NK_BUTTON_RIGHT,
    double = c.NK_BUTTON_DOUBLE,
};

pub const Handle = c.nk_handle;
pub const Vec2 = c.struct_nk_vec2;
pub const Rect = c.struct_nk_rect;
pub const UserFont = c.nk_user_font;
pub const FontConfig = c.struct_nk_font_config;
pub const NullTexture = c.nk_draw_null_texture;

pub const vertex = struct {
    comptime {
        if (!feature.vertex_backend) {
            @compileError("Nuklear vertex backend is not enabled. Pass `.vertex_backend = true` in nuklear build options.");
        }
    }

    pub fn convert(ctx: *Context, cmds: *Buffer, verts: *Buffer, elems: *Buffer, cfg: *const ConvertConfig) error{OutOfMemory}!void {
        switch (c.nk_convert(&ctx.c, &cmds.c, &verts.c, &elems.c, cfg)) {
            c.NK_CONVERT_SUCCESS => {},
            c.NK_CONVERT_INVALID_PARAM => unreachable,
            c.NK_CONVERT_COMMAND_BUFFER_FULL => return error.OutOfMemory,
            c.NK_CONVERT_VERTEX_BUFFER_FULL => return error.OutOfMemory,
            c.NK_CONVERT_ELEMENT_BUFFER_FULL => return error.OutOfMemory,
            else => unreachable,
        }
    }

    pub fn iterator(ctx: *Context, cmds: *Buffer) CommandIterator {
        return .{ .ctx = &ctx.c, .buf = &cmds.c };
    }

    pub const CommandIterator = struct {
        ctx: *c.nk_context,
        buf: *c.nk_buffer,
        first: bool = true,
        cmd: ?*const Command = undefined,

        pub fn next(it: *CommandIterator) ?*const Command {
            while (true) {
                if (it.first) {
                    it.cmd = c.nk__draw_begin(it.ctx, it.buf);
                    it.first = false;
                } else {
                    it.cmd = c.nk__draw_next(it.cmd, it.buf, it.ctx);
                }

                if (it.cmd) |cmd| {
                    if (cmd.elem_count > 0) {
                        return it.cmd;
                    }
                } else {
                    return null;
                }
            }
        }
    };

    // TODO: wrap this to make it nicer
    pub const ConvertConfig = c.nk_convert_config;

    // TODO: wrap this
    pub const LayoutElement = c.nk_draw_vertex_layout_element;
    pub const layout_end: LayoutElement = .{
        .attribute = c.NK_VERTEX_ATTRIBUTE_COUNT,
        .format = c.NK_FORMAT_COUNT,
        .offset = 0,
    };

    pub const Command = c.nk_draw_command;
};

pub const feature = struct {
    pub const default_allocator = @hasDecl(c, "NK_INCLUDE_DEFAULT_ALLOCATOR");
    pub const vertex_backend = @hasDecl(c, "NK_INCLUDE_VERTEX_BUFFER_OUTPUT");
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
pub const mach = @import("mach.zig");
