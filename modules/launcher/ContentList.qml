pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property var currentList: showWallpapers ? wallpaperList.item : appList.item // Can be either ListView or PathView, so can't type properly
    property string animState: showWallpapers ? "wallpapers" : "apps"

    // Clipboard reader (Option D): `→` morphs the launcher into a reader for the
    // highlighted entry, `←` morphs back. Only meaningful in clipboard mode.
    property bool readerActive: false
    // Where the highlighted row sat (in this item's coords) when the reader was
    // entered -- the reader's header is the shared element: it starts here and
    // slides to the top, and slides back down here on exit.
    property real readerStartY: 0
    property bool readerExiting: false
    // displayState, NOT state: state's binding involves `frozen` (which we set
    // from readerActive), so reading it here would close a binding loop.
    readonly property bool canRead: (appList.item?.displayState ?? "") === "clipboard"
    // Owned, not derived from currentIndex: the entry being read is lifted OUT
    // of the list model, so list indices can't describe it.
    property var readerEntry: null
    onCanReadChanged: if (!canRead) resetReader()

    function currentRowY(): real {
        const l = appList.item;
        return l?.currentItem ? l.currentItem.y - l.contentY : 0;
    }

    function resetReader(): void {
        partTimer.stop();
        const l = appList.item;
        if (l) {
            l.liftedEntry = null;
            l.maskedEntry = null;
            l.pendingIndex = -1;
        }
        readerEntry = null;
        readerActive = false;
        readerExiting = false;
    }

    // The row hands itself off to the reader: mask+lift it out of the model
    // (neighbours close the gap with the standard animations) as the header
    // spawns at its position and rises.
    function enterReader(): void {
        const l = appList.item;
        if (!canRead || readerActive)
            return;
        // Mid-exit re-entry: the reader instance is still alive and its header
        // is sliding down -- reverse it in place instead of dropping the
        // keypress until the slide lands. Same entry, so nothing needs
        // rebuilding: cancel the staged re-insert (or re-lift if it already
        // happened) and send the header back up from wherever it is.
        if (readerExiting) {
            const r = clipReader.item;
            if (!r || !readerEntry || !l)
                return;
            partTimer.stop();
            if (l.liftedEntry !== readerEntry) {
                const i = l.fullResults.indexOf(readerEntry);
                l.setLifted(readerEntry, Math.max(0, Math.min(i, l.fullResults.length - 2)));
            }
            // Active BEFORE exiting: the reader Loader's `active` is
            // `readerActive || readerExiting`, and bindings re-evaluate between
            // these two writes -- clearing exiting first flips it false for one
            // statement, which tears down the live reader (invalidating its
            // context, so r.reenter() explodes) and builds a fresh one.
            readerActive = true;
            readerExiting = false;
            r.reenter();
            return;
        }
        if (!l?.currentEntry)
            return;
        readerStartY = currentRowY();
        readerEntry = l.currentEntry;
        const i = l.fullResults.indexOf(readerEntry);
        l.setLifted(readerEntry, Math.max(0, Math.min(i, l.fullResults.length - 2)));
        readerActive = true;
    }

    // PgUp/PgDn/Home/End inside the reader scroll its text (smoothly).
    function readerScrollPage(dir: int): void {
        clipReader.item?.scrollPage(dir);
    }

    function readerScrollEdge(dir: int): void {
        clipReader.item?.scrollEdge(dir);
    }

    // ↑/↓ inside the reader step through the UNFILTERED results and move the
    // lift with them (the previous entry returns to the hidden list).
    function browseReader(step: int): void {
        const l = appList.item;
        if (!l || !readerActive || readerExiting)
            return;
        const full = l.fullResults;
        const i = full.indexOf(readerEntry);
        const j = i + step;
        if (i < 0 || j < 0 || j >= full.length)
            return;
        readerEntry = full[j];
        l.setLifted(readerEntry, Math.max(0, Math.min(j, full.length - 2)));
    }

    // Mirror of enter, staged so the reorder is actually SEEN: the header
    // starts sliding immediately toward where the gap WILL open -- which is
    // exactly where the below-neighbour sits right now (it inherits that spot
    // when the row returns above it). The re-insert itself waits ~140ms until
    // the list has melted in, so the neighbours visibly part to make room
    // mid-slide; the returning row stays masked until the header lands in the
    // hole, so the entry never renders twice.
    function exitReader(): void {
        if (!readerActive || readerExiting)
            return;
        const r = clipReader.item;
        const l = appList.item;
        if (r?.exitTo && l) {
            readerExiting = true;
            const i = Math.max(0, l.fullResults.indexOf(readerEntry));
            // The landing spot comes from the LAYOUT, not the animated item: on
            // a quick enter->exit the below-neighbour is still mid-flight
            // closing the gap, so its animated y sits below the settled gap and
            // the header would land short, then snap on unmask. Rows are
            // fixed-height, so index math gives the settled position directly
            // (and covers the last-row case with no special branch).
            const target = l.originY + i * (root.Tokens.sizes.launcher.itemHeight + l.spacing) - l.contentY;
            partTimer.index = i;
            readerActive = false;
            r.exitTo(target, () => {
                l.maskedEntry = null;
                root.readerEntry = null;
                root.readerExiting = false;
            });
            partTimer.restart();
        } else {
            resetReader();
        }
    }

    Timer {
        id: partTimer

        property int index: 0

        interval: 140
        onTriggered: {
            if (root.readerExiting)
                appList.item?.clearLift(index);
        }
    }

    // Closing the launcher mid-read must drop the reader, the lift/mask AND the
    // filter freeze, then re-sync (the freeze made the clear-on-close sync a
    // no-op).
    Connections {
        function onLauncherChanged(): void {
            if (!root.screenState.launcher && (root.readerActive || root.readerExiting)) {
                root.resetReader();
                appList.item?.syncDisplayText();
            }
        }

        target: root.screenState
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    // Reader rides on `state` (not animState) so the opacity fade below never
    // fires for it -- entering the reader is a pure geometric morph.
    state: readerActive && canRead ? "reader" : animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: root.Tokens.sizes.launcher.wallpaperHeight
                wallpaperList.active: true
            }
        },
        State {
            name: "reader"

            // Keep appList alive (currentIndex/model persist for ↑/↓ browse) but
            // hidden under the reader; no left/right anchors so width is intrinsic
            // and grows to the reader's content, centred like the wallpapers state.
            PropertyChanges {
                root.implicitWidth: clipReader.item?.implicitWidth ?? root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, clipReader.item?.implicitHeight ?? 0)
                appList.active: true
                appList.opacity: 0
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        // Reader enter/exit: the other rows melt out fast under the travelling
        // header (the shared element carries the continuity, not a crossfade).
        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
            frozen: root.readerActive
            exiting: root.readerExiting
        }
    }

    Loader {
        id: clipReader

        // Not state-driven: the reader must survive the flip back to the list
        // (readerExiting) so its header can finish sliding down onto the row.
        active: root.readerActive || root.readerExiting

        anchors.fill: parent

        sourceComponent: ClipReader {
            entry: root.readerEntry
            startY: root.readerStartY
            // Search text minus the `;` prefix: seeded with the list filter on
            // entry, live as the user keeps typing (the list itself is frozen).
            findTerm: {
                const t = root.search.text;
                const p = GlobalConfig.launcher.clipboardPrefix;
                return t.startsWith(p) ? t.slice(p.length) : t;
            }
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: WallpaperList {
            objectName: "launcherWallpaperList"

            search: root.search
            screenState: root.screenState
            panels: root.panels
            content: root.content
        }
    }

    Row {
        id: empty

        opacity: root.currentList?.count === 0 ? 1 : 0
        scale: root.currentList?.count === 0 ? 1 : 0.5

        spacing: Tokens.spacing.medium
        padding: Tokens.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: root.state === "wallpapers" ? "wallpaper_slideshow" : "manage_search"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.state === "wallpapers" ? qsTr("No wallpapers found") : qsTr("No results")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: root.state === "wallpapers" && Wallpapers.list.length === 0 ? qsTr("Try putting some wallpapers in %1").arg(Paths.shortenHome(Paths.wallsdir)) : qsTr("Try searching for something else")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitWidth {
        enabled: root.screenState.launcher

        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState.launcher

        Anim {}
    }
}
