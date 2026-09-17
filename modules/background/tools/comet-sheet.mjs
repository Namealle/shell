#!/usr/bin/env node
// Renders a COMET PASS offscreen through the real kernels at a set of ages and
// measures whether the object evolves -- which, before v12, it did not: over an
// 8.4 s pass nothing about it changed except its position.
//
//   cc -O2 -o /tmp/bhrender modules/background/tools/bhrender.c -lEGL -lGL -lm
//   node modules/background/tools/comet-sheet.mjs /tmp/bhrender OUTDIR [label] [config.json]
//   COMET_FAMILY=slow COMET_AGES=40 node ...
//
// Measures, in the order of the V12 acceptance tests:
//   M9   coma sigma, ion length, dust length and lit pixels over the pass:
//        each must PEAK inside it rather than sitting flat, the dust must peak
//        AFTER the ion, and the ion must be exactly zero before activation
//   M10  do the synchrones move? The dust tail's along-axis ridge profile is
//        cross-correlated between frames one second apart; the shift must be
//        AWAY from the nucleus and the same sign across the pass
//
// Every length is measured on the PIXELS -- walked out along the published
// direction until the ridge falls under the visibility floor -- never read
// back from the uniform that set it.
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFileSync, writeFileSync, mkdirSync, rmSync } from "fs";
import { execFileSync } from "child_process";
import vm from "vm";
import { makeHost } from "./test-events.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const FRAG = join(repo, "modules", "background", "shaders", "starfield.frag");
const rulesContext = vm.createContext({ Math, JSON, isFinite, Number, Object, Array, console });
vm.runInContext(readFileSync(join(repo, "services", "ambient", "rules.js"), "utf8") + "\nthis.validateDocument = validateDocument;", rulesContext);

function fragFunction(src, name) {
    const re = new RegExp("^(?:float|vec2|vec3|vec4)\\s+" + name + "\\s*\\(", "m");
    const m = re.exec(src);
    if (!m) throw new Error("no " + name + "() in starfield.frag");
    const open = src.indexOf("{", m.index);
    let depth = 0, i = open;
    for (; i < src.length; ++i) {
        if (src[i] === "{") depth++;
        else if (src[i] === "}" && --depth === 0) break;
    }
    return src.slice(m.index, i + 1);
}

const KERNELS = ["hash4", "lightCurve", "naProfile", "ablationStreak", "tailSegment",
    "cometHash", "cometGrain", "cometField", "supernovaField", "radialField", "stormHash",
    "trainPoint", "trainShear", "stormTrainRay", "stormTrainSegment", "stormFireball", "meteorStorm", "eventSlot"];

function previewShader() {
    const src = readFileSync(FRAG, "utf8");
    const kernels = KERNELS.filter(n => new RegExp("^(?:float|vec2|vec3|vec4)\\s+" + n + "\\s*\\(", "m").test(src))
        .map(n => fragFunction(src, n)).join("\n\n");
    return `#version 450 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    vec2 resolution;
    vec4 event0Head; vec4 event0Colour; vec4 event0Tail01; vec4 event0Tail23;
    vec2 event0Tail4; vec4 event0Shape; vec4 event0Bounds;
    vec4 event1Head; vec4 event1Colour; vec4 event1Tail01; vec4 event1Tail23;
    vec2 event1Tail4; vec4 event1Shape; vec4 event1Bounds;
    vec4 event2Head; vec4 event2Colour; vec4 event2Tail01; vec4 event2Tail23;
    vec2 event2Tail4; vec4 event2Shape; vec4 event2Bounds;
    vec4 snRemnant; vec4 snTone; vec4 snShell; vec4 snExtra;
    vec4 snBody; vec4 snHot; vec4 snWisp; vec4 snDust; vec4 snJet;
    vec4 stormHead; vec4 stormShape; vec4 stormColour; vec4 stormSpan;
    vec4 event0Burn; vec4 event1Burn; vec4 event2Burn;
    vec4 meteorTone; vec4 stormTone; vec4 stormBurn; vec4 stormTrain; vec4 stormWind;
    float qt_Opacity;
} ubuf;

${kernels}

vec3 encodeDisplay(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 decodeDisplay(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void main() {
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    vec3 events = eventSlot(pixel, ubuf.event0Head, ubuf.event0Colour, ubuf.event0Tail01, ubuf.event0Tail23, ubuf.event0Tail4, ubuf.event0Shape, ubuf.event0Bounds, ubuf.event0Burn, ubuf.meteorTone);
    fragColor = vec4(clamp(encodeDisplay(decodeDisplay(events)), 0.0, 1.0), 1.0);
}
`;
}

