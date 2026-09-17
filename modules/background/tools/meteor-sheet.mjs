#!/usr/bin/env node
// Renders METEORS offscreen, through the REAL kernels, at a set of ages across
// each object's life, and measures what a person actually sees: where the light
// curve peaks, how the streak's width runs along it, what colour it is in each
// fifth of its path, how much of the light is in the head, and -- for a storm
// fireball -- what its persistent train does after the head has gone.
//
//   cc -O2 -o /tmp/bhrender modules/background/tools/bhrender.c -lEGL -lGL -lm
//   node modules/background/tools/meteor-sheet.mjs /tmp/bhrender OUTDIR [label] [config.json]
//   SHEET_W=2880 SHEET_H=1800 node ...            # a landscape buffer
//   METEOR_POP=12 METEOR_AGES=26 node ...         # the population sweep's size
//
// `tailSegment`, `stormFireball`, `stormTrainSegment`, `meteorStorm`, `hash4`
// and `eventSlot` are lifted out of shaders/starfield.frag by name, and the
// uniforms come from captureEvent()/eventState()/stormFireballState() in
// Starfield.qml, so this is what the shell draws and not a restatement of it.
//
// WHY THE MEASUREMENT IS HERE AND NOT ONLY IN PYTHON. The population sweep is
// a few hundred full-buffer frames; at 59 MB a frame that is gigabytes of
// float32 nobody reads twice. Every frame is measured the moment it is
// rendered and then deleted, except the handful listed in `keep`, which stay
// for meteor_curve.py's ridge extraction, its colour work against the
// reference photographs, and the contact sheets.
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

