pragma Singleton

import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(`${GlobalConfig.launcher.actionPrefix}keybinds `.length);
    }

    function formatCombo(modmask, key) {
        const parts = [];
        if (modmask & 64) parts.push("Super");
        if (modmask & 1)  parts.push("Shift");
        if (modmask & 2)  parts.push("CapsLock");
        if (modmask & 4)  parts.push("Ctrl");
        if (modmask & 8)  parts.push("Alt");
        if (modmask & 16) parts.push("NumLock");
        if (modmask & 32) parts.push("Hyper");
        if (modmask & 128) parts.push("AltGr");

        parts.push(toTitleCase(key));
        return parts.join(" + ");
    }

    function toTitleCase(str) {
        return str[0].toUpperCase() + str.slice(1).toLowerCase();
    }

    list: keybinds.instances
    useFuzzy: GlobalConfig.launcher.useFuzzy.keybinds
    property list<string> keys: ["combo", "description", "dispatcher", "arg"]
    property list<real> weights: [3, 2, 1, 1]

    Variants {
        id: keybinds
        Keybinds {}
    }

    Process {
        id: getKeybinds

        running: true
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const keybindsData = JSON.parse(text);
                const filtered = keybindsData.filter(bind => ( bind.mouse === false && bind.dispatcher !== "global" ))
                const clean = filtered.map(bind => ({
                    combo: formatCombo(bind.modmask, bind.key),
                    dispatcher: bind.dispatcher,
                    arg: bind.arg,
                    has_description: bind.has_description,
                    description: bind.description,
                }));
            keybinds.model = clean;
            }
        }
    }

    component Keybinds: QtObject {
        required property var modelData
        readonly property string name: modelData.combo + modelData.description + modelData.arg + modelData.dispatcher
        readonly property string combo: modelData.combo
        readonly property string dispatcher: modelData.dispatcher
        readonly property string arg: modelData.arg
        readonly property bool has_description: modelData.has_description
        readonly property string description: modelData.description
    }
}

