pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

// Emoji / glyph picker backing the `:` launcher mode. The dataset is huge
// (~12k lines from `caelestia emoji`, "<glyph> <keywords>"), so instead of one
// QObject per entry (which either froze on creation or went stale in the
// model), the whole set lives as cheap parallel STRING arrays and the launcher
// model is just an array of INTEGER indices. Integers are their own stable
// identity, so the ListView diffs and animates exactly like the other modes,
// with zero per-entry objects. Search runs natively in C++ (Search) and the
// delegate reads glyph/name by index. Activating copies the glyph.
Singleton {
    id: root

    property bool loaded: false

    // Parallel string arrays for the whole dataset (index-aligned).
    property var glyphs: []
    property var keywords: []

    function reload(): void {
        if (root.loaded)
            return;
        root.loaded = true;
        listProc.running = true;
    }

    function transformSearch(text: string): string {
        return text.slice(GlobalConfig.launcher.emojiPrefix.length);
    }

    // Returns an array of indices into glyphs/keywords (the model items).
    function query(text: string): var {
        const q = transformSearch(text).trim();
        if (!q.length) {
            const idx = [];
            const n = Math.min(200, root.glyphs.length);
            for (let i = 0; i < n; i++)
                idx.push(i);
            return idx;
        }
        return Search.fuzzyIndices(root.keywords, q, 200);
    }

    function glyphAt(i: int): string {
        return root.glyphs[i] ?? "";
    }

    function nameAt(i: int): string {
        return root.keywords[i] ?? "";
    }

    function activate(i: int): void {
        // printf '%s' copies the glyph exactly (no trailing newline).
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "emoji", root.glyphs[i] ?? ""]);
    }

    Process {
        id: listProc

        command: ["caelestia", "emoji"]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = [];
                const k = [];
                for (const line of text.split("\n")) {
                    const s = line.trim();
                    if (!s.length)
                        continue;
                    const sp = s.indexOf(" ");
                    if (sp >= 0) {
                        g.push(s.slice(0, sp));
                        k.push(s.slice(sp + 1).trim());
                    } else {
                        g.push(s);
                        k.push("");
                    }
                }
                root.glyphs = g;
                root.keywords = k;
            }
        }
    }

    // Preload the (cheap, object-free) string arrays at startup so the first
    // `:` is instant.
    Component.onCompleted: root.reload()
}
