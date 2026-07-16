pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

// Clipboard-history picker backing the `;` launcher mode.
//
// Best-of-both design: entries are persistent QtObjects (via Variants) and the
// query returns them RANK-ORDERED, so the ListView animates reordering exactly
// like the apps picker. The ranking itself runs in C++ (Search.fuzzyIndices) so
// searching 750 long (-preview-width 999) entries never freezes the way the JS
// Searcher did. `previews` and `entries` are parallel (both derive from
// rawEntries in order), so ranked indices map straight back to the objects.
Singleton {
    id: root

    // Raw `cliphist list` lines, newest first.
    property var rawEntries: []
    readonly property list<QtObject> entries: variants.instances
    readonly property var previews: root.rawEntries.map(line => {
        const tab = line.indexOf("\t");
        return tab >= 0 ? line.slice(tab + 1) : line;
    })

    function reload(): void {
        listProc.running = true;
    }

    function transformSearch(text: string): string {
        return text.slice(GlobalConfig.launcher.clipboardPrefix.length);
    }

    function query(text: string): var {
        const q = transformSearch(text).trim();
        if (!q.length)
            return [...root.entries];
        return Search.fuzzyIndices(root.previews, q, 200).map(i => root.entries[i]);
    }

    function activate(line: string): void {
        // Pass the raw line as $1 (data, never interpolated into the script)
        // so arbitrary clipboard content can't break shell quoting.
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "clip", line]);
    }

    Variants {
        id: variants

        model: root.rawEntries

        ClipEntry {}
    }

    component ClipEntry: QtObject {
        id: entry

        required property var modelData
        readonly property string raw: modelData

        readonly property string preview: {
            const tab = entry.raw.indexOf("\t");
            return tab >= 0 ? entry.raw.slice(tab + 1) : entry.raw;
        }
        // cliphist renders images as "[[ binary data 234 KiB png 1815x596 ]]"
        readonly property var binMatch: entry.preview.match(/^\[\[ binary data (.+) \]\]$/)

        readonly property string icon: entry.binMatch ? "image" : "content_paste"
        readonly property string name: entry.binMatch ? "Image" : entry.preview.replace(/\s+/g, " ").trim()
        readonly property string desc: {
            if (entry.binMatch)
                return entry.binMatch[1];
            const n = entry.name.length;
            return `${n} ${n === 1 ? "character" : "characters"}`;
        }

        function onClicked(list: var): void {
            root.activate(entry.raw);
            list.screenState.launcher = false;
        }
    }

    Process {
        id: listProc

        command: ["cliphist", "-preview-width", "999", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.rawEntries = text.split("\n").filter(l => l.length > 0)
        }
    }

    Component.onCompleted: root.reload()
}
