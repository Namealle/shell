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

const NAMES = ["clamp", "modulo", "random", "ease", "normalized", "parameterRange", "paletteSnapshot", "phenomenon", "moodState", "eventOff", "lightCurveAt", "meteorToneVector", "eventConfig", "eventEnabled", "familyDefaults", "cometLook", "chooseFamily", "captureEvent", "classifyCapture", "schedule", "rateScale", "holeReach", "radialPlacement", "captureRadial", "radialSchedule", "dramatic", "warmStart", "scheduleRadial", "mixColour", "linearGain", "supernovaShellReach", "supernovaEjecta", "cfgShockSpeed", "supernovaParticles", "supernovaSite", "supernovaState", "radialState", "eventPath", "cometHead", "eventState", "cometState", "cometRatio", "cometTurn", "cometParticles", "pushEvent", "drainPending", "publishEvents", "publishPhenomena", "stormValue", "stormTrailAngle", "captureStorm", "stormRate", "stormPhase", "stormRadiant", "stormState", "stormOff", "stormFireballState", "stormFireballParticles", "farBoost", "nebulaConfig", "nebulaEnabled", "nebulaFlowRate", "nebulaDrift", "nebulaBoundary", "nebulaDriftPerSec", "nebulaReach", "nebulaSink", "captureNebula", "scheduleNebula", "nebulaState", "pushNebula", "publishNebula"];

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
        dustParallax: { x: 0, y: 0 },
        flowZoom: { x: 1, y: 1, z: 1 },
        mood: Qt.vector4d(0, 0, 0, 0),
        // The nebula block's QML defaults. publishNebula reads the published
        // gain back to skip a redundant write, so the host has to start where
        // the ShaderEffect's properties start.
        nebulaHead: Qt.vector4d(0, 0, 0, 0),
        nebulaShape: Qt.vector4d(1, 0, 1, 0),
        nebulaTone0: Qt.vector4d(0, 0, 0, 0),
        nebulaTone1: Qt.vector4d(0, 0, 0, 0),
        nebulaStars: Qt.vector4d(-1000000, -1000000, -1000000, -1000000),
        nebulaStars2: Qt.vector4d(-1000000, -1000000, 1, 1),
        nebulaBounds: Qt.vector4d(0, 0, 0, 0)
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
        // The nebula reads the regime directly: 0 is the inward stream, 1 the
        // camera flying out. Both are live properties in QML, so a test sets
        // them the way the shell would rather than through a config key.
        _cameraBlend: o.cameraBlend === undefined ? 0 : o.cameraBlend,
        _cameraOutward: o.cameraOutward === undefined ? 0 : o.cameraOutward,
        cameraDustFlow: o.cameraDustFlow === undefined ? 3 : o.cameraDustFlow,
        radialSpeed: o.radialSpeed === undefined ? 6 : o.radialSpeed,
        particlesEnabled: o.particlesEnabled !== false,
        _particles: o.particles === undefined ? { config: { dust: { farFlow: 24 }, mass: 1 } } : o.particles,
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
            nebula: document.events.nebula,
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
            bhHalo: { x: 0, y: 0, z: 0, w: o.hole === false ? 0 : 1 },
            bhDisk: { x: 3, y: 11, z: 0, w: 1 },
            bhArcs: { x: 0, y: 1.75, z: 0.6, w: 0 }
        },
        _state: null
    };
    host._state = {
        clock: 0,
        live: [0.5, 0.5, 0.5, 0.5],
        palette: [],
        camFlow: 0,
        events: new Array(12).fill(null),
        eventIds: new Array(12).fill(0),
        familyLast: {},
        moodClock: 0,
        mood: [0, 0, 0, 0],
        phenomenonSlots: [null, null, null],
        firstEpisode: new Array(12).fill(false),
        pendingEvents: [],
        geo: [0, 0, 0],
        nebula: null,
        nebulaPending: null,
        nebulaId: 0,
        nebulaLast: null
    };
    return scheduler(host);
}

// ---------------------------------------------------------------- simulation
const KINDS = ["meteors", "comet", "satellites", "shower", "slowWanderer", "starBirth", "nova", "redGiant", "supernova", "pulsar", "kilonova", "gammaBurst"];
// The nebula passage has no slot and no place in s.events, so it is counted
// beside the table rather than in it.
const NEBULA = "nebula";

