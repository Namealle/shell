#!/usr/bin/env node
// Renders one peak frame per event family through the REAL shader kernels and
// the REAL CPU descriptors, offscreen, with no Quickshell and no GPU.
//
//   cc -O2 -o /tmp/bhrender modules/background/tools/bhrender.c -lEGL -lGL -lm
//   node modules/background/tools/events-sheet.mjs /tmp/bhrender OUTDIR [label]
//
// `tailSegment`, `radialField`, `cometField` and `eventSlot` are lifted out of
// shaders/starfield.frag by name, so the picture is what the shell draws and
// not a re-implementation. The event uniforms come from captureEvent/
// eventState and captureRadial/radialState in Starfield.qml the same way.
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { execFileSync } from "child_process";
import vm from "vm";
import { makeHost } from "./test-events.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const FRAG = join(repo, "modules", "background", "shaders", "starfield.frag");

const rulesContext = vm.createContext({ Math, JSON, isFinite, Number, Object, Array, console });
vm.runInContext(readFileSync(join(repo, "services", "ambient", "rules.js"), "utf8") + "\nthis.validateDocument = validateDocument;", rulesContext);

// ---------------------------------------------------------------- frag slice
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

function previewShader() {
    const src = readFileSync(FRAG, "utf8");
    const kernels = ["tailSegment", "cometField", "radialField", "eventSlot"]
        .filter(n => src.indexOf(n + "(") >= 0)
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
    vec4 event3Head; vec4 event3Colour; vec4 event3Tail01; vec4 event3Shape; vec4 event3Bounds;
    vec4 event4Head; vec4 event4Colour; vec4 event4Tail01; vec4 event4Shape; vec4 event4Bounds;
    vec4 event5Head; vec4 event5Colour; vec4 event5Tail01; vec4 event5Shape; vec4 event5Bounds;
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
    vec3 events = eventSlot(pixel, ubuf.event0Head, ubuf.event0Colour, ubuf.event0Tail01, ubuf.event0Tail23, ubuf.event0Tail4, ubuf.event0Shape, ubuf.event0Bounds);
    events += eventSlot(pixel, ubuf.event1Head, ubuf.event1Colour, ubuf.event1Tail01, ubuf.event1Tail23, ubuf.event1Tail4, ubuf.event1Shape, ubuf.event1Bounds);
    events += eventSlot(pixel, ubuf.event2Head, ubuf.event2Colour, ubuf.event2Tail01, ubuf.event2Tail23, ubuf.event2Tail4, ubuf.event2Shape, ubuf.event2Bounds);
    events += radialField(pixel, ubuf.event3Head, ubuf.event3Colour, ubuf.event3Tail01, ubuf.event3Shape, ubuf.event3Bounds);
    events += radialField(pixel, ubuf.event4Head, ubuf.event4Colour, ubuf.event4Tail01, ubuf.event4Shape, ubuf.event4Bounds);
    events += radialField(pixel, ubuf.event5Head, ubuf.event5Colour, ubuf.event5Tail01, ubuf.event5Shape, ubuf.event5Bounds);
    // main() treats the event sum as display-encoded before adding it to the
    // linear sky, which on a #000000 sky is exactly this.
    fragColor = vec4(clamp(encodeDisplay(decodeDisplay(events)), 0.0, 1.0), 1.0);
}
`;
}

// ---------------------------------------------------------------- descriptors
// A near-layer star, evaluated by the same formula stars() uses, is the
// yardstick every event is measured against.
export function starReference(optics) {
    const hotSigma = Math.min(2.5, optics * 0.62);
    const hot = hotSigma * hotSigma / (hotSigma * hotSigma + 0.0833333);
    return { sigma: hotSigma, peak: 1 - Math.exp(-3.2 * hot) };
}

function host(width, height, configPath) {
    const document = rulesContext.validateDocument(configPath ? JSON.parse(readFileSync(configPath, "utf8")) : null);
    return makeHost(document, { width, height, screenSeed: 20260913 });
}

// Sweep the CPU envelope and keep the frame with the largest published gain.
function peakFrame(h, e, produce) {
    let best = null;
    const steps = 600;
    for (let i = 0; i <= steps; ++i) {
        h._state.clock = e.start + e.duration * i / steps;
        const state = produce(e);
        const gain = state.head[3];
        if (!best || gain > best.gain) best = { gain, state, age: h._state.clock - e.start };
    }
    return best;
}

export function families(width, height, configPath) {
    const h = host(width, height, configPath);
    const w = width, hh = height;
    const out = [];
    const place = (e, cx, cy) => {
        const dx = Math.cos(e.angle), dy = Math.sin(e.angle);
        if (e.radial) { e.x = cx; e.y = cy; return e; }
        e.p0 = [cx - dx * e.distance / 2, cy - dy * e.distance / 2];
        e.p1 = [cx, cy];
        e.p2 = [cx + dx * e.distance / 2, cy + dy * e.distance / 2];
        e.capture = false;
        return e;
    };
    let id = 1;
    for (const family of ["straight", "curved", "skipping"]) {
        const e = place(h.captureEvent(0, id++, 0, family), w / 2, hh / 2);
        out.push({ name: "meteor-" + family, slot: 0, best: peakFrame(h, e, x => h.eventState(x, 0, false, 3)) });
    }
    // Off the light source, so the anti-sunward tails are not degenerate.
    for (const family of ["fast", "slow", "bent", "pulsating", "fragmenting", "spiral"]) {
        const e = place(h.captureEvent(1, id++, 0, family), w * 0.30, hh * 0.34);
        out.push({ name: "comet-" + family, slot: 0, best: peakFrame(h, e, x => h.eventState(x, 0, false, 3)) });
    }
    {
        const e = place(h.captureEvent(2, id++, 0, "satellite"), w / 2, hh / 2);
        out.push({ name: "satellite", slot: 0, best: peakFrame(h, e, x => h.eventState(x, 0, false, 3)) });
        const s = place(h.captureEvent(4, id++, 0, "slowWanderer"), w / 2, hh / 2);
        out.push({ name: "slowWanderer", slot: 0, best: peakFrame(h, s, x => h.eventState(x, 0, false, 3)) });
    }
    for (let kind = 5; kind <= 11; ++kind) {
        if (kind - 5 >= h.radialNames.length) break;
        const name = h.radialNames[kind - 5];
        let e = null;
        for (let attempt = 0; attempt < 40 && !e; ++attempt) e = h.captureRadial(kind, id + attempt, 0);
        id += 40;
        if (!e) continue;
        place(e, w / 2, hh / 2);
        out.push({ name: name, slot: 3, best: peakFrame(h, e, x => h.radialState(x)) });
    }
    return { h, out, optics: Math.max(1, Math.sqrt(w * hh / (1024 * 576))) };
}

// ---------------------------------------------------------------- rendering
function uniformText(width, height, entry) {
    const s = entry.best.state;
    const slot = entry.slot;
    const lines = ["resolution " + width + " " + height, "qt_Opacity 1"];
    const v = (name, a) => lines.push("event" + slot + name + " " + a.map(x => x.toFixed(6)).join(" "));
    v("Head", s.head);
    v("Colour", s.colour);
    v("Tail01", s.tail01);
    if (slot === 0) {
        v("Tail23", s.tail23);
        lines.push("event0Tail4 " + s.tail4.map(x => x.toFixed(6)).join(" "));
    }
    v("Shape", s.shape);
    v("Bounds", s.bounds);
    return lines.join("\n") + "\n";
}

function main() {
    const bhrender = process.argv[2];
    const outDir = process.argv[3];
    const label = process.argv[4] || "v8";
    const configPath = process.argv[5] || null;
    if (!bhrender || !outDir) { console.error("usage: events-sheet.mjs BHRENDER OUTDIR [label] [config.json]"); process.exit(1); }
    mkdirSync(outDir, { recursive: true });
    const W = Number(process.env.SHEET_W) || 1440, H = Number(process.env.SHEET_H) || 2560;
    const frag = join(outDir, "events-preview.frag");
    writeFileSync(frag, previewShader());
    const { out, optics } = families(W, H, configPath);
    const star = starReference(optics);
    const manifest = [];
    for (const entry of out) {
        const u = join(outDir, entry.name + ".uniforms");
        const raw = join(outDir, label + "-" + entry.name + ".f32");
        writeFileSync(u, uniformText(W, H, entry));
        execFileSync(bhrender, [frag, String(W), String(H), u, raw], { stdio: ["ignore", "ignore", "pipe"] });
        manifest.push({ name: entry.name, raw, gain: entry.best.gain, age: entry.best.age, head: entry.best.state.head, bounds: entry.best.state.bounds });
    }
    writeFileSync(join(outDir, label + "-manifest.json"), JSON.stringify({ width: W, height: H, optics, star, label, entries: manifest }, null, 2));
    console.log("rendered " + manifest.length + " families to " + outDir + " (star reference: sigma " + star.sigma.toFixed(2) + " px, peak " + star.peak.toFixed(3) + ")");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
