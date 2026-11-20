pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.items
import qs.modules.launcher.services

StyledListView {
    id: root

    required property SearchBar search
    required property ScreenState screenState

    property string displayText

    // While the clipboard reader is open, typing is find-within-entry, not list
    // filtering: hold displayText (and therefore results + currentEntry) still.
    property bool frozen: false

    readonly property string requestedState: stateForText(search.text)
    readonly property string displayState: stateForText(displayText)

    // Typing while the clipboard reader's exit is still sliding home: the
    // query changes under an entry that is lifted out of this list, held for
    // a staged re-insert, and being landed on a row. Said either side of the
    // change, because ContentList has to hold the reader's rail BEFORE the
    // results move under it, and re-aim the exit after.
    signal exitQueryChanging
    signal exitQueryChanged

    function syncDisplayText(): void {
        if (frozen)
            return;
        if (screenState.launcher && requestedState === displayState) {
            const requery = root.exiting && displayText !== search.text;
            if (requery)
                root.exitQueryChanging();
            displayText = search.text;
            if (requery)
                root.exitQueryChanged();
        }
    }

    function stateForText(text: string): string {
        if (text.startsWith(GlobalConfig.launcher.clipboardPrefix))
            return "clipboard";

        const prefix = GlobalConfig.launcher.actionPrefix;
        if (text.startsWith(prefix)) {
            for (const action of ["calc", "scheme", "variant"])
                if (text.startsWith(`${prefix}${action} `))
                    return action;

            return "actions";
        }

        return "apps";
    }

    function resultsForText(text: string): var {
        switch (stateForText(text)) {
        case "clipboard":
            return Clipboard.query(text);
        case "actions":
            return Actions.query(text);
        case "calc":
            return [0];
        case "scheme":
            return Schemes.query(text);
        case "variant":
            return M3Variants.query(text);
        default:
            return Apps.search(text);
        }
    }

    // Shared-element physics for the clipboard reader: the entry being read is
    // LIFTED out of the model (its neighbours close the gap with the standard
    // move/displaced animations, exactly like filtering) and its row is masked.
    // On exit the lift clears first -- neighbours part to reopen the gap while
    // the reader's header slides into it -- and the mask clears only when the
    // header lands, so the entry never exists in two places at once.
    property var liftedEntry: null
    property var maskedEntry: null
    // The thumbnail-only counterpart, for rows whose picture is an orphaned
    // reader morph still flying home (ClipReader.latchMorph). Set by
    // ContentList; read by ClipItem.
    property var thumbMaskedEntries: []
    // The clipboard reader's pill is standing in for the highlight (see
    // ClipReader's pill). Set by ContentList.
    property bool highlightMasked: false
    property int pendingIndex: -1

    // Del in the clipboard picker. The deletion reaches the model a
    // `cliphist delete` + `cliphist list` round trip later, as an ordinary
    // values change -- which resets to the top exactly like a new query, so
    // every delete threw the view back to the newest entry. Remember the row
    // and the query it belongs to; that change then keeps the index, and the
    // highlight lands on the entry that slid up into the gap. Typing before
    // the reload lands is a real query change and still resets.
    property int deleteIndex: -1
    property string deleteQuery: ""

    function deleteCurrent(): bool {
        const entry = root.currentItem?.modelData;
        if (!entry?.del)
            return false;
        root.deleteIndex = root.currentIndex;
        root.deleteQuery = root.displayText;
        entry.del();
        return true;
    }

    // The model change is taken OUT of the keypress and onto the next event
    // loop turn, and that is the whole of it.
    //
    // Applied synchronously from the key handler it lands in the middle of
    // ContentList still flipping readerActive/readerExiting and starting the
    // reader's own animations, and Qt's view bookkeeping does not survive it:
    // every displaced row is handed a ViewTransition.destination of (0,0) and
    // moved there. A one-shot timer fixes it for two reasons, and the delay is
    // not really either of them -- the change now arrives after Qt has finished
    // with the previous one, and a lift and an unlift issued in the SAME turn
    // coalesce into nothing at all, since `wantLift` returns to what the model
    // already is. Which is the truthful outcome: at that speed nothing had
    // moved yet, so there is nothing to undo.
    //
    // Deliberately a single turn and NOT "wait until the rows are at rest".
    // Waiting for the transitions makes an exit sit through the whole entry
    // animation before turning around, and leaves the row missing from the list
    // long after the reader has closed.
    //
    // The mask is NOT deferred. It has to be immediate or the row would draw
    // underneath its own header while that header flies.
    property var wantLift: null
    property int wantIndex: -1

    // When the last lift was REQUESTED, so the exit path can tell "the
    // neighbours are still closing the gap" from "the list settled long ago".
    // Those want opposite things from the re-insert, and there is no way to ask
    // a ListView whether its transitions are still running.
    //
    // Requested, not applied -- which is the whole of the both-keys-at-once
    // case. A lift spends a turn in the coalescing window below before it
    // reaches the model, so an exit landing inside THAT window would read a
    // timestamp from some earlier lift, conclude the list had long since
    // settled, and stage the re-insert. The lift then applies a turn later and
    // starts a gap-close that nothing cancels for 140ms -- the same excursion,
    // now only reachable by pressing both arrows together. Timed from the
    // request, that exit re-inserts at once, the coalescing timer finds the
    // lift already undone, and nothing moves at all: at that speed nothing had
    // moved yet, so there is nothing to undo.
    property double liftRequestedAt: 0

    function setLifted(entry: var, index: int): void {
        root.readerGapIndex = -1;
        root.maskedEntry = entry;
        root.wantLift = entry;
        root.wantIndex = index;
        root.liftRequestedAt = Date.now();
        coalesce.restart();
    }

    function clearLift(restoreIndex: int): void {
        root.wantLift = null;
        root.wantIndex = restoreIndex;
        coalesce.restart();
    }

    // Whether a row inserted in front of `index` lands ABOVE the view instead
    // of parting the rows below it a stride down.
    //
    // QQuickListView decides that per change (applyInsertionChange, and
    // removeItem for a removal): a change whose slot lies before the first
    // row in view is absorbed above it -- the content grows or shrinks at the
    // top (originY moves a stride) and every row below keeps its y. Only a
    // change at or after that row moves the rows below it. "In view" is the
    // first row whose bottom edge is past contentY, so the insert lands above
    // exactly when the row now at `index` ends at or above contentY.
    //
    // Key navigation keeps the highlighted row in view, so the entry the
    // reader opens on is never above it that way. The wheel scrolls without
    // moving the highlight: scroll down, read the highlighted row from above
    // the view, close, and the re-insert lands above. The rows below were held
    // a stride low for a parting that never came, and stayed there for good --
    // two rows drawn in one slot, the slot above empty (his recording of
    // 2026-11-19 17:35; ClipInvariants logged "row 7 drawn 65.0px off its
    // slot; rows 7 and 8 drawn on one slot", hold=65 on row 7). Traced in the
    // nest (wheel a notch, read row 0, close): the lift at index 0 with row 2
    // first in view left every row's y alone and moved originY 0 -> 65; the
    // re-insert moved originY back and again left every y alone, so rows 1-7
    // kept hold=65 with nothing to spend it on.
    function insertLandsAbove(index: int): bool {
        if (index >= root.count)
            return false;
        const it = root.itemAtIndex(index);
        const top = it ? it.y : root.originY + index * (Tokens.sizes.launcher.itemHeight + root.spacing);
        const height = it ? it.height : Tokens.sizes.launcher.itemHeight;
        return top + height <= root.contentY;
    }

    // Teardown, where no animation is owed to anyone.
    function resetLift(): void {
        coalesce.stop();
        root.readerGapIndex = -1;
        root.wantLift = null;
        root.wantIndex = -1;
        root.liftedEntry = null;
        root.maskedEntry = null;
        root.pendingIndex = -1;
    }

    // -- the rows a SECOND model change moves without animating them --
    //
    // A change that lands inside an earlier change's transitions is handled by
    // the view on its own terms: it animates the row next to the change and
    // hard-places every other one. Measured on a reader opened and shut inside
    // its own gap-close -- five rows owed a stride back down, one animated and
    // four moved in a single frame, which is the row he filmed "teleporting
    // from default position to existing one in one frame".
    //
    // Distinct from the corrupt (0,0) destination settleTo repairs, and not
    // fixable there: these rows are handed no transition at all, so nothing of
    // ours runs for them. Two theories were tested and dropped -- it is not the
    // add/displaced split (removing addDisplaced so the change falls through to
    // displaced leaves the same single row animating), and the rows are not
    // rebuilt (delegate identities are unchanged across the frame).
    //
    // So the answer is the ROW's, exactly as it is for the rows a filter brings
    // in without moving them: only what actually arrived without motion should
    // move, and a row can tell -- settleTo stamps every row the view DID hand a
    // transition to, so a jump carrying an older stamp than this change is a
    // placement. See ClipItem's onYChanged.
    property double repairAt: 0

    function applyLift(): void {
        // Before the model change, so a transition started inside it stamps
        // later than this and the row knows it was animated after all.
        root.repairAt = Date.now();
        if (root.wantLift === root.liftedEntry)
            return;
        // The re-insert the rows below the gap are held for (gapHold) is about
        // to land above the view, where it parts nothing: the hold would never
        // be spent. Checked again here, not only when the exit staged it,
        // because the view can scroll in between. Releasing the gap index
        // slides the held rows back onto their slots (ClipItem).
        if (!root.wantLift && root.readerGapIndex >= 0 && root.insertLandsAbove(root.readerGapIndex))
            root.readerGapIndex = -1;
        root.pendingIndex = root.wantIndex;
        root.liftedEntry = root.wantLift;
    }

    // A lift or unlift still inside the coalescing window, applied now -- for
    // a keypress that has to read the model as it is about to be.
    function flushLift(): void {
        if (!coalesce.running)
            return;
        coalesce.stop();
        root.applyLift();
    }

    Timer {
        id: coalesce

        interval: 1
        onTriggered: root.applyLift()
    }

    readonly property var fullResults: root.resultsForText(root.displayText)
    readonly property var results: root.liftedEntry ? root.fullResults.filter(e => e !== root.liftedEntry) : root.fullResults
    readonly property var currentEntry: state === "clipboard" ? (root.results[root.currentIndex] ?? null) : null

    // -- the rows a filter change brings in without moving them --
    //
    // Narrowing a filter drops the visible rows, and the ones that take their
    // place were ALREADY in the model, below the fold. The view instantiates
    // those where they land: no add to fade, no move or displacement to slide.
    // Instrumented on the real history, ";e" -> ";eg" emits zero transitions of
    // any kind, and ";fe" -> ";fec" emits seven that each travel zero distance
    // -- which is the same thing on screen. That is the "swaps in a single
    // frame" this exists to answer.
    //
    // The answer belongs to the ROW, not to the list. A list-level offset was
    // tried and is wrong on its face: it shifts every row, including the ones
    // that are already where they belong and the ones that are mid-slide, so a
    // change that moved four rows correctly nudged the other three for no
    // reason and double-moved the four. Per row, only what actually arrived
    // without motion animates -- see ClipItem's entrance.
    //
    // A delegate is only built for a row that was not on screen a moment ago,
    // so "was one just built?" is the exact question, and the row asks it by
    // looking at how recently the results changed.
    property double filterChangedAt: 0
    // When the reader last began closing, so the rows can
    // come back in a cascade rather than as one block. Separate from
    // filterChangedAt because nothing is rebuilt here -- the rows were behind
    // the reader the whole time, so they have to be TOLD to play, where a
    // filter's rows announce themselves by being built.
    property double readerClosedAt: 0
    // 0..1, how much of that cascade to play -- see
    // ContentList, which sets it from how long the reader was actually open.
    property real readerCascade: 0
    // Which row of the LIFTED list the closing reader's entry returns above, or
    // -1 when the re-insert is not staged. Rows from here down are about to be
    // parted a stride by it -- see ClipItem's gapHold.
    property int readerGapIndex: -1
    property string lastTopState: ""
    property var lastLifted: null

    onResultsChanged: {
        const sameMode = root.displayState === root.lastTopState;
        const liftChanged = root.liftedEntry !== root.lastLifted;

        root.lastTopState = root.displayState;
        root.lastLifted = root.liftedEntry;

        // Not across a mode switch -- that has its own fade-and-scale
        // transition and does not want a second one inside it -- and not for
        // the reader's lift or re-insert, whose one-row change has its own
        // choreography and must not make the row scrolling up into the gap
        // look like a filter result.
        if (!sameMode || liftChanged)
            return;

        root.filterChangedAt = Date.now();
    }

    model: ScriptModel {
        values: root.results

        // Identity, NOT the default Structure -- this is the whole typing
        // freeze.
        //
        // ScriptModel diffs old against new to emit move/insert/remove ops
        // (which is what makes the row animations possible at all), and that
        // diff is O(old x new) comparisons: ~70k of them for a clipboard
        // filter going 300 <-> 750. Under Structure, every comparison that is
        // not already identical falls into a RECURSIVE walk of both objects'
        // properties -- for a ClipEntry that means comparing raw (up to 999
        // chars), preview, name, desc, binMatch, imgDims and the rest, tens of
        // thousands of times per keystroke. Measured 100ms of a 140ms stall.
        //
        // Every mode this list serves compares correctly by identity, so the
        // structural walk buys nothing here: clipboard entries are the shared
        // ClipEntry instances resolved through Clipboard.entryFor, apps are
        // DesktopEntry objects, actions/schemes/variants are declared QtObject
        // instances, and calc is a literal.
        comparisonMode: ObjectComparison.Identity

        // Lift/unlift must not yank the view back to the top: they pass the
        // index to keep via pendingIndex, a delete via deleteIndex; genuine
        // query changes still reset.
        onValuesChanged: {
            if (root.pendingIndex >= 0)
                root.currentIndex = root.pendingIndex;
            else if (root.deleteIndex >= 0 && root.deleteQuery === root.displayText)
                root.currentIndex = Math.min(root.deleteIndex, root.results.length - 1);
            else {
                root.currentIndex = 0;
                // A new query starts at the top, so put the view there now
                // rather than leave it to the highlight range. Left to the
                // range, a query that shrank the list from deep in the
                // history (past where the new content ends) left the view
                // with no rows built at all: only the current row, the rest
                // of the panel black until some later change -- filmed by
                // him on ";df" typed 55 rows down, and measured the same
                // without the reader: count 4, itemAtIndex null for every
                // row, forceLayout no help; NoHighlightRange, or this, and
                // the rows are there. Same place the range would have put it,
                // in the same frame.
                root.positionViewAtBeginning();
            }
            root.pendingIndex = -1;
            root.deleteIndex = -1;
        }
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    // Every mode uses fixed-height rows (clipboard included), so item count sizes
    // the list exactly -- a stable, discrete height. Deriving it from contentHeight
    // instead makes the launcher chase a value that fluctuates all through the
    // move/displaced animations, which overshoots and ghosts. Keep it count-based,
    // identical to apps/actions.
    implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    // implicitHeight, NOT height: this list is anchors.fill on a parent the
    // reader inflates to 640px+, so `height` asks whether the row fits a
    // viewport that is about to stop existing. implicitHeight is the resting
    // height -- count-based and never animated -- so the range describes where
    // the rows actually land. Outside the reader the two are equal.
    //
    // That also retires the exit-window freeze this used to need: the freeze
    // existed because the range re-evaluated against the ANIMATING height and
    // yanked contentY mid-slide, and implicitHeight does not animate.
    preferredHighlightEnd: implicitHeight
    highlightRangeMode: ListView.ApplyRange

    // Only while the reader's header is sliding home.
    //
    // ApplyRange repositions the view in one frame, which is right everywhere
    // else -- the highlight's own glide carries the motion. During the exit it
    // is the one thing NOT animating: the header is sliding, the list is fading
    // in, the neighbours are parting, and the rows teleporting a row upward
    // through the middle of that reads as the whole animation ending early.
    //
    // Gated rather than always on: an unconditional Behavior intercepts the
    // Flickable's own writes during a drag or wheel flick and turns ordinary
    // scrolling to treacle.
    property bool exiting: false

    Behavior on contentY {
        enabled: root.exiting
        Anim {}
    }

    // -- the selection stays where it can be seen --
    //
    // The wheel (and the scrollbar, and a touchpad) scroll the list without
    // moving the selection, and keys never leave it off screen, so only a
    // scroll could put it there -- and then `->` read a row nobody could see.
    // His recording of 2026-11-19 20:09: the selection on row 11, the wheel
    // took the list well past it, `->` lifted the reader off a row 150px
    // above the panel (the picture came in clipped through the top edge),
    // and the close aimed back up there: the re-insert above the view jumped
    // the list in one frame and the picture landed a row off. Filmed again
    // the same afternoon at 17:35 (a76db60c).
    //
    // So once a scroll takes the selected row out of view, the selection
    // moves to the row under the pointer -- the one being looked at, and the
    // one a wheel scroll always has, since the wheel only reaches the list
    // under the pointer -- and stays with the pointer for the rest of that
    // scroll, so where the wheel stops, the row under the pointer is the one
    // `->` opens. With the pointer elsewhere it goes to the first whole row
    // on the side the selection left by. The highlight is placed at once
    // rather than glided: it was off screen, so nothing visible jumps, and a
    // glide in from outside the view would have the highlight range drag the
    // list back after it, against the scroll. Any other move of the
    // selection (a key, a query) hands it back to the keys.
    //
    // Only for a scroll the user made. A keypress or a new query moves the
    // highlight on its glide and the range scrolls after it, so while the
    // glide runs the view is following the selection, not leaving it. The
    // reader owns the selection while it is open or landing (readerBusy);
    // whatever a scroll did meanwhile is settled when it hands back.
    property bool readerBusy: false
    property bool snapHighlight: false
    // The selection was put under the pointer by a scroll and nothing else
    // has moved it since.
    property bool selectionOnPointer: false
    readonly property real viewHeight: Math.min(root.height, root.implicitHeight)

    // Whether row `index` is whole inside the view.
    function rowInView(index: int): bool {
        const y = root.rowY(index);
        return y >= root.contentY - 0.5 && y + Tokens.sizes.launcher.itemHeight <= root.contentY + root.viewHeight + 0.5;
    }

    // `scrolled`: the list just moved. Without it (an open asking), a
    // selection in view stays where it is even if the pointer has since
    // moved to another row -- the highlight is what says what opens.
    function keepSelectionInView(scrolled = true): void {
        if (root.state !== "clipboard" || root.readerBusy || root.count === 0 || root.frozen)
            return;
        if (root.highlightItem?.gliding)
            return;
        const inView = root.rowInView(root.currentIndex);
        if (inView && (!root.selectionOnPointer || !scrolled))
            return;
        const stride = Tokens.sizes.launcher.itemHeight + root.spacing;
        let k = -1;
        if (pointer.hovered) {
            // From the scene: a handler declared in a Flickable may sit on its
            // contentItem, whose coordinates scroll.
            const sp = pointer.point.scenePosition;
            const p = root.mapFromItem(null, sp.x, sp.y);
            const at = p.y + root.contentY - root.originY;
            const i = Math.floor(at / stride);
            // On a row, not in the spacing between two.
            if (i >= 0 && i < root.count && at - i * stride < Tokens.sizes.launcher.itemHeight && root.rowInView(i))
                k = i;
        }
        // Between two rows, or on one cut by the edge: stay put if still in
        // view; the next row under the pointer takes over when it comes.
        if (k < 0 && inView)
            return;
        const onPointer = k >= 0;
        if (k < 0) {
            const first = Math.ceil((root.contentY - root.originY - 0.5) / stride);
            const last = Math.floor((root.contentY + root.viewHeight - Tokens.sizes.launcher.itemHeight - root.originY + 0.5) / stride);
            k = root.rowY(root.currentIndex) < root.contentY ? first : last;
            k = Math.max(0, Math.min(root.count - 1, k));
        }
        // The first move off a selection the scroll took out of view: the
        // highlight fades in on its new row. Later ones keep it under the
        // pointer as rows pass beneath, and move it outright, like a hover.
        const takeover = !inView;
        root.selectionOnPointer = onPointer;
        if (k === root.currentIndex)
            return;
        root.snapHighlight = true;
        root.currentIndex = k;
        root.snapHighlight = false;
        if (takeover) {
            root.highlightFade = 0;
            highlightFadeIn.restart();
        }
    }

    property real highlightFade: 1

    Anim {
        id: highlightFadeIn

        target: root
        property: "highlightFade"
        to: 1
        type: Anim.DefaultEffects
    }

    onContentYChanged: root.keepSelectionInView()
    onCurrentIndexChanged: {
        if (!root.snapHighlight)
            root.selectionOnPointer = false;
    }
    // The reader handing the list back after a scroll during its close.
    onReaderBusyChanged: if (!root.readerBusy) selectionCheck.restart()

    Timer {
        id: selectionCheck

        interval: 0
        onTriggered: root.keepSelectionInView()
    }

    // Passive: where the pointer is over the list, for the row it points at.
    HoverHandler {
        id: pointer
    }

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        // The glide below is running: the range is scrolling the view after
        // the selection, which is not the selection leaving the view.
        readonly property bool gliding: glide.running

        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        // Faded in where a scroll put it (keepSelectionInView): it has no
        // place on screen to travel from, so it appears rather than jumps.
        opacity: 0.08 * root.highlightFade

        // From the LAYOUT, not the animated item -- the same reason exitReader
        // computes its landing spot this way.
        //
        // currentItem.y is a live value mid-transition. Re-inserting the lifted
        // entry displaces every row BELOW the gap, so stepping down onto one
        // aimed the highlight at a row still animating into place and it chased
        // it the whole way; stepping up onto an undisplaced row was instant. The
        // asymmetry was the tell.
        //
        // Rows are fixed-height in every mode this list serves (see
        // implicitHeight above), so index math gives the settled position
        // directly -- and outside a transition the two agree exactly.
        y: root.originY + root.currentIndex * (Tokens.sizes.launcher.itemHeight + root.spacing)
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        // Hidden while the reader's pill stands for it. Only hidden: its
        // geometry and its glide are untouched, because the view's highlight
        // range tracks this item -- snapping it while masked (tried) scrolled
        // the list a row further under the reader and changed where every
        // row lands. The lift keeps currentIndex on the row being read, so
        // the highlight is already on the landing row when the mask comes off.
        visible: !root.highlightMasked

        Behavior on y {
            // Off for the one write that puts the selection back in view
            // (keepSelectionInView).
            enabled: !root.snapHighlight

            Anim {
                id: glide
            }
        }
    }

    state: screenState.launcher && !frozen ? requestedState : displayState

    onStateChanged: {
        // Gates the launcher's full-size image preload (see Wrapper): the
        // picker's pictures are only worth decoding once the picker is what is
        // on screen. Assigned on every state change, not just the clipboard
        // one, so leaving the mode turns it back off.
        Clipboard.picking = state === "clipboard";

        if (state === "scheme" || state === "variant")
            Schemes.reload();
        else if (state === "clipboard")
            Clipboard.reload();
    }

    Component.onCompleted: displayText = search.text

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                root.delegate: calcItem
            }
        },
        State {
            name: "scheme"

            PropertyChanges {
                root.delegate: schemeItem
            }
        },
        State {
            name: "variant"

            PropertyChanges {
                root.delegate: variantItem
            }
        },
        State {
            name: "clipboard"

            PropertyChanges {
                root.delegate: clipItem
            }
        }
    ]

    transitions: Transition {
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 1
                    to: 0.9
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
            }
            PropertyAction {
                target: root
                property: "delegate"
                value: null
            }
            ScriptAction {
                script: root.displayText = root.search.text
            }
            PropertyAction {
                target: root
                property: "delegate"
            }
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 0.9
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
            }
            // add only -- NOT remove. A remove-fade leaves every filtered-out row
            // fading in place under its replacement (double-text ghost), and a
            // slide-out exit was tried and rejected; removed rows vanish
            // instantly, like the launcher always did before the first mode
            // switch.
            PropertyAction {
                target: root.add
                property: "enabled"
                value: true
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 1
            to: 0
        }
    }

    // Rows can be moved across the whole content span by a model change (e.g. a
    // clipboard filter hoisting a match from thousands of px down). The curve's
    // overshoot scales with the animated distance, so animating such teleports
    // literally sends rows flying across the screen. Cap the ANIMATED distance
    // at one viewport: longer moves first jump to a viewport away, then slide
    // the final stretch with the usual curve -- bounded overshoot, same feel,
    // and genuinely short moves are untouched.
    function capTravel(item: Item, destY: real): void {
        if (!item)
            return;
        const travel = destY - item.y;
        if (Math.abs(travel) > height)
            item.y = destY - Math.sign(travel) * height;
    }

    // Where row `index` rests, from the LAYOUT rather than from anything
    // animated. Every mode this list serves has fixed-height rows (see
    // implicitHeight), so index math gives the settled position directly.
    function rowY(index: int): real {
        return originY + index * (Tokens.sizes.launcher.itemHeight + spacing);
    }

    // Backstop for a ViewTransition.destination that arrives corrupt. When a
    // model change lands while an earlier change's transitions are still in
    // flight, QQuickItemView hands every displaced row a destination of (0,0)
    // and has usually MOVED the row there before this script runs.
    //
    // Stating the animation's `to` is half the answer; the item's CURRENT
    // position can be a lie too. Two cases, and they look nothing like each
    // other:
    //
    //   - Clobbered: the row was moved to the bogus destination, so it sits a
    //     whole list away from its slot. There is nothing to animate from, so
    //     drop it on the slot and let the animation find zero travel.
    //   - Mid-flight: an interrupted lift leaves rows exactly on their
    //     trajectory, a row-height or less off their slot. That position is the
    //     truthful place to turn around from -- snapping it is what makes a
    //     reversal teleport instead of reverse.
    //
    // Two row-heights separates them comfortably. Detected rather than assumed,
    // so the healthy path is untouched: on an uninterrupted transition Qt's
    // destination IS rowY(index) to the pixel and this falls through to
    // capTravel exactly as before.
    //
    // It repairs the POSITION only. The target stays a `to:` binding, and that
    // split is load-bearing: a Transition's animation objects are shared by
    // every item transitioning at once, while its `to:` binding and
    // ViewTransition.index are evaluated per item. Writing `someAnim.to = ...`
    // from here has each item's job pick up whichever value the last
    // ScriptAction left behind, landing the whole list one slot out.
    function settleTo(item: Item, index: int, destY: real): void {
        if (!item)
            return;
        // The row's proof that the view is animating it -- see repairAt. Only
        // ClipItem keeps it; the other modes' rows go through here too, and
        // writing a property they do not have threw out of this function
        // before the repair below ran.
        if (item.transitionedAt !== undefined)
            item.transitionedAt = Date.now();
        const want = root.rowY(index);
        if (Math.abs(destY - want) > 0.5) {
            const stride = Tokens.sizes.launcher.itemHeight + root.spacing;
            if (Math.abs(item.y - want) > stride * 2)
                item.y = want;
            return;
        }
        root.capTravel(item, want);
    }

    move: Transition {
        id: moveT

        SequentialAnimation {
            ScriptAction {
                script: root.settleTo(moveT.ViewTransition.item, moveT.ViewTransition.index, moveT.ViewTransition.destination.y)
            }
            ParallelAnimation {
                Anim {
                    property: "y"
                    to: root.rowY(moveT.ViewTransition.index)
                }
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    to: 1
                }
            }
        }
    }

    addDisplaced: Transition {
        id: addDispT

        // Sequential, like move and displaced, and for the same reason: the
        // repair in settleTo has to have run before anything animates. Children
        // of a Transition run in parallel, so a bare ScriptAction here would
        // race the very animation it exists to correct.
        SequentialAnimation {
            ScriptAction {
                script: root.settleTo(addDispT.ViewTransition.item, addDispT.ViewTransition.index, addDispT.ViewTransition.destination.y)
            }
            ParallelAnimation {
                Anim {
                    property: "y"
                    type: Anim.StandardSmall
                    to: root.rowY(addDispT.ViewTransition.index)
                }
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    to: 1
                }
            }
        }
    }

    displaced: Transition {
        id: dispT

        SequentialAnimation {
            ScriptAction {
                script: root.settleTo(dispT.ViewTransition.item, dispT.ViewTransition.index, dispT.ViewTransition.destination.y)
            }
            ParallelAnimation {
                Anim {
                    property: "y"
                    to: root.rowY(dispT.ViewTransition.index)
                }
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    to: 1
                }
            }
        }
    }

    Component {
        id: appItem

        AppItem {
            screenState: root.screenState
        }
    }

    Component {
        id: actionItem

        ActionItem {
            list: root
        }
    }

    Component {
        id: calcItem

        CalcItem {
            list: root
        }
    }

    Component {
        id: schemeItem

        SchemeItem {
            list: root
        }
    }

    Component {
        id: variantItem

        VariantItem {
            list: root
        }
    }

    Component {
        id: clipItem

        ClipItem {
            list: root
        }
    }

    Connections {
        function onTextChanged() {
            root.syncDisplayText();
        }

        target: root.search
    }

    Connections {
        function onLauncherChanged() {
            root.syncDisplayText();
        }

        target: root.screenState
    }
}
