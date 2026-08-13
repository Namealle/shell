pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.launcher.services
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

    // The reader lifts its entry OUT of the list model (AppList.results filters
    // out liftedEntry), so a filter that matched exactly one entry leaves the
    // model empty while the reader is up. That is not "no results" -- without
    // this the placeholder fades in on top of the reader's own body.
    readonly property bool showEmpty: currentList?.count === 0 && !readerActive && !readerExiting

    // Clipboard reader (Option D): `→` morphs the launcher into a reader for the
    // highlighted entry, `←` morphs back. Only meaningful in clipboard mode.
    property bool readerActive: false
    // Where the highlighted row sat (in this item's coords) when the reader was
    // entered -- the reader's header is the shared element: it starts here and
    // slides to the top, and slides back down here on exit.
    property real readerStartY: 0
    property bool readerExiting: false
    // The list's contentY when exitReader measured the header's landing target.
    property real exitContentY: 0
    // displayState, NOT state: state's binding involves `frozen` (which we set
    // from readerActive), so reading it here would close a binding loop.
    readonly property bool canRead: (appList.item?.displayState ?? "") === "clipboard"
    // Owned, not derived from currentIndex: the entry being read is lifted OUT
    // of the list model, so list indices can't describe it.
    property var readerEntry: null
    // Which way the last ↑/↓ went, for the reader's body slide. 0 means "not a
    // browse" -- an open has no direction, and its morph must not get one.
    property int readerStep: 0
    // Not while exiting: erasing the `;` unfreezes the list, which flips
    // displayState off "clipboard" and would fire this hard reset straight
    // through the exit slide that the erase itself just started.
    onCanReadChanged: if (!canRead && !readerExiting) resetReader()

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
        readerStep = 0;
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
        // An open is not a browse: clear the direction left over from the last
        // one, or the body would slide while the header is still morphing.
        readerStep = 0;
        readerEntry = l.currentEntry;
        const i = l.fullResults.indexOf(readerEntry);
        l.setLifted(readerEntry, Math.max(0, Math.min(i, l.fullResults.length - 2)));
        readerActive = true;
        // Explicit rather than left to the currentEntry hook: lifting the entry
        // out of the model moves currentEntry to a neighbour, so that hook would
        // centre the window one row off.
        prefetchAround(1);
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
        // BEFORE readerEntry: changing that runs the reader's staging
        // synchronously, and the slide it starts has to already know which way
        // it is going.
        readerStep = step;
        readerEntry = full[j];
        l.setLifted(readerEntry, Math.max(0, Math.min(j, full.length - 2)));
        root.prefetchAround(step);
    }

    // Decode around the highlight so the reader's next entry is already in hand
    // when the key is pressed -- the reader can only swap instantly if it has
    // nothing to wait for.
    //
    // Weighted towards travel, and re-issued on every move: the queue is
    // replaced, not appended to, so reversing direction re-prioritises at once
    // rather than finishing a window you have already left. Always includes the
    // CURRENT entry, which is what makes → into the reader instant too.
    function prefetchAround(step: int): void {
        const l = appList.item;
        if (!l || !canRead)
            return;
        const full = l.fullResults;
        const cur = readerActive ? readerEntry : l.currentEntry;
        const i = full.indexOf(cur);
        if (i < 0)
            return;
        const dir = step >= 0 ? 1 : -1;
        const out = [cur];
        // Asymmetric on purpose: the row you are heading towards is far likelier
        // to be read than the one you just left, but backing up one step is
        // common enough to be worth covering.
        const ahead = 4;
        const behind = 2;
        for (let d = 1; d <= ahead; d++) {
            const f = full[i + dir * d];
            if (f)
                out.push(f);
            if (d <= behind) {
                const b = full[i - dir * d];
                if (b)
                    out.push(b);
            }
        }
        Clipboard.prefetch(out);
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
            // The contentY `target` is relative to. Scrolling during the slide
            // shifts the header by the difference (see ClipReader.exitScroll).
            exitContentY = l.contentY;
            partTimer.index = i;
            partTimer.fromIndex = l.currentIndex;
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

    // Put the lifted entry back. Normally on partTimer, so the neighbours are
    // seen parting mid-slide; early if a keypress needs the model settled first.
    function reinsert(): void {
        const l = appList.item;
        if (!root.readerExiting || !l)
            return;
        // Carry over anything ↑/↓ did during the slide. Restoring the captured
        // index flat undid those keypresses ~140ms after they landed, which read
        // as the first key after ← being ignored.
        //
        // A DELTA rather than currentIndex itself: while the entry is lifted the
        // index counts the filtered list, and it is additionally clamped to
        // length-2 on the last row, so the two only coincide in the common case.
        const want = partTimer.index + l.currentIndex - partTimer.fromIndex;
        l.clearLift(Math.max(0, Math.min(want, l.fullResults.length - 1)));
    }

    // ↑/↓ outside the reader. Ordinary navigation, except inside the exit window.
    //
    // The re-insert shifts every row below the gap, so a keypress landing in the
    // 140ms before it starts the highlight towards a row that then moves out from
    // under it -- traced at 327 → 389 → 324 in 9ms, a glide cancelled and
    // restarted for no net movement. The press was not dropped, it was spent.
    //
    // Settling the model first costs only the remainder of a wait that exists for
    // an animation the user has just overtaken, and leaves the highlight one
    // stable target. Deliberately BEFORE the step: reinsert() reads currentIndex
    // to carry the delta, so it has to see the pre-step value.
    function listStep(step: int): void {
        if (readerExiting && partTimer.running) {
            partTimer.stop();
            reinsert();
        }
        const l = currentList;
        if (!l)
            return;
        if (step > 0)
            l.incrementCurrentIndex();
        else
            l.decrementCurrentIndex();
    }

    Timer {
        id: partTimer

        property int index: 0
        // currentIndex when the exit started, so navigation during the slide can
        // be told apart from the index sitting still.
        property int fromIndex: 0

        interval: 140
        onTriggered: root.reinsert()
    }

    // Dropping the reader, the lift/mask and the filter freeze has to happen on
    // REOPEN, not on close. Resetting on close flipped the state -- and with it
    // implicitWidth -- out of the reader while the close animation was still on
    // screen, which is the inner half of the width teleport (Wrapper.qml freezes
    // the outer one). Closing needs no cleanup of its own: the content Loader
    // tears this whole subtree down once the launcher is off screen. The only
    // case that survives is a reopen that caught the still-alive tree, so clean
    // up there, where the state flip is invisible anyway.
    Connections {
        function onLauncherChanged(): void {
            if (root.screenState.launcher && (root.readerActive || root.readerExiting)) {
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
            // appList.opacity is deliberately NOT a PropertyChanges -- see the
            // binding on the Loader itself. It must not be state-restored.
            PropertyChanges {
                root.implicitWidth: clipReader.item?.implicitWidth ?? root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, clipReader.item?.implicitHeight ?? 0)
                appList.active: true
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

        // A BINDING, not a PropertyChanges in the reader state. PropertyChanges
        // restores the value it captured on state entry, and with the Behavior
        // below still in flight that capture is the current animated value, not
        // 1 -- so entering/exiting the reader faster than the Behavior can
        // finish re-captures a lower base every cycle and decays the list's
        // opacity geometrically to zero, permanently, across every launcher
        // mode. A binding has a fixed target and cannot drift.
        opacity: root.state === "reader" ? 0 : 1

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

    // Prefetch while browsing the LIST too, not just inside the reader. This is
    // the one that makes → open instantly: by the time the reader is created its
    // entry has usually been decoded already.
    // Which row the highlight was on last, so the window can be aimed the way
    // you are actually travelling. The reader's own browse passes a real step;
    // this signal does not carry one, and assuming "down" pointed the window
    // backwards for the entire time you were arrowing up -- the direction the
    // weighting exists to serve.
    property int prefetchLastIndex: -1

    Connections {
        target: appList.item

        function onCurrentEntryChanged(): void {
            if (root.readerActive || root.readerExiting)
                return;
            const i = appList.item?.currentIndex ?? -1;
            // First move of a session has no direction yet; down is the way a
            // list is read, and it is what a fresh highlight at the top wants.
            const step = root.prefetchLastIndex < 0 || i >= root.prefetchLastIndex ? 1 : -1;
            root.prefetchLastIndex = i;
            root.prefetchAround(step);
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
            browseStep: root.readerStep
            startY: root.readerStartY
            exitScroll: root.readerExiting ? (appList.item?.contentY ?? 0) - root.exitContentY : 0
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

        opacity: root.showEmpty ? 1 : 0
        scale: root.showEmpty ? 1 : 0.5

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
