#!/usr/bin/env node
// Tests for the METEOR STORM half of the starfield (events.shower).
//   node modules/background/tools/test-storm.mjs
//   node modules/background/tools/test-storm.mjs --report   # phases, counts, px
//
// Like test-events.mjs, nothing here is a re-implementation: the scheduler and
// the storm functions are lifted verbatim out of Starfield.qml by makeHost(),
// and the configuration goes through services/ambient/rules.js unchanged.
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFileSync } from "fs";
import vm from "vm";
import { makeHost } from "./test-events.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const rulesContext = vm.createContext({ Math, JSON, isFinite, Number, Object, Array, console });
vm.runInContext(readFileSync(join(repo, "services", "ambient", "rules.js"), "utf8") + "\nthis.validateDocument = validateDocument;", rulesContext);
const validateDocument = rulesContext.validateDocument;

let passed = 0, failed = 0;
function check(name, ok, detail) {
    if (ok) { passed++; console.log("ok    " + name + (detail ? "   " + detail : "")); }
    else { failed++; console.log("FAIL  " + name + (detail ? "   " + detail : "")); }
}

const OUTPUTS = [
    { name: "DP-3 2160x3840 device", width: 2160, height: 3840 },
    { name: "HDMI-A-1 3440x1440 device", width: 3440, height: 1440 },
    { name: "tablet 2880x1800 device", width: 2880, height: 1800 }
];

function host(options, config) {
    return makeHost(validateDocument(config === undefined ? null : config), options || {});
}

// One storm, forced at t=0 through the same pushEvent the `fire` IPC uses.
function storm(h) {
    h._state.clock = 0;
    h.pushEvent("storm", 0, null);
    h._state.clock = 0.001;
    h.publishEvents();
    return h._state.events[3];
}

// ------------------------------------------------------------- the rate hump
{
    const h = host({ width: 2160, height: 3840, hole: false });
    const e = storm(h);
    check("a forced storm captures a storm episode", !!(e && e.radiantOffset && e.rateMax > 0),
        e ? `${e.duration.toFixed(1)} s, peak ${e.rateMax.toFixed(2)}/s` : "none");
    check("total duration is 60-150 s", e.duration >= 60 && e.duration <= 150, e.duration.toFixed(1) + " s");
    check("build-up is 20-40 s", e.ramp >= 20 && e.ramp <= 40, e.ramp.toFixed(1) + " s");
    check("decay is 30-60 s", e.decay >= 30 && e.decay <= 60, e.decay.toFixed(1) + " s");
    check("peak rate is several a second", e.rateMax >= 2.5 && e.rateMax <= 8, e.rateMax.toFixed(2) + "/s");

    // A hump, not a switch: one rise, one fall, and no step a frame could show.
    const dt = 1 / 30;
    let rises = 0, falls = 0, worstStep = 0, previous = h.stormRate(e, 0);
    let peakAt = 0, peak = 0;
    for (let t = dt; t <= e.duration; t += dt) {
        const r = h.stormRate(e, t);
        if (r > previous + 1e-9) rises++;
        if (r < previous - 1e-9) falls++;
        worstStep = Math.max(worstStep, Math.abs(r - previous));
        if (r > peak) { peak = r; peakAt = t; }
        previous = r;
    }
    check("the rate is a smooth hump, not a switch", worstStep <= 0.02 * e.rateMax,
        `worst frame step ${worstStep.toFixed(4)}/s = ${(100 * worstStep / e.rateMax).toFixed(2)} % of peak`);
    check("the hump rises then falls once", rises > 100 && falls > 100 && peakAt > e.ramp * 0.9 && peakAt < e.ramp + e.peakSec + 1,
        `peak at ${peakAt.toFixed(1)} s, ramp ends ${e.ramp.toFixed(1)} s`);
    check("it starts at the floor and ends there", Math.abs(h.stormRate(e, 0.02) - e.rateFloor) < 0.02 && Math.abs(h.stormRate(e, e.duration - 0.02) - e.rateFloor) < 0.02,
        `floor ${e.rateFloor.toFixed(2)}/s`);

    // The phase is the integral. This is the contract the shader depends on:
    // its streak index advances at exactly `rate` per second only if it is.
    let numeric = 0, worstPhase = 0;
    for (let t = dt; t <= e.duration; t += dt) {
        numeric += h.stormRate(e, t - dt / 2) * dt;
        worstPhase = Math.max(worstPhase, Math.abs(numeric - h.stormPhase(e, t)));
    }
    check("phase is the rate's exact integral", worstPhase < 0.05,
        `worst |analytic - numeric| ${worstPhase.toFixed(4)} meteors over ${h.stormPhase(e, e.duration).toFixed(0)}`);
    let monotone = true, previousPhase = -1;
    for (let t = 0; t <= e.duration; t += dt) {
        const p = h.stormPhase(e, t);
        if (p < previousPhase - 1e-9) monotone = false;
        previousPhase = p;
    }
    check("phase never runs backwards", monotone);

    const total = h.stormPhase(e, e.duration);
    check("a storm is 120-400 meteors", total >= 120 && total <= 400, total.toFixed(0) + " streaks");
}

