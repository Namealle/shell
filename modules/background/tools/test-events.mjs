#!/usr/bin/env node
// Node tests + audit for the EVENT half of the starfield.
//   node modules/background/tools/test-events.mjs               # tests
//   node modules/background/tools/test-events.mjs --audit        # rate table, defaults
//   node modules/background/tools/test-events.mjs --audit FILE   # rate table for a config
//
// The scheduler is NOT re-implemented here. The functions are lifted verbatim
// out of modules/background/Starfield.qml (QML type annotations stripped from
// the signature line only) and run against a host object that supplies the
// same properties the QML root supplies, so this exercises the shipped code.
// Configuration goes through services/ambient/rules.js unchanged, exactly as
// the shell's FileView does.
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFileSync } from "fs";
import { createRequire } from "module";
import vm from "vm";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const QML = join(root, "modules", "background", "Starfield.qml");
const RULES = join(root, "services", "ambient", "rules.js");
const require = createRequire(import.meta.url);
const ParticlePhysics = require(join(root, "modules", "background", "particles", "Physics.js"));

// ---------------------------------------------------------------- rules.js
const rulesContext = vm.createContext({ Math, JSON, isFinite, Number, Object, Array, console });
vm.runInContext(readFileSync(RULES, "utf8") + "\nthis.validateDocument = validateDocument;", rulesContext);
const validateDocument = rulesContext.validateDocument;

// ---------------------------------------------------------------- extraction
const qml = readFileSync(QML, "utf8");
function extract(name) {
    const head = qml.indexOf("\n    function " + name + "(");
    if (head < 0) throw new Error("no function " + name + " in Starfield.qml");
    const open = qml.indexOf("{", head);
    let depth = 0, i = open;
    for (; i < qml.length; ++i) {
        if (qml[i] === "{") depth++;
        else if (qml[i] === "}" && --depth === 0) break;
    }
    const signature = qml.slice(head + 1, open).replace(/\s*:\s*[A-Za-z_$][\w$]*/g, "");
    const args = signature.slice(signature.indexOf("("), signature.lastIndexOf(")") + 1);
    return "host[\"" + name + "\"] = function " + args + " " + qml.slice(open, i + 1) + ";";
}

const NAMES = ["clamp", "modulo", "random", "ease", "normalized", "parameterRange", "paletteSnapshot", "phenomenon", "moodState", "eventOff", "eventConfig", "eventEnabled", "familyDefaults", "cometLook", "chooseFamily", "captureEvent", "classifyCapture", "schedule", "rateScale", "holeReach", "radialPlacement", "captureRadial", "radialSchedule", "dramatic", "warmStart", "scheduleRadial", "radialState", "eventPath", "eventState", "cometState", "pushEvent", "drainPending", "publishEvents", "publishPhenomena"];

