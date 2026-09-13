pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components.containers
import qs.services as Services

// The sky's own windows, one per enabled screen, owned by the starfield.qml
// entry point -- a second Quickshell process with its own QML engine, its own
// main thread and its own render thread, so the shell's animations never queue
// behind the renderer's per-frame JS.
//
// These sit on the BACKGROUND layer; the shell's own background window drops to
// BOTTOM and transparent while this runs (Background.qml `opaque`), so the two
// clients have no map-order dependency on each other. The desktop clock and the
// Visualiser stay in the shell, on top.
Variants {
    model: Services.Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled && Services.Starfield.enabledFor(s.name))

    StyledWindow {
        id: win

        required property ShellScreen modelData

        screen: modelData
        name: "starfield"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        color: "black"
        surfaceFormat.opaque: false
        // Purely decorative: never take a click, whatever is or is not above it.
        mask: Region {}

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        StarfieldLayer {
            anchors.fill: parent
            screenName: win.modelData.name
        }
    }
}