export function simulate(host, seconds, step) {
    const dt = step === undefined ? 1 / 30 : step;
    const frames = Math.round(seconds / dt);
    const stat = KINDS.map(name => ({ name, scheduled: 0, drawnFrames: 0, peakGain: 0, peakSigma: 0, peakReach: 0, starved: 0 }));
    const seen = KINDS.map(() => new Set());
    const nebula = { name: NEBULA, scheduled: 0, drawnFrames: 0, peakGain: 0, peakSigma: 0, peakReach: 0, starved: 0 };
    const nebulaSeen = new Set();
    for (let f = 0; f < frames; ++f) {
        host._state.clock = f * dt;
        host._state.moodClock = f * dt;
        // One flow second per active second at the shipped radialSpeed: the
        // passage reads the same accumulator advance() writes.
        host._state.geo[0] = f * dt;
        host.publishEvents();
        host.publishNebula();
        const head = host.shader.nebulaHead;
        if (head && head.w > 0) {
            nebula.drawnFrames++;
            nebula.peakGain = Math.max(nebula.peakGain, head.w);
            nebula.peakSigma = Math.max(nebula.peakSigma, head.z);
            const nb = host.shader.nebulaBounds;
            nebula.peakReach = Math.max(nebula.peakReach, Math.max(nb.z - nb.x, nb.w - nb.y) / 2);
        }
        const live = host._state.nebula;
        if (live && !nebulaSeen.has(live.index)) { nebulaSeen.add(live.index); nebula.scheduled++; }
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
        // v9: the storm draws through its OWN block, not through a slot, so
        // slot occupancy cannot see it and the shower's row read 0 s/h for a
        // family that is on screen for a minute and a half at a time. Its
        // fireballs still take slots and are still counted there.
        const stormShape = host.shader.stormShape;
        if (stormShape && stormShape.w > 0) {
            const s = stat[3];
            s.drawnFrames++;
            const sh = host.shader.stormHead;
            s.peakGain = Math.max(s.peakGain, stormShape.w);
            s.peakSigma = Math.max(s.peakSigma, stormShape.x);
            if (sh) s.peakReach = Math.max(s.peakReach, Math.max(host.width, host.height) / 2);
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
    const pending = host._state.nebula;
    if (pending && pending.start > seconds) { nebula.scheduled--; nebula.nextAt = pending.start; }
    nebula.perHour = nebula.scheduled * 3600 / seconds;
    nebula.drawnSec = nebula.drawnFrames * dt;
    stat.push(nebula);
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
            // A family can be off, or simply slower than the window: the
            // nebula's 20-45 min interval starts behind the shared dramatic
            // cooldown, so the first passage can land past the hour.
            const late = s.nextAt !== undefined ? "due at " + (s.nextAt / 60).toFixed(1) + " min" : "off / never";
            console.log(s.name.padEnd(15) + "    0.00        —          " + late);
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
        // v9: overriding one phase of a supernova recomputes its duration, so
        // `fire supernova tablet '{"shellSpan":20}'` is a shorter shell rather
        // than a life cycle truncated in the middle of a phase.
        {
            h2._state.pendingEvents = [];
            h2.pushEvent("supernova", 0, { precursor: 4, shellSpan: 20, remnant: 40 });
            const fired = h2._state.pendingEvents[h2._state.pendingEvents.length - 1];
            check("a fired supernova recomputes its duration from the overrides",
                !!fired && Math.abs(fired.duration - (4 + fired.rise + fired.hold + 20 + 40)) < 1e-9,
                fired ? fired.duration.toFixed(2) + " s" : "not queued");
        }
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
        // v9's supernova asks for a 0.12 short-side margin so a 0.20 short-side
        // shell is not half off the screen. With his hole on that is a much
        // smaller acceptance region, so it is measured rather than assumed.
        let wide = 0;
        for (let i = 0; i < 400; ++i) if (h2.radialPlacement(i, 777, 0.12)) wide++;
        check("a supernova can be placed on " + out.name, wide >= 396, wide + "/400 captures found a spot at a 0.12 margin");
        // And it PREFERS a spot its whole shell clears, falling back to the
        // plain keep-out when there is nowhere that does.
        const pad = 0.5 * 0.40 * Math.min(out.width, out.height);
        let padded = 0;
        for (let i = 0; i < 400; ++i) if (h2.radialPlacement(i, 555, 0.12, pad)) padded++;
        check("the shell-wide keep-out is preferred where it fits on " + out.name, padded > 0,
            (padded / 4).toFixed(1) + " % of captures clear the hole by the whole shell");
    }
    // v9 WARM START. v8 scheduled every family's FIRST episode a full random
    // interval after the shell started, so a restart put the supernova 21-48
    // minutes away and the first minutes of every session were guaranteed to
    // have nothing dramatic in them. These bounds are the fix, pinned.
    {
        // Minimum interval per family at rateScale 1, in active seconds, from
        // the shipped defaults: the warm window is [0.3, 1] x this. Kind 3 is
        // 0.42 h since the v9 storm widened `shower.everyHours` to [0.42, 1].
        const MIN = [45, 300, 150, 1512, 2700, 480, 360, 1080, 1800, 1800, 2160, 2520];
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
    // v9 SUPERNOVA: the life cycle. A force-fired v8 supernova on his tablet was
    // a ~40 px dot with a soft halo; these bounds are what replaced it.
    {
        const h2 = makeHost(validateDocument(null), { width: 2880, height: 1800, screenSeed: 20260913, hole: false });
        let e = null;
        for (let a = 0; a < 40 && !e; ++a) e = h2.captureRadial(8, a, 0);
        check("a supernova captures four phases", !!e && e.precursor >= 10 && e.precursor <= 20
            && e.shellSpan >= 30 && e.shellSpan <= 90 && e.remnant >= 120 && e.remnant <= 300,
            e ? "precursor " + e.precursor.toFixed(1) + " s, shell " + e.shellSpan.toFixed(1)
                + " s, remnant " + e.remnant.toFixed(1) + " s, total " + e.duration.toFixed(1) + " s" : "no capture");
        // The whole life cycle fits inside the dramatic cooldown, which is what
        // makes "one supernova at a time" a fact rather than a hope: the four
        // extra uniform vectors live outside the slot on exactly that basis.
        check("the life cycle fits inside the dramatic cooldown", e.duration < 900,
            e.duration.toFixed(1) + " s < 900 s");
        // Sizes, in SHORT SIDES across, against the brief: flash 8-12 %, shell
        // 25-40 %. Both keys are diameters, so this is the captured value.
        // v11 halved the flash. Requirement A allows a hard core of 3-6 % and a
        // bloom to about 10 %: 0.15-0.25 put the bloom's 64/255 disc at a fifth
        // of the screen's short side, which with the sky lift gone was the only
        // thing left that could still read as the screen flashing. Measured on
        // the shipped envelope by tools/sn_bloom.mjs: peak 9.1 % for 0.35 s,
        // hard core 3.4 %.
        const shortSide = 1800;
        check("the flash is 8-12 % of the short side across", 2 * e.flash / shortSide >= 0.08 && 2 * e.flash / shortSide <= 0.12,
            (2 * e.flash / shortSide * 100).toFixed(1) + " % (" + (2 * e.flash).toFixed(0) + " px)");
        check("the shell reaches 25-40 % of the short side across", 2 * e.shell / shortSide >= 0.25 && 2 * e.shell / shortSide <= 0.40,
            (2 * e.shell / shortSide * 100).toFixed(1) + " % (" + (2 * e.shell).toFixed(0) + " px)");
        // Every channel is continuous at 30 Hz, not only the total: a phase
        // handover that steps in the halo sigma or in the colour is a visible
        // cut even when head.w never moves. The bound on each is generous
        // compared with a cut and tight compared with a phase change.
        const dt = 1 / 30;
        let worst = { channel: "", step: 0, at: 0 };
        let previous = null;
        const limits = { gain: 0.09, sigma: 0.06, colour: 0.10, radius: 0.06 };
        for (let f = 0; f * dt <= e.duration; ++f) {
            h2._state.clock = e.start + f * dt;
            const s = h2.radialState(e);
            const x = s.extras || { remnant: [0, 0, 0, 0], tone: [0, 0, 0, 0], shell: [0, 0, 0, 0], extra: [0, 0, 0, 0] };
            const now = {
                // Absolute gains, so a change of the peak that the fractions
                // exactly cancel is correctly read as no change at all.
                gain: s.head[3] * (s.tail01[1] + s.tail01[2]),
                shell: s.head[3] * s.tail01[3],
                shock: x.shell[1],
                inner: x.shell[3],
                spike: s.head[3] * x.extra[0],
                sigma: s.head[2] / 100,
                halo: s.tail01[0] / 100,
                radius: s.shape[0] / 1000,
                nebulaR: x.remnant[2] / 1000,
                shockW: x.shell[2] / 1000,
                colourR: s.colour[0],
                colourG: s.colour[1],
                colourB: s.colour[2],
                // v11: `lift` was the sky lift's gain and is gone. The remnant's
                // own body gain took the vector and is the channel worth the
                // same continuity check -- it is what draws the gas.
                body: x.remnant[3]
            };
            if (previous && s.head[3] > 0 && previous.gain + previous.shell + previous.nebula > 0)
                for (const key of Object.keys(now)) {
                    const step = Math.abs(now[key] - previous[key]);
                    const limit = key.startsWith("colour") ? limits.colour
                        : key === "sigma" || key === "halo" ? limits.sigma
                            : key === "radius" || key === "nebulaR" || key === "shockW" ? limits.radius : limits.gain;
                    if (step > limit && step / limit > worst.step) worst = { channel: key, step: step / limit, at: f * dt, value: step, limit };
                }
            previous = s.head[3] > 0 ? now : null;
        }
        check("no channel of the life cycle steps between two frames", worst.step === 0,
            worst.step ? worst.channel + " stepped " + worst.value.toFixed(4) + " (limit " + worst.limit + ") at " + worst.at.toFixed(2) + " s" : "13 channels, " + Math.round(e.duration * 30) + " frames");
        // v11, requirement A. There is no absolute term left. The v9/v10 sky
        // lift lived on this vector and reached every pixel of the screen; what
        // replaced it is the remnant's own frame, and the strongest thing that
        // can be said about the whole episode from the CPU side is that nothing
        // it ever publishes reaches outside the bounds box the shader rejects
        // on. Swept over the life cycle at 30 Hz. The cap is a third of the
        // SHORT side -- 600 px here, against the 1584 px radius the lift used to
        // cover and a screen half-diagonal of 1698 px.
        let widest = 0, widestAt = 0, anyDrawn = 0;
        for (let f = 0; f * dt <= e.duration; ++f) {
            h2._state.clock = e.start + f * dt;
            const s2 = h2.radialState(e);
            if (!(s2.head[3] > 0)) continue;
            ++anyDrawn;
            const reach = Math.max(s2.bounds[2] - s2.head[0], s2.bounds[3] - s2.head[1]);
            if (reach > widest) { widest = reach; widestAt = f * dt; }
        }
        check("nothing the episode publishes reaches outside its own box",
            anyDrawn > 0 && widest > 0 && widest <= shortSide / 3,
            "widest reach " + widest.toFixed(0) + " px at t+" + widestAt.toFixed(0) + " s = "
            + (widest / shortSide).toFixed(3) + " of the short side, over " + anyDrawn + " drawn frames");
        // Sedov: r ~ t^0.4 within the shell phase, measured off the published
        // radius rather than asserted from the source.
        // v10: the shell's clock starts at the DETONATION, which is where the
        // debris starts too. supernovaParticles drives the shock front off the
        // same number.
        const at = (u) => {
            h2._state.clock = e.start + e.precursor + u * e.shellSpan;
            return h2.radialState(e).shape[0];
        };
        const r1 = at(0.2), r2 = at(0.8);
        const exponent = Math.log(r2 / r1) / Math.log(4);
        check("the shell decelerates on the Sedov exponent", Math.abs(exponent - 0.4) < 0.02,
            "r ~ t^" + exponent.toFixed(3) + " over u 0.2 -> 0.8");
        check("the shell reaches its captured radius", Math.abs(at(1) - e.shell) < 1,
            at(1).toFixed(1) + " px of " + e.shell.toFixed(1));
        // The site travels with the far layer in the camera regime and is fixed
        // with the hole on, which is what every other phenomenon does.
        {
            h2._state.clock = e.start + 30;
            const still = h2.radialState(e).head.slice(0, 2);
            h2._state.camFlow = -400;        // 400 flow seconds of camera "out"
            const moved = h2.radialState(e).head.slice(0, 2);
            const centre = [1440, 900];
            const r0 = Math.hypot(still[0] - centre[0], still[1] - centre[1]);
            const r1c = Math.hypot(moved[0] - centre[0], moved[1] - centre[1]);
            // u = r^2/(2R^2) advances by -flow*(6/1080)*0.10, so the drifted
            // radius is exactly R*sqrt(2u). This checks the law, not a number.
            const R = 900, u = 0.5 * (r0 / R) * (r0 / R) + 400 * (6 / 1080) * 0.10;
            check("the supernova drifts on the far layer's own streamline",
                Math.abs(r1c - R * Math.sqrt(2 * u)) < 0.5 && r1c > r0 + 10,
                r0.toFixed(1) + " -> " + r1c.toFixed(1) + " px from the centre");
            h2._state.camFlow = 0;
            const back = h2.radialState(e).head.slice(0, 2);
            check("with no camera the site does not move at all",
                back[0] === still[0] && back[1] === still[1], "fixed at " + back.map(x => x.toFixed(1)).join(", "));
        }
        // The extras reach the shader through publishPhenomena, and are zeroed
        // when no supernova is live: a stale snShell would leave a nebula's
        // filament field switched on under another family's slot.
        {
            const h3 = makeHost(validateDocument(null), { width: 2880, height: 1800, screenSeed: 20260913, hole: false });
            let sn = null;
            for (let a2 = 0; a2 < 40 && !sn; ++a2) sn = h3.captureRadial(8, a2, 0);
            sn.start = 0;
            h3._state.events[8] = sn;
            h3._state.clock = 0.5;
            h3.publishPhenomena();
            h3._state.clock = sn.precursor + sn.rise + sn.hold + 20;
            h3.publishPhenomena();
            const NAMES = ["snRemnant", "snTone", "snShell", "snExtra", "snBody", "snHot", "snWisp", "snDust", "snJet",
                "snPop0", "snPop1", "snPop2", "snPop3", "snPop4", "snPop5", "snGrain", "snFlow", "snTurn", "snTurn2"];
            const live = NAMES.map(k => h3.shader[k]);
            check("publishPhenomena publishes the supernova's nineteen extra vectors",
                live.every(v => !!v) && live[0].z > 0 && Math.abs(Math.hypot(live[8].x, live[8].y) - 1) < 1e-9
                && h3.shader.event3Colour.w === 6,
                "style " + h3.shader.event3Colour.w + ", remnant radius " + live[0].z.toFixed(1)
                + " px, jet axis " + live[8].x.toFixed(3) + "," + live[8].y.toFixed(3));
            h3._state.events[8] = null;
            h3._state.phenomenonSlots = [null, null, null];
            h3._state.clock += 1;
            h3.publishPhenomena();
            check("and zeroes them when no supernova is live",
                NAMES.every(k => {
                    const v = h3.shader[k];
                    // snJet's axis rests at (1,0): it is a rotation, and a zero
                    // vector there would be a degenerate frame rather than an
                    // off switch. The two switches are snRemnant.w and snShell.y.
                    if (k === "snJet") return v.x === 1 && v.y === 0 && v.z === 0 && v.w === 0;
                    return v.x === 0 && v.y === 0 && v.z === 0 && v.w === 0;
                }), "all nine cleared");
        }
        // ---- v12: THE GRAIN SCHEDULE ------------------------------------
        // The grains live in the fragment shader, so what can be tested here is
        // the CONTRACT the CPU hands it -- and every one of these is a property
        // the shader relies on rather than a number that happens to be true.
        // KEEP IN STEP with supernovaRemnant()/snSlice() in starfield.frag: the
        // three constants below (the four-wide palette window, the 1.16-cell
        // support bound and the 0.16..0.84 in-cell placement) are copied from
        // it, and if either side moves alone these checks are what notices.
        {
            const WINDOW = 4;          // cA..cD, so an index may sit 0..3 above `base`
            const REACH = 1.16;        // cells: the 3x3 neighbourhood's guaranteed radius
            const g = h2.radialState(e);
            const sample = (age) => {
                h2._state.clock = e.start + age;
                return h2.radialState(e).extras;
            };
            const remnantAt = e.precursor + 0.6 * e.shellSpan;
            const span = 0.4 * e.shellSpan + e.remnant;
            const early = sample(remnantAt + span * 0.10);
            const mid = sample(remnantAt + span * 0.50);
            const late = sample(remnantAt + span * 0.88);
            check("the reverse shock walks INWARD through the remnant",
                early.turn[2] > mid.turn[2] && mid.turn[2] > late.turn[2] && late.turn[2] < 0.4,
                "shock radius " + early.turn[2].toFixed(2) + " -> " + mid.turn[2].toFixed(2)
                + " -> " + late.turn[2].toFixed(2) + " of the rim");
            // The published rate must be the ACTUAL rate, because the shader
            // reconstructs a grain's birth-time schedule position from it. A
            // sign error or a factor here would freeze or reverse the turnover
            // and nothing else would catch it.
            const dt = span * 0.40;
            const measured = (early.turn[2] - mid.turn[2]) / dt;
            check("snTurn2.x is the reverse shock's true speed",
                Math.abs(measured - early.turn2[0]) < 1e-6,
                "published " + early.turn2[0].toFixed(6) + " vs measured "
                + measured.toFixed(6) + " rim radii per second");
            // The whole point: swept material has advanced along the sequence,
            // so the schedule at a fixed radius moves by toneAdvance over the
            // episode. If this is ~0 there is no turnover to see.
            const posAt = (x, u) => x.turn[0] + x.turn[1] * u
                + x.turn[3] * (() => { const s = Math.max(0, Math.min(1, (u - x.turn[2]) * 2.2222222)); return s * s * (3 - 2 * s); })();
            const walk = posAt(late, 0.5) - posAt(early, 0.5);
            check("the schedule walks a whole population or more at mid-radius",
                walk > 1.0, "moved " + walk.toFixed(2) + " populations at u = 0.5");
            // THE WINDOW NEVER CLIPS. The shader hoists four adjacent
            // populations and reconstructs a grain's tone as an offset into
            // them; a grain whose index falls outside gets clamped, and the
            // clamp boundary follows a smooth field's level set, which draws a
            // visible edge. This sweeps the whole episode and the whole radius
            // range with the shader's own arithmetic.
            // The invariant is NOT "the index is inside the window" -- an index
            // past either END of the palette is clipped to the same tone the
            // window's own end already holds, and snPop() clamps identically.
            // What must hold is that the tone the shader RECONSTRUCTS is the
            // tone the schedule asked for:
            //
            //     clamp(base + clamp(idx - base, 0, 3), 0, 5) === clamp(idx, 0, 5)
            //
            // A window that is too narrow, or a `base` that is mis-centred,
            // breaks this in the middle of the palette -- and because `base` is
            // a floor() of a smooth field, the failure is not a stray pixel, it
            // is a hard edge along that field's level set. This sweeps the
            // whole episode, the whole radius range, and both extremes of the
            // per-grain jitter and the birth-time spread.
            const clamp01 = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
            let mismatches = 0, worstAt = "";
            for (let k = 0; k <= 60; ++k) {
                const x = sample(remnantAt + span * (k / 60));
                if (!x || !x.grain || x.grain[0] <= 0) continue;
                const spread = x.flow[3], life = x.grain[2];
                for (let i = 0; i <= 60; ++i) {
                    const u = i / 60;
                    const sx = clamp01((u - x.turn[2]) * 2.2222222, 0, 1);
                    const pos = x.turn[0] + x.turn[1] * u + x.turn[3] * (sx * sx * (3 - 2 * sx));
                    const rate = x.turn[3] * 6 * sx * (1 - sx) * 2.2222222 * x.turn2[0];
                    const base = clamp01(Math.floor(pos - rate * life - spread * 0.5
                        - x.turn[1] * 0.12 + 0.5), 0, 2);
                    // Every corner a grain in this neighbourhood can reach:
                    // freshly born or at the end of its life, and either end of
                    // the jitter.
                    for (const ago of [0, life]) {
                        for (const jit of [-spread * 0.5, 0, spread * 0.5]) {
                            const idx = Math.floor(pos - rate * ago + jit + 0.5);
                            const got = clamp01(base + clamp01(idx - base, 0, WINDOW - 1), 0, 5);
                            const want = clamp01(idx, 0, 5);
                            if (got !== want) {
                                mismatches++;
                                worstAt = "u " + u.toFixed(2) + " t " + (k / 60).toFixed(2)
                                    + " idx " + idx + " base " + base + " -> " + got + " not " + want;
                            }
                        }
                    }
                }
            }
            check("the hoisted window reconstructs every grain's own tone",
                mismatches === 0, mismatches ? mismatches + " mismatches, e.g. " + worstAt
                    : "0 mismatches over 61 ages x 61 radii x 6 corners, window " + WINDOW + " wide");
            // THE 3x3 NEIGHBOURHOOD IS EXACT. A grain sits at its cell plus
            // 0.16..0.84, so the nearest edge of the nine cells is 1.16 away;
            // the shader caps `stretch` at 1.16/rad for exactly this reason,
            // and the cap only works if `rad` itself can never reach 1.16.
            const size = mid.grain[3];
            const radMax = size * (0.55 + 0.75 * 1.0);
            check("a grain's support can never leave the 3x3 neighbourhood",
                radMax < REACH, "largest grain radius " + radMax.toFixed(3)
                + " cells against the " + REACH + " the neighbourhood guarantees");
            check("the curl displacement stays under one cell",
                mid.flow[0] <= 0.5, "curl amplitude " + mid.flow[0].toFixed(3) + " cells");
            const dying = sample(remnantAt + span * 0.99);
            check("grain opacity follows the remnant's own envelope",
                early.turn2[2] > 0 && (!dying || !dying.turn2 || dying.turn2[2] < early.turn2[2]),
                "opacity envelope " + early.turn2[2].toFixed(3) + " -> "
                + ((dying && dying.turn2) ? dying.turn2[2].toFixed(3) : "episode over"));
            // Six populations, all of them actually distinct, all of them with
            // a dust fraction in range. A duplicated tone would silently make
            // the turnover invisible over part of its range.
            const pops = [mid.pop0, mid.pop1, mid.pop2, mid.pop3, mid.pop4, mid.pop5];
            let minGap = 9;
            for (let i = 0; i < 6; ++i)
                for (let j = i + 1; j < 6; ++j) {
                    const norm = (p) => { const m = Math.max(p[0], p[1], p[2]); return [p[0] / m, p[1] / m, p[2] / m]; };
                    const a = norm(pops[i]), b = norm(pops[j]);
                    minGap = Math.min(minGap, Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]));
                }
            check("the six populations are six distinct tones",
                minGap > 0.20 && pops.every(p => p[3] >= 0 && p[3] <= 1),
                "closest pair " + minGap.toFixed(3) + " apart in normalised linear rgb");
            h2._state.clock = e.start + remnantAt + span * 0.5;
        }
        // The episode ends dark: no residue, no ring left on the screen.
        h2._state.clock = e.start + e.duration - 0.05;
        const last = h2.radialState(e);
        check("the supernova ends at nothing", last.head[3] * (last.tail01[1] + last.tail01[2] + last.tail01[3]) < 0.004,
            "final published gain " + (last.head[3] * (last.tail01[1] + last.tail01[2] + last.tail01[3])).toFixed(5));
    }
    {
        // ------------------------------------------------- v10, the comet
        // "It was moving slow, same as the other stars, and the tail was in
        // the wrong direction." (ledger 2285) The direction half is pure
        // geometry, so it is checked here against the shipped cometState; the
        // speed half needs a live pool and is in tools/comet_harness.qml.
        const h3 = makeHost(validateDocument(null), { width: 2880, height: 1800 });
        h3._state.clock = 0;
        const e = h3.captureEvent(1, 0, 0, "slow");
        e.light = [1440, 900];
        const angle = (dirX, dirY, x, y) => {
            const s3 = h3.cometState(e, [x, y], 0.5, 0, 0.8, e.pointWidth, 5);
            const ion = Math.atan2(s3.tail01[1], s3.tail01[0]);
            const dust = Math.atan2(s3.tail23[1], s3.tail23[0]);
            const trail = Math.atan2(-dirY, -dirX);
            const wrap = (a) => Math.abs(((a - trail + Math.PI * 3) % (Math.PI * 2)) - Math.PI) * 180 / Math.PI;
            return { ion: wrap(ion), dust: wrap(dust), forward: Math.max(s3.tail01[0] * dirX + s3.tail01[1] * dirY, s3.tail23[0] * dirX + s3.tail23[1] * dirY) };
        };
        // The camera regime: no light source on the sky, so both tails trail.
        e.lightWeight = 0;
        let worstIon = 0, worstDust = 0, worstForward = -1;
        for (let n = 0; n < 64; ++n) {
            const a = n * Math.PI / 32, dirX = Math.cos(a), dirY = Math.sin(a);
            e.vel = [dirX * 140, dirY * 140];
            // Every heading, from a spread of places on the screen, including
            // straight at and straight away from where the hole would be.
            const at = [1440 + 700 * Math.cos(a * 1.7), 900 + 500 * Math.sin(a * 2.3)];
            const m = angle(dirX, dirY, at[0], at[1]);
            worstIon = Math.max(worstIon, m.ion);
            worstDust = Math.max(worstDust, m.dust);
            worstForward = Math.max(worstForward, m.forward);
        }
        check("with no hole, both tails trail the motion within 30 degrees",
            worstIon <= 30 && worstDust <= 30,
            "worst ion " + worstIon.toFixed(1) + " deg, worst dust " + worstDust.toFixed(1) + " deg over 64 headings");
        check("and neither of them ever points ahead of it",
            worstForward < 0, "worst forward component " + worstForward.toFixed(3));
        // The orbital regime: the hole is the only light on the sky, so the
        // ion tail is anti-sunward and the DUST still trails the motion.
        e.lightWeight = 1;
        let antiHole = 0, dustTrails = 0, forward = -1;
        for (let n = 0; n < 64; ++n) {
            const a = n * Math.PI / 32, dirX = Math.cos(a), dirY = Math.sin(a);
            e.vel = [dirX * 140, dirY * 140];
            const at = [1440 + 700 * Math.cos(a * 1.7), 900 + 500 * Math.sin(a * 2.3)];
            const st = h3.cometState(e, at, 0.5, 0, 0.8, e.pointWidth, 5);
            const away = Math.hypot(at[0] - e.light[0], at[1] - e.light[1]);
            const wantX = (at[0] - e.light[0]) / away, wantY = (at[1] - e.light[1]) / away;
            const dot = st.tail01[0] * wantX + st.tail01[1] * wantY;
            // Anti-sunward EXCEPT where anti-sunward would be ahead of the
            // nucleus, which is a comet flying at the hole. There the clamp
            // wins, and it must: a tail in front of its own nucleus is the one
            // thing a comet cannot have.
            const clamped = wantX * -dirX + wantY * -dirY < 0.17;
            if (!clamped) {
                if (dot > 0.999) ++antiHole;
            } else if (Math.abs(st.tail01[0] * -dirX + st.tail01[1] * -dirY - 0.17) < 1e-9) ++antiHole;
            const trail = st.tail23[0] * -dirX + st.tail23[1] * -dirY;
            if (trail > Math.cos(0.45)) ++dustTrails;
            forward = Math.max(forward, Math.max(st.tail01[0] * dirX + st.tail01[1] * dirY, st.tail23[0] * dirX + st.tail23[1] * dirY));
        }
        check("with the hole on, the ion tail points away from it",
            antiHole === 64, antiHole + "/64 headings anti-sunward, or clamped off the nucleus's own path where anti-sunward would be ahead of it");
        check("while the dust still trails the motion",
            dustTrails === 64, dustTrails + "/64 headings");
        check("and nothing points ahead of the motion in either regime",
            forward <= 0.171, "worst forward component " + forward.toFixed(3) + " against the 80 degree clamp");
        // The families keep their variety, and the slowest of them is still
        // three times the field.
        const ratios = ["fast", "slow", "bent", "pulsating", "fragmenting", "spiral"].map(f => h3.cometRatio(f));
        check("every comet family is 3-8x the field, and they still differ",
            Math.min(...ratios) >= 3 && Math.max(...ratios) <= 8 && new Set(ratios).size === 6,
            ratios.map(r => r.toFixed(1)).join(", "));
        check("and each of them bends by its own amount",
            new Set(["fast", "slow", "bent", "pulsating", "fragmenting", "spiral"].map(f => h3.cometTurn(f))).size === 6);
        // With no pool at all this is byte-for-byte v9: the sheets sweep it.
        const v9 = makeHost(validateDocument(null), { width: 2880, height: 1800 });
        const e9 = v9.captureEvent(1, 0, 0, "slow");
        const st9 = v9.cometState(e9, [900, 600], 0.5, 0, 0.8, e9.pointWidth, 5);
        const dxl = 900 - e9.light[0], dyl = 600 - e9.light[1], l = Math.hypot(dxl, dyl);
        check("with no body behind it, the comet is exactly v9",
            Math.abs(st9.tail01[0] - dxl / l) < 1e-12 && Math.abs(st9.tail01[1] - dyl / l) < 1e-12,
            "ion tail still anti-sunward");
    }
    nebulaTests();
    console.log("\n" + (failures ? failures + " failures" : "all " + checks + " checks passed"));
    return failures;
}

