import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services
import Quickshell.Widgets

Item {
    id: root

    required property Keybinds.Keybind modelData
    required property var list

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.normal
        onClicked: root.modelData?.onClicked(root.list)
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger
        anchors.margins: Tokens.padding.smaller

        Loader {
            id: icon
            asynchronous: true
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.sizes.launcher.itemHeight * 0.8
            height: Tokens.sizes.launcher.itemHeight * 0.8
            sourceComponent: root.modelData.icon.startsWith("image://") ? appIconComp : materialIconComp
        }

        Component {
            id: appIconComp
            IconImage {
                asynchronous: true
                source: root.modelData.icon
                implicitSize: parent.height * 0.8
            }
        }

        Component {
            id: materialIconComp
            MaterialIcon {
                text: root.modelData.icon
                font.pointSize: Tokens.font.size.extraLarge
            }
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.verticalCenter: icon.verticalCenter
            implicitWidth: parent.width - icon.width
            implicitHeight: name.implicitHeight + desc.implicitHeight

            StyledText {
                id: name
                text: root.modelData.combo
                font.pointSize: Tokens.font.size.normal
            }

            StyledText {
                id: desc
                text: root.modelData.has_description ? root.modelData.description : root.modelData.dispatcher + " " + root.modelData.arg
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
                width: root.width - icon.width - Tokens.rounding.normal * 2
                anchors.top: name.bottom
            }
        }
    }
}
