#!/usr/bin/env node
// Renders the v9 supernova's LIFE CYCLE offscreen, through the real kernels and
// the real CPU envelope, one frame per named phase moment.
//
//   cc -O2 -o /tmp/bhrender modules/background/tools/bhrender.c -lEGL -lGL -lm
//   node modules/background/tools/supernova-sheet.mjs /tmp/bhrender OUTDIR [label] [W H]
//   python3 modules/background/tools/supernova_sheet.py OUTDIR/LABEL-manifest.json OUT.png
//
// `supernovaField`, `snWeb`, `radialField` and `eventSlot` are lifted out of
// shaders/starfield.frag by name and the uniforms come from captureRadial /
// supernovaState in Starfield.qml, so this is what the shell draws rather than
// a re-implementation of it. The sky lift is applied exactly as main() applies
// it, on the #000000 sky the harness renders on.
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { execFileSync } from "child_process";
import vm from "vm";
import { makeHost } from "./test-events.mjs";
import { previewShader, uniformText } from "./events-sheet.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const rulesContext = vm.createContext({ Math, JSON, isFinite, Number, Object, Array, console });
vm.runInContext(readFileSync(join(repo, "services", "ambient", "rules.js"), "utf8") + "\nthis.validateDocument = validateDocument;", rulesContext);

// The moments worth a frame, as (label, age). Anything given as a function of
// the captured episode is resolved after capture.
function moments(e) {
    const flashEnd = e.precursor + e.rise + e.hold;
    const shellEnd = flashEnd + e.shellSpan;
    return [
        ["precursor-early", e.precursor * 0.25],
        ["precursor-late", e.precursor * 0.92],
        ["rise-half", e.precursor + e.rise * 0.5],
        ["flash-peak", e.precursor + e.rise + e.hold * 0.5],
        ["flash-plus-1s", flashEnd + 1],
        ["shell-05s", flashEnd + 5],
        ["shell-15s", flashEnd + 15],
        ["shell-quarter", flashEnd + e.shellSpan * 0.25],
        ["shell-half", flashEnd + e.shellSpan * 0.5],
        ["shell-end", shellEnd - 1],
        ["remnant-early", shellEnd + e.remnant * 0.10],
        ["remnant-mid", shellEnd + e.remnant * 0.45],
        ["remnant-late", shellEnd + e.remnant * 0.80],
        ["remnant-end", e.duration - 2]
    ];
}

function main() {
    const bhrender = process.argv[2];
    const outDir = process.argv[3];
    const label = process.argv[4] || "v9";
    const W = Number(process.argv[5]) || 2880, H = Number(process.argv[6]) || 1800;
    const configPath = process.argv[7] || null;
    if (!bhrender || !outDir) {
        console.error("usage: supernova-sheet.mjs BHRENDER OUTDIR [label] [W H] [config.json]");
        process.exit(1);
    }
    mkdirSync(outDir, { recursive: true });
    const document = rulesContext.validateDocument(configPath ? JSON.parse(readFileSync(configPath, "utf8")) : null);
    // hole:false is the regime he runs; placement is forced to the centre so
    // every frame of the sheet is the same object at the same place.
    const h = makeHost(document, { width: W, height: H, screenSeed: 20260913, hole: false });
    let e = null;
    for (let attempt = 0; attempt < 40 && !e; ++attempt) e = h.captureRadial(8, attempt, 0);
    if (!e) throw new Error("no supernova placement");
    e.x = W / 2;
    e.y = H / 2;
    const frag = join(outDir, "supernova-preview.frag");
    writeFileSync(frag, previewShader());
    // v11: supernovaRemnant() samples blackhole-noise.png on binding 2 through
    // nebulaTap, exactly as the live ShaderEffect binds it. This sheet used to
    // call bhrender with five arguments and no textures at all, which was fine
    // while the supernova was pure arithmetic and is a black remnant now.
    // bh_probe owns the PNG -> .raw conversion, so there is one copy of it.
    const shaders = join(repo, "modules", "background", "shaders");
    const t1 = join(outDir, "t1.raw"), t2 = join(outDir, "t2.raw");
    execFileSync("python3", ["-c",
        "import sys; sys.path.insert(0, sys.argv[1]); import bh_probe;" +
        " bh_probe._rawtex(sys.argv[2], sys.argv[3]); bh_probe._rawtex(sys.argv[4], sys.argv[5])",
        here, join(shaders, "blackhole-lut.png"), t1, join(shaders, "blackhole-noise.png"), t2],
        { stdio: ["ignore", "ignore", "pipe"] });
    const entries = [];
    for (const [name, age] of moments(e)) {
        h._state.clock = e.start + age;
        const state = h.radialState(e);
        const entry = { name, slot: 3, best: { state, gain: state.head[3], age } };
        const u = join(outDir, label + "-" + name + ".uniforms");
        const raw = join(outDir, label + "-" + name + ".f32");
        writeFileSync(u, uniformText(W, H, entry));
        execFileSync(bhrender, [frag, String(W), String(H), u, raw, t1, t2], { stdio: ["ignore", "ignore", "pipe"] });
        entries.push({
            name, raw, age: Number(age.toFixed(2)), gain: state.head[3],
            head: state.head, bounds: state.bounds,
            shellRadiusPx: state.shape[0], shellWidthPx: state.shape[1],
            // v11: snShell is the SHOCK now and the remnant has its own vector.
            shockWidthPx: state.extras ? state.extras.shell[2] : 0,
            remnantRadiusPx: state.extras ? state.extras.remnant[2] : 0,
            remnantGain: state.extras ? state.extras.remnant[3] : 0,
            hollowFrac: state.extras ? state.extras.body[0] : 0,
            colour: state.colour.slice(0, 3)
        });
    }
    const spans = {
        precursorSec: e.precursor, riseSec: e.rise, holdSec: e.hold, decaySec: e.decay,
        shellSec: e.shellSpan, remnantSec: e.remnant, durationSec: e.duration,
        flashRadiusPx: e.flash, shellRadiusPx: e.shell, hypernova: e.hyper,
        shortSidePx: Math.min(W, H)
    };
    writeFileSync(join(outDir, label + "-manifest.json"),
        JSON.stringify({ width: W, height: H, label, spans, entries }, null, 2));
    console.log("rendered " + entries.length + " phase frames to " + outDir);
    console.log(JSON.stringify(spans, null, 1));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