// ---------------------------------------------------------------- nebula
// The passage has no slot and no place in s.events, so simulate() cannot see
// it: it is driven here through the same publishNebula() the renderer calls,
// with the geometric accumulator advanced the way advance() advances it.
function nebulaHost(options) {
    const o = Object.assign({ width: 2880, height: 1800, dpr: 1, holeSize: 0.11 }, options || {});
    const document = validateDocument(o.config || null);
    const host = makeHost(document, o);
    host.paletteColors = document.palette.rgb;
    host._state.palette = new Array(document.palette.rgb.length).fill(1 / document.palette.rgb.length);
    return host;
}

// One second of publishes, with geo advancing exactly as advance() does: the
// nebula's drift is expressed against the same accumulator, so this is the
// renderer's own clock and not a second model of it.
function nebulaRun(host, seconds, step) {
    const dt = step === undefined ? 1 : step;
    const perSec = -host.nebulaDriftPerSec() / host.nebulaFlowRate();
    const seen = [];
    for (let t = 0; t <= seconds; t += dt) {
        host._state.clock = t;
        host._state.geo[0] = perSec * t;
        host.publishNebula();
        const head = host.shader.nebulaHead;
        if (head && head.w > 0)
            seen.push({ t: t, x: head.x, y: head.y, semi: head.z, gain: head.w,
                bounds: host.shader.nebulaBounds, shape: host.shader.nebulaShape,
                episode: host._state.nebula });
    }
    return seen;
}

