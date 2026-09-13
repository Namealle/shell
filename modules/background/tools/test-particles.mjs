#!/usr/bin/env node
// Node tests for the particle CPU half. Run from anywhere:
//   node modules/background/tools/test-particles.mjs
// The four particles/*.js modules are plain CommonJS under their QML guard, so
// they load here unchanged and run the same code the shell runs.
import { createRequire } from "module";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFileSync } from "fs";

const require = createRequire(import.meta.url);
const particles = join(dirname(fileURLToPath(import.meta.url)), "..", "particles");
const Physics = require(join(particles, "Physics.js"));
const Appearance = require(join(particles, "Appearance.js"));
const Binning = require(join(particles, "Binning.js"));
const Packing = require(join(particles, "Packing.js"));

const W = 2160, H = 3840, RH = 0.11 * 2160, DT = 1 / 30;
// Rh is the dynamical scale and the SHADOW radius; Rd is the disk's material
// rim. Boundaries pick one or the other by what they mean. With no disk
// geometry supplied, Rd is the v4 default disk: 2.783 Rh.
const RADII = Physics.visibleRadius(RH, undefined);
const SHADOW = RADII.shadow, RIM = RADII.disk;
let failures = 0, checks = 0;
function check(name, ok, detail) {
    ++checks;
    if (!ok) { ++failures; console.log("FAIL  " + name + (detail === undefined ? "" : "   " + detail)); }
    else console.log("ok    " + name + (detail === undefined ? "" : "   " + detail));
}

function birthInput() {
    return {colors: [], weights: [], mix: 0.32, params: {}, legacy: [0, 0, 0, 0.5], seed: 12345,
        archetypes: [0.82, 0.10, 0.04, 0.02, 0.015, 0.005]};
}
// One simulation, advanced and rendered exactly as Starfield.qml does.
function simulate(options) {
    const o = options || {};
    const input = birthInput();
    const pool = Physics.create(W, H, RH, o.seed === undefined ? 7 : o.seed, o.config || {},
        (p, i) => Appearance.birth(p, i, input), o.geometry);
    pool.absorb = o.absorb === undefined ? 1 : o.absorb;
    let items = null, bins = null;
    const visit = o.visit || (() => {});
    const warm = o.warmSec === undefined ? 60 : o.warmSec;
    const measure = o.measureSec === undefined ? 30 : o.measureSec;
    for (let f = 0; f < Math.round((warm + measure) / DT); ++f) {
        pool.absorb = o.absorb === undefined ? 1 : o.absorb;
        Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        items = Appearance.render(items, pool, {twinkle: 0.22});
        if (f * DT < warm) continue;
        bins = Binning.build(bins, items, W, H);
        visit(items, bins, pool, f);
    }
    return {pool, items, bins};
}
const S = Appearance.STRIDE;
const IX = 0, ICORE = 4, ISTREAK = 6, IFLAGS = 11, IID = 16, IGEN = 17, ISTRETCH = 20;
const radiusOf = (d, b) => Math.hypot(d[b] - W / 2, d[b + 1] - H / 2);

// ---------------------------------------------------------------- continuity
// The bug this replaced: a star crossing streak.bendRadiusRd had its exposure
// switched from 0.035 s to 0.26 s in one frame, and a first-come-first-served
// instance cap flipped stars in and out of that state every frame on top. Both
// showed up as a rendered streak length jumping several tens of pixels between
// consecutive frames. Nothing may jump now.
{
    let worstStreak = 0, worstStretch = 0, jumps = 0, samples = 0;
    const prev = new Map();
    simulate({visit: items => {
        const d = items.data;
        for (let j = 0; j < items.count; ++j) {
            const b = j * S, key = d[b + IID] + ":" + d[b + IGEN];
            const p = prev.get(key);
            if (p) {
                const ds = Math.abs(d[b + ISTREAK] - p.streak), dt = Math.abs(d[b + ISTRETCH] - p.stretch);
                if (ds > worstStreak) worstStreak = ds;
                if (dt > worstStretch) worstStretch = dt;
                if (ds > 5) ++jumps;
                ++samples;
            }
            prev.set(key, {streak: d[b + ISTREAK], stretch: d[b + ISTRETCH]});
        }
    }});
    check("no one-frame streak jump over 5 px", jumps === 0,
        `worst ${worstStreak.toFixed(2)} px over ${samples} frame pairs`);
    // A star at full gain and the shortest time constant moves at most
    // DT/(0.45+DT) = 6.9 % of the remaining gap per frame.
    check("stretch moves at most 7 % of its gap per frame", worstStretch <= 0.07 + 1e-9,
        `worst ${worstStretch.toFixed(4)}`);
    check("the ramp still takes many frames", worstStretch > 0 && worstStretch < 0.07);
}

// ---------------------------------------------------------- per-star variation
// Two stars at the same radius must not render the same shape. Birth freezes an
// onset scale, a gain and a rate per star, so a radius shell carries a spread.
{
    const shell = [];
    simulate({measureSec: 10, visit: items => {
        const d = items.data;
        for (let j = 0; j < items.count; ++j) {
            const b = j * S, r = radiusOf(d, b) / RIM;
            if (r > 0.50 && r < 0.60) shell.push(d[b + ISTRETCH]);
        }
    }});
    shell.sort((a, b) => a - b);
    const q = f => shell[Math.min(shell.length - 1, Math.floor(f * shell.length))];
    const spread = q(0.9) - q(0.1);
    check("stars in one radius shell carry a spread of deformation", shell.length > 200 && spread > 0.15,
        `n=${shell.length} p10=${q(0.1).toFixed(3)} p50=${q(0.5).toFixed(3)} p90=${q(0.9).toFixed(3)} spread=${spread.toFixed(3)}`);
    const distinct = new Set(shell.map(v => v.toFixed(2))).size;
    check("not everyone converges on one value", distinct > 20, `${distinct} distinct hundredths`);
}
{
    // The three traits are frozen at birth and genuinely differ between stars.
    const input = birthInput();
    const pool = Physics.create(W, H, RH, 3, {}, (p, i) => Appearance.birth(p, i, input));
    for (let f = 0; f < 600; ++f) Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
    const onset = [], gain = [], rate = [];
    for (let k = 0; k < pool.liveCount; ++k) {
        const i = pool.live[k];
        onset.push(pool.tideOnset[i]); gain.push(pool.tideGain[i]); rate.push(pool.tideRate[i]);
    }
    const span = a => Math.max(...a) - Math.min(...a);
    check("birth freezes a spread of onset radii", span(onset) > 0.6, `span ${span(onset).toFixed(3)}`);
    check("birth freezes a spread of susceptibilities", span(gain) > 0.35, `span ${span(gain).toFixed(3)}`);
    check("birth freezes a spread of blend rates", span(rate) > 1.2, `span ${span(rate).toFixed(2)} s`);
    const inBounds = onset.every(v => v >= 0.62 && v <= 1.42) && gain.every(v => v >= 0.55 && v <= 1)
        && rate.every(v => v >= 0.45 && v <= 1.9);
    check("frozen traits stay inside their documented ranges", inBounds);
}

