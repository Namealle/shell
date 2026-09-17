#!/usr/bin/env node
// Renders a meteor storm offscreen, through the REAL kernels, at a set of ages
// across the rate hump, so the picture can be measured instead of described.
//
//   cc -O2 -o /tmp/bhrender modules/background/tools/bhrender.c -lEGL -lGL -lm
//   node modules/background/tools/storm-sheet.mjs /tmp/bhrender OUTDIR [label] [config.json]
//   SHEET_W=2880 SHEET_H=1800 node ...        # the tablet
//
// `meteorStorm`, `stormFireball`, `stormTrainSegment`, `stormHash`, `hash4` and
// `eventSlot` are lifted out of shaders/starfield.frag by name, so this is what
// the shell draws; the uniforms come from stormState()/stormFireballState() in
// Starfield.qml the same way. Feed the manifest to storm_sheet.py for the
// contact sheet and the per-frame measurements.
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
    // radialField dispatches style 6 to supernovaField, so the supernova's two
    // kernels come along even though a storm never lights one: the lifted
    // eventSlot -> radialField chain has to compile whole.
    const kernels = ["hash4", "tailSegment", "cometField", "snPolar", "supernovaField", "radialField", "stormHash", "stormTrainSegment", "stormFireball", "meteorStorm", "eventSlot"]
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
    // main() adds the storm into the far-field accumulator, which is display-
    // encoded before the sky decode; on a #000000 sky that is exactly this.
    vec3 sky = meteorStorm(pixel);
    vec3 events = eventSlot(pixel, ubuf.event0Head, ubuf.event0Colour, ubuf.event0Tail01, ubuf.event0Tail23, ubuf.event0Tail4, ubuf.event0Shape, ubuf.event0Bounds);
    events += eventSlot(pixel, ubuf.event1Head, ubuf.event1Colour, ubuf.event1Tail01, ubuf.event1Tail23, ubuf.event1Tail4, ubuf.event1Shape, ubuf.event1Bounds);
    events += eventSlot(pixel, ubuf.event2Head, ubuf.event2Colour, ubuf.event2Tail01, ubuf.event2Tail23, ubuf.event2Tail4, ubuf.event2Shape, ubuf.event2Bounds);
    fragColor = vec4(clamp(encodeDisplay(decodeDisplay(sky) + decodeDisplay(events)), 0.0, 1.0), 1.0);
}
`;
}

function uniformText(width, height, frame) {
    const lines = ["resolution " + width + " " + height, "qt_Opacity 1"];
    const v = (name, a) => lines.push(name + " " + a.map(x => x.toFixed(6)).join(" "));
    v("stormHead", frame.storm.head);
    v("stormShape", frame.storm.shape);
    v("stormColour", frame.storm.colour);
    v("stormSpan", frame.storm.span);
    frame.slots.forEach((s, i) => {
        v("event" + i + "Head", s.head);
        v("event" + i + "Colour", s.colour);
        v("event" + i + "Tail01", s.tail01);
        v("event" + i + "Tail23", s.tail23);
        v("event" + i + "Tail4", s.tail4);
        v("event" + i + "Shape", s.shape);
        v("event" + i + "Bounds", s.bounds);
    });
    return lines.join("\n") + "\n";
}

function main() {
    const bhrender = process.argv[2];
    const outDir = process.argv[3];
    const label = process.argv[4] || "v9";
    const configPath = process.argv[5] || null;
    if (!bhrender || !outDir) { console.error("usage: storm-sheet.mjs BHRENDER OUTDIR [label] [config.json]"); process.exit(1); }
    mkdirSync(outDir, { recursive: true });
    const W = Number(process.env.SHEET_W) || 1440, H = Number(process.env.SHEET_H) || 2560;
    const frag = join(outDir, "storm-preview.frag");
    writeFileSync(frag, previewShader());

    const document = rulesContext.validateDocument(configPath ? JSON.parse(readFileSync(configPath, "utf8")) : null);
    const h = makeHost(document, { width: W, height: H, screenSeed: 20260913, hole: false });
    h._state.clock = 0;
    h.pushEvent("storm", 0, null);
    h._state.clock = 0.001;
    h.publishEvents();
    const e = h._state.events[3];
    const span = e.duration + (e.offset || 0);
    // Across the hump, with five closely-spaced samples inside the plateau so
    // the on-screen count is a measurement and not one lucky frame.
    const ages = [0.04, 0.16, 0.28].map(x => x * e.duration)
        .concat([0, 1, 2, 3, 4].map(i => (e.ramp + 1 + i * 3.5)))
        .concat([0.78, 0.90, 0.98].map(x => x * e.duration))
        .concat(e.children.map(c => c.at + c.flight * 0.90))      // each terminal flash
        .concat(e.offset > 1 ? [e.duration + e.offset * 0.6] : [])
        .filter(x => x < span).sort((a, b) => a - b);

    const manifest = [];
    for (const age of ages) {
        h._state.clock = e.start + age;
        const storm = h.stormState() || h.stormOff();
        const slots = [];
        for (const c of e.children) {
            const slot = h.stormFireballState(e, c);
            if (slot && slots.length < 3) slots.push(slot);
        }
        while (slots.length < 3) slots.push({ head: [0, 0, 1, 0], colour: [0, 0, 0, 0], tail01: [0, 0, 0, 0], tail23: [0, 0, 0, 0], tail4: [0, 0], shape: [0, 0, 0, 0], bounds: [0, 0, 0, 0] });
        const name = "t" + Math.round(age).toString().padStart(3, "0");
        const u = join(outDir, name + ".uniforms");
        const raw = join(outDir, label + "-" + name + ".f32");
        writeFileSync(u, uniformText(W, H, { storm, slots }));
        execFileSync(bhrender, [frag, String(W), String(H), u, raw], { stdio: ["ignore", "ignore", "pipe"] });
        manifest.push({
            name, raw, age: Number(age.toFixed(2)),
            rate: Number(storm.head[3].toFixed(3)),
            phase: Number(storm.head[2].toFixed(1)),
            window: storm.span[0],
            radiant: [Math.round(storm.head[0]), Math.round(storm.head[1])],
            headSigma: Number(storm.shape[0].toFixed(2)),
            fireballs: slots.filter(s => s.head[3] > 0).length
        });
    }
    writeFileSync(join(outDir, label + "-storm-manifest.json"), JSON.stringify({
        width: W, height: H, label,
        storm: { duration: e.duration, ramp: e.ramp, peak: e.peakSec, decay: e.decay, rateMax: e.rateMax, rateFloor: e.rateFloor, total: h.stormPhase(e, e.duration), children: e.children.length, span },
        frames: manifest
    }, null, 2));
    console.log(`rendered ${manifest.length} storm frames to ${outDir} (${e.duration.toFixed(0)} s, ${h.stormPhase(e, e.duration).toFixed(0)} streaks, peak ${e.rateMax.toFixed(1)}/s)`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
