import QtQuick

// State provider only. Advance time with the renderer's active clock.
QtObject {
    id: root

    // "" keeps the v4 defaults. A named preset only supplies fallbacks: any
    // property the service assigns explicitly replaces its binding and wins.
    property string preset: ""
    readonly property var presets: ({
            target: {
                // Every value below is the result of a measured fit against
                // ~/Downloads/LocalSend/wallpaper.png, not taste: see
                // tools/bh_ringdiff.py for the metrics and tools/bh_fit.py for
                // the objective. Re-run them before changing any of it.
                size: 0.11,
                tilt: 13,
                intensity: 1,
                // Gains on the LENSED (order-1) arcs over and under the shadow.
                // Down from 1/0.9 now that disk.halo carries the ring hugging
                // the shadow: it thins the disk vertically without emptying it.
                haloUpper: 0.82,
                haloLower: 0.51,
                diskOuterRs: 11,
                lensReach: 8,
                lensStretch: 1.6,
                footprintCap: 0.2,
                // White level. The reference peaks at 0.962 linear and its
                // q99.9 is 0.958; at these caps this render measures 0.989 and
                // 0.963. Lower caps clip the band the reference is built on.
                diskCap: 1,
                photonCap: 1,
                disk: {
                    exposure: 1.7,
                    // 0.8 measured azimuthal high-frequency energy 2.05 against
                    // the reference's 0.655: its arms are one sheet, not
                    // separated filaments. 0.29 lands on 0.640.
                    detail: 0.29,
                    falloff: 1.25,
                    // The reference's disk plane is rolled in the image plane;
                    // its major axis measures +14.0 deg, and bhDisk.z has
                    // carried this angle through the shader all along at 0.
                    roll: 11,
                    // The photon-ring COMPLEX between the shadow edge and the
                    // ISCO's direct image at 1.4257 Rh. Without it the 1.0-1.45
                    // Rh annuli measured .057/.058 against the reference's
                    // .580/.461 -- a dark moat where its brightest light is.
                    halo: {
                        gain: 0.76,
                        reachRh: 1.61
                    },
                    streaks: {
                        octaves: 2,
                        radialScale: 1.4,
                        innerPeriodSec: 12,
                        warp: 0.25,
                        grain: 0.08,
                        smear: 0.85
                    },
                    hue: {
                        innerTemperature: 10000,
                        outerTemperature: 2800,
                        warmth: 0,
                        whiteness: 0.49
                    },
                    // The reference carries no beaming asymmetry: its mean
                    // light left of centre over right measures 0.967. At the
                    // v6 strength 0.22 this render measured 1.439.
                    doppler: {
                        strength: 0
                    },
                    glow: {
                        gain: 0.008,
                        radiusPx: 2.5
                    },
                    rim: {
                        skirt: 1,
                        fray: 0.92,
                        clump: 0.3
                    },
                    depth: {
                        foreground: 0.09,
                        lane: 0.35
                    },
                    // Off. Measured, the razor bands are the single largest
                    // source of "drawn circle" energy (radial ripple in the
                    // polar sector 1.8-3.6 Rh: 1.05 with them at ANY gain,
                    // 0.30 without, reference 0.19), and the owner rejected
                    // drawn rings in v5. The keys stay for anyone who wants them.
                    arcs: {
                        gain: 0,
                        radiusRh: 1.6,
                        spacingRh: 0.55,
                        count: 4
                    }
                },
                photon: {
                    mode: "shared-field",
                    widthPx: 0.75,
                    gain: 0.9,
                    textureStrength: 0.8
                }
            }
        })
    readonly property var _preset: presets[preset] || ({})
    property bool enabled: false
    property real size: pick("size", 0.075)
    property real tilt: pick("tilt", 14)
    property real intensity: pick("intensity", 0.85)
    property real warmth: 0.5
    property real spin: 1
    property real diskInnerRs: 3
    property real diskOuterRs: pick("diskOuterRs", 8)
    property real beamStrength: 0.15
    property real haloUpper: pick("haloUpper", 0.55)
    property real haloLower: pick("haloLower", 0.35)
    property real photonWidth: 0.006
    property real structure: 0.05
    property real tiltWander: 0
    property real transitionSec: 30
    // Declared luminous-footprint budget, checked by verification, not clamped
    // in the shader: raising it is the owner saying a larger disk is wanted.
    property real footprintCap: pick("footprintCap", 0.04)
    // Output limiters the shader actually enforces. Raising them is the owner
    // asking for a brighter core; a change is discrete config, it does not slew.
    property real diskCap: pick("diskCap", 0.25)
    property real photonCap: pick("photonCap", 0.3)
    // Lensing reach in Rh. The C2 taper now runs over .8*RL..RL, so RL=4 is the
    // v4 envelope exactly; wider values bend the star field further out.
    property real lensReach: pick("lensReach", 8)
    property real lensStretch: pick("lensStretch", 1.5)
    // Objects map directly to blackHole.disk / blackHole.photon in JSON.
    // An explicit object REPLACES the preset's; the two are not merged.
    property var disk: ({})
    property var photon: ({})
    // The preset is a fallback LAYER beneath disk/photon, not their default
    // value: a consumer that assigns an empty object cannot erase it, and
    // explicit keys still win key by key (one nested level deep).
    readonly property var _diskAll: layered(_preset.disk, disk)
    readonly property var _photonAll: layered(_preset.photon, photon)
    property vector2d resolution: Qt.vector2d(2160, 3840)
    property vector2d centre: Qt.vector2d(resolution.x / 2, resolution.y / 2)
    property real time: 0
    property bool running: true
    property vector4d ambientHole: Qt.vector4d(0.5, 0.5, 0.5, 0.5)

    property real _lastTime: 0
    property real _phase: 0
    property real _wanderPhase: 0
    property real _detailPhase: 0
    property var _strengths: [0.75, 0.25, 0.06, 0.35, 0.06, 0.22, 0.5, 0.008, 0.45, 1.18, 0.8, 1, 0, 0, 0.7, 0.6, 0.6, 0.6, 0.35, 0.3]
    property real _enablePosition: 0
    property vector4d _ambient: Qt.vector4d(0.5, 0.5, 0.5, 0.5)
    property bool _ready: false
    readonly property real _rh: Math.max(1, clamp(size, 0.01, 0.2) * Math.min(resolution.x, resolution.y))
    readonly property real _tilt: clamp(clamp(tilt, 1, 80) + clamp(tiltWander, 0, 1) * Math.sin(_wanderPhase), 1, 80) * Math.PI / 180

    readonly property vector2d bhCentre: centre
    readonly property vector4d bhGeometry: Qt.vector4d(_rh, clamp(lensReach, 4, 12) * _rh, Math.sin(_tilt), Math.cos(_tilt))
    readonly property vector4d bhDisk: Qt.vector4d(clamp(diskInnerRs, 3, 7), Math.max(clamp(diskInnerRs, 3, 7) + 0.5, clamp(diskOuterRs, 3.5, 11)), value(_diskAll, "roll", 0, -90, 90) * Math.PI / 180, Math.max(1, clamp(photonWidth, 0.001, 0.02) * _rh))
    // Exposure only widens the x ceiling; at the default exposure 1 it is <=1.
    readonly property vector4d bhLook: Qt.vector4d(clamp(intensity * _strengths[11] * (0.8 + 0.4 * _ambient.z), 0, 2), clamp(warmth + 0.3 * (_ambient.y - 0.5), 0, 1), clamp(beamStrength, 0, 0.2), clamp(structure * (0.8 + 0.4 * _ambient.w), 0, 0.08))
    readonly property vector4d bhHalo: Qt.vector4d(clamp(haloUpper, 0, 1), clamp(haloLower, 0, 1), 0.6, ease(_enablePosition))
    readonly property vector4d bhPhase: Qt.vector4d(_phase, modulo(4 * _phase, 2 * Math.PI), _wanderPhase, _ambient.x)
    readonly property vector4d bhCaps: Qt.vector4d(clamp(diskCap, 0.1, 1), clamp(photonCap, 0.1, 1), clamp(footprintCap, 0.01, 0.5), 0.08)
    readonly property vector4d bhDetail: Qt.vector4d(_strengths[0], Math.round(value(_diskAll, "seed", 457, 0, 65535)), value(_diskAll, "rotationSign", 1, -1, 1) < 0 ? -1 : 1, Math.round(value(_diskAll.streaks, "octaves", 2, 1, 3)))
    readonly property vector4d bhStreaks: Qt.vector4d(value(_diskAll.streaks, "radialScale", 1, 0.5, 2), _innerCycles, _strengths[1], _strengths[2])
    readonly property vector4d bhKnots: Qt.vector4d(value(_diskAll.knots, "density", 0.03, 0, 0.06), _strengths[3], 16, 48)
    readonly property vector4d bhEmbers: Qt.vector4d(2 * Math.floor(value(_diskAll.embers, "count", 24, 0, 32) / 2), value(_diskAll.embers, "radiusRs", 0.012, 0.004, 0.025), value(_diskAll.embers, "trailSec", 0.35, 0, 0.6), _strengths[4])
    readonly property vector4d bhDoppler: Qt.vector4d(_physical ? 1 : 0, _strengths[5], 0, 0)
    readonly property vector4d bhHue: Qt.vector4d(Math.log(value(_diskAll.hue, "innerTemperature", 6500, 4200, 10000)), Math.log(value(_diskAll.hue, "outerTemperature", 1700, 1000, 2800)), _strengths[6], _strengths[13])
    readonly property vector4d bhGlow: Qt.vector4d(_strengths[7], value(_diskAll.glow, "radiusPx", 1.5, 0.25, 2.5), value(_diskAll.halo, "gain", 0, 0, 1), value(_diskAll.halo, "reachRh", 1.43, 1, 2))
    readonly property vector4d bhPhoton: Qt.vector4d(_strengths[8], _strengths[9], _strengths[10], _photonAll.mode === "off" ? 0 : 1)
    readonly property vector4d bhDetailPhase: Qt.vector4d(_detailPhase, 1 / 30, 0, 0)
    readonly property vector4d bhRim: Qt.vector4d(_strengths[14], _strengths[15], _strengths[16], _strengths[17])
    readonly property vector4d bhDepth: Qt.vector4d(_strengths[18], _strengths[19], value(_diskAll, "falloff", 1, 1, 3), clamp(lensStretch, 1, 3))
    readonly property vector4d bhArcs: Qt.vector4d(_strengths[12], value(_diskAll.arcs, "radiusRh", 1.75, 1.2, 2.6), value(_diskAll.arcs, "spacingRh", 0.6, 0.2, 1), Math.round(value(_diskAll.arcs, "count", 2, 0, 4)))
    // innerPeriodSec is the friendly spelling; the integer cycle count is what
    // keeps every row's turn count whole and the 4096-s repeat exact.
    readonly property real _innerCycles: Number.isFinite(_diskAll.streaks && _diskAll.streaks.innerCyclesPer4096) ? Math.round(clamp(_diskAll.streaks.innerCyclesPer4096, 16, 1024)) : Math.round(4096 / value(_diskAll.streaks, "innerPeriodSec", 12, 4, 256))
    readonly property bool _physical: !!_diskAll.doppler && _diskAll.doppler.preset === "physical"
    // Qt's supportsAtlasTextures belongs to the CONSUMING ShaderEffect, where
    // it must be false. Leave colorSpace unset (invalid), preserving RG bytes.
    readonly property Image bhTransfer: Image {
        source: Qt.resolvedUrl("shaders/blackhole-lut.png")
        smooth: false
        mipmap: false
        visible: false
        asynchronous: false
    }
    // Opaque RGBA8 lattice: linear sampling of stored bytes, NOT sRGB decoding.
    readonly property Image bhNoise: Image {
        source: Qt.resolvedUrl("shaders/blackhole-noise.png")
        smooth: true
        mipmap: false
        visible: false
        asynchronous: false
    }

    function layered(base: var, over: var): var {
        if (!base)
            return over || ({});
        const out = {};
        for (const k in base)
            out[k] = base[k];
        for (const k in over || ({})) {
            const b = out[k], o = over[k];
            out[k] = b && o && typeof b === "object" && typeof o === "object" ? Object.assign({}, b, o) : o;
        }
        return out;
    }

    function value(group: var, key: string, fallback: real, lo: real, hi: real): real {
        return group && Number.isFinite(group[key]) ? clamp(group[key], lo, hi) : fallback;
    }

    function strengthTargets(): var {
        return [value(_diskAll, "detail", 0.75, 0, 0.85), value(_diskAll.streaks, "warp", 0.25, 0, 0.25), value(_diskAll.streaks, "grain", 0.06, 0, 0.08), value(_diskAll.knots, "gain", 0.35, 0, 0.5), value(_diskAll.embers, "gain", 0.06, 0, 0.06), value(_diskAll.doppler, "strength", _physical ? 1 : 0.22, 0, 1), value(_diskAll.hue, "warmth", 0.5, 0, 1), value(_diskAll.glow, "gain", 0.008, 0, 0.008), value(_photonAll, "widthPx", 0.45, 0.1, 0.75), value(_photonAll, "gain", 1.18, 0, 1.5), value(_photonAll, "textureStrength", 0.8, 0, 1), value(_diskAll, "exposure", 1, 0.5, 2), value(_diskAll.arcs, "gain", 0, 0, 0.02), value(_diskAll.hue, "whiteness", 0, 0, 1), value(_diskAll.rim, "skirt", 0.7, 0, 1), value(_diskAll.rim, "fray", 0.6, 0, 1), value(_diskAll.rim, "clump", 0.6, 0, 1), value(_diskAll.streaks, "smear", 0.6, 0, 1), value(_diskAll.depth, "foreground", 0.35, 0, 1), value(_diskAll.depth, "lane", 0.3, 0, 1)];
    }

    function pick(key: string, fallback: real): real {
        return Number.isFinite(_preset[key]) ? _preset[key] : fallback;
    }

    function clamp(x: real, lo: real, hi: real): real {
        return Number.isFinite(x) ? Math.max(lo, Math.min(hi, x)) : lo;
    }

    function modulo(x: real, n: real): real {
        return ((x % n) + n) % n;
    }

    function ease(x: real): real {
        x = clamp(x, 0, 1);
        return x * x * x * (10 + x * (-15 + 6 * x));
    }

    function advance(dt: real): void {
        if (!running || !Number.isFinite(dt) || dt <= 0)
            return;
        // This clock is independent of spin, ambient activity and enable state.
        _detailPhase = modulo(_detailPhase + dt / 4096, 1);
        const targets = strengthTargets();
        const strengths = _strengths.slice();
        const slew = 1 - Math.exp(-dt / 30);
        for (let i = 0; i < strengths.length; ++i)
            strengths[i] += (targets[i] - strengths[i]) * slew;
        _strengths = strengths;
        const oldActivity = _ambient.x;
        const current = [_ambient.x, _ambient.y, _ambient.z, _ambient.w];
        const target = [ambientHole.x, ambientHole.y, ambientHole.z, ambientHole.w];
        for (let i = 0; i < 4; ++i)
            current[i] += clamp((clamp(target[i], 0, 1) - current[i]) * (1 - Math.exp(-dt / 120)), -0.002 * dt, 0.002 * dt);
        _ambient = Qt.vector4d(current[0], current[1], current[2], current[3]);
        const activity = 1 + 0.1 * ((oldActivity + current[0]) / 2 - 0.5);
        _phase = modulo(_phase + dt * clamp(spin, -4, 4) * activity * 2 * Math.PI / 4096, 2 * Math.PI);
        _wanderPhase = modulo(_wanderPhase + dt * 2 * Math.PI / 2048, 2 * Math.PI);
        _enablePosition = clamp(_enablePosition + (enabled ? 1 : -1) * dt / Math.max(0.001, transitionSec), 0, 1);
    }

    function reset(): void {
        _lastTime = time;
        _phase = 0;
        _wanderPhase = 0;
        _detailPhase = 0;
        _strengths = strengthTargets();
        _enablePosition = 0;
        _ambient = Qt.vector4d(0.5, 0.5, 0.5, 0.5);
    }

    onTimeChanged: {
        let dt = time - _lastTime;
        _lastTime = time;
        if (dt < -2048)
            dt += 4096;
        if (_ready)
            advance(dt);
    }
    onRunningChanged: _lastTime = time
    Component.onCompleted: {
        _lastTime = time;
        _strengths = strengthTargets();
        _ready = true;
    }
}
