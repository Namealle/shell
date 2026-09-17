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
    // `void` is in the list since v12: snCurl returns its two flow fields
    // through `out` parameters, because one scalar potential per channel is
    // two fields from the same three taps and returning a struct would cost a
    // type the lifted slice would also have to carry.
    const re = new RegExp("^(?:void|float|vec2|vec3|vec4)\\s+" + name + "\\s*\\(", "m");
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

export function previewShader() {
    const src = readFileSync(FRAG, "utf8");
    // eventSlot dispatches style 6 (through radialField) and style 7, so both
    // v9 kernels and their helpers come along or the lifted slice will not
    // compile. meteorStorm and nebulaField are here so ONE sheet can carry the
    // whole v9 catalogue -- every family, the storm and the passage -- through
    // one shader in main()'s own composite order. The filter keeps this list
    // valid against an older frag.
    const kernels = ["hash4", "lightCurve", "naProfile", "ablationStreak", "tailSegment", "cometField", "supernovaField", "radialField",
        "stormHash", "trainPoint", "stormTrainRay", "stormTrainSegment", "stormFireball", "meteorStorm", "nebulaTap", "nebulaStar",
        "nebulaField", "snPop", "snCurl", "snSlice", "supernovaRemnant", "eventSlot"]
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
    vec4 snRemnant; vec4 snTone; vec4 snShell; vec4 snExtra;
    vec4 snBody; vec4 snHot; vec4 snWisp; vec4 snDust; vec4 snJet;
    vec4 snPop0; vec4 snPop1; vec4 snPop2; vec4 snPop3; vec4 snPop4; vec4 snPop5;
    vec4 snGrain; vec4 snFlow; vec4 snTurn; vec4 snTurn2;
    vec4 stormHead; vec4 stormShape; vec4 stormColour; vec4 stormSpan;
    vec4 nebulaHead; vec4 nebulaShape; vec4 nebulaTone0; vec4 nebulaTone1;
    vec4 nebulaStars; vec4 nebulaStars2; vec4 nebulaBounds;
    vec4 event0Burn; vec4 event1Burn; vec4 event2Burn;
    vec4 meteorTone; vec4 stormTone; vec4 stormBurn; vec4 stormTrain; vec4 stormWind;
    float qt_Opacity;
} ubuf;
layout(binding = 2) uniform sampler2D bhNoise;

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
    // main()'s own v9 composite order on a #000000 sky: far dust (nothing here)
    // -> the cloud's extinction and emission -> the storm's streaks, which the
    // cloud must NOT dim -> the sky lift, which scales the sky the events are
    // then added to. The multiplicative half of the lift has nothing to scale
    // on a black sky, so what shows is the flat haze -- the term that has to
    // return to #000000.
    vec3 sky = vec3(0.0);
    vec4 nebula = nebulaField(pixel);
    sky = sky * (1.0 - nebula.a) + nebula.rgb;
    if (ubuf.stormShape.w > 0.0) sky += decodeDisplay(meteorStorm(pixel));
    // v11: the supernova's whole-sky lift used to be copied here from main().
    // It is gone from both (ledger 2286, "I don't like that my screen flashes"),
    // so there is nothing global left to copy. What took its vector IS a sky
    // layer, and it joins the sky exactly the way the nebula above does -- same
    // contract, same place in the order, so this is the shipped composite and
    // not a third hand copy of one.
    vec4 remnant = supernovaRemnant(pixel);
    sky = sky * (1.0 - remnant.a) + remnant.rgb;
    vec3 events = eventSlot(pixel, ubuf.event0Head, ubuf.event0Colour, ubuf.event0Tail01, ubuf.event0Tail23, ubuf.event0Tail4, ubuf.event0Shape, ubuf.event0Bounds, ubuf.event0Burn, ubuf.meteorTone);
    events += eventSlot(pixel, ubuf.event1Head, ubuf.event1Colour, ubuf.event1Tail01, ubuf.event1Tail23, ubuf.event1Tail4, ubuf.event1Shape, ubuf.event1Bounds, ubuf.event1Burn, ubuf.meteorTone);
    events += eventSlot(pixel, ubuf.event2Head, ubuf.event2Colour, ubuf.event2Tail01, ubuf.event2Tail23, ubuf.event2Tail4, ubuf.event2Shape, ubuf.event2Bounds, ubuf.event2Burn, ubuf.meteorTone);
    events += radialField(pixel, ubuf.event3Head, ubuf.event3Colour, ubuf.event3Tail01, ubuf.event3Shape, ubuf.event3Bounds);
    events += radialField(pixel, ubuf.event4Head, ubuf.event4Colour, ubuf.event4Tail01, ubuf.event4Shape, ubuf.event4Bounds);
    events += radialField(pixel, ubuf.event5Head, ubuf.event5Colour, ubuf.event5Tail01, ubuf.event5Shape, ubuf.event5Bounds);
    // main() treats the event sum as display-encoded before adding it to the
    // linear sky, which on a #000000 sky is exactly this.
    fragColor = vec4(clamp(encodeDisplay(sky + decodeDisplay(events)), 0.0, 1.0), 1.0);
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
    // v9's two block events. Neither is a slot, so both are rendered through
    // their own uniform block and land in the same catalogue: this is the one
    // sheet where every family the sky can show is beside every other.
    {
        // The storm at the top of its hump, with its fireballs on the slots.
        h._state.clock = 0;
        h.pushEvent("storm", 0, null);
        h._state.clock = 0.001;
        h.publishEvents();
        const e = h._state.events[3];
        if (e) {
            let best = null;
            for (let i = 0; i <= 240; ++i) {
                h._state.clock = e.start + e.duration * i / 240;
                const storm = h.stormState() || h.stormOff();
                const slots = [];
                for (const c of e.children) {
                    const slot = h.stormFireballState(e, c);
                    if (slot && slots.length < 3) slots.push(slot);
                }
                while (slots.length < 3) slots.push({ head: [0, 0, 1, 0], colour: [0, 0, 0, 0], tail01: [0, 0, 0, 0], tail23: [0, 0, 0, 0], tail4: [0, 0], shape: [0, 0, 0, 0], bounds: [0, 0, 0, 0] });
                // Rate first, fireballs as the tie-break: the busiest frame of
                // the hump is the honest "peak" for a shower.
                const score = storm.head[3] + slots.filter(x => x.head[3] > 0).length;
                if (!best || score > best.score)
                    best = { score, gain: storm.shape[3], state: storm, slots, age: h._state.clock - e.start };
            }
            out.push({ name: "storm", slot: 0, block: "storm", slots: best.slots, best: best });
        }
    }
    {
        // The passage at its densest, geometry advancing as advance() does.
        const e = h.captureNebula(3, 0);
        if (e) {
            e.geo = 0;
            h._state.nebula = e;
            const perSec = -h.nebulaDriftPerSec() / h.nebulaFlowRate();
            let best = null;
            for (let i = 0; i <= 240; ++i) {
                const t = e.duration * i / 240;
                h._state.clock = t;
                h._state.geo[0] = perSec * t;
                const state = h.nebulaState(e);
                if (!best || state.head[3] > best.gain) best = { gain: state.head[3], state, age: t };
            }
            out.push({ name: "nebula", slot: 0, block: "nebula", best: best });
        }
    }
    return { h, out, optics: Math.max(1, Math.sqrt(w * hh / (1024 * 576))) };
}