function uniformText(width, height, s) {
    const lines = ["resolution " + width + " " + height, "qt_Opacity 1",
        "stormShape 1 0 0 0", "stormHead 0 0 0 0", "stormTrain 0 0 0 0"];
    const v = (n, a) => lines.push("event0" + n + " " + a.map(x => x.toFixed(6)).join(" "));
    v("Head", s.head); v("Colour", s.colour); v("Tail01", s.tail01);
    v("Tail23", s.tail23); v("Tail4", s.tail4); v("Shape", s.shape);
    v("Bounds", s.bounds); v("Burn", s.burn);
    return lines.join("\n") + "\n";
}

// ---------------------------------------------------------------- measuring
const FLOOR = 2.0 / 255.0;
const DECODE = new Float32Array(1025);
for (let i = 0; i <= 1024; ++i) {
    const c = i / 1024;
    DECODE[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}
const lin = c => DECODE[Math.max(0, Math.min(1024, Math.round(c * 1024)))];

function read(path, w, h) {
    const b = readFileSync(path);
    return new Float32Array(b.buffer, b.byteOffset, w * h * 4);
}
function sample(f, w, h, x, y) {
    const xi = Math.floor(x), yi = Math.floor(y);
    if (xi < 0 || yi < 0 || xi >= w - 1 || yi >= h - 1) return 0;
    const fx = x - xi, fy = y - yi;
    let l = 0;
    for (let c = 0; c < 3; ++c) {
        const i00 = (yi * w + xi) * 4 + c;
        l += lin(f[i00]) * (1 - fx) * (1 - fy) + lin(f[i00 + 4]) * fx * (1 - fy)
            + lin(f[((yi + 1) * w + xi) * 4 + c]) * (1 - fx) * fy
            + lin(f[((yi + 1) * w + xi + 1) * 4 + c]) * fx * fy;
    }
    return l;
}
// The transverse ridge at a distance `t` along a direction from the head.
function ridgeAt(f, w, h, hx, hy, dx, dy, t, reach) {
    let best = 0;
    const N = Math.max(12, Math.ceil(reach));
    for (let i = -N; i <= N; ++i) {
        const s = (i / N) * reach;
        const v = sample(f, w, h, hx + dx * t - dy * s, hy + dy * t + dx * s);
        if (v > best) best = v;
    }
    return best;
}
// How far a tail actually reaches, measured: walk out until the ridge has been
// under the visibility floor for a run of samples.
function tailReach(f, w, h, hx, hy, dx, dy, limit, reach) {
    const step = Math.max(2, limit / 160);
    let last = 0, misses = 0;
    for (let t = step; t <= limit * 1.4; t += step) {
        const r = ridgeAt(f, w, h, hx, hy, dx, dy, t, reach * (0.35 + 0.9 * t / Math.max(1, limit)));
        if (r >= FLOOR) { last = t; misses = 0; } else if (++misses > 6) break;
    }
    return last;
}

function measure(path, w, h, s) {
    const f = read(path, w, h);
    let litPx = 0, flux = 0, peak = 0;
    for (let i = 0, n = w * h; i < n; ++i) {
        const o = i * 4;
        const m = Math.max(f[o], Math.max(f[o + 1], f[o + 2]));
        if (m >= FLOOR) { litPx++; flux += lin(f[o]) + lin(f[o + 1]) + lin(f[o + 2]); }
        if (m > peak) peak = m;
    }
    const hx = s.head[0], hy = s.head[1];
    // The coma's measured size: the radius holding half the light inside three
    // published coma sigmas, which is insensitive to the tails crossing it.
    const R = Math.max(8, 3.2 * s.tail4[1]);
    const bins = new Float64Array(64);
    for (let y = Math.max(0, Math.floor(hy - R)); y <= Math.min(h - 1, Math.ceil(hy + R)); ++y)
        for (let x = Math.max(0, Math.floor(hx - R)); x <= Math.min(w - 1, Math.ceil(hx + R)); ++x) {
            const d = Math.hypot(x - hx, y - hy);
            if (d > R) continue;
            const o = (y * w + x) * 4;
            bins[Math.min(63, Math.floor(64 * d / R))] += lin(f[o]) + lin(f[o + 1]) + lin(f[o + 2]);
        }
    let total = 0;
    for (let i = 0; i < 64; ++i) total += bins[i];
    let half = 0, comaR = 0;
    for (let i = 0; i < 64; ++i) { half += bins[i]; if (half >= 0.5 * total) { comaR = (i + 0.5) * R / 64; break; } }
    const ionLen = s.shape[0] > 0 ? tailReach(f, w, h, hx, hy, s.tail01[0], s.tail01[1], Math.max(8, s.tail01[2]), Math.max(4, s.tail01[3] * 3)) : 0;
    const dustLen = s.shape[1] > 0 ? tailReach(f, w, h, hx, hy, s.tail23[0], s.tail23[1], Math.max(8, s.tail23[2]), Math.max(6, s.tail23[3] * 4)) : 0;
    // The along-axis ridge profile of the DUST tail, for the synchrone shift.
    // Sampled from 0.12 of the tail out, because the coma sits on the base of
    // it and one sample of a nucleus outweighs the whole band pattern in any
    // correlation that includes it. Measured: with the base in, the peak sat
    // at lag 0 with a score 20x every other lag.
    const prof = [];
    if (dustLen > 20) {
        const nrm = Math.max(6, s.tail23[3] * 4);
        for (let i = 0; i < 96; ++i) {
            const uu = 0.12 + 0.88 * (i + 0.5) / 96;
            prof.push(ridgeAt(f, w, h, hx, hy, s.tail23[0], s.tail23[1], uu * dustLen, nrm * (0.35 + 0.9 * uu)));
        }
    }
    return {
        litPx, flux: Number(flux.toFixed(3)), peak255: Number((peak * 255).toFixed(1)),
        comaR: Number(comaR.toFixed(2)), ionLen: Number(ionLen.toFixed(1)), dustLen: Number(dustLen.toFixed(1)),
        prof: prof.map(x => Number(x.toFixed(6)))
    };
}

// Cross-correlate two along-axis profiles; returns the shift in samples that
// maximises the correlation. Positive = the pattern moved AWAY from the head.
// DETRENDED first. The along-axis ridge is mostly the tail's own smooth
// falloff, and correlating that against itself peaks at zero lag whatever the
// pattern on top of it is doing -- which is how a moving synchrone measures as
// stationary. Subtracting a 13-sample moving average leaves the bands.
// RATIO detrending, not difference: the tail's brightness falls by more than
// an order of magnitude along its length, so a difference leaves the ripple
// near the head carrying all the weight and the bands further out carrying
// none. Dividing by the local mean equalises them, which is what makes the
// shift a measurement of the PATTERN rather than of the envelope.
function detrend(x, half) {
    const out = new Array(x.length);
    for (let i = 0; i < x.length; ++i) {
        let s = 0, n = 0;
        for (let j = Math.max(0, i - half); j <= Math.min(x.length - 1, i + half); ++j) { s += x[j]; n++; }
        const mean = s / n;
        out[i] = mean > 1e-9 ? x[i] / mean - 1 : 0;
    }
    return out;
}
function shift(a0, b0, maxLag) {
    if (!a0.length || a0.length !== b0.length) return null;
    const a = detrend(a0, 6), b = detrend(b0, 6);
    const mean = x => x.reduce((p, c) => p + c, 0) / x.length;
    const ma = mean(a), mb = mean(b);
    // -Infinity, not 0: with `best` starting at zero an all-negative
    // correlation silently returns lag 0, which reads as "the pattern did not
    // move" and is the most convincing way to fail this measurement.
    let best = -Infinity, bestLag = 0;
    for (let lag = -maxLag; lag <= maxLag; ++lag) {
        let s = 0, n = 0;
        for (let i = 0; i < a.length; ++i) {
            const j = i + lag;
            if (j < 0 || j >= a.length) continue;
            s += (a[i] - ma) * (b[j] - mb);
            n++;
        }
        if (n > a.length * 0.6) {
            s /= n;
            if (s > best) { best = s; bestLag = lag; }
        }
    }
    return bestLag;
}

function main() {
    const bhrender = process.argv[2], outDir = process.argv[3];
    const label = process.argv[4] || "v12", configPath = process.argv[5] || null;
    if (!bhrender || !outDir) { console.error("usage: comet-sheet.mjs BHRENDER OUTDIR [label] [config.json]"); process.exit(1); }
    mkdirSync(outDir, { recursive: true });
    const W = Number(process.env.SHEET_W) || 2880, H = Number(process.env.SHEET_H) || 1800;
    const AGES = Number(process.env.COMET_AGES) || 34;
    const family = process.env.COMET_FAMILY || "slow";
    const frag = join(outDir, "comet-preview.frag");
    writeFileSync(frag, previewShader());
    const document = rulesContext.validateDocument(configPath ? JSON.parse(readFileSync(configPath, "utf8")) : null);
    const h = makeHost(document, { width: W, height: H, screenSeed: 20260917, hole: false });
    h._state.clock = 0;
    const e = h.captureEvent(1, 3, 0, family);
    // Off the light source, so the anti-sunward tails are not degenerate --
    // the same placement events-sheet.mjs uses.
    const dx = Math.cos(e.angle), dy = Math.sin(e.angle);
    const cx = W * 0.30, cy = H * 0.34;
    e.p0 = [cx - dx * e.distance / 2, cy - dy * e.distance / 2];
    e.p1 = [cx, cy];
    e.p2 = [cx + dx * e.distance / 2, cy + dy * e.distance / 2];
    e.capture = false;
    h.cometFramePass(e);

    const frames = [];
    let rendered = 0;
    for (let a = 0; a < AGES; ++a) {
        const u = (a + 0.5) / AGES;
        // Two frames a second apart at each age, so the synchrone shift is a
        // measurement over a KNOWN interval and not over an age step.
        const pair = [];
        for (const dt of [0, 1]) {
            h._state.clock = e.start + u * e.duration + dt;
            const s = h.eventState(e, 0, false, 3);
            const name = `c${String(a).padStart(2, "0")}${dt ? "b" : "a"}`;
            const uni = join(outDir, name + ".uniforms");
            const raw = join(outDir, label + "-" + name + ".f32");
            writeFileSync(uni, uniformText(W, H, s));
            execFileSync(bhrender, [frag, String(W), String(H), uni, raw], { stdio: ["ignore", "ignore", "pipe"] });
            rendered++;
            const rec = measure(raw, W, H, s);
            const keep = dt === 0 && a % Math.max(1, Math.floor(AGES / 6)) === 0;
            if (!keep) { rmSync(raw, { force: true }); rmSync(uni, { force: true }); }
            else rec.raw = raw;
            pair.push(rec);
        }
        const lag = shift(pair[0].prof, pair[1].prof, 24);
        // THE PHASE, measured directly, which is what M10 actually claims.
        // Cross-correlation is ill-posed here on purpose: the dust tail now
        // carries THREE band families moving at three different speeds
        // (synchrones at 13u, the Sun-aligned striae at their own offset
        // angle, and the advected grain), so the composite does not rigidly
        // translate and a single lag is whichever family wins that frame --
        // measured, it jumped between -24 and +24 samples. Projecting the
        // profile onto cos(13u) and sin(13u) isolates the synchrone family
        // and returns its phase, and the design says that phase advances by
        // 2*pi/striaeDriftSec per second.
        const phaseOf = prof => {
            if (!prof.length) return null;
            let c = 0, sn = 0;
            for (let i = 0; i < prof.length; ++i) {
                const uu = 0.12 + 0.88 * (i + 0.5) / prof.length;
                c += prof[i] * Math.cos(13.0 * uu);
                sn += prof[i] * Math.sin(13.0 * uu);
            }
            return Math.atan2(sn, c);
        };
        const p0 = phaseOf(detrend(pair[0].prof, 6)), p1 = phaseOf(detrend(pair[1].prof, 6));
        let dPhase = null;
        if (p0 !== null && p1 !== null) {
            dPhase = p1 - p0;
            while (dPhase > Math.PI) dPhase -= 2 * Math.PI;
            while (dPhase < -Math.PI) dPhase += 2 * Math.PI;
        }
        frames.push(Object.assign(pair[0], {
            u: Number(u.toFixed(4)), age: Number((u * e.duration).toFixed(2)),
            head: [Math.round(h.eventState(e, 0, false, 3).head[0]), Math.round(h.eventState(e, 0, false, 3).head[1])],
            range: Number(h.cometRange(e, u).toFixed(1)),
            ratio: Number((h.cometRange(e, u) / e.rPeri).toFixed(3)),
            activity: Number(h.cometActivity(e, u).toFixed(4)),
            synchroneShift: lag === null ? null : lag,
            synchronePhase: p0 === null ? null : Number(p0.toFixed(4)),
            // The phase advance per second, and the same thing as a fraction
            // of the tail's length, which is the unit M10's bound is in.
            synchroneDPhase: dPhase === null ? null : Number(dPhase.toFixed(4)),
            synchroneRate: dPhase === null ? null : Number((dPhase / 13.0).toFixed(5)),
            prof: undefined
        }));
    }
    writeFileSync(join(outDir, label + "-comet-manifest.json"), JSON.stringify({
        width: W, height: H, label, family,
        comet: {
            duration: e.duration, distance: e.distance, rPeri: e.rPeri, rMax: e.rMax, periU: e.periU,
            coma: e.coma, ionLength: e.ionLength, dustLength: e.dustLength, striaeDriftSec: e.striaeDriftSec
        },
        frames
    }, null, 2));
    console.log(`rendered ${rendered} comet frames (${family}, ${e.duration.toFixed(1)} s, r ${e.rPeri.toFixed(0)}-${e.rMax.toFixed(0)} px) to ${outDir}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
