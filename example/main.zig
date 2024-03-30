ctx: c.nk_context,
atlas: c.nk_font_atlas,

pipe: *mach.gpu.RenderPipeline,
uniform_buf: *mach.gpu.Buffer,
null_bind: *mach.gpu.BindGroup,
atlas_bind: *mach.gpu.BindGroup,
vertex_buf: NkGpuBuf,
index_buf: NkGpuBuf,

pub fn init(app: *App) !void {
    try mach.init(.{});

    const shader = mach.device.createShaderModuleWGSL("nuklear.wgsl", @embedFile("nuklear.wgsl"));
    defer shader.release();

    app.pipe = mach.device.createRenderPipeline(&.{
        .label = "nuklear",
        .fragment = &mach.gpu.FragmentState.init(.{
            .module = shader,
            .entry_point = "fragment",
            .targets = &.{
                .{
                    .format = mach.descriptor.format,
                    .blend = &.{
                        .color = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
                        .alpha = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
                    },
                },
            },
        }),
        .vertex = mach.gpu.VertexState.init(.{
            .module = shader,
            .entry_point = "vertex",
            .buffers = &.{wgpu_vertex_layout},
        }),
    });
    errdefer app.pipe.release();

    app.uniform_buf = mach.device.createBuffer(&.{
        .label = "nuklear uniforms",
        .size = @sizeOf(Uniforms),
        .usage = .{ .uniform = true, .copy_dst = true },
    });
    errdefer app.uniform_buf.release();

    const sampler = mach.device.createSampler(&.{});

    // Create null texture
    {
        const tex = mach.device.createTexture(&.{
            .label = "nuklear null texture",
            .size = .{
                .width = 1,
                .height = 1,
            },
            .format = .r8_unorm,
            .usage = .{
                .texture_binding = true,
                .copy_dst = true,
            },
        });
        defer tex.release();
        mach.queue.writeTexture(
            &.{ .texture = tex },
            &.{ .bytes_per_row = 4, .rows_per_image = 1 },
            &.{ .width = 1, .height = 1 },
            &[4]u8{ 0xff, 0xff, 0xff, 0xff }, // Single white pixel
        );

        const view = tex.createView(&.{});
        defer view.release();

        app.null_bind = mach.device.createBindGroup(&mach.gpu.BindGroup.Descriptor.init(.{
            .label = "nuklear null bind group",
            .layout = app.pipe.getBindGroupLayout(0),
            .entries = &.{
                mach.gpu.BindGroup.Entry.buffer(0, app.uniform_buf, 0, @sizeOf(Uniforms)),
                mach.gpu.BindGroup.Entry.sampler(1, sampler),
                mach.gpu.BindGroup.Entry.textureView(2, view),
            },
        }));
    }

    app.vertex_buf = .{ .usage = .{ .copy_dst = true, .vertex = true } };
    app.index_buf = .{ .usage = .{ .copy_dst = true, .index = true } };

    c.nk_font_atlas_init_default(&app.atlas);
    errdefer c.nk_font_atlas_clear(&app.atlas);
    c.nk_font_atlas_begin(&app.atlas);
    const font: *c.nk_font = c.nk_font_atlas_add_default(&app.atlas, 13, null);
    {
        var width: c_int = undefined;
        var height: c_int = undefined;
        const data_ptr: [*]const u8 = @ptrCast(@alignCast(c.nk_font_atlas_bake(&app.atlas, &width, &height, c.NK_FONT_ATLAS_ALPHA8)));
        const data = data_ptr[0..@intCast(width * height)];

        const tex = mach.device.createTexture(&.{
            .label = "nuklear font atlas texture",
            .size = .{
                .width = @intCast(width),
                .height = @intCast(height),
            },
            .format = .r8_unorm,
            .usage = .{
                .texture_binding = true,
                .copy_dst = true,
            },
        });
        defer tex.release();

        mach.queue.writeTexture(
            &.{ .texture = tex },
            &.{
                .bytes_per_row = @intCast(width),
                .rows_per_image = @intCast(height),
            },
            &.{
                .width = @intCast(width),
                .height = @intCast(height),
            },
            data,
        );

        const view = tex.createView(&.{});
        defer view.release();

        app.atlas_bind = mach.device.createBindGroup(&mach.gpu.BindGroup.Descriptor.init(.{
            .label = "nuklear font atlas bind group",
            .layout = app.pipe.getBindGroupLayout(0),
            .entries = &.{
                mach.gpu.BindGroup.Entry.buffer(0, app.uniform_buf, 0, @sizeOf(Uniforms)),
                mach.gpu.BindGroup.Entry.sampler(1, sampler),
                mach.gpu.BindGroup.Entry.textureView(2, view),
            },
        }));
    }
    c.nk_font_atlas_end(&app.atlas, c.nk_handle_ptr(app.atlas_bind), null);

    if (!c.nk_init_default(&app.ctx, &font.handle)) {
        return error.NuklearInit;
    }
}

