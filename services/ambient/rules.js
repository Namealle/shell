// Plain ES5: shared by QML and the Node verification shim. No titles are retained.
var MAX_ENTRIES = 32;
var MAX_PATTERN = 256;
var CONTROLS = ["green", "violet", "warm", "calm", "twinkle", "brightness", "flow", "meteor"];
var SIGNALS = ["cpuLoad", "cpuHeat", "gpuLoad", "gpuHeat", "vram", "ram", "network",
    "rain", "wind", "humidity", "temperature", "weatherNight", "night", "media", "idle",
    "agentProcess", "agentWindow", "load", "heat", "loadRising", "memoryPressure", "agent",
    "cpuLoadRising", "gpuLoadRising", "notifications"];

function own(obj, key) { return Object.prototype.hasOwnProperty.call(obj, key); }
function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {}; }
function finite(value) { return typeof value === "number" && isFinite(value); }
function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
function number(value, fallback, low, high) { return finite(value) ? clamp(value, low, high) : fallback; }
function boolean(value, fallback) { return typeof value === "boolean" ? value : fallback; }
function interval(value, fallback, minimum) {
    if (!Array.isArray(value) || value.length !== 2 || !finite(value[0]) || !finite(value[1]))
        return fallback.slice();
    var low = clamp(value[0], minimum, 3600);
    return [low, Math.max(low, clamp(value[1], minimum, 3600))];
}

function defaultReactive() {
    return {
        enabled: true, contextScope: "perScreen", processPresenceWeight: 0.35, paletteBudget: 0.45,
        birthTauSec: 60, liveTauSec: 90, maxChangePerSec: 0.005,
        matchers: [
            {id: "htb", "class": "^zen$", title: "\\bHTB\\b|Hack\\s*The\\s*Box|hackthebox\\.(com|eu)", flags: "i"},
            {id: "steam", "class": "^steam$", flags: "i"},
            {id: "game", "class": "^steam_app_[0-9]+$", flags: "i"},
            {id: "terminal", "class": "^(foot|footclient)$"},
            {id: "agentWindow", "class": "^(foot|footclient)$", title: "^[✳◑]"}
        ],
        rules: [
            {signal: "htb", add: {green: 0.32}},
            {signal: "agent", add: {violet: 0.14, twinkle: 0.04}},
            {signal: "heat", add: {warm: 0.20}},
            {signal: "load", add: {warm: 0.10, flow: 0.25}},
            {signal: "loadRising", add: {flow: 0.05}},
            {signal: "rain", add: {calm: 0.22, brightness: -0.25, twinkle: -0.15}},
            {signal: "wind", add: {flow: 0.04}},
            {signal: "night", add: {calm: 0.20, flow: -0.15, twinkle: -0.15, meteor: -0.25}},
            {signal: "idle", add: {calm: 0.10, flow: -0.10, meteor: -0.10}},
            {signal: "media", add: {twinkle: 0.05}},
            {signal: "steam", add: {violet: 0.03}},
            {signal: "game", add: {warm: 0.06}},
            {signal: "terminal", add: {calm: 0.04}},
            {signal: "memoryPressure", add: {calm: 0.05}},
            {signal: "network", enabled: false, add: {twinkle: 0.03}},
            {signal: "notifications", enabled: false, add: {meteor: 0.04}}
        ]
    };
}

