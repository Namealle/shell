// Birth-owned optical values. Rendering offsets never enter the force state.
function clamp(x, a, b) { return Math.max(a, Math.min(b, Number.isFinite(x) ? x : a)); }
function smooth(a, b, x) { var t = clamp((x - a) / Math.max(1e-9, b - a), 0, 1); return t * t * (3 - 2 * t); }
function draw(seed, salt) {
    var x = (seed + Math.imul(salt, 1013904223)) | 0;
    x ^= x << 13; x ^= x >>> 17; x ^= x << 5;
    return (x >>> 0) / 4294967296;
}
function choose(weights, count, u) {
    var sum = 0, i;
    for (i = 0; i < count; ++i) sum += Math.max(0, Number(weights[i]) || 0);
    if (sum <= 0) return Math.min(count - 1, Math.floor(u * count));
    var target = u * sum;
    for (i = 0; i < count - 1; ++i) { target -= Math.max(0, Number(weights[i]) || 0); if (target < 0) return i; }
    return count - 1;
}
function range(value, fallback, lo, hi, u) {
    var a = value && value.length === 2 ? clamp(value[0], lo, hi) : fallback[0];
    var b = value && value.length === 2 ? clamp(value[1], lo, hi) : fallback[1];
    return Math.min(a, b) + u * Math.abs(b - a);
}
function ensure(s) {
    if (s.exposure) return;
    for (var k of ["exposure", "maxStreak", "entryStamp", "altR", "altG", "altB", "flare", "shimmerRate"])
        s[k] = new Float64Array(s.capacity);
    s.entryStamp.fill(-1);
}
function birth(s, i, input) {
    ensure(s);
    var seed = ((input.seed | 0) ^ Math.imul(i + 1, 1664525) ^ Math.imul(s.generation[i], 1013904223)) >>> 0;
    var near = s.depth[i] > 0.5, params = input.params || {}, colors = input.colors || [];
    // A few near particles carry v3's four-point flare. The draw is frozen here;
    // render() caps how many of them may actually be flared at once.
    var flared = near && draw(seed, 83) < s.config.flare.share;
    s.flare[i] = flared ? 1 : 0;
    var v = draw(seed, 11), rgb = [0.73 + 0.27 * v, 0.84 + 0.14 * v, 1 - 0.06 * v];
    // A flared near star always takes a palette colour and keeps far more of it:
    // these are the handful of stars the eye reads as coloured.
    var tinted = colors.length > 0 && (flared || draw(seed, 19) < clamp(input.mix, 0, 0.45));
    var index = tinted ? choose(input.weights || [], colors.length, draw(seed, 23)) : 0;
    if (tinted) {
        rgb = colors[index].slice();
        var white = 0.10 * draw(seed, 29), whiten = flared ? 0.30 : 0.35;
        for (var c = 0; c < 3; ++c) {
            rgb[c] += (1 - rgb[c]) * white;
            if (near) rgb[c] += (1 - rgb[c]) * whiten;
        }
    } else if (!colors.length) {
        var legacy = input.legacy || [0, 0, 0, 0.5], total = legacy[0] + legacy[1] + legacy[2];
        var factor = Math.min(1, 0.45 / Math.max(1e-9, total));
        var t = draw(seed, 31), target = rgb;
        if (t < legacy[0] * factor) target = [0.65, 1, 0.78];
        else if (t < (legacy[0] + legacy[1]) * factor) target = [0.86, 0.80, 1];
        else if (t < total * factor) target = [1, 0.83, 0.67];
        for (c = 0; c < 3; ++c) { rgb[c] += (target[c] - rgb[c]) * 0.45; if (near) rgb[c] += (1 - rgb[c]) * 0.65; }
    } else if (near) for (c = 0; c < 3; ++c) rgb[c] += (1 - rgb[c]) * 0.35;
    var weights = input.archetypes || [0.82, 0.10, 0.04, 0.02, 0.015, 0.005];
    var w = [], sum = 0;
    for (var a = 0; a < 6; ++a) { w[a] = Math.max(0, Number(weights[a]) || 0); sum += w[a]; }
    if (sum <= 0) { w = [1, 0, 0, 0, 0, 0]; sum = 1; }
    for (a = 0; a < 6; ++a) w[a] /= sum;
    if (w[0] < 0.75) { var scale = 0.25 / (1 - w[0]); for (a = 1; a < 6; ++a) w[a] *= scale; w[0] = 0.75; }
    var kind = choose(w, 6, draw(seed, 37));
    // The original report's decayer is near-only.
    if (!near && kind === 2) kind = 0;
    s.archetype[i] = kind; s.seed[i] = seed;
    s.phase[i] = draw(seed, 41) * 2 * Math.PI;
    s.r[i] = rgb[0]; s.g[i] = rgb[1]; s.b[i] = rgb[2];
    s.altR[i] = rgb[0]; s.altG[i] = rgb[1]; s.altB[i] = rgb[2];
    s.size[i] = range(near ? s.config.sizes.nearPx : s.config.sizes.middlePx, near ? [2.4, 4.4] : [1, 2], 0.25, 12, draw(seed, 43));
    s.capturedSize[i] = range(s.config.sizes.capturedPx, [1.0, 1.8], 0.25, 12, draw(seed, 47));
    // Near luminosity is the gain of a saturating core (see the shader): 2.6
    // already reaches 0.93 of full white at the centre, so the brightest near
    // particles read like v3's near stars instead of like normalized dust.
    s.luminosity[i] = near ? (flared ? 3.4 : 2.6) + 1.4 * draw(seed, 53) : 0.4 + 0.6 * draw(seed, 53);
    s.exposure[i] = s.config.streak.exposureSec; s.maxStreak[i] = s.config.streak.maxPx;
    // Frozen here so the twinkle term costs one sine per frame, not a hash too.
    s.shimmerRate[i] = 193 + Math.floor(draw(seed, 79) * 238);
    s.entryStamp[i] = -1;
    var p = params[["steady", "pulsator", "decayer", "glint", "wanderer", "binary"][kind]] || {};
    s.p0[i] = 0; s.p1[i] = 0; s.p2[i] = 0; s.p3[i] = 0;
    var period = 1;
    if (kind === 1) {
        period = range(p.periodSec, [6, 40], 1, 4096, draw(seed, 59));
        s.p1[i] = range(p.amplitude, [0.08, 0.22], 0, 0.22, draw(seed, 61));
    } else if (kind === 2) {
        s.p0[i] = range(p.lifeSec, [20, 90], 20, 3600, draw(seed, 59));
        s.p1[i] = range(p.fadeInSec, [3, 8], 0.1, 120, draw(seed, 61));
    } else if (kind === 3) {
        period = range(p.everySec, [18, 65], 2, 4096, draw(seed, 59));
        s.p1[i] = range(p.widthSec, [0.8, 2], 0.1, 60, draw(seed, 61));
        s.p2[i] = p.gain === undefined ? 0.18 : clamp(p.gain, 0, 0.18);
    } else if (kind === 4) {
        period = range(p.periodSec, [30, 100], 2, 4096, draw(seed, 59));
        s.p1[i] = p.offsetPx === undefined ? 8 : clamp(p.offsetPx, 0, 8);
    } else if (kind === 5) {
        period = range(p.periodSec, [12, 45], 2, 4096, draw(seed, 59));
        s.p1[i] = 0.5 * range(p.separationPx, [1.5, 5], 0, 16, draw(seed, 61));
    }
    if (kind !== 2) s.p0[i] = Math.max(1, Math.round(4096 / period));
    // Optional color-shifter retains two resolved colors, never palette indices.
    var shift = params.colorShifter || {}, share = clamp(shift.share || 0, 0, Math.max(0, w[0] - 0.75));
    if (kind === 0 && tinted && draw(seed, 67) < share / Math.max(0.001, w[0])) {
        var other = colors[(index + 1) % colors.length];
        s.archetype[i] = 6;
        s.p0[i] = Math.max(1, Math.round(4096 / range(shift.periodSec, [120, 360], 30, 4096, draw(seed, 71))));
        var whitening = near ? 0.35 : 0;
        s.altR[i] = other[0] + (1 - other[0]) * whitening;
        s.altG[i] = other[1] + (1 - other[1]) * whitening;
        s.altB[i] = other[2] + (1 - other[2]) * whitening;
    }
}
// The four-point flare reuses the shader's v3 cross. Its optical scale is
// FLARE_OPTICS core radii; spikes taper to zero at 22 of those and the residual
// glow is under a quarter code by FLARE_SUPPORT of them. FLARE_CORE_MAX keeps
// the bin radius inside the support byte.
var FLARE_SUPPORT = 25.0, FLARE_OPTICS = 0.55, FLARE_CORE_MAX = 4.8;
// Bin radius of an already-quantized core/streak pair, in 0.5 px steps. The
// quantization and the packed position's reconstruction error are inside the
// 0.20 px margin.
function supportFor(core, streak, flare) {
    var sigma = core / 2.354820045;
    var radius = 3.5 * Math.sqrt(sigma * sigma + 1 / 12 + streak * streak / 12) + 0.20;
    if (flare) radius = Math.max(radius, FLARE_SUPPORT * FLARE_OPTICS * Math.min(core, FLARE_CORE_MAX));
    return Math.ceil(radius * 2) / 2;
}
// Hard per-configuration ceilings, so the atlas can be allocated once and never
// resized: a binary emits two render instances, every other archetype one, no
// live core or streak can exceed the validated configuration maxima, and
// render() itself caps how many instances may carry a flare.
function bounds(s) {
    var z = s.config.sizes;
    var core = Math.round(clamp(Math.max(z.nearPx[1], z.middlePx[1], z.capturedPx[1]), 0.25, 12) * 16) / 16;
    var streak = Math.round(clamp(s.config.streak.maxPx, 0, 32) * 255 / 32) * 32 / 255;
    var nearCore = Math.round(clamp(z.nearPx[1], 0.25, 12) * 16) / 16;
    return {maxItems: 2 * s.targetPopulation, maxSupport: supportFor(core, streak, false),
        maxFlares: s.config.flare.maxAlive, flareSupport: supportFor(nearCore, streak, true)};
}
// Render instances are one flat Float64Array, not an array of objects: writing
// eighteen properties per instance per frame is the single most expensive thing
// this file can do in QML's JS engine. The field order is the contract shared
// with Binning.js and Packing.js (and documented in PARTICLES.md).
var STRIDE = 18;
var IX = 0, IY = 1, IVX = 2, IVY = 3, ICORE = 4, ISUPPORT = 5, ISTREAK = 6, IR = 7,
    IG = 8, IB = 9, ILUM = 10, IFLAGS = 11, IPHASE = 12, IP0 = 13, IAGE = 14,
    ICAPTURED = 15, IID = 16, IGENERATION = 17;
