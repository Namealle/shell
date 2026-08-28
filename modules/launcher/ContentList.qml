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
    // TEMPORARY (trial): when the reader last opened, so a close can tell a
    // real reading session from a keypress the next keypress cancelled.
    property double readerOpenedAt: 0
    // The list's contentY when exitReader measured the header's landing target.
    property real exitContentY: 0
    // displayState, NOT state: state's binding involves `frozen` (which we set
    // from readerActive), so reading it here would close a binding loop.
    readonly property bool canRead: (appList.item?.displayState ?? "") === "clipboard"
    // Owned, not derived from currentIndex: the entry being read is lifted OUT
    // of the list model, so list indices can't describe it.
    property var readerEntry: null
    // Which way the last ↑/↓ went. The reader no longer needs telling -- the
    // rail derives its direction from the index change -- but prefetchAround
    // still aims its window with it.
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
        if (l)
            l.resetLift();
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
            if (l.wantLift !== readerEntry) {
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
            readerOpenedAt = Date.now();
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
        readerOpenedAt = Date.now();
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
        // Still before readerEntry, though the reason has shrunk: the reader
        // used to stage synchronously off this write and the slide it started
        // had to already know its direction. The rail derives direction from the
        // index change instead, so this is now only prefetchAround's aim.
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
        //
        // Widened for the rail, and this is a correctness requirement now rather
        // than a nicety: the window has to cover every delegate the rail
        // instantiates, or a LIVE neighbour slides past as a blank frame. It
        // used to be enough to have the next entry ready by the time a key was
        // pressed, because only one entry was ever on screen.
        //
        // No fast-scroll detection to go with it. A held arrow repeats ~25-30x/s
        // and outruns any window worth building, because `cliphist decode` runs
        // one subprocess at a time -- a bigger queue is stale before it drains.
        // What matters is that the entry you STOP on resolves instantly, and
        // that already holds: the queue is replaced on every move with the
        // current entry first, so the last keypress wins.
        const ahead = 5;
        const behind = 3;
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
        // Image entries never enter the decode queue above (their thumbnails are
        // precached per row), so retaining is the only thing that keeps them
        // warm -- and on the rail every entry in this window is instantiated,
        // not just the one being read. Retained newest-first, so the current
        // entry survives longest.
        for (let k = out.length - 1; k >= 0; k--)
            Clipboard.retain(out[k]);
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
            // TEMPORARY (trial): cascade the rows back in. Stamped as the exit
            // STARTS, so the cascade runs under the header's slide rather than
            // after it.
            //
            // Only when the rows actually went away. A reader opened and closed
            // in the same breath never lets the list fade out -- the rows are
            // still sitting there at full strength, and the row that was lifted
            // has barely moved -- so throwing all of them out to their offset
            // and sliding them back is a full movement with nothing behind it.
            // That is what reads as a glitch: the transition undoes itself in a
            // moment while the cascade plays out in full regardless.
            //
            // SCALED by how long the reader was actually open, rather than
            // switched on past a threshold. A threshold has a cliff in it --
            // the same gesture a few milliseconds either side of the line
            // playing nothing or playing everything -- and an animation that
            // sometimes happens and sometimes does not for no visible reason is
            // the very inconsistency this was meant to remove. Scaled, a glance
            // gets a hint of the cascade, a real read gets all of it, and there
            // is no line to land on.
            //
            // Deliberately elapsed TIME and not the fade's current opacity:
            // these curves are front-loaded, so opacity is already 0.03 after
            // 80ms and would call that a completed departure.
            l.readerCascade = Math.max(0, Math.min(1, (Date.now() - root.readerOpenedAt) / root.Tokens.anim.durations.expressiveFastSpatial));
            l.readerClosedAt = Date.now();
            readerActive = false;
            r.exitTo(target, () => {
                // In order, and never partly: the row goes back into the model
                // first (normally partTimer did that mid-slide already, and
                // this is then a no-op), then the mask comes off. So the entry
                // is never drawn twice, and never missing from both.
                //
                // Safe to run early -- which a close from the top row does, its
                // header having no distance to travel, so the slide can settle
                // inside this very call.
                partTimer.stop();
                root.reinsert();
                l.maskedEntry = null;
                root.readerEntry = null;
                root.readerExiting = false;
            });
            // The staged re-insert is right only for a list that has SETTLED:
            // it exists so the neighbours are seen parting mid-slide, which
            // needs them to be sitting still first.
            //
            // Inside the enter's own gap-close it does the opposite. The rows
            // are still travelling upward over the lifted row's slot, and
            // holding the re-insert for another 140ms lets them keep going --
            // closing a gap around a row that the exit has already decided to
            // put back, and only then turning around. That is the whole
            // "they keep moving as if it were missing, then come back": a
            // close-then-reopen excursion for a keypress pair that meant
            // nothing had happened.
            //
            // Re-inserting at once instead lets the rows reverse from wherever
            // they have got to -- settleTo keeps a mid-flight row on its
            // trajectory rather than snapping it, which is exactly the
            // turn-around this needs.
            if (Date.now() - l.liftRequestedAt < root.Tokens.anim.durations.expressiveDefaultSpatial)
                root.reinsert();
            else
                partTimer.restart();
        } else {
            resetReader();
        }
    }

    // Put the lifted entry back. Normally on partTimer, so the neighbours are
    // seen parting mid-slide; early if a keypress needs the model settled first.
    function reinsert(): void {
        const l = appList.item;
        // Guarded on the LIFT, not on readerExiting. The exit handoff can land
        // before this timer does -- a slide with little or nothing left to
        // travel settles in a frame or two -- and clearing readerExiting is the
        // first thing it does. Asked about that flag, the timer then found the
        // exit already over and returned WITHOUT putting the entry back, so the
        // row stayed filtered out of the list until some later reader replaced
        // the lift, and the highlight sat one row off ever after.
        //
        // The lift is the thing that has to be undone exactly once, so ask
        // about the lift: idempotent, and correct from whichever of the two
        // paths gets here first. wantLift as well as liftedEntry, because on a
        // fast toggle the lift may still be inside the coalescing window, and
        // an unlift that skipped itself because "nothing is lifted yet" would
        // let that pending lift apply a frame later with nothing left to undo
        // it -- stranding the entry outside the list.
        if (!l || (!l.wantLift && !l.liftedEntry))
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
            // The rail's model. The list's filter is frozen while the reader is
            // open, so fullResults is stable for the reader's whole lifetime --
            // which is what lets the rail keep seven live delegates without
            // anything reshuffling underneath them.
            entries: appList.item?.fullResults ?? []
            // readerEntry stays the thing that is owned (the lift is keyed on
            // it); this is just where it sits. -1 while the entry has been
            // cleared but the exit slide is still running.
            index: Math.max(0, (appList.item?.fullResults ?? []).indexOf(root.readerEntry))
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
