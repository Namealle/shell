pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils
import "ambient/rules.js" as Rules

Singleton {
    id: root

    // Testing: `starfield-shell fire <family> [screen] [overrides]` -- which is
    // `qs -p ~/.config/quickshell/caelestia/starfield.qml ipc call starfield
    // fire ...`, because the sky is its own process now. `caelestia shell
    // starfield fire ...` reaches this handler in the SHELL's instance, which
    // only draws anything when starfield.json says `"process": "shell"`.
    // It queues one episode of a phenomenon family (starBirth, nova, redGiant,
    // supernova, pulsar, kilonova, gammaBurst), a transient (meteors, comet,
    // satellites, shower/storm, slowWanderer) or `nebula` on one screen, or on
    // every screen when the screen is empty. It goes through pushEvent, so it
    // obeys the same slot and cap rules as a scheduled one.
    //
    // ALL THREE arguments are required -- Quickshell's IpcHandler checks the
    // arity and QML rejects a default value on an annotated parameter (`Type
    // annotations are not supported (yet)`), so an empty string is how you say
    // "no screen" and "no overrides":
    //     starfield fire nebula tablet ''
    //     starfield fire shower '' ''
    //
    // `overrides` is a JSON object written straight onto the captured episode,
    // which is how a phase is addressed: a v9 supernova's whole life cycle is
    // four to five minutes, and watching it through `grim` is only practical
    // with the spans compressed. Example, the same shapes in a quarter of the
    // time:  starfield fire supernova tablet '{"precursor":4,"shellSpan":20,"remnant":40}'
    // Invalid JSON is ignored, not an error: this is a test hook.
    signal fire(string name, string screen, var overrides)

    IpcHandler {
        target: "starfield"

        function fire(name: string, screen: string, overrides: string): string {
            let parsed = null;
            if (overrides) {
                try {
                    const value = JSON.parse(overrides);
                    if (value && typeof value === "object" && !Array.isArray(value))
                        parsed = value;
                } catch (error) {
                    parsed = null;
                }
            }
            root.fire(name, screen, parsed);
            return `queued ${name} on ${screen || "every screen"}${parsed ? " with " + JSON.stringify(parsed) : ""}`;
        }
    }

    // One validated snapshot: deleted keys cannot retain old adapter values.
    readonly property var document: state.document
    // "separate" (the default) draws the sky in its own Quickshell process, so
    // the shell's main thread never waits on the sky's per-frame JS; "shell"
    // restores the in-process path. Changing it needs both processes restarted:
    // `starfield-shell restart` and `caelestia shell -r`.
    readonly property string process: document.process
    readonly property bool inShell: document.process === "shell"
    readonly property real density: document.density
    readonly property real driftSpeed: document.driftSpeed
    readonly property real driftDirection: document.driftDirection
    readonly property real twinkle: document.twinkle
    readonly property real flareFraction: document.flareFraction
    readonly property real brightness: document.brightness
    readonly property real edgeLift: document.edgeLift
    readonly property int fps: document.fps
    readonly property color backgroundColor: document.backgroundColor
    readonly property var motion: document.motion
    readonly property var variety: document.variety
    readonly property var variables: document.variables
    readonly property var reactive: document.reactive
    readonly property var palette: document.palette
    readonly property var paletteColors: palette.rgb
    readonly property var paletteIds: palette.ids
    readonly property var paletteBaseWeights: palette.baseWeights
    readonly property var archetypes: document.archetypes
    // Birth-owned metadata travels through the contract's descriptor-parameter object.
    readonly property var archetypeParams: Object.assign({}, archetypes, {
        palette: {
            variationWhite: palette.variationWhite,
            foregroundWhite: palette.foregroundWhite
        }
    })
    // One object reaches the renderer, so a v6 family, the phenomena block and the
    // two new caps travel on the binding Background.qml already forwards.
    readonly property var eventFamilies: ({
            comet: document.comet,
            meteors: document.meteors,
            shower: document.events.shower,
            slowWanderer: document.events.slowWanderer,
            starBirth: document.events.starBirth,
            nova: document.events.nova,
            redGiant: document.events.redGiant,
            supernova: document.events.supernova,
            kilonova: document.events.kilonova,
            pulsar: document.events.pulsar,
            gammaBurst: document.events.gammaBurst,
            satelliteGlint: document.events.satelliteGlint,
            nebula: document.events.nebula,
            phenomena: document.phenomena,
            phenomenonCap: document.events.phenomenonCap,
            phenomenonGainCap: document.events.phenomenonGainCap,
            dramaCooldownSec: document.events.dramaCooldownSec,
            rateScale: document.events.rateScale
        })
    readonly property int eventHeadCap: document.events.headCap
    // Sparse pass-throughs: an absent key is the renderer's documented default.
    readonly property var blackHole: document.blackHole
    readonly property var particles: document.particles
    readonly property bool particlesEnabled: document.particlesEnabled
    readonly property var meteors: ({
            enabled: document.meteors.enabled,
            interval: Qt.vector2d(document.meteors.interval[0], document.meteors.interval[1]),
            companionChance: document.meteors.companionChance,
            fireballChance: document.meteors.fireballChance
        })
    readonly property var comet: ({
            enabled: document.comet.enabled,
            interval: Qt.vector2d(document.comet.interval[0], document.comet.interval[1])
        })
    readonly property var satellites: ({
            enabled: document.satellites.enabled,
            interval: Qt.vector2d(document.satellites.interval[0], document.satellites.interval[1])
        })

    function enabledFor(screenName: string): bool {
        return document.screens.indexOf(screenName) !== -1;
    }

    QtObject {
        id: state

        property var document: Rules.validateDocument(null)
    }

    Timer {
        id: reloadDebounce

        interval: 150
        onTriggered: file.reload()
    }

    FileView {
        id: file

        path: Paths.config + "/starfield.json"
        watchChanges: true
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onFileChanged: reloadDebounce.restart()
        onLoadFailed: state.document = Rules.validateDocument(null)
        onLoaded: state.document = Rules.parseDocument(text())
    }
}
