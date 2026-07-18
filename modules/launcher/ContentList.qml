pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property var currentList: showWallpapers ? wallpaperList.item : appList.item // Can be either ListView or PathView, so can't type properly
    property string animState: showWallpapers ? "wallpapers" : "apps"

    // Clipboard reader (Option D): `→` morphs the launcher into a reader for the
    // highlighted entry, `←` morphs back. Only meaningful in clipboard mode.
    property bool readerActive: false
    // displayState, NOT state: state's binding involves `frozen` (which we set
    // from readerActive), so reading it here would close a binding loop.
    readonly property bool canRead: (appList.item?.displayState ?? "") === "clipboard"
    readonly property var readerEntry: appList.item?.currentEntry ?? null
    onCanReadChanged: if (!canRead) readerActive = false

    // Closing the launcher mid-read must drop the reader AND the filter freeze,
    // then re-sync (the freeze made the usual clear-on-close sync a no-op).
    Connections {
        function onLauncherChanged(): void {
            if (!root.screenState.launcher && root.readerActive) {
                root.readerActive = false;
                appList.item?.syncDisplayText();
            }
        }

        target: root.screenState
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    // Reader rides on `state` (not animState) so the opacity fade below never
    // fires for it -- entering the reader is a pure geometric morph.
    state: readerActive && canRead ? "reader" : animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: root.Tokens.sizes.launcher.wallpaperHeight
                wallpaperList.active: true
            }
        },
        State {
            name: "reader"

            // Keep appList alive (currentIndex/model persist for ↑/↓ browse) but
            // hidden under the reader; no left/right anchors so width is intrinsic
            // and grows to the reader's content, centred like the wallpapers state.
            PropertyChanges {
                root.implicitWidth: clipReader.item?.implicitWidth ?? root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, clipReader.item?.implicitHeight ?? 0)
                appList.active: true
                appList.opacity: 0
                clipReader.active: true
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
            frozen: root.readerActive
        }
    }

    Loader {
        id: clipReader

        active: false

        anchors.fill: parent

        sourceComponent: ClipReader {
            entry: root.readerEntry
            // Search text minus the `;` prefix: seeded with the list filter on
            // entry, live as the user keeps typing (the list itself is frozen).
            findTerm: {
                const t = root.search.text;
                const p = GlobalConfig.launcher.clipboardPrefix;
                return t.startsWith(p) ? t.slice(p.length) : t;
            }
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: WallpaperList {
            objectName: "launcherWallpaperList"

            search: root.search
            screenState: root.screenState
            panels: root.panels
            content: root.content
        }
    }

    Row {
        id: empty

        opacity: root.currentList?.count === 0 ? 1 : 0
        scale: root.currentList?.count === 0 ? 1 : 0.5

        spacing: Tokens.spacing.medium
        padding: Tokens.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: root.state === "wallpapers" ? "wallpaper_slideshow" : "manage_search"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.state === "wallpapers" ? qsTr("No wallpapers found") : qsTr("No results")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: root.state === "wallpapers" && Wallpapers.list.length === 0 ? qsTr("Try putting some wallpapers in %1").arg(Paths.shortenHome(Paths.wallsdir)) : qsTr("Try searching for something else")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitWidth {
        enabled: root.screenState.launcher

        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState.launcher

        Anim {}
    }
}
