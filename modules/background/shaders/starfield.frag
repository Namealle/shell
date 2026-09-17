#version 440
#extension GL_GOOGLE_include_directive : require

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
    vec2 event0Tail4;
    vec4 event0Shape;
    vec4 event0Bounds;
    vec4 event1Head;
    vec4 event1Colour;
    vec4 event1Tail01;
    vec4 event1Tail23;
    vec2 event1Tail4;
    vec4 event1Shape;
    vec4 event1Bounds;
    vec4 event2Head;
    vec4 event2Colour;
    vec4 event2Tail01;
    vec4 event2Tail23;
    vec2 event2Tail4;
    vec4 event2Shape;
    vec4 event2Bounds;
    vec2 activeStamp;
    float radialMode;
    vec2 centreOffset;
    vec3 flowZoom;
    vec3 birthPadding;
    vec3 legacyPadding;
    float paddingAge;
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
    float captureHistory;
    float legacyMaterialAlive;
    vec4 particleAtlasInfo;
    vec4 particleDomain;
    vec4 particleData;
    vec2 particleGrid;
    float particlesEnabled;
    float particleReady;
    vec4 dustCluster;
    vec2 dustParallax;
    float particleMu;
    // Microlensing flux ceiling (phenomena.microlensing). 1 disables it.
    float lensFlux;
    // Phenomenon slots 3-5: long, faint, low-gain radial events only, so they
    // carry five vectors rather than a transient slot's seven. Neither class
    // spills into the other. 240 B, against 336 B for three full slots. v8
    // added the third: with seven families on two slots a red giant and a
    // supernova spent most of an hour queued behind a 200 s star birth.
    vec4 event3Head;
    vec4 event3Colour;
    vec4 event3Tail01;
    vec4 event3Shape;
    vec4 event3Bounds;
    vec4 event4Head;
    vec4 event4Colour;
    vec4 event4Tail01;
    vec4 event4Shape;
    vec4 event4Bounds;
    vec4 event5Head;
    vec4 event5Colour;
    vec4 event5Tail01;
    vec4 event5Shape;
    vec4 event5Bounds;
    // ---- v9 EXTRAS, in this order: supernova (64 B), storm (64 B), nebula
    // (112 B). UBO reflection 1600 -> 1840 B of 16384. The order here is the
    // contract every offline tool re-declares (events-sheet.mjs, storm-sheet,
    // supernova-sheet, nebula_sheet.py, bhrender.c); it is verified from the
    // driver's own reflection by tools/bh_probe.py --check, never by hand.
    // v9 SUPERNOVA extras, 64 B. One supernova is alive at a time - the
    // dramatic cooldown is 900 s against a ~290 s life - so the life cycle's
    // fifth through eighth vectors ride beside the phenomenon slots instead of
    // costing a slot nothing else would use.
    //   snRemnant = (siteX, siteY, radiusPx, bodyGain)  the remnant's own frame
    //   snTone    = (rimR, rimG, rimB, turbulencePhase)
    //   snShell   = (shockRadiusPx, shockGain, shockWidthPx, innerGain)
    //   snExtra   = (spikeGain, spikeLengthPx, pulsarGain, seedAngle)
    //   snBody    = (hollowFrac, cavityGain, filigreeGain, dustOpacity)
    //   snHot     = (hotR, hotG, hotB, knotGain)        inner blue-white knots
    //   snWisp    = (wispR, wispG, wispB, wispGain)     the outer red wisps
    //   snDust    = (dustR, dustG, dustB, jetGain)      the grey-brown sheets
    //   snJet     = (axisX, axisY, jetReach, jetWidth)  both in shell radii
    // v11 renamed snFlash -> snRemnant. It used to carry the whole-sky lift
    // gain, which is gone (see main()); it now carries the comoving frame
    // supernovaRemnant() is drawn in, which is the vector that replaced it.
    // 64 -> 144 B for the supernova; the block is 1920 of 16384.
    vec4 snRemnant;
    vec4 snTone;
    vec4 snShell;
    vec4 snExtra;
    vec4 snBody;
    vec4 snHot;
    vec4 snWisp;
    vec4 snDust;
    vec4 snJet;
    // v12 GRAIN POPULATIONS, 160 B. The remnant's visible gas stopped being a
    // noise field with a time-varying tint and became thousands of individual
    // grains, each one born with ONE of six colours and keeping it until it
    // dies (ledger 2403: "instead of it just transition the color slowly it
    // should make new particles of new tone"). The six tones are not a palette
    // ramp, they are element populations, and they are MEASURED off
    // reference/sa0225Mosk01.jpg rather than chosen: a six-way cluster of that
    // image's lit interior in linear light returns exactly these, with the
    // area shares in snPop*.w's comment. See supernovaRemnant().
    //   snPop0..5 = (r, g, b, dustFrac)   population tone, linear, peak = 1
    //   snGrain   = (grainGain, cellsPerUnit, lifeSec, grainSizeCells)
    //   snFlow    = (curlAmp, curlScale, layerCreep, toneSpread)
    //   snTurn    = (posLo, posSpan, shockU, toneAdvance)
    //   snTurn2   = (shockUDot, sheetGain, grainOpacity, parallax)
    // Block 1920 -> 2080 B of 16384; offsets verified off the baked .qsb by
    // tools/bh_probe.py --check, never by hand.
    vec4 snPop0;
    vec4 snPop1;
    vec4 snPop2;
    vec4 snPop3;
    vec4 snPop4;
    vec4 snPop5;
    vec4 snGrain;
    vec4 snFlow;
    vec4 snTurn;
    vec4 snTurn2;
    // METEOR STORM (events.shower), ONE slot for the whole shower. Four vec4,
    // 64 B, whatever the peak rate is: the kernel generates every streak from
    // the storm's seed and its PHASE, so several meteors a second cost no more
    // uniform than one. See meteorStorm() for the layout of each vector.
    vec4 stormHead;
    vec4 stormShape;
    vec4 stormColour;
    vec4 stormSpan;
    // ---- NEBULA PASSAGE (v9) ------------------------------------------
    // One cloud, so one block rather than a slot: it is not a point source and
    // it composites at a different stage (into the far field, under everything
    // else). 112 B. head.w <= 0 is the whole switch.
    vec4 nebulaHead;   // x, y, semiMajorPx, gain
    vec4 nebulaShape;  // majorDirX, majorDirY (unit), aspect (minor/major), turbPhase
    vec4 nebulaTone0;  // emission tone A rgb, dust opacity
    vec4 nebulaTone1;  // emission tone B rgb, embedded-star gain
    vec4 nebulaStars;  // star0 x, y, star1 x, y (absolute px; far off = absent)
    vec4 nebulaStars2; // star2 x, y, coreSigmaPx, scatterSigmaPx
    vec4 nebulaBounds; // x0, y0, x1, y1
    // ---- v12 METEORS, 128 B, APPENDED so every offset above is unchanged --
    // Three per-slot vectors and five shared ones. They are at the END of the
    // block on purpose: the offline sheets re-declare this layout by hand
    // (events-sheet.mjs, storm-sheet.mjs, meteor-sheet.mjs) and appending
    // cannot move anything they already read. Block 2080 -> 2208 B of 16384;
    // offsets are read off the baked .qsb by tools/bh_probe.py --check, never
    // added up by hand.
    //
    //   eventNBurn = (F, headPathU, pathSpan, speed01)
    //     F           where along its own path this streak is brightest. The
    //                 kernel this replaced peaked at 0.09 of the LIFE; the
    //                 measured population is 0.52 +- 0.09 (Subasinghe, 113
    //                 light curves). headPathU is where the head is NOW and
    //                 pathSpan how much path the drawn trail covers, so a
    //                 point on the trail can be lit by the light curve at the
    //                 place the head was when it passed -- which is what makes
    //                 a streak a lens instead of a taper off a dot.
    //     speed01     the entry speed, normalised. The second spectrum (the
    //                 violet-red leading edge) is absent below ~15 km/s.
    //   meteorTone / stormTone = (naGain, trainGain, leadGain, curveSharp)
    //     the three extra emitters' gains as a share of the head, and the
    //     light curve's sharpness. Zero in all three disables the v12 colour
    //     and leaves the shape change alone, which is how the config keys
    //     switch it off.
    //   stormBurn  = (curveF, curveSpread, flareShare, doublePeakShare)
    //   stormTrain = (trainShare, trainWindow, trainSecLo, trainSecHi)
    //   stormWind  = (windPxPerSec, foldSec, trainGain, diffuseSec)
    vec4 event0Burn;
    vec4 event1Burn;
    vec4 event2Burn;
    vec4 meteorTone;
    vec4 stormTone;
    vec4 stormBurn;
    vec4 stormTrain;
    vec4 stormWind;
    // -------------------------------------------------------------------
#define BH_UNIFORMS
#include "blackhole.glsl"
#undef BH_UNIFORMS
} ubuf;

#include "blackhole.glsl"

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
// Binding 2 belongs to D's disk noise; 3 is the coherent particle atlas.
layout(binding = 4) uniform sampler2D descriptorAtlas;
layout(binding = 3) uniform sampler2D particleAtlas;