// --------------------------------------------------------- counts and window
{
    const h = host({ width: 2160, height: 3840, hole: false });
    const e = storm(h);
    // The kernel's own lifetimes: ordinary 0.55-1.60 s, earthgrazer 2.8-5.4 s.
    // Alive count is rate * mean life, and the window has to cover the longest.
    const frag = readFileSync(join(repo, "modules", "background", "shaders", "starfield.frag"), "utf8");
    check("the kernel's loop is hard-bounded", /for \(int j = 0; j < 48; \+\+j\)/.test(frag) && /if \(j >= window\) break;/.test(frag));
    let worstWindow = 0, peakAlive = 0, short = 0;
    for (let t = 0.5; t < e.duration; t += 0.5) {
        h._state.clock = t;
        h.publishEvents();
        const span = h.shader.stormSpan, head = h.shader.stormHead;
        if (head.w <= 0) continue;
        worstWindow = Math.max(worstWindow, span.x);
        peakAlive = Math.max(peakAlive, head.w * 1.30);        // rate * mean ordinary life
        if (span.x < Math.min(48, Math.ceil(head.w * 5.4))) short++;
    }
    check("the window always covers the longest streak alive", short === 0 && worstWindow > 0 && worstWindow <= 48,
        `peak window ${worstWindow} candidates, ${short} frames short`);
    check("5-10 ordinary streaks are in the air at the peak", peakAlive >= 4 && peakAlive <= 12,
        peakAlive.toFixed(1) + " concurrent");

    // First-order phase inversion: a streak's apparent clock runs at
    // 1 - age*r'/r. It must never run BACKWARDS anywhere a streak is likely to
    // exist, which is everywhere the rate is worth drawing.
    let worstClock = 1;
    for (let t = 0.05; t < e.duration; t += 0.05) {
        const r = h.stormRate(e, t);
        if (r < 0.30) continue;                                 // < one meteor per three seconds
        const slope = (h.stormRate(e, t + 0.01) - h.stormRate(e, t - 0.01)) / 0.02;
        worstClock = Math.min(worstClock, 1 - 1.6 * slope / r);
    }
    check("a streak's apparent clock never runs backwards", worstClock > 0.2,
        `slowest ${worstClock.toFixed(2)}x real time`);
}

// ------------------------------------------------------- radiant and geometry
for (const out of OUTPUTS) {
    const shortSide = Math.min(out.width, out.height);
    let inside = 0, offCentre = 0, onScreen = 0, keepOut = 0;
    const captures = 200;
    for (let seed = 0; seed < captures; ++seed) {
        const h = host({ width: out.width, height: out.height, screenSeed: seed * 37 + 1 });
        const e = storm(h);
        const place = h.stormRadiant(e);
        const centre = [out.width / 2, out.height / 2];
        const r = Math.hypot(place[0] - centre[0], place[1] - centre[1]);
        keepOut = 1.25 * h.holeReach();
        if (r < keepOut) inside++;
        if (r > 0.12 * shortSide) offCentre++;
        const margin = shortSide * 0.04;
        if (place[0] > margin && place[0] < out.width - margin && place[1] > margin && place[1] < out.height - margin) onScreen++;
    }
    check("no radiant lands on the drawn hole on " + out.name, inside === 0, `${inside} inside ${keepOut.toFixed(0)} px, ${captures} captures`);
    check("every radiant is off-centre on " + out.name, offCentre === captures, `${offCentre}/${captures} beyond 0.12 short sides`);
    check("every radiant is ON the buffer on " + out.name, onScreen === captures, `${onScreen}/${captures} inside a 0.04 short-side margin`);
}

