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

    StyledText {
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger
        anchors.margins: Tokens.padding.smaller
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.key
    }

    StyledText {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.dispatcher + " " + modelData.arg
    }
}
