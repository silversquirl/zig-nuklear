@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var tex: texture_2d<f32>;

struct Uniforms {
    fb_size: vec2<f32>,
}

struct VertexOutput {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
}

@vertex
fn vertex(
    @location(0) pos: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) color: vec4<f32>,
) -> VertexOutput {
    let half_size = 0.5 * u.fb_size;
    let clip_pos = vec2(-half_size.x + pos.x, half_size.y - pos.y) / half_size;
    return VertexOutput(vec4(clip_pos, 0, 1), uv, color);
}

@fragment
fn fragment(@location(0) uv: vec2<f32>, @location(1) color: vec4<f32>) -> @location(0) vec4<f32> {
    return color * textureSample(tex, samp, uv).xxxx;
}