// A shower meteor's apparent length is f*(tan(theta) - tan(theta - trail)):
// short beside the radiant, long far from it. Verified against the trail ANGLE
// the CPU publishes, which is what the kernel divides the projection by.
{
    const h = host({ width: 2160, height: 3840, hole: false });
    const e = storm(h);
    const focal = 2160;
    const project = theta => focal * Math.tan(theta);
    const trail = (e.trailLo + e.trailHi) / 2;
    const lengths = [0.08, 0.30, 0.60, 0.90].map(theta => project(theta) - project(Math.max(theta - trail, 0.004)));
    let growing = true;
    for (let i = 1; i < lengths.length; ++i)
        if (lengths[i] <= lengths[i - 1]) growing = false;
    check("streaks foreshorten toward the radiant", growing,
        lengths.map((l, i) => `${[5, 17, 34, 52][i]} deg: ${(100 * l / focal).toFixed(1)} %`).join(", "));
    const far = project(0.785) - project(0.785 - e.trailHi);
    const near = project(0.785) - project(0.785 - e.trailLo);
    check("far-from-radiant trails are 8-30 % of the short side",
        near / focal >= 0.08 && near / focal <= 0.31 && far / focal >= 0.08 && far / focal <= 0.31,
        `${(100 * near / focal).toFixed(1)} - ${(100 * far / focal).toFixed(1)} % at 45 deg`);
}

// Head sigma, per output, against the 3-6 px the kernel spreads it across.
for (const out of OUTPUTS) {
    const h = host({ width: out.width, height: out.height, hole: false });
    const e = storm(h);
    const lo = e.headSigma * 0.66, hi = e.headSigma * 1.33;
    const shortSide = Math.min(out.width, out.height);
    check("head sigma is 2-7 px on " + out.name, lo >= 1.8 && hi <= 7.5,
        `${lo.toFixed(2)} - ${hi.toFixed(2)} px  (${(100 * e.headSigma / shortSide).toFixed(3)} % of the short side)`);
}

