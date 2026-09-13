// The QML half of the v10 comet, driven headlessly: loads the real
// Starfield.qml WITH its real particle pool, force-fires a comet the way
// `caelestia shell starfield fire comet` does, and measures the two things he
// reported wrong (ledger 2285) -- how fast it goes against the field it is
// crossing, and which way its tail points. test-events covers the tail
// geometry against every heading; this covers the live body.
//
//   cd modules/background && QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
//     /usr/lib/qt6/bin/qml tools/comet_harness.qml
//
// QT_ASSUME_STDERR_HAS_CONSOLE is not optional: without it every console.log
// here is silently dropped and the run looks like it printed nothing.
import QtQuick
import ".."

Item {
    id: root

    // His tablet's real device buffer.
    width: 2880
    height: 1800

    property int failures: 0
    property int step: 0
    property real clock: 0
    property var track: []

    function advanceBy(seconds, grain) {
        const dt = grain === undefined ? 0.25 : grain;
        for (let i = 0; i < Math.round(seconds / dt); ++i) {
            field.seek(clock += dt);
            field._particlePending = null;
            field.publishEvents();
            field.publishParticles();
            const e = field._state.events[1];
            if (!e || clock < e.start || clock > e.start + e.duration)
                continue;
            const head = shader().event0Head.w > 0 ? shader().event0Head : shader().event1Head;
            const ion = shader().event0Head.w > 0 ? shader().event0Tail01 : shader().event1Tail01;
            const dust = shader().event0Head.w > 0 ? shader().event0Tail23 : shader().event1Tail23;
            track.push({
                t: clock,
                age: clock - e.start,
                x: head.x,
                y: head.y,
                gain: head.w,
                vx: e.vel ? e.vel[0] : 0,
                vy: e.vel ? e.vel[1] : 0,
                ionX: ion.x,
                ionY: ion.y,
                dustX: dust.x,
                dustY: dust.y,
                body: e.body,
                alive: e.body >= 0 && field._particles.alive[e.body] ? 1 : 0,
                motes: transients(field._particles, 2)
            });
        }
    }

    function transients(pool, group) {
        let n = 0;
        for (let k = 0; k < pool.liveCount; ++k) {
            const i = pool.live[k];
            if (pool.transient[i] && pool.p2[i] === group)
                ++n;
        }
        return n;
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

    // Degrees between a tail direction and the direction the nucleus is going
    // AWAY from -- 0 is straight behind it, 180 is straight ahead of it.
    function lag(f, tx, ty) {
        const speed = Math.hypot(f.vx, f.vy);
        if (speed < 1e-6)
            return 0;
        const bx = -f.vx / speed, by = -f.vy / speed;
        return Math.acos(Math.max(-1, Math.min(1, tx * bx + ty * by))) * 180 / Math.PI;
    }

    function onScreen(f) {
        return f.x > -0.05 * root.width && f.x < 1.05 * root.width && f.y > -0.05 * root.height && f.y < 1.05 * root.height;
    }

    Starfield {
        id: field

        anchors.fill: parent
        running: false
        devicePixelRatio: 1
        screenSeed: 5
        paletteColors: [[0.72, 1, 0.86], [1, 0.86, 0.86]]
        paletteWeightsTarget: [0.5, 0.5]
        blackHole: ({
                enabled: false,
                preset: "target"
            })
        particlesEnabled: true
        eventFamilies: ({
                rateScale: 0
            })
        meteorsEnabled: false
        satellitesEnabled: false
    }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            if (step === 0) {
                advanceBy(120, 2);
                expect("the camera regime has taken over", field._cameraBlend === 1);
                expect("the field is populated", field._particles.aliveCount > 400, field._particles.aliveCount + " particles");
                root.track = [];
                expect("fire comet is accepted", field.pushEvent("comet", 0, {
                    family: "slow"
                }) === true);
                field.publishEvents();
                const e = field._state.events[1];
                expect("and it puts a real body on the field", e.body >= 0 && field._particles.alive[e.body] === 1 && field._particles.transient[e.body] === 1, "particle " + e.body);
                expect("3-8x the field it is crossing", e.ratio >= 3 && e.ratio <= 8.5, e.speed.toFixed(0) + " px/s against a field at " + e.flowAt.toFixed(1) + " px/s = " + e.ratio.toFixed(1) + "x");
                expect("and it is on screen for 8-25 s", e.duration >= 8 && e.duration <= 25, e.duration.toFixed(1) + " s over a " + e.distance.toFixed(0) + " px chord");
            } else if (step === 1) {
                const e = field._state.events[1];
                advanceBy(e.duration - 0.5, 0.25);
                const seen = track.filter(f => f.gain > 0.02 && onScreen(f));
                if (seen.length < 10) {
                    expect("the comet was drawn", false, seen.length + " frames of " + track.length);
                    ++step;
                    return;
                }
                let worstIon = 0, worstDust = 0, ahead = 0;
                for (const f of seen) {
                    worstIon = Math.max(worstIon, lag(f, f.ionX, f.ionY));
                    worstDust = Math.max(worstDust, lag(f, f.dustX, f.dustY));
                    if (lag(f, f.ionX, f.ionY) > 90 || lag(f, f.dustX, f.dustY) > 90)
                        ++ahead;
                }
                expect("both tails trail the motion the whole way across", worstIon <= 30 && worstDust <= 30, seen.length + " frames, worst ion " + worstIon.toFixed(1) + " deg, worst dust " + worstDust.toFixed(1) + " deg");
                expect("and neither ever points ahead of the nucleus", ahead === 0, ahead + " frames with a tail in front");
                const first = seen[0], last = seen[seen.length - 1];
                const travelled = Math.hypot(last.x - first.x, last.y - first.y);
                const elapsed = last.t - first.t;
                expect("it crosses the field at its own speed", travelled / elapsed > 3 * e.flowAt, travelled.toFixed(0) + " px in " + elapsed.toFixed(1) + " s = " + (travelled / elapsed).toFixed(0) + " px/s against " + e.flowAt.toFixed(1) + " px/s");
                // A chord, and a curved one.
                let bow = 0;
                const ux = (last.x - first.x) / travelled, uy = (last.y - first.y) / travelled;
                for (const f of seen)
                    bow = Math.max(bow, Math.abs((f.x - first.x) * -uy + (f.y - first.y) * ux));
                expect("on a long chord, slightly curved", travelled > 0.8 * Math.min(root.width, root.height) && bow > 4, "chord " + travelled.toFixed(0) + " px, bow " + bow.toFixed(0) + " px");
                expect("and it sheds material along it", Math.max(...seen.map(f => f.motes)) >= 4, Math.max(...seen.map(f => f.motes)) + " motes alive at once");
            } else if (step === 2) {
                advanceBy(30, 1);
                const pool = field._particles;
                expect("nothing is left behind when it has gone", transients(pool, 2) === 0 && shader().event0Head.w === 0 && shader().event1Head.w === 0, transients(pool, 2) + " motes, gain " + shader().event0Head.w.toFixed(3));
                // The other regime: the hole is the light source, and gravity
                // is what curves the pass.
                field.blackHole = ({
                        enabled: true,
                        preset: "target"
                    });
                advanceBy(90, 2);
                expect("the orbital regime has taken over", field._cameraBlend === 0);
                root.track = [];
                expect("fire comet is accepted with the hole on", field.pushEvent("comet", 0, {
                    family: "bent"
                }) === true);
                field.publishEvents();
                const e = field._state.events[1];
                expect("it is still a body, and still faster than the field", e.body >= 0 && e.speed > e.flowAt, e.speed.toFixed(0) + " px/s against " + e.flowAt.toFixed(1) + " px/s = " + e.ratio.toFixed(1) + "x");
            } else if (step === 3) {
                const e = field._state.events[1];
                advanceBy(e.duration - 0.5, 0.25);
                const seen = track.filter(f => f.gain > 0.02 && onScreen(f));
                if (seen.length < 8) {
                    expect("the orbital comet was drawn", false, seen.length + " frames");
                    ++step;
                    return;
                }
                let ahead = 0, antiHole = 0;
                for (const f of seen) {
                    if (lag(f, f.dustX, f.dustY) > 90 || lag(f, f.ionX, f.ionY) > 100)
                        ++ahead;
                    const hx = f.x - e.light[0], hy = f.y - e.light[1], hl = Math.hypot(hx, hy);
                    if (hl > 1 && (f.ionX * hx + f.ionY * hy) / hl > 0.9)
                        ++antiHole;
                }
                expect("the dust still trails the motion and nothing is ahead of it", ahead === 0, seen.length + " frames, " + ahead + " with a tail in front");
                expect("and the ion tail is anti-sunward where it can be", antiHole > 0.4 * seen.length, antiHole + " of " + seen.length + " frames pointing away from the hole");
                let bend = 0;
                const v0 = Math.atan2(seen[0].vy, seen[0].vx), v1 = Math.atan2(seen[seen.length - 1].vy, seen[seen.length - 1].vx);
                bend = Math.abs(((v1 - v0 + Math.PI * 3) % (Math.PI * 2)) - Math.PI) * 180 / Math.PI;
                expect("gravity bends the pass for real", bend > 1, "velocity turned " + bend.toFixed(1) + " deg on the way past");
            } else {
                console.log(failures === 0 ? "\nQML COMET HARNESS PASS" : "\nQML COMET HARNESS FAIL (" + failures + ")");
                Qt.exit(failures === 0 ? 0 : 1);
            }
            ++step;
        }
    }
}
