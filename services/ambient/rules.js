// Plain ES5: shared by QML and the Node verification shim. No titles are retained.
var MAX_ENTRIES = 32;
var MAX_PATTERN = 256;
var CONTROLS = ["green", "violet", "warm", "calm", "twinkle", "brightness", "flow", "meteor", "mix"];
var ARCHETYPES = ["steady", "pulsator", "decayer", "glint", "wanderer", "binary"];
var HOLE = ["activity", "warmth", "brightness", "structure"];
var ROLE_HUES = {
    green: 120,
    yellow: 60,
    red: 0,
    blue: 240,
    pink: 330,
    orange: 30,
    purple: 270,
    teal: 180
};
var SIGNALS = ["cpuLoad", "cpuHeat", "gpuLoad", "gpuHeat", "vram", "ram", "network", "rain", "wind", "humidity", "temperature", "weatherNight", "night", "media", "idle", "agentProcess", "agentWindow", "load", "heat", "loadRising", "memoryPressure", "agent", "agentFalling", "cpuLoadRising", "gpuLoadRising", "notifications", "workspaceActivity"];
// Rule-addressable schedules. A signal biases the NEXT interval of one of these
// and never triggers an event, so nothing on screen maps 1:1 to a notification.
var EVENT_TARGETS = ["meteors", "comet", "satellites", "shower", "slowWanderer", "starBirth", "nova", "redGiant", "supernova", "kilonova", "pulsar", "gammaBurst", "tde", "nebula"];

function own(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
}
function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {};
}
function finite(value) {
    return typeof value === "number" && isFinite(value);
}
function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}
function number(value, fallback, low, high) {
    return finite(value) ? clamp(value, low, high) : fallback;
}
function boolean(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}
function interval(value, fallback, minimum, maximum) {
    if (!Array.isArray(value) || value.length !== 2 || !finite(value[0]) || !finite(value[1]))
        return fallback.slice();
    var cap = maximum === undefined ? 86400 : maximum;
    var low = clamp(value[0], minimum, cap);
    return [low, Math.max(low, clamp(value[1], minimum, cap))];
}
// v6 schedules reject instead of repairing, so an inverted or out-of-range pair
// falls back to its documented default rather than to a silently clamped one.
function orderedPair(value, minimum, maximum) {
    if (!Array.isArray(value) || value.length !== 2 || !finite(value[0]) || !finite(value[1]) || value[0] > value[1])
        return undefined;
    return value[0] >= minimum && value[1] <= maximum ? [value[0], value[1]] : undefined;
}
function everyMinutes(value) {
    // Minutes, not seconds: one minute to a full day.
    return orderedPair(value, 1, 1440);
}
function everyHours(value) {
    return orderedPair(value, 0.25, 168);
}

function normalize(values, fallback) {
    var total = 0, out = [], i;
    for (i = 0; i < values.length; i++) {
        out[i] = finite(values[i]) ? Math.max(0, values[i]) : 0;
        total += out[i];
    }
    if (!total)
        return fallback ? fallback.slice() : out.map(function () {
            return out.length ? 1 / out.length : 0;
        });
    return out.map(function (v) {
        return v / total;
    });
}

function validId(id) {
    return typeof id === "string" && /^[A-Za-z][A-Za-z0-9_]{0,47}$/.test(id) && id !== "constructor" && id !== "prototype";
}

function defaultPalette() {
    return {
        colors: ["#A8E6BD", "#FFF0AD", "#F2B1B1", "#ADCFFF", "#F4B9DA", "#FFD0A8", "#CFB8F4", "#A8E4DE"],
        ids: ["green", "yellow", "red", "blue", "pink", "orange", "purple", "teal"],
        weights: [1, 1, 1, 1, 1, 1, 1, 1],
        lightness: 0.45,
        saturationCap: 0.28,
        mix: 0.32,
        variationWhite: [0, 0.10],
        foregroundWhite: 0.35
    };
}

function lighten(rgb, lightness, saturationCap) {
    var maximum = Math.max(rgb[0], rgb[1], rgb[2]);
    if (!maximum)
        return [1, 1, 1];
    var c = rgb.map(function (v) {
        return v / maximum * (1 - lightness) + lightness;
    });
    var saturation = Math.max(c[0], c[1], c[2]) - Math.min(c[0], c[1], c[2]);
    var scale = Math.min(1, saturationCap / Math.max(saturation, 1e-9));
    return c.map(function (v) {
        return 1 + (v - 1) * scale;
    });
}

function hue(rgb) {
    var high = Math.max(rgb[0], rgb[1], rgb[2]), low = Math.min(rgb[0], rgb[1], rgb[2]), delta = high - low;
    if (delta < 1e-9)
        return null;
    var h = high === rgb[0] ? (rgb[1] - rgb[2]) / delta : high === rgb[1] ? 2 + (rgb[2] - rgb[0]) / delta : 4 + (rgb[0] - rgb[1]) / delta;
    return (h * 60 + 360) % 360;
}

function validatePalette(value, warn) {
    var p = object(value), defaults = defaultPalette();
    var input = p.colors === undefined ? defaults.colors : Array.isArray(p.colors) ? p.colors : [];
    // User colours without IDs must never inherit semantic names from the preset.
    var ids = p.ids === undefined && p.colors === undefined ? defaults.ids : Array.isArray(p.ids) ? p.ids : [];
    var weights = Array.isArray(p.weights) ? p.weights : [];
    var result = {
        colors: [],
        ids: [],
        weights: [],
        rgb: [],
        hues: [],
        sourceIndices: [],
        lightness: number(p.lightness, 0.45, 0, 1),
        saturationCap: number(p.saturationCap, 0.28, 0, 0.28),
        mix: number(p.mix, 0.32, 0, 0.45),
        variationWhite: interval(p.variationWhite, [0, 0.10], 0, 1),
        foregroundWhite: number(p.foregroundWhite, 0.35, 0, 1)
    };
    var seen = Object.create(null);
    for (var i = 0; i < input.length && result.colors.length < 16; i++) {
        var hex = input[i];
        if (typeof hex !== "string" || !/^#[0-9a-fA-F]{6}$/.test(hex)) {
            // The only dynamic (and entire) warning payload is the index.
            if (typeof warn === "function")
                warn(i);
            else
                console.warn(i);
            continue;
        }
        var rgb = [parseInt(hex.slice(1, 3), 16) / 255, parseInt(hex.slice(3, 5), 16) / 255, parseInt(hex.slice(5, 7), 16) / 255];
        var id = validId(ids[i]) && !own(seen, ids[i]) ? ids[i] : "";
        if (id)
            seen[id] = true;
        result.colors.push(hex.toUpperCase());
        result.rgb.push(lighten(rgb, result.lightness, result.saturationCap));
        result.hues.push(hue(rgb));
        result.ids.push(id);
        result.sourceIndices.push(i);
        result.weights.push(number(weights[i], 1, 0, 1000000));
    }
    result.baseWeights = normalize(result.weights);
    return result;
}

