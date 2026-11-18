#version 440
// The reader's flying picture (ClipReader's morph overlay), drawn at its exact
// fractional box: the rounded rect is cut analytically and antialiased over one
// pixel, on a quad two pixels larger than the box, so an edge 0.3px into a pixel
// covers 30% of it. A clip rect or a scissor rasterises the box edges onto pixel
// boundaries instead, and a picture creeping the last few pixels home moves in
// whole-pixel steps.
//
// Two textures, as MorphPicture had two Images: the row's thumbnail under, the
// full decode faded over it (fullOpacity), both cropped to the box like
// Image.PreserveAspectCrop, over the container colour.
//
// Filtering. The picture is drawn smaller than its texture for most of a
// morph, at a scale that changes every frame. One bilinear tap per pixel
// skips texels at any scale under 1 -- fine text, 1px lines and checkers
// alias into moire that rearranges itself as the scale changes: the shimmer
// he saw on open and close (measured against an area-averaged downscale of
// the source: error jumping 6 -> 15 -> 6 frame to frame). So the full decode
// is AREA-averaged: an n x n grid of taps across each pixel's footprint
// (n up to 4, the scale's own ceiling), each tap through textureGrad with the
// footprint divided by n, so beyond 4x the mip chain takes the remainder.
// At 1:1 -- resting in the body -- it is one tap, exactly a plain sample.
//
// The thumbnail is the row's own picture, drawn by the row with ONE bilinear
// tap, and the handoff to the row must not change a pixel. So it is sampled
// the row's way at the row's size and area-averaged only as the box grows
// away from it (thumbArea, 0 at the slot -> 1 at 1.5x the slot).
// Rebuild from repo root: /usr/lib/qt6/bin/qsb --glsl "300 es,150" --hlsl 50 --msl 12 -o modules/launcher/shaders/morphpic.frag.qsb modules/launcher/shaders/morphpic.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // the effect item, px
    vec4 box;           // the picture: x, y, w, h in the item, px
    float radius;       // corner radius, px
    float thumbOpacity; // 0 until the thumbnail has decoded
    float fullOpacity;  // the full decode's fade over it
    vec4 bg;            // container colour (opaque)
    vec2 thumbCrop;     // fraction of each texture axis the box shows
    vec2 fullCrop;
    float thumbArea;    // 0: the row's single tap; 1: area-averaged
};
layout(binding = 1) uniform sampler2D thumb;
layout(binding = 2) uniform sampler2D full;

// Area average of `tex` over this pixel's footprint around uv.
vec4 area(sampler2D tex, vec2 uv, vec2 gx, vec2 gy) {
    vec2 size = vec2(textureSize(tex, 0));
    float fpx = max(abs(gx.x * size.x), abs(gy.x * size.x));
    float fpy = max(abs(gx.y * size.y), abs(gy.y * size.y));
    int nx = int(clamp(ceil(fpx - 1e-3), 1.0, 4.0));
    int ny = int(clamp(ceil(fpy - 1e-3), 1.0, 4.0));
    vec2 sx = gx / float(nx);
    vec2 sy = gy / float(ny);
    vec4 sum = vec4(0.0);
    for (int j = 0; j < ny; j++) {
        for (int i = 0; i < nx; i++) {
            vec2 o = (float(i) + 0.5 - 0.5 * float(nx)) * sx + (float(j) + 0.5 - 0.5 * float(ny)) * sy;
            sum += textureGrad(tex, uv + o, sx, sy);
        }
    }
    return sum / float(nx * ny);
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 half_ = box.zw * 0.5;
    vec2 c = box.xy + half_;
    float r = min(radius, min(half_.x, half_.y));
    vec2 q = abs(p - c) - (half_ - vec2(r));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float cover = clamp(0.5 - d, 0.0, 1.0);

    // Not clamped before the derivatives are taken: a clamped coordinate has
    // no footprint at the box edge. Clamped where the textures are read.
    vec2 n = (p - box.xy) / box.zw;
    vec2 tu = 0.5 + (n - 0.5) * thumbCrop;
    vec2 fu = 0.5 + (n - 0.5) * fullCrop;
    vec2 tgx = dFdx(tu), tgy = dFdy(tu);
    vec2 fgx = dFdx(fu), fgy = dFdy(fu);
    vec2 tc = clamp(tu, 0.0, 1.0);
    vec2 fc = clamp(fu, 0.0, 1.0);

    vec4 col = bg;
    vec4 t = mix(textureLod(thumb, tc, 0.0), area(thumb, tc, tgx, tgy), thumbArea) * thumbOpacity;
    col = t + col * (1.0 - t.a);
    vec4 f = area(full, fc, fgx, fgy) * fullOpacity;
    col = f + col * (1.0 - f.a);
    fragColor = col * cover * qt_Opacity;
}
