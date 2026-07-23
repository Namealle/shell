// Behavioural tests for the SpringAnim C++ type.
//
// Run:
//   QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
//     qml6 -I build/qml tests/springanim.qml
//
// Exits 0 when every case passes, otherwise the number of failures.
//
// Two properties are checked. First, that each family's spring reproduces the
// overshoot of the bezier curve it was fitted to -- overshoot is set by zeta
// alone, so this is the direct test of "does it still feel the same". Second,
// that a retarget mid-flight preserves both position and momentum, which is the
// behaviour springs were adopted for and the one thing an easing curve cannot
// do.
//
// Note the tolerance on overshoot is a little loose because the value is only
// observed on frames the property is written; offscreen that is ~16ms, roughly
// 3x coarser than a 175Hz display, which slightly clips the sampled peak of the
// fastest curves.
import QtQuick
import Caelestia.Components

Item {
    id: root

    width: 100
    height: 100

    property int failures: 0
    property int reported: 0
    readonly property int total: overshootCases.count + carryCases.count + 1

    function report(name, detail, ok) {
        console.warn((ok ? "  PASS  " : "  FAIL  ") + name + "   " + detail);
        if (!ok)
            root.failures++;
        if (++root.reported === root.total) {
            console.warn(root.failures === 0 ? "\nAll " + root.total + " cases passed." : "\n" + root.failures + " of " + root.total + " cases FAILED.");
            Qt.exit(root.failures);
        }
    }

    Component.onCompleted: console.warn("\nSpringAnim behavioural tests\n")

    // -- overshoot fidelity, one case per animation family --
    Repeater {
        id: overshootCases

        model: [
            // name, zeta, omega, expected overshoot %, tolerance
            ["DefaultSpatial", 0.806, 19.80, 1.4, 0.3],
            ["FastSpatial", 0.605, 29.40, 9.2, 0.5],
            ["SlowSpatial", 0.784, 14.25, 1.9, 0.3],
            ["Standard", 1.000, 19.50, 0.0, 0.1],
            ["Emphasized", 0.848, 21.20, 0.7, 0.3]
        ]

        Item {
            id: oc

            required property var modelData

            property real v: 0
            property real peak: 0

            Behavior on v {
                SpringAnim {
                    physics: true
                    zeta: oc.modelData[1]
                    omega: oc.modelData[2]
                    duration: 500
                }
            }

            Component.onCompleted: v = 1
            onVChanged: if (v > peak)
                peak = v

            Timer {
                interval: 1500
                running: true
                onTriggered: {
                    const got = (oc.peak - 1) * 100;
                    const want = oc.modelData[3];
                    const settled = Math.abs(oc.v - 1) < 0.001;
                    root.report(oc.modelData[0], `overshoot ${got.toFixed(2)}% (want ${want.toFixed(1)}%), settled=${settled}`, settled && Math.abs(got - want) <= oc.modelData[4]);
                }
            }
        }
    }

    // -- the physics toggle must work in BOTH directions, repeatedly --
    //
    // Regression test for the bug that made the whole feature look like it did
    // nothing: the bezier path applies `defaultEasing` via setEasing(), which
    // emits easingChanged, which is the same signal used to detect "a call site
    // overrode the easing". So the first bezier animation used to latch
    // m_easingExplicit permanently and springs could never engage again. With
    // springs.enabled=false at startup that meant they never ran at all, and
    // flipping the toggle afterwards did nothing.
    //
    // Every other case here sets physics:true from the outset and so never
    // touches the bezier path -- which is exactly why they all passed while the
    // feature was dead in practice.
    Item {
        id: toggleCase

        property real v: 0
        property real trough: 1
        property bool measuring: false

        Behavior on v {
            SpringAnim {
                id: toggleSpring

                physics: false
                zeta: 0.605
                omega: 29.40
                duration: 350
                // Must be set to something other than the default, or the
                // bezier path skips setEasing() and the bug cannot reproduce.
                //
                // Deliberately the `standard` curve, which does NOT overshoot,
                // even though zeta=0.605 corresponds to expressiveFastSpatial.
                // Using the matching curve would make this test useless: the
                // whole point of the fit is that spring and bezier look alike,
                // so the two paths must be told apart by a feature they do not
                // share. Here that is overshoot -- bezier gives 0%, spring 9.2%.
                defaultEasing.type: Easing.BezierSpline
                defaultEasing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
            }
        }

        onVChanged: if (measuring && v < trough)
            trough = v

        // Phase 1: run one animation, 0 -> 1, on the bezier path.
        Component.onCompleted: v = 1

        // Phase 2: enable physics and animate back, 1 -> 0. A spring at
        // zeta=0.605 undershoots past its target by 9.2%; the bezier path
        // cannot go below 0 at all, so any real undershoot proves the spring
        // engaged.
        Timer {
            interval: 800
            running: true
            onTriggered: {
                toggleSpring.physics = true;
                toggleCase.measuring = true;
                toggleCase.trough = 1;
                toggleCase.v = 0;
            }
        }

        Timer {
            interval: 2000
            running: true
            onTriggered: {
                const os = -toggleCase.trough * 100;
                root.report("physics toggle off->on", `undershoot after enabling ${os.toFixed(2)}% (want ~9.2%, 0% = springs never engaged)`, os > 5);
            }
        }
    }

    // -- retarget mid-flight: position continuous, momentum preserved --
    Repeater {
        id: carryCases

        model: [
            // zeta, omega
            [0.200, 19.80],
            [0.605, 29.40],
            [0.806, 19.80]
        ]

        Item {
            id: cc

            required property var modelData

            property real v: 0
            property real vAt: -1
            property real maxAfter: 0
            property real jump: -1
            property real velBefore: 0
            property real velAfter: 0
            property bool armed: false

            Behavior on v {
                SpringAnim {
                    id: cspring

                    physics: true
                    zeta: cc.modelData[0]
                    omega: cc.modelData[1]
                    duration: 500
                }
            }

            Component.onCompleted: v = 1

            onVChanged: {
                if (!armed)
                    return;
                // Position continuity. The bug this guards against wrote the
                // stale QQuickBehavior fromValue, teleporting the property all
                // the way back to where the animation began -- an error of
                // ~0.64 here. Ordinary motion covers well under 0.15 in the one
                // frame between the retarget and this sample.
                if (jump < 0) {
                    jump = Math.abs(v - vAt);
                    velAfter = cspring.velocity;
                }
                if (v > maxAfter)
                    maxAfter = v;
            }

            Timer {
                interval: 90
                running: true
                onTriggered: {
                    cc.vAt = cc.v;
                    cc.maxAfter = cc.v;
                    cc.velBefore = cspring.velocity;
                    cc.armed = true;
                    cc.v = 0;
                }
            }

            Timer {
                interval: 2000
                running: true
                onTriggered: {
                    const continuous = cc.jump >= 0 && cc.jump < 0.15;
                    // The momentum assertion, and the frame-rate-independent
                    // one: the new job must resume at the speed the old one
                    // had. Without carry-over this reads 0. Position excursion
                    // is reported too, but not asserted -- at high omega the
                    // spring can reverse inside a single frame, so the peak is
                    // simply never sampled.
                    const kept = cc.velBefore > 0 ? cc.velAfter / cc.velBefore : 0;
                    const stopped = Math.abs(cc.v) < 0.01;
                    root.report(`retarget zeta=${cc.modelData[0].toFixed(3)}`, `continuous=${continuous} velocity kept=${(kept * 100).toFixed(0)}% excursion=${(cc.maxAfter - cc.vAt).toFixed(3)} settled=${stopped}`, continuous && stopped && kept > 0.5);
                }
            }
        }
    }
}
