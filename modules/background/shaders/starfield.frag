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
    vec4 event0Head;
    vec4 event0Colour;
    vec4 event0Tail01;
    vec4 event0Tail23;
    vec4 event0Shape;
    vec4 event0Bounds;
    vec4 event1Head;
    vec4 event1Colour;
    vec4 event1Tail01;
    vec4 event1Tail23;
    vec4 event1Shape;
    vec4 event1Bounds;
    vec4 event2Head;
    vec4 event2Colour;
    vec4 event2Tail01;
    vec4 event2Tail23;
    vec4 event2Shape;
    vec4 event2Bounds;
    vec2 activeStamp;
    float radialMode;
    vec2 centreOffset;
    vec3 flowZoom;
    vec3 birthPadding;
    vec4 flowGrid0;
    vec4 flowGrid1;
    vec4 flowGrid2;
    vec4 flowSeeds0;
    vec4 flowSeeds1;
    vec4 flowSeeds2;
    vec4 driftGrid0;
    vec4 driftGrid1;
    vec4 driftGrid2;
    mat4 driftSeeds0;
    mat4 driftSeeds1;
    mat4 driftSeeds2;
    float flowPhaseLocal;
    float variableFraction;
    vec4 mood;
} ubuf;

// Procedural identity, without a finite star catalogue. One cell per layer.
vec4 hash4(vec2 p) {
    vec4 p4 = fract(vec4(p.xy, p.xy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

vec2 rotate(vec2 p, float c, float s) {
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}


// Literal column selection retains GLSL ES 100 / desktop 120 compatibility.
vec4 columnAt(mat4 m, float column) {
    if (column < 0.5) return m[0];
    if (column < 1.5) return m[1];
    if (column < 2.5) return m[2];
    return m[3];
}
layout(binding = 1) uniform sampler2D descriptorAtlas;

// All channels are opaque, nearest-sampled RGB bytes. Palette RGB and all
// metadata for a cohort share one row and one scene-graph publication.
vec3 descriptor(float row, float column) {
    return texture(descriptorAtlas, vec2((column + 0.5) / 64.0, (mod(row, 256.0) + 0.5) / 256.0)).rgb;
}
vec3 descriptorBytes(float row, float column) {
    return floor(descriptor(row, column) * 255.0 + 0.5);
}
float descriptorWord(float row, float column) {
    return dot(descriptorBytes(row, column), vec3(1.0, 256.0, 65536.0));
}
float descriptor16(float row, float column, float maximum) {
    return dot(descriptorBytes(row, column).rg, vec2(1.0, 256.0)) * (maximum / 65535.0);
}
float chooseArchetype(float row, float draw) {
    float p = descriptorWord(row, 50.0);
    if (draw < max(0.75, mod(p, 1024.0) / 1023.0)) return 0.0;
    if (draw < floor(p / 1024.0) / 1023.0) return 1.0;
    p = descriptorWord(row, 51.0);
    if (draw < mod(p, 1024.0) / 1023.0) return 2.0;
    if (draw < floor(p / 1024.0) / 1023.0) return 3.0;
    p = descriptorWord(row, 52.0);
    if (draw < mod(p, 1024.0) / 1023.0) return 4.0;
    return 5.0;
}
float choosePalette(float row, float draw) {
    // Six RGB fetches at most, with early exits for the selected CDF triplet.
    for (int i = 0; i < 6; ++i) {
        vec3 cdf = descriptor(row, 44.0 + float(i));
        if (draw < cdf.r) return min(15.0, float(i) * 3.0);
        if (draw < cdf.g) return min(15.0, float(i) * 3.0 + 1.0);
        if (draw < cdf.b) return min(15.0, float(i) * 3.0 + 2.0);
    }
    return 15.0;
}
vec4 archetypeParameters(float row, float kind) {
    float col = 16.0 + 4.0 * kind;
    vec4 maxima = kind < 1.5 ? vec4(4096.0, 4096.0, 1.0, 1.0)
        : kind < 2.5 ? vec4(3600.0, 3600.0, 120.0, 120.0)
        : kind < 3.5 ? vec4(4096.0, 4096.0, 60.0, 60.0)
        : kind < 4.5 ? vec4(4096.0, 4096.0, 8.0, 8.0)
        : kind < 5.5 ? vec4(4096.0, 4096.0, 16.0, 16.0)
        : vec4(4096.0, 4096.0, 1.0, 1.0);
    return vec4(descriptor16(row, col, maxima.x), descriptor16(row, col + 1.0, maxima.y),
                descriptor16(row, col + 2.0, maxima.z), descriptor16(row, col + 3.0, maxima.w));
}
float activeAge(float row) {
    float days = descriptorWord(row, 54.0) - 32768.0;
    float seconds = descriptorWord(row, 55.0) / 128.0;
    // Subtract integer days BEFORE converting to seconds. Months of active
    // uptime do not consume the sub-second precision of a young decayer.
    return (ubuf.activeStamp.x - days) * 86400.0 + ubuf.activeStamp.y - seconds;
}

// INTEGRATION: all far-layer pixel -> (u, theta) mapping lives here. Pass
// bhWarpBackground(pixel, weight) here for FAR; bhWarpMaterial for other layers.
vec4 radialCoordinates(vec2 pixel, vec2 centre, float radius, float zoom, float baseAngle) {
    vec2 relative = pixel - centre;
    vec2 q = relative / (radius * zoom);
    float u = 0.5 * dot(q, q);
    vec2 base = pixel - ubuf.resolution * 0.5;
    float t = (base.x * relative.y - base.y * relative.x) / max(dot(base, relative), 0.0001);
    float t2 = t * t;
    float angle = baseAngle + t * (1.0 + t2 * (-1.0 / 3.0 + t2 * (1.0 / 5.0 + t2 * (-1.0 / 7.0 + t2 / 9.0))));
    if (abs(t) > 0.25 || dot(base, relative) <= 0.0) angle = atan(relative.y, relative.x);
    return vec4(q, u, angle);
}

// BEGIN CENTRAL FADE / LIFETIME — replace the radial rim factors here with
// bhWarpMaterial's rimLife during integration. Do not add a second centre fade.
float centralMinimumU(float radius, float zoom, float padding, float requestedSupport, float layer) {
    float middle = step(0.5, layer), nearLayer = step(1.5, layer);
    float inner = mix(mix(0.008, 0.025, middle), 0.070, nearLayer);
    float depth = mix(mix(0.10, 0.42, middle), 1.0, nearLayer);
    float edgeR = 1.0 + padding / radius;
    float starR = max(2.0 * inner, sqrt(max(0.0, edgeR * edgeR - mix(15120.0, 1200.0, middle) * (6.0 / 1080.0) * depth)));
    float pixelR = max(0.0, starR - requestedSupport / (radius * zoom));
    return pixelR * pixelR * 0.5;
}
float centralLifetime(float r, float age, float layer, vec4 h) {
    float middle = step(0.5, layer), nearLayer = step(1.5, layer);
    float inner = mix(mix(0.008, 0.025, middle), 0.070, nearLayer);
    float outer = mix(mix(0.020, 0.060, middle), 0.140, nearLayer);
    float lifetime = mix(7440.0, 480.0, middle) + 120.0 * fract(h.x * 13.71 + h.z * 19.13);
    return smoothstep(inner, outer, r * 0.5) * smoothstep(0.0, 4.0, age)
        * (1.0 - smoothstep(lifetime - 90.0, lifetime, age));
}
// END CENTRAL FADE / LIFETIME

vec3 stars(vec2 pixel, float baseAngle, float scale, float layer) {
    float nearLayer = step(1.5, layer);
    float middleLayer = step(0.5, layer);
    float displayScale = max(1.0, sqrt(ubuf.resolution.x * ubuf.resolution.y / (1024.0 * 576.0)));
    float optics = mix(1.0, displayScale, nearLayer);
    float cellSize = mix(mix(12.0, 30.0, middleLayer), 110.0, nearLayer) * scale;
    float depth = mix(mix(0.10, 0.42, middleLayer), 1.0, nearLayer);
    float requestedSupport = mix(mix(3.5, 6.0, middleLayer), 42.0 * optics, nearLayer);
    vec4 h;
    vec2 p;
    float support;
    float cellMargin;
    float life = 1.0;
    float age = 0.0;
    if (ubuf.radialMode > 0.5) {
        vec4 grid = layer < 0.5 ? ubuf.flowGrid0 : layer < 1.5 ? ubuf.flowGrid1 : ubuf.flowGrid2;
        vec4 seeds = layer < 0.5 ? ubuf.flowSeeds0 : layer < 1.5 ? ubuf.flowSeeds1 : ubuf.flowSeeds2;
        float zoom = layer < 0.5 ? ubuf.flowZoom.x : layer < 1.5 ? ubuf.flowZoom.y : ubuf.flowZoom.z;
        float shortSide = min(ubuf.resolution.x, ubuf.resolution.y);
        float radius = shortSide * 0.5;
        vec2 centre = ubuf.resolution * 0.5 + ubuf.centreOffset * depth;
        float padding = layer < 0.5 ? ubuf.birthPadding.x : layer < 1.5 ? ubuf.birthPadding.y : ubuf.birthPadding.z;
        float minimumU = centralMinimumU(radius, zoom, padding, requestedSupport, layer);
        vec4 coordinates = radialCoordinates(pixel, centre, radius, zoom, baseAngle);
        vec2 q = coordinates.xy;
        float u = coordinates.z;
        float angle = coordinates.w;
        if (u < minimumU || u < 1e-12) return vec3(0.0);
        // Integer sector count makes both sides of atan's branch cut identical.
        float sectors = floor(grid.y * 6.28318530718 + 0.5);
        float angleOffset = 0.37 + layer * 1.23;
        float angularCell = mod((angle - angleOffset) * grid.y, sectors);
        float sector = floor(angularCell);
        float radialCell = u * grid.x + grid.z;
        float row = floor(radialCell);
        float rowId = row + grid.w;
        vec2 salt = rowId < 256.0 ? seeds.xy : seeds.zw;
        h = hash4(vec2(sector, mod(rowId, 256.0)) + salt + layer * vec2(173.17, 319.43));
        if (h.w > mix(0.90, 0.68, nearLayer)) return vec3(0.0);
        // Non-flare foreground halos are below one output code well before
        // 18*optics. Reject their empty surroundings before the expensive work;
        // the maximum birth flare multiplier (1.3) makes this test immutable.
        if (nearLayer > 0.5 && fract(h.x * 71.31 + h.z * 23.17) >= ubuf.flareFraction * 65.0 * 1.3)
            requestedSupport = min(requestedSupport, 18.0 * optics);
        vec2 jitter = 0.18 + 0.64 * h.xy;
        float starU = (row + jitter.y - grid.z) / grid.x;
        if (starU <= 0.0) return vec3(0.0);
        float r = sqrt(2.0 * starU);
        float pixelR = sqrt(2.0 * u);
        if (abs(pixelR - r) * radius * zoom > requestedSupport) return vec3(0.0);
        float deltaAngle = (angularCell - sector - jitter.x) / grid.y;
        float a2 = deltaAngle * deltaAngle;
        // sin lower bound gives a conservative, cheap angular rejection.
        if (abs(deltaAngle) * (1.0 - a2 / 6.0) * pixelR * radius * zoom > requestedSupport) return vec3(0.0);
        float sinA = deltaAngle * (1.0 + a2 * (-1.0 / 6.0 + a2 * (1.0 / 120.0 + a2 * (-1.0 / 5040.0 + a2 / 362880.0))));
        float cosA = 1.0 + a2 * (-1.0 / 2.0 + a2 * (1.0 / 24.0 + a2 * (-1.0 / 720.0 + a2 / 40320.0)));
        vec2 direction = rotate(q / pixelR, cosA, -sinA);
        vec2 starPosition = centre + radius * zoom * r * direction;
        p = pixel - starPosition; // physical pixels: round cores, screen-aligned crosses
        if (dot(p,p) >= requestedSupport * requestedSupport) return vec3(0.0);
        float innerR = sqrt(max(0.0, 2.0 * (row - grid.z) / grid.x));
        float outerR = sqrt(max(0.0, 2.0 * (row + 1.0 - grid.z) / grid.x));
        float angularMargin = r * sin(min(jitter.x, 1.0 - jitter.x) / grid.y);
        float radialMargin = min(r - innerR, outerR - r);
        // Dust needs only a subpixel guard. A full pixel erased cores in
        // the narrow inner sectors. Both guards remain strictly inside the
        // cell; the support taper reaches zero before its boundary.
        cellMargin = max(0.0, radius * zoom * min(angularMargin, radialMargin) - mix(0.125, 1.0, middleLayer));
        support = min(requestedSupport, mix(0.98, 0.9, middleLayer) * cellMargin);
        if (support <= 0.0 || dot(p,p) >= support * support) return vec3(0.0);
        // Entry is measured against an immutable expanded rectangle, including
        // maximum camera excursion and optical support. Thus the palette was
        // sealed before even an off-screen star's halo could become visible.
        vec2 boundary = (ubuf.resolution * 0.5 + padding) / max(abs(direction), vec2(0.00001));
        float edgeR = min(boundary.x, boundary.y) / radius;
        age = (0.5 * edgeR * edgeR - starU) / ((6.0 / 1080.0) * depth);
        life = centralLifetime(r, age, layer, h);
        if (life <= 0.0) return vec3(0.0);
    } else {
        float angle = 0.37 + layer * 1.23;
        float c = cos(angle), s = sin(angle);
        vec2 centre = ubuf.cameraCentre * ubuf.resolution;
        float zoom = exp(ubuf.camera.z * depth);
        float turn = ubuf.camera.w * depth;
        float cameraC = cos(turn), cameraS = sin(turn);
        vec2 samplePoint = rotate(pixel - centre, cameraC, -cameraS) / zoom + centre;
        vec4 grid = layer < 0.5 ? ubuf.driftGrid0 : layer < 1.5 ? ubuf.driftGrid1 : ubuf.driftGrid2;
        mat4 seeds = layer < 0.5 ? ubuf.driftSeeds0 : layer < 1.5 ? ubuf.driftSeeds1 : ubuf.driftSeeds2;
        vec2 world = rotate(samplePoint - ubuf.resolution * 0.5, c, s) / cellSize + grid.xy;
        vec2 cell = floor(world);
        vec2 id = cell + grid.zw;
        vec2 block = floor(id / 256.0);
        vec2 salt = columnAt(seeds, block.x + 2.0 * block.y).xy;
        h = hash4(mod(id, 256.0) + salt + layer * vec2(173.17, 319.43));
        if (h.w > mix(0.76, 0.68, nearLayer)) return vec3(0.0);
        support = min(requestedSupport, max(0.0, cellSize * 0.5 - 1.0));
        vec2 position = support + 1.0 + h.xy * max(vec2(0.0), vec2(cellSize - 2.0 * (support + 1.0)));
        vec2 delta = (fract(world) * cellSize - position) * zoom;
        support *= zoom;
        cellMargin = support;
        if (support <= 0.0 || dot(delta,delta) >= support * support) return vec3(0.0);
        p = rotate(rotate(delta, c, -s), cameraC, cameraS);
    }
    float originalSupport = support;
    vec2 originalP = p;
    vec3 birth = vec3(0.5, 0.0, 0.0); // calm, tinted mix, palette count
    float cohort = 0.0;
    float birthBucket = 0.0;
    float archetype = 0.0;
    // Independently salted projections of the already uniform cell hash.
    // Avoid two additional full hashes on each supported dust fragment.
    vec4 draws = fract(h.xyzw * vec4(73.17, 31.73, 59.31, 97.13)
        + h.wzxy * vec4(19.71, 53.11, 41.17, 61.19));
    if (ubuf.radialMode > 0.5) {
        birthBucket = (ubuf.flowPhaseLocal - age) / 30.0;
        float n = floor(birthBucket);
        cohort = n - 1.0 + (draws.x < fract(birthBucket) ? 1.0 : 0.0);
        if (middleLayer > 0.5) {
            birth = descriptorBytes(cohort, 53.0) / vec3(255.0, 255.0, 1.0);
            birth.y = min(0.45, birth.y);
            archetype = chooseArchetype(cohort, draws.y);
        } else {
            float farHeader = descriptorWord(cohort, 57.0);
            birth = vec3(mod(farHeader, 256.0) / 255.0, 0.0, floor(farHeader / 262144.0));
            archetype = draws.y < min(0.25, mod(floor(farHeader / 256.0), 1024.0) / 1023.0) ? 1.0 : 0.0;
        }
        // The near-only decayer's middle-layer share returns to steady.
        if (nearLayer < 0.5 && archetype > 1.5 && archetype < 2.5) archetype = 0.0;
        if (middleLayer > 0.5 && archetype == 0.0 && birth.z > 0.0 && draws.z < birth.y
            && draws.y < descriptor16(cohort, 58.0, 1.0) / max(0.00001, birth.y)) archetype = 6.0;
    }
    float calm = birth.x;
    float acceptance = middleLayer > 0.5 ? mix(0.76, 0.68, nearLayer) : mix(0.90, 0.62, calm);
    float moodTarget = acceptance;
    if (ubuf.mood.x < 0.5) moodTarget -= mix(0.08, 0.06, middleLayer) * (1.0 - nearLayer);
    else if (ubuf.mood.x < 1.5) moodTarget += mix(0.14, 0.02, middleLayer) * (1.0 - nearLayer);
    float population = mix(1.0 - step(acceptance, h.w), 1.0 - step(moodTarget, h.w), ubuf.mood.y);
    if (population <= 0.0) return vec3(0.0);
    life *= population;
    vec4 traits = fract(h.zwxy * vec4(97.31, 41.13, 71.17, 89.31)
        + h.yxwz * vec4(61.91, 11.71, 37.13, 23.17));
    float tauTime = ubuf.phaseTime * (6.28318530718 / 4096.0);
    vec4 parameters = vec4(0.0);
    float behaviour = 1.0;
    float behaviourPhase = traits.z * 6.28318530718;
    float behaviourCycles = 1.0;
    float motionA = 0.0;
    vec2 binaryOffset = vec2(0.0);
    if (archetype > 0.5) {
        parameters = archetypeParameters(cohort, archetype);
        behaviourCycles = max(1.0, floor(4096.0 / max(1.0, mix(parameters.x, parameters.y, traits.x)) + 0.5));
        float oscillation = tauTime * behaviourCycles + behaviourPhase;
        if (archetype < 1.5) {
            float amplitude = mix(parameters.z, parameters.w, traits.y);
            behaviour = 1.0 + min(amplitude, middleLayer > 0.5 ? 0.22 : 0.08) * sin(oscillation);
        } else if (archetype < 2.5) {
            // The next boundary's actual sealed ACTIVE timestamp, not flow age.
            float anchor = floor(birthBucket) + 1.0;
            float anchorDistance = age - (anchor - birthBucket) * 30.0;
            if (anchorDistance < 0.0) return vec3(0.0);
            float a = activeAge(anchor);
            float L = mix(parameters.x, parameters.y, traits.x);
            float entrance = mix(parameters.z, parameters.w, traits.y);
            behaviour = smoothstep(0.0, entrance, a) * (1.0 - smoothstep(0.55 * L, L, a))
                * (1.0 + 0.25 * exp2(-4.0 * max(0.0, a) / L));
        } else if (archetype < 3.5) {
            float period = 4096.0 / behaviourCycles;
            float width = min(period * 0.5, mix(parameters.z, parameters.w, traits.y));
            float phaseAge = abs(fract(oscillation / 6.28318530718) - 0.5) * period;
            behaviour = 1.0 + min(0.18, descriptor(cohort, 58.0).b) * (1.0 - smoothstep(0.0, width * 0.5, phaseAge));
        } else if (archetype < 4.5) {
            // Original rejection contains the complete moving support disc.
            motionA = min(min(parameters.z, 8.0), min(0.15 * cellMargin, 0.20 * support));
            vec2 delta = motionA * 0.70710678118 * vec2(sin(oscillation), sin(tauTime * (behaviourCycles + 1.0) + behaviourPhase * 1.7));
            p -= delta;
            support -= motionA;
        } else if (archetype < 5.5) {
            motionA = min(min(mix(parameters.z, parameters.w, traits.y) * 0.5, 8.0), 0.15 * support);
            binaryOffset = motionA * vec2(cos(oscillation), sin(oscillation));
            support -= motionA;
        }
    }
    if (behaviour <= 0.0) return vec3(0.0);
    float r2 = dot(p, p);

    float variation = fract(h.z * 37.19);
    float phase = h.z * 6.28318530718;
    float cycles = floor(mix(370.0, 990.0, variation));
    float flareDraw = fract(h.x * 71.31 + h.z * 23.17);
    float flare = (archetype == 0.0 ? 1.0 : 0.0) * nearLayer * (1.0 - step(ubuf.flareFraction * 65.0 * mix(1.3, 0.7, calm), flareDraw));
    float variableDraw = fract(h.y * 47.23 + h.z * 11.73);
    float variable = (archetype == 0.0 ? 1.0 : 0.0) * middleLayer * (1.0 - flare) * (1.0 - step(ubuf.variableFraction, variableDraw));
    float slowCycles = variable > 0.5 ? floor(mix(18.0, 46.0, variation)) : floor(mix(31.0, 83.0, h.z));
    float slow = sin(tauTime * slowCycles + phase * 2.3);
    float pulse = sin(tauTime * cycles + phase + 0.55 * slow);
    float shimmer = 1.0 + ubuf.twinkle * (0.60 * pulse + 0.28 * sin(tauTime * floor(mix(193.0, 431.0, h.w)) + phase * 1.7));
    // Unsynchronised 0.5–1.5 s glints, with variable strength, on a minority.
    if (variation > 0.78 && archetype == 0.0) {
        float glint = pow(max(0.0, sin(tauTime * floor(mix(63.0, 181.0, h.z)) + phase * 3.7)), 48.0);
        shimmer += ubuf.twinkle * glint * (0.8 + 0.6 * slow) * (1.0 + 0.35 * ubuf.mood.y * step(1.5, ubuf.mood.x) * (1.0 - step(2.5, ubuf.mood.x)));
    }
    shimmer *= 1.0 + variable * 0.15 * slow;
    float visibility = life;
    if (ubuf.mood.x > 0.5 && ubuf.mood.x < 1.5 && middleLayer == 0.0)
        visibility *= mix(1.0, 0.85, ubuf.mood.y);

    // Dust never scales with the screen: its faintest peaks remain perceptible.
    float sigma = mix(0.44, 0.56, h.z) + middleLayer * 0.12;
    sigma = mix(sigma, mix(1.0, 1.4, h.z) * optics, nearLayer);
    sigma *= mix(0.92, 1.08, calm);
    sigma = min(2.5, sigma);
    float energy = mix(0.32, 1.28, h.z * h.z);
    energy *= mix(1.0, 1.35, middleLayer);
    energy = mix(energy, mix(1.8, 2.8, h.z), nearLayer);
    // Pixel footprint convolved with the point spread: stable subpixel movement.
    float variance = sigma * sigma + 0.0833333;
    float core = exp2(-0.7213475 * r2 / variance) * sigma * sigma / variance;
    float halo = middleLayer * 0.024 * exp2(-r2 / (mix(3.5, 14.0, nearLayer) * optics * optics));
    float light = (core + halo) * energy * shimmer;

    if (nearLayer > 0.0 && flare == 0.0) {
        // A capped hot point plus redistributed light in a broad Gaussian halo.
        // The shoulder approaches white smoothly instead of clipping a wide core
        // into a flat disc. Sigma and convolution are in physical pixels.
        float hotSigma = min(2.5, optics * mix(0.55, 0.68, h.z) * mix(0.92, 1.08, calm));
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

    if (archetype > 4.5 && archetype < 5.5) {
        vec2 a = p - binaryOffset, b = p + binaryOffset;
        float a2 = dot(a, a), b2 = dot(b, b);
        float cutA = 1.0 - smoothstep(support * support * 0.64, support * support, a2);
        float cutB = 1.0 - smoothstep(support * support * 0.64, support * support, b2);
        float pairCore = 0.5 * (exp2(-0.7213475 * a2 / variance) * cutA + exp2(-0.7213475 * b2 / variance) * cutB) * sigma * sigma / variance;
        light = (pairCore + halo) * energy * shimmer;
        if (nearLayer > 0.5) {
            float hotSigma = min(2.5, optics * mix(0.55, 0.68, h.z) * mix(0.92, 1.08, calm));
            float hotVariance = hotSigma * hotSigma + 0.0833333;
            float pairHot = 0.5 * (exp2(-0.7213475 * a2 / hotVariance) * cutA + exp2(-0.7213475 * b2 / hotVariance) * cutB) * hotSigma * hotSigma / hotVariance;
            float sharedSoft = exp2(-r2 / (26.0 * optics * optics));
            light = 1.0 - exp(-(3.2 * pairHot + 0.085 * sharedSoft) * shimmer);
        }
    } else {
        light *= 1.0 - smoothstep(support * support * 0.64, support * support, r2);
    }
    // Shared halo and displaced cores all die inside the unmodified cell disc.
    if (motionA > 0.0)
        light *= 1.0 - smoothstep(originalSupport * originalSupport * 0.64, originalSupport * originalSupport, dot(originalP, originalP));
    vec3 tint = mix(vec3(0.73, 0.84, 1.0), vec3(1.0, 0.98, 0.94), h.z);
    float tintDraw = fract(h.x * 31.17 + h.y * 17.13 + h.z * 7.97);
    if (birth.z > 0.5 && middleLayer > 0.5 && draws.z < birth.y) {
        float index = choosePalette(cohort, draws.w);
        tint = descriptor(cohort, index);
        if (archetype > 5.5) {
            float byteIndex = floor(index / 2.0);
            vec3 neighbours = descriptorBytes(cohort, 60.0 + floor(byteIndex / 3.0));
            float component = mod(byteIndex, 3.0);
            float packed = component < 0.5 ? neighbours.x : component < 1.5 ? neighbours.y : neighbours.z;
            float neighbour = mod(floor(packed / (mod(index, 2.0) < 0.5 ? 1.0 : 16.0)), 16.0);
            tint = mix(tint, descriptor(cohort, neighbour), 0.5 - 0.5 * cos(tauTime * behaviourCycles + behaviourPhase));
        }
        vec3 whitening = descriptor(cohort, 59.0);
        tint = mix(tint, vec3(1.0), min(0.10, mix(whitening.x, whitening.y, traits.w)));
        tint = mix(tint, vec3(1.0), nearLayer * whitening.z);
    } else if (birth.z < 0.5) {
        vec3 probability = ubuf.radialMode > 0.5 ? descriptor(cohort, 56.0) : vec3(0.0);
        probability *= min(1.0, 0.45 / max(0.00001, probability.x + probability.y + probability.z));
        vec3 target = tint;
        if (tintDraw < probability.x) target = vec3(0.65, 1.0, 0.78);
        else if (tintDraw < probability.x + probability.y) target = vec3(0.86, 0.80, 1.0);
        else if (tintDraw < probability.x + probability.y + probability.z) target = vec3(1.0, 0.83, 0.67);
        tint = mix(tint, target, 0.45);
        tint = mix(tint, vec3(1.0), nearLayer * 0.65);
    } else {
        tint = mix(tint, vec3(1.0), nearLayer * 0.35);
    }
    return light * tint * visibility * behaviour;
}

// CPU bounds and at most six connected segments across three generic slots.
// Every segment uses total tail distance for opacity/width. max-combination
// avoids bright joints; the nucleus is evaluated exactly once per slot.
float tailSegment(vec2 pixel, vec2 a, vec2 b, float travelled, vec4 head, vec4 shape, float style) {
    vec2 v = b - a;
    float length = sqrt(dot(v, v));
    if (length < 0.001) return 0.0;
    float t = clamp(dot(pixel - a, v) / (length * length), 0.0, 1.0);
    float u = clamp((travelled + t * length) / max(shape.x, 0.001), 0.0, 1.0);
    float width = head.z * (style > 0.5 ? 1.8 + 8.0 * u : 1.0 - 0.65 * u);
    vec2 delta = pixel - mix(a, b, t);
    float r2 = dot(delta, delta);
    // Compact circular cross-section; bounding box alone must not cut a glow.
    float support = head.z * (style > 0.5 ? 14.0 : 6.0);
    if (r2 >= support * support) return 0.0;
    float variance = width * width + 0.0833333;
    float light = exp2(-0.7213475 * r2 / variance) * width / sqrt(variance);
    light *= pow(1.0 - u, style > 0.5 ? 1.6 : 2.0);
    return light * (1.0 - smoothstep(0.64 * support * support, support * support, r2));
}
vec3 eventSlot(vec2 pixel, vec4 head, vec4 colour, vec4 tail01, vec4 tail23, vec4 shape, vec4 bounds) {
    if (head.w <= 0.0 || pixel.x < bounds.x || pixel.y < bounds.y || pixel.x > bounds.z || pixel.y > bounds.w) return vec3(0.0);
    vec2 p = pixel - head.xy;
    float r2 = dot(p, p);
    float sigma2 = head.z * head.z;
    float variance = sigma2 + 0.0833333;
    float extent = head.z * (colour.w > 0.5 && colour.w < 1.5 ? 14.0 : 6.0);
    float taper = 1.0 - smoothstep(0.64 * extent * extent, extent * extent, r2);
    float hot = exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
    float glow = colour.w > 1.5 ? 0.0 : exp2(-r2 / (sigma2 * (colour.w > 0.5 ? 32.0 : 6.0)));
    vec3 nucleus = (hot * (colour.w > 1.5 ? 1.0 : 1.35) + glow * (colour.w > 0.5 ? 0.22 : 0.12)) * taper * mix(colour.rgb, vec3(1.0), 0.60);
    float tail = 0.0;
    if (shape.z > 0.5) tail = tailSegment(pixel, tail01.xy, tail01.zw, 0.0, head, shape, colour.w);
    float distance = length(tail01.zw - tail01.xy);
    if (shape.z > 1.5) tail = max(tail, tailSegment(pixel, tail01.zw, tail23.xy, distance, head, shape, colour.w));
    distance += length(tail23.xy - tail01.zw);
    if (shape.z > 2.5) tail = max(tail, tailSegment(pixel, tail23.xy, tail23.zw, distance, head, shape, colour.w));
    return head.w * (nucleus + shape.y * tail * colour.rgb);
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
        vec2 relative = pixel - ubuf.resolution * 0.5;
        float baseAngle = ubuf.radialMode > 0.5 ? atan(relative.y, relative.x) : 0.0;
        vec3 field = stars(pixel, baseAngle, scale, 0.0);
        field += stars(pixel, baseAngle, scale, 1.0);
        field += stars(pixel, baseAngle, scale, 2.0);
        colour += field * ubuf.brightness;
    }
    colour += eventSlot(pixel, ubuf.event0Head, ubuf.event0Colour, ubuf.event0Tail01, ubuf.event0Tail23, ubuf.event0Shape, ubuf.event0Bounds);
    colour += eventSlot(pixel, ubuf.event1Head, ubuf.event1Colour, ubuf.event1Tail01, ubuf.event1Tail23, ubuf.event1Shape, ubuf.event1Bounds);
    colour += eventSlot(pixel, ubuf.event2Head, ubuf.event2Colour, ubuf.event2Tail01, ubuf.event2Tail23, ubuf.event2Shape, ubuf.event2Bounds);
    // Stationary sub-code-value dither; no animated noise in the black sky.
    float dither = fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715)))) - 0.5;
    // Never lift empty black pixels with dither: the default sky is exactly zero.
    float lit = step(1.0 / 255.0, max(colour.r, max(colour.g, colour.b)));
    colour += lit * dither / 255.0;
    fragColor = vec4(clamp(colour, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}
