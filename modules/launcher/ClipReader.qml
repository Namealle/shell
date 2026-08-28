pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

// Reader mode for the `;` clipboard picker. The launcher morphs into this: a
// selectable, line-numbered view of the highlighted entry's REAL text (list
// previews flatten newlines; `cliphist decode` restores them). Typing while in
// the reader finds within THIS entry (the list filter is frozen meanwhile) and
// scrolls to the first match. Images show their decoded thumbnail; other
// binaries just their descriptor.
//
// Two pieces and nothing else: a header that does not travel, and a rail that
// does.
//
//   +-------------------+
//   | # title.txt       |  <- header: fixed, content swaps
//   +-------------------+
//   | ...entry 3 tail   |   |
//   |...................|   | rail travels
//   | entry 4 head...   |   v
//   +-------------------+
//
// Everything about ONE entry lives in ClipBody. Seven of them are alive at any
// time and the rail scrolls between them, so browsing is a scroll past live
// neighbours rather than a swap of one body's contents.
//
// That is what retired the old transition, which was a live body plus a
// ShaderEffectSource of the entry being left, glued one frame away. Six patches
// hung off that one choice -- latched outW/outH so a frozen bitmap in a
// shrinking box would not squash, stagedW/stagedH because by slide time the
// frame had already resized to the ARRIVING entry, a live outExit because the
// two directions leave past different edges and only the top one holds still,
// onFinished-not-onStopped because stop() re-armed the capture, bodyTargetH
// because text loads progressively so the target height is not knowable at
// freeze time, and a monotonic railDist so a later taller entry could push the
// outgoing further out but never pull it back. All six were defending the same
// root cause: the outgoing entry was a bitmap and not a real thing. A bitmap
// cannot resize, cannot finish loading, and does not know which edge it is
// leaving by. A live neighbour does all three for free.
//
// It also gave the preloading something to reach. Thumbnails are decoded to
// disk on launcher open, reader-size copies are warmed when `;` is pressed, and
// decoded text is prefetched around the highlight on every move -- but with only
// one entry ever instantiated, a warm neighbour stayed warm and unused.
Item {
    id: root

    // The UNFILTERED result list and the position in it -- the rail's model, in
    // place of the single entry this used to take. The list's filter is frozen
    // while the reader is open, so this is stable for the rail's lifetime.
    required property var entries
    required property int index
    // Live find term (search text minus the `;` prefix), seeded by the filter.
    property string findTerm: ""

    // The entry under the header. Everything the header draws comes from here;
    // everything about how it RENDERS comes from `body`.
    readonly property var entry: root.entries[root.index] ?? null
    // The live ClipBody for that entry. The reader reads geometry off it --
    // widths, heights, the morph's landing box -- rather than computing any of
    // it a second time.
    //
    // Registered BY the delegates rather than read from ListView.currentItem,
    // because the rail deliberately has no currentIndex at all. See the rail.
    property var body: null

    onIndexChanged: {
        // The delegate for the new index is normally already alive -- cacheBuffer
        // keeps three max-height entries either side, and a browse only ever
        // moves by one. Without a currentIndex nothing else would force it into
        // existence, so if a jump ever outruns the buffer, do it here rather than
        // leave the reader with no body to size itself from.
        if (!rail.itemAtIndex(root.index))
            rail.positionViewAtIndex(root.index, ListView.Beginning);
    }

    // A new entry is under the header: take the rail to it.
    onBodyChanged: rail.pin()

    readonly property int maxHeight: Clipboard.readerMaxHeight
    readonly property int minWidth: Tokens.sizes.launcher.itemWidth

    // How far down the header sits, and NOT padding.large, for the same reason
    // there is no padding below the body: the reader has no edge of its own to
    // pad against. Content.qml already holds the whole content region a
    // padding.large off the launcher's top, so an inset here was a second
    // helping of it -- measured, the reader's title ink sat 13px lower than the
    // list's for the same window edge.
    //
    // The row is the thing to match, not the window, and a row does not pad its
    // content either -- it CENTRES it in itemHeight. So this is that centring,
    // which puts the header exactly where the row it was lifted from would have
    // drawn its own icon and title. See rowAlignY, which is the correction this
    // makes unnecessary.
    //
    // Floored at 0 for the degenerate case of a header taller than a row; the
    // morph's alignment stays correct there because rowAlignY re-derives from
    // this rather than assuming it won.
    readonly property real topInset: Math.max(0, (Tokens.sizes.launcher.itemHeight - header.implicitHeight) / 2)

    // Forwarded to whichever body is being read. PgUp/PgDn/Home/End reach the
    // reader from Content.qml and belong to the entry, not to the rail -- the
    // rail is stepped by the list's own browse.
    function scrollPage(dir: int): void {
        root.body?.scrollPage(dir);
    }

    function scrollEdge(dir: int): void {
        root.body?.scrollEdge(dir);
    }

    function resetZoom(): void {
        root.body?.resetZoom();
    }

    // Shared-element morph: the header IS the row. It starts at the row's y
    // (startY, from ContentList) and slides to the top; the rail is anchored to
    // it, so it unfolds beneath as the header rises. exitTo() runs the reverse
    // and only then lets ContentList swap back to the list.
    property real startY: 0
    property real slideY: 0
    property real slideX: 0
    property bool exiting: false
    property var exitCb: null

    // How far the list has scrolled since exitTo's target was measured.
    //
    // That target is a viewport coordinate, computed once from the list's
    // contentY when the exit starts. Scroll during the slide and the row moves
    // out from under it, so the header animates to where the row USED to be.
    // A scroll is a pure translation of the shared element, so nothing needs
    // retargeting -- just shift everything the slide positions. Fed by
    // ContentList, which owns the list.
    property real exitScroll: 0
    readonly property real slidePos: root.slideY - root.exitScroll

    // The header's resting insets differ from the row content's insets in the
    // list (padding.large vs padding.medium horizontally). The slide targets the
    // row CONTENT's exact position so the landing handoff is pixel-true, not
    // "close then snap".
    //
    // Vertically there is nothing left to correct, and that is topInset's doing
    // rather than a coincidence: the header now RESTS at the offset a row centres
    // its content to, so the enter slide is a pure translation from the row's y
    // to zero. Left derived rather than written as 0 so it stays true if either
    // end of that ever moves.
    readonly property real rowAlignY: (Tokens.sizes.launcher.itemHeight - header.implicitHeight) / 2 - root.topInset
    readonly property real rowAlignX: Tokens.padding.medium - Tokens.padding.large

    function exitTo(targetY: real, cb: var): void {
        // Stop BEFORE storing the callback: stopping a still-running enter
        // slide fires onStopped, which must not consume (and instantly fire)
        // the exit callback.
        slideAnim.stop();
        slideXAnim.stop();
        // The morph folds the body back into the row off LIVE endpoints, so a
        // zoomed image would hand a magnified, off-centre picture to a landing
        // computed for the fitted one. Back to fit before the slide starts.
        root.resetZoom();
        root.exitCb = cb;
        root.exiting = true;
        // The exit morph is aimed at the entry you are LEAVING FROM, which is
        // the one being read now. Re-latch, since a browse has almost certainly
        // moved off whatever the enter morph was aimed at.
        root.beginMorph();
        slideAnim.from = root.slideY;
        slideAnim.to = targetY + root.rowAlignY;
        slideXAnim.from = root.slideX;
        slideXAnim.to = root.rowAlignX;
        root.morphT = 0;
        slideAnim.start();
        slideXAnim.start();
    }

    // Mid-exit reversal: stop the outbound slide wherever it is and return the
    // header to the top. The pending exit callback is discarded FIRST --
    // stopping fires onStopped, which must not consume (and run) the handoff
    // that would unmask the row under the re-opened reader.
    function reenter(): void {
        root.exitCb = null;
        slideAnim.stop();
        slideXAnim.stop();
        root.exiting = false;
        root.beginMorph();
        slideAnim.from = root.slideY;
        slideAnim.to = 0;
        slideXAnim.from = root.slideX;
        slideXAnim.to = 0;
        root.morphT = 1;
        slideAnim.start();
        slideXAnim.start();
    }

    Anim {
        id: slideAnim

        target: root
        property: "slideY"
        onStopped: {
            const cb = root.exitCb;
            root.exitCb = null;
            if (cb)
                cb();
        }
    }

    Anim {
        id: slideXAnim

        target: root
        property: "slideX"
    }

    // Straight through from the body being read. The frame is always exactly
    // cropping the content moving through it, because ContentList's Behaviors
    // animate these on the same curve, the same tick and the same duration as
    // the rail's own contentY -- so the two are in lockstep with no
    // interpolation code at all. A body still growing as its text loads simply
    // retargets both.
    implicitWidth: root.body?.implicitWidth ?? root.minWidth
    // The dip/hold machinery that used to sit between these and the content
    // (heldHeight, dip, kick, holdTimer, maxHold) is gone. It existed to cover
    // decode latency while the next entry loaded, and a preloaded live
    // neighbour already knows its height before you arrive at it. What replaces
    // it is ClipBody's own implicitHeight floor, for the cold entry beyond the
    // prefetch window.

    // No bottom padding, and note that this is padding.large ONCE where the
    // other three sides get it -- deliberately, because the fourth side is not
    // an edge. The reader has no border of its own: the launcher is a single
    // surface, and below the body is Content.qml's own padding.large holding the
    // search bar off. So a bottom inset here was never padding against
    // anything, it was a second helping of the same gap, and it measured: 37px
    // from the last row's ink down to the search pill against 13px from the
    // header's ink down to that row. The soft edge that replaced it costs no
    // space at all -- see ClipBody.fadeRamp.
    //
    // The rail's bottomMargin goes with it, and not for tidiness: rail height
    // and body height are equal by construction (this implicitHeight is computed
    // FROM the body's), and a rail left taller than the entry pinned to its top
    // would show the gap to the NEXT entry in the difference.
    readonly property real minHeight: header.implicitHeight + root.topInset * 2
    implicitHeight: Math.max(root.minHeight, header.implicitHeight + (root.body?.implicitHeight ?? 0) + root.topInset + Tokens.spacing.small)

    Component.onCompleted: {
        // Start exactly on the row's content, become the header.
        slideY = startY + rowAlignY;
        slideX = rowAlignX;
        slideAnim.from = slideY;
        slideAnim.to = 0;
        slideXAnim.from = slideX;
        slideXAnim.to = 0;
        slideAnim.start();
        slideXAnim.start();
        beginMorph();
        morphT = 1;
    }

    // -- header: same icon + title as the row --
    //
    // The one persistent instance in the whole reader, because it is the shared
    // element of the enter/exit morph: it IS the lifted list row, flying up from
    // the list and back down onto it. The rail travels underneath it; it does
    // not travel itself. Its content just rebinds as the index moves.
    //
    // Deliberately NOT crossfaded on that rebind, though the shape invites it.
    // A held arrow repeats faster than any fade worth seeing, so the header
    // would sit permanently dimmed for as long as the key is down -- the exact
    // scar the old body fade left, and the reason it was eventually deleted.
    // The rail already carries the motion; the header's job is to be the one
    // thing that does not move.
    Item {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        // slideY/slideX carry the shared-element motion; the rail is anchored
        // below, so it compresses/unfolds with the header rather than being
        // overlapped.
        anchors.topMargin: root.topInset + root.slidePos
        anchors.leftMargin: Tokens.padding.large + root.slideX
        anchors.bottomMargin: 0

        implicitHeight: Math.max(headerIcon.implicitHeight, headerText.implicitHeight)

        MaterialIcon {
            id: headerIcon

            anchors.verticalCenter: parent.verticalCenter
            // Natural width, matching ClipItem's leading slot exactly: the row
            // reserves one 1em square for every entry type, so the header does
            // too, and the title sits at the same x in both. Any mismatch here
            // rides visibly through the whole slide and teleports across when
            // the handoff unmasks the row.
            text: Clipboard.iconOf(root.entry)
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        Item {
            id: headerText

            anchors.left: headerIcon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: title.implicitHeight + meta.implicitHeight

            StyledText {
                id: title

                anchors.left: parent.left
                anchors.right: parent.right
                text: root.entry?.name ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: meta

                anchors.left: parent.left
                anchors.top: title.bottom
                // Counts come from the body, which owns the decode. Falls back
                // to the row's own descriptor until it has one -- which is also
                // what a cold entry beyond the prefetch window shows.
                text: {
                    const c = root.body?.charCount ?? 0;
                    if (c > 0) {
                        const l = root.body?.lineCount ?? 1;
                        return `${c} ${c === 1 ? "character" : "characters"} · ${l} ${l === 1 ? "line" : "lines"}`;
                    }
                    return root.entry?.desc ?? "";
                }
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
            }
        }
    }

    // -- the rail --
    //
    // Seven entries in a vertical column. The column scrolls. The frame resizes
    // to whatever is under it. That is the whole model.
    ListView {
        id: rail

        // During exit the list is already returning underneath; only the header
        // (the shared element) stays visible for the slide back onto its row.
        visible: !root.exiting

        anchors.top: header.bottom
        anchors.topMargin: Tokens.spacing.small
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.bottomMargin: 0

        // The frame. Both entries in flight have their own size and the frame is
        // a third size on its way between them, so whatever hangs outside is cut
        // here -- exactly what the old body slide was already being cropped by.
        clip: true

        model: root.entries
        // NO currentIndex, deliberately, and this is the single most load-bearing
        // line in the file.
        //
        // QQuickItemView tracks its current item and, whenever currentIndex is
        // set programmatically (moveReason == SetIndex), scrolls contentY the
        // minimum needed to bring that item into view. It writes contentY from
        // C++, which BYPASSES the Behavior below -- so the rail teleports.
        //
        // It bites exactly where the bug was reported: reverse direction before a
        // move finishes and the current item is only half in view, so the view
        // "corrects" it in one frame. Traced at contentY 407 -> 244 in the same
        // event that currentIndex changed, arriving before pin() had run at all;
        // pin then animated the last 25px, which is why it read as the entry
        // appearing with no transition rather than as a jump. A move that starts
        // from rest never triggers it, which is why only reversals looked broken.
        //
        // Setting the range to agree with us does not help: any correction it
        // makes is unanimated and lands on (or next to) the target, which is the
        // same thing as having no transition. The only fix is to leave it without
        // a tracked item -- currentItem null means trackedItem null means
        // trackedPositionChanged returns immediately. The delegates announce
        // themselves to root.body instead, and `active` keys off root.index, so
        // nothing needed currentIndex in the first place.
        //
        // Programmatic only. That also settles the nesting: the wheel and the
        // keys reach each body's own inner Flickable without contest.
        interactive: false
        spacing: Tokens.spacing.medium

        // The preload, expressed as a pixel budget rather than a count, so it
        // self-scales: three max-height entries either side, and many more when
        // they are short.
        //
        // displayMargin, NOT cacheBuffer, and that is the difference between a
        // delegate existing when you step onto it and not. cacheBuffer's items
        // are created LAZILY, by a pass that runs once the view has gone idle --
        // so for the first moment after opening, and for the whole of a fast
        // browse, they are simply not there. Stepping onto one that is missing
        // falls through to positionViewAtIndex below, which writes contentY from
        // C++ and therefore does not animate: that is the one-frame teleport,
        // both on the first step after opening (nothing above the entry the
        // reader opened on had been built yet) and again in a burst.
        // displayMargin extends the region the view treats as visible, so those
        // delegates are built in the same pass as the visible ones.
        //
        // Plus whatever travel is still in flight, in the direction of travel. A
        // browse retargets the rail before it has arrived, so during a burst the
        // index runs ahead of contentY and the entry being stepped onto is
        // further off than any fixed budget can cover -- the margin has to reach
        // where the rail is GOING, not where it is. It costs nothing that was not
        // about to be needed anyway: those are exactly the entries the rail is
        // about to scroll past, and it collapses back to the base the moment the
        // rail settles.
        readonly property real lead: rail.target - rail.contentY
        displayMarginBeginning: 3 * root.maxHeight + Math.max(0, -rail.lead)
        displayMarginEnd: 3 * root.maxHeight + Math.max(0, rail.lead)

        // NOT padding -- nothing is drawn here, the rail never rests in it, and
        // `interactive: false` means it cannot be flicked into. It exists to put
        // Flickable's own bounds out of reach of the rail's own travel, at both
        // ends.
        //
        // Bottom: contentY == lastItem.y sits exactly on maxYExtent, and the
        // frame is ANIMATING towards the last entry's height for the whole move,
        // so for most of it maxYExtent is short and returnToBounds() clamps.
        // Measured, with the margin removed: contentY parked at 1672 against a
        // target of 2222 -- contentHeight minus the height of the entry being
        // LEFT.
        //
        // Top: the spatial curve overshoots ~21% of its travel, which drives
        // contentY negative on the way to entry 0, past minYExtent.
        //
        // Every clamp is a C++ write, so it is silent and it does not animate --
        // the same class of interference as the tracked-item reposition above,
        // and the reason both are designed out rather than worked around. The
        // margins also PRESERVE the overshoot instead of flattening it against
        // the bounds.
        topMargin: root.maxHeight
        bottomMargin: root.maxHeight

        // The rail's position, and the whole mechanism: pin the entry being read
        // to the top of the frame and let the Behavior carry the travel.
        //
        // Written, NOT bound. `contentY: body.y` is the obvious form and it
        // closes a loop with ListView's own layout: contentY decides which
        // delegates exist, instantiating one changes contentHeight and the y of
        // everything after it, and body.y is exactly what the binding reads. Qt
        // catches it -- "Binding loop detected for property contentY" -- and
        // BREAKS the binding, which leaves the rail parked and the reader showing
        // the wrong entry. (The standalone probes missed this: their delegates
        // were fixed-height and all within cacheBuffer from the first frame, so
        // nothing was ever created mid-move.)
        //
        // Driving it from the two signals that actually mean "the entry being
        // read moved" is the same value with no cycle, and the Behavior still
        // animates the result.
        //
        // StrictlyEnforceRange was the other obvious alternative and is strictly
        // worse: it hands the motion to ListView's velocity-based move, which
        // loses a race it cannot win, because the frame height is animating
        // underneath and the target keeps moving. Measured 236 against 784 and
        // 523 against 886 -- sampled well after both animations should have
        // finished, so that is not lag -- and it overshoots the wrong way on a
        // reversal.
        //
        // `target` is the same number kept separately, because contentY itself is
        // the ANIMATED value and says nothing about where it is heading. The
        // display margins above need the destination; see lead.
        property real target: 0

        function pin(): void {
            const it = root.body;
            if (it) {
                rail.target = it.y;
                rail.contentY = it.y;
            }
        }

        Component.onCompleted: {
            // Nothing else would bring the first entry into existence: with no
            // currentIndex the view only builds what is around contentY, which
            // starts at 0. Instant on purpose -- the open is the header's morph,
            // not a rail move.
            rail.positionViewAtIndex(root.index, ListView.Beginning);
            rail.target = rail.contentY;
            rail.pin();
        }

        // The entry being read moved without the index changing -- which is what
        // happens when a neighbour ABOVE it finishes decoding and grows. Without
        // this, a prefetch landing would slide the entry you are reading out from
        // under you.
        Connections {
            target: root.body
            ignoreUnknownSignals: true

            function onYChanged(): void {
                rail.pin();
            }
        }

        // The shell's spatial curve, which is also what ContentList animates the
        // frame's implicitWidth/implicitHeight on. Same curve, same tick, same
        // duration: that is what puts the frame and the rail in lockstep.
        Behavior on contentY {
            Anim {}
        }

        delegate: ClipBody {
            id: bodyDelegate

            required property int index
            required property var modelData

            width: rail.width
            height: implicitHeight

            entry: modelData
            active: bodyDelegate.index === root.index
            // Is the enter/exit morph aimed at THIS entry -- see root.morphIndex.
            readonly property bool morphTarget: bodyDelegate.index === root.morphIndex

            // Neighbours are the browse transition and nothing else. During the
            // enter morph the frame is still animating down from the LIST's size,
            // so everything below the entry being read is visible purely because
            // the frame has not finished closing on it: opening on a one-line clip
            // put the next two entries on screen for the length of the morph
            // (measured: rail 181px tall around a 19px entry, with neighbours at
            // y=31 and y=62). They are not sliding anywhere, so they read as
            // stowaways rather than as motion.
            //
            // Gated on the INDEX still being the morph's own, not on the morph
            // being in flight -- step before it lands and the rail really is
            // browsing, so the neighbour arriving has to be visible. That is the
            // same interruption morphIndex exists for.
            visible: bodyDelegate.active || root.index !== root.morphIndex || !root.morphInFlight
            // Only the entry being read. Finding inside a neighbour has nothing
            // to scroll to, and it would cost a lowercased copy of every entry
            // on the rail per keystroke.
            findTerm: bodyDelegate.active ? root.findTerm : ""
            // The leading-slot morph is aimed at one entry and at nothing else,
            // so every other body on the rail draws its own image/swatch
            // immediately. Keyed on the morph's target rather than on `active`:
            // step mid-morph and those stop being the same entry, and keying on
            // active would then hide the arriving picture (which no morph is
            // covering) while showing the departing one twice.
            handedOff: !bodyDelegate.morphTarget || (root.morphT >= 1 && !root.morphing)

            // Stands in for ListView.currentItem, which the rail deliberately
            // does not have. Whichever delegate is active announces itself, and
            // hands the slot back if it is recycled while still active (which
            // would otherwise leave the reader sizing itself off a dead object).
            //
            // Order-independent: on a step the outgoing delegate may clear the
            // slot before or after the incoming one claims it, and the guard on
            // identity makes both orders land the same way.
            onActiveChanged: {
                if (bodyDelegate.active)
                    root.body = bodyDelegate;
                else if (root.body === bodyDelegate)
                    root.body = null;
            }

            // Same registration, same reasons, for the morph's target -- which is
            // the same delegate as `body` right up until you step mid-morph.
            onMorphTargetChanged: {
                if (bodyDelegate.morphTarget)
                    root.morphBody = bodyDelegate;
                else if (root.morphBody === bodyDelegate)
                    root.morphBody = null;
            }

            Component.onCompleted: {
                if (bodyDelegate.active)
                    root.body = bodyDelegate;
                if (bodyDelegate.morphTarget)
                    root.morphBody = bodyDelegate;
            }

            Component.onDestruction: {
                if (root.body === bodyDelegate)
                    root.body = null;
                if (root.morphBody === bodyDelegate)
                    root.morphBody = null;
            }
        }
    }

    // -- leading-slot morphs: the row's thumbnail/swatch becomes the body --
    // Second shared elements riding the same slide, one per entry kind that has
    // something in its leading slot. At t=0 both exactly cover the header's
    // material icon slot -- which is pixel-identical to the row's thumbnail /
    // swatch slot, so the icon really is "under" it -- and at t=1 they exactly
    // cover the rect the corresponding body item paints. Every endpoint is a
    // live binding (the slot follows slideX/slideY), so enter, exit and
    // mid-flight reversals all stay glued.
    property real morphT: 0

    Behavior on morphT {
        Anim {
            id: morphAnim
        }
    }

    // The entry the morph is aimed at, LATCHED when it starts -- not read live
    // off root.index, which is a different entry the moment you step before the
    // morph has landed.
    //
    // Following the index instead is what made a quick step after opening on an
    // image look like the next picture teleporting in: the overlay simply
    // re-pointed at the arriving entry, so its image appeared at whatever size
    // the curve happened to be at, parked near the header for the rest of the
    // morph, and then popped into the body. Traced with the overlay drawing
    // entry 7 at 488px wide and, on the very next sample, entry 8 at 585px --
    // with entry 8's real image held hidden underneath the whole time, so the
    // rail scrolled an empty box into place.
    //
    // Latched, the two motions are independent and both stay correct: the morph
    // finishes onto the entry it lifted from (following it up as the rail
    // carries it away, see morphBodyTop), and the entry you stepped to is just
    // an ordinary neighbour sliding in with its picture already drawn.
    property int morphIndex: root.index
    // Its live body, registered by the delegate exactly as `body` is, and for
    // the same reason -- the rail has no currentItem to ask.
    property var morphBody: null

    function beginMorph(): void {
        root.morphIndex = root.index;
    }

    // The whole enter/exit morph, including the tail of the overshoot. See the
    // note on `morphing` for why the value alone is not enough.
    readonly property bool morphInFlight: root.morphing || root.morphT < 1

    // The handoff between a morph and the body item it lands on is keyed on the
    // ANIMATION, not on morphT reaching 1 -- the expressive spatial curve
    // overshoots (peak 1.0139), so it crosses 1.0 at only 47% of the duration
    // (243ms of 514ms, measured). Keying on the value handed off there and
    // snapped the last 271ms away invisibly: the morph appeared to arrive early
    // and hard, with none of the overshoot the rest of the launcher has.
    // `running` goes true synchronously with the assignment and stays true
    // across a mid-flight retarget, so this neither flashes at the start nor
    // breaks reenter().
    readonly property bool morphing: morphAnim.running

    // The source slot, shared by both morphs: the square the ROW draws, which is
    // the icon's 1em advance (see headerIcon and ClipItem). implicitWidth, not
    // implicitHeight -- the line box is 1.2em and a morph starting from it would
    // begin 8px larger than the thumbnail it is supposed to be lifting off.
    //
    // Also fixes the thumbnail sourceSize on both ends at 2x this: ClipItem's
    // `thumb` and this file's `mThumb` load the same url at the same size, which
    // is what makes the morph's first frame a synchronous cache hit rather than
    // an empty rect. They have to move together or that silently stops working.
    readonly property real slotS: headerIcon.implicitWidth
    readonly property real slotX: Tokens.padding.large + root.slideX
    readonly property real slotY: root.topInset + root.slidePos + (header.implicitHeight - root.slotS) / 2
    // Top of the morph target's content in root coordinates -- where both morphs
    // land. Two offsets come off it: how far that entry is scrolled WITHIN
    // itself, and how far the rail has carried it since.
    //
    // The second is zero for an uninterrupted morph -- the entry being morphed
    // to is the one pinned to the top of the frame, so contentY IS its y. It
    // stops being zero the moment you step mid-morph, and then it is exactly
    // what keeps the overlay glued to the entry it is landing on while the rail
    // slides that entry out of the frame. Without it the morph would finish onto
    // empty space and hand off to a body that had already moved.
    readonly property real morphBodyTop: root.topInset + root.slidePos + header.implicitHeight + Tokens.spacing.small - (root.morphBody?.scrollY ?? 0) - (root.morphBody ? rail.contentY - root.morphBody.y : 0)

    // Geometry of the body being morphed to, read off the live ClipBody rather
    // than recomputed here -- so the handoff at t=1 is exact by construction
    // instead of by two expressions agreeing.
    readonly property bool morphIsImage: root.morphBody?.isImage ?? false
    readonly property bool morphIsColour: root.morphBody?.isColour ?? false
    readonly property color morphColour: root.morphBody?.colourValue ?? "transparent"
    readonly property real bodyContentW: root.morphBody?.contentW ?? (root.minWidth - Tokens.padding.large * 2)
    // Where that content box sits inside the frame -- non-zero exactly while the
    // frame is a different width from the entry, which is the whole of a move.
    // See ClipBody.contentX; reading it rather than restating it is what keeps
    // the landing exact.
    readonly property real bodyContentX: root.morphBody?.contentX ?? 0
    readonly property real bodyImgBoxW: root.morphBody?.imgBoxW ?? 0
    readonly property real bodyImgFitH: root.morphBody?.imgFitH ?? 0
    readonly property string bodyImgSrc: root.morphBody?.imgSrc ?? ""
    readonly property int bodyImgDecodeW: root.morphBody?.imgDecodeW ?? Clipboard.readerMaxWidth
    readonly property bool bodyImgReady: root.morphBody?.imgReady ?? false
    readonly property real bodySwatchHeight: root.morphBody?.swatchHeight ?? 0

    // -- corner rounding --
    //
    // The row's thumbnail is a rounded square (ClipItem's thumbWrapper, a
    // StyledClippingRect at rounding.small) and the reader's image is square, so
    // the morph travels between the two. It did not: the scissor clip below is
    // exact but cannot round, so the corners changed in one frame at whichever
    // end the overlay handed off -- most visibly on the exit, where a square
    // picture became a rounded thumbnail the instant the overlay went away.
    //
    // Rounding costs a texture round trip however it is done. Quickshell's
    // ClippingRectangle renders its content through a ShaderEffectSource and
    // samples it in a shader, at every radius including 0 -- there is no
    // rectangular fast path -- and a layer + Mask is the same trip by another
    // name.
    //
    // How much that trip actually costs is worth stating precisely, because the
    // number this file used to carry (7% less high-frequency energy, which read
    // as the picture snapping into focus at the t=1 landing) does not reproduce.
    // Measured on a round trip at the seam's box size, against the same texture
    // drawn straight: pixel-IDENTICAL at integer positions (max channel
    // difference 0/255), and 0.99 of the detail at fractional ones, i.e. the cost
    // is a second bilinear sample and nothing more. That was measured on
    // layer.enabled rather than on ClippingRectangle itself, which cannot be
    // loaded outside the quickshell binary -- so it is the mechanism that was
    // tested, not the component. Treat 7% as unexplained rather than as refuted.
    //
    // Either way the conservative arrangement is the same, and it is cheap: carry
    // the rounding only for the end of the morph that is actually round. The
    // radius reaches 0 exactly at roundEnd and the path switches there too, so
    // the seam is the same box, the same texture and square corners on both
    // sides -- geometrically identical, whatever the sampling does. And the t=1
    // landing, the one that sits still at full size and was the original
    // complaint, never enters the rounded path at all.
    //
    // Deliberately StyledClippingRect and not a Mask effect: the exit lands on
    // ClipItem's thumbWrapper, which IS a StyledClippingRect at this radius, so
    // matching the component matches its antialiasing and its shader. A mask that
    // merely looked similar would leave the pop where it is, just smaller.
    readonly property real roundEnd: 0.25
    readonly property bool morphRounded: root.morphT < root.roundEnd
    // Clamped at both ends: morphT overshoots past 1, and the exit can drive it
    // to exactly 0 where the row's own radius takes over.
    readonly property real morphRadius: Tokens.rounding.small * Math.max(0, Math.min(1, 1 - root.morphT / root.roundEnd))

    // The two copies of the picture the overlay draws, defined once and
    // instantiated in both clip paths. Same url, same sourceSize, same fillMode,
    // caching on at both ends, so the two instantiations resolve to ONE texture
    // and cost no second decode -- the same sharing that makes the row's
    // thumbnail a synchronous cache hit here in the first place.
    component MorphPicture: Item {
        // The picture the row was already showing, scaled up. Blurry at full
        // size, but it is the right image at the right aspect, and mImg fades
        // over it. Underneath sits the container's surface colour, which only
        // shows for entries whose row thumbnail has not decoded either.
        Image {
            id: mThumb

            anchors.fill: parent
            source: root.bodyImgSrc
            fillMode: Image.PreserveAspectCrop
            cache: !Clipboard.noCache
            asynchronous: true
            sourceSize.width: root.slotS * 2
            sourceSize.height: root.slotS * 2
        }

        Image {
            id: mImg

            anchors.fill: parent
            source: root.bodyImgSrc
            fillMode: Image.PreserveAspectCrop
            // Shares its decode with the body's own image -- see the note there.
            cache: !Clipboard.noCache
            asynchronous: true
            // This is the one that actually needs the mipmaps. The morph draws
            // this texture into a box that starts at slotS (~41px) and grows to
            // imgBoxW, so early frames are a 20x-plus reduction. Four bilinear
            // taps cannot represent that and shimmer instead; a mip chain
            // pre-averages it. The extra softness only exists while the box is
            // tiny, which is exactly when there is no detail to lose.
            mipmap: true
            sourceSize.width: root.bodyImgDecodeW
            // Cross-fade over the thumbnail rather than popping. Effects-fast,
            // not spatial: the geometry is already animating underneath and a
            // slow fade would just read as the picture arriving late.
            opacity: root.bodyImgReady ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }
    }

    // Both overlays live in here, and it exists for one edge: the top.
    //
    // A morph is allowed over the header -- it is LIFTING OFF the header's icon
    // slot, so at t=0 it is entirely inside the header's band and it grows out of
    // it. What is not allowed is the tail of an interrupted morph, which rides its
    // entry out of the frame (see morphBodyTop) and, unclipped, swept a
    // full-size picture straight across the title on its way up.
    //
    // So the cut travels with the morph: at t=0 the top edge is on the slot, which
    // is exactly where the overlay starts, so nothing is cut and the lift is
    // untouched. At t=1 it is exactly the rail's own top edge, so the ride-out
    // passes UNDER the header like any other rail content. In between the two
    // interpolate together -- the clip edge and the overlay's own top are the same
    // expression, one pixel apart -- so there is no moment where the cut is ahead
    // of the picture.
    //
    // Only the top, and the bottom is deliberately whatever the overlays need.
    // Pulling it in to the rail's would clip the growing picture's lower edge
    // while the frame is still opening, and the EXIT morph leaves the frame
    // entirely -- it folds back down onto a row that can be most of a list-height
    // below, long after the frame has started shrinking away from it.
    Item {
        id: morphClip

        clip: true
        width: root.width
        y: Math.min(rail.y, root.slotY + (rail.y - root.slotY) * Math.min(1, root.morphT)) - 1
        height: Math.max(root.height - y, morphImg.y + morphImg.height, morphSwatch.y + morphSwatch.height)

        Item {
            id: morphImg

            // Geometry only -- the clipping lives in the two children, which is
            // what lets the morph be rounded at the row end and scissor-exact at
            // the body end. See root.roundEnd.

            // The rect the body's image actually paints -- the same imgBoxW the body
            // Image is sized to, so the handoff at t=1 is exact. Only horizontal
            // centring can occur: the box is the image's own shape, so there is no
            // letterbox.
            readonly property real fitW: root.bodyImgBoxW > 0 ? root.bodyImgBoxW : root.bodyContentW
            readonly property real fitH: root.bodyImgBoxW > 0 ? root.bodyImgFitH : root.bodyContentW
            readonly property real dstX: Tokens.padding.large + root.bodyContentX + (root.bodyContentW - fitW) / 2

            // Size AND position both ride the raw curve, overshoot included. They
            // have to be the same t or the picture does not bounce -- it slides.
            //
            // Size used to be clamped here, Math.min(1, morphT), on the argument
            // that the texture is decoded at exactly fitW so drawing it past 1 is
            // a magnification with no pixels behind it. That much is true. What
            // the argument missed is what the clamp leaves behind: position kept
            // riding the raw curve, so at the peak the picture was its final SIZE
            // at an overshot POSITION -- a pure translation. A translation moves
            // both edges the same way, so against a frame growing symmetrically
            // around it, one edge opened a gap and the other stayed pinned. Which
            // is what it looked like: a picture sliding sideways, on a launcher
            // that was visibly bouncing. Reported as "the launcher overshoots but
            // the image does not", and that was exactly right.
            //
            // The magnification it was avoiding is 1.39% -- the curve's peak, and
            // the whole of it. Confirmed by running the morph at a 25% overshoot
            // curve and 3000ms, where the softness IS visible and the bounce is
            // unmistakable; at 1/18th of that, only the bounce survives.
            //
            // Still worth knowing if the curve is ever made more expressive: past
            // roughly 5% the softness starts to cost more than the bounce is
            // worth, and the fix then is a clamp again, not a bigger sourceSize
            // (that only moves the softness onto the RESTING image, which is
            // worse -- it is there all the time instead of for 200ms).
            readonly property real sizeT: root.morphT

            visible: root.morphIsImage && root.morphInFlight
            x: root.slotX + (dstX - root.slotX) * root.morphT
            // Relative to morphClip, which is what carries the cut. The absolute
            // expression is unchanged.
            y: root.slotY + (root.morphBodyTop - root.slotY) * root.morphT - morphClip.y
            width: root.slotS + (fitW - root.slotS) * sizeT
            height: root.slotS + (fitH - root.slotS) * sizeT

            // The rounded end of the morph -- the row's own component, at the
            // row's own radius, so the exit landing is a handoff between two
            // identical things rather than a resemblance. Carries the surface
            // colour itself; no backing rect needed, since a ClippingRectangle
            // paints one under its content.
            StyledClippingRect {
                anchors.fill: parent
                visible: root.morphRounded
                radius: root.morphRadius
                color: Colours.palette.m3surfaceContainerHigh

                MorphPicture {
                    anchors.fill: parent
                }
            }

            // The square end. A plain scissor clip: exact, no texture round trip,
            // and therefore the path the t=1 landing on the body image is made
            // through -- the landing hands off between two items drawn the same
            // way, which is the property worth keeping whatever the round trip
            // costs.
            Item {
                anchors.fill: parent
                visible: !root.morphRounded
                clip: true

                StyledRect {
                    anchors.fill: parent
                    color: Colours.palette.m3surfaceContainerHigh
                }

                MorphPicture {
                    anchors.fill: parent
                }
            }
        }

        // The colour swatch's morph. Full body width at t=1, so the only endpoint
        // that differs from the slot is the size -- and the radius stays put, since
        // both the row's swatch and the body's use rounding.small. A plain rect,
        // not a clipping one: there is no child to clip, and a Rectangle composites
        // a semi-transparent colour without going through a shader.
        StyledRect {
            id: morphSwatch

            visible: root.morphIsColour && root.morphInFlight
            x: root.slotX + (Tokens.padding.large + root.bodyContentX - root.slotX) * root.morphT
            // Relative to morphClip, which is what carries the cut. The absolute
            // expression is unchanged.
            y: root.slotY + (root.morphBodyTop - root.slotY) * root.morphT - morphClip.y
            width: root.slotS + (root.bodyContentW - root.slotS) * root.morphT
            height: root.slotS + (root.bodySwatchHeight - root.slotS) * root.morphT
            radius: Tokens.rounding.small
            color: root.morphColour
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }
    }
}
