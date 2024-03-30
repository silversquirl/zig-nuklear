//! mach-core integration for Nuklear

pub fn event(in: nuklear.Context.Input, event_: core.Event) void {
    switch (event_) {
        .key_press => |ev| if (mapKey(ev.key)) |key| {
            in.key(key, true);
        },
        .key_release => |ev| if (mapKey(ev.key)) |key| {
            in.key(key, false);
        },
        .char_input => |ev| in.unicode(ev.codepoint),

        .mouse_motion => |ev| in.motion(@intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y)),
        .mouse_press => |ev| if (mapButton(ev.button)) |btn| {
            in.button(btn, @intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y), true);
        },
        .mouse_release => |ev| if (mapButton(ev.button)) |btn| {
            in.button(btn, @intFromFloat(ev.pos.x), @intFromFloat(ev.pos.y), false);
        },
        .mouse_scroll => |ev| in.scroll(.{ .x = ev.xoffset, .y = ev.yoffset }),

        else => {},
    }
}
fn mapKey(key: core.Key) ?nuklear.Key {
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

        // TODO: shortcuts

        else => null,
    };
}
fn mapButton(btn: core.MouseButton) ?nuklear.Button {
    return switch (btn) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        // TODO: double click
        else => null,
    };
}

pub const Draw = struct {
    pipe: *gpu.RenderPipeline,
    uniform_buf: *gpu.Buffer,
    null_bind: *gpu.BindGroup,
    atlas_bind: *gpu.BindGroup,
    vertex_buf: NkGpuBuf = .{ .usage = .{ .copy_dst = true, .vertex = true } },
    index_buf: NkGpuBuf = .{ .usage = .{ .copy_dst = true, .index = true } },

    cmds: nuklear.Buffer,
    verts: nuklear.Buffer,
    idx: nuklear.Buffer,

    pub const InitOptions = struct {
        device: *gpu.Device,
        queue: *gpu.Queue,
        target_format: gpu.Texture.Format,
        atlas_to_bake: *nuklear.FontAtlas,
    };
    pub const DrawOptions = struct {
        device: *gpu.Device,
        queue: *gpu.Queue,
        ctx: *nuklear.Context,
        framebuffer_size: core.Size,
        target: *gpu.TextureView,
    };

    pub fn init(
        opts: InitOptions,
    ) Draw {
        const shader = opts.device.createShaderModuleWGSL("nuklear.wgsl", @embedFile("nuklear.wgsl"));
        defer shader.release();

        const pipe = opts.device.createRenderPipeline(&.{
            .label = "nuklear",
            .fragment = &gpu.FragmentState.init(.{
                .module = shader,
                .entry_point = "fragment",
                .targets = &.{
                    .{
                        .format = opts.target_format,
                        .blend = &.{
                            .color = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
                            .alpha = .{ .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
                        },
                    },
                },
            }),
            .vertex = gpu.VertexState.init(.{
                .module = shader,
                .entry_point = "vertex",
                .buffers = &.{wgpu_vertex_layout},
            }),
        });

        const uniform_buf = opts.device.createBuffer(&.{
            .label = "nuklear uniforms",
            .size = @sizeOf(Uniforms),
            .usage = .{ .uniform = true, .copy_dst = true },
        });

        const sampler = opts.device.createSampler(&.{});

        // Create null texture
        const null_bind = blk: {
            const tex = opts.device.createTexture(&.{
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
            opts.queue.writeTexture(
                &.{ .texture = tex },
                &.{ .bytes_per_row = 4, .rows_per_image = 1 },
                &.{ .width = 1, .height = 1 },
                &[4]u8{ 0xff, 0xff, 0xff, 0xff }, // Single white pixel
            );

            const view = tex.createView(&.{});
            defer view.release();

            break :blk opts.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
                .label = "nuklear null bind group",
                .layout = pipe.getBindGroupLayout(0),
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, uniform_buf, 0, @sizeOf(Uniforms)),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                    gpu.BindGroup.Entry.textureView(2, view),
                },
            }));
        };

        // Bake font atlas
        const atlas_bind = blk: {
            const data, const width, const height = opts.atlas_to_bake.bake(.alpha8);

            const tex = opts.device.createTexture(&.{
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

            opts.queue.writeTexture(
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

            break :blk opts.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
                .label = "nuklear font atlas bind group",
                .layout = pipe.getBindGroupLayout(0),
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, uniform_buf, 0, @sizeOf(Uniforms)),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                    gpu.BindGroup.Entry.textureView(2, view),
                },
            }));
        };

        opts.atlas_to_bake.end(.{ .ptr = atlas_bind }, null);

        return .{
            .pipe = pipe,
            .uniform_buf = uniform_buf,
            .null_bind = null_bind,
            .atlas_bind = atlas_bind,

            .cmds = nuklear.Buffer.initDefault(),
            .verts = nuklear.Buffer.initDefault(),
            .idx = nuklear.Buffer.initDefault(),
        };
    }

    pub fn deinit(state: *Draw) void {
        state.pipe.release();
        state.uniform_buf.release();
        state.null_bind.release();
        state.atlas_bind.release();

        state.vertex_buf.deinit();
        state.index_buf.deinit();

        state.cmds.free();
        state.verts.free();
        state.idx.free();
    }

    pub fn draw(state: *Draw, opts: DrawOptions) error{OutOfMemory}!void {
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
                .texture = .{ .ptr = state.null_bind },
                .uv = .{ .x = 0, .y = 0 },
            },
        };

        try nuklear.vertex.convert(opts.ctx, &state.cmds, &state.verts, &state.idx, &cfg);
        defer {
            state.cmds.clear();
            state.verts.clear();
            state.idx.clear();
        }

        std.debug.assert(state.idx.size() >= state.verts.size());
        if (state.idx.size() > 0) {
            state.vertex_buf.upload(opts.device, opts.queue, &state.verts);
            state.index_buf.upload(opts.device, opts.queue, &state.idx);

            opts.queue.writeBuffer(state.uniform_buf, 0, &[1]Uniforms{.{
                .fb_size = .{
                    @floatFromInt(opts.framebuffer_size.width),
                    @floatFromInt(opts.framebuffer_size.height),
                },
            }});

            const enc = opts.device.createCommandEncoder(&.{});
            defer enc.release();

            var elem_idx: u32 = 0;
            var it = nuklear.vertex.iterator(opts.ctx, &state.cmds);
            while (it.next()) |cmd| {
                const pass = enc.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
                    .color_attachments = &.{.{
                        .view = opts.target,
                        .load_op = if (elem_idx == 0) .clear else .load,
                        .store_op = .store,
                        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                    }},
                }));
                defer pass.end();
                pass.setPipeline(state.pipe);
                const index_format: gpu.IndexFormat = if (nuklear.feature.draw_index_32bit) .uint32 else .uint16;
                pass.setIndexBuffer(state.index_buf.buf.?, index_format, 0, state.index_buf.size);
                pass.setVertexBuffer(0, state.vertex_buf.buf.?, 0, state.vertex_buf.size);
                const scissor = clampRect(cmd.clip_rect, opts.framebuffer_size);
                pass.setScissorRect(scissor.x, scissor.y, scissor.w, scissor.h);
                pass.setBindGroup(0, @ptrCast(cmd.texture.ptr), null);

                pass.drawIndexed(cmd.elem_count, 1, elem_idx, 0, 0);
                elem_idx += cmd.elem_count;
            }

            const cmd = enc.finish(null);
            defer cmd.release();
            opts.queue.submit(&.{cmd});
        }
    }

    const Uniforms = extern struct {
        fb_size: [2]f32 align(8),
    };

    fn clampRect(rect: nuklear.Rect, size: core.Size) struct { x: u32, y: u32, w: u32, h: u32 } {
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

    const vertex_size = @sizeOf([2]f32) + @sizeOf([2]f32) + @sizeOf([4]u8);
    const wgpu_vertex_layout = gpu.VertexBufferLayout.init(.{
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
        usage: gpu.Buffer.UsageFlags,
        size: usize = 0,
        buf: ?*gpu.Buffer = null,

        pub fn deinit(buf: NkGpuBuf) void {
            if (buf.buf) |b| b.release();
        }

        pub fn upload(
            buf: *NkGpuBuf,
            device: *gpu.Device,
            queue: *gpu.Queue,
            nk_buf: *nuklear.Buffer,
        ) void {
            if (buf.size < nk_buf.size()) {
                if (buf.buf) |b| b.release();

                // Increase capacity
                while (true) {
                    buf.size +|= buf.size / 2 + 8;
                    if (buf.size >= nk_buf.size()) break;
                }

                // Allocate new buffer
                buf.buf = device.createBuffer(&.{
                    .size = buf.size,
                    .usage = buf.usage,
                });
            }

            // Upload data
            const data = nk_buf.memoryConst(u8);
            queue.writeBuffer(buf.buf.?, 0, data);
        }
    };
};

const std = @import("std");
const gpu = @import("mach").gpu;
const core = @import("mach").core;
const nuklear = @import("bindings.zig");
