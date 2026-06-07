import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var list
    required property string character
    required property string name

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    function trigger() {
        root.list.visibilities.launcher = false;
        Quickshell.execDetached(["sh", "-c", `echo -n '${root.character}' | wl-copy`]);
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

        StyledText {
            id: characterDisplay

            text: root.character
            font.pointSize: Tokens.font.size.extraLarge
            color: Colours.palette.m3onSurface

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
        }

        Item {
            anchors.left: characterDisplay.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.verticalCenter: characterDisplay.verticalCenter

            implicitWidth: parent.width - characterDisplay.width - Tokens.spacing.normal
            implicitHeight: nameText.implicitHeight

            StyledText {
                id: nameText

                // We strip out the aliases inside parenthesis for the UI display
                text: {
                    let fullName = root.name;
                    let bracketIndex = fullName.indexOf("(");
                    if (bracketIndex !== -1) {
                        return fullName.substring(0, bracketIndex).trim();
                    }
                    return fullName;
                }
                font.pointSize: Tokens.font.size.normal
            }
        }
    }
}
