import QtQuick

// Rebuild from repo root: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o modules/background/shaders/starfield.frag.qsb modules/background/shaders/starfield.frag
Item {
    id: root

    property bool running: true
    property real devicePixelRatio: Screen.devicePixelRatio
    property real density: 1
    property real twinkle: 0.22
    property real flareFraction: 0.003
    property real brightness: 1
    property color backgroundColor: "#000000"
    property real edgeLift: 0
    property int fps: 30
    // Writable active seconds. An explicit seek replays the current targets;
    // reproducing a changed configuration requires replaying its signal history.
    property real time: 0
    property real driftSpeed: 3.5
    property real driftDirection: 165
    property real motionWander: 0.8
    property real motionZoom: 0.025
    property real motionRotation: 0.5
    property bool meteorsEnabled: true
    property vector2d meteorsInterval: Qt.vector2d(45, 120)
    property bool cometEnabled: true
    property vector2d cometInterval: Qt.vector2d(900, 1800)
    property bool satellitesEnabled: true
    property vector2d satellitesInterval: Qt.vector2d(240, 480)
    property string motionMode: "radial"
    property real radialSpeed: 6
    property real centreWander: 0.012
    property real zoomBreath: 0.003
    // Reserved opt-in. Reversing the stream would resurrect expired palettes;
    // until bidirectional history is available the flow remains inward.
    property bool reversals: false
    property int screenSeed: 0
    property vector4d ambientBirth: Qt.vector4d(0, 0, 0, 0.5)
    property vector4d ambientLive: Qt.vector4d(0.5, 0.5, 0.5, 0.5)
    property bool varietyEnabled: true
    property int varietySeed: 1
    property real variableFraction: 0.006
    property real companionChance: 0.04
    property real fireballChance: 0.01

    // Mutable JS numbers stay doubles; only publish() converts bounded values
    // to GPU floats. No target has a direct binding to the ShaderEffect.
    property var _state: null
    property bool _writingTime: false
    property real _pending: 0
    property bool _firstFrame: true

    function clamp(x: real, lo: real, hi: real): real {
        return Number.isFinite(x) ? Math.max(lo, Math.min(hi, x)) : lo;
    }

    function modulo(x: real, n: real): real {
        return ((x % n) + n) % n;
    }

    function random(index: real, salt: real): real {
        let n = (Math.imul(index | 0, 1664525) + Math.imul(salt | 0, 1013904223)) >>> 0;
        n ^= n << 13;
        n ^= n >>> 17;
        n ^= n << 5;
        return (n >>> 0) / 4294967296;
    }

    function ease(value: real): real {
        const x = clamp(value, 0, 1);
        return x * x * (3 - 2 * x);
    }

    function wave(t: real, cycles: real, phase: real): real {
        return Math.sin(modulo(t, 4096) * (2 * Math.PI / 4096) * cycles + phase);
    }

    function sineIntegral(from: real, to: real, cycles: real, phase: real): real {
        const rate = 2 * Math.PI * cycles / 4096;
        return (Math.cos(modulo(from, 4096) * rate + phase) - Math.cos(modulo(to, 4096) * rate + phase)) / rate;
    }

    function resetState(): void {
        const history = [];
        for (let i = 0; i < 256; ++i)
            history.push([0, 0, 0, 0.5]);
        _state = {
            clock: 0,
            flow: 0,
            birth: [0, 0, 0, 0.5],
            live: [0.5, 0.5, 0.5, 0.5],
            history: history,
            publishedHistory: [],
            bucket: 0,
            travel: [0, 0],
            events: [null, null, null],
            eventIds: [0, 0, 0],
            moodClock: Date.now() / 1000,
            moodCorrection: 0,
            mood: [0, 0, 0, 0],
            historyWrites: 0,
            publications: 0
        };
    }

    function filtered(value: real, target: real, dt: real, tau: real): real {
        const delta = (clamp(target, 0, 1) - value) * (1 - Math.exp(-dt / tau));
        return value + clamp(delta, -0.005 * dt, 0.005 * dt);
    }

    // 256 samples x 30 flow seconds = 7680 seconds. The far layer's longest
    // padded corner-to-centre journey on the supported buffers is < 6300 s;
    // its 7560 s safety lifetime leaves two sealed interpolation endpoints.
    // Keep 30 s sampling for every layer: extending coverage must not delay
    // the palette response of new middle/near stars or clamp a living palette.
    // Samples are sealed at flow boundaries. Interpolation in the shader uses
    // P[n-1] and P[n], both already sealed at a star's immutable birth phase.
    function advance(dt: real): void {
        const s = _state;
        const before = s.birth.slice();
        const oldFlow = s.flow;
        const oldRate = 0.8 + 0.4 * s.live[2];
        const birth = [ambientBirth.x, ambientBirth.y, ambientBirth.z, ambientBirth.w];
        const live = [ambientLive.x, ambientLive.y, ambientLive.z, ambientLive.w];
        for (let i = 0; i < 4; ++i) {
            s.birth[i] = filtered(s.birth[i], birth[i], dt, 60);
            s.live[i] = filtered(s.live[i], live[i], dt, i === 3 ? 120 : 90);
        }
        // Flow seconds include the user speed. Changing it never changes an
        // inferred birth phase. Zero speed freezes the ring as well as motion.
        const flowRate = (oldRate + 0.8 + 0.4 * s.live[2]) * 0.5;
        s.flow += dt * flowRate * clamp(radialSpeed, 0, 26) / 6;
        const bucket = Math.floor((s.flow + 1e-7) / 30);
        for (let n = Math.max(s.bucket + 1, bucket - 255); n <= bucket; ++n) {
            const f = clamp((n * 30 - oldFlow) / Math.max(1e-12, s.flow - oldFlow), 0, 1);
            s.history[modulo(n, 256)] = before.map((x, i) => x + (s.birth[i] - x) * f);
            ++s.historyWrites;
        }
        s.bucket = bucket;
        const from = s.clock;
        const to = from + dt;
        const heading = driftDirection * Math.PI / 180;
        const along = driftSpeed * flowRate * (dt + motionWander * (0.55 * sineIntegral(from, to, 113, 0.3) + 0.25 * sineIntegral(from, to, 46, 2.1)));
        const across = driftSpeed * flowRate * motionWander * (0.8 * sineIntegral(from, to, 74, 0) + 0.38 * sineIntegral(from, to, 175, 0));
        s.travel[0] += along * Math.cos(heading) - across * Math.sin(heading);
        s.travel[1] += along * Math.sin(heading) + across * Math.cos(heading);
        s.clock = to;
        // Wall time chooses the mood, but its display clock is active time.
        // Resume / wall-clock corrections slew, rather than replace a mask.
        const correction = clamp(s.moodCorrection, -dt * 0.05, dt * 0.05);
        s.moodCorrection -= correction;
        s.moodClock += dt + correction;
    }

    function seek(target: real): void {
        if (!Number.isFinite(target))
            return;
        if (target < _state.clock) {
            resetState();
            // Negative fixtures retain normalized periodic phase, neutral past.
            if (target < 0) {
                _state.clock = target;
                _state.flow = target * clamp(radialSpeed, 0, 26) / 6;
                _state.bucket = Math.floor(_state.flow / 30);
            }
        }
        // Explicit seeks are a verification/configuration operation, not a
        // suspend catch-up path. Runtime frame gaps never enter this loop.
        while (_state.clock < target - 1e-9)
            advance(Math.min(30, target - _state.clock));
        publish();
    }

    function frame(dt: real): void {
        if (!running || !visible || !_state)
            return;
        if (_firstFrame || !Number.isFinite(dt) || dt <= 0 || dt > 0.25) {
            _firstFrame = false;
            _pending = 0;
            return;
        }
        _pending += dt;
        const period = 1 / clamp(fps, 1, 60);
        if (_pending + 1e-9 < period)
            return;
        const elapsed = _pending;
        _pending = modulo(_pending, period);
        // Preserve all elapsed active time; the remainder above controls cadence.
        const step = elapsed - _pending;
        advance(step);
        _writingTime = true;
        time = _state.clock;
        _writingTime = false;
        publish();
    }

    function moodState(): var {
        if (!varietyEnabled)
            return [0, 0, 0, 0];
        const slot = Math.floor(_state.moodClock / 900);
        const salt = varietySeed ^ screenSeed;
        const choice = random(slot, salt + 2201);
        const kind = choice < 0.50 ? 0 : choice < 0.75 ? 1 : choice < 0.95 ? 2 : 3;
        const duration = 240 + 300 * random(slot, salt + 2202);
        const centre = 450 + 60 * (random(slot, salt + 2203) - 0.5);
        const age = modulo(_state.moodClock, 900) - centre + duration / 2;
        const weight = ease(age / 60) * ease((duration - age) / 60);
        return [kind, weight, slot, duration];
    }

    // QMatrix4x4's constructor is ROW-major. GLSL history columns each hold one
    // sample: transpose the four vectors here, never pass a JS array as a UBO.
    function historyMatrix(index: int): matrix4x4 {
        const a = _state.history[index * 4];
        const b = _state.history[index * 4 + 1];
        const c = _state.history[index * 4 + 2];
        const d = _state.history[index * 4 + 3];
        return Qt.matrix4x4(a[0], b[0], c[0], d[0], a[1], b[1], c[1], d[1], a[2], b[2], c[2], d[2], a[3], b[3], c[3], d[3]);
    }

    function blockSalt(block: real, layer: int, axis: int): real {
        return random(block, screenSeed + 761 + layer * 997 + axis * 347) * 97;
    }

    function eventOff(): var {
        return [0, 0, 0, 0, 1, 0, 1];
    }

    // All traits, including geometry and the next interval, are captured once.
    function schedule(kind: int): var {
        const s = _state;
        if (!(kind === 0 ? meteorsEnabled : kind === 1 ? cometEnabled : satellitesEnabled))
            return null;
        const index = s.eventIds[kind]++;
        const salt = screenSeed + 113 + kind * 701;
        const range = kind === 0 ? meteorsInterval : kind === 1 ? cometInterval : satellitesInterval;
        const minimum = Math.max(kind === 0 ? 3 : kind === 1 ? 60 : 45, range.x);
        const maximum = Math.max(minimum, range.y);
        const activeMood = s.mood[0] === 3 ? s.mood[1] : 0;
        const rate = kind === 0 ? 0.5 + s.live[3] : 1;
        const low = minimum + (18 - minimum) * activeMood;
        const high = maximum + (36 - maximum) * activeMood;
        const previous = s.events[kind];
        const base = previous ? previous.start : s.clock;
        let start = Math.max(s.clock, base + (low + (high - low) * random(index, salt)) / rate);
        const fireball = kind === 0 && activeMood === 0 && random(index, salt + 9) < clamp(fireballChance, 0, 1);
        const pair = kind === 0 && random(index, salt + 1) < clamp(companionChance, 0, 1);
        const offset = pair ? 0.35 + 0.35 * random(index, salt + 2) : 0;
        const duration = kind === 0 ? (fireball ? 1.4 + 0.8 * random(index, salt + 3) : 0.55 + 0.60 * random(index, salt + 3)) : kind === 1 ? 20 + 15 * random(index, salt + 3) : 30 + 15 * random(index, salt + 3);
        // Serialize the rare tracks; a companion is the only second head. This
        // avoids hiding/replacing active geometry to enforce the overlap cap.
        for (let pass = 0; pass < 3; ++pass) {
            for (const other of s.events) {
                if (other && start < other.start + other.duration + other.offset + 1 && start + duration + offset + 1 > other.start)
                    start = other.start + other.duration + other.offset + 1;
            }
        }
        const w = width * devicePixelRatio;
        const h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const optics = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
        return {
            kind: kind,
            index: index,
            start: start,
            duration: duration,
            pair: pair,
            offset: offset,
            fireball: fireball,
            angle: (random(index, salt + 4) * 2 - 1) * Math.PI,
            x: w * (0.20 + 0.60 * random(index, salt + 5)),
            y: h * (0.20 + 0.60 * random(index, salt + 6)),
            distance: shortSide * (kind === 0 ? 0.28 : kind === 1 ? 0.72 : 0.85),
            shortSide: shortSide,
            pointWidth: kind === 0 ? optics * 0.40 * (fireball ? 1.4 : 1) : kind === 1 ? optics * 0.70 : 0.65
        };
    }

    function eventState(e: var, companion: bool): var {
        if (!e || (companion && !e.pair))
            return eventOff();
        const age = _state.clock - e.start - (companion ? e.offset : 0);
        if (age < 0 || age > e.duration)
            return eventOff();
        const u = age / e.duration;
        const angle = e.angle + (companion ? 0.025 : 0);
        const dx = Math.cos(angle);
        const dy = Math.sin(angle);
        const progress = e.kind === 0 ? (1 - Math.exp(-2.4 * u)) / (1 - Math.exp(-2.4)) : u;
        const envelope = ease(u / (e.kind === 0 ? 0.09 : 0.16)) * ease((1 - u) / (e.kind === 0 ? 0.38 : 0.20));
        const light = envelope * (e.kind === 0 ? (companion ? 0.45 : e.fireball ? 1.3 : 0.90) : e.kind === 1 ? 0.28 : 0.33);
        const tail = e.shortSide * (e.kind === 0 ? (e.fireball ? 0.18 : 0.13) * (1 - 0.40 * u) : e.kind === 1 ? 0.22 : 0);
        return [e.x + dx * e.distance * (progress - 0.5) + (companion ? e.shortSide * 0.012 : 0), e.y + dy * e.distance * (progress - 0.5), tail, light, dx, dy, e.pointWidth];
    }

    function publish(): void {
        const s = _state;
        if (!s || width <= 0 || height <= 0)
            return;
        const w = width * devicePixelRatio;
        const h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const radius = shortSide / 2;
        const displayScale = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
        const scale = displayScale / Math.sqrt(Math.max(0.0001, clamp(density, 0, 3)));
        const tauPhase = random(screenSeed, 8761) * Math.PI * 2;
        shader.resolution = Qt.vector2d(w, h);
        shader.radialMode = motionMode === "drift" ? 0 : 1;
        shader.phaseTime = modulo(s.clock, 4096);
        shader.flowPhaseLocal = modulo(s.flow, 7680);
        shader.density = clamp(density, 0, 3);
        shader.twinkle = clamp(twinkle, 0, 1) * (0.6 + 0.8 * s.live[0]);
        shader.brightness = clamp(brightness, 0, 3) * (0.8 + 0.4 * s.live[1]);
        shader.flareFraction = clamp(flareFraction, 0, 0.025);
        shader.variableFraction = clamp(variableFraction, 0, 1);
        shader.skyColor = backgroundColor;
        shader.edgeLift = clamp(edgeLift, 0, 1);
        shader.cameraCentre = Qt.vector2d(0.5 + 0.035 * wave(s.clock, 31, 0), 0.5 + 0.025 * wave(s.clock, 40, 0));
        shader.camera = Qt.vector4d(0, 0, motionZoom * (0.7 * wave(s.clock, 102, 0) + 0.3 * wave(s.clock, 54, 0)), motionRotation * Math.PI / 180 * (0.75 * wave(s.clock, 126, 0) + 0.25 * wave(s.clock, 46, 0)));
        // Depth-scaled wander stays subordinate even for the farthest stars.
        // 2048 s is the only 4096-compatible period in [1800,2700].
        shader.centreOffset = Qt.vector2d(shortSide * clamp(centreWander, 0, 0.012) * wave(s.clock, 2, tauPhase), shortSide * clamp(centreWander, 0, 0.012) * wave(s.clock, 2, tauPhase + 1.7));
        const breath = clamp(zoomBreath, 0, 0.003) * (0.65 * wave(s.clock, 10, 0.4) + 0.35 * wave(s.clock, 14, 2.1));
        shader.flowZoom = Qt.vector3d(Math.exp(0.10 * breath), Math.exp(0.42 * breath), Math.exp(breath));
        const padding = [];
        for (let layer = 0; layer < 3; ++layer) {
            const depth = [0.10, 0.42, 1][layer];
            const cellSize = [12, 30, 110][layer] * scale;
            const sectors = Math.max(4, Math.round(2 * Math.PI * radius / cellSize));
            const invAngle = sectors / (2 * Math.PI);
            const invU = radius * radius / (cellSize * cellSize * invAngle);
            const advanceCells = s.flow * (6 / 1080) * depth * invU;
            const row = Math.floor(advanceCells);
            const block = Math.floor(row / 256);
            shader["flowGrid" + layer] = Qt.vector4d(invU, invAngle, modulo(advanceCells, 1), modulo(row, 256));
            shader["flowSeeds" + layer] = Qt.vector4d(blockSalt(block, layer, 0), blockSalt(block, layer, 1), blockSalt(block + 1, layer, 0), blockSalt(block + 1, layer, 1));
            padding.push([3.5, 6, 42 * displayScale][layer] + 2 + shortSide * 0.012 * depth + Math.hypot(w, h) * 0.003 * depth);
            const angle = 0.37 + layer * 1.23;
            // Centre the sampled rectangle in the 256-cell salt window. This
            // guarantees two blocks per axis even on the dense portrait grid.
            const tx = w * 0.5 - s.travel[0] * displayScale * depth;
            const ty = h * 0.5 - s.travel[1] * displayScale * depth;
            const ox = (Math.cos(angle) * tx - Math.sin(angle) * ty + 137.2 * (layer + 1)) / cellSize;
            const oy = (Math.sin(angle) * tx + Math.cos(angle) * ty + 931.7 * (layer + 1)) / cellSize;
            const bx = Math.floor(ox) - 128;
            const by = Math.floor(oy) - 128;
            shader["driftGrid" + layer] = Qt.vector4d(ox - bx, oy - by, modulo(bx, 256), modulo(by, 256));
            const salts = [];
            for (let iy = 0; iy < 2; ++iy) {
                for (let ix = 0; ix < 2; ++ix) {
                    const a = Math.floor(bx / 256) + ix;
                    const b = Math.floor(by / 256) + iy;
                    salts.push([blockSalt(a, layer, 0) + blockSalt(b, layer, 2), blockSalt(a, layer, 1) + blockSalt(b, layer, 3)]);
                }
            }
            shader["driftSeeds" + layer] = Qt.matrix4x4(salts[0][0], salts[1][0], salts[2][0], salts[3][0], salts[0][1], salts[1][1], salts[2][1], salts[3][1], 0, 0, 0, 0, 0, 0, 0, 0);
        }
        shader.birthPadding = Qt.vector3d(padding[0], padding[1], padding[2]);
        // advance() replaces sealed sample vectors. Compare those references
        // so the larger ring rebuilds matrices only when a sample changes.
        for (let i = 0; i < 64; ++i) {
            const offset = i * 4;
            if (s.history[offset] === s.publishedHistory[offset] && s.history[offset + 1] === s.publishedHistory[offset + 1] && s.history[offset + 2] === s.publishedHistory[offset + 2] && s.history[offset + 3] === s.publishedHistory[offset + 3])
                continue;
            shader["birthHistory" + i] = historyMatrix(i);
            for (let j = offset; j < offset + 4; ++j)
                s.publishedHistory[j] = s.history[j];
        }
        s.mood = moodState();
        shader.mood = Qt.vector4d(s.mood[0], s.mood[1], 0, 0);
        const moodTwinkle = [0.18, 0.16, 0.24, 0.22][s.mood[0]];
        shader.twinkle *= 1 + (moodTwinkle / 0.22 - 1) * s.mood[1];
        for (let kind = 0; kind < 3; ++kind) {
            const e = s.events[kind];
            const enabled = kind === 0 ? meteorsEnabled : kind === 1 ? cometEnabled : satellitesEnabled;
            // Disabling cancels pending arrivals. An already visible event
            // finishes its captured envelope rather than vanishing mid-flight.
            if (!enabled && e && s.clock < e.start)
                s.events[kind] = null;
            else if (!e || s.clock > e.start + e.duration + e.offset)
                s.events[kind] = schedule(kind);
        }
        const meteor = eventState(s.events[0], false);
        const companion = eventState(s.events[0], true);
        const comet = eventState(s.events[1], false);
        const satellite = eventState(s.events[2], false);
        shader.meteorHead = Qt.vector4d(meteor[0], meteor[1], meteor[2], meteor[3]);
        shader.meteorShape = Qt.vector3d(meteor[4], meteor[5], meteor[6]);
        shader.companionHead = Qt.vector4d(companion[0], companion[1], companion[2], companion[3]);
        shader.companionShape = Qt.vector3d(companion[4], companion[5], companion[6]);
        shader.cometHead = Qt.vector4d(comet[0], comet[1], comet[2], comet[3]);
        shader.cometShape = Qt.vector3d(comet[4], comet[5], comet[6]);
        shader.satelliteHead = Qt.vector4d(satellite[0], satellite[1], satellite[6], satellite[3]);
        ++s.publications;
    }

    onTimeChanged: {
        if (_state && !_writingTime)
            seek(time);
    }
    onRunningChanged: {
        _pending = 0;
        _firstFrame = true;
        if (running && _state)
            _state.moodCorrection = Date.now() / 1000 - _state.moodClock;
    }
    Component.onCompleted: {
        resetState();
        seek(time);
    }

    ShaderEffect {
        id: shader
        objectName: "starfieldShader"
        anchors.fill: parent
        blending: false

        property vector2d resolution: Qt.vector2d(1, 1)
        property vector4d camera: Qt.vector4d(0, 0, 0, 0)
        property vector2d cameraCentre: Qt.vector2d(0.5, 0.5)
        property real phaseTime: 0
        property real density: 1
        property real twinkle: 0.22
        property real flareFraction: 0.003
        property real brightness: 1
        property color skyColor: "#000000"
        property real edgeLift: 0
        property vector4d meteorHead: Qt.vector4d(0, 0, 0, 0)
        property vector3d meteorShape: Qt.vector3d(1, 0, 1)
        property vector4d companionHead: Qt.vector4d(0, 0, 0, 0)
        property vector3d companionShape: Qt.vector3d(1, 0, 1)
        property vector4d cometHead: Qt.vector4d(0, 0, 0, 0)
        property vector3d cometShape: Qt.vector3d(1, 0, 1)
        property vector4d satelliteHead: Qt.vector4d(0, 0, 1, 0)
        property real radialMode: 1
        property vector2d centreOffset: Qt.vector2d(0, 0)
        property vector3d flowZoom: Qt.vector3d(1, 1, 1)
        property vector3d birthPadding: Qt.vector3d(0, 0, 0)
        property vector4d flowGrid0: Qt.vector4d(1, 1, 0, 0)
        property vector4d flowGrid1: Qt.vector4d(1, 1, 0, 0)
        property vector4d flowGrid2: Qt.vector4d(1, 1, 0, 0)
        property vector4d flowSeeds0: Qt.vector4d(0, 0, 0, 0)
        property vector4d flowSeeds1: Qt.vector4d(0, 0, 0, 0)
        property vector4d flowSeeds2: Qt.vector4d(0, 0, 0, 0)
        property vector4d driftGrid0: Qt.vector4d(0, 0, 0, 0)
        property vector4d driftGrid1: Qt.vector4d(0, 0, 0, 0)
        property vector4d driftGrid2: Qt.vector4d(0, 0, 0, 0)
        property matrix4x4 driftSeeds0
        property matrix4x4 driftSeeds1
        property matrix4x4 driftSeeds2
        property real flowPhaseLocal: 0
        property real variableFraction: 0.006
        property vector4d mood: Qt.vector4d(0, 0, 0, 0)
        property matrix4x4 birthHistory0
        property matrix4x4 birthHistory1
        property matrix4x4 birthHistory2
        property matrix4x4 birthHistory3
        property matrix4x4 birthHistory4
        property matrix4x4 birthHistory5
        property matrix4x4 birthHistory6
        property matrix4x4 birthHistory7
        property matrix4x4 birthHistory8
        property matrix4x4 birthHistory9
        property matrix4x4 birthHistory10
        property matrix4x4 birthHistory11
        property matrix4x4 birthHistory12
        property matrix4x4 birthHistory13
        property matrix4x4 birthHistory14
        property matrix4x4 birthHistory15
        property matrix4x4 birthHistory16
        property matrix4x4 birthHistory17
        property matrix4x4 birthHistory18
        property matrix4x4 birthHistory19
        property matrix4x4 birthHistory20
        property matrix4x4 birthHistory21
        property matrix4x4 birthHistory22
        property matrix4x4 birthHistory23
        property matrix4x4 birthHistory24
        property matrix4x4 birthHistory25
        property matrix4x4 birthHistory26
        property matrix4x4 birthHistory27
        property matrix4x4 birthHistory28
        property matrix4x4 birthHistory29
        property matrix4x4 birthHistory30
        property matrix4x4 birthHistory31
        property matrix4x4 birthHistory32
        property matrix4x4 birthHistory33
        property matrix4x4 birthHistory34
        property matrix4x4 birthHistory35
        property matrix4x4 birthHistory36
        property matrix4x4 birthHistory37
        property matrix4x4 birthHistory38
        property matrix4x4 birthHistory39
        property matrix4x4 birthHistory40
        property matrix4x4 birthHistory41
        property matrix4x4 birthHistory42
        property matrix4x4 birthHistory43
        property matrix4x4 birthHistory44
        property matrix4x4 birthHistory45
        property matrix4x4 birthHistory46
        property matrix4x4 birthHistory47
        property matrix4x4 birthHistory48
        property matrix4x4 birthHistory49
        property matrix4x4 birthHistory50
        property matrix4x4 birthHistory51
        property matrix4x4 birthHistory52
        property matrix4x4 birthHistory53
        property matrix4x4 birthHistory54
        property matrix4x4 birthHistory55
        property matrix4x4 birthHistory56
        property matrix4x4 birthHistory57
        property matrix4x4 birthHistory58
        property matrix4x4 birthHistory59
        property matrix4x4 birthHistory60
        property matrix4x4 birthHistory61
        property matrix4x4 birthHistory62
        property matrix4x4 birthHistory63

        fragmentShader: "shaders/starfield.frag.qsb"
    }

    FrameAnimation {
        running: root.running && root.visible && root.width > 0 && root.height > 0
        onRunningChanged: {
            root._pending = 0;
            root._firstFrame = true;
        }
        onTriggered: root.frame(frameTime)
    }
}