// All channels are opaque, nearest-sampled RGB bytes. Palette RGB and all
// metadata for a cohort share one row and one scene-graph publication.
vec3 descriptor(float row, float column) {
    return texture(descriptorAtlas, vec2((column + 0.5) / 64.0, (mod(row, 256.0) + 0.5) / 1536.0)).rgb;
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

// Separate tile, one atomic texture publication. The immutable palette tile
// retains its original contiguous 64x256 layout and texture-cache locality.
float entryWord(float offset) {
    vec2 texel = vec2(mod(offset,64.0),256.0+floor(offset/64.0));
    vec3 bytes = floor(texture(descriptorAtlas,(texel+0.5)/vec2(64.0,1536.0)).rgb*255.0+0.5);
    return dot(bytes,vec3(1.0,256.0,65536.0));
}
float entryAge(float row, float sector, vec2 jitterHash) {
    vec2 headerPixel=vec2(sector,256.0+mod(row,64.0));
    vec3 header=floor(texture(descriptorAtlas,(headerPixel+0.5)/vec2(64.0,1536.0)).rgb*255.0+0.5);
    float base=4096.0+dot(header.rg,vec2(1.0,256.0))*4.0;
    for (int i=0;i<20;++i) {
        if (float(i)>=header.b) break;
        float offset = base+float(i)*4.0;
        vec2 capturedHash = vec2(entryWord(offset),entryWord(offset+1.0))/16777216.0;
        if (all(lessThan(abs(capturedHash-jitterHash),vec2(0.00000006)))) {
            float day = entryWord(offset+2.0);
            if (day < 0.5) return 1e7;
            float seconds = entryWord(offset+3.0)/128.0;
            return (ubuf.activeStamp.x-(day-32768.0))*86400.0+ubuf.activeStamp.y-seconds;
        }
    }
    return 1e8;
}

// INTEGRATION: all far-layer pixel -> (u, theta) mapping lives here. Pass
// bhWarpBackground(pixel, weight) here for FAR; bhWarpMaterial for other layers.
vec4 radialCoordinates(vec2 pixel, vec2 centre, float radius, float zoom, float baseAngle, vec2 screenPixel) {
    vec2 relative = pixel - centre;
    vec2 q = relative / (radius * zoom);
    float u = 0.5 * dot(q, q);
    vec2 base = screenPixel - ubuf.resolution * 0.5;
    float t = (base.x * relative.y - base.y * relative.x) / max(dot(base, relative), 0.0001);
    float t2 = t * t;
    float angle = baseAngle + t * (1.0 + t2 * (-1.0 / 3.0 + t2 * (1.0 / 5.0 + t2 * (-1.0 / 7.0 + t2 / 9.0))));
    if (abs(t) > 0.25 || dot(base, relative) <= 0.0) angle = atan(relative.y, relative.x);
    return vec4(q, u, angle);
}

// BEGIN CENTRAL FADE / LIFETIME — legacy cohorts retain their v3 policy.
// New capture cohorts replace it with material rim life and the history guard.
// Do not apply a second centre fade outside this block.
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
float captureLifetime(float sourceR, float age, float pixelRim) {
    float rh = ubuf.bhGeometry.x;
    float candidateRim = smoothstep(rh, 1.08*rh, sqrt(sourceR*sourceR+rh*rh));
    return mix(1.0,candidateRim,ubuf.bhHalo.w) * pixelRim * smoothstep(0.0,4.0,age)
        * (1.0-smoothstep(7440.0,7560.0,age));
}
// END CENTRAL FADE / LIFETIME

// Material mapping has its own radial derivative; bhJacobian is FAR-only.
mat2 materialJacobian(vec2 pixel) {
    vec2 p = pixel-ubuf.bhCentre;
    float r = length(p), rh = ubuf.bhGeometry.x;
    if (r <= rh || r >= ubuf.bhGeometry.y) return mat2(1.0);
    float t = clamp((r/rh-3.2)/0.8,0.0,1.0);
    float w = ubuf.bhHalo.w*bhTaper(r);
    float dw = -ubuf.bhHalo.w*30.0*t*t*(t-1.0)*(t-1.0)/(0.8*rh);
    float source = sqrt(max(1e-8,r*r-rh*rh));
    float tangential = mix(r,source,w)/r;
    float radial = 1.0-w+w*r/source+dw*(source-r);
    vec2 e = p/r;
    return mat2(tangential)+(radial-tangential)*mat2(e.x*e.x,e.x*e.y,e.x*e.y,e.y*e.y);
}
float filteredCore(vec2 p, float sigma, vec3 footprint) {
    float a = sigma*sigma+footprint.x, b = footprint.y, d = sigma*sigma+footprint.z;
    float determinant = max(1e-8,a*d-b*b);
    float mahalanobis = (d*p.x*p.x-2.0*b*p.x*p.y+a*p.y*p.y)/determinant;
    return exp2(-0.7213475*mahalanobis)*sigma*sigma/sqrt(determinant);
}

vec3 stars(vec2 pixel, float baseAngle, float scale, float layer, float capturePass, vec2 screenPixel, float pixelRim) {
    float nearLayer = step(1.5, layer);
    float middleLayer = step(0.5, layer);
    float displayScale = max(1.0, sqrt(ubuf.resolution.x * ubuf.resolution.y / (1024.0 * 576.0)));
    float optics = mix(1.0, displayScale, nearLayer);
    float cellSize = mix(mix(12.0, 30.0, middleLayer), 110.0, nearLayer) * scale;
    if (layer < 0.5 && ubuf.dustCluster.w > 0.0) cellSize *= ubuf.dustCluster.w;
    float depth = mix(mix(0.10, 0.42, middleLayer), 1.0, nearLayer);
    float requestedSupport = mix(mix(3.5, 6.0, middleLayer), 42.0 * optics, nearLayer);
    vec4 h;
    vec2 p;
    float support;
    float cellMargin;
    float life = 1.0;
    float age = 0.0;
    float candidateR = 0.0;
    vec2 entryCell = vec2(0.0);
    if (ubuf.radialMode > 0.5) {
        vec4 grid = layer < 0.5 ? ubuf.flowGrid0 : layer < 1.5 ? ubuf.flowGrid1 : ubuf.flowGrid2;
        vec4 seeds = layer < 0.5 ? ubuf.flowSeeds0 : layer < 1.5 ? ubuf.flowSeeds1 : ubuf.flowSeeds2;
        float zoom = layer < 0.5 ? ubuf.flowZoom.x : layer < 1.5 ? ubuf.flowZoom.y : ubuf.flowZoom.z;
        float shortSide = min(ubuf.resolution.x, ubuf.resolution.y);
        float radius = shortSide * 0.5;
        vec2 centre = ubuf.resolution * 0.5 + ubuf.centreOffset * (capturePass < -1.5 ? depth : mix(depth, 1.0, ubuf.bhHalo.w));
        // Slow bounded parallax of the far field: the inward flow is 1/r, so the
        // corners would otherwise be the one frozen region of the sky.
        if (layer < 0.5) centre += ubuf.dustParallax;
        float padding = layer < 0.5 ? ubuf.legacyPadding.x : layer < 1.5 ? ubuf.legacyPadding.y : ubuf.legacyPadding.z;
        float minimumU = centralMinimumU(radius, zoom, padding, requestedSupport, layer);
        vec4 coordinates = radialCoordinates(pixel, centre, radius, zoom, baseAngle, screenPixel);
        vec2 q = coordinates.xy;
        float u = coordinates.z;
        float angle = coordinates.w;
        if ((u < minimumU && (capturePass < -1.5 || layer < 0.5 || capturePass == 0.0 || ubuf.captureHistory < 0.5)) || u < 1e-12) return vec3(0.0);
        // Integer sector count makes both sides of atan's branch cut identical.
        float sectors = floor(grid.y * 6.28318530718 + 0.5);
        float angleOffset = 0.37 + layer * 1.23;
        float angularCell = mod((angle - angleOffset) * grid.y, sectors);
        float sector = floor(angularCell);
        float radialCell = u * grid.x + grid.z;
        float row = floor(radialCell);
        float rowId = row + grid.w;
        entryCell = vec2(mod(rowId,256.0),sector);
        vec2 salt = rowId < 256.0 ? seeds.xy : seeds.zw;
        h = hash4(vec2(sector, mod(rowId, 256.0)) + salt + layer * vec2(173.17, 319.43));
        float keep = mix(0.90, 0.68, nearLayer);
        // Two-level Neyman-Scott occupancy: sparse cluster centres (dustCluster.x
        // cells across) inside a much coarser void/stream field (dustCluster.y).
        // Mean density is 1, so the cell count is preserved; the variance is what
        // makes the field read as tributaries instead of even rain.
        if (ubuf.dustCluster.z > 0.0 && layer < 0.5) {
            vec2 cell = vec2(sector, mod(rowId, 256.0));
            float fine = hash4(floor(cell / ubuf.dustCluster.x) + salt + vec2(51.7, 11.3)).x;
            float coarse = hash4(floor(cell / ubuf.dustCluster.y) + salt + vec2(7.1, 88.9)).y;
            float density = (0.10 + 3.6 * fine * fine) * (0.32 + 1.7 * coarse * coarse);
            keep = clamp(mix(keep, keep * density, ubuf.dustCluster.z), 0.0, 1.0);
        }
        if (h.w > keep) return vec3(0.0);
        // Non-flare foreground halos are below one output code well before
        // 18*optics. Reject their empty surroundings before the expensive work;
        // the maximum birth flare multiplier (1.3) makes this test immutable.
        if (nearLayer > 0.5 && fract(h.x * 71.31 + h.z * 23.17) >= ubuf.flareFraction * 65.0 * 1.3)
            requestedSupport = min(requestedSupport, 18.0 * optics);
        vec2 jitter = 0.18 + 0.64 * h.xy;
        float starU = (row + jitter.y - grid.z) / grid.x;
        if (starU <= 0.0) return vec3(0.0);
        float r = sqrt(2.0 * starU);
        candidateR = r * radius * zoom;
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
        // Cohort birth is measured against an immutable expanded rectangle, including
        // maximum camera excursion and optical support. Thus the palette was
        // sealed before even an off-screen star's halo could become visible.
        vec2 boundary = (ubuf.resolution * 0.5 + padding) / max(abs(direction), vec2(0.00001));
        float edgeR = min(boundary.x, boundary.y) / radius;
        age = (0.5 * edgeR * edgeR - starU) / ((6.0 / 1080.0) * depth);
        if (capturePass > -1.5 && ubuf.paddingAge >= 0.0) {
            float newPadding = layer < 0.5 ? ubuf.birthPadding.x : layer < 1.5 ? ubuf.birthPadding.y : ubuf.birthPadding.z;
            vec2 newBoundary = (ubuf.resolution*0.5+newPadding)/max(abs(direction),vec2(0.00001));
            float newEdge = min(newBoundary.x,newBoundary.y)/radius;
            float newAge = (0.5*newEdge*newEdge-starU)/((6.0/1080.0)*depth);
            // Both ages advance by exactly one per flow second. This choice
            // is a birth-time predicate, never a live palette reassignment.
            if (newAge <= ubuf.paddingAge) age = newAge;
        }
        // The camera regime reverses this stream: a star is then born at the
        // centre and its age is how far it has come OUT, not how far it has
        // come in. radialMode carries the blend in its fraction (1 = the inward
        // stream, 2 = fully reversed), and mixing the two ages rather than
        // switching between them is what keeps a star's sealed birth cohort
        // walking smoothly across the change instead of jumping palettes.
        float outward = clamp(ubuf.radialMode - 1.0, 0.0, 1.0);
        if (outward > 0.0)
            age = mix(age, max(0.0, starU - minimumU) / ((6.0 / 1080.0) * depth), outward);
        life = centralLifetime(r, age, layer, h);
        // Defer material rejection until its immutable cohort policy is known.
        if ((capturePass < -1.5 || layer < 0.5 || capturePass == 0.0 || ubuf.captureHistory < 0.5) && life <= 0.0) return vec3(0.0);
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
            float captured = capturePass < -1.5 ? 0.0 : step(0.5, descriptor(cohort,63.0).g);
            if (capturePass >= 0.0 && abs(captured-capturePass)>0.5) return vec3(0.0);
            if (captured > 0.5) life = captureLifetime(candidateR, age, pixelRim);
            if (life <= 0.0) return vec3(0.0);
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
    // Mood kinds 4 (clearing) and 5 (nebular). Both are weighted by mood.y,
    // which eases over sixty seconds, and both are applied the way kinds 0-3
    // are: the two binary outcomes are interpolated, never the threshold, so a
    // star fades across the change instead of switching on one frame.
    float clearing = step(3.5, ubuf.mood.x) * (1.0 - step(4.5, ubuf.mood.x));
    float nebular = ubuf.mood.y * step(4.5, ubuf.mood.x) * (1.0 - step(5.5, ubuf.mood.x));
    float moodTarget = acceptance;
    if (ubuf.mood.x < 0.5) moodTarget -= mix(0.08, 0.06, middleLayer) * (1.0 - nearLayer);
    else if (ubuf.mood.x < 1.5) moodTarget += mix(0.14, 0.02, middleLayer) * (1.0 - nearLayer);
    // Clearing thins the far dust a little; the middle and near layers keep
    // their population and take a warm cast further down instead.
    else moodTarget -= 0.07 * clearing * (1.0 - middleLayer);
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
            // First nucleus entry is captured once on the CPU, in active
            // seconds. Pre-entry halos stay dark; the birth cohort is unchanged.
            float a = entryAge(entryCell.x,entryCell.y,h.xy);
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
    vec3 footprint = vec3(0.0833333,0.0,0.0833333);
    float lens = 1.0;
    bool filtered = capturePass > -1.5 && (layer < 0.5 || capturePass > 0.5) && ubuf.bhHalo.w > 0.0 && length(screenPixel-ubuf.bhCentre) < ubuf.bhGeometry.y;
    if (filtered) {
        // Source-space pixel covariance, after candidate/support rejection.
        mat2 j = layer < 0.5 ? bhJacobian(screenPixel) : materialJacobian(screenPixel);
        vec2 j0 = vec2(j[0].x,j[1].x), j1 = vec2(j[0].y,j[1].y);
        footprint = vec3(dot(j0,j0),dot(j0,j1),dot(j1,j1))/12.0;
        core = filteredCore(p,sigma,footprint);
        // Microlensing. The same Jacobian's determinant is the area
        // magnification of the lens map, so 1/|det J| is the flux it
        // concentrates into this pixel. Surface brightness is conserved by the
        // filtering above; this is the flux term that filtering alone drops.
        // Far layer only and hard-capped, so a background star crossing the
        // hole brightens over the tens of seconds it takes to drift past and
        // still never outshines a near star. Four ALU where the Jacobian is
        // already in hand, nothing at all anywhere else.
        if (layer < 0.5 && ubuf.lensFlux > 1.0)
            lens = clamp(1.0/max(abs(determinant(j)),0.0001),1.0,ubuf.lensFlux);
    }
    float halo = middleLayer * 0.024 * exp2(-r2 / (mix(3.5, 14.0, nearLayer) * optics * optics));
    float light = (core + halo) * energy * shimmer * lens;

    if (nearLayer > 0.0 && flare == 0.0) {
        // A capped hot point plus redistributed light in a broad Gaussian halo.
        // The shoulder approaches white smoothly instead of clipping a wide core
        // into a flat disc. Sigma and convolution are in physical pixels.
        float hotSigma = min(2.5, optics * mix(0.55, 0.68, h.z) * mix(0.92, 1.08, calm));
        float hotVariance = hotSigma * hotSigma + 0.0833333;
        float hot = exp2(-0.7213475 * r2 / hotVariance) * hotSigma * hotSigma / hotVariance;
        if (filtered) hot = filteredCore(p,hotSigma,footprint);
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
        if (filtered) pairCore = 0.5*(filteredCore(a,sigma,footprint)*cutA+filteredCore(b,sigma,footprint)*cutB);
        light = (pairCore + halo) * energy * shimmer;
        if (nearLayer > 0.5) {
            float hotSigma = min(2.5, optics * mix(0.55, 0.68, h.z) * mix(0.92, 1.08, calm));
            float hotVariance = hotSigma * hotSigma + 0.0833333;
            float pairHot = 0.5 * (exp2(-0.7213475 * a2 / hotVariance) * cutA + exp2(-0.7213475 * b2 / hotVariance) * cutB) * hotSigma * hotSigma / hotVariance;
            if (filtered) pairHot = 0.5*(filteredCore(a,hotSigma,footprint)*cutA+filteredCore(b,hotSigma,footprint)*cutB);
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
    // A nebular mood doubles the tinted share. The extra band [mix, 2*mix) is
    // only fetched while the mood is running, and those stars take their colour
    // weighted by the same eased weight, so they saturate in and out.
    vec3 plain = mix(tint, vec3(1.0), nearLayer * 0.35);
    float tintBand = birth.y * (1.0 + nebular);
    if (birth.z > 0.5 && middleLayer > 0.5 && draws.z < tintBand) {
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
        if (draws.z >= birth.y) tint = mix(plain, tint, nebular);
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
        tint = plain;
    }
    // Clearing warms the material the far dust stopped hiding.
    if (clearing > 0.0 && middleLayer > 0.5)
        tint = mix(tint, tint * vec3(1.06, 1.0, 0.92), ubuf.mood.y);
    return light * tint * visibility * behaviour;
}

// ---- v12: THE ABLATION STREAK -------------------------------------------
// "commets and metorieds ... they seems to be underdeveloped and unrealistic
//  ... because the rail looks underdeveloped they just apper and disaper they
//  dont burn change glare deform like a real once." (ledger 2404)
//
// Four verbs, and the kernel below this comment did none of them. It drew a
// meteor BACKWARDS: brightest at entry (the envelope peaked at 9 % of the
// life), decelerating 10.5x, with a trail that was five samples of the head's
// own path -- so it could not be displaced, could not outlive the head, and
// got SHORTER as the meteor aged.
//
// A real one is a 4 m column of vapour that RISES to a maximum around the
// middle of its path and falls after it, and everything that makes the head
// look like a glowing ball is bloom convolved with saturation, which is why
// the saturated disc grows with the LOGARITHM of the brightness and why the
// right way to draw a flare is to grow the disc rather than to raise a value
// the display is already clipping.
//
// THE LIGHT CURVE. F is the fraction of the path flown before maximum;
// measured over 113 light curves it is 0.52 +- 0.09.
//   L(x) = (x/F)^a * ((1-x)/(1-F))^b,   a = s*F,  b = s*(1-F),  so F = a/(a+b)
// One exp2 over two log2 rather than two pow(), and exactly 1 at x = F.
//
// A NUMBER WORTH KNOWING BEFORE TUNING `s`: the measured "pointedness"
// P = width at -1 mag / width at -2 mag is 0.70 +- 0.05, and for this curve
// family P = 1/sqrt(1 + 2^(-2/s)) at F = 0.5, which is bounded BELOW by
// 1/sqrt(2) = 0.707 however sharp s is made. The measured 0.70 is not
// reachable by making this curve sharper; it would need a different family.
// s = 4.5 sits at P = 0.78, inside the acceptance window, with the half
// maximum spanning about half the path -- a broad fusiform, which is what the
// bolide reference is a photograph of.
float lightCurve(float x, float F, float s) {
    float u = clamp(x, 0.0005, 0.9995);
    float f = clamp(F, 0.08, 0.92);
    return exp2(s * (f * log2(u / f) + (1.0 - f) * log2((1.0 - u) / (1.0 - f))));
}
// Sodium's along-path profile, and the whole of "change colour" in one curve.
// Na and K vaporise at ~99 km and "vaporization is almost complete before other
// elements start to evaporate"; Fe, Mg and Si peak 5-15 km lower. Five km of
// altitude at a 45 degree entry is 0.17 of a 42 km path and the 10-15 km figure
// gives 0.33-0.50, so the warm emitter LEADS the maximum by roughly a quarter
// of the path -- and Borovicka's Draconid 4 puts it plainly: "at the
// disintegration end height, almost all the sodium had evaporated."
//
// So the meteor runs warm early and then STOPS being warm, and what is left
// underneath is the blue-white of magnesium and iron. No hue is interpolated
// into another anywhere in this: one emitter switches off and a different one
// is what remains. That is his rule and the physics at the same time.
float naProfile(float pu, float F) {
    float c = (pu - clamp(F - 0.25, 0.06, 0.80)) * 3.3333333;
    return exp2(-1.4426950 * c * c) * smoothstep(0.95, 0.62, pu);
}
// One segment of a streak's trail, and the shared body of every meteor in the
// sky: eventSlot's style 0 calls it per polyline segment, meteorStorm calls it
// once per accepted candidate with a straight radial ray.
//   head  = (x, y, headSigmaPx, gain)
//   shape = (totalPx, headShare, segments, glare)
//   burn  = (F, headPathU, pathSpan, speed01)
//   tone  = (naGain, trainGain, leadGain, curveSharp)
//
// THREE EMITTERS ON ONE CENTRELINE, each with its own along-path profile, its
// own width and a FIXED tone. The colour along the path changes because which
// emitter is bright there changes -- never because one hue is interpolated
// into another, which is the rule the v12 supernova's grain populations were
// built to obey as well (ledger 2403).
//
//   wake       the head's own tone, lit by the light curve where the head WAS
//              when it passed. This is what turns a taper into a lens.
//   Na sheath  fixed orange-yellow, the 589 nm doublet. Sodium is released at
//              ~99 km, about 5 km ABOVE where magnesium and iron peak, and
//              "almost all the sodium had evaporated" by the end: the warm
//              tone LEADS the maximum by a quarter of the path and is gone
//              before the meteor is.
//   [O I] train  fixed green, the forbidden 557.7 nm line -- ATMOSPHERIC
//              oxygen, not the meteoroid. It therefore exists only where the
//              head has already been (zero at the head, rising behind it) and
//              it is what is LEFT when the head dies.
//
// WIDTH GROWS WITH AGE. A real train expands radially at 10.5 m/s, near
// constant and independent of altitude between 86 and 97 km, so the oldest
// part is always the widest. Style 0 shipped 1.0 - 0.65u, shrinking by 65 %,
// while stormTrainSegment forty lines down already had 0.55 + 1.4u. Two code
// paths drawing the same physical object disagreed about its shape.
vec3 ablationStreak(vec2 pixel, vec2 a, vec2 b, float travelled, vec4 head, vec4 shape, vec4 burn, vec4 tone, vec3 headTone) {
    vec2 v = b - a;
    float len = sqrt(dot(v, v));
    if (len < 0.001) return vec3(0.0);
    float t = clamp(dot(pixel - a, v) / (len * len), 0.0, 1.0);
    float du = clamp((travelled + t * len) / max(shape.x, 0.001), 0.0, 1.0);
    vec2 delta = pixel - mix(a, b, t);
    float r2 = dot(delta, delta);
    float sigma = max(head.z, 0.35);
    // Compact support, cut where every emitter is already under a 255th: the
    // widest is the saturation bloom at 2.4 x the local width, and the local
    // width reaches 4.6 sigma at the far end, so 34 sigma is 3.1 of the widest
    // Gaussian's own sigma and the taper below finishes it.
    float support = sigma * 34.0;
    if (r2 >= support * support) return vec3(0.0);
    float w = sigma * (1.4 + 3.2 * du);
    float pu = burn.y - du * burn.z;
    float L = lightCurve(pu, burn.x, max(tone.w, 0.5));
    float age = 1.0 - du;
    float share = 2.0 * (1.0 - shape.y);
    // The wake and its sodium are the vapour cloud, and a point in it stays
    // lit for a fraction of a second; the [O I] train is atmospheric oxygen
    // that keeps glowing for seconds. TWO DIFFERENT CLOCKS, which is what
    // makes the near half of a streak white and the far half green -- one
    // emitter has gone out and a different one has not. Nothing crossfades.
    float fade = 0.30 + 0.70 * age;
    // The wake fades behind the head on its own clock, ON TOP of the light
    // curve: a point is lit by how bright the head was there and then goes out.
    float wake = L * exp2(-1.4426950 * r2 / (w * w)) * fade;
    // ...and it BLOOMS where it is bright, for the same reason the head does.
    // A real train expands radially at only 10.5 m/s, which over the third of
    // a second of path this trail covers is three metres against a four-metre
    // head: the breadth in every photograph of a meteor is not the column
    // getting wider, it is the point-spread function convolved with
    // SATURATION. So the width here is driven by L squared -- a bright stretch
    // flares out and a faint one stays a hairline, which is what the closeup
    // reference shows (a trail four times wider than its own head three head
    // widths behind it) and what the shipped taper could not do at all.
    float wb = w * 2.4;
    vec3 sum = headTone * ((wake + 0.30 * L * L * exp2(-1.4426950 * r2 / (wb * wb)) * fade) * share);
    if (tone.x > 0.0) {
        // Sodium is a neutral-atom line in the vapour cloud and it goes out
        // FAST -- faster than the wake continuum it sits in. That is the third
        // clock, and it is what leaves the far end of a bright streak to the
        // green train alone instead of to a warm haze.
        float wn = w * 1.15;
        sum += vec3(1.00, 0.58, 0.19) * (tone.x * naProfile(pu, burn.x)
             * exp2(-1.4426950 * r2 / (wn * wn)) * (0.10 + 0.90 * age * age) * share);
    }
    if (tone.y > 0.0) {
        // The green train. sqrt(L) rather than L: the line saturates, so a
        // faint stretch of path still leaves something behind it. The 0.55 is
        // the width compensation -- this emitter is drawn 2.2 x wider than the
        // wake, so at equal peak it would carry twice the FLUX and the streak
        // reads as a green laser rather than as a white streak with a green
        // train behind it. Checked on a 2x crop, not on a contact sheet.
        float wt = w * 1.8;
        float tr = smoothstep(0.0, 0.18, du) * sqrt(L)
                 * exp2(-1.4426950 * r2 / (wt * wt)) * (0.62 + 0.38 * age);
        sum += vec3(0.48, 1.00, 0.58) * (tone.y * 0.55 * tr * share);
    }
    // The same edge taper the shipped kernel used, so the bounding box can
    // never cut a glow on a straight line.
    return sum * (1.0 - smoothstep(0.64 * support * support, support * support, r2));
}
// CPU bounds and at most six connected segments across three generic slots.
// Every segment uses total tail distance for opacity/width. max-combination
// avoids bright joints; the nucleus is evaluated exactly once per slot.
// STYLE 2 ONLY since v12 -- a meteor's trail is ablationStreak() above.
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
    float support = head.z * 14.0;
    if (r2 >= support * support) return 0.0;
    float variance = width * width + 0.0833333;
    float light = exp2(-0.7213475 * r2 / variance) * width / sqrt(variance);
    light *= pow(1.0 - u, style > 0.5 ? 1.6 : 2.0);
    // Style 0 leaves an ionisation train: a wide, dim component that outlives
    // the bright core of the streak, so a meteor leaves something behind
    // instead of a clean hairline. Its own (1-u) power is shallower, which is
    // what makes the train read as persistence rather than as a fatter streak.
    if (style < 0.5) {
        float train = width * 5.0 + 1.6;
        light += 0.18 * exp2(-0.7213475 * r2 / (train * train)) * pow(1.0 - u, 0.7);
    }
    return light * (1.0 - smoothstep(0.64 * support * support, support * support, r2));
}
// Style 5, comet: nucleus and coma, a straight bluish ion tail and a curved,
// striated warm dust tail, both anti-sunward from the only light source on the
// sky (the hole, or the radial centre when it is off). Every tail brightens
// toward the nucleus. ~2 exp2 for the coma, 1 exp2 + 1 cos per tail, inside
// the CPU bounds only.
//   head   = (x, y, nucleusSigmaPx, gain)
//   tail01 = (ionDirX, ionDirY, ionLengthPx, ionWidthPx)
//   tail23 = (dustDirX, dustDirY, dustLengthPx, dustWidth0Px)
//   tail4  = (dustCurve, comaSigmaPx)
//   shape  = (ionGain, dustGain, comaGain, striationAmp)
// v12. Value noise from one integer hash, C1 by pre-easing the fractional
// part -- the same trick nebulaTap uses on the noise texture, done
// arithmetically so the comet kernel needs no sampler and the three offscreen
// sheets need no texture bound to render a comet.
float cometHash(vec2 p) {
    vec3 v = fract(vec3(p.x, p.y, p.x) * 0.1031);
    v += dot(v, vec3(v.y, v.z, v.x) + 33.33);
    return fract((v.x + v.y) * v.z);
}
float cometGrain(vec2 q) {
    vec2 i = floor(q), f = q - i;
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(cometHash(i), cometHash(i + vec2(1.0, 0.0)), f.x),
               mix(cometHash(i + vec2(0.0, 1.0)), cometHash(i + vec2(1.0, 1.0)), f.x), f.y);
}
//   burn = (synchronePhase, striaeOffsetRad, striaeBands, dustReddening)
vec3 cometField(vec2 pixel, vec4 head, vec4 colour, vec4 tail01, vec4 tail23, vec2 tail4, vec4 shape, vec4 burn) {
    vec2 p = pixel - head.xy;
    float r2 = dot(p, p);
    float sigma2 = head.z * head.z;
    float variance = sigma2 + 0.0833333;
    float nucleus = exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
    float coma2 = max(tail4.y * tail4.y, 0.0001);
    float inner = exp2(-0.7213475 * r2 / coma2);
    float outer = exp2(-0.1000000 * r2 / coma2);
    vec3 sum = (nucleus * 1.30 + shape.z * (inner * 0.72 + outer * 0.26)) * mix(colour.rgb, vec3(1.0), 0.55);
    if (shape.x > 0.0 && tail01.z > 0.0) {
        vec2 d = tail01.xy;
        float along = dot(p, d);
        if (along > 0.0 && along < tail01.z) {
            float u = along / tail01.z;
            float across = dot(p, vec2(-d.y, d.x));
            float w = max(tail01.w * (0.8 + 1.7 * u), 0.5);
            // Ion rays: near-parallel streamers, so the modulation is in the
            // across coordinate and drifts slowly down the tail.
            float ray = 1.0 + shape.w * 0.75 * cos(9.0 * across / w + 3.1 * u);
            sum += shape.x * exp2(-1.4426950 * across * across / (w * w)) * pow(1.0 - u, 1.5)
                 * max(ray, 0.0) * smoothstep(0.0, 0.06, u) * mix(vec3(0.50, 0.69, 1.0), colour.rgb, 0.32);
        }
    }
    if (shape.y > 0.0 && tail23.z > 0.0) {
        vec2 d = tail23.xy;
        float along = dot(p, d);
        if (along > 0.0 && along < tail23.z) {
            float u = along / tail23.z;
            // The parabola is applied to the SAMPLE point, so the curved tail
            // is a straight one in warped space: six ops, no curve solve.
            float across = dot(p, vec2(-d.y, d.x)) - tail4.x * u * u * tail23.z;
            // ASYMMETRIC EDGE. A dust tail has a HARD sunward edge and a
            // DIFFUSE trailing one, against the ion tail's two sharp ones.
            // That contrast is the cheapest cue that sells two tails as two
            // different things, and it is one sign test.
            float w = max(tail23.w * (0.7 + 2.8 * u) * (across > 0.0 ? 0.70 : 1.45), 0.5);
            // ---- SYNCHRONES, AND THEY MOVE. The shipped modulation had NO
            // TIME TERM, so the pattern was welded to the tail and the tail
            // was a decal: over an 8.4 s pass nothing about it changed except
            // its position. burn.x is 2*pi*age/striaeDriftSec, so the bands
            // march outward and new ones appear at the head. One argument, and
            // the single highest-value edit in this kernel.
            float syn = cos(13.0 * u - burn.x);
            // ---- STRIAE, A SECOND FAMILY, and this corrects an easy mistake.
            // Synchrones point back at the nucleus; striae are closer to
            // SUN-ALIGNED and are OFFSET from the local synchrone. Hale-Bopp
            // showed at least 12 straight bands 1.5-3 degrees from the
            // nucleus, each 1-3 arcmin wide -- an aspect of 20:1 to 60:1 with
            // spacing about their own width. The offset angle is the one
            // physical number the research could not pin down (Pfeifer & Jones
            // 2019 was not reachable open-access), so it is a config key with
            // a range, tuned by eye against the McNaught and West references,
            // and said so rather than invented.
            float band = u * cos(burn.y) + (across / tail23.z) * sin(burn.y);
            float str = cos(6.2831853 * burn.z * band - 0.35 * burn.x);
            // ---- GRAIN, so the tail is made of something. Two octaves of
            // value noise in the tail's own (u, across) frame, ADVECTED by u
            // so it flows outward with the dust rather than sitting still, and
            // the second octave rotated so the two lattices have no common
            // structure to lock to (V11 noise rule 2).
            vec2 q = vec2(u * 7.0 - 0.22 * burn.x, across / w * 1.6);
            vec2 q2 = vec2(q.x * 0.6820 - q.y * 0.7314, q.x * 0.7314 + q.y * 0.6820) * 2.17 + 11.3;
            float grain = cometGrain(q) * 0.62 + cometGrain(q2) * 0.38;
            float texture = 1.0 + shape.w * (0.46 * syn + 0.30 * str + 0.70 * (grain - 0.5));
            // ---- COLOUR WARMS OUTWARD. The dust is reflected sunlight,
            // slightly redder than the Sun, and the reddening RISES with
            // distance from the nucleus: about 5-8 % per 1000 A in the inner
            // coma to ~15 % along the tail axis.
            vec3 warm = vec3(1.0, 0.87 * (1.0 - 0.30 * burn.w * u), 0.64 * (1.0 - 0.85 * burn.w * u));
            sum += shape.y * exp2(-1.4426950 * across * across / (w * w)) * pow(1.0 - u, 1.25)
                 * max(texture, 0.0) * smoothstep(0.0, 0.05, u) * mix(warm, colour.rgb, 0.32);
        }
    }
    return head.w * max(sum, vec3(0.0));
}
// Style 6, supernova, THE POINT SOURCES: the precursor star, the core-collapse
// flash and its bloom, the diffraction spikes, and the neutron star blinking at
// the centre afterwards. Everything DISTRIBUTED -- the shock front, the sheets,
// the cavities, the filigree rim, the jets and the outer wisps -- moved out of
// here in v11 into supernovaRemnant(), which is a SKY layer: it composites into
// the far field like the nebula passage does, so it can take light away as well
// as add it and the stars shine through the remnant instead of over it.
//   head    = (x, y, coreSigmaPx, peak)
//   colour  = (r, g, b, 6)                      the phase's primary colour
//   tail01  = (haloSigmaPx, haloGain, coreGain, unused since v11)
//   shape   = (shellRadiusPx, shellWidthPx, filamentAmp, toneWeight)  published
//             for the harnesses and the sheets; the shock is drawn from snShell
// plus ubuf.snExtra. Every gain is a fraction of head.w.
vec3 supernovaField(vec2 pixel, vec4 head, vec4 colour, vec4 tail01, vec4 shape) {
    vec2 p = pixel - head.xy;
    float r2 = dot(p, p);
    float sigma2 = head.z * head.z;
    float variance = sigma2 + 0.0833333;
    vec3 hot = colour.rgb;
    // The point: the precursor star, the collapse core, and the halo that grows
    // into the flash's bloom and shrinks back out of it.
    float value = tail01.z * exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
    if (tail01.y > 0.0 && tail01.x > 0.0)
        value += tail01.y * exp2(-0.7213475 * r2 / (tail01.x * tail01.x));
    vec3 sum = value * hot;
    // Diffraction spikes: four cardinal rays and four at 45 degrees at half the
    // gain, on the episode's frozen angle. A long anisotropic Gaussian tapered
    // along its own length reads as a ray; without the taper it is a bar.
    if (ubuf.snExtra.x > 0.0 && ubuf.snExtra.y > 0.0) {
        float c = cos(ubuf.snExtra.w), s = sin(ubuf.snExtra.w);
        vec2 a1 = vec2(c * p.x + s * p.y, c * p.y - s * p.x);
        vec2 a2 = vec2(a1.x + a1.y, a1.y - a1.x) * 0.70710678;
        float wd = max(head.z * 0.85, 1.2);
        vec2 t1 = max(vec2(0.0), 1.0 - abs(a1) / ubuf.snExtra.y);
        vec2 t2 = max(vec2(0.0), 1.0 - abs(a2) / ubuf.snExtra.y);
        float ray = exp2(-1.4426950 * a1.y * a1.y / (wd * wd)) * t1.x * t1.x
                  + exp2(-1.4426950 * a1.x * a1.x / (wd * wd)) * t1.y * t1.y
                  + 0.45 * exp2(-1.4426950 * a2.y * a2.y / (wd * wd)) * t2.x * t2.x
                  + 0.45 * exp2(-1.4426950 * a2.x * a2.x / (wd * wd)) * t2.y * t2.y;
        sum += ubuf.snExtra.x * ray * vec3(0.82, 0.89, 1.0);
    }
    // The neutron star the collapse left behind: a hard blue-white point on the
    // core's own sigma, blinking on the CPU's raised cosine.
    if (ubuf.snExtra.z > 0.0)
        sum += ubuf.snExtra.z * exp2(-0.7213475 * r2 / variance) * sigma2 / variance * vec3(0.76, 0.85, 1.0);
    return head.w * max(sum, vec3(0.0));
}
// Style 3, radial: core + halo + ring + echo ring. One kernel draws nova,
// supernova, hypernova, star birth, red giant, a pulsar's point and a light
// echo; they differ only in the CPU envelope, colour, size and schedule. Three
// exp2 and about twenty-five ALU inside the bounds, one compare outside.
//   head   = (x, y, coreSigmaPx, gain)
//   shape  = (haloSigmaPx, ringGain, ringWidthPx, ringRadiusPx)
//   tail01 = (echoRadiusPx, echoGain, haloGain, coreGain)
// The colour is already resolved and whitened on the CPU, so nothing here
// re-tints it and a family can be as warm or as neutral as its envelope wants.
vec3 radialField(vec2 pixel, vec4 head, vec4 colour, vec4 tail01, vec4 shape, vec4 bounds) {
    if (head.w <= 0.0 || pixel.x < bounds.x || pixel.y < bounds.y || pixel.x > bounds.z || pixel.y > bounds.w) return vec3(0.0);
    // Style 6, v9's supernova: its own kernel, its own four vectors. Bounded
    // above as well as below - style 7 (the storm's fireball) is dispatched by
    // eventSlot and must never fall through to here.
    if (colour.w > 5.5 && colour.w < 6.5) return supernovaField(pixel, head, colour, tail01, shape);
    vec2 p = pixel - head.xy;
    float r2 = dot(p, p);
    float sigma2 = head.z * head.z;
    float variance = sigma2 + 0.0833333;
    // Style 4, gamma-ray burst: core + halo + two OPPOSED cones. No rings, so
    // the ring channel is re-read as the beam and tail01 as the gains.
    //   tail01 = (haloSigmaPx, haloGain, coreGain, beamGain)
    //   shape  = (dirX, dirY, beamLengthPx, beamWidthPx)
    if (colour.w > 3.5) {
        float value = tail01.z * exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
        if (tail01.y > 0.0 && tail01.x > 0.0)
            value += tail01.y * exp2(-0.7213475 * r2 / (tail01.x * tail01.x));
        if (tail01.w > 0.0 && shape.z > 0.0) {
            float along = abs(dot(p, shape.xy));
            float u = along / shape.z;
            if (u < 1.0) {
                float across = dot(p, vec2(-shape.y, shape.x));
                float w = max(shape.w * (0.30 + 1.0 * u), 0.5);
                // smoothstep off the origin keeps the cones from doubling the
                // core; pow(1-u,2) is what makes them read as beams, not bars.
                value += tail01.w * exp2(-1.4426950 * across * across / (w * w))
                       * (1.0 - u) * (1.0 - u) * smoothstep(0.0, 0.10, u);
            }
        }
        return head.w * max(value, 0.0) * colour.rgb;
    }
    float value = tail01.w * exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
    if (tail01.z > 0.0 && shape.x > 0.0)
        value += tail01.z * exp2(-0.7213475 * r2 / (shape.x * shape.x));
    if (shape.z > 0.0 && (shape.y > 0.0 || tail01.y > 0.0)) {
        float d = sqrt(r2);
        if (shape.y > 0.0) {
            float t = (d - shape.w) / shape.z;
            value += shape.y * exp2(-1.4426950 * t * t);
        }
        // The echo is the same ring further out and twice as soft. It is its
        // own branch, not nested in the shell's: a light echo outlives the
        // shell that threw it.
        if (tail01.y > 0.0) {
            float e = (d - tail01.x) / (shape.z * 2.0);
            value += tail01.y * exp2(-1.4426950 * e * e);
        }
    }
    return head.w * max(value, 0.0) * colour.rgb;
}
// ---- Meteor storm -------------------------------------------------------
// One integer hash, no transcendental: the angle reject runs once per candidate
// per pixel and is the whole cost of a storm for the pixels no streak crosses.
float stormHash(float k, float salt) {
    float x = fract((k + salt) * 0.1031);
    x *= x + 33.33;
    x *= x + x;
    return fract(x);
}
// ---- v12: THE PERSISTENT TRAIN, which is the "deform" he asked for by name
//
// WHAT IT WAS. Four points on the head's own path, each pulled along its own
// frozen bearing by at most shortSide * 0.045. Swept on his tablet, a 20 s
// train turned through 1.8 to 7.5 degrees over its WHOLE LIFE with a sagitta
// of 0.3-2.3 % of its chord: a straight line, and structurally so -- three
// segments admit at most one inflection, so it could bow and could never kink,
// S-bend or loop. The offscreen sheet shows it: a featureless grey bar, fading.
//
// WHAT A REAL ONE DOES, from the six-panel evolution of one real train
// (Cordonnier 2024 Fig. 1; that train lasted at least 22 minutes):
//   0-5 s      essentially straight, brightest, GREEN ([O I] 557.7 + metals)
//   5-30 s     first visible bend or S-kink; colour shifting off green
//   30 s-2 m   pronounced kinks, one or two LOOPS, bright knots at the folds
//   2-10 m     corkscrew or a split pair; dull ORANGE FeO continuum; widening
//   > 10 m     turbulent diffusion, and the HIGH end blurs out first
//
// THE MECHANISM IS WIND SHEAR, and it is measured: horizontal winds at 90 km
// run to a few tens of m/s, and 27 m/s to 81 m/s were measured at different
// points OF ONE REAL PERSEID TRAIN. That DIFFERENTIAL is the shear. The config
// key is therefore a wind speed and the pixel amplitude is derived from it
// through the storm's own gnomonic focal length; see captureStorm.
//
// THE FOLD IS THE POINT. A displacement across the track is a graph over the
// along-track coordinate and can never double back on itself, however large it
// is made -- so a pure shear gives kinks and never a loop. Warping the ALONG
// coordinate makes v -> along non-monotonic, and a non-monotonic centreline is
// exactly what a loop is. The train is therefore evaluated as an eight-segment
// polyline whose vertices are warped in both coordinates, not as a displaced
// straight ray: the vertices are free, so the curve can cross itself.
//
//   frame = (o, d, n, lengthPx)     the train's own frame
//   warp  = (shearPx, fold, phase, clockSec)
vec2 trainPoint(vec2 o, vec2 d, vec2 n, float len, float v, vec4 warp) {
    float ph = warp.z;
    // Held at zero until the fold time and then grown, so loops appear LATE --
    // which is when real ones show them.
    float kF = 1.15 + 1.35 * fract(ph * 0.6180339);
    float uu = v + warp.y * sin(6.2831853 * kF * v + ph * 6.2831853 + 0.17 * warp.w);
    // Three terms of a wind spectrum, amplitude ~ 1/k so the long wavelengths
    // carry it, each creeping at its OWN small rate: the shape then morphs
    // instead of sliding, which is the difference between a train deforming
    // and a train being dragged. 0.4288 normalises the three amplitudes to 1.
    float s = 1.66667 * sin(3.769911 * uu + ph * 4.1 + 0.031 * warp.w)
            + 0.47619 * sin(13.19469 * uu + ph * 7.7 + 0.053 * warp.w)
            + 0.18868 * sin(33.30088 * uu + ph * 11.3 + 0.079 * warp.w);
    s *= warp.x * 0.4288 * (0.22 + 0.78 * clamp(uu, 0.0, 1.2));
    return o + d * (len * uu) + n * s;
}
// The across-track wind spectrum on its own, evaluated at the SAMPLE POINT
// rather than at eight vertices. The slot fireball's train is one object and
// gets the polyline above, and therefore gets loops; a storm's own trains are
// many, they are the dimmest things on the screen, and they get this -- three
// sines and no fold. It still kinks, because a three-term spectrum at three
// scales does; it cannot double back on itself, because a displacement across
// the track is a graph over the along-track coordinate. That is the honest
// difference between the two, and it is a cost decision: sixteen candidates
// with the polyline would be about 150 ALU on every pixel of the buffer.
float trainShear(float u, float ph, float t) {
    return (1.66667 * sin(3.769911 * u + ph * 4.1 + 0.031 * t)
          + 0.47619 * sin(13.19469 * u + ph * 7.7 + 0.053 * t)
          + 0.18868 * sin(33.30088 * u + ph * 11.3 + 0.079 * t)) * 0.4288;
}
// The drawn train: eight capsules on the warped centreline, max-combined so a
// fold crossing itself brightens like a fold and not like a sum.
//   widen  the diffusion factor; diffusivity goes as 1/pressure, so the HIGH
//          end of a train -- the end nearest where the head died, which was
//          highest -- blurs out first. One term, and almost nobody renders it.
float stormTrainRay(vec2 pixel, vec2 o, vec2 d, float len, float width, vec4 warp, float widen) {
    vec2 n = vec2(-d.y, d.x);
    float best = 0.0;
    vec2 prev = trainPoint(o, d, n, len, 0.0, warp);
    for (int i = 1; i <= 8; ++i) {
        vec2 cur = trainPoint(o, d, n, len, float(i) * 0.125, warp);
        vec2 ab = cur - prev;
        float L2 = dot(ab, ab);
        float t = L2 > 1e-6 ? clamp(dot(pixel - prev, ab) / L2, 0.0, 1.0) : 0.0;
        vec2 delta = pixel - (prev + ab * t);
        float r2 = dot(delta, delta);
        float u = (float(i - 1) + t) * 0.125;
        float w = width * (0.55 + 1.4 * u) * (1.0 + (widen - 1.0) * (1.0 - 0.55 * u));
        if (r2 < w * w * 20.25)
            best = max(best, exp2(-1.4426950 * r2 / (w * w)) * (1.0 - 0.45 * u));
        prev = cur;
    }
    return best;
}
// SUPERSEDED by stormTrainRay above, kept because the v9/v11 offscreen sheets
// and their committed numbers are rendered through the lifted kernel by name.
// Style 7, a storm fireball's persistent train. Wider and softer than a
// meteor's streak, and it does not taper to a point: a train is what is LEFT
// after the head has gone, so its brightness falls with age (on the CPU) and
// along its own length, but its width grows.
float stormTrainSegment(vec2 pixel, vec2 a, vec2 b, float travelled, float total, float width) {
    vec2 v = b - a;
    float len = sqrt(dot(v, v));
    if (len < 0.001) return 0.0;
    float t = clamp(dot(pixel - a, v) / (len * len), 0.0, 1.0);
    float u = clamp((travelled + t * len) / max(total, 0.001), 0.0, 1.0);
    float w = width * (0.55 + 1.4 * u);
    vec2 delta = pixel - mix(a, b, t);
    float r2 = dot(delta, delta);
    float support = width * 9.0;
    if (r2 >= support * support) return 0.0;
    return exp2(-1.4426950 * r2 / (w * w)) * (1.0 - 0.55 * u)
         * (1.0 - smoothstep(0.55 * support * support, support * support, r2));
}
// Style 7, a storm fireball: nucleus + terminal flash + a persistent train the
// CPU drifts and shears for ten to thirty seconds. The train travels as four
// points in the slot's existing vectors, so it needs no uniform of its own.
//   head   = (x, y, headSigmaPx, gain)
//   colour = (r, g, b, 7)
// v12 re-laid the vectors: the train is a RAY with a warp, not four points.
//   tail01 = (originX, originY, dirX, dirY)   origin is the head end
//   tail23 = (lengthPx, shearPx, fold, phase)
//   tail4  = (trainWidthPx, trainGain)
//   shape  = (diffuseWiden, flashSigmaPx, nucleusGain, flashGain)
//   burn   = (greenWeight, metalWeight, feoWeight, trainClockSec)
vec3 stormFireball(vec2 pixel, vec4 head, vec4 colour, vec4 tail01, vec4 tail23, vec2 tail4, vec4 shape, vec4 burn, vec4 tone) {
    vec2 p = pixel - head.xy;
    float r2 = dot(p, p);
    float sigma2 = head.z * head.z;
    float variance = sigma2 + 0.0833333;
    float value = shape.z * exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
    if (shape.w > 0.0 && shape.y > 0.0)
        value += shape.w * exp2(-0.7213475 * r2 / (shape.y * shape.y));
    vec3 sum = value * mix(colour.rgb, vec3(1.0), 0.40);
    if (tail4.y > 0.0 && tail23.x > 0.0) {
        float train = stormTrainRay(pixel, tail01.xy, tail01.zw, tail23.x, tail4.x,
                                    vec4(tail23.y, tail23.z, tail23.w, burn.w), shape.x);
        // THREE TONES ON THREE CLOCKS, and this is his colour rule stated by
        // the chemistry. A persistent train has three phases and they are
        // three different emitters, not one hue sliding into another:
        //   afterglow      a few seconds, several thousand K -- the forbidden
        //                  [O I] 557.7 nm green with the neutral metals
        //   recombination  tens of seconds -- Mg I 383, Fe I, OH, O2
        //   continuum      the rest of its life -- a broad molecular band, the
        //                  leading candidate FeO, giving the "orange arc" at
        //                  570-630 nm, measured at ~40x the Na D lines. A late
        //                  train is DISTINCTLY ORANGE, not grey.
        // The weights are the CPU's, one per phase, computed on the train's
        // own clock.
        vec3 trainTone = burn.x * vec3(0.50, 1.00, 0.60)
                       + burn.y * vec3(1.00, 0.92, 0.72)
                       + burn.z * vec3(1.00, 0.52, 0.16);
        sum += (tail4.y * train) * trainTone;
    }
    return head.w * max(sum, vec3(0.0));
}
// The storm itself. Nothing about an ordinary storm streak reaches the CPU:
// this kernel generates all of them from the storm's seed and its phase.
//   stormHead   = (radiantX, radiantY, phase, ratePerSec)
//   stormShape  = (headSigmaPx, trailLoRad, trailHiRad, gain)
//   stormColour = (tintR, tintG, tintB, paletteMix)
//   stormSpan   = (window, earthgrazerShare, fragmentShare, seed)
//
// PHASE is the storm's cumulative expected meteor count, integrated on the CPU
// from the rate hump. Streak k launches where phase == k, so k advances at
// exactly `rate` per second whatever the hump is doing, and a streak's age
// comes back as (phase - k)/rate. That inversion is EXACT for a constant or a
// linear rate; under the hump's curvature it stretches a long streak's apparent
// life by a few per cent, which is smaller than the variety draw sitting next
// to it. It cannot move the rate, because the rate is phase's derivative.
//
// The projection is gnomonic about the radiant: a shower meteor travels a great
// circle away from it, which projects to a straight RADIAL line, and its
// apparent length is f*(tan(theta) - tan(theta - trail)). That is the
// perspective foreshortening for free - a meteor beside the radiant is a point,
// one sixty degrees away is a long streak - and it is what lets a single angle
// compare reject a candidate, because every streak lies on a ray from one point.
vec3 meteorStorm(vec2 pixel) {
    float gain = ubuf.stormShape.w;
    if (gain <= 0.0) return vec3(0.0);
    vec2 rel = pixel - ubuf.stormHead.xy;
    float d = length(rel);
    float focal = min(ubuf.resolution.x, ubuf.resolution.y);
    float phi = atan(rel.y, rel.x);
    float rate = max(ubuf.stormHead.w, 0.02);
    float seed = ubuf.stormSpan.w;
    float base = ubuf.stormShape.x;
    float support = base * 17.0 + 4.0;
    float top = floor(ubuf.stormHead.z);
    float frac = ubuf.stormHead.z - top;
    int window = int(ubuf.stormSpan.x);
    vec3 sum = vec3(0.0);
    // 48 is the hard bound: the CPU never asks for more than ceil(8*5.5)+3 =
    // 47 candidates, because peakRate is validated at 8 a second and 5.5 s is
    // the longest life in here. Candidates past `window` are not iterated.
    for (int j = 0; j < 48; ++j) {
        if (j >= window) break;
        float k = top - float(j);
        float a = stormHash(k, seed) * 6.2831853;
        float dphi = phi - a;
        dphi -= 6.2831853 * floor(dphi * 0.1591549 + 0.5);
        float across = dphi * d;
        if (abs(across) > support) continue;
        vec4 h = hash4(vec2(k * 0.017, seed));
        vec4 g = hash4(vec2(seed + 7.31, k * 0.017));
        // An earthgrazer is the same streak drawn slowly and far from the
        // radiant: long, shallow, and alive for seconds instead of one.
        float grazer = step(h.x, ubuf.stormSpan.y);
        // 0.30-0.90 rad/s is a meteor crossing twenty to forty degrees of sky in
        // its own second, and it is also what keeps one ON the buffer: the short
        // side spans about fifty degrees here, so a faster streak would cross it
        // in a third of its life and the storm would look emptier than its rate.
        float omega = mix(0.30 + 0.60 * h.y, 0.08 + 0.10 * h.y, grazer);
        float life = mix(0.65 + 1.30 * h.z, 3.0 + 2.5 * h.z, grazer);
        float age = (frac + float(j)) / rate;
        if (age > life) continue;
        // A fast streak starts nearer the radiant, so it has room to run before
        // it leaves the sky; an earthgrazer starts furthest out, which is where
        // one is seen. Both are the same draw, biased by the speed it made.
        float fast = clamp((omega - 0.30) / 0.60, 0.0, 1.0);
        float theta = min(mix(0.05, 0.95, h.w * h.w) * (1.0 - 0.45 * fast) + mix(0.0, 0.40, grazer) + omega * age, 1.35);
        float dh = focal * tan(theta);
        float trail = mix(ubuf.stormShape.y, ubuf.stormShape.z, g.x) * mix(1.0, 2.2, grazer);
        float dt = focal * tan(max(theta - min(trail, omega * age + 0.004), 0.004));
        if (d < dt - support || d > dh + support) continue;
        float sigma = base * mix(0.66, 1.33, g.w);
        // In over six per cent of its life and out over the last twenty-eight:
        // a streak never appears or vanishes on a frame.
        float env = smoothstep(0.0, 0.06 * life, age) * smoothstep(0.0, 0.28 * life, life - age);
        // Cubed uniform: many faint, few bright. This is the distribution, not
        // a taste dial - a real shower is mostly meteors you almost miss. The
        // floor is where a head still clears 139/255 against a bright star's
        // 243: faint enough to be the many, bright enough to be seen at all.
        float bright = (0.28 + 0.72 * g.y * g.y * g.y) * env;
        float span = max(dh - dt, 1.0);
        float u = clamp((dh - d) / span, 0.0, 1.0);
        // v12: the same light curve the slot meteors fly. The path fraction a
        // drawn point was flown at is EXACT in theta and costs no
        // transcendental, because theta = theta0 + omega*age: the head is at
        // age/life of its path and the drawn trail covers
        // min(trail, omega*age)/(omega*life) of it.
        vec4 m = hash4(vec2(k * 0.017 + 3.77, seed + 19.13));
        // A normal drawn from three uniforms: sd(u1+u2+u3-1.5) = 0.5 exactly,
        // so 2*spread*(sum-1.5) has sd = spread.
        float F = ubuf.stormBurn.x + 2.0 * ubuf.stormBurn.y * (m.x + m.y + m.z - 1.5);
        // An earthgrazer skims, stays in thin air and brightens gradually: its
        // curve is late-peaked by construction, which is most of why one reads
        // as a different object rather than as a slow ordinary streak.
        F = clamp(mix(F, 0.70 + 0.15 * m.x, grazer), 0.20, 0.90);
        float pHead = age / life;
        float pSpan = min(trail, omega * age + 0.004) / max(omega * life, 1e-5);
        float L = lightCurve(pHead - u * pSpan, F, max(ubuf.stormTone.w, 0.5));
        float w = sigma * (1.0 + 2.4 * u);
        float over = max(d - dh, 0.0);
        float across2 = across * across + over * over;
        float body = exp2(-1.4426950 * across2 / (w * w)) * L * (0.35 + 0.65 * (1.0 - u));
        vec2 dir = vec2(cos(a), sin(a));
        vec2 q = pixel - (ubuf.stormHead.xy + dir * dh);
        float r2 = dot(q, q);
        float sigma2 = sigma * sigma;
        float variance = sigma2 + 0.0833333;
        // The head carries the light curve too, and its bloom grows with it:
        // the same "the disc grows with log brightness" the slot meteors use,
        // reached here through one extra exp2 rather than a uniform.
        float glare = clamp(L * (0.35 + 0.65 * g.y), 0.0, 1.0);
        float value = 1.45 * L * exp2(-0.7213475 * r2 / variance) * sigma2 / variance
                    + (0.10 + 0.55 * glare) * exp2(-r2 / (sigma2 * (7.0 + 70.0 * glare)))
                    + 0.85 * body;
        if (g.z < ubuf.stormSpan.z) {
            // Fragmenting: two siblings separate from the head after the split
            // and keep flying on their own slightly divergent rays.
            float split = smoothstep(0.40 * life, 0.95 * life, age);
            vec2 n = vec2(-dir.y, dir.x) * (split * focal * 0.010);
            float left = dot(q - n, q - n), right = dot(q + n, q + n);
            value += 0.60 * split * (exp2(-0.7213475 * left / variance) + exp2(-0.7213475 * right / variance)) * sigma2 / variance;
        }
        // Colour by speed: a fast streak is green-teal, a slow one orange, and
        // the sky's own palette is mixed into both by the same paletteMix the
        // ordinary meteors use.
        vec3 tint = mix(vec3(1.0, 0.72, 0.38), vec3(0.50, 1.0, 0.80), smoothstep(0.45, 1.15, omega));
        vec3 body3 = mix(mix(tint, ubuf.stormColour.rgb, ubuf.stormColour.w), vec3(1.0), 0.45);
        sum += value * bright * body3;
        // v12: the storm's streaks get the same three extra emitters the slot
        // meteors do, on the same profiles, so a storm streak and an ordinary
        // meteor are the same object drawn by two code paths instead of two
        // different-looking things that happen to share a name.
        if (ubuf.stormTone.x > 0.0 || ubuf.stormTone.y > 0.0) {
            float puHere = pHead - u * pSpan;
            float fadeHere = 0.30 + 0.70 * (1.0 - u);
            float wn = w * 1.15, wt = w * 1.8;
            vec3 extra = vec3(1.00, 0.58, 0.19)
                * (ubuf.stormTone.x * naProfile(puHere, F)
                   * exp2(-1.4426950 * across2 / (wn * wn))
                   * (0.10 + 0.90 * (1.0 - u) * (1.0 - u)));
            extra += vec3(0.48, 1.00, 0.58)
                * (ubuf.stormTone.y * 0.55 * smoothstep(0.0, 0.18, u) * sqrt(L)
                   * exp2(-1.4426950 * across2 / (wt * wt)) * (0.62 + 0.38 * (1.0 - u)) * 1.0);
            // The head runs warm before maximum for the same reason the slot
            // meteors do -- the sodium is where the head is.
            extra += vec3(1.00, 0.58, 0.19) * (ubuf.stormTone.x * naProfile(pHead, F)
                   * 1.2 * exp2(-0.7213475 * r2 / variance) * sigma2 / variance);
            sum += extra * bright * 0.70;
        }
    }
    // ---- v12: THE STORM'S OWN PERSISTENT TRAINS ---------------------------
    // A meteor storm's picture is not the five or six streaks alive at one
    // instant. It is what they LEAVE: after half a minute at peak there are
    // several trains hanging in the sky, all radiating from one point, and
    // that is what makes a storm legible AS a storm rather than as a few fast
    // lines. It is also the complaint open since ledger 2284 -- he still
    // cannot spot the special events -- and nothing that vanishes inside a
    // second was ever going to answer it.
    //
    // 13.4 % of meteors leave a persistent train (Cordonnier, 4726 meteors),
    // and the gate is TERMINAL HEIGHT below 93.5 km -- slow and deep, not fast
    // and bright, which is the opposite of the folklore. So a fast streak's
    // train is short and faint here and a slow one's is long and bright.
    //
    // A SECOND STATELESS STREAM: train index m advances at rate*trainShare per
    // second on the storm's own phase, and the streak that left it is
    // k = m/trainShare on the SAME index stream, so a train lies on a ray a
    // meteor really flew rather than on one invented for it.
    if (ubuf.stormTrain.x > 0.0 && ubuf.stormTrain.y > 0.5) {
        float tPhase = ubuf.stormHead.z * ubuf.stormTrain.x;
        float tTop = floor(tPhase);
        int tWindow = int(ubuf.stormTrain.y);
        float tGainCfg = ubuf.stormWind.z;
        for (int j = 0; j < 16; ++j) {
            if (j >= tWindow) break;
            float m = tTop - float(j);
            float k = floor(m / ubuf.stormTrain.x);
            float a = stormHash(k, seed) * 6.2831853;
            float dphi = phi - a;
            dphi -= 6.2831853 * floor(dphi * 0.1591549 + 0.5);
            vec4 h = hash4(vec2(k * 0.017, seed));
            vec4 g = hash4(vec2(seed + 7.31, k * 0.017));
            float grazer = step(h.x, ubuf.stormSpan.y);
            float omega = mix(0.30 + 0.60 * h.y, 0.08 + 0.10 * h.y, grazer);
            float life = mix(0.65 + 1.30 * h.z, 3.0 + 2.5 * h.z, grazer);
            // Slow and deep: the train's life and gain both follow it.
            float slow = 1.0 - clamp((omega - 0.08) / 0.82, 0.0, 1.0);
            float tLife = mix(ubuf.stormTrain.z, ubuf.stormTrain.w, 0.20 + 0.80 * slow * (0.4 + 0.6 * g.y));
            float tAge = (ubuf.stormHead.z - k) / rate - life;
            if (tAge < 0.0 || tAge > tLife) continue;
            float fast = clamp((omega - 0.30) / 0.60, 0.0, 1.0);
            float theta = min(mix(0.05, 0.95, h.w * h.w) * (1.0 - 0.45 * fast) + mix(0.0, 0.40, grazer) + omega * life, 1.35);
            float trail = mix(ubuf.stormShape.y, ubuf.stormShape.z, g.x) * mix(1.0, 2.2, grazer);
            float rHead = focal * tan(theta);
            float rFoot = focal * tan(max(theta - min(trail, omega * life), 0.004));
            float span = max(rHead - rFoot, 1.0);
            float tLive = tAge / max(tLife, 0.001);
            float widen = 1.0 + 1.9 * (1.0 - exp2(-1.4426950 * tAge / max(2.0, ubuf.stormWind.w)));
            float width = base * (2.2 + 1.6 * g.w) * 0.55;
            float shearEnv = (1.0 - exp2(-3.6067 * tLive)) * 1.0855;
            float shear = ubuf.stormWind.x * shearEnv;
            float support = shear * 1.2 + width * 7.0 * widen;
            if (abs(dphi * d) > support) continue;
            if (d < rFoot - support || d > rHead + support) continue;
            float u = clamp((rHead - d) / span, 0.0, 1.0);
            float across = dphi * d - shear * trainShear(u, fract(h.w * 7.77), tAge) * (0.22 + 0.78 * u);
            float w = width * (0.55 + 1.4 * u) * (1.0 + (widen - 1.0) * (1.0 - 0.55 * u));
            float over = max(d - rHead, 0.0) + max(rFoot - d, 0.0);
            // Mass is conserved as it widens, so as it spreads it dims; and the
            // last three candidates of the window fade rather than pop out of
            // existence when the loop's bound drops them.
            float edge = 1.0 - smoothstep(float(tWindow) - 3.0, float(tWindow) - 0.2, float(j));
            float value = exp2(-1.4426950 * (across * across + over * over) / (w * w))
                        * pow(1.0 - tLive, 1.4) / widen * edge
                        * smoothstep(0.0, 0.12, u) * (1.0 - 0.45 * u);
            // Three tones on three clocks, the same chemistry the fireball's
            // train reads, evaluated here because every train has its own age.
            float green = exp2(-1.4426950 * tAge / 4.5);
            float mt = (tAge - 9.0) * 0.0769231;
            float metal = exp2(-1.4426950 * mt * mt);
            float feo = 1.0 - exp2(-1.4426950 * max(0.0, tAge - 3.0) * 0.0625);
            vec3 tone = (green * vec3(0.50, 1.00, 0.60) + metal * vec3(1.00, 0.92, 0.72)
                       + feo * vec3(1.00, 0.52, 0.16)) / max(1e-4, green + metal + feo);
            sum += value * tGainCfg * (0.25 + 0.75 * slow) * (0.35 + 0.65 * g.y) * tone;
        }
    }
    return gain * max(sum, vec3(0.0));
}
vec3 eventSlot(vec2 pixel, vec4 head, vec4 colour, vec4 tail01, vec4 tail23, vec2 tail4, vec4 shape, vec4 bounds, vec4 burn, vec4 tone) {
    if (head.w <= 0.0 || pixel.x < bounds.x || pixel.y < bounds.y || pixel.x > bounds.z || pixel.y > bounds.w) return vec3(0.0);
    // Style 7 is the storm's fireball; style 6 is the supernova and reaches its
    // own kernel through radialField below. Styles are dispatched from the top
    // down, so the two v9 additions cannot shadow each other.
    // The storm's fireball reads the SHOWER's tone block, not the ordinary
    // meteors' one: events.shower and events.meteors carry the same key names
    // and are separately configured, and a fireball belongs to the shower.
    if (colour.w > 6.5) return stormFireball(pixel, head, colour, tail01, tail23, tail4, shape, burn, ubuf.stormTone);
    if (colour.w > 4.5 && colour.w < 5.5) return cometField(pixel, head, colour, tail01, tail23, tail4, shape, burn);
    if (colour.w > 2.5) return radialField(pixel, head, colour, tail01, shape, bounds);
    vec2 p = pixel - head.xy;
    float r2 = dot(p, p);
    float sigma2 = head.z * head.z;
    float variance = sigma2 + 0.0833333;
    if (colour.w < 0.5) {
        // ---- v12 STYLE 0: THE METEOR --------------------------------------
        // shape.w is the GLARE, and it used to be the entry FLASH -- a bloom
        // that existed for the first 16 % of the path and then never again,
        // commented in the source as "the entry bloom of a meteor". There is
        // no such thing. A head blooms where it is BRIGHT, which is around the
        // middle of the path and at a terminal burst, and the bloom is the
        // right place to put a flare because the saturated disc grows with the
        // logarithm of the brightness while the value itself is clipped by the
        // display and cannot show anything at all (V12 brief 1.4, 2.7).
        float glare = clamp(shape.w, 0.0, 1.0);
        float extent = head.z * (7.0 + 26.0 * glare);
        float taper = 1.0 - smoothstep(0.64 * extent * extent, extent * extent, r2);
        float hot = exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
        float bloom = exp2(-r2 / (sigma2 * (7.0 + 95.0 * glare)));
        float headShare = 2.0 * shape.y;
        vec3 nucleus = (hot * 1.35 + bloom * (0.10 + 0.70 * glare)) * taper
                     * mix(colour.rgb, vec3(1.0), 0.60) * headShare;
        // The HEAD's own colour changes along the path, and this is the part
        // that answers "change" where he can actually see it -- on the
        // brightest thing in the streak rather than only on the tail. The
        // sodium sheath is a property of WHERE THE HEAD IS, so it belongs on
        // the head as well as behind it: the meteor runs warm early, the warm
        // emitter dies, and the blue-white left underneath is what it ends as.
        if (tone.x > 0.0)
            nucleus += vec3(1.00, 0.58, 0.19) * (tone.x * naProfile(burn.y, burn.x)
                     * (hot * 0.90 + bloom * 0.30 * glare) * taper * headShare);
        // The leading edge. Meteor spectra are TWO spectra at two temperatures
        // in two places: the ~4000 K vapour cloud that is the head and the
        // wake, and a ~10000 K component that forms IN FRONT of the meteoroid
        // near the shock wave and is absent below about 15 km/s. It is drawn
        // here rather than in the trail because it is physically ahead of the
        // head, and a slow meteor gets none of it at all.
        if (tone.z > 0.0 && burn.w > 0.25) {
            vec2 dir = tail01.xy - tail01.zw;              // trail -> head
            float dl = length(dir);
            if (dl > 0.001) {
                dir /= dl;
                float along = dot(p, dir);
                float gate = tone.z * smoothstep(0.25, 0.65, burn.w);
                // Ca II at 393 nm and the N2 bands at 631 nm together, so the
                // precursor is violet-RED rather than blue: it has to read as
                // a DIFFERENT emitter from the blue-white head, not as more of
                // the head.
                //
                // TWO PARTS, because at a real head's angular size that is
                // what a camera records. A thin needle reaching ahead -- the
                // shock-heated column itself -- and a violet-red FRINGE on the
                // leading half of the head's own bloom, which is the part that
                // survives being a couple of pixels across. The closeup
                // reference shows both: a hairline precursor in front, and the
                // violet edge on the saturated ball.
                float forward = along / max(1e-4, sqrt(r2));
                nucleus += vec3(1.00, 0.40, 0.90)
                         * (gate * 0.85 * bloom * smoothstep(0.0, 0.85, forward) * taper);
                float reach = head.z * 10.0;
                if (along > 0.0 && along < reach) {
                    float across = dot(p, vec2(-dir.y, dir.x));
                    float wl = max(head.z * 0.80, 0.45);
                    float fade = 1.0 - along / reach;
                    nucleus += vec3(1.00, 0.40, 0.90)
                             * (gate * fade * exp2(-1.4426950 * across * across / (wl * wl)));
                }
            }
        }
        vec3 trail = vec3(0.0);
        if (shape.z > 0.5) trail = ablationStreak(pixel, tail01.xy, tail01.zw, 0.0, head, shape, burn, tone, colour.rgb);
        float run = length(tail01.zw - tail01.xy);
        if (shape.z > 1.5) trail = max(trail, ablationStreak(pixel, tail01.zw, tail23.xy, run, head, shape, burn, tone, colour.rgb));
        run += length(tail23.xy - tail01.zw);
        if (shape.z > 2.5) trail = max(trail, ablationStreak(pixel, tail23.xy, tail23.zw, run, head, shape, burn, tone, colour.rgb));
        run += length(tail23.zw - tail23.xy);
        if (shape.z > 3.5) trail = max(trail, ablationStreak(pixel, tail23.zw, tail4, run, head, shape, burn, tone, colour.rgb));
        return head.w * (nucleus + trail);
    }
    // Styles 1 and 2 -- the satellite's glint and the slow wanderer -- are
    // untouched by v12 and keep the kernel they were measured with.
    float flash = clamp(shape.w, 0.0, 1.0);
    float extent = head.z * (colour.w < 1.5 ? 14.0 : 6.0 + 12.0 * flash);
    float taper = 1.0 - smoothstep(0.64 * extent * extent, extent * extent, r2);
    float hot = exp2(-0.7213475 * r2 / variance) * sigma2 / variance;
    float glow = colour.w > 1.5 ? exp2(-r2 / (sigma2 * (6.0 + 40.0 * flash))) : exp2(-r2 / (sigma2 * 32.0));
    vec3 nucleus = (hot * (colour.w > 1.5 ? 1.0 : 1.35) + glow * 0.22 * flash) * taper * mix(colour.rgb, vec3(1.0), 0.60);
    float tail = 0.0;
    if (shape.z > 0.5) tail = tailSegment(pixel, tail01.xy, tail01.zw, 0.0, head, shape, colour.w);
    float distance = length(tail01.zw - tail01.xy);
    if (shape.z > 1.5) tail = max(tail, tailSegment(pixel, tail01.zw, tail23.xy, distance, head, shape, colour.w));
    distance += length(tail23.xy - tail01.zw);
    if (shape.z > 2.5) tail = max(tail, tailSegment(pixel, tail23.xy, tail23.zw, distance, head, shape, colour.w));
    distance += length(tail23.zw-tail23.xy);
    if (shape.z > 3.5) tail = max(tail, tailSegment(pixel,tail23.zw,tail4,distance,head,shape,colour.w));
    return head.w * (nucleus + shape.y * tail * colour.rgb);
}

// ---- NEBULA PASSAGE ----------------------------------------------------
// A cloud, not a point: a ragged domain-warped field inside one ellipse, with
// its own extinction. It is the only event that takes light AWAY, so it is
// composited into the far layer (before the shadow, under the particles and
// under the disk) rather than added at the end like every slot event.
//
// One hardware-bilinear tap IS a C1 value-noise lattice when the fractional
// part is pre-eased: the filter then interpolates the four texels with a
// smoothstep weight instead of a linear one, which is the same trick
// bhNoiseRow uses on the same texture. blackhole-noise.png's R channel has an
// x period of 32 texels and G one of 64 - both divide 64 - and both have a y
// period of 127 with the last row duplicated, so folding the integer part by
// (64, 127) keeps BOTH channels continuous across the fold and no wrap mode is
// relied on. Two decorrelated fields for one fetch.
vec2 nebulaTap(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    vec2 c = vec2(mod(i.x, 64.0), mod(i.y, 127.0)) + f + 0.5;
    return texture(bhNoise, c / 128.0).rg;
}
// An embedded young star: a hot core, and the light it scatters back out of
// the material around it. Returns (core, scatter) so the caller can weight the
// scatter by the local density - that is what makes it read as the CLOUD
// glowing rather than a star pasted on top of one.
vec2 nebulaStar(vec2 p, vec2 star, float core, float scatter) {
    vec2 d = p - star;
    float r2 = dot(d, d);
    float variance = core * core + 0.0833333;
    return vec2(exp2(-0.7213475 * r2 / variance) * core * core / variance,
                exp2(-r2 / (scatter * scatter)));
}
// rgb = linear emission, a = the dust column's opacity to whatever is behind.
// Three texture fetches and ~70 ALU inside the ellipse, one compare outside.
vec4 nebulaField(vec2 pixel) {
    if (ubuf.nebulaHead.w <= 0.0 || pixel.x < ubuf.nebulaBounds.x || pixel.y < ubuf.nebulaBounds.y
        || pixel.x > ubuf.nebulaBounds.z || pixel.y > ubuf.nebulaBounds.w) return vec4(0.0);
    vec2 d = pixel - ubuf.nebulaHead.xy;
    vec2 e = ubuf.nebulaShape.xy;
    // Cloud frame: x along the major axis, y across it, both in semi-axes.
    vec2 q = vec2(dot(d, e), dot(d, vec2(-e.y, e.x)))
           / vec2(max(ubuf.nebulaHead.z, 1.0), max(ubuf.nebulaHead.z * ubuf.nebulaShape.z, 1.0));
    float rr = dot(q, q);
    if (rr >= 1.0) return vec4(0.0);
    // Each octave is advected at its own velocity, so the structure SHEARS
    // through itself over minutes instead of sliding across as one picture.
    float t = ubuf.nebulaShape.w;
    vec2 p = q * 3.2;
    vec2 w = nebulaTap(p * 0.80 + vec2(t, -0.62 * t)) - 0.5;
    vec2 n1 = nebulaTap(p * 1.70 + w * 1.8 + vec2(-0.41 * t, 0.93 * t));
    // The boundary is two octaves biting inward, so the rim is ragged and wispy
    // at two scales while the hard ellipse above stays the cost bound: both
    // bites are >= 0, so at rr = 1 the envelope has already reached zero and
    // nothing can step at the edge of the bounding test.
    float env = 1.0 - smoothstep(0.04, 1.0, rr + 0.34 * (w.x + 0.5) + 0.24 * (n1.x + 0.5) * (n1.x + 0.5));
    if (env <= 0.0) return vec4(0.0);
    vec2 n2 = nebulaTap(p * 4.10 + w * 2.4 + vec2(13.7 + 1.7 * t, 5.3 - 1.1 * t));
    float soft = 0.62 * n1.x + 0.38 * n2.x;
    // Ridged layer: the filaments and sheets a soft fbm alone never grows.
    float ridge = 1.0 - abs(2.0 * (0.65 * n1.y + 0.35 * n2.y) - 1.0);
    // env squared is the denser core; the un-squared term is what keeps the
    // wisps alive out at the rim.
    float density = env * env * (0.30 + 1.15 * soft) + env * 0.62 * ridge * ridge;
    // Dust lane: where the warped medium octave falls away there is material
    // that absorbs and does not emit. It darkens the emission and it is the
    // part of the opacity that does not follow the glow.
    float lane = smoothstep(0.26, 0.56, 0.70 * n1.x + 0.30 * n2.y + 0.18 * w.y);
    float opacity = clamp(ubuf.nebulaTone0.w * (0.70 * density + 0.85 * env * (1.0 - lane)), 0.0, 0.94);
    // Two tones, mixed by the medium octave rather than by position, so the
    // colour is patchy like real emission instead of a gradient across a disc.
    // The mix is pushed to its ENDS rather than left linear: a
    // palette that is saturation-capped to 0.28 has very little chroma to
    // begin with, and averaging two of those over most of the cloud threw away
    // what there was (measured mean chroma 0.017 linear, against 0.05 for the
    // pure tones). Large regions of each tone with a transition between them
    // is both more colour and more like emission.
    vec3 tint = mix(ubuf.nebulaTone0.rgb, ubuf.nebulaTone1.rgb,
                    smoothstep(0.34, 0.66, 0.5 + 1.6 * (n1.y - 0.5) + 0.55 * w.y));
    // 0.36 is a CALIBRATION, not taste: it is what makes the cloud's 99th
    // linear percentile equal `gain`, so the documented 0.35 ceiling on that
    // key is the q99 the sky actually gets (measured, tools/nebula_sheet.py).
    vec3 emission = tint * (density * lane * 0.36);
    if (ubuf.nebulaTone1.w > 0.0) {
        float core = max(ubuf.nebulaStars2.z, 0.5), scatter = max(ubuf.nebulaStars2.w, 1.0);
        vec2 a = nebulaStar(pixel, ubuf.nebulaStars.xy, core, scatter);
        a += nebulaStar(pixel, ubuf.nebulaStars.zw, core, scatter);
        a += nebulaStar(pixel, ubuf.nebulaStars2.xy, core, scatter);
        // The core is NOT normalized with the body: an embedded young star is
        // meant to be a star. 4.0 puts it at 0.54 linear (199/255) at the
        // shipped gains, against an ordinary near star's 243/255. The halo is
        // cut well inside the bounding ellipse, so a star near the rim cannot
        // leave a hard circle where the cloud ends.
        emission += (mix(tint, vec3(1.0), 0.62) * a.x * 4.0
                  + tint * a.y * (0.08 + 1.10 * density))
                  * ubuf.nebulaTone1.w * smoothstep(1.0, 0.55, rr);
    }
    return vec4(emission * ubuf.nebulaHead.w, opacity);
}
// ---- v12 GRAIN POPULATIONS: the cloud is made of grains -----------------
// v11 fixed "static" and "not hyper-detailed". He came back (ledger 2403) with
// three things it still got wrong and one it had never tried:
//
//   "phase chaning when it changes the color it feels unatural and as just pure
//    color fade transition [...] instead of it just transition the color slowly
//    it should make new particles of new tone [...] atfrist it is full of green
//    particles then over time more of particles that color is closer to red
//    start appering the closer and closer and then finaaly red"
//   "the clouds in speaking of i wan it to me more of particles based"
//   "the gas right now feeels too static it should behave like real gas on the
//    wind [...] that gas is volumetric and 3 each part of it moves differently"
//   "supernovas still look far from the reference image"
//
// All four are ONE construction. The gas stopped being a noise field with a
// time-varying tint and became a POPULATION: thousands of grains that are born,
// drift on a divergence-free wind, and die, each one carrying a single colour
// it was born with. Nothing in here lerps a hue. The only thing that changes
// smoothly is HOW MANY grains of each tone are being born.
//
//   NO CPU. QML's JS charges 211 ns per particle-iteration (14x node,
//   V11-PERF-REPORT.md), so thousands of grains on the main thread is not a
//   budget question, it is impossible. The GPU sat at 4 % with room to 15. So
//   every grain is STATELESS: a cell grid in the remnant's comoving frame, one
//   grain per cell, and its birth time, life, position, size, stretch,
//   brightness and TONE all derived from hash4(cell, generation, slice). There
//   is no buffer, no atlas row and no frame-to-frame state anywhere; a grain
//   is as procedural as one of the field's stars, and for the same reason.
//
//   BIRTH-FROZEN TONE, WHICH IS THE SKY'S OWN LAW. A star's traits are frozen
//   at birth here and always have been. A grain's tone is chosen ONCE, from the
//   birth-rate distribution as it stood AT THE GRAIN'S BIRTH TIME, and never
//   read again. The distribution slides; the grain does not. So mid-change the
//   cloud is a visible MIXTURE of two tones in different individual grains --
//   which is what he described, and what a hue histogram taken mid-change shows
//   as two peaks instead of one travelling bump.
//
//   THE SLIDE IS THE REVERSE SHOCK. Cas A is ~350 years old and its reverse
//   shock is still walking INWARD through the ejecta in the material's frame,
//   heating and ionising each layer as it reaches it. That is a physical reason
//   for new-toned material to appear progressively from the outside in, which
//   is exactly the turnover he asked for, so the schedule is driven by a
//   reverse-shock radius that walks in rather than by a clock.
//
//   SIX POPULATIONS, MEASURED OFF HIS REFERENCE. Not a palette ramp and not my
//   taste: a six-way cluster of sa0225Mosk01.jpg's lit interior, in linear
//   light, normalised per pixel so tone is separated from brightness, returns
//   exactly six and they are the six below with these area shares --
//   blue 25.9 %, crimson 19.5 %, magenta 15.8 %, blue-white 15.6 %, cyan
//   15.0 %, yellow-green 8.1 %. Ordered here INSIDE -> OUT, which is what makes
//   one 1-D schedule serve both the radial structure and the time turnover.
//   In Chandra's element mapping those are iron (purple), the bulk ejecta and
//   the synchrotron blast wave (blue and blue-white), calcium (green), sulphur
//   (yellow) and silicon (red) -- and the Si-rich jets are the fastest, outermost
//   material, which is why crimson sits at the end of the sequence.
//
//   VOLUME, NOT A SHEET. Four depth slices, each a real plane section of the
//   shell: a plane at line-of-sight depth z cuts a shell of inner radius a in
//   an annulus of outer radius sqrt(1-z^2) and inner sqrt(a^2-z^2), so the two
//   slices past |z| > a are filled DISCS -- the near and far caps, which is why
//   the middle of the reference is full of material and the middle of v11's is
//   empty. Each slice has its own lattice rotation, its own curl field, its own
//   morph phase and its own perspective magnification, and they composite
//   back-to-front so near material extincts far material. Each part moves
//   differently because each part IS a different part.
//
// ---- v11, kept ---------------------------------------------------------
//
// v11 answered "the cloud is static and not moving with the rest" and "it looks
// nothing like a real supernova". Everything below that answered it is kept:
//
//   COMOVING. Everything is evaluated in q = (pixel - site)/R, the MATERIAL's
//   own frame: the site travels on the far layer's streamline and R is the
//   remnant's live radius, so the pattern travels, grows and shears with the
//   debris instead of sitting still while the sky moves past it. Two dots and a
//   divide. The axis it is rotated into is the same frozen axis the jets use.
//
//   HOLLOW, NOT SOLID. The body is the projected COLUMN through a spherical
//   shell of inner radius `a`: sqrt(1-u^2) - sqrt(a^2-u^2). It peaks at the
//   limb, thins to (1-a) through the middle and reaches zero at the rim. That
//   single term is the difference between a sphere and a disc, and it is why
//   the middle of the remnant is dark in both references and bright in v10's.
//
//   BROKEN, NOT CIRCULAR. The outer radius itself is modulated by the coarse
//   octaves (+-25 %), so the rim is ragged at two scales. A shell broken only
//   in brightness still reads as a drawn circle -- that hard circular edge is
//   the first thing wrong with his screenshot.
//
//   FOAM. `cav` cuts dark cavities out of the body and `lobe` kills whole
//   sectors of the rim, which is the bubble topology of the JWST frame and the
//   reason a real remnant is bright on one side and absent on the other.
//
//   FILIGREE. A ridged high octave squared twice is a field of thin threads,
//   concentrated in a band at the limb, plus an eighth-power channel for the
//   isolated bright knots. v12 demotes this to the DIFFUSE UNDERLAY the grains
//   sit on (snTurn2.y): grains on black read as confetti, grains on a faint
//   sheet read as a cloud that is made of them. The four noise artefacts this
//   term cost to get right, and the rules that stop them coming back, are
//   unchanged and still enforced below.
//
//   IT TAKES LIGHT AWAY. Returning (emission, opacity) like nebulaField means
//   main() composites it INTO the far field: the dust column multiplies the
//   stars behind it, so they shine THROUGH the remnant and are dimmed by its
//   sheets, which is what makes the JWST frame read as translucent layers. No
//   additive sprite can do that.
//
// The six populations, indexed by an INTEGER. The chain of mixes evaluates to
// the pure tone at every integer, so this is a lookup and not a ramp: a grain
// is never the average of two populations, which is the whole point. It is
// called THREE OR FOUR TIMES PER PIXEL, hoisted out of the grain loop, never
// per grain -- see the window `base` below. rgb is linear with peak 1, w is the
// population's dust fraction (how much of it absorbs rather than emits).
vec4 snPop(float i) {
    vec4 c = mix(ubuf.snPop0, ubuf.snPop1, clamp(i, 0.0, 1.0));
    c = mix(c, ubuf.snPop2, clamp(i - 1.0, 0.0, 1.0));
    c = mix(c, ubuf.snPop3, clamp(i - 2.0, 0.0, 1.0));
    c = mix(c, ubuf.snPop4, clamp(i - 3.0, 0.0, 1.0));
    return mix(c, ubuf.snPop5, clamp(i - 4.0, 0.0, 1.0));
}
// TWO divergence-free flow fields for the price of three texture taps.
//
// Curl noise (Bridson, Hourihan & Nordenstam, SIGGRAPH 2007): the curl of a
// scalar potential is divergence-free by construction, so advecting by
// v = (dpsi/dy, -dpsi/dx) never compresses the material into sinks the way a
// raw vector-noise field does -- grains would pile into blobs and leave holes,
// which is the one artefact that would make this read as a texture again.
//
// nebulaTap returns TWO decorrelated value-noise channels per fetch, so three
// forward-differenced taps produce two independent potentials and therefore two
// independent flows. Forward differences rather than central: central costs
// four taps for a difference that is visually identical at this amplitude, and
// the half-cell bias is a translation of the field, which nothing here can see.
// The epsilon is half a lattice cell -- smaller reads the bilinear facet the
// tap is built on and turns the flow into a grid of straight segments.
void snCurl(vec2 p, out vec2 v0, out vec2 v1) {
    vec2 c = nebulaTap(p);
    vec2 cx = nebulaTap(p + vec2(0.5, 0.0));
    vec2 cy = nebulaTap(p + vec2(0.0, 0.5));
    vec2 g0 = (vec2(cx.x, cy.x) - c.x) * 2.0;
    vec2 g1 = (vec2(cx.y, cy.y) - c.y) * 2.0;
    v0 = vec2(g0.y, -g0.x);
    v1 = vec2(g1.y, -g1.x);
}
// ONE DEPTH SLICE OF GRAINS. Returns (emission, opacity) for the plane at
// line-of-sight depth z, in the slice's own frame, ready to be composited
// back-to-front by the caller.
//
//   THE GRID IS LAID DOWN IN A FLOW-WARPED COORDINATE. That is what makes the
//   grains move, and it is the only way a stateless grain can travel further
//   than its own cell: the lattice itself is displaced by the curl field, so
//   the cells stretch, shear and rotate the way a Lagrangian mesh does and the
//   grains ride inside them. The displacement is held under one cell so the
//   3x3 neighbourhood below is EXACT -- no grain that covers this pixel can be
//   outside it -- and that bound is not a quality compromise because a grain
//   only lives `lifeSec`: it is reborn long before it would have needed to
//   travel further. Short lives are what make a one-step advection honest.
//
//   THE FIELD MORPHS, IT DOES NOT SLIDE. Translating a noise potential in time
//   is the cheap way to animate a flow and it reads as one picture sliding
//   across the screen -- which is half of what "too static" means: the shape
//   never changes, it just arrives somewhere else. The curl is LINEAR in the
//   potential, so cross-fading the two potentials the same three taps already
//   produced gives a field that evolves in place and is still exactly
//   divergence-free. Each slice cross-fades on its own phase, so no two slices
//   are ever showing the same flow.
//
//   EVERY ATTRIBUTE IS FROZEN FOR THE GRAIN'S LIFE. `gen` is a floor(), so it
//   steps only when the cell recycles; every hash downstream of it is constant
//   between two births. That is the mechanical guarantee behind "for a tracked
//   grain, hue is constant over its life".
vec4 snSlice(vec2 q, float z, float slice, float t, float age, float edge,
             float posHere, float posRate, float spread, float base,
             vec4 cA, vec4 cB, vec4 cC, vec4 cD) {
    // The slice's own annulus. |z| past the shell's inner radius makes it a
    // filled disc: those are the near and far CAPS, and they are why the middle
    // of the remnant carries material instead of being a hole.
    float a = ubuf.snBody.x;
    float zz = z * z;
    float ro = sqrt(max(1.0 - zz, 0.0));
    float ri = sqrt(max(a * a - zz, 0.0));
    // PERSPECTIVE MAGNIFICATION is the parallax. A near slice is closer to the
    // camera and subtends more, so the material coordinate it must be sampled
    // at is the screen coordinate DIVIDED by its own magnification. It is the
    // same effect the particle side already measures on the ejecta (the near
    // cap magnified 2.16x against the far one by t+28 s), and because the
    // magnification is fixed while R grows, the slices separate radially as the
    // remnant expands -- which is layer parallax, for two multiplies.
    vec2 qm = q / (1.0 + ubuf.snTurn2.w * z);
    float nd = length(qm);
    if (nd >= ro * edge) return vec4(0.0);
    float env = smoothstep(ro * edge, ro * edge * 0.86, nd);
    if (ri > 0.0) env *= smoothstep(ri * edge * 0.80, ri * edge, nd);
    if (env <= 0.004) return vec4(0.0);
    // Each slice on its own lattice axes, for the reason the sharp cartesian
    // octaves are rotated 31 and 67 degrees: two lattices that share an
    // orientation share their creases, and coincident creases read as a mesh.
    float ang = 1.1781 * slice + 0.37;
    float ca = cos(ang), sa = sin(ang);
    vec2 qr = vec2(qm.x * ca - qm.y * sa, qm.x * sa + qm.y * ca);
    vec2 f0, f1;
    snCurl(qr * ubuf.snFlow.y + vec2(3.1 * slice, 7.9 * slice)
           + vec2(0.09 * t, -0.06 * t), f0, f1);
    float morph = 0.5 + 0.5 * sin(6.2831853 * (0.085 * t + 0.31 * slice));
    vec2 flow = mix(f0, f1, morph) * ubuf.snFlow.x;
    // THE FILAMENT AXIS IS MOSTLY TANGENTIAL. A shocked sheet seen edge-on lies
    // ALONG the rim, and Cas A's filaments measure strongly polar-anisotropic
    // (radial:tangential stretch ratios around 10 in the literature) -- which
    // is also what sn_reference.py's `tangential` metric scores, and what the
    // polar thread octave was put in for in v11. But shear ALSO draws a grain
    // out along its own streamline, and where the flow is circulating the two
    // agree. Blending 65 % tangent with 35 % streamline keeps the tangential
    // majority the reference has while letting a fast radial finger stretch
    // the way it is really moving. A still region with no flow falls back to
    // pure tangent, so a grain is never stretched along a degenerate axis.
    float fl = length(flow);
    vec2 tang = nd > 1e-4 ? vec2(-qr.y, qr.x) / nd : vec2(0.0, 1.0);
    vec2 fdir = fl > 1e-4 ? flow / fl : tang;
    // THE SLICES ARE A SCALE HIERARCHY AS WELL AS A DEPTH STACK, and this is
    // the single change that stopped the gas reading as a field of rice. Four
    // slices at ONE lattice pitch give four sheets of identically sized grains,
    // and a uniform grain size is a texture however many of them there are --
    // it is the v11 spaghetti lesson ("THREE SCALES OF STRUCTURE, not one")
    // arriving again for the grains. So the pitch doubles and a bit across the
    // stack, a factor of 4.5 end to end: broad blobs, knots, fine knots and
    // near-speckle, all superimposed.
    //
    // It is also the right way round physically. The NEAREST slice is closest
    // to the camera, so its structure subtends the most and its grains are the
    // coarsest; the far cap's are the finest. And because an eddy's turnover
    // time goes as its size to the two-thirds (Kolmogorov), the fine slices
    // live proportionally shorter -- the speckle boils while the blobs drift.
    // `grainCells` is the MIDDLE of the hierarchy, not its floor: the pitch
    // runs 2.3x finer to 1.5x coarser than the dial, a factor of 3.5 end to
    // end. It is centred rather than one-sided because the bound at the fine
    // end is the SCREEN -- a grain under about two pixels stops being a knot
    // and starts being sparkle in motion -- and the bound at the coarse end is
    // the remnant, which only holds so many blobs.
    float sc = exp2((1.5 - slice) * 0.60);
    vec2 p = qr * (ubuf.snGrain.y * sc) + flow;
    vec2 cell = floor(p);
    float life = max(ubuf.snGrain.z * exp2((slice - 1.5) * 0.40), 0.25);
    float size = ubuf.snGrain.w;
    float shrp = clamp(sc - 0.75, 0.0, 1.0);
    float opw = min(sc, 1.6);
    // MORE LIGHT AT THE LARGE SCALES. A turbulent cascade carries most of its
    // energy in the biggest eddies (E(k) ~ k^-5/3), and the reference agrees
    // with the physics: its defining feature is BROAD bright sheets with fine
    // structure on them, not an even carpet of speckle. Weighting the slices
    // by the same two-thirds power that sets their lifetimes puts the light
    // where the material is and gives the gas a foreground.
    float ew = exp2((slice - 1.5) * 0.40);
    vec3 em = vec3(0.0);
    float op = 0.0;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            vec2 c = cell + vec2(float(i), float(j));
            // Stagger, so the cells do not all turn over on the same frame --
            // a synchronised field pulses, and a pulsing field is a texture.
            vec4 h = hash4(c + vec2(11.37 * slice, 5.71 * slice));
            float phase = age / life + h.x * 9.0;
            float gen = floor(phase);
            float age01 = phase - gen;
            // The generation re-hash. The multipliers on `gen` are irrational
            // so no (cell, generation) pair can ever land on another one's
            // hash input -- an integer multiplier would make cell+1 at
            // generation g collide with cell at generation g+k.
            vec4 g = hash4(c * 1.7 + vec2(0.73171 * gen + 3.1 * slice,
                                          1.37193 * gen + 7.9));
            vec2 at = c + vec2(0.16 + 0.68 * g.x, 0.16 + 0.68 * g.y);
            vec2 dd = p - at;
            // Anisotropy: g.z runs a grain from a round KNOT to a long THREAD.
            // Squared, so most grains are knots and the threads are the tail --
            // the reference is a field of knots with filaments THROUGH it, and
            // making every grain a thread is how the whole thing turns back
            // into the curling worms v11 was made of.
            float stretch = 1.0 + 2.3 * g.z * g.z;
            float rad0 = size * (0.55 + 0.75 * g.z);
            // ---- THE 3x3 NEIGHBOURHOOD IS EXACT, AND HERE IS WHY -----------
            // A grain sits at its cell + [0.16, 0.84], so the nearest edge of
            // the 3 cells either side is 1.16 cells away in every direction.
            // If a grain's SUPPORT stays under 1.16 cells, no pixel outside the
            // neighbourhood can ever be inside a grain, and the nine cells are
            // not an approximation -- they are the complete answer.
            //
            // The first version violated that and it was the real cause of the
            // straight-edged "facets": a Gaussian has no support bound at all,
            // the reject cut it at 4.5 % of peak, and the stretch pushed a long
            // grain 2.6 cells out. Every elongated grain was being sliced off
            // square at the neighbourhood edge, so the gas was crossed by hard
            // lines ON THE GRAIN LATTICE -- which is why it survived rotating
            // the noise octaves and survived turning the curl off. Widening to
            // 5x5 would have cost 2.8x the loop to move the same line further
            // out; bounding the support removes it.
            //
            // So: a COMPACT kernel whose support is exactly `rad`, and a
            // stretch capped so the semi-major axis cannot pass 1.16. Small
            // grains may still be long threads, which is where the filaments
            // come from; only the largest are held rounder.
            float rad = rad0;
            stretch = min(stretch, 1.16 / max(rad, 1e-4));
            // EACH GRAIN PICKS ITS OWN AXIS, between the tangent and the local
            // streamline. Stretching every grain along the tangent draws the
            // whole remnant as concentric arcs -- which is the worms failure
            // and the pinwheel failure wearing a third hat, and it is what the
            // first version of this did. A per-grain mix keeps the tangential
            // MAJORITY the reference measures while giving the field the
            // crossing, branching filaments it actually has. hash4 channels are
            // all spent, so the mix weight is a cheap decorrelation of two.
            // Weighted toward the STREAMLINE. The flow is smooth, so grains
            // that follow it align with their neighbours and lie end to end in
            // long filaments -- which is the reference's defining structure and
            // the thing a fully random per-grain axis destroys. The tangent
            // stays in the mix because a shocked sheet seen edge-on really is
            // tangential; what is gone is EVERY grain taking it, which drew the
            // whole remnant as concentric arcs.
            float ax = 0.40 + 0.60 * fract(g.y * 3.137 + g.z * 1.673);
            vec2 am = tang * (1.0 - ax) + fdir * ax;
            float aml = length(am);
            vec2 fd = aml > 1e-4 ? am / aml : tang;
            vec2 e = vec2(dot(dd, fd) / stretch, dot(dd, vec2(-fd.y, fd.x)));
            float d2 = dot(e, e) / (rad * rad);
            if (d2 >= 1.0) continue;
            // Fast rise, slow fade, zero at both ends: a grain never appears or
            // vanishes on a frame, which is the other half of "unnatural".
            float live = 4.0 * age01 * (1.0 - age01);
            // THE TONE, FROZEN AT BIRTH. `posHere` is where the birth-rate
            // distribution sits at this radius NOW; a grain of age `bornAgo`
            // sampled it at posHere - posRate*bornAgo, and that is the only
            // time its colour is ever decided. Rounding to an integer is what
            // makes it a POPULATION rather than a gradient -- the grain is one
            // of six things, not 0.37 of the way between two of them.
            float bornAgo = age01 * life;
            float idx = floor(posHere - posRate * bornAgo
                              + (g.w - 0.5) * spread + 0.5);
            float k = clamp(idx - base, 0.0, 3.0);
            vec4 tone = mix(mix(mix(cA, cB, clamp(k, 0.0, 1.0)),
                                cC, clamp(k - 1.0, 0.0, 1.0)),
                            cD, clamp(k - 2.0, 0.0, 1.0));
            // A COMPACT KERNEL: (1 - r^2/rad^2)^2, reaching exactly zero with
            // zero slope at the support radius. Zero AT the edge is what a
            // Gaussian plus a reject could not give -- that pair leaves a step
            // at the cut, and a step in a moving field is a crawling edge.
            // The quartic version of this ((1-x^4)^2) is flatter-topped and
            // scored better on knot count, and it looked like a bowl of beans:
            // grains with that little skirt stop overlapping and the gas stops
            // being gas (lit fraction 0.77 against the reference's 0.96). The
            // picture won.
            //
            // The extra `b` on the coarse slices softens them further. A
            // 20-pixel blob with a crisp edge and a dust fraction reads as a
            // cut-out; a knot may have an edge, a cloud may not.
            float b = 1.0 - d2;
            float w = live * b * b * mix(b, 1.0, shrp);
            // Brightness decorrelated from size and tone by hand: hash4 has
            // four channels and this grain has spent all four.
            em += tone.rgb * (w * (0.30 + 1.70 * fract(g.x + g.z + g.w)));
            // A slice's TOTAL opacity per unit area is (grains per area) x
            // (grain area) x (per-grain opacity), and the first two cancel the
            // lattice pitch exactly -- so without this factor every slice
            // contributes the same extinction and the coarse one does it in a
            // handful of big opaque lumps. Scaling per-grain opacity by the
            // pitch puts the extinction where the material actually is: a lot
            // of small dense knots, a few large thin clouds.
            op += w * tone.w * opw;
        }
    }
    return vec4(em * (env * ew), op * env);
}
// rgb = linear emission, a = the dust column's opacity to whatever is behind.
vec4 supernovaRemnant(vec2 pixel) {
    float gain = ubuf.snRemnant.w, shock = ubuf.snShell.y;
    if (gain <= 0.0 && shock <= 0.0) return vec4(0.0);
    float R = max(ubuf.snRemnant.z, 1.0);
    vec2 d = pixel - ubuf.snRemnant.xy;
    float r2 = dot(d, d);
    // Two reaches: the remnant's own 1.38 R (the outer wisps live out to 1.34)
    // and the shock front's, which early in the shell phase runs inside R and
    // late in it runs past. One max, one compare.
    float bound = max(R * 1.38, ubuf.snShell.x + 4.0 * ubuf.snShell.z);
    if (r2 >= bound * bound) return vec4(0.0);
    // The episode's own frame. snJet.xy is a unit vector, so this is a rotation
    // and q.x is ALONG the jet axis, which the jet term below needs anyway.
    vec2 ax = ubuf.snJet.xy;
    vec2 q = vec2(dot(d, ax), dot(d, vec2(-ax.y, ax.x))) / R;
    float nd = sqrt(r2) / R;
    float t = ubuf.snTone.w;
    // The episode's age in SECONDS. snTone.w is that age scaled by 0.05 (the
    // advection phase, chosen so float32 carries a 2000 s episode to five
    // decimal places and so nothing ever wraps), and the grains need the
    // unscaled one because their lifetimes are in seconds. One multiply, and
    // the two can never drift apart because there is only one of them.
    float age = t * 20.0;
    // Domain warp, three octaves on top of it. Each is advected at its own
    // velocity so the interior CHURNS through itself over tens of seconds
    // rather than sliding across as one picture, and the phase is the episode's
    // own age, never wrapped -- a wrap in a noise coordinate is a jump.
    vec2 w = nebulaTap(q * 2.4 + vec2(0.29 * t, -0.17 * t)) - 0.5;
    vec2 n1 = nebulaTap(q * 5.1 + w * 1.5 + vec2(-0.13 * t, 0.23 * t));
    vec2 n2 = nebulaTap(q * 10.0 + w * 1.9 + vec2(7.3 + 0.19 * t, 3.1 - 0.15 * t));
    // EACH SHARP OCTAVE ON ITS OWN AXES. nebulaTap is a bilinear value lattice,
    // so it is only C0 across its own grid lines; one squaring hides that (the
    // nebula passage never notices) and three turn the creases into straight
    // segments aligned with the screen -- a visible rectilinear mesh over the
    // whole remnant. Rotating the two sharpest octaves by 31 and 67 degrees
    // puts each lattice on its own axes, so no two creases line up with each
    // other or with the pixel grid, at four multiplies and two adds each.
    vec2 q3 = vec2(q.x * 0.85717 - q.y * 0.51504, q.x * 0.51504 + q.y * 0.85717);
    vec2 q4 = vec2(q.x * 0.39073 - q.y * 0.92050, q.x * 0.92050 + q.y * 0.39073);
    vec2 n3 = nebulaTap(q3 * 19.0 + w * 1.1 + vec2(21.7 - 0.11 * t, 11.3 + 0.13 * t));
    vec2 n4 = nebulaTap(q4 * 27.0 + w * 0.6 + vec2(5.9 + 0.08 * t, 17.3 - 0.07 * t));
    // A fifth tap that exists only for the KNOTS. The reference comparison put
    // the first version at 22.6 knots per radian of rim against 50 in the
    // Chandra composite and 101 in the JWST frame, and its knots at 0.025 rim
    // radii across against 0.017 and 0.012: too few and twice too big, which is
    // one fault, not two -- they were being drawn off octaves chosen for the
    // threads. 40 on G spans 55 cells of its 64 period, which is as fine as
    // this texture goes before it repeats.
    vec2 q5 = vec2(q.x * 0.97437 - q.y * 0.22495, q.x * 0.22495 + q.y * 0.97437);
    vec2 n5 = nebulaTap(q5 * 38.0 + w * 0.35 + vec2(31.1 - 0.06 * t, 3.7 + 0.05 * t));
    // WHICH CHANNEL EACH OCTAVE READS IS NOT ARBITRARY. blackhole-noise.png's R
    // channel has an x period of 32 texels and G one of 64 (nebulaTap's own
    // comment), so an octave whose coordinate spans more cells than its
    // channel's period repeats -- and a repeating ridged field does not read as
    // noise, it reads as a row of identical glyphs, which is exactly what the
    // first pass drew at q*43. The bound is |q| <= 1.38, so: scale 10 on R
    // spans 14 cells, 19 on R spans 26 of 32, 27 on G spans 37 of 64. Nothing
    // here may go above 23 on R or 46 on G.
    // The rim's own radius, broken at two scales.
    float edge = 1.0 + 0.26 * w.x + 0.30 * (n1.x - 0.5) + 0.18 * (n2.y - 0.5);
    // RAYLEIGH-TAYLOR FINGERS, put in by COUNT rather than left to the noise.
    // At the contact discontinuity the decelerating ejecta is the heavy fluid
    // pushing on the lighter shocked medium, the interface goes unstable, and
    // the finger spacing is set by the shell thickness -- which for Cas A's
    // R_CD/R_FS of about 0.80 works out at roughly 25 fingers around the limb,
    // reaching 75-80 % of the way out to the forward shock. 25 is written here
    // because a noise-only rim gets the raggedness and not the COUNT, and the
    // count is what the eye reads as fingers rather than as fuzz. The amplitude
    // is modulated by the coarse octave and the phase is warped by it, so it is
    // never a regular scallop -- the pinwheel artefact (K3) is a periodic term
    // drawing radial creases ACROSS the body; this one only moves the rim's own
    // radius, and it is amplitude-zero over whole sectors.
    float phi = atan(q.y, q.x);
    edge += 0.10 * (0.35 + 0.65 * (n1.y)) * sin(phi * 25.0 + 6.3 * w.y + 2.1 * (n2.x - 0.5));
    edge = max(edge, 0.30);
    float u = nd / edge;
    // THREE SCALES OF STRUCTURE, not one. A single ridged octave gives one
    // thread width everywhere, which is the "spaghetti" the first version of
    // this drew; what makes both references read as hyper-detailed is that
    // there is structure at every scale you look at. So: broad SHEETS (one
    // squaring), curling THREADS (two) and a near-speckle GRAIN (three), added
    // rather than averaged so a thread can sit on a sheet. The warp falls with
    // the octave -- a strongly warped fine octave curls into closed loops, and
    // loops read as worms rather than as filaments.
    float sheet = 1.0 - abs(2.0 * n2.y - 1.0);
    sheet *= sheet;
    // TANGENTIAL THREADS, on a POLAR grid. A shocked sheet seen edge-on lies
    // ALONG the rim; a cartesian ridged octave closes into rings instead, and
    // rings read as worms. 64 cells around the circle is a multiple of BOTH of
    // the noise texture's x periods (32 and 64), so the angular index wraps
    // exactly and nothing tears at atan's branch cut -- that is the one thing
    // v9's snPolar got right and it is kept. At the limb its cells are about
    // 2.4x longer around the rim than across it, which is the anisotropy the
    // reference comparison measures as the tangential fraction, and it is the
    // shader's half of the particle-side filament axis. The radial advection
    // makes the threads creep through the shell instead of sitting still.
    // The ANGULAR coordinate is warped by the coarse octave before it is
    // sampled. Without that, the polar lattice's own radial grid lines survive
    // the ridging as a comb of hairs pointing at the centre -- v9's snPolar
    // comment calls the same failure a pinwheel, and it is the spoke he
    // rejected wearing a different hat. The warp is a function of q, which is
    // continuous across the branch cut, so the exact wrap is untouched.
    float turn = phi * 0.15915494;
    float spin = turn * 64.0 + 9.5 * w.x + 5.0 * (n1.y - 0.5);
    // ONE polar octave, not two. A second one at twice the angular rate put
    // 128 of the lattice's radial creases across the outer wisps and they read
    // as a comb of hairs pointing at the centre -- the same spoke, one more
    // time. The fine scale comes from the rotated cartesian `grain` instead,
    // which has no preferred direction at all.
    vec2 pol = nebulaTap(vec2(spin, nd * 30.0 - 0.22 * t));
    float thread = 1.0 - abs(2.0 * pol.x - 1.0);
    thread *= thread;
    thread *= thread;
    float grain = 1.0 - abs(2.0 * n4.y - 1.0);
    grain *= grain;
    grain *= grain;
    float fil = 0.32 * sheet + 0.52 * thread + 0.52 * grain;
    // The shock front and the wisps take a softer ridge: a front broken by the
    // thread octave alone reads as lightning rather than as shocked gas.
    float ridge = 0.55 * sheet + 0.45 * thread;
    vec3 hot = ubuf.snHot.rgb, rim = ubuf.snTone.rgb;
    vec3 emission = vec3(0.0);
    float opacity = 0.0;
    float body = 0.0;
    // ---- v12: THE BIRTH-RATE SCHEDULE --------------------------------------
    // One 1-D quantity, `pos`, decides which population a grain born here and
    // now belongs to. It carries BOTH structures at once, which is why it is
    // one number and not two:
    //
    //   the RADIAL one -- posLo at the centre walking to posLo+posSpan at the
    //   rim, which is iron and bulk ejecta inside, shocked sheets at the limb,
    //   calcium/sulphur knots on the rim and silicon wisps beyond it; and
    //
    //   the TIME one -- the reverse shock, at radius snTurn.z, walking INWARD
    //   at snTurn2.x per second. Material it has already passed has advanced
    //   snTurn.w further along the sequence. So the turnover starts at the rim
    //   and travels in, which is both what Cas A does and what he described.
    //
    // `posRate` is the exact derivative of that with respect to time, and it is
    // the only thing that lets a stateless grain know what the distribution
    // looked like when it was born: a grain of age `a` sampled pos - posRate*a.
    float sx = clamp((u - ubuf.snTurn.z) * 2.2222222, 0.0, 1.0);
    float sweep = sx * sx * (3.0 - 2.0 * sx);
    float posHere = ubuf.snTurn.x + ubuf.snTurn.y * u + ubuf.snTurn.w * sweep;
    // THE INVERTED LAYER, and it is the most recognisable non-obvious thing
    // about this object. Cas A's iron is NOT in the middle: in the south-east
    // it sits OUTSIDE the silicon it was born under (Hughes et al. 2000), at a
    // higher ionisation age because that material crossed the reverse shock
    // earlier. So the populations are not clean nested shells. In ONE frozen
    // sector -- the same seed angle the diffraction spikes use, so it is a
    // property of this episode and not of the screen -- the schedule is pulled
    // back toward the iron end at large radius, and a violet plume reaches the
    // rim through the warm knots. One cosine, raised to the fourth for a ~90
    // degree sector.
    float pl = max(0.0, cos(phi - ubuf.snExtra.w));
    pl *= pl;
    posHere -= ubuf.snFlow.z * pl * pl * smoothstep(0.28, 0.86, u);
    // THE POPULATIONS ARE CLUSTERED, NOT SHUFFLED. Element layers in a real
    // remnant are coherent regions metres-per-second of turbulence has torn up,
    // not a salt-and-pepper mix -- the reference's yellow is in PATCHES, its
    // white-cyan in long RIBBONS. Shifting the schedule by a smooth field adds
    // that second scale for free: every grain in a neighbourhood samples nearly
    // the same offset, so a whole region comes out one population while the
    // per-grain jitter still mixes two tones inside it. Two scales of mixing,
    // and it costs nothing -- `n1` and `w` are already on the register from the
    // structure octaves, and because this rides in `posHere` it is inside the
    // hoisted window and never widens it.
    //
    // IT GETS ITS OWN WARPED, ROTATED TAP, AND THAT IS NOT OPTIONAL. The first
    // version clustered off `w` directly and drew straight-edged polygons
    // across the whole gas. `w` is the ONE octave in this kernel that is
    // neither warped nor rotated -- it is what warps the others -- so its
    // bilinear level sets are straight segments in screen space, and
    // QUANTISING ANYTHING against them prints them. That is artefact family K2,
    // the rectilinear mesh, arriving through the tone schedule instead of
    // through a ridge, which is why rotating the sharp octaves did not stop it:
    // the rule is about the lattice a hard edge is taken against, not about
    // which octave is sharpest. Warped by the coarse octave and rotated 47
    // degrees, this one has no straight contour left to print. Scale 3.3 spans
    // 9 cells of R's 32-texel period, well inside the 23 the glyph rule allows.
    //
    // It is also deliberately COARSE. The offset is evaluated at the PIXEL and
    // applied to every grain near it, so a field that changed quickly would
    // hand one grain two different tones at its two edges and leave a colour
    // seam down the middle of it. At 3.3 a lattice cell is about 8 grain cells
    // wide, a grain covers ~4 % of one, and a grain only splits if its value
    // lands inside that of a half-integer -- a few per cent, under the
    // per-grain brightness variation, and it reads as more mixing.
    vec2 q6 = vec2(q.x * 0.68200 - q.y * 0.73135, q.x * 0.73135 + q.y * 0.68200);
    vec2 n6 = nebulaTap(q6 * 3.3 + w * 2.2 + vec2(12.9 - 0.05 * t, 27.3 + 0.04 * t));
    posHere += 2.05 * (n6.x - 0.5) + 0.80 * (n1.y - 0.5);
    float posRate = ubuf.snTurn.w * 6.0 * sx * (1.0 - sx) * 2.2222222 * ubuf.snTurn2.x;
    // A FOUR-WIDE WINDOW, hoisted. Inside one 3x3 neighbourhood the grain
    // indices span the birth-time spread (posRate * life), the per-grain
    // jitter (`spread`), and the radial walk across three cells. Four adjacent
    // populations cover all of it, so the palette is evaluated four times per
    // pixel instead of once per grain -- 36 lookups become 4. The clamp inside
    // the loop is the safety net, not the mechanism; test-particles asserts it
    // never bites for the shipped schedule.
    float spread = ubuf.snFlow.w;
    float base = clamp(floor(posHere - posRate * ubuf.snGrain.z - spread * 0.5
                             - ubuf.snTurn.y * 0.12 + 0.5), 0.0, 2.0);
    vec4 cA = snPop(base), cB = snPop(base + 1.0);
    vec4 cC = snPop(base + 2.0), cD = snPop(base + 3.0);
    if (gain > 0.0 && u < 1.0) {
        // The hollow-shell column, normalised so its limb peak is 1.
        float a = ubuf.snBody.x;
        float uu = u * u;
        float inner = a * a - uu;
        body = (sqrt(max(1.0 - uu, 0.0)) - sqrt(max(inner, 0.0))) / sqrt(max(1.0 - a * a, 0.01));
        // Cavities, and whole sectors of rim that are simply not there.
        float cav = smoothstep(0.62, 0.22, 0.58 * n2.x + 0.42 * n1.y);
        float lobe = 0.26 + 0.74 * smoothstep(0.28, 0.80, 0.5 + w.y + 0.45 * (n1.x - 0.5));
        body *= (1.0 - ubuf.snBody.y * cav) * lobe;
        // The filigree band at the limb, where the shocked sheets are seen
        // edge-on, and the isolated knots along it. A knot is where two
        // INDEPENDENT fine channels both ridge, which is what makes them sparse
        // and point-like instead of another texture: hundreds per frame, the
        // way Cas A's bright knots are hundreds and not thousands.
        float band = exp2(-1.4426950 * (u - a) * (u - a) / 0.0225);
        // THREE channels off THREE DIFFERENT LATTICES -- 13, 31 and 67 degrees,
        // at 38, 19 and 27 cells -- squared once. Two channels of the SAME tap
        // share a lattice exactly, and the product of two ridges on one lattice
        // is locked to it: at gain it drew a circuit board, legible as repeated
        // glyphs under magnification, and it buried the filaments it was
        // supposed to sit on. Three independent lattices have no common
        // structure to lock to, and a triple product is sparse enough that it
        // needs half the sharpening a double one did.
        float knot = (1.0 - abs(2.0 * n5.y - 1.0)) * (1.0 - abs(2.0 * n3.y - 1.0))
            * (1.0 - abs(2.0 * n4.y - 1.0));
        knot *= knot;
        // v12: the tint that used to colour the gas is DEMOTED to the diffuse
        // underlay only. It was one tone crossfading over the whole cloud on
        // the episode's clock, which is precisely "it feels unnatural and as
        // just pure color fade transition" -- there was no other mechanism it
        // could have been. The gas's colour now comes entirely from the grain
        // populations below, which is the point of the whole pass; this term
        // survives as the faint sheet they sit ON, and it reads the same
        // schedule so it can never disagree with them.
        // NOT cB/cC. The hoisted window's `base` is a floor() of a smooth
        // field, and a floor() of a bilinear field DRAWS THAT FIELD'S LATTICE:
        // the level sets of a bilinear interpolant are straight inside each
        // cell, so the underlay snapped from one population to the next along
        // visible polygons -- artefact family K2 (the rectilinear mesh)
        // arriving by a route the octave rotations cannot reach, because this
        // one is a quantisation and not an octave. The GRAINS are immune by
        // construction (a grain's index is absolute, and cA..cD shift with
        // `base` so the reconstructed tone does not move), which is why only
        // the wash showed it. A wash may legitimately blend, so it reads the
        // schedule CONTINUOUSLY and the quantisation stays where it belongs.
        vec3 tint = snPop(clamp(posHere + 0.9 * u, 0.0, 5.0)).rgb;
        // The interior is NOT empty: a remnant seen through is translucent
        // layered gas, and the 0.34 floor is the sheets projected through the
        // middle. The band multiplies only the filigree, so the rim is where
        // the detail is and the middle is where the light comes through.
        // The BAND weights the filigree toward the limb, but it must not switch
        // it off through the middle: looking through the centre of a shell you
        // see its near cap and its far cap superposed, both full of filaments,
        // at lower surface brightness. Weighting them 0.30 there made the
        // interior smooth, and the reference comparison caught it as an edge
        // density of 1.96 against 0.91 and 1.20 in the references -- a rim too
        // detailed for its own interior rather than an interior too dim.
        emission += tint * (gain * ubuf.snTurn2.y * body
            * (0.26 + 1.30 * ubuf.snBody.z * fil * (0.78 + 1.22 * band)));
        emission += hot * (gain * ubuf.snHot.w * knot * body * (0.45 + 1.55 * band) * 5.5);
        // ---- THE GRAINS ---------------------------------------------------
        // Four depth slices, composited BACK TO FRONT: each one's emission is
        // dimmed by the accumulated opacity of everything nearer to the camera,
        // so near material occludes and extincts far material and the stack
        // reads as a volume rather than as four transparencies added together.
        // The two outer slices are past the shell's inner radius and project as
        // filled caps; the two inner ones project as annuli.
        //
        // The loop is bounded and it is the only unbounded-looking thing in the
        // kernel: 4 slices x 9 cells x 1 grain, every iteration a straight-line
        // block with one early `continue`, and it is reached only inside
        // u < 1 -- an idle sky pays the same single compare it always did.
        // OPTICALLY THIN. A young remnant's plasma emits and does not reabsorb
        // its own light; only the DUST in it takes light away. So the slices'
        // emission ADDS and the over-operator is the wrong tool for the glow --
        // the far cap has to shine THROUGH the near one, dimmed by its dust,
        // which is the whole translucency claim. `s` walks 3 -> 0, i.e. near to
        // far, so `gAcc` always holds the dust of everything NEARER than the
        // slice being added, which is exactly what should attenuate it.
        float gAcc = 0.0;
        vec3 gEm = vec3(0.0);
        for (int s = 3; s >= 0; --s) {
            float z = (float(s) - 1.5) * 0.52;
            vec4 sl = snSlice(q, z, float(s), t, age, edge,
                              posHere, posRate, spread, base, cA, cB, cC, cD);
            gEm += sl.rgb * (1.0 - gAcc);
            gAcc = gAcc + sl.a * (1.0 - gAcc);
        }
        // snGrain.x is an ABSOLUTE linear gain, not a fraction of `gain`. The
        // gas and the diffuse underlay are two different things now and each
        // one is calibrated against its own measured percentile, the way the
        // nebula passage's 0.36 and the body's 0.34 were: tying the grains to
        // the body's dial would mean one number setting two brightnesses and
        // neither of them landing where it was measured to.
        emission += gEm * (ubuf.snGrain.x * (0.34 + 0.66 * body));
        // The dust column. Densest where the gas is dense and NOT in a cavity
        // and NOT on a bright filament, which is what leaves the sheets grey
        // and brown between the lit threads. The grains carry their own share
        // of it -- a population's w is how much of it absorbs rather than
        // emits -- so the two add before the cap.
        opacity = clamp(ubuf.snBody.w * body * (0.30 + 0.90 * (0.5 + w.x)) * (1.0 - 0.55 * ridge)
                        + ubuf.snTurn2.z * gAcc, 0.0, 0.92);
        // v12: 0.26 -> 0.12. This term is a flat grey-blue wash proportional to
        // the dust column, and with the grains carrying the colour it was
        // mostly diluting them -- measured, it cost about 0.03 of mean
        // saturation for light the grains already provide.
        emission += ubuf.snDust.rgb * (opacity * 0.12 * gain);
    }
    // The outer wisps: fast material beyond the rim, faint and stringy, the red
    // wisps and the outer shock of the Chandra composite.
    if (gain > 0.0 && ubuf.snWisp.w > 0.0) {
        float out1 = smoothstep(0.84, 1.00, u) * (1.0 - smoothstep(1.02, 1.34, u));
        emission += ubuf.snWisp.rgb * (gain * ubuf.snWisp.w * out1 * ridge);
    }
    // The jets: two opposed lobes on the frozen axis, widening as they go, cut
    // off at their own reach. Both references have them coming out of the rim.
    if (gain > 0.0 && ubuf.snDust.w > 0.0) {
        float along = abs(q.x), across = abs(q.y);
        float wj = max(ubuf.snJet.w, 0.01) * (0.35 + 0.90 * along);
        float jet = exp2(-1.4426950 * across * across / (wj * wj))
            * smoothstep(0.16, 0.58, along)
            * max(0.0, 1.0 - along / max(ubuf.snJet.z, 0.1));
        // v12: the jets are drawn in the SILICON population's own colour. In
        // Cas A the NE and SW jets are the fastest, outermost, Si- and S-rich
        // material, which is the same population the outer wisps are made of
        // and the last one the schedule reaches -- so taking their tone from
        // snPop5 rather than from a mix of two unrelated uniforms is both the
        // physics and the one palette.
        emission += mix(ubuf.snPop5.rgb, ubuf.snPop4.rgb, 0.30)
            * (gain * ubuf.snDust.w * jet * (0.30 + 1.60 * ridge));
    }
    // The shock front, in PIXELS: it has its own Sedov radius and runs through
    // the comoving field rather than with it, which is what a blast wave into a
    // medium does. Broken by the same octaves, so the front is filamentary and
    // tangential instead of a drawn ring.
    if (shock > 0.0) {
        float sd = nd * R;
        float sr = ubuf.snShell.x * edge;
        float sw = max(ubuf.snShell.z, 1.0);
        float su = (sd - sr) / (sd < sr ? sw * 2.4 : sw);
        // The front is blue-white on its LEADING edge and cools to the rim tone
        // behind it, because that is the temperature gradient across a shock
        // and because one flat white ring is what made the first pass read as
        // lightning. The grain rides on top of the softer ridge so the front is
        // made of knots at the scale you zoom to.
        vec3 frontTone = mix(rim, hot, clamp(0.30 + 0.60 * su, 0.0, 1.0));
        emission += frontTone * (shock * exp2(-1.4426950 * su * su)
            * (0.30 + 1.30 * ridge + 0.70 * grain));
        if (ubuf.snShell.w > 0.0) {
            float ir = ubuf.snShell.x * 0.66 * edge;
            float iu = (sd - ir) / max(sw * 0.55, 1.0);
            emission += mix(hot, rim, 0.30) * (ubuf.snShell.w * exp2(-1.4426950 * iu * iu)
                * (0.35 + 1.25 * sheet + 0.60 * thread));
        }
    }
    return vec4(max(emission, vec3(0.0)), opacity);
}
// ------------------------------------------------------------------------