// ------------------------------------------------------------- mass and reach
// blackHole.mass reaches the particles as particles.mass. The drive is
// (reach/r)^3 with reach proportional to rh*cbrt(mass), so it is exactly
// proportional to mass/r^3: one number moves both the reach and the strength.
{
    // The global budget is lifted here so it cannot mask the comparison: it
    // normalises the TOTAL deformation to an instance count, which would hide a
    // heavier hole's extra reach behind a smaller scale for everyone. Captured
    // stars are skipped for the same reason - their four-second capture ramp
    // deforms them whatever the mass is, and the capture shell sits just
    // outside the rim.
    function profile(mass) {
        const sum = new Array(16).fill(0), count = new Array(16).fill(0);
        simulate({config: {mass, streak: {bendMaxAlive: 3200}}, measureSec: 20, visit: items => {
            const d = items.data;
            for (let j = 0; j < items.count; ++j) {
                const b = j * S, bin = Math.floor(radiusOf(d, b) / RIM * 8);
                if (bin < 16 && d[b + 15] < 0.01) { sum[bin] += d[b + ISTRETCH]; ++count[bin]; }
            }
        }});
        return sum.map((v, i) => count[i] ? v / count[i] : 0);
    }
    const light = profile(0.5), heavy = profile(3);
    // The reach is bendRadiusRd * cbrt(mass) * the star's own onset scale, so
    // 0.70 Rd becomes 0.556 Rd at mass 0.5 and 1.010 Rd at mass 3; with the
    // 0.62-1.42 onset spread that is 0.34-0.79 Rd against 0.63-1.43 Rd. Bins 7
    // and 8 are 0.875-1.125 Rd: past every light-hole onset, inside the heavy
    // hole's widest.
    const far = a => (a[7] + a[8]) / 2;
    check("a heavier hole reaches further out", far(heavy) > 0.02 && far(light) < 0.005,
        `0.875-1.125 Rd: mass 0.5 -> ${far(light).toFixed(4)}, mass 3 -> ${far(heavy).toFixed(4)}`);
    // Near the rim the response saturates for both, so mass shows up as reach
    // and as the total deformation carried, not as a deeper floor.
    check("a heavier hole deforms harder everywhere it is not already saturated",
        heavy.slice(4, 16).every((v, i) => v >= light[i + 4] - 1e-6),
        `0.5-2 Rd heavy ${heavy.slice(4, 16).map(v => v.toFixed(3)).join(",")} light ${light.slice(4, 16).map(v => v.toFixed(3)).join(",")}`);
    const outer = a => a.slice(6).reduce((x, y) => x + y, 0);
    check("mass scales how much of the field is deformed at all",
        outer(heavy) > 2 * outer(light),
        `0.75 Rd outward: heavy ${outer(heavy).toFixed(3)} light ${outer(light).toFixed(3)}`);
}
{
    // The hole's own enable envelope gates all of it: with the hole off, absorb
    // fades to zero over thirty seconds and the deformation goes with it.
    let maxStretch = 0, anyFlag = 0;
    simulate({absorb: 0, warmSec: 20, measureSec: 10, visit: items => {
        const d = items.data;
        for (let j = 0; j < items.count; ++j) {
            const b = j * S;
            if (d[b + ISTRETCH] > maxStretch) maxStretch = d[b + ISTRETCH];
            if (d[b + IFLAGS] >= 64) ++anyFlag;
        }
    }});
    check("a disabled hole leaves no deformation at all", maxStretch === 0 && anyFlag === 0,
        `max stretch ${maxStretch}`);
}

// ------------------------------------------------------------------- packing
{
    // The stretch survives the byte quantisation monotonically, and lands in
    // texel +1 green, which the shader already fetches for the position.
    const list = [];
    for (let i = 0; i <= 20; ++i)
        list.push({x: 100 + i * 40, y: 200, vx: 30, vy: 0, core: 2, support: 12,
            streak: 8, r: 1, g: 1, b: 1, lum: 1, flags: i ? 64 : 0, halfMajor: 12, halfMinor: 12,
            stretch: i / 20});
    const items = Appearance.instances(list);
    const bins = Binning.build(null, items, 1024, 1024);
    const packet = Packing.pack(null, bins, items, {domain: [0, 0, 1024, 1024], clock: 0, revision: 1, minHeight: 0});
    check("packet verifies", Packing.verify(packet));
    const read = i => packet.bytes[(packet.dataBase + 8 * i) * 4 + 5];
    let monotonic = true, exact = true;
    for (let i = 0; i <= 20; ++i) {
        if (i && read(i) <= read(i - 1)) monotonic = false;
        if (Math.abs(read(i) / 255 - i / 20) > 1 / 255) exact = false;
    }
    check("stretch packs monotonically into texel +1 green", monotonic, `0 -> ${read(0)}, 1 -> ${read(20)}`);
    check("stretch round-trips inside one code", exact);
    // The transverse sagitta headroom in the reject box follows the same scalar.
    const boxAt = i => packet.bytes[(packet.dataBase + 8 * i) * 4 + 29];
    check("the reject box grows with the stretch, not with a flag bit",
        boxAt(20) > boxAt(10) && boxAt(10) > boxAt(0), `${boxAt(0)} ${boxAt(10)} ${boxAt(20)}`);
}

