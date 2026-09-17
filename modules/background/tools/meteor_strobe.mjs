#!/usr/bin/env node
// The anti-strobe report for every v12 meteor envelope, and the M13 spatial
// bound that replaces the temporal one for a meteor.
//
//   node modules/background/tools/meteor_strobe.mjs [count] [config.json]
//
// WHY A METEOR IS NOT BOUND BY THE TEMPORAL RULE. The validator's floors
// (RISE_FLOOR 0.8 s, BURST_RISE_FLOOR 0.35 s) are the anti-strobe contract for
// the RADIAL phenomena, and they are right for those: a nova is a fixed point
// of light that gets brighter, so a fast rise is a pixel blinking. A meteor's
// light is carried by a MOVING object -- no pixel is lit for longer than the
// head's crossing time -- so the eye reads travel, not a blink. The shipped
// 0.7 s meteor completed its entire rise in 1.9 frames and he has never once
// complained about one; the thing he did complain about was a supernova
// lifting the WHOLE SCREEN (ledger 2286), which is a spatial fault.
//
// So this prints two things, and the second is the one that matters:
//   1. the temporal number anyway, honestly, per envelope: the largest step
//      between two 30 fps frames as a fraction of that envelope's own peak
//   2. the SPATIAL bound: for every published state, the furthest any drawn
//      component reaches from the head, against the bounds box the CPU
//      published. Outside that box eventSlot returns before it reads anything,
//      so a pixel there is bit-for-bit what it would be with no meteor at all
//      -- which is the M13 guarantee, and it has to hold at the flare's peak.
//
// The envelopes are the shipped ones: eventState() is lifted verbatim.
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFileSync } from "fs";
import vm from "vm";
import { makeHost } from "./test-events.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const rulesContext = vm.createContext({ Math, JSON, isFinite, Number, Object, Array, console });
vm.runInContext(readFileSync(join(repo, "services", "ambient", "rules.js"), "utf8")
    + "\nthis.validateDocument = validateDocument;", rulesContext);

const count = Number(process.argv[2] || 40);
const configPath = process.argv[3] || "";
const W = 1440, H = 2560;
const document = rulesContext.validateDocument(configPath ? JSON.parse(readFileSync(configPath, "utf8")) : null);

// The shader's own reach, per kernel, so "how far does this draw" is read off
// the same constants the fragment shader uses and not guessed.
//   eventSlot style 0: head extent    head.z * (7 + 26 * glare)
//   ablationStreak:    trail support  head.z * 34, about every polyline point
const HEAD_EXTENT = (sigma, glare) => sigma * (7.0 + 26.0 * glare);
const TRAIL_SUPPORT = sigma => sigma * 34.0;