function weightsObject(value, defaults) {
    var w = object(value), values = [];
    for (var i = 0; i < ARCHETYPES.length; i++)
        values.push(number(w[ARCHETYPES[i]], defaults[i], 0, 1));
    values = normalize(values, defaults);
    var result = {};
    for (i = 0; i < ARCHETYPES.length; i++)
        result[ARCHETYPES[i]] = values[i];
    return result;
}

function validateArchetypes(value) {
    var a = object(value), p = object(a.pulsator), d = object(a.decayer), g = object(a.glint);
    var w = object(a.wanderer), b = object(a.binary), c = object(a.colorShifter);
    var far = weightsObject(a.farWeights, [0.97, 0.03, 0, 0, 0, 0]);
    for (var i = 2; i < ARCHETYPES.length; i++) {
        far.steady += far[ARCHETYPES[i]];
        far[ARCHETYPES[i]] = 0;
    }
    return {
        weights: weightsObject(a.weights, [0.82, 0.10, 0.04, 0.02, 0.015, 0.005]),
        farWeights: far,
        pulsator: {
            periodSec: interval(p.periodSec, [6, 40], 6, 360),
            amplitude: interval(p.amplitude, [0.08, 0.22], 0, 0.22)
        },
        decayer: {
            lifeSec: interval(d.lifeSec, [20, 90], 20, 600),
            fadeInSec: interval(d.fadeInSec, [3, 8], 3, 20)
        },
        glint: {
            everySec: interval(g.everySec, [18, 65], 18, 3600),
            widthSec: interval(g.widthSec, [0.8, 2], 0.8, 2),
            gain: number(g.gain, 0.18, 0, 0.18)
        },
        wanderer: {
            periodSec: interval(w.periodSec, [30, 100], 30, 600),
            offsetPx: number(w.offsetPx, 8, 0, 8)
        },
        binary: {
            periodSec: interval(b.periodSec, [12, 45], 12, 360),
            separationPx: interval(b.separationPx, [1.5, 5], 0, 5)
        },
        colorShifter: {
            enabled: boolean(c.enabled, false),
            share: number(c.share, 0.005, 0, 0.005),
            periodSec: interval(c.periodSec, [120, 360], 120, 3600)
        }
    };
}

function validateFamilies(value, comet) {
    // duration, weight, gain cap, tail range, bend range. Unspecified tails are conservative defaults.
    var defaults = comet ? {
        fast: [[4, 9], 0.18, 0.95, [0.06, 0.11], [0, 0]],
        slow: [[30, 65], 0.34, 0.70, [0.20, 0.32], [0, 0]],
        bent: [[12, 28], 0.28, 0.80, [0.12, 0.20], [0.02, 0.06]],
        pulsating: [[20, 40], 0.08, 0.75, [0.14, 0.24], [0.02, 0.06]],
        fragmenting: [[8, 16], 0.02, 0.80, [0.08, 0.16], [0.02, 0.06]],
        spiral: [[18, 35], 0.10, 0.65, [0.08, 0.18], [0, 0.06]]
    } : {
        // v12 lengthened the meteor tails. The trail is the only place a light
        // curve is visible in ONE frame, and at 0.08-0.14 short sides against a
        // 0.28-0.38 chord it covered a quarter to a half of the path with
        // nothing along it to see. The ceiling is row[3][1], so raising a
        // default raises the bound with it: a config that set the old value
        // still validates, which is what keeps this a widening and not a
        // rejection.
        straight: [[0.7, 1.3], 0.72, 0.85, [0.13, 0.22], [0, 0]],
        curved: [[0.9, 1.7], 0.20, 0.80, [0.11, 0.17], [0.005, 0.02]],
        skipping: [[1.2, 2.2], 0.08, 0.70, [0.12, 0.19], [0, 0]]
    };
    var input = object(value), out = {}, names = Object.keys(defaults);
    for (var i = 0; i < names.length; i++) {
        var name = names[i], f = object(input[name]), row = defaults[name];
        out[name] = {
            weight: number(f.weight, row[1], 0, 1),
            durationSec: interval(f.durationSec, row[0], row[0][0], row[0][1]),
            gain: number(f.gain, row[2], 0, row[2]),
            tailShortSide: interval(f.tailShortSide, row[3], 0, row[3][1]),
            bendShortSide: interval(f.bendShortSide, row[4], 0, row[4][1])
        };
        if (name === "fragmenting" || name === "spiral")
            out[name].cooldownSec = number(f.cooldownSec, name === "spiral" ? 14400 : 7200, name === "spiral" ? 14400 : 7200, 604800);
    }
    if (comet) {
        var other = 0;
        for (i = 0; i < names.length; i++)
            if (names[i] !== "fragmenting")
                other += out[names[i]].weight;
        out.fragmenting.weight = Math.min(out.fragmenting.weight, other * 0.02 / 0.98);
    }
    return out;
}

// The anti-strobe floors are the taste contract, not documentation. A rise
// faster than RISE_FLOOR, a pulsar period under PERIOD_FLOOR, a trough below
// FLOOR_FRACTION of peak or an edge shorter than EDGE_FLOOR is rejected, so no
// enabled family can produce a blink the renderer would then have to defend.
var RISE_FLOOR = 0.8;
var PERIOD_FLOOR = 0.8;
var FLOOR_FRACTION = 0.5;
var EDGE_FLOOR = 0.10;
// A gamma-ray burst is sub-second by nature, so it gets its own rise floor
// rather than the nova's. 0.35 s is ten frames at 30 fps: eased, never a step.
var BURST_RISE_FLOOR = 0.35;

// Every row is [default, kind, low, high]. Kinds: bool, num, int, pair (ordered),
// span (a from-to pair, which may descend), minutes, hours. A malformed or
// out-of-range value is REJECTED, never clamped: the documented default applies
// and only the key's index warns, exactly as PARTICLE_SPEC does.
var EVENT_SPEC = {
    phenomenonCap: [3, "int", 1, 3],
    dramaCooldownSec: [900, "num", 300, 86400],
    // One master dial on every interval in the catalogue: 2 is twice as many
    // events, 0.5 half as many, 0 turns scheduled events off entirely.
    rateScale: [1, "num", 0, 4],
    phenomenonGainCap: [1.6, "num", 0.3, 3]
};