pub fn deinit(app: *App) void {
    c.nk_free(&app.ctx);
    c.nk_font_atlas_clear(&app.atlas);

    app.pipe.release();
    app.uniform_buf.release();
    app.null_bind.release();
    app.atlas_bind.release();
    app.vertex_buf.deinit();
    app.index_buf.deinit();

    mach.deinit();
}

pub fn update(app: *App) !bool {
    defer c.nk_clear(&app.ctx);

    // Process input
    var it = mach.pollEvents();
    c.nk_input_begin(&app.ctx);
    while (it.next()) |event| {
        switch (event) {
            .close => return true,

            .key_press => |ev| if (nuklearKey(ev.key)) |key| {
                c.nk_input_key(&app.ctx, key, true);
            },
            .key_release => |ev| if (nuklearKey(ev.key)) |key| {
                c.nk_input_key(&app.ctx, key, true);
            },
            .char_input => |ev| c.nk_input_unicode(&app.ctx, ev.codepoint),

            .mouse_motion => |ev| c.nk_input_motion(&app.ctx, @intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y)),
            .mouse_press => |ev| if (nuklearButton(ev.button)) |btn| {
                c.nk_input_button(&app.ctx, btn, @intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y), true);
            },
            .mouse_release => |ev| if (nuklearButton(ev.button)) |btn| {
                c.nk_input_button(&app.ctx, btn, @intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y), false);
            },
            .mouse_scroll => |ev| c.nk_input_scroll(&app.ctx, .{ .x = ev.xoffset, .y = ev.yoffset }),

            else => {},
        }
    }
    c.nk_input_end(&app.ctx);

    // Update UI
    if (c.nk_begin(
        &app.ctx,
        "Hello",
        .{ .x = 0, .y = 0, .w = 100, .h = 200 },
        c.NK_WINDOW_BORDER | c.NK_WINDOW_MOVABLE | c.NK_WINDOW_SCALABLE | c.NK_WINDOW_MINIMIZABLE,
    )) {
        c.nk_layout_row_dynamic(&app.ctx, 30, 1);
        if (c.nk_button_label(&app.ctx, "Click me!")) {
            std.log.info("Hello from Nuklear!", .{});
        }
    }
    c.nk_end(&app.ctx);

    // Draw
    const cfg: c.nk_convert_config = .{
        .shape_AA = c.NK_ANTI_ALIASING_ON,
        .line_AA = c.NK_ANTI_ALIASING_ON,
        .vertex_layout = &nk_vertex_layout,
        .vertex_size = vertex_size,
        .vertex_alignment = 2 * @alignOf(f32),
        .circle_segment_count = 22,
        .curve_segment_count = 22,
        .arc_segment_count = 22,
        .global_alpha = 1.0,
        .tex_null = .{
            .texture = c.nk_handle_ptr(app.null_bind),
            .uv = .{ .x = 0, .y = 0 },
        },
    };

    var cmds: c.nk_buffer = undefined;
    var verts: c.nk_buffer = undefined;
    var idx: c.nk_buffer = undefined;
    c.nk_buffer_init_default(&cmds);
    c.nk_buffer_init_default(&verts);
    c.nk_buffer_init_default(&idx);
    defer {
        c.nk_buffer_free(&cmds);
        c.nk_buffer_free(&verts);
        c.nk_buffer_free(&idx);
    }

    switch (c.nk_convert(&app.ctx, &cmds, &verts, &idx, &cfg)) {
        c.NK_CONVERT_SUCCESS => {},
        c.NK_CONVERT_INVALID_PARAM => unreachable,
        c.NK_CONVERT_COMMAND_BUFFER_FULL => return error.OutOfMemory,
        c.NK_CONVERT_VERTEX_BUFFER_FULL => return error.OutOfMemory,
        c.NK_CONVERT_ELEMENT_BUFFER_FULL => return error.OutOfMemory,
        else => unreachable,
    }

    std.debug.assert(idx.size >= verts.size);
    if (idx.size > 0) {
        app.vertex_buf.upload(mach.queue, &verts);
        app.index_buf.upload(mach.queue, &idx);

        const fb_size = mach.size();
        mach.queue.writeBuffer(app.uniform_buf, 0, &[1]Uniforms{.{
            .fb_size = .{
                @floatFromInt(fb_size.width),
                @floatFromInt(fb_size.height),
            },
        }});

        const enc = mach.device.createCommandEncoder(&.{});
        defer enc.release();

        const view = mach.swap_chain.getCurrentTextureView().?;

        var elem_idx: u32 = 0;
        var command: ?*const c.nk_draw_command = c.nk__draw_begin(&app.ctx, &cmds);
        while (command) |cmd| : (command = c.nk__draw_next(command, &cmds, &app.ctx)) {
            if (cmd.elem_count == 0) continue;

            const pass = enc.beginRenderPass(&mach.gpu.RenderPassDescriptor.init(.{
                .color_attachments = &.{.{
                    .view = view,
                    .load_op = if (elem_idx == 0) .clear else .load,
                    .store_op = .store,
                    .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                }},
            }));
            defer pass.end();
            pass.setPipeline(app.pipe);
            // TODO: feature-detect index format
            pass.setIndexBuffer(app.index_buf.buf.?, .uint16, 0, app.index_buf.size);
            pass.setVertexBuffer(0, app.vertex_buf.buf.?, 0, app.vertex_buf.size);
            const scissor = clampRect(cmd.clip_rect, fb_size);
            pass.setScissorRect(scissor.x, scissor.y, scissor.w, scissor.h);
            pass.setBindGroup(0, @ptrCast(cmd.texture.ptr), null);

            pass.drawIndexed(cmd.elem_count, 1, elem_idx, 0, 0);
            elem_idx += cmd.elem_count;
        }

        const cmd = enc.finish(null);
        defer cmd.release();
        mach.queue.submit(&.{cmd});
        mach.swap_chain.present();
    }

    return false;
}

