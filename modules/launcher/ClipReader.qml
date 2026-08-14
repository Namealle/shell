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
    readonly property var body: rail.currentItem

    readonly property int maxHeight: Clipboard.readerMaxHeight
    readonly property int minWidth: Tokens.sizes.launcher.itemWidth

    readonly property bool isImage: root.entry?.isImage ?? false
    readonly property string colour: root.entry?.colour ?? ""
    readonly property bool isColour: root.colour.length > 0
    readonly property color colourValue: root.isColour ? root.colour : "transparent"

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
    // list (padding.large vs padding.medium horizontally; top padding vs row
    // centring vertically). The slide targets the row CONTENT's exact position
    // so the landing handoff is pixel-true, not "close then snap".
    readonly property real rowAlignY: (Tokens.sizes.launcher.itemHeight - header.implicitHeight) / 2 - Tokens.padding.large
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
    readonly property real minHeight: header.implicitHeight + Tokens.padding.large * 2
    implicitHeight: Math.max(root.minHeight, header.implicitHeight + (root.body?.implicitHeight ?? 0) + Tokens.padding.large * 2 + Tokens.spacing.small)

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
        anchors.topMargin: Tokens.padding.large + root.slidePos
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
            text: root.entry?.icon ?? "content_paste"
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
        anchors.bottomMargin: Tokens.padding.large

        // The frame. Both entries in flight have their own size and the frame is
        // a third size on its way between them, so whatever hangs outside is cut
        // here -- exactly what the old body slide was already being cropped by.
        clip: true

        model: root.entries
        currentIndex: root.index
        // Programmatic only. That also settles the nesting: the wheel and the
        // keys reach each body's own inner Flickable without contest.
        interactive: false
        spacing: Tokens.spacing.medium

        // The preload, expressed as a pixel budget rather than a count, so it
        // self-scales: three max-height entries either side, and many more when
        // they are short.
        cacheBuffer: 3 * root.maxHeight

        // NOT padding -- nothing is drawn here, the rail never rests in it, and
        // `interactive: false` means it cannot be flicked into. It exists to put
        // Flickable's own bounds out of reach of the binding below.
        //
        // contentY == lastItem.y sits exactly on maxYExtent, and the frame is
        // ANIMATING towards the last entry's height for the whole move -- so for
        // most of it maxYExtent is short and returnToBounds() clamps. Measured:
        // contentY parked at 1672 against a target of 2222, which is
        // contentHeight minus the height of the entry being LEFT. The clamp is
        // an imperative write, so the binding is not restored; it only
        // re-evaluates when currentItem.y next changes, and it does not change
        // again. Top margin for the mirror image: the spatial curve overshoots
        // ~21% of its travel, which drives contentY negative on the way to entry
        // 0, past minYExtent.
        //
        // The Behavior happens to mask both -- it rewrites contentY every frame,
        // so a clamped frame is simply overwritten by the next one. That holds
        // only while the animation outlasts the frame's resize, which is not a
        // thing to depend on. The margins also PRESERVE the overshoot rather
        // than flattening it against the bounds.
        topMargin: root.maxHeight
        bottomMargin: root.maxHeight

        // The rail's position, and the whole mechanism: pin the current entry to
        // the top of the frame and let the Behavior carry the travel.
        //
        // StrictlyEnforceRange was the obvious alternative and is strictly
        // worse: it hands the motion to ListView's velocity-based move, which
        // loses a race it cannot win, because the frame height is animating
        // underneath and the target keeps moving. Measured 236 against 784 and
        // 523 against 886 -- sampled well after both animations should have
        // finished, so that is not lag -- and it overshoots the wrong way on a
        // reversal.
        // Written, NOT bound.
        //
        // `contentY: currentItem.y` is the obvious form and it closes a loop
        // with ListView's own layout: contentY decides which delegates exist,
        // instantiating one changes contentHeight and the y of everything after
        // it, and currentItem.y is exactly what the binding reads. Qt catches it
        // -- "Binding loop detected for property contentY" -- and BREAKS the
        // binding, which leaves the rail parked wherever it was and the reader
        // showing the wrong entry. (The probes missed this: their delegates were
        // fixed-height and all within cacheBuffer from the first frame, so
        // nothing was ever created mid-move.)
        //
        // Driving it from the two signals that actually mean "the current entry
        // moved" is the same value with no cycle, and the Behavior still
        // animates the result.
        function pin(): void {
            const it = rail.currentItem;
            if (it)
                rail.contentY = it.y;
        }

        // The index changed, so a different delegate is current.
        onCurrentItemChanged: rail.pin()
        Component.onCompleted: rail.pin()

        // The current entry itself moved without the index changing -- which is
        // what happens when a neighbour ABOVE it finishes decoding and grows.
        // Without this, a prefetch landing would slide the entry you are reading
        // out from under you.
        Connections {
            target: rail.currentItem
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
            // Only the entry being read. Finding inside a neighbour has nothing
            // to scroll to, and it would cost a lowercased copy of every entry
            // on the rail per keystroke.
            findTerm: bodyDelegate.active ? root.findTerm : ""
            // The leading-slot morph is aimed at the entry being entered and at
            // nothing else, so every neighbour draws its own image/swatch
            // immediately.
            handedOff: bodyDelegate.active ? (root.morphT >= 1 && !root.morphing) : true
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
    readonly property real slotY: Tokens.padding.large + root.slidePos + (header.implicitHeight - root.slotS) / 2
    // Top of the body's content in root coordinates -- where both morphs land.
    // The rail's own scroll is not in this: the entry being morphed to is pinned
    // to the top of the frame, so the only offset that matters is how far that
    // entry is scrolled WITHIN itself.
    readonly property real bodyTop: Tokens.padding.large + root.slidePos + header.implicitHeight + Tokens.spacing.small - (root.body?.scrollY ?? 0)

    // Geometry of the body being morphed to, read off the live ClipBody rather
    // than recomputed here -- so the handoff at t=1 is exact by construction
    // instead of by two expressions agreeing.
    readonly property real bodyContentW: root.body?.contentW ?? (root.minWidth - Tokens.padding.large * 2)
    readonly property real bodyImgBoxW: root.body?.imgBoxW ?? 0
    readonly property real bodyImgFitH: root.body?.imgFitH ?? 0
    readonly property string bodyImgSrc: root.body?.imgSrc ?? ""
    readonly property int bodyImgDecodeW: root.body?.imgDecodeW ?? Clipboard.readerMaxWidth
    readonly property bool bodyImgReady: root.body?.imgReady ?? false
    readonly property real bodySwatchHeight: root.body?.swatchHeight ?? 0

    Item {
        id: morphImg

        // A plain scissor clip, NOT a StyledClippingRect. That type does its
        // rounded clipping by rendering the content into a ShaderEffectSource
        // and sampling the result, and a whole extra texture round-trip costs
        // real detail: measured against the body Image at identical geometry,
        // the picture carried 7% less high-frequency energy inside the
        // ClippingRectangle than outside it, so the handoff at t=1 read as the
        // image suddenly sharpening. Scissor clipping is exact -- with it the
        // two paths measure 0.992 of each other, i.e. the same picture.
        //
        // The cost is that the corners no longer round during the morph (the
        // backing rect below still does, for entries whose thumbnail has not
        // decoded). An 8px radius on a 41px box for the first frames is a
        // cheaper thing to lose than a visible snap on a 968px one.
        clip: true

        // The rect the body's image actually paints -- the same imgBoxW the body
        // Image is sized to, so the handoff at t=1 is exact. Only horizontal
        // centring can occur: the box is the image's own shape, so there is no
        // letterbox.
        readonly property real fitW: root.bodyImgBoxW > 0 ? root.bodyImgBoxW : root.bodyContentW
        readonly property real fitH: root.bodyImgBoxW > 0 ? root.bodyImgFitH : root.bodyContentW
        readonly property real dstX: Tokens.padding.large + (root.bodyContentW - fitW) / 2

        // POSITION rides the raw curve, including its 1.39% overshoot -- that is
        // the bounce, and it is shared with the header, the window and every
        // other spatial move in the shell.
        //
        // SIZE deliberately does not. The texture is decoded at exactly fitW, so
        // any overshoot past 1 asks the image to be drawn larger than it has
        // pixels for: a magnification, soft for the whole tail of the animation,
        // resolving in one frame the instant the curve settles. Sizing the
        // texture for the peak instead only moves that softness onto the resting
        // image, which is worse. Clamping here means the morph only ever
        // minifies -- the direction with real pixels behind it -- and the last
        // frame of the morph is pixel-identical to the body image it hands off
        // to. The 13px of size bounce this gives up is the cheapest part of the
        // overshoot; the travel still carries it.
        readonly property real sizeT: Math.min(1, root.morphT)

        visible: root.isImage && (root.morphing || root.morphT < 1)
        x: root.slotX + (dstX - root.slotX) * root.morphT
        y: root.slotY + (root.bodyTop - root.slotY) * root.morphT
        width: root.slotS + (fitW - root.slotS) * sizeT
        height: root.slotS + (fitH - root.slotS) * sizeT

        StyledRect {
            anchors.fill: parent
            // Clamped: morphT passes 1 on the overshoot, which would otherwise
            // ask for a negative radius.
            radius: Tokens.rounding.small * Math.max(0, 1 - root.morphT)
            color: Colours.palette.m3surfaceContainerHigh
        }

        // The picture the row was already showing, scaled up. Same url and same
        // sourceSize as ClipItem's `thumb` with caching on at both ends, so
        // this is a synchronous QQuickPixmapCache hit and the morph has real
        // content from its first frame. Blurry at full size, but it is the
        // right image at the right aspect, and mImg fades over it. Underneath
        // sits the rect's surface colour, which now only shows for entries
        // whose row thumbnail has not decoded yet either.
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

    // The colour swatch's morph. Full body width at t=1, so the only endpoint
    // that differs from the slot is the size -- and the radius stays put, since
    // both the row's swatch and the body's use rounding.small. A plain rect,
    // not a clipping one: there is no child to clip, and a Rectangle composites
    // a semi-transparent colour without going through a shader.
    StyledRect {
        id: morphSwatch

        visible: root.isColour && (root.morphing || root.morphT < 1)
        x: root.slotX + (Tokens.padding.large - root.slotX) * root.morphT
        y: root.slotY + (root.bodyTop - root.slotY) * root.morphT
        width: root.slotS + (root.bodyContentW - root.slotS) * root.morphT
        height: root.slotS + (root.bodySwatchHeight - root.slotS) * root.morphT
        radius: Tokens.rounding.small
        color: root.colourValue
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
    }
}
