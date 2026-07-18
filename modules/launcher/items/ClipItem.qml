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
            text: root.modelData?.icon ?? "content_paste"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        // Colour entries paint the actual colour as their swatch instead of an icon.
        StyledRect {
            id: swatch

            visible: root.isColour
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: icon.implicitHeight
            implicitHeight: icon.implicitHeight
            radius: Tokens.rounding.small
            color: root.isColour ? root.swatchColour : "transparent"
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }

        StyledClippingRect {
            id: thumbWrapper

            visible: root.isImage
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: icon.implicitHeight
            implicitHeight: icon.implicitHeight
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHigh

            Image {
                id: thumb

                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true
                sourceSize.width: width * 2
                sourceSize.height: height * 2
            }
        }

        // NOT `id: text` -- that shadows the StyledTexts' own `text` property
        // inside this scope, silently breaking desc's `visible: text.length > 0`.
        Item {
            id: textCol

            anchors.left: root.isImage ? thumbWrapper.right : (root.isColour ? swatch.right : icon.right)
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