// The same lift storm-sheet.mjs uses: eventSlot dispatches every style, so the
// whole chain has to compile even though a meteor lights none of the others.
const KERNELS = ["hash4", "ablationStreak", "tailSegment", "cometField", "supernovaField", "radialField",
    "stormHash", "stormTrainRay", "stormTrainSegment", "stormFireball", "meteorStorm", "eventSlot"];

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
    vec3 sky = meteorStorm(pixel);
    vec3 events = eventSlot(pixel, ubuf.event0Head, ubuf.event0Colour, ubuf.event0Tail01, ubuf.event0Tail23, ubuf.event0Tail4, ubuf.event0Shape, ubuf.event0Bounds);
    events += eventSlot(pixel, ubuf.event1Head, ubuf.event1Colour, ubuf.event1Tail01, ubuf.event1Tail23, ubuf.event1Tail4, ubuf.event1Shape, ubuf.event1Bounds);
    events += eventSlot(pixel, ubuf.event2Head, ubuf.event2Colour, ubuf.event2Tail01, ubuf.event2Tail23, ubuf.event2Tail4, ubuf.event2Shape, ubuf.event2Bounds);
    fragColor = vec4(clamp(encodeDisplay(decodeDisplay(sky) + decodeDisplay(events)), 0.0, 1.0), 1.0);
}
`;
}

const OFF = { head: [0, 0, 1, 0], colour: [0, 0, 0, 0], tail01: [0, 0, 0, 0], tail23: [0, 0, 0, 0], tail4: [0, 0], shape: [0, 0, 0, 0], bounds: [0, 0, 0, 0] };
const STORM_OFF = { head: [0, 0, 0, 0], shape: [1, 0, 0, 0], colour: [1, 1, 1, 0], span: [0, 0, 0, 0] };

function uniformText(width, height, storm, slots) {
    const lines = ["resolution " + width + " " + height, "qt_Opacity 1"];
    const v = (name, a) => lines.push(name + " " + a.map(x => x.toFixed(6)).join(" "));
    v("stormHead", storm.head);
    v("stormShape", storm.shape);
    v("stormColour", storm.colour);
    v("stormSpan", storm.span);
    for (let i = 0; i < 3; ++i) {
        const s = slots[i] || OFF;
        v("event" + i + "Head", s.head);
        v("event" + i + "Colour", s.colour);
        v("event" + i + "Tail01", s.tail01);
        v("event" + i + "Tail23", s.tail23);
        v("event" + i + "Tail4", s.tail4);
        v("event" + i + "Shape", s.shape);
        v("event" + i + "Bounds", s.bounds);
    }
    return lines.join("\n") + "\n";
}

// ---------------------------------------------------------------- measuring
const FLOOR = 2.0 / 255.0;
function decode(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
// 256 entries is finer than the 8-bit frames the same numbers are quoted in.
const DECODE = new Float32Array(1025);
for (let i = 0; i <= 1024; ++i) DECODE[i] = decode(i / 1024);
function lin(c) { return DECODE[Math.max(0, Math.min(1024, Math.round(c * 1024)))]; }

function readFrame(path, w, h) {
    const buf = readFileSync(path);
    return new Float32Array(buf.buffer, buf.byteOffset, w * h * 4);
}

// Bilinear sample of the ENCODED frame, decoded to linear afterwards: the
// frames are what the screen shows, and every brightness quoted anywhere in
// this tree is quoted in those units.
function sampleLinear(f, w, h, x, y, out) {
    const xi = Math.floor(x), yi = Math.floor(y);
    if (xi < 0 || yi < 0 || xi >= w - 1 || yi >= h - 1) { out[0] = out[1] = out[2] = 0; return 0; }
    const fx = x - xi, fy = y - yi;
    let l = 0;
    for (let c = 0; c < 3; ++c) {
        const i00 = ((yi) * w + xi) * 4 + c, i10 = i00 + 4;
        const i01 = ((yi + 1) * w + xi) * 4 + c, i11 = i01 + 4;
        const v = lin(f[i00]) * (1 - fx) * (1 - fy) + lin(f[i10]) * fx * (1 - fy)
            + lin(f[i01]) * (1 - fx) * fy + lin(f[i11]) * fx * fy;
        out[c] = v;
        l += v;
    }
    return l;
}

// The polyline the slot published, as a list of points with cumulative length.
function polyline(slot) {
    const p = [[slot.tail01[0], slot.tail01[1]], [slot.tail01[2], slot.tail01[3]],
    [slot.tail23[0], slot.tail23[1]], [slot.tail23[2], slot.tail23[3]], [slot.tail4[0], slot.tail4[1]]];
    const count = Math.max(1, Math.round(slot.shape[2]));
    const pts = p.slice(0, count + 1);
    const cum = [0];
    for (let i = 1; i < pts.length; ++i)
        cum.push(cum[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
    return { pts, cum, total: cum[cum.length - 1] };
}
function alongPath(poly, u) {
    const want = u * poly.total;
    for (let i = 1; i < poly.pts.length; ++i) {
        if (want <= poly.cum[i] || i === poly.pts.length - 1) {
            const seg = Math.max(1e-6, poly.cum[i] - poly.cum[i - 1]);
            const t = Math.max(0, Math.min(1, (want - poly.cum[i - 1]) / seg));
            const a = poly.pts[i - 1], b = poly.pts[i];
            const dx = (b[0] - a[0]) / seg, dy = (b[1] - a[1]) / seg;
            return { x: a[0] + (b[0] - a[0]) * t, y: a[1] + (b[1] - a[1]) * t, dx, dy };
        }
    }
    return { x: poly.pts[0][0], y: poly.pts[0][1], dx: 1, dy: 0 };
}

// FWHM of the transverse profile at `u`, measured on the drawn pixels: step out
// from the centreline in both directions until the linear value falls under
// half its ridge maximum. Sub-pixel by bilinear sampling, so a 1 px streak
// still returns a number.
function transverse(f, w, h, poly, u, reach, absolute) {
    const at = alongPath(poly, u);
    const nx = -at.dy, ny = at.dx;
    const rgb = [0, 0, 0];
    const N = Math.max(24, Math.ceil(reach * 4));
    const prof = new Float64Array(2 * N + 1);
    for (let i = -N; i <= N; ++i) {
        const s = (i / N) * reach;
        prof[i + N] = sampleLinear(f, w, h, at.x + nx * s, at.y + ny * s, rgb);
    }
    let peak = 0, pk = N;
    for (let i = 0; i <= 2 * N; ++i) if (prof[i] > peak) { peak = prof[i]; pk = i; }
    if (peak <= 0) return { fwhm: 0, core: 0, peak: 0 };
    const step = reach / N;
    // TWO widths, because they answer two different questions and the shipped
    // kernel makes them disagree. `fwhm` is the half maximum of the profile
    // HERE -- how wide the streak looks at this point, which the broad
    // ionisation halo dominates once the core has faded. `core` is the width
    // above a fixed ABSOLUTE level (half the head end's ridge peak) -- how wide
    // the BRIGHT part is, which is the taper the eye reads as the shape of the
    // streak. A kernel can grow one while shrinking the other.
    const cross = level => {
        let lo = pk, hi = pk;
        if (prof[pk] <= level) return 0;
        while (lo > 0 && prof[lo] > level) lo--;
        while (hi < 2 * N && prof[hi] > level) hi++;
        const fl = lo < pk ? (prof[lo + 1] - level) / Math.max(1e-12, prof[lo + 1] - prof[lo]) : 0;
        const fh = hi > pk ? (prof[hi - 1] - level) / Math.max(1e-12, prof[hi - 1] - prof[hi]) : 0;
        return ((hi - fh) - (lo + fl)) * step;
    };
    return { fwhm: cross(peak * 0.5), core: absolute > 0 ? cross(absolute) : cross(peak * 0.5), peak };
}

// Five bins along the path plus one AHEAD of the head, each an integral of the
// transverse profile, so the colour reported is the colour of the light and not
// of one lucky pixel.
function colourBins(f, w, h, poly, reach, bins) {
    const out = [];
    const rgb = [0, 0, 0];
    for (let b = 0; b <= bins; ++b) {
        // b == bins is the LEAD bin: one head-reach in front of the head, along
        // the direction of travel. The second spectrum forms there.
        const lead = b === bins;
        const u = lead ? 0 : (b + 0.5) / bins;
        const at = alongPath(poly, u);
        const cx = lead ? at.x + at.dx * reach * 0.9 : at.x;
        const cy = lead ? at.y + at.dy * reach * 0.9 : at.y;
        const nx = -at.dy, ny = at.dx;
        let r = 0, g = 0, bl = 0;
        const N = Math.max(16, Math.ceil(reach * 3));
        for (let i = -N; i <= N; ++i) {
            const s = (i / N) * reach;
            sampleLinear(f, w, h, cx + nx * s, cy + ny * s, rgb);
            r += rgb[0]; g += rgb[1]; bl += rgb[2];
        }
        const sum = r + bl;
        out.push({
            u: Number(u.toFixed(3)), lead,
            r: r, g: g, b: bl,
            rb: sum > 1e-9 ? (r - bl) / sum : 0,
            green: (r + g + bl) > 1e-9 ? (g - (r + bl) / 2) / (r + g + bl) : 0,
            flux: r + g + bl
        });
    }
    return out;
}

function measure(path, w, h, slot, opts) {
    const f = readFrame(path, w, h);
    const rgb = [0, 0, 0];
    let litPx = 0, total = 0, peak = 0;
    for (let i = 0, n = w * h; i < n; ++i) {
        const o = i * 4;
        const m = Math.max(f[o], Math.max(f[o + 1], f[o + 2]));
        if (m >= FLOOR) { litPx++; total += lin(f[o]) + lin(f[o + 1]) + lin(f[o + 2]); }
        if (m > peak) peak = m;
    }
    const rec = { litPx, flux: Number(total.toFixed(4)), peak255: Number((peak * 255).toFixed(2)) };
    if (!slot || slot.head[3] <= 0) return rec;
    // The head: a disc on the PUBLISHED sigma, so the head/trail split has one
    // definition across every version of the kernel.
    const hx = slot.head[0], hy = slot.head[1], sigma = Math.max(0.6, slot.head[2]);
    const R = Math.max(4, (opts && opts.headRadii ? opts.headRadii : 5) * sigma);
    let headFlux = 0, headPeak = 0;
    const x0 = Math.max(0, Math.floor(hx - R)), x1 = Math.min(w - 1, Math.ceil(hx + R));
    const y0 = Math.max(0, Math.floor(hy - R)), y1 = Math.min(h - 1, Math.ceil(hy + R));
    for (let y = y0; y <= y1; ++y) for (let x = x0; x <= x1; ++x) {
        if ((x - hx) * (x - hx) + (y - hy) * (y - hy) > R * R) continue;
        const o = (y * w + x) * 4;
        headFlux += lin(f[o]) + lin(f[o + 1]) + lin(f[o + 2]);
        const m = Math.max(f[o], Math.max(f[o + 1], f[o + 2]));
        if (m > headPeak) headPeak = m;
    }
    // The saturated DISC: how many pixels around the head are at or above 250
    // of 255. The flare a camera records is this growing, not the value rising
    // past a clip nobody can see (V12 brief 1.4, 2.7).
    let sat = 0;
    const SR = Math.max(6, 24 * sigma);
    for (let y = Math.max(0, Math.floor(hy - SR)); y <= Math.min(h - 1, Math.ceil(hy + SR)); ++y)
        for (let x = Math.max(0, Math.floor(hx - SR)); x <= Math.min(w - 1, Math.ceil(hx + SR)); ++x) {
            const o = (y * w + x) * 4;
            if (Math.max(f[o], Math.max(f[o + 1], f[o + 2])) >= 250 / 255) sat++;
        }
    rec.headPeak255 = Number((headPeak * 255).toFixed(2));
    rec.headFlux = Number(headFlux.toFixed(4));
    rec.headShare = total > 1e-9 ? Number((headFlux / total).toFixed(4)) : 0;
    rec.satPx = sat;
    const poly = polyline(slot);
    if (poly.total > 4) {
        const reach = Math.max(6, 9 * sigma);
        const ref = transverse(f, w, h, poly, 0.1, reach, 0);
        const level = ref.peak * 0.5;
        const ws = [0.1, 0.4, 0.8].map(u => transverse(f, w, h, poly, u, reach, level));
        rec.width = ws.map(x => Number(x.fwhm.toFixed(3)));
        rec.core = ws.map(x => Number(x.core.toFixed(3)));
        rec.bins = colourBins(f, w, h, poly, reach, 5).map(b => ({
            u: b.u, lead: b.lead, rb: Number(b.rb.toFixed(4)), green: Number(b.green.toFixed(4)), flux: Number(b.flux.toFixed(4))
        }));
        rec.drawnPx = Number(poly.total.toFixed(1));
    }
    return rec;
}

// ---------------------------------------------------------------- scenarios
function main() {
    const bhrender = process.argv[2];
    const outDir = process.argv[3];
    const label = process.argv[4] || "v11";
    const configPath = process.argv[5] || null;
    if (!bhrender || !outDir) { console.error("usage: meteor-sheet.mjs BHRENDER OUTDIR [label] [config.json]"); process.exit(1); }
    mkdirSync(outDir, { recursive: true });
    const W = Number(process.env.SHEET_W) || 1440, H = Number(process.env.SHEET_H) || 2560;
    const POP = Number(process.env.METEOR_POP) || 12;
    const AGES = Number(process.env.METEOR_AGES) || 26;
    const frag = join(outDir, "meteor-preview.frag");
    writeFileSync(frag, previewShader());
    const document = rulesContext.validateDocument(configPath ? JSON.parse(readFileSync(configPath, "utf8")) : null);
    const host = () => makeHost(document, { width: W, height: H, screenSeed: 20260917, hole: false });

    let rendered = 0;
    const render = (name, storm, slots, keep) => {
        const u = join(outDir, name + ".uniforms");
        const raw = join(outDir, label + "-" + name + ".f32");
        writeFileSync(u, uniformText(W, H, storm || STORM_OFF, slots));
        execFileSync(bhrender, [frag, String(W), String(H), u, raw], { stdio: ["ignore", "ignore", "pipe"] });
        rendered++;
        const rec = measure(raw, W, H, slots[0], null);
        if (!keep) { rmSync(raw, { force: true }); rmSync(u, { force: true }); }
        else rec.raw = raw;
        return rec;
    };

    // ---- 1. the ordinary meteor population --------------------------------
    // Each meteor is captured through the shipped captureEvent and flown
    // through the shipped eventState, so the light curve measured here is the
    // one the shell draws.
    const meteors = [];
    for (let k = 0; k < POP; ++k) {
        const h = host();
        h._state.clock = 0;
        const family = h.chooseFamily(0, k, 0);
        const e = h.captureEvent(0, k, 0, family);
        const frames = [];
        let arc = 0, px = null, py = null;
        for (let a = 0; a < AGES; ++a) {
            const u = (a + 0.5) / AGES;
            h._state.clock = e.start + u * e.duration;
            const slot = h.eventState(e, 0, false, 3);
            const keep = k === 0 && (a % Math.max(1, Math.floor(AGES / 6)) === 0);
            const rec = render(`m${String(k).padStart(2, "0")}a${String(a).padStart(2, "0")}`, null, [slot], keep);
            if (px !== null) arc += Math.hypot(slot.head[0] - px, slot.head[1] - py);
            px = slot.head[0]; py = slot.head[1];
            frames.push(Object.assign(rec, {
                u: Number(u.toFixed(4)), age: Number((u * e.duration).toFixed(3)),
                gain: Number(slot.head[3].toFixed(5)), sigma: Number(slot.head[2].toFixed(3)),
                arc: Number(arc.toFixed(2)), head: [Math.round(slot.head[0]), Math.round(slot.head[1])],
                flash: Number(slot.shape[3].toFixed(4))
            }));
        }
        const span = Math.max(1e-6, arc);
        for (const fr of frames) fr.pathU = Number((fr.arc / span).toFixed(4));
        meteors.push({ index: k, family, fireball: !!e.fireball, duration: Number(e.duration.toFixed(3)), distance: Number(e.distance.toFixed(1)), tail: Number(e.tail.toFixed(1)), pointWidth: Number(e.pointWidth.toFixed(3)), arc: Number(arc.toFixed(1)), frames });
    }

    // ---- 2. the ordinary fireball -----------------------------------------
    const fireballs = [];
    for (let k = 0; k < 3; ++k) {
        const h = host();
        h._state.clock = 0;
        const e = h.captureEvent(0, 500 + k, 0, "straight");
        if (!e.fireball) { e.fireball = true; e.pointWidth *= 1.5; }
        const frames = [];
        let arc = 0, px = null, py = null;
        for (let a = 0; a < AGES; ++a) {
            const u = (a + 0.5) / AGES;
            h._state.clock = e.start + u * e.duration;
            const slot = h.eventState(e, 0, false, 3);
            const keep = k === 0 && (a % Math.max(1, Math.floor(AGES / 6)) === 0);
            const rec = render(`f${k}a${String(a).padStart(2, "0")}`, null, [slot], keep);
            if (px !== null) arc += Math.hypot(slot.head[0] - px, slot.head[1] - py);
            px = slot.head[0]; py = slot.head[1];
            frames.push(Object.assign(rec, { u: Number(u.toFixed(4)), age: Number((u * e.duration).toFixed(3)), gain: Number(slot.head[3].toFixed(5)), sigma: Number(slot.head[2].toFixed(3)), arc: Number(arc.toFixed(2)), flash: Number(slot.shape[3].toFixed(4)) }));
        }
        const span = Math.max(1e-6, arc);
        for (const fr of frames) fr.pathU = Number((fr.arc / span).toFixed(4));
        fireballs.push({ index: 500 + k, duration: Number(e.duration.toFixed(3)), frames });
    }

    // ---- 3. the storm fireball's persistent train --------------------------
    // The one object in the tree that is meant to OUTLIVE its head. Ages run
    // from the flight through the whole train life at the keyframes the
    // deformation literature uses (t, +2, +5, +10, +20, +30 s).
    const h = host();
    h._state.clock = 0;
    h.pushEvent("storm", 0, null);
    h._state.clock = 0.001;
    h.publishEvents();
    const storm = h._state.events[3];
    const child = storm.children && storm.children.length ? storm.children[0] : null;
    const trainFrames = [];
    let trainMeta = null;
    if (child) {
        trainMeta = { at: child.at, flight: child.flight, train: child.train, angle: child.angle };
        const ages = [0.25, 0.55, 0.90].map(x => x * child.flight)
            .concat([0.2, 1, 2, 5, 10, 15, 20, 25, 30, 40, 55].map(t => child.flight + t))
            .filter(a => a <= child.flight + child.train);
        for (const age of ages) {
            h._state.clock = storm.start + child.at + age;
            const slot = h.stormFireballState(storm, child);
            if (!slot) continue;
            const name = "tr" + String(Math.round(age * 10)).padStart(4, "0");
            // The storm is switched OFF in the train frames on purpose: the
            // ridge walk measures the train's own centreline, and an ordinary
            // streak crossing it would be measured as a kink in it.
            const rec = render(name, STORM_OFF, [slot], true);
            trainFrames.push(Object.assign(rec, {
                age: Number(age.toFixed(2)), trainAge: Number(Math.max(0, age - child.flight).toFixed(2)),
                head: [Math.round(slot.head[0]), Math.round(slot.head[1])],
                p0: [Math.round(slot.tail01[0]), Math.round(slot.tail01[1])],
                p3: [Math.round(slot.tail23[2]), Math.round(slot.tail23[3])],
                trainLen: Number(slot.shape[0].toFixed(1)), trainWidth: Number(slot.tail4[0].toFixed(2)),
                trainGain: Number((slot.head[3] * slot.tail4[1]).toFixed(5))
            }));
        }
    }

    // ---- 4. the storm at its peak ------------------------------------------
    const stormFrames = [];
    for (const age of [storm.ramp + 2, storm.ramp + storm.peakSec * 0.5, storm.ramp + storm.peakSec * 0.9]) {
        h._state.clock = storm.start + age;
        const st = h.stormState();
        if (!st) continue;
        const slots = [];
        for (const c of storm.children) {
            const slot = h.stormFireballState(storm, c);
            if (slot && slots.length < 3) slots.push(slot);
        }
        const name = "st" + String(Math.round(age)).padStart(3, "0");
        const rec = render(name, st, slots, true);
        stormFrames.push(Object.assign(rec, { age: Number(age.toFixed(1)), rate: Number(st.head[3].toFixed(2)), window: st.span[0], radiant: [Math.round(st.head[0]), Math.round(st.head[1])] }));
    }

    const manifest = {
        width: W, height: H, label,
        meteors, fireballs,
        train: { child: trainMeta, frames: trainFrames },
        storm: { duration: storm.duration, ramp: storm.ramp, peak: storm.peakSec, rateMax: storm.rateMax, children: storm.children.length, frames: stormFrames }
    };
    writeFileSync(join(outDir, label + "-meteor-manifest.json"), JSON.stringify(manifest, null, 2));
    console.log(`rendered ${rendered} frames to ${outDir}: ${meteors.length} meteors x ${AGES} ages, ${fireballs.length} fireballs, ${trainFrames.length} train, ${stormFrames.length} storm`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
