import QtQuick

// State provider only. Advance time with the renderer's active clock.
QtObject {
    id: root

    property bool enabled: false
    property real size: 0.075
    property real tilt: 14
    property real intensity: 0.65
    property real warmth: 0.5
    property real spin: 1
    property real diskInnerRs: 3
    property real diskOuterRs: 8
    property real beamStrength: 0.15
    property real haloUpper: 0.55
    property real haloLower: 0.35
    property real photonWidth: 0.006
    property real structure: 0.05
    property real tiltWander: 0
    property real transitionSec: 30
    property vector2d resolution: Qt.vector2d(2160, 3840)
    property vector2d centre: Qt.vector2d(resolution.x / 2, resolution.y / 2)
    property real time: 0
    property bool running: true
    property vector4d ambientHole: Qt.vector4d(0.5, 0.5, 0.5, 0.5)

    property real _lastTime: 0
    property real _phase: 0
    property real _wanderPhase: 0
    property real _enablePosition: 0
    property vector4d _ambient: Qt.vector4d(0.5, 0.5, 0.5, 0.5)
    property bool _ready: false
    readonly property real _rh: Math.max(1, clamp(size, 0.01, 0.2) * Math.min(resolution.x, resolution.y))
    readonly property real _tilt: clamp(clamp(tilt, 1, 80) + clamp(tiltWander, 0, 1) * Math.sin(_wanderPhase), 1, 80) * Math.PI / 180

    readonly property vector2d bhCentre: centre
    readonly property vector4d bhGeometry: Qt.vector4d(_rh, 4 * _rh, Math.sin(_tilt), Math.cos(_tilt))
    readonly property vector4d bhDisk: Qt.vector4d(clamp(diskInnerRs, 3, 7), Math.max(clamp(diskInnerRs, 3, 7) + 0.5, clamp(diskOuterRs, 3.5, 9)), 0, Math.max(1, clamp(photonWidth, 0.001, 0.02) * _rh))
    readonly property vector4d bhLook: Qt.vector4d(clamp(intensity * (0.8 + 0.4 * _ambient.z), 0, 1), clamp(warmth + 0.3 * (_ambient.y - 0.5), 0, 1), clamp(beamStrength, 0, 0.2), clamp(structure * (0.8 + 0.4 * _ambient.w), 0, 0.08))
    readonly property vector4d bhHalo: Qt.vector4d(clamp(haloUpper, 0, 1), clamp(haloLower, 0, 1), 0.45, ease(_enablePosition))
    readonly property vector4d bhPhase: Qt.vector4d(_phase, modulo(4 * _phase, 2 * Math.PI), _wanderPhase, _ambient.x)
    readonly property vector4d bhCaps: Qt.vector4d(0.25, 0.30, 0.03, 0.08)
    // Qt's supportsAtlasTextures belongs to the CONSUMING ShaderEffect, where
    // it must be false. Leave colorSpace unset (invalid), preserving RG bytes.
    readonly property Image bhTransfer: Image {
        source: Qt.resolvedUrl("shaders/blackhole-lut.png")
        smooth: false
        mipmap: false
        visible: false
        asynchronous: false
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
        _ready = true;
    }
}
