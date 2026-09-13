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
const TARGET_DISK = {innerRs: 3, outerRs: 10.5, arcGain: 0.013, arcRadiusRh: 1.6, arcSpacingRh: 0.55, arcCount: 4};
{
    // The geometry mirrors bhOuter()/bhImpact()/bhArcReach() in blackhole.glsl.
    // If that file moves, these pin the drift.
    const r = Physics.visibleRadius(RH, TARGET_DISK);
    check("the shadow is Rh, and the disk and the arcs are separate radii outside it",
        Math.abs(r.shadow / RH - 1) < 1e-9 && Math.abs(r.disk / RH - 3.567) < 0.01
        && Math.abs(r.arcs / RH - 3.900) < 0.01,
        `shadow ${(r.shadow / RH).toFixed(3)}, disk ${(r.disk / RH).toFixed(3)}, arcs ${(r.arcs / RH).toFixed(3)} Rh`);
    check("the v4 default disk gives a smaller material rim, still outside the shadow",
        Math.abs(RIM / RH - 2.783) < 0.01 && RIM > SHADOW, `${(RIM / RH).toFixed(3)} Rh`);
    check("a disk that draws no arcs reports no reach past its material edge",
        Math.abs(Physics.visibleRadius(RH, {innerRs: 3, outerRs: 10.5, arcGain: 0}).arcs / RH - 3.567) < 0.01);
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

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
