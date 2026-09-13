// Offscreen renderer for blackhole-preview.frag. Surfaceless EGL + llvmpipe
// (LIBGL_ALWAYS_SOFTWARE=1) so no window, no GPU and no Quickshell instance is
// needed. QT_QPA_PLATFORM=offscreen renders ShaderEffect black and
// QT_QUICK_BACKEND=software does not render it at all, which is why this exists.
//
// Build:  cc -O2 -o bhrender bhrender.c -lEGL -lGL -lm
// Usage:  bhrender <frag.glsl> <W> <H> <uniforms.txt> <out.f32> [tex1.raw tex2.raw]
//
// uniforms.txt: one "name v0 [v1 v2 v3 ...]" per line (up to 16 floats). Offsets
// come from the live program via glGetActiveUniformsiv, so the std140 layout is
// never hand-computed here.
// tex*.raw: "W H\n" ASCII header then W*H*4 RGBA8 bytes. tex1 -> binding 1
// (nearest), tex2 -> binding 2 (linear). Binding 4 gets a 1x1 black dummy.
// out.f32: W*H*4 little-endian float32 RGBA, row 0 = top.
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GLFN(r, n, a) typedef r(*PFN_##n) a; static PFN_##n p_##n;
GLFN(GLuint, glCreateShader, (GLenum))
GLFN(void, glShaderSource, (GLuint, GLsizei, const char *const *, const GLint *))
GLFN(void, glCompileShader, (GLuint))
GLFN(void, glGetShaderiv, (GLuint, GLenum, GLint *))
GLFN(void, glGetShaderInfoLog, (GLuint, GLsizei, GLsizei *, char *))
GLFN(GLuint, glCreateProgram, (void))
GLFN(void, glAttachShader, (GLuint, GLuint))
GLFN(void, glLinkProgram, (GLuint))
GLFN(void, glGetProgramiv, (GLuint, GLenum, GLint *))
GLFN(void, glGetProgramInfoLog, (GLuint, GLsizei, GLsizei *, char *))
GLFN(void, glUseProgram, (GLuint))
GLFN(void, glGenVertexArrays, (GLsizei, GLuint *))
GLFN(void, glBindVertexArray, (GLuint))
GLFN(void, glGenBuffers, (GLsizei, GLuint *))
GLFN(void, glBindBuffer, (GLenum, GLuint))
GLFN(void, glBufferData, (GLenum, GLsizeiptr, const void *, GLenum))
GLFN(void, glBindBufferBase, (GLenum, GLuint, GLuint))
GLFN(void, glGetUniformIndices, (GLuint, GLsizei, const char *const *, GLuint *))
GLFN(void, glGetActiveUniformsiv, (GLuint, GLsizei, const GLuint *, GLenum, GLint *))
GLFN(void, glGenFramebuffers, (GLsizei, GLuint *))
GLFN(void, glBindFramebuffer, (GLenum, GLuint))
GLFN(void, glFramebufferTexture2D, (GLenum, GLenum, GLenum, GLuint, GLint))
GLFN(GLenum, glCheckFramebufferStatus, (GLenum))
GLFN(void, glActiveTexture, (GLenum))

static void loadgl(void) {
#define L(n) p_##n = (PFN_##n)eglGetProcAddress(#n)
    L(glCreateShader); L(glShaderSource); L(glCompileShader); L(glGetShaderiv);
    L(glGetShaderInfoLog); L(glCreateProgram); L(glAttachShader); L(glLinkProgram);
    L(glGetProgramiv); L(glGetProgramInfoLog); L(glUseProgram); L(glGenVertexArrays);
    L(glBindVertexArray); L(glGenBuffers); L(glBindBuffer); L(glBufferData);
    L(glBindBufferBase); L(glGetUniformIndices); L(glGetActiveUniformsiv);
    L(glGenFramebuffers); L(glBindFramebuffer); L(glFramebufferTexture2D);
    L(glCheckFramebufferStatus); L(glActiveTexture);
#undef L
}

static char *slurp(const char *path, long *len) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "open %s failed\n", path); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc(n + 1);
    if (fread(b, 1, n, f) != (size_t)n) { fprintf(stderr, "read %s failed\n", path); exit(2); }
    b[n] = 0; fclose(f);
    if (len) *len = n;
    return b;
}

