pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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

    function copySelection(): bool {
        return root.body?.copySelection() ?? false;
    }

    // Shared-element morph: the header IS the row. It starts at the row's y
    // (startY, from ContentList) and slides to the top; the rail is anchored to
    // it, so it unfolds beneath as the header rises. exitTo() runs the reverse
    // and only then lets ContentList swap back to the list.
    property real startY: 0
    // How tall the panel was when the reader was opened, i.e. where its bottom
    // edge is -- see enterDistance.
    property real startHeight: 0
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

    // The list underneath (AppList), for the one thing that has to land on a
    // row other than the header's: an orphaned leading-slot morph folding back
    // into its own row's thumbnail. See rowSlotOf.
    property var listView: null

    // -- the body's own slide --
    //
    // The text travels WITH the header. Entering, the header flies up from the
    // row to the top, so the body comes up from below it; exiting, the header
    // goes back down onto the row and the body goes down with it. Direction is
    // taken from the slide the header is actually about to run, never assumed:
    // opening on the top row is a real case where the header barely moves, and
    // can move the other way.
    //
    // Text only. An image or a colour already HAS its shared-element morph --
    // the row's thumbnail or swatch growing into the body -- and a second
    // translation laid over that would drag the morph off its landing.
    property real bodySlide: 0
    property real bodyFade: 1
    // Travel scales with the body, and the DURATION follows the travel, so the
    // speed is the same whatever is being read.
    //
    // The ceiling is three rows' worth -- a scroll's distance rather than a
    // nudge, sized against paging the text (ClipBody.scrollPage moves 0.9 of a
    // viewport). The FIRST row is what made that necessary: open the reader
    // anywhere else and the header flies up from its row, which is most of what
    // you see, but on row 0 the header already sits where it lands, nothing
    // flies, and the body is the only thing moving. A row-sized offset vanished
    // inside the panel's own growth there.
    //
    // But a fixed distance is wrong at the other end. A one-line entry is ~19px
    // tall, so three rows of travel moved it ten times its own height, and at a
    // fixed 500ms that read as slow -- the panel had finished growing long
    // before the text stopped arriving. Scaling both together keeps a
    // one-liner's entrance short and quick and a full-screen one long and
    // stately, at one constant speed.
    readonly property real bodySlideMax: (Tokens.sizes.launcher.itemHeight + Tokens.spacing.small) * 3
    readonly property real bodySlideDistance: {
        const h = root.body?.liveHeight ?? 0;
        // No body to measure yet -- take the long entrance rather than a
        // fraction of a guess, since an entry still resolving its height is far
        // likelier to be a big one than a one-liner.
        if (h <= 0)
            return root.bodySlideMax;
        return Math.max(Tokens.spacing.large * 2, Math.min(root.bodySlideMax, h * 0.6));
    }
    readonly property int bodySlideDuration: Math.max(Tokens.anim.durations.expressiveFastEffects, Math.round(Tokens.anim.durations.expressiveDefaultSpatial * root.bodySlideDistance / root.bodySlideMax))

    // -- where an ENTERING body starts: on the panel's bottom edge --
    //
    // The distance above is a nudge sized to the body, and on the way in it was
    // not a slide at all. The Translate moves the rail WITH its clip, so that
    // clip never crops anything the slide does; the only edge the text can come
    // in across is the panel's own. And 195px below the header is nowhere near
    // it on a seven-row list: filmed at 28ms a frame, the text is simply there
    // on the first frame, whole and at full opacity in the middle of the panel
    // on top of rows that are still fading, and then travels. "Appearing and
    // sliding", where a browse inside the reader truly slides.
    //
    // So start the rail exactly on the bottom edge. No duration scaling either,
    // and not for simplicity: the panel's height, the header's slide and this
    // all run the same curve over the same 500ms, so the three stay in lockstep
    // and the text crosses the edge and rides up at the pace the panel resizes,
    // whether it is growing for a page or shrinking for a one-liner.
    //
    // Zero or less means the row opened sits so low that the rail, anchored
    // under the header, already starts at the edge and rides up with it.
    readonly property real enterDistance: root.startHeight - (root.topInset + root.startY + root.rowAlignY + header.implicitHeight + Tokens.spacing.small)

    // Asked of the ENTRY, not of `body`: the delegates register themselves a
    // moment after this reader is built, so on the way in there is nothing to
    // ask yet. Same three tests ClipBody makes.
    readonly property bool entryIsText: !!root.entry && !root.entry.binMatch && Clipboard.colourEntryOf(root.entry).length === 0

    // `exitEdge`: on the way out, how far below its resting place the rail has
    // to end to sit exactly on the bottom edge of the panel the list is about
    // to have -- the mirror of enterDistance. Negative when unknown.
    function beginBodySlide(travel: real, entering: bool, fresh = false, exitEdge = -1): void {
        bodySlideAnim.stop();
        bodyFadeAnim.stop();

        if (!root.entryIsText) {
            root.bodySlide = 0;
            // What the rail's visibility used to say outright: on the way out
            // the list is already back underneath, so only the header (the
            // shared element) has any business still being drawn.
            root.bodyFade = entering ? 1 : 0;
            return;
        }

        // Which way the BODY goes: the same way the header does, travel < 0
        // being the header rising.
        //
        // When the header has nowhere to go the sign of ~0 is meaningless, and
        // that is not a corner case -- it is opening on the row the header
        // already lands on, i.e. the first one. Fall back to the direction the
        // READER is unfolding instead: up on the way in, down on the way out.
        // Taking the raw sign there sent the body up on the way out while the
        // panel collapsed downwards underneath it.
        const dir = Math.abs(travel) > 4 ? (travel > 0 ? 1 : -1) : (entering ? -1 : 1);
        // From the edge only when the body comes up from below, which is every
        // open but the odd one whose header travels downwards.
        const fromEdge = fresh && dir < 0 && root.startHeight > 0;
        // And back out across it. The way out used to be a 195px nudge under a
        // fade, which is its own thing to look at -- a body dissolving is not a
        // body leaving -- and it is what made every open after the first look
        // like the old one: close and re-open inside the header's slide and the
        // reader is still alive, so the body was picked up a nudge below its
        // place and half faded, and "came back" by appearing while it slid.
        // Leaving across the edge at full strength, a re-entry finds it either
        // still in view and simply turns it round, or past the edge, where
        // coming back IS sliding in.
        const toEdge = !entering && dir > 0 && exitEdge >= 0;
        if (entering) {
            // Start on the far side of where the header is going, so the body
            // arrives travelling the same way the header does.
            //
            // Only on a fresh open. A re-entry half-way through an exit turns
            // the body round from wherever it has got to.
            if (fresh)
                root.bodySlide = fromEdge ? Math.max(0, root.enterDistance) : -dir * root.bodySlideDistance;
            // Deliberately NOT faded up from nothing. The rail clips, so the
            // body scrolls in from outside the frame with its text readable the
            // whole way -- which is the point, since scrolling never fades. It
            // used to start invisible and spend the fade's duration becoming
            // legible, and that showed up as the reader feeling slow to answer
            // the keypress. Animated rather than assigned so a re-entry
            // half-way through an exit brings it back from where it got to.
            bodySlideAnim.to = 0;
            bodyFadeAnim.to = 1;
        } else if (toEdge) {
            bodySlideAnim.to = Math.max(root.bodySlide, exitEdge);
            bodyFadeAnim.to = 1;
        } else {
            bodySlideAnim.to = dir * root.bodySlideDistance;
            bodyFadeAnim.to = 0;
        }
        // Set here rather than bound, so a body that resolves its height
        // mid-flight cannot change the duration of the run already going.
        // A re-entry too: it is undoing an exit that ran at the panel's pace.
        bodySlideAnim.duration = fromEdge || toEdge || (entering && !fresh) ? Tokens.anim.durations.expressiveDefaultSpatial : root.bodySlideDuration;
        // Kept under the slide's, so the body is always gone before the slide
        // ends rather than lingering over the list coming back.
        bodyFadeAnim.duration = Math.min(Tokens.anim.durations.expressiveDefaultEffects, Math.round(root.bodySlideDuration * 0.7));
        bodySlideAnim.from = root.bodySlide;
        bodyFadeAnim.from = root.bodyFade;
        bodySlideAnim.start();
        bodyFadeAnim.start();
    }

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

    function exitTo(targetY: real, cb: var, endHeight = 0): void {
        // Stop BEFORE storing the callback: stopping a still-running enter
        // slide fires onStopped, which must not consume (and instantly fire)
        // the exit callback.
        slideAnim.stop();
        root.stopFollow();
        root.stopExitSprings();
        slideXAnim.stop();
        // The morph folds the body back into the row off LIVE endpoints, so a
        // zoomed image would hand a magnified, off-centre picture to a landing
        // computed for the fitted one. Back to fit before the slide starts.
        root.resetZoom();
        root.exitCb = cb;
        // A browse's leaving header face is not carried home on the row: it
        // finishes within about a frame-pair, from where it is.
        root.hurrySwap();
        // Before the latch: any orphan already in flight turns for its row
        // here (see onExitingChanged), and one made by the latch starts out
        // aimed at its row.
        root.exiting = true;
        // The exit morph is aimed at the entry you are LEAVING FROM, which is
        // the one being read now. Re-latch, since a browse has almost certainly
        // moved off whatever the enter morph was aimed at. If the enter morph
        // was still in flight towards another entry, the latch hands that
        // picture to an orphan, which folds it into its own row -- see
        // latchMorph.
        root.latchMorph(root.index, false, true);
        slideAnim.from = root.slideY;
        slideAnim.to = targetY + root.rowAlignY;
        slideXAnim.from = root.slideX;
        slideXAnim.to = root.rowAlignX;
        if (root.morphIsImage || root.morphIsColour) {
            // A picture (or swatch) folding home: on the spring, header
            // included -- the picture rides the header's slot, so a header
            // overshooting by 5px carried the picture past its row too.
            root.startExitSprings(slideAnim.to);
        } else {
            root.setMorphT(0);
            slideAnim.start();
            slideXAnim.start();
        }
        root.pillReleased = false;
        root.runPill(1);
        // Where the rail ends up under the landed header, against where the
        // panel's bottom edge ends up.
        const edge = endHeight > 0 ? Math.max(0, endHeight - (root.topInset + slideAnim.to + header.implicitHeight + Tokens.spacing.small)) : -1;
        root.beginBodySlide(slideAnim.to - slideAnim.from, false, false, edge);
    }

    // The row the exit is landing on moved: the query changed under the slide
    // (ContentList.requeryExit). The header carries on from where it is to
    // where that row is NOW, every frame: `target` is a function of the live
    // list (the row's drawn position once the view has it, index math until
    // then). A fixed target measured at the keypress was wrong as soon as the
    // view settled the new list a turn later -- the re-insert moves the origin
    // and the scroll -- and the header was seen sliding the wrong way and out
    // of the panel before coming back. Same curve and duration as the slide,
    // and the same handoff when it lands; the callback is held aside across
    // the stop, which would otherwise run it (onStopped).
    //
    // The body is re-aimed with it: it hangs off the header, so a header now
    // landing higher would park the leaving text that much inside the panel,
    // over the new rows, instead of on its bottom edge (`endHeight`, the
    // panel the new list is going to have; see exitTo).
    property var followTarget: null
    property real followFrom: 0
    property real followT: 0

    function followExit(target: var, endHeight: real): void {
        if (!root.exiting)
            return;
        if (slideSpring.running) {
            // A spring is retargeted, not restarted: it turns for the row's
            // live position from where it is, at the speed it had.
            slideSpring.target = () => target() + root.rowAlignY;
        } else {
            const cb = root.exitCb;
            root.exitCb = null;
            slideAnim.stop();
            root.stopFollow();
            root.exitCb = cb;
            root.followFrom = root.slideY;
            root.followTarget = target;
            root.followT = 0;
            root.slideY = Qt.binding(() => root.followFrom + (root.followTarget() + root.rowAlignY - root.followFrom) * root.followT);
            followAnim.start();
        }
        if (!root.entryIsText || root.bodyFade <= 0)
            return;
        const edge = Math.max(0, endHeight - (root.topInset + target() + root.rowAlignY + header.implicitHeight + Tokens.spacing.small));
        if (edge <= root.bodySlide && !bodySlideAnim.running)
            return;
        bodySlideAnim.stop();
        bodySlideAnim.from = root.bodySlide;
        bodySlideAnim.to = Math.max(root.bodySlide, edge);
        bodySlideAnim.duration = Tokens.anim.durations.expressiveDefaultSpatial;
        bodySlideAnim.start();
    }

    // Back to an ordinary slideY, frozen where it is drawn.
    function stopFollow(): void {
        if (!root.followTarget)
            return;
        followAnim.stop();
        root.slideY = root.slideY;
        root.followTarget = null;
    }

    Anim {
        id: followAnim

        target: root
        property: "followT"
        from: 0
        to: 1
        onFinished: {
            root.stopFollow();
            root.finishExit();
        }
    }

    // Mid-exit reversal: stop the outbound slide wherever it is and return the
    // header to the top. The pending exit callback is discarded FIRST --
    // stopping fires onStopped, which must not consume (and run) the handoff
    // that would unmask the row under the re-opened reader.
    function reenter(): void {
        root.exitCb = null;
        slideAnim.stop();
        root.stopFollow();
        root.stopExitSprings();
        slideXAnim.stop();
        root.suppressSwap();
        root.exiting = false;
        root.beginMorph();
        slideAnim.from = root.slideY;
        slideAnim.to = 0;
        slideXAnim.from = root.slideX;
        slideXAnim.to = 0;
        root.setMorphT(1);
        slideAnim.start();
        slideXAnim.start();
        root.pillReleased = false;
        root.runPill(0);
        root.beginBodySlide(slideAnim.to - slideAnim.from, true);
    }

    // A NEW open in the reader that is already here: another row, asked for
    // while the last exit was still sliding (ContentList.enterReader). Everything
    // Component.onCompleted does, from whatever state the exit left behind.
    //
    // In place because building a reader is not free once you are deep in the
    // history -- the rail instantiates every body within three frame-heights
    // either side. Measured 30 rows down: ~85ms to build one and ~65ms to tear
    // it down, and a burst of <- / down / -> does that per keypress while the
    // keys queue up behind it: 1.0s of event-loop stall over 70 keys, single
    // stalls of 360-410ms, against 60ms with the reader kept. It froze.
    //
    // startY, index and startHeight are bindings and already say the new row.
    function reopen(): void {
        // What the leading-slot overlay is drawing right now, taken before
        // anything below moves it -- the jump and the header's teleport both
        // move its live endpoints. See latchMorph.
        const shown = root.snapMorph();
        // First, for the reason exitTo gives: stopping the slide runs it.
        root.exitCb = null;
        slideAnim.stop();
        root.stopFollow();
        root.stopExitSprings();
        slideXAnim.stop();
        root.suppressSwap();
        root.resetSwap();
        root.exiting = false;
        root.resetZoom();
        // The rail goes to the new entry AT ONCE -- this is an open, and an
        // open's motion is the header's, not a browse across the rail.
        rail.jump();
        root.slideY = root.startY + root.rowAlignY;
        root.slideX = root.rowAlignX;
        slideAnim.from = root.slideY;
        slideAnim.to = 0;
        slideXAnim.from = root.slideX;
        slideXAnim.to = 0;
        slideAnim.start();
        slideXAnim.start();
        // A new open from the row the highlight is on: the pill IS that
        // highlight again (it was drawn there a frame ago, at full tint) and
        // fades out over this slide like any open.
        root.pillReleased = false;
        root.pillTint = 1;
        root.runPill(0);
        // Rewinds morphT past its Behavior, then latches -- see latchMorph.
        root.latchMorph(root.index, true, false, shown);
        root.setMorphT(1);
        root.bodyFade = 1;
        root.beginBodySlide(-(root.startY + root.rowAlignY), true, true);
    }

    // -- the close of a picture, on a spring --
    //
    // Measured at 165Hz on a 640x360 picture folding into its 41px slot, on
    // the expressive curve the rest of the reader uses: the picture reached
    // the slot's size 227ms in, still shrinking at ~500px/s, carried on to
    // 32.6x36.6 (the curve's 1.39% overshoot, times a 599px size travel) and
    // 4.3px past the row, then crept back over the last ~220ms in single
    // whole-pixel steps (the edges were drawn on pixel boundaries). That is
    // the hard landing he felt, not the handoff -- which was already within
    // 0.002px of the row's thumbnail.
    //
    // Header, slot and picture all ride critically damped springs instead:
    // they arrive from one side with the speed decaying to nothing, the
    // picture drawn at sub-pixel positions the whole way (the overlay's
    // shader, shaders/morphpic.frag), and the handoff waits for rest. Text
    // exits keep the curve; they have no picture to fold.
    readonly property bool exitSpringsRunning: slideSpring.running || slideXSpring.running || morphSpring.running

    function startExitSprings(slideTo: real): void {
        // In px: settled below a fiftieth of a pixel, moving under 2px/s.
        slideSpring.epsilon = 0.02;
        slideSpring.velocityEpsilon = 2;
        slideXSpring.epsilon = 0.02;
        slideXSpring.velocityEpsilon = 2;
        slideSpring.target = null;
        slideSpring.to = slideTo;
        slideXSpring.to = root.rowAlignX;
        slideSpring.start(root.slideY, 0);
        slideXSpring.start(root.slideX, 0);
        // morphT is a fraction of the picture's whole size travel, so its
        // thresholds are that same fiftieth of a pixel, scaled.
        const span = Math.max(1, root.morphIsImage ? Math.max(root.morphFitW, root.morphFitH) - root.slotS : root.bodyContentW - root.slotS);
        morphSpring.epsilon = 0.02 / span;
        morphSpring.velocityEpsilon = 2 / span;
        morphSpring.to = 0;
        // An open still in flight hands over from where it is. Its curve is
        // the Behavior's (which refuses a stop() -- not a root animation), so
        // it is ended the way a disabled Behavior ends: by a write while the
        // spring has it switched off. That drops an adopted path, so the
        // path is re-snapshotted first, exactly as setMorphT does for a curve.
        const r = root.adopted && root.morphing && root.morphGoal !== 0 ? root.liveMorphRect() : null;
        morphSpring.start(root.morphT, 0);
        root.morphT = root.morphT;
        if (r)
            root.adopt(r);
        root.morphGoal = 0;
    }

    function stopExitSprings(): void {
        slideSpring.stop();
        slideSpring.target = null;
        slideXSpring.stop();
        morphSpring.stop();
    }

    function exitSpringSettled(): void {
        if (root.exitSpringsRunning)
            return;
        root.adopted = false;
        root.finishExit();
    }

    // Critically damped at 24 rad/s for all three: the picture is at 95% of
    // its travel by ~200ms, within a pixel by ~370ms, and at rest by ~550ms,
    // against the curve's 512ms that ended in the overshoot.
    Spring {
        id: slideSpring

        omega: 24
        onValueChanged: if (running) root.slideY = value
        onSettled: {
            root.slideY = value;
            root.exitSpringSettled();
        }
    }

    Spring {
        id: slideXSpring

        omega: 24
        onValueChanged: if (running) root.slideX = value
        onSettled: {
            root.slideX = value;
            root.exitSpringSettled();
        }
    }

    Spring {
        id: morphSpring

        omega: 24
        onValueChanged: if (running) root.morphT = value
        onSettled: {
            root.morphT = value;
            root.exitSpringSettled();
        }
    }

    Anim {
        id: slideAnim

        target: root
        property: "slideY"
        onStopped: root.finishExit()
    }

    // The exit's handoff back to the list, which tears this reader down --
    // and with it every orphan still folding a picture into its own row. So
    // it waits for them: the header has landed and sits exactly on its row,
    // which looks the same whether the reader is still drawing it or the row
    // is, and the orphans land on the same beat anyway (same curve, same
    // duration, started by the same keypress). See latchMorph.
    function finishExit(): void {
        if (root.orphans.length > 0 || root.exitSpringsRunning)
            return;
        const cb = root.exitCb;
        root.exitCb = null;
        if (cb)
            cb();
    }

    Anim {
        id: slideXAnim

        target: root
        property: "slideX"
    }

    // Same curve and duration as the header's slide above, so the two read as
    // one movement rather than as two things that happen to overlap.
    Anim {
        id: bodySlideAnim

        target: root
        property: "bodySlide"
    }

    // The fade is deliberately the shorter curve: on the way out it clears the
    // body before the slide has finished, which is what keeps it from being
    // drawn over the list coming back underneath.
    Anim {
        id: bodyFadeAnim

        target: root
        property: "bodyFade"
        type: Anim.DefaultEffects
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
        // Lifts off as the list's highlight and fades its tint over the slide.
        pillTint = 1;
        runPill(0);
        beginMorph();
        setMorphT(1);
        swapShown = entry;
        // to: 0, so the header's travel is the negation of where it starts.
        beginBodySlide(-(startY + rowAlignY), true, true);
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
    //
    // What it does instead, on a browse only, is a blur-replace in place -- his
    // ask, after the iOS 26 toolbar pill (ScreenRecording 11-14 20-03-42): the
    // header stays put, the old glyphs blur and fade out fast, the new ones
    // arrive already blurred and sharpen. No direction; the rail carries that.
    //
    // The real content still rebinds on the keypress frame exactly as before --
    // nothing that measures the header (implicitHeight, slotS, the title's x)
    // changes or lags. What leaves is a GHOST: a copy of the header's own items
    // holding what was on screen the frame before, at the blur and opacity it
    // was drawn with, so a step mid-transition starts from whatever is
    // displayed. Ghosts are children of the header and ride its slide.
    //
    // A held arrow is the case the old note above is about, and it is handled
    // by capping rather than by skipping: a step arriving while the last one is
    // still resolving brings the new content in at swapHeldBlur and
    // swapHeldOpacity -- light, legible -- and the full resolve only runs once
    // the steps stop. Never on open, exit, reenter() or reopen(): there the
    // header is the lifted row and its content does not change.
    //
    // The knobs, all here. Durations are the shell's effects tokens, picked
    // against the reference frame by frame (curve values computed off the
    // token beziers): the old glyphs are heavily blurred within ~33ms and gone
    // by ~70-80ms there, which is Fast (150ms; 0.61 at 33ms) on the blur and
    // Default (200ms; 0.74 at 67ms) on the fade -- blur leading the fade, so
    // the old title never just dims while still sharp. The new glyphs read
    // within ~50ms but are only crisp at ~200-250ms: Default on their fade and
    // Slow (300ms; 0.95 at 167ms) on the blur. Default for the incoming blur
    // looked sharp by 100ms, visibly faster than the reference.
    //
    // And a SWELL, his second verdict on the first build ("very subtle ... in
    // original there was some shrink and expansion"). Measured off the same
    // reference: the pill grows 130 -> 152px (+16 %) over ~7 frames, settles
    // over ~11 more and dips ~1.5 % under its rest size once before resting;
    // the glyphs that arrive are ~10-12 % oversized and shrink to size while
    // they sharpen. From its peak the reference has half the excess left at
    // 83ms and none at ~167ms. DefaultSpatial (500ms) has 46 % left at 83ms
    // and 6 % at 167ms -- the same settle -- and its one undershoot is 1.4 %
    // of the excess, 0.14 % of the size: there, but not a bounce. (Tried
    // FastSpatial first, filmed: it is spent by 100ms, while the incoming
    // glyphs are still blurred, and what is left to see is its 0.9 % dip
    // crawling back for 250ms.) So the incoming face starts at swapInScale
    // and settles to exactly 1 on the default curve, alongside the Slow
    // blur, and a leaving face swells by the same amount while it blurs out
    // (Fast spatial over its fade -- it is gone before it would settle, so
    // that is pure growth). Both scale about the
    // header's left-centre, i.e. the icon's left edge, so the title does not
    // drift sideways and nothing reaches into the left padding; what a long
    // title pushes past the right edge is cut at the reader's own right inset
    // (swapClip), never at the panel's edge.
    readonly property real swapBlurMax: 48
    // Blur of the incoming content on a single step, and of a leaving ghost at
    // the end of its fade, as fractions of swapBlurMax.
    readonly property real swapInBlur: 1
    readonly property real swapOutBlur: 1
    // Where a leaving face's blur starts on its first frame, as a fraction of
    // swapBlurMax. MultiEffect barely blurs below ~0.15, so a ghost launched
    // from a sharp face spent its first two frames only dimming, the old
    // title fully legible.
    readonly property real swapOutBlurFloor: 0.3
    readonly property real swapInOpacity: 0.3
    readonly property real swapInScale: 1.1
    readonly property real swapOutScale: 1.1
    readonly property int swapScaleDuration: Tokens.anim.durations.expressiveDefaultSpatial
    // While steps keep arriving: a light blur that still reads (~2px), and a
    // leaving face that is gone within about one key repeat (~33ms), so at
    // most one ghost is ever under the title. That fade is the one number here
    // that is not a token -- nothing in the shell is short enough, and at
    // 200ms a held arrow stacked four or five half-opaque titles on top of
    // each other (filmed). A third of expressiveFastEffects.
    readonly property real swapHeldBlur: 0.1
    readonly property real swapHeldOpacity: 0.85
    // The scale under a hold: a step arriving mid-transition never raises
    // the live face again -- it carries on settling from where it is, so a
    // held arrow does not pump on every repeat -- and a leaving face swells
    // only this much over its short fade.
    readonly property real swapHeldOutScale: 1.02
    readonly property int swapHeldFadeDuration: Math.round(Tokens.anim.durations.expressiveFastEffects / 3)
    readonly property int swapOutBlurDuration: Tokens.anim.durations.expressiveFastEffects
    readonly property int swapOutFadeDuration: Tokens.anim.durations.expressiveDefaultEffects
    readonly property int swapInBlurDuration: Tokens.anim.durations.expressiveSlowEffects
    readonly property int swapInFadeDuration: Tokens.anim.durations.expressiveDefaultEffects

    // The live content's state; at rest 0 and 1, where it renders with no
    // layer at all.
    property real swapBlur: 0
    property real swapOpacity: 1
    // At rest exactly 1: a visual transform only, so nothing that measures
    // the header (implicitHeight, slotS, the title's x) sees it.
    property real swapScale: 1
    // The entry the header last drew, so a change that is not a change (the
    // rail's entries array replaced around the same entry) does nothing.
    property var swapShown: null
    property bool swapSuppressed: false

    function metaFor(e: var, b: var): string {
        // Counts come from the body, which owns the decode. Falls back to the
        // row's own descriptor until it has one -- which is also what a cold
        // entry beyond the prefetch window shows.
        const c = b?.charCount ?? 0;
        if (c > 0) {
            const l = b?.lineCount ?? 1;
            return `${c} ${c === 1 ? "character" : "characters"} · ${l} ${l === 1 ? "line" : "lines"}`;
        }
        return e?.desc ?? "";
    }

    onEntryChanged: {
        const prev = root.swapShown;
        const e = root.entry;
        if (e === prev)
            return;
        root.swapShown = e;
        if (!prev || !e || root.exiting || root.swapSuppressed)
            return;
        root.swapHeader(prev);
    }

    function swapHeader(prev: var): void {
        const burst = swapIn.running;
        // What was on screen: prev's content at the live state. Its body is a
        // neighbour on the rail now, which is where its counts come from.
        const pb = rail.itemAtIndex(root.entries.indexOf(prev));
        let g = null;
        for (let i = 0; i < ghosts.count; i++) {
            const c = ghosts.itemAt(i);
            if (c && !c.busy) {
                g = c;
                break;
            }
            if (c && (!g || c.opacity < g.opacity))
                g = c;
        }
        // A burst hurries every face already leaving, from where it is.
        if (burst)
            for (let i = 0; i < ghosts.count; i++) {
                const c = ghosts.itemAt(i);
                if (c && c.busy && c !== g)
                    c.hurry(root.swapHeldFadeDuration);
            }
        // From what is on screen -- blur, opacity and scale -- except that a
        // single step's ghost starts no softer than swapOutBlurFloor (see
        // there). A burst's stays light, which is the cap.
        const blur0 = burst ? root.swapBlur : Math.max(root.swapBlur, root.swapOutBlurFloor);
        const swell = (burst ? root.swapHeldOutScale : root.swapOutScale) - 1;
        if (g)
            g.launch(Clipboard.iconOf(prev), prev?.name ?? "", root.metaFor(prev, pb), blur0, root.swapOpacity, burst ? root.swapHeldBlur : root.swapOutBlur, burst ? root.swapHeldFadeDuration : root.swapOutFadeDuration, burst ? root.swapHeldFadeDuration : root.swapOutBlurDuration, root.swapScale, root.swapScale + swell);
        swapIn.stop();
        root.swapBlur = burst ? Math.min(root.swapHeldBlur, root.swapInBlur) : root.swapInBlur;
        root.swapOpacity = burst ? root.swapHeldOpacity : root.swapInOpacity;
        swapIn.start();
        // The swell: a single step arrives oversized; a step inside a
        // transition leaves the scale where it is and only restarts its
        // settle from there, so a held arrow never pumps it.
        swapScaleAnim.stop();
        if (!burst)
            root.swapScale = root.swapInScale;
        swapScaleAnim.start();
    }

    // reopen(): a new open, so the header is a lifted row again and whatever a
    // browse left in flight has no business on it.
    function resetSwap(): void {
        swapIn.stop();
        swapScaleAnim.stop();
        root.swapBlur = 0;
        root.swapOpacity = 1;
        root.swapScale = 1;
        for (let i = 0; i < ghosts.count; i++)
            ghosts.itemAt(i)?.clear();
    }

    function hurrySwap(): void {
        for (let i = 0; i < ghosts.count; i++) {
            const c = ghosts.itemAt(i);
            if (c?.busy)
                c.hurry(root.swapHeldFadeDuration);
        }
    }

    // reenter()/reopen() may move the index in the same turn (ContentList's
    // re-entry browses to the highlighted row right after); that is part of
    // the re-entry, not a browse.
    function suppressSwap(): void {
        root.swapSuppressed = true;
        swapUnsuppress.restart();
    }

    Timer {
        id: swapUnsuppress

        interval: 0
        onTriggered: root.swapSuppressed = false
    }

    ParallelAnimation {
        id: swapIn

        Anim {
            target: root
            property: "swapBlur"
            to: 0
            type: Anim.SlowEffects
            duration: root.swapInBlurDuration
        }
        Anim {
            target: root
            property: "swapOpacity"
            to: 1
            type: Anim.DefaultEffects
            duration: root.swapInFadeDuration
        }
    }

    // Apart from swapIn, whose `running` is what says "burst": the settle is
    // longer than the blur, and folding it in would widen that window.
    Anim {
        id: swapScaleAnim

        target: root
        property: "swapScale"
        to: 1
        type: Anim.DefaultSpatial
        duration: root.swapScaleDuration
    }

    // A copy of the header's face holding what was on screen, leaving.
    component HeaderGhost: Item {
        id: ghost

        property string icon: ""
        property string title: ""
        property string meta: ""
        property real blur: 0
        readonly property bool busy: gOut.running

        function launch(icon: string, title: string, meta: string, blur: real, op: real, blurTo: real, fadeDur: int, blurDur: int, scale0: real, scaleTo: real): void {
            gOut.stop();
            ghost.icon = icon;
            ghost.title = title;
            ghost.meta = meta;
            ghost.blur = blur;
            ghost.opacity = op;
            ghost.scale = scale0;
            gBlur.to = blurTo;
            gScale.to = scaleTo;
            gFade.duration = fadeDur;
            gBlur.duration = blurDur;
            gScale.duration = fadeDur;
            gOut.start();
        }

        // Finish sooner, from wherever the fade has got to (no `from` on the
        // animations, so a restart starts at the current values).
        function hurry(dur: int): void {
            if (gFade.duration <= dur)
                return;
            gOut.stop();
            gFade.duration = dur;
            gBlur.duration = dur;
            gScale.duration = dur;
            gOut.start();
        }

        function clear(): void {
            gOut.stop();
            ghost.opacity = 0;
            ghost.blur = 0;
            ghost.scale = 1;
        }

        // Geometry comes from the Repeater (the header's box inside
        // swapClip). Swells about its left-centre, as the live face does.
        transformOrigin: Item.Left
        opacity: 0
        visible: ghost.opacity > 0
        // Always on, so the effect is built before a ghost is first needed:
        // switched on in the frame the fade starts, that first frame came out
        // dimmed but still sharp. Costs nothing while idle -- an invisible
        // item's layer is never rendered.
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: ghost.blur
            blurMax: root.swapBlurMax
        }

        ParallelAnimation {
            id: gOut

            // Durations set per launch -- see launch() and hurry().
            Anim {
                id: gFade

                target: ghost
                property: "opacity"
                to: 0
                type: Anim.DefaultEffects
            }
            Anim {
                id: gBlur

                target: ghost
                property: "blur"
                type: Anim.FastEffects
            }
            // The swell, over the fade: the face is gone before it would
            // settle, so it is spent as pure growth.
            Anim {
                id: gScale

                target: ghost
                property: "scale"
                type: Anim.FastSpatial
            }
        }

        MaterialIcon {
            id: gIcon

            anchors.verticalCenter: parent.verticalCenter
            text: ghost.icon
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        Item {
            anchors.left: gIcon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: gTitle.implicitHeight + gMeta.implicitHeight

            StyledText {
                id: gTitle

                anchors.left: parent.left
                anchors.right: parent.right
                text: ghost.title
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: gMeta

                anchors.left: parent.left
                anchors.top: gTitle.bottom
                text: ghost.meta
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
            }
        }
    }

    // -- the pill: the row's selection highlight, travelling with it --
    //
    // His ask ("making the row move as a pill not just a text"). The lifted
    // row used to be bare glyphs, so in flight its title was drawn straight
    // over the text of every row it crossed, both legible at once, while the
    // list's own highlight sat parked and empty on the landing row like a hole
    // waiting to be filled (his screenshot of an exit mid-flight).
    //
    // So the highlight goes with the row. Geometry is exactly AppList's
    // highlight for that row -- the list's own x and width, itemHeight, the
    // same radius -- placed off the header's own slide (slidePos and slideX,
    // less the row-content offsets the header is aligned with), which is the
    // row's top-left at both ends and follows exitScroll like the header. At
    // the row end it is the list highlight, pixel for pixel.
    //
    // Fill is OPAQUE: the panel's surface with the highlight's tint
    // (onSurface at 0.08, which is all the list highlight is) composited on
    // top, so nothing it crosses shows through. The translucent highlight
    // itself would have kept the text-through-text.
    //
    // The tint rides pillTint, which runs on the slide's own curve and
    // duration and is restarted from wherever it is with every slide: it fades
    // out over an open (on the top row too, where the header barely travels)
    // and in over an exit, and turns round on a reenter. At rest in the reader
    // the pill is not drawn at all.
    //
    // ContentList hides the list's own highlight while the pill stands for
    // it (highlightMasked), and the handoff back is the exit's own: the reader
    // is torn down when the slide stops (`running`, never the eased value),
    // in the same turn the mask comes off.
    property real pillTint: 0
    // An Up/Down during the exit moves the selection off this row: the list's
    // highlight comes back and glides to the new row, and the pill keeps its
    // opaque backing but gives its tint up. See ContentList.listStep.
    property bool pillReleased: false

    function runPill(to: real): void {
        pillAnim.stop();
        pillAnim.from = root.pillTint;
        pillAnim.to = to;
        pillAnim.start();
    }

    function releasePill(): void {
        if (root.pillReleased)
            return;
        root.pillReleased = true;
        root.runPill(0);
    }

    // Default spatial, like slideAnim: the same curve and duration, started in
    // the same statements.
    Anim {
        id: pillAnim

        target: root
        property: "pillTint"
    }

    // Declared before the header and the rail, so it is under both, under the
    // morph overlays and the orphans, and over the list rows (the reader's
    // Loader is above the list's).
    //
    // A plain Rectangle, not a StyledRect: that one eases every colour change
    // (CAnim), and the tint here is already being driven frame by frame.
    Rectangle {
        id: pill

        x: (root.listView?.x ?? 0) + root.slideX - root.rowAlignX
        y: (root.listView?.y ?? 0) + root.slidePos - root.rowAlignY
        width: root.listView?.width ?? root.width
        height: Tokens.sizes.launcher.itemHeight
        radius: Tokens.rounding.large
        visible: root.exiting || pillAnim.running || root.pillTint > 0
        // With the header (declared next, so the title draws over it), over
        // the rail and over any orphaned morph (orphanLayer). An orphan is a
        // leftover from another entry going home; the row being closed is one
        // solid object and the leftover passes BEHIND it. Left at z 0 the
        // orphan covered the pill and only the title showed above the picture:
        // bare text over an image, which is what the pill exists to prevent
        // (his frame, 2026-11-15). The row's own morph (morphClip) stays above.
        z: 1
        color: {
            const s = Colours.tPalette.m3surface;
            return Qt.tint(Qt.rgba(s.r, s.g, s.b, 1), Qt.alpha(Colours.palette.m3onSurface, 0.08 * root.clamp01(root.pillTint)));
        }
    }

    Item {
        id: header

        // Over the rail and over any orphaned morph (orphanLayer), under the
        // live morph overlay (morphClip), which lifts off this header's own
        // icon slot. See orphanLayer for why the orphans go under the title.
        z: 1

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

        // Where a swelling face is cut: at the reader's own edge on the right
        // (header's right margin), so the end of a long title scaled 1.1x
        // about the left runs into the inset and never past the panel. Clear
        // of the blur's spread above and below. At rest nothing reaches it,
        // so the scissor changes no pixel.
        Item {
            id: swapClip

            readonly property real padX: Tokens.padding.large
            readonly property real padY: root.swapBlurMax

            x: -padX
            y: -padY
            width: header.width + padX * 2
            height: header.height + padY * 2
            clip: true

            // The live face. Exactly the header's box, so every anchor below lays
            // out as it did when these were the header's own children. The layer
            // exists only while a blur is in flight: at rest the text renders
            // straight, with no FBO in the way of its crispness.
            Item {
                id: headerLive

                x: swapClip.padX
                y: swapClip.padY
                width: header.width
                height: header.height
                opacity: root.swapOpacity
                // The swell, about the left-centre: the icon's left edge stays
                // put. A transform, so implicitHeight, slotS and the title's x
                // never see it.
                scale: root.swapScale
                transformOrigin: Item.Left
                layer.enabled: root.swapBlur > 0
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: root.swapBlur
                    blurMax: root.swapBlurMax
                }

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
                        text: root.metaFor(root.entry, root.body)
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }
                }
            }

            // Leaving faces, newest last. Four is enough for a held arrow: each
            // one is gone within swapOutFadeDuration, and a fifth step inside that
            // window reuses the faintest.
            Repeater {
                id: ghosts

                model: 4

                HeaderGhost {
                    x: swapClip.padX
                    y: swapClip.padY
                    width: header.width
                    height: header.height
                }
            }
        }
    }

    // -- the rail --
    //
    // Seven entries in a vertical column. The column scrolls. The frame resizes
    // to whatever is under it. That is the whole model.
    ListView {
        id: rail

        // See beginBodySlide: the fade is what now says "only the header stays
        // drawn on the way out", and it says it for image and colour entries
        // by going straight to zero, exactly as `!root.exiting` used to.
        visible: root.bodyFade > 0
        opacity: root.bodyFade

        // Plus the exit scroll, which the header SUBTRACTS (see slidePos) to
        // stay on a row the list is scrolling away with. The rail hangs off the
        // header, so it would follow -- and it is leaving for the panel's edge,
        // which does not scroll. Close the last visible row and step down: the
        // list scrolls a stride, and the body parked just past the edge was
        // carried a stride back up into view, at full strength, over the row
        // below its own.
        transform: Translate {
            y: root.bodySlide + root.exitScroll
        }

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
        //
        // Not while the reader is leaving, and that is a freeze, not a nicety.
        // Nothing browses during an exit, so there is no travel to build ahead
        // of -- but when the exit lands ContentList clears readerEntry, the
        // index falls to 0, and the view drops contentY to the top while
        // `target` still says where the entry WAS. Deep in the history that is
        // a lead of the whole distance scrolled: measured 71,752px, 87,294px
        // and 101,534px at entries 358, 416 and 470, and the view obediently
        // built every body in it -- 402, 454 and 556 of them -- in the tick
        // before the reader was destroyed. 870-960ms of frozen shell at the end
        // of every close, growing with how far down you had read.
        //
        // Nor across a jump, for the same reason from the other side: the view
        // is repositioned first and `target` caught up a statement later, and
        // in between the two disagree by the whole distance. A reader opened at
        // entry 470 read a lead of -101,392px and built 71 bodies above itself
        // (214ms) before the next line took the margin away again.
        property bool jumping: false
        readonly property real lead: root.exiting || rail.jumping ? 0 : rail.target - rail.contentY
        //
        // The base budget is GROWN INTO over the open rather than paid on it. A
        // pixel budget is a count that depends on what is around: among
        // one-liners three frame-heights is ~25 bodies either side, ~3.3ms
        // each, all built in the statement that creates the reader -- measured
        // 113-175ms of frozen shell per open, 300+ entries down where the
        // history is mostly short commands. Starting from two rows' worth still
        // builds both immediate neighbours (they begin where the entry ends),
        // so the first step after opening has its delegate; the rest arrive a
        // few per frame while the header is still flying.
        property real marginGrowth: 0
        readonly property real marginBase: (Tokens.sizes.launcher.itemHeight + Tokens.spacing.small) * 2
        readonly property real margin: rail.marginBase + (3 * root.maxHeight - rail.marginBase) * rail.marginGrowth

        NumberAnimation {
            id: marginRamp

            target: rail
            property: "marginGrowth"
            from: 0
            to: 1
            duration: Tokens.anim.durations.expressiveDefaultSpatial
        }

        displayMarginBeginning: rail.margin + Math.max(0, -rail.lead)
        displayMarginEnd: rail.margin + Math.max(0, rail.lead)

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

        // Nothing else would bring the first entry into existence: with no
        // currentIndex the view only builds what is around contentY, which
        // starts at 0. Instant on purpose -- the open is the header's morph,
        // not a rail move. positionViewAtIndex writes contentY from C++, past
        // the Behavior, which for once is the point.
        function jump(): void {
            rail.jumping = true;
            rail.positionViewAtIndex(root.index, ListView.Beginning);
            rail.target = rail.contentY;
            rail.pin();
            rail.jumping = false;
        }

        Component.onCompleted: {
            rail.jump();
            marginRamp.start();
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
            //
            // And held while an orphaned morph of this entry is still in the
            // air on its way HERE (see latchMorph): the orphan is the picture,
            // and this body is where it lands. One folding home to its row is
            // not coming here, so it holds nothing.
            readonly property bool orphanTarget: root.bodyOrphanEntries.indexOf(bodyDelegate.modelData) >= 0
            handedOff: (!bodyDelegate.morphTarget || (root.morphT >= 1 && !root.morphing)) && !bodyDelegate.orphanTarget

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
    // Where morphT is HEADED. The Behavior's own `to` is internal, and the
    // adopted path below has to know which end it is travelling to. Every
    // write to morphT goes through setMorphT so the two cannot disagree.
    property real morphGoal: 0

    // Off for the one write that rewinds the morph -- see reopen().
    property bool morphRewind: false

    Behavior on morphT {
        // Off while the exit spring drives it (startExitSprings).
        enabled: !root.morphRewind && !morphSpring.running

        Anim {
            id: morphAnim

            // An adopted start (see adopt) is spent once the run that began
            // from it is over. Both ends of the adopted path are the plain
            // path's own endpoints, so dropping it at rest changes nothing on
            // screen.
            onRunningChanged: {
                if (!running)
                    root.adopted = false;
            }
        }
    }

    function setMorphT(v: real): void {
        // Turning an ADOPTED morph round: its path ran from a snapshot, not
        // from the slot, so the plain path at the same t is somewhere else.
        // Re-snapshot what is on screen and run from there instead. A plain
        // morph needs nothing -- it is the same expression in both directions,
        // which is why reversing it mid-flight was always continuous.
        //
        // Only while the run is actually going. Straight after reopen()'s
        // rewind the snapshot was taken AT the current t with nothing run yet,
        // so it already is the start; re-reading it there measured the
        // degenerate goal == t0 state and handed the slot back as the "live"
        // rect -- an orphan adopted by a reopen jumped onto the slot.
        if (root.adopted && root.morphing && v !== root.morphGoal) {
            const r = root.liveMorphRect();
            if (r)
                root.adopt(r);
        }
        root.morphGoal = v;
        root.morphT = v;
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
    // The entry itself, which -- unlike morphBody -- exists from the first
    // frame. The delegates register a moment after this reader is built, and
    // the opening morph's first frame cannot wait for them: that is the frame
    // that has to draw the row's own thumbnail.
    readonly property var morphEntry: root.entries[root.morphIndex] ?? null
    // The exact url ClipItem assigns to the row's thumbnail -- `file://` plus
    // the same `/tmp/...` path -- so with the same sourceSize, fillMode and
    // caching the morph's first frame is a synchronous pixmap-cache hit on the
    // picture the row was drawing.
    readonly property string morphSrc: root.morphEntry?.isImage && root.morphEntry.entryId ? `file:///tmp/caelestia-clip-preview-${root.morphEntry.entryId}.png` : ""

    // `shown`: a snapMorph() taken earlier in the same turn, for a caller that
    // turned the channel round in between (ContentList's re-entry browse) --
    // the orphan must leave going the way the picture was going on screen.
    function beginMorph(shown = null): void {
        root.latchMorph(root.index, false, false, shown);
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
    readonly property bool morphing: morphAnim.running || morphSpring.running

    // The source slot, shared by both morphs: the square the ROW draws, which is
    // the icon's 1em advance (see headerIcon and ClipItem). implicitWidth, not
    // implicitHeight -- the line box is 1.2em and a morph starting from it would
    // begin 8px larger than the thumbnail it is supposed to be lifting off.
    //
    // This used to fix the thumbnail sourceSize too, at 2x this, back when
    // ClipItem decoded at the same 2x. ClipItem moved to the flat
    // Clipboard.thumbSize and this did not, so the two copies asked for
    // different sizes -- a different pixmap-cache key -- and the morph's first
    // frames drew an empty rect where the row's picture had just been. Both
    // now read Clipboard.thumbSize itself, so they cannot drift apart again.
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
    //
    // The KIND is asked of the entry until the body has registered, but only
    // for the entry being read: that is the opening morph's first frame. A
    // latched target that has lost its body is one the rail carried far
    // away, and drawing it with no body to measure would snap it back to the
    // header -- so that stays hidden, as it always was.
    readonly property bool morphIsImage: root.morphBody ? root.morphBody.isImage : (root.morphIndex === root.index && (root.morphEntry?.isImage ?? false))
    readonly property bool morphIsColour: root.morphBody ? root.morphBody.isColour : (root.morphIndex === root.index && !!root.morphEntry && Clipboard.colourEntryOf(root.morphEntry).length > 0)
    readonly property color morphColour: root.morphBody ? root.morphBody.colourValue : (root.morphIsColour ? Clipboard.colourEntryOf(root.morphEntry) : "transparent")
    readonly property real bodyContentW: root.morphBody?.contentW ?? (root.minWidth - Tokens.padding.large * 2)
    // Where that content box sits inside the frame -- non-zero exactly while the
    // frame is a different width from the entry, which is the whole of a move.
    // See ClipBody.contentX; reading it rather than restating it is what keeps
    // the landing exact.
    readonly property real bodyContentX: root.morphBody?.contentX ?? 0
    readonly property real bodyImgBoxW: root.morphBody?.imgBoxW ?? 0
    readonly property real bodyImgFitH: root.morphBody?.imgFitH ?? 0
    readonly property string bodyImgSrc: root.morphBody?.imgSrc ?? ""
    // ClipBody's own formula when there is no body yet, so the decode the
    // overlay asks for on the first frame is the one the body asks for next.
    readonly property int bodyImgDecodeW: root.morphBody?.imgDecodeW ?? (root.morphEntry?.imgDims ? Clipboard.readerDecodeWidth(root.morphEntry.imgDims) : Clipboard.readerMaxWidth)
    readonly property bool bodyImgReady: root.morphBody?.imgReady ?? false
    readonly property real bodySwatchHeight: root.morphBody?.swatchHeight ?? 0
    // The row's thumbnail url, from the entry. Through the body's imgSrc once
    // there is a body, because that is the one ClipBody bounces when it has to
    // repair a missing file -- an Image does not retry a url that failed, and
    // the entry's url never changes.
    readonly property string morphThumbSrc: root.morphBody ? root.bodyImgSrc : root.morphSrc

    // The rect the body's image actually paints -- the same imgBoxW the body
    // Image is sized to, so the handoff at t=1 is exact. Only horizontal
    // centring can occur: the box is the image's own shape, so there is no
    // letterbox.
    readonly property real morphFitW: root.bodyImgBoxW > 0 ? root.bodyImgBoxW : root.bodyContentW
    readonly property real morphFitH: root.bodyImgBoxW > 0 ? root.bodyImgFitH : root.bodyContentW
    readonly property real imgDstX: Tokens.padding.large + root.bodyContentX + (root.bodyContentW - root.morphFitW) / 2
    readonly property real swatchDstX: Tokens.padding.large + root.bodyContentX

    // Cross-fade of the full-size copy over the thumbnail -- see MorphPicture.
    // Effects-fast, not spatial: the geometry is already animating underneath
    // and a slow fade would just read as the picture arriving late.
    property real morphFullOpacity: root.bodyImgReady ? 1 : 0
    // Off for the one write that hands an orphan's opacity back -- latchMorph.
    property bool fullOpacityJump: false

    Behavior on morphFullOpacity {
        enabled: !root.fullOpacityJump

        Anim {
            type: Anim.FastEffects
        }
    }

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

    function clamp01(v: real): real {
        return Math.max(0, Math.min(1, v));
    }

    // The radius over a run from a snapshot of radius `from`: rounding only
    // ever happens over the slot end's last roundEnd of the travel, exactly as
    // on the plain path, so a picture that was square when it was snapshotted
    // stays square until it is nearly home.
    function radiusAlong(from: real, toSlot: bool, u: real): real {
        if (toSlot)
            return from + (Tokens.rounding.small - from) * root.clamp01((u - (1 - root.roundEnd)) / root.roundEnd);
        return from * root.clamp01(1 - u / root.roundEnd);
    }

    readonly property bool morphRounded: root.adopted ? root.morphRadius > 0 : root.morphT < root.roundEnd
    // Clamped at both ends: morphT overshoots past 1, and the exit can drive it
    // to exactly 0 where the row's own radius takes over.
    readonly property real morphRadius: root.adopted ? root.radiusAlong(root.adoptR, !root.adoptToBody, root.adoptU) : Tokens.rounding.small * Math.max(0, Math.min(1, 1 - root.morphT / root.roundEnd))

    // -- interrupted morphs: nothing that is in the air disappears --
    //
    // The overlay above has ONE channel -- morphT plus the latched morphIndex --
    // and an exit needs that channel for the entry being read. So a morph
    // still flying towards another entry when the exit starts used to lose it
    // outright: open an image, step down onto text before the picture had
    // landed, press <- and the half-grown picture vanished in one frame (filmed
    // at 165fps, frame 435), because the exit re-latched the channel onto the
    // text entry and the picture's own body was hidden in the same frame.
    //
    // The rule now, in latchMorph, for every re-latch:
    //
    //   - what is on screen leaves on its own. If the channel was drawing a
    //     picture or swatch still in flight towards a different entry, that
    //     exact rect -- position, size, radius, the top cut -- becomes an
    //     ORPHAN: an independent object that animates from where it is to
    //     where it was GOING. A picture that was closing goes on to its own
    //     row's thumbnail slot, glued to the row as the list cascades and
    //     scrolls (the list stays laid out under an open reader too, so that
    //     holds whatever the reader does next); one that was opening goes on
    //     to its own body on the rail -- unless an exit made it, below.
    //   - what arrives starts from where it is drawn. Latching onto an entry
    //     that has an orphan in the air adopts the orphan's rect as the
    //     channel's start, so it turns round from there instead of starting
    //     again at the slot. Latching onto the entry being read mid-flight
    //     (an exit) adopts the rect its body is painted in.
    //
    // Only two things turn an object round once it is in the air: the reader
    // opened again on ITS entry (the adoption above), and an exit while it
    // was still opening (onExitingChanged, spawnOrphan). Nothing the reader
    // does for ANOTHER entry may: an orphan used to take its direction from
    // the reader's current state, so an open on the next row turned every
    // picture still folding home round into a body nobody was reading, and a
    // fast Right/Left/Down burst stacked them -- filmed, five rows "opening"
    // at once (recording_20261114_23-37-02, frames 350-380 and 500-545).
    //
    // Same curve and duration as everything else (Anim's default), so an
    // orphan made by an exit lands on the header's beat.
    property bool adopted: false
    property real adoptT0: 0
    property real adoptX: 0
    property real adoptY: 0
    property real adoptW: 0
    property real adoptH: 0
    property real adoptClip: 0
    property real adoptR: 0
    readonly property bool adoptToBody: root.morphGoal >= 0.5
    // 0 at the snapshot, 1 at the goal, overshoot included -- the same curve
    // value the plain path uses, renormalised to the stretch that is left.
    readonly property real adoptU: {
        const d = root.morphGoal - root.adoptT0;
        return Math.abs(d) < 1e-6 ? 1 : (root.morphT - root.adoptT0) / d;
    }

    function adopt(r: var): void {
        root.adoptX = r.x;
        root.adoptY = r.y;
        root.adoptW = r.w;
        root.adoptH = r.h;
        root.adoptClip = r.clip;
        root.adoptR = r.r;
        root.adoptT0 = root.morphT;
        root.adopted = true;
    }

    // What the overlay is drawing this instant, in this item's coordinates.
    function liveMorphRect(): var {
        if (root.morphIsImage)
            return {
                x: morphImg.x,
                y: morphImg.y + morphClip.y,
                w: morphImg.width,
                h: morphImg.height,
                clip: morphClip.y,
                r: root.morphRounded ? root.morphRadius : 0
            };
        if (root.morphIsColour)
            return {
                x: morphSwatch.x,
                y: morphSwatch.y + morphClip.y,
                w: morphSwatch.width,
                h: morphSwatch.height,
                clip: morphClip.y,
                r: Tokens.rounding.small
            };
        return null;
    }

    // The rect the morph target's body paints, for a latch onto an entry whose
    // body is on screen.
    function bodyRestRect(): var {
        if (root.morphIsImage)
            return {
                x: root.imgDstX,
                y: root.morphBodyTop,
                w: root.morphFitW,
                h: root.morphFitH,
                clip: rail.y - 1,
                r: 0
            };
        if (root.morphIsColour)
            return {
                x: root.swatchDstX,
                y: root.morphBodyTop,
                w: root.bodyContentW,
                h: root.bodySwatchHeight,
                clip: rail.y - 1,
                r: Tokens.rounding.small
            };
        return null;
    }

    // Everything an orphan needs to carry on drawing exactly what the overlay
    // draws now. Taken separately from the latch because reopen() has to take
    // it before the rail jump and the header teleport move its endpoints.
    function snapMorph(): var {
        return {
            index: root.morphIndex,
            entry: root.morphEntry,
            inFlight: root.morphInFlight,
            // Which way it was going -- the orphan keeps that (spawnOrphan).
            goal: root.morphGoal,
            rect: root.morphInFlight ? root.liveMorphRect() : null,
            isColour: !root.morphIsImage,
            colour: root.morphColour,
            thumbSrc: root.morphThumbSrc,
            fullSrc: root.bodyImgSrc,
            decodeW: root.bodyImgDecodeW,
            fullOpacity: root.morphFullOpacity
        };
    }

    // Re-aim the morph channel at entry `n`. `rewind` drops morphT to 0 past
    // its Behavior (reopen: a new open); `fromBody` lets an in-flight latch
    // start from the target's painted body (exitTo).
    function latchMorph(n: int, rewind: bool, fromBody: bool, shown = null): void {
        const s = shown ?? root.snapMorph();
        const target = root.entries[n] ?? null;

        // An orphan of the entry being latched comes back into the channel.
        let back = null;
        for (const o of root.orphans) {
            if (o.entry === target) {
                back = o.liveRect();
                root.dropOrphan(o);
                break;
            }
        }

        if (n !== s.index && s.inFlight && s.rect && s.entry)
            root.spawnOrphan(s);

        if (rewind) {
            root.adopted = false;
            root.morphRewind = true;
            root.morphGoal = 0;
            root.morphT = 0;
            root.morphRewind = false;
        }

        root.morphIndex = n;

        if (back) {
            root.adopt(back);
            // And its full-size copy at the strength the orphan was drawing
            // it, faded back up from there rather than popped.
            root.fullOpacityJump = true;
            root.morphFullOpacity = back.fade;
            root.fullOpacityJump = false;
            root.morphFullOpacity = Qt.binding(() => root.bodyImgReady ? 1 : 0);
        } else if (n !== s.index) {
            const r = fromBody && s.inFlight && root.bodyFade > 0 && root.morphBody ? root.bodyRestRect() : null;
            if (r)
                root.adopt(r);
            else
                root.adopted = false;
        }
    }

    // -- orphans --
    property var orphans: []
    readonly property var orphanEntries: root.orphans.map(o => o.entry)
    readonly property var bodyOrphanEntries: root.orphans.filter(o => !o.toRow).map(o => o.entry)

    function spawnOrphan(s: var): void {
        const o = orphanComp.createObject(orphanLayer, {
            entry: s.entry,
            isColour: s.isColour,
            colour: s.colour,
            thumbSrc: s.thumbSrc,
            fullSrc: s.fullSrc,
            decodeW: s.decodeW,
            fullOpacity: s.fullOpacity,
            sX: s.rect.x,
            sY: s.rect.y,
            sW: s.rect.w,
            sH: s.rect.h,
            sClip: s.rect.clip,
            sR: s.rect.r,
            // Where it was going, from the snapshot -- not from what the
            // reader is doing now, which is the latch's business. reopen()
            // and reenter() take the snapshot of a picture that was folding
            // home, and that is where it carries on to. An exit turns an
            // opening one round, as it turns the channel.
            toRow: root.exiting || s.goal < 0.5
        });
        if (!o)
            return;
        root.orphans = root.orphans.concat([o]);
        o.launch();
    }

    // Hidden in the same turn, not just destroyed: destroy() is deferred, and
    // one more frame of it under whatever took over would be the picture drawn
    // twice.
    function dropOrphan(o: var): void {
        o.visible = false;
        root.orphans = root.orphans.filter(x => x !== o);
        o.destroy();
    }

    function landOrphan(o: var): void {
        root.dropOrphan(o);
        if (root.exiting && !slideAnim.running && !followAnim.running && !root.exitSpringsRunning)
            root.finishExit();
    }

    // An exit turns every orphan still opening round for its row, from where
    // it is -- the same thing the exit does to the channel. The reverse never
    // happens: an orphan folding home keeps folding home when the reader comes
    // back (reenter, reopen), and lands on its row's slot under the reader.
    // The one way back into a body is to be adopted by an open of its own
    // entry (latchMorph).
    onExitingChanged: {
        if (!root.exiting)
            return;
        for (const o of root.orphans)
            if (!o.toRow)
                o.turnHome();
    }

    // Where a row's leading slot is drawn, in this item's coordinates (the
    // reader fills the same box the list does). The live delegate when there is
    // one -- its visualY carries the close cascade and the gap hold, so the
    // orphan lands on the thumbnail where it is DRAWN, pixel for pixel -- and
    // index math for a row the view has not built, which is the header's own
    // landing formula.
    function rowSlotOf(e: var): var {
        const l = root.listView;
        if (!l || !e)
            return null;
        // Read for the dependency: a row built or recycled moves results or
        // contentY with it, which is what re-asks itemAtIndex.
        l.count;
        const k = l.results.indexOf(e);
        const it = k >= 0 ? l.itemAtIndex(k) : null;
        if (it && it.modelData === e && it.leadY !== undefined)
            return {
                x: l.x + it.x + it.leadX,
                y: l.y + it.visualY - l.contentY + it.leadY
            };
        const j = l.fullResults.indexOf(e);
        if (j < 0)
            return null;
        return {
            x: l.x + Tokens.padding.large + root.rowAlignX,
            y: l.y + l.originY + j * (Tokens.sizes.launcher.itemHeight + l.spacing) - l.contentY + (Tokens.sizes.launcher.itemHeight - root.slotS) / 2
        };
    }

    // One picture or swatch that has left the channel and is on its way home.
    // Geometry is a lerp from the snapshot it was made from (s*) to a LIVE
    // target (t*), driven by its own `o` on the shell's default curve. A
    // retarget re-snapshots and starts again from 0, so it never jumps.
    component Orphan: Item {
        id: orphan

        property var entry: null
        property bool isColour: false
        property color colour: "transparent"
        property string thumbSrc: ""
        property string fullSrc: ""
        property int decodeW: 0
        property real fullOpacity: 1

        property real sX: 0
        property real sY: 0
        property real sW: 0
        property real sH: 0
        property real sClip: 0
        property real sR: 0
        // Latched per run: home is the row while the list is coming back,
        // the body while the reader is open.
        property bool toRow: true
        property real o: 0

        Behavior on fullOpacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        // -- targets --
        readonly property var body: {
            if (orphan.toRow)
                return null;
            rail.contentY;
            root.index;
            const i = root.entries.indexOf(orphan.entry);
            return i >= 0 ? rail.itemAtIndex(i) : null;
        }
        readonly property var row: orphan.toRow ? root.rowSlotOf(orphan.entry) : null
        // The rail's own top edge as drawn: it hangs off the header and is
        // translated by the body slide and the exit scroll (see rail).
        readonly property real railTop: rail.y + root.bodySlide + root.exitScroll
        readonly property real bodyW: orphan.body ? (orphan.isColour ? orphan.body.contentW : (orphan.body.imgBoxW > 0 ? orphan.body.imgBoxW : orphan.body.contentW)) : orphan.sW
        readonly property real bodyH: orphan.body ? (orphan.isColour ? orphan.body.swatchHeight : (orphan.body.imgBoxW > 0 ? orphan.body.imgFitH : orphan.body.contentW)) : orphan.sH

        readonly property real tX: orphan.toRow ? (orphan.row ? orphan.row.x : orphan.sX) : (orphan.body ? Tokens.padding.large + orphan.body.contentX + (orphan.isColour ? 0 : (orphan.body.contentW - orphan.bodyW) / 2) : orphan.sX)
        // No body to land on (the rail dropped it): up past the rail's top
        // edge, under the header, where the cut below hides it -- the same
        // place the plain morph's ride-out goes.
        readonly property real tY: orphan.toRow ? (orphan.row ? orphan.row.y : orphan.sY) : (orphan.body ? orphan.railTop - (rail.contentY - orphan.body.y) - orphan.body.scrollY : orphan.railTop - orphan.sH - 2)
        readonly property real tW: orphan.toRow ? (orphan.row ? root.slotS : orphan.sW) : orphan.bodyW
        readonly property real tH: orphan.toRow ? (orphan.row ? root.slotS : orphan.sH) : orphan.bodyH

        readonly property real cX: orphan.sX + (orphan.tX - orphan.sX) * orphan.o
        readonly property real cY: orphan.sY + (orphan.tY - orphan.sY) * orphan.o
        // Folding home, the size stops at the slot: the curve's overshoot
        // would take it a few px under the thumbnail and grow it back, and a
        // picture on its way home only ever shrinks. Position keeps the
        // overshoot.
        readonly property bool shrinkHome: orphan.toRow && orphan.sW >= orphan.tW && orphan.sH >= orphan.tH
        readonly property real cW: orphan.shrinkHome ? Math.max(orphan.tW, orphan.sW + (orphan.tW - orphan.sW) * orphan.o) : orphan.sW + (orphan.tW - orphan.sW) * orphan.o
        readonly property real cH: orphan.shrinkHome ? Math.max(orphan.tH, orphan.sH + (orphan.tH - orphan.sH) * orphan.o) : orphan.sH + (orphan.tH - orphan.sH) * orphan.o
        // The top cut, carried over from the overlay it was made from (which
        // may have been passing under the header) and eased out to nothing by
        // the landing on a row -- never ahead of the picture's own top, the
        // overshoot included. Towards a body it eases onto the rail's top edge,
        // the cut every rail picture has.
        readonly property real tClip: orphan.toRow ? Math.min(orphan.tY, orphan.cY) - 1 : orphan.railTop - 1
        readonly property real cClip: orphan.sClip + (orphan.tClip - orphan.sClip) * root.clamp01(orphan.o)
        readonly property real cR: orphan.isColour ? Tokens.rounding.small : root.radiusAlong(orphan.sR, orphan.toRow, orphan.o)
        // Landing on a row, the full-size copy gives way to the thumbnail over
        // the same last stretch the corners round in, on the same curve value.
        // The row draws only the 96px thumbnail -- the very pixmap mThumb
        // holds -- and the full-size copy minified to 41px samples differently
        // (filmed: the picture visibly re-sampled on the handoff frame). With
        // this the last frame of the orphan is the row's own picture, so the
        // handoff has nothing left to change.
        //
        // From sFade, the value it had when this run began, so a retarget
        // turns it round instead of popping it: towards a row it only ever
        // falls, towards a body it climbs back over the travel.
        property real sFade: 1
        readonly property real rowFade: orphan.toRow ? Math.min(orphan.sFade, root.clamp01((1 - orphan.o) / root.roundEnd)) : orphan.sFade + (1 - orphan.sFade) * root.clamp01(orphan.o)

        function liveRect(): var {
            return {
                x: orphan.cX,
                y: orphan.cY,
                w: orphan.cW,
                h: orphan.cH,
                clip: orphan.cClip,
                r: orphan.cR,
                fade: orphan.fullOpacity * orphan.rowFade
            };
        }

        function launch(): void {
            oAnim.stop();
            orphan.o = 0;
            oAnim.start();
        }

        // Turn round for the row, from where it is. One way only -- see
        // onExitingChanged.
        function turnHome(): void {
            const r = orphan.liveRect();
            orphan.sFade = orphan.rowFade;
            orphan.sX = r.x;
            orphan.sY = r.y;
            orphan.sW = r.w;
            orphan.sH = r.h;
            orphan.sClip = r.clip;
            orphan.sR = r.r;
            orphan.toRow = true;
            orphan.launch();
        }

        Component.onCompleted: orphan.fullOpacity = Qt.binding(() => oPicRound.fullReady || oPicSquare.fullReady ? 1 : 0)

        x: 0
        y: 0
        width: root.width
        height: root.height

        Anim {
            id: oAnim

            target: orphan
            property: "o"
            from: 0
            to: 1
            onFinished: root.landOrphan(orphan)
        }

        Item {
            id: oClip

            clip: true
            width: root.width
            y: orphan.cClip
            height: Math.max(root.height - y, orphan.cY + orphan.cH - y)

            Item {
                x: orphan.cX
                y: orphan.cY - oClip.y
                width: orphan.cW
                height: orphan.cH
                visible: !orphan.isColour

                StyledClippingRect {
                    anchors.fill: parent
                    visible: orphan.cR > 0
                    radius: orphan.cR
                    color: Colours.palette.m3surfaceContainerHigh

                    MorphPicture {
                        id: oPicRound

                        anchors.fill: parent
                        thumbSrc: orphan.thumbSrc
                        fullSrc: orphan.fullSrc
                        decodeW: orphan.decodeW
                        fullOpacity: orphan.fullOpacity * orphan.rowFade
                    }
                }

                Item {
                    anchors.fill: parent
                    visible: orphan.cR <= 0
                    clip: true

                    StyledRect {
                        anchors.fill: parent
                        color: Colours.palette.m3surfaceContainerHigh
                    }

                    MorphPicture {
                        id: oPicSquare

                        anchors.fill: parent
                        thumbSrc: orphan.thumbSrc
                        fullSrc: orphan.fullSrc
                        decodeW: orphan.decodeW
                        fullOpacity: orphan.fullOpacity * orphan.rowFade
                    }
                }
            }

            StyledRect {
                visible: orphan.isColour
                x: orphan.cX
                y: orphan.cY - oClip.y
                width: orphan.cW
                height: orphan.cH
                radius: Tokens.rounding.small
                color: orphan.colour
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
            }
        }
    }

    Component {
        id: orphanComp

        Orphan {}
    }

    // The two copies of the picture the overlay draws, defined once and
    // instantiated in both clip paths (and in every orphan). Same url, same
    // sourceSize, same fillMode, caching on at both ends, so the instantiations
    // resolve to ONE texture and cost no second decode -- the same sharing that
    // makes the row's thumbnail a synchronous cache hit here in the first place.
    component MorphPicture: Item {
        id: pic

        property string thumbSrc: ""
        property string fullSrc: ""
        property int decodeW: 0
        property real fullOpacity: 0
        readonly property bool fullReady: mImg.status === Image.Ready

        // The picture the row was already showing, scaled up. Blurry at full
        // size, but it is the right image at the right aspect, and mImg fades
        // over it. Underneath sits the container's surface colour, which only
        // shows for entries whose row thumbnail has not decoded either.
        //
        // Same url and same sourceSize as ClipItem's `thumb` -- the pair that
        // forms the pixmap cache key -- so this is drawn on the morph's first
        // frame from the pixmap the row was drawing.
        Image {
            id: mThumb

            anchors.fill: parent
            source: pic.thumbSrc
            fillMode: Image.PreserveAspectCrop
            cache: !Clipboard.noCache
            asynchronous: true
            sourceSize.width: Clipboard.thumbSize
            sourceSize.height: Clipboard.thumbSize
        }

        Image {
            id: mImg

            anchors.fill: parent
            source: pic.fullSrc
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
            sourceSize.width: pic.decodeW
            // Cross-fades over the thumbnail rather than popping; the fade is
            // the owner's (morphFullOpacity, or the orphan's own).
            opacity: pic.fullOpacity
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

        // Over the header, as it always was by declaration order -- the
        // header is raised for the orphans, so this has to say it outright.
        z: 1
        clip: true
        width: root.width
        y: root.adopted ? root.adoptClip + ((root.adoptToBody ? rail.y - 1 : Math.min(rail.y, root.slotY) - 1) - root.adoptClip) * root.clamp01(root.adoptU) : Math.min(rail.y, root.slotY + (rail.y - root.slotY) * Math.min(1, root.morphT)) - 1
        height: Math.max(root.height - y, morphImg.y + morphImg.height, morphSwatch.y + morphSwatch.height)

        Item {
            id: morphImg

            // Geometry only -- the drawing is the shader below. (It used to
            // be two children, rounded at the row end and scissor-exact at the
            // body end; see root.roundEnd.)

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
            //
            // Adopted (see latchMorph), the same lerp runs from the snapshot it
            // was handed to the end it is heading for, on the same curve value.
            readonly property real sizeT: root.morphT

            visible: root.morphIsImage && root.morphInFlight
            x: root.adopted ? root.adoptX + ((root.adoptToBody ? root.imgDstX : root.slotX) - root.adoptX) * root.adoptU : root.slotX + (root.imgDstX - root.slotX) * root.morphT
            // Relative to morphClip, which is what carries the cut. The absolute
            // expression is unchanged.
            y: (root.adopted ? root.adoptY + ((root.adoptToBody ? root.morphBodyTop : root.slotY) - root.adoptY) * root.adoptU : root.slotY + (root.morphBodyTop - root.slotY) * root.morphT) - morphClip.y
            width: root.adopted ? root.adoptW + ((root.adoptToBody ? root.morphFitW : root.slotS) - root.adoptW) * root.adoptU : root.slotS + (root.morphFitW - root.slotS) * sizeT
            height: root.adopted ? root.adoptH + ((root.adoptToBody ? root.morphFitH : root.slotS) - root.adoptH) * root.adoptU : root.slotS + (root.morphFitH - root.slotS) * sizeT

            // Drawn by one shader at the box's exact fractional geometry,
            // rounded end and square end alike: the corner radius goes to 0
            // exactly where the old square path took over, and the edges are
            // antialiased instead of landing on pixel boundaries. Both of the
            // old paths (a ClippingRectangle, a scissor clip) drew the box
            // edges on whole pixels -- measured: an edge 0.56px into a column
            // filled all of it -- so the last pixels of a landing moved in
            // whole-pixel steps. At rest on the row (whole-pixel box, radius
            // rounding.small) it draws the thumbnail's own pixels.
            Item {
                anchors.fill: parent

                // Texture providers only; the shader draws them.
                Image {
                    id: shThumb

                    visible: false
                    source: root.morphThumbSrc
                    // As MorphPicture and ClipItem have it: with sourceSize
                    // it decides the decode (cropped fills 96px on the short
                    // side; stretched would fit 96 on the long one -- a
                    // smaller, softer texture than the row's), and the decode
                    // is the pixmap-cache key the first frame has to hit.
                    fillMode: Image.PreserveAspectCrop
                    cache: !Clipboard.noCache
                    asynchronous: true
                    sourceSize.width: Clipboard.thumbSize
                    sourceSize.height: Clipboard.thumbSize
                }

                Image {
                    id: shFull

                    visible: false
                    source: root.bodyImgSrc
                    fillMode: Image.PreserveAspectCrop
                    cache: !Clipboard.noCache
                    asynchronous: true
                    // See MorphPicture: the reduction to ~41px needs the mips.
                    mipmap: true
                    sourceSize.width: root.bodyImgDecodeW
                }

                ShaderEffect {
                    // Image.PreserveAspectCrop: the box shows all of one axis
                    // of the texture and a centred fraction of the other.
                    function crop(tw: real, th: real): size {
                        const bw = Math.max(1, morphImg.width);
                        const bh = Math.max(1, morphImg.height);
                        if (tw <= 0 || th <= 0)
                            return Qt.size(1, 1);
                        const s = Math.max(bw / tw, bh / th);
                        return Qt.size(bw / (tw * s), bh / (th * s));
                    }

                    readonly property var thumb: shThumb
                    readonly property var full: shFull
                    readonly property size itemSize: Qt.size(width, height)
                    readonly property rect box: Qt.rect(2, 2, morphImg.width, morphImg.height)
                    readonly property real radius: root.morphRounded ? root.morphRadius : 0
                    readonly property real thumbOpacity: shThumb.status === Image.Ready ? 1 : 0
                    // Near the row the full decode gives way to the row's own
                    // thumbnail, over the stretch the corners round in -- the
                    // same rule as an orphan's rowFade. Mipmapped down to 41px
                    // the full decode is visibly softer than the thumbnail the
                    // row draws (filmed: the texture changed on the handoff
                    // frame); this way the last frames are the row's pixels.
                    readonly property real fullOpacity: shFull.status === Image.Ready ? root.morphFullOpacity * (root.adopted ? 1 : root.clamp01(root.morphT / root.roundEnd)) : 0
                    readonly property color bg: Colours.palette.m3surfaceContainerHigh
                    readonly property size thumbCrop: crop(shThumb.implicitWidth, shThumb.implicitHeight)
                    readonly property size fullCrop: crop(shFull.implicitWidth, shFull.implicitHeight)

                    x: -2
                    y: -2
                    width: morphImg.width + 4
                    height: morphImg.height + 4
                    fragmentShader: Qt.resolvedUrl("shaders/morphpic.frag.qsb")
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
            x: root.adopted ? root.adoptX + ((root.adoptToBody ? root.swatchDstX : root.slotX) - root.adoptX) * root.adoptU : root.slotX + (Tokens.padding.large + root.bodyContentX - root.slotX) * root.morphT
            // Relative to morphClip, which is what carries the cut. The absolute
            // expression is unchanged.
            y: (root.adopted ? root.adoptY + ((root.adoptToBody ? root.morphBodyTop : root.slotY) - root.adoptY) * root.adoptU : root.slotY + (root.morphBodyTop - root.slotY) * root.morphT) - morphClip.y
            width: root.adopted ? root.adoptW + ((root.adoptToBody ? root.bodyContentW : root.slotS) - root.adoptW) * root.adoptU : root.slotS + (root.bodyContentW - root.slotS) * root.morphT
            height: root.adopted ? root.adoptH + ((root.adoptToBody ? root.bodySwatchHeight : root.slotS) - root.adoptH) * root.adoptU : root.slotS + (root.bodySwatchHeight - root.slotS) * root.morphT
            radius: Tokens.rounding.small
            color: root.morphColour
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }
    }

    // Orphans: over the rail, UNDER the header and its pill.
    //
    // An orphan made by an exit and the header it was interrupted by are
    // flying to different rows, and usually they have to cross: the header
    // comes down from the top to the row being read, the picture goes to its
    // own row, which is the one next to it. Drawn over the header, the picture
    // swept across the title for most of the slide -- filmed, the title was
    // under it from the second frame after <- to the landing, which is the
    // same thing morphClip's top cut exists to stop. Under it, the title stays
    // legible and the picture passes behind it the way rail content does.
    //
    // Over the rail, because that is where the overlay it was made from was
    // drawn: the exit from a text entry slides the body out at full strength,
    // and the picture must not drop behind that text on the frame it orphans.
    Item {
        id: orphanLayer

        anchors.fill: parent
    }
}
