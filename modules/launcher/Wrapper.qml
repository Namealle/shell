pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property var panels

    readonly property bool shouldBeActive: screenState.launcher && Config.launcher.enabled

    readonly property real maxHeight: {
        let max = screen.height - Config.border.thickness * 2 + Tokens.padding.extraLarge;
        if (screenState.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }

    property real offsetScale: shouldBeActive ? 0 : 1

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            // Launcher opening: get the picker's files on disk now, so pressing
            // `;` paints a full list at once instead of one row at a time as
            // each cliphist decode returns.
            Clipboard.preloadDecode();
            // Seed the held set now, not when `;` is pressed: these are what the
            // picker opens on, and warming them here is the whole point of doing
            // it at launcher-open time.
            Clipboard.seedRetained();
        } else {
            // The picker cannot still be open if the launcher is not, and
            // AppList is destroyed on close without getting a state change to
            // clear this itself.
            Clipboard.picking = false;
        }

        // Break BOTH bindings during the close anim. Width matters as much as
        // height: closing out of the clipboard reader flips ContentList back to
        // the list state, and a live width binding collapses the expanded
        // reader down to itemWidth in a single frame while the launcher is
        // still on screen.
        if (shouldBeActive) {
            implicitHeight = Qt.binding(() => content.implicitHeight);
            implicitWidth = Qt.binding(() => content.implicitWidth || 630);
        } else {
            implicitHeight = implicitHeight;
            implicitWidth = implicitWidth;
        }
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Component.onCompleted: Qt.callLater(() => Apps) // Load apps on init

    Behavior on offsetScale {
        Anim {}
    }

    // -- clipboard image preload --
    //
    // Deliberately HERE and not inside the launcher's content: that Loader is
    // deactivated when the launcher closes, taking every delegate and every
    // pixmap reference with it, so a preload living in there would be thrown
    // away on close and rebuilt from cold on the next open -- which is the one
    // moment it exists to cover.
    //
    // Per screen rather than in the Clipboard singleton, and that is correct
    // rather than wasteful: Qt bakes the screen's device pixel ratio into the
    // decode, so a 1x and a 1.5x monitor genuinely need different pixmaps, and a
    // singleton with no window of its own would warm neither reliably.
    //
    // One delegate per retained SLOT, and the slot count is a constant -- so
    // these are built once for the life of the launcher and a retain only ever
    // re-points one slot's two source bindings. Modelled on the entry ARRAY it
    // rebuilt every delegate each time that array was reassigned, which
    // retain() did on nearly every call: see Clipboard.retained.
    Repeater {
        model: Clipboard.retainMax

        Item {
            id: preload

            required property int index

            readonly property var modelData: Clipboard.retained[preload.index] ?? null

            readonly property string src: preload.modelData?.entryId ? `file:///tmp/caelestia-clip-preview-${preload.modelData.entryId}.png` : ""

            // Never drawn -- this exists only to hold its decode in
            // QQuickPixmapCache. Every property that forms the cache key has to
            // match what the reader will ask for, or it warms an entry nobody
            // requests; that would fail silently, since a miss just looks like
            // the old behaviour.
            //
            // The row thumbnail, held for as long as the launcher exists.
            //
            // Holding it is the point, not just warming it. These are tiny and
            // Qt caches them happily on their own -- measured 0-4ms to re-enter
            // the picker -- right up until the full-size copies below land in
            // the same cache and evict them, because Qt's pool for unreferenced
            // pixmaps is far smaller than a screenful of full-size pictures. The
            // symptom was every `;` re-decoding seven multi-megabyte PNGs down
            // to 96px: 93-162ms of empty icon slots, read as a flicker. A live
            // reference cannot be evicted, so this simply removes the question.
            //
            // Not gated on the picker being open -- it is cheap (37KB each) and
            // decoding it early is the whole point: the list should paint
            // complete the instant `;` is pressed.
            Image {
                width: 0
                height: 0
                visible: false
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                source: root.shouldBeActive && Clipboard.preloadReady ? preload.src : ""
                sourceSize.width: Clipboard.thumbSize
                sourceSize.height: Clipboard.thumbSize
            }

            Image {
                // The reader's copy. Gated on the picker actually being open --
                // this is the expensive stage, and opening the launcher to
                // search for an app should not decode a screenful of pictures.
                //
                // AND on this screen's own launcher, not just the global picking
                // flag: every screen has one of these, so without the second
                // half both monitors decode the whole set and hold two copies of
                // it, when only the focused screen can possibly show the picker.
                width: 0
                height: 0
                visible: false
                asynchronous: true
                cache: true
                mipmap: true
                // Must match the reader's Images: fillMode is part of the cache
                // key, so warming with the default Stretch built an entry
                // nothing would ever ask for.
                fillMode: Image.PreserveAspectCrop
                source: Clipboard.pickingSettled && root.shouldBeActive ? preload.src : ""
                sourceSize.width: Clipboard.readerDecodeWidth(preload.modelData?.imgDims ?? null)
            }
        }
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight
        }
    }
}
