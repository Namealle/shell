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