// ------------------------------------------------------------- atlas ceiling
// The atlas is allocated once from bounds()/capacity(); a later resize of the
// sampled texture cost 13 ms -> 6700 ms per frame on llvmpipe and never
// recovered. Continuous deformation means ANY instance may be fully stretched,
// so the ceiling must cover that, whatever the live budget happens to be.
{
    let ceiling = 0, worst = 0, worstRefs = 0;
    const sim = simulate({config: {stressPreset: true}, warmSec: 40, measureSec: 20,
        visit: (items, bins, pool) => {
            if (!ceiling) {
                const c = Appearance.bounds(pool);
                ceiling = Packing.capacity(bins, c.maxItems, c.maxSupport, c.maxFlares, c.flareSupport, c.maxBends, c.bendSupport, c.maxTde, c.tdeSupport);
            }
            const layout = Packing.layout(null, bins, items.count, 0);
            if (layout.height > worst) worst = layout.height;
            if (bins.references > worstRefs) worstRefs = bins.references;
        }});
    check("the live atlas never outgrows the pre-sized ceiling", worst <= ceiling,
        `worst ${worst} of ceiling ${ceiling} rows (2100 particles, ${worstRefs} references)`);
    check("the stretch budget stays inside its configured instance count",
        sim.pool.stretchBudget > 0 && sim.pool.stretchBudget <= 1,
        `budget ${sim.pool.stretchBudget.toFixed(3)}`);
}

// -------------------------------------------------- tidal disruption (R7)
// Particles only: no slot, no uniform, no shader change. The victim's packed
// streak is ramped to the configured length and it then splits into siblings.
{
    const input = birthInput();
    const pool = Physics.create(W, H, RH, 11, {}, (p, i) => Appearance.birth(p, i, input));
    pool.absorb = 1;
    let items = null;
    for (let f = 0; f < 30 * 90; ++f) {
        Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        items = Appearance.render(items, pool, {twinkle: 0.22});
    }
    const before = pool.aliveCount;
    const fired = Physics.doom(pool, {streakPx: 140, stretchSec: 8, fragments: 6});
    check("a victim is found on a deep inbound orbit", fired && pool.tde.index >= 0,
        fired ? `particle ${pool.tde.index}, pericentre ${(pool.pericentre[pool.tde.index] / SHADOW).toFixed(2)} Rh` : "none");
    const victim = pool.tde.index;
    // The ramp must be gradual, and the rendered streak must actually reach it.
    let prev = 0, worstStep = 0, peak = 0, split = 0;
    for (let f = 0; f < 30 * 14; ++f) {
        Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        items = Appearance.render(items, pool, {twinkle: 0.22});
        const d = items.data;
        for (let j = 0; j < items.count; ++j) {
            const b = j * S;
            if (d[b + IID] !== victim) continue;
            const v = d[b + ISTREAK];
            if (prev) worstStep = Math.max(worstStep, Math.abs(v - prev));
            if (v > peak) peak = v;
            prev = v;
        }
        if (!split && pool.counters.tde) split = f;
    }
    check("the trail is drawn out to the longest the packed byte carries", peak > 110,
        `peak rendered streak ${peak.toFixed(1)} px (140 requested, field ceiling 120)`);
    // This is the whole point: the ramp up AND the fade back after the split
    // are both gradual. The first version snapped 120 px -> 8 px on the frame
    // the victim split, which is the same defect as the old bend cap.
    check("it is drawn out and drawn back over many frames, never in one", worstStep < 6,
        `worst single-frame change ${worstStep.toFixed(2)} px`);
    check("the victim then splits into siblings", pool.counters.tde === 1 && pool.counters.tdeFragments >= 4,
        `${pool.counters.tdeFragments} siblings at frame ${split} (${(split / 30).toFixed(1)} s), population ${before} -> ${pool.aliveCount}`);
    for (let f = 0; f < 30 * 8; ++f) {
        Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        items = Appearance.render(items, pool, {twinkle: 0.22});
    }
    check("the descriptor is cleared once the fade is over", pool.tde === null);
    // The whole point of the ceiling work: a 160 px trail must fit the atlas
    // that was sized once, before any disruption existed.
    const c = Appearance.bounds(pool);
    const bins = Binning.build(null, items, W, H);
    const sized = Packing.capacity(bins, c.maxItems, c.maxSupport, c.maxFlares, c.flareSupport, c.maxBends, c.bendSupport, c.maxTde, c.tdeSupport);
    const without = Packing.capacity(bins, c.maxItems, c.maxSupport, c.maxFlares, c.flareSupport, c.maxBends, c.bendSupport, 0, 0);
    check("the atlas ceiling covers the longest disruption trail", c.tdeSupport > c.bendSupport && sized >= without,
        `tdeSupport ${c.tdeSupport.toFixed(1)} vs bendSupport ${c.bendSupport.toFixed(1)}; ceiling ${without} -> ${sized} rows`);
    let worstHeight = 0;
    Physics.doom(pool, {streakPx: 160, stretchSec: 6, fragments: 8});
    for (let f = 0; f < 30 * 12; ++f) {
        Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        items = Appearance.render(items, pool, {twinkle: 0.22});
        const b2 = Binning.build(null, items, W, H);
        worstHeight = Math.max(worstHeight, Packing.layout(null, b2, items.count, 0).height);
    }
    check("the live atlas stays inside it through a full disruption", worstHeight <= sized,
        `worst ${worstHeight} of ${sized} rows`);
}