// Test and fixture helper: the same flat form from an array of plain objects.
function instances(list) {
    if (list && list.data) return list;
    var out = {data: new Float64Array(list.length * STRIDE), count: list.length, stride: STRIDE};
    for (var i = 0; i < list.length; ++i) {
        var p = list[i], b = i * STRIDE;
        out.data[b + IX] = p.x; out.data[b + IY] = p.y;
        out.data[b + IVX] = p.vx || 0; out.data[b + IVY] = p.vy || 0;
        out.data[b + ICORE] = p.core || 0; out.data[b + ISUPPORT] = p.support || 0;
        out.data[b + ISTREAK] = p.streak || 0;
        out.data[b + IR] = p.r || 0; out.data[b + IG] = p.g || 0; out.data[b + IB] = p.b || 0;
        out.data[b + ILUM] = p.lum || 0;
        out.data[b + IFLAGS] = p.flags === undefined ? (p.kind || 0) : p.flags;
        out.data[b + IPHASE] = p.phase || 0; out.data[b + IP0] = p.p0 || 0;
        out.data[b + IAGE] = p.age || 0; out.data[b + ICAPTURED] = p.captured || 0;
        out.data[b + IID] = p.id || 0; out.data[b + IGENERATION] = p.generation || 0;
    }
    return out;
}
function render(previous, s, style) {
    ensure(s);
    var items = previous && previous.data ? previous : {data: new Float64Array(STRIDE * 64), count: 0, stride: STRIDE};
    var out = items.data, count = 0;
    var tau = 2 * Math.PI, phaseTime = ((s.clock % 4096) + 4096) % 4096;
    var twinkle = clamp(style && style.twinkle || 0, 0, 1);
    var cycle = phaseTime * tau / 4096;
    // Every array this loop touches is hoisted; a property lookup on the state
    // object costs more than the arithmetic around it in QML's JS engine.
    var X = s.x, Y = s.y, VX = s.vx, VY = s.vy, AGE = s.age, SEED = s.seed;
    var KIND = s.archetype, PHASE = s.phase, P0 = s.p0, P1 = s.p1, P2 = s.p2;
    var SIZE = s.size, CAPSIZE = s.capturedSize, LUM = s.luminosity, FLARE = s.flare, DEPTH = s.depth;
    var RCAP = s.radiusAtCapture, CTIME = s.captureTime, ENTRY = s.entryTime, STAMP = s.entryStamp;
    var EXPOSURE = s.exposure, MAXSTREAK = s.maxStreak, GEN = s.generation, SHIMMER = s.shimmerRate;
    var R = s.r, G = s.g, B = s.b, ALTR = s.altR, ALTG = s.altG, ALTB = s.altB;
    var live = s.live, n = s.liveCount, cx = s.centreX, cy = s.centreY, rh = s.rh;
    var width = s.width, height = s.height, clock = s.clock, dim = s.config.flare.capturedLight;
    var flareCap = s.config.flare.maxAlive, flares = 0;
    for (var k = 0; k < n; ++k) {
        var i = live[k];
        var kind = KIND[i], phase = PHASE[i];
        var oscillation = cycle * P0[i] + phase;
        var behavior = 1, ox = 0, oy = 0;
        if (kind === 1) behavior += P1[i] * Math.sin(oscillation);
        else if (kind === 2) {
            if (ENTRY) STAMP[i] = ENTRY[i];
            else if (STAMP[i] < 0 && X[i] >= 0 && X[i] <= width && Y[i] >= 0 && Y[i] <= height) STAMP[i] = clock;
            var age = STAMP[i] < 0 ? -1 : clock - STAMP[i];
            var life = P0[i];
            behavior = age < 0 ? 0 : smooth(0, P1[i], age) * (1 - smooth(0.55 * life, life, age)) * (1 + 0.25 * Math.pow(2, -4 * Math.max(0, age) / life));
        } else if (kind === 3) {
            var period = 4096 / P0[i], fraction = oscillation / tau;
            var phaseAge = Math.abs(fraction - Math.floor(fraction) - 0.5) * period;
            behavior += P2[i] * (1 - smooth(0, Math.min(period * 0.5, P1[i]) * 0.5, phaseAge));
        } else if (kind === 4) {
            ox = P1[i] * Math.SQRT1_2 * Math.sin(oscillation);
            oy = P1[i] * Math.SQRT1_2 * Math.sin(cycle * (P0[i] + 1) + phase * 1.7);
        } else if (kind === 5) { ox = P1[i] * Math.cos(oscillation); oy = P1[i] * Math.sin(oscillation); }
        var captured = RCAP[i] > 0 ? smooth(0, 4, clock - CTIME[i]) : 0;
        var core = SIZE[i] + captured * (CAPSIZE[i] - SIZE[i]);
        var vx = VX[i], vy = VY[i];
        var streak = Math.min(MAXSTREAK[i], Math.sqrt(vx * vx + vy * vy) * EXPOSURE[i]);
        // Round the rendered geometry first; the bin radius includes its
        // quantization and position reconstruction error, not just source math.
        core = (((core > 12 ? 12 : (core > 0.25 ? core : 0.25)) * 16 + 0.5) | 0) / 16;
        streak = (((streak > 32 ? 32 : (streak > 0 ? streak : 0)) * (255 / 32) + 0.5) | 0) * (32 / 255);
        // The flare cap is enforced here, not at birth, so the atlas allocation
        // ceiling is a hard bound: the excess simply renders as a plain core.
        var components = kind === 5 ? 2 : 1;
        var flare = FLARE[i] > 0.5 && flares + components <= flareCap ? 1 : 0;
        flares += flare * components;
        var support = supportFor(core, streak, flare);
        var dx = X[i] - cx, dy = Y[i] - cy;
        var radius = Math.sqrt(dx * dx + dy * dy);
        // Both fades are inlined smoothsteps and both are 1 almost everywhere:
        // a particle is only inside the rim fade or younger than 0.35 s rarely.
        var span = core * 2 > 6 ? core * 2 : 6, fade = 1;
        if (radius < rh + span) {
            var u = radius <= rh ? 0 : (radius - rh) / span;
            fade = u * u * (3 - 2 * u);
        }
        var age0 = AGE[i];
        if (age0 < 0.35) { var w0 = age0 <= 0 ? 0 : age0 / 0.35; fade *= w0 * w0 * (3 - 2 * w0); }
        var shimmer = twinkle > 0 ? 1 + 0.15 * twinkle * Math.sin(cycle * SHIMMER[i] + phase) : 1;
        var light = LUM[i] * (1 - dim * captured) * behavior * fade * shimmer;
        var mix = kind === 6 ? 0.5 - 0.5 * Math.cos(oscillation) : 0;
        // kind 0..6, bit 3 = four-point flare, bit 4 = near layer (saturating core)
        var flags = kind + 8 * flare + (DEPTH[i] > 0.5 ? 16 : 0);
        for (var component = 0; component < components; ++component) {
            if ((count + 1) * 18 > out.length) {
                var grown = new Float64Array(Math.max((count + 1) * 18, out.length * 2));
                grown.set(out);
                out = items.data = grown;
            }
            // Literal offsets: a module-scope name costs a dictionary lookup
            // per write in QML's JS engine. Order is the STRIDE contract above.
            var b = count * 18, sign = component === 0 ? 1 : -1;
            out[b] = X[i] + sign * ox; out[b + 1] = Y[i] + sign * oy;
            out[b + 2] = vx; out[b + 3] = vy; out[b + 4] = core;
            out[b + 5] = support; out[b + 6] = streak;
            out[b + 7] = R[i] + mix * (ALTR[i] - R[i]);
            out[b + 8] = G[i] + mix * (ALTG[i] - G[i]);
            out[b + 9] = B[i] + mix * (ALTB[i] - B[i]);
            out[b + 10] = light / components; out[b + 11] = flags;
            out[b + 12] = phase; out[b + 13] = P0[i]; out[b + 14] = AGE[i];
            out[b + 15] = captured; out[b + 16] = i; out[b + 17] = GEN[i];
            ++count;
        }
    }
    items.count = count;
    return items;
}

if (typeof module !== "undefined") module.exports = { birth: birth, render: render, draw: draw,
    supportFor: supportFor, bounds: bounds, instances: instances, STRIDE: STRIDE };