// ---------------------------------------------------------------- fireballs
{
    const h = host({ width: 2880, height: 1800, hole: false });
    const e = storm(h);
    check("a storm carries 1-3 fireballs", e.children.length >= 1 && e.children.length <= 3, e.children.length + " fireballs");
    check("the fireball list is never empty by accident", e.children.every(c => c.flight > 0 && c.train > 0));
    const shortSide = 1800;
    let worstFlashStep = 0, sawFlash = false, sawTrain = 0, worstSlots = 0, peak = 0;
    const c = e.children[0];
    let previous = 0;
    for (let t = c.at - 1; t < c.at + c.flight + c.train + 1; t += 1 / 30) {
        h._state.clock = t;
        const slot = h.stormFireballState(e, c);
        const value = slot ? slot.head[3] * slot.shape[3] : 0;
        if (value > 0.2) sawFlash = true;
        if (slot) peak = Math.max(peak, slot.head[3]);
        worstFlashStep = Math.max(worstFlashStep, Math.abs(value - previous));
        previous = value;
        if (slot && t > c.at + c.flight + 1) sawTrain = t - (c.at + c.flight);
    }
    check("the fireball flashes", sawFlash, `flash sigma ${c.flashSigma.toFixed(0)} px = ${(100 * c.flashSigma * 5 / shortSide).toFixed(1)} % of the short side across`);
    check("the flash has no strobe edge", worstFlashStep <= 0.05 * peak,
        `worst frame step ${worstFlashStep.toFixed(4)} = ${(100 * worstFlashStep / peak).toFixed(1)} % of the slot peak, against the 5 % anti-strobe floor`);
    // v12 widened trainSec to [16, 44]: at [12, 26] no train ever reached
    // trainFoldSec, so none could loop, and a storm's residue was gone before
    // the next fireball arrived.
    check("the train outlives the head by 14-46 s", sawTrain >= 14 && sawTrain <= 46, sawTrain.toFixed(1) + " s");
    check("the fireball is 2x an ordinary storm head", c.sigma / e.headSigma >= 1.7 && c.sigma / e.headSigma <= 2.4,
        `${c.sigma.toFixed(2)} px against ${e.headSigma.toFixed(2)} px`);

    // v12: the train is a RAY WITH A WARP, not four points, so what is checked
    // here is the contract the shader reads -- the origin drifts bodily, the
    // shear amplitude grows and saturates, the fold is held at zero and then
    // opens late, and the three tone weights run green -> metal -> orange and
    // always sum to one. What the deformation LOOKS like is not assertable
    // from uniforms and is measured on rendered frames instead, by the ridge
    // walk in tools/meteor_curve.py (M4).
    const at = f => {
        h._state.clock = e.start + c.at + c.flight + f * c.train;
        return h.stormFireballState(e, c);
    };
    const early = at(0.01), mid = at(0.5), late = at(0.9);
    const drift = Math.hypot(late.tail01[0] - early.tail01[0], late.tail01[1] - early.tail01[1]);
    check("the train drifts bodily", drift > 0.005 * shortSide && drift < 0.09 * shortSide,
        `${drift.toFixed(0)} px = ${(100 * drift / shortSide).toFixed(1)} % of the short side, against the 6 % M5 bound`);
    check("the shear grows and saturates",
        early.tail23[1] < 0.25 * late.tail23[1] && mid.tail23[1] > 0.55 * late.tail23[1],
        `${early.tail23[1].toFixed(0)} -> ${mid.tail23[1].toFixed(0)} -> ${late.tail23[1].toFixed(0)} px, derived from ${(e.trainShearPx).toFixed(0)} px at full envelope`);
    check("the fold opens late, or not at all on a short train",
        early.tail23[2] === 0 && late.tail23[2] >= mid.tail23[2],
        `fold ${early.tail23[2].toFixed(3)} -> ${mid.tail23[2].toFixed(3)} -> ${late.tail23[2].toFixed(3)}, starts at ${e.trainFoldSec} s of a ${c.train.toFixed(0)} s train`);
    const weights = s => [s.burn[0], s.burn[1], s.burn[2]];
    const sums = [early, mid, late].map(s => weights(s).reduce((a, b) => a + b, 0));
    check("the train's three tones always sum to one", sums.every(x => Math.abs(x - 1) < 1e-6),
        sums.map(x => x.toFixed(4)).join(", "));
    check("the tone sequence is green -> metal -> orange",
        weights(early)[0] > weights(late)[0] && weights(late)[2] > weights(early)[2]
        && weights(late)[2] > weights(late)[0],
        `green ${weights(early)[0].toFixed(2)} -> ${weights(late)[0].toFixed(2)}, `
        + `FeO ${weights(early)[2].toFixed(2)} -> ${weights(late)[2].toFixed(2)}`);
    check("the train widens as it diffuses", late.shape[0] > 1.4 * early.shape[0],
        `widen ${early.shape[0].toFixed(2)} -> ${late.shape[0].toFixed(2)}`);
    // M13 is spatial, so the box has to hold the WARPED ray, not the straight
    // one. The warp's own worst case is analytic: the three shear terms sum to
    // 2.332 and the 0.4288 normalises them, so the across displacement tops
    // out at 1.156 x shear, and the fold moves the ends by 0.16 of the length.
    let contained = true, worst = Infinity;
    for (let f = 0; f <= 1.0001; f += 0.02) {
        const s2 = at(f);
        if (!s2) continue;
        const [ox, oy, dx2, dy2] = s2.tail01;
        const [len, shear, fold] = s2.tail23;
        const across = 1.156 * shear + 9 * s2.tail4[0] * s2.shape[0];
        for (const v of [-fold, 1 + fold]) {
            const px = ox + dx2 * len * v, py = oy + dy2 * len * v;
            for (const sgn of [-1, 1]) {
                const qx = px - dy2 * across * sgn, qy = py + dx2 * across * sgn;
                const m = Math.min(qx - s2.bounds[0], qy - s2.bounds[1], s2.bounds[2] - qx, s2.bounds[3] - qy);
                if (m < worst) worst = m;
                if (m < 0) contained = false;
            }
        }
    }
    check("the warped train stays inside its own bounds box", contained,
        `worst margin ${worst.toFixed(0)} px over the whole train life`);

    // Fireballs travel the SAME ray out of the radiant the streaks do.
    const place = h.stormRadiant(e);
    let radial = true, growingR = 0;
    for (let t = 0.05; t < c.flight; t += 0.1) {
        h._state.clock = e.start + c.at + t;
        const slot = h.stormFireballState(e, c);
        if (!slot) continue;
        const a = Math.atan2(slot.head[1] - place[1], slot.head[0] - place[0]);
        if (Math.abs(Math.atan2(Math.sin(a - c.angle), Math.cos(a - c.angle))) > 1e-6) radial = false;
        const r = Math.hypot(slot.head[0] - place[0], slot.head[1] - place[1]);
        if (r <= growingR) radial = false;
        growingR = r;
    }
    check("a fireball diverges from the radiant", radial, "on its own ray, monotonically outward");

    // A fireball is a slot, composited after the disk and not shadow-masked, so
    // its flash must not land on the drawn hole. 200 captures per output.
    for (const out of OUTPUTS) {
        let onHole = 0, offBuffer = 0, total = 0, keepOut = 0;
        for (let seed = 0; seed < 200; ++seed) {
            const g = host({ width: out.width, height: out.height, screenSeed: seed * 53 + 7 });
            const s2 = storm(g);
            const place = g.stormRadiant(s2);
            keepOut = 1.25 * g.holeReach();
            for (const child of s2.children) {
                const d = out.width * 0 + Math.min(out.width, out.height) * Math.tan(Math.min(child.theta0 + child.omega * child.flight, 1.35));
                const x = place[0] + Math.cos(child.angle) * d, y = place[1] + Math.sin(child.angle) * d;
                total++;
                // The whole ray, radiant to flash: the train covers all of it.
                const vx = x - place[0], vy = y - place[1], len = vx * vx + vy * vy;
                const t = len > 0 ? Math.max(0, Math.min(1, ((out.width / 2 - place[0]) * vx + (out.height / 2 - place[1]) * vy) / len)) : 0;
                if (Math.hypot(place[0] + vx * t - out.width / 2, place[1] + vy * t - out.height / 2) < keepOut) onHole++;
                if (x < 0 || y < 0 || x > out.width || y > out.height) offBuffer++;
            }
        }
        check("no fireball crosses the drawn hole on " + out.name, onHole === 0, `${onHole}/${total} inside ${keepOut.toFixed(0)} px`);
        check("every fireball flares on the buffer on " + out.name, offBuffer === 0, `${total - offBuffer}/${total} on screen`);
    }

    // And they take the transient heads, which the v8 shower used for plain
    // meteors and the storm no longer needs.
    for (let t = 0; t < e.duration + e.offset; t += 0.25) {
        h._state.clock = t;
        h.publishEvents();
        let used = 0;
        for (let i = 0; i < 3; ++i)
            if (h.shader["event" + i + "Colour"].w > 5.5) used++;
        worstSlots = Math.max(worstSlots, used);
    }
    check("fireballs reach the transient heads", worstSlots >= 1, worstSlots + " heads at once, style 7");
}