// v8 rates and gains. v6 shipped every phenomenon at a gain below an ordinary
// bright star's (0.95 linear) and a core sigma of 2.25 px against a star's
// 1.55: measured on his DP-3, a nova was 125/255 where a star is 243/255, and
// star birth 46/255. Three families were off. He reported seeing no cosmic
// events at all (ledger 2283); these are the rates and gains that answer it.
var EVENT_FAMILY_SPEC = {
    starBirth: {
        enabled: [true, "bool"],
        everyMinutes: [[8, 16], "minutes"],
        durationSec: [[80, 170], "pair", 10, 1800],
        gain: [0.60, "num", 0, 0.60],
        condenseSec: [[25, 55], "pair", 1, 600],
        haloPx: [[40, 9], "span", 0.5, 96],
        paletteMix: [0.30, "num", 0, 0.45]
    },
    nova: {
        enabled: [true, "bool"],
        everyMinutes: [[6, 13], "minutes"],
        riseSec: [[1.2, 2.4], "pair", RISE_FLOOR, 30],
        holdSec: [[0.6, 1.6], "pair", 0, 30],
        decaySec: [[20, 45], "pair", 1, 600],
        gain: [0.90, "num", 0, 0.90],
        shellShortSide: [[0.035, 0.06], "pair", 0, 0.25],
        shellGain: [0.26, "num", 0, 0.30],
        paletteMix: [0.30, "num", 0, 0.45]
    },
    redGiant: {
        enabled: [true, "bool"],
        everyMinutes: [[18, 34], "minutes"],
        durationSec: [[140, 280], "pair", 10, 1800],
        gain: [0.60, "num", 0, 0.60],
        swellSec: [[45, 80], "pair", 1, 600],
        collapseSec: [[30, 55], "pair", 1, 600],
        nebulaShortSide: [0.030, "num", 0, 0.25],
        nebulaGain: [0.16, "num", 0, 0.20]
    },
    // v9 SUPERNOVA. A force-fired v8 supernova on his 2880x1800 tablet was a
    // ~40 px dot with a soft halo (evidence/v8-fire-supernova-tablet-tiny.png):
    // nobody spots that. It is a four-phase LIFE CYCLE now and the keys are its
    // phases -- precursor, core collapse, Sedov shock shell, remnant nebula --
    // so a sky where one happens is a sky where something happened.
    // `flashShortSide` and `shellShortSide` are the drawn DIAMETER as a share of
    // the short side, not a radius: 0.25 is a quarter of the screen across.
    supernova: {
        enabled: [true, "bool"],
        everyHours: [[0.5, 1], "hours"],
        precursorSec: [[10, 20], "pair", 0, 120],
        riseSec: [[0.8, 1.5], "pair", RISE_FLOOR, 30],
        holdSec: [[0.16, 0.28], "pair", 0, 30],
        decaySec: [[25, 60], "pair", 1, 600],
        // v11: the bloom is half what it was and `skyLift` is gone with the
        // whole-sky lift it drove (ledger 2286). A document that still
        // carries the key is accepted and the key is dropped, like any
        // other retired one.
        flashShortSide: [[0.08, 0.12], "pair", 0, 0.6],
        spikeGain: [0.55, "num", 0, 1.5],
        gain: [1.35, "num", 0, 1.35],
        shellSec: [[30, 90], "pair", 5, 600],
        shellShortSide: [[0.25, 0.40], "pair", 0, 0.6],
        shellGain: [0.55, "num", 0, 0.80],
        // v10. The explosion's footprint on the PARTICLE FIELD: how many debris
        // particles the star is replaced by, and how hard the shock shoves the
        // stars it reaches (in short sides per second, falling to nothing at
        // 2.4x the drawn rim). 0 for either leaves the sprite alone.
        debrisCount: [[300, 400], "pair", 0, 480],
        shockShortSide: [0.32, "num", 0, 2],
        filaments: [0.70, "num", 0, 1.5],
        // v11 remnant structure. Shares, all of them, and all defaulted from
        // the two Cas A references rather than from taste: the interior is
        // mostly dark bubbles, the sheets between the lit threads are dusty
        // enough to dim the stars behind them, the rim is a field of isolated
        // hot knots, there are red wisps past it and a pair of jets out of it.
        cavities: [0.80, "num", 0, 1],
        dustOpacity: [0.55, "num", 0, 1],
        knotGain: [0.55, "num", 0, 2],
        wispGain: [0.30, "num", 0, 1.5],
        jetGain: [0.34, "num", 0, 1.5],
        jetReach: [1.30, "num", 0, 3],
        jetWidth: [0.10, "num", 0.01, 1],
        remnantSec: [[120, 300], "pair", 1, 1800],
        remnantGain: [0.26, "num", 0, 0.40],
        pulsarGain: [0.30, "num", 0, 0.60],
        pulsarPeriodSec: [1.4, "num", PERIOD_FLOOR, 60],
        hypernovaShare: [0.15, "num", 0, 1],
        hypernovaGain: [1.60, "num", 0, 1.60],
        hypernovaCooldownSec: [10800, "num", 600, 604800],
        paletteMix: [0.35, "num", 0, 0.45]
    },
    kilonova: {
        enabled: [true, "bool"],
        everyHours: [[0.6, 1.4], "hours"],
        flashSec: [0.6, "num", 0.35, 5],
        gain: [1.10, "num", 0, 1.10],
        ringShortSide: [0.05, "num", 0, 0.25],
        ringGain: [0.34, "num", 0, 0.40],
        ringSec: [[8, 15], "pair", 1, 120]
    },
    pulsar: {
        enabled: [true, "bool"],
        everyHours: [[0.5, 1.1], "hours"],
        durationSec: [[120, 260], "pair", 10, 1800],
        periodSec: [[0.9, 2.2], "pair", PERIOD_FLOOR, 60],
        gain: [0.70, "num", 0, 0.70],
        floorFraction: [0.55, "num", FLOOR_FRACTION, 1],
        edgeSec: [0.14, "num", EDGE_FLOOR, 5]
    },
    gammaBurst: {
        enabled: [true, "bool"],
        everyHours: [[0.7, 1.8], "hours"],
        riseSec: [[0.4, 0.7], "pair", BURST_RISE_FLOOR, 30],
        flashSec: [[0.5, 0.8], "pair", 0.1, 5],
        gain: [1.00, "num", 0, 1.00],
        beamShortSide: [[0.10, 0.18], "pair", 0, 0.25],
        beamGain: [0.42, "num", 0, 0.50],
        afterglowSec: [[30, 90], "pair", 1, 600]
    },
    satelliteGlint: {
        enabled: [true, "bool"],
        gain: [2.2, "num", 1, 4],
        widthSec: [[1.5, 3], "pair", 0.5, 30]
    },
    // The nebula passage: a cloud, not a point. sizeShortSide is its DIAMETER
    // as a fraction of the short side, gain its peak linear emission (the
    // renderer's own cap is what keeps the sky dark: q99 <= 0.35 linear at
    // 0.35), dustOpacity how much of the far field its lanes take away, and
    // `stars` the number of embedded young stars, rounded by the renderer.
    nebula: {
        enabled: [true, "bool"],
        everyMinutes: [[20, 45], "minutes"],
        durationSec: [[180, 480], "pair", 60, 1800],
        fadeSec: [[30, 60], "pair", 5, 300],
        sizeShortSide: [[0.40, 0.80], "pair", 0.15, 1.2],
        gain: [0.30, "num", 0, 0.35],
        dustOpacity: [0.55, "num", 0, 0.9],
        stars: [[1, 3], "pair", 0, 3],
        starGain: [0.45, "num", 0, 0.8],
        paletteMix: [0.40, "num", 0, 0.45],
        // A fraction of the far dust's own rate. 1 is exactly the dust's speed,
        // which crosses from the edge to the hole in 60-200 s: a fly-past
        // rather than a passage.
        driftScale: [0.45, "num", 0.05, 2],
        // v10. What the passage does to the material inside it rather than to
        // the light in front of it: the camera's approach slows by `drag` while
        // a particle is inside the cloud, and it takes `tint` of the cloud's
        // own colour. Both are deliberately small -- it is a passage, not a
        // wall.
        drag: [0.55, "num", 0, 2],
        tint: [0.30, "num", 0, 1]
    }
};

