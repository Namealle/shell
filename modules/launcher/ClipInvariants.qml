pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.utils

// Debug-only invariant check for the clipboard list and reader. Built only
// while the flag file `$XDG_CONFIG_HOME/caelestia/clip-invariants` exists (see
// Clipboard.checkInvariants), so with the flag off none of this exists.
//
// What it asserts is what a settled launcher must look like, whatever keys
// got it there: every built row on its own slot, nothing held, hidden, faded
// or doubled, every slot the viewport shows actually built, the lift and the
// mask cleared, the reader gone once closed -- or, with the reader open and at
// rest, the reader on its entry with nothing in flight. Each of those has been
// broken by an interrupted transition at least once (his screenshots of a gap
// with two rows printed in one slot, an empty panel under one row).
//
// "Settled" is measured, not guessed from animation state: the check runs
// settleMs after the last thing that could have started motion (a key, a
// query, the reader opening or closing, a browse). Nothing in the list or
// the reader animates for longer than ~600ms, so anything still wrong then
// is stuck. A violation is appended as one line to
// `$XDG_STATE_HOME/caelestia/clip-invariants.log`, once per distinct state.
//
// The same checks answer over IPC (`qs ipc call clipcheck dump` / `mid`) for
// the nested test rig in ~/namealle/projects/clipboard-tests.
Item {
    id: root

    required property Item content
    required property var list
    required property Loader readerLoader
    required property var search
    required property bool launcherOpen

    readonly property int settleMs: 1500
    readonly property string logPath: `${Paths.state}/clip-invariants.log`
    property string lastLogged: ""

    visible: false

    function rows(): var {
        const l = root.list;
        const out = [];
        for (const c of l.contentItem.children)
            if (c.holdY !== undefined && c.index >= 0)
                out.push(c);
        out.sort((a, b) => a.index - b.index);
        return out;
    }

    function readerAtRest(): string {
        const r = root.readerLoader.item;
        const c = root.content;
        if (!r)
            return "reader flagged open with no reader";
        const bad = [];
        if (Math.abs(r.slideY) > 0.5 || Math.abs(r.slideX) > 0.5)
            bad.push(`header off its rest ${r.slideX.toFixed(1)},${r.slideY.toFixed(1)}`);
        if (Math.abs(r.bodySlide) > 0.5)
            bad.push(`body slid ${r.bodySlide.toFixed(1)}`);
        if (r.entryIsText && r.bodyFade < 0.99)
            bad.push(`body faded ${r.bodyFade.toFixed(2)}`);
        if (root.readerLoader.opacity < 0.99)
            bad.push(`reader faded ${root.readerLoader.opacity.toFixed(2)}`);
        if (!r.body)
            bad.push("no body");
        else if (r.body.modelData !== c.readerEntry)
            bad.push("body is another entry");
        if (r.entry !== c.readerEntry)
            bad.push("header is another entry");
        if (r.orphans.length > 0)
            bad.push(`${r.orphans.length} orphans left`);
        if (root.list.maskedEntry !== c.readerEntry)
            bad.push("row not masked");
        return bad.join("; ");
    }

    // The full settled check. Returns "OK ..." or "BAD <reasons> ...", then one
    // line per built row.
    function dump(): string {
        const l = root.list;
        const c = root.content;
        if (!l)
            return "BAD no list";
        const tail = `text="${root.search.text}" count=${l.count} cur=${l.currentIndex} contentY=${l.contentY.toFixed(1)}`;
        if (c.readerActive && !c.readerExiting) {
            const rb = root.readerAtRest();
            return `${rb ? "BAD " + rb : "OK"} [reader] | ${tail} entry=${(c.readerEntry?.name ?? "?").slice(0, 30)}`;
        }
        const stride = Tokens.sizes.launcher.itemHeight + l.spacing;
        const clip = l.state === "clipboard";
        const rs = clip ? root.rows() : [];
        const bad = [];
        const seen = {};
        const out = [];
        for (const r of rs) {
            const want = l.originY + r.index * stride;
            const drawn = r.visualY;
            const onScreen = drawn + r.height > l.contentY && drawn < l.contentY + l.height;
            out.push(`  [${r.index}] y=${r.y.toFixed(1)} want=${want.toFixed(1)} drawn=${drawn.toFixed(1)} hold=${r.holdY.toFixed(1)} ent=${r.entranceY.toFixed(1)} vis=${r.visible} op=${r.opacity.toFixed(2)}/${r.contentOpacity.toFixed(2)}${onScreen ? "" : " (off)"} ${(r.modelData?.name ?? "?").slice(0, 28)}`);
            if (!onScreen)
                continue;
            if (Math.abs(drawn - want) > 0.5)
                bad.push(`row ${r.index} drawn ${(drawn - want).toFixed(1)}px off its slot`);
            if (!r.visible)
                bad.push(`row ${r.index} hidden`);
            if (r.opacity < 0.99 || r.contentOpacity < 0.99)
                bad.push(`row ${r.index} faded`);
            if (r.thumbMasked)
                bad.push(`row ${r.index} picture masked`);
            const slot = Math.round(drawn);
            if (seen[slot] !== undefined)
                bad.push(`rows ${seen[slot]} and ${r.index} drawn on one slot`);
            seen[slot] = r.index;
        }
        if (clip) {
            const have = {};
            for (const r of rs)
                have[r.index] = true;
            const missing = [];
            const bottom = l.contentY + Math.min(l.height, l.implicitHeight);
            for (let i = 0; i < l.count; i++) {
                const y = l.originY + i * stride;
                if (y + stride > l.contentY && y < bottom && !have[i])
                    missing.push(i);
            }
            if (missing.length)
                bad.push(`no row built in slots ${missing.join(",")}`);
            if (l.count !== l.fullResults.length)
                bad.push(`count ${l.count} vs ${l.fullResults.length} results`);
        }
        if (root.readerLoader.active)
            bad.push("reader still alive");
        if (c.readerActive || c.readerExiting)
            bad.push(`reader flags active=${c.readerActive} exiting=${c.readerExiting}`);
        if (l.liftedEntry || l.wantLift || l.maskedEntry)
            bad.push("lift/mask left set");
        if (l.count > 0 && (l.currentIndex < 0 || l.currentIndex >= l.count))
            bad.push(`currentIndex ${l.currentIndex} of ${l.count}`);
        return [`${bad.length ? "BAD " + bad.join("; ") : "OK"} | ${tail}`].concat(out).join("\n");
    }

    // What must hold even mid-flight, for the rig's mid-burst checks.
    function mid(): string {
        const l = root.list;
        const c = root.content;
        const r = root.readerLoader.item;
        const bad = [];
        if (r && c.readerExiting && c.readerEntry && l && l.fullResults.indexOf(c.readerEntry) < 0 && root.readerLoader.opacity > 0.05)
            bad.push("reader still drawn for an entry the query dropped");
        if (r && c.readerExiting) {
            const stride = Tokens.sizes.launcher.itemHeight + (l?.spacing ?? 0);
            if (r.slidePos < -2 * stride || r.slidePos > c.height + stride)
                bad.push(`exiting header drawn off the panel at ${r.slidePos.toFixed(0)} (panel ${c.height.toFixed(0)})`);
        }
        return bad.length ? "BAD " + bad.join("; ") : "OK";
    }

    function check(): void {
        if (!root.launcherOpen || !root.list || root.list.state !== "clipboard")
            return;
        const d = root.dump();
        if (!d.startsWith("BAD")) {
            root.lastLogged = "";
            return;
        }
        const head = d.split("\n")[0];
        if (head === root.lastLogged)
            return;
        root.lastLogged = head;
        logger.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s %s\\n" "$(date -Is)" "$2" >>"$1"', "log", root.logPath, d.replace(/\n/g, " //")];
        logger.running = true;
    }

    function poke(): void {
        settle.restart();
    }

    Timer {
        id: settle

        interval: root.settleMs
        onTriggered: root.check()
    }

    Process {
        id: logger
    }

    Connections {
        function onTextChanged(): void {
            root.poke();
        }

        target: root.search
    }

    Connections {
        function onReaderActiveChanged(): void {
            root.poke();
        }

        function onReaderExitingChanged(): void {
            root.poke();
        }

        target: root.content
    }

    Connections {
        function onCurrentIndexChanged(): void {
            root.poke();
        }

        function onCountChanged(): void {
            root.poke();
        }

        target: root.list
    }

    Connections {
        function onIndexChanged(): void {
            root.poke();
        }

        target: root.readerLoader.item
        ignoreUnknownSignals: true
    }

    IpcHandler {
        target: "clipcheck"

        function dump(): string {
            return root.dump();
        }

        function mid(): string {
            return root.mid();
        }
    }
}
