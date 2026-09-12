pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    // Presence/type checks prevent removed keys retaining JsonAdapter's old values.
    property var document: ({})
    readonly property real density: number("density", 1, 0, 3)
    readonly property real driftSpeed: number("driftSpeed", 3.5, 0, 30)
    readonly property real driftDirection: number("driftDirection", 165, -360, 360)
    readonly property real twinkle: number("twinkle", 0.22, 0, 1)
    readonly property real flareFraction: number("flareFraction", 0.003, 0, 0.025)
    readonly property real brightness: number("brightness", 1, 0, 3)
    readonly property real edgeLift: number("edgeLift", 0, 0, 1)
    readonly property int fps: Math.round(number("fps", 30, 1, 60))
    readonly property var motion: ({
            wander: groupNumber("motion", "wander", 0.8, 0, 2),
            zoom: groupNumber("motion", "zoom", 0.025, 0, 0.15),
            rotation: groupNumber("motion", "rotation", 0.5, 0, 3)
        })
    readonly property var meteors: ({
            enabled: groupEnabled("meteors"),
            interval: intervalRange("meteors", 10, 30, 3)
        })
    readonly property var comet: ({
            enabled: groupEnabled("comet"),
            interval: intervalRange("comet", 180, 300, 60)
        })
    readonly property var satellites: ({
            enabled: groupEnabled("satellites"),
            interval: intervalRange("satellites", 75, 140, 45)
        })
    readonly property color backgroundColor: typeof document.backgroundColor === "string" && /^#[0-9a-fA-F]{6}$/.test(document.backgroundColor) ? adapter.backgroundColor : "#000000"

    function enabledFor(screenName: string): bool {
        return Array.isArray(document.screens) && adapter.screens.indexOf(screenName) !== -1;
    }

    function number(key: string, fallback: real, minimum: real, maximum: real): real {
        return typeof document[key] === "number" && isFinite(document[key]) ? Math.max(minimum, Math.min(maximum, adapter[key])) : fallback;
    }

    function groupNumber(group: string, key: string, fallback: real, minimum: real, maximum: real): real {
        const value = document[group]?.[key];
        return typeof value === "number" && isFinite(value) ? Math.max(minimum, Math.min(maximum, adapter[group][key])) : fallback;
    }

    function groupEnabled(group: string): bool {
        return typeof document[group]?.enabled === "boolean" ? adapter[group].enabled : true;
    }

    function intervalRange(group: string, low: real, high: real, minimum: real): vector2d {
        const value = document[group]?.interval;
        if (!Array.isArray(value) || value.length !== 2 || !value.every(v => typeof v === "number" && isFinite(v)))
            return Qt.vector2d(low, high);
        const first = Math.max(minimum, Math.min(3600, value[0]));
        return Qt.vector2d(first, Math.max(first, Math.min(3600, value[1])));
    }

    FileView {
        id: file

        path: `${Paths.config}/starfield.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: root.document = ({})
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.document = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
            } catch (error) {
                root.document = ({});
                console.warn("Starfield: invalid starfield.json:", error);
            }
        }

        JsonAdapter {
            id: adapter

            property var screens: []
            property real density: 1
            property real driftSpeed: 3.5
            property real driftDirection: 165
            property real twinkle: 0.22
            property real flareFraction: 0.003
            property real brightness: 1
            property real edgeLift: 0
            property string backgroundColor: "#000000"
            property real fps: 30
            property JsonObject motion: JsonObject {
                property real wander: 0.8
                property real zoom: 0.025
                property real rotation: 0.5
            }
            property JsonObject meteors: JsonObject {
                property bool enabled: true
                property var interval: [10, 30]
            }
            property JsonObject comet: JsonObject {
                property bool enabled: true
                property var interval: [180, 300]
            }
            property JsonObject satellites: JsonObject {
                property bool enabled: true
                property var interval: [75, 140]
            }
        }
    }
}
