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

const NAMES = ["clamp", "modulo", "random", "ease", "normalized", "parameterRange", "paletteSnapshot", "phenomenon", "moodState", "eventOff", "eventConfig", "eventEnabled", "familyDefaults", "cometLook", "chooseFamily", "captureEvent", "classifyCapture", "schedule", "rateScale", "holeReach", "radialPlacement", "captureRadial", "radialSchedule", "dramatic", "scheduleRadial", "radialState", "eventPath", "eventState", "cometState", "pushEvent", "drainPending", "publishEvents", "publishPhenomena", "farBoost", "nebulaConfig", "nebulaEnabled", "nebulaFlowRate", "nebulaDrift", "nebulaBoundary", "nebulaDriftPerSec", "nebulaReach", "nebulaSink", "captureNebula", "scheduleNebula", "nebulaState", "pushNebula", "publishNebula"];

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
        events: new Array(12).fill(null),
        eventIds: new Array(12).fill(0),
        familyLast: {},
        moodClock: 0,
        mood: [0, 0, 0, 0],
        phenomenonSlots: [null, null, null],
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
    const composite = frag.indexOf("far = far*(1.0-nebula.a)+nebula.rgb;");
    const shadow = frag.indexOf("if (hole) far *= 1.0-bhShadowMask(pixel);", composite);
    const particles = frag.indexOf("vec3 linearColour = disk.rgb+(1.0-disk.a)*far", composite);
    check("the cloud joins the far field", composite > 0);
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
