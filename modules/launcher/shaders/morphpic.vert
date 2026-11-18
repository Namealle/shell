#version 440
// Qt's default ShaderEffect vertex stage, compiled here only so the pipeline
// has a GLSL ES 3.0 version in common with morphpic.frag (which needs
// textureGrad/textureSize -- not in ES 1.0, the default stage's only ES).
// Rebuild from repo root: /usr/lib/qt6/bin/qsb --glsl "300 es,150" --hlsl 50 --msl 12 -o modules/launcher/shaders/morphpic.vert.qsb modules/launcher/shaders/morphpic.vert

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 box;
    float radius;
    float thumbOpacity;
    float fullOpacity;
    vec4 bg;
    vec2 thumbCrop;
    vec2 fullCrop;
    float thumbArea;
};

out gl_PerVertex { vec4 gl_Position; };

void main() {
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