// ------------------------------------------------- the hole's three radii (v7b)
// Two bugs, two directions. v6 anchored every boundary to Rh, the shadow radius,
// so with the target preset's 3.900 Rh picture the capture ring circularised
// INSIDE the disk and stars were drawn on top of the material: 65.8 % of the
// rendered ink sat inside the drawn hole. v7 over-corrected and killed stars at
// the outermost arcs, which he rejected the same day (ledger 2282): "now the
// stars disappear too far from the hole, they are disappearing somewhere close
// to the rings". A star must reach the black core. Crossing the disk band on the
// way is an occlusion, composited in starfield.frag, not a swallow.
// The live `target` preset as of b0aa32dc: the ring rework turned the outer
// arcs OFF and widened the disk to 11 Rs, so the material rim and the shadow
// are the only two boundaries left that describe anything drawn.
const TARGET_DISK = {innerRs: 3, outerRs: 11, arcGain: 0, arcRadiusRh: 1.6, arcSpacingRh: 0.55, arcCount: 4};
const ARCS_ON = {innerRs: 3, outerRs: 10.5, arcGain: 0.013, arcRadiusRh: 1.6, arcSpacingRh: 0.55, arcCount: 4};
{
    // The geometry mirrors bhOuter()/bhImpact()/bhArcReach() in blackhole.glsl.
    // If that file moves, these pin the drift.
    const r = Physics.visibleRadius(RH, TARGET_DISK);
    check("the shadow is Rh and the live target preset's material rim is 3.735 Rh",
        Math.abs(r.shadow / RH - 1) < 1e-9 && Math.abs(r.disk / RH - 3.735) < 0.01,
        `shadow ${(r.shadow / RH).toFixed(3)}, disk ${(r.disk / RH).toFixed(3)}, arcs ${(r.arcs / RH).toFixed(3)} Rh`);
    // With the arcs off, arcs collapses onto the material rim and describes
    // nothing extra; the branch still has to work for a preset that draws them.
    const withArcs = Physics.visibleRadius(RH, ARCS_ON);
    check("arcs are reported separately only when the disk actually draws them",
        Math.abs(r.arcs - r.disk) < 1e-9 && Math.abs(withArcs.arcs / RH - 3.900) < 0.01,
        `arcs off -> ${(r.arcs / RH).toFixed(3)}, arcs on -> ${(withArcs.arcs / RH).toFixed(3)} Rh`);
    check("the v4 default disk gives a smaller material rim, still outside the shadow",
        Math.abs(RIM / RH - 2.783) < 0.01 && RIM > SHADOW, `${(RIM / RH).toFixed(3)} Rh`);
    // b_c = 3*sqrt(3)/2 Rs lands exactly on Rh, which is what makes Rh the
    // shadow radius and not the size of the hole.
    check("the screen radius of the photon sphere is Rh itself",
        Math.abs(Physics.screenRadius(1.5, RH) / RH - 1) < 0.02, `${(Physics.screenRadius(1.5, RH) / RH).toFixed(4)} Rh`);
}
for (const geometry of [undefined, TARGET_DISK]) {
    const label = geometry ? "target preset" : "default disk";
    let worst = Infinity, inBand = 0, total = 0, front = 0, frontMiddle = 0, near = 0;
    let shadow = 0, diskRim = 0, capIn = 0, capOut = 0, capFloor = 0;
    let nearLight = 0, nearN = 0, fieldLight = 0, fieldN = 0;
    const capturedAt = [];
    const ILUM = 10, IID = 16;
    simulate({geometry, measureSec: 60, visit: (items, bins, pool) => {
        const d = items.data;
        shadow = pool.shadow; diskRim = pool.diskRim;
        capIn = pool.captureInner; capOut = pool.captureOuter; capFloor = pool.captureFloor;
        for (let j = 0; j < items.count; ++j) {
            const b = j * S, lum = d[b + ILUM], flags = d[b + IFLAGS], id = d[b + IID];
            // A binary companion or a wanderer is DRAWN a few px off its own
            // physics position; the fade is a function of the physics radius,
            // and the shader clips the rest at the pixel level (shadowPass).
            const r = Math.hypot(pool.x[id] - W / 2, pool.y[id] - H / 2);
            if (lum > 0.001) {
                ++total;
                if (r > pool.shadow && r < pool.diskRim) ++inBand;
                if (flags >= 16 && flags < 32 || flags >= 48) ++near;
                if (Math.floor(flags / 32) % 2 === 1) { ++front; if (Math.floor(flags / 16) % 2 === 0) ++frontMiddle; }
            }
            if (lum > 0.02 && r < worst) worst = r;
            // The dissolve: light in the last 5 % before the shadow against the
            // open field two shadow radii out.
            if (r < 1.05 * pool.shadow) { nearLight += lum; ++nearN; }
            else if (r > 1.5 * pool.shadow && r < 2 * pool.shadow) { fieldLight += lum; ++fieldN; }
        }
        for (let k = 0; k < pool.liveCount; ++k) {
            const i = pool.live[k];
            if (pool.radiusAtCapture[i] > 0) capturedAt.push(pool.radiusAtCapture[i]);
        }
    }});
    // THE invariant: the black core stays black.
    check(`nothing visible is drawn inside the shadow (${label})`, worst >= shadow,
        `closest visible ${worst.toFixed(1)} px vs shadow ${shadow.toFixed(1)} px (${(worst / shadow).toFixed(4)} Rh)`);
    const dissolve = (nearLight / Math.max(1, nearN)) / Math.max(1e-9, fieldLight / Math.max(1, fieldN));
    check(`a star dissolves into the shadow instead of switching off (${label})`,
        nearN > 100 && dissolve < 0.35,
        `mean light at the shadow is ${(100 * dissolve).toFixed(1)} % of the open field's`);
    // ...and stars DO reach it: the v7 regression was an empty disk band.
    check(`the flow crosses the disk band instead of stopping outside it (${label})`,
        inBand / Math.max(1, total) > 0.05,
        `${(100 * inBand / Math.max(1, total)).toFixed(1)} % of instances between the shadow and the rim`);
    // Where a star CIRCULARISES, not where it has spiralled to since.
    capturedAt.sort((a, b) => a - b);
    const lo = capturedAt[0], hi = capturedAt[capturedAt.length - 1];
    check(`stars circularise at the disk's rim, not out past the arcs (${label})`,
        capturedAt.length > 200 && lo >= capFloor - 0.5 && hi <= capOut + 0.5,
        `${capturedAt.length} samples, ${(lo / diskRim).toFixed(2)}-${(hi / diskRim).toFixed(2)} Rd, drag window ${(capFloor / diskRim).toFixed(2)}-${(capOut / diskRim).toFixed(2)} Rd`);
    check(`the capture band starts at the disk's material rim (${label})`,
        Math.abs(capIn / diskRim - 1) < 1e-9, `band starts at ${(capIn / diskRim).toFixed(3)} Rd`);
    // Depth ordering is what keeps a star in the band off the TOP of the disk.
    check(`only near stars are composited in front of the disk (${label})`,
        frontMiddle === 0 && front > 0 && front / Math.max(1, near) < 0.30,
        `${front} front of ${near} near, ${frontMiddle} middle wrongly in front`);
}
{
    // Mass carries the band's STANDOFF above the disk rim, not the rim, which is
    // drawn and does not move with it.
    const a = Physics.create(W, H, RH, 5, {mass: 1}, null, TARGET_DISK);
    const b = Physics.create(W, H, RH, 5, {mass: 3}, null, TARGET_DISK);
    check("a heavier hole captures from further out, from the same rim",
        Math.abs(a.diskRim - b.diskRim) < 1e-9 && b.captureOuter > a.captureOuter
        && Math.abs((b.captureOuter / b.diskRim - 1) / (a.captureOuter / a.diskRim - 1) - Math.cbrt(3)) < 1e-6,
        `standoff ${(a.captureOuter / a.diskRim - 1).toFixed(4)} -> ${(b.captureOuter / b.diskRim - 1).toFixed(4)} Rd`);
    check("the swallow radius is the shadow on every preset",
        Math.abs(a.shadow - RH) < 1e-9 && Math.abs(Physics.create(W, H, RH, 5, {}, null).shadow - RH) < 1e-9);
}
{
    // The occlusion half of the fix lives in the fragment shader, where node
    // cannot run it. What node CAN do is pin the one line that was wrong: the
    // particle field behind the disk must be attenuated by the disk's geometric
    // coverage (particleDiskAbsorb), not by the alpha its shading left (disk.a).
    const frag = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "shaders", "starfield.frag"), "utf8");
    check("particles behind the disk are attenuated by the disk's own coverage",
        /diskOcclusion\s*=\s*particleDiskAbsorb\(pixel,\s*disk\.a\)/.test(frag)
        && /\(1\.0-diskOcclusion\)\*material/.test(frag),
        "starfield.frag composites material through (1-diskOcclusion)");
    check("front particles are still composited over the disk, masked only by the shadow",
        /\+ahead\*shadowPass/.test(frag));
    check("the swept particle death is still the shadow, never the drawn rim",
        /smoothstep\(ubuf\.bhGeometry\.x,ubuf\.bhGeometry\.x\+0\.75,r\)/.test(frag));
}

