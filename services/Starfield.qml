pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils
import "ambient/rules.js" as Rules

Singleton {
    id: root

    // One validated snapshot: deleted keys cannot retain old adapter values.
    readonly property var document: state.document
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
            phenomena: document.phenomena,
            phenomenonCap: document.events.phenomenonCap,
            dramaCooldownSec: document.events.dramaCooldownSec
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
