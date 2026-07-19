pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: search.height + listWrapper.height + padding + search.anchors.bottomMargin

    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding

        ContentList {
            id: list

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: qsTr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

        onAccepted: {
            // Reader mode: copy the entry being read (it is lifted out of the
            // list model, so list indices can't reach it).
            if (list.readerActive) {
                list.readerEntry?.onClicked(list.currentList);
                return;
            }

            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    if (Colours.scheme === "dynamic" && currentItem.modelData.path !== Wallpapers.actualCurrent)
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.clipboardPrefix)) {
                    currentItem.modelData.onClicked(list.currentList);
                } else if (text.startsWith(GlobalConfig.launcher.emojiPrefix)) {
                    currentItem.activate();
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        Keys.onUpPressed: list.readerActive ? list.browseReader(-1) : list.currentList?.decrementCurrentIndex()
        Keys.onDownPressed: list.readerActive ? list.browseReader(1) : list.currentList?.incrementCurrentIndex()

        // → morphs into the clipboard reader, ← morphs back. Both give up in-field
        // cursor movement while in clipboard/reader mode (short filter text).
        Keys.onRightPressed: event => {
            if (text.startsWith(GlobalConfig.launcher.clipboardPrefix) && !list.readerActive) {
                list.enterReader();
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }
        Keys.onLeftPressed: event => {
            if (list.readerActive) {
                // Restore the list filter the reader froze (typing in the reader
                // was find-within-entry, not filtering); restore BEFORE unfreezing
                // so the swap never re-filters the list. The swap itself happens
                // after the header has slid back onto its row (exitReader).
                text = list.currentList?.displayText ?? text;
                list.exitReader();
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }

        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            // Reader: PgUp/PgDn page through the text, Home/End jump to the
            // edges (both animated in ClipReader). Home/End give up find-field
            // cursor jumps while reading; in list mode they stay with the field.
            if (list.readerActive) {
                if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                    list.readerScrollPage(event.key === Qt.Key_PageDown ? 1 : -1);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                    list.readerScrollEdge(event.key === Qt.Key_Home ? -1 : 1);
                    event.accepted = true;
                    return;
                }
            }

            // Del removes the highlighted clipboard entry (cliphist delete) --
            // list mode only: in the reader the list highlight sits on the
            // below-neighbour, not the entry being read, so it would delete
            // the wrong one.
            if (event.key === Qt.Key_Delete && !list.readerActive && text.startsWith(GlobalConfig.launcher.clipboardPrefix)) {
                const item = list.currentList?.currentItem;
                if (item?.modelData?.del) {
                    item.modelData.del();
                    event.accepted = true;
                }
                return;
            }

            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    search.text = "";
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
