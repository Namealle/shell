import QtQuick

// A critically damped spring driving one number, integrated per rendered frame.
//
// Physics instead of a timed curve where a motion has to END smoothly: a
// curve ends at a fixed instant, and the expressive ones get there by
// overshooting -- on a picture shrinking 600px into a 41px slot, the
// standard curve's 1.39% overshoot was an 8px-too-small picture that then
// crept back a pixel at a time. Critically damped, the value approaches its
// target from one side with its velocity decaying continuously to zero.
//
// Same integrator as ClipBody's scrollAnim (semi-implicit Euler, substepped,
// dt clamped), once per frame at the display's own rate -- Qt's
// SpringAnimation is capped at 62fps.
//
// The time step is the ANIMATION DRIVER's, the clock every Behavior and
// curve in the shell runs on, read off a linear NumberAnimation. Not
// FrameAnimation.frameTime: that is wall time between ticks, which jitters
// 5.2-6.8ms on a steady 6.06ms (165Hz) display, so a spring integrated on it
// moved alternately too far and too short each presented frame -- measured
// as width steps of 4.8, 5.6, 3.8, 4.5px where the curve's were an even 6.1,
// 5.2, 4.4, 3.7.
//
// Retargeting keeps the velocity: change `to` (or `target`) mid-flight and
// the value turns towards the new target from where it is, moving as it was.
Item {
    id: root

    // The value this drives. Read it; write it only through start().
    property real value: 0
    property real velocity: 0
    // Where it is going. `target`, when set, is a function read every frame
    // (a target that moves while the spring runs); otherwise `to`.
    property real to: 0
    property var target: null
    // Natural frequency, rad/s. Critically damped: the fastest approach with
    // no overshoot. 90% of the way at 3.9/omega, 99% at 6.6/omega.
    property real omega: 20
    // At rest once both the distance and the speed are this small, in the
    // value's own units -- set them from what a unit is on screen.
    property real epsilon: 0.001
    property real velocityEpsilon: 0.01

    signal settled

    function goal(): real {
        return root.target ? root.target() : root.to;
    }

    property bool running: false
    property real clock: 0
    property real lastClock: 0

    function start(from: real, velocity: real): void {
        root.value = from;
        root.velocity = velocity;
        // Already running, the clock carries on and this is a fresh origin;
        // stopped, the clock restarts at 0 and the first tick is skipped.
        root.lastClock = root.clock;
        root.running = true;
    }

    function stop(): void {
        root.running = false;
        root.velocity = 0;
    }

    visible: false

    NumberAnimation on clock {
        running: root.running
        from: 0
        to: 1e7
        duration: 1e7
    }

    onClockChanged: {
        if (!root.running)
            return;
        const ms = root.clock - root.lastClock;
        root.lastClock = root.clock;
        if (ms <= 0)
            return;
        root.step(ms / 1000);
    }

    function step(frame: real): void {
        // A stalled frame must not integrate one huge step.
        const dt = Math.min(frame, 1 / 30);
        const steps = Math.max(1, Math.ceil(dt * 480));
        const h = dt / steps;
        const g = root.goal();
        const w = root.omega;
        let x = root.value;
        let v = root.velocity;
        for (let i = 0; i < steps; i++) {
            v += (-w * w * (x - g) - 2 * w * v) * h;
            x += v * h;
        }
        if (Math.abs(x - g) < root.epsilon && Math.abs(v) < root.velocityEpsilon) {
            root.velocity = 0;
            root.value = g;
            root.running = false;
            root.settled();
            return;
        }
        root.velocity = v;
        root.value = x;
    }
}