// Readonly root constants the scheduler reads by bare name, taken from the
// same source rather than restated here.
function constants() {
    const out = {};
    const re = /readonly property (?:int|real|var) (\w+): (.+)/g;
    let m;
    while ((m = re.exec(qml))) {
        try { out[m[1]] = JSON.parse(m[2].replace(/'/g, '"')); } catch (e) { /* not a literal */ }
    }
    return out;
}

export function scheduler(host) {
    Object.assign(host, constants());
    // Sloppy mode: `with` resolves the QML root's bare property names onto the
    // host, which is exactly how the QML engine resolves them. The functions
    // are ASSIGNED, never declared, so a cross-call resolves through the host
    // at call time and a test may replace one.
    const make = new Function("host", "with (host) { " + NAMES.map(extract).join("\n") + " }");
    make(host);
    return host;
}

// ---------------------------------------------------------------- host
const Qt = {
    vector2d: (x, y) => ({ x, y }),
    vector4d: (x, y, z, w) => ({ x, y, z, w })
};

export function makeHost(document, options) {
    const o = options || {};
    const w = o.width === undefined ? 1440 : o.width;
    const h = o.height === undefined ? 2560 : o.height;
    // His live hole: preset "target", size 0.11, lensReach 8, disk 3..11 Rs,
    // arcs off. The keep-out is measured against what that actually draws.
    const holeSize = o.holeSize === undefined ? 0.11 : o.holeSize;
    const holeRadius = o.holeRadius === undefined ? holeSize * Math.min(w, h) : o.holeRadius;
    const shader = {
        centreOffset: { x: 0, y: 0 },
        mood: Qt.vector4d(0, 0, 0, 0)
    };
    const host = {
        Qt, Math, Number, Array, Object, JSON, console, ParticlePhysics,
        width: w,
        height: h,
        devicePixelRatio: o.dpr === undefined ? 1 : o.dpr,
        screenSeed: o.screenSeed === undefined ? 12345 : o.screenSeed,
        varietyEnabled: document.variety.enabled,
        varietySeed: document.variety.seed,
        meteorsEnabled: document.meteors.enabled,
        meteorsInterval: Qt.vector2d(document.meteors.interval[0], document.meteors.interval[1]),
        cometEnabled: document.comet.enabled,
        cometInterval: Qt.vector2d(document.comet.interval[0], document.comet.interval[1]),
        satellitesEnabled: document.satellites.enabled,
        satellitesInterval: Qt.vector2d(document.satellites.interval[0], document.satellites.interval[1]),
        companionChance: document.meteors.companionChance,
        fireballChance: document.meteors.fireballChance,
        eventHeadCap: document.events.headCap,
        paletteColors: o.paletteColors || [],
        eventFamilies: {
            comet: document.comet,
            meteors: document.meteors,
            shower: document.events.shower,
            slowWanderer: document.events.slowWanderer,
            starBirth: document.events.starBirth,
            nova: document.events.nova,
            redGiant: document.events.redGiant,
            supernova: document.events.supernova,
            kilonova: document.events.kilonova,
            pulsar: document.events.pulsar,
            gammaBurst: document.events.gammaBurst,
            satelliteGlint: document.events.satelliteGlint,
            phenomena: document.phenomena,
            phenomenonCap: document.events.phenomenonCap,
            dramaCooldownSec: document.events.dramaCooldownSec,
            rateScale: document.events.rateScale,
            phenomenonGainCap: document.events.phenomenonGainCap
        },
        shader,
        _hole: {
            enabled: o.hole !== false,
            bhCentre: { x: w / 2, y: h / 2 },
            bhGeometry: { x: holeRadius, y: holeRadius * 8, z: 0, w: 0 },
            bhDisk: { x: 3, y: 11, z: 0, w: 1 },
            bhArcs: { x: 0, y: 1.75, z: 0.6, w: 0 }
        },
        _state: null
    };
    host._state = {
        clock: 0,
        live: [0.5, 0.5, 0.5, 0.5],
        palette: [],
        events: new Array(12).fill(null),
        eventIds: new Array(12).fill(0),
        familyLast: {},
        moodClock: 0,
        mood: [0, 0, 0, 0],
        phenomenonSlots: [null, null, null],
        firstEpisode: new Array(12).fill(false),
        pendingEvents: []
    };
    return scheduler(host);
}

// ---------------------------------------------------------------- simulation
const KINDS = ["meteors", "comet", "satellites", "shower", "slowWanderer", "starBirth", "nova", "redGiant", "supernova", "pulsar", "kilonova", "gammaBurst"];

export function simulate(host, seconds, step) {
    const dt = step === undefined ? 1 / 30 : step;
    const frames = Math.round(seconds / dt);
    const stat = KINDS.map(name => ({ name, scheduled: 0, drawnFrames: 0, peakGain: 0, peakSigma: 0, peakReach: 0, starved: 0 }));
    const seen = KINDS.map(() => new Set());
    for (let f = 0; f < frames; ++f) {
        host._state.clock = f * dt;
        host._state.moodClock = f * dt;
        host.publishEvents();
        // Slot occupancy, read back off the uniforms the shader would see.
        const drawn = new Set();
        for (let i = 0; i < 6; ++i) {
            const head = host.shader["event" + i + "Head"];
            if (!head || head.w <= 0) continue;
            const colour = host.shader["event" + i + "Colour"];
            const key = i + ":" + Math.round(head.x) + ":" + Math.round(head.y);
            drawn.add(key);
            const kind = host._slotKind ? host._slotKind[i] : -1;
            if (kind >= 0) {
                const s = stat[kind];
                if (!drawn.has("k" + kind)) { s.drawnFrames++; drawn.add("k" + kind); }
                s.peakGain = Math.max(s.peakGain, head.w);
                s.peakSigma = Math.max(s.peakSigma, head.z);
                const b = host.shader["event" + i + "Bounds"];
                s.peakReach = Math.max(s.peakReach, Math.max(b.z - b.x, b.w - b.y) / 2);
            }
        }
        for (let k = 0; k < KINDS.length; ++k) {
            const e = host._state.events[k];
            if (e && !seen[k].has(e.index)) { seen[k].add(e.index); stat[k].scheduled++; }
        }
    }
    // The final scheduled-but-unstarted episode never ran inside the window.
    for (let k = 0; k < KINDS.length; ++k) {
        const e = host._state.events[k];
        if (e && e.start > seconds) stat[k].scheduled--;
        stat[k].perHour = stat[k].scheduled * 3600 / seconds;
        stat[k].drawnSec = stat[k].drawnFrames * dt;
    }
    return stat;
}

// Instrumented publish: record which kind fed which slot. Patched around the
// shipped publishEvents so slot starvation shows up as a kind that schedules
// but never draws.
export function instrument(host) {
    const realState = host.eventState, realRadial = host.radialState;
    host._slotKind = [-1, -1, -1, -1, -1, -1];
    let order = [];
    host.eventState = function (e, branch, companion, segments) {
        const out = realState.call(host, e, branch, companion, segments);
        if (out.head[3] > 0) order.push(e ? kindOf(e) : -1);
        else order.push(-1);
        return out;
    };
    host.radialState = function (e) {
        const out = realRadial.call(host, e);
        return out;
    };
    const realPublish = host.publishEvents;
    host.publishEvents = function () {
        order = [];
        host._slotKind = [-1, -1, -1, -1, -1, -1];
        // A shower's children are kind-0 meteors; credit them to the shower.
        const shower = host._state.events[3];
        if (shower && shower.children)
            for (const child of shower.children) child._shower = true;
        realPublish.call(host);
        for (let i = 0; i < 3; ++i) host._slotKind[i] = order[i] === undefined ? -1 : order[i];
        for (let i = 0; i < 3; ++i) {
            const owner = host._state.phenomenonSlots[i];
            host._slotKind[3 + i] = owner ? owner.kind : -1;
        }
    };
    function kindOf(e) {
        return e._shower ? 3 : e.kind;
    }
    return host;
}

// ---------------------------------------------------------------- reporting
function table(stat, title) {
    console.log("\n" + title);
    console.log("kind            sched/h   drawn s/h   peak gain   peak sigma px   peak reach px");
    for (const s of stat) {
        if (s.scheduled === 0 && s.drawnFrames === 0) {
            console.log(s.name.padEnd(15) + "    0.00        —          off / never");
            continue;
        }
        console.log(s.name.padEnd(15) +
            s.perHour.toFixed(2).padStart(7) + "   " +
            s.drawnSec.toFixed(1).padStart(9) + "   " +
            s.peakGain.toFixed(3).padStart(9) + "   " +
            s.peakSigma.toFixed(2).padStart(13) + "   " +
            s.peakReach.toFixed(1).padStart(13));
    }
}

function audit(configPath) {
    const text = configPath ? readFileSync(configPath, "utf8") : null;
    const document = validateDocument(text ? JSON.parse(text) : null);
    // His three outputs in DEVICE pixels, which is what the shader works in:
    // DP-3 is 3840x2160 rotated at scale 1.5 (logical 1440x2560, device
    // 2160x3840), the tablet is 2880x1800 at scale 2.4, HDMI-A-1 is 1:1.
    const outputs = [
        { name: "DP-3 2160x3840 device", width: 2160, height: 3840 },
        { name: "HDMI-A-1 3440x1440 device", width: 3440, height: 1440 },
        { name: "tablet 2880x1800 device", width: 2880, height: 1800 }
    ];
    console.log("config: " + (configPath || "DEFAULTS"));
    for (const out of outputs) {
        const host = instrument(makeHost(document, out));
        const stat = simulate(host, 3600, 1 / 15);
        table(stat, out.name + "   (one hour, 15 Hz)");
    }
}

// ---------------------------------------------------------------- tests
let failures = 0, checks = 0;
function check(name, ok, detail) {
    ++checks;
    console.log((ok ? "ok    " : "FAIL  ") + name + (detail === undefined ? "" : "   " + detail));
    if (!ok) ++failures;
}

function tests() {
    const document = validateDocument(null);
    // Three hours: an hourly family can miss a one-hour window by luck, and a
    // test that depends on luck is not a test.
    const HOURS = 3;
    const host = instrument(makeHost(document, { width: 1440, height: 2560 }));
    const stat = simulate(host, HOURS * 3600, 1 / 15);
    table(stat, "defaults, DP-3 (" + HOURS + " hours, per hour)");
    const by = {};
    for (const s of stat) { s.drawnSec /= HOURS; by[s.name] = s; }

    // A near-layer star on this buffer: 1.55 px sigma, 0.955 linear peak.
    const STAR_SIGMA = 1.55, STAR_PEAK = 0.955;
    check("meteors fire at least 20/h", by.meteors.perHour >= 20, by.meteors.perHour.toFixed(1) + "/h");
    check("comets fire every 5-15 min", by.comet.perHour >= 4 && by.comet.perHour <= 13, by.comet.perHour.toFixed(1) + "/h");
    check("satellites cross every few minutes", by.satellites.perHour >= 10, by.satellites.perHour.toFixed(1) + "/h");
    check("a satellite is at least as big as a star", by.satellites.peakSigma >= STAR_SIGMA * 0.95, by.satellites.peakSigma.toFixed(2) + " px");
    for (const name of ["starBirth", "nova", "redGiant", "supernova", "pulsar", "kilonova", "gammaBurst"]) {
        check(name + " is scheduled", by[name].perHour > 0, by[name].perHour.toFixed(2) + "/h");
        check(name + " is actually drawn", by[name].drawnFrames > 0, by[name].drawnSec.toFixed(0) + " s/h");
        check(name + " reads bigger than a star", by[name].peakSigma >= STAR_SIGMA * 1.8, by[name].peakSigma.toFixed(2) + " px");
    }
    const notable = ["comet", "starBirth", "nova", "redGiant", "supernova", "pulsar", "kilonova", "gammaBurst"].reduce((a, n) => a + by[n].perHour, 0);
    check("a notable non-meteor event at least every 4 min", notable >= 15, notable.toFixed(1) + "/h");
    check("a nova outshines a bright star", by.nova.peakGain > STAR_PEAK, by.nova.peakGain.toFixed(2));
    check("a supernova outshines a nova", by.supernova.peakGain > by.nova.peakGain, by.supernova.peakGain.toFixed(2));

    // rateScale is the master dial, and 0 means no scheduled events at all.
    for (const scale of [0, 0.5, 2]) {
        const doc = validateDocument({ events: { rateScale: scale } });
        const h2 = instrument(makeHost(doc, { width: 1440, height: 2560 }));
        const st = simulate(h2, 1800, 1 / 10);
        const total = st.reduce((a, s) => a + s.perHour, 0);
        if (scale === 0) check("rateScale 0 fires nothing", total === 0, total.toFixed(1) + "/h");
        else check("rateScale " + scale + " scales the catalogue", total > 0, total.toFixed(1) + "/h");
    }
    {
        const doc = validateDocument(null);
        const h2 = makeHost(doc, { width: 1440, height: 2560 });
        h2._state.clock = 10;
        check("pushEvent queues an episode", h2.pushEvent("kilonova", 0, {}) && h2._state.pendingEvents.length === 1);
        h2._state.events[10] = null;
        h2.drainPending();
        const landed = h2._state.events[10];
        check("drainPending lands it on its family", !!landed && landed.kind === 10 && Math.abs(landed.start - 10) < 0.001);
        check("the queue is then empty", h2._state.pendingEvents.length === 0);
        check("pushEvent rejects an unknown family", h2.pushEvent("nope", 0, {}) === false);
        for (let i = 0; i < 8; ++i) h2.pushEvent("nova", 60, {});
        check("the queue is bounded", h2._state.pendingEvents.length <= 4, String(h2._state.pendingEvents.length));
    }

    // Anti-strobe: no phenomenon may step more than the nova's own rise slope
    // between two 30 Hz frames. Proven by sampling, not asserted.
    {
        const doc = validateDocument(null);
        const h2 = instrument(makeHost(doc, { width: 1440, height: 2560, screenSeed: 99 }));
        const dt = 1 / 30;
        // Each family's own eased-rise floor: 0.8 s for the slow phenomena,
        // 0.35 s for the two sub-second bursts. A smoothstep to peak P over T
        // seconds cannot exceed 1.5*P/T per second, so the per-frame bound is
        // 0.05*P/T. Proven by sampling every published frame, not asserted.
        const FLOOR = { 5: 0.8, 6: 0.8, 7: 0.8, 8: 0.8, 9: 0.8, 10: 0.35, 11: 0.35 };
        const worst = {}, last = [0, 0, 0, 0, 0, 0], held = [0, 0, 0, 0, 0, 0], top = {};
        for (let f = 0; f < Math.round(3 * 3600 / dt); ++f) {
            h2._state.clock = f * dt;
            h2._state.moodClock = f * dt;
            h2.publishEvents();
            for (let i = 3; i < 6; ++i) {
                const g = h2.shader["event" + i + "Head"].w;
                const owner = h2._state.phenomenonSlots[i - 3];
                const kind = owner ? owner.kind : -1;
                // An arrival, a departure or a handover is not a step.
                if (kind >= 0 && kind === held[i] && last[i] > 0 && g > 0) {
                    const step = Math.abs(g - last[i]);
                    if (!(worst[kind] >= step)) worst[kind] = step;
                }
                top[kind] = Math.max(top[kind] || 0, g);
                held[i] = kind;
                last[i] = g;
            }
        }
        for (const kind of Object.keys(FLOOR)) {
            const bound = 0.05 * (top[kind] || 1) / FLOOR[kind];
            const seen = worst[kind] || 0;
            check("kind " + kind + " never steps faster than its eased rise floor",
                seen <= bound * 1.05, seen.toFixed(4) + " <= " + bound.toFixed(4) + " per frame");
        }
    }
    // Placement. His live hole is preset "target": size 0.11 of the short side
    // and lensReach 8. v6 excluded 1.6 x the LENSING reach, 12.8 Rh, which on
    // every one of his three outputs covers the whole buffer - so radialPlacement
    // returned null every time and no phenomenon was ever placed anywhere.
    for (const out of [
        { name: "DP-3 2160x3840", width: 2160, height: 3840 },
        { name: "HDMI-A-1 3440x1440", width: 3440, height: 1440 },
        { name: "tablet 2880x1800", width: 2880, height: 1800 }
    ]) {
        const h2 = makeHost(validateDocument(null), out);
        let placed = 0;
        for (let i = 0; i < 400; ++i) if (h2.radialPlacement(i, 4321)) placed++;
        check("a phenomenon can be placed on " + out.name, placed >= 396, placed + "/400 captures found a spot");
        // And never on the drawn material.
        const reach = h2.holeReach();
        let inside = 0;
        for (let i = 0; i < 400; ++i) {
            const p = h2.radialPlacement(i, 99);
            if (p && Math.hypot(p[0] - out.width / 2, p[1] - out.height / 2) < reach) inside++;
        }
        check("no placement lands on the drawn hole on " + out.name, inside === 0, inside + " inside " + reach.toFixed(0) + " px");
    }
    // v9 WARM START. v8 scheduled every family's FIRST episode a full random
    // interval after the shell started, so a restart put the supernova 21-48
    // minutes away and the first minutes of every session were guaranteed to
    // have nothing dramatic in them. These bounds are the fix, pinned.
    {
        // Minimum interval per family at rateScale 1, in active seconds, from
        // the shipped defaults: the warm window is [0.3, 1] x this.
        const MIN = [45, 300, 150, 2700, 2700, 480, 360, 1080, 1800, 1800, 2160, 2520];
        const firsts = [];
        for (let seed = 1; seed <= 24; ++seed) {
            const h2 = makeHost(validateDocument(null), { screenSeed: seed * 977, width: 2880, height: 1800, hole: false });
            // A few frames, so a family whose placement was rejected once still
            // gets its first episode inside the window.
            for (let f = 0; f < 4; ++f) { h2._state.clock = f / 30; h2.publishEvents(); }
            firsts.push(h2._state.events.map(e => (e ? e.start : Infinity)));
        }
        let radialBad = 0, transientBad = 0, dramaLate = 0, dramaClose = 0;
        for (const row of firsts) {
            for (let k = 5; k < 12; ++k) {
                const cap = (k === 8 || k === 10 || k === 11) ? 240 : Infinity;
                // The dramatic cap overrides the window's own lower bound: a
                // 30-60 minute family capped at four minutes lands AT the cap.
                const lo = Math.min(0.3 * MIN[k], cap), hi = Math.min(MIN[k], cap);
                // Kilonova and burst queue a dramatic cooldown behind the
                // supernova, which is exactly the rule being kept.
                const queued = (k === 10 || k === 11) && row[k] >= row[8] + 900 - 1;
                if (!queued && !(row[k] >= lo - 1e-6 && row[k] <= hi + 1e-6)) radialBad++;
            }
            for (let k = 0; k < 5; ++k)
                if (!(row[k] >= 0.3 * MIN[k] - 1e-6 && row[k] <= MIN[k] + 400)) transientBad++;
            const drama = Math.min(row[8], row[10], row[11]);
            if (!(drama <= 240 + 1e-6)) dramaLate++;
            const sorted = [row[8], row[10], row[11]].sort((a, b) => a - b);
            if (sorted[1] - sorted[0] < 900 - 1 || sorted[2] - sorted[1] < 900 - 1) dramaClose++;
        }
        check("every phenomenon's first episode lands in its warm-start window", radialBad === 0, radialBad + " outside over 24 seeds");
        check("every transient's first episode lands in its warm-start window", transientBad === 0, transientBad + " outside over 24 seeds");
        check("something dramatic is scheduled inside the first four minutes", dramaLate === 0, dramaLate + " seeds without one");
        check("the dramatic cooldown still spaces the warm-started families", dramaClose === 0, dramaClose + " seeds too close");
        // rateScale moves the first occurrence with everything else.
        const fast = makeHost(validateDocument({ events: { rateScale: 2 } }), { screenSeed: 4242, width: 2880, height: 1800, hole: false });
        for (let f = 0; f < 4; ++f) { fast._state.clock = f / 30; fast.publishEvents(); }
        const slow = makeHost(validateDocument({ events: { rateScale: 0.5 } }), { screenSeed: 4242, width: 2880, height: 1800, hole: false });
        for (let f = 0; f < 4; ++f) { slow._state.clock = f / 30; slow.publishEvents(); }
        check("rateScale applies to the first occurrence too",
            fast._state.events[5].start <= 480 / 2 + 1e-6 && slow._state.events[5].start <= 480 * 2 + 1e-6
            && fast._state.events[5].start < slow._state.events[5].start,
            "starBirth first at " + fast._state.events[5].start.toFixed(1) + " s (2x) vs " + slow._state.events[5].start.toFixed(1) + " s (0.5x)");
        check("rateScale moves the dramatic cap as well", fast._state.events[8].start <= 120 + 1e-6,
            "supernova first at " + fast._state.events[8].start.toFixed(1) + " s at rateScale 2");
        // A retired phenomenon reschedules on the ORDINARY interval, not on the
        // warm window: the warm start is a per-process first, never a loop.
        {
            const h2 = makeHost(validateDocument(null), { screenSeed: 31337, width: 2880, height: 1800, hole: false });
            h2._state.clock = 0;
            h2.publishEvents();
            const first = h2._state.events[8].start;
            h2._state.events[8] = null;
            h2.publishEvents();
            check("a retired family does not warm-start twice", h2._state.events[8].start >= 1800 - 1e-6,
                "first " + first.toFixed(1) + " s, reschedule " + h2._state.events[8].start.toFixed(1) + " s");
        }
    }
    console.log("\n" + (failures ? failures + " failures" : "all " + checks + " checks passed"));
    return failures;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
    if (process.argv[2] === "--audit") audit(process.argv[3]);
    else process.exit(tests() ? 1 : 0);
}