vec3 decodeDisplay(vec3 c) {
    c = max(c,vec3(0.0));
    if (max(c.r,max(c.g,c.b)) <= 0.04045) return c/12.92;
    return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));
}
vec3 encodeDisplay(vec3 c) {
    c = max(c,vec3(0.0));
    if (max(c.r,max(c.g,c.b)) <= 0.0031308) return c*12.92;
    return mix(c*12.92,1.055*pow(c,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),c));
}
// RGB24 atlas layout is shared with particles/Packing.js. The common empty
// pixel pays one header fetch. Geometry rejection precedes optical data reads.
vec3 particleTexel(float index) {
    vec2 p = vec2(mod(index,ubuf.particleAtlasInfo.x),floor(index/ubuf.particleAtlasInfo.x));
    return floor(texture(particleAtlas,(p+0.5)/ubuf.particleAtlasInfo.xy).rgb*255.0+0.5);
}
float particleOffset(vec3 header) {
    return header.r+256.0*header.g+65536.0*step(64.0,mod(header.b,128.0));
}
vec3 particleHit(vec2 pixel, float index, float absorb, out float front) {
    float base = ubuf.particleData.x+8.0*index;
    vec3 g0 = particleTexel(base), g1 = particleTexel(base+1.0);
    vec2 p = vec2(g0.r+256.0*g0.g,g0.b+256.0*g1.r)/65535.0;
    p = ubuf.particleDomain.xy+p*ubuf.particleDomain.zw;
    vec2 d = pixel-p;
    front = 0.0;
    // Oriented bounding box of the kernel, exactly the one the binner used. A
    // long streak fills about a tenth of the disc its half-length would sweep,
    // so rejecting on the box keeps the appearance fetches off most pixels.
    vec3 box = particleTexel(base+7.0);
    if (abs(d.x)*2.0>=box.r || abs(d.y)*2.0>=box.g) return vec3(0.0);
    vec3 v0 = particleTexel(base+2.0), v1 = particleTexel(base+3.0);
    vec3 light = particleTexel(base+4.0), optical = particleTexel(base+6.0);
    // kind 0..6 in the low three bits, bit 3 = four-point flare, bit 4 = near.
    float flags = particleTexel(base+5.0).r;
    float flared = step(8.0,mod(flags,16.0)), nearLayer = step(16.0,mod(flags,32.0));
    front = step(32.0,mod(flags,64.0));
    vec2 velocity = vec2(v0.r+256.0*v0.g,v0.b+256.0*v1.r)*(65536.0/65535.0)-32768.0;
    float speed = length(velocity);
    vec2 direction = speed>0.01 ? velocity/speed : vec2(1.0,0.0);
    float core = g1.b/16.0;
    float sigma = core/2.354820045;
    float streak = optical.b*(120.0/255.0);
    // Continuous tidal deformation, 0..1, from particles/Appearance.js. It is
    // the CPU's relaxed per-star state, so every term below moves over many
    // frames; nothing here switches between two shapes.
    float stretch = g1.g*(1.0/255.0);
    float minorVariance = sigma*sigma+1.0/12.0;
    // Radial squash: the same tide that draws the trail out along the motion
    // pinches the star across it, at constant integrated energy.
    minorVariance *= 1.0-0.40*stretch;
    float majorVariance = minorVariance+streak*streak/12.0;
    vec2 q = vec2(dot(d,direction),dot(d,vec2(-direction.y,direction.x)));
    // Deep in the field the trail follows the local orbit: the transverse
    // coordinate is offset by the arc of the true path, so a long streak reads as
    // a curved wake instead of a straight chord. kappa is the exact local
    // curvature of the softened two-body acceleration, computed here rather than
    // packed, so it costs nothing for the particles that do not bend, and the
    // stretch weights it in so the arc grows out of the chord.
    if (stretch>0.002 && speed>1.0) {
        vec2 toCentre = ubuf.bhCentre-p;
        float rc2 = dot(toCentre,toCentre)+1.0;
        vec2 acc = toCentre*(ubuf.particleMu/(rc2*sqrt(rc2)));
        float kappa = dot(acc,vec2(-direction.y,direction.x))/(speed*speed);
        // Bounded by the sagitta headroom the bin radius reserved, which the
        // packer also scales by this same stretch.
        q.y -= clamp(0.5*kappa*q.x*q.x,-6.0,6.0)*stretch;
    }
    float distance = q.x*q.x/majorVariance+q.y*q.y/minorVariance;
    float energy = (light.g+256.0*light.b)*(4.0/65535.0);
    float value = 0.0;
    if (distance<12.25) {
        float kernel = exp2(-0.7213475204*distance)*(1.0-smoothstep(9.0,12.25,distance));
        // Near particles use v3's saturating near-star core: a hot point that
        // approaches white instead of an energy-normalized bump that cannot.
        // Middle particles keep the normalized kernel, so a streak spreads its
        // light rather than gaining brightness.
        value = nearLayer>0.5
            ? 1.0-exp2(-1.442695041*energy*kernel)
            : energy*kernel/(6.28318530718*sqrt(minorVariance*majorVariance));
    }
    if (flared>0.5) {
        // v3's four-point cross, in particle space. Spikes taper to zero at
        // PARTICLE_FLARE_SPAN core radii; particles/Appearance.js sizes the bin
        // support from the same constants.
        float optics = min(core,4.8)*0.55;
        vec2 a = abs(d)/optics;
        vec2 taper = max(vec2(0.0),1.0-a/22.0);
        taper *= taper;
        vec2 thin = exp2(-a*a/0.38), skirt = exp2(-a*a/2.0);
        float cross = dot(thin,taper.yx)*0.48+dot(skirt,taper.yx)*0.10;
        float glowR2 = dot(a,a);
        float glow = 0.10*exp2(-glowR2/12.0)+0.030*exp2(-glowR2/125.0);
        value += (cross+glow)*0.55*clamp(energy/3.0,0.0,1.0);
    }
    if (value<=0.0) { front = 0.0; return vec3(0.0); }
    float captured = box.b/255.0;
    vec3 rgb = decodeDisplay(vec3(v1.g,v1.b,light.r)/255.0);
    return rgb*value*(1.0-captured*absorb*(1.0-front));
}
vec3 particlePage(vec2 pixel, vec3 header, float absorb, inout vec3 ahead) {
    float offset = particleOffset(header), count = mod(header.b,64.0);
    vec3 light = vec3(0.0);
    for (int j=0;j<16;++j) {
        if (float(j)>=count) break;
        vec3 reference = particleTexel(ubuf.particleAtlasInfo.w+offset+float(j));
        float index = reference.r+256.0*reference.g;
        if (index<ubuf.particleData.y) {
            float front;
            vec3 value = particleHit(pixel,index,absorb,front);
            light += value*(1.0-front);
            ahead += value*front;
        }
    }
    return light;
}
vec3 particleField(vec2 pixel, float absorb, out vec3 ahead) {
    ahead = vec3(0.0);
    if (ubuf.particleReady<0.5 || ubuf.particleData.y<0.5) return vec3(0.0);
    vec2 bin = floor(pixel/32.0);
    if (any(lessThan(bin,vec2(0.0))) || any(greaterThanEqual(bin,ubuf.particleGrid))) return vec3(0.0);
    vec3 header = particleTexel(ubuf.particleAtlasInfo.z+bin.x+bin.y*ubuf.particleGrid.x);
    if (header.b<0.5) return vec3(0.0);
    vec3 light = particlePage(pixel,header,absorb,ahead);
    if (header.b>=128.0) {
        // Explicit overflow path, up to 8192 occupants; the CPU's hard bound
        // is 6400 render instances. No seventeenth occupant is discarded.
        for (int page=0;page<511;++page) {
            float next = particleOffset(header)+mod(header.b,64.0);
            header = particleTexel(ubuf.particleAtlasInfo.w+next);
            light += particlePage(pixel,header,absorb,ahead);
            if (header.b<128.0) break;
        }
    }
    return light;
}
// Particle absorption into the bright inner disk: D's geometric envelope, never below the raw coverage.
float particleDiskAbsorb(vec2 pixel, float diskCoverage) { return max(diskCoverage, bhDiskAbsorb(pixel)); }