function nebulaTests() {
    console.log("\n-- nebula passage");
    const frag = readFileSync(join(root, "modules", "background", "shaders", "starfield.frag"), "utf8");
    // Composite order, read off the shader rather than asserted: the cloud
    // joins the far field BEFORE the shadow is subtracted from it and before
    // the disk and the particles composite over it, which is the whole of
    // "behind the disk, in front of the far dust, never over the shadow".
    // v9-merged: the same statement also carries the storm's linear delta,
    // which is added OUTSIDE the (1-nebula.a) factor - a passage dims the
    // stars behind it and can never dim a meteor in front of it.
    const decode = frag.indexOf("vec3 farLinear = decodeDisplay(far);");
    const composite = frag.indexOf("far = farLinear*(1.0-nebula.a)+nebula.rgb+stormLinear;", decode);
    const storm = frag.indexOf("stormLinear = decodeDisplay(far+meteorStorm(skySource)*ubuf.brightness)-farLinear;", decode);
    const shadow = frag.indexOf("if (hole) far *= 1.0-bhShadowMask(pixel);", composite);
    const particles = frag.indexOf("vec3 linearColour = disk.rgb+(1.0-disk.a)*far", composite);
    check("the cloud joins the far field", composite > 0);
    check("the storm rides in beside it, unextincted", storm > decode && storm < composite);
    check("the shadow is subtracted after it", shadow > composite);
    check("the disk and the particles composite over it", particles > shadow);

    // Rate and spacing, one day of scheduling on the tablet.
    {
        const host = nebulaHost();
        const starts = [];
        for (let t = 0; t < 86400; t += 5) {
            host._state.clock = t;
            host._state.geo[0] = t;
            host.publishNebula();
            const e = host._state.nebula;
            if (e && starts[starts.length - 1] !== e.start) starts.push(e.start);
        }
        const gaps = starts.slice(1).map((s, i) => s - starts[i]).filter(g => g > 0);
        const mean = gaps.reduce((a, b) => a + b, 0) / Math.max(1, gaps.length);
        check("one passage every 20-45 min at rateScale 1",
            gaps.length > 20 && Math.min(...gaps) >= 1200 - 1 && mean >= 1500 && mean <= 2900,
            gaps.length + " passages, mean " + (mean / 60).toFixed(1) + " min, min " + (Math.min(...gaps) / 60).toFixed(1) + " min");
    }
    // The first passage of a session is inside the documented interval, not
    // behind the whole first round of dramatic schedules.
    {
        const firsts = [];
        for (const seed of [7, 12345, 20260913]) {
            const host = nebulaHost({ screenSeed: seed });
            for (let t = 0; t < 900; t += 5) {
                host._state.clock = t;
                host._state.geo[0] = t;
                host.publishEvents();
                host.publishNebula();
            }
            firsts.push(host._state.nebula.start / 60);
        }
        check("the first passage of a session is inside 20-50 min",
            firsts.every(x => x >= 20 && x <= 50),
            firsts.map(x => x.toFixed(1)).join(", ") + " min on three seeds");
    }
    // Never beside a supernova: both families write the same familyLast.drama.
    {
        const host = nebulaHost();
        let worst = 1e9, pairs = 0;
        for (let t = 0; t < 6 * 3600; t += 5) {
            host._state.clock = t;
            host._state.geo[0] = t;
            host.publishEvents();
            host.publishNebula();
            const n = host._state.nebula, s = host._state.events[8];
            if (n && s) {
                const overlap = Math.min(n.start + n.duration, s.start + s.duration) - Math.max(n.start, s.start);
                if (overlap > -1e9) { worst = Math.min(worst, -overlap); ++pairs; }
            }
        }
        check("a passage and a supernova never overlap", pairs > 0 && worst > 0,
            "closest approach " + worst.toFixed(0) + " s apart over 6 h");
    }
    // Geometry and both regimes.
    for (const out of [
        { name: "tablet 2880x1800", width: 2880, height: 1800 },
        { name: "DP-3 2160x3840", width: 2160, height: 3840 }
    ]) {
        const short = Math.min(out.width, out.height);
        for (const regime of ["hole", "camera"]) {
            const camera = regime === "camera";
            const host = nebulaHost(Object.assign({}, out, camera
                ? { hole: false, cameraBlend: 1, cameraOutward: 1 }
                : {}));
            const e = host.captureNebula(11, 0);
            host._state.nebula = e;
            const frames = nebulaRun(host, e.duration, 1);
            const label = out.name + " " + regime;
            check("a passage lasts 3-8 minutes on " + label,
                e.duration >= 150 && e.duration <= 500, e.duration.toFixed(0) + " s");
            check("it is drawn for most of it on " + label,
                frames.length > e.duration * 0.55, frames.length + " of " + e.duration.toFixed(0) + " s");
            const peak = frames.reduce((a, b) => a.gain > b.gain ? a : b);
            check("its size is 40-110 % of the short side on " + label,
                2 * peak.semi >= 0.40 * short && 2 * peak.semi <= 1.10 * short,
                (200 * peak.semi / short).toFixed(0) + " % at peak gain");
            check("its peak linear gain is capped on " + label,
                peak.gain <= 0.35 + 1e-6, peak.gain.toFixed(3));
            // Entry and exit: it starts and ends at nothing, with no step.
            let worstStep = 0;
            for (let i = 1; i < frames.length; ++i)
                if (frames[i].t - frames[i - 1].t <= 1.001)
                    worstStep = Math.max(worstStep, Math.abs(frames[i].gain - frames[i - 1].gain));
            check("the envelope never steps on " + label,
                worstStep <= 0.02, worstStep.toFixed(4) + " per second");
            // Motion: it travels with the far layer, in the regime's direction.
            const first = frames[0], last = frames[frames.length - 1];
            const r0 = Math.hypot(first.x - out.width / 2, first.y - out.height / 2);
            const r1 = Math.hypot(last.x - out.width / 2, last.y - out.height / 2);
            check("it drifts " + (camera ? "outward" : "inward") + " on " + label,
                camera ? r1 > r0 + 0.1 * short : r1 < r0 - 0.1 * short,
                "r " + r0.toFixed(0) + " -> " + r1.toFixed(0) + " px");
            if (camera)
                check("and grows with its depth on " + label,
                    last.semi > first.semi * 1.5, first.semi.toFixed(0) + " -> " + last.semi.toFixed(0) + " px");
            else
                check("and shears as the tide takes hold on " + label,
                    last.shape.z < first.shape.z - 0.02, "aspect " + first.shape.z.toFixed(2) + " -> " + last.shape.z.toFixed(2));
            // Bounds contain the drawn ellipse exactly.
            const bad = frames.filter(f => {
                const a = f.semi, b = f.semi * f.shape.z;
                const bx = Math.sqrt(a * a * f.shape.x * f.shape.x + b * b * f.shape.y * f.shape.y);
                const by = Math.sqrt(a * a * f.shape.y * f.shape.y + b * b * f.shape.x * f.shape.x);
                return Math.abs((f.bounds.z - f.bounds.x) / 2 - bx) > 0.5 || Math.abs((f.bounds.w - f.bounds.y) / 2 - by) > 0.5;
            });
            check("the CPU bounds are the exact ellipse on " + label, bad.length === 0, bad.length + " frames off");
            // Under infall it dissolves before its centre reaches the disk.
            if (!camera) {
                const reach = host.holeReach();
                const inside = frames.filter(f => Math.hypot(f.x - out.width / 2, f.y - out.height / 2) < 0.55 * reach);
                check("it has dissolved before the disk rim on " + label,
                    inside.length === 0, inside.length + " frames inside " + (0.55 * reach).toFixed(0) + " px");
            }
        }
    }
    // The reversal: the same episode, walked forward and then backward.
    {
        const host = nebulaHost({ hole: false, cameraBlend: 1, cameraOutward: 1 });
        const e = host.captureNebula(11, 0);
        e.geo = 0;
        host._state.nebula = e;
        const perSec = -host.nebulaDriftPerSec() / host.nebulaFlowRate();
        host._state.clock = 60;
        host._state.geo[0] = perSec * 60;
        const out = host.nebulaState(e);
        // The camera flips: geo runs the other way from here, and the cloud
        // walks back in the way it came out rather than continuing. Same
        // episode, same state function, one accumulator.
        host._state.clock = 120;
        host._state.geo[0] = perSec * 20;
        const back = host.nebulaState(e);
        const centre = host.width * host.devicePixelRatio / 2;
        check("a camera reversal walks the cloud back",
            Math.abs(back.head[0] - centre) < Math.abs(out.head[0] - centre) - 1,
            "x " + out.head[0].toFixed(0) + " -> " + back.head[0].toFixed(0) + ", centre " + centre.toFixed(0));
    }
    // Force-fire, and the switch.
    {
        const host = nebulaHost();
        check("fire nebula queues a passage", host.pushEvent("nebula", 0, null) === true);
        host._state.clock = 1;
        host.publishNebula();
        check("and it is the running episode", host._state.nebula !== null && host._state.nebulaPending === null);
        const off = nebulaHost({ config: { events: { nebula: { enabled: false } } } });
        off._state.clock = 4000;
        off._state.geo[0] = 4000;
        off.publishNebula();
        check("enabled:false draws nothing", off.shader.nebulaHead.w === 0);
        const zero = nebulaHost({ config: { events: { rateScale: 0 } } });
        zero._state.clock = 8000;
        zero._state.geo[0] = 8000;
        zero.publishNebula();
        check("rateScale 0 draws nothing", zero.shader.nebulaHead.w === 0);
    }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
    if (process.argv[2] === "--audit") audit(process.argv[3]);
    else process.exit(tests() ? 1 : 0);
}
