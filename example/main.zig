ctx: nuklear.Context,
atlas: nuklear.FontAtlas,
draw: nuklear.mach.Draw,

pub fn init(app: *App) !void {
    try mach.init(.{});

    app.atlas = nuklear.FontAtlas.initDefault();
    errdefer app.atlas.clear();
    app.atlas.begin();
    const font = app.atlas.addDefault(13, null);

    app.draw = nuklear.mach.Draw.init(.{
        .device = mach.device,
        .queue = mach.queue,
        .target_format = mach.descriptor.format,
        .atlas_to_bake = &app.atlas,
    });
    app.ctx = nuklear.Context.initDefault(font.handle());
}

pub fn deinit(app: *App) void {
    app.ctx.free();
    app.atlas.clear();
    app.draw.deinit();

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
            nuklear.mach.event(in, event);
            switch (event) {
                .close => return true,

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
    const view = mach.swap_chain.getCurrentTextureView().?;
    defer view.release();
    try app.draw.draw(.{
        .device = mach.device,
        .queue = mach.queue,
        .ctx = &app.ctx,
        .framebuffer_size = mach.size(),
        .target = view,
    });
    mach.swap_chain.present();

    return false;
}

pub const App = @This();

const std = @import("std");
const mach = @import("mach").core;
const nuklear = @import("nuklear");
