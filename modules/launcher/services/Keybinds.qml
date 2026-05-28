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
        if (modmask & 4)  parts.push("Ctrl");
        if (modmask & 8)  parts.push("Alt");
        if (modmask & 1)  parts.push("Shift");
        if (modmask & 2)  parts.push("CapsLock");
        if (modmask & 16) parts.push("NumLock");
        if (modmask & 32) parts.push("Hyper");
        if (modmask & 128) parts.push("AltGr");

        let keyName = key;
        if (key === "mouse:272") keyName = "LMB";
        else if (key === "mouse:273") keyName = "RMB";
        else if (key === "mouse:274") keyName = "MMB";
        else if (key === "mouse:275") keyName = "Mouse4";
        else if (key === "mouse:276") keyName = "Mouse5";
        else if (key === "mouseUp") keyName = "MouseUp";
        else if (key === "mouseDown") keyName = "MouseDown";
        else keyName = toTitleCase(key);

        if (keyName) parts.push(keyName);
        return parts.join(" + ");
    }

    function toTitleCase(str) {
        if (!str) return ""; 
        return str[0].toUpperCase() + str.slice(1).toLowerCase();
    }

    function reload(): void {
        getKeybinds.running = true;
    }

    list: keybinds.instances
    useFuzzy: GlobalConfig.launcher.useFuzzy.keybinds
    property list<string> keys: ["combo", "description", "dispatcher", "arg"]
    property list<real> weights: [3, 2, 1, 1]

    Variants {
        id: keybinds
        Keybind {}
    }

    Process {
        id: getKeybinds

        running: true
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const keybindsData = JSON.parse(text);
                const filtered = keybindsData.filter(bind => bind.dispatcher !== "global")
                const clean = filtered.map(bind => {
                    const baseCombo = formatCombo(bind.modmask, bind.key);
                    const submapStr = (bind.submap && bind.submap !== "" && bind.submap !== "global") ? `[${bind.submap}] ` : "";
                    return {
                        combo: submapStr + baseCombo,
                        dispatcher: bind.dispatcher,
                        arg: bind.arg,
                        has_description: bind.has_description,
                        description: bind.description,
                    };
                });

                const groupMap = {};
                clean.forEach(item => {
                    const comboMatch = item.combo.match(/^(.*?)\s*(\d+)$/);
                    const argMatch = item.arg.match(/^(.*?)\s*(\d+)$/);
                    if (comboMatch && argMatch) {
                        const groupId = `${item.dispatcher}||${comboMatch[1].trim()}||${argMatch[1].trim()}`;
                        if (!groupMap[groupId]) groupMap[groupId] = [];
                        item.comboNum = parseInt(comboMatch[2], 10);
                        item.argNum = parseInt(argMatch[2], 10);
                        groupMap[groupId].push(item);
                    }
                });

                const finalModel = [];
                const addedGroups = new Set();

                clean.forEach(item => {
                    const comboMatch = item.combo.match(/^(.*?)\s*(\d+)$/);
                    const argMatch = item.arg.match(/^(.*?)\s*(\d+)$/);
                    if (comboMatch && argMatch) {
                        const baseCombo = comboMatch[1].trim();
                        const baseArg = argMatch[1].trim();
                        const groupId = `${item.dispatcher}||${baseCombo}||${baseArg}`;
                        const gItems = groupMap[groupId];
                        
                        if (gItems.length > 1) {
                            if (!addedGroups.has(groupId)) {
                                addedGroups.add(groupId);
                                const minCombo = Math.min(...gItems.map(i => i.comboNum));
                                const maxCombo = Math.max(...gItems.map(i => i.comboNum));
                                const minArg = Math.min(...gItems.map(i => i.argNum));
                                const maxArg = Math.max(...gItems.map(i => i.argNum));
                                
                                finalModel.push({
                                    isGroup: true,
                                    items: gItems,
                                    combo: `${baseCombo} ${minCombo}-${maxCombo}`,
                                    dispatcher: item.dispatcher,
                                    arg: `${baseArg} ${minArg}-${maxArg}`,
                                    has_description: false,
                                    description: "",
                                });
                            }
                        } else {
                            finalModel.push(item);
                        }
                    } else {
                        finalModel.push(item);
                    }
                });
                
                keybinds.model = finalModel;
            }
        }
    }

    component Keybind: QtObject {
        required property var modelData
        readonly property string name: modelData.combo + modelData.description + modelData.arg + modelData.dispatcher
        readonly property string combo: modelData.combo
        readonly property string dispatcher: modelData.dispatcher
        readonly property string arg: modelData.arg
        readonly property bool has_description: modelData.has_description
        readonly property string description: modelData.description
        readonly property string icon: Icons.getKeybindIcon(dispatcher, arg)
        readonly property bool isGroup: modelData.isGroup ?? false
        readonly property var items: modelData.items ?? []

        signal triggerAction()

        function onClicked(list: AppList): void {
            if (isGroup) {
                triggerAction();
                return;
            }
            list.visibilities.launcher = false;
            Quickshell.execDetached(["hyprctl", "dispatch", dispatcher, arg]);
        }
    }
}