function report() {
    const out = { count, width: W, height: H, meteors: [] };
    let worstStep = 0, worstStepAt = null, worstMargin = Infinity, worstMarginAt = null;
    for (let k = 0; k < count; ++k) {
        const h = makeHost(document, { width: W, height: H, screenSeed: 20260917, hole: false });
        h._state.clock = 0;
        const family = h.chooseFamily(0, k, 0);
        const e = h.captureEvent(0, k, 0, family);
        const dt = 1 / 120;
        let peak = 0;
        const gains = [];
        for (let t = 0; t <= e.duration + 1e-9; t += dt) {
            h._state.clock = e.start + t;
            const s = h.eventState(e, 0, false, 3);
            const g = s && s.head ? s.head[3] : 0;
            gains.push(g);
            if (g > peak) peak = g;
        }
        // The step between two frames a 30 fps display actually shows, which is
        // every fourth sample of a 120 Hz sweep.
        let step = 0, stepAt = 0;
        for (let i = 4; i < gains.length; i += 4) {
            const d = Math.abs(gains[i] - gains[i - 4]);
            if (d > step) { step = d; stepAt = i * dt; }
        }
        const frac = peak > 0 ? step / peak : 0;
        // The spatial bound, swept over the same life.
        let margin = Infinity, marginAt = 0, reach = 0;
        for (let t = 0; t <= e.duration + 1e-9; t += 1 / 60) {
            h._state.clock = e.start + t;
            const s = h.eventState(e, 0, false, 3);
            if (!s || s.head[3] <= 0) continue;
            const sigma = s.head[2], glare = Math.max(0, Math.min(1, s.shape[3]));
            const pts = [[s.tail01[0], s.tail01[1]], [s.tail01[2], s.tail01[3]],
            [s.tail23[0], s.tail23[1]], [s.tail23[2], s.tail23[3]], [s.tail4[0], s.tail4[1]]];
            const n = Math.max(1, Math.round(s.shape[2])) + 1;
            const need = Math.max(HEAD_EXTENT(sigma, glare), TRAIL_SUPPORT(sigma));
            for (let i = 0; i < n; ++i) {
                const m = Math.min(pts[i][0] - need - s.bounds[0], pts[i][1] - need - s.bounds[1],
                    s.bounds[2] - need - pts[i][0], s.bounds[3] - need - pts[i][1]);
                if (m < margin) { margin = m; marginAt = t; }
            }
            reach = Math.max(reach, need);
        }
        const row = {
            index: k, family, duration: Number(e.duration.toFixed(3)),
            fireball: !!e.fireball, flares: (e.flares || []).map(f => [Number(f[0].toFixed(3)), Number(f[1].toFixed(2))]),
            flareSec: e.flareSec, doublePeak: !!e.doublePeak,
            peakGain: Number(peak.toFixed(4)),
            stepFrac: Number(frac.toFixed(4)), stepAt: Number(stepAt.toFixed(3)),
            reachPx: Number(reach.toFixed(1)), boundsMarginPx: Number(margin.toFixed(1)), marginAt: Number(marginAt.toFixed(3))
        };
        out.meteors.push(row);
        if (frac > worstStep) { worstStep = frac; worstStepAt = row; }
        if (margin < worstMargin) { worstMargin = margin; worstMarginAt = row; }
    }
    out.worstTemporalStep = Number(worstStep.toFixed(4));
    out.worstTemporalIndex = worstStepAt ? worstStepAt.index : null;
    out.worstBoundsMarginPx = Number(worstMargin.toFixed(1));
    out.worstBoundsIndex = worstMarginAt ? worstMarginAt.index : null;
    out.spatiallyContained = worstMargin >= 0;
    return out;
}

const r = report();
const flared = r.meteors.filter(m => m.flares.length);
const dbl = r.meteors.filter(m => m.doublePeak);
console.error(`meteors ${r.count}   flaring ${flared.length} (${(100 * flared.length / r.count).toFixed(0)} %)   `
    + `double-peaked ${dbl.length} (${(100 * dbl.length / r.count).toFixed(0)} %)`);
const worstOf = rows => rows.length ? Math.max(...rows.map(m => m.stepFrac)) : 0;
r.worstStepNoFlare = Number(worstOf(r.meteors.filter(m => !m.flares.length)).toFixed(4));
r.worstStepFlare = Number(worstOf(flared).toFixed(4));
console.error(`worst 30 fps step ${(100 * r.worstTemporalStep).toFixed(1)} % of that meteor's own peak (index ${r.worstTemporalIndex})`);
console.error(`  no flare ${(100 * r.worstStepNoFlare).toFixed(1)} %   with a flare ${(100 * r.worstStepFlare).toFixed(1)} %   `
    + `(the shipped v11 envelope was 72 % on a 0.7 s meteor)`);
console.error(`EXEMPT from the temporal floors by design -- see the header. The binding rule is spatial:`);
console.error(`every drawn component inside its own published bounds box, worst margin `
    + `${r.worstBoundsMarginPx} px (index ${r.worstBoundsIndex}) -> ${r.spatiallyContained ? "CONTAINED" : "ESCAPES"}`);
console.log(JSON.stringify(r));
