import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services
import Quickshell.Widgets

Item {
    id: root

    required property var modelData
    required property var list

    property bool expanded: false

    function toggleExpanded() {
        expanded = !expanded;
    }
    property int selectedSubItem: -1

    implicitHeight: Tokens.sizes.launcher.itemHeight + childContainer.height
    anchors.left: parent?.left
    anchors.right: parent?.right
    clip: true

    Connections {
        target: root.modelData
        function onTriggerAction() {
            if (root.expanded && root.selectedSubItem >= 0) {
                const child = root.modelData.items[root.selectedSubItem];
                root.list.visibilities.launcher = false;
                Quickshell.execDetached(["hyprctl", "dispatch", child.dispatcher, child.arg]);
            } else if (root.modelData.isGroup) {
                root.toggleExpanded();
            }
        }
    }

    property real highlightHeight: Tokens.sizes.launcher.itemHeight
    property real highlightOffsetX: selectedSubItem === -1 ? 0 : childContainer.x + childColumn.x
    property real highlightOffsetY: selectedSubItem === -1 ? 0 : childContainer.y + childColumn.y + selectedSubItem * Tokens.sizes.launcher.itemHeight
    property real highlightWidth: selectedSubItem === -1 ? width : childColumn.width

    function navigateDown() {
        if (expanded && selectedSubItem < root.modelData.items.length - 1) {
            selectedSubItem++;
            return true;
        } else {
            selectedSubItem = -1;
            return false;
        }
    }

    function navigateUp() {
        if (expanded && selectedSubItem > 0) {
            selectedSubItem--;
            return true;
        } else if (expanded && selectedSubItem === 0) {
            selectedSubItem = -1;
            return true;
        } else {
            return false;
        }
    }

    function navigateIntoFromTop() {
        selectedSubItem = -1;
    }

    function navigateIntoFromBottom() {
        if (expanded && root.modelData.items.length > 0) {
            selectedSubItem = root.modelData.items.length - 1;
        } else {
            selectedSubItem = -1;
        }
    }

    Item {
        id: header
        height: Tokens.sizes.launcher.itemHeight
        anchors.left: parent.left
        anchors.right: parent.right

        StateLayer {
            radius: Tokens.rounding.normal
            onClicked: {
                if (root.modelData.isGroup) {
                    root.toggleExpanded();
                } else {
                    root.modelData?.onClicked(root.list);
                }
            }
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
                sourceComponent: root.modelData.icon.includes("/") ? appIconComp : materialIconComp
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
                implicitWidth: parent.width - icon.width - (root.modelData.isGroup ? chevron.width + Tokens.spacing.normal : 0)
                implicitHeight: name.implicitHeight + desc.implicitHeight

                Row {
                    id: name
                    spacing: Tokens.spacing.small
                    
                    StyledText {
                        text: root.modelData.combo
                        font.pointSize: Tokens.font.size.normal
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    MaterialIcon {
                        visible: root.modelData.comboIcon !== undefined
                        text: root.modelData.comboIcon !== undefined ? root.modelData.comboIcon : ""
                        font.pointSize: Tokens.font.size.normal
                        color: Colours.palette.m3onSurface
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                StyledText {
                    id: desc
                    text: root.modelData.has_description ? root.modelData.description : root.modelData.dispatcher + " " + root.modelData.arg
                    font.pointSize: Tokens.font.size.small
                    color: Colours.palette.m3outline
                    elide: Text.ElideRight
                    width: parent.width
                    anchors.top: name.bottom
                }
            }

            MaterialIcon {
                id: chevron
                visible: root.modelData.isGroup === true
                text: root.expanded ? "expand_less" : "expand_more"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                font.pointSize: Tokens.font.size.large
                color: Colours.palette.m3outline
            }
        }
    }

    Item {
        id: childContainer
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.expanded ? childColumn.implicitHeight : 0
        clip: true

        Behavior on height {
            Anim { type: Anim.DefaultSpatial }
        }

        Column {
            id: childColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Tokens.sizes.launcher.itemHeight * 0.6 // Indent
            anchors.rightMargin: Tokens.padding.larger
            spacing: 0

            Repeater {
                model: root.modelData.items
            delegate: Item {
                id: subItemRoot
                implicitHeight: Tokens.sizes.launcher.itemHeight
                width: childColumn.width

                StateLayer {
                    radius: Tokens.rounding.normal
                    onClicked: {
                        root.list.visibilities.launcher = false;
                        Quickshell.execDetached(["hyprctl", "dispatch", modelData.dispatcher, modelData.arg]);
                    }
                }

                readonly property string iconStr: modelData.icon ?? ""

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.larger
                    anchors.rightMargin: Tokens.padding.larger
                    anchors.margins: Tokens.padding.smaller
                    
                    Loader {
                        id: subIcon
                        asynchronous: true
                        anchors.verticalCenter: parent.verticalCenter
                        width: Tokens.sizes.launcher.itemHeight * 0.8
                        height: Tokens.sizes.launcher.itemHeight * 0.8
                        sourceComponent: subItemRoot.iconStr.includes("/") ? subAppIconComp : subMaterialIconComp
                    }

                    Component {
                        id: subAppIconComp
                        IconImage {
                            asynchronous: true
                            source: subItemRoot.iconStr
                            implicitSize: parent.height * 0.8
                        }
                    }

                    Component {
                        id: subMaterialIconComp
                        MaterialIcon {
                            text: subItemRoot.iconStr
                            font.pointSize: Tokens.font.size.extraLarge
                        }
                    }

                    Item {
                        anchors.left: subIcon.right
                        anchors.leftMargin: Tokens.spacing.normal
                        anchors.verticalCenter: subIcon.verticalCenter
                        implicitWidth: parent.width - subIcon.width
                        implicitHeight: subName.implicitHeight + subDesc.implicitHeight

                        StyledText {
                            id: subName
                            text: modelData.combo
                            font.pointSize: Tokens.font.size.normal
                        }
                        
                        StyledText {
                            id: subDesc
                            text: modelData.has_description ? modelData.description : modelData.dispatcher + " " + modelData.arg
                            anchors.top: subName.bottom
                            font.pointSize: Tokens.font.size.small
                            color: Colours.palette.m3outline
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }
            }
        }
    }
    }
}
