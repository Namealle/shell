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
// Rebuild from repo root: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o modules/launcher/shaders/morphpic.frag.qsb modules/launcher/shaders/morphpic.frag

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
};
layout(binding = 1) uniform sampler2D thumb;
layout(binding = 2) uniform sampler2D full;

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 half_ = box.zw * 0.5;
    vec2 c = box.xy + half_;
    float r = min(radius, min(half_.x, half_.y));
    vec2 q = abs(p - c) - (half_ - vec2(r));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float cover = clamp(0.5 - d, 0.0, 1.0);

    vec2 n = clamp((p - box.xy) / box.zw, 0.0, 1.0);
    vec4 col = bg;
    vec4 t = texture(thumb, 0.5 + (n - 0.5) * thumbCrop) * thumbOpacity;
    col = t + col * (1.0 - t.a);
    vec4 f = texture(full, 0.5 + (n - 0.5) * fullCrop) * fullOpacity;
    col = f + col * (1.0 - f.a);
    fragColor = col * cover * qt_Opacity;
}
