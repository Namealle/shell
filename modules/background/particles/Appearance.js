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
    for (var k of ["exposure", "maxStreak", "entryStamp", "altR", "altG", "altB"])
        s[k] = new Float64Array(s.capacity);
    s.entryStamp.fill(-1);
}
function birth(s, i, input) {
    ensure(s);
    var seed = ((input.seed | 0) ^ Math.imul(i + 1, 1664525) ^ Math.imul(s.generation[i], 1013904223)) >>> 0;
    var near = s.depth[i] > 0.5, params = input.params || {}, colors = input.colors || [];
    var v = draw(seed, 11), rgb = [0.73 + 0.27 * v, 0.84 + 0.14 * v, 1 - 0.06 * v];
    var tinted = colors.length > 0 && draw(seed, 19) < clamp(input.mix, 0, 0.45);
    var index = tinted ? choose(input.weights || [], colors.length, draw(seed, 23)) : 0;
    if (tinted) {
        rgb = colors[index].slice();
        var white = 0.10 * draw(seed, 29);
        for (var c = 0; c < 3; ++c) {
            rgb[c] += (1 - rgb[c]) * white;
            if (near) rgb[c] += (1 - rgb[c]) * 0.35;
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
    s.size[i] = range(near ? s.config.sizes.nearPx : s.config.sizes.middlePx, near ? [2, 4] : [1, 2], 0.25, 12, draw(seed, 43));
    s.capturedSize[i] = range(s.config.sizes.capturedPx, [0.8, 1.4], 0.25, 12, draw(seed, 47));
    s.luminosity[i] = near ? 2.4 + 1.4 * draw(seed, 53) : 0.4 + 0.6 * draw(seed, 53);
    s.exposure[i] = s.config.streak.exposureSec; s.maxStreak[i] = s.config.streak.maxPx;
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
// Bin radius of an already-quantized core/streak pair. The quantization and the
// packed position's reconstruction error are inside the 0.20 px margin.
function supportFor(core, streak) {
    var sigma = core / 2.354820045;
    return Math.ceil((3.5 * Math.sqrt(sigma * sigma + 1 / 12 + streak * streak / 12) + 0.20) * 4) / 4;
}
// Hard per-configuration ceilings, so the atlas can be allocated once and never
// resized: a binary emits two render instances, every other archetype one, and
// no live core or streak can exceed the validated configuration maxima.
function bounds(s) {
    var z = s.config.sizes;
    var core = Math.max(z.nearPx[1], z.middlePx[1], z.capturedPx[1]);
    return {maxItems: 2 * s.targetPopulation,
        maxSupport: supportFor(Math.round(clamp(core, 0.25, 12) * 16) / 16,
            Math.round(clamp(s.config.streak.maxPx, 0, 32) * 255 / 32) * 32 / 255)};
}
function render(previous, s, style) {
    ensure(s);
    var items = previous || [], count = 0;
    var tau = 2 * Math.PI, phaseTime = ((s.clock % 4096) + 4096) % 4096;
    var twinkle = clamp(style && style.twinkle || 0, 0, 1);
    for (var i = 0; i < s.capacity; ++i) {
        if (!s.alive[i]) continue;
        var kind = s.archetype[i], phase = s.phase[i];
        var oscillation = phaseTime * tau / 4096 * s.p0[i] + phase;
        var behavior = 1, ox = 0, oy = 0;
        if (kind === 1) behavior += s.p1[i] * Math.sin(oscillation);
        else if (kind === 2) {
            if (s.entryTime) s.entryStamp[i] = s.entryTime[i];
            else if (s.entryStamp[i] < 0 && s.x[i] >= 0 && s.x[i] <= s.width && s.y[i] >= 0 && s.y[i] <= s.height) s.entryStamp[i] = s.clock;
            var age = s.entryStamp[i] < 0 ? -1 : s.clock - s.entryStamp[i];
            var life = s.p0[i];
            behavior = age < 0 ? 0 : smooth(0, s.p1[i], age) * (1 - smooth(0.55 * life, life, age)) * (1 + 0.25 * Math.pow(2, -4 * Math.max(0, age) / life));
        } else if (kind === 3) {
            var period = 4096 / s.p0[i], fraction = oscillation / tau;
            var phaseAge = Math.abs(fraction - Math.floor(fraction) - 0.5) * period;
            behavior += s.p2[i] * (1 - smooth(0, Math.min(period * 0.5, s.p1[i]) * 0.5, phaseAge));
        } else if (kind === 4) {
            ox = s.p1[i] * Math.SQRT1_2 * Math.sin(oscillation);
            oy = s.p1[i] * Math.SQRT1_2 * Math.sin(phaseTime * tau / 4096 * (s.p0[i] + 1) + phase * 1.7);
        } else if (kind === 5) { ox = s.p1[i] * Math.cos(oscillation); oy = s.p1[i] * Math.sin(oscillation); }
        var captured = s.radiusAtCapture[i] > 0 ? smooth(0, 4, s.clock - s.captureTime[i]) : 0;
        var core = s.size[i] + captured * (s.capturedSize[i] - s.size[i]);
        var speed = Math.sqrt(s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i]);
        var streak = Math.min(s.maxStreak[i], speed * s.exposure[i]);
        // Round the rendered geometry first; the bin radius includes its
        // quantization and position reconstruction error, not just source math.
        core = Math.round(clamp(core, 0.25, 12) * 16) / 16;
        streak = Math.round(clamp(streak, 0, 32) * 255 / 32) * 32 / 255;
        var support = supportFor(core, streak);
        var radius = Math.hypot(s.x[i] - s.centreX, s.y[i] - s.centreY);
        var fade = smooth(s.rh, s.rh + Math.max(6, core * 2), radius) * smooth(0, 0.35, s.age[i]);
        var shimmer = 1 + 0.15 * twinkle * Math.sin(phaseTime * tau / 4096 * (193 + Math.floor(draw(s.seed[i], 79) * 238)) + phase);
        var light = s.luminosity[i] * (1 - 0.94 * captured) * behavior * fade * shimmer;
        var mix = kind === 6 ? 0.5 - 0.5 * Math.cos(oscillation) : 0;
        var components = kind === 5 ? 2 : 1;
        for (var component = 0; component < components; ++component) {
            var item = items[count] || {};
            var sign = component === 0 ? 1 : -1;
            item.x = s.x[i] + sign * ox; item.y = s.y[i] + sign * oy;
            item.vx = s.vx[i]; item.vy = s.vy[i]; item.core = core;
            item.support = support; item.streak = streak;
            item.r = s.r[i] + mix * (s.altR[i] - s.r[i]);
            item.g = s.g[i] + mix * (s.altG[i] - s.g[i]);
            item.b = s.b[i] + mix * (s.altB[i] - s.b[i]);
            item.lum = light / components; item.kind = kind; item.phase = phase;
            item.p0 = s.p0[i]; item.age = s.age[i]; item.captured = captured;
            item.id = i; item.generation = s.generation[i];
            items[count++] = item;
        }
    }
    items.length = count;
    return items;
}

if (typeof module !== "undefined") module.exports = { birth: birth, render: render, draw: draw,
    supportFor: supportFor, bounds: bounds };