static GLuint compile(GLenum type, const char *src, const char *tag) {
    GLuint s = p_glCreateShader(type);
    p_glShaderSource(s, 1, &src, NULL);
    p_glCompileShader(s);
    GLint ok = 0; p_glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[16384]; p_glGetShaderInfoLog(s, sizeof log, NULL, log);
        fprintf(stderr, "%s compile failed:\n%s\n", tag, log); exit(3);
    }
    return s;
}

static GLuint loadtex(const char *path, GLint filter, int unit) {
    long n; char *raw = slurp(path, &n);
    int w = 0, h = 0, off = 0;
    sscanf(raw, "%d %d%n", &w, &h, &off);
    while (raw[off] == ' ' || raw[off] == '\n') off++;
    GLuint t; glGenTextures(1, &t);
    p_glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D, t);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, raw + off);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
    free(raw);
    return t;
}

static const char *VERT =
    "#version 450 core\n"
    "layout(location = 0) out vec2 qt_TexCoord0;\n"
    "void main(){\n"
    "  vec2 p = vec2((gl_VertexID<<1)&2, gl_VertexID&2);\n"
    "  qt_TexCoord0 = vec2(p.x, 1.0-p.y);\n"
    "  gl_Position = vec4(p*2.0-1.0, 0.0, 1.0);\n"
    "}\n";

