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
        if (root.closeVerdict)
            bad.push(root.closeVerdict);
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

    // -- a picture folding home: the close itself, frame by frame --
    //
    // Sampled on every rendered frame of an exit whose entry is an image or a
    // colour, and judged once the row has taken over. Three things, each the
    // way a landing can be felt as hard:
    //   - its size never leaves the range between where it started and the
    //     slot, on either axis (a curve overshooting a 600px size travel took
    //     it to 32.6px on a 41px slot);
    //   - the last step before the handoff is no bigger than the one before
    //     it (the motion comes to rest, it does not stop);
    //   - the frame the row takes over, its thumbnail is where the picture
    //     was drawn (within 0.1px).
    // A violation goes to the log like any other, and into `dump`.
    property string closeVerdict: ""
    property var closeBoxes: []
    property var closeRows: []
    property real closeSlot: 0
    property bool closeWatching: false
    property var closeEntry: null

    // `masked`: the row's box even while the reader masks it (it is laid out
    // all the same), for following where the picture is landing.
    function closeRowBox(masked = false): var {
        const l = root.list;
        if (!l || !root.closeEntry)
            return null;
        const k = l.results.indexOf(root.closeEntry);
        const it = k >= 0 ? l.itemAtIndex(k) : null;
        if (!it || it.leadX === undefined || (!it.visible && !masked))
            return null;
        const o = l.mapToItem(root.content, 0, 0);
        return [o.x + it.x + it.leadX, o.y + it.visualY - l.contentY + it.leadY];
    }

    // How far past its landing the picture may go: the reader bounces it
    // ~2px (ClipReader.exitOvershootPx), this allows 3. The old curve's dip
    // was 8.4px.
    readonly property real closeOvershootPx: 3

    function judgeClose(rowBox: var): string {
        const b = root.closeBoxes;
        const rows = root.closeRows;
        const s = root.closeSlot;
        const n = root.closeOvershootPx;
        const bad = [];
        // Size, per axis, between where it started and the slot, give or take
        // the bounce: an extreme aspect grows on one axis while it shrinks on
        // the other.
        for (const [k, axis] of [[2, "width"], [3, "height"]]) {
            const lo = Math.min(b[0][k], s) - n;
            const hi = Math.max(b[0][k], s) + n;
            const vals = b.map(x => x[k]);
            const mn = Math.min(...vals), mx = Math.max(...vals);
            if (mn < lo || mx > hi)
                bad.push(`${axis} went to ${(mn < lo ? mn : mx).toFixed(1)}px, more than ${n}px past ${b[0][k].toFixed(1)}..${s.toFixed(1)}`);
        }
        // Position: how far it goes past its row once that row has stopped
        // moving -- before that (a query typed into the close moves the row)
        // the picture is chasing a moving target, not overshooting. Past =
        // on the far side of the row from where it was when the row stopped.
        let past = 0;
        const fin = rows.length ? rows[rows.length - 1] : null;
        // The last frame the row was still moving (or not yet built).
        let k = -1;
        if (fin) {
            for (let i = 0; i < rows.length; i++)
                if (!rows[i] || Math.abs(rows[i][1] - fin[1]) > 0.5)
                    k = i;
            const side = k + 1 < b.length ? Math.sign(b[k + 1][1] - fin[1]) : 0;
            for (let i = k + 1; i < b.length && side; i++)
                past = Math.max(past, (fin[1] - b[i][1]) * side);
        }
        if (past > n)
            bad.push(`went ${past.toFixed(1)}px past its row`);
        // The return: from the frame furthest past the slot (or, with no
        // bounce, from the fastest frame) to the end, no step out of keeping
        // with the one before -- the motion's own speed carries it home and
        // nothing jumps (floor 0.25px, for the turn).
        const step = (p, q) => Math.max(Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1]), Math.abs(p[2] - q[2]), Math.abs(p[3] - q[3]));
        const pastSlot = x => Math.max((x[2] - s) * Math.sign(s - b[0][2]), (x[3] - s) * Math.sign(s - b[0][3]));
        let peak = 0;
        for (let i = 1; i < b.length; i++)
            if (pastSlot(b[i]) > pastSlot(b[peak]))
                peak = i;
        if (pastSlot(b[peak]) <= 0) {
            peak = 1;
            for (let i = 2; i < b.length; i++)
                if (step(b[i], b[i - 1]) > step(b[peak], b[peak - 1]))
                    peak = i;
        }
        // Against the larger of the two steps before: this samples on its
        // own frame callback, which can land before or after the animation's
        // write, so a frame now and then reads as no step and the next as two.
        //
        // And only once the row has stopped moving, like the position check.
        // A query typed into the close moves the row (measured: 788 -> 73px
        // through its own displacement transition), the header chases it,
        // and its steps rise and fall with that chase -- 5.8, 7.8, 14.1, 21,
        // 26, 32, 35, 33... -- a motion, not a jump, which read as one when
        // the check started at the size's deepest point.
        for (let i = Math.max(3, peak + 1, k + 2); i < b.length; i++) {
            const a = step(b[i], b[i - 1]);
            const before = Math.max(step(b[i - 1], b[i - 2]), step(b[i - 2], b[i - 3]));
            if (a > Math.max(0.25, 1.6 * before)) {
                bad.push(`step of ${a.toFixed(2)}px after ${before.toFixed(2)}px on the way home`);
                break;
            }
        }
        // Only where the row can be seen: a row the query put below the
        // panel's edge is left across that edge (ContentList.requeryRowY)
        // and both are clipped away.
        const l = root.list;
        const top = l ? l.mapToItem(root.content, 0, 0).y : 0;
        const shown = rowBox && l && rowBox[1] + s > top && rowBox[1] < top + Math.min(l.height, l.implicitHeight);
        if (shown && b.length) {
            const f = b[b.length - 1];
            const d = Math.max(Math.abs(f[0] - rowBox[0]), Math.abs(f[1] - rowBox[1]), Math.abs(f[2] - s), Math.abs(f[3] - s));
            if (d > 0.1)
                bad.push(`handoff ${d.toFixed(2)}px off the row's thumbnail`);
        }
        return bad.length ? "image close: " + bad.join(", ") : "";
    }

    FrameAnimation {
        id: closeAnim

        running: root.closeWatching
        onTriggered: {
            const c = root.content;
            const r = root.readerLoader.item;
            if (c.readerExiting && r) {
                if (r.morphEntry !== root.closeEntry || !r.morphInFlight)
                    return;
                const m = r.liveMorphRect();
                if (m) {
                    root.closeBoxes.push([m.x, m.y, m.w, m.h]);
                    root.closeRows.push(root.closeRowBox(true));
                }
                return;
            }
            // The exit is over. Judge it on the first frame the row draws.
            root.closeWatching = false;
            if (c.readerActive || root.closeBoxes.length < 3)
                return;
            root.closeVerdict = root.judgeClose(root.closeRowBox());
            root.poke();
        }
    }

    Connections {
        function onReaderExitingChanged(): void {
            const r = root.readerLoader.item;
            if (!root.content.readerExiting || !r || !(r.morphIsImage || r.morphIsColour))
                return;
            root.closeVerdict = "";
            root.closeBoxes = [];
            root.closeRows = [];
            root.closeSlot = r.slotS;
            root.closeEntry = r.morphEntry;
            root.closeWatching = true;
        }

        target: root.content
    }

    // -- frame trace (debug, for the rig) --
    //
    // Per rendered frame: the reader's leading-slot morph (the box it draws,
    // fractional, in this launcher's coordinates), the morph value, the
    // header, and the row thumbnail the morph lands on -- before and after
    // the handoff, so the frame where one gives way to the other is in the
    // same record. `traceStart`, act, `traceDump`.
    property var trace: []
    property double traceT0: 0
    property var traceEntry: null

    function traceSample(): void {
        const r = root.readerLoader.item;
        const l = root.list;
        const s = {
            t: Math.round((Date.now() - root.traceT0) * 10) / 10,
            dt: Math.round(traceAnim.frameTime * 10000) / 10
        };
        const o = root.content.mapToItem(null, 0, 0);
        s.o = [Math.round(o.x * 1000) / 1000, Math.round(o.y * 1000) / 1000];
        if (r) {
            root.traceEntry = r.morphEntry ?? root.traceEntry;
            const m = r.liveMorphRect();
            s.reader = 1;
            s.m = Math.round(r.morphT * 1e5) / 1e5;
            s.morphing = r.morphing ? 1 : 0;
            s.inFlight = r.morphInFlight ? 1 : 0;
            s.slideY = Math.round(r.slideY * 1000) / 1000;
            if (m)
                s.box = [m.x, m.y, m.w, m.h, m.r].map(v => Math.round(v * 1000) / 1000);
        }
        if (l && root.traceEntry) {
            const k = l.results.indexOf(root.traceEntry);
            const it = k >= 0 ? l.itemAtIndex(k) : null;
            if (it && it.leadX !== undefined) {
                s.row = [l.x + it.x + it.leadX, l.y + it.visualY - l.contentY + it.leadY].map(v => Math.round(v * 1000) / 1000);
                s.rowVis = it.visible ? 1 : 0;
                s.rowThumbVis = it.thumbMasked ? 0 : 1;
            }
        }
        root.trace.push(s);
    }

    FrameAnimation {
        id: traceAnim

        running: false
        onTriggered: root.traceSample()
    }

    IpcHandler {
        target: "clipcheck"

        function traceStart(): string {
            root.trace = [];
            root.traceEntry = null;
            root.traceT0 = Date.now();
            traceAnim.running = true;
            return "tracing";
        }

        function traceDump(): string {
            traceAnim.running = false;
            return root.trace.map(s => JSON.stringify(s)).join("\n");
        }

        function dump(): string {
            return root.dump();
        }

        function mid(): string {
            return root.mid();
        }
    }
}