// Closed and sparse, like PARTICLE_SPEC: only a key the file carries reaches the
// renderer, so an absent key keeps the renderer's own documented default.
var PHENOMENA_SPEC = {
    tde: {
        group: {
            enabled: {
                boolean: true
            },
            everyMinutes: {
                pair: [1, 1440]
            },
            // The maximum feeds the one-time particle atlas ceiling; see PARTICLES.md.
            streakPx: {
                pair: [0, 160]
            },
            stretchSec: {
                pair: [1, 120]
            },
            fragments: {
                pair: [1, 16]
            },
            diskFlash: {
                number: [0, 0.5]
            }
        }
    },
    microlensing: {
        group: {
            enabled: {
                boolean: true
            },
            gainCap: {
                number: [1, 3]
            }
        }
    },
    moods: {
        group: {
            clearing: {
                number: [0, 1]
            },
            nebular: {
                number: [0, 1]
            }
        }
    }
};

function familyValue(value, kind, low, high) {
    if (kind === "bool")
        return typeof value === "boolean" ? value : undefined;
    if (kind === "num")
        return finite(value) && value >= low && value <= high ? value : undefined;
    if (kind === "int")
        return integral(value) && value >= low && value <= high ? value : undefined;
    if (kind === "minutes")
        return everyMinutes(value);
    if (kind === "hours")
        return everyHours(value);
    if (kind === "pair")
        return orderedPair(value, low, high);
    // A span runs from its first value to its second and may descend (a halo that
    // condenses), so only the bounds apply, never the ordering.
    if (!Array.isArray(value) || value.length !== 2 || !finite(value[0]) || !finite(value[1]))
        return undefined;
    return Math.min(value[0], value[1]) >= low && Math.max(value[0], value[1]) <= high ? [value[0], value[1]] : undefined;
}

// A family object is closed; the events root is not, because its siblings belong
// to the v4 validators above, so `open` skips a key this spec does not own.
function validateFamily(value, spec, warn, open) {
    var input = object(value), keys = Object.keys(input), taken = {}, out = {}, i;
    for (i = 0; i < keys.length; i++) {
        var key = keys[i], row = own(spec, key) ? spec[key] : null;
        if (!row && open)
            continue;
        var accepted = row ? familyValue(input[key], row[1], row[2], row[3]) : undefined;
        if (accepted === undefined)
            warned(warn, i);
        else
            taken[key] = accepted;
    }
    var names = Object.keys(spec);
    for (i = 0; i < names.length; i++) {
        var name = names[i], fallback = spec[name][0];
        out[name] = own(taken, name) ? taken[name] : (Array.isArray(fallback) ? fallback.slice() : fallback);
    }
    return out;
}

function validateEvents(value, warn) {
    var e = object(value), s = object(e.shower), w = object(e.slowWanderer);
    // v4 keys keep their v4 clamping; every v6 key rejects instead.
    var out = {
        headCap: Math.round(number(e.headCap, 3, 1, 3)),
        // The meteor storm. v8's three keys keep their names, their meaning and
        // their v4 CLAMPING; only their bounds widened, which can never reject a
        // file that used to validate. Everything after `gain` is v9: the shape
        // of the rate hump, the look of a streak, and the fireballs.
        shower: {
            enabled: boolean(s.enabled, true),
            everyHours: interval(s.everyHours, [0.42, 1], 0.25, 168),
            durationSec: interval(s.durationSec, [70, 130], 20, 600),
            gain: number(s.gain, 1, 0, 1.5),
            rampFraction: number(s.rampFraction, 0.32, 0.1, 0.6),
            peakRate: number(s.peakRate, 6, 0.2, 8),
            radiantBias: number(s.radiantBias, 0.28, 0, 0.45),
            paletteMix: number(s.paletteMix, 0.30, 0, 0.45),
            streakShortSide: interval(s.streakShortSide, [0.10, 0.30], 0, 0.45),
            headPx: interval(s.headPx, [3, 6], 1, 12),
            fireballs: interval(s.fireballs, [1, 3], 0, 6),
            trainSec: interval(s.trainSec, [12, 26], 0, 60),
            earthgrazerShare: number(s.earthgrazerShare, 0.08, 0, 0.35),
            fragmentShare: number(s.fragmentShare, 0.06, 0, 0.35)
        },
        slowWanderer: {
            enabled: boolean(w.enabled, true),
            everyHours: interval(w.everyHours, [0.75, 2], 0.25, 168),
            durationSec: interval(w.durationSec, [180, 360], 180, 360),
            gain: number(w.gain, 0.75, 0, 0.75)
        }
    };
    var caps = validateFamily(e, EVENT_SPEC, warn, true);
    out.phenomenonCap = caps.phenomenonCap;
    out.dramaCooldownSec = caps.dramaCooldownSec;
    out.rateScale = caps.rateScale;
    out.phenomenonGainCap = caps.phenomenonGainCap;
    var names = Object.keys(EVENT_FAMILY_SPEC);
    for (var i = 0; i < names.length; i++)
        out[names[i]] = validateFamily(e[names[i]], EVENT_FAMILY_SPEC[names[i]], warn);
    return out;
}

function validatePhenomena(value, warn) {
    return validateGroup(value, PHENOMENA_SPEC, false, warn);
}

// Closed-object schemas. A key is forwarded only when the file carries it, so a
// renderer default (and a black-hole preset fallback) owns every absent key.
var PARTICLE_SPEC = {
    population: {
        group: {
            near: {
                integer: [0, 3200]
            },
            middle: {
                integer: [0, 3200]
            }
        }
    },
    stressPreset: {
        boolean: true
    },
    // v10. The transient reserve: how many event particles (supernova debris, a
    // comet's nucleus and the motes it sheds, a fireball's spray) may be alive
    // at once, and how long a star shoved by a shock takes to relax back into
    // the flow. The reserve is ATLAS-ALLOCATED whether or not an event ever
    // fires, because a resize of the sampled texture cost 13 ms -> 6700 ms per
    // frame on llvmpipe and never recovered; 0 turns the footprint off and
    // gives the rows back.
    debris: {
        group: {
            maxAlive: {
                integer: [0, 480]
            },
            relaxSec: {
                number: [0.05, 12]
            }
        }
    },
    vref: {
        number: [10, 600]
    },
    launch: {
        group: {
            plunge: {
                number: [0, 1]
            },
            miss: {
                number: [0, 1]
            },
            wide: {
                number: [0, 1]
            },
            betaBound: {
                pair: [0.10, 0.99]
            },
            unboundShare: {
                number: [0, 1]
            },
            betaUnbound: {
                pair: [1.001, 2]
            },
            handedness: {
                number: [0, 1]
            }
        }
    },
    capture: {
        group: {
            radius: {
                pair: [1.05, 8]
            },
            gamma: {
                number: [0, 2]
            },
            spiralSec: {
                pair: [5, 240]
            }
        }
    },
    epsilonRh: {
        number: [0.01, 0.20]
    },
    substeps: {
        integer: [4, 32]
    },
    streak: {
        group: {
            exposureSec: {
                number: [0, 0.10]
            },
            maxPx: {
                number: [0, 32]
            }
        }
    },
    sizes: {
        group: {
            nearPx: {
                pair: [0.25, 12]
            },
            middlePx: {
                pair: [0.25, 12]
            },
            capturedPx: {
                pair: [0.25, 12]
            }
        }
    },
    safetyLifeSec: {
        pair: [30, 600]
    }
};

