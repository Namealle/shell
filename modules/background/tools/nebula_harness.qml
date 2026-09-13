// The QML half of the nebula passage, driven headlessly: loads the real
// Starfield.qml, force-fires a passage the way `caelestia shell starfield fire
// nebula` does, and checks what publish() actually writes into the uniform
// block across a whole episode and across a change of regime. Node covers the
// scheduler and nebula_sheet.py covers the pixels; this covers the part only
// QML runs -- the property block, publishNebula() and the live regime.
//
//   cd modules/background && QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
//     /usr/lib/qt6/bin/qml tools/nebula_harness.qml
//
// QT_ASSUME_STDERR_HAS_CONSOLE is not optional: without it every console.log
// here is silently dropped and the run looks like it printed nothing.
import QtQuick
import ".."
import "../particles/Physics.js" as ParticlePhysics

Item {
    id: root

    // The tablet's real device buffer: the crossing time is the flow's
    // business, so a passage on a small buffer is honestly a short one.
    width: 2880
    height: 1800

    property int failures: 0
    property int step: 0
    property real clock: 0
    property var track: []

    // publish() returns early while the descriptor atlas is decoding, and the
    // atlas decodes through the event loop, which a tight seek loop inside one
    // timer tick never gives back. The uniform block would then only be written
    // on whichever publish happened to find it ready. publishNebula() is called
    // explicitly for the same reason camera_harness reads internals: this is
    // the shipped function, against the shipped state, writing the real block.
    function advanceBy(seconds) {
        for (let i = 0; i < seconds; ++i) {
            field.seek(++clock);
            field.publishNebula();
            const head = shader().nebulaHead;
            if (head.w > 0)
                track.push({
                    t: clock,
                    x: head.x,
                    y: head.y,
                    semi: head.z,
                    gain: head.w,
                    aspect: shader().nebulaShape.z,
                    phase: shader().nebulaShape.w,
                    opacity: shader().nebulaTone0.w,
                    starGain: shader().nebulaTone1.w,
                    // PLAIN NUMBERS. Reading a vector4d property hands back a
                    // wrapper that aliases the live property, so storing the
                    // wrapper made every captured frame report whatever the
                    // block held at the END of the run - zeros, once the
                    // passage was over.
                    x0: shader().nebulaBounds.x,
                    y0: shader().nebulaBounds.y,
                    x1: shader().nebulaBounds.z,
                    y1: shader().nebulaBounds.w
                });
        }
    }

    function shader() {
        for (let i = 0; i < field.children.length; ++i)
            if (field.children[i].objectName === "starfieldShader")
                return field.children[i];
        return null;
    }

    function expect(name, ok, detail) {
        console.log((ok ? "ok    " : "FAIL  ") + name + (detail === undefined ? "" : "   " + detail));
        if (!ok)
            ++failures;
    }

    function radius(f) {
        return Math.hypot(f.x - root.width * 0.5, f.y - root.height * 0.5);
    }

    Starfield {
        id: field

        anchors.fill: parent
        running: false
        devicePixelRatio: 1
        screenSeed: 7
        paletteColors: [[0.72, 1, 0.86], [1, 0.86, 0.86]]
        paletteWeightsTarget: [0.5, 0.5]
        blackHole: ({
                enabled: true,
                preset: "target"
            })
        particlesEnabled: true
    }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            if (step === 0) {
                advanceBy(60);
                expect("publish() reached the shader at all", shader().resolution.x === root.width,
                    "resolution " + shader().resolution.x + "x" + shader().resolution.y);
                expect("nothing is drawn before a passage is due",
                    shader().nebulaHead.w === 0, "gain " + shader().nebulaHead.w);
                expect("fire nebula is accepted", field.pushEvent("nebula", 0, null) === true);
                root.track = [];
                advanceBy(400);
                expect("the passage was drawn", track.length > 90,
                    track.length + " of " + field._state.nebula.duration.toFixed(0) + " published seconds");
            } else if (step === 1) {
                if (track.length < 3) { expect("the passage was published", false, track.length + " seconds"); ++step; return; }
                const first = track[0], peak = track.reduce((a, b) => a.gain > b.gain ? a : b);
                const last = track[track.length - 1];
                expect("it fades in and out rather than appearing",
                    first.gain < 0.05 && last.gain < 0.05 && peak.gain > 0.2,
                    first.gain.toFixed(3) + " -> " + peak.gain.toFixed(3) + " -> " + last.gain.toFixed(3));
                let worst = 0;
                for (let i = 1; i < track.length; ++i)
                    if (track[i].t - track[i - 1].t <= 1.001)
                        worst = Math.max(worst, Math.abs(track[i].gain - track[i - 1].gain));
                expect("with no step in the envelope", worst < 0.02, worst.toFixed(4) + " per second");
                expect("it drifts inward with the infall",
                    radius(last) < radius(first) - 0.1 * Math.min(root.width, root.height),
                    "r " + radius(first).toFixed(0) + " -> " + radius(last).toFixed(0) + " px");
                expect("the tide shears it as it approaches",
                    last.aspect < first.aspect - 0.01,
                    "aspect " + first.aspect.toFixed(2) + " -> " + last.aspect.toFixed(2));
                expect("its internal turbulence advances",
                    peak.phase > first.phase && peak.phase < 12,
                    "phase " + first.phase.toFixed(2) + " -> " + peak.phase.toFixed(2));
                expect("it is 40-110 % of the short side",
                    2 * peak.semi >= 0.40 * Math.min(root.width, root.height)
                    && 2 * peak.semi <= 1.10 * Math.min(root.width, root.height),
                    (200 * peak.semi / Math.min(root.width, root.height)).toFixed(0) + " %");
                expect("its dust and its stars are published",
                    peak.opacity > 0 && peak.starGain >= 0,
                    "opacity " + peak.opacity.toFixed(2) + ", star gain " + peak.starGain.toFixed(2));
                expect("nothing is left on the block when it ends",
                    shader().nebulaHead.w === 0, "gain " + shader().nebulaHead.w);
            } else if (step === 2) {
                // The toggle: exactly what starfield-hole off writes.
                field.blackHole = ({
                        enabled: false,
                        preset: "target"
                    });
                advanceBy(60);
                expect("the camera regime has taken over", field._cameraBlend === 1);
                expect("fire nebula is accepted in the camera regime",
                    field.pushEvent("nebula", 0, null) === true);
                root.track = [];
                advanceBy(500);
                expect("the passage was drawn there too", track.length > 90,
                    track.length + " published seconds");
            } else if (step === 3) {
                if (track.length < 3) { expect("the camera passage was published", false, track.length + " seconds"); ++step; return; }
                const first = track[0], last = track[track.length - 1];
                expect("it drifts outward with the camera",
                    radius(last) > radius(first),
                    "r " + radius(first).toFixed(0) + " -> " + radius(last).toFixed(0) + " px");
                expect("and grows with its depth",
                    last.semi > first.semi * 1.4,
                    first.semi.toFixed(0) + " -> " + last.semi.toFixed(0) + " px");
                let worstBound = 0, worstAt = "";
                for (const f of track) {
                    const width = f.x1 - f.x0;
                    const low = 2 * f.semi * f.aspect, high = 2 * f.semi;
                    const off = Math.max(low - width, width - high, 0);
                    if (off > worstBound) {
                        worstBound = off;
                        worstAt = "t=" + f.t + " width " + width.toFixed(1) + " for " + low.toFixed(1) + ".." + high.toFixed(1);
                    }
                }
                expect("its bounds always contain its own ellipse", worstBound <= 1,
                    track.length + " frames, worst " + worstBound.toFixed(2) + " px" + (worstAt ? " (" + worstAt + ")" : ""));
                // Reverse, mid-passage, and watch the same cloud turn around.
                field.pushEvent("nebula", 0, null);
                advanceBy(120);
                const before = shader().nebulaHead;
                const r0 = radius({
                    x: before.x,
                    y: before.y
                });
                field.cameraDirection = "in";
                advanceBy(60);
                const after = shader().nebulaHead;
                // v10: the passage reaches the PARTICLES, not only the light
                // in front of them.
                const pool = field._particles;
                expect("the passage is handed to the particle field",
                    pool.cloud !== null && pool.cloud.drag > 0 && pool.cloud.weight > 0,
                    pool.cloud ? "drag " + pool.cloud.drag.toFixed(3) + ", tint " + pool.cloud.weight.toFixed(3) + ", radius " + pool.cloud.radius.toFixed(0) + " px" : "no cloud");
                let inside = 0;
                for (let k = 0; k < pool.liveCount; ++k)
                    if (ParticlePhysics.cloudWeight(pool, pool.live[k]) > 0.1)
                        ++inside;
                expect("and there is material inside it", inside > 5, inside + " particles in the cloud");
                expect("a reversal turns the cloud around, mid-passage",
                    after.w > 0 && radius({
                        x: after.x,
                        y: after.y
                    }) < r0,
                    "r " + r0.toFixed(0) + " -> " + radius({
                        x: after.x,
                        y: after.y
                    }).toFixed(0) + " px");
            } else {
                console.log(failures === 0 ? "\nQML NEBULA HARNESS PASS" : "\nQML NEBULA HARNESS FAIL (" + failures + ")");
                Qt.exit(failures === 0 ? 0 : 1);
            }
            ++step;
        }
    }
}