function patternValid(pattern, flags) {
    if (typeof pattern !== "string" || !pattern.length || pattern.length > MAX_PATTERN)
        return false;
    // Bound GUI-thread matching: no backreferences, lookarounds or repeated groups.
    if (/\\[1-9]|\(\?|\)[+*{]/.test(pattern))
        return false;
    try { new RegExp(pattern, flags); return true; } catch (error) { return false; }
}

function validateMatchers(value) {
    var result = [], seen = Object.create(null);
    if (!Array.isArray(value))
        return result;
    for (var i = 0; i < Math.min(value.length, MAX_ENTRIES); i++) {
        var m = object(value[i]), id = m.id, flags = m.flags === undefined ? "" : m.flags;
        if (typeof id !== "string" || !/^[A-Za-z][A-Za-z0-9_]{0,47}$/.test(id) || own(seen, id)
                || id === "constructor" || id === "prototype" || (SIGNALS.indexOf(id) !== -1 && id !== "agentWindow"))
            continue;
        seen[id] = true;
        var validFlags = typeof flags === "string" && /^(i?m?|mi)$/.test(flags);
        var valid = validFlags && patternValid(m["class"], flags)
            && (m.title === undefined || patternValid(m.title, flags));
        // Invalid entries survive only as disabled category IDs; never throw away siblings.
        result.push({id: id, "class": valid ? m["class"] : "", title: valid ? m.title : undefined,
            flags: validFlags ? flags : "", enabled: valid && boolean(m.enabled, true)});
    }
    return result;
}

function validateReactive(value) {
    var r = object(value), defaults = defaultReactive();
    var matchers = validateMatchers(r.matchers === undefined ? defaults.matchers : r.matchers);
    var known = SIGNALS.slice(), i;
    for (i = 0; i < matchers.length; i++)
        if (matchers[i].enabled) known.push(matchers[i].id);
    var input = r.rules === undefined ? defaults.rules : r.rules;
    var rules = [];
    if (Array.isArray(input)) {
        for (i = 0; i < Math.min(input.length, MAX_ENTRIES); i++) {
            var entry = object(input[i]), add = object(entry.add), clean = {};
            for (var c = 0; c < CONTROLS.length; c++) {
                var key = CONTROLS[c];
                if (finite(add[key])) clean[key] = clamp(add[key], -1, 1);
            }
            rules.push({signal: typeof entry.signal === "string" ? entry.signal.slice(0, 48) : "",
                enabled: boolean(entry.enabled, true) && known.indexOf(entry.signal) !== -1 && Object.keys(clean).length > 0,
                add: clean});
        }
    }
    return {enabled: boolean(r.enabled, true), contextScope: "perScreen",
        processPresenceWeight: number(r.processPresenceWeight, 0.35, 0, 1),
        paletteBudget: number(r.paletteBudget, 0.45, 0, 0.45),
        // Frozen renderer API has no filter-setting properties. Keep these contract constants.
        birthTauSec: 60, liveTauSec: 90, maxChangePerSec: 0.005,
        matchers: matchers, rules: rules};
}

function validateDocument(value) {
    var d = object(value), m = object(d.motion), v = object(d.variety), variables = object(d.variables);
    var mode = m.mode === "drift" ? "drift" : "radial";
    var meteor = object(d.meteors), comet = object(d.comet), satellites = object(d.satellites);
    var screens = [];
    if (Array.isArray(d.screens)) {
        for (var i = 0; i < d.screens.length; i++) {
            var name = d.screens[i];
            if (typeof name === "string" && name.length > 0 && name.length <= 128 && screens.indexOf(name) === -1)
                screens.push(name);
        }
    }
    return {
        screens: screens, density: number(d.density, 1, 0, 3),
        driftSpeed: number(d.driftSpeed, 3.5, 0, 30), driftDirection: number(d.driftDirection, 165, -360, 360),
        twinkle: number(d.twinkle, 0.22, 0, 1), flareFraction: number(d.flareFraction, 0.003, 0, 0.025),
        brightness: number(d.brightness, 1, 0, 3), edgeLift: number(d.edgeLift, 0, 0, 1),
        backgroundColor: typeof d.backgroundColor === "string" && /^#[0-9a-fA-F]{6}$/.test(d.backgroundColor) ? d.backgroundColor : "#000000",
        fps: Math.round(number(d.fps, 30, 1, 60)),
        motion: {mode: mode, radialSpeed: number(m.radialSpeed, 6, 0, 26),
            centreWander: number(m.centreWander, 0.012, 0, 0.05), zoom: number(m.zoom, mode === "drift" ? 0.025 : 0.003, 0, 0.15),
            reversals: boolean(m.reversals, false), wander: number(m.wander, 0.8, 0, 2), rotation: number(m.rotation, 0.5, 0, 3)},
        variety: {enabled: boolean(v.enabled, true), seed: Math.round(number(v.seed, 1, 0, 2147483647))},
        variables: {fraction: number(variables.fraction, 0.006, 0, 0.05)},
        meteors: {enabled: boolean(meteor.enabled, true), interval: interval(meteor.interval, [45, 120], 3),
            companionChance: number(meteor.companionChance, 0.04, 0, 1), fireballChance: number(meteor.fireballChance, 0.01, 0, 1)},
        comet: {enabled: boolean(comet.enabled, true), interval: interval(comet.interval, [900, 1800], 60)},
        satellites: {enabled: boolean(satellites.enabled, true), interval: interval(satellites.interval, [240, 480], 45)},
        reactive: validateReactive(d.reactive)
    };
}

function parseDocument(text) {
    try { return validateDocument(JSON.parse(text)); } catch (error) { return validateDocument(null); }
}

function compileMatchers(matchers) {
    var compiled = [];
    for (var i = 0; i < matchers.length; i++) {
        var m = matchers[i];
        if (!m.enabled) continue;
        compiled.push({id: m.id, classRx: new RegExp(m["class"], m.flags),
            titleRx: m.title === undefined ? null : new RegExp(m.title, m.flags)});
    }
    return compiled;
}

function sameWorkspace(a, b) {
    if (!a || !b) return false;
    if (a.id !== undefined && b.id !== undefined && a.id === b.id && a.id !== 0) return true;
    return !!a.name && !!b.name && a.name === b.name;
}

function onOutput(t, monitor) {
    if (!t || !monitor) return false;
    var ipc = t.lastIpcObject || {}, ws = t.workspace || ipc.workspace || {};
    var owner = t.monitor || ws.monitor;
    if (owner) return owner === monitor || (typeof owner.name === "string" && owner.name.length > 0 && owner.name === monitor.name)
        || (owner.id !== undefined && owner.id === monitor.id);
    return ipc.monitor !== undefined && (ipc.monitor === monitor.id || ipc.monitor === monitor.name);
}

function visible(t, monitor) {
    if (!t || !monitor) return false;
    var ipc = t.lastIpcObject || {}, mi = monitor.lastIpcObject || {};
    if (t.mapped === false || ipc.mapped === false || t.hidden === true || ipc.hidden === true
            || t.minimized === true || ipc.minimized === true || ipc.minimised === true
            || (t.wayland && t.wayland.minimized === true) || !onOutput(t, monitor))
        return false;
    var ws = t.workspace || ipc.workspace;
    return t.pinned === true || ipc.pinned === true || sameWorkspace(ws, monitor.activeWorkspace || mi.activeWorkspace)
        || sameWorkspace(ws, monitor.specialWorkspace || mi.specialWorkspace);
}

function visibilityWeight(t, monitor, active) {
    if (!visible(t, monitor)) return 0;
    return t === active || t.activated === true || (t.wayland && t.wayland.activated === true) ? 1 : 0.6;
}

function runningFor(monitor, toplevels, locked) {
    if (locked) return false;
    for (var i = 0; i < toplevels.length; i++) {
        var t = toplevels[i], ipc = t.lastIpcObject || {};
        if (visible(t, monitor) && number(ipc.fullscreen, number(t.fullscreen, 0, 0, 3), 0, 3) > 1)
            return false;
    }
    return true;
}

function categories(compiled, toplevels, monitor, active) {
    var result = Object.create(null);
    for (var m = 0; m < compiled.length; m++) result[compiled[m].id] = 0;
    for (var i = 0; i < toplevels.length; i++) {
        var t = toplevels[i], weight = visibilityWeight(t, monitor, active);
        if (!weight) continue;
        var ipc = t.lastIpcObject || {};
        var appClass = typeof ipc["class"] === "string" ? ipc["class"].slice(0, 256) : "";
        for (m = 0; m < compiled.length; m++) {
            var matcher = compiled[m];
            if (!matcher.classRx.test(appClass)) continue;
            // Read only AFTER class matching. Never attach a title or window to the result/state.
            if (matcher.titleRx) {
                var title = typeof t.title === "string" ? t.title : (typeof ipc.title === "string" ? ipc.title : "");
                if (!matcher.titleRx.test(title.slice(0, 512))) continue;
            }
            result[matcher.id] = Math.max(result[matcher.id], weight);
        }
    }
    return result;
}

function seedFor(name) {
    var hash = 2166136261, text = typeof name === "string" ? name : "";
    for (var i = 0; i < text.length; i++) {
        hash ^= text.charCodeAt(i);
        hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
        hash >>>= 0;
    }
    return hash & 0x7fffffff;
}

function evaluate(config, signals) {
    var target = [0, 0, 0, 0.5, 0.5, 0.5, 0.5, 0.5];
    if (config.enabled) {
        for (var i = 0; i < config.rules.length; i++) {
            var rule = config.rules[i];
            if (!rule.enabled || !own(signals, rule.signal) || !finite(signals[rule.signal])) continue;
            var strength = clamp(signals[rule.signal], 0, 1);
            for (var c = 0; c < CONTROLS.length; c++) {
                var add = rule.add[CONTROLS[c]];
                if (finite(add)) target[c] += strength * add;
            }
        }
    }
    for (var j = 0; j < target.length; j++) target[j] = clamp(target[j], 0, 1);
    var total = target[0] + target[1] + target[2], budget = number(config.paletteBudget, 0.45, 0, 0.45);
    if (total > budget) for (j = 0; j < 3; j++) target[j] *= budget / total;
    return {birth: target.slice(0, 4), live: target.slice(4, 8)};
}
