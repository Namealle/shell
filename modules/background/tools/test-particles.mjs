#!/usr/bin/env node
// Node tests for the particle CPU half. Run from anywhere:
//   node modules/background/tools/test-particles.mjs
// The four particles/*.js modules are plain CommonJS under their QML guard, so
// they load here unchanged and run the same code the shell runs.
import { createRequire } from "module";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const require = createRequire(import.meta.url);
const particles = join(dirname(fileURLToPath(import.meta.url)), "..", "particles");
const Physics = require(join(particles, "Physics.js"));
const Appearance = require(join(particles, "Appearance.js"));
const Binning = require(join(particles, "Binning.js"));
const Packing = require(join(particles, "Packing.js"));

const W = 2160, H = 3840, RH = 0.11 * 2160, DT = 1 / 30;
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
        (p, i) => Appearance.birth(p, i, input));
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
// The bug this replaced: a star crossing streak.bendRadiusRh had its exposure
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
            const b = j * S, r = radiusOf(d, b) / RH;
            if (r > 1.55 && r < 1.65) shell.push(d[b + ISTRETCH]);
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
    // deforms them whatever the mass is, and the capture shell sits at 3.3-4 Rh.
    function profile(mass) {
        const sum = new Array(12).fill(0), count = new Array(12).fill(0);
        simulate({config: {mass, streak: {bendMaxAlive: 3200}}, measureSec: 20, visit: items => {
            const d = items.data;
            for (let j = 0; j < items.count; ++j) {
                const b = j * S, bin = Math.floor(radiusOf(d, b) / RH * 2);
                if (bin < 12 && d[b + 15] < 0.01) { sum[bin] += d[b + ISTRETCH]; ++count[bin]; }
            }
        }});
        return sum.map((v, i) => count[i] ? v / count[i] : 0);
    }
    const light = profile(0.5), heavy = profile(3);
    // The reach is bendRadiusRh * cbrt(mass) * the star's own onset scale, so
    // 2.4 Rh becomes 1.9 Rh at mass 0.5 and 3.5 Rh at mass 3. Bins 8 and 9 are
    // 4.0-5.0 Rh: past every light-hole onset, inside the heavy hole's widest.
    const far = a => (a[8] + a[9]) / 2;
    check("a heavier hole reaches further out", far(heavy) > 0.02 && far(light) < 0.005,
        `4-5 Rh: mass 0.5 -> ${far(light).toFixed(4)}, mass 3 -> ${far(heavy).toFixed(4)}`);
    // Inside about 2 Rh the response saturates for both, so mass shows up as
    // reach and as the total deformation carried, not as a deeper floor.
    check("a heavier hole deforms harder everywhere it is not already saturated",
        heavy.slice(4, 12).every((v, i) => v >= light[i + 4] - 1e-6),
        `2-6 Rh heavy ${heavy.slice(4, 12).map(v => v.toFixed(3)).join(",")} light ${light.slice(4, 12).map(v => v.toFixed(3)).join(",")}`);
    const outer = a => a.slice(5).reduce((x, y) => x + y, 0);
    check("mass scales how much of the field is deformed at all",
        outer(heavy) > 2 * outer(light),
        `2.5 Rh outward: heavy ${outer(heavy).toFixed(3)} light ${outer(light).toFixed(3)}`);
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
                ceiling = Packing.capacity(bins, c.maxItems, c.maxSupport, c.maxFlares, c.flareSupport, c.maxBends, c.bendSupport);
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

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
