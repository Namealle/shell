import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property Keybinds.Keybinds modelData
    required property var list

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.normal
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: Tokens.spacing.normal
        anchors.verticalCenter: parent.verticalCenter

        width: parent.width - anchors.leftMargin
        spacing: 0

        StyledText {
            text: root.modelData.combo
            font.pointSize: Tokens.font.size.normal
        }

        StyledText {
           text: root.modelData.has_description ? root.modelData.description : root.modelData.dispatcher + " " + root.modelData.arg
           font.pointSize: Tokens.font.size.small
           color: Colours.palette.m3outline

           elide: Text.ElideRight
           anchors.left: parent.left
           anchors.right: parent.right
        }
    }
}
