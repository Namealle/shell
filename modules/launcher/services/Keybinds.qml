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

    list: keybinds.instances
    useFuzzy: GlobalConfig.launcher.useFuzzy.keybinds

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
                const clean = keybindsData.map(bind => ({
                    key: bind.key,
                    dispatcher: bind.dispatcher,
                    arg: bind.arg,
                    has_description: bind.has_description,
                    description: bind.description,
                    modmask: bind.modmask,
                }));
            keybinds.model = clean;
            }
        }
    }

    component Keybinds: QtObject {
        required property var modelData
        readonly property string key: modelData.key
        readonly property string dispatcher: modelData.dispatcher
        readonly property string arg: modelData.arg
        readonly property bool has_description: modelData.has_description
        readonly property string description: modelData.description
        readonly property int modmask: modelData.modmask
    }
}
