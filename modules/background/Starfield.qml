import QtQuick
import "particles/Physics.js" as ParticlePhysics
import "particles/Appearance.js" as ParticleAppearance
import "particles/Binning.js" as ParticleBinning
import "particles/Packing.js" as ParticlePacking

// qsb resolves the sibling blackhole.glsl include from the input file directory.
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
    // ---- Camera fly-through --------------------------------------------------
    // The regime with no hole in it. `cameraEnabled` "auto" ties it to the black
    // hole, so ONE toggle turns off the hole, its gravity, its capture and its
    // tide together and puts a moving camera in their place; true/false force
    // it. The crossfade is the hole's own enable envelope run backwards, which
    // is why nothing about the toggle is a cut. Defaults leave a configured hole
    // exactly as it was.
    property var cameraEnabled: "auto"
    property string cameraDirection: "out"
    property real cameraSpeed: 6
    property real cameraDepth: 16
    property real cameraDustFlow: 3
    property real cameraRoll: 0.15
    property real cameraWander: 0.35
    property real cameraSizeGain: 0.55
    property real _cameraPosition: 0
    readonly property bool _cameraWanted: cameraEnabled === true
        || (cameraEnabled !== false && !(_hole && _hole.enabled))
    // ease(1-x) == 1-ease(x) for this smoothstep, so in "auto" this is exactly
    // the complement of the hole's own envelope and the two regimes always sum
    // to one: no frame has a hole half drawn over a camera half flying.
    readonly property real _cameraBlend: ease(_cameraPosition)
    // The far dust reverses only when the camera is flying FORWARD. In reverse
    // the stream runs inward, which is the direction it already had.
    readonly property real _cameraOutward: cameraDirection === "in" ? 0 : _cameraBlend
    property int screenSeed: 0
    property vector4d ambientBirth: Qt.vector4d(0, 0, 0, 0.5)
    property vector4d ambientLive: Qt.vector4d(0.5, 0.5, 0.5, 0.5)
    property bool varietyEnabled: true
    property int varietySeed: 1
    property real variableFraction: 0.006
    property real companionChance: 0.04
    property real fireballChance: 0.01

    property var paletteColors: []
    property var paletteWeightsTarget: []
    property real paletteMixTarget: 0.32
    property var archetypeWeightsTarget: [0.82, 0.10, 0.04, 0.02, 0.015, 0.005]
    property var archetypeParams: ({})
    property real calmTarget: 0.5
    property vector4d ambientHole: Qt.vector4d(0.5, 0.5, 0.5, 0.5)
    property var blackHole: ({})
    property var particles: ({})
    property bool particlesEnabled: true
    property var eventFamilies: ({})
    property int eventHeadCap: 3

    // advance() is the only active-clock driver, including explicit seeks.
    // Targets are filtered once, inside BlackHole (120 s, .002/s).
    property BlackHole _hole: BlackHole {
        enabled: root.blackHole && root.blackHole.enabled !== undefined ? root.blackHole.enabled : false
        size: root.blackHole && root.blackHole.size !== undefined ? root.blackHole.size : pick("size", 0.075)
        tilt: root.blackHole && root.blackHole.tilt !== undefined ? root.blackHole.tilt : pick("tilt", 14)
        intensity: root.blackHole && root.blackHole.intensity !== undefined ? root.blackHole.intensity : pick("intensity", 0.85)
        warmth: root.blackHole && root.blackHole.warmth !== undefined ? root.blackHole.warmth : 0.5
        spin: root.blackHole && root.blackHole.spin !== undefined ? root.blackHole.spin : 1
        diskInnerRs: root.blackHole && root.blackHole.diskInnerRs !== undefined ? root.blackHole.diskInnerRs : 3
        diskOuterRs: root.blackHole && root.blackHole.diskOuterRs !== undefined ? root.blackHole.diskOuterRs : pick("diskOuterRs", 8)
        beamStrength: root.blackHole && root.blackHole.beamStrength !== undefined ? root.blackHole.beamStrength : 0.15
        haloUpper: root.blackHole && root.blackHole.haloUpper !== undefined ? root.blackHole.haloUpper : pick("haloUpper", 0.55)
        haloLower: root.blackHole && root.blackHole.haloLower !== undefined ? root.blackHole.haloLower : pick("haloLower", 0.35)
        photonWidth: root.blackHole && root.blackHole.photonWidth !== undefined ? root.blackHole.photonWidth : 0.006
        structure: root.blackHole && root.blackHole.structure !== undefined ? root.blackHole.structure : 0.05
        tiltWander: root.blackHole && root.blackHole.tiltWander !== undefined ? root.blackHole.tiltWander : 0
        transitionSec: root.blackHole && root.blackHole.transitionSec !== undefined ? root.blackHole.transitionSec : 30
        preset: root.blackHole && typeof root.blackHole.preset === "string" ? root.blackHole.preset : ""
        footprintCap: root.blackHole && root.blackHole.footprintCap !== undefined ? root.blackHole.footprintCap : pick("footprintCap", 0.03)
        diskCap: root.blackHole && root.blackHole.diskCap !== undefined ? root.blackHole.diskCap : pick("diskCap", 0.25)
        photonCap: root.blackHole && root.blackHole.photonCap !== undefined ? root.blackHole.photonCap : pick("photonCap", 0.3)
        disk: root.blackHole && root.blackHole.disk !== undefined ? root.blackHole.disk : (_preset.disk !== undefined ? _preset.disk : ({}))
        photon: root.blackHole && root.blackHole.photon !== undefined ? root.blackHole.photon : (_preset.photon !== undefined ? _preset.photon : ({}))
        resolution: Qt.vector2d(root.width * root.devicePixelRatio, root.height * root.devicePixelRatio)
        centre: Qt.vector2d(resolution.x / 2 + shader.centreOffset.x, resolution.y / 2 + shader.centreOffset.y)
        // A disruption's stream landing on the disk brightens it for twenty
        // seconds. It rides the hole's own ambient activity channel, which
        // already slews with tau 30 s, so the flash arrives and leaves at the
        // same rate every other activity change does.
        // z is the brightness channel (bhLook.x reads _ambient.z); the
        // brainstorm called it activity, but activity is the pattern-speed
        // channel and would not brighten anything.
        ambientHole: Qt.vector4d(root.ambientHole.x, root.ambientHole.y, Math.min(1, root.ambientHole.z + root._tdeFlash), root.ambientHole.w)
    }

    property real _tdeFlash: 0

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
        _particles = null;
        _particlePending = null;
        _particleAtlasHeight = 0;
        shader.particleReady = 0;
        _hole.reset();
        // A fresh state has no continuity to protect, so the regime starts where
        // the configuration says rather than easing in from the other one.
        _cameraPosition = _cameraWanted ? 1 : 0;
        const history = [];
        const colors = paletteSnapshot();
        const palette = normalized(paletteWeightsTarget, colors.length, null);
        const archetypes = archetypeWeights(archetypeWeightsTarget);
        const initialMix = clamp(paletteMixTarget, 0, 0.45);
        const initialCalm = colors.length ? clamp(calmTarget, 0, 1) : 0.5;
        for (let i = 0; i < 256; ++i) {
            const bucket = i === 0 ? 0 : i - 256;
            history.push(sealDescriptor(bucket * 30, [0, 0, 0, 0.5], palette, archetypes, initialMix, initialCalm));
        }
        _state = {
            clock: 0,
            flow: 0,
            // Signed per-layer geometric advance, in flow seconds. It is the
            // SAME accumulation as `flow` (the same addend, in the same order,
            // so bit for bit the same number) while the camera is off; the
            // camera is what gives a layer a different rate and a sign, and a
            // separate accumulator is what lets the far field reverse without
            // ever running the descriptor history backwards.
            geo: [0, 0, 0],
            birth: [0, 0, 0, 0.5],
            live: [0.5, 0.5, 0.5, 0.5],
            history: history,
            atlasRevision: 1,
            publishedRevision: 0,
            pendingRevision: 0,
            pendingImage: null,
            runtimeAtlas: false,
            palette: palette,
            archetypes: archetypes,
            mix: initialMix,
            calm: initialCalm,
            entries: {},
            entryOverflow: 0,
            entrySignature: "",
            entryPixels: new Array(64 * 1280 * 3).fill(0),
            nearHashes: {},
            entryGeometry: "",
            entrySeed: screenSeed,
            entryDirty: true,
            lastLegacyFlow: 0,
            captureHistory: false,
            paddingEpoch: -1,
            bucket: 0,
            travel: [0, 0],
            // 0-4 transient (meteors, comet, satellites, shower, slowWanderer);
            // 5-9 radial phenomena (star birth, nova, red giant, supernova,
            // pulsar). The two classes never share a slot in either direction.
            events: [null, null, null, null, null, null, null, null, null, null],
            eventIds: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            familyLast: {},
            moodClock: Date.now() / 1000,
            moodCorrection: 0,
            mood: [0, 0, 0, 0],
            // Which kind owns phenomenon slot 3 and slot 4, or null.
            phenomenonSlots: [null, null],
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
    // Samples are sealed at flow boundaries. The shader selects ONE of P[n-1]
    // and P[n] with a birth-owned categorical draw; it never blends RGB meanings.
    function advance(dt: real): void {
        const s = _state;
        const before = s.birth.slice();
        const oldPalette = s.palette.slice(), oldArchetypes = s.archetypes.slice();
        const oldMix = s.mix, oldCalm = s.calm;
        const oldFlow = s.flow;
        const oldRate = 0.8 + 0.4 * s.live[2];
        const birth = [ambientBirth.x, ambientBirth.y, ambientBirth.z, ambientBirth.w];
        const live = [ambientLive.x, ambientLive.y, ambientLive.z, ambientLive.w];
        for (let i = 0; i < 4; ++i) {
            s.birth[i] = filtered(s.birth[i], birth[i], dt, 60);
            s.live[i] = filtered(s.live[i], live[i], dt, i === 3 ? 120 : 90);
        }
        const colors = paletteSnapshot();
        const palette = normalized(paletteWeightsTarget, colors.length, null);
        // Reordering changes future index meanings only. Sealed rows own RGB.
        s.palette = palette.map((x, i) => filtered(s.palette[i] || 0, x, dt, 60));
        const archetypes = archetypeWeights(archetypeWeightsTarget);
        s.archetypes = archetypeWeights(s.archetypes.map((x, i) => filtered(x, archetypes[i], dt, 60)));
        s.mix = filtered(s.mix, clamp(paletteMixTarget, 0, 0.45), dt, 60);
        s.calm = filtered(s.calm, colors.length ? calmTarget : ambientBirth.w, dt, 60);
        _hole.advance(dt);
        _cameraPosition = clamp(_cameraPosition + (_cameraWanted ? 1 : -1) * dt / Math.max(0.001, _hole.transitionSec), 0, 1);
        // Flow seconds include the user speed. Changing it never changes an
        // inferred birth phase. Zero speed freezes the ring as well as motion.
        const flowRate = (oldRate + 0.8 + 0.4 * s.live[2]) * 0.5;
        const dFlow = dt * flowRate * clamp(radialSpeed, 0, 26) / 6;
        s.flow += dFlow;
        // +1 is the inward stream. Flying the camera forward reverses it, and
        // it passes through zero on the way, so the far field decelerates,
        // stops and turns instead of cutting. Reverse playback keeps the
        // inward sign: that stream already runs the way reverse wants it.
        const sign = 1 - 2 * _cameraOutward;
        const dustRate = 1 + _cameraBlend * (clamp(cameraDustFlow, 0, 64) / Math.max(1e-6, farBoost()) - 1);
        s.geo[0] += dFlow * sign * dustRate;
        s.geo[1] += dFlow * sign;
        s.geo[2] += dFlow * sign;
        const bucket = Math.floor((s.flow + 1e-7) / 30);
        for (let n = Math.max(s.bucket + 1, bucket - 255); n <= bucket; ++n) {
            const f = clamp((n * 30 - oldFlow) / Math.max(1e-12, s.flow - oldFlow), 0, 1);
            const lerp = (a, b) => a + (b - a) * f;
            s.history[modulo(n, 256)] = sealDescriptor(s.clock + dt * f, before.map((x, i) => lerp(x, s.birth[i])), s.palette.map((x, i) => lerp(oldPalette[i] || 0, x)), oldArchetypes.map((x, i) => lerp(x, s.archetypes[i])), lerp(oldMix, s.mix), lerp(oldCalm, s.calm));
            if (s.history[modulo(n, 256)].pixels[190] > 0)
                s.captureHistory = true;
            else
                s.lastLegacyFlow = n * 30;
            ++s.historyWrites;
            ++s.atlasRevision;
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
        advanceParticles(dt);
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
                _state.geo = [_state.flow, _state.flow, _state.flow];
                _state.bucket = Math.floor(_state.flow / 30);
            }
        }
        // Explicit seeks are a verification/configuration operation, not a
        // suspend catch-up path. Runtime frame gaps never enter this loop.
        if (_hole.enabled && _state.paddingEpoch < 0)
            _state.paddingEpoch = _state.flow;
        while (_state.clock < target - 1e-9) {
            advance(Math.min(30, target - _state.clock));
            // Rebuild entry history during explicit replay, not at its final
            // destination. A seek must not rejuvenate an already-dead ID.
            if (!particlesEnabled)
                publishEntries();
        }
        _state.runtimeAtlas = false;
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
        _state.runtimeAtlas = true;
        publish();
    }

    // `phenomena` travels inside eventFamilies; an absent block is the default.
    function phenomenon(name: string): var {
        return ((eventFamilies || {}).phenomena || {})[name] || {};
    }

    function moodState(): var {
        if (!varietyEnabled)
            return [0, 0, 0, 0];
        const slot = Math.floor(_state.moodClock / 900);
        const salt = varietySeed ^ screenSeed;
        const choice = random(slot, salt + 2201);
        // Kinds 4 (clearing) and 5 (nebular) take their share off the top; the
        // four original kinds keep their relative proportions in what is left,
        // so a zero share reproduces the v5 distribution exactly.
        const moods = phenomenon("moods");
        const clearing = clamp(moods.clearing === undefined ? 0.15 : moods.clearing, 0, 1);
        const nebular = clamp(moods.nebular === undefined ? 0.15 : moods.nebular, 0, 1);
        const share = Math.min(0.9, clearing + nebular);
        const scale = clearing + nebular > 0 ? share / (clearing + nebular) : 0;
        let kind;
        if (choice < clearing * scale)
            kind = 4;
        else if (choice < share)
            kind = 5;
        else {
            const t = (choice - share) / Math.max(1e-6, 1 - share);
            kind = t < 0.50 ? 0 : t < 0.75 ? 1 : t < 0.95 ? 2 : 3;
        }
        const duration = 240 + 300 * random(slot, salt + 2202);
        const centre = 450 + 60 * (random(slot, salt + 2203) - 0.5);
        const age = modulo(_state.moodClock, 900) - centre + duration / 2;
        const weight = ease(age / 60) * ease((duration - age) / 60);
        return [kind, weight, slot, duration];
    }

    // Every row is an immutable value. All 12 packed history floats travel in
    // columns 44..55 of the SAME 64x256 opaque image as their descriptors.
    // This replaces the 12 KiB UBO with exact RGB24 storage (no bit operations
    // in GLSL). No finite palette-version bank, shortened ring or live RGB UBO.
    function normalized(values: var, count: int, fallback: var): var {
        const out = [];
        let total = 0;
        for (let i = 0; i < count; ++i) {
            const x = Number(values && values[i]);
            out.push(Number.isFinite(x) ? Math.max(0, x) : 0);
            total += out[i];
        }
        if (total <= 0) {
            for (let i = 0; i < count; ++i)
                out[i] = fallback && Number.isFinite(fallback[i]) ? Math.max(0, fallback[i]) : 1;
            total = out.reduce((a, b) => a + b, 0);
        }
        return out.map(x => total > 0 ? x / total : 1 / Math.max(1, count));
    }

    function archetypeWeights(values: var): var {
        const a = normalized(values, 6, [0.82, 0.10, 0.04, 0.02, 0.015, 0.005]);
        const moving = a.slice(1).reduce((x, y) => x + y, 0);
        const scale = Math.min(1, 0.25 / Math.max(1e-12, moving));
        for (let i = 1; i < 6; ++i)
            a[i] *= scale;
        a[0] = 1 - Math.min(0.25, moving);
        return a;
    }

    function parameterRange(object: var, key: string, fallback: var, low: real, high: real): var {
        const raw = object && object[key];
        if (!Array.isArray(raw) || raw.length !== 2 || !raw.every(x => Number.isFinite(x)))
            return fallback.slice();
        const a = clamp(raw[0], low, high);
        return [a, clamp(raw[1], a, high)];
    }

    function paletteSnapshot(): var {
        if (!Array.isArray(paletteColors))
            return [];
        return paletteColors.slice(0, 16).map(c => [0, 1, 2].map(i => clamp(Number(c && c[i]), 0, 1)));
    }

    function sealDescriptor(stamp: real, birth: var, weights: var, archetypes: var, mix: real, calm: real): var {
        const colors = paletteSnapshot();
        const pixels = new Array(64 * 3).fill(0);
        const packed = new Array(12).fill(0);
        function rgb(column, r, g, b) {
            pixels[column * 3] = Math.round(r);
            pixels[column * 3 + 1] = Math.round(g);
            pixels[column * 3 + 2] = Math.round(b);
        }
        function integer(column, value) {
            const n = Math.round(value);
            rgb(column, n % 256, Math.floor(n / 256) % 256, Math.floor(n / 65536) % 256);
        }
        function number16(column, value, maximum) {
            const q = Math.round(clamp(value / maximum, 0, 1) * 65535);
            rgb(column, q % 256, Math.floor(q / 256), 0);
        }
        for (let i = 0; i < colors.length; ++i)
            rgb(i, colors[i][0] * 255, colors[i][1] * 255, colors[i][2] * 255);
        const cw = normalized(weights, colors.length, null);
        let cumulative = 0;
        for (let i = 0; i < 16; ++i) {
            cumulative += i < cw.length ? cw[i] : 0;
            const threshold = i >= colors.length - 1 ? 255 : Math.round(cumulative * 255);
            packed[Math.floor(i / 3)] += threshold * Math.pow(256, i % 3);
        }
        const aw = archetypeWeights(archetypes);
        cumulative = 0;
        for (let i = 0; i < 6; ++i) {
            cumulative += aw[i];
            packed[6 + Math.floor(i / 2)] += (i === 5 ? 1023 : Math.round(cumulative * 1023)) * Math.pow(1024, i % 2);
        }
        packed[9] = Math.round(clamp(calm, 0, 1) * 255) + 256 * Math.round(clamp(mix, 0, 0.45) * 255) + 65536 * colors.length;
        // Epoch days are biased to represent the startup prehistory. The second
        // word is 1/128 s within the day: <2^24, 7.8125 ms precision at any uptime.
        const ticks = Math.floor(stamp * 128);
        packed[10] = Math.floor(ticks / 11059200) + 32768;
        packed[11] = modulo(ticks, 11059200);
        for (let i = 0; i < 12; ++i)
            integer(44 + i, packed[i]);
        rgb(56, clamp(birth[0], 0, 1) * 255, clamp(birth[1], 0, 1) * 255, clamp(birth[2], 0, 1) * 255);
        const params = archetypeParams || {};
        const pulse = params.pulsator || {};
        const decay = params.decayer || {};
        const glint = params.glint || {};
        const wander = params.wanderer || {};
        const binary = params.binary || {};
        const shifter = params.colorShifter || {};
        const ranges = [[0, 0, 0, 0], parameterRange(pulse, "periodSec", [6, 40], 1, 4096).concat(parameterRange(pulse, "amplitude", [0.08, 0.22], 0, 0.22)), parameterRange(decay, "lifeSec", [20, 90], 20, 3600).concat(parameterRange(decay, "fadeInSec", [3, 8], 0.1, 120)), parameterRange(glint, "everySec", [18, 65], 2, 4096).concat(parameterRange(glint, "widthSec", [0.8, 2], 0.1, 60)), parameterRange(wander, "periodSec", [30, 100], 2, 4096).concat([clamp(wander.offsetPx === undefined ? 8 : wander.offsetPx, 0, 8), 0]), parameterRange(binary, "periodSec", [12, 45], 2, 4096).concat(parameterRange(binary, "separationPx", [1.5, 5], 0, 16)), parameterRange(shifter, "periodSec", [120, 360], 30, 4096).concat([0, 0])];
        const maxima = [[1, 1, 1, 1], [4096, 4096, 1, 1], [3600, 3600, 120, 120], [4096, 4096, 60, 60], [4096, 4096, 8, 8], [4096, 4096, 16, 16], [4096, 4096, 1, 1]];
        for (let a = 0; a < 7; ++a)
            for (let j = 0; j < 4; ++j)
                number16(16 + 4 * a + j, ranges[a][j], maxima[a][j]);
        const far = params.farWeights || {
            steady: 0.97,
            pulsator: 0.03
        };
        const farWeights = normalized(Array.isArray(far) ? far : [far.steady, far.pulsator], 2, [0.97, 0.03]);
        // Far dust needs one header fetch, including calm and palette mode.
        integer(57, Math.round(clamp(calm, 0, 1) * 255) + 256 * Math.round(Math.min(0.25, farWeights[1]) * 1023) + 262144 * colors.length);
        const shiftShare = shifter.enabled ? clamp(shifter.share === undefined ? 0.005 : shifter.share, 0, 0.005) : 0;
        // Shifters take steady share; all non-steady types together remain <=25%.
        const sealedSteady = Math.max(0.75, Math.round(aw[0] * 1023) / 1023);
        number16(58, Math.floor(Math.min(shiftShare, sealedSteady - 0.75) * 65535) / 65535, 1);
        pixels[58 * 3 + 2] = Math.round(clamp(glint.gain === undefined ? 0.18 : glint.gain, 0, 0.18) * 255);
        rgb(59, 0, 0.10 * 255, 0.35 * 255); // fixed layer traits, not live brightness
        function hue(c) {
            const hi = Math.max(...c), lo = Math.min(...c), d = hi - lo;
            if (d < 1e-6)
                return 0;
            const h = hi === c[0] ? (c[1] - c[2]) / d : hi === c[1] ? 2 + (c[2] - c[0]) / d : 4 + (c[0] - c[1]) / d;
            return modulo(h, 6);
        }
        const order = colors.map((c, i) => [hue(c), i]).sort((a, b) => a[0] - b[0]);
        for (let i = 0; i < order.length; ++i) {
            const index = order[i][1], next = order[(i + 1) % order.length][1];
            const byte = 60 * 3 + Math.floor(index / 2);
            pixels[byte] += next * Math.pow(16, index % 2);
        }
        // Only future sealed cohorts adopt capture lifetime. Startup prehistory
        // keeps v3 lifetime; disabling/re-enabling never upgrades those IDs.
        rgb(63, 3, stamp > 0 && _hole.enabled ? 255 : 0, 0);
        return {
            packed: packed,
            pixels: pixels
        };
    }

    function atlasUrl(): string {
        // 24-bit BI_RGB BMP has no colour profile or gamma chunk, no alpha to
        // premultiply. The first 64x256 tile is the unchanged immutable cohort
        // atlas; a 64x1280 entry ledger follows it. A single 64x1536 upload
        // publishes both tiles and their uniforms atomically, at any DPR.
        // QImage uploads this opaque image as RGBA8. Bottom-up rows are explicit.
        const bytes = [];
        function le(n, count) {
            for (let i = 0; i < count; ++i)
                bytes.push(Math.floor(n / Math.pow(256, i)) % 256);
        }
        le(0x4d42, 2);
        le(54 + 64 * 1536 * 3, 4);
        le(0, 4);
        le(54, 4);
        le(40, 4);
        le(64, 4);
        le(1536, 4);
        le(1, 2);
        le(24, 2);
        le(0, 4);
        le(64 * 1536 * 3, 4);
        le(0, 4);
        le(0, 4);
        le(0, 4);
        le(0, 4);
        for (let row = 1535; row >= 0; --row) {
            const p = row < 256 ? _state.history[row].pixels : _state.entryPixels;
            const offset = row < 256 ? 0 : (row - 256) * 64 * 3;
            for (let x = 0; x < 64; ++x)
                bytes.push(p[offset + x * 3 + 2], p[offset + x * 3 + 1], p[offset + x * 3]);
        }
        return "data:image/bmp;base64," + Qt.btoa(bytes);
    }

    function blockSalt(block: real, layer: int, axis: int): real {
        return random(block, screenSeed + 761 + layer * 997 + axis * 347) * 97;
    }

    // The far layer's inflow multiplier. Read by both the grid advance and the
    // camera's dust rate, which is expressed against it.
    function farBoost(): real {
        const dust = _particles && particlesEnabled ? _particles.config.dust : null;
        return dust ? dust.farFlow * Math.sqrt(_particles.config.mass) : 1;
    }

    // Lateral camera drift, as a fraction of the short side. The long 2048 s
    // swing is v3's; the camera regime borrows part of its AMPLITUDE for a
    // livelier pair of periods instead of adding to it, so the excursion never
    // leaves the 0.012 short sides that every birth-padding guarantee is sized
    // for. Both extra periods are integer cycles of 4096 s, so nothing steps
    // when the phase clock wraps.
    function wanderOffset(clock: real, phase: real): var {
        const a = clamp(centreWander, 0, 0.012);
        const w = 0.5 * clamp(cameraWander, 0, 1) * _cameraBlend;
        return [a * ((1 - w) * wave(clock, 2, phase) + w * wave(clock, 11, phase * 1.3)),
            a * ((1 - w) * wave(clock, 2, phase + 1.7) + w * wave(clock, 17, phase * 0.7 + 2.1))];
    }

    function eventOff(): var {
        return {
            head: [0, 0, 1, 0],
            colour: [1, 1, 1, 0],
            tail01: [0, 0, 0, 0],
            tail23: [0, 0, 0, 0],
            tail4: [0, 0],
            shape: [0, 0, 0, 0],
            bounds: [0, 0, 0, 0]
        };
    }

    // Kinds 5-9 are the radial phenomena; their names are the JSON family keys.
    readonly property var radialNames: ["starBirth", "nova", "redGiant", "supernova", "pulsar"]

    function eventConfig(kind: int): var {
        const config = eventFamilies || {};
        if (kind >= 5)
            return (config.events || config)[radialNames[kind - 5]] || {};
        return kind === 0 ? config.meteors || {} : kind === 1 ? config.comet || {} : kind === 3 ? (config.events || config).shower || {} : kind === 4 ? (config.events || config).slowWanderer || {} : {};
    }

    function eventEnabled(kind: int): bool {
        if (kind < 3)
            return kind === 0 ? meteorsEnabled : kind === 1 ? cometEnabled : satellitesEnabled;
        const cfg = eventConfig(kind);
        if (cfg.enabled !== undefined)
            return cfg.enabled !== false;
        // An absent family is its documented default, and the pulsar's is off:
        // a strictly periodic point is the one item in the catalogue the taste
        // rules argue against, so it never turns itself on.
        return kind !== 9;
    }

    function familyDefaults(kind: int): var {
        // weight, duration low/high, gain cap, tail low/high, bend low/high,
        // travel low/high. Lengths are fractions of the captured short side.
        return kind === 0 ? {
            straight: [0.75, 0.7, 1.3, 0.85, 0.08, 0.14, 0, 0, 0.28, 0.38],
            curved: [0.20, 0.9, 1.7, 0.80, 0.06, 0.10, 0.005, 0.02, 0.28, 0.38],
            skipping: [0.05, 1.2, 2.2, 0.70, 0.08, 0.12, 0, 0.008, 0.3, 0.4]
        } : {
            fast: [0.15, 4, 9, 0.55, 0.04, 0.08, 0, 0, 0.35, 0.65],
            slow: [0.50, 30, 65, 0.26, 0.20, 0.32, 0, 0, 0.5, 0.8],
            bent: [0.30, 12, 28, 0.38, 0.10, 0.18, 0.02, 0.06, 0.5, 0.8],
            pulsating: [0.05, 20, 40, 0.32, 0.12, 0.22, 0.01, 0.04, 0.5, 0.8],
            fragmenting: [0, 8, 16, 0.38, 0.06, 0.14, 0.01, 0.04, 0.45, 0.65],
            spiral: [0, 18, 35, 0.25, 0.08, 0.16, 0, 0, 0.5, 0.8]
        };
    }

    function chooseFamily(kind: int, index: int, start: real): string {
        const defaults = familyDefaults(kind);
        const names = Object.keys(defaults);
        const overrides = eventConfig(kind).families || {};
        const weights = names.map(name => {
            const cfg = overrides[name] || {};
            const value = cfg.weight === undefined ? defaults[name][0] : clamp(cfg.weight, 0, 100);
            const cooldown = name === "fragmenting" ? 7200 : name === "spiral" ? 14400 : 0;
            if (cooldown && start - (_state.familyLast[name] === undefined ? -1e12 : _state.familyLast[name]) < Math.max(cooldown, Number(cfg.cooldownSec) || 0))
                return 0;
            return value;
        });
        const fragment = names.indexOf("fragmenting");
        if (fragment >= 0) {
            const other = weights.reduce((a, b, i) => a + (i === fragment ? 0 : b), 0);
            weights[fragment] = Math.min(weights[fragment], other * 0.02 / 0.98);
        }
        const probabilities = normalized(weights, names.length, names.map(name => defaults[name][0]));
        let draw = random(index, screenSeed + 3107 + kind * 701);
        for (let i = 0; i < names.length; ++i) {
            draw -= probabilities[i];
            if (draw < 0)
                return names[i];
        }
        return names[names.length - 1];
    }

    function captureEvent(kind: int, index: int, start: real, family: string): var {
        const salt = screenSeed + 113 + kind * 701;
        const cfg = eventConfig(kind);
        const d = kind < 2 ? familyDefaults(kind)[family] : [1, kind === 4 ? 180 : 30, kind === 4 ? 360 : 45, kind === 4 ? 0.40 : 0.33, 0, 0, 0.01, 0.04, 0.85, 1.1];
        const f = (cfg.families || {})[family] || cfg;
        function sample(key, fallback, lo, hi, offset) {
            const range = parameterRange(f, key, fallback, lo, hi);
            return range[0] + (range[1] - range[0]) * random(index, salt + offset);
        }
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const optics = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
        const angle = (random(index, salt + 4) * 2 - 1) * Math.PI;
        const dx = Math.cos(angle), dy = Math.sin(angle);
        const x = w * (0.2 + 0.6 * random(index, salt + 5));
        const y = h * (0.2 + 0.6 * random(index, salt + 6));
        const distance = shortSide * (d[8] + (d[9] - d[8]) * random(index, salt + 7));
        const centre = [w * 0.5 + shader.centreOffset.x, h * 0.5 + shader.centreOffset.y];
        const bend = sample("bendShortSide", [d[6], d[7]], 0, 0.12, 8) * shortSide;
        const toward = clamp((centre[0] - x) * -dy + (centre[1] - y) * dx, -bend, bend);
        const colors = paletteSnapshot();
        const defaultMix = kind === 0 ? 0.25 : kind === 1 ? 0.35 : 0.25;
        const mixConfig = (eventFamilies || {}).paletteMix;
        const mixValue = cfg.paletteMix === undefined ? (mixConfig && mixConfig[kind === 0 ? "meteors" : "comet"]) : cfg.paletteMix;
        const mix = clamp(mixValue === undefined ? defaultMix : mixValue, 0, 0.45);
        let colour = kind === 2 ? [1, 0.95, 0.86] : [0.81, 0.89, 1];
        if (colors.length && random(index, salt + 21) < mix) {
            const weights = normalized(_state.palette, colors.length, null);
            let draw = random(index, salt + 22), pick = 0;
            for (; pick < weights.length - 1; ++pick) {
                draw -= weights[pick];
                if (draw < 0)
                    break;
            }
            colour = colors[pick].slice();
        }
        const pair = kind === 0 && random(index, salt + 1) < clamp(companionChance, 0, 1);
        const fireball = kind === 0 && random(index, salt + 9) < clamp(fireballChance, 0, 1);
        const duration = sample("durationSec", [d[1], d[2]], kind < 2 ? 0.5 : 10, kind === 4 ? 3600 : 300, 3);
        const event = {
            kind: kind,
            index: index,
            family: family,
            start: start,
            duration: duration,
            offset: pair ? 0.35 + 0.35 * random(index, salt + 2) : 0,
            pair: pair,
            fireball: fireball,
            p0: [x - dx * distance / 2, y - dy * distance / 2],
            p1: [x - dy * toward, y + dx * toward],
            p2: [x + dx * distance / 2, y + dy * distance / 2],
            centre: centre,
            angle: angle,
            distance: distance,
            shortSide: shortSide,
            tail: sample("tailShortSide", [d[4], d[5]], 0, 0.4, 11) * shortSide,
            gain: clamp(f.gain === undefined ? d[3] : f.gain, 0, d[3]),
            headCap: Math.round(clamp(eventHeadCap, 0, 3)),
            pointWidth: kind === 0 ? optics * 0.40 * (fireball ? 1.4 : 1) : kind === 1 ? optics * 0.70 : 0.65,
            colour: colour,
            bend: toward,
            pulsePeriod: sample("periodSec", [4, 9], 2, 60, 12),
            pulseAmplitude: clamp(f.amplitude === undefined ? 0.12 : f.amplitude, 0, 0.12),
            lobes: 2 + Math.floor(random(index, salt + 13) * 2),
            splitU: sample("splitU", [0.45, 0.65], 0.3, 0.75, 14),
            splitSec: clamp(f.splitSec === undefined ? 1.5 : f.splitSec, 1.5, 5),
            omega: (random(index, salt + 15) < 0.5 ? -1 : 1) * Math.PI / 3,
            radius: shortSide * (0.22 + 0.12 * random(index, salt + 16))
        };
        // Satellite glint: one hash-placed smooth brightening somewhere along
        // the pass. Birth-frozen like everything else here, so it never moves,
        // and it modulates the gain the slot already publishes at 30 Hz - no
        // new slot, no new uniform, no shader change.
        if (kind === 2) {
            const glint = (eventFamilies || {}).satelliteGlint || {};
            const span = parameterRange(glint, "widthSec", [1.5, 3], 0.5, 10);
            event.glintGain = glint.enabled === false ? 1 : clamp(glint.gain === undefined ? 2.2 : glint.gain, 1, 4);
            event.glintWidth = span[0] + (span[1] - span[0]) * random(index, salt + 17);
            // Kept clear of both ends so the brightening never lands on the
            // entrance or exit fade and read as a pop.
            event.glintAt = duration * (0.25 + 0.5 * random(index, salt + 18));
        }
        classifyCapture(event);
        return event;
    }

    // Active-second scheduling, up to seven days; hourly streams do not get
    // silently clamped to the v2 one-hour interval ceiling. Descriptors include
    // their schedule and geometry; edits only affect the next captured event.
    function schedule(kind: int): var {
        const s = _state;
        if (!eventEnabled(kind))
            return null;
        const index = s.eventIds[kind]++;
        const cfg = eventConfig(kind);
        let range;
        if (kind >= 3) {
            range = parameterRange(cfg, "everyHours", kind === 3 ? [2, 5] : [2, 6], 0.01, 168).map(x => x * 3600);
        } else {
            const v = kind === 0 ? meteorsInterval : kind === 1 ? cometInterval : satellitesInterval;
            const minimum = clamp(v.x, kind === 0 ? 3 : kind === 1 ? 60 : 45, 604800);
            range = [minimum, clamp(v.y, minimum, 604800)];
        }
        const shower = s.events[3];
        const inShower = shower && s.clock >= shower.start && s.clock <= shower.start + shower.duration;
        const activeMood = !inShower && s.mood[0] === 3 ? s.mood[1] : 0;
        const rate = kind === 0 ? 0.5 + s.live[3] : 1;
        if (kind === 0)
            range = [range[0] + (18 - range[0]) * activeMood, range[1] + (36 - range[1]) * activeMood];
        const previous = s.events[kind];
        const base = previous ? previous.start : s.clock;
        let start = Math.max(s.clock, base + (range[0] + (range[1] - range[0]) * random(index, screenSeed + 113 + kind * 701)) / rate);
        const family = kind < 2 ? chooseFamily(kind, index, start) : kind === 3 ? "shower" : kind === 4 ? "slowWanderer" : "satellite";
        const e = captureEvent(kind, index, start, kind === 3 ? "straight" : family);
        if (kind === 3) {
            e.duration = 30 + 30 * random(index, screenSeed + 4091);
            e.pair = false;
            e.offset = 0;
        }
        // Reserve complete episodes, companions and splits without replacing
        // visible heads. Ordinary arrivals are capped at two; splits may use 3.
        // Transient heads reserve against each other only. The radial phenomena
        // in 5-9 are a separate class with its own slots, so a six-minute
        // remnant can no longer starve a meteor.
        for (let pass = 0; pass < 6; ++pass)
            for (let k = 0; k < 5; ++k) {
                const other = s.events[k];
                if (k !== kind && other && start < other.start + other.duration + other.offset + 1 && start + e.duration + e.offset + 1 > other.start)
                    start = other.start + other.duration + other.offset + 1;
            }
        e.start = start;
        if (family === "fragmenting" || family === "spiral")
            s.familyLast[family] = start;
        if (kind === 3) {
            e.family = "shower";
            e.children = [];
            e.radiant = [e.centre[0] - Math.cos(e.angle) * e.shortSide * 0.45, e.centre[1] - Math.sin(e.angle) * e.shortSide * 0.45];
            const count = 4 + Math.floor(random(index, screenSeed + 4092) * 3);
            // Equal stagger fits the captured 30..60s episode and remains 4..12s.
            const stagger = clamp((e.duration - 3) / (count - 1), 4, 12);
            for (let i = 0; i < count; ++i) {
                const child = captureEvent(0, index * 7 + i, start + i * stagger, "straight");
                // Family overrides cannot leave a visible child unfinished when
                // its reserved episode ends, or overbook the next head slot.
                child.duration = Math.min(child.duration, stagger - 1, e.duration - i * stagger);
                const a = e.angle + (random(index * 7 + i, screenSeed + 4093) - 0.5) * 0.12;
                const dx = Math.cos(a), dy = Math.sin(a);
                const along = e.shortSide * (0.30 + 0.35 * random(index * 7 + i, screenSeed + 4094));
                const x = e.radiant[0] + dx * along, y = e.radiant[1] + dy * along;
                child.p0 = [x - dx * child.distance / 2, y - dy * child.distance / 2];
                child.p1 = [x, y];
                child.p2 = [x + dx * child.distance / 2, y + dy * child.distance / 2];
                child.angle = a;
                child.bend = 0;
                child.pair = false;
                child.offset = 0;
                child.capture = false;
                classifyCapture(child);
                child.gain = Math.min(0.60, child.gain);
                e.children.push(child);
            }
        }
        return e;
    }

    // ---- Radial phenomena (kinds 5-9) -------------------------------------
    // All five draw through shader style 3 (core + halo + ring + echo ring) and
    // differ only in envelope, colour, size and schedule. Everything below is
    // captured once, at schedule time, from the same hash stream the transient
    // events use, so an edit to the config only reaches the NEXT episode.

    // A phenomenon may not sit where the shader cannot draw it honestly: events
    // composite after the disk and are not shadow-masked, so one inside the
    // lensing reach would shine straight through the hole. Rejection, not
    // clamping, so the distribution outside the exclusion stays uniform.
    function radialPlacement(index: int, salt: real): var {
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const margin = 0.05 * shortSide;
        const centre = [w * 0.5 + shader.centreOffset.x, h * 0.5 + shader.centreOffset.y];
        const keepOut = 1.6 * (_hole.enabled ? _hole.bhGeometry.y : 0);
        for (let attempt = 0; attempt < 8; ++attempt) {
            const x = margin + (w - 2 * margin) * random(index, salt + 40 + attempt * 2);
            const y = margin + (h - 2 * margin) * random(index, salt + 41 + attempt * 2);
            if (Math.hypot(x - centre[0], y - centre[1]) >= keepOut)
                return [x, y];
        }
        return null;
    }

    function captureRadial(kind: int, index: int, start: real): var {
        const name = radialNames[kind - 5];
        const cfg = eventConfig(kind);
        const salt = screenSeed + 5501 + kind * 907;
        const place = radialPlacement(index, salt);
        if (!place)
            return null;
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const optics = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
        function sample(key, fallback, lo, hi, offset) {
            const range = parameterRange(cfg, key, fallback, lo, hi);
            return range[0] + (range[1] - range[0]) * random(index, salt + offset);
        }
        function value(key, fallback, cap) {
            return clamp(cfg[key] === undefined ? fallback : cfg[key], 0, cap);
        }
        // Near-layer optical scale, so a phenomenon is as legible as the
        // brightest stars rather than as a speck of dust.
        const core = optics * 0.9;
        const e = {
            kind: kind,
            family: name,
            index: index,
            start: start,
            radial: true,
            x: place[0],
            y: place[1],
            shortSide: shortSide,
            core: core,
            colour: [1, 0.96, 0.88],
            hyper: false
        };
        const colors = paletteSnapshot();
        const mix = clamp(cfg.paletteMix === undefined ? 0.30 : cfg.paletteMix, 0, 0.45);
        if (colors.length && random(index, salt + 21) < mix) {
            const weights = normalized(_state.palette, colors.length, null);
            let draw = random(index, salt + 22), pick = 0;
            for (; pick < weights.length - 1; ++pick) {
                draw -= weights[pick];
                if (draw < 0)
                    break;
            }
            // Kept close to white: these are bright objects, not coloured ones.
            const c = colors[pick];
            e.colour = [c[0] + (1 - c[0]) * 0.45, c[1] + (1 - c[1]) * 0.45, c[2] + (1 - c[2]) * 0.45];
        }
        if (kind === 5) {
            e.gain = value("gain", 0.22, 0.22);
            e.duration = sample("durationSec", [180, 360], 10, 1800, 3);
            e.condense = Math.min(sample("condenseSec", [40, 90], 0, 600, 5), e.duration * 0.5);
            // haloPx is a from-to span and MAY descend (18 -> 4 is the default
            // condensation), so it is read directly rather than through
            // parameterRange, which sorts its pair.
            const raw = Array.isArray(cfg.haloPx) && cfg.haloPx.length === 2 && cfg.haloPx.every(x => Number.isFinite(x)) ? cfg.haloPx : [18, 4];
            e.halo0 = clamp(raw[0], 0.5, 64) * optics * 0.5;
            e.halo1 = clamp(raw[1], 0.5, 64) * optics * 0.5;
        } else if (kind === 6) {
            e.gain = value("gain", 0.45, 0.45);
            e.rise = Math.max(0.8, sample("riseSec", [1.5, 3], 0, 600, 3));
            e.hold = sample("holdSec", [0.5, 1.5], 0, 600, 5);
            e.decay = sample("decaySec", [25, 60], 0, 600, 7);
            e.duration = e.rise + e.hold + e.decay;
            e.shell = sample("shellShortSide", [0.02, 0.04], 0, 0.15, 9) * shortSide;
            e.shellGain = value("shellGain", 0.12, 0.15);
        } else if (kind === 7) {
            e.gain = value("gain", 0.28, 0.28);
            e.duration = sample("durationSec", [240, 480], 10, 1800, 3);
            e.swell = Math.min(sample("swellSec", [90, 150], 0, 600, 5), e.duration * 0.4);
            e.collapse = Math.min(sample("collapseSec", [45, 75], 0, 600, 7), e.duration * 0.3);
            e.nebula = clamp(cfg.nebulaShortSide === undefined ? 0.015 : cfg.nebulaShortSide, 0, 0.15) * shortSide;
            e.nebulaGain = value("nebulaGain", 0.06, 0.15);
            e.warm = [1, 0.86, 0.72];
        } else if (kind === 8) {
            e.rise = Math.max(0.8, sample("riseSec", [0.8, 1.5], 0, 600, 3));
            e.hold = sample("holdSec", [0.5, 1.5], 0, 600, 5);
            e.decay = sample("decaySec", [90, 240], 0, 600, 7);
            e.remnant = sample("remnantSec", [180, 360], 0, 1800, 9);
            e.duration = e.rise + e.hold + e.decay + e.remnant;
            e.shell = sample("shellShortSide", [0.06, 0.11], 0, 0.15, 11) * shortSide;
            e.shellGain = value("shellGain", 0.10, 0.15);
            e.echoGain = value("echoGain", 0.04, 0.15);
            e.echoDelay = sample("echoDelaySec", [60, 120], 0, 600, 13);
            e.echoScale = 2 + random(index, salt + 15);
            const share = clamp(cfg.hypernovaShare === undefined ? 0.15 : cfg.hypernovaShare, 0, 1);
            const cooldown = Math.max(600, Math.min(604800, Number(cfg.hypernovaCooldownSec) || 21600));
            const last = _state.familyLast.hypernova === undefined ? -1e12 : _state.familyLast.hypernova;
            e.hyper = random(index, salt + 17) < share && start - last >= cooldown;
            e.gain = e.hyper ? value("hypernovaGain", 0.78, 0.78) : value("gain", 0.70, 0.70);
            if (e.hyper)
                e.peakColour = [0.82, 0.90, 1];
        } else {
            e.gain = value("gain", 0.30, 0.30);
            e.duration = sample("durationSec", [240, 600], 10, 1800, 3);
            e.period = Math.max(0.8, sample("periodSec", [0.8, 2], 0, 600, 5));
            e.floor = Math.max(0.5, clamp(cfg.floorFraction === undefined ? 0.60 : cfg.floorFraction, 0, 1));
            e.edge = Math.max(0.10, clamp(cfg.edgeSec === undefined ? 0.12 : cfg.edgeSec, 0, 600));
        }
        return e;
    }

    // Dramatic families share one cooldown, so the sky never stacks two of them.
    function dramatic(kind: int): bool {
        return kind === 8;
    }

    function scheduleRadial(kind: int): var {
        const s = _state;
        if (!eventEnabled(kind))
            return null;
        const index = s.eventIds[kind]++;
        const cfg = eventConfig(kind);
        const salt = screenSeed + 5501 + kind * 907;
        let range;
        if (kind === 8 || kind === 9)
            range = parameterRange(cfg, "everyHours", kind === 8 ? [1.5, 3] : [2, 4], 0.25, 168).map(x => x * 3600);
        else
            range = parameterRange(cfg, "everyMinutes", kind === 5 ? [20, 45] : kind === 6 ? [25, 50] : [45, 90], 1, 1440).map(x => x * 60);
        const previous = s.events[kind];
        const base = previous ? previous.start : s.clock;
        let start = Math.max(s.clock, base + range[0] + (range[1] - range[0]) * random(index, salt));
        if (dramatic(kind)) {
            const cooldown = clamp(Number((eventFamilies || {}).dramaCooldownSec) || 4500, 600, 86400);
            const last = s.familyLast.drama === undefined ? -1e12 : s.familyLast.drama;
            start = Math.max(start, last + cooldown);
        }
        const e = captureRadial(kind, index, start);
        if (!e)
            return null;
        // Phenomena reserve against each other only: the transient heads are a
        // separate class and must never be pushed around by a six-minute
        // remnant, which is the whole reason for the split. Reservation allows
        // exactly `phenomenonCap` to overlap, so the second slot is used but no
        // episode is ever scheduled into a slot that cannot exist — a
        // phenomenon that lost a slot mid-life would pop, which is the failure
        // this whole pass is about.
        const cap = Math.round(clamp(Number((eventFamilies || {}).phenomenonCap) || 2, 1, 2));
        for (let pass = 0; pass < 6; ++pass) {
            const ends = [];
            for (let k = 5; k < s.events.length; ++k) {
                const other = s.events[k];
                if (k !== kind && other && start < other.start + other.duration && start + e.duration > other.start)
                    ends.push(other.start + other.duration);
            }
            if (ends.length < cap)
                break;
            start = Math.min(...ends) + 1;
        }
        e.start = start;
        if (dramatic(kind))
            s.familyLast.drama = start;
        if (e.hyper)
            s.familyLast.hypernova = start;
        return e;
    }

    // Head, colour, tail01, shape and bounds for shader style 3. `exempt` is
    // the share of the gain that a supernova flash may spend outside the
    // combined phenomenon cap; it eases with the flash rather than switching.
    function radialState(e: var): var {
        const off = {
            head: [0, 0, 0, 0],
            colour: [0, 0, 0, 3],
            tail01: [0, 0, 0, 0],
            shape: [0, 0, 0, 0],
            bounds: [0, 0, 0, 0],
            exempt: 0
        };
        if (!e)
            return off;
        const age = _state.clock - e.start;
        if (age < 0 || age > e.duration)
            return off;
        // Every component carries an ABSOLUTE linear gain here and is turned
        // into a fraction of the slot's peak at the end. A shell that was
        // scaled by the core's own decay could never outlive it, which is
        // exactly what a nova shell has to do.
        let coreAbs = 0, haloAbs = 0, ringAbs = 0, echoAbs = 0;
        let halo = 0, core = e.core;
        let ringWidth = 0, ringRadius = 0, echoRadius = 0;
        let colour = e.colour, exempt = 0;
        if (e.kind === 5) {
            // Star birth: a diffuse knot condenses into a core. Nothing in it
            // is sudden; the entrance and the exit are both tens of seconds.
            const t = ease(age / Math.max(0.001, e.condense));
            halo = e.halo0 + (e.halo1 - e.halo0) * t;
            core = e.core * (0.6 + 0.4 * t);
            const env = e.gain * ease(age / Math.max(0.001, e.condense)) * ease((e.duration - age) / 60);
            haloAbs = env * 0.27 * (1 - 0.45 * t);
            coreAbs = env * 0.72 * t * t;
        } else if (e.kind === 6) {
            const flash = e.rise + e.hold;
            let env;
            if (age < e.rise)
                env = e.gain * ease(age / e.rise);
            else if (age < flash)
                env = e.gain;
            else {
                const d = (age - flash) / Math.max(0.001, e.decay);
                env = e.gain * Math.exp(-3.2 * d) * ease((1 - d) / 0.18);
            }
            coreAbs = env;
            haloAbs = 0.15 * env;
            halo = e.core * 3.5;
            // The shell leaves in the last 60 % of the decay and fades out with
            // its own radius, so it never ends on a visible edge. Its gain is
            // its own, so it survives the core it came from.
            const u = clamp((age - flash - 0.4 * e.decay) / Math.max(0.001, 0.6 * e.decay), 0, 1);
            if (u > 0 && u < 1) {
                ringRadius = e.shell * u;
                ringWidth = Math.max(1.5, e.core * (0.8 + 2.5 * u));
                ringAbs = e.shellGain * ease(u / 0.2) * (1 - u) * (1 - u);
            }
        } else if (e.kind === 7) {
            // Red giant: swell and warm, hold, collapse, then one half-second
            // brightening and a planetary-nebula shell.
            const grow = ease(age / Math.max(0.001, e.swell));
            const shrink = ease((e.duration - age) / Math.max(0.001, e.collapse));
            const size = grow * shrink;
            halo = e.core * (2.5 + 9 * size);
            colour = [e.colour[0] + (e.warm[0] - e.colour[0]) * size, e.colour[1] + (e.warm[1] - e.colour[1]) * size, e.colour[2] + (e.warm[2] - e.colour[2]) * size];
            const tail = e.duration - age;
            // A gentle final flare, eased in and out over a second either side.
            const flare = tail < e.collapse ? ease((e.collapse - tail) / Math.max(0.001, e.collapse * 0.5)) : 0;
            const env = e.gain * ease(age / 20) * (0.55 + 0.45 * size) * (1 + 0.35 * flare) * ease(tail / 6);
            coreAbs = 0.70 * env;
            haloAbs = 0.30 * size * env;
            const u = clamp((age - (e.duration - e.collapse)) / Math.max(0.001, e.collapse), 0, 1);
            if (u > 0) {
                ringRadius = e.nebula * u;
                ringWidth = Math.max(1.5, e.core * (1 + 3 * u));
                ringAbs = e.nebulaGain * ease(u / 0.25) * (1 - u);
            }
        } else if (e.kind === 8) {
            const flash = e.rise + e.hold;
            let env;
            if (age < e.rise)
                env = e.gain * ease(age / e.rise);
            else if (age < flash)
                env = e.gain;
            else {
                const d = (age - flash) / Math.max(0.001, e.decay + e.remnant);
                env = e.gain * Math.exp(-4.0 * d) * ease((1 - d) / 0.25);
            }
            // The flash exemption eases away over three seconds of the decay,
            // so the combined phenomenon cap takes hold without a step.
            exempt = ease((flash + 3 - age) / 3);
            if (e.hyper && e.peakColour) {
                const peak = ease((flash + 1.5 - age) / 1.5);
                colour = [e.colour[0] + (e.peakColour[0] - e.colour[0]) * peak, e.colour[1] + (e.peakColour[1] - e.colour[1]) * peak, e.colour[2] + (e.peakColour[2] - e.colour[2]) * peak];
            }
            coreAbs = env;
            haloAbs = 0.18 * env;
            halo = e.core * 4;
            const span = e.decay + e.remnant;
            const u = clamp((age - flash) / Math.max(0.001, span), 0, 1);
            if (u > 0) {
                ringRadius = e.shell * Math.pow(u, 0.55);
                // The ring widens as it fades, which is what makes it read as
                // dissipating rather than simply going away.
                ringWidth = Math.max(2, e.core * (1 + 9 * u));
                ringAbs = e.shellGain * ease(u / 0.08) * (1 - u) * (1 - u);
                const delayed = (age - flash - e.echoDelay) / Math.max(0.001, span - e.echoDelay);
                if (delayed > 0 && delayed < 1) {
                    echoRadius = ringRadius * e.echoScale;
                    echoAbs = e.echoGain * ease(delayed / 0.15) * (1 - delayed);
                }
            }
        } else {
            // Pulsar: a raised cosine with guaranteed edges and a trough that
            // never drops below floorFraction of the peak. It modulates.
            const phase = modulo(age, e.period) / e.period;
            const duty = 0.5 - 0.5 * Math.cos(2 * Math.PI * phase);
            const soft = Math.min(1, e.edge * 4 / e.period);
            const shaped = duty * (1 - soft) + soft * 0.5;
            const env = e.gain * (e.floor + (1 - e.floor) * shaped) * ease(age / 8) * ease((e.duration - age) / 8);
            coreAbs = env;
            haloAbs = 0.10 * env;
            halo = e.core * 2.5;
        }
        // head.w is the slot's peak value; every component travels as a
        // fraction of it, so the shader's single multiply reproduces all four
        // absolute gains and the slot only switches off when all of them are 0.
        const peak = Math.max(coreAbs + haloAbs, ringAbs + echoAbs);
        if (peak <= 0.0004)
            return off;
        const reach = Math.max(Math.max(ringRadius + 3 * ringWidth, echoRadius + 6 * ringWidth), Math.max(3 * halo, 6 * core));
        return {
            head: [e.x, e.y, core, peak],
            colour: colour.concat(3),
            tail01: [echoRadius, echoAbs / peak, haloAbs / peak, coreAbs / peak],
            shape: [halo, ringAbs / peak, ringWidth, ringRadius],
            bounds: [e.x - reach, e.y - reach, e.x + reach, e.y + reach],
            exempt: exempt
        };
    }

    // One analytic curve supplies the head AND every tail point. Integration
    // round: this captured artistic path is separate from gravitational lensing.
    function eventPath(e: var, u: real, branch: int): var {
        const t = clamp(u, 0, 1);
        let x, y;
        if (e.capture) {
            const v = 1 - t;
            x = v * v * v * e.p0[0] + 3 * v * v * t * e.p1[0] + 3 * v * t * t * e.p2[0] + t * t * t * e.p3[0];
            y = v * v * v * e.p0[1] + 3 * v * v * t * e.p1[1] + 3 * v * t * t * e.p2[1] + t * t * t * e.p3[1];
        } else if (e.family === "spiral") {
            const a = e.angle + e.omega * t;
            const r = e.radius * (1 - 0.55 * t);
            x = e.centre[0] + r * Math.cos(a);
            y = e.centre[1] + r * Math.sin(a);
        } else {
            const v = 1 - t;
            x = v * v * e.p0[0] + 2 * v * t * e.p1[0] + t * t * e.p2[0];
            y = v * v * e.p0[1] + 2 * v * t * e.p1[1] + t * t * e.p2[1];
        }
        if (e.family === "fragmenting" && branch !== 0) {
            const split = ease((t - e.splitU) / (1 - e.splitU));
            const offset = branch * e.shortSide * 0.035 * split * split;
            x -= Math.sin(e.angle) * offset;
            y += Math.cos(e.angle) * offset;
        }
        return [x, y];
    }

    function eventState(e: var, branch: int, companion: bool, segments: int): var {
        if (!e || (companion && !e.pair))
            return eventOff();
        const age = _state.clock - e.start - (companion ? e.offset : 0);
        if (age < 0 || age > e.duration)
            return eventOff();
        const u = age / e.duration;
        const progress = e.kind === 0 ? (1 - Math.exp(-2.4 * u)) / (1 - Math.exp(-2.4)) : u;
        const envelope = ease(u / (e.kind === 0 ? 0.09 : 0.16)) * ease((1 - u) / (e.kind === 0 ? 0.38 : 0.20));
        let gain = e.gain * envelope * (companion ? 0.5 : 1);
        if (e.family === "pulsating")
            gain *= (1 + e.pulseAmplitude * Math.sin(age * 2 * Math.PI / e.pulsePeriod)) / (1 + e.pulseAmplitude);
        if (e.family === "skipping")
            gain *= 0.10 + 0.90 * Math.pow(Math.sin(Math.PI * e.lobes * u), 2);
        if (e.kind === 2 && e.glintGain > 1) {
            // A Gaussian in time: smooth at both edges by construction, so the
            // brightening has no slope a blink could hide in.
            const t = (age - e.glintAt) / Math.max(0.5, e.glintWidth);
            gain *= 1 + (e.glintGain - 1) * Math.exp(-2.8 * t * t);
        }
        if (e.family === "fragmenting") {
            const split = ease((u - e.splitU) * e.duration / e.splitSec);
            const heads = Math.max(1, e.headCap);
            gain *= branch === 0 ? 1 - (heads - 1) * split / heads : split / heads;
        }
        const count = e.tail > 0 ? (e.capture ? 4 : segments) : 0;
        const span = e.tail / Math.max(1, e.family === "spiral" ? e.radius * Math.abs(e.omega) : e.distance);
        const points = [];
        for (let i = 0; i < 5; ++i) {
            const p = eventPath(e, Math.max(0, progress - span * Math.min(i, count) / Math.max(1, count)), branch);
            if (companion) {
                p[0] += e.shortSide * 0.012;
                p[1] += e.shortSide * 0.003;
            }
            points.push(p);
        }
        let length = 0;
        for (let i = 0; i < count; ++i)
            length += Math.hypot(points[i + 1][0] - points[i][0], points[i + 1][1] - points[i][1]);
        if (e.capture) {
            const r = Math.hypot(points[0][0] - e.hole[0], points[0][1] - e.hole[1]);
            gain *= ease((r - e.hole[2]) / (0.18 * e.hole[2]));
        }
        const width = e.pointWidth;
        const extent = width * (e.kind === 1 ? 14 : 6);
        const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
        return {
            head: [points[0][0], points[0][1], width, gain],
            colour: e.colour.concat(e.kind === 1 ? 1 : e.kind >= 2 ? 2 : 0),
            tail01: points[0].concat(points[1]),
            tail23: points[2].concat(points[3]),
            tail4: points[4],
            shape: [length, e.kind === 1 ? 0.23 : 0.62, count, 0],
            bounds: [Math.min(...xs) - extent, Math.min(...ys) - extent, Math.max(...xs) + extent, Math.max(...ys) + extent]
        };
    }

    function publishEvents(): void {
        const s = _state;
        for (let kind = 0; kind < 10; ++kind) {
            const e = s.events[kind];
            const radial = kind >= 5;
            if (!eventEnabled(kind) && e && s.clock < e.start)
                s.events[kind] = null;
            else if (!e || s.clock > e.start + e.duration + (radial ? 0 : e.offset))
                s.events[kind] = radial ? scheduleRadial(kind) : schedule(kind);
        }
        const shower = s.events[3];
        const showerActive = shower && s.clock >= shower.start && s.clock <= shower.start + shower.duration;
        if (showerActive && s.mood[0] === 3)
            shader.mood = Qt.vector4d(0, 0, 0, 0);
        const slots = [];
        function append(e) {
            if (!e || s.clock < e.start || s.clock > e.start + e.duration + e.offset)
                return;
            const fragment = e.family === "fragmenting";
            const ceiling = Math.min(e.headCap, fragment ? 3 : 2);
            const branches = fragment ? [0, -1, 1].slice(0, ceiling) : [0];
            for (const branch of branches) {
                if (slots.length < ceiling)
                    slots.push(eventState(e, branch, false, fragment ? 2 : 3));
            }
            if (e.pair && slots.length < ceiling)
                slots.push(eventState(e, 0, true, 3));
        }
        if (showerActive) {
            for (const child of shower.children)
                append(child);
        } else
            append(s.events[0]);
        for (const kind of [1, 2, 4])
            append(s.events[kind]);
        for (let i = 0; i < 3; ++i) {
            const slot = slots[i] || eventOff();
            shader["event" + i + "Tail4"] = Qt.vector2d(slot.tail4[0], slot.tail4[1]);
            for (const name of ["head", "colour", "tail01", "tail23", "shape", "bounds"]) {
                const v = slot[name];
                shader["event" + i + name[0].toUpperCase() + name.slice(1)] = Qt.vector4d(v[0], v[1], v[2], v[3]);
            }
        }
        publishPhenomena();
    }

    // Slots 3-4. Long, faint, low-gain radial events only; they never spill
    // into the transient heads and the heads never spill into them.
    function publishPhenomena(): void {
        const s = _state;
        const cap = Math.round(clamp(Number((eventFamilies || {}).phenomenonCap) || 2, 1, 2));
        // Slot ownership is STICKY. An episode claims a slot only in its first
        // quarter-second, while its envelope is still at nothing, and keeps it
        // until it ends. A phenomenon that could take a freed slot halfway
        // through its life would appear at whatever gain it had reached, which
        // is the one-frame pop this whole pass exists to remove; instead that
        // episode simply never draws. Scheduling already keeps at most `cap`
        // overlapping, so it should not come up.
        const owner = s.phenomenonSlots;
        for (let i = 0; i < 2; ++i) {
            if (owner[i] === null)
                continue;
            const held = s.events[owner[i]];
            if (!held || _state.clock > held.start + held.duration || i >= cap)
                owner[i] = null;
        }
        for (let kind = 5; kind < 10; ++kind) {
            const e = s.events[kind];
            if (!e || owner.indexOf(kind) >= 0)
                continue;
            const age = s.clock - e.start;
            if (age < 0 || age > 0.25)
                continue;
            for (let i = 0; i < cap; ++i)
                if (owner[i] === null) {
                    owner[i] = kind;
                    break;
                }
        }
        const live = [];
        for (let i = 0; i < cap; ++i)
            live.push(owner[i] === null ? null : radialState(s.events[owner[i]]));
        // Combined peak-gain cap outside a supernova flash. The exemption is an
        // eased weight, not a test, so the cap takes hold without a step; the
        // scale itself is continuous in the sum for the same reason.
        let capped = 0;
        for (const state of live)
            if (state)
                capped += state.head[3] * (1 - state.exempt);
        const scale = capped > 0.55 ? 0.55 / capped : 1;
        for (let i = 0; i < 2; ++i) {
            const state = live[i];
            const head = state ? [state.head[0], state.head[1], state.head[2], state.head[3] * (state.exempt + (1 - state.exempt) * scale)] : [0, 0, 0, 0];
            const slot = state || {
                colour: [0, 0, 0, 3],
                tail01: [0, 0, 0, 0],
                shape: [0, 0, 0, 0],
                bounds: [0, 0, 0, 0]
            };
            shader["event" + (i + 3) + "Head"] = Qt.vector4d(head[0], head[1], head[2], head[3]);
            for (const name of ["colour", "tail01", "shape", "bounds"]) {
                const v = slot[name];
                shader["event" + (i + 3) + name[0].toUpperCase() + name.slice(1)] = Qt.vector4d(v[0], v[1], v[2], v[3]);
            }
        }
    }

    // Capture is a scheduling decision. These points and the rim are immutable
    // even if the hole or event rules change before the event finishes.
    function classifyCapture(e: var): void {
        e.capture = false;
        if (!_hole.enabled || (e.kind !== 0 && !(e.kind === 1 && e.family === "bent")))
            return;
        const c = [_hole.bhCentre.x, _hole.bhCentre.y], rh = _hole.bhGeometry.x;
        const vx = e.p2[0] - e.p0[0], vy = e.p2[1] - e.p0[1];
        const t = clamp(((c[0] - e.p0[0]) * vx + (c[1] - e.p0[1]) * vy) / Math.max(1, vx * vx + vy * vy), 0, 1);
        const distance = Math.hypot(e.p0[0] + vx * t - c[0], e.p0[1] + vy * t - c[1]);
        if (e.kind === 1) {
            e.p1 = [e.p1[0] + 0.35 * (c[0] - e.p1[0]), e.p1[1] + 0.35 * (c[1] - e.p1[1])];
        }
        if ((e.kind === 0 && distance >= 3 * rh) || random(e.index, screenSeed + 9173 + e.kind * 701) >= (e.kind === 0 ? 0.30 : 0.20))
            return;
        const r = Math.max(1, Math.hypot(e.p0[0] - c[0], e.p0[1] - c[1]));
        const dx = (e.p0[0] - c[0]) / r, dy = (e.p0[1] - c[1]) / r;
        e.capture = true;
        e.pair = false;
        e.offset = 0;
        e.hole = c.concat(rh);
        e.p3 = [c[0] + 0.70 * rh * dx, c[1] + 0.70 * rh * dy];
        e.p1 = [e.p0[0] + vx * 0.32, e.p0[1] + vy * 0.32];
        e.p2 = [c[0] + 1.35 * rh * dx - 0.28 * rh * dy, c[1] + 1.35 * rh * dy + 0.28 * rh * dx];
        e.distance = Math.hypot(e.p1[0] - e.p0[0], e.p1[1] - e.p0[1]) + Math.hypot(e.p2[0] - e.p1[0], e.p2[1] - e.p1[1]) + Math.hypot(e.p3[0] - e.p2[0], e.p3[1] - e.p2[1]);
    }

    // Bound the shader's float32 identity without assuming a driver sum tree.
    function identityHash(x: real, y: real, variant: int): var {
        const f = Math.fround, fract = x => f(x - Math.floor(x));
        const a = [x, y, x, y].map((v, i) => fract(f(f(v) * f([0.1031, 0.1030, 0.0973, 0.1099][i]))));
        const b = [a[3], a[2], a[0], a[1]];
        // A GLSL dot may use fused multiply-add or a different sum tree.
        // Its four positive products are bounded by +/-2 float32 ULPs of
        // the correctly rounded exact sum. Keep every such result, so entry
        // time follows the GPU's unchanged v3 identity on either driver.
        let exact = 0;
        for (let i = 0; i < 4; ++i)
            exact += a[i] * f(b[i] + f(33.33));
        const rounded = f(exact);
        const ulp = Math.pow(2, Math.floor(Math.log2(Math.max(rounded, 1e-30))) - 23);
        const dot = f(rounded + (variant - 2) * ulp);
        const p = a.map(x => f(x + dot));
        return [fract(f(f(p[0] + p[1]) * p[2])), fract(f(f(p[0] + p[2]) * p[1])), fract(f(f(p[1] + p[2]) * p[3])), fract(f(f(p[2] + p[3]) * p[0]))];
    }

    // Entry ledger is deliberately separate from the immutable descriptor atlas.
    // A decayer starts once its nucleus enters the screen. Its halo is held
    // dark before that entry, so slow/paused edge approaches cannot spend life
    // off-screen. The initial fade defines its first visible appearance,
    // in ACTIVE seconds, including at radialSpeed=0. It never re-arms. Palette,
    // kind and parameters still come from its original sealed birth cohort.
    // Near candidate variants are enumerated; dead IDs remain until their row
    // is consumed. Hash words plus day/seconds identify the exact GPU variant.
    // The ledger shares the descriptor upload transaction, not its sealed bytes.
    function publishEntries(): void {
        const s = _state, records = [];
        let dirty = s.entryDirty;
        if (s.entrySeed !== screenSeed) {
            s.entrySeed = screenSeed;
            s.entries = {};
            s.nearHashes = {};
            dirty = true;
        }
        if (motionMode !== "drift" && density > 0) {
            const f = Math.fround;
            const w = width * devicePixelRatio, h = height * devicePixelRatio, R = Math.min(w, h) / 2;
            const optics = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
            const cellSize = 110 * optics / Math.sqrt(Math.max(0.0001, clamp(density, 0, 3)));
            const sectors = Math.max(4, Math.round(2 * Math.PI * R / cellSize));
            const invAngle = sectors / (2 * Math.PI), invU = R * R / (cellSize * cellSize * invAngle);
            const geometry = [w, h, invAngle].join(":");
            if (geometry !== s.entryGeometry) {
                s.entryGeometry = geometry;
                s.nearHashes = {};
                dirty = true;
            }
            const cells = s.geo[2] * (6 / 1080) * invU, advanceRows = Math.floor(cells), block = Math.floor(advanceRows / 256);
            const grid = Qt.vector4d(invU, invAngle, modulo(cells, 1), modulo(advanceRows, 256));
            const seeds = Qt.vector4d(blockSalt(block, 2, 0), blockSalt(block, 2, 1), blockSalt(block + 1, 2, 0), blockSalt(block + 1, 2, 1));
            const phase = random(screenSeed, 8761) * Math.PI * 2;
            const wander = wanderOffset(s.clock, phase);
            const offset = [2 * R * wander[0], 2 * R * wander[1]];
            const zoom = f(Math.exp(clamp(zoomBreath, 0, 0.003) * (0.65 * wave(s.clock, 10, 0.4) + 0.35 * wave(s.clock, 14, 2.1))));
            const maxRadius = Math.hypot(w / 2 + 42 * optics + Math.abs(offset[0]), h / 2 + 42 * optics + Math.abs(offset[1])) / (R * zoom);
            const maxRow = Math.ceil(0.5 * maxRadius * maxRadius * grid.x + 1);
            for (const key of Object.keys(s.entries))
                if (s.entries[key].row < advanceRows) {
                    delete s.entries[key];
                    dirty = true;
                }
            for (const key of Object.keys(s.nearHashes))
                if (Number(key.split(":")[0]) < advanceRows)
                    delete s.nearHashes[key];
            // The largest supported buffer uses <32 near rows and <40 sectors;
            // a 64-row/64-sector window has no simultaneous live-ID collisions.
            s.entryOverflow = Math.max(s.entryOverflow, maxRow - 64, sectors - 64);
            for (let row = 0; row < maxRow; ++row) {
                for (let sector = 0; sector < sectors; ++sector) {
                    const rowId = row + grid.w;
                    const hx = f(f(sector + (rowId < 256 ? seeds.x : seeds.z)) + f(2 * f(173.17)));
                    const hy = f(f(modulo(rowId, 256) + (rowId < 256 ? seeds.y : seeds.w)) + f(2 * f(319.43)));
                    const cellKey = (advanceRows + row) + ":" + sector;
                    if (!s.nearHashes[cellKey]) {
                        // Drivers may also reassociate the two input additions.
                        const hx2 = f(sector + f((rowId < 256 ? seeds.x : seeds.z) + f(2 * f(173.17))));
                        const hy2 = f(modulo(rowId, 256) + f((rowId < 256 ? seeds.y : seeds.w) + f(2 * f(319.43))));
                        const variants = [], seen = {};
                        for (const input of [[hx, hy], [hx2, hy2], [hx, hy2], [hx2, hy]]) {
                            for (let j = 0; j < 5; ++j) {
                                const v = identityHash(input[0], input[1], j), key = v[0] + ":" + v[1];
                                if (!seen[key]) {
                                    seen[key] = true;
                                    const jx = f(f(0.18) + f(f(0.64) * v[0]));
                                    const jy = f(f(0.18) + f(f(0.64) * v[1]));
                                    const angle = 2.83 + (sector + jx) / grid.y;
                                    variants.push(v.concat([jx, jy, Math.cos(angle), Math.sin(angle)]));
                                }
                            }
                        }
                        s.nearHashes[cellKey] = variants;
                        dirty = true;
                    }
                    for (let variant = 0; variant < s.nearHashes[cellKey].length; ++variant) {
                        const v = s.nearHashes[cellKey][variant];
                        const jitter = [v[4], v[5]];
                        const u = (row + jitter[1] - grid.z) / grid.x;
                        if (u <= 0)
                            continue;
                        const r = Math.sqrt(2 * u), dx = v[6], dy = v[7];
                        const x = w / 2 + offset[0] + R * zoom * r * dx;
                        const y = h / 2 + offset[1] + R * zoom * r * dy;
                        const distance = Math.max(-x, x - w, -y, y - h);
                        const key = cellKey + ":" + variant;
                        let entry = s.entries[key];
                        if (!entry) {
                            entry = {
                                row: advanceRows + row,
                                sector: sector,
                                variant: variant,
                                hash: [v[0], v[1]],
                                stamp: -1,
                                distance: distance,
                                clock: s.clock
                            };
                            s.entries[key] = entry;
                            dirty = true;
                        }
                        if (entry.stamp < 0 && distance <= 0) {
                            const t = entry.distance > 0 ? entry.distance / Math.max(1e-9, entry.distance - distance) : 1;
                            entry.stamp = entry.clock + (s.clock - entry.clock) * t;
                            dirty = true;
                        }
                        entry.distance = distance;
                        entry.clock = s.clock;
                    }
                }
            }
        }
        if (dirty) {
            for (const key of Object.keys(s.entries)) {
                const e = s.entries[key];
                records.push([e.sector, modulo(e.row, 64), e.variant, e.hash[0], e.hash[1], e.stamp]);
            }
            records.sort((a, b) => a[1] - b[1] || a[0] - b[0] || a[2] - b[2]);
            s.entrySignature = JSON.stringify(records);
            s.entryDirty = false;
            s.entryPixels.fill(0);
            let previous = -1, count = 0, header = 0;
            for (let index = 0; index < records.length; ++index) {
                const r = records[index], cell = r[1] * 64 + r[0];
                if (cell !== previous) {
                    header = cell * 3;
                    s.entryPixels[header] = index % 256;
                    s.entryPixels[header + 1] = Math.floor(index / 256);
                    previous = cell;
                    count = 0;
                }
                s.entryPixels[header + 2] = ++count;
                const values = [Math.floor(r[3] * 16777216), Math.floor(r[4] * 16777216), r[5] < 0 ? 0 : Math.floor(r[5] / 86400) + 32768, r[5] < 0 ? 0 : Math.floor(modulo(r[5], 86400) * 128)];
                for (let j = 0; j < 4; ++j) {
                    const i = (4096 + index * 4 + j) * 3, n = values[j];
                    s.entryPixels[i] = n % 256;
                    s.entryPixels[i + 1] = Math.floor(n / 256) % 256;
                    s.entryPixels[i + 2] = Math.floor(n / 65536) % 256;
                }
            }
            s.entryOverflow = Math.max(s.entryOverflow, records.length - 19456);
            ++s.atlasRevision;
        }
    }

    function publish(): void {
        const s = _state;
        if (!s || width <= 0 || height <= 0)
            return;
        if (_hole.enabled && s.paddingEpoch < 0)
            s.paddingEpoch = s.flow;
        if (!particlesEnabled)
            publishEntries();
        shader.particlesEnabled = particlesEnabled ? 1 : 0;
        // Data URLs can still complete asynchronously despite asynchronous:false.
        // Decode into the inactive image. Until it is Ready retain BOTH the old
        // texture and its uniforms; an unsealed row can never reach a live frame.
        if (s.publishedRevision !== s.atlasRevision) {
            if (s.pendingRevision !== s.atlasRevision) {
                s.pendingRevision = s.atlasRevision;
                const image = shader.descriptorAtlas === descriptorImage ? descriptorBack : descriptorImage;
                s.pendingImage = image;
                image.source = atlasUrl();
                if (image.status === Image.Ready)
                    completeAtlas(image);
            }
            return;
        }
        const w = width * devicePixelRatio;
        const h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const radius = shortSide / 2;
        const displayScale = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
        const scale = displayScale / Math.sqrt(Math.max(0.0001, clamp(density, 0, 3)));
        const tauPhase = random(screenSeed, 8761) * Math.PI * 2;
        shader.resolution = Qt.vector2d(w, h);
        // 0 drift, 1 the inward radial stream, 1..2 the same stream reversed by
        // the camera: the fraction above 1 IS the camera blend, so the shader
        // gets the regime crossfade without a new uniform and without touching
        // the UBO layout. Every existing test is `radialMode > 0.5`.
        shader.radialMode = motionMode === "drift" ? 0 : 1 + _cameraOutward;
        shader.phaseTime = modulo(s.clock, 4096);
        shader.activeStamp = Qt.vector2d(Math.floor(s.clock / 86400), modulo(s.clock, 86400));
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
        const wander = wanderOffset(s.clock, tauPhase);
        shader.centreOffset = Qt.vector2d(shortSide * wander[0], shortSide * wander[1]);
        // Bounded, 4096-safe parallax of the far field. The 1/r inflow leaves the
        // corners nearly still; this is the floor that keeps every region moving.
        const parallax = _particles && particlesEnabled ? _particles.config.dust.parallaxPx : 0;
        shader.dustParallax = Qt.vector2d(parallax * wave(s.clock, 16, tauPhase), parallax * wave(s.clock, 12, tauPhase + 2.3));
        const clustered = _particles && particlesEnabled ? _particles.config.dust : null;
        shader.dustCluster = Qt.vector4d(clustered ? clustered.clusterCells : 16, clustered ? clustered.voidCells : 44, clustered ? clustered.clusterGain : 0, clustered ? clustered.cellScale : 1);
        shader.particleMu = _particles && particlesEnabled ? _particles.mu : 0;
        const breath = clamp(zoomBreath, 0, 0.003) * (0.65 * wave(s.clock, 10, 0.4) + 0.35 * wave(s.clock, 14, 2.1));
        shader.flowZoom = Qt.vector3d(Math.exp(0.10 * breath), Math.exp(0.42 * breath), Math.exp(breath));
        const padding = [], capturePadding = [];
        // With particles on, the far layer is the only procedural one left and its
        // depth-0.10 flow reads as frozen: 0.6 px/s at mid-screen on a 4K output.
        // The cell grid advances at a constant rate in u = r^2/2, so the radial
        // speed is already proportional to 1/r; the multiplier just makes it
        // visible, and sqrt(mass) ties it to the same mass the particles feel.
        const dust = _particles ? _particles.config.dust : null;
        const boost = farBoost();
        const farCellScale = particlesEnabled && dust ? dust.cellScale : 1;
        for (let layer = 0; layer < 3; ++layer) {
            const depth = [0.10, 0.42, 1][layer];
            const cellSize = [12, 30, 110][layer] * scale * (layer === 0 ? farCellScale : 1);
            const sectors = Math.max(4, Math.round(2 * Math.PI * radius / cellSize));
            const invAngle = sectors / (2 * Math.PI);
            const invU = radius * radius / (cellSize * cellSize * invAngle);
            const advanceCells = s.geo[layer] * (6 / 1080) * depth * invU * (layer === 0 ? boost : 1);
            const row = Math.floor(advanceCells);
            const block = Math.floor(row / 256);
            shader["flowGrid" + layer] = Qt.vector4d(invU, invAngle, modulo(advanceCells, 1), modulo(row, 256));
            shader["flowSeeds" + layer] = Qt.vector4d(blockSalt(block, layer, 0), blockSalt(block, layer, 1), blockSalt(block + 1, layer, 0), blockSalt(block + 1, layer, 1));
            // Retain the v3 descriptor plane, including its 32-flow-second
            // near guard. Entry-based decayers no longer use that guard as age.
            const opticalPadding = [3.5, 6, 42 * displayScale][layer] + 2 + shortSide * 0.012 * depth + Math.hypot(w, h) * 0.003 * depth;
            const extra = layer === 2 ? radius * (Math.sqrt(Math.pow(1 + opticalPadding / radius, 2) + 2 * (6 / 1080) * 32) - (1 + opticalPadding / radius)) : 0;
            padding.push(opticalPadding + extra);
            // Full shared-centre excursion plus the largest allowed material
            // displacement at a screen edge (Rh <= .4 R). Only post-epoch
            // births adopt this plane; existing IDs never change their cohort.
            const materialGuard = layer > 0 ? radius * (1 - Math.sqrt(1 - 0.4 * 0.4)) : 0;
            capturePadding.push(Math.max(opticalPadding + extra, opticalPadding + shortSide * 0.012 * (1 - depth) + materialGuard));
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
        shader.legacyPadding = Qt.vector3d(padding[0], padding[1], padding[2]);
        shader.birthPadding = Qt.vector3d(capturePadding[0], capturePadding[1], capturePadding[2]);
        shader.paddingAge = s.paddingEpoch < 0 ? -1 : Math.min(8000, s.flow - s.paddingEpoch);
        shader.captureHistory = s.captureHistory ? 1 : 0;
        // Cohort dither can select a policy up to two seals back. After 660
        // flow seconds every older 480..600 s material ID is permanently dead.
        shader.legacyMaterialAlive = s.flow <= s.lastLegacyFlow + 660 ? 1 : 0;
        s.mood = moodState();
        shader.mood = Qt.vector4d(s.mood[0], s.mood[1], 0, 0);
        // Microlensing needs no scheduler and no slot: the shader already has
        // the lens Jacobian in hand wherever it filters a far star, and this is
        // only the flux ceiling. 1 disables the term entirely.
        // The disruption flash: eased in over the first quarter of its twenty
        // seconds and out over the last half, on top of whatever the hole's own
        // slew is doing, so it never steps.
        const flash = phenomenon("tde").diskFlash;
        const depth = clamp(flash === undefined ? 0.15 : flash, 0, 0.5);
        if (_particles && s.tdeFlashUntil !== undefined && _particles.clock < s.tdeFlashUntil) {
            const span = s.tdeFlashUntil - s.tdeFlashFrom;
            const at = _particles.clock - s.tdeFlashFrom;
            _tdeFlash = depth * ease(at / (span * 0.25)) * ease((s.tdeFlashUntil - _particles.clock) / (span * 0.5));
        } else if (_tdeFlash !== 0) {
            _tdeFlash = 0;
        }
        const lensing = phenomenon("microlensing");
        shader.lensFlux = lensing.enabled === false ? 1 : clamp(lensing.gainCap === undefined ? 2.5 : lensing.gainCap, 1, 3);
        const moodTwinkle = [0.18, 0.16, 0.24, 0.22, 0.20, 0.19][s.mood[0]];
        shader.twinkle *= 1 + (moodTwinkle / 0.22 - 1) * s.mood[1];
        for (const name of ["bhCentre", "bhGeometry", "bhDisk", "bhLook", "bhHalo", "bhPhase", "bhCaps"])
            shader[name] = _hole[name];
        for (const name of ["bhDetail", "bhStreaks", "bhKnots", "bhEmbers", "bhDoppler", "bhHue", "bhGlow", "bhPhoton", "bhDetailPhase", "bhArcs", "bhRim", "bhDepth"])
            if (_hole[name] !== undefined)
                shader[name] = _hole[name];
        publishEvents();
        publishParticles();
        ++s.publications;
    }

    function completeAtlas(image: var): void {
        const s = _state;
        if (!s || image !== s.pendingImage || image.status !== Image.Ready || s.pendingRevision !== s.atlasRevision || (s.runtimeAtlas && !running))
            return;
        shader.descriptorAtlas = image;
        s.publishedRevision = s.pendingRevision;
        s.pendingImage = null;
        publish();
    }

    // Particle positions, appearance, bins and timestamp commit as one revision.
    // The inactive Canvas owns its reusable ImageData; a late paint retains the
    // previous texture AND metadata. No simulation arrays are read by onPaint.
    property var _particles: null
    property var _particleItems: null
    property var _particleBins: null
    property var _particlePending: null
    property string _particleConfiguration: ""
    property real _particleDpr: 1
    property real _particleLogicalWidth: 0
    property real _particleLogicalHeight: 0
    property real _particlePublishedClock: -1
    property string _particlePublishedConfiguration: ""
    property var _particleBirthInput: null
    property var _particleBirth: null
    property var _particlePaletteRef: null
    property var _particleSettingsRef: undefined
    property var _particleMassRef: undefined
    property var _particleSettings: ({})
    property string _particleSettingsText: ""
    property int _particleAtlasHeight: 0
    property int _particleRevision: 0
    property int _particlePublications: 0
    property int _particleMissed: 0
    property int _particleSentinelErrors: 0

    function prepareParticles(): bool {
        if (!particlesEnabled || width <= 0 || height <= 0)
            return false;
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const rh = _hole.bhGeometry.x;
        // How big the hole LOOKS, from the hole's own published uniforms: the
        // disk's radii and its outer arcs. Physics turns this into the swallow
        // radius, the capture band and the tidal reach, so no particle is ever
        // drawn on top of the object it is falling into. Read-only: the look of
        // the disk is BlackHole.qml's to change, and this follows it.
        const geometry = {
            innerRs: _hole.bhDisk.x, outerRs: _hole.bhDisk.y,
            arcGain: _hole.bhArcs.x, arcRadiusRh: _hole.bhArcs.y,
            arcSpacingRh: _hole.bhArcs.z, arcCount: _hole.bhArcs.w
        };
        // Serializing the settings twice a frame was pure garbage: both property
        // objects are replaced wholesale on an edit, so identity is the test.
        // blackHole.mass is the canonical key; particles.mass overrides it, so
        // one number scales the particle potential and the far-dust flow alike.
        const mass = blackHole && blackHole.mass !== undefined ? blackHole.mass : undefined;
        if (particles !== _particleSettingsRef || mass !== _particleMassRef) {
            _particleSettingsRef = particles;
            _particleMassRef = mass;
            _particleSettings = Object.assign({}, particles);
            if (mass !== undefined && _particleSettings.mass === undefined)
                _particleSettings.mass = mass;
            _particleSettingsText = JSON.stringify(_particleSettings);
        }
        const signature = _particleSettingsText + ":" + w + ":" + h + ":" + rh
            + ":" + geometry.innerRs + ":" + geometry.outerRs
            + ":" + geometry.arcGain + ":" + geometry.arcRadiusRh
            + ":" + geometry.arcSpacingRh + ":" + geometry.arcCount;
        if (!_particles) {
            _particles = ParticlePhysics.create(w, h, rh, screenSeed ^ varietySeed, _particleSettings, undefined, geometry);
            _particleConfiguration = signature;
        } else if (signature !== _particleConfiguration) {
            // DPR converts units only; ordinary resize and reactive edits leave
            // existing physical positions and velocities untouched.
            if (devicePixelRatio !== _particleDpr && width === _particleLogicalWidth && height === _particleLogicalHeight) {
                const factor = devicePixelRatio / _particleDpr;
                ParticlePhysics.rescale(_particles, factor);
                if (_particles.exposure)
                    for (let i = 0; i < _particles.capacity; ++i) {
                        if (_particles.archetype[i] === 4 || _particles.archetype[i] === 5)
                            _particles.p1[i] *= factor;
                        _particles.maxStreak[i] *= factor;
                    }
            }
            ParticlePhysics.configure(_particles, w, h, rh, _particleSettings, geometry);
            _particleConfiguration = signature;
            // A new bin grid can need a different number of texels; recompute
            // the shared allocation instead of keeping the old one forever.
            _particleAtlasHeight = 0;
        }
        _particleDpr = devicePixelRatio;
        _particleLogicalWidth = width;
        _particleLogicalHeight = height;
        return true;
    }

    function advanceParticles(dt: real): void {
        if (!prepareParticles())
            return;
        const s = _state, phase = random(screenSeed, 8761) * Math.PI * 2;
        const m = Math.min(_particles.width, _particles.height);
        const wander = wanderOffset(s.clock, phase);
        const cx = _particles.width / 2 + m * wander[0];
        const cy = _particles.height / 2 + m * wander[1];
        // The birth input and its callback are retained: rebuilding the palette
        // snapshot and the closure every frame allocated for roughly one birth.
        // Only the resolved colours are re-snapshotted, and only when they move.
        if (!_particleBirthInput) {
            _particleBirthInput = {
                colors: [],
                weights: null,
                mix: 0,
                archetypes: null,
                params: null,
                legacy: null,
                seed: 0
            };
            _particleBirth = (pool, i) => ParticleAppearance.birth(pool, i, _particleBirthInput);
        }
        const input = _particleBirthInput;
        // A palette edit replaces the property's array; QML never mutates it in
        // place, so identity is enough and costs nothing per frame.
        if (paletteColors !== _particlePaletteRef) {
            input.colors = paletteSnapshot();
            _particlePaletteRef = paletteColors;
        }
        input.weights = s.palette;
        input.mix = s.mix;
        input.archetypes = s.archetypes;
        input.params = archetypeParams;
        input.legacy = s.birth;
        input.seed = screenSeed ^ varietySeed;
        // With the hole disabled the envelope fades to 0 over 30 s; the swallow
        // radius and the central render fade follow it, so particles keep moving
        // through the centre instead of vanishing into an invisible point.
        _particles.absorb = _hole.bhHalo.w;
        // The camera regime. `cameraRate` is depth units per active second: one
        // traversal of the whole depth range takes 60 s at speed 6, so a star
        // at the far plane crawls and the same star at the near plane streaks
        // past at `depth` times that. Zero speed freezes the camera with the
        // rest of the motion. The roll is a bounded sinusoid in RATE, so its
        // integral is a +-4 degree sway that can never wind up.
        const depthRange = clamp(cameraDepth, 2, 64);
        const pace = clamp(cameraSpeed, 0, 30);
        _particles.cameraBlend = _cameraBlend;
        _particles.cameraDir = cameraDirection === "in" ? -1 : 1;
        _particles.cameraDepth = depthRange;
        _particles.cameraRate = pace > 0 ? (depthRange - 1) * pace / 360 : 0;
        _particles.cameraRoll = clamp(cameraRoll, 0, 2) * (Math.PI / 180) * wave(s.clock, 23, phase + 0.9);
        _particles.cameraSizeGain = clamp(cameraSizeGain, 0, 1);
        scheduleTde();
        ParticlePhysics.advance(_particles, dt, radialSpeed, s.live[2], cx, cy, blackHole && blackHole.disk && blackHole.disk.rotationSign < 0 ? -1 : 1, _particleBirth);
    }

    // Tidal disruption: particles only, so it costs no slot, no uniform and no
    // shader change. The renderer owns the schedule and the physics owns the
    // stretch and the split. A firing that finds no suitable victim is retried
    // shortly rather than skipped, because a victim has to be inbound on a
    // deep orbit and that is a matter of seconds either way.
    function scheduleTde(): void {
        const s = _state;
        const cfg = phenomenon("tde");
        if (cfg.enabled === false || !_hole.enabled) {
            s.tdeNext = -1;
            return;
        }
        const pool = _particles;
        if (s.tdeNext === undefined || s.tdeNext < 0) {
            s.tdeNext = pool.clock + parameterRange(cfg, "everyMinutes", [40, 90], 1, 1440)[0] * 60;
            s.tdeIndex = 0;
        }
        if (pool.clock < s.tdeNext)
            return;
        const index = s.tdeIndex++;
        const streak = parameterRange(cfg, "streakPx", [60, 140], 0, 160);
        const stretch = parameterRange(cfg, "stretchSec", [6, 12], 1, 120);
        const pieces = parameterRange(cfg, "fragments", [4, 8], 1, 16);
        const fired = ParticlePhysics.doom(pool, {
            streakPx: streak[0] + (streak[1] - streak[0]) * random(index, screenSeed + 7717),
            stretchSec: stretch[0] + (stretch[1] - stretch[0]) * random(index, screenSeed + 7719),
            fragments: Math.round(pieces[0] + (pieces[1] - pieces[0]) * random(index, screenSeed + 7721))
        });
        if (!fired) {
            s.tdeNext = pool.clock + 5;
            return;
        }
        s.tdeFlashFrom = pool.clock;
        s.tdeFlashUntil = pool.clock + 20;
        const range = parameterRange(cfg, "everyMinutes", [40, 90], 1, 1440);
        s.tdeNext = pool.clock + (range[0] + (range[1] - range[0]) * random(index, screenSeed + 7723)) * 60;
    }

    function publishParticles(): void {
        if (!prepareParticles())
            return;
        if (_particlePending) {
            ++_particleMissed;
            return;
        }
        const pool = _particles;
        if (shader.particleReady > 0 && _particlePublishedClock === pool.clock && _particlePublishedConfiguration === _particleConfiguration && radialSpeed === 0)
            return;
        // Optional lower publication rate: the atlas is rebuilt less often while
        // integration keeps its own cadence. The achievable rates are 30/n, so a
        // request of 20 publishes every second frame (15 Hz). The shader
        // interpolates nothing, so particles visibly step below 30. Default 30.
        const hz = pool.config.publishHz;
        if (hz < 30 && shader.particleReady > 0 && _particlePublishedConfiguration === _particleConfiguration && pool.clock - _particlePublishedClock + 1e-9 < 1 / hz)
            return;
        _particleItems = ParticleAppearance.render(_particleItems, pool, {
            twinkle: shader.twinkle
        });
        _particleBins = ParticleBinning.build(_particleBins, _particleItems, pool.width, pool.height);
        const canvas = shader.particleAtlas === particleFront ? particleBack : particleFront;
        // One height for BOTH buffers, sized for every population this
        // configuration can reach, so the sampled texture is allocated once and
        // never resized. One resize of it cost 13 ms -> 6700 ms per frame of
        // scene-graph submission on llvmpipe and did not recover.
        if (!_particleAtlasHeight) {
            const ceiling = ParticleAppearance.bounds(pool);
            _particleAtlasHeight = ParticlePacking.capacity(_particleBins, ceiling.maxItems, ceiling.maxSupport, ceiling.maxFlares, ceiling.flareSupport, ceiling.maxBends, ceiling.bendSupport, ceiling.maxTde, ceiling.tdeSupport);
        }
        const layout = ParticlePacking.layout(canvas.packet, _particleBins, _particleItems.count, _particleAtlasHeight);
        _particleAtlasHeight = layout.height;
        canvas.width = layout.width;
        canvas.height = layout.height;
        canvas.snapshot = {
            items: _particleItems,
            bins: _particleBins,
            domain: [-pool.padding - 40, -pool.padding - 40, pool.width + 2 * pool.padding + 80, pool.height + 2 * pool.padding + 80],
            clock: pool.clock,
            configuration: _particleConfiguration,
            minHeight: _particleAtlasHeight,
            revision: ++_particleRevision
        };
        canvas.paintedRevision = 0;
        _particlePending = canvas;
        canvas.requestPaint();
    }

    function completeParticles(canvas: var): void {
        if (canvas !== _particlePending || !canvas.packet || canvas.paintedRevision !== canvas.packet.revision || (_state.runtimeAtlas && !running))
            return;
        if (!ParticlePacking.verify(canvas.packet)) {
            ++_particleSentinelErrors;
            _particlePending = null;
            return;
        }
        const p = canvas.packet;
        shader.particleAtlas = canvas;
        shader.particleAtlasInfo = Qt.vector4d(p.width, p.height, p.headersBase, p.listBase);
        shader.particleDomain = Qt.vector4d(p.domain[0], p.domain[1], p.domain[2], p.domain[3]);
        shader.particleData = Qt.vector4d(p.dataBase, p.count, p.clock, p.revision);
        shader.particleGrid = Qt.vector2d(canvas.snapshot.bins.nx, canvas.snapshot.bins.ny);
        shader.particleReady = 1;
        _particlePublishedClock = p.clock;
        _particlePublishedConfiguration = canvas.snapshot.configuration;
        _particlePending = null;
        ++_particlePublications;
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
        if (running && _state && _state.pendingImage)
            completeAtlas(_state.pendingImage);
        if (running && _particlePending && _particlePending.paintedRevision)
            completeParticles(_particlePending);
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
        supportsAtlasTextures: false

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
        property vector4d event0Head: Qt.vector4d(0, 0, 0, 0)
        property vector4d event0Colour: Qt.vector4d(0, 0, 0, 0)
        property vector4d event0Tail01: Qt.vector4d(0, 0, 0, 0)
        property vector2d event0Tail4: Qt.vector2d(0, 0)
        property vector4d event0Tail23: Qt.vector4d(0, 0, 0, 0)
        property vector4d event0Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d event0Bounds: Qt.vector4d(0, 0, 0, 0)
        property vector4d event1Head: Qt.vector4d(0, 0, 0, 0)
        property vector4d event1Colour: Qt.vector4d(0, 0, 0, 0)
        property vector4d event1Tail01: Qt.vector4d(0, 0, 0, 0)
        property vector2d event1Tail4: Qt.vector2d(0, 0)
        property vector4d event1Tail23: Qt.vector4d(0, 0, 0, 0)
        property vector4d event1Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d event1Bounds: Qt.vector4d(0, 0, 0, 0)
        property vector4d event2Head: Qt.vector4d(0, 0, 0, 0)
        property vector4d event2Colour: Qt.vector4d(0, 0, 0, 0)
        property vector4d event2Tail01: Qt.vector4d(0, 0, 0, 0)
        property vector2d event2Tail4: Qt.vector2d(0, 0)
        property vector4d event2Tail23: Qt.vector4d(0, 0, 0, 0)
        property vector4d event2Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d event2Bounds: Qt.vector4d(0, 0, 0, 0)
        // Phenomenon slots: style 3 only, so five vectors instead of seven.
        property vector4d event3Head: Qt.vector4d(0, 0, 0, 0)
        property vector4d event3Colour: Qt.vector4d(0, 0, 0, 3)
        property vector4d event3Tail01: Qt.vector4d(0, 0, 0, 0)
        property vector4d event3Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d event3Bounds: Qt.vector4d(0, 0, 0, 0)
        property vector4d event4Head: Qt.vector4d(0, 0, 0, 0)
        property vector4d event4Colour: Qt.vector4d(0, 0, 0, 3)
        property vector4d event4Tail01: Qt.vector4d(0, 0, 0, 0)
        property vector4d event4Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d event4Bounds: Qt.vector4d(0, 0, 0, 0)
        property vector2d activeStamp: Qt.vector2d(0, 0)
        property var bhTransfer: root._hole.bhTransfer
        property var bhNoise: root._hole["bhNoise"] || root._hole.bhTransfer
        property vector4d bhDetail: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhStreaks: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhKnots: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhEmbers: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhDoppler: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhHue: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhGlow: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhPhoton: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhDetailPhase: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhArcs: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhRim: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhDepth: Qt.vector4d(0, 0, 0, 0)
        property real captureHistory: 0
        property real legacyMaterialAlive: 1
        property vector2d bhCentre: Qt.vector2d(0, 0)
        property vector4d bhGeometry: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhDisk: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhLook: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhHalo: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhPhase: Qt.vector4d(0, 0, 0, 0)
        property vector4d bhCaps: Qt.vector4d(0, 0, 0, 0)
        property var particleAtlas: particleFront
        property vector4d particleAtlasInfo: Qt.vector4d(256, 16, 4, 4)
        property vector4d particleDomain: Qt.vector4d(0, 0, 1, 1)
        property vector4d particleData: Qt.vector4d(0, 0, 0, 0)
        property vector2d particleGrid: Qt.vector2d(1, 1)
        property real particlesEnabled: 1
        property real particleReady: 0
        property vector4d dustCluster: Qt.vector4d(6, 19, 0, 0)
        property vector2d dustParallax: Qt.vector2d(0, 0)
        property real particleMu: 0
        property var descriptorAtlas: descriptorImage
        property real radialMode: 1
        property vector2d centreOffset: Qt.vector2d(0, 0)
        property vector3d flowZoom: Qt.vector3d(1, 1, 1)
        property vector3d birthPadding: Qt.vector3d(0, 0, 0)
        property vector3d legacyPadding: Qt.vector3d(0, 0, 0)
        property real paddingAge: -1
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
        // Microlensing flux ceiling; 1 leaves the far field exactly as v5 drew it.
        property real lensFlux: 1

        fragmentShader: "shaders/starfield.frag.qsb"
    }

    Image {
        id: descriptorImage
        objectName: "starfieldDescriptorAtlas"
        visible: false
        width: 64
        height: 1536
        sourceSize: Qt.size(64, 1536)
        smooth: false
        mipmap: false
        cache: false
        asynchronous: false
        onStatusChanged: root.completeAtlas(descriptorImage)
    }

    Image {
        id: descriptorBack
        objectName: "starfieldDescriptorAtlasBack"
        visible: false
        width: 64
        height: 1536
        sourceSize: Qt.size(64, 1536)
        smooth: false
        mipmap: false
        cache: false
        asynchronous: false
        onStatusChanged: root.completeAtlas(descriptorBack)
    }

    component ParticleCanvas: Canvas {
        id: particleCanvas
        width: 256
        height: 16
        // Keep the texture provider alive outside the viewport; opacity 0
        // can elide its scene-graph node. No extra ShaderEffectSource pass.
        x: -width - 1
        smooth: false
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        property var pixels: null
        property var packet: null
        property var snapshot: null
        property int paintedRevision: 0
        onPaint: {
            if (!snapshot)
                return;
            const ctx = getContext("2d");
            packet = ParticlePacking.pack(packet, snapshot.bins, snapshot.items, snapshot, (w, h) => {
                pixels = ctx.createImageData(w, h);
                return pixels.data;
            });
            // Qt 6 requires the explicit dirty rectangle for this data upload;
            // it also keeps the upload proportional to the texels actually used
            // rather than to the once-allocated texture.
            ctx.putImageData(pixels, 0, 0, 0, 0, width, Math.min(height, Math.ceil(packet.texelsUsed / width)));
            paintedRevision = packet.revision;
        }
        onPainted: root.completeParticles(this)
    }

    ParticleCanvas {
        id: particleFront
        objectName: "starfieldParticleFront"
    }

    ParticleCanvas {
        id: particleBack
        objectName: "starfieldParticleBack"
    }

    // A running FrameAnimation keeps Qt's animation driver alive, and the render
    // loop then repaints every vsync whether or not anything changed: three
    // outputs at 144 Hz is 4.8x the work this renderer actually publishes. A
    // Timer drives the same 30 Hz tick without holding the driver open, so the
    // scene graph renders once per publication instead of once per refresh.
    Timer {
        id: driver
        interval: Math.round(1000 / root.clamp(root.fps, 1, 60))
        repeat: true
        running: root.running && root.visible && root.width > 0 && root.height > 0
        property real stamp: 0
        onRunningChanged: {
            root._pending = 0;
            root._firstFrame = true;
            stamp = Date.now() / 1000;
        }
        onTriggered: {
            const now = Date.now() / 1000;
            const dt = now - stamp;
            stamp = now;
            root.frame(dt);
        }
    }
}
