import QtQuick

// Rebuild from repo root: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o modules/background/shaders/starfield.frag.qsb modules/background/shaders/starfield.frag
Item {
    id: root

    property bool running: true
    property real devicePixelRatio: Screen.devicePixelRatio
    property real density: 1
    property real driftSpeed: 3.5
    property real driftDirection: 165
    property real twinkle: 0.22
    property real flareFraction: 0.003
    property real brightness: 1
    property color backgroundColor: "#000000"
    property real edgeLift: 0
    property int fps: 30
    property real motionWander: 0.8
    property real motionZoom: 0.025
    property real motionRotation: 0.5
    property bool meteorsEnabled: true
    property vector2d meteorsInterval: Qt.vector2d(10, 30)
    property bool cometEnabled: true
    property vector2d cometInterval: Qt.vector2d(180, 300)
    property bool satellitesEnabled: true
    property vector2d satellitesInterval: Qt.vector2d(75, 140)

    // Seconds of active animation; seeking is deterministic and independent of fps.
    property real time: 0
    property real previousTime: 0
    property real travelX: 0
    property real travelY: 0
    property real zoomOffset: 0
    property real rotationOffset: 0
    readonly property vector4d camera: Qt.vector4d(travelX, travelY, zoomOffset, rotationOffset)
    readonly property vector2d cameraCentre: Qt.vector2d(0.5 + 0.035 * Math.sin(time * 0.047), 0.5 + 0.025 * Math.sin(time * 0.061))
    readonly property var meteor: eventState(0, false)
    readonly property var meteorCompanion: eventState(0, true)
    readonly property var comet: eventState(1, false)
    readonly property var satellite: eventState(2, false)

    // Exact integrals of the wandering velocity: no Euler drift, and changing
    // speed/heading/amplitude live preserves the current camera position.
    function sineIntegral(from: real, to: real, rate: real, phase: real): real {
        return (Math.cos(from * rate + phase) - Math.cos(to * rate + phase)) / rate;
    }

    onTimeChanged: {
        const from = previousTime;
        const dt = time - from;
        const heading = driftDirection * Math.PI / 180;
        const along = driftSpeed * (dt + motionWander * (0.55 * sineIntegral(from, time, 0.173, 0.3) + 0.25 * sineIntegral(from, time, 0.071, 2.1)));
        const across = driftSpeed * motionWander * (0.8 * sineIntegral(from, time, 0.113, 0) + 0.38 * sineIntegral(from, time, 0.269, 0));
        travelX += along * Math.cos(heading) - across * Math.sin(heading);
        travelY += along * Math.sin(heading) + across * Math.cos(heading);
        zoomOffset += motionZoom * (0.7 * (Math.sin(time * 0.157) - Math.sin(from * 0.157)) + 0.3 * (Math.sin(time * 0.083) - Math.sin(from * 0.083)));
        rotationOffset += motionRotation * Math.PI / 180 * (0.75 * (Math.sin(time * 0.193) - Math.sin(from * 0.193)) + 0.25 * (Math.sin(time * 0.071) - Math.sin(from * 0.071)));
        previousTime = time;
    }

    function random(index: int, salt: int): real {
        let n = (index * 1664525 + salt * 1013904223) >>> 0;
        n ^= n << 13;
        n ^= n >>> 17;
        n ^= n << 5;
        return (n >>> 0) / 4294967296;
    }

    function ease(value: real): real {
        const x = Math.max(0, Math.min(1, value));
        return x * x * (3 - 2 * x);
    }

    // One jittered event per time slot. Adjacent start gaps remain inside the
    // requested interval range. Only three candidates are inspected, on the CPU.
    // Return [head x, head y, tail length, light, direction x, direction y, width].
    function eventState(kind: int, companion: bool): var {
        const off = [0, 0, 0, 0, 1, 0, 1];
        if (!(kind === 0 ? meteorsEnabled : kind === 1 ? cometEnabled : satellitesEnabled))
            return off;
        const range = kind === 0 ? meteorsInterval : kind === 1 ? cometInterval : satellitesInterval;
        const minimum = Math.max(kind === 0 ? 3 : kind === 1 ? 60 : 45, range.x);
        const maximum = Math.max(minimum, range.y);
        const mean = (minimum + maximum) / 2;
        const jitter = (maximum - minimum) / 4;
        const slot = Math.floor(time / mean) - 1;
        const salt = 113 + kind * 701;
        const physicalWidth = width * devicePixelRatio;
        const physicalHeight = height * devicePixelRatio;
        const shortSide = Math.min(physicalWidth, physicalHeight);
        const optics = Math.max(1, Math.sqrt(physicalWidth * physicalHeight / (1024 * 576)));
        for (let index = slot - 1; index <= slot + 1; index++) {
            if (index < 0)
                continue;
            const start = (index + 1) * mean + (random(index, salt) * 2 - 1) * jitter;
            if (companion && random(index, salt + 1) > 0.18)
                continue;
            const offset = companion ? 0.22 + 0.18 * random(index, salt + 2) : 0;
            const duration = kind === 0 ? 0.55 + 0.60 * random(index, salt + 3) : kind === 1 ? 20 + 15 * random(index, salt + 3) : 30 + 15 * random(index, salt + 3);
            const age = time - start - offset;
            if (age < 0 || age > duration)
                continue;
            const u = age / duration;
            const angle = (random(index, salt + 4) * 2 - 1) * Math.PI + (companion ? 0.06 : 0);
            const dx = Math.cos(angle);
            const dy = Math.sin(angle);
            const distance = shortSide * (kind === 0 ? 0.28 : kind === 1 ? 0.72 : 0.85);
            const progress = kind === 0 ? (1 - Math.exp(-2.4 * u)) / (1 - Math.exp(-2.4)) : u;
            const centreX = physicalWidth * (0.20 + 0.60 * random(index, salt + 5));
            const centreY = physicalHeight * (0.20 + 0.60 * random(index, salt + 6));
            const headX = centreX + dx * distance * (progress - 0.5) + (companion ? shortSide * 0.012 : 0);
            const headY = centreY + dy * distance * (progress - 0.5);
            const envelope = ease(u / (kind === 0 ? 0.09 : 0.16)) * ease((1 - u) / (kind === 0 ? 0.38 : 0.20));
            const intensity = envelope * (kind === 0 ? (companion ? 0.52 : 0.90) : kind === 1 ? 0.28 : 0.33);
            const tail = shortSide * (kind === 0 ? 0.13 * (1 - 0.40 * u) : kind === 1 ? 0.22 : 0);
            const pointWidth = kind === 0 ? optics * 0.40 : kind === 1 ? optics * 0.70 : 0.65;
            return [headX, headY, tail, intensity, dx, dy, pointWidth];
        }
        return off;
    }

    ShaderEffect {
        anchors.fill: parent

        readonly property vector2d resolution: Qt.vector2d(width * root.devicePixelRatio, height * root.devicePixelRatio)
        readonly property vector4d camera: root.camera
        readonly property vector2d cameraCentre: root.cameraCentre
        // Scintillation frequencies have integer cycles per wrap: no wrap seam.
        readonly property real phaseTime: root.time % 4096
        readonly property real density: Math.max(0, Math.min(3, root.density))
        readonly property real twinkle: Math.max(0, Math.min(1, root.twinkle))
        readonly property real flareFraction: Math.max(0, Math.min(0.025, root.flareFraction))
        readonly property real brightness: Math.max(0, Math.min(3, root.brightness))
        readonly property color skyColor: root.backgroundColor
        readonly property real edgeLift: Math.max(0, Math.min(1, root.edgeLift))
        readonly property vector4d meteorHead: Qt.vector4d(root.meteor[0], root.meteor[1], root.meteor[2], root.meteor[3])
        readonly property vector3d meteorShape: Qt.vector3d(root.meteor[4], root.meteor[5], root.meteor[6])
        readonly property vector4d companionHead: Qt.vector4d(root.meteorCompanion[0], root.meteorCompanion[1], root.meteorCompanion[2], root.meteorCompanion[3])
        readonly property vector3d companionShape: Qt.vector3d(root.meteorCompanion[4], root.meteorCompanion[5], root.meteorCompanion[6])
        readonly property vector4d cometHead: Qt.vector4d(root.comet[0], root.comet[1], root.comet[2], root.comet[3])
        readonly property vector3d cometShape: Qt.vector3d(root.comet[4], root.comet[5], root.comet[6])
        readonly property vector4d satelliteHead: Qt.vector4d(root.satellite[0], root.satellite[1], root.satellite[6], root.satellite[3])

        fragmentShader: "shaders/starfield.frag.qsb"
    }

    Timer {
        id: ticker

        property real lastTick: 0

        interval: Math.ceil(1000 / Math.max(1, Math.min(60, root.fps)))
        repeat: true
        running: root.running && root.visible && root.width > 0 && root.height > 0
        onRunningChanged: lastTick = Date.now()
        onTriggered: {
            const now = Date.now();
            root.time += Math.max(0, now - lastTick) / 1000;
            lastTick = now;
        }
    }
}
