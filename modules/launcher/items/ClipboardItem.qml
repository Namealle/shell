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

    implicitHeight: Tokens.sizes.launcher.itemHeight

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

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width - Tokens.spacing.normal
            implicitHeight: contentText.implicitHeight

            StyledText {
                id: contentText

                text: root.content
                font.pointSize: Tokens.font.size.normal
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
