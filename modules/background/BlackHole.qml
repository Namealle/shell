import QtQuick

// State provider only. Advance time with the renderer's active clock.
QtObject {
    id: root

    // "" keeps the v4 defaults. A named preset only supplies fallbacks: any
    // property the service assigns explicitly replaces its binding and wins.
    property string preset: ""
    readonly property var presets: ({
            target: {
                size: 0.11,
                tilt: 28,
                intensity: 1,
                haloUpper: 1,
                haloLower: 0.9,
                footprintCap: 0.11,
                diskCap: 0.6,
                photonCap: 0.7,
                disk: {
                    exposure: 2,
                    detail: 0.8,
                    streaks: {
                        octaves: 3,
                        radialScale: 1.4,
                        innerCyclesPer4096: 32,
                        warp: 0.25,
                        grain: 0.08
                    },
                    hue: {
                        innerTemperature: 7000,
                        outerTemperature: 1700,
                        warmth: 0.35,
                        whiteness: 0.85
                    },
                    glow: {
                        gain: 0.008,
                        radiusPx: 2.5
                    },
                    arcs: {
                        gain: 0.013,
                        radiusRh: 1.7,
                        spacingRh: 0.6,
                        count: 2
                    }
                },
                photon: {
                    mode: "shared-field",
                    widthPx: 0.6,
                    gain: 1.35,
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
    property real footprintCap: pick("footprintCap", 0.03)
    // Output limiters the shader actually enforces. Raising them is the owner
    // asking for a brighter core; a change is discrete config, it does not slew.
    property real diskCap: pick("diskCap", 0.25)
    property real photonCap: pick("photonCap", 0.3)
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
    property var _strengths: [0.75, 0.25, 0.06, 0.35, 0.06, 0.22, 0.5, 0.008, 0.45, 1.18, 0.8, 1, 0, 0]
    property real _enablePosition: 0
    property vector4d _ambient: Qt.vector4d(0.5, 0.5, 0.5, 0.5)
    property bool _ready: false
    readonly property real _rh: Math.max(1, clamp(size, 0.01, 0.2) * Math.min(resolution.x, resolution.y))
    readonly property real _tilt: clamp(clamp(tilt, 1, 80) + clamp(tiltWander, 0, 1) * Math.sin(_wanderPhase), 1, 80) * Math.PI / 180

    readonly property vector2d bhCentre: centre
    readonly property vector4d bhGeometry: Qt.vector4d(_rh, 4 * _rh, Math.sin(_tilt), Math.cos(_tilt))
    readonly property vector4d bhDisk: Qt.vector4d(clamp(diskInnerRs, 3, 7), Math.max(clamp(diskInnerRs, 3, 7) + 0.5, clamp(diskOuterRs, 3.5, 9)), 0, Math.max(1, clamp(photonWidth, 0.001, 0.02) * _rh))
    // Exposure only widens the x ceiling; at the default exposure 1 it is <=1.
    readonly property vector4d bhLook: Qt.vector4d(clamp(intensity * _strengths[11] * (0.8 + 0.4 * _ambient.z), 0, 2), clamp(warmth + 0.3 * (_ambient.y - 0.5), 0, 1), clamp(beamStrength, 0, 0.2), clamp(structure * (0.8 + 0.4 * _ambient.w), 0, 0.08))
    readonly property vector4d bhHalo: Qt.vector4d(clamp(haloUpper, 0, 1), clamp(haloLower, 0, 1), 0.6, ease(_enablePosition))
    readonly property vector4d bhPhase: Qt.vector4d(_phase, modulo(4 * _phase, 2 * Math.PI), _wanderPhase, _ambient.x)
    readonly property vector4d bhCaps: Qt.vector4d(clamp(diskCap, 0.1, 1), clamp(photonCap, 0.1, 1), clamp(footprintCap, 0.01, 0.12), 0.08)
    readonly property vector4d bhDetail: Qt.vector4d(_strengths[0], Math.round(value(_diskAll, "seed", 457, 0, 65535)), value(_diskAll, "rotationSign", 1, -1, 1) < 0 ? -1 : 1, Math.round(value(_diskAll.streaks, "octaves", 2, 1, 3)))
    readonly property vector4d bhStreaks: Qt.vector4d(value(_diskAll.streaks, "radialScale", 1, 0.5, 2), Math.round(value(_diskAll.streaks, "innerCyclesPer4096", 32, 16, 128)), _strengths[1], _strengths[2])
    readonly property vector4d bhKnots: Qt.vector4d(value(_diskAll.knots, "density", 0.03, 0, 0.06), _strengths[3], 16, 48)
    readonly property vector4d bhEmbers: Qt.vector4d(2 * Math.min(bhStreaks.y - 1, Math.floor(value(_diskAll.embers, "count", 24, 0, 32) / 2)), value(_diskAll.embers, "radiusRs", 0.012, 0.004, 0.025), value(_diskAll.embers, "trailSec", 0.35, 0, 0.6), _strengths[4])
    readonly property vector4d bhDoppler: Qt.vector4d(_physical ? 1 : 0, _strengths[5], 0, 0)
    readonly property vector4d bhHue: Qt.vector4d(Math.log(value(_diskAll.hue, "innerTemperature", 6500, 4200, 10000)), Math.log(value(_diskAll.hue, "outerTemperature", 1700, 1000, 2800)), _strengths[6], _strengths[13])
    readonly property vector4d bhGlow: Qt.vector4d(_strengths[7], value(_diskAll.glow, "radiusPx", 1.5, 0.25, 2.5), 0, 0)
    readonly property vector4d bhPhoton: Qt.vector4d(_strengths[8], _strengths[9], _strengths[10], _photonAll.mode === "off" ? 0 : 1)
    readonly property vector4d bhDetailPhase: Qt.vector4d(_detailPhase, 1 / 30, 0, 0)
    readonly property vector4d bhArcs: Qt.vector4d(_strengths[12], value(_diskAll.arcs, "radiusRh", 1.75, 1.2, 2.6), value(_diskAll.arcs, "spacingRh", 0.6, 0.2, 1), Math.round(value(_diskAll.arcs, "count", 2, 0, 2)))
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
        return [value(_diskAll, "detail", 0.75, 0, 0.85), value(_diskAll.streaks, "warp", 0.25, 0, 0.25), value(_diskAll.streaks, "grain", 0.06, 0, 0.08), value(_diskAll.knots, "gain", 0.35, 0, 0.5), value(_diskAll.embers, "gain", 0.06, 0, 0.06), value(_diskAll.doppler, "strength", _physical ? 1 : 0.22, 0, 1), value(_diskAll.hue, "warmth", 0.5, 0, 1), value(_diskAll.glow, "gain", 0.008, 0, 0.008), value(_photonAll, "widthPx", 0.45, 0.1, 0.75), value(_photonAll, "gain", 1.18, 0, 1.5), value(_photonAll, "textureStrength", 0.8, 0, 1), value(_diskAll, "exposure", 1, 0.5, 2), value(_diskAll.arcs, "gain", 0, 0, 0.02), value(_diskAll.hue, "whiteness", 0, 0, 1)];
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