const Uniforms = extern struct {
    fb_size: [2]f32 align(8),
};

fn clampRect(rect: c.struct_nk_rect, size: mach.Size) struct { x: u32, y: u32, w: u32, h: u32 } {
    const x: u32 = @intFromFloat(@max(0, rect.x));
    const y: u32 = @intFromFloat(@max(0, rect.y));
    const w: u32 = @intFromFloat(@max(0, rect.w));
    const h: u32 = @intFromFloat(@max(0, rect.h));

    return .{
        .x = @min(x, size.width),
        .y = @min(y, size.height),
        .w = @min(x +| w, size.width) -| x,
        .h = @min(y +| h, size.height) -| y,
    };
}

fn nuklearKey(key: mach.Key) ?c.nk_keys {
    return switch (key) {
        .left_shift => c.NK_KEY_SHIFT,
        .right_shift => c.NK_KEY_SHIFT,
        .left_control => c.NK_KEY_CTRL,
        .right_control => c.NK_KEY_CTRL,
        .delete => c.NK_KEY_DEL,
        .enter => c.NK_KEY_ENTER,
        .kp_enter => c.NK_KEY_ENTER,
        .tab => c.NK_KEY_TAB,
        .backspace => c.NK_KEY_BACKSPACE,
        // NK_KEY_COPY,
        // NK_KEY_CUT,
        // NK_KEY_PASTE,
        .up => c.NK_KEY_UP,
        .down => c.NK_KEY_DOWN,
        .left => c.NK_KEY_LEFT,
        .right => c.NK_KEY_RIGHT,

        // TODO: implement these actions
        // Shortcuts: text field
        // NK_KEY_TEXT_INSERT_MODE,
        // NK_KEY_TEXT_REPLACE_MODE,
        // NK_KEY_TEXT_RESET_MODE,
        .home => c.NK_KEY_TEXT_LINE_START,
        .end => c.NK_KEY_TEXT_LINE_END,
        // NK_KEY_TEXT_START,
        // NK_KEY_TEXT_END,
        // NK_KEY_TEXT_UNDO,
        // NK_KEY_TEXT_REDO,
        // NK_KEY_TEXT_SELECT_ALL,
        // NK_KEY_TEXT_WORD_LEFT,
        // NK_KEY_TEXT_WORD_RIGHT,

        // Shortcuts: scrollbar
        // NK_KEY_SCROLL_START,
        // NK_KEY_SCROLL_END,
        // NK_KEY_SCROLL_DOWN,
        // NK_KEY_SCROLL_UP,

        else => null,
    };
}
fn nuklearButton(btn: mach.MouseButton) ?c.nk_buttons {
    return switch (btn) {
        .left => c.NK_BUTTON_LEFT,
        .right => c.NK_BUTTON_RIGHT,
        .middle => c.NK_BUTTON_MIDDLE,
        // TODO: double click
        else => null,
    };
}