var BLACK_HOLE_SPEC = {
    enabled: {
        boolean: true
    },
    size: {
        number: [0.01, 0.2]
    },
    tilt: {
        number: [1, 35]
    },
    intensity: {
        number: [0, 1]
    },
    warmth: {
        number: [0, 1]
    },
    spin: {
        number: [0, 2]
    },
    diskInnerRs: {
        number: [3, 6]
    },
    diskOuterRs: {
        number: [3.5, 12]
    },
    beamStrength: {
        number: [0, 0.2]
    },
    haloUpper: {
        number: [0, 1]
    },
    haloLower: {
        number: [0, 1]
    },
    photonWidth: {
        number: [0.001, 0.02]
    },
    // Legacy field: its 0.08 cap belongs here and never to disk.detail.
    structure: {
        number: [0, 0.08]
    },
    tiltWander: {
        number: [0, 1]
    },
    transitionSec: {
        number: [30, 300]
    },
    preset: {
        choices: ["", "target"]
    },
    footprintCap: {
        number: [0.01, 0.12]
    },
    diskCap: {
        number: [0.10, 1]
    },
    photonCap: {
        number: [0.10, 1]
    },
    disk: {
        group: {
            detail: {
                number: [0, 0.85]
            },
            seed: {
                integer: [0, 65535]
            },
            rotationSign: {
                integer: [-1, 1]
            },
            exposure: {
                number: [0.5, 2]
            },
            streaks: {
                group: {
                    octaves: {
                        integer: [1, 3]
                    },
                    radialScale: {
                        number: [0.5, 2]
                    },
                    innerCyclesPer4096: {
                        integer: [16, 128]
                    },
                    warp: {
                        number: [0, 0.25]
                    },
                    grain: {
                        number: [0, 0.08]
                    }
                }
            },
            knots: {
                group: {
                    density: {
                        number: [0, 0.06]
                    },
                    gain: {
                        number: [0, 0.5]
                    }
                }
            },
            embers: {
                group: {
                    count: {
                        integer: [0, 32]
                    },
                    radiusRs: {
                        number: [0.004, 0.025]
                    },
                    trailSec: {
                        number: [0, 0.6]
                    },
                    gain: {
                        number: [0, 0.06]
                    }
                }
            },
            doppler: {
                group: {
                    preset: {
                        choices: ["film", "physical"]
                    },
                    strength: {
                        number: [0, 1]
                    }
                }
            },
            hue: {
                group: {
                    innerTemperature: {
                        number: [4200, 10000]
                    },
                    outerTemperature: {
                        number: [1000, 2800]
                    },
                    warmth: {
                        number: [0, 1]
                    },
                    whiteness: {
                        number: [0, 1]
                    }
                }
            },
            glow: {
                group: {
                    gain: {
                        number: [0, 0.008]
                    },
                    radiusPx: {
                        number: [0.25, 2.5]
                    }
                }
            },
            arcs: {
                group: {
                    gain: {
                        number: [0, 0.02]
                    },
                    radiusRh: {
                        number: [1.2, 2.6]
                    },
                    spacingRh: {
                        number: [0.2, 1]
                    },
                    count: {
                        integer: [0, 2]
                    }
                }
            }
        }
    },
    photon: {
        group: {
            mode: {
                choices: ["shared-field", "off"]
            },
            widthPx: {
                number: [0.1, 0.75]
            },
            gain: {
                number: [0, 1.5]
            },
            textureStrength: {
                number: [0, 1]
            }
        }
    }
};

function warned(warn, index) {
    // Same contract as the palette warning: the index is the entire payload.
    if (typeof warn === "function")
        warn(index);
    else
        console.warn(index);
}

function integral(value) {
    return finite(value) && Math.floor(value) === value;
}

// One closed-object walk. clamped=true keeps the v3 black-hole habit of pulling
// a finite number into range; clamped=false rejects instead of repairing, so a
// malformed particle value falls back to the renderer default it documents.
function validateGroup(value, spec, clamped, warn) {
    var input = object(value), out = {}, keys = Object.keys(input);
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i], v = input[key], rule = own(spec, key) ? spec[key] : null;
        if (!rule) {
            warned(warn, i);
        } else if (rule.group !== undefined) {
            if (v !== null && typeof v === "object" && !Array.isArray(v))
                out[key] = validateGroup(v, rule.group, clamped, warn);
            else
                warned(warn, i);
        } else if (rule.boolean) {
            if (typeof v === "boolean")
                out[key] = v;
            else
                warned(warn, i);
        } else if (rule.choices !== undefined) {
            if (typeof v === "string" && rule.choices.indexOf(v) !== -1)
                out[key] = v;
            else
                warned(warn, i);
        } else if (rule.pair !== undefined) {
            // Ordered pairs are never sorted here; an inverted pair is malformed.
            if (Array.isArray(v) && v.length === 2 && finite(v[0]) && finite(v[1]) && v[0] <= v[1] && v[0] >= rule.pair[0] && v[1] <= rule.pair[1])
                out[key] = [v[0], v[1]];
            else
                warned(warn, i);
        } else {
            var bounds = rule.integer !== undefined ? rule.integer : rule.number;
            var ok = rule.integer !== undefined && !clamped ? integral(v) : finite(v);
            if (ok && !clamped)
                ok = v >= bounds[0] && v <= bounds[1];
            if (!ok)
                warned(warn, i);
            else if (rule.integer !== undefined)
                out[key] = Math.round(clamp(v, bounds[0], bounds[1]));
            else
                out[key] = clamp(v, bounds[0], bounds[1]);
        }
    }
    return out;
}

function validateParticles(value, warn) {
    var input = object(value), out = validateGroup(input, PARTICLE_SPEC, false, warn);
    if (!own(out, "population"))
        return out;
    // The shared 3200 budget is rejected whole, never reduced proportionally.
    var stress = out.stressPreset === true, p = out.population;
    var near = own(p, "near") ? p.near : (stress ? 600 : 120);
    var middle = own(p, "middle") ? p.middle : (stress ? 1500 : 480);
    if (near + middle > 3200) {
        delete out.population;
        warned(warn, Object.keys(input).indexOf("population"));
    }
    return out;
}

function validateBlackHole(value, warn) {
    var out = validateGroup(value, BLACK_HOLE_SPEC, true, warn);
    // v3 geometry rule survives: the outer radius never crosses the inner one.
    if (own(out, "diskOuterRs")) {
        var inner = own(out, "diskInnerRs") ? out.diskInnerRs : 3;
        out.diskOuterRs = Math.max(out.diskOuterRs, inner + 0.5);
    }
    return out;
}

