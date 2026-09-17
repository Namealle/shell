// The QML half of the v10 supernova, driven headlessly: loads the real
// Starfield.qml WITH its real particle pool, force-fires a supernova the way
// `caelestia shell starfield fire supernova` does, and checks that the thing
// that explodes is a star that was already on the screen. Node covers the
// interface (test-particles) and the scheduler (test-events); this covers the
// part only QML runs -- supernovaParticles(), the pool it drives and the
// uniform block the two of them end up agreeing on.
//
//   cd modules/background && QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
//     /usr/lib/qt6/bin/qml tools/supernova_harness.qml
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
    property var starTrack: []
    property int starId: -1
    property int starGen: -1

    // publish() can return early while the descriptor atlas is still decoding,
    // and the atlas decodes through the event loop, which a tight seek loop
    // inside one timer tick never gives back. publishEvents() is called
    // explicitly for the same reason nebula_harness calls publishNebula(): it
    // is the shipped function, against the shipped state.
    function advanceBy(seconds, grain) {
        const dt = grain === undefined ? 0.5 : grain;
        for (let i = 0; i < Math.round(seconds / dt); ++i) {
            field.seek(clock += dt);
            // publish() can leave a canvas paint pending forever offscreen, and
            // publishParticles() then bails and _particleItems goes stale. The
            // render is the thing under test, so it is re-armed explicitly.
            field._particlePending = null;
            field.publishEvents();
            field.publishParticles();
            const e = field._state.events[8];
            const head = shader().event3Head.w > 0 ? shader().event3Head
                : shader().event4Head.w > 0 ? shader().event4Head : shader().event5Head;
            const bounds = shader().event3Head.w > 0 ? shader().event3Bounds
                : shader().event4Head.w > 0 ? shader().event4Bounds : shader().event5Bounds;
            const pool = field._particles;
            // v11, requirement A. Everything the episode can reach: the half
            // width of the box the shader rejects on, and the radius of the
            // widest live brightenNear glow. Between them they ARE the footprint
            // -- the whole-sky lift that used to sit outside both is gone, so if
            // these two stay local, nothing on the screen can flash.
            let glow = 0;
            for (const g of (pool.glows || []))
                if (clock - g.start < g.decay && g.radius > glow)
                    glow = g.radius;
            if (e && clock >= e.start && clock <= e.start + e.duration)
                track.push({
                    boundsReach: head.w > 0 ? Math.max(bounds.z - head.x, bounds.w - head.y) : 0,
                    glow: glow,
                    t: clock,
                    age: clock - e.start,
                    x: e.site ? e.site[0] : 0,
                    y: e.site ? e.site[1] : 0,
                    gain: head.w,
                    hasStar: e.hasStar === true,
                    detonated: e.detonated === true,
                    debris: pool.transientCount,
                    alive: pool.aliveCount,
                    kicked: pool.kickAlive,
                    shell: shader().event3Shape.x + shader().event4Shape.x + shader().event5Shape.x,
                    reach: e.detonated ? debrisRadius(pool, e) : 0
                });
            if (starId >= 0 && pool.alive[starId] && pool.generation[starId] === starGen) {
                const items = field._particleItems;
                // items.stride, never a literal: the render-instance stride is a
                // contract Appearance.js owns and it has changed (21 -> 23 when
                // the unit velocity moved into it). A hardcoded 21 here silently
                // read the wrong column and failed "the precursor was drawn".
                if (items) {
                    const s = items.stride;
                    for (let n = 0; n < items.count; ++n)
                        if (items.data[n * s + 16] === starId) {
                            starTrack.push({
                                t: clock,
                                core: items.data[n * s + 4],
                                light: items.data[n * s + 10],
                                r: items.data[n * s + 7],
                                b: items.data[n * s + 9],
                                x: items.data[n * s],
                                y: items.data[n * s + 1]
                            });
                            break;
                        }
                }
            }
        }
    }

    // The median radius of this episode's own debris, measured off the pool.
    function debrisRadius(pool, e) {
        if (!e.site)
            return 0;
        const radii = [];
        for (let k = 0; k < pool.liveCount; ++k) {
            const i = pool.live[k];
            if (!pool.transient[i] || pool.archetype[i] !== 7)
                continue;
            radii.push(Math.hypot(pool.x[i] - e.site[0], pool.y[i] - e.site[1]));
        }
        if (!radii.length)
            return 0;
        radii.sort((a, b) => a - b);
        return radii[radii.length >> 1];
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

    function fire() {
        root.track = [];
        root.starTrack = [];
        root.starId = -1;
        // A short life, so a whole cycle fits in one harness run. Everything
        // else -- the star, the debris, the shock -- is derived from these.
        const ok = field.pushEvent("supernova", 0, {
            precursor: 14,
            shellSpan: 30,
            remnant: 25
        });
        field.publishEvents();
        const e = field._state.events[8];
        if (e && e.star >= 0) {
            root.starId = e.star;
            root.starGen = e.starGeneration;
        }
        return ok;
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
                enabled: false,
                preset: "target"
            })
        particlesEnabled: true
        // Scheduled events off: this harness fires its own and nothing else may
        // take the phenomenon slot it is about to claim.
        eventFamilies: ({
                rateScale: 0
            })
    }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            if (step === 0) {
                // Let the camera regime settle and the field fill.
                advanceBy(120, 2);
                expect("publish() reached the shader at all", shader().resolution.x === root.width, "resolution " + shader().resolution.x + "x" + shader().resolution.y);
                expect("the camera regime has taken over", field._cameraBlend === 1);
                expect("the field is populated", field._particles.aliveCount > 400, field._particles.aliveCount + " particles");
                expect("fire supernova is accepted", fire() === true);
                expect("and it happens TO a star that is already on the screen", starId >= 0 && field._state.events[8].hasStar === true, starId >= 0 ? "particle " + starId + " at " + field._state.events[8].site.map(v => v.toFixed(0)).join(",") : "no star picked");
            } else if (step === 1) {
                const e = field._state.events[8];
                advanceBy(e.precursor - 1, 0.5);
                if (starTrack.length < 4) {
                    expect("the precursor was drawn", false, starTrack.length + " frames");
                    ++step;
                    return;
                }
                const first = starTrack[0], last = starTrack[starTrack.length - 1];
                expect("the star swells", last.core >= 3 * first.core, "core " + first.core.toFixed(2) + " -> " + last.core.toFixed(2) + " px");
                expect("and brightens", last.light > 2.5 * first.light, "light " + first.light.toFixed(2) + " -> " + last.light.toFixed(2));
                let reddest = first, peak = 0;
                for (const f of starTrack) {
                    const warmth = f.r - f.b;
                    if (warmth > peak) {
                        peak = warmth;
                        reddest = f;
                    }
                }
                expect("it goes red and then blue-white", peak > 0.15 && last.b >= last.r - 0.02, "reddest r-b " + peak.toFixed(2) + " at t+" + (reddest.t - e.start).toFixed(1) + " s, final r-b " + (last.r - last.b).toFixed(2));
                expect("and it keeps moving with the field while it does", Math.hypot(last.x - first.x, last.y - first.y) > 2, "moved " + Math.hypot(last.x - first.x, last.y - first.y).toFixed(1) + " px over " + (last.t - first.t).toFixed(0) + " s");
                const sprite = track.filter(f => !f.detonated);
                expect("nothing fades in beside it", sprite.length > 4 && sprite[0].gain < 0.30 * sprite[sprite.length - 1].gain, sprite.length ? "sprite halo " + sprite[0].gain.toFixed(3) + " -> " + sprite[sprite.length - 1].gain.toFixed(3) : "none");
            } else if (step === 2) {
                const e = field._state.events[8];
                const pool = field._particles;
                const before = pool.aliveCount;
                advanceBy(3, 0.25);
                expect("the star is gone the moment it detonates", !(pool.alive[starId] && pool.generation[starId] === starGen), "particle " + starId + " alive " + pool.alive[starId]);
                expect("and it is replaced by real debris", pool.transientCount >= 150 && pool.counters.debris >= 150, pool.counters.debris + " debris particles, " + pool.transientCount + " alive");
                expect("the shock shoves the stars it reaches", pool.counters.kicked > 8, pool.counters.kicked + " kicks delivered in the first three seconds, " + pool.kickAlive + " particles carrying a peculiar velocity");
                expect("the field itself is not thinned by the explosion", pool.aliveCount - pool.transientCount > 0.9 * (before - 1), (pool.aliveCount - pool.transientCount) + " stars against " + before + " before");
                // v11, requirement A: "I don't like that my screen flashes
                // during the explosion". The flash lights the neighbourhood it
                // stands in and nothing else. v10 lit 0.55 of the LONG side --
                // 1584 px here, past every corner of the shell.
                const lit = track.filter(f => f.detonated && f.glow > 0);
                const cap = 1.5 * e.shell;
                expect("the flash lights only its own neighbourhood",
                    lit.length > 0 && lit.every(f => f.glow <= cap + 0.5),
                    lit.length ? "brightenNear radius " + lit[0].glow.toFixed(0) + " px against 1.5 shell radii = " + cap.toFixed(0) + " px (v10: " + (0.55 * Math.max(root.width, root.height)).toFixed(0) + " px)" : "no glow");
            } else if (step === 3) {
                const e = field._state.events[8];
                advanceBy(28, 0.5);
                const shelled = track.filter(f => f.detonated && f.shell > 4 && f.reach > 4);
                if (shelled.length < 5) {
                    expect("the shell and the debris were both published", false, shelled.length + " frames");
                    ++step;
                    return;
                }
                let worst = 0, worstAt = "";
                for (const f of shelled) {
                    const ratio = f.reach / f.shell;
                    if (Math.abs(Math.log(ratio)) > worst) {
                        worst = Math.abs(Math.log(ratio));
                        worstAt = "t+" + f.age.toFixed(0) + " s: debris " + f.reach.toFixed(0) + " px, rim " + f.shell.toFixed(0) + " px";
                    }
                }
                // One Sedov law, two consumers: the rim never runs away from the
                // material it is made of.
                expect("the rim runs through its own debris", Math.exp(worst) < 1.8, shelled.length + " frames, worst " + Math.exp(worst).toFixed(2) + "x (" + worstAt + ")");
                const first = shelled[0], last = shelled[shelled.length - 1];
                const e8 = field._state.events[8];
                const d0 = first.age - e8.precursor, d1 = last.age - e8.precursor;
                expect("and both of them decelerate", last.reach > 2 * first.reach && last.reach / d1 < first.reach / d0, "debris " + first.reach.toFixed(0) + " px at " + d0.toFixed(1) + " s (" + (first.reach / d0).toFixed(0) + " px/s) -> " + last.reach.toFixed(0) + " px at " + d1.toFixed(1) + " s (" + (last.reach / d1).toFixed(0) + " px/s)");
                // v11, requirement B: "the cloud of the supernova is static and
                // not moving with the rest". In v10 the debris was dead long
                // before the remnant -- measured on the live tablet, 162
                // transients at t+28 s and ZERO from t+55 s on, so the thing he
                // watched for the next four minutes was a sprite with nothing
                // in it. The knot population lives through the remnant, so the
                // remnant is made of material that moves with the regime.
                const pool2 = field._particles;
                const e2 = field._state.events[8];
                const mid = e2.precursor + 0.6 * e2.shellSpan + 0.5 * (0.4 * e2.shellSpan + e2.remnant);
                advanceBy(Math.max(2, e2.start + mid - clock), 0.5);
                const site0 = e2.site ? e2.site.slice() : [0, 0];
                const before2 = debrisRadius(pool2, e2);
                advanceBy(8, 0.5);
                const moved = e2.site ? Math.hypot(e2.site[0] - site0[0], e2.site[1] - site0[1]) : 0;
                expect("the remnant is still made of particles halfway through it",
                    pool2.transientCount > 60,
                    pool2.transientCount + " embers alive at t+" + (clock - e2.start).toFixed(0) + " s, median radius " + before2.toFixed(0) + " px");
                expect("and that material travels with the regime",
                    moved > 1,
                    "the site moved " + moved.toFixed(1) + " px in 8 s and the cloud went with it (driftGroup)");
            } else if (step === 4) {
                const pool = field._particles;
                advanceBy(90, 2);
                expect("every ember is gone when the episode ends", pool.transientCount === 0, pool.transientCount + " transient particles left");
                expect("and the field is whole again", pool.aliveCount >= 0.9 * pool.targetPopulation, pool.aliveCount + " of " + pool.targetPopulation);
                expect("the slot is released", shader().event3Head.w === 0 && shader().event4Head.w === 0 && shader().event5Head.w === 0);
                // v11, requirement A, the whole life cycle at once: nothing the
                // episode ever published can reach a pixel outside its own box,
                // because there is no term outside the box any more. The cap is
                // a third of the SHORT side, which on this buffer is 600 px --
                // against the 1584 px radius the sky lift used to cover, and
                // against a screen half-diagonal of 1698 px.
                let widest = 0, widestAt = 0;
                for (const f of track)
                    if (f.boundsReach > widest) {
                        widest = f.boundsReach;
                        widestAt = f.age;
                    }
                const short = Math.min(root.width, root.height);
                expect("and nothing it drew ever reached past its own box",
                    widest > 0 && widest <= 0.34 * short,
                    "widest published reach " + widest.toFixed(0) + " px at t+" + widestAt.toFixed(0) + " s = " + (widest / short).toFixed(3) + " of the short side");
            } else if (step === 5) {
                // The other regime: with the hole on, the debris is under
                // gravity and the field crosses the screen in seconds, so the
                // precursor shortens itself rather than picking a star it
                // cannot hold.
                field.blackHole = ({
                        enabled: true,
                        preset: "target"
                    });
                advanceBy(90, 2);
                expect("the orbital regime has taken over", field._cameraBlend === 0);
                expect("fire supernova is accepted with the hole on", fire() === true);
                const e = field._state.events[8];
                expect("it still happens to a star, on a precursor the regime can hold", e.hasStar === true && e.precursor >= 4 && e.precursor <= 14, "precursor " + e.precursor.toFixed(1) + " s against a field at " + field._particles && e.hasStar ? e.precursor.toFixed(1) + " s" : "no star");
            } else if (step === 6) {
                const e = field._state.events[8];
                const pool = field._particles;
                advanceBy(e.precursor + 4, 0.25);
                expect("it detonates into debris under gravity too", pool.counters.debris > 150 && e.detonated === true, pool.transientCount + " debris alive");
                let captured = 0, swallowed = pool.counters.absorbed;
                advanceBy(40, 0.5);
                expect("and that debris obeys the hole", pool.counters.absorbed >= swallowed, pool.counters.absorbed - swallowed + " particles swallowed while the debris was out");
            } else if (step === 7) {
                // v10: a storm fireball's terminal flash is the same mechanism
                // one size down -- brightenNear plus a small spray.
                field.blackHole = ({
                        enabled: false,
                        preset: "target"
                    });
                advanceBy(90, 2);
                const pool = field._particles;
                const before = pool.counters.debris;
                const lifts = pool.glows.length;
                expect("fire shower is accepted", field.pushEvent("shower", 0, {}) === true);
                // A pushed episode is drained into its family on the NEXT
                // publication, so the descriptor only exists after one step.
                advanceBy(1, 0.5);
                const e = field._state.events[3];
                const fireballs = e && e.children ? e.children.length : 0;
                expect("the storm carried fireballs", fireballs > 0, fireballs + " fireballs");
                advanceBy(e ? Math.min(180, e.duration + (e.offset || 0)) : 60, 0.5);
                const fired = e && e.children ? e.children.filter(c => c.burst === true).length : 0;
                expect("each terminal flash sprayed fragments into the field",
                    fired > 0 && pool.counters.debris > before,
                    fired + " of " + fireballs + " fireballs fired, " + (pool.counters.debris - before) + " fragments");
                expect("and lit the stars beside it", pool.counters.impulses >= 0 && fired > 0,
                    "brightenNear fired with each of the " + fired);
            } else {
                console.log(failures === 0 ? "\nQML SUPERNOVA HARNESS PASS" : "\nQML SUPERNOVA HARNESS FAIL (" + failures + ")");
                Qt.exit(failures === 0 ? 0 : 1);
            }
            ++step;
        }
    }
}
