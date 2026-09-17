#!/usr/bin/env node
// How wide the detonation's bloom gets, and for how long.
//
//   node modules/background/tools/sn_bloom.mjs <share> <seconds> [config.json]
//
// Requirement A (v11) allows a hard core of 3-6 % of the short side and a bloom
// to about 10 % for no more than 0.4 s. "For how long" cannot be read off a
// contact sheet -- the sheet samples a dozen moments of a four-minute episode --
// so this sweeps supernovaState() itself at 120 Hz and solves the drawn profile
// for its own 64/255 contour at every step.
//
// The profile is the shader's, not a model of it: supernovaField draws the core
// as tail01.z * exp2(-0.7213475*r2/(sigma2+1/12)) * sigma2/(sigma2+1/12) and the
// halo as tail01.y * exp2(-0.7213475*r2/haloSigma^2), both times head.w, and
// exp2(-0.7213475 x) is exp(-x/2) to seven figures. Scanned rather than solved
// because the sum of two Gaussians has no closed-form contour.
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

const share = Number(process.argv[2] || 0.10);
const seconds = Number(process.argv[3] || 300);
const configPath = process.argv[4] || "";
const W = 2880, H = 1800, SHORT = Math.min(W, H);
const LEVEL = 64 / 255;      // the bright disc, the contour supernova_sheet.py calls `disc`
const CORE_LEVEL = 64 / 255;

const document = rulesContext.validateDocument(configPath ? JSON.parse(readFileSync(configPath, "utf8")) : null);
const h = makeHost(document, { width: W, height: H, screenSeed: 20260913 });
let e = null;
for (let i = 0; i < 60 && !e; ++i) e = h.captureRadial(8, i, 0);
if (!e) { console.error("no supernova captured"); process.exit(1); }
e.start = 0;
h._state.events[8] = e;

// The drawn value at radius r, in display units, from one published state.
function valueAt(s, r) {
    const peak = s.head[3], sigma = s.head[2];
    const variance = sigma * sigma + 0.0833333;
    const r2 = r * r;
    let v = s.tail01[2] * Math.exp(-0.5 * r2 / variance) * sigma * sigma / variance;
    if (s.tail01[1] > 0 && s.tail01[0] > 0) v += s.tail01[1] * Math.exp(-0.5 * r2 / (s.tail01[0] * s.tail01[0]));
    return peak * v;
}
// Largest radius at which the point source is still above `level`.
function contour(s, level) {
    if (valueAt(s, 0) < level) return 0;
    let lo = 0, hi = Math.max(8, 8 * Math.max(s.head[2], s.tail01[0]));
    if (valueAt(s, hi) > level) return hi;
    for (let i = 0; i < 40; ++i) {
        const mid = 0.5 * (lo + hi);
        if (valueAt(s, mid) > level) lo = mid; else hi = mid;
    }
    return lo;
}
// The core alone, with the halo suppressed: the "hard white core" of A.
function coreContour(s, level) {
    const only = { head: s.head, tail01: [0, 0, s.tail01[2], 0] };
    return contour(only, level);
}

const dt = 1 / 120;
let above = 0, peak = 0, peakAt = 0, corePeak = 0, coreAt = 0;
const trace = [];
for (let t = 0; t <= seconds; t += dt) {
    h._state.clock = t;
    const s = h.radialState(e);
    if (!s || s.head[3] <= 0) continue;
    const d = 2 * contour(s, LEVEL) / SHORT;
    const c = 2 * coreContour(s, CORE_LEVEL) / SHORT;
    if (d > share) above += dt;
    if (d > peak) { peak = d; peakAt = t; }
    if (c > corePeak) { corePeak = c; coreAt = t; }
    if (trace.length < 4000 && t < e.precursor + e.rise + e.hold + 6) trace.push([Number(t.toFixed(3)), Number(d.toFixed(4)), Number(c.toFixed(4))]);
}
console.log(JSON.stringify({
    share, seconds: Number(above.toFixed(3)),
    peak: Number(peak.toFixed(4)), peakAt: Number(peakAt.toFixed(3)),
    corePeak: Number(corePeak.toFixed(4)), corePeakAt: Number(coreAt.toFixed(3)),
    spans: { precursor: e.precursor, rise: e.rise, hold: e.hold, decay: e.decay },
    trace
}));
