import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.modules.launcher.services
import qs.services

// Delegate for a clipboard-history entry (the `;` launcher mode). A fixed-height
// single-line row, exactly like the other launcher pickers. Left slot is a
// decoded thumbnail for image entries, a swatch for colour entries, otherwise the
// content-aware Material icon from Clipboard.iconFor(); then title + description.
// Full content (real newlines, selectable) lives in the reader -- press `→`.
Item {
    id: root

    required property var modelData
    required property var list
    // For the entrance stagger below -- the view injects it.
    required property int index

    readonly property bool isImage: root.modelData?.isImage ?? false
    readonly property string swatchColour: root.isImage ? "" : Clipboard.colourEntryOf(root.modelData)
    readonly property bool isColour: root.swatchColour.length > 0
    readonly property string imgCache: root.isImage ? `/tmp/caelestia-clip-preview-${root.modelData.entryId}.png` : ""

    // Re-point the thumbnail whenever the delegate is recycled onto a different
    // image entry.
    //
    // Assigned STRAIGHT to the file, not after waiting for `decoder`. The file
    // is normally already on disk -- Clipboard.preloadDecode() writes the whole
    // visible set when the launcher opens -- and its pixmap is normally already
    // in QQuickPixmapCache, so this resolves synchronously and the row paints
    // with no gap at all. Routing it through the Process meant every entry into
    // the picker blanked each thumbnail and left it empty for a process spawn,
    // just to run `test -s` on a file that was already there: a visible flicker
    // on `;`, bought for nothing. The Process is now only a repair path, below.
    //
    // The empty assignment still happens, in the same turn, so a recycled
    // delegate cannot show the PREVIOUS entry's picture while the new one
    // resolves. Same turn matters: nothing renders between the two statements,
    // so on the normal cached path no blank frame is ever drawn.
    readonly property string decodeKey: root.isImage ? (root.modelData?.raw ?? "") : ""
    onDecodeKeyChanged: {
        decoder.running = false;
        thumb.source = "";
        if (root.decodeKey) {
            thumb.source = `file://${root.imgCache}`;
            // Hold the full-size copy too, so `→` on this row is instant. The
            // pixmaps live in the launcher's Wrapper, which outlives this
            // delegate; this only registers interest.
            Clipboard.retain(root.modelData);
        }
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight

    // -- entrance for a row the filter brought in without moving it --
    //
    // A narrowing filter fills the viewport from BELOW THE FOLD, and the view
    // builds those rows straight at their final position: no add to fade, no
    // displacement to slide, nothing to watch. Measured on the real history,
    // ";e" -> ";eg" emits no transitions at all and ";fe" -> ";fec" emits seven
    // that travel zero distance, which looks identical.
    //
    // Being BUILT is the exact signal. A row that survived the filter is not
    // recreated -- it keeps whatever slide the view gave it and never doubles
    // up -- so this can only ever fire for a row that genuinely arrived without
    // motion. That is the whole reason it lives here and not on the list: a
    // list-level offset shifts everything, including the rows already in place
    // and the ones mid-slide, which reads as a glitch rather than as movement.
    //
    // Staggered by row on purpose. Seven rows arriving together on one curve
    // read as a single block sliding; a few tens of milliseconds between
    // neighbours is what makes a list look like it is settling into place. The
    // app list gets that quality for free, because its rows each move a
    // different distance and so never arrive in step.
    transform: [
        Translate {
            id: entrance
        },
        Translate {
            id: gapHold
        }
    ]

    // `fade` only for rows that are genuinely NEW. A row coming back from
    // behind the reader was never gone, and hiding it to bring it back is what
    // made the list flash black: every row dropped to nothing at once and then
    // waited out its own stagger before it began to return, so for the length
    // of the cascade there was simply nothing on screen. Those rows stagger
    // their POSITION only and let the list's own fade carry them in.
    // 0..1, scaling both the offset and the stagger, so a weak entrance is
    // genuinely a smaller version of a strong one rather than a shorter one.
    property real entranceStrength: 1

    // Where the row is drawn, as opposed to where the view has laid it out: the
    // reader's header has to lift off the former.
    readonly property real visualY: root.y + entrance.y + gapHold.y

    // Stamped by AppList.settleTo for every row the view hands a transition to,
    // so a jump carrying an older stamp than the current change is a placement
    // the view made without one -- see AppList.repairAt.
    property double transitionedAt: 0
    property real lastY: 0
    property bool laidOut: false

    // The view moved this row without animating it: carry the travel on the
    // row's own Translate instead, which is the same answer the filter entrance
    // gives and the same curve the rows the view DID animate are running.
    //
    // Handled here rather than a frame later on a timer because the write is
    // synchronous with the view's own: setting the offset inside this handler
    // means the frame that renders the new y already carries it, so there is no
    // moment where the row is drawn at the placed position. A frame late would
    // just be the teleport followed by a slide back.
    //
    // ADDED to whatever offset is there rather than replacing it: the
    // reader-close cascade below fires in the same turn, so overwriting its
    // offset would trade this jump for a smaller one instead of removing it.
    onYChanged: {
        const prev = root.lastY;
        root.lastY = root.y;
        // A row built into its slot has no previous position to be moved from.
        if (!root.laidOut) {
            root.laidOut = true;
            return;
        }
        let d = root.y - prev;
        // The re-insert this row was held for -- see gapHold. Spent against the
        // view's own travel as it happens, so the two cancel to the pixel on
        // every frame instead of as closely as two animations can be started
        // together, and whether the view animates the row or places it.
        if (gapHold.y > 0 && d > 0) {
            const used = Math.min(gapHold.y, d);
            gapHold.y -= used;
            d -= used;
        }
        const l = root.list;
        if (!l)
            return;
        const at = l.repairAt;
        // Only inside the change that stamped it, and only if this row is not
        // one the view took care of.
        if (at <= 0 || Date.now() - at > 40 || root.transitionedAt >= at)
            return;
        if (Math.abs(d) < 1)
            return;
        // Rows below the fold move a stride on every lift and no one sees it.
        // Against BOTH heights: implicitHeight is the list's resting extent,
        // but the panel is still animating down from the reader's size, so for
        // part of the exit the window is taller than the list and a row past
        // implicitHeight is genuinely on screen. The reverse holds mid-morph.
        const view = Math.max(l.height, l.implicitHeight);
        if (root.y + root.implicitHeight < l.contentY || root.y > l.contentY + view)
            return;
        entranceAnim.stop();
        // No stagger: this is not an entrance, it is one row's own interrupted
        // travel resumed, and it has to stay in step with the rows the view is
        // animating on the same curve.
        root.entranceStrength = 0;
        entrance.y -= d;
        entranceAnim.start();
    }

    function playEntrance(fade: bool, strength: real): void {
        // STOPPED first, and that is the whole of a row that went blank and
        // stayed blank. start() on an already-running animation does nothing,
        // so a second trigger arriving in the last frames of a run re-zeroed
        // the opacity below and then had nothing left to raise it again --
        // the row kept its slot in the layout and drew nothing in it.
        entranceAnim.stop();
        // Set before starting, so the row is already displaced through its
        // stagger instead of popping down when the pause ends.
        root.entranceStrength = strength;
        entrance.y = (Tokens.sizes.launcher.itemHeight + Tokens.spacing.small) * strength;
        if (fade)
            content.opacity = 0;
        entranceAnim.start();
    }

    Component.onCompleted: {
        // Only rows built as part of a filter change, not rows built by
        // scrolling. The list stamps the time whenever its results change for a
        // reason worth animating (its own mode switch and the reader's lift are
        // excluded there).
        if (!root.list || Date.now() - root.list.filterChangedAt > 150)
            return;
        root.playEntrance(true, 1);
    }

    // The same cascade when the reader closes. These rows
    // are not rebuilt -- they were behind the reader all along -- so they have
    // to be told. The row being read is excluded: it is still masked, and the
    // header morph is already carrying it back onto its slot.
    //
    // A row BELOW the gap is owed one more thing. While its neighbour is being
    // read it rests a stride high, on the slot it inherited, and the re-insert
    // that parts it back down is staged 140ms into the exit. Left to that, the
    // cascade and the parting are the same stride in opposite directions a
    // beat apart: measured on the second row after a close from the first, it
    // began on its own slot (the cascade's offset happens to equal the stride),
    // was carried 58px up over the returning row, and was pushed back down when
    // the re-insert landed -- the "nudge up and then down". It only shows on a
    // close that barely resizes the panel; anywhere else the panel's own travel
    // buries it.
    //
    // So the row is held on the slot it is coming BACK to, and the hold is
    // spent against the view's travel in onYChanged. What is left on screen is
    // the cascade alone, identical to the rows above the gap.
    Connections {
        function onReaderGapIndexChanged(): void {
            // A re-entry before the re-insert landed: the row stays a stride
            // high after all, under a reader that is covering it again.
            if (root.list.readerGapIndex < 0 && gapHold.y !== 0)
                holdRelease.start();
        }

        function onReaderClosedAtChanged(): void {
            if (root.list?.maskedEntry === root.modelData)
                return;
            const gap = root.list?.readerGapIndex ?? -1;
            if (gap >= 0 && root.index >= gap) {
                holdRelease.stop();
                gapHold.y = Tokens.sizes.launcher.itemHeight + Tokens.spacing.small;
            }
            const strength = root.list?.readerCascade ?? 0;
            // Nothing worth moving for -- a reader that opened and shut in the
            // same gesture leaves this at essentially zero.
            if (strength < 0.02)
                return;
            root.playEntrance(false, strength);
        }

        target: root.list
    }

    Anim {
        id: holdRelease

        target: gapHold
        property: "y"
        to: 0
    }

    SequentialAnimation {
        id: entranceAnim

        PauseAnimation {
            // Capped: past a screenful the delay stops meaning anything, and
            // the list only ever enters from the top anyway.
            // Floored: a recycled delegate can report index -1, and a negative
            // duration is a QML warning plus a silently dropped pause.
            duration: Math.max(0, Math.min(root.index, 6) * 24 * root.entranceStrength)
        }

        ParallelAnimation {
            Anim {
                target: entrance
                property: "y"
                to: 0
                type: Anim.DefaultSpatial
            }
            // On the content, NOT the row: the list's add transition animates
            // the row's own opacity for genuinely new entries, and two
            // animations on one property fight.
            Anim {
                target: content
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    // While this entry is lifted into the reader (or its header is still sliding
    // back), the reader's header IS this row -- rendering it here too would show
    // the same object twice.
    visible: root.list?.maskedEntry !== root.modelData

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.modelData?.onClicked(root.list)
    }

    // Repair path only: reached when the file was NOT already on disk, which
    // after preloadDecode() means a row scrolled to beyond the preloaded set.
    // Decode it, then bounce the source -- an Image will not retry a url that
    // failed to load, so re-assigning the same string is a no-op and it has to
    // be cleared first.
    Process {
        id: decoder

        command: ["sh", "-c", "test -s \"$2\" || (printf '%s' \"$1\" | cliphist decode > \"$2\")", "dec", root.modelData?.raw ?? "", root.imgCache]
        onExited: {
            if (!root.imgCache)
                return;
            thumb.source = "";
            thumb.source = `file://${root.imgCache}`;
        }
    }

    Item {
        id: content

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        MaterialIcon {
            id: icon

            visible: !root.isImage && !root.isColour
            anchors.verticalCenter: parent.verticalCenter
            // Natural width, and that width IS the row's leading slot -- the
            // swatch and thumbnail below size themselves from it. Safe to build
            // the column on because Material Symbols is a uniform-advance font:
            // numberOfHMetrics is 1, so every one of its 6301 glyphs advances
            // exactly 1em (41.7px here) and no icon can shift its own row.
            //
            // Deliberately NOT the line height, which is 1.2em / 50px. That
            // extra 0.2em is leading -- vertical space for stacking lines of
            // text, of which there are none in an icon slot. 1em is the box the
            // glyphs are actually drawn to.
            text: Clipboard.iconOf(root.modelData)
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        // Colour entries paint the actual colour as their swatch instead of an icon.
        StyledRect {
            id: swatch

            visible: root.isColour
            anchors.verticalCenter: parent.verticalCenter
            // Square on the icon's ADVANCE, so the leading slot is one width for
            // every entry type and the titles line up down the list. Both
            // dimensions read implicitWidth on purpose -- implicitHeight is the
            // 1.2em line box and would make this 8px taller than it is wide.
            implicitWidth: icon.implicitWidth
            implicitHeight: icon.implicitWidth
            radius: Tokens.rounding.small
            color: root.isColour ? root.swatchColour : "transparent"
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }

        StyledClippingRect {
            id: thumbWrapper

            visible: root.isImage
            anchors.verticalCenter: parent.verticalCenter
            // Same square as the swatch -- see there.
            implicitWidth: icon.implicitWidth
            implicitHeight: icon.implicitWidth
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHigh

            Image {
                id: thumb

                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                // Cached, unlike every other Image in the clipboard UI. The
                // reader's opening morph loads this exact url at this exact
                // sourceSize, so leaving the entry in QQuickPixmapCache makes
                // that load a synchronous hit -- which is the only reason the
                // morph has something to draw before the full-res decode
                // finishes. Cheap to keep: this is a ~50px square.
                cache: true
                asynchronous: true
                // Shared with the launcher's warm copy -- see Clipboard.thumbSize.
                sourceSize.width: Clipboard.thumbSize
                sourceSize.height: Clipboard.thumbSize
                // The file was not there -- decode it and come back. Only
                // reachable past the preloaded set; see `decoder`.
                onStatusChanged: {
                    if (status === Image.Error && root.decodeKey && !decoder.running)
                        decoder.running = true;
                }
            }
        }

        // NOT `id: text` -- that shadows the StyledTexts' own `text` property
        // inside this scope, silently breaking desc's `visible: text.length > 0`.
        Item {
            id: textCol

            // All three leading slots are the same 1em square at the same x, so
            // there is nothing to branch on -- which is the point. icon is the
            // one to measure from: the other two derive their size from it, and
            // it is laid out for every entry type rather than only its own.
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            implicitHeight: name.implicitHeight + desc.height

            StyledText {
                id: name

                anchors.left: parent.left
                anchors.right: parent.right
                text: root.modelData?.name ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: desc

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: name.bottom

                text: root.modelData?.desc ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight

                visible: text.length > 0
                // On own text, NOT `visible`: visible reads combined ancestor
                // visibility, and the reader's row-mask toggles that -- height
                // reacting to it loops the binding.
                height: text.length > 0 ? implicitHeight : 0
            }
        }
    }
}