const vertex_size = @sizeOf([2]f32) + @sizeOf([2]f32) + @sizeOf([4]u8);
const wgpu_vertex_layout = mach.gpu.VertexBufferLayout.init(.{
    .array_stride = vertex_size,
    .attributes = &.{
        .{ .shader_location = 0, .format = .float32x2, .offset = 0 },
        .{ .shader_location = 1, .format = .float32x2, .offset = @sizeOf(f32) * 2 },
        .{ .shader_location = 2, .format = .unorm8x4, .offset = @sizeOf(f32) * (2 * 2) },
    },
});

const nk_vertex_layout = [_:vertex_layout_end]c.nk_draw_vertex_layout_element{
    .{ .attribute = c.NK_VERTEX_POSITION, .format = c.NK_FORMAT_FLOAT, .offset = 0 },
    .{ .attribute = c.NK_VERTEX_TEXCOORD, .format = c.NK_FORMAT_FLOAT, .offset = @sizeOf(f32) * 2 },
    .{ .attribute = c.NK_VERTEX_COLOR, .format = c.NK_FORMAT_R8G8B8A8, .offset = @sizeOf(f32) * (2 + 2) },
};
const vertex_layout_end: c.nk_draw_vertex_layout_element = .{
    .attribute = c.NK_VERTEX_ATTRIBUTE_COUNT,
    .format = c.NK_FORMAT_COUNT,
    .offset = 0,
};

const NkGpuBuf = struct {
    usage: mach.gpu.Buffer.UsageFlags,
    size: usize = 0,
    buf: ?*mach.gpu.Buffer = null,

    pub fn deinit(buf: NkGpuBuf) void {
        if (buf.buf) |b| b.release();
    }

    pub fn upload(buf: *NkGpuBuf, queue: *mach.gpu.Queue, nk_buf: *c.nk_buffer) void {
        if (buf.size < nk_buf.size) {
            if (buf.buf) |b| b.release();

            // Increase capacity
            while (true) {
                buf.size +|= buf.size / 2 + 8;
                if (buf.size >= nk_buf.size) break;
            }

            // Allocate new buffer
            buf.buf = mach.device.createBuffer(&.{
                .size = buf.size,
                .usage = buf.usage,
            });
        }

        // Upload data
        const data: [*]const u8 = @ptrCast(c.nk_buffer_memory_const(nk_buf));
        queue.writeBuffer(buf.buf.?, 0, data[0..nk_buf.size]);
    }
};

pub const App = @This();

const std = @import("std");
const mach = @import("mach").core;
const c = @import("nuklear").c;