// ================================================== camera fly-through (v8)
// The other regime. blackHole.enabled:false used to fade the DRAWING of the
// hole and nothing else: mu was untouched, so stars went on falling into an
// invisible mass, went on circularising into an invisible ring, and - because
// the swallow radius follows the same envelope - stopped dying at the centre
// and piled up there until their safety life expired. Measured before this
// change: 289 captures and 76 instances inside 1 Rh over 180 s with the hole
// off, against 0 inside 1 Rh with it on. The camera regime replaces all of it.
const CAM_DEPTH = 16, CAM_RATE = (CAM_DEPTH - 1) * 6 / 360;
function flyThrough(pool, o) {
    pool.cameraBlend = o.blend === undefined ? 1 : o.blend;
    pool.cameraDir = o.dir === undefined ? 1 : o.dir;
    pool.cameraDepth = CAM_DEPTH;
    pool.cameraRate = o.rate === undefined ? CAM_RATE : o.rate;
    pool.cameraRoll = o.roll === undefined ? 0 : o.roll;
    pool.cameraSizeGain = 0.55;
    // The hole's envelope and the camera's are complements: one toggle.
    pool.absorb = 1 - (o.blend === undefined ? 1 : o.blend);
}
function fly(o) {
    const options = o || {};
    const input = birthInput();
    const pool = Physics.create(W, H, RH, options.seed === undefined ? 7 : options.seed, options.config || {},
        (p, i) => Appearance.birth(p, i, input), options.geometry);
    let items = null;
    const warm = options.warmSec === undefined ? 240 : options.warmSec;
    const measure = options.measureSec === undefined ? 60 : options.measureSec;
    const visit = options.visit || (() => {});
    for (let f = 0; f < Math.round((warm + measure) / DT); ++f) {
        flyThrough(pool, options.at ? options.at(f * DT) : options);
        Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        items = Appearance.render(items, pool, {twinkle: 0.22});
        if (f * DT >= warm) visit(items, pool, f * DT);
    }
    return {pool, items};
}
const BINS = 12, RMAX = Math.hypot(W / 2, H / 2);
// Screen area of each radial bin, by sampling: the outer bins are mostly off a
// 2160x3840 rectangle, so a pi*r^2 annulus would be badly wrong.
const BIN_AREA = new Array(BINS).fill(0);
{
    let seed = 12345;
    const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);
    for (let n = 0; n < 400000; ++n)
        ++BIN_AREA[Math.min(BINS - 1, Math.floor(BINS * Math.hypot(rnd() * W - W / 2, rnd() * H - H / 2) / RMAX))];
}
{
    // ---- the hole's physics is gone, not just its picture
    const before = {};
    const out = fly({visit: (items, pool, t) => { if (t < DT * 1.5) Object.assign(before, pool.counters); }});
    const pool = out.pool;
    let core = 0, maxDrift = 0;
    for (let k = 0; k < pool.liveCount; ++k) {
        const i = pool.live[k];
        const r = Math.hypot(pool.x[i] - W / 2, pool.y[i] - H / 2);
        if (r < RH) ++core;
        // A still star under a moving camera: speed is exactly r*rate/z.
        const want = r * CAM_RATE / Physics.cameraDepthOf(pool, i);
        const have = Math.hypot(pool.vx[i], pool.vy[i]);
        maxDrift = Math.max(maxDrift, Math.abs(have - want) / Math.max(1, want));
    }
    check("the camera regime captures nothing and swallows nothing",
        pool.counters.captures - (before.captures || 0) === 0
        && pool.counters.absorbed - (before.absorbed || 0) === 0,
        `${pool.counters.captures - (before.captures || 0)} captures, ${pool.counters.absorbed - (before.absorbed || 0)} swallowed in 60 s`);
    // A uniform field puts pi*Rh^2/(W*H) of 600 stars - about 13 - inside 1 Rh
    // and they are passing through, not parked. The old hole-off left 76 there,
    // dragged in by a mass nobody could see and unable to die at the centre.
    const uniform = 600 * Math.PI * RH * RH / (W * H);
    check("nothing piles up in the centre the invisible hole used to hold",
        core < 2 * uniform, `${core} instances inside 1 Rh against ${uniform.toFixed(0)} for a uniform field (the old hole-off left ~76)`);
    // The stored velocity is the step's actual displacement rate, which is what
    // a streak has to be drawn from; it sits half a step under the continuous
    // law, and half a step at the near plane is 0.4 %.
    check("every star moves at the camera's own r/z law",
        maxDrift < 0.01, `worst relative error ${(100 * maxDrift).toFixed(2)} %`);
    check("the population is held without the orbital birth path",
        pool.aliveCount > 560 && pool.aliveCount <= 600, `${pool.aliveCount} alive`);
}
{
    // ---- perspective: speed grows with radius, monotonically, in both directions
    for (const dir of [1, -1]) {
        const label = dir > 0 ? "out" : "in";
        const n = new Array(BINS).fill(0), v = new Array(BINS).fill(0);
        let wrongWay = 0, moving = 0;
        fly({dir, visit: items => {
            const d = items.data;
            for (let j = 0; j < items.count; ++j) {
                const b = j * S, bin = Math.min(BINS - 1, Math.floor(BINS * radiusOf(d, b) / RMAX));
                ++n[bin];
                v[bin] += Math.hypot(d[b + 2], d[b + 3]);
                // Radial, and radial the right way: out is away from the centre,
                // in is the same trajectories played backwards.
                const radial = (d[b] - W / 2) * d[b + 2] + (d[b + 1] - H / 2) * d[b + 3];
                if (Math.abs(radial) > 1e-6) { ++moving; if (radial * dir <= 0) ++wrongWay; }
            }
        }});
        check(`every star moves ${dir > 0 ? "away from" : "toward"} the centre and nowhere else (${label})`,
            moving > 10000 && wrongWay === 0, `${wrongWay} of ${moving} instances going the wrong way`);
        const mean = v.map((x, i) => n[i] > 20 ? x / n[i] : NaN).filter(x => x === x);
        let rising = true;
        for (let i = 1; i < mean.length; ++i) if (!(mean[i] > mean[i - 1])) rising = false;
        check(`screen speed grows with radius, every bin (${label})`,
            rising && mean.length >= 10 && mean[mean.length - 1] / mean[0] > 10,
            `${mean.map(x => x.toFixed(0)).join(" ")} px/s over ${mean.length} bins, ${(mean[mean.length - 1] / mean[0]).toFixed(0)}x end to end`);
        // Uniform density is the whole reason the birth distribution is what it
        // is: births are the time-reverse of deaths, so neither direction piles
        // stars up anywhere. The two inner bins are the centre, which reverse
        // deliberately empties (below), and the outer bin is mostly padding
        // where instances live off screen.
        const share = n.map((x, i) => x / BIN_AREA[i]);
        const mid = share.slice(2, BINS - 1);
        const lo = Math.min(...mid), hi = Math.max(...mid);
        check(`the field stays uniform across the screen (${label})`, hi / lo < 1.35,
            `bin density spread ${(hi / lo).toFixed(2)}x over bins 2-${BINS - 2}`);
        const centre = share[0] / (share.reduce((a, b, i) => i >= 2 && i < BINS - 1 ? a + b : a, 0) / (BINS - 3));
        check(`the centre is populated like the rest of the sky (${label})`,
            centre > 0.5, `centre density ${centre.toFixed(2)} of the mid-field`);
    }
}
{
    // ---- births: the far plane going out, the screen edge coming in
    const place = {out: [], in: []};
    for (const dir of [1, -1]) {
        const key = dir > 0 ? "out" : "in";
        const input = birthInput();
        const pool = Physics.create(W, H, RH, 11, {}, (p, i) => {
            Appearance.birth(p, i, input);
            place[key].push([Math.hypot(p.x[i] - W / 2, p.y[i] - H / 2), p.depthZ[i]]);
        });
        for (let f = 0; f < Math.round(120 / DT); ++f) {
            flyThrough(pool, {dir});
            Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        }
    }
    const outs = place.out, ins = place.in;
    const atFar = outs.filter(p => p[1] >= CAM_DEPTH - 1e-9).length / outs.length;
    check("going out, every birth is at the far plane", atFar > 0.999,
        `${(100 * atFar).toFixed(1)} % of ${outs.length} births at z = ${CAM_DEPTH}`);
    // Uniform per unit area at the far plane is what a uniform 3-D field
    // crossing a plane looks like, and it is what keeps the screen uniform.
    // The reference is the padded rectangle itself, not a disc: on a 2160x3840
    // output half the AREA is nothing like half the radius.
    const want = BIN_AREA.reduce((a, x, i) => i >= Math.floor(BINS * 0.707) ? a + x : a, 0)
        / BIN_AREA.reduce((a, x) => a + x, 0);
    const outer = outs.filter(p => p[0] > 0.707 * RMAX).length / outs.length;
    check("going out, births are uniform per unit area, not heaped at the centre",
        Math.abs(outer - want) < 0.05,
        `${(100 * outer).toFixed(0)} % beyond 0.707 R against ${(100 * want).toFixed(0)} % of the area`);
    // Coming in they arrive ON the padded boundary, which is what a forward
    // death is: the padding is max(32, Rh/4) outside the screen.
    const pad = Math.max(32, 0.25 * RH);
    const offEdge = ins.filter(p => {
        const r = p[0];
        return r >= Math.min(W, H) / 2 && r <= RMAX + 2 * pad;
    }).length / ins.length;
    check("coming in, births arrive at the screen edge", offEdge > 0.99,
        `${(100 * offEdge).toFixed(1)} % of ${ins.length} births on the padded boundary`);
    const spread = ins.filter(p => p[1] < CAM_DEPTH * 0.5).length / ins.length;
    check("coming in, births carry the depth spread forward deaths arrive with",
        spread > 0.15 && spread < 0.35, `${(100 * spread).toFixed(0)} % born inside half the depth`);
}
{
    // ---- reverse really is the reverse: the map is exactly invertible
    const input = birthInput();
    const pool = Physics.create(W, H, RH, 3, {}, (p, i) => Appearance.birth(p, i, input));
    for (let f = 0; f < Math.round(30 / DT); ++f) {
        flyThrough(pool, {});
        Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
    }
    const ids = [], x0 = [], y0 = [], z0 = [];
    for (let k = 0; k < pool.liveCount; ++k) {
        const i = pool.live[k];
        ids.push(i); x0.push(pool.x[i]); y0.push(pool.y[i]); z0.push(pool.depthZ[i]);
    }
    const gen = ids.map(i => pool.generation[i]);
    // 200 steps out, then 200 back, with births and deaths off so the same
    // stars are still there to compare.
    const opts = {deaths: false};
    for (let f = 0; f < 200; ++f) { flyThrough(pool, {}); Physics.step(pool, DT, opts); }
    let moved = 0;
    for (let k = 0; k < ids.length; ++k)
        moved = Math.max(moved, Math.hypot(pool.x[ids[k]] - x0[k], pool.y[ids[k]] - y0[k]));
    for (let f = 0; f < 200; ++f) { flyThrough(pool, {dir: -1}); Physics.step(pool, DT, opts); }
    let worst = 0, worstZ = 0, alive = 0;
    for (let k = 0; k < ids.length; ++k) {
        const i = ids[k];
        if (!pool.alive[i] || pool.generation[i] !== gen[k]) continue;
        ++alive;
        worst = Math.max(worst, Math.hypot(pool.x[i] - x0[k], pool.y[i] - y0[k]));
        worstZ = Math.max(worstZ, Math.abs(pool.depthZ[i] - z0[k]));
    }
    check("the field travelled a real distance before it was reversed", moved > 200,
        `furthest star moved ${moved.toFixed(0)} px`);
    check("reverse returns every star to where it started", alive > 400 && worst < 1e-6 && worstZ < 1e-9,
        `${alive} stars, worst ${worst.toExponential(2)} px, worst depth ${worstZ.toExponential(2)}`);
}
{
    // ---- the crossfade is a crossfade: nothing steps when the regime changes
    let worst = 0, worstStreak = 0;
    const prev = new Map();
    // Thirty seconds of orbital regime, the hole's own 30 s envelope, then the
    // camera. `at` mirrors what BlackHole.advance does to bhHalo.w.
    const ease = x => x * x * (3 - 2 * x);
    fly({warmSec: 0, measureSec: 120, at: t => ({blend: ease(Math.max(0, Math.min(1, (t - 30) / 30)))}),
        visit: items => {
            const d = items.data;
            for (let j = 0; j < items.count; ++j) {
                const b = j * S, key = d[b + IID] + ":" + d[b + IGEN];
                const p = prev.get(key);
                if (p) {
                    worst = Math.max(worst, Math.hypot(d[b] - p[0], d[b + 1] - p[1]));
                    worstStreak = Math.max(worstStreak, Math.abs(d[b + ISTREAK] - p[2]));
                }
                prev.set(key, [d[b], d[b + 1], d[b + ISTREAK]]);
            }
        }});
    // The fastest thing on screen in the orbital regime passes the shadow at a
    // few hundred px/s, i.e. ~20 px in a frame. Nothing may teleport.
    check("no star jumps when the regime crossfades", worst < 60,
        `worst one-frame move ${worst.toFixed(1)} px across the 30 s change`);
    check("no streak jumps when the regime crossfades", worstStreak < 8,
        `worst one-frame streak change ${worstStreak.toFixed(2)} px`);
}
{
    // ---- depth is the only thing that dims and shrinks a star, and it can only
    //      dim and shrink it: the atlas ceiling bounds() allocated from the
    //      configured sizes is still the ceiling in the camera regime.
    let maxCore = 0, born = 0, loud = 0, deep = 0, near = 0, deepLight = 0, nearLight = 0;
    const out = fly({visit: (items, pool) => {
        const d = items.data;
        for (let j = 0; j < items.count; ++j) {
            const b = j * S, z = pool.depthZ[d[b + IID]];
            maxCore = Math.max(maxCore, d[b + ICORE]);
            if (z > CAM_DEPTH - 0.02) { ++born; if (d[b + 10] > 0.25) ++loud; }
            if (z > CAM_DEPTH * 0.8) { ++deep; deepLight += d[b + 10]; }
            else if (z < 3) { ++near; nearLight += d[b + 10]; }
        }
    }});
    check("a star's core stays inside the configured size range", maxCore <= 4.8 + 1e-9,
        `worst core ${maxCore.toFixed(2)} px against the 4.8 px near ceiling the atlas is sized for`);
    check("a star arrives out of the far plane instead of appearing at full light",
        born > 200 && loud / born < 0.02,
        `${loud} of ${born} instances at the far plane over 0.25 light`);
    check("a star brightens as the camera closes on it",
        deep > 100 && near > 100 && nearLight / near > 1.4 * (deepLight / deep),
        `mean light ${(deepLight / deep).toFixed(3)} deep, ${(nearLight / near).toFixed(3)} near`);
    // The invariant, on one state rendered both ways: depth never adds light or
    // size to a star, so nothing the camera does can overflow the atlas.
    const pool = out.pool;
    pool.cameraBlend = 0;
    const offItems = Appearance.render(null, pool, {twinkle: 0});
    const off = new Map();
    for (let j = 0; j < offItems.count; ++j) {
        const b = j * S;
        off.set(offItems.data[b + IID] + ":" + j, [offItems.data[b + ICORE], offItems.data[b + 10]]);
    }
    pool.cameraBlend = 1;
    const onItems = Appearance.render(null, pool, {twinkle: 0});
    let grew = 0, compared = 0, shrank = 0;
    for (let j = 0; j < onItems.count; ++j) {
        const b = j * S, was = off.get(onItems.data[b + IID] + ":" + j);
        if (!was) continue;
        ++compared;
        if (onItems.data[b + ICORE] > was[0] + 1e-9 || onItems.data[b + 10] > was[1] + 1e-9) ++grew;
        if (onItems.data[b + ICORE] < was[0] - 1e-9) ++shrank;
    }
    check("depth only ever dims and shrinks, so the atlas ceiling still holds",
        compared > 400 && grew === 0 && shrank > compared * 0.5,
        `${grew} of ${compared} instances brighter or bigger with the camera on, ${shrank} smaller`);
}
{
    // ---- the hole-on regime is untouched: same stream, same stars, same bytes
    const run = camera => {
        const input = birthInput();
        const pool = Physics.create(W, H, RH, 7, {}, (p, i) => Appearance.birth(p, i, input), TARGET_DISK);
        for (let f = 0; f < Math.round(90 / DT); ++f) {
            pool.absorb = 1;
            if (camera) flyThrough(pool, {blend: 0});
            Physics.advance(pool, DT, 6, 0.5, W / 2, H / 2, 1, pool.birthCallback);
        }
        const out = [];
        for (let k = 0; k < pool.liveCount; ++k) {
            const i = pool.live[k];
            out.push([i, pool.generation[i], pool.x[i], pool.y[i], pool.vx[i], pool.vy[i]]);
        }
        return {out, pool};
    };
    const a = run(false), b = run(true);
    let same = a.out.length === b.out.length && a.out.length > 400;
    for (let i = 0; same && i < a.out.length; ++i)
        for (let j = 0; j < 6; ++j) if (a.out[i][j] !== b.out[i][j]) same = false;
    check("a camera at blend 0 does not perturb the orbital regime by one bit",
        same, `${a.out.length} live stars compared bit for bit after 90 s`);
    check("and it still captures and swallows exactly as v7 did",
        a.pool.counters.captures === b.pool.counters.captures
        && a.pool.counters.absorbed === b.pool.counters.absorbed,
        `${a.pool.counters.captures} captures, ${a.pool.counters.absorbed} swallowed`);
}
{
    // ---- the renderer half: the far field reverses with the same one toggle
    const dir = dirname(fileURLToPath(import.meta.url));
    const frag = readFileSync(join(dir, "..", "shaders", "starfield.frag"), "utf8");
    const qml = readFileSync(join(dir, "..", "Starfield.qml"), "utf8");
    const rules = readFileSync(join(dir, "..", "..", "..", "services", "ambient", "rules.js"), "utf8");
    check("the shader ages an outward star from the centre it was born at",
        /float outward = clamp\(ubuf\.radialMode - 1\.0, 0\.0, 1\.0\);/.test(frag)
        && /age = mix\(age, max\(0\.0, starU - minimumU\)/.test(frag),
        "starfield.frag carries the blend in radialMode's fraction");
    check("the renderer hands it that blend and only that blend",
        /shader\.radialMode = motionMode === "drift" \? 0 : 1 \+ _cameraOutward;/.test(qml)
        && /cameraDirection === "in" \? 0 : _cameraBlend/.test(qml));
    check("the grid advance is signed and per layer, and the history is not",
        /s\.geo\[layer\] \* \(6 \/ 1080\)/.test(qml) && /s\.flow \+= dFlow;/.test(qml)
        && /const sign = 1 - 2 \* _cameraOutward;/.test(qml));
    // The validated schema: defaults first, then that every bound rejects.
    const Rules = new Function(rules + "\nreturn {validateDocument: validateDocument};")();
    const base = Rules.validateDocument(null).motion.camera;
    check("camera defaults leave a configured hole exactly as it was",
        base.enabled === "auto" && base.direction === "out" && base.speed === 6
        && base.depth === 16 && base.dustFlow === 3 && base.roll === 0.15
        && base.wander === 0.35 && base.sizeGain === 0.55,
        JSON.stringify(base));
    const bad = Rules.validateDocument({motion: {camera: {enabled: "yes", direction: "sideways",
        speed: 1e6, depth: -3, dustFlow: "3", roll: 99, wander: null, sizeGain: 4}}}).motion.camera;
    check("every camera bound clamps or falls back, none of them throw",
        bad.enabled === "auto" && bad.direction === "out" && bad.speed === 30 && bad.depth === 2
        && bad.dustFlow === 3 && bad.roll === 2 && bad.wander === 0.35 && bad.sizeGain === 1,
        JSON.stringify(bad));
    const on = Rules.validateDocument({motion: {camera: {enabled: false, direction: "in", speed: 0}}}).motion.camera;
    check("the regime and the direction are both explicit switches",
        on.enabled === false && on.direction === "in" && on.speed === 0);
}

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
