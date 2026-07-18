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

    required property SearchBar search
    required property ScreenState screenState

    property string displayText

    // While the clipboard reader is open, typing is find-within-entry, not list
    // filtering: hold displayText (and therefore results + currentEntry) still.
    property bool frozen: false

    readonly property string requestedState: stateForText(search.text)
    readonly property string displayState: stateForText(displayText)

    function syncDisplayText(): void {
        if (frozen)
            return;
        if (screenState.launcher && requestedState === displayState)
            displayText = search.text;
    }

    function stateForText(text: string): string {
        if (text.startsWith(GlobalConfig.launcher.clipboardPrefix))
            return "clipboard";
        if (text.startsWith(GlobalConfig.launcher.emojiPrefix))
            return "emoji";

        const prefix = GlobalConfig.launcher.actionPrefix;
        if (text.startsWith(prefix)) {
            for (const action of ["calc", "scheme", "variant"])
                if (text.startsWith(`${prefix}${action} `))
                    return action;

            return "actions";
        }

        return "apps";
    }

    function resultsForText(text: string): var {
        switch (stateForText(text)) {
        case "clipboard":
            return Clipboard.query(text);
        case "emoji":
            return Emoji.query(text);
        case "actions":
            return Actions.query(text);
        case "calc":
            return [0];
        case "scheme":
            return Schemes.query(text);
        case "variant":
            return M3Variants.query(text);
        default:
            return Apps.search(text);
        }
    }

    // The results feeding the model, exposed so the clipboard reader can read the
    // highlighted entry directly (currentItem can be unrealised when scrolled).
    readonly property var results: root.resultsForText(root.displayText)
    readonly property var currentEntry: state === "clipboard" ? (root.results[root.currentIndex] ?? null) : null

    model: ScriptModel {
        values: root.results
        onValuesChanged: root.currentIndex = 0
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    // Every mode uses fixed-height rows (clipboard included), so item count sizes
    // the list exactly -- a stable, discrete height. Deriving it from contentHeight
    // instead makes the launcher chase a value that fluctuates all through the
    // move/displaced animations, which overshoots and ghosts. Keep it count-based,
    // identical to apps/actions.
    implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {}
        }
    }

    state: screenState.launcher && !frozen ? requestedState : displayState

    onStateChanged: {
        if (state === "scheme" || state === "variant")
            Schemes.reload();
        else if (state === "clipboard")
            Clipboard.reload();
        else if (state === "emoji")
            Emoji.reload();
    }

    Component.onCompleted: displayText = search.text

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.delegate: appItem
            }
        },
        State {
            name: "actions"

            PropertyChanges {
                root.delegate: actionItem
            }
        },
        State {
            name: "calc"

            PropertyChanges {
                root.delegate: calcItem
            }
        },
        State {
            name: "scheme"

            PropertyChanges {
                root.delegate: schemeItem
            }
        },
        State {
            name: "variant"

            PropertyChanges {
                root.delegate: variantItem
            }
        },
        State {
            name: "clipboard"

            PropertyChanges {
                root.delegate: clipItem
            }
        },
        State {
            name: "emoji"

            PropertyChanges {
                root.delegate: emojiItem
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
                target: root
                property: "delegate"
                value: null
            }
            ScriptAction {
                script: root.displayText = root.search.text
            }
            PropertyAction {
                target: root
                property: "delegate"
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
            // add only -- NOT remove. A remove-fade leaves every filtered-out row
            // fading in place for ~350ms while its replacement slides in over it:
            // two rows rendered on the same spot (the "ghost" overlap). Removed
            // rows must vanish instantly; the mode switch itself never needs the
            // fade either, since the whole list is at opacity 0 when delegates
            // are swapped.
            PropertyAction {
                target: root.add
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
            type: Anim.DefaultEffects
            property: "opacity"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: !root.state

        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            from: 1
            to: 0
        }
    }

    // Rows can be moved across the whole content span by a model change (e.g. a
    // clipboard filter hoisting a match from thousands of px down). The curve's
    // overshoot scales with the animated distance, so animating such teleports
    // literally sends rows flying across the screen. Cap the ANIMATED distance
    // at one viewport: longer moves first jump to a viewport away, then slide
    // the final stretch with the usual curve -- bounded overshoot, same feel,
    // and genuinely short moves are untouched.
    function capTravel(item: Item, destY: real): void {
        if (!item)
            return;
        const travel = destY - item.y;
        if (Math.abs(travel) > height)
            item.y = destY - Math.sign(travel) * height;
    }

    move: Transition {
        id: moveT

        SequentialAnimation {
            ScriptAction {
                script: root.capTravel(moveT.ViewTransition.item, moveT.ViewTransition.destination.y)
            }
            ParallelAnimation {
                Anim {
                    property: "y"
                }
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    to: 1
                }
            }
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            type: Anim.StandardSmall
        }
        Anim {
            type: Anim.DefaultEffects
            property: "opacity"
            to: 1
        }
    }

    displaced: Transition {
        id: dispT

        SequentialAnimation {
            ScriptAction {
                script: root.capTravel(dispT.ViewTransition.item, dispT.ViewTransition.destination.y)
            }
            ParallelAnimation {
                Anim {
                    property: "y"
                }
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    to: 1
                }
            }
        }
    }

    Component {
        id: appItem

        AppItem {
            screenState: root.screenState
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
        id: variantItem

        VariantItem {
            list: root
        }
    }

    Component {
        id: clipItem

        ClipItem {
            list: root
        }
    }

    Component {
        id: emojiItem

        EmojiItem {
            list: root
        }
    }

    Connections {
        function onTextChanged() {
            root.syncDisplayText();
        }

        target: root.search
    }

    Connections {
        function onLauncherChanged() {
            root.syncDisplayText();
        }

        target: root.screenState
    }
}
