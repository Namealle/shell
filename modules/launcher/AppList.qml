pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.items
import qs.modules.launcher.services

StyledListView {
    id: root

    required property StyledTextField search
    required property DrawerVisibilities visibilities

    model: ScriptModel {
        id: model

        onValuesChanged: root.currentIndex = 0
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.normal
        color: Colours.palette.m3onSurface
        opacity: 0.08

        x: root.currentItem?.highlightOffsetX ?? 0
        y: (root.currentItem?.y ?? 0) + (root.currentItem?.highlightOffsetY ?? 0)
        
        implicitWidth: root.currentItem?.highlightWidth ?? root.width
        implicitHeight: root.currentItem?.highlightHeight ?? root.currentItem?.implicitHeight ?? 0

        Behavior on x { Anim { type: Anim.DefaultSpatial } }
        Behavior on y { Anim { type: Anim.DefaultSpatial } }
        Behavior on implicitWidth { Anim { type: Anim.DefaultSpatial } }
        Behavior on implicitHeight { Anim { type: Anim.DefaultSpatial } }
    }

    function incrementCurrentIndex() {
        if (currentItem && typeof currentItem.navigateDown === "function") {
            if (currentItem.navigateDown()) return;
        }
        if (currentIndex < count - 1) {
            currentIndex++;
            if (currentItem && typeof currentItem.navigateIntoFromTop === "function") {
                currentItem.navigateIntoFromTop();
            }
        }
    }

    function decrementCurrentIndex() {
        if (currentItem && typeof currentItem.navigateUp === "function") {
            if (currentItem.navigateUp()) return;
        }
        if (currentIndex > 0) {
            currentIndex--;
            if (currentItem && typeof currentItem.navigateIntoFromBottom === "function") {
                currentItem.navigateIntoFromBottom();
            }
        }
    }

    state: {
        const text = search.text;
        const prefix = GlobalConfig.launcher.actionPrefix;
        if (text.startsWith(";"))
            return "emoji";
            
        if (text.startsWith(":"))
            return "clipboard";

        if (text.startsWith(prefix)) {
            for (const action of ["calc", "scheme", "variant", "keybinds"])
                if (text.startsWith(`${prefix}${action} `))
                    return action;

            return "actions";
        }

        return "apps";
    }

    onStateChanged: {
        if (state === "scheme" || state === "variant")
            Schemes.reload();
        if (state === "keybinds")
            Keybinds.reload();
        if (state === "clipboard")
            Clipboards.reload();
    }

    states: [
        State {
            name: "apps"

            PropertyChanges {
                model.values: Apps.search(search.text)
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                model.values: Actions.query(search.text)
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                model.values: [0]
                root.delegate: calcItem
            }
        },
        State {
            name: "scheme"

            PropertyChanges {
                model.values: Schemes.query(search.text)
                root.delegate: schemeItem
            }
        },
        State {
            name: "keybinds"

            PropertyChanges {
                model.values: Keybinds.query(search.text)
                root.delegate: keybindItem
            }
        },
        State {
            name: "variant"

            PropertyChanges {
                model.values: M3Variants.query(search.text)
                root.delegate: variantItem
            }
        },
        State {
            name: "emoji"

            PropertyChanges {
                target: Emojis
                currentSearch: Emojis.transformSearch(search.text)
            }
            PropertyChanges {
                target: root
                model: Emojis.model
                delegate: emojiItem
            }
        },
        State {
            name: "clipboard"

            PropertyChanges {
                target: Clipboards
                currentSearch: Clipboards.transformSearch(search.text)
            }
            PropertyChanges {
                target: root
                model: Clipboards.model
                delegate: clipboardItem
            }
        }
    ]

    transitions: Transition {
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 1
                    to: 0.9
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardAccel
                }
            }
            PropertyAction {
                targets: [model, root]
                properties: "values,delegate,model"
            }
            ParallelAnimation {
                Anim {
                    target: root
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    target: root
                    property: "scale"
                    from: 0.9
                    to: 1
                    duration: Tokens.anim.durations.small
                    easing: Tokens.anim.standardDecel
                }
            }
            PropertyAction {
                targets: [root.add, root.remove]
                property: "enabled"
                value: true
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: !root.state

        Anim {
            properties: "opacity,scale"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            properties: "opacity,scale"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            type: Anim.StandardSmall
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    displaced: Transition {
        Anim {
            property: "y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    Component {
        id: appItem

        AppItem {
            visibilities: root.visibilities
        }
    }

    Component {
        id: actionItem

        ActionItem {
            list: root
        }
    }

    Component {
        id: calcItem

        CalcItem {
            list: root
        }
    }

    Component {
        id: schemeItem

        SchemeItem {
            list: root
        }
    }
    Component {
        id: keybindItem

        KeybindItem {
            list: root
        }
    }
    Component {
        id: variantItem

        VariantItem {
            list: root
        }
    }
    
    Component {
        id: emojiItem

        EmojiItem {
            list: root
        }
    }
    
    Component {
        id: clipboardItem
        
        ClipboardItem {
            list: root
        }
    }
}
