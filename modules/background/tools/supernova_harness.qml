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
            const pool = field._particles;
            if (e && clock >= e.start && clock <= e.start + e.duration)
                track.push({
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
                if (items)
                    for (let n = 0; n < items.count; ++n)
                        if (items.data[n * 21 + 16] === starId) {
                            starTrack.push({
                                t: clock,
                                core: items.data[n * 21 + 4],
                                light: items.data[n * 21 + 10],
                                r: items.data[n * 21 + 7],
                                b: items.data[n * 21 + 9],
                                x: items.data[n * 21],
                                y: items.data[n * 21 + 1]
                            });
                            break;
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
            } else if (step === 4) {
                const pool = field._particles;
                advanceBy(90, 2);
                expect("every ember is gone when the episode ends", pool.transientCount === 0, pool.transientCount + " transient particles left");
                expect("and the field is whole again", pool.aliveCount >= 0.9 * pool.targetPopulation, pool.aliveCount + " of " + pool.targetPopulation);
                expect("the slot is released", shader().event3Head.w === 0 && shader().event4Head.w === 0 && shader().event5Head.w === 0);
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
            } else {
                console.log(failures === 0 ? "\nQML SUPERNOVA HARNESS PASS" : "\nQML SUPERNOVA HARNESS FAIL (" + failures + ")");
                Qt.exit(failures === 0 ? 0 : 1);
            }
            ++step;
        }
    }
}