function defaultReactive() {
    return {
        enabled: true,
        contextScope: "perScreen",
        processPresenceWeight: 0.35,
        paletteBudget: 0.45,
        birthTauSec: 60,
        liveTauSec: 90,
        maxChangePerSec: 0.005,
        matchers: [
            {
                id: "htb",
                "class": "^zen$",
                title: "\\bHTB\\b|Hack\\s*The\\s*Box|hackthebox\\.(com|eu)",
                flags: "i"
            },
            {
                id: "steam",
                "class": "^steam$",
                flags: "i"
            },
            {
                id: "game",
                "class": "^steam_app_[0-9]+$",
                flags: "i"
            },
            {
                id: "terminal",
                "class": "^(foot|footclient)$"
            },
            {
                id: "agentWindow",
                "class": "^(foot|footclient)$",
                title: "^[✳◑]"
            }
        ],
        rules: [
            {
                signal: "htb",
                add: {
                    palette: {
                        green: 0.35,
                        teal: 0.08
                    }
                }
            },
            {
                signal: "rain",
                add: {
                    archetypes: {
                        decayer: 0.025,
                        pulsator: -0.02
                    },
                    calm: 0.12,
                    twinkle: -0.08
                }
            },
            {
                signal: "night",
                add: {
                    palette: {
                        blue: 0.16,
                        purple: 0.10
                    },
                    calm: 0.12,
                    flow: -0.08,
                    meteor: -0.12
                }
            },
            {
                signal: "agent",
                add: {
                    archetypes: {
                        wanderer: 0.007
                    },
                    palette: {
                        purple: 0.16,
                        teal: 0.06
                    }
                }
            },
            {
                signal: "load",
                add: {
                    archetypes: {
                        pulsator: 0.04
                    }
                }
            },
            {
                signal: "heat",
                add: {
                    palette: {
                        orange: 0.18,
                        red: 0.08
                    }
                }
            },
            {
                signal: "media",
                add: {
                    archetypes: {
                        pulsator: 0.01
                    }
                }
            },
            {
                signal: "idle",
                add: {
                    calm: 0.08,
                    meteor: -0.08
                }
            },
            {
                signal: "workspaceActivity",
                enabled: false,
                add: {
                    archetypes: {
                        wanderer: 0.003
                    }
                }
            },
            {
                signal: "network",
                enabled: false,
                add: {
                    archetypes: {
                        glint: 0.002
                    }
                }
            },
            {
                signal: "notifications",
                enabled: false,
                add: {
                    archetypes: {
                        pulsator: 0.003
                    }
                }
            },
            {
                signal: "gpuLoad",
                add: {
                    hole: {
                        activity: 0.25
                    }
                }
            },
            {
                signal: "heat",
                add: {
                    hole: {
                        warmth: 0.15,
                        brightness: 0.20
                    }
                }
            },
            {
                signal: "agent",
                add: {
                    hole: {
                        structure: 0.10
                    }
                }
            },
            {
                signal: "night",
                add: {
                    hole: {
                        brightness: -0.15
                    }
                }
            },
            {
                signal: "agentFalling",
                enabled: false,
                add: {
                    events: {
                        nova: 0.6
                    }
                }
            },
            {
                signal: "heat",
                enabled: false,
                add: {
                    events: {
                        redGiant: 0.4
                    }
                }
            },
            {
                signal: "gpuLoad",
                enabled: false,
                add: {
                    events: {
                        tde: 0.3
                    }
                }
            },
            {
                signal: "night",
                enabled: false,
                add: {
                    events: {
                        starBirth: 0.3,
                        supernova: -0.3
                    }
                }
            }
        ]
    };
}