int main(int argc, char **argv) {
    if (argc < 6) { fprintf(stderr, "usage: %s frag W H uniforms out [tex1 tex2]\n", argv[0]); return 1; }
    int W = atoi(argv[2]), H = atoi(argv[3]);

    static const EGLint cfgattr[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                                     EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE};
    static const EGLint ctxattr[] = {EGL_CONTEXT_MAJOR_VERSION, 4,
                                     EGL_CONTEXT_MINOR_VERSION, 5,
                                     EGL_CONTEXT_OPENGL_PROFILE_MASK,
                                     EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE};
    EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (dpy == EGL_NO_DISPLAY) { fprintf(stderr, "no EGL display\n"); return 4; }
    if (!eglInitialize(dpy, NULL, NULL)) { fprintf(stderr, "eglInitialize failed\n"); return 4; }
    eglBindAPI(EGL_OPENGL_API);
    EGLConfig cfg; EGLint nc = 0;
    eglChooseConfig(dpy, cfgattr, &cfg, 1, &nc);
    EGLContext ctx = eglCreateContext(dpy, nc ? cfg : EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ctxattr);
    if (ctx == EGL_NO_CONTEXT) { fprintf(stderr, "eglCreateContext failed 0x%x\n", eglGetError()); return 4; }
    if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
        fprintf(stderr, "eglMakeCurrent failed 0x%x\n", eglGetError()); return 4;
    }
    loadgl();

    char *frag = slurp(argv[1], NULL);
    GLuint prog = p_glCreateProgram();
    p_glAttachShader(prog, compile(GL_VERTEX_SHADER, VERT, "vert"));
    p_glAttachShader(prog, compile(GL_FRAGMENT_SHADER, frag, argv[1]));
    p_glLinkProgram(prog);
    GLint ok = 0; p_glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) { char log[16384]; p_glGetProgramInfoLog(prog, sizeof log, NULL, log);
               fprintf(stderr, "link failed:\n%s\n", log); return 3; }
    p_glUseProgram(prog);

    // Uniform block: ask the driver where each member lives.
    GLint blockSize = 0;
    {
        GLuint idx = 0;
        typedef GLuint (*PFN_gubi)(GLuint, const char *);
        PFN_gubi gubi = (PFN_gubi)eglGetProcAddress("glGetUniformBlockIndex");
        typedef void (*PFN_gaubiv)(GLuint, GLuint, GLenum, GLint *);
        PFN_gaubiv gaubiv = (PFN_gaubiv)eglGetProcAddress("glGetActiveUniformBlockiv");
        idx = gubi(prog, "buf");
        if (idx == GL_INVALID_INDEX) { fprintf(stderr, "no uniform block 'buf'\n"); return 3; }
        gaubiv(prog, idx, GL_UNIFORM_BLOCK_DATA_SIZE, &blockSize);
    }
    unsigned char *ubo = calloc(1, blockSize);

    long ulen; char *utxt = slurp(argv[4], &ulen);
    for (char *line = strtok(utxt, "\n"); line; line = strtok(NULL, "\n")) {
        char name[128]; float v[16]; int n = 0, off = 0;
        if (sscanf(line, "%127s%n", name, &off) != 1 || name[0] == '#') continue;
        char *q = line + off;
        while (n < 16 && sscanf(q, "%f%n", &v[n], &off) == 1) { n++; q += off; }
        if (!n) continue;
        char full[192]; snprintf(full, sizeof full, "buf.%s", name);
        const char *names[2] = {full, name};
        GLuint index = GL_INVALID_INDEX; GLint offset = -1, stride = 0;
        for (int t = 0; t < 2 && index == GL_INVALID_INDEX; t++)
            p_glGetUniformIndices(prog, 1, &names[t], &index);
        if (index == GL_INVALID_INDEX) { fprintf(stderr, "note: %s not active (dropped)\n", name); continue; }
        p_glGetActiveUniformsiv(prog, 1, &index, GL_UNIFORM_OFFSET, &offset);
        p_glGetActiveUniformsiv(prog, 1, &index, GL_UNIFORM_MATRIX_STRIDE, &stride);
        if (offset < 0) continue;
        if (stride > 0 && n == 16) {                       // mat4, column-major
            for (int c = 0; c < 4; c++)
                memcpy(ubo + offset + c * stride, v + c * 4, 16);
        } else {
            memcpy(ubo + offset, v, n * sizeof(float));
        }
    }
    GLuint ub; p_glGenBuffers(1, &ub);
    p_glBindBuffer(GL_UNIFORM_BUFFER, ub);
    p_glBufferData(GL_UNIFORM_BUFFER, blockSize, ubo, GL_STATIC_DRAW);
    p_glBindBufferBase(GL_UNIFORM_BUFFER, 0, ub);

    if (argc >= 8) { loadtex(argv[6], GL_NEAREST, 1); loadtex(argv[7], GL_LINEAR, 2); }
    {   // binding 4 dummy so the sampler is never undefined
        GLuint t; unsigned char px[4] = {0, 0, 0, 255};
        glGenTextures(1, &t); p_glActiveTexture(GL_TEXTURE4); glBindTexture(GL_TEXTURE_2D, t);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }

    GLuint fbo, col;
    p_glGenFramebuffers(1, &fbo);
    p_glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenTextures(1, &col);
    p_glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, col);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, W, H, 0, GL_RGBA, GL_FLOAT, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, col, 0);
    if (p_glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "incomplete FBO\n"); return 5;
    }

    GLuint vao; p_glGenVertexArrays(1, &vao); p_glBindVertexArray(vao);
    glViewport(0, 0, W, H);
    glDisable(GL_BLEND); glDisable(GL_DEPTH_TEST);
    glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glFinish();

    float *px = malloc((size_t)W * H * 4 * sizeof(float));
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, W, H, GL_RGBA, GL_FLOAT, px);
    GLenum err = glGetError();
    if (err) fprintf(stderr, "GL error 0x%x\n", err);
    FILE *out = fopen(argv[5], "wb");
    // glReadPixels row 0 is the BOTTOM; flip so row 0 is the top (Qt order).
    for (int y = H - 1; y >= 0; y--) fwrite(px + (size_t)y * W * 4, sizeof(float), (size_t)W * 4, out);
    fclose(out);
    fprintf(stderr, "rendered %dx%d, ubo %d bytes\n", W, H, blockSize);
    return 0;
}
