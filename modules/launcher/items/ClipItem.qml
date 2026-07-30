import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.components
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
    readonly property string swatchColour: root.isImage ? "" : (root.modelData?.colour ?? "")
    readonly property bool isColour: root.swatchColour.length > 0
    readonly property string imgCache: root.isImage ? `/tmp/caelestia-clip-preview-${root.modelData.entryId}.png` : ""

    // Re-decode whenever the delegate is recycled onto a different image entry.
    readonly property string decodeKey: root.isImage ? (root.modelData?.raw ?? "") : ""
    onDecodeKeyChanged: {
        thumb.source = "";
        decoder.running = false;
        if (root.decodeKey)
            decoder.running = true;
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

    // Decode the image entry to a cached thumbnail file (skips if already done).
    Process {
        id: decoder

        command: ["sh", "-c", "test -s \"$2\" || (printf '%s' \"$1\" | cliphist decode > \"$2\")", "dec", root.modelData?.raw ?? "", root.imgCache]
        onExited: thumb.source = root.imgCache ? `file://${root.imgCache}` : ""
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
            text: root.modelData?.icon ?? "content_paste"
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
                sourceSize.width: width * 2
                sourceSize.height: height * 2
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