// ------------------------------------------------------------------ schedule
{
    const stats = [];
    for (let seed = 0; seed < 6; ++seed) {
        const h = host({ width: 2160, height: 3840, screenSeed: seed * 101 + 3 });
        let count = 0, last = -1;
        for (let t = 0; t < 6 * 3600; t += 5) {
            h._state.clock = t;
            h.publishEvents();
            const e = h._state.events[3];
            if (e && e.index !== last && e.start <= 6 * 3600) { count++; last = e.index; }
        }
        stats.push(count / 6);
    }
    const mean = stats.reduce((a, b) => a + b, 0) / stats.length;
    check("a storm every 25-60 min at rateScale 1", mean >= 1.0 && mean <= 2.4,
        `${mean.toFixed(2)}/h = one every ${(60 / mean).toFixed(0)} min over six hours x six seeds`);
}

// ------------------------------------------------------------------- config
{
    const document = validateDocument({ events: { shower: { durationSec: [30, 60], gain: 0.60, everyHours: [0.75, 2] } } });
    check("v8's three shower keys still validate", document.events.shower.durationSec[0] === 30 && document.events.shower.gain === 0.60 && document.events.shower.everyHours[1] === 2,
        JSON.stringify(document.events.shower.durationSec) + " gain " + document.events.shower.gain);
    const bad = validateDocument({ events: { shower: { peakRate: 99, headPx: [40, 80], earthgrazerShare: -2 } } });
    check("out-of-range storm keys clamp to their bounds", bad.events.shower.peakRate === 8 && bad.events.shower.headPx[1] === 12 && bad.events.shower.earthgrazerShare === 0,
        `peakRate ${bad.events.shower.peakRate}, headPx ${JSON.stringify(bad.events.shower.headPx)}`);
    const off = host({ width: 2160, height: 3840 }, { events: { shower: { enabled: false } } });
    off._state.clock = 1;
    off.publishEvents();
    check("a disabled storm publishes nothing", off.shader.stormShape.w === 0);
    const quiet = host({ width: 2160, height: 3840 }, { events: { rateScale: 0.5 } });
    const qe = storm(quiet);
    check("rateScale divides the storm's peak rate", Math.abs(qe.rateMax - 3) < 1e-9, qe.rateMax.toFixed(2) + "/s at rateScale 0.5");
}