function patternValid(pattern, flags) {
    if (typeof pattern !== "string" || !pattern.length || pattern.length > MAX_PATTERN)
        return false;
    // Bound GUI-thread matching: no backreferences, lookarounds or repeated groups.
    if (/\\[1-9]|\(\?|\)[+*{]/.test(pattern))
        return false;
    try {
        new RegExp(pattern, flags);
        return true;
    } catch (error) {
        return false;
    }
}

function validateMatchers(value) {
    var result = [], seen = Object.create(null);
    if (!Array.isArray(value))
        return result;
    for (var i = 0; i < Math.min(value.length, MAX_ENTRIES); i++) {
        var m = object(value[i]), id = m.id, flags = m.flags === undefined ? "" : m.flags;
        if (typeof id !== "string" || !/^[A-Za-z][A-Za-z0-9_]{0,47}$/.test(id) || own(seen, id) || id === "constructor" || id === "prototype" || (SIGNALS.indexOf(id) !== -1 && id !== "agentWindow"))
            continue;
        seen[id] = true;
        var validFlags = typeof flags === "string" && /^(i?m?|mi)$/.test(flags);
        var valid = validFlags && patternValid(m["class"], flags) && (m.title === undefined || patternValid(m.title, flags));
        // Invalid entries survive only as disabled category IDs; never throw away siblings.
        result.push({
            id: id,
            "class": valid ? m["class"] : "",
            title: valid ? m.title : undefined,
            flags: validFlags ? flags : "",
            enabled: valid && boolean(m.enabled, true)
        });
    }
    return result;
}

function validateReactive(value) {
    var r = object(value), defaults = defaultReactive();
    var matchers = validateMatchers(r.matchers === undefined ? defaults.matchers : r.matchers);
    var known = SIGNALS.slice(), i;
    for (i = 0; i < matchers.length; i++)
        if (matchers[i].enabled)
            known.push(matchers[i].id);
    var input = r.rules === undefined ? defaults.rules : r.rules;
    var rules = [];
    if (Array.isArray(input)) {
        for (i = 0; i < Math.min(input.length, MAX_ENTRIES); i++) {
            var entry = object(input[i]), add = object(entry.add), clean = {};
            for (var c = 0; c < CONTROLS.length; c++) {
                var key = CONTROLS[c];
                if (finite(add[key]))
                    clean[key] = clamp(add[key], -1, 1);
            }
            var groups = ["palette", "archetypes", "hole", "events"];
            var lists = {
                archetypes: ARCHETYPES,
                hole: HOLE,
                events: EVENT_TARGETS
            };
            for (var g = 0; g < groups.length; g++) {
                var group = groups[g], nested = object(add[group]), keys = Object.keys(nested), accepted = {};
                for (var k = 0; k < Math.min(keys.length, group === "palette" ? 32 : lists[group].length); k++) {
                    var name = keys[k];
                    var allowed = group === "palette" ? (validId(name) || /^(0|[1-9][0-9]{0,5})$/.test(name)) : lists[group].indexOf(name) !== -1;
                    if (allowed && finite(nested[name]))
                        accepted[name] = clamp(nested[name], -1, 1);
                }
                if (Object.keys(accepted).length)
                    clean[group] = accepted;
            }
            rules.push({
                signal: typeof entry.signal === "string" ? entry.signal.slice(0, 48) : "",
                enabled: boolean(entry.enabled, true) && known.indexOf(entry.signal) !== -1 && Object.keys(clean).length > 0,
                add: clean
            });
        }
    }
    return {
        enabled: boolean(r.enabled, true),
        contextScope: "perScreen",
        processPresenceWeight: number(r.processPresenceWeight, 0.35, 0, 1),
        paletteBudget: number(r.paletteBudget, 0.45, 0, 0.45),
        // Frozen renderer API has no filter-setting properties. Keep these contract constants.
        birthTauSec: 60,
        liveTauSec: 90,
        maxChangePerSec: 0.005,
        matchers: matchers,
        rules: rules
    };
}

// The camera fly-through. `enabled` is "auto" by default, which ties the whole
// regime to the black hole: a hole that is off has no mass to fall into, so the
// field stops being an infall and becomes a camera moving forward through a
// nearly static sky. true/false force it on or off regardless of the hole.
// `direction` "out" is the camera flying toward the centre (stars stream out of
// it and leave at the edges); "in" is the same playback reversed.
function validateCamera(value) {
    var c = object(value);
    return {
        enabled: c.enabled === true || c.enabled === false ? c.enabled : "auto",
        direction: c.direction === "in" ? "in" : "out",
        speed: number(c.speed, 6, 0, 30),
        depth: number(c.depth, 16, 2, 64),
        dustFlow: number(c.dustFlow, 3, 0, 64),
        roll: number(c.roll, 0.15, 0, 2),
        wander: number(c.wander, 0.35, 0, 1),
        sizeGain: number(c.sizeGain, 0.55, 0, 1)
    };
}

function validateDocument(value, warn) {
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
        screens: screens,
        // Which process draws the sky. "separate" is the second Quickshell
        // instance (starfield.qml); "shell" is the old in-shell path, kept for
        // A/B. Either way this document is the only configuration.
        process: d.process === "shell" ? "shell" : "separate",
        density: number(d.density, 1, 0, 3),
        driftSpeed: number(d.driftSpeed, 3.5, 0, 30),
        driftDirection: number(d.driftDirection, 165, -360, 360),
        twinkle: number(d.twinkle, 0.22, 0, 1),
        flareFraction: number(d.flareFraction, 0.003, 0, 0.025),
        brightness: number(d.brightness, 1, 0, 3),
        edgeLift: number(d.edgeLift, 0, 0, 1),
        backgroundColor: typeof d.backgroundColor === "string" && /^#[0-9a-fA-F]{6}$/.test(d.backgroundColor) ? d.backgroundColor : "#000000",
        fps: Math.round(number(d.fps, 30, 1, 60)),
        motion: {
            mode: mode,
            radialSpeed: number(m.radialSpeed, 6, 0, 26),
            centreWander: number(m.centreWander, 0.012, 0, 0.05),
            zoom: number(m.zoom, mode === "drift" ? 0.025 : 0.003, 0, 0.15),
            reversals: boolean(m.reversals, false),
            wander: number(m.wander, 0.8, 0, 2),
            rotation: number(m.rotation, 0.5, 0, 3),
            camera: validateCamera(m.camera)
        },
        variety: {
            enabled: boolean(v.enabled, true),
            seed: Math.round(number(v.seed, 1, 0, 2147483647))
        },
        variables: {
            fraction: number(variables.fraction, 0.006, 0, 0.05)
        },
        meteors: {
            enabled: boolean(meteor.enabled, true),
            interval: interval(meteor.interval, [45, 120], 3),
            companionChance: number(meteor.companionChance, 0.04, 0, 1),
            fireballChance: number(meteor.fireballChance, 0.01, 0, 1),
            paletteMix: number(meteor.paletteMix, 0.25, 0, 0.45),
            families: validateFamilies(meteor.families, false)
        },
        comet: {
            enabled: boolean(comet.enabled, true),
            interval: interval(comet.interval, [300, 900], 60),
            paletteMix: number(comet.paletteMix, 0.35, 0, 0.45),
            families: validateFamilies(comet.families, true)
        },
        satellites: {
            enabled: boolean(satellites.enabled, true),
            interval: interval(satellites.interval, [150, 330], 45)
        },
        palette: validatePalette(d.palette, warn),
        archetypes: validateArchetypes(d.archetypes),
        events: validateEvents(d.events, warn),
        phenomena: validatePhenomena(d.phenomena, warn),
        blackHole: validateBlackHole(d.blackHole, warn),
        particles: validateParticles(d.particles, warn),
        particlesEnabled: boolean(d.particlesEnabled, true),
        reactive: validateReactive(d.reactive)
    };
}

function parseDocument(text, warn) {
    try {
        return validateDocument(JSON.parse(text), warn);
    } catch (error) {
        return validateDocument(null, warn);
    }
}

function compileMatchers(matchers) {
    var compiled = [];
    for (var i = 0; i < matchers.length; i++) {
        var m = matchers[i];
        if (!m.enabled)
            continue;
        compiled.push({
            id: m.id,
            classRx: new RegExp(m["class"], m.flags),
            titleRx: m.title === undefined ? null : new RegExp(m.title, m.flags)
        });
    }
    return compiled;
}

function sameWorkspace(a, b) {
    if (!a || !b)
        return false;
    if (a.id !== undefined && b.id !== undefined && a.id === b.id && a.id !== 0)
        return true;
    return !!a.name && !!b.name && a.name === b.name;
}

function onOutput(t, monitor) {
    if (!t || !monitor)
        return false;
    var ipc = t.lastIpcObject || {}, ws = t.workspace || ipc.workspace || {};
    var owner = t.monitor || ws.monitor;
    if (owner)
        return owner === monitor || (typeof owner.name === "string" && owner.name.length > 0 && owner.name === monitor.name) || (owner.id !== undefined && owner.id === monitor.id);
    return ipc.monitor !== undefined && (ipc.monitor === monitor.id || ipc.monitor === monitor.name);
}

function visible(t, monitor) {
    if (!t || !monitor)
        return false;
    var ipc = t.lastIpcObject || {}, mi = monitor.lastIpcObject || {};
    if (t.mapped === false || ipc.mapped === false || t.hidden === true || ipc.hidden === true || t.minimized === true || ipc.minimized === true || ipc.minimised === true || (t.wayland && t.wayland.minimized === true) || !onOutput(t, monitor))
        return false;
    var ws = t.workspace || ipc.workspace;
    return t.pinned === true || ipc.pinned === true || sameWorkspace(ws, monitor.activeWorkspace || mi.activeWorkspace) || sameWorkspace(ws, monitor.specialWorkspace || mi.specialWorkspace);
}

function visibilityWeight(t, monitor, active) {
    if (!visible(t, monitor))
        return 0;
    return t === active || t.activated === true || (t.wayland && t.wayland.activated === true) ? 1 : 0.6;
}

function runningFor(monitor, toplevels, locked) {
    if (locked)
        return false;
    for (var i = 0; i < toplevels.length; i++) {
        var t = toplevels[i], ipc = t.lastIpcObject || {};
        if (visible(t, monitor) && number(ipc.fullscreen, number(t.fullscreen, 0, 0, 3), 0, 3) > 1)
            return false;
    }
    return true;
}