void legacyMain() {
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    vec3 colour = ubuf.skyColor.rgb;
    vec2 edgePosition = qt_TexCoord0 * 2.0 - 1.0;
    float edge = pow(clamp(dot(edgePosition, edgePosition) * 0.6, 0.0, 1.0), 1.5);
    colour += ubuf.edgeLift * edge * vec3(0.10, 0.19, 0.30);
    bool hole = ubuf.bhHalo.w > 0.0 && length(pixel-ubuf.bhCentre) < ubuf.bhGeometry.y;
    vec3 material = vec3(0.0), farField = vec3(0.0), linearColour = vec3(0.0);
    vec3 legacyColour = colour;
    float localEnvelope = 0.0;
    vec4 nebula = vec4(0.0);
    // v11: the remnant is sky, exactly like the passage, in both paths.
    vec4 remnant = vec4(0.0);
    if (ubuf.density > 0.0) {
        float scale = max(1.0, sqrt(ubuf.resolution.x * ubuf.resolution.y / (1024.0 * 576.0)));
        scale /= sqrt(max(0.0001, ubuf.density));
        vec2 relative = pixel - ubuf.resolution * 0.5;
        float baseAngle = ubuf.radialMode > 0.5 ? atan(relative.y, relative.x) : 0.0;
        if (ubuf.bhHalo.w <= 0.0 && ubuf.paddingAge < 0.0) {
            // A compile-time legacy specialization: no lens or migration
            // branches in the common, never-enabled sky kernel.
            vec3 field = stars(pixel,baseAngle,scale,0.0,-2.0,pixel,1.0);
            // Only the far layer is behind the cloud; the other two are not.
            nebula = nebulaField(pixel);
            remnant = supernovaRemnant(pixel);
            field *= (1.0-nebula.a)*(1.0-remnant.a);
            field += stars(pixel,baseAngle,scale,1.0,-2.0,pixel,1.0);
            field += stars(pixel,baseAngle,scale,2.0,-2.0,pixel,1.0);
            colour += field*ubuf.brightness;
        } else {
        vec2 farSource = pixel, materialSource = pixel;
        float farAngle = baseAngle, materialAngle = baseAngle;
        float pass = -1.0, rimLife = 1.0;
        bool domain = true;
        if (hole && ubuf.radialMode > 0.5) {
            float weight;
            farSource = bhWarpBackground(pixel,weight);
            domain = all(greaterThanEqual(farSource,vec2(0.0))) && all(lessThan(farSource,ubuf.resolution));
            materialSource = bhWarpMaterial(pixel,rimLife);
            pass = 1.0;
        }
        // One common evaluation per layer keeps the disabled render arithmetic
        // intact and avoids duplicating the entire star kernel in each branch.
        if (domain) farField = stars(farSource,farAngle,scale,0.0,-1.0,pixel,1.0);
        nebula = nebulaField(farSource);
        remnant = supernovaRemnant(farSource);
        farField *= (1.0-nebula.a)*(1.0-remnant.a);
        vec3 middleField = stars(materialSource,materialAngle,scale,1.0,pass,pixel,rimLife);
        vec3 nearField = stars(materialSource,materialAngle,scale,2.0,pass,pixel,rimLife);
        if (pass > 0.5 && ubuf.legacyMaterialAlive > 0.5) {
            middleField += stars(pixel,baseAngle,scale,1.0,0.0,pixel,1.0);
            nearField += stars(pixel,baseAngle,scale,2.0,0.0,pixel,1.0);
        }
        vec3 field = farField;
        field += middleField;
        field += nearField;
        legacyColour = colour+field*ubuf.brightness;
        if (hole) material = middleField+nearField;
        else colour = legacyColour;
        }
    }
    // The v3 path accumulates its layers display-encoded, so the cloud's
    // linear emission is encoded once here and joins the sky the same way a
    // star does. Both accumulators take it, so the hole's linear composite and
    // the legacy overlap correction stay in step.
    if (nebula.a > 0.0 || max(nebula.r,max(nebula.g,nebula.b)) > 0.0) {
        vec3 glow = encodeDisplay(nebula.rgb);
        colour += glow;
        legacyColour += glow;
    }
    if (max(remnant.r,max(remnant.g,remnant.b)) > 0.0) {
        vec3 glow = encodeDisplay(remnant.rgb);
        colour += glow;
        legacyColour += glow;
    }

    if (hole) {
        localEnvelope = ubuf.bhHalo.w*bhTaper(length(pixel-ubuf.bhCentre));
        vec3 base = decodeDisplay(colour+farField*ubuf.brightness);
        vec3 foreground = decodeDisplay(material*ubuf.brightness);
        vec3 background = base+foreground;
        // V3 added display-encoded layers. Fade that overlap correction with
        // the SAME spatial/enable envelope, so changing to linear composition
        // cannot pop at enable=0 or create a radiance seam at 4 Rh.
        if (max(base.r,max(base.g,base.b))>0.0 && max(foreground.r,max(foreground.g,foreground.b))>0.0)
            background += (decodeDisplay(legacyColour)-background)*(1.0-localEnvelope);
        background -= base*bhShadowMask(pixel);
        vec4 disk = bhDisk(pixel);
        linearColour = disk.rgb+(1.0-disk.a)*background;
    }
    // Captures have their own immutable rim fade; foreground passes stay in
    // front of the shadow and disk. Both are composed in linear light locally.
    vec3 e0 = eventSlot(pixel,ubuf.event0Head,ubuf.event0Colour,ubuf.event0Tail01,ubuf.event0Tail23,ubuf.event0Tail4,ubuf.event0Shape,ubuf.event0Bounds,ubuf.event0Burn,ubuf.meteorTone);
    vec3 e1 = eventSlot(pixel,ubuf.event1Head,ubuf.event1Colour,ubuf.event1Tail01,ubuf.event1Tail23,ubuf.event1Tail4,ubuf.event1Shape,ubuf.event1Bounds,ubuf.event1Burn,ubuf.meteorTone);
    vec3 e2 = eventSlot(pixel,ubuf.event2Head,ubuf.event2Colour,ubuf.event2Tail01,ubuf.event2Tail23,ubuf.event2Tail4,ubuf.event2Shape,ubuf.event2Bounds,ubuf.event2Burn,ubuf.meteorTone);
    e2 += radialField(pixel,ubuf.event3Head,ubuf.event3Colour,ubuf.event3Tail01,ubuf.event3Shape,ubuf.event3Bounds);
    e2 += radialField(pixel,ubuf.event4Head,ubuf.event4Colour,ubuf.event4Tail01,ubuf.event4Shape,ubuf.event4Bounds);
    e2 += radialField(pixel,ubuf.event5Head,ubuf.event5Colour,ubuf.event5Tail01,ubuf.event5Shape,ubuf.event5Bounds);
    // The legacy path has no far-field accumulator to join, so the storm rides
    // with the events here: no lensing on it, which is what `particlesEnabled:
    // false` already gives up for everything else in this branch.
    if (ubuf.stormShape.w>0.0) e2 += meteorStorm(pixel);
    if (hole) {
        vec3 events = decodeDisplay(e0+e1+e2);
        if (max(events.r,max(events.g,events.b))>0.0 && localEnvelope<1.0) {
            vec3 legacyEvents = legacyColour;
            legacyEvents += e0; legacyEvents += e1; legacyEvents += e2;
            events += (decodeDisplay(legacyEvents)-decodeDisplay(legacyColour)-events)*(1.0-localEnvelope);
        }
        colour = encodeDisplay(linearColour+events);
    }
    else { colour += e0; colour += e1; colour += e2; }
    float dither = fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715)))) - 0.5;
    float lit = step(1.0 / 255.0, max(colour.r, max(colour.g, colour.b)));
    colour += lit * dither / 255.0;
    fragColor = vec4(clamp(colour, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}

void main() {
    if (ubuf.particlesEnabled<0.5) { legacyMain(); return; }
    vec2 pixel = qt_TexCoord0*ubuf.resolution;
    float r = length(pixel-ubuf.bhCentre);
    bool hole = ubuf.bhHalo.w>0.0 && r<ubuf.bhGeometry.y;
    vec4 disk = hole ? bhDisk(pixel) : vec4(0.0);
    vec2 edgePosition = qt_TexCoord0*2.0-1.0;
    float edge = pow(clamp(dot(edgePosition,edgePosition)*0.6,0.0,1.0),1.5);
    vec3 far = ubuf.skyColor.rgb+ubuf.edgeLift*edge*vec3(0.10,0.19,0.30);
    vec3 material = vec3(0.0), ahead = vec3(0.0);
    // The nebula passage rides with the far field: it is evaluated at the same
    // (lensed) source coordinate, so it bends with the background it belongs
    // to, and it is applied to `far` after the decode and before the shadow.
    vec4 nebula = vec4(0.0);
    // How much of a particle BEHIND the disk the disk eats. disk.a is only the
    // alpha the emissive shading happened to leave; bhDiskAbsorb is the disk's
    // geometric coverage weighted by its own emissivity, which is what actually
    // stands between a star and the camera. Taking the larger of the two is why
    // a star can cross the disk band alive without ever being drawn ON TOP of
    // the material (his report, ledger 2281).
    float diskOcclusion = 0.0;
    // A storm meteor is sky, not foreground: it is accumulated into `far`, so
    // one passing the hole is lensed by the same warp the background stars get,
    // is eaten by the shadow, and sinks behind the disk. No other event has
    // that, because no other event is evaluated at a pixel.
    // The far stars, the cloud and the storm all read the SAME lensed source,
    // so all three bend together with the background they belong to.
    vec2 skySource = pixel;
    if (hole && ubuf.radialMode>0.5 && (ubuf.density>0.0 || ubuf.stormShape.w>0.0 || ubuf.nebulaHead.w>0.0)) { float weight; skySource=bhWarpBackground(pixel,weight); }
    if (ubuf.density>0.0) {
        float scale = max(1.0,sqrt(ubuf.resolution.x*ubuf.resolution.y/(1024.0*576.0)))/sqrt(ubuf.density);
        vec2 relative = pixel-ubuf.resolution*0.5;
        float angle = ubuf.radialMode>0.5 ? atan(relative.y,relative.x) : 0.0;
        if (all(greaterThanEqual(skySource,vec2(0.0))) && all(lessThan(skySource,ubuf.resolution)))
            far += stars(skySource,angle,scale,0.0,-1.0,pixel,1.0)*ubuf.brightness;
        diskOcclusion = particleDiskAbsorb(pixel,disk.a);
        material = particleField(pixel,diskOcclusion,ahead)*ubuf.brightness;
        ahead *= ubuf.brightness;
    }
    // Outside the density guard: a passage is the sky's own dust, not the far
    // star layer's, and `far` carries the palette and the edge lift whether or
    // not any star is drawn. The kernel's own head.w test is the switch.
    nebula = nebulaField(skySource);
    // ---- v9 COMPOSITE ORDER: far dust -> nebula -> storm -> shadow ----------
    // The dust lanes eat the far field and the emission joins it, both before
    // the shadow, so the cloud is behind the disk and never drawn over the
    // shadow. The storm is added AFTER the cloud, because a meteor is in the
    // atmosphere and nothing in deep space can extinct it.
    //
    // The storm accumulates display-encoded with the stars (that is what it was
    // measured as), and the cloud's extinction is linear, so the storm's
    // contribution is taken as the exact DIFFERENCE the encoded accumulation
    // would have made. With no cloud alive that is bit-for-bit the storm's own
    // branch; with no storm alive it costs one compare.
    vec3 farLinear = decodeDisplay(far);
    vec3 stormLinear = vec3(0.0);
    if (ubuf.stormShape.w>0.0) stormLinear = decodeDisplay(far+meteorStorm(skySource)*ubuf.brightness)-farLinear;
    far = farLinear*(1.0-nebula.a)+nebula.rgb+stormLinear;
    // v11: the supernova remnant is the sky's own gas, not a sprite on top of
    // it. Same contract and the same place in the order as the nebula passage:
    // its dust column multiplies whatever is behind it (so the stars shine
    // THROUGH it) and its emission joins the far field, both before the shadow,
    // so with the hole on it sinks behind the disk like everything else. It is
    // evaluated at skySource, the LENSED coordinate, so it bends with the
    // background it belongs to.
    vec4 remnant = supernovaRemnant(skySource);
    far = far*(1.0-remnant.a)+remnant.rgb*ubuf.brightness;
    if (hole) far *= 1.0-bhShadowMask(pixel);
    // Explicit particles live in the apparent plane. bhWarpMaterial is used
    // only by legacyMain; their swept death remains at Rh, never sqrt(2)*Rh.
    float shadowPass = mix(1.0,smoothstep(ubuf.bhGeometry.x,ubuf.bhGeometry.x+0.75,r),ubuf.bhHalo.w);
    material *= shadowPass;
    // A small share of near particles is in front of the disk: composited after
    // it, masked by the geometric shadow only, so the disk reads as behind them.
    // Everything else is BEHIND the disk and is attenuated by the disk's own
    // coverage, not by the alpha its shading left: a middle star crossing the
    // material sinks into it instead of riding over the top of it.
    vec3 linearColour = disk.rgb+(1.0-disk.a)*far+(1.0-diskOcclusion)*material+ahead*shadowPass;
    // v11 REMOVED: the v9/v10 core-collapse SKY LIFT lived here. It multiplied
    // every pixel of the screen by 1 + 2.5*gauss and added a flat haze, which
    // is what "I don't like that my screen flashes during the explosion"
    // (ledger 2286) was about. Measured on his tablet before it went: the whole
    // -frame mean went 12.7 -> 54.0 of 255 in one second, a 4.3x lift on pixels
    // a thousand px from the site. Nothing global replaces it. The detonation
    // is still the brightest moment on the screen, but every term that makes it
    // so is now bounded: the core and its bloom by the slot's own `bounds` box,
    // the neighbouring stars by brightenNear's 1.5 shell radii. A pixel outside
    // those is bit-for-bit what it would have been with no supernova at all,
    // and tools/sn_flash.py proves it on real frames.
    vec3 events = eventSlot(pixel,ubuf.event0Head,ubuf.event0Colour,ubuf.event0Tail01,ubuf.event0Tail23,ubuf.event0Tail4,ubuf.event0Shape,ubuf.event0Bounds,ubuf.event0Burn,ubuf.meteorTone);
    events += eventSlot(pixel,ubuf.event1Head,ubuf.event1Colour,ubuf.event1Tail01,ubuf.event1Tail23,ubuf.event1Tail4,ubuf.event1Shape,ubuf.event1Bounds,ubuf.event1Burn,ubuf.meteorTone);
    events += eventSlot(pixel,ubuf.event2Head,ubuf.event2Colour,ubuf.event2Tail01,ubuf.event2Tail23,ubuf.event2Tail4,ubuf.event2Shape,ubuf.event2Bounds,ubuf.event2Burn,ubuf.meteorTone);
    events += radialField(pixel,ubuf.event3Head,ubuf.event3Colour,ubuf.event3Tail01,ubuf.event3Shape,ubuf.event3Bounds);
    events += radialField(pixel,ubuf.event4Head,ubuf.event4Colour,ubuf.event4Tail01,ubuf.event4Shape,ubuf.event4Bounds);
    events += radialField(pixel,ubuf.event5Head,ubuf.event5Colour,ubuf.event5Tail01,ubuf.event5Shape,ubuf.event5Bounds);
    vec3 colour = encodeDisplay(linearColour+decodeDisplay(events));
    float dither = fract(52.9829189*fract(dot(floor(pixel),vec2(0.06711056,0.00583715))))-0.5;
    float lit = step(1.0/255.0,max(colour.r,max(colour.g,colour.b)));
    colour += lit*dither/255.0;
    fragColor = vec4(clamp(colour,0.0,1.0),1.0)*ubuf.qt_Opacity;
}
