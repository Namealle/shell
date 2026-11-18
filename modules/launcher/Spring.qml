import QtQuick

// A damped spring driving one number, integrated per rendered frame.
//
// Physics instead of a timed curve where a motion has to END smoothly: a
// curve ends at a fixed instant and decelerates into it on a schedule, where
// a spring's velocity decays continuously to zero and carries through a
// retarget. `zeta` is the damping ratio: 1 is critical (the fastest approach
// with no overshoot), below 1 it overshoots once by
// exp(-pi*zeta/sqrt(1-zeta^2)) of the distance and comes back -- see
// zetaForOvershoot for choosing it in pixels rather than as a fraction.
//
// Advanced once per frame at the display's own rate (Qt's SpringAnimation is
// capped at 62fps), by the exact solution over the frame -- see step().
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
    // Natural frequency, rad/s. Critically damped: 90% of the way at
    // 3.9/omega, 99% at 6.6/omega.
    property real omega: 20
    property real zeta: 1
    // At rest once both the distance and the speed are this small, in the
    // value's own units -- set them from what a unit is on screen.
    property real epsilon: 0.001
    property real velocityEpsilon: 0.01

    signal settled

    // The damping ratio that overshoots a move of `distance` by `px`.
    //
    // The overshoot of a spring is a FRACTION of the distance, so one ratio
    // for every move gives a 600px move thirty times the bounce of a 20px one
    // -- the same trap as the old curve, whose 1.39% of a 600px size change
    // was an 8px dip on a 41px picture. Solved per move instead: the bounce
    // is the same few pixels whatever the distance. Moves shorter than that
    // are critically damped; there is nothing to bounce past.
    function zetaForOvershoot(distance: real, px: real): real {
        if (distance <= px * 1.5)
            return 1;
        const l = Math.log(distance / px);
        // Floored at 0.6 -- his Hyprland windows, one overshoot of ~9% and a
        // faint return -- so a move only a few px long gets a proportionate
        // flick, not a wobble that fills the move.
        return Math.max(0.6, Math.min(1, l / Math.sqrt(Math.PI * Math.PI + l * l)));
    }

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
        const g = root.goal();
        const w = root.omega;
        const z = Math.min(1, root.zeta);
        // Solved exactly over the frame, not integrated: the target is held
        // for the frame and the damped oscillator's own solution advances the
        // state. An Euler step (even substepped at 480Hz) adds damping of its
        // own, and the overshoot is exponentially sensitive to damping --
        // measured, it halved a 2px bounce. Exact, the bounce is what
        // zetaForOvershoot asked for at any frame rate.
        const x0 = root.value - g;
        const v0 = root.velocity;
        let x, v;
        if (z >= 0.9999) {
            const e = Math.exp(-w * dt);
            const c = v0 + w * x0;
            x = e * (x0 + c * dt);
            v = e * (v0 - w * c * dt);
        } else {
            const wd = w * Math.sqrt(1 - z * z);
            const e = Math.exp(-z * w * dt);
            const cs = Math.cos(wd * dt);
            const sn = Math.sin(wd * dt);
            x = e * (x0 * (cs + z * w / wd * sn) + v0 / wd * sn);
            v = e * (v0 * (cs - z * w / wd * sn) - x0 * (w * w / wd) * sn);
        }
        if (Math.abs(x) < root.epsilon && Math.abs(v) < root.velocityEpsilon) {
            root.velocity = 0;
            root.value = g;
            root.running = false;
            root.settled();
            return;
        }
        root.velocity = v;
        root.value = g + x;
    }
}
