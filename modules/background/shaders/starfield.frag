#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 camera;
    vec2 cameraCentre;
    float phaseTime;
    float density;
    float twinkle;
    float flareFraction;
    float brightness;
    vec4 skyColor;
    float edgeLift;
    vec4 meteorHead;
    vec3 meteorShape;
    vec4 companionHead;
    vec3 companionShape;
    vec4 cometHead;
    vec3 cometShape;
    vec4 satelliteHead;
} ubuf;

// No textures, sine hash or finite star catalogue. Each layer evaluates one cell.
vec4 hash4(vec2 p) {
    vec4 p4 = fract(vec4(p.xy, p.xy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

vec2 rotate(vec2 p, float c, float s) {
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

vec3 stars(vec2 pixel, float scale, float layer) {
    float nearLayer = step(1.5, layer);
    float middleLayer = step(0.5, layer);
    float displayScale = max(1.0, sqrt(ubuf.resolution.x * ubuf.resolution.y / (1024.0 * 576.0)));
    float optics = mix(1.0, displayScale, nearLayer);
    float cellSize = mix(12.0, 30.0, middleLayer);
    cellSize = mix(cellSize, 110.0, nearLayer) * scale;
    float depth = mix(0.10, 0.42, middleLayer);
    depth = mix(depth, 1.0, nearLayer);

    // Independent, incommensurate grids; neither the grid nor stars tile on screen.
    float angle = 0.37 + layer * 1.23;
    float c = cos(angle), s = sin(angle);
    vec2 centre = ubuf.cameraCentre * ubuf.resolution;
    float zoom = exp(ubuf.camera.z * depth);
    float turn = ubuf.camera.w * depth;
    float cameraC = cos(turn), cameraS = sin(turn);
    vec2 samplePoint = rotate(pixel - centre, cameraC, -cameraS) / zoom + centre;
    samplePoint -= ubuf.camera.xy * displayScale * depth;
    vec2 world = rotate(samplePoint, c, s) + vec2(137.2, 931.7) * (layer + 1.0);
    vec2 cell = floor(world / cellSize);
    vec4 h = hash4(cell + layer * vec2(173.17, 319.43));
    if (h.w > mix(0.76, 0.68, nearLayer))
        return vec3(0.0);

    // Support stays INSIDE the owning cell: no neighbour loop and no seam popping.
    float support = mix(3.5, 6.0, middleLayer);
    support = min(mix(support, 42.0 * optics, nearLayer), cellSize * 0.46);
    vec2 position = support + 1.0 + h.xy * (cellSize - 2.0 * (support + 1.0));
    vec2 delta = world - (cell * cellSize + position);
    delta *= zoom;
    float r2 = dot(delta, delta);
    support *= zoom;
    if (r2 > support * support)
        return vec3(0.0);

    // Undo the grid rotation: diffraction crosses stay aligned to the display.
    vec2 p = rotate(rotate(delta, c, -s), cameraC, cameraS);
    float variation = fract(h.z * 37.19);
    float phase = h.z * 6.28318530718;
    float tauTime = ubuf.phaseTime * (6.28318530718 / 4096.0);
    float cycles = floor(mix(370.0, 990.0, variation));
    float slow = sin(tauTime * floor(mix(31.0, 83.0, h.z)) + phase * 2.3);
    float pulse = sin(tauTime * cycles + phase + 0.55 * slow);
    float shimmer = 1.0 + ubuf.twinkle * (0.60 * pulse + 0.28 * sin(tauTime * floor(mix(193.0, 431.0, h.w)) + phase * 1.7));
    // Unsynchronised 0.5–1.5 s glints, with variable strength, on a minority.
    if (variation > 0.78) {
        float glint = pow(max(0.0, sin(tauTime * floor(mix(63.0, 181.0, h.z)) + phase * 3.7)), 48.0);
        shimmer += ubuf.twinkle * glint * (0.8 + 0.6 * slow);
    }
    // A few background stars dissolve over tens of seconds; no frame randomness.
    float visibility = variation > 0.96 && nearLayer == 0.0 ? smoothstep(0.03, 0.65, 0.5 + 0.5 * slow) : 1.0;

    // Dust never scales with the screen: its faintest peaks remain perceptible.
    float sigma = mix(0.44, 0.56, h.z) + middleLayer * 0.12;
    sigma = mix(sigma, mix(1.0, 1.4, h.z) * optics, nearLayer);
    float energy = mix(0.32, 1.28, h.z * h.z);
    energy *= mix(1.0, 1.35, middleLayer);
    energy = mix(energy, mix(1.8, 2.8, h.z), nearLayer);
    // Pixel footprint convolved with the point spread: stable subpixel movement.
    float variance = sigma * sigma + 0.0833333;
    float core = exp2(-0.7213475 * r2 / variance) * sigma * sigma / variance;
    float halo = middleLayer * 0.024 * exp2(-r2 / (mix(3.5, 14.0, nearLayer) * optics * optics));
    float light = (core + halo) * energy * shimmer;

    // Keep the foreground population fixed when increasing the dust population.
    float flare = nearLayer * (1.0 - step(ubuf.flareFraction * 85.0, variation));
    if (nearLayer > 0.0 && flare == 0.0) {
        // A capped hot point plus redistributed light in a broad Gaussian halo.
        // The shoulder approaches white smoothly instead of clipping a wide core
        // into a flat disc. Sigma and convolution are in physical pixels.
        float hotSigma = min(2.5, optics * mix(0.55, 0.68, h.z));
        float hotVariance = hotSigma * hotSigma + 0.0833333;
        float hot = exp2(-0.7213475 * r2 / hotVariance) * hotSigma * hotSigma / hotVariance;
        float soft = exp2(-r2 / (26.0 * optics * optics));
        light = 1.0 - exp(-(3.2 * hot + 0.085 * soft) * shimmer);
    }
    if (flare > 0.0) {
        float breath = 1.0 + ubuf.twinkle * 0.45 * pulse;
        vec2 a = abs(p) / optics;
        float length = mix(28.0, 35.0, h.z) * breath;
        vec2 taper = max(vec2(0.0), 1.0 - a / length);
        taper *= taper;
        vec2 thin = exp2(-a * a / 0.38);
        vec2 skirt = exp2(-a * a / 2.0);
        float cross = dot(thin, taper.yx) * 0.48 + dot(skirt, taper.yx) * 0.10;
        float glowR2 = r2 / (optics * optics);
        float glow = 0.10 * exp2(-glowR2 / 12.0) + 0.030 * exp2(-glowR2 / 125.0);
        light += (cross + glow) * breath;
    }

    // Compact support reaches zero smoothly before a cell boundary can clip it.
    light *= 1.0 - smoothstep(support * support * 0.64, support * support, r2);
    vec3 tint = mix(vec3(0.73, 0.84, 1.0), vec3(1.0, 0.98, 0.94), h.z);
    return light * tint * visibility;
}

// CPU-computed deterministic event geometry; uniform branches skip idle events.
// Every distance and the anti-alias footprint are in physical pixels.
vec3 streak(vec2 pixel, vec4 head, vec3 shape, bool slowComet) {
    if (head.w <= 0.0)
        return vec3(0.0);
    vec2 p = pixel - head.xy;
    float along = -dot(p, shape.xy);
    float across = dot(p, vec2(-shape.y, shape.x));
    float extent = shape.z * (slowComet ? 14.0 : 6.0);
    if (along < -extent || along > head.z + extent || abs(across) > extent)
        return vec3(0.0);
    float u = clamp(along / max(head.z, 1.0), 0.0, 1.0);
    float width = shape.z * (slowComet ? 1.8 + 8.0 * u : 1.0 - 0.65 * u);
    float variance = width * width + 0.0833333;
    float tail = exp2(-0.7213475 * across * across / variance) * width / sqrt(variance);
    tail *= smoothstep(-shape.z, shape.z, along) * pow(1.0 - u, slowComet ? 1.6 : 2.0);
    float coreVariance = shape.z * shape.z + 0.0833333;
    float r2 = dot(p, p);
    float hot = exp2(-0.7213475 * r2 / coreVariance) * shape.z * shape.z / coreVariance;
    float glow = exp2(-r2 / (shape.z * shape.z * (slowComet ? 32.0 : 6.0)));
    vec3 nucleus = (1.35 * hot + (slowComet ? 0.22 : 0.12) * glow) * vec3(0.94, 0.97, 1.0);
    vec3 tailTint = slowComet ? vec3(0.68, 0.80, 1.0) : vec3(0.81, 0.89, 1.0);
    return head.w * (nucleus + tail * tailTint * (slowComet ? 0.23 : 0.62));
}

vec3 satellite(vec2 pixel) {
    if (ubuf.satelliteHead.w <= 0.0)
        return vec3(0.0);
    vec2 p = pixel - ubuf.satelliteHead.xy;
    float r2 = dot(p, p);
    if (r2 > 16.0)
        return vec3(0.0);
    float sigma2 = ubuf.satelliteHead.z * ubuf.satelliteHead.z;
    float light = exp2(-0.7213475 * r2 / (sigma2 + 0.0833333)) * sigma2 / (sigma2 + 0.0833333);
    return light * ubuf.satelliteHead.w * vec3(1.0, 0.95, 0.86);
}

void main() {
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    vec3 colour = ubuf.skyColor.rgb;
    vec2 edgePosition = qt_TexCoord0 * 2.0 - 1.0;
    float edge = pow(clamp(dot(edgePosition, edgePosition) * 0.6, 0.0, 1.0), 1.5);
    colour += ubuf.edgeLift * edge * vec3(0.10, 0.19, 0.30);
    if (ubuf.density > 0.0) {
        // Keep the composition's star count similar across aspect ratios, while
        // all distances are evaluated in physical pixels, independent of QML DPR.
        float scale = max(1.0, sqrt(ubuf.resolution.x * ubuf.resolution.y / (1024.0 * 576.0)));
        scale /= sqrt(max(0.0001, ubuf.density));
        vec3 field = stars(pixel, scale, 0.0);
        field += stars(pixel, scale, 1.0);
        field += stars(pixel, scale, 2.0);
        colour += field * ubuf.brightness;
    }
    colour += streak(pixel, ubuf.meteorHead, ubuf.meteorShape, false);
    colour += streak(pixel, ubuf.companionHead, ubuf.companionShape, false);
    colour += streak(pixel, ubuf.cometHead, ubuf.cometShape, true);
    colour += satellite(pixel);
    // Stationary sub-code-value dither; no animated noise in the black sky.
    float dither = fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715)))) - 0.5;
    // Never lift empty black pixels with dither: the default sky is exactly zero.
    float lit = step(1.0 / 255.0, max(colour.r, max(colour.g, colour.b)));
    colour += lit * dither / 255.0;
    fragColor = vec4(clamp(colour, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}
