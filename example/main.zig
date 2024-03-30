ctx: nuklear.Context,
atlas: nuklear.FontAtlas,

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

    app.atlas = nuklear.FontAtlas.initDefault();
    errdefer app.atlas.clear();
    app.atlas.begin();
    const font = app.atlas.addDefault(13, null);
    {
        const data, const width, const height = app.atlas.bake(.alpha8);

        const tex = mach.device.createTexture(&.{
            .label = "nuklear font atlas texture",
            .size = .{
                .width = width,
                .height = height,
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
                .bytes_per_row = width,
                .rows_per_image = height,
            },
            &.{
                .width = width,
                .height = height,
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
    app.atlas.end(.{ .ptr = app.atlas_bind }, null);
    app.ctx = nuklear.Context.initDefault(font.handle());
}

pub fn deinit(app: *App) void {
    app.ctx.free();
    app.atlas.clear();

    app.pipe.release();
    app.uniform_buf.release();
    app.null_bind.release();
    app.atlas_bind.release();
    app.vertex_buf.deinit();
    app.index_buf.deinit();

    mach.deinit();
}

pub fn update(app: *App) !bool {
    defer app.ctx.clear();

    // Process input
    {
        var it = mach.pollEvents();
        const in = app.ctx.input();
        defer in.end();
        while (it.next()) |event| {
            switch (event) {
                .close => return true,

                .key_press => |ev| if (nuklearKey(ev.key)) |key| {
                    in.key(key, true);
                },
                .key_release => |ev| if (nuklearKey(ev.key)) |key| {
                    in.key(key, false);
                },
                .char_input => |ev| in.unicode(ev.codepoint),

                .mouse_motion => |ev| in.motion(@intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y)),
                .mouse_press => |ev| if (nuklearButton(ev.button)) |btn| {
                    in.button(btn, @intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y), true);
                },
                .mouse_release => |ev| if (nuklearButton(ev.button)) |btn| {
                    in.button(btn, @intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y), false);
                },
                .mouse_scroll => |ev| in.scroll(.{ .x = ev.xoffset, .y = ev.yoffset }),

                else => {},
            }
        }
    }

    // Update UI
    if (app.ctx.begin("Hello", .{ .x = 0, .y = 0, .w = 100, .h = 200 }, .{
        .border = true,
        .movable = true,
        .scalable = true,
        .minimizable = true,
    })) |win| {
        defer win.end();
        win.layoutRowDynamic(30, 1);
        if (win.buttonText("Click me!")) {
            std.log.info("Hello from Nuklear!", .{});
        }
    }

    // Draw
    const cfg: nuklear.c.nk_convert_config = .{
        .shape_AA = nuklear.c.NK_ANTI_ALIASING_ON,
        .line_AA = nuklear.c.NK_ANTI_ALIASING_ON,
        .vertex_layout = &nk_vertex_layout,
        .vertex_size = vertex_size,
        .vertex_alignment = 2 * @alignOf(f32),
        .circle_segment_count = 22,
        .curve_segment_count = 22,
        .arc_segment_count = 22,
        .global_alpha = 1.0,
        .tex_null = .{
            .texture = .{ .ptr = app.null_bind },
            .uv = .{ .x = 0, .y = 0 },
        },
    };

    var cmds = nuklear.Buffer.initDefault();
    var verts = nuklear.Buffer.initDefault();
    var idx = nuklear.Buffer.initDefault();
    defer {
        cmds.free();
        verts.free();
        idx.free();
    }

    try nuklear.vertex.convert(&app.ctx, &cmds, &verts, &idx, &cfg);

    std.debug.assert(idx.size() >= verts.size());
    if (idx.size() > 0) {
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
        var it = nuklear.vertex.iterator(&app.ctx, &cmds);
        while (it.next()) |cmd| {
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

fn clampRect(rect: nuklear.Rect, size: mach.Size) struct { x: u32, y: u32, w: u32, h: u32 } {
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

fn nuklearKey(key: mach.Key) ?nuklear.Key {
    return switch (key) {
        .left_shift => .shift,
        .right_shift => .shift,
        .left_control => .ctrl,
        .right_control => .ctrl,
        .delete => .del,
        .enter => .enter,
        .kp_enter => .enter,
        .tab => .tab,
        .backspace => .backspace,
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,

        .home => .text_line_start,
        .end => .text_line_end,

        else => null,
    };
}
fn nuklearButton(btn: mach.MouseButton) ?nuklear.Button {
    return switch (btn) {
        .left => .left,
        .right => .right,
        .middle => .middle,
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

const nk_vertex_layout = [_:nuklear.vertex.layout_end]nuklear.vertex.LayoutElement{
    .{ .attribute = nuklear.c.NK_VERTEX_POSITION, .format = nuklear.c.NK_FORMAT_FLOAT, .offset = 0 },
    .{ .attribute = nuklear.c.NK_VERTEX_TEXCOORD, .format = nuklear.c.NK_FORMAT_FLOAT, .offset = @sizeOf(f32) * 2 },
    .{ .attribute = nuklear.c.NK_VERTEX_COLOR, .format = nuklear.c.NK_FORMAT_R8G8B8A8, .offset = @sizeOf(f32) * (2 + 2) },
};

const NkGpuBuf = struct {
    usage: mach.gpu.Buffer.UsageFlags,
    size: usize = 0,
    buf: ?*mach.gpu.Buffer = null,

    pub fn deinit(buf: NkGpuBuf) void {
        if (buf.buf) |b| b.release();
    }

    pub fn upload(buf: *NkGpuBuf, queue: *mach.gpu.Queue, nk_buf: *nuklear.Buffer) void {
        if (buf.size < nk_buf.size()) {
            if (buf.buf) |b| b.release();

            // Increase capacity
            while (true) {
                buf.size +|= buf.size / 2 + 8;
                if (buf.size >= nk_buf.size()) break;
            }

            // Allocate new buffer
            buf.buf = mach.device.createBuffer(&.{
                .size = buf.size,
                .usage = buf.usage,
            });
        }

        // Upload data
        const data = nk_buf.memoryConst(u8);
        queue.writeBuffer(buf.buf.?, 0, data);
    }
};

pub const App = @This();

const std = @import("std");
const mach = @import("mach").core;
const nuklear = @import("nuklear");