// ---------------------------------------------------------------- rendering
export function uniformText(width, height, entry) {
    const s = entry.best.state;
    const slot = entry.slot;
    const lines = ["resolution " + width + " " + height, "qt_Opacity 1"];
    // The storm and the passage are not slot events: they own their own block,
    // so they are written whole and nothing else in the file is touched.
    if (entry.block === "storm") {
        for (const [name, vec] of [["stormHead", s.head], ["stormShape", s.shape], ["stormColour", s.colour], ["stormSpan", s.span]])
            lines.push(name + " " + vec.map(y => y.toFixed(6)).join(" "));
        for (const [i, slotState] of (entry.slots || []).entries()) {
            const w = (name, a) => lines.push("event" + i + name + " " + a.map(x => x.toFixed(6)).join(" "));
            w("Head", slotState.head); w("Colour", slotState.colour); w("Tail01", slotState.tail01);
            w("Tail23", slotState.tail23);
            lines.push("event" + i + "Tail4 " + slotState.tail4.map(x => x.toFixed(6)).join(" "));
            w("Shape", slotState.shape); w("Bounds", slotState.bounds);
            w("Burn", slotState.burn || [0.52, 0, 0, 0]);
        }
        for (const [name, vec] of [["stormBurn", s.burn], ["stormTrain", s.train], ["stormWind", s.wind]])
            if (vec) lines.push(name + " " + vec.map(y => y.toFixed(6)).join(" "));
        lines.push("stormTone " + (entry.tone || [0, 0, 0, 4.5]).map(y => y.toFixed(6)).join(" "));
        return lines.join("\n") + "\n";
    }
    if (entry.block === "nebula") {
        for (const [name, vec] of [["nebulaHead", s.head], ["nebulaShape", s.shape], ["nebulaTone0", s.tone0],
            ["nebulaTone1", s.tone1], ["nebulaStars", s.stars], ["nebulaStars2", s.stars2], ["nebulaBounds", s.bounds]])
            lines.push(name + " " + vec.map(y => y.toFixed(6)).join(" "));
        return lines.join("\n") + "\n";
    }
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
    v("Burn", s.burn || [0.52, 0, 0, 0]);
    lines.push("meteorTone " + (entry.tone || [0, 0, 0, 4.5]).map(y => y.toFixed(6)).join(" "));
    // v9 supernova extras: four vectors beside the slot, zero for every other
    // family, so one uniforms file format covers the whole catalogue.
    const zero = [0, 0, 0, 0];
    const x = s.extras || { remnant: zero, tone: zero, shell: zero, extra: zero,
        body: zero, hot: zero, wisp: zero, dust: zero, jet: [1, 0, 0, 0],
        pop0: zero, pop1: zero, pop2: zero, pop3: zero, pop4: zero, pop5: zero,
        grain: zero, flow: zero, turn: zero, turn2: zero };
    for (const [name, vec] of [["snRemnant", x.remnant], ["snTone", x.tone], ["snShell", x.shell],
        ["snExtra", x.extra], ["snBody", x.body], ["snHot", x.hot], ["snWisp", x.wisp],
        ["snDust", x.dust], ["snJet", x.jet],
        ["snPop0", x.pop0], ["snPop1", x.pop1], ["snPop2", x.pop2],
        ["snPop3", x.pop3], ["snPop4", x.pop4], ["snPop5", x.pop5],
        ["snGrain", x.grain], ["snFlow", x.flow], ["snTurn", x.turn], ["snTurn2", x.turn2]])
        lines.push(name + " " + vec.map(y => y.toFixed(6)).join(" "));
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
    // The nebula samples blackhole-noise.png on binding 2, exactly as the live
    // ShaderEffect binds it. bh_probe owns the PNG -> .raw conversion, so there
    // is one copy of that and not a second one here.
    const shaders = join(repo, "modules", "background", "shaders");
    const t1 = join(outDir, "t1.raw"), t2 = join(outDir, "t2.raw");
    execFileSync("python3", ["-c",
        "import sys; sys.path.insert(0, sys.argv[1]); import bh_probe;" +
        " bh_probe._rawtex(sys.argv[2], sys.argv[3]); bh_probe._rawtex(sys.argv[4], sys.argv[5])",
        here, join(shaders, "blackhole-lut.png"), t1, join(shaders, "blackhole-noise.png"), t2],
        { stdio: ["ignore", "ignore", "pipe"] });
    const manifest = [];
    for (const entry of out) {
        const u = join(outDir, entry.name + ".uniforms");
        const raw = join(outDir, label + "-" + entry.name + ".f32");
        writeFileSync(u, uniformText(W, H, entry));
        execFileSync(bhrender, [frag, String(W), String(H), u, raw, t1, t2], { stdio: ["ignore", "ignore", "pipe"] });
        manifest.push({ name: entry.name, raw, gain: entry.best.gain, age: entry.best.age, head: entry.best.state.head, bounds: entry.best.state.bounds });
    }
    writeFileSync(join(outDir, label + "-manifest.json"), JSON.stringify({ width: W, height: H, optics, star, label, entries: manifest }, null, 2));
    console.log("rendered " + manifest.length + " families to " + outDir + " (star reference: sigma " + star.sigma.toFixed(2) + " px, peak " + star.peak.toFixed(3) + ")");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
