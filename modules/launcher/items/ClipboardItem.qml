import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var list
    required property string clipId
    required property string content

    // Grow to fit content (up to 3 wrapped lines + char count),
    // but never shrink below the standard launcher row height.
    implicitHeight: Math.max(
        Tokens.sizes.launcher.itemHeight,
        textColumn.implicitHeight + Tokens.padding.smaller * 2
    )

    anchors.left: parent?.left
    anchors.right: parent?.right

    function trigger() {
        root.list.visibilities.launcher = false;
        // Decode the selected clip and pipe it to wl-copy
        Quickshell.execDetached(["sh", "-c", `echo -n '${root.clipId}' | cliphist decode | wl-copy`]);
    }

    StateLayer {
        radius: Tokens.rounding.normal
        onClicked: root.trigger()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger
        anchors.margins: Tokens.padding.smaller

        MaterialIcon {
            id: icon

            text: "content_paste"
            font.pointSize: Tokens.font.size.extraLarge
            color: Colours.palette.m3onSurface

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: (Tokens.sizes.launcher.itemHeight - height - (Tokens.padding.smaller * 2)) / 2
        }

        Column {
            id: textColumn

            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: (Tokens.sizes.launcher.itemHeight - (contentText.font.pixelSize + charCountText.font.pixelSize) - (Tokens.padding.smaller * 2)) / 2
            spacing: 0

            StyledText {
                id: contentText

                text: root.content
                font.pointSize: Tokens.font.size.normal
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                width: parent.width
            }

            StyledText {
                id: charCountText

                text: root.content.length >= 999 
                      ? "999+ characters"
                      : root.content.length + " characters"
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
                width: parent.width
            }
        }
    }
}
