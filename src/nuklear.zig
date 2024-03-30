//! Zig implementations of functions required by Nuklear

comptime {
    // 2 plus 2 is 4, minus 1 that's 3 quick maths
    @setFloatMode(.Optimized);
}

export fn zig_nuklear_assert(x: bool) void {
    if (!x) unreachable;
}

export fn zig_nuklear_memset(s: [*]u8, c: c_int, n: usize) [*]u8 {
    @memset(s[0..n], @intCast(c));
    return s;
}

export fn zig_nuklear_memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    @memcpy(dest[0..n], src[0..n]);
    return dest;
}

export fn zig_nuklear_inv_sqrt(x: f32) f32 {
    return 1.0 / @sqrt(x);
}

export fn zig_nuklear_sin(x: f32) f32 {
    return @sin(x);
}

export fn zig_nuklear_cos(x: f32) f32 {
    return @cos(x);
}