function categories(compiled, toplevels, monitor, active) {
    var result = Object.create(null);
    for (var m = 0; m < compiled.length; m++)
        result[compiled[m].id] = 0;
    for (var i = 0; i < toplevels.length; i++) {
        var t = toplevels[i], weight = visibilityWeight(t, monitor, active);
        if (!weight)
            continue;
        var ipc = t.lastIpcObject || {};
        var appClass = typeof ipc["class"] === "string" ? ipc["class"].slice(0, 256) : "";
        for (m = 0; m < compiled.length; m++) {
            var matcher = compiled[m];
            if (!matcher.classRx.test(appClass))
                continue;
            // Read only AFTER class matching. Never attach a title or window to the result/state.
            if (matcher.titleRx) {
                var title = typeof t.title === "string" ? t.title : (typeof ipc.title === "string" ? ipc.title : "");
                if (!matcher.titleRx.test(title.slice(0, 512)))
                    continue;
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

function nearestHue(palette, degrees) {
    var best = -1, distance = 30 + 1e-9;
    for (var i = 0; i < palette.hues.length; i++) {
        if (palette.hues[i] === null)
            continue;
        var gap = Math.abs(palette.hues[i] - degrees);
        gap = Math.min(gap, 360 - gap);
        if (gap < distance) {
            best = i;
            distance = gap;
        }
    }
    return best;
}

function paletteIndex(palette, key) {
    if (/^(0|[1-9][0-9]{0,5})$/.test(key))
        return palette.sourceIndices.indexOf(Number(key));
    var index = palette.ids.indexOf(key);
    return index !== -1 ? index : own(ROLE_HUES, key) ? nearestHue(palette, ROLE_HUES[key]) : -1;
}

function archetypeProbabilities(values, steadyAdd) {
    var out = values.slice(), sum = 0, i;
    for (i = 1; i < 6; i++) {
        out[i] = Math.max(0, out[i]);
        sum += out[i];
    }
    out[0] = Math.max(0, 1 - sum + steadyAdd);
    out = normalize(out, [1, 0, 0, 0, 0, 0]);
    sum = 1 - out[0];
    if (sum > 0.25) {
        for (i = 1; i < 6; i++)
            out[i] *= 0.25 / sum;
        out[0] = 0.75;
    }
    return out;
}

function evaluate(config, signals, palette, archetypes) {
    palette = palette || validatePalette(null);
    archetypes = archetypes || validateArchetypes(null);
    var target = [0, 0, 0, 0.5, 0.5, 0.5, 0.5, 0.5, palette.mix];
    var weights = palette.baseWeights.slice(), types = [], hole = [0.5, 0.5, 0.5, 0.5], steadyAdd = 0, eventAdds = {};
    for (var a = 0; a < ARCHETYPES.length; a++)
        types.push(archetypes.weights[ARCHETYPES[a]]);
    if (config.enabled) {
        for (var i = 0; i < config.rules.length; i++) {
            var rule = config.rules[i];
            if (!rule.enabled || !own(signals, rule.signal) || !finite(signals[rule.signal]))
                continue;
            var strength = clamp(signals[rule.signal], 0, 1);
            for (var c = 0; c < CONTROLS.length; c++) {
                var add = rule.add[CONTROLS[c]];
                if (!finite(add))
                    continue;
                if (c < 3) {
                    var legacyIndex = nearestHue(palette, [120, 270, 30][c]);
                    if (legacyIndex === -1)
                        continue;
                    weights[legacyIndex] += strength * add;
                }
                target[c] += strength * add;
            }
            var paletteAdds = object(rule.add.palette), keys = Object.keys(paletteAdds);
            for (var k = 0; k < keys.length; k++) {
                var index = paletteIndex(palette, keys[k]);
                if (index !== -1)
                    weights[index] += strength * paletteAdds[keys[k]];
            }
            var typeAdds = object(rule.add.archetypes), holeAdds = object(rule.add.hole);
            for (a = 0; a < ARCHETYPES.length; a++) {
                if (!finite(typeAdds[ARCHETYPES[a]]))
                    continue;
                if (a === 0)
                    steadyAdd += strength * typeAdds.steady;
                else
                    types[a] += strength * typeAdds[ARCHETYPES[a]];
            }
            for (a = 0; a < HOLE.length; a++)
                if (finite(holeAdds[HOLE[a]]))
                    hole[a] += strength * holeAdds[HOLE[a]];
            var eventTargets = object(rule.add.events);
            for (var t = 0; t < EVENT_TARGETS.length; t++) {
                var family = EVENT_TARGETS[t];
                if (finite(eventTargets[family]))
                    eventAdds[family] = (own(eventAdds, family) ? eventAdds[family] : 0) + strength * eventTargets[family];
            }
        }
    }
    // A bias scales the NEXT scheduled interval and nothing else: a positive add
    // shortens it, and a summed add of +-1 is exactly the 0.5x-2x clamp.
    var eventBias = {}, biased = Object.keys(eventAdds);
    for (var b = 0; b < biased.length; b++)
        eventBias[biased[b]] = clamp(Math.pow(2, -eventAdds[biased[b]]), 0.5, 2);
    for (var j = 0; j < target.length; j++)
        target[j] = clamp(target[j], 0, 1);
    var total = target[0] + target[1] + target[2], budget = number(config.paletteBudget, 0.45, 0, 0.45);
    if (total > budget)
        for (j = 0; j < 3; j++)
            target[j] *= budget / total;
    weights = normalize(weights, palette.baseWeights);
    while (weights.length < 16)
        weights.push(0);
    return {
        birth: target.slice(0, 4),
        live: target.slice(4, 8),
        paletteWeights: weights,
        archetypeWeights: archetypeProbabilities(types, steadyAdd),
        mix: palette.rgb.length ? Math.min(target[8], budget) : 0,
        calm: target[3],
        hole: hole.map(function (v) {
            return clamp(v, 0, 1);
        }),
        eventBias: eventBias
    };
}

function vectorArray(value) {
    return Array.isArray(value) ? value : [value.x, value.y, value.z, value.w];
}
function rounded(value) {
    return finite(value) ? Math.round(value * 1000) / 1000 : 0;
}
function serializeProfile(profile) {
    return {
        running: profile.running,
        birth: vectorArray(profile.birth).map(rounded),
        live: vectorArray(profile.live).map(rounded),
        paletteWeights: profile.paletteWeights.map(rounded),
        archetypeWeights: profile.archetypeWeights.map(rounded),
        mix: rounded(profile.mix),
        calm: rounded(profile.calm),
        hole: vectorArray(profile.hole).map(rounded),
        eventBias: serializeNumbers(object(profile.eventBias))
    };
}
function serializeNumbers(values) {
    var out = Object.create(null), keys = Object.keys(values);
    for (var i = 0; i < keys.length; i++)
        if (finite(values[keys[i]]))
            out[keys[i]] = rounded(values[keys[i]]);
    return out;
}
