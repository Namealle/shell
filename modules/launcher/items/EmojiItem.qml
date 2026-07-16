import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

// Delegate for an emoji/glyph entry (the `:` launcher mode). modelData is an
// integer index into the Emoji singleton's parallel arrays; the glyph stands
// in for the left icon.
Item {
    id: root

    required property var modelData
    required property var list

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    function activate(): void {
        Emoji.activate(root.modelData);
        root.list.screenState.launcher = false;
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.activate()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        StyledText {
            id: glyph

            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.sizes.launcher.itemHeight - Tokens.padding.small * 2
            horizontalAlignment: Text.AlignHCenter

            text: Emoji.glyphAt(root.modelData)
            font: Tokens.font.headline.medium
        }

        StyledText {
            anchors.left: glyph.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: Emoji.nameAt(root.modelData)
            font: Tokens.font.body.medium
            elide: Text.ElideRight
        }
    }
}
