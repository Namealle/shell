import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

// Delegate for a clipboard-history entry (the `;` launcher mode). Left slot is
// a decoded thumbnail for image entries, otherwise the content-aware Material
// icon from Clipboard.iconFor(); then title + description.
Item {
    id: root

    required property var modelData
    required property var list

    readonly property bool isImage: root.modelData?.isImage ?? false
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

            visible: !root.isImage
            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData?.icon ?? "content_paste"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
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

        Item {
            anchors.left: root.isImage ? thumbWrapper.right : icon.right
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
                height: visible ? implicitHeight : 0
            }
        }
    }
}
