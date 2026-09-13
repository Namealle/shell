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
var EVENT_TARGETS = ["meteors", "comet", "satellites", "shower", "slowWanderer", "starBirth", "nova", "redGiant", "supernova", "kilonova", "pulsar", "gammaBurst", "tde"];

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
        fast: [[4, 9], 0.15, 0.55, [0.04, 0.08], [0, 0]],
        slow: [[30, 65], 0.50, 0.26, [0.20, 0.32], [0, 0]],
        bent: [[12, 28], 0.30, 0.38, [0.08, 0.18], [0.02, 0.06]],
        pulsating: [[20, 40], 0.05, 0.32, [0.12, 0.22], [0.02, 0.06]],
        fragmenting: [[8, 16], 0, 0.38, [0.08, 0.16], [0.02, 0.06]],
        spiral: [[18, 35], 0, 0.25, [0.08, 0.16], [0, 0.06]]
    } : {
        straight: [[0.7, 1.3], 0.75, 0.85, [0.08, 0.14], [0, 0]],
        curved: [[0.9, 1.7], 0.20, 0.80, [0.04, 0.10], [0.005, 0.02]],
        skipping: [[1.2, 2.2], 0.05, 0.70, [0.08, 0.14], [0, 0]]
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

// Every row is [default, kind, low, high]. Kinds: bool, num, int, pair (ordered),
// span (a from-to pair, which may descend), minutes, hours. A malformed or
// out-of-range value is REJECTED, never clamped: the documented default applies
// and only the key's index warns, exactly as PARTICLE_SPEC does.
var EVENT_SPEC = {
    phenomenonCap: [2, "int", 1, 2],
    dramaCooldownSec: [4500, "num", 600, 86400]
};

var EVENT_FAMILY_SPEC = {
    starBirth: {
        enabled: [true, "bool"],
        everyMinutes: [[20, 45], "minutes"],
        durationSec: [[180, 360], "pair", 10, 1800],
        gain: [0.22, "num", 0, 0.22],
        condenseSec: [[40, 90], "pair", 1, 600],
        haloPx: [[18, 4], "span", 0.5, 64],
        paletteMix: [0.30, "num", 0, 0.45]
    },
    nova: {
        enabled: [true, "bool"],
        everyMinutes: [[25, 50], "minutes"],
        riseSec: [[1.5, 3], "pair", RISE_FLOOR, 30],
        holdSec: [[0.5, 1.5], "pair", 0, 30],
        decaySec: [[25, 60], "pair", 1, 600],
        gain: [0.45, "num", 0, 0.45],
        shellShortSide: [[0.02, 0.04], "pair", 0, 0.15],
        shellGain: [0.12, "num", 0, 0.12],
        paletteMix: [0.30, "num", 0, 0.45]
    },
    redGiant: {
        enabled: [true, "bool"],
        everyMinutes: [[45, 90], "minutes"],
        durationSec: [[240, 480], "pair", 10, 1800],
        gain: [0.28, "num", 0, 0.28],
        swellSec: [[90, 150], "pair", 1, 600],
        collapseSec: [[45, 75], "pair", 1, 600],
        nebulaShortSide: [0.015, "num", 0, 0.15],
        nebulaGain: [0.06, "num", 0, 0.06]
    },
    supernova: {
        enabled: [true, "bool"],
        everyHours: [[1.5, 3], "hours"],
        riseSec: [[0.8, 1.5], "pair", RISE_FLOOR, 30],
        holdSec: [[0.5, 1.5], "pair", 0, 30],
        decaySec: [[90, 240], "pair", 1, 600],
        gain: [0.70, "num", 0, 0.70],
        remnantSec: [[180, 360], "pair", 1, 1800],
        shellShortSide: [[0.06, 0.11], "pair", 0, 0.15],
        shellGain: [0.10, "num", 0, 0.10],
        echoGain: [0.04, "num", 0, 0.04],
        echoDelaySec: [[60, 120], "pair", 1, 600],
        hypernovaShare: [0.15, "num", 0, 1],
        hypernovaGain: [0.78, "num", 0, 0.78],
        hypernovaCooldownSec: [21600, "num", 600, 604800],
        paletteMix: [0.35, "num", 0, 0.45]
    },
    kilonova: {
        enabled: [false, "bool"],
        minSpacingSec: [3600, "num", 600, 604800],
        maxPerHour: [1, "int", 0, 4],
        flashSec: [0.4, "num", 0.1, 5],
        gain: [0.55, "num", 0, 0.55],
        ringShortSide: [0.03, "num", 0, 0.15],
        ringSec: [[8, 15], "pair", 1, 120]
    },
    pulsar: {
        enabled: [false, "bool"],
        everyHours: [[2, 4], "hours"],
        durationSec: [[240, 600], "pair", 10, 1800],
        periodSec: [[0.8, 2.0], "pair", PERIOD_FLOOR, 60],
        gain: [0.30, "num", 0, 0.30],
        floorFraction: [0.60, "num", FLOOR_FRACTION, 1],
        edgeSec: [0.12, "num", EDGE_FLOOR, 5]
    },
    gammaBurst: {
        enabled: [false, "bool"],
        everyHours: [[4, 12], "hours"],
        flashSec: [[0.5, 0.8], "pair", 0.1, 5],
        gain: [0.45, "num", 0, 0.45],
        beamShortSide: [[0.10, 0.18], "pair", 0, 0.25],
        afterglowSec: [[30, 90], "pair", 1, 600],
        cooldownSec: [14400, "num", 600, 604800]
    },
    satelliteGlint: {
        enabled: [true, "bool"],
        gain: [2.2, "num", 1, 4],
        widthSec: [[1.5, 3], "pair", 0.5, 30]
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
        shower: {
            enabled: boolean(s.enabled, true),
            everyHours: interval(s.everyHours, [2, 5], 2, 168),
            durationSec: interval(s.durationSec, [30, 60], 30, 60),
            gain: number(s.gain, 0.60, 0, 0.60)
        },
        slowWanderer: {
            enabled: boolean(w.enabled, true),
            everyHours: interval(w.everyHours, [2, 6], 2, 168),
            durationSec: interval(w.durationSec, [180, 360], 180, 360),
            gain: number(w.gain, 0.40, 0, 0.40)
        }
    };
    var caps = validateFamily(e, EVENT_SPEC, warn, true);
    out.phenomenonCap = caps.phenomenonCap;
    out.dramaCooldownSec = caps.dramaCooldownSec;
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
            rotation: number(m.rotation, 0.5, 0, 3)
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
            interval: interval(comet.interval, [900, 1800], 60),
            paletteMix: number(comet.paletteMix, 0.35, 0, 0.45),
            families: validateFamilies(comet.families, true)
        },
        satellites: {
            enabled: boolean(satellites.enabled, true),
            interval: interval(satellites.interval, [240, 480], 45)
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
