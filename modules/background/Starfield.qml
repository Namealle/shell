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
    property vector2d cometInterval: Qt.vector2d(300, 900)
    property bool satellitesEnabled: true
    property vector2d satellitesInterval: Qt.vector2d(150, 330)
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

    // ---- Per-frame probe (diagnostics, off by default) ---------------------
    // `starfield-shell perf on|dump|off`. Every probe sits behind one test of
    // _perf, so an unprobed frame pays a handful of property reads and makes no
    // clock call at all. The clock is INJECTED (an ElapsedTimer, nanoseconds)
    // rather than declared here, because this file is also loaded by the
    // headless harnesses under plain `/usr/lib/qt6/bin/qml`, which has no
    // Quickshell types; with no clock and no `perf on` nothing here runs.
    property var perfClock: null
    property var _perf: null

    function perfStart(): void {
        _perf = {
            frames: 0,
            paints: 0,
            atlases: 0,
            since: perfClock ? perfClock.elapsedNs() : 0,
            worst: 0,
            frame: 0,
            advance: 0,
            physics: 0,
            publish: 0,
            events: 0,
            parts: 0,
            render: 0,
            bin: 0,
            layout: 0,
            paint: 0,
            pack: 0,
            upload: 0,
            atlas: 0,
            // Handed to Binning.build and Packing.pack so the two halves of
            // their cost -- the sweep over the whole bin GRID and the work per
            // PARTICLE -- can be told apart. Absent without a clock.
            sub: perfClock ? {
                clock: perfClock,
                binClear: 0,
                binWalk: 0,
                binGrid: 0,
                binInsert: 0,
                packClear: 0,
                packGrid: 0,
                packInst: 0
            } : null
        };
    }

    function perfStop(): void {
        _perf = null;
    }

    // One window's rolling averages, then the window restarts: consecutive
    // dumps are consecutive intervals, which is what a leak shows up in.
    function perfDump(): var {
        const p = _perf;
        if (!p)
            return null;
        const span = (perfClock ? perfClock.elapsedNs() : 0) - p.since;
        const n = Math.max(1, p.frames);
        const ms = x => Math.round(x / 1000) / 1000;
        const pool = _particles;
        const out = {
            w: Math.round(width),
            h: Math.round(height),
            dpr: devicePixelRatio,
            sec: Math.round(span / 1e6) / 1000,
            frames: p.frames,
            fps: Math.round(1e11 * p.frames / Math.max(1, span)) / 100,
            // ms per frame, main thread, this output
            msFrame: ms(p.frame / n),
            msAdvance: ms(p.advance / n),
            msPhysics: ms(p.physics / n),
            msPublish: ms(p.publish / n),
            msEvents: ms(p.events / n),
            msParts: ms(p.parts / n),
            msRender: ms(p.render / n),
            msBin: ms(p.bin / n),
            msLayout: ms(p.layout / n),
            msPaint: ms(p.paint / n),
            msPack: ms(p.pack / n),
            msUpload: ms(p.upload / n),
            msAtlasTotal: ms(p.atlas / n),
            msBinClear: p.sub ? ms(p.sub.binClear / n) : 0,
            msBinWalk: p.sub ? ms(p.sub.binWalk / n) : 0,
            msBinGrid: p.sub ? ms(p.sub.binGrid / n) : 0,
            msBinInsert: p.sub ? ms(p.sub.binInsert / n) : 0,
            msPackClear: p.sub ? ms(p.sub.packClear / n) : 0,
            msPackGrid: p.sub ? ms(p.sub.packGrid / n) : 0,
            msPackInst: p.sub ? ms(p.sub.packInst / n) : 0,
            worstMs: ms(p.worst),
            // share of ONE core this output's frame work took over the window
            corePct: Math.round(1000 * (p.frame + p.paint) / Math.max(1, span)) / 10,
            atlases: p.atlases,
            paints: p.paints,
            // bookkeeping that a leak would grow
            alive: pool ? pool.aliveCount : 0,
            live: pool ? pool.liveCount : 0,
            transient: pool ? pool.transientCount : 0,
            kicks: pool ? pool.kickAlive : 0,
            glows: pool ? pool.glows.length : 0,
            items: _particleItems ? _particleItems.count : 0,
            atlasH: _particleAtlasHeight,
            events: _state ? _state.events.filter(e => e).length : 0,
            pendingEvents: _state ? _state.pendingEvents.length : 0,
            entries: _state ? Object.keys(_state.entries).length : 0,
            hashes: _state ? Object.keys(_state.nearHashes).length : 0,
            publications: _state ? _state.publications : 0,
            missed: _particleMissed,
            sentinel: _particleSentinelErrors
        };
        perfStart();
        return out;
    }

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
        // A new state means a new entry ledger; the cached prefix is stale.
        _atlasPrefix = "";
        _atlasPrefixVersion = -1;
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
            // v9: the camera's share of the far layer's advance, for the one
            // event that has to travel with the field instead of with a pixel.
            camFlow: 0,
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
            entryVersion: 0,
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
            // 5-11 radial phenomena (star birth, nova, red giant, supernova,
            // pulsar, kilonova, gamma-ray burst). The two classes never share a
            // slot in either direction.
            events: [null, null, null, null, null, null, null, null, null, null, null, null],
            eventIds: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            // Whether this family has ever had an episode scheduled in this
            // process. Only the first one gets the warm start; a phenomenon
            // that loses a slot and is retired reschedules on the ordinary
            // interval, so retirement can never turn into a fast loop.
            firstEpisode: [false, false, false, false, false, false, false, false, false, false, false, false],
            // R6: episodes handed to the scheduler from outside its intervals
            // (a physics detection, or a family whose arrival is conditional).
            // Drained by publishEvents into the family's own entry, in order.
            pendingEvents: [],
            familyLast: {},
            moodClock: Date.now() / 1000,
            moodCorrection: 0,
            mood: [0, 0, 0, 0],
            // Which kind owns phenomenon slot 3 and slot 4, or null.
            phenomenonSlots: [null, null, null],
            // The nebula passage: one cloud, its own block, outside both slot
            // classes because it composites into the far field rather than on
            // top of everything.
            nebula: null,
            nebulaPending: null,
            nebulaId: 0,
            nebulaLast: null,
            // v10: which supernova episode currently owns a precursor star and
            // its debris, so the state machine fires its transitions once.
            novaEpisode: null,
            cometEpisode: null,
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
        // v9: the far layer's advance attributable to the CAMERA, with the
        // cell-size factor already folded out (see supernovaSite). It is the
        // same addend geo[0] takes, weighted by the regime blend and multiplied
        // by the far boost the grid divides out, so it is zero with the hole on
        // and eases in over the same 30 s crossfade everything else uses.
        s.camFlow += dFlow * sign * dustRate * farBoost() * _cameraBlend;
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
        // A running storm's radiant tracks the camera here, where dt is real:
        // the roll integrates the same bounded sinusoid the particles roll by,
        // and the creep is the far plane's own magnification rate, which is the
        // camera term a direction at infinity is entitled to. Both are clamped,
        // so a long storm in a fast fly-through can never lose its radiant.
        const storming = s.events[3];
        if (storming && storming.radiantOffset && s.clock >= storming.start && s.clock <= storming.start + storming.duration + (storming.offset || 0)) {
            const depthRange = clamp(cameraDepth, 2, 64);
            const pace = clamp(cameraSpeed, 0, 30);
            const dir = cameraDirection === "in" ? -1 : 1;
            const creepRate = pace > 0 ? (depthRange - 1) * pace / 360 * 0.10 / depthRange : 0;
            storming.creep = clamp(storming.creep * Math.exp(dir * _cameraBlend * creepRate * dt), 0.35, 2.2);
            storming.roll += clamp(cameraRoll, 0, 2) * (Math.PI / 180) * wave(s.clock, 23, random(screenSeed, 8761) * Math.PI * 2 + 0.9) * _cameraBlend * dt;
        }
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
        const perf = _perf;
        const t0 = perf ? perfClock.elapsedNs() : 0;
        advance(step);
        const t1 = perf ? perfClock.elapsedNs() : 0;
        _writingTime = true;
        time = _state.clock;
        _writingTime = false;
        _state.runtimeAtlas = true;
        publish();
        if (perf) {
            const t2 = perfClock.elapsedNs();
            perf.advance += t1 - t0;
            perf.publish += t2 - t1;
            perf.frame += t2 - t0;
            if (t2 - t0 > perf.worst)
                perf.worst = t2 - t0;
            ++perf.frames;
        }
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

    // The BMP header plus the entry ledger's 1280 rows, already base64-encoded.
    // Rebuilt only when publishEntries rewrites the ledger, which is never while
    // particles are on.
    property string _atlasPrefix: ""
    property int _atlasPrefixVersion: -1
    property var _atlasTail: null

    function atlasPrefix(): string {
        const s = _state;
        if (_atlasPrefix && _atlasPrefixVersion === s.entryVersion)
            return _atlasPrefix;
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
        const p = s.entryPixels;
        for (let row = 1535; row >= 256; --row) {
            const offset = (row - 256) * 64 * 3;
            for (let x = 0; x < 64; ++x)
                bytes.push(p[offset + x * 3 + 2], p[offset + x * 3 + 1], p[offset + x * 3]);
        }
        _atlasPrefix = Qt.btoa(bytes);
        _atlasPrefixVersion = s.entryVersion;
        return _atlasPrefix;
    }

    function atlasUrl(): string {
        // 24-bit BI_RGB BMP has no colour profile or gamma chunk, no alpha to
        // premultiply. The first 64x256 tile is the unchanged immutable cohort
        // atlas; a 64x1280 entry ledger follows it. A single 64x1536 upload
        // publishes both tiles and their uniforms atomically, at any DPR.
        // QImage uploads this opaque image as RGBA8. Bottom-up rows are explicit.
        //
        // Bottom-up is what makes this cheap: the ledger's 1280 rows come FIRST
        // in the byte stream and only the 256 descriptor rows follow, so 83 % of
        // the image never changes between two seals. Both the header + ledger
        // prefix (245814 bytes) and the descriptor tail (49152) are multiples of
        // three, and base64 encodes three bytes at a time, so the encoding of
        // the whole is exactly the concatenation of the two encodings -- proved
        // against python's base64 this session. Rebuilding and encoding all
        // 295 kB cost 29 ms, one dropped frame per output every 30 flow seconds.
        const s = _state;
        let tail = _atlasTail;
        if (!tail)
            tail = _atlasTail = new Array(256 * 64 * 3);
        let at = 0;
        for (let row = 255; row >= 0; --row) {
            const p = s.history[row].pixels;
            for (let x = 0; x < 64; ++x) {
                const c = x * 3;
                tail[at++] = p[c + 2];
                tail[at++] = p[c + 1];
                tail[at++] = p[c];
            }
        }
        return "data:image/bmp;base64," + atlasPrefix() + Qt.btoa(tail);
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
            bounds: [0, 0, 0, 0],
            burn: [0.52, 0, 0, 0]
        };
    }

    // v12. The meteor light curve, shared by the CPU envelope and the shader's
    // trail so a point on the trail is lit by exactly what the head was lit by
    // when it passed. F is the fraction of the path flown before maximum -- the
    // measured population is 0.52 +- 0.09 over 113 light curves, against the
    // 0.09 the shipped envelope peaked at, which is a real meteor played
    // backwards.
    //   L(x) = (x/F)^(s*F) * ((1-x)/(1-F))^(s*(1-F)),  exactly 1 at x = F.
    function lightCurveAt(x: real, F: real, s: real): real {
        const u = clamp(x, 0.0005, 0.9995);
        const f = clamp(F, 0.08, 0.92);
        return Math.pow(u / f, s * f) * Math.pow((1 - u) / (1 - f), s * (1 - f));
    }

    // The configured meteor tone block, read once per publication. naGain and
    // trainGain at zero switch the v12 emitters off and leave the shape change
    // on its own, which is how a config turns the colour work off without
    // turning the light curve off with it.
    function meteorToneVector(kind: int): var {
        const cfg = eventConfig(kind) || {};
        const value = (key, fallback, lo, hi) => {
            const raw = cfg[key];
            return clamp(raw === undefined || raw === null ? fallback : Number(raw), lo, hi);
        };
        return [value("naGain", 0.45, 0, 1), value("trainGain", 0.40, 0, 1),
            value("leadingEdgeGain", 0.30, 0, 0.6), value("curveSharp", 4.5, 0.5, 12)];
    }

    // Kinds 5-11 are the radial phenomena; their names are the JSON family keys.
    readonly property var radialNames: ["starBirth", "nova", "redGiant", "supernova", "pulsar", "kilonova", "gammaBurst"]
    // Transient heads 0-2, phenomenon slots 3-5. v8 adds the third phenomenon
    // slot: with seven families on two slots a red giant and a supernova spent
    // most of an hour queued behind a 200 s star birth.
    readonly property int transientSlotCount: 3
    readonly property int phenomenonSlotCount: 3
    // Combined peak linear gain across the phenomenon slots, outside a flash.
    // v6 held this at 0.55, which was below a single near star's 0.95: two
    // phenomena together could not reach the brightness of one ordinary star.
    readonly property real phenomenonGainCeiling: 1.6
    // v9 WARM START. The first dramatic episode of a process lands inside this
    // many active seconds, divided by rateScale like every other interval.
    readonly property real warmStartCapSec: 240

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
        // v6 shipped the pulsar, kilonova and gamma-ray burst off on a taste
        // argument. He could not see any cosmic event at all (ledger 2283), so
        // every family in the catalogue is on and the anti-strobe floors - not
        // an off switch - are what keeps them civil.
        return true;
    }

    function familyDefaults(kind: int): var {
        // weight, duration low/high, gain cap, tail low/high, bend low/high,
        // travel low/high. Lengths are fractions of the captured short side.
        // v12 lengthened the meteor trails. The trail is the only place the
        // light curve is VISIBLE in a single frame -- the head is one point,
        // and what makes a meteor read as a burning column in every photograph
        // is the curve laid out along the path. At the shipped 0.08-0.14 short
        // sides against a 0.28-0.38 chord the drawn trail covered 0.21-0.50 of
        // the path, most of it within a few per cent of the head's own
        // brightness, so there was nothing along it to see. It now covers
        // roughly 0.39-0.67, which is where the fusiform shows.
        return kind === 0 ? {
            straight: [0.72, 0.7, 1.3, 0.85, 0.13, 0.22, 0, 0, 0.28, 0.38],
            curved: [0.20, 0.9, 1.7, 0.80, 0.11, 0.17, 0.005, 0.02, 0.28, 0.38],
            skipping: [0.08, 1.2, 2.2, 0.70, 0.12, 0.19, 0, 0.008, 0.3, 0.4]
        } : {
            fast: [0.18, 4, 9, 0.95, 0.06, 0.11, 0, 0, 0.35, 0.65],
            slow: [0.34, 30, 65, 0.70, 0.20, 0.32, 0, 0, 0.5, 0.8],
            bent: [0.28, 12, 28, 0.80, 0.12, 0.20, 0.02, 0.06, 0.5, 0.8],
            pulsating: [0.08, 20, 40, 0.75, 0.14, 0.24, 0.01, 0.04, 0.5, 0.8],
            fragmenting: [0.02, 8, 16, 0.80, 0.08, 0.16, 0.01, 0.04, 0.45, 0.65],
            spiral: [0.10, 18, 35, 0.65, 0.10, 0.18, 0, 0, 0.5, 0.8]
        };
    }

    // coma scale, ion length, ion gain, dust length, dust gain, dust curve,
    // striation amplitude, dust lag angle in radians. Lengths multiply the
    // captured `tail`; this table is the whole of what makes one comet family
    // look unlike another. A fast comet is a bright blue spike with a stub of
    // dust; a slow one is a broad curved fan; a bent one is nearly all dust.
    function cometLook(family: string): var {
        return family === "fast" ? [0.80, 1.25, 0.75, 0.55, 0.26, 0.06, 0.16, 0.13] : family === "slow" ? [1.55, 1.25, 0.48, 1.15, 0.52, 0.20, 0.42, 0.26] : family === "bent" ? [1.20, 0.85, 0.32, 1.30, 0.58, 0.42, 0.58, 0.38] : family === "pulsating" ? [1.35, 1.15, 0.60, 0.95, 0.38, 0.16, 0.30, 0.20] : family === "fragmenting" ? [0.85, 0.90, 0.50, 0.80, 0.34, 0.13, 0.48, 0.18] : [1.10, 0.95, 0.42, 1.05, 0.44, 0.32, 0.36, 0.30];
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
        // kind >= 2: weight, duration low/high, gain cap, tail, bend, travel.
        // The 0.33/0.40 gain caps v6 used put a satellite and a slow wanderer
        // below an ordinary star; 0.55 puts them at one that moves.
        const d = kind < 2 ? familyDefaults(kind)[family] : [1, kind === 4 ? 180 : 30, kind === 4 ? 360 : 45, kind === 4 ? 0.75 : 0.55, 0, 0, 0.01, 0.04, 0.85, 1.1];
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
            // v10: the chord's midpoint, kept so cometParticles can re-cut a
            // longer chord around the same point once it knows how fast the
            // field is actually moving.
            origin: [x, y],
            centre: centre,
            angle: angle,
            distance: distance,
            shortSide: shortSide,
            tail: sample("tailShortSide", [d[4], d[5]], 0, 0.4, 11) * shortSide,
            gain: clamp(f.gain === undefined ? d[3] : f.gain, 0, d[3]),
            headCap: Math.round(clamp(eventHeadCap, 0, 3)),
            // v6 gave a satellite and a slow wanderer a FIXED 0.65 px sigma
            // whatever the buffer: measured, 14 lit pixels against a bright
            // star's 1.55 px sigma and 243/255. They were smaller and dimmer
            // than an ordinary star, which is why he never saw one.
            pointWidth: kind === 0 ? optics * 0.42 * (fireball ? 1.5 : 1) : kind === 1 ? optics * 0.55 : kind === 4 ? optics * 0.56 : optics * 0.62,
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
        // v12. The four draws that make one meteor unlike the next. They are
        // FROZEN AT BIRTH, like every other trait in this file: a meteoroid
        // does not decide halfway down what shape its light curve is.
        if (kind === 0) {
            const curve = cfg.curveF === undefined ? 0.52 : clamp(Number(cfg.curveF), 0.20, 0.90);
            const spread = cfg.curveSpread === undefined ? 0.09 : clamp(Number(cfg.curveSpread), 0, 0.25);
            // A normal from three uniforms: sd(u1+u2+u3-1.5) is exactly 0.5,
            // so 2*spread*(sum-1.5) has sd = spread. Cheaper and more honest
            // than a Box-Muller nobody can seed reproducibly here.
            const n = random(index, salt + 30) + random(index, salt + 31) + random(index, salt + 32) - 1.5;
            event.curveF = clamp(curve + 2 * spread * n, 0.20, 0.90);
            event.curveSharp = cfg.curveSharp === undefined ? 4.5 : clamp(Number(cfg.curveSharp), 0.5, 12);
            // The head's share of the light. CAMO transverse slices give about
            // 80:20 for a single body and 50:50 for one fragmenting hard, and
            // the shipped kernel had it hardcoded at 0.62 for everything.
            const ratio = parameterRange(cfg, "headTrailRatio", [0.50, 0.80], 0.3, 0.95);
            event.headShare = ratio[0] + (ratio[1] - ratio[0]) * random(index, salt + 33);
            // Entry speed, normalised, for the leading edge: the second
            // spectrum is absent below about 15 km/s, so a slow meteor must
            // get no violet precursor at all.
            event.speed01 = clamp((distance / Math.max(0.05, duration) / shortSide - 0.12) / 0.40, 0, 1);
            // v12 FLARES, in MAGNITUDES. Gross fragmentation is what produces
            // a bright flare: ordinary ones run to 1.5 mag, bright ones to 3,
            // and a terminal burst measured -6.5 -> -11 is 4.5 mag in 0.3 s.
            // The magnitudes drive the SATURATED DISC as well as the gain,
            // which is the only half of it the display can show -- a value
            // already at 255 cannot get brighter, but its disc can grow, and
            // that is what a camera records and what the eye reads as a flare.
            //
            // A fireball flares repeatedly as successive fragments release
            // (Zdar's first severe fragmentation was at 0.016 MPa and the
            // later ones at 1.4-2.5 MPa: a weak early crumble, then a strong
            // late shatter), and the LAST one is the biggest.
            const mag = parameterRange(cfg, "flareMag", [1.5, 4.5], 0, 6);
            event.flareSec = cfg.flareSec === undefined ? 0.22 : clamp(Number(cfg.flareSec), 0.10, 0.60);
            event.flares = [];
            if (fireball) {
                const count = 2 + Math.floor(random(index, salt + 34) * 3);
                for (let i = 0; i < count; ++i) {
                    const last = i === count - 1;
                    const at = last ? 0.90 + 0.07 * random(index, salt + 40 + i)
                        : 0.55 + 0.30 * (i + random(index, salt + 40 + i)) / Math.max(1, count - 1);
                    const m = last ? mag[1] * (0.85 + 0.15 * random(index, salt + 50 + i))
                        : mag[0] + (mag[1] - mag[0]) * 0.55 * random(index, salt + 50 + i);
                    event.flares.push([at, m]);
                }
            } else if (random(index, salt + 35) < (cfg.flareShare === undefined ? 0.12 : clamp(Number(cfg.flareShare), 0, 1))) {
                // An ORDINARY meteor gets an ordinary flare. The census is
                // blunt about this: 86.6 % of 1496 CAMO videos show continuous
                // fragmentation with no discrete flare at all, 9.0 % show
                // negligible fragmentation and only 4.3 % show the gross kind
                // that produces one. An ordinary flare runs to about 1.5
                // magnitudes; the 4.5-magnitude terminal burst belongs to a
                // fireball, and giving it to a third of all meteors moved the
                // whole population's light-curve maximum onto the flare --
                // measured, F went 0.525 +- 0.075 to 0.592 +- 0.147, which is
                // a sky of late-peaked meteors against a census that has 11 %.
                event.flares.push([0.78 + 0.18 * random(index, salt + 36),
                    mag[0] + (mag[1] - mag[0]) * 0.35 * random(index, salt + 37)]);
            }
            // The dustball model: a meteoroid is grains held by a glue with a
            // lower boiling point, the outer grains go first and the core
            // releases all at once. 18 % of an 891-event morphology census are
            // double-peaked, and that is the mechanism.
            const dbl = cfg.doublePeakShare === undefined ? 0.18 : clamp(Number(cfg.doublePeakShare), 0, 0.5);
            event.doublePeak = random(index, salt + 38) < dbl;
            event.secondF = clamp(event.curveF + 0.16 + 0.18 * random(index, salt + 39), 0.25, 0.95);
            event.secondGain = 0.55 + 0.30 * random(index, salt + 60);
        }
        // A comet is not a streak with a wider brush. It carries a coma, a
        // straight ion tail pointing away from the only light source on the sky
        // and a broader dust tail that lags behind it and curves, all captured
        // here and drawn by shader style 5.
        if (kind === 1) {
            const look = cometLook(family);
            event.coma = optics * 2.6 * look[0];
            event.ionLength = event.tail * look[1];
            event.ionWidth = Math.max(1.2, shortSide * 0.0030 * (0.7 + 0.6 * random(index, salt + 24)));
            event.ionGain = look[2];
            event.dustLength = event.tail * look[3];
            event.dustWidth = Math.max(2, shortSide * 0.0075 * (0.75 + 0.5 * random(index, salt + 25)));
            event.dustGain = look[4];
            event.curve = look[5];
            event.striae = look[6];
            event.lagAngle = look[7];
            event.dustSide = random(index, salt + 28) < 0.5 ? -1 : 1;
            event.comaGain = 0.34 + 0.18 * random(index, salt + 27);
            // Anti-sunward means away from the hole; with no hole, away from
            // the radial centre the whole field already flows out of.
            event.light = _hole.enabled ? [_hole.bhCentre.x, _hole.bhCentre.y] : centre.slice();
        }
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

    // v9 WARM START. v8 based every schedule on `previous ? previous.start :
    // s.clock`, so a family with no previous episode waited a FULL random
    // interval from the moment the shell started: after every restart the
    // supernova was 21-48 minutes away, the kilonova 36-84 and the burst 42-108.
    // The sky he actually watched -- the first few minutes after a restart --
    // could not contain a dramatic event at all, which is most of why he could
    // not spot one (his report, ledger 2284).
    //
    // The FIRST episode of each family now lands uniformly in [0.3, 1] x that
    // family's own interval MINIMUM, and the first dramatic one is additionally
    // capped at `warmStartCapSec` so something big happens inside the first four
    // minutes. `minimum` and `interval` both arrive already divided by
    // rateScale, and the cap is divided by it here, so the one dial moves the
    // first occurrence exactly as it moves every later one. The shared dramatic
    // cooldown is applied by the caller AFTER this, so it is still respected:
    // the supernova takes the early slot (it is scheduled first) and the
    // kilonova and the burst queue behind it a cooldown apart.
    function warmStart(kind: int, index: int, minimum: real, interval: real): real {
        const s = _state;
        const previous = s.events[kind];
        if (previous || s.firstEpisode[kind])
            return (previous ? previous.start : s.clock) + interval;
        let start = s.clock + minimum * (0.3 + 0.7 * random(index, screenSeed + 6607 + kind * 131));
        if (dramatic(kind))
            start = Math.min(start, s.clock + warmStartCapSec / Math.max(1e-6, rateScale()));
        return start;
    }

    // Active-second scheduling, up to seven days; hourly streams do not get
    // silently clamped to the v2 one-hour interval ceiling. Descriptors include
    // their schedule and geometry; edits only affect the next captured event.
    function schedule(kind: int): var {
        const s = _state;
        if (!eventEnabled(kind))
            return null;
        const master = rateScale();
        if (master <= 0)
            return null;
        const index = s.eventIds[kind]++;
        const cfg = eventConfig(kind);
        let range;
        if (kind >= 3) {
            range = parameterRange(cfg, "everyHours", kind === 3 ? [0.75, 2] : [0.75, 2], 0.01, 168).map(x => x * 3600);
        } else {
            const v = kind === 0 ? meteorsInterval : kind === 1 ? cometInterval : satellitesInterval;
            const minimum = clamp(v.x, kind === 0 ? 3 : kind === 1 ? 60 : 45, 604800);
            range = [minimum, clamp(v.y, minimum, 604800)];
        }
        range = [range[0] / master, range[1] / master];
        const shower = s.events[3];
        const inShower = shower && s.clock >= shower.start && s.clock <= shower.start + shower.duration;
        const activeMood = !inShower && s.mood[0] === 3 ? s.mood[1] : 0;
        const rate = kind === 0 ? 0.5 + s.live[3] : 1;
        if (kind === 0)
            range = [range[0] + (18 - range[0]) * activeMood, range[1] + (36 - range[1]) * activeMood];
        const interval = (range[0] + (range[1] - range[0]) * random(index, screenSeed + 113 + kind * 701)) / rate;
        let start = Math.max(s.clock, warmStart(kind, index, range[0] / rate, interval));
        const family = kind < 2 ? chooseFamily(kind, index, start) : kind === 3 ? "shower" : kind === 4 ? "slowWanderer" : "satellite";
        const e = captureEvent(kind, index, start, kind === 3 ? "straight" : family);
        if (kind === 3) {
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
        s.firstEpisode[kind] = true;
        if (family === "fragmenting" || family === "spiral")
            s.familyLast[family] = start;
        if (kind === 3)
            captureStorm(e, index);
        return e;
    }

    // ---- The meteor storm (kind 3) -----------------------------------------
    // v8's shower was six ordinary meteors on a 30-60 s timer, staggered 4-12 s
    // apart and capped at 0.60 gain: one meteor at a time, dimmer than a normal
    // one, radiating from a point nobody could infer from six samples. He could
    // not spot it (ledger 2284), and there was nothing to spot.
    //
    // A storm is now ONE slot with a procedural kernel behind it (meteorStorm in
    // starfield.frag). The CPU owns the schedule, the radiant, the rate hump and
    // the fireballs; the shader owns every ordinary streak, generated from the
    // storm's seed and its cumulative PHASE. Several meteors a second therefore
    // cost four vec4 of uniform rather than dozens of slots, and the three
    // transient heads stay free - which is what the fireballs use.
    function stormValue(cfg: var, key: string, fallback: real, low: real, high: real): real {
        const raw = cfg && cfg[key];
        return clamp(raw === undefined || raw === null ? fallback : Number(raw), low, high);
    }

    // A trail is an ANGLE on the sky, not a length on the screen: the same
    // meteor is a point beside the radiant and a long streak sixty degrees away.
    // This is the angle whose gnomonic projection, at the 45 deg reference where
    // tan is 1, spans `fraction` of the short side.
    function stormTrailAngle(fraction: real): real {
        return Math.PI / 4 - Math.atan(clamp(1 - fraction, 0.02, 1));
    }

    function captureStorm(e: var, index: int): void {
        const cfg = eventConfig(3) || {};
        const salt = screenSeed + 4091;
        const draw = offset => random(index, salt + offset);
        const span = (key, fallback, low, high, offset) => {
            const r = parameterRange(cfg, key, fallback, low, high);
            return r[0] + (r[1] - r[0]) * draw(offset);
        };
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        e.family = "shower";
        // Build-up, plateau and decay out of ONE duration, so the documented
        // key keeps its meaning and the shape is a fraction of it.
        e.duration = span("durationSec", [70, 130], 20, 600, 1);
        const rampFraction = stormValue(cfg, "rampFraction", 0.32, 0.1, 0.6);
        e.ramp = e.duration * rampFraction;
        e.decay = (e.duration - e.ramp) * 0.62;
        e.peakSec = Math.max(0, e.duration - e.ramp - e.decay);
        e.rateMax = stormValue(cfg, "peakRate", 6, 0.2, 8) * Math.max(0.05, rateScale());
        // The hump starts and ends at the ORDINARY meteor rate, so a storm
        // arrives out of the sky the viewer already has rather than switching
        // one on: 1/82 s against a peak of four a second, the same ratio a real
        // shower has against the sporadic background.
        const spacing = clamp(meteorsInterval.x, 3, 604800) + clamp(meteorsInterval.y, 3, 604800);
        e.rateFloor = meteorsEnabled ? clamp(2 * Math.max(0.05, rateScale()) / Math.max(6, spacing), 0.002, e.rateMax * 0.25) : 0.002;
        const trail = parameterRange(cfg, "streakShortSide", [0.10, 0.30], 0, 0.45);
        e.trailLo = stormTrailAngle(trail[0]);
        e.trailHi = stormTrailAngle(trail[1]);
        const headPx = parameterRange(cfg, "headPx", [3, 6], 1, 12);
        // The shader spreads each streak's sigma over 0.66..1.33 of this, which
        // reproduces the pair exactly when its ends are a factor of two apart.
        e.headSigma = (headPx[0] + headPx[1]) * 0.5 * shortSide / 2160;
        e.stormGain = stormValue(cfg, "gain", 1, 0, 1.5);
        e.grazers = stormValue(cfg, "earthgrazerShare", 0.08, 0, 0.35);
        e.fragments = stormValue(cfg, "fragmentShare", 0.06, 0, 0.35);
        e.stormMix = stormValue(cfg, "paletteMix", 0.30, 0, 0.45);
        // v12. The storm's own light-curve population and its train stream.
        // The kernel draws each streak's F, flare and train from these plus the
        // streak index, so a storm's variety costs no uniform per streak.
        e.curveF = stormValue(cfg, "curveF", 0.52, 0.20, 0.90);
        e.curveSpread = stormValue(cfg, "curveSpread", 0.09, 0, 0.25);
        e.flareShare = stormValue(cfg, "flareShare", 0.30, 0, 1);
        e.doublePeakShare = stormValue(cfg, "doublePeakShare", 0.18, 0, 0.5);
        e.trainShare = stormValue(cfg, "trainShare", 0.13, 0, 0.40);
        e.trainGain = stormValue(cfg, "trainGain", 0.40, 0, 1);
        e.trainFoldSec = stormValue(cfg, "trainFoldSec", 22, 4, 120);
        e.trainDiffuseSec = stormValue(cfg, "trainDiffuseSec", 34, 4, 240);
        // THE SHEAR, derived from a wind speed rather than typed as pixels.
        //
        // Horizontal winds at 90 km run to a few tens of m/s, and the shear is
        // the DIFFERENTIAL along one train: 27 m/s to 81 m/s were measured at
        // different points of one real Perseid train, a 54 m/s spread, which
        // is 1.2x the 45 m/s this key defaults to.
        //
        // THE ONE HONEST APPROXIMATION IN HERE, stated rather than hidden: the
        // drawn train lives `trainSec` seconds and a real one deforms this
        // much over MINUTES. Its clock is compressed onto the three-minute
        // panel of Cordonnier's six -- "pronounced kinks, one or two loops" --
        // because that is the picture, and playing the real rate would give a
        // straight bar for the whole of a 30 s train, which is precisely what
        // the shipped one did. Everything else below is arithmetic:
        //   metres  = differential * 180 s
        //   radians = metres / 100 km            (the range)
        //   pixels  = radians * focal            (focal = shortSide, gnomonic,
        //                                         taken at theta = 0, which is
        //                                         the conservative end)
        const windMs = stormValue(cfg, "trainWindSpeed", 45, 0, 160);
        e.trainShearPx = shortSide * (windMs * 1.2 * 180) / 100000;
        const trainRange = parameterRange(cfg, "trainSec", [16, 44], 0, 180);
        e.trainSecLo = trainRange[0];
        e.trainSecHi = trainRange[1];
        // The shader's train loop is bounded; the joint bound
        // ceil(trainShare * peakRate * trainSec[1]) <= 16 is what keeps it so,
        // and it is validated here rather than discovered on the screen. Each
        // candidate costs [derived] 0.056 GPU points over the whole buffer.
        e.trainWindow = Math.min(16, Math.max(0, Math.ceil(e.trainShare * e.rateMax * e.trainSecHi)));
        e.creep = 1;
        e.roll = 0;
        // The radiant: off-centre by construction (a storm pointed at the middle
        // of the screen reads as a zoom, not a shower), and never on the hole,
        // because a radiant inside the drawn material would put the convergence
        // point behind something opaque. Same keep-out the phenomena use.
        const bias = stormValue(cfg, "radiantBias", 0.28, 0, 0.45);
        const centre = [w * 0.5 + shader.centreOffset.x, h * 0.5 + shader.centreOffset.y];
        const keepOut = 1.25 * holeReach();
        e.radiantOffset = [0, 0];
        for (let attempt = 0; attempt < 16; ++attempt) {
            const a = draw(20 + attempt) * Math.PI * 2;
            // The keep-out the phenomena use is 1109 px on DP-3 against a 605 px
            // radiant bias, so a hole-on storm has to be PUSHED past it, not
            // redrawn until it misses: sixteen draws inside the disk all fail.
            // A radiant just off the short edge is the better picture anyway -
            // every streak then crosses the whole buffer.
            const r = clamp(Math.max(shortSide * bias * (0.72 + 0.56 * draw(40 + attempt)), _hole.enabled ? keepOut * 1.05 : 0), 0, 0.75 * shortSide);
            e.radiantOffset = [Math.cos(a) * r, Math.sin(a) * r];
            const px = centre[0] + e.radiantOffset[0], py = centre[1] + e.radiantOffset[1];
            const clear = !_hole.enabled || Math.hypot(px - _hole.bhCentre.x, py - _hole.bhCentre.y) >= keepOut;
            // ON the buffer, not merely near it. Pushing the radiant past the
            // hole's keep-out can send it off the short edge, and a shower whose
            // convergence point is off-screen reads as meteors going one way
            // rather than as a storm. The angle is what the retries vary.
            const margin = shortSide * 0.04;
            if (clear && px > margin && px < w - margin && py > margin && py < h - margin)
                break;
        }
        // Fireballs are the one part of a storm the shader does NOT generate:
        // they carry a terminal flash and a train that outlives them by half a
        // minute, so they need the CPU's clock and a real slot each. One to
        // three of them, spread across the peak, on the free transient heads.
        // v12: trainSec is now the general train life and is the same key
        // the procedural stream reads. 12-26 s never reached the fold time,
        // so no train in the sky could ever loop.
        const trainSpan = [e.trainSecLo, e.trainSecHi];
        const count = Math.round(span("fireballs", [1, 3], 0, 6, 3));
        const from = e.ramp * 0.55;
        const to = e.ramp + e.peakSec + e.decay * 0.45;
        e.children = [];
        let overhang = 0;
        for (let i = 0; i < count; ++i) {
            const pick = o => random(index * 13 + i, salt + o);
            const flight = 1.6 + 1.6 * pick(91);
            const train = trainSpan[0] + (trainSpan[1] - trainSpan[0]) * pick(101);
            const at = from + (to - from) * (i + 0.15 + 0.7 * pick(141)) / Math.max(1, count);
            // A fireball is AIMED, not drawn like the others. Its ray and its
            // angular speed are solved so the terminal flash lands on a point
            // inside the buffer: a free draw flares off the corner most of the
            // time, because the radiant is off-centre and tan() runs away.
            // ...and never onto the hole. A fireball is a SLOT, composited
            // after the disk and not shadow-masked, so one flaring on the disk
            // would shine straight through it - the same reason the phenomena
            // reject a placement inside the drawn material. The procedural
            // streaks have no such problem: they are evaluated at the lensed
            // source, so they bend around the hole and sink behind the disk.
            // Drawn in POLAR coordinates about the hole, because on the tablet
            // the keep-out circle covers most of the buffer: a rejection loop
            // over a rectangle fails a third of the time, a radius that starts
            // outside it never does. The angle is what the retries vary, until
            // the point is on the buffer too.
            const edge = shortSide * 0.05;
            const origin = [centre[0] + e.radiantOffset[0], centre[1] + e.radiantOffset[1]];
            // The whole RAY has to miss the hole, not only its far end: the
            // train runs all the way back to the radiant, and a train drawn
            // across the shadow shines through it exactly as a flash would.
            const misses = point => {
                if (!_hole.enabled)
                    return true;
                const vx = point[0] - origin[0], vy = point[1] - origin[1];
                const len = vx * vx + vy * vy;
                const t = len > 0 ? clamp(((_hole.bhCentre.x - origin[0]) * vx + (_hole.bhCentre.y - origin[1]) * vy) / len, 0, 1) : 0;
                return Math.hypot(origin[0] + vx * t - _hole.bhCentre.x, origin[1] + vy * t - _hole.bhCentre.y) >= keepOut;
            };
            let target = null;
            for (let attempt = 0; attempt < 40; ++attempt) {
                const ta = pick(201 + attempt) * Math.PI * 2;
                const tr = Math.max(_hole.enabled ? keepOut * 1.06 : 0, shortSide * (0.12 + 0.34 * pick(241 + attempt)));
                const point = [_hole.bhCentre.x + Math.cos(ta) * tr, _hole.bhCentre.y + Math.sin(ta) * tr];
                if (point[0] > edge && point[0] < w - edge && point[1] > edge && point[1] < h - edge && misses(point)) {
                    target = point;
                    break;
                }
            }
            // No clear ray in forty tries means the radiant sits so close to the
            // keep-out that the hole blocks most of the sky from it. Drop THIS
            // fireball rather than aim it through the disk: a storm with one
            // fireball is a storm; one shining through the hole is a bug.
            if (!target)
                continue;
            const ray = [target[0] - origin[0], target[1] - origin[1]];
            const reach = Math.max(shortSide * 0.08, Math.hypot(ray[0], ray[1]));
            const thetaEnd = Math.min(Math.atan(reach / shortSide), 1.15);
            const theta0 = Math.max(0.05, thetaEnd - (0.22 + 0.26 * pick(81)) * flight);
            const child = {
                fireball: true,
                at: at,
                angle: Math.atan2(ray[1], ray[0]),
                theta0: theta0,
                omega: (thetaEnd - theta0) / flight,
                flight: flight,
                train: train,
                sigma: e.headSigma * (1.7 + 0.7 * pick(111)),
                flashSigma: shortSide * (0.010 + 0.010 * pick(121)),
                trainWidth: e.headSigma * (2.4 + 1.6 * pick(151)),
                gain: e.stormGain * (1.45 + 0.55 * pick(131)),
                // The wind as a SHEAR, not four independent bearings: one base
                // direction plus a twist along the train's length. Four random
                // angles put an elbow in the polyline, which is what the first
                // live capture showed - a train bends, it does not hinge.
                drift: [pick(161) * Math.PI * 2, (pick(162) - 0.5) * 1.8],
                colour: e.colour.slice()
            };
            e.children.push(child);
            overhang = Math.max(overhang, at + flight + train - e.duration);
        }
        // The episode is not recycled while a train is still fading, and the
        // reservation against the other transients covers the same span.
        e.offset = Math.max(0, overhang);
    }

    // The rate hump: a trickle, a smoothstep up to `rateMax`, a plateau, and a
    // smoothstep back down. Meteors per second, already through rateScale.
    function stormRate(e: var, age: real): real {
        if (!e || !e.radiantOffset || age < 0 || age >= e.duration)
            return 0;
        const s = age < e.ramp ? ease(age / Math.max(1e-6, e.ramp))
            : age < e.ramp + e.peakSec ? 1
            : ease(1 - (age - e.ramp - e.peakSec) / Math.max(1e-6, e.decay));
        return e.rateFloor + (e.rateMax - e.rateFloor) * s;
    }

    // Its integral, in closed form: the storm's cumulative expected meteor
    // count. This is the single number that makes a streak's launch time and
    // the rate the SAME fact - streak k launches where phase reaches k, so k
    // advances at exactly `rate` per second whatever the hump is doing.
    // INT of smoothstep(0,1,x) from 0 to u is u^3 - u^4/2; the falling shoulder
    // is that same integral read backwards.
    function stormPhase(e: var, age: real): real {
        if (!e || !e.radiantOffset)
            return 0;
        const t = clamp(age, 0, e.duration);
        const rise = e.rateMax - e.rateFloor;
        const bump = u => u * u * u * (1 - 0.5 * u);
        if (t < e.ramp)
            return e.rateFloor * t + rise * e.ramp * bump(t / Math.max(1e-6, e.ramp));
        let total = e.rateFloor * e.ramp + rise * e.ramp * 0.5;
        if (t < e.ramp + e.peakSec)
            return total + e.rateMax * (t - e.ramp);
        total += e.rateMax * e.peakSec;
        const rest = t - e.ramp - e.peakSec;
        return total + e.rateFloor * rest + rise * e.decay * (0.5 - bump(1 - rest / Math.max(1e-6, e.decay)));
    }

    // Where the radiant is right now. It is a point on the SKY, so it takes the
    // shared centre wander and the camera's roll, and in the camera regime a
    // slow radial creep at the far plane's own depth - the far layer is what a
    // direction at infinity moves with. A translating camera does not carry a
    // direction off the screen, and integrating the near field's magnification
    // here would have done exactly that (4.8x over a 100 s storm, measured).
    function stormRadiant(e: var): var {
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const cx = w * 0.5 + shader.centreOffset.x, cy = h * 0.5 + shader.centreOffset.y;
        const creep = clamp(Number(e.creep) || 1, 0.35, 2.2);
        const roll = Number(e.roll) || 0;
        const rx = e.radiantOffset[0] * creep, ry = e.radiantOffset[1] * creep;
        const cos = Math.cos(roll), sin = Math.sin(roll);
        return [cx + rx * cos - ry * sin, cy + rx * sin + ry * cos];
    }

    // The four vectors the storm kernel reads, or null when no storm is running.
    function stormState(): var {
        const s = _state;
        const e = s.events[3];
        if (!e || !e.radiantOffset || !eventEnabled(3))
            return null;
        const age = s.clock - e.start;
        if (age < 0 || age >= e.duration)
            return null;
        const rate = stormRate(e, age);
        if (rate <= 0 || e.stormGain <= 0)
            return null;
        const place = stormRadiant(e);
        // The window is how far back the kernel has to look for a streak that
        // is still alive: the longest life in the kernel is 5.4 s (an
        // earthgrazer), so rate*5.4 candidates plus a margin, and the loop is
        // hard-bounded at 40 in the shader whatever this says.
        const window = Math.min(48, Math.max(4, Math.ceil(rate * 5.5) + 3));
        return {
            head: [place[0], place[1], stormPhase(e, age), rate],
            shape: [e.headSigma, e.trailLo, e.trailHi, e.stormGain],
            colour: e.colour.concat(e.stormMix),
            span: [window, e.grazers, e.fragments, modulo(e.index * 7919 + screenSeed, 4096)],
            // v12: the light-curve population and the train stream. Every
            // streak's own F, flare and train are hash-drawn in the kernel from
            // these four numbers plus its index, so several a second still cost
            // one uniform block.
            burn: [e.curveF, e.curveSpread, e.flareShare, e.doublePeakShare],
            train: [e.trainShare, e.trainWindow, e.trainSecLo, e.trainSecHi],
            // 1.45 x trainGain: the key is one emitter's share of a head,
            // and a PERSISTENT train is the same emitter seen with no head
            // beside it to be read against. Matching them numerically made
            // the residue invisible next to the streaks that left it.
            wind: [e.trainShearPx, e.trainFoldSec, e.trainGain * 1.45, e.trainDiffuseSec]
        };
    }

    function stormOff(): var {
        return {
            head: [0, 0, 0, 0],
            shape: [1, 0, 0, 0],
            colour: [1, 1, 1, 0],
            span: [0, 0, 0, 0],
            burn: [0.52, 0.09, 0, 0],
            train: [0, 0, 0, 0],
            wind: [0, 0, 0, 0]
        };
    }

    // One fireball, drawn through shader style 7 on an ordinary transient head.
    // It flies the same gnomonic ray out of the radiant the procedural streaks
    // do, flares at the end of its flight, and leaves a train that drifts and
    // shears for ten to thirty seconds after the head has gone.
    function stormFireballState(e: var, c: var): var {
        const s = _state;
        const age = s.clock - e.start - c.at;
        if (age < 0 || age > c.flight + c.train)
            return null;
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const focal = shortSide;
        const place = stormRadiant(e);
        const dx = Math.cos(c.angle), dy = Math.sin(c.angle);
        const at = t => {
            const theta = Math.min(c.theta0 + c.omega * clamp(t, 0, c.flight), 1.35);
            const d = focal * Math.tan(theta);
            return [place[0] + dx * d, place[1] + dy * d];
        };
        const flown = Math.min(age, c.flight);
        const head = at(flown);
        const trainAge = Math.max(0, age - c.flight);
        const life = clamp(trainAge / Math.max(0.001, c.train), 0, 1);
        // v12. The train is a RAY with a warp, not four drifting points. It
        // runs from where the head is (or died) back down the path it flew;
        // the shader deforms it. See stormTrainRay() for why the fold is the
        // part that matters and why four points could never produce one.
        const foot = at(0);
        let vx = foot[0] - head[0], vy = foot[1] - head[1];
        let trainLen = Math.hypot(vx, vy);
        if (trainLen < 1) {
            vx = -dx;
            vy = -dy;
            trainLen = 1;
        }
        const tdx = vx / trainLen, tdy = vy / trainLen;
        // THE SHEAR ENVELOPE, linear then saturating, and the BODILY DRIFT,
        // which is the mean wind against the shear's differential. The train
        // drifts; it does not teleport.
        const shearEnv = (1 - Math.exp(-2.5 * life)) / (1 - Math.exp(-2.5));
        const shear = (e.trainShearPx || 0) * shearEnv;
        const bearing = c.drift[0] + 0.25 * Math.sin(0.11 * trainAge + c.drift[0]);
        const drift = (e.trainShearPx || 0) * 0.50 * shearEnv;
        const ox = head[0] + Math.cos(bearing) * drift;
        const oy = head[1] + Math.sin(bearing) * drift;
        // The fold is held at zero until trainFoldSec of the train's own life
        // and then grown, so loops appear LATE -- which is when real ones show
        // them. A short train never loops, and that is correct.
        const foldStart = clamp(Number(e.trainFoldSec) || 22, 0, 1e6);
        const fold = 0.16 * ease(clamp((trainAge - foldStart) / Math.max(2, 0.55 * c.train), 0, 1));
        // Diffusion widens it as it ages; the high end goes first (shader).
        const widen = 1 + 1.9 * (1 - Math.exp(-trainAge / Math.max(2, Number(e.trainDiffuseSec) || 34)));
        // The three phases of a persistent train, each on its own clock, in
        // the train's own seconds. Normalised so the SUM is 1: the brightness
        // is trainGain's business, the colour is theirs.
        const green = Math.exp(-trainAge / 4.5);
        const metal = Math.exp(-Math.pow((trainAge - 9) / 13, 2));
        const feo = 1 - Math.exp(-Math.max(0, trainAge - 3) / 16);
        const toneSum = Math.max(1e-4, green + metal + feo);
        const length = trainLen;
        // Nucleus: alive through the flight only. Flash: a Gaussian in time at
        // the end of it. Train: rises with the flight and then fades over its
        // own lifetime.
        const coreEnv = ease(age / 0.18) * ease((c.flight - age) / 0.40);
        // 0.90 s wide: the brightest thing in a storm still has no edge a
        // blink could hide in - 0.033 of its own peak per frame at 30 Hz,
        // inside the 0.05 the anti-strobe floors are proven against.
        const t = (age - c.flight * 0.90) / 0.90;
        const flashEnv = Math.exp(-2.6 * t * t);
        const trainEnv = ease(age / Math.max(0.3, c.flight * 0.5)) * Math.pow(1 - life, 1.4);
        const coreAbs = c.gain * coreEnv;
        const flashAbs = c.gain * 0.60 * flashEnv;
        const trainAbs = c.gain * 0.42 * trainEnv;
        const peak = Math.max(coreAbs + flashAbs, trainAbs);
        if (peak <= 0.0004)
            return null;
        // The box has to hold the warped ray, not the straight one: the shear
        // moves the centreline by up to `shear` px sideways and the fold moves
        // it along by up to 0.16 of its length, and outside this box the
        // kernel returns before it reads anything.
        // 1.156 is the warp's own worst case: the three shear terms sum to
        // 2.332, the 0.4288 normalises them, and the along-track envelope
        // tops out at 1.156. 1.25 is that with room, and the fold's 0.16 of
        // the length is covered by the 1.2 reach below.
        const pad = Math.max(3 * c.flashSigma, 9 * c.trainWidth * widen, 6 * c.sigma) + shear * 1.25;
        const reach = trainLen * 1.2;
        const xs = [head[0], ox, ox + tdx * reach];
        const ys = [head[1], oy, oy + tdy * reach];
        return {
            head: [head[0], head[1], c.sigma, peak],
            colour: c.colour.concat(7),
            tail01: [ox, oy, tdx, tdy],
            tail23: [trainLen, shear, fold, c.drift[0] * 0.159154 + 0.37],
            tail4: [c.trainWidth, trainAbs / peak],
            shape: [widen, c.flashSigma, coreAbs / peak, flashAbs / peak],
            bounds: [Math.min(...xs) - pad, Math.min(...ys) - pad, Math.max(...xs) + pad, Math.max(...ys) + pad],
            burn: [green / toneSum, metal / toneSum, feo / toneSum, trainAge]
        };
    }

    // v10. A fireball's terminal flash is the storm's one moment of violence,
    // so it reaches the field the same way a supernova does: it lights the
    // stars around it and sprays a handful of fragments. Small, because a storm
    // is many small things and the fireballs are the loud ones -- not because
    // it is a lesser mechanism. Fires once per fireball, on the frame its own
    // flash peaks.
    function stormFireballParticles(e: var, c: var, at: var): void {
        if (!_particles || !_particles.live || !particlesEnabled || c.burst)
            return;
        const age = _state.clock - e.start - c.at;
        if (age < c.flight * 0.90)
            return;
        c.burst = true;
        const P = _particles;
        const shortSide = Math.min(P.width, P.height);
        ParticlePhysics.brightenNear(P, at[0], at[1], 0.26 * shortSide, 0.75, 1.4);
        ParticlePhysics.spawnBurst(P, at[0], at[1], 14, [0.06 * shortSide, 0.20 * shortSide], {
            lifeSec: [0.9, 2.4],
            sizePx: [0.8, 1.9],
            lum: [2.0, 3.6],
            colour: c.colour,
            endColour: [0.95, 0.45, 0.18],
            fastShare: 0.12,
            fastGain: 1.9,
            streakPx: Math.min(40, P.config.streak.bendMaxPx),
            exposureSec: 0.05,
            drag: 0.9,
            group: 3
        });
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
    // How far out the hole is actually DRAWN, from its own published uniforms -
    // the same call the particles use so that one number moves both.
    // bhGeometry.y is the LENSING reach (8 Rh under the `target` preset), not
    // the drawn material: 1.6x it is 12.8 Rh, which on his DP-3, HDMI-A-1 and
    // tablet alike covers the WHOLE buffer. Measured acceptance 0.000 on all
    // three, so radialPlacement returned null every time and no phenomenon had
    // ever been placed on any of his screens (his report, ledger 2283). The
    // exclusion has to be the material an event would shine through, which is
    // the disk's rim (887 px on DP-3 against a 3041 px lensing reach).
    function holeReach(): real {
        if (!_hole.enabled)
            return 0;
        const radii = ParticlePhysics.visibleRadius(_hole.bhGeometry.x, {
            innerRs: _hole.bhDisk.x,
            outerRs: _hole.bhDisk.y,
            arcGain: _hole.bhArcs.x,
            arcRadiusRh: _hole.bhArcs.y,
            arcSpacingRh: _hole.bhArcs.z,
            arcCount: _hole.bhArcs.w
        });
        return Math.max(radii.arcs, radii.disk);
    }

    // `marginShare` is how far from an edge, in short sides, a phenomenon may
    // land; 0.05 is the v6 default. v9's supernova asks for 0.12 because its
    // shell reaches 0.20 short sides and a rim half off the screen is half an
    // event. Acceptance measured on the tablet with his hole on: 32 %, so one
    // placement in 500 exhausts the sixteen attempts.
    function radialPlacement(index: int, salt: real, marginShare: real, keepOutPad: real): var {
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        const margin = (marginShare === undefined ? 0.05 : clamp(marginShare, 0, 0.3)) * shortSide;
        const centre = [w * 0.5 + shader.centreOffset.x, h * 0.5 + shader.centreOffset.y];
        // `keepOutPad` is extra clearance in PIXELS for an episode that draws
        // something wide around its own centre: the keep-out guards where the
        // event IS, and a v9 supernova's shell reaches 0.20 short sides beyond
        // that, so a centre that merely clears the drawn material still puts
        // the rim on the disk. Callers ask for it and fall back without it.
        const keepOut = 1.25 * holeReach() + (Number.isFinite(keepOutPad) ? Math.max(0, keepOutPad) : 0);
        for (let attempt = 0; attempt < 16; ++attempt) {
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
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h);
        // A supernova asks for its own shell's reach on top of the keep-out and
        // takes the ordinary one if sixteen attempts cannot find that much room.
        // Measured with his hole on, 1000 captures of sixteen attempts each:
        // the padded placement succeeds 85.3 % of the time on DP-3, 99.9 % on
        // HDMI-A-1 and 28.3 % on the tablet, where the hole is 41 % of the short
        // side and there is often nowhere that clears both. The fallback is
        // exactly v8's placement, so this is never worse, only usually better.
        const shellPad = kind === 8 ? 0.5 * parameterRange(cfg, "shellShortSide", [0.25, 0.40], 0, 0.6)[1] * shortSide : 0;
        let place = radialPlacement(index, salt, kind === 8 ? 0.12 : 0.05, shellPad);
        if (!place && shellPad > 0)
            place = radialPlacement(index, salt, 0.12, 0);
        if (!place)
            return null;
        const optics = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
        function sample(key, fallback, lo, hi, offset) {
            const range = parameterRange(cfg, key, fallback, lo, hi);
            return range[0] + (range[1] - range[0]) * random(index, salt + offset);
        }
        function value(key, fallback, cap) {
            return clamp(cfg[key] === undefined ? fallback : cfg[key], 0, cap);
        }
        // Near-layer optical scale. v6 used optics*0.9, which on his DP-3 is a
        // 2.25 px sigma against a bright star's 1.55 px: measured, a nova was
        // 125/255 where a star is 243/255 and 17 px across, so every phenomenon
        // read as a slightly odd star. The family-scaled core below is 3.5-6.5
        // px and the gains are raised to match (his report, ledger 2283).
        const coreScale = kind === 5 ? 1.6 : kind === 6 ? 2.0 : kind === 7 ? 1.8 : kind === 8 ? 2.6 : kind === 9 ? 1.4 : kind === 10 ? 2.2 : 1.8;
        const core = optics * coreScale;
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
            e.gain = value("gain", 0.60, 0.60);
            e.duration = sample("durationSec", [80, 170], 10, 1800, 3);
            e.condense = Math.min(sample("condenseSec", [25, 55], 0, 600, 5), e.duration * 0.5);
            // haloPx is a from-to span and MAY descend (40 -> 9 is the default
            // condensation), so it is read directly rather than through
            // parameterRange, which sorts its pair.
            const raw = Array.isArray(cfg.haloPx) && cfg.haloPx.length === 2 && cfg.haloPx.every(x => Number.isFinite(x)) ? cfg.haloPx : [40, 9];
            e.halo0 = clamp(raw[0], 0.5, 96) * optics * 0.5;
            e.halo1 = clamp(raw[1], 0.5, 96) * optics * 0.5;
        } else if (kind === 6) {
            e.gain = value("gain", 0.90, 0.90);
            e.rise = Math.max(0.8, sample("riseSec", [1.2, 2.4], 0, 600, 3));
            e.hold = sample("holdSec", [0.6, 1.6], 0, 600, 5);
            e.decay = sample("decaySec", [20, 45], 0, 600, 7);
            e.duration = e.rise + e.hold + e.decay;
            e.shell = sample("shellShortSide", [0.035, 0.06], 0, 0.25, 9) * shortSide;
            e.shellGain = value("shellGain", 0.26, 0.30);
        } else if (kind === 7) {
            e.gain = value("gain", 0.60, 0.60);
            e.duration = sample("durationSec", [140, 280], 10, 1800, 3);
            e.swell = Math.min(sample("swellSec", [45, 80], 0, 600, 5), e.duration * 0.4);
            e.collapse = Math.min(sample("collapseSec", [30, 55], 0, 600, 7), e.duration * 0.3);
            e.nebula = clamp(cfg.nebulaShortSide === undefined ? 0.030 : cfg.nebulaShortSide, 0, 0.25) * shortSide;
            e.nebulaGain = value("nebulaGain", 0.16, 0.20);
            e.warm = [1, 0.80, 0.62];
        } else if (kind === 8) {
            // ---- v9 SUPERNOVA: a four-phase life cycle ----------------------
            // 1 precursor: the star brightens, reddens and pulses faster.
            // 2 core collapse: a white-blue flash that lifts the whole sky.
            // 3 shell: a filamentary Sedov shock, r ~ t^0.4, cooling as it goes.
            // 4 remnant: a two-tone turbulent nebula with the neutron star the
            //   collapse left behind still blinking at its centre.
            // Every span and every radius is captured here, once, from the same
            // hash stream, so an edit only reaches the NEXT episode.
            e.precursor = sample("precursorSec", [10, 20], 0, 120, 19);
            e.rise = Math.max(0.8, sample("riseSec", [0.8, 1.5], 0, 600, 3));
            // v11: the bloom may sit at its widest for 0.16-0.28 s, not 0.6-1.6.
            // Requirement A allows a ~10 % bloom for at most 0.4 s, and the
            // measured window above 95 % of peak width is the eased tail of the
            // rise plus this hold: 0.28-0.40 s (tools/sn_flash.py --bloom).
            e.hold = sample("holdSec", [0.16, 0.28], 0, 600, 5);
            e.decay = sample("decaySec", [25, 60], 1, 600, 7);
            e.shellSpan = sample("shellSec", [30, 90], 5, 600, 21);
            e.remnant = sample("remnantSec", [120, 300], 1, 1800, 9);
            e.duration = e.precursor + e.rise + e.hold + e.shellSpan + e.remnant;
            // Both are the drawn DIAMETER as a share of the short side, halved
            // here into the radius everything downstream works in.
            // v11 halved the flash: 0.15-0.25 of the short side put the bloom's
            // visible disc at 20 % of the screen's short side, which with the
            // sky lift gone is the only thing left that could still read as
            // "the screen flashed". 0.08-0.12 puts it at 9-13 %, against a hard
            // core of 4-5 %, which is requirement A's 3-6 % core and ~10 %
            // bloom. Measured with tools/sn_flash.py, not chosen by eye.
            e.flash = 0.5 * sample("flashShortSide", [0.08, 0.12], 0, 0.6, 23) * shortSide;
            e.shell = 0.5 * sample("shellShortSide", [0.25, 0.40], 0, 0.6, 11) * shortSide;
            e.shellGain = value("shellGain", 0.55, 0.80);
            e.spikeGain = value("spikeGain", 0.55, 1.5);
            e.filaments = value("filaments", 0.70, 1.5);
            e.remnantGain = value("remnantGain", 0.26, 0.40);
            // v11 remnant structure. Every one of these is a share, and every
            // one of them came off a reference rather than off a slider:
            // `cavities` is how much of the body the dark bubbles eat (the JWST
            // frame's interior is mostly holes), `dustOpacity` how hard the
            // grey-brown sheets extinct the stars behind them, `knotGain` the
            // isolated blue-white knots along the rim, `wispGain` the red outer
            // wisps beyond it, and the jet is the pair of lobes both references
            // have shooting out of the rim, measured in remnant radii.
            e.cavities = value("cavities", 0.80, 1);
            e.dustOpacity = value("dustOpacity", 0.55, 1);
            e.knotGain = value("knotGain", 0.55, 2);
            e.wispGain = value("wispGain", 0.30, 1.5);
            e.jetGain = value("jetGain", 0.34, 1.5);
            e.jetReach = clamp(cfg.jetReach === undefined ? 1.30 : cfg.jetReach, 0, 3);
            e.jetWidth = clamp(cfg.jetWidth === undefined ? 0.10 : cfg.jetWidth, 0.01, 1);
            e.pulsarGain = value("pulsarGain", 0.30, 0.60);
            e.pulsarPeriod = Math.max(0.8, clamp(cfg.pulsarPeriodSec === undefined ? 1.4 : cfg.pulsarPeriodSec, 0, 60));
            // Birth-frozen orientation for the diffraction spikes and the
            // filament web, so two supernovae never break the same way.
            e.spin = (random(index, salt + 25) * 2 - 1) * Math.PI;
            // Where the far layer's streamline was when this was captured. See
            // supernovaSite(): the site travels with the far dust in the camera
            // regime and is fixed with the hole on, exactly as the far field is.
            e.camFlow = _state.camFlow === undefined ? 0 : _state.camFlow;
            const share = clamp(cfg.hypernovaShare === undefined ? 0.15 : cfg.hypernovaShare, 0, 1);
            const cooldown = Math.max(600, Math.min(604800, Number(cfg.hypernovaCooldownSec) || 10800));
            const last = _state.familyLast.hypernova === undefined ? -1e12 : _state.familyLast.hypernova;
            e.hyper = random(index, salt + 17) < share && start - last >= cooldown;
            e.gain = e.hyper ? value("hypernovaGain", 1.60, 1.60) : value("gain", 1.35, 1.35);
            if (e.hyper) {
                e.flash *= 1.25;
                e.shell *= 1.20;
            }
            // The physics colours. `e.colour` (the palette-mixed one) stays the
            // PRECURSOR's, because that phase is a star and a star is where his
            // palette belongs; the collapse, the shock and the remnant are what
            // the temperature says they are.
            e.peakColour = e.hyper ? [0.78, 0.87, 1] : [0.84, 0.90, 1];
            e.precursorColour = [1, 0.66, 0.45];
            e.shellWarm = [1, 0.92, 0.60];
            e.shellCool = [1, 0.46, 0.28];
            // v12. The palette is MEASURED off his reference rather than
            // chosen. `tools/sn_reference.py --palette` clusters the lit
            // interior of reference/sa0225Mosk01.jpg six ways in linear light,
            // each pixel normalised to its own peak so tone is separated from
            // brightness, and returns these six with these area shares. They
            // are ordered INSIDE -> OUT, which is what lets one 1-D schedule
            // carry both the radial structure and the time turnover.
            //
            //   0 iron, magenta-violet      15.8 % of the lit area
            //   1 bulk ejecta, blue         25.9 %   the largest population
            //   2 shocked sheets, cyan      15.0 %
            //   3 blast wave, blue-white    15.6 %   31.5 % of the ENERGY
            //   4 calcium/sulphur, yellow    8.1 %   the knot clusters
            //   5 silicon, crimson          19.5 %   wisps and both jets
            //
            // The .w is the population's DUST FRACTION: how much of a grain of
            // it absorbs rather than emits. Iron and bulk ejecta are the cold,
            // dense, absorbing material; the blast wave is nearly pure
            // emission. That is what makes the near slices eat the far ones
            // instead of all four just adding up.
            //
            // v11's four tones (blue-white knots, orange rim, red wisps,
            // grey-brown dust) were fitted to the JWST infrared frame. He is
            // pointing at the CHANDRA composite, and the two disagree about the
            // one thing that matters: measured, the Chandra frame's colour walk
            // runs -0.50 -0.10 -0.17 -0.18 -0.11 +0.01 in (R-B)/(R+B) from
            // centre to rim -- blue nearly all the way out -- and v11 scored
            // -0.13 -0.06 +0.05 +0.08 +0.10 +0.20, which is the same walk with
            // the sign flipped. It was red where the reference is blue.
            // The second measured number, and it is the one that stops six
            // tones reading as one grey average: each population's share of the
            // lit ENERGY divided by its share of the lit AREA. The blast wave
            // is 31.5 % of the light on 15.6 % of the picture and the bulk
            // ejecta is 14.7 % on 25.9 %, so one is nearly FOUR TIMES the
            // surface brightness of the other. A palette of six equally bright
            // tones is a plaid; this is why the reference has bright white and
            // cyan SHEETS standing out of a dim violet and crimson body. The
            // emissivity is folded into the rgb rather than carried in a fifth
            // component, which is free and leaves the hue untouched (scaling
            // all three channels is a brightness, not a colour).
            const emis = [0.56, 0.57, 1.39, 2.02, 1.62, 0.56];
            const tones = [
                [0.931, 0.361, 1.000, 0.55],
                [0.153, 0.343, 1.000, 0.62],
                [0.446, 0.694, 1.000, 0.30],
                [0.861, 0.883, 1.000, 0.10],
                [1.000, 0.957, 0.316, 0.18],
                [1.000, 0.174, 0.302, 0.40]
            ];
            e.pops = tones.map((p, i) => [p[0] * emis[i], p[1] * emis[i], p[2] * emis[i], p[3]]);
            // The non-grain terms read the same palette, so the front, the
            // wisps and the knots can never disagree with the gas: the shock
            // front is the blast wave (3), the rim tone the shocked sheets (2),
            // the wisps silicon (5) and the dust the cold bulk ejecta (1),
            // darkened, because the reference's obscuring material is BLUE and
            // v11's was grey-brown.
            e.remnantHot = tones[3].slice(0, 3);
            e.remnantTone = tones[2].slice(0, 3);
            e.remnantWisp = tones[5].slice(0, 3);
            e.remnantDust = [0.16, 0.19, 0.34];
            // ---- the grain field's own dials --------------------------------
            // `grainGain` is the gas's brightness; `grainCells` how many cells
            // fit in one remnant radius, which with one grain per cell and four
            // slices is the grain COUNT (see STARFIELD.md for the arithmetic);
            // `grainLifeSec` how long a grain lives, which is also how far the
            // one-step advection is ever asked to carry it; `grainSize` its
            // radius in cells, held under 0.5 so the shader's 3x3 neighbourhood
            // is exact.
            // The cell COUNT is free: every pixel walks the same 3x3
            // neighbourhood whatever the lattice pitch is, so raising this
            // makes more and finer grains at exactly the same cost. What it is
            // really bounded by is the screen -- at 30 cells per remnant radius
            // a cell is R/30 px across, which on his 3440x1440 is about 9 px,
            // and a grain of 0.28 cells is 2.5 px. Below about two pixels a
            // grain starts aliasing into sparkle instead of reading as a knot.
            e.grainGain = value("grainGain", 1.05, 3);
            e.grainCells = Math.max(4, clamp(cfg.grainCells === undefined ? 20 : cfg.grainCells, 4, 64));
            e.grainLife = Math.max(1.5, clamp(cfg.grainLifeSec === undefined ? 7.5 : cfg.grainLifeSec, 1.5, 60));
            e.grainSize = clamp(cfg.grainSize === undefined ? 0.44 : cfg.grainSize, 0.10, 0.50);
            e.grainOpacity = value("grainOpacity", 0.42, 1);
            // The wind. `curlAmp` is in CELLS and is what bounds the 3x3
            // neighbourhood, so it is hard-capped at 0.5 rather than validated
            // into a range: above that the shader would start missing grains
            // and the gas would sparkle at cell boundaries.
            e.curlAmp = clamp(cfg.curlAmp === undefined ? 0.44 : cfg.curlAmp, 0, 0.5);
            e.curlScale = Math.max(0.5, clamp(cfg.curlScale === undefined ? 3.1 : cfg.curlScale, 0.5, 12));
            e.parallax = clamp(cfg.parallax === undefined ? 0.17 : cfg.parallax, 0, 0.5);
            // How many populations are being born at one instant. 1.5 means a
            // grain's index is its schedule position give or take three
            // quarters of a step, so two adjacent tones are always in the air
            // and a third appears at the crossings -- the MIXTURE he asked for.
            // 0 would make the cloud one pure tone that steps; the shader's
            // four-wide window is sized for 1.5 and test-particles asserts the
            // window never clips.
            e.toneSpread = clamp(cfg.toneSpread === undefined ? 1.5 : cfg.toneSpread, 0, 2.2);
            e.sheetGain = value("sheetGain", 0.30, 1.2);
            // How far the inverted-layer plume pulls the schedule back toward
            // iron at large radius, in populations. 0 turns the feature off.
            e.plume = clamp(cfg.plume === undefined ? 2.3 : cfg.plume, 0, 4);
        } else if (kind === 9) {
            // A pulsar MODULATES; the validator floors (period >= 0.8 s, trough
            // >= 0.5 of peak, edge >= 0.10 s) make a square blink unreachable.
            e.gain = value("gain", 0.70, 0.70);
            e.duration = sample("durationSec", [120, 260], 10, 1800, 3);
            e.period = Math.max(0.8, sample("periodSec", [0.9, 2.2], 0, 600, 5));
            e.floor = Math.max(0.5, clamp(cfg.floorFraction === undefined ? 0.55 : cfg.floorFraction, 0, 1));
            e.edge = Math.max(0.10, clamp(cfg.edgeSec === undefined ? 0.14 : cfg.edgeSec, 0, 600));
        } else if (kind === 10) {
            // Kilonova: a hot white flash, then one ring that expands and
            // reddens through the r-process colour as it goes.
            e.gain = value("gain", 1.10, 1.10);
            e.flash = Math.max(0.35, clamp(cfg.flashSec === undefined ? 0.6 : cfg.flashSec, 0, 5));
            e.ringSpan = sample("ringSec", [8, 15], 1, 120, 3);
            e.duration = e.flash + e.ringSpan;
            e.ring = clamp(cfg.ringShortSide === undefined ? 0.05 : cfg.ringShortSide, 0, 0.25) * shortSide;
            e.ringGain = value("ringGain", 0.34, 0.40);
            e.coolColour = [1, 0.62, 0.42];
            e.peakColour = [0.90, 0.95, 1];
        } else {
            // Gamma-ray burst: a hard point with two opposed beams (shader
            // style 4), then a long afterglow point. The rise is eased over
            // riseSec so a sub-second peak never arrives as a single frame.
            e.gain = value("gain", 1.00, 1.00);
            e.rise = Math.max(0.35, sample("riseSec", [0.4, 0.7], 0, 30, 3));
            e.flash = sample("flashSec", [0.5, 0.8], 0.1, 5, 5);
            e.afterglow = sample("afterglowSec", [30, 90], 1, 600, 7);
            e.duration = e.rise + e.flash + e.afterglow;
            e.beam = sample("beamShortSide", [0.10, 0.18], 0, 0.25, 9) * shortSide;
            e.beamWidth = Math.max(2, e.beam * 0.055);
            e.beamGain = value("beamGain", 0.42, 0.50);
            const a = random(index, salt + 11) * Math.PI;
            e.beamDir = [Math.cos(a), Math.sin(a)];
            e.peakColour = [0.80, 0.88, 1];
        }
        return e;
    }

    // Schedule key, default range, bounds and unit per radial kind, so both
    // scheduleRadial and the documentation read from one table.
    function radialSchedule(kind: int): var {
        const minutes = (range) => ({
            key: "everyMinutes",
            range: range,
            low: 1,
            high: 1440,
            unit: 60
        });
        const hours = (range) => ({
            key: "everyHours",
            range: range,
            low: 0.1,
            high: 168,
            unit: 3600
        });
        return kind === 5 ? minutes([8, 16]) : kind === 6 ? minutes([6, 13]) : kind === 7 ? minutes([18, 34]) : kind === 8 ? hours([0.35, 0.8]) : kind === 9 ? hours([0.5, 1.1]) : kind === 10 ? hours([0.6, 1.4]) : hours([0.7, 1.8]);
    }

    // Dramatic families share one cooldown, so the sky never stacks two of them.
    function dramatic(kind: int): bool {
        return kind === 8 || kind === 10 || kind === 11;
    }

    // One master dial on every interval in the catalogue. 1 is the shipped
    // cadence, 2 is twice as many, 0 turns scheduled events off entirely.
    function rateScale(): real {
        const raw = Number((eventFamilies || {}).rateScale);
        return Number.isFinite(raw) ? clamp(raw, 0, 4) : 1;
    }

    function scheduleRadial(kind: int): var {
        const s = _state;
        if (!eventEnabled(kind))
            return null;
        const rate = rateScale();
        if (rate <= 0)
            return null;
        const index = s.eventIds[kind]++;
        const warm = !s.events[kind] && !s.firstEpisode[kind];
        const cfg = eventConfig(kind);
        const salt = screenSeed + 5501 + kind * 907;
        const fallback = radialSchedule(kind);
        let range = parameterRange(cfg, fallback.key, fallback.range, fallback.low, fallback.high).map(x => x * fallback.unit);
        range = [range[0] / rate, range[1] / rate];
        const interval = range[0] + (range[1] - range[0]) * random(index, salt);
        let start = Math.max(s.clock, warmStart(kind, index, range[0], interval));
        if (dramatic(kind)) {
            const cooldown = clamp(Number((eventFamilies || {}).dramaCooldownSec) || 1500, 300, 86400) / rate;
            const last = s.familyLast.drama === undefined ? -1e12 : s.familyLast.drama;
            start = Math.max(start, last + cooldown);
        }
        const e = captureRadial(kind, index, start);
        if (!e)
            return null;
        s.firstEpisode[kind] = true;
        // Phenomena reserve against each other only: the transient heads are a
        // separate class and must never be pushed around by a six-minute
        // remnant, which is the whole reason for the split. Reservation allows
        // exactly `phenomenonCap` to overlap, so a slot is used but no episode
        // is ever scheduled into a slot that cannot exist — a phenomenon that
        // lost a slot mid-life would pop.
        const cap = Math.round(clamp(Number((eventFamilies || {}).phenomenonCap) || phenomenonSlotCount, 1, phenomenonSlotCount));
        // v9: a WARM-STARTED DRAMATIC episode reserves on INSTANT occupancy
        // instead. The rule above is conservative — it counts every episode that
        // overlaps anywhere in the new one's life, not the ones alive at its
        // moment — and star birth, nova and red giant are scheduled first
        // (publishEvents walks the kinds in order) and are long, so at a cold
        // start all three usually straddled the supernova's four-minute window
        // and pushed it past the very cap the warm start exists to enforce.
        // Slot ownership is sticky and claimed in the first second, so a free
        // slot AT THE START is all a phenomenon actually needs; anything that
        // collides later is retired and rescheduled by publishPhenomena, which
        // is the mechanism that already exists for exactly that.
        const instant = warm && dramatic(kind);
        for (let pass = 0; pass < 6; ++pass) {
            const ends = [];
            for (let k = 5; k < s.events.length; ++k) {
                const other = s.events[k];
                if (k === kind || !other)
                    continue;
                const overlaps = instant ? other.start <= start && start < other.start + other.duration
                    : start < other.start + other.duration && start + e.duration > other.start;
                if (overlaps)
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

    function mixColour(a: var, b: var, t: real): var {
        const k = clamp(t, 0, 1);
        return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
    }

    // ---- v9 SUPERNOVA -------------------------------------------------------
    // WHERE IT IS. Every other phenomenon is nailed to the pixel it was placed
    // on. In the camera regime that makes the supernova the one thing on the
    // screen that is not moving while the field streams past it, so it travels
    // on the FAR layer's own streamline: it is the most distant object on the
    // sky and the far layer is where a supernova belongs.
    //
    // The far field advances at a constant rate in u = (r/R)^2/2 (the shader's
    // `radialCoordinates`), and the grid's own cell factor invU cancels between
    // `advanceCells` and u, so the motion is exactly
    //     u(t) = u0 - (camFlow(t) - camFlow(capture)) * (6/1080) * 0.10
    // with r = R*sqrt(2u). That reverses with `motion.camera.direction`, freezes
    // with `speed` 0 and slows as 1/r with radius, because it IS the far layer's
    // motion rather than a copy of it. `camFlow` carries the regime blend, so
    // with the hole on the site is fixed exactly as it has always been and the
    // 30 s crossfade eases the drift in without a step.
    //
    // It does NOT scale with the drift. That flow is area-preserving - it
    // stretches a patch tangentially by r'/r and squashes it radially by r/r' -
    // so its isotropic magnification is exactly 1, and the remnant's apparent
    // size is its own expansion, which is the truth for a source that far away.
    // The particles' z/z' perspective was the other candidate and it cannot
    // carry a life cycle at all: at the shipped speed 6 and depth 16 the camera
    // crosses the whole depth in 60 active seconds, so a 3-D-anchored event
    // would leave the screen before its shell finished, let alone its remnant.
    function supernovaSite(e: var): var {
        // v10. The supernova IS a star: `e.site` is that particle's live
        // position, written every frame by supernovaParticles() and latched to
        // the debris anchor once the star has been consumed. The far-layer
        // drift below is what a supernova with no particle behind it still
        // does -- the offscreen sweeps, a pool that could not spare a star, and
        // particlesEnabled false all land there.
        if (e.site)
            return e.site;
        const s = _state;
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const R = Math.min(w, h) / 2;
        // The shared wander enters the far layer at the layer's own depth, 0.10,
        // exactly as stars() applies it for layer 0.
        const cx = w * 0.5 + shader.centreOffset.x * 0.10;
        const cy = h * 0.5 + shader.centreOffset.y * 0.10;
        const flow = (s.camFlow === undefined ? 0 : s.camFlow) - (e.camFlow === undefined ? 0 : e.camFlow);
        const dx = e.x - cx, dy = e.y - cy;
        const r0 = Math.hypot(dx, dy);
        if (!flow || r0 < 1e-3)
            return [e.x, e.y];
        const q0 = r0 / R;
        const u = 0.5 * q0 * q0 - flow * (6 / 1080) * 0.10;
        if (!(u > 1e-9))
            return [cx, cy];
        const r = R * Math.sqrt(2 * u);
        return [cx + dx * r / r0, cy + dy * r / r0];
    }

    // The whole life cycle, on shader style 6 (`supernovaField`). The CPU owns
    // every envelope, every radius and every colour; the shader owns the
    // structure - the filament web, the diffraction spikes, the rim brightening
    // and the advected turbulence. Five phases share one continuous set of
    // channels, and every handover is a crossfade in EVERY channel rather than
    // only in the total, so no frame of it is a cut:
    //   head    = (x, y, coreSigmaPx, peak)
    //   colour  = (r, g, b, 6)                       the phase's primary colour
    //   tail01  = (haloSigmaPx, haloGain, coreGain, shellGain)
    //   shape   = (shellRadiusPx, shellWidthPx, filamentAmp, toneWeight)
    // plus four vectors of its own, because one supernova is alive at a time
    // (the dramatic cooldown is 900 s against a ~290 s life) and a phenomenon
    // slot's five vectors cannot carry a flash, a shock and a nebula at once:
    //   snRemnant = (siteX, siteY, radiusPx, bodyGain)   the remnant's own frame
    //   snTone    = (rimR, rimG, rimB, turbulencePhase)
    //   snShell   = (shockRadiusPx, shockGain, shockWidthPx, innerGain)
    //   snExtra   = (spikeGain, spikeLengthPx, pulsarGain, seedAngle)
    // Every gain except the sky lift is a FRACTION of head.w, the same
    // convention style 3 uses, so one multiply in the shader reproduces them.
    function supernovaState(e: var, age: real): var {
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const flashAt = e.precursor + e.rise, flashEnd = flashAt + e.hold;
        const site = supernovaSite(e);
        // The precursor's ceiling, and the level the collapse rises FROM. Every
        // gain in this file is in DISPLAY units, not linear: main() decodes the
        // event sum before adding it to the linear sky, so 0.95 is the 243/255
        // an ordinary bright star renders at and 1.35 is a clipped white core.
        const base = e.gain * 0.50;
        let core = e.core, halo = 0, coreAbs = 0, haloAbs = 0;
        let shellR = 0, shellW = 0, shellAbs = 0, innerR = 0, innerAbs = 0;
        // v11. The remnant's radius is the COMOVING FRAME the whole gas layer is
        // drawn in, and it has to move with the material: v10 held the filament
        // field still at a fixed radius because it was pretending to be the
        // ambient medium lit up by a passing shock, and the result was a frozen
        // picture with the sky streaming past it -- "this part looks flat: the
        // cloud of the supernova is static and not moving with the rest". The
        // ejecta expands homologously as t^0.4, so this does too, with a floor
        // so the noise coordinate is never sampled at a degenerate scale in the
        // first frames, and a slow creep through the remnant phase after that.
        let nebulaR = 0, nebulaAbs = 0, pulsarAbs = 0, spikeAbs = 0, spikeLen = 0;
        let filaments = 0, tone = 0, remnantV = 0;
        // v12: the remnant's own 0..1 envelope, and the span it runs over. Both
        // were local to the remnant branch; the grain schedule needs them at
        // this level, and there is one copy of each so the grains and the gas
        // can never be on two different clocks.
        let remnantEnv = 0, remnantSpanSec = 0.4 * e.shellSpan + e.remnant;
        let colour = e.colour, second = e.peakColour;
        // v10: the shell's clock starts at the DETONATION, not at the end of
        // the flash. The shock leaves when the star explodes -- that is the
        // same instant spawnBurst puts the debris on the field, and
        // supernovaParticles drives the shock front from this same `u` -- so
        // the rim and its own material cannot be two seconds apart. They were:
        // measured 26 px of rim against 78 px of debris at t+16 s, and the
        // shell also stepped 0.27 in one frame when it appeared mid-flight at
        // the end of the flash instead of growing out of the star.
        const shockU = clamp((age - e.precursor) / Math.max(0.001, e.shellSpan), 0, 1);
        if (age < e.precursor) {
            // 1. PRECURSOR (10-20 s). The star that is about to die brightens,
            // reddens and pulses FASTER. The pulse phase is the integral of
            // 1/period, so the period can shorten without the pulse ever
            // jumping, and its amplitude eases to nothing over the last 1.5 s:
            // a swing left mid-stroke when the collapse takes over would be a
            // step, and 0.9 s is the shortest period, above the 0.8 s floor.
            // The field's own stars cannot be addressed individually (they are
            // a procedural hash grid), so this star is DRAWN at the site the
            // shell will use - it is the same object, one phase earlier.
            const t = clamp(age / Math.max(0.001, e.precursor), 0, 1);
            const T0 = 3.2, T1 = 1.0;
            const phase = 2 * Math.PI * (e.precursor / (T1 - T0)) * Math.log((T0 + (T1 - T0) * t) / T0);
            const pulse = 1 + (0.15 + 0.30 * t) * ease((e.precursor - age) / 1.5) * Math.sin(phase);
            const env = base * (0.55 + 0.45 * t * t) * pulse * ease(age / 2.5);
            core = e.core * (0.9 + 0.5 * t);
            halo = e.core * (2.4 + 2.2 * t);
            coreAbs = env * 0.69;
            haloAbs = env * 0.31;
            colour = mixColour(e.colour, e.precursorColour, ease(t));
            // v10. When the precursor is a real particle the PARTICLE is the
            // star: Appearance.render swells it, brightens it and walks it red
            // then blue-white, on its own pulse, moving with the regime. The
            // sprite keeps only the halo it casts, because two cores drawn on
            // the same pixel is one star too many -- and the sprite's is the
            // one that "fades in", which is exactly what he objected to
            // (ledger 2285: "it should first be a star and then explode").
            if (e.hasStar) {
                coreAbs = 0;
                core = e.core * 0.25;
                haloAbs = env * 0.34;
                halo = e.core * (1.8 + 3.4 * t);
            }
        } else if (age < flashEnd) {
            // 2. CORE COLLAPSE (0.5-1.5 s). A hard white-blue flash. The rise is
            // >= 0.8 s and eased, the core/halo split and both sigmas ease with
            // it from exactly where the precursor left them, and the sky lift
            // below is what makes it read as light arriving rather than as a
            // bright dot appearing.
            const k = ease((age - e.precursor) / e.rise);
            const env = base + (e.gain - base) * k;
            core = e.core * (1.4 + 2.2 * k);
            // sigma = flash/1.6 is what puts the disc's 64/255 contour at
            // exactly `flashShortSide` across: a Gaussian at 0.89 display units
            // falls to 0.25 at 1.594 sigma.
            halo = e.core * 4.6 + (e.flash / 1.6 - e.core * 4.6) * k;
            coreAbs = env * (0.69 - 0.35 * k);
            haloAbs = env * (0.31 + 0.35 * k);
            colour = mixColour(e.precursorColour, e.peakColour, k);
        } else {
            // 3/4. The core fades into the shock over `decaySec`, its bloom
            // shrinking back to a point, while the shell leaves and the remnant
            // grows out of it.
            const d = age - flashEnd;
            const fade = Math.exp(-3 * d / Math.max(0.001, e.decay));
            const k = ease(d / Math.max(0.001, e.decay * 0.8));
            core = e.core * (3.6 - 2.4 * k);
            // v11: the bloom's SIZE collapses in under half a second while its
            // LIGHT still fades over `decay`. It used to shrink on the decay's
            // own clock (25-60 s), which left a disc a tenth of the short side
            // across parked on the screen for half a minute -- the part of "my
            // screen flashes during the explosion" that would have survived
            // deleting the sky lift. The photosphere of a real collapse shrinks
            // too, so this is the honest envelope as well as the quieter one.
            const kh = ease(d / 0.45);
            halo = (e.flash / 1.6) * (1 - kh) + e.core * 4.5 * kh;
            coreAbs = e.gain * fade * 0.34;
            haloAbs = e.gain * fade * 0.66;
            colour = e.peakColour;
            const u = shockU;
            if (u > 0) {
                colour = mixColour(mixColour(e.peakColour, e.shellWarm, ease(u / 0.40)), e.shellCool, ease((u - 0.35) / 0.65));
                second = mixColour(e.peakColour, e.remnantTone, ease((u - 0.55) / 0.40));
            }
            // 4. REMNANT (2-5 min). It grows out of the shell's last 40 % rather
            // than replacing it, so there is no moment where one ends: a faint
            // two-tone filament web, slowly advected, with the neutron star the
            // collapse left behind blinking at the centre. The blink obeys the
            // pulsar family's own floors - period >= 0.8 s, trough >= 0.55 of
            // peak - so it modulates instead of flashing.
            const remnantAt = e.precursor + 0.6 * e.shellSpan;
            const rv = clamp((age - remnantAt) / Math.max(0.001, remnantSpanSec), 0, 1);
            remnantV = rv;
            if (rv > 0) {
                remnantEnv = ease(rv / 0.16) * ease((1 - rv) / 0.55);
                nebulaAbs = e.remnantGain * remnantEnv;
                const turn = modulo(d, e.pulsarPeriod) / e.pulsarPeriod;
                pulsarAbs = e.pulsarGain * (0.55 + 0.45 * (0.5 - 0.5 * Math.cos(2 * Math.PI * turn)))
                    * ease(rv / 0.08) * ease((1 - rv) / 0.60);
                filaments = Math.max(filaments, e.filaments);
                tone = ease(rv / 0.20);
                colour = mixColour(colour, e.remnantHot, ease((rv - 0.05) / 0.35));
                second = mixColour(second, e.remnantTone, ease(rv / 0.30));
            }
        }
        // 3. SHELL (30-90 s). Sedov-Taylor: a blast wave into a uniform medium
        // decelerates as r ~ t^0.4, which is the whole reason it reads as an
        // explosion slowing down rather than a ring being scaled up. It
        // broadens and breaks into filaments as it ages, cools white -> yellow
        // -> orange-red, and carries a hotter, narrower inner rim that dies
        // sooner than the front does. Outside the phase chain because it starts
        // UNDER the flash and has to grow continuously out of nothing.
        if (shockU > 0) {
            shellR = e.shell * Math.pow(shockU, 0.4);
            shellW = Math.max(2, e.shell * 0.030 * (1 + 3.4 * shockU));
            shellAbs = e.shellGain * ease(shockU / 0.05) * Math.pow(1 - shockU, 1.1);
            innerR = shellR * 0.66;
            innerAbs = e.shellGain * 0.50 * ease(shockU / 0.05) * Math.pow(1 - shockU, 2.4);
            filaments = Math.max(filaments, e.filaments * ease(shockU / 0.35));
        }
        // The comoving frame's radius: the material's own t^0.4 expansion, a
        // floor of 0.34 of the shell so the first frames do not sample the noise
        // at a degenerate scale, and a 40 % creep once the remnant is the thing
        // on the screen. Published every frame the episode is alive, because the
        // shock is drawn in this frame too.
        nebulaR = e.shell * Math.max(0.34, Math.pow(Math.max(shockU, 0.02), 0.4)) * (1 + 0.40 * remnantV);
        // The spikes belong to the collapse alone. v11 deleted the SKY LIFT that
        // used to be computed beside them: it was an absolute gain main() used
        // to multiply every pixel of the screen by, and it is the thing he
        // objected to (ledger 2286). Nothing global replaces it; the diffraction
        // spikes are the only part of the collapse that reaches past the bloom,
        // and they are inside the slot's own `bounds` box like everything else.
        if (age >= e.precursor && age < flashEnd + 2.5) {
            const rising = ease((age - e.precursor) / e.rise);
            const falling = age < flashEnd ? 1 : ease((flashEnd + 2.5 - age) / 2.5);
            spikeAbs = e.gain * e.spikeGain * 0.45 * rising * falling;
            spikeLen = e.flash * 2.6;
        }
        const peak = Math.max(Math.max(coreAbs + haloAbs, spikeAbs), Math.max(shellAbs + innerAbs, nebulaAbs + pulsarAbs));
        if (peak <= 0.0004)
            return {
                head: [0, 0, 0, 0],
                colour: [0, 0, 0, 3],
                tail01: [0, 0, 0, 0],
                shape: [0, 0, 0, 0],
                bounds: [0, 0, 0, 0],
                exempt: 0
            };
        // The BOUNDS box is the events slot's own -- the point sources only,
        // since v11 moved the distributed half into the far layer, which
        // rejects on its own circle (supernovaRemnant's `bound`). shellR is
        // still in it because the harnesses and the sheets read shape.xy.
        // It has to cover the FAR-LAYER kernel's own bound too, or the box is
        // not the honest envelope of the episode: supernovaRemnant rejects at
        // max(1.38 R, shockR + 4 shockW) and breaks its shock radius by up to
        // +25 % with the same noise that ragged the rim. Measured before this
        // line covered it: 9 pixels at 1.6/255 outside the published box, which
        // is nothing to look at and everything to a test that says "nothing".
        const reach = Math.max(Math.max(nebulaR * 1.38, shellR * 1.25 + 4 * shellW),
            Math.max(Math.max(3.6 * halo, 6 * core), spikeAbs > 0 ? spikeLen * 1.05 : 0));
        // v11: the jets' 3-D axis, frozen at capture, and the frame the remnant
        // kernel rotates into. supernovaParticles launches the particle jets on
        // the SAME angle, so the drawn lobes and the material inside them are
        // one object rather than two that happen to overlap.
        const jetAngle = e.spin * 0.5;
        // Display -> linear for everything that now composites into the far
        // field. The shell dial is a display-unit number and always has been.
        const shellLin = linearGain(shellAbs);
        const innerLin = linearGain(innerAbs);
        // 0.34 is a CALIBRATION, not taste: it is what puts the drawn remnant's
        // 99th linear percentile at the `remnantGain` dial, the same way the
        // nebula passage's 0.36 does (tools/nebula_sheet.py established that
        // method; tools/sn_reference.py measures this one).
        const bodyLin = linearGain(nebulaAbs) * 0.34;
        // ---- v12: THE REVERSE SHOCK, AND THE TURNOVER IT DRIVES ------------
        // Cas A is ~350 years old and has NOT finished exploding: its reverse
        // shock is still walking inward through the ejecta in the material's
        // own frame at 1150-1300 km/s over most of the rim, and in the west it
        // moves inward in the OBSERVER's frame too (-1884 +- 17 km/s, Vink et
        // al. 2022). Each layer it reaches is heated and ionised, and lights up
        // in its own element's colour. So the physical answer to "the colour
        // change should be new particles of a new tone appearing" is: the wave
        // starts at the rim and travels IN, and a grain born behind it is born
        // with the new tone while the old grains in front of it die on their
        // own lifetimes. That is one mechanism for his complaint and for the
        // object, and it is why this is a radius walking inward and not a clock.
        //
        // `shockRadiusU` starts outside everything (1.30, nothing swept) and
        // ends inside the core (0.10). `shockRateU` is its speed, which the
        // shader needs because it is the only way a stateless grain can know
        // what the birth-rate distribution looked like when it was born.
        const shockRadiusU = 1.30 - 1.20 * remnantV;
        const shockRateU = 1.20 / Math.max(0.001, remnantSpanSec);
        // The schedule's two halves. `posSpan` is the RADIAL walk across the
        // six populations at a fixed time -- deliberately under two populations
        // wide, because the reference's own radial colour walk is muted
        // (measured -0.50 -0.10 -0.17 -0.18 -0.11 +0.01) even though its local
        // chroma is high: it is not a rainbow disc, it is a blue object with
        // warm knots in it. `toneAdvance` is how far swept material moves along
        // the sequence, and it is the bigger of the two, because the TURNOVER
        // is the thing he asked for.
        //
        // Together they make the object walk, over one episode, from a violet
        // and blue cold-ejecta cloud (nothing swept) through the reference's
        // own mid-life picture -- blue-violet interior, blue-white sheets and
        // yellow knots at the limb, crimson beyond it -- to a fully swept,
        // warm-ended remnant. Every step of that is population turnover; no
        // grain's hue ever moves.
        const posLo = 0;
        const posSpan = 1.7;
        const toneAdvance = 2.9;
        // 1.35 is a CALIBRATION in the same family as the body's 0.34 and the
        // nebula passage's 0.36: it is what puts the drawn GAS's 99th linear
        // percentile at the `grainGain` dial, measured with
        // tools/sn_reference.py --brightness rather than chosen by eye. The
        // grains carry their own one because they are their own layer now.
        const grainAbs = linearGain(nebulaAbs) * e.grainGain * 5.40;
        return {
            head: [site[0], site[1], core, peak],
            colour: colour.concat(6),
            tail01: [halo, haloAbs / peak, coreAbs / peak, shellAbs / peak],
            shape: [shellR, shellW, filaments, tone],
            bounds: [site[0] - reach, site[1] - reach, site[0] + reach, site[1] + reach],
            // The flash spends its gain outside the combined phenomenon cap and
            // eases back inside it over three seconds, as it always has.
            exempt: ease((flashEnd + 3 - age) / 3),
            extras: {
                // v11. This vector used to be the sky lift's gain and radius.
                // It is now the remnant's own frame: where it is, how big it is
                // and how bright its body is. Nothing in it reaches a pixel
                // outside 1.38 of `radiusPx`, which is the whole difference.
                remnant: [site[0], site[1], nebulaR, bodyLin],
                // The advection phase is the episode's own age and is NEVER
                // wrapped: it indexes a noise field, where a wrap is a jump. An
                // episode is bounded well under 2000 s, so 0.05 * age stays
                // inside 100 and float32 carries it to five decimal places.
                tone: second.concat(age * 0.05),
                // v11: the SHOCK's own geometry. It was (innerR, innerGain,
                // nebulaR, nebulaGain); the remnant took its own vector, so this
                // is the front the far layer draws.
                shell: [shellR, shellLin, shellW, innerLin],
                extra: [spikeAbs / peak, spikeLen, pulsarAbs / peak, e.spin],
                // hollowFrac: the shell is thin while the shock is young and
                // thickens as the ejecta fills in behind it, which is the
                // difference between a ring and a filled sphere at each end of
                // the life cycle. cavityGain and dustOpacity are constants he
                // can reach through the config if he ever wants to.
                body: [0.84 - 0.12 * remnantV, e.cavities, e.filaments, e.dustOpacity],
                hot: e.remnantHot.concat(e.knotGain),
                wisp: e.remnantWisp.concat(e.wispGain * (0.25 + 0.75 * ease(shockU / 0.25))),
                dust: e.remnantDust.concat(e.jetGain * ease(shockU / 0.18)),
                jet: [Math.cos(jetAngle), Math.sin(jetAngle), e.jetReach, e.jetWidth],
                // ---- v12: the grain populations and their schedule ---------
                pop0: e.pops[0], pop1: e.pops[1], pop2: e.pops[2],
                pop3: e.pops[3], pop4: e.pops[4], pop5: e.pops[5],
                grain: [grainAbs, e.grainCells, e.grainLife, e.grainSize],
                flow: [e.curlAmp, e.curlScale, e.plume, e.toneSpread],
                turn: [posLo, posSpan, shockRadiusU, toneAdvance],
                turn2: [shockRateU, e.sheetGain, e.grainOpacity * remnantEnv, e.parallax]
            }
        };
    }

    // ---- v10: the supernova is a star that explodes -------------------------
    // His question (ledger 2285): "isn't a supernova an exploded star? So it
    // should first be a star and then explode, not just fade in and then out."
    // It should, and now it does. This is the whole state machine, and it is
    // the ONLY part of the episode with side effects: supernovaState() stays a
    // pure function of (episode, age) so the offscreen sheets can still sweep
    // it, and everything here writes into the episode (`site`, `hasStar`) which
    // that function reads back.
    //
    //   1. arrival     pick a real, visible, near particle and mark it. The
    //                  precursor is shortened against the MEASURED field speed:
    //                  how long a star can be held on the screen is a property
    //                  of the regime, not a wish, and with the hole on the
    //                  field crosses the screen in a few seconds.
    //   2. precursor   `e.site` follows that particle every frame. It swells,
    //                  brightens, reddens then whitens and pulses faster --
    //                  all of it in Appearance.render, on the particle itself.
    //   3. detonation  the star is REMOVED and replaced, on one frame, by:
    //                  150-400 debris particles (spawnBurst), an expanding
    //                  shock that shoves the neighbours outward as it reaches
    //                  them (applyImpulse 'front'), a luminosity lift on the
    //                  neighbourhood (brightenNear), and the flash and sky lift
    //                  the sprite already had.
    //   4. after       an invisible anchor particle carries the site, so the
    //                  shell rim and the remnant ride exactly the same camera
    //                  projection their own debris does.
    function supernovaShellReach(e: var): real {
        return e.shell;
    }
    // v11. The remnant is drawn into the FAR FIELD now, which is linear light,
    // while every dial in this file is in DISPLAY units (0.95 is the 243/255 an
    // ordinary bright star renders at). The events path decodes the whole event
    // sum in main(); the far field does not, so the conversion happens here,
    // once, on the published gain. Without it a 0.55 shell dial arrives as 0.55
    // LINEAR -- 197/255 where it used to be 140 -- and every remnant on the
    // sky would be half a stop too bright for a reason nobody could find.
    function linearGain(display: real): real {
        const c = Math.max(0, display);
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }
    // The median ejecta speed that puts the debris cloud on the shell's own
    // radius at the end of the shell's own span. r(t) = (v0*t0/0.4)*((t/t0)^0.4
    // - 1) is the exact integral of the Sedov decay Physics applies, so solving
    // it for v0 is what makes "the rim and the debris agree" a fact rather than
    // a hope. spawnBurst's median is the midpoint of the range times the 0.707
    // of the sphere-on-a-plane projection, so the range is centred on v0/0.707.
    function supernovaEjecta(e: var): real {
        const t0 = 0.02;
        const span = Math.max(1, e.shellSpan);
        const grow = Math.pow(span / t0, 0.4) - 1;
        return grow > 0 ? 0.4 * supernovaShellReach(e) / (t0 * grow) : 0;
    }
    function supernovaParticles(): void {
        const s = _state;
        const e = s.events[8];
        // A pool with no live list is a stub (the offscreen sheets, the node
        // host): the episode then plays exactly as v9's sprite did.
        if (!_particles || !_particles.live || !particlesEnabled) {
            s.novaEpisode = null;
            return;
        }
        const P = _particles;
        if (!e || s.clock < e.start || s.clock > e.start + e.duration) {
            if (s.novaEpisode) {
                if (ParticlePhysics.novaStar(P) >= 0)
                    ParticlePhysics.clearNova(P);
                s.novaEpisode = null;
            }
            return;
        }
        const age = s.clock - e.start;
        const w = P.width, h = P.height, shortSide = Math.min(w, h);
        if (s.novaEpisode !== e) {
            s.novaEpisode = e;
            e.star = -1;
            e.starGeneration = -1;
            e.detonated = false;
            e.shockAt = 0;
            e.hasStar = false;
            // A seek lands mid-episode. There is no star to swell any more, so
            // the episode plays as the v9 sprite did rather than detonating a
            // burst nobody watched arrive.
            if (age > 0.5) {
                e.detonated = age >= e.precursor;
                return;
            }
            const flow = ParticlePhysics.flowSpeed(P);
            const hold = Math.max(4, Math.min(e.precursor, 0.5 * shortSide / Math.max(1, flow)));
            const i = ParticlePhysics.pickStar(P, {
                holdSec: hold,
                marginPx: 0.12 * shortSide,
                keepOutPx: 1.25 * holeReach() + 0.5 * supernovaShellReach(e)
            });
            if (i < 0)
                return;
            e.precursor = hold;
            e.duration = e.precursor + e.rise + e.hold + e.shellSpan + e.remnant;
            e.star = i;
            e.starGeneration = P.generation[i];
            e.hasStar = true;
            e.site = [P.x[i], P.y[i]];
            ParticlePhysics.markNova(P, i, {
                precursorSec: hold,
                // x4.2 on a 2.4-4.8 px near core is 10-20 px, which the packed
                // core byte clamps at 12; `bounds()` reserves three instances
                // at exactly that ceiling so the atlas never resizes for it.
                sizeGain: 4.2,
                lumGain: 5.5,
                warm: e.precursorColour,
                hot: e.peakColour
            });
        }
        const star = e.star >= 0 && P.alive[e.star] && P.generation[e.star] === e.starGeneration ? e.star : -1;
        if (!e.detonated) {
            if (star >= 0)
                e.site = [P.x[star], P.y[star]];
            else if (e.hasStar) {
                // The star died before its own supernova -- swallowed, or it
                // ran out of life. The site LATCHES where it was, so nothing
                // jumps, and the sprite takes its core back.
                e.hasStar = false;
                ParticlePhysics.clearNova(P);
            }
            if (age < e.precursor)
                return;
            e.detonated = true;
            const at = e.site ? e.site.slice() : supernovaSite(e);
            if (star >= 0)
                ParticlePhysics.remove(P, star, "supernova");
            ParticlePhysics.clearNova(P);
            e.hasStar = false;
            // From the detonation on, the site travels on the FAR LAYER's own
            // streamline -- a supernova is the most distant thing on the sky,
            // and that is where v9 put it. The debris expands about the site by
            // its own velocity and the whole cloud is translated by the same
            // drift each frame (driftGroup), so the rim and the material it is
            // made of can only move together. `x`/`y`/`camFlow` are what
            // supernovaSite integrates from, so they are re-anchored here to
            // where the star actually died.
            e.x = at[0];
            e.y = at[1];
            e.camFlow = s.camFlow;
            e.site = at.slice();
            const cfg = eventConfig(8);
            const index = e.index;
            const optics = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
            const grain = Math.min(2, Math.sqrt(optics));
            const span = parameterRange(cfg, "debrisCount", [300, 400], 0, 480);
            const count = Math.round(span[0] + (span[1] - span[0]) * random(index, screenSeed + 9311));
            const median = supernovaEjecta(e);
            const mid = median / 0.7071;
            const streakCap = P.config.streak.bendMaxPx;
            // ---- v11: THREE POPULATIONS, NOT ONE CLOUD ----------------------
            // "It should behave like a gas moving in a 3-D plane" (ledger 2286).
            // A single isotropic burst of identical embers is a puff; Cas A in
            // both references is three things at once, and so is this:
            //
            //   SHELL  most of the mass, a thin fast shell, streaked and lying
            //          TANGENTIALLY (curl about a right angle) so the rim reads
            //          as thousands of curling threads instead of as spokes.
            //          Dies with the shock, which is when its light is gone.
            //   JETS   two opposed cones on a frozen 3-D axis at 2-3x the shell
            //          speed, RADIAL (curl ~ 0) and long-streaked -- the fast
            //          jets shooting out of the rim in the Chandra composite.
            //   KNOTS  the dense clumps that survive. They are the REMNANT'S
            //          MATERIAL: they live through the whole remnant phase, so
            //          what he looks at for four minutes is made of particles
            //          that move with the regime, not of a sprite. Slower,
            //          smaller, redder, barely streaked -- and cheap, because a
            //          decelerated fragment's streak is zero and a plain dot
            //          costs a third of what a 48 px trail costs.
            //
            // Every one of them carries `dome: true`, so each fragment stores
            // the line-of-sight component of its own 3-D launch direction and
            // the near cap is magnified against the far one. That is the whole
            // "hollow sphere you fly past" and it costs five flops per ember.
            const jetAngle = e.spin * 0.5;
            const jetAxis = [Math.cos(jetAngle), Math.sin(jetAngle),
                (random(index, screenSeed + 9317) * 2 - 1) * 0.55];
            // The split is a COST decision as much as a physical one. The knots
            // are the ones alive during the remnant, so their share is what
            // sets the mid-remnant frame budget: measured on the tablet, each
            // long-lived ember is 0.023 points of a core, and 38 % put
            // mid-remnant at idle + 3.2 against a + 3.0 budget. 34 % puts it at
            // + 2.8, and eleven fewer knots out of a hundred and forty is not
            // something the eye has any way to find.
            const shellN = Math.round(count * 0.55);
            const jetN = Math.round(count * 0.11);
            const knotN = Math.max(0, count - shellN - jetN);
            // Fragments, not blobs. Particle sizes are physical pixels and are
            // NOT optics-scaled (nearPx is 2.4-4.8 px on every buffer), so
            // multiplying by the full optical scale made the debris three times
            // the size of the stars it was thrown out of -- measured 2.7-9.2 px
            // on the tablet, and it read as bubbles. sqrt of the optical scale
            // keeps a big buffer's debris legible without leaving the star range.
            const common = {
                dome: true,
                drag: 0.6,
                t0: 0.02,
                group: 1
            };
            ParticlePhysics.spawnBurst(P, at[0], at[1], shellN, [0.78 * mid, 1.62 * mid],
                Object.assign({
                    lifeSec: [clamp(0.45 * e.shellSpan, 14, 60), clamp(1.05 * e.shellSpan, 20, 70)],
                    sizePx: [0.8 * grain, 2.4 * grain],
                    lum: [2.2, 4.4],
                    colour: [1, 0.97, 0.92],
                    endColour: [0.95, 0.34, 0.16],
                    fastShare: 0.10,
                    fastGain: 2.4,
                    // 62-118 degrees off radial: tangential, but not a perfect
                    // ring of tangents -- a perfect one reads as a drawn circle.
                    curl: [1.0821, 2.0595],
                    streakPx: Math.min(48, streakCap),
                    exposureSec: 0.055
                }, common));
            ParticlePhysics.spawnBurst(P, at[0], at[1], jetN, [2.0 * mid, 3.2 * mid],
                Object.assign({
                    // cos 16 degrees: a narrow bipolar cone, which is what makes
                    // it read as a jet rather than as a wide fan.
                    cone: [jetAxis[0], jetAxis[1], jetAxis[2], 0.9613],
                    lifeSec: [clamp(0.70 * e.shellSpan, 20, 70), clamp(1.25 * e.shellSpan, 26, 90)],
                    sizePx: [0.7 * grain, 1.9 * grain],
                    lum: [3.0, 5.2],
                    colour: [0.88, 0.94, 1],
                    endColour: [1, 0.52, 0.62],
                    fastShare: 0.22,
                    fastGain: 1.5,
                    curl: [0, 0.26],
                    streakPx: Math.min(72, streakCap),
                    exposureSec: 0.075
                }, common));
            ParticlePhysics.spawnBurst(P, at[0], at[1], knotN, [0.42 * mid, 1.15 * mid],
                Object.assign({
                    // Through the remnant and out the other side: this is the
                    // material the remnant IS. Bounded by the 600 s ceiling
                    // spawnAt clamps `lifeSec` to.
                    lifeSec: [clamp(0.55 * e.shellSpan + 0.80 * e.remnant, 40, 560),
                        clamp(0.70 * e.shellSpan + 1.00 * e.remnant, 60, 600)],
                    sizePx: [0.7 * grain, 1.8 * grain],
                    lum: [1.5, 3.2],
                    colour: [1, 0.90, 0.72],
                    endColour: [0.78, 0.16, 0.10],
                    fastShare: 0.05,
                    fastGain: 1.8,
                    curl: [0.7854, 2.3562],
                    streakPx: Math.min(22, streakCap),
                    exposureSec: 0.040
                }, common));
            // The flash lights the neighbourhood it is standing in -- and ONLY
            // the neighbourhood. v10 used 0.55 of the LONG side, which on his
            // tablet is 1690 px: every star on the screen brightened at once,
            // which is a sky flash made out of particles rather than out of a
            // uniform, and deleting main()'s lift without this would have left
            // half of it behind. 1.5 shell radii is the radius requirement A
            // names, it is bounded by the episode's own geometry, and the gain
            // goes up because a smaller neighbourhood may be lit harder.
            ParticlePhysics.brightenNear(P, at[0], at[1], 1.5 * supernovaShellReach(e), 2.4, Math.max(2.5, e.rise + e.hold + 2));
            e.shockAt = 0;
            return;
        }
        // The site drifts with the far layer; the cloud goes with it, as one
        // body, so nothing inside the explosion can slide against anything else
        // in it. One pass over the transients per frame, only while a supernova
        // is running.
        const site = supernovaSite(Object.assign({}, e, {site: null}));
        if (e.site) {
            ParticlePhysics.driftGroup(P, 1, site[0] - e.site[0], site[1] - e.site[1]);
            e.site = site;
        }
        // The shock front, one kick per particle as it reaches it: the same
        // Sedov law and the same clock the rim is drawn with, so what pushes
        // the neighbours outward is the ring he can see doing it. It reaches
        // `shockReach` times further than the luminous rim, because the
        // pressure wave runs ahead of the material that is lit up -- and
        // because at 600 particles over a 2880x1800 buffer the drawn rim
        // encloses about ten stars, which is not an explosion the field feels.
        const d = age - e.precursor;
        const u = clamp(d / Math.max(0.001, e.shellSpan), 0, 1);
        if (u < 1 && e.site) {
            const reach = 2.4 * supernovaShellReach(e);
            const front = reach * Math.pow(u, 0.4);
            if (front > e.shockAt) {
                ParticlePhysics.applyImpulse(P, e.site[0], e.site[1],
                    cfgShockSpeed(), front,
                    {kind: "front", fromPx: e.shockAt, maxPx: reach});
                e.shockAt = front;
            }
        }
    }
    // One dial, in short sides per second, on how hard a supernova shoves the
    // stars beside it. Default 0.32 of the short side, which displaces the
    // closest neighbours by about 60 px and leaves the rim untouched.
    function cfgShockSpeed(): real {
        const cfg = eventConfig(8);
        const share = Number(cfg.shockShortSide);
        const shortSide = Math.min(width, height) * devicePixelRatio;
        return (Number.isFinite(share) ? clamp(share, 0, 2) : 0.32) * shortSide;
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
        // v9: the supernova is its own kernel (style 6) and its own life cycle.
        if (e.kind === 8)
            return supernovaState(e, age);
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
        } else if (e.kind === 9) {
            // Pulsar: a raised cosine with guaranteed edges and a trough that
            // never drops below floorFraction of the peak. It modulates.
            const phase = modulo(age, e.period) / e.period;
            const duty = 0.5 - 0.5 * Math.cos(2 * Math.PI * phase);
            const soft = Math.min(1, e.edge * 4 / e.period);
            const shaped = duty * (1 - soft) + soft * 0.5;
            const env = e.gain * (e.floor + (1 - e.floor) * shaped) * ease(age / 8) * ease((e.duration - age) / 8);
            coreAbs = env;
            haloAbs = 0.14 * env;
            halo = e.core * 3;
        } else if (e.kind === 10) {
            // Kilonova: a hot flash that cools into one expanding r-process
            // ring. The colour ramp is the whole point of the family, so it is
            // driven by the RING's own age rather than the core's.
            // 0.35 s is the burst rise floor: ten frames at 30 fps, eased, so a
            // sub-second family is still never a step. The decay is paced to
            // the same budget - it was the fall, not the rise, that first
            // tripped the anti-strobe test.
            const rise = Math.max(0.35, e.flash * 0.6);
            let env;
            if (age < rise)
                env = e.gain * ease(age / rise);
            else
                env = e.gain * Math.exp(-2.2 * (age - rise) / Math.max(0.5, e.flash));
            exempt = ease((e.flash + 2 - age) / 2);
            coreAbs = env;
            haloAbs = 0.22 * env;
            halo = e.core * 3.2;
            const u = clamp((age - rise) / Math.max(0.001, e.ringSpan), 0, 1);
            if (u > 0 && u < 1) {
                ringRadius = e.ring * Math.pow(u, 0.6);
                ringWidth = Math.max(2, e.core * (0.9 + 5 * u));
                ringAbs = e.ringGain * ease(u / 0.12) * (1 - u) * (1 - u);
                const warm = ease(u / 0.7);
                const hot = e.peakColour, cool = e.coolColour;
                colour = [hot[0] + (cool[0] - hot[0]) * warm, hot[1] + (cool[1] - hot[1]) * warm, hot[2] + (cool[2] - hot[2]) * warm];
            } else
                colour = e.peakColour;
        } else {
            // Gamma-ray burst: an eased sub-second point with two opposed
            // beams (style 4), then a long afterglow point on the same core.
            // The rise is >= 0.35 s by construction, so nothing lands inside a
            // single frame at 30 fps.
            const peakAt = e.rise + e.flash * 0.35;
            let env;
            if (age < e.rise)
                env = e.gain * ease(age / e.rise);
            else if (age < peakAt)
                env = e.gain;
            else if (age < e.rise + e.flash)
                // The flash decays TO the afterglow level, not to zero: ending
                // it at zero put a 0.27 linear step in one frame right where
                // the afterglow began, which the anti-strobe test catches.
                env = e.gain * (0.14 + 0.86 * ease((e.rise + e.flash - age) / Math.max(0.001, e.flash * 0.65)));
            else {
                const d = (age - e.rise - e.flash) / Math.max(0.001, e.afterglow);
                env = e.gain * 0.14 * Math.exp(-2.6 * d) * ease((1 - d) / 0.2);
            }
            exempt = ease((e.rise + e.flash + 2 - age) / 2);
            colour = e.peakColour;
            coreAbs = env;
            haloAbs = 0.20 * env;
            halo = e.core * 3.5;
            // The beams live only while the flash does; the afterglow is a
            // point. beamAbs travels in the ring channel, reinterpreted by the
            // style-4 branch of radialField.
            const beamEnv = age < e.rise + e.flash ? env / Math.max(0.001, e.gain) : 0;
            if (beamEnv > 0) {
                ringAbs = e.beamGain * beamEnv;
                ringRadius = e.beam;
                ringWidth = e.beamWidth;
            }
        }
        // head.w is the slot's peak value; every component travels as a
        // fraction of it, so the shader's single multiply reproduces all four
        // absolute gains and the slot only switches off when all of them are 0.
        const peak = Math.max(coreAbs + haloAbs, ringAbs + echoAbs);
        if (peak <= 0.0004)
            return off;
        const beam = e.kind === 11;
        const reach = beam ? Math.max(ringRadius + 3 * ringWidth, Math.max(3 * halo, 6 * core)) : Math.max(Math.max(ringRadius + 3 * ringWidth, echoRadius + 6 * ringWidth), Math.max(3 * halo, 6 * core));
        return {
            head: [e.x, e.y, core, peak],
            colour: colour.concat(beam ? 4 : 3),
            // Style 4 re-reads tail01 as (haloSigmaPx, haloGain, coreGain,
            // beamGain) and shape as (dirX, dirY, beamLengthPx, beamWidthPx).
            tail01: beam ? [halo, haloAbs / peak, coreAbs / peak, ringAbs / peak] : [echoRadius, echoAbs / peak, haloAbs / peak, coreAbs / peak],
            shape: beam ? [e.beamDir[0], e.beamDir[1], ringRadius, ringWidth] : [halo, ringAbs / peak, ringWidth, ringRadius],
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

    // v10: where the nucleus actually is. A fragment carries the same lateral
    // split the drawn path used, measured off the real body rather than off a
    // Bezier that is no longer what the comet is flying.
    function cometHead(e: var, branch: int, progress: real): var {
        const head = [e.site[0], e.site[1]];
        if (e.family === "fragmenting" && branch !== 0) {
            const split = ease((progress - e.splitU) / Math.max(1e-6, 1 - e.splitU));
            const offset = branch * e.shortSide * 0.035 * split * split;
            head[0] -= Math.sin(e.angle) * offset;
            head[1] += Math.cos(e.angle) * offset;
        }
        return head;
    }

    function eventState(e: var, branch: int, companion: bool, segments: int): var {
        if (!e || (companion && !e.pair))
            return eventOff();
        const age = _state.clock - e.start - (companion ? e.offset : 0);
        if (age < 0 || age > e.duration)
            return eventOff();
        const u = age / e.duration;
        // v12 DECELERATION. The shipped law was (1-e^-2.4u)/(1-e^-2.4): 77 % of
        // the path flown in the first half of the life, a start/end speed ratio
        // of 10.51, and a trail that got SHORTER as the meteor aged because it
        // spans a fixed progress interval. Real visible-phase deceleration is a
        // few per cent; strong terminal deceleration belongs to a fireball,
        // where it is real (Zdar nad Sazavou went 21.89 -> 4.8 km/s) and is
        // what precedes the terminal burst.
        const drag = e.kind === 0 ? (e.fireball ? 0.22 : 0.05) : 0;
        const progress = e.kind === 0 ? (u - drag * u * u * u) / (1 - drag) : u;
        // v12 LIGHT CURVE for a meteor; the v6 in/out ease for everything else.
        const sharp = e.curveSharp === undefined ? 4.5 : e.curveSharp;
        let envelope = e.kind === 0
            ? lightCurveAt(progress, e.curveF === undefined ? 0.52 : e.curveF, sharp)
            : ease(u / 0.16) * ease((1 - u) / 0.20);
        // The second grain release. max(), not a sum: the peak stays 1 and the
        // curve gains a shoulder rather than a taller maximum.
        if (e.kind === 0 && e.doublePeak)
            envelope = Math.max(envelope, e.secondGain * lightCurveAt(progress, e.secondF, sharp * 1.8));
        // Flares, summed in MAGNITUDES, Gaussian in TIME on the published FWHM.
        let flareMag = 0;
        if (e.kind === 0 && e.flares)
            for (const f of e.flares) {
                const t = (age - f[0] * e.duration) / Math.max(0.05, e.flareSec);
                flareMag += f[1] * Math.exp(-2.7725887 * t * t);
            }
        // 10^(0.4 dm) is the linear factor; the slot's own gain is capped at
        // 3.2x the family cap, because past that the value is clipped anyway
        // and everything further belongs to the disc.
        const boost = flareMag > 0 ? Math.pow(10, 0.4 * flareMag) : 1;
        let gain = e.gain * Math.min(envelope * boost, 3.2) * (companion ? 0.5 : 1);
        if (e.family === "pulsating")
            gain *= (1 + e.pulseAmplitude * Math.sin(age * 2 * Math.PI / e.pulsePeriod)) / (1 + e.pulseAmplitude);
        if (e.family === "skipping")
            gain *= 0.10 + 0.90 * Math.pow(Math.sin(Math.PI * e.lobes * u), 2);
        // shape.w: a satellite's glint, and -- for a meteor since v12 -- the
        // GLARE. It used to be `ease((0.26 - u)/0.20)`, an "entry bloom"
        // peaking at u = 0 and gone by u = 0.16. There is no entry bloom. A
        // head blooms where it is bright, and the apparent size of a head is
        // the point-spread function convolved with SATURATION, so the
        // saturated disc grows with the LOGARITHM of the brightness. That is
        // also why a flare belongs here rather than in the gain: the value is
        // already clipped by the display and cannot show anything more.
        let flash = 0;
        if (e.kind === 0) {
            // The flare's magnitudes reach the disc UNCAPPED, which is the
            // whole point: a head already at 255/255 cannot get brighter, and
            // the disc is the only channel left that a camera -- or an eye --
            // actually reads as a flare. The denominator puts an ordinary
            // meteor's own maximum at about half the range, so a flare has
            // somewhere to grow into instead of arriving already clipped.
            const bright = e.gain * envelope * boost * (e.fireball ? 3.0 : 1);
            flash = clamp(Math.log(1 + 18 * bright) / Math.log(1 + 18 * 12), 0, 1);
        }
        if (e.kind === 2 && e.glintGain > 1) {
            // A Gaussian in time: smooth at both edges by construction, so the
            // brightening has no slope a blink could hide in.
            const t = (age - e.glintAt) / Math.max(0.5, e.glintWidth);
            const lift = Math.exp(-2.8 * t * t);
            gain *= 1 + (e.glintGain - 1) * lift;
            flash = clamp(lift, 0, 1);
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
        if (e.kind === 1)
            return cometState(e, e.site ? cometHead(e, branch, progress) : points[0], progress, branch, gain, width, age);
        // v12: a meteor's head bloom reaches 33 sigma at full glare and its
        // trail's widest emitter has 24 sigma of compact support, so the box
        // has to be 34 sigma or the bounds test cuts the glow on a straight
        // line. Style 2 keeps the 7 it was measured with.
        const extent = width * (e.kind === 0 ? 44 : 7);
        const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
        return {
            head: [points[0][0], points[0][1], width, gain],
            colour: e.colour.concat(e.kind >= 2 ? 2 : 0),
            tail01: points[0].concat(points[1]),
            tail23: points[2].concat(points[3]),
            tail4: points[4],
            // shape.y was a hardcoded 0.62 for every object in the sky; it is
            // now the streak's own head:trail draw. shape.w is the glare.
            shape: [length, e.kind === 0 ? (e.headShare === undefined ? 0.62 : e.headShare) : 0.62, count, flash],
            bounds: [Math.min(...xs) - extent, Math.min(...ys) - extent, Math.max(...xs) + extent, Math.max(...ys) + extent],
            // (F, headPathU, pathSpan, speed01). pathSpan is min(span,
            // progress) because the polyline is clamped at the start of the
            // path, so the drawn trail is shorter than `span` early on.
            burn: e.kind === 0
                ? [e.curveF === undefined ? 0.52 : e.curveF, progress, Math.min(span, progress), e.speed01 === undefined ? 0 : e.speed01]
                : [0.52, 0, 0, 0]
        };
    }

    // Style 5. The tails are recomputed every publish because their direction
    // is a property of WHERE the comet is, not of when it was captured: the
    // ion tail points straight away from the light source and swings as the
    // comet passes it, and the dust tail lags between that and anti-velocity
    // and bends away from the ion tail. Everything else was captured at birth.
    function cometState(e: var, head: var, progress: real, branch: int, gain: real, width: real, age: real): var {
        // v10. A comet is a BODY. Its nucleus is a particle with its own proper
        // motion (see cometParticles), and the tails are built from where that
        // particle actually is and which way it is actually going, this frame.
        //
        // WHICH WAY A TAIL POINTS. A dust tail is material left behind, so it
        // TRAILS THE MOTION and curves off the path -- always, in both regimes.
        // An ion tail is gas driven off by light, so it points away from the
        // light source; and in the camera regime there is no light source, so
        // it trails the motion too. That is what he expected to see and did not
        // get: "the tail was in the wrong direction" (ledger 2285), because v9
        // pointed BOTH tails away from the screen centre whatever the comet was
        // doing. `lightWeight` is the hole's own envelope, so the two models
        // crossfade with the regime and neither is ever a cut. With no velocity
        // at all -- the offscreen sheets, a pool that could not spare a slot --
        // this is exactly v9.
        let bx = 0, by = 0;
        const v = e.vel;
        const speed = v ? Math.hypot(v[0], v[1]) : 0;
        if (speed > 1e-4) {
            bx = -v[0] / speed;
            by = -v[1] / speed;
        }
        let ax = head[0] - e.light[0], ay = head[1] - e.light[1];
        const alen = Math.hypot(ax, ay);
        if (alen > 0.0001) {
            ax /= alen;
            ay /= alen;
        } else {
            ax = 1;
            ay = 0;
        }
        if (speed <= 1e-4) {
            bx = ax;
            by = ay;
        }
        const lit = speed > 1e-4 ? clamp(e.lightWeight === undefined ? 1 : e.lightWeight, 0, 1) : 1;
        let ix = bx + (ax - bx) * lit, iy = by + (ay - by) * lit;
        let ilen = Math.hypot(ix, iy);
        if (ilen < 1e-4) {
            ix = bx;
            iy = by;
            ilen = 1;
        }
        ix /= ilen;
        iy /= ilen;
        // NEVER AHEAD OF THE MOTION. Off the anti-velocity by at most 80
        // degrees: a tail in front of its own nucleus is the one thing a comet
        // cannot have, whatever the light happens to be doing.
        if (speed > 1e-4) {
            const dot = ix * bx + iy * by;
            const floorCos = 0.17;
            if (dot < floorCos) {
                let px = ix - bx * dot, py = iy - by * dot;
                const plen = Math.hypot(px, py);
                if (plen > 1e-6) {
                    px /= plen;
                    py /= plen;
                }
                const sn = Math.sqrt(Math.max(0, 1 - floorCos * floorCos));
                ix = bx * floorCos + px * sn;
                iy = by * floorCos + py * sn;
            }
        }
        // The dust lags the trail direction by a fixed angle on a birth-frozen
        // side, the way a real dust tail lags the anti-solar line. BLENDING two
        // directions is the wrong model: a comet receding straight from the
        // light has them antiparallel, the blend collapses onto the ion tail,
        // and the two tails draw on top of each other.
        const side = e.dustSide;
        const turn = side * e.lagAngle;
        const cos = Math.cos(turn), sin = Math.sin(turn);
        const dx = bx * cos - by * sin, dy = bx * sin + by * cos;
        // An outburst: the coma swells and brightens while the tails do not.
        const breath = e.family === "pulsating" ? 1 + 0.45 * Math.max(0, Math.sin(age * 2 * Math.PI / e.pulsePeriod)) : 1;
        // A fragment carries its own small coma and a short stub of dust.
        const share = branch === 0 ? 1 : 0.45;
        const coma = e.coma * breath * share;
        const dust = e.dustLength * (branch === 0 ? 1 : 0.5);
        const ion = e.ionLength * share;
        // A tail reaches one way only, so the box follows the two tails rather
        // than squaring the longer of them: the slow family's box halves.
        const pad = Math.max(9 * e.dustWidth, 3 * coma, 6 * width);
        const tipX = head[0] + dx * dust - dy * e.curve * side * dust;
        const tipY = head[1] + dy * dust + dx * e.curve * side * dust;
        const xs = [head[0], head[0] + ix * ion, tipX];
        const ys = [head[1], head[1] + iy * ion, tipY];
        return {
            head: [head[0], head[1], width, gain],
            colour: e.colour.concat(5),
            tail01: [ix, iy, ion, e.ionWidth],
            tail23: [dx, dy, dust, e.dustWidth],
            tail4: [Math.abs(e.curve) * side, coma],
            shape: [e.ionGain * share, e.dustGain * share, e.comaGain * breath, e.striae],
            bounds: [Math.min(...xs) - pad, Math.min(...ys) - pad, Math.max(...xs) + pad, Math.max(...ys) + pad],
            burn: [0.52, 0, 0, 0]
        };
    }

    // ---- v10: the comet is a body with its own proper motion ----------------
    // "I saw a large comet or whatever that was with a large tail and it feels
    // really poor for me: it was moving slow, same as the other stars, and the
    // tail was in the wrong direction." (ledger 2285)
    //
    // It moved at the field's speed because v9 drew it along a captured Bezier
    // over a 30-65 s duration that had nothing to do with how fast anything
    // else on the screen was going. It now crosses a long chord at a MEASURED
    // multiple of the field's own speed, as a particle, and the tails come off
    // that particle's velocity.
    //
    // 3-8x the field. "Slow" is the slowest family and it is still three times
    // the flow, because slower than that is the complaint.
    function cometRatio(family: string): real {
        return family === "fast" ? 7.5 : family === "slow" ? 3.2 : family === "bent" ? 4.2 : family === "pulsating" ? 4.6 : family === "fragmenting" ? 6.0 : 5.0;
    }
    // How far the chord turns over the whole pass, in radians. With the hole on
    // this is done for real by gravity (the velocity is in vx/vy and the pass is
    // a genuine hyperbola); with the camera on there is no force, so the
    // peculiar channel is rotated by hand at the same rate.
    function cometTurn(family: string): real {
        return family === "fast" ? 0.10 : family === "slow" ? 0.34 : family === "bent" ? 0.95 : family === "pulsating" ? 0.28 : family === "fragmenting" ? 0.22 : 1.50;
    }
    function cometParticles(): void {
        const s = _state;
        const e = s.events[1];
        if (!_particles || !_particles.live || !particlesEnabled) {
            s.cometEpisode = null;
            return;
        }
        const P = _particles;
        if (!e || s.clock < e.start || s.clock > e.start + e.duration + (e.offset || 0)) {
            s.cometEpisode = null;
            return;
        }
        const age = s.clock - e.start;
        if (s.cometEpisode !== e) {
            s.cometEpisode = e;
            e.body = -1;
            e.bodyGeneration = -1;
            e.shedAt = s.clock;
            e.turnAt = s.clock;
            // A seek landed mid-pass: there is no body to spawn halfway along
            // its own chord, so the episode plays as v9's sprite did.
            if (age > 0.5)
                return;
            const shortSide = Math.min(P.width, P.height);
            const flow = ParticlePhysics.flowSpeed(P);
            // A LONG chord, 1.1-1.6 short sides, so it enters and leaves off
            // the screen instead of appearing in the middle of it.
            const chord = shortSide * (1.1 + 0.5 * random(e.index, screenSeed + 4409));
            let speed = cometRatio(e.family) * Math.max(1, flow);
            // Six seconds is the floor on a pass. With the hole on the field is
            // itself streaming at a few hundred px/s, so a comet at three times
            // that would cross in four seconds and read as a meteor; the floor
            // takes precedence there and the ratio is honoured wherever the
            // regime leaves room for it, which is the camera regime he runs.
            speed = clamp(speed, chord / 25, chord / 6);
            const dx = Math.cos(e.angle), dy = Math.sin(e.angle);
            const origin = e.origin || [e.p0[0] * 0.5 + e.p2[0] * 0.5, e.p0[1] * 0.5 + e.p2[1] * 0.5];
            const at = [origin[0] - dx * chord / 2, origin[1] - dy * chord / 2];
            e.p0 = at.slice();
            e.p2 = [origin[0] + dx * chord / 2, origin[1] + dy * chord / 2];
            e.distance = chord;
            e.speed = speed;
            e.flowAt = flow;
            e.ratio = speed / Math.max(1e-6, flow);
            e.duration = chord / speed;
            e.body = ParticlePhysics.spawnBody(P, at[0], at[1], dx * speed, dy * speed, {
                lifeSec: e.duration + 6,
                // Big enough to lens and occlude like the body it is, small
                // enough that it and the sprite's own nucleus read as one.
                sizePx: clamp(e.pointWidth * 1.5, 1, 9),
                lum: 3.6,
                colour: e.colour,
                depth: 1,
                group: 2,
                streakPx: Math.min(36, P.config.streak.bendMaxPx),
                exposureSec: 0.05
            });
            e.bodyGeneration = e.body >= 0 ? P.generation[e.body] : -1;
            e.omega = cometTurn(e.family) * (random(e.index, screenSeed + 4411) < 0.5 ? -1 : 1) / Math.max(0.001, e.duration);
            e.site = at.slice();
            e.vel = [dx * speed, dy * speed];
            e.siteAt = s.clock;
        }
        // The ion tail's model crossfades with the regime, on the hole's own
        // envelope: anti-sunward with the hole on, trailing the motion with it
        // off, and no frame between them is a cut.
        e.lightWeight = clamp(1 - _cameraBlend, 0, 1);
        const i = e.body;
        if (i >= 0 && P.alive[i] && P.generation[i] === e.bodyGeneration) {
            e.site = [P.x[i], P.y[i]];
            e.vel = [P.vx[i] + P.kickX[i], P.vy[i] + P.kickY[i]];
            e.siteAt = s.clock;
            const turn = e.omega * (s.clock - e.turnAt);
            if (turn && (P.kickX[i] || P.kickY[i])) {
                const c = Math.cos(turn), sn = Math.sin(turn);
                const kx = P.kickX[i], ky = P.kickY[i];
                P.kickX[i] = kx * c - ky * sn;
                P.kickY[i] = kx * sn + ky * c;
            }
            e.turnAt = s.clock;
            // It sheds. A few small motes a pass, each on its own short life,
            // so the trail is made of material and not only of a sprite.
            if (s.clock - e.shedAt >= 0.7 && age > 0.4 && age < e.duration - 0.4) {
                e.shedAt = s.clock;
                ParticlePhysics.spawnBurst(P, P.x[i], P.y[i], 1, [0.04 * e.speed, 0.16 * e.speed], {
                    lifeSec: [3.5, 8],
                    sizePx: [0.7, 1.5],
                    lum: [1.2, 2.4],
                    colour: e.colour,
                    endColour: [0.45, 0.58, 0.82],
                    fastShare: 0,
                    drag: 0.9,
                    group: 2
                });
            }
        } else if (e.site && e.vel) {
            // The body left the field. Dead-reckon the site rather than
            // stopping the sprite in mid-air while its envelope fades out.
            const dt = s.clock - (e.siteAt === undefined ? s.clock : e.siteAt);
            e.site = [e.site[0] + e.vel[0] * dt, e.site[1] + e.vel[1] * dt];
            e.siteAt = s.clock;
        }
    }

    // R6. An episode handed in from outside the interval scheduler - a physics
    // detection (a particle merge becoming a kilonova) or any conditional
    // arrival - waits here until its family's entry is free. It is captured at
    // push time from the same hash stream, so it is as deterministic as a
    // scheduled one, and it obeys exactly the same slot and cap rules.
    function pushEvent(name: string, delaySec: real, overrides: var): bool {
        // The nebula is not a radial phenomenon and has no slot, but it is
        // reached the same way: `caelestia shell starfield fire nebula`.
        if (name === "nebula")
            return pushNebula(delaySec, overrides);
        // `storm` and `shower` are the same family; v8 only knew the seven
        // radial names, so `fire shower` did nothing and the storm could not be
        // looked at on demand. Transient kinds capture through schedule()'s own
        // path, which is what gives a forced storm its radiant and fireballs.
        const transient = ["meteors", "comet", "satellites", "shower", "slowWanderer"].indexOf(name === "storm" ? "shower" : name);
        const kind = transient >= 0 ? transient : radialNames.indexOf(name) + 5;
        if (kind < 0 || (transient < 0 && kind < 5) || !_state)
            return false;
        const s = _state;
        if (s.pendingEvents.length >= 4)
            s.pendingEvents.shift();
        const at = s.clock + Math.max(0, Number(delaySec) || 0);
        const e = transient >= 0
            ? captureEvent(kind, s.eventIds[kind]++, at, kind === 3 ? "straight" : kind < 2 ? chooseFamily(kind, s.eventIds[kind] - 1, at) : kind === 4 ? "slowWanderer" : "satellite")
            : captureRadial(kind, s.eventIds[kind]++, at);
        if (!e)
            return false;
        // A forced shower captures its storm here, BEFORE the overrides, so
        // `fire shower tablet '{"peakRate":6}'` changes the storm it made
        // rather than being overwritten by it.
        if (kind === 3) {
            e.pair = false;
            captureStorm(e, s.eventIds[3] - 1);
        }
        if (overrides) {
            for (const key of Object.keys(overrides))
                e[key] = overrides[key];
            // A supernova's duration is the SUM of its phases, so overriding one
            // of them without this would leave the episode ending in the middle
            // of a phase. Recomputed from whatever the overrides left behind,
            // which is what makes `fire supernova tablet '{"shellSpan":20}'` a
            // shorter shell rather than a truncated life cycle.
            if (kind === 8)
                e.duration = e.precursor + e.rise + e.hold + e.shellSpan + e.remnant;
        }
        s.pendingEvents.push(e);
        return true;
    }

    // Drained after the interval scheduler, so a pushed episode takes its
    // family's turn rather than racing it. A pushed episode never evicts a
    // running one; it waits, and is dropped if it is still waiting two minutes
    // after its moment, which is what keeps a burst of detections from turning
    // into a queue that plays out long after the cause is gone.
    function drainPending(): void {
        const s = _state;
        if (!s.pendingEvents.length)
            return;
        const keep = [];
        for (const e of s.pendingEvents) {
            if (s.clock < e.start) {
                keep.push(e);
                continue;
            }
            if (s.clock > e.start + 120)
                continue;
            const held = s.events[e.kind];
            if (held && s.clock >= held.start && s.clock <= held.start + held.duration + (e.kind < 5 ? held.offset || 0 : 0)) {
                keep.push(e);
                continue;
            }
            e.start = s.clock;
            s.events[e.kind] = e;
        }
        s.pendingEvents = keep;
    }

    function publishEvents(): void {
        const s = _state;
        for (let kind = 0; kind < s.events.length; ++kind) {
            const e = s.events[kind];
            const radial = kind >= 5;
            if (!eventEnabled(kind) && e && s.clock < e.start)
                s.events[kind] = null;
            else if (!e || s.clock > e.start + e.duration + (radial ? 0 : e.offset))
                s.events[kind] = radial ? scheduleRadial(kind) : schedule(kind);
        }
        drainPending();
        // v10: the supernova's state machine, once per publication. It is the
        // only place an event touches the particle field, and the only place
        // any of these descriptors are mutated.
        supernovaParticles();
        cometParticles();
        const shower = s.events[3];
        // A fireball's train outlives the rate hump by design, so the episode
        // stays "active" for the overhang `captureStorm` reserved in `offset`.
        const showerActive = shower && s.clock >= shower.start && s.clock <= shower.start + shower.duration + (shower.offset || 0);
        if (showerActive && s.clock <= shower.start + shower.duration && s.mood[0] === 3)
            shader.mood = Qt.vector4d(0, 0, 0, 0);
        const slots = [];
        // v12 SLOT PRIORITY, decided here rather than discovered on the screen.
        //
        // There are three transient heads. v9 filled them with storm fireballs
        // FIRST and a fireball holds its head for `trainSec` AFTER its own head
        // has died, so three fireballs could silently drop the comet, the
        // satellite and the wanderer for the better part of a minute -- and
        // v12 makes trains longer, which would have made it worse.
        //
        // Two rules, and they are the whole policy:
        //   1. an event's FIRST head competes for any free slot; only its
        //      EXTRA heads (a fragment's branches, a meteor's companion) are
        //      capped at two. v9 capped the first head too, so a meteor with a
        //      companion already blocked the comet completely.
        //   2. a fireball whose head is still burning is the loudest thing in
        //      the sky and takes a slot first, but never more than two of the
        //      three. A fireball that is only carrying a TRAIN -- dim, slow,
        //      and the thing that lasts longest -- drops BELOW the comet, the
        //      satellite and the wanderer and takes whatever is left.
        function append(e) {
            if (!e || s.clock < e.start || s.clock > e.start + e.duration + e.offset)
                return;
            const fragment = e.family === "fragmenting";
            const extras = Math.min(e.headCap, fragment ? 3 : 2);
            const branches = fragment ? [0, -1, 1].slice(0, extras) : [0];
            let taken = 0;
            for (const branch of branches) {
                if (slots.length < transientSlotCount && taken < extras) {
                    slots.push(eventState(e, branch, false, fragment ? 2 : 3));
                    taken++;
                }
            }
            if (e.pair && slots.length < transientSlotCount && taken < extras) {
                slots.push(eventState(e, 0, true, 3));
                taken++;
            }
        }
        // The storm's ordinary streaks are the shader's, not a slot's. What the
        // CPU still owns is the four vectors that describe the storm and the
        // one to three fireballs, which take the transient heads the v8 shower
        // used to fill with six plain meteors.
        const storm = stormState() || stormOff();
        shader.stormHead = Qt.vector4d(storm.head[0], storm.head[1], storm.head[2], storm.head[3]);
        shader.stormShape = Qt.vector4d(storm.shape[0], storm.shape[1], storm.shape[2], storm.shape[3]);
        shader.stormColour = Qt.vector4d(storm.colour[0], storm.colour[1], storm.colour[2], storm.colour[3]);
        shader.stormSpan = Qt.vector4d(storm.span[0], storm.span[1], storm.span[2], storm.span[3]);
        shader.stormBurn = Qt.vector4d(storm.burn[0], storm.burn[1], storm.burn[2], storm.burn[3]);
        shader.stormTrain = Qt.vector4d(storm.train[0], storm.train[1], storm.train[2], storm.train[3]);
        shader.stormWind = Qt.vector4d(storm.wind[0], storm.wind[1], storm.wind[2], storm.wind[3]);
        const ceiling = Math.min(Math.round(clamp(eventHeadCap, 0, 3)), transientSlotCount);
        const trainsWaiting = [];
        if (showerActive && shower.children) {
            // Never more than two of the three, so the rest of the catalogue
            // always has somewhere to go while a storm is running.
            const liveCeiling = Math.min(ceiling, transientSlotCount - 1);
            for (const child of shower.children) {
                const slot = stormFireballState(shower, child);
                if (!slot)
                    continue;
                stormFireballParticles(shower, child, slot.head);
                const burning = s.clock - shower.start - child.at <= child.flight + 0.35;
                if (burning) {
                    if (slots.length < liveCeiling)
                        slots.push(slot);
                } else {
                    trainsWaiting.push(slot);
                }
            }
        }
        append(s.events[0]);
        for (const kind of [1, 2, 4])
            append(s.events[kind]);
        for (const slot of trainsWaiting)
            if (slots.length < ceiling)
                slots.push(slot);
        for (let i = 0; i < 3; ++i) {
            const slot = slots[i] || eventOff();
            shader["event" + i + "Tail4"] = Qt.vector2d(slot.tail4[0], slot.tail4[1]);
            for (const name of ["head", "colour", "tail01", "tail23", "shape", "bounds", "burn"]) {
                const v = slot[name] || [0, 0, 0, 0];
                shader["event" + i + name[0].toUpperCase() + name.slice(1)] = Qt.vector4d(v[0], v[1], v[2], v[3]);
            }
        }
        // v12 tone blocks. One vector each for the ordinary meteors and for the
        // shower, because the two carry the same key names under separate
        // config objects and a fireball belongs to the shower.
        const mt = meteorToneVector(0), st = meteorToneVector(3);
        shader.meteorTone = Qt.vector4d(mt[0], mt[1], mt[2], mt[3]);
        shader.stormTone = Qt.vector4d(st[0], st[1], st[2], st[3]);
        publishPhenomena();
    }

    // Slots 3-5. Long, faint, low-gain radial events only; they never spill
    // into the transient heads and the heads never spill into them.
    function publishPhenomena(): void {
        const s = _state;
        const cap = Math.round(clamp(Number((eventFamilies || {}).phenomenonCap) || phenomenonSlotCount, 1, phenomenonSlotCount));
        // Slot ownership is STICKY. An episode claims a slot only in its first
        // second, while its envelope is still at nothing, and keeps it until it
        // ends. A phenomenon that could take a freed slot halfway through its
        // life would appear at whatever gain it had reached, which is the
        // one-frame pop the v6 pass existed to remove.
        //
        // The slot now holds the EPISODE, not its kind. Holding the kind
        // released nothing: publishEvents replaces s.events[kind] with the next
        // episode the instant the current one ends, so `clock > held.start +
        // held.duration` always read a future end and slots 3-4 stayed owned by
        // the first star birth and the first nova for the life of the process.
        // Measured over six hours on three seeds: red giant 0.83 scheduled/h and
        // 0 s drawn, supernova 0.33/h and 0 s drawn - neither had ever reached
        // the screen (his report, ledger 2283).
        const owner = s.phenomenonSlots;
        for (let i = 0; i < phenomenonSlotCount; ++i) {
            const held = owner[i];
            if (held && (s.clock > held.start + held.duration || i >= cap))
                owner[i] = null;
        }
        for (let kind = 5; kind < s.events.length; ++kind) {
            const e = s.events[kind];
            if (!e || owner.indexOf(e) >= 0)
                continue;
            const age = s.clock - e.start;
            if (age < 0 || age > 1)
                continue;
            let free = -1;
            for (let i = 0; i < cap; ++i)
                if (owner[i] === null) {
                    free = i;
                    break;
                }
            if (free >= 0)
                owner[free] = e;
            else if (age > 0.25)
                // Every slot was busy at arrival. The episode is RETIRED rather
                // than silently dropped, so publishEvents schedules a fresh one
                // against the current occupants and the family arrives later
                // instead of never.
                s.events[kind] = null;
        }
        const live = [];
        for (let i = 0; i < cap; ++i)
            live.push(owner[i] === null ? null : radialState(owner[i]));
        // Combined peak-gain cap outside a supernova flash. The exemption is an
        // eased weight, not a test, so the cap takes hold without a step; the
        // scale itself is continuous in the sum for the same reason.
        let capped = 0;
        for (const state of live)
            if (state)
                capped += state.head[3] * (1 - state.exempt);
        const ceiling = clamp(Number((eventFamilies || {}).phenomenonGainCap) || phenomenonGainCeiling, 0.3, 3);
        const scale = capped > ceiling ? ceiling / capped : 1;
        // v9: the supernova's four extra vectors. Whichever slot holds one owns
        // them; at most one is ever alive, because the dramatic cooldown is
        // 900 s against a ~290 s life and publishEvents replaces an episode only
        // after it has ended. Its per-component gains are fractions of the
        // slot's peak, so the combined-gain scale below reaches them for free;
        // the sky lift is absolute and is covered by the flash exemption.
        let extras = null;
        for (const state of live)
            if (state && state.extras && !extras)
                extras = state.extras;
        shader.snRemnant = extras ? Qt.vector4d(extras.remnant[0], extras.remnant[1], extras.remnant[2], extras.remnant[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snTone = extras ? Qt.vector4d(extras.tone[0], extras.tone[1], extras.tone[2], extras.tone[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snShell = extras ? Qt.vector4d(extras.shell[0], extras.shell[1], extras.shell[2], extras.shell[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snExtra = extras ? Qt.vector4d(extras.extra[0], extras.extra[1], extras.extra[2], extras.extra[3]) : Qt.vector4d(0, 0, 0, 0);
        // v11: five more, the remnant's structure and its palette. They are
        // zeroed with the other four, and snRemnant.w / snShell.y are the two
        // switches the kernel tests -- with both at 0 it returns on one compare.
        shader.snBody = extras ? Qt.vector4d(extras.body[0], extras.body[1], extras.body[2], extras.body[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snHot = extras ? Qt.vector4d(extras.hot[0], extras.hot[1], extras.hot[2], extras.hot[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snWisp = extras ? Qt.vector4d(extras.wisp[0], extras.wisp[1], extras.wisp[2], extras.wisp[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snDust = extras ? Qt.vector4d(extras.dust[0], extras.dust[1], extras.dust[2], extras.dust[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snJet = extras ? Qt.vector4d(extras.jet[0], extras.jet[1], extras.jet[2], extras.jet[3]) : Qt.vector4d(1, 0, 0, 0);
        // v12: the six grain populations and the schedule that decides which of
        // them a grain born now belongs to. Zeroed with the rest when no
        // supernova is alive; snGrain.x is the whole switch on the shader side,
        // inside a branch that already needs snRemnant.w > 0.
        shader.snPop0 = extras ? Qt.vector4d(extras.pop0[0], extras.pop0[1], extras.pop0[2], extras.pop0[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snPop1 = extras ? Qt.vector4d(extras.pop1[0], extras.pop1[1], extras.pop1[2], extras.pop1[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snPop2 = extras ? Qt.vector4d(extras.pop2[0], extras.pop2[1], extras.pop2[2], extras.pop2[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snPop3 = extras ? Qt.vector4d(extras.pop3[0], extras.pop3[1], extras.pop3[2], extras.pop3[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snPop4 = extras ? Qt.vector4d(extras.pop4[0], extras.pop4[1], extras.pop4[2], extras.pop4[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snPop5 = extras ? Qt.vector4d(extras.pop5[0], extras.pop5[1], extras.pop5[2], extras.pop5[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snGrain = extras ? Qt.vector4d(extras.grain[0], extras.grain[1], extras.grain[2], extras.grain[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snFlow = extras ? Qt.vector4d(extras.flow[0], extras.flow[1], extras.flow[2], extras.flow[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snTurn = extras ? Qt.vector4d(extras.turn[0], extras.turn[1], extras.turn[2], extras.turn[3]) : Qt.vector4d(0, 0, 0, 0);
        shader.snTurn2 = extras ? Qt.vector4d(extras.turn2[0], extras.turn2[1], extras.turn2[2], extras.turn2[3]) : Qt.vector4d(0, 0, 0, 0);
        for (let i = 0; i < phenomenonSlotCount; ++i) {
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

    // ---- Nebula passage ---------------------------------------------------
    // The one event that is a CLOUD. It is minutes long, it is most of the
    // short side across, and it is the only thing on the sky that takes light
    // AWAY: its dust lanes occlude the far field it passes in front of. So it
    // gets its own uniform block rather than a slot (nothing about a point
    // source fits it), its own entry in _state rather than a place in
    // s.events, and its position is not captured once and replayed but FOLLOWS
    // the far layer's own flow law. That last choice is what makes it drift
    // with the regime, reverse when the camera reverses and stay in step with
    // a field the CPU never simulates, for one subtraction per frame.

    function nebulaConfig(): var {
        const config = eventFamilies || {};
        return (config.events || config).nebula || {};
    }

    function nebulaEnabled(): bool {
        const cfg = nebulaConfig();
        return cfg.enabled === undefined ? true : cfg.enabled !== false;
    }

    // u = r^2/2 in half-short-sides, per unit of the signed geometric
    // accumulator _state.geo[0]. This is the shader's own far-dust law
    // (stars(), layer 0, depth 0.10, boosted by the dust flow), so a cloud
    // advanced by it is travelling WITH the dust rather than beside it.
    function nebulaFlowRate(): real {
        return (6 / 1080) * 0.10 * farBoost();
    }

    // Signed du/dt, for predicting a passage's travel at capture time only:
    // negative while the stream runs inward, positive while the camera flies
    // out. The live position never uses this - it reads _state.geo[0], which
    // already carries the rate, the sign and the crossfade between them.
    function nebulaDriftPerSec(): real {
        const dustRate = 1 + _cameraBlend * (clamp(cameraDustFlow, 0, 64) / Math.max(1e-6, farBoost()) - 1);
        const flowPerSec = clamp(radialSpeed, 0, 26) / 6 * (0.8 + 0.4 * _state.live[2]);
        return -(1 - 2 * _cameraOutward) * dustRate * flowPerSec * nebulaFlowRate() * nebulaDrift();
    }

    // A cloud is not a mote. At the dust's own rate the far layer crosses from
    // the screen edge to the hole in 60-200 s depending on the direction, which
    // is a fly-past rather than a passage; 0.45 of it is the same direction,
    // the same reversal and the same regime crossfade at a speed that reads as
    // something large and far away, and puts a crossing inside the 3-8 min the
    // family is documented at.
    function nebulaDrift(): real {
        const cfg = nebulaConfig();
        return clamp(cfg.driftScale === undefined ? 0.45 : cfg.driftScale, 0.05, 2);
    }

    // Distance from the field's centre to the edge of the buffer along one
    // angle. A passage enters just outside THAT, not outside the corner: the
    // half-diagonal is 1.9x the half-height on his tablet, so entering at the
    // corner radius left a third of the episode off-screen.
    function nebulaBoundary(angle: real): real {
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        return Math.min(0.5 * w / Math.max(0.02, Math.abs(Math.cos(angle))),
            0.5 * h / Math.max(0.02, Math.abs(Math.sin(angle))));
    }

    // The hole's drawn material, which is what a passage dissolves into. This
    // is NOT the phenomenon keep-out: a phenomenon is a point composited after
    // the disk, so one placed there would shine through the hole, while the
    // cloud is part of the far field - the disk composites in front of it and
    // the shadow is subtracted from it. It is therefore allowed to reach the
    // rim, which is where its material is going, and it fades out over the last
    // stretch so nothing ever has to be clipped against the hole.
    function nebulaReach(): real {
        return _hole.enabled ? holeReach() : 0;
    }

    // Where a passage is completely gone, and where it begins to dissolve.
    function nebulaSink(): real {
        const reach = nebulaReach();
        return reach > 0 ? 0.55 * reach : 0;
    }

    function captureNebula(index: int, start: real): var {
        const cfg = nebulaConfig();
        const salt = screenSeed + 7717;
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        if (!(w > 0 && h > 0))
            return null;
        const shortSide = Math.min(w, h);
        const radius = shortSide / 2;
        const optics = Math.max(1, Math.sqrt(w * h / (1024 * 576)));
        function sample(key, fallback, lo, hi, offset) {
            const range = parameterRange(cfg, key, fallback, lo, hi);
            return range[0] + (range[1] - range[0]) * random(index, salt + offset);
        }
        const wanted = sample("durationSec", [180, 480], 60, 1800, 3);
        const entrance = sample("fadeSec", [30, 60], 5, 300, 5);
        const semi = 0.5 * sample("sizeShortSide", [0.40, 0.80], 0.15, 1.2, 7) * shortSide;
        // Which way the far field runs when the passage is captured. The camera
        // regime flies outward, so a cloud begins small and deep and grows past
        // the edges; the infall regime brings it in from off the edge instead.
        const outward = _cameraOutward > 0.5;
        const sink = nebulaSink();
        const exitU = 0.5 * Math.pow(Math.max(sink, 0.06 * shortSide) / radius, 2);
        const drift = nebulaDriftPerSec();
        // Where a passage begins: just outside the buffer under infall, so it
        // arrives from off-screen; at depth near the centre under the camera,
        // so it fades in small and grows. The crossing time is then the FLOW's
        // business, not a captured speed, and the configured duration is what
        // the cloud has at most - one that reaches the disk edge sooner ends
        // there rather than lingering invisibly behind its own schedule.
        // The direction is REJECTED, not clamped, when there is no room in it:
        // the hole's material reaches 740 px on his tablet against a 900 px
        // half-height, so a cloud arriving along the short axis would dissolve
        // into the disk before its centre ever crossed the edge of the buffer.
        // Sixteen attempts, then whatever the last one was.
        let angle = 0, boundary = 0;
        for (let attempt = 0; attempt < 16; ++attempt) {
            // Well clear of the salts the palette and the stars use below: two
            // draws from one salt would tie the entry angle to the colour.
            angle = random(index, salt + 101 + attempt * 2) * 2 * Math.PI;
            boundary = nebulaBoundary(angle);
            if (outward || boundary >= 1.25 * Math.max(sink, 1))
                break;
        }
        const edgeU = 0.5 * Math.pow((boundary + 0.80 * semi) / radius, 2);
        const enterU = outward ? 0.012 : Math.min(12, edgeU);
        const leaveU = outward ? 0.5 * Math.pow((boundary + 1.6 * semi) / radius, 2) : exitU;
        const crossing = Math.abs(drift) > 1e-9 ? Math.abs(enterU - leaveU) / Math.abs(drift) : 1e9;
        const duration = Math.max(30, Math.min(wanted, crossing + 0.5 * entrance));
        const fade = Math.min(entrance, duration * 0.45);
        // The screen radius the cloud will have at MID-passage. In the camera
        // regime its apparent size follows its depth, and this is what the
        // configured size means there: the cloud is that big halfway past,
        // roughly a third of it when it fades in at depth and half again as
        // large when it goes by the edge.
        const midU = Math.max(1e-4, enterU + drift * duration * 0.5);
        const referenceR = Math.max(0.25 * radius, Math.sqrt(2 * midU) * radius);
        const colors = paletteSnapshot();
        const mix = clamp(cfg.paletteMix === undefined ? 0.40 : cfg.paletteMix, 0, 0.45);
        // Cold interstellar grey-blue. A palette hue is mixed toward it, never
        // away from it, so no hue the palette does not list is ever generated
        // and the saturation cap the palette formula applied still holds.
        const neutral = [0.58, 0.66, 0.80];
        function pick(offset) {
            if (!colors.length)
                return -1;
            const weights = normalized(_state.palette, colors.length, null);
            let draw = random(index, salt + offset), chosen = 0;
            for (; chosen < weights.length - 1; ++chosen) {
                draw -= weights[chosen];
                if (draw < 0)
                    break;
            }
            return chosen;
        }
        function tone(chosen) {
            if (chosen < 0)
                return neutral.slice();
            const k = mix / 0.45;
            return [0, 1, 2].map(i => neutral[i] + (colors[chosen][i] - neutral[i]) * k);
        }
        const first = pick(21);
        let second = pick(22);
        if (second === first && colors.length > 1)
            second = (first + 1 + Math.floor(random(index, salt + 23) * (colors.length - 1))) % colors.length;
        const counts = parameterRange(cfg, "stars", [1, 3], 0, 3);
        const count = Math.round(counts[0] + (counts[1] - counts[0]) * random(index, salt + 25));
        const stars = [];
        for (let i = 0; i < count; ++i)
            stars.push([(random(index, salt + 31 + i * 2) * 2 - 1) * 0.52,
                (random(index, salt + 32 + i * 2) * 2 - 1) * 0.52]);
        return {
            family: "nebula",
            index: index,
            start: start,
            duration: duration,
            fade: fade,
            semi: semi,
            // Set the first time the episode is published with a non-negative
            // age, so a passage that waited in the schedule does not arrive
            // already halfway across the sky.
            geo: null,
            enterU: enterU,
            exitU: exitU,
            referenceR: referenceR,
            // Birth-frozen, like every other captured number here. The hole's
            // BOOLEAN flips in one frame while its drawn envelope takes thirty
            // seconds, so a passage reading the boolean live would snap back to
            // full brightness the instant the hole was switched off in the
            // middle of its dissolve. Frozen radii plus the live envelope below
            // eases the whole thing away instead.
            reach: nebulaReach(),
            sink: sink,
            angle: angle,
            boundary: boundary,
            tilt: random(index, salt + 11) * Math.PI,
            aspect: 0.52 + 0.30 * random(index, salt + 13),
            // Two tones, both listed palette hues pulled toward the same cold
            // neutral. Teal and a soft pink are what his default palette gives.
            tone0: tone(first),
            tone1: tone(second),
            gain: clamp(cfg.gain === undefined ? 0.30 : cfg.gain, 0, 0.35),
            dust: clamp(cfg.dustOpacity === undefined ? 0.55 : cfg.dustOpacity, 0, 0.9),
            starGain: count > 0 ? clamp(cfg.starGain === undefined ? 0.45 : cfg.starGain, 0, 0.8) : 0,
            starCore: optics * 0.95,
            stars: stars,
            shortSide: shortSide,
            optics: optics
        };
    }

    // One passage every 20-45 minutes at rateScale 1, and never on the same
    // screen as a supernova remnant. The two directions are covered
    // differently, and deliberately:
    //   - A dramatic family scheduled AFTER a passage is placed reads
    //     familyLast.drama, which a passage writes exactly as the dramatic
    //     families write it, so it takes its turn in the shared cooldown.
    //   - A dramatic episode already on the books is RESERVED against here,
    //     by the overlap test schedule() already uses for the transient heads.
    // Reading familyLast.drama for the second direction is what a dramatic
    // family does, and it is wrong for this one: those families schedule in
    // chronological order, so their `last` is the most recent start, while a
    // passage is scheduled once against whatever the first round of dramatic
    // schedules left there - a gamma-ray burst booked for 90 minutes out was
    // pushing the FIRST passage of a session to 92 minutes, measured, and
    // making `everyMinutes` below ~15 min inert. Reserving against the actual
    // episodes is both stricter (it is the real overlap) and honest about
    // what it costs (nothing, unless they would collide).
    function scheduleNebula(): var {
        const s = _state;
        if (!nebulaEnabled())
            return null;
        const rate = rateScale();
        if (rate <= 0)
            return null;
        const cfg = nebulaConfig();
        const index = s.nebulaId++;
        const salt = screenSeed + 7717;
        let range = parameterRange(cfg, "everyMinutes", [20, 45], 1, 1440).map(x => x * 60);
        range = [range[0] / rate, range[1] / rate];
        const base = s.nebulaLast === null ? s.clock : s.nebulaLast;
        let start = Math.max(s.clock, base + range[0] + (range[1] - range[0]) * random(index, salt));
        const e = captureNebula(index, start);
        if (!e)
            return null;
        for (let pass = 0; pass < 6; ++pass) {
            let moved = false;
            for (let kind = 5; kind < s.events.length; ++kind) {
                const other = s.events[kind];
                if (!dramatic(kind) || !other)
                    continue;
                if (start < other.start + other.duration && start + e.duration > other.start) {
                    start = other.start + other.duration + 1;
                    moved = true;
                }
            }
            if (!moved)
                break;
        }
        e.start = start;
        s.familyLast.drama = start;
        s.nebulaLast = start;
        return e;
    }

    // The published uniform block. A pure function of the clock, the geometric
    // accumulator and the episode, so the offscreen harness can sweep it.
    function nebulaState(e: var): var {
        const off = {
            head: [0, 0, 0, 0],
            shape: [1, 0, 1, 0],
            tone0: [0, 0, 0, 0],
            tone1: [0, 0, 0, 0],
            stars: [-1e6, -1e6, -1e6, -1e6],
            stars2: [-1e6, -1e6, 1, 1],
            bounds: [0, 0, 0, 0]
        };
        if (!e || e.geo === null)
            return off;
        const age = _state.clock - e.start;
        if (age < 0 || age > e.duration)
            return off;
        const w = width * devicePixelRatio, h = height * devicePixelRatio;
        const shortSide = Math.min(w, h), radius = shortSide / 2;
        const zoom = shader.flowZoom === undefined ? 1 : shader.flowZoom.x;
        // The far layer's own coordinate. geo carries the camera's sign, so a
        // reversal walks the cloud back out the way it came in.
        const u = Math.max(1e-6, e.enterU - (_state.geo[0] - e.geo) * nebulaFlowRate());
        const r = Math.sqrt(2 * u) * radius * zoom;
        // Exactly the far layer's centre in stars(): the shared wander at the
        // layer's own depth, plus the far field's bounded parallax.
        const enable = _hole.bhHalo === undefined ? 0 : _hole.bhHalo.w;
        const depth = 0.10 + (1 - 0.10) * enable;
        const parallax = shader.dustParallax === undefined ? {
            x: 0,
            y: 0
        } : shader.dustParallax;
        const cx = w * 0.5 + shader.centreOffset.x * depth + parallax.x;
        const cy = h * 0.5 + shader.centreOffset.y * depth + parallax.y;
        const x = cx + r * Math.cos(e.angle), y = cy + r * Math.sin(e.angle);
        // Perspective. In the camera regime the cloud is a body at a DEPTH, so
        // its apparent size follows its screen radius and it swells as it comes
        // past. Under infall it is not approaching the camera at all - it is
        // crossing the sky at one distance - so its angular size is CONSTANT
        // and the tide is the only thing that reshapes it.
        const scale = clamp(1 + 0.90 * _cameraBlend * (r / Math.max(1, e.referenceR) - 1), 0.12, 2.4);
        const reach = e.reach, sink = e.sink;
        // Tidal field: radial stretch, tangential squeeze, growing as the cloud
        // falls in. The major axis turns from its birth-frozen angle toward the
        // radius as the tide takes hold, so the shear arrives rather than cuts.
        const shear = reach > 0 ? 0.65 * enable * clamp(Math.pow(1.6 * reach / Math.max(r, 1.6 * reach), 2.0), 0, 1) : 0;
        let dx = Math.cos(e.tilt) + (Math.cos(e.angle) - Math.cos(e.tilt)) * shear;
        let dy = Math.sin(e.tilt) + (Math.sin(e.angle) - Math.sin(e.tilt)) * shear;
        const length = Math.max(1e-6, Math.hypot(dx, dy));
        dx /= length;
        dy /= length;
        const major = Math.min(e.semi * scale * (1 + 0.28 * shear), 0.65 * shortSide);
        const aspect = Math.max(0.24, e.aspect * (1 - 0.40 * shear));
        const minor = major * aspect;
        const envTime = ease(age / Math.max(0.001, e.fade)) * ease((e.duration - age) / Math.max(0.001, e.fade));
        // It feeds the disk edge: the cloud dissolves across the last stretch
        // into the rim, is already behind the disk's own composite by then, and
        // the shader subtracts the shadow from the far field it has joined - so
        // nothing of it is ever drawn over the hole itself.
        const envHole = sink > 0 ? 1 - enable * (1 - ease((r - sink) / Math.max(1, 0.90 * reach))) : 1;
        // And gone once it has left the buffer entirely, measured along its own
        // direction rather than at the corner.
        const outer = e.boundary + 1.05 * major;
        const envEdge = 1 - ease((r - outer) / Math.max(1, 0.22 * shortSide));
        const gain = e.gain * envTime * envHole * envEdge;
        if (gain <= 0.0008)
            return off;
        const stars = [-1e6, -1e6, -1e6, -1e6], stars2 = [-1e6, -1e6, Math.max(0.5, e.starCore * (0.6 + 0.4 * scale)), Math.max(2, 0.20 * major)];
        for (let i = 0; i < e.stars.length && i < 3; ++i) {
            const px = x + e.stars[i][0] * major * dx + e.stars[i][1] * minor * -dy;
            const py = y + e.stars[i][0] * major * dy + e.stars[i][1] * minor * dx;
            if (i < 2) {
                stars[i * 2] = px;
                stars[i * 2 + 1] = py;
            } else {
                stars2[0] = px;
                stars2[1] = py;
            }
        }
        // Exact axis-aligned bound of the rotated ellipse.
        const bx = Math.sqrt(major * major * dx * dx + minor * minor * dy * dy);
        const by = Math.sqrt(major * major * dy * dy + minor * minor * dx * dx);
        return {
            head: [x, y, major, gain],
            // The turbulence phase is the EPISODE's age, not the session clock:
            // bounded, exact, and it starts every passage at the same place in
            // its own evolution rather than wherever the process happened to be.
            shape: [dx, dy, aspect, age * 0.012],
            tone0: e.tone0.concat(e.dust),
            tone1: e.tone1.concat(e.starGain),
            stars: stars,
            stars2: stars2,
            bounds: [x - bx, y - by, x + bx, y + by]
        };
    }

    // A forced passage waits for a running one exactly as a pushed phenomenon
    // waits for its family's entry, and is dropped if it is still waiting two
    // minutes later.
    function pushNebula(delaySec: real, overrides: var): bool {
        const s = _state;
        if (!s)
            return false;
        const e = captureNebula(s.nebulaId++, s.clock + Math.max(0, Number(delaySec) || 0));
        if (!e)
            return false;
        if (overrides)
            for (const key of Object.keys(overrides))
                e[key] = overrides[key];
        s.nebulaPending = e;
        return true;
    }

    function publishNebula(): void {
        const s = _state;
        if (s.nebula && s.clock > s.nebula.start + s.nebula.duration)
            s.nebula = null;
        if (s.nebula && s.clock < s.nebula.start && !nebulaEnabled())
            s.nebula = null;
        // A pushed passage waits for a RUNNING one and replaces a merely
        // scheduled one, exactly as drainPending does for a radial family: the
        // next passage is twenty minutes away, and a forced one that waited for
        // it would be no use to anybody.
        const running = s.nebula !== null && s.clock >= s.nebula.start;
        if (s.nebulaPending) {
            if (s.clock > s.nebulaPending.start + 120)
                s.nebulaPending = null;
            else if (!running && s.clock >= s.nebulaPending.start) {
                s.nebulaPending.start = s.clock;
                s.nebula = s.nebulaPending;
                s.nebulaPending = null;
            }
        }
        if (!s.nebula)
            s.nebula = scheduleNebula();
        if (s.nebula && s.nebula.geo === null && s.clock >= s.nebula.start)
            s.nebula.geo = s.geo[0];
        const n = nebulaState(s.nebula);
        // v10. The passage is something the field goes THROUGH, not a sheet of
        // paint in front of it: material inside the cloud is held back (with
        // the camera on, its approach slows, so it moves slower AND stays
        // smaller AND stays dimmer -- all three depth cues together) and takes
        // a little of the cloud's colour. Both are small on purpose.
        if (_particles && _particles.live && particlesEnabled) {
            const cfg = nebulaConfig();
            const share = n.head[3] > 0 && s.nebula ? clamp(n.head[3] / Math.max(1e-6, s.nebula.gain), 0, 1) : 0;
            ParticlePhysics.setCloud(_particles, share > 0.01 ? {
                x: n.head[0], y: n.head[1], radius: n.head[2],
                aspect: n.shape[2], angle: Math.atan2(n.shape[1], n.shape[0]),
                drag: clamp(cfg.drag === undefined ? 0.55 : cfg.drag, 0, 2) * share,
                tint: [n.tone0[0], n.tone0[1], n.tone0[2]],
                weight: clamp(cfg.tint === undefined ? 0.30 : cfg.tint, 0, 1) * share
            } : null);
        }
        // A passage runs for four minutes in every thirty. The rest of the
        // time the block is already off, and rewriting seven vector4ds at
        // 30 Hz on three screens to say so is 630 allocations a second for
        // nothing.
        if (n.head[3] <= 0 && shader.nebulaHead.w <= 0)
            return;
        shader.nebulaHead = Qt.vector4d(n.head[0], n.head[1], n.head[2], n.head[3]);
        shader.nebulaShape = Qt.vector4d(n.shape[0], n.shape[1], n.shape[2], n.shape[3]);
        shader.nebulaTone0 = Qt.vector4d(n.tone0[0], n.tone0[1], n.tone0[2], n.tone0[3]);
        shader.nebulaTone1 = Qt.vector4d(n.tone1[0], n.tone1[1], n.tone1[2], n.tone1[3]);
        shader.nebulaStars = Qt.vector4d(n.stars[0], n.stars[1], n.stars[2], n.stars[3]);
        shader.nebulaStars2 = Qt.vector4d(n.stars2[0], n.stars2[1], n.stars2[2], n.stars2[3]);
        shader.nebulaBounds = Qt.vector4d(n.bounds[0], n.bounds[1], n.bounds[2], n.bounds[3]);
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
            // The only writer of entryPixels; atlasUrl's cached base64 prefix
            // is keyed on this.
            ++s.entryVersion;
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
                const perfAtlas = _perf;
                const tAtlas = perfAtlas ? perfClock.elapsedNs() : 0;
                s.pendingRevision = s.atlasRevision;
                const image = shader.descriptorAtlas === descriptorImage ? descriptorBack : descriptorImage;
                s.pendingImage = image;
                image.source = atlasUrl();
                if (perfAtlas) {
                    perfAtlas.atlas += perfClock.elapsedNs() - tAtlas;
                    ++perfAtlas.atlases;
                }
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
        const perf = _perf;
        const tA = perf ? perfClock.elapsedNs() : 0;
        publishEvents();
        publishNebula();
        const tB = perf ? perfClock.elapsedNs() : 0;
        publishParticles();
        if (perf) {
            const tC = perfClock.elapsedNs();
            perf.events += tB - tA;
            perf.parts += tC - tB;
        }
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
    // The retained halves of prepareParticles: one geometry object and one
    // numeric signature, so neither is rebuilt on a frame that changed nothing.
    property var _particleGeometry: null
    property var _particleSig: [NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN]
    property bool _particleSigDirty: true
    property string _particleSignature: ""
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
        // One retained object: this runs twice a frame per output and Physics
        // only reads it, so a fresh one every time was garbage for nothing.
        const geometry = _particleGeometry || (_particleGeometry = {
            innerRs: 0,
            outerRs: 0,
            arcGain: 0,
            arcRadiusRh: 0,
            arcSpacingRh: 0,
            arcCount: 0
        });
        const disk = _hole.bhDisk, arcs = _hole.bhArcs;
        geometry.innerRs = disk.x;
        geometry.outerRs = disk.y;
        geometry.arcGain = arcs.x;
        geometry.arcRadiusRh = arcs.y;
        geometry.arcSpacingRh = arcs.z;
        geometry.arcCount = arcs.w;
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
            _particleSigDirty = true;
        }
        // Building a ten-part string and comparing it was the rest of that
        // garbage, twice a frame per output, to answer a question that ten
        // number comparisons answer. The signature stays a string because the
        // published snapshot and publishParticles compare it by value; it just
        // only changes when something in it does.
        const sig = _particleSig;
        if (_particleSigDirty || sig[0] !== w || sig[1] !== h || sig[2] !== rh
            || sig[3] !== geometry.innerRs || sig[4] !== geometry.outerRs
            || sig[5] !== geometry.arcGain || sig[6] !== geometry.arcRadiusRh
            || sig[7] !== geometry.arcSpacingRh || sig[8] !== geometry.arcCount) {
            _particleSigDirty = false;
            sig[0] = w;
            sig[1] = h;
            sig[2] = rh;
            sig[3] = geometry.innerRs;
            sig[4] = geometry.outerRs;
            sig[5] = geometry.arcGain;
            sig[6] = geometry.arcRadiusRh;
            sig[7] = geometry.arcSpacingRh;
            sig[8] = geometry.arcCount;
            _particleSignature = _particleSettingsText + ":" + sig.join(":");
        }
        const signature = _particleSignature;
        if (!_particles) {
            _particles = ParticlePhysics.create(w, h, rh, screenSeed ^ varietySeed, _particleSettings, undefined, geometry);
            // v10: the optical half of a transient birth. Physics must not reach
            // into Appearance's arrays, so it is handed in exactly the way the
            // ordinary birth callback is.
            _particles.transientBirth = (pool, index, traits) => ParticleAppearance.transient(pool, index, traits);
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
        const perf = _perf;
        const t0 = perf ? perfClock.elapsedNs() : 0;
        ParticlePhysics.advance(_particles, dt, radialSpeed, s.live[2], cx, cy, blackHole && blackHole.disk && blackHole.disk.rotationSign < 0 ? -1 : 1, _particleBirth);
        if (perf)
            perf.physics += perfClock.elapsedNs() - t0;
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
        const perf = _perf;
        const t0 = perf ? perfClock.elapsedNs() : 0;
        _particleItems = ParticleAppearance.render(_particleItems, pool, {
            twinkle: shader.twinkle
        });
        const t1 = perf ? perfClock.elapsedNs() : 0;
        _particleBins = ParticleBinning.build(_particleBins, _particleItems, pool.width, pool.height, perf ? perf.sub : undefined);
        const t2 = perf ? perfClock.elapsedNs() : 0;
        if (perf) {
            perf.render += t1 - t0;
            perf.bin += t2 - t1;
        }
        const canvas = shader.particleAtlas === particleFront ? particleBack : particleFront;
        // One height for BOTH buffers, sized for every population this
        // configuration can reach, so the sampled texture is allocated once and
        // never resized. One resize of it cost 13 ms -> 6700 ms per frame of
        // scene-graph submission on llvmpipe and did not recover.
        if (!_particleAtlasHeight) {
            const ceiling = ParticleAppearance.bounds(pool);
            _particleAtlasHeight = ParticlePacking.capacity(_particleBins, ceiling.maxItems, ceiling.maxSupport, ceiling.maxFlares, ceiling.flareSupport, ceiling.maxBends, ceiling.bendSupport, ceiling.maxTde, ceiling.tdeSupport, ceiling.maxWide, ceiling.wideSupport);
        }
        const t3 = perf ? perfClock.elapsedNs() : 0;
        const layout = ParticlePacking.layout(canvas.packet, _particleBins, _particleItems.count, _particleAtlasHeight);
        if (perf)
            perf.layout += perfClock.elapsedNs() - t3;
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
        property vector4d event5Head: Qt.vector4d(0, 0, 0, 0)
        property vector4d event5Colour: Qt.vector4d(0, 0, 0, 3)
        property vector4d event5Tail01: Qt.vector4d(0, 0, 0, 0)
        property vector4d event5Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d event5Bounds: Qt.vector4d(0, 0, 0, 0)
        // ---- v9 extras. This order IS the std140 layout in starfield.frag:
        // supernova (64 B), storm (64 B), nebula (112 B), 1600 -> 1840 B.
        // v9 supernova extras, 144 B since v11. One supernova is alive at a
        // time, so these ride beside the phenomenon slots rather than inside
        // one. The last five are the remnant's structure and palette; Qt binds
        // by name, but this order IS the layout in starfield.frag, so keep it.
        property vector4d snRemnant: Qt.vector4d(0, 0, 0, 0)
        property vector4d snTone: Qt.vector4d(0, 0, 0, 0)
        property vector4d snShell: Qt.vector4d(0, 0, 0, 0)
        property vector4d snExtra: Qt.vector4d(0, 0, 0, 0)
        property vector4d snBody: Qt.vector4d(0, 0, 0, 0)
        property vector4d snHot: Qt.vector4d(0, 0, 0, 0)
        property vector4d snWisp: Qt.vector4d(0, 0, 0, 0)
        property vector4d snDust: Qt.vector4d(0, 0, 0, 0)
        property vector4d snJet: Qt.vector4d(1, 0, 0, 0)
        // v12 grain populations, 160 B. Qt binds a `vector4d` property to the
        // uniform of the same name, which is why these are ten named vectors
        // and not one array: a std140 `vec4 snPop[6]` would need `snPop[0]`
        // style names that a QML property cannot carry.
        property vector4d snPop0: Qt.vector4d(0, 0, 0, 0)
        property vector4d snPop1: Qt.vector4d(0, 0, 0, 0)
        property vector4d snPop2: Qt.vector4d(0, 0, 0, 0)
        property vector4d snPop3: Qt.vector4d(0, 0, 0, 0)
        property vector4d snPop4: Qt.vector4d(0, 0, 0, 0)
        property vector4d snPop5: Qt.vector4d(0, 0, 0, 0)
        property vector4d snGrain: Qt.vector4d(0, 0, 0, 0)
        property vector4d snFlow: Qt.vector4d(0, 0, 0, 0)
        property vector4d snTurn: Qt.vector4d(0, 0, 0, 0)
        property vector4d snTurn2: Qt.vector4d(0, 0, 0, 0)
        // The meteor storm: one slot for the whole shower, however many streaks
        // are in the air. stormShape.w is the gain AND the off switch.
        property vector4d stormHead: Qt.vector4d(0, 0, 0, 0)
        property vector4d stormShape: Qt.vector4d(1, 0, 0, 0)
        property vector4d stormColour: Qt.vector4d(1, 1, 1, 0)
        property vector4d stormSpan: Qt.vector4d(0, 0, 0, 0)
        // The nebula passage. One cloud, so one block instead of a slot; it
        // composites into the far field, under the particles and under the
        // disk, because it is the only event with extinction of its own.
        property vector4d nebulaHead: Qt.vector4d(0, 0, 0, 0)
        property vector4d nebulaShape: Qt.vector4d(1, 0, 1, 0)
        property vector4d nebulaTone0: Qt.vector4d(0, 0, 0, 0)
        property vector4d nebulaTone1: Qt.vector4d(0, 0, 0, 0)
        property vector4d nebulaStars: Qt.vector4d(-1000000, -1000000, -1000000, -1000000)
        property vector4d nebulaStars2: Qt.vector4d(-1000000, -1000000, 1, 1)
        property vector4d nebulaBounds: Qt.vector4d(0, 0, 0, 0)
        // ---- v12 meteors, 128 B, APPENDED to the block so no offset above it
        // moves and the offline sheets that re-declare the layout by hand keep
        // reading what they already read.
        //   eventNBurn = (F, headPathU, pathSpan, speed01)
        //   meteorTone / stormTone = (naGain, trainGain, leadGain, curveSharp)
        //   stormBurn  = (curveF, curveSpread, flareShare, doublePeakShare)
        //   stormTrain = (trainShare, trainWindow, trainSecLo, trainSecHi)
        //   stormWind  = (windPxPerSec, foldSec, trainGain, diffuseSec)
        property vector4d event0Burn: Qt.vector4d(0.52, 0, 0, 0)
        property vector4d event1Burn: Qt.vector4d(0.52, 0, 0, 0)
        property vector4d event2Burn: Qt.vector4d(0.52, 0, 0, 0)
        property vector4d meteorTone: Qt.vector4d(0, 0, 0, 4.5)
        property vector4d stormTone: Qt.vector4d(0, 0, 0, 4.5)
        property vector4d stormBurn: Qt.vector4d(0.52, 0.09, 0, 0)
        property vector4d stormTrain: Qt.vector4d(0, 0, 0, 0)
        property vector4d stormWind: Qt.vector4d(0, 0, 0, 0)
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
        // Immediate, NOT Threaded. Measured 2026-09-17 on the tablet: Threaded
        // moved nothing off the main thread -- Qt runs the onPaint JS on the GUI
        // thread either way and only the rasterisation crosses -- and cost 15.4
        // -> 15.8 % of a core per output, plus a QQuickContext2D thread and 0.6
        // points more on QSGRenderThread for the command buffer. V12's
        // "unverified one-liner" is a loss; do not re-propose it.
        renderStrategy: Canvas.Immediate
        property var pixels: null
        property var packet: null
        property var snapshot: null
        property int paintedRevision: 0
        onPaint: {
            if (!snapshot)
                return;
            const perf = root._perf;
            const t0 = perf ? root.perfClock.elapsedNs() : 0;
            const ctx = getContext("2d");
            packet = ParticlePacking.pack(packet, snapshot.bins, snapshot.items, snapshot, (w, h) => {
                pixels = ctx.createImageData(w, h);
                return pixels.data;
            }, perf ? perf.sub : undefined);
            const t1 = perf ? root.perfClock.elapsedNs() : 0;
            // Qt 6 requires the explicit dirty rectangle for this data upload;
            // it also keeps the upload proportional to the texels actually used
            // rather than to the once-allocated texture.
            ctx.putImageData(pixels, 0, 0, 0, 0, width, Math.min(height, Math.ceil(packet.texelsUsed / width)));
            paintedRevision = packet.revision;
            if (perf) {
                const t2 = root.perfClock.elapsedNs();
                perf.pack += t1 - t0;
                perf.upload += t2 - t1;
                perf.paint += t2 - t0;
                ++perf.paints;
            }
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