// ------------------------------------------------------------------- the IPC
{
    const h = host({ width: 2160, height: 3840 });
    check("fire shower queues a storm", h.pushEvent("shower", 0, null) && h._state.pendingEvents.length === 1);
    const h2 = host({ width: 2160, height: 3840 });
    check("fire storm is the same family", h2.pushEvent("storm", 0, null) && h2._state.pendingEvents[0].kind === 3);
    check("fire meteors still works", h2.pushEvent("meteors", 0, null) && h2._state.pendingEvents[1].kind === 0);
    check("an unknown family is still rejected", h2.pushEvent("nope", 0, null) === false);
    h2._state.clock = 0.5;
    h2.publishEvents();
    h2._state.clock = 1.5;
    h2.publishEvents();
    check("a forced storm lands and draws", h2.shader.stormShape.w > 0 && h2.shader.stormHead.w > 0,
        `gain ${h2.shader.stormShape.w.toFixed(2)}, rate ${h2.shader.stormHead.w.toFixed(2)}/s`);
}

if (process.argv.includes("--report")) {
    for (const out of OUTPUTS) {
        const h = host({ width: out.width, height: out.height, hole: false });
        const e = storm(h);
        const shortSide = Math.min(out.width, out.height);
        const focal = shortSide;
        console.log("\n" + out.name);
        console.log(`  storm       ${e.duration.toFixed(0)} s = ramp ${e.ramp.toFixed(0)} + peak ${e.peakSec.toFixed(0)} + decay ${e.decay.toFixed(0)}, ${h.stormPhase(e, e.duration).toFixed(0)} streaks`);
        console.log(`  rate        ${e.rateFloor.toFixed(2)} -> ${e.rateMax.toFixed(2)} -> ${e.rateFloor.toFixed(2)} per second`);
        console.log(`  head sigma  ${(e.headSigma * 0.66).toFixed(2)} - ${(e.headSigma * 1.33).toFixed(2)} px`);
        for (const theta of [0.10, 0.35, 0.60, 0.90]) {
            const lo = focal * (Math.tan(theta) - Math.tan(Math.max(theta - e.trailLo, 0.004)));
            const hi = focal * (Math.tan(theta) - Math.tan(Math.max(theta - e.trailHi, 0.004)));
            console.log(`  trail ${(theta * 180 / Math.PI).toFixed(0).padStart(2)} deg  ${lo.toFixed(0).padStart(4)} - ${hi.toFixed(0).padStart(4)} px  =  ${(100 * lo / shortSide).toFixed(1)} - ${(100 * hi / shortSide).toFixed(1)} % of the short side`);
        }
        for (const c of e.children)
            console.log(`  fireball    at ${c.at.toFixed(0)} s, ${c.flight.toFixed(1)} s flight + ${c.train.toFixed(0)} s train, head ${c.sigma.toFixed(1)} px, flash ${(100 * c.flashSigma * 5 / shortSide).toFixed(1)} % across`);
    }
}

console.log(`\n${passed}/${passed + failed} checks passed`);
process.exit(failed ? 1 : 0);
