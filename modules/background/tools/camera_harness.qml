// The QML half, driven headlessly: loads the real Starfield.qml, toggles the
// black hole the way ~/namealle/scripts/starfield-hole does and checks the
// regime follows. Node covers the particle modules and camera_flow.py covers
// the shader; this covers the part only QML runs -- the bindings, the envelope,
// publish() and the uniforms it writes.
//
//   cd modules/background && QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
//     /usr/lib/qt6/bin/qml tools/camera_harness.qml
//
// QT_ASSUME_STDERR_HAS_CONSOLE is not optional: without it every console.log
// here is silently dropped and the run looks like it printed nothing.
// The ShaderEffect does not RENDER offscreen, so this reads uniforms, never
// pixels; camera_flow.py is the one that renders.
import QtQuick
import ".."

Item {
    id: root

    width: 1080
    height: 1920

    property int failures: 0
    property int step: 0
    // The renderer's own clock, driven explicitly: `time` only moves under the
    // frame loop, which a headless harness does not run. One second per seek,
    // so the 30 s envelope is sampled thirty times rather than jumped.
    property real clock: 0

    function advanceBy(seconds) {
        for (let i = 0; i < seconds; ++i)
            field.seek(++clock);
    }

    // The ShaderEffect is internal; it carries an objectName so verification can
    // find it without the renderer exposing its uniforms.
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

    function radial(sign) {
        let n = 0, right = 0;
        const p = field._particles;
        for (let k = 0; k < p.liveCount; ++k) {
            const i = p.live[k];
            const dx = p.x[i] - p.centreX, dy = p.y[i] - p.centreY;
            const dot = dx * p.vx[i] + dy * p.vy[i];
            if (Math.abs(dot) > 1e-6) {
                ++n;
                if (dot * sign > 0)
                    ++right;
            }
        }
        return [right, n];
    }

    Starfield {
        id: field

        anchors.fill: parent
        running: false
        devicePixelRatio: 1
        screenSeed: 7
        paletteColors: [[0.72, 1, 0.86], [1, 0.97, 0.82]]
        paletteWeightsTarget: [0.5, 0.5]
        blackHole: ({
                enabled: true,
                preset: "target"
            })
        particlesEnabled: true
    }

    property int captures: 0

    // One step per tick: the descriptor atlas is decoded through the event loop,
    // so publish() only finishes its uniforms once control has been given back.
    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            if (step === 0) {
                advanceBy(90);
                root.captures = field._particles.counters.captures;
                expect("the orbital regime runs", field._particles.aliveCount > 500,
                    field._particles.aliveCount + " stars");
                expect("the camera is off while the hole is on",
                    field._cameraBlend === 0 && field._cameraWanted === false);
                expect("the hole is still capturing", root.captures > 0, root.captures + " captures");
                expect("publish() reached the shader at all", shader().resolution.x === root.width,
                    "resolution " + shader().resolution.x + "x" + shader().resolution.y);
                expect("radialMode is the plain inward stream", shader().radialMode === 1,
                    String(shader().radialMode));
            } else if (step === 1) {
                // The toggle: exactly what starfield-hole off writes.
                field.blackHole = ({
                        enabled: false,
                        preset: "target"
                    });
                advanceBy(15);
                const mid = field._cameraBlend;
                expect("the regime crossfades rather than switching", mid > 0.05 && mid < 0.95,
                    "blend " + mid.toFixed(3) + " halfway through the 30 s envelope");
                expect("the hole's envelope is its exact complement",
                    Math.abs(mid + field._hole.bhHalo.w - 1) < 1e-9,
                    "camera " + mid.toFixed(4) + " + hole " + field._hole.bhHalo.w.toFixed(4));
            } else if (step === 2) {
                expect("the shader is told, in radialMode's fraction",
                    Math.abs(shader().radialMode - (1 + field._cameraBlend)) < 1e-6,
                    "radialMode " + shader().radialMode.toFixed(3) + " for blend " + field._cameraBlend.toFixed(3));
                advanceBy(60);
                expect("the camera has taken over", field._cameraBlend === 1);
                // Captures during the crossfade are correct: half an envelope is
                // still half a hole. What must stop is captures once it is over,
                // so the baseline is taken here rather than before the toggle.
                root.captures = field._particles.counters.captures;
                expect("the population came back after the change",
                    field._particles.aliveCount > 480, field._particles.aliveCount + " stars");
                let core = 0;
                const p = field._particles;
                for (let k = 0; k < p.liveCount; ++k) {
                    const i = p.live[k];
                    if (Math.hypot(p.x[i] - p.centreX, p.y[i] - p.centreY) < p.rh)
                        ++core;
                }
                const out = radial(1);
                expect("every star is flying outward", out[1] > 200 && out[0] === out[1],
                    out[0] + " of " + out[1]);
                expect("nothing is parked in the centre", core < 25, core + " inside 1 Rh");
            } else if (step === 3) {
                expect("the shader has the fully reversed stream", shader().radialMode === 2,
                    String(shader().radialMode));
                // starfield-camera in
                field.cameraDirection = "in";
                advanceBy(60);
                const back = radial(-1);
                expect("nothing is captured once the camera is fully on",
                    field._particles.counters.captures === root.captures,
                    root.captures + " captures, unchanged over a further 60 s");
                expect("reverse turns every star around", back[1] > 200 && back[0] === back[1],
                    back[0] + " of " + back[1]);
                expect("the population survived the reversal",
                    field._particles.aliveCount > 480, field._particles.aliveCount + " stars");
            } else if (step === 4) {
                expect("the far field goes back to the inward stream it already had",
                    shader().radialMode === 1, String(shader().radialMode));
                expect("the geometric accumulators stay finite and signed",
                    field._state.geo.every(v => Number.isFinite(v)),
                    JSON.stringify(field._state.geo.map(v => Number(v.toFixed(1)))));
                // starfield-hole on
                field.cameraDirection = "out";
                field.blackHole = ({
                        enabled: true,
                        preset: "target"
                    });
                advanceBy(60);
                expect("turning the hole back on restores the orbital regime",
                    field._cameraBlend === 0 && field._particles.aliveCount > 480,
                    field._particles.aliveCount + " stars, blend " + field._cameraBlend);
                expect("and it captures again",
                    field._particles.counters.captures > root.captures,
                    root.captures + " -> " + field._particles.counters.captures + " captures");
            } else {
                expect("radialMode is back to the plain inward stream", shader().radialMode === 1,
                    String(shader().radialMode));
                console.log(failures === 0 ? "\nQML HARNESS PASS" : "\nQML HARNESS FAIL (" + failures + ")");
                Qt.exit(failures === 0 ? 0 : 1);
            }
            ++step;
        }
    }
}
