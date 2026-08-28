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
    // For the entrance stagger below -- the view injects it.
    required property int index

    implicitHeight: Tokens.sizes.launcher.itemHeight

    // Entrance for a row the filter brought in without moving it. Same problem
    // and same answer as the clipboard's rows -- ClipItem carries the full
    // reasoning; in short, a narrowing filter fills the viewport from below the
    // fold and the view builds those rows straight at their final position, so
    // nothing about them animates. Being BUILT is the signal, a surviving row
    // is never rebuilt and so keeps its own slide, and the stagger is what
    // stops seven rows arriving in step from reading as one block.
    transform: Translate {
        id: entrance
    }

    Component.onCompleted: {
        if (!root.list || Date.now() - root.list.filterChangedAt > 150)
            return;
        entrance.y = Tokens.sizes.launcher.itemHeight + Tokens.spacing.small;
        content.opacity = 0;
        entranceAnim.start();
    }

    SequentialAnimation {
        id: entranceAnim

        PauseAnimation {
            duration: Math.min(root.index, 6) * 24
        }

        ParallelAnimation {
            Anim {
                target: entrance
                property: "y"
                to: 0
                type: Anim.DefaultSpatial
            }
            Anim {
                target: content
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

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
        id: content

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
