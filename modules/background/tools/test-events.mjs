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
import vm from "vm";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const QML = join(root, "modules", "background", "Starfield.qml");
const RULES = join(root, "services", "ambient", "rules.js");

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

const NAMES = ["clamp", "modulo", "random", "ease", "normalized", "parameterRange", "paletteSnapshot", "phenomenon", "moodState", "eventOff", "eventConfig", "eventEnabled", "familyDefaults", "chooseFamily", "captureEvent", "classifyCapture", "schedule", "radialPlacement", "captureRadial", "dramatic", "scheduleRadial", "radialState", "eventPath", "eventState", "publishEvents", "publishPhenomena"];

export function scheduler(host) {
    // radialNames is a readonly property, not a function.
    host.radialNames = ["starBirth", "nova", "redGiant", "supernova", "pulsar"];
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
    const holeRadius = o.holeRadius === undefined ? 0.075 * Math.min(w, h) : o.holeRadius;
    const shader = {
        centreOffset: { x: 0, y: 0 },
        mood: Qt.vector4d(0, 0, 0, 0)
    };
    const host = {
        Qt, Math, Number, Array, Object, JSON, console,
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
            rateScale: document.events.rateScale
        },
        shader,
        _hole: {
            enabled: o.hole !== false,
            bhCentre: { x: w / 2, y: h / 2 },
            bhGeometry: { x: holeRadius, y: holeRadius * 2.6, z: 0, w: 0 }
        },
        _state: null
    };
    host._state = {
        clock: 0,
        live: [0.5, 0.5, 0.5, 0.5],
        palette: [],
        events: new Array(host.slotKinds === undefined ? 12 : host.slotKinds).fill(null),
        eventIds: new Array(12).fill(0),
        familyLast: {},
        moodClock: 0,
        mood: [0, 0, 0, 0],
        phenomenonSlots: [null, null],
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
        for (let i = 0; i < 5; ++i) {
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
    host._slotKind = [-1, -1, -1, -1, -1];
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
        host._slotKind = [-1, -1, -1, -1, -1];
        // A shower's children are kind-0 meteors; credit them to the shower.
        const shower = host._state.events[3];
        if (shower && shower.children)
            for (const child of shower.children) child._shower = true;
        realPublish.call(host);
        for (let i = 0; i < 3; ++i) host._slotKind[i] = order[i] === undefined ? -1 : order[i];
        for (let i = 0; i < 2; ++i) {
            const owner = host._state.phenomenonSlots[i];
            host._slotKind[3 + i] = owner === null ? -1 : owner;
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
    const outputs = [
        { name: "DP-3 1440x2560", width: 1440, height: 2560 },
        { name: "HDMI-A-1 3440x1440", width: 3440, height: 1440 },
        { name: "tablet 2880x1800", width: 2880, height: 1800 }
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
    const host = instrument(makeHost(document, { name: "d", width: 1440, height: 2560 }));
    const stat = simulate(host, 3600, 1 / 15);
    table(stat, "defaults, DP-3 (one hour)");
    const by = {};
    for (const s of stat) by[s.name] = s;

    check("meteors fire at least 20/h", by.meteors.perHour >= 20, by.meteors.perHour.toFixed(1) + "/h");
    check("comets fire at least 4/h", by.comet.perHour >= 4, by.comet.perHour.toFixed(1) + "/h");
    check("satellites fire at least 8/h", by.satellites.perHour >= 8, by.satellites.perHour.toFixed(1) + "/h");
    for (const name of ["starBirth", "nova", "redGiant", "supernova"]) {
        check(name + " is scheduled", by[name].perHour > 0, by[name].perHour.toFixed(2) + "/h");
        check(name + " is actually drawn", by[name].drawnFrames > 0, by[name].drawnSec.toFixed(0) + " s/h");
    }
    const notable = ["comet", "starBirth", "nova", "redGiant", "supernova", "pulsar", "kilonova"].reduce((a, n) => a + by[n].perHour, 0);
    check("a notable non-meteor event at least every 4 min", notable >= 15, notable.toFixed(1) + "/h");
    check("phenomena peak above a bright star's core sigma", by.nova.peakSigma >= 6, by.nova.peakSigma.toFixed(1) + " px");
    check("supernova outshines a comet", by.supernova.peakGain > 0.6, by.supernova.peakGain.toFixed(2));
    console.log("\n" + (failures ? failures + " failures" : "all " + checks + " checks passed"));
    return failures;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
    if (process.argv[2] === "--audit") audit(process.argv[3]);
    else process.exit(tests() ? 1 : 0);
}
