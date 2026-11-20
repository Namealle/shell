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
            let rb = root.readerAtRest();
            for (const v of [root.openVerdict, root.openFlight])
                if (v)
                    rb = rb ? rb + "; " + v : v;
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
        const nt = root.nativeText();
        if (nt)
            bad.push(nt);
        if (root.closeVerdict)
            bad.push(root.closeVerdict);
        if (root.openVerdict)
            bad.push(root.openVerdict);
        if (root.openFlight)
            bad.push(root.openFlight);
        if (root.closeFlight)
            bad.push(root.closeFlight);
        return [`${bad.length ? "BAD " + bad.join("; ") : "OK"} | ${tail}`].concat(out).join("\n");
    }

    // Text in the rows or the search bar drawn natively: it changes its look
    // whenever the launcher's transform comes and goes (see launcher/
    // Wrapper.qml), so every one of them is distance-field. A row type added
    // later without it is caught here.
    function nativeText(): string {
        const found = [];
        const walk = it => {
            if (!it || found.length > 2)
                return;
            if (it.renderType !== undefined && it.renderType === Text.NativeRendering && it.visible && (it.text ?? "") !== "")
                found.push(String(it.text).slice(0, 24));
            for (const c of it.children ?? [])
                walk(c);
        };
        walk(root.list?.contentItem);
        walk(root.search);
        return found.length ? `native text in the launcher: "${found.join('", "')}"` : "";
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

    // -- two rows in one slot, whenever it happens --
    //
    // The settled check above only looks 1.5 s after the last key, query or
    // reader change; a wheel scroll is none of those, and a pair of rows can
    // sit on one slot for a while before anything pokes it. This one samples
    // the list every 50 ms while the clipboard list is up and logs the moment
    // two drawn rows have stood in one slot (less than half a stride apart)
    // for longer than any of the list's own animations lets two rows cross
    // (overlapMs), with the state of every row at that moment -- the hold
    // (gapHold) and entrance offsets are what told the 2026-11-19 bug apart:
    // a row held a stride low for a re-insert Qt had absorbed above the view.
    // Logged once per pair until the pair is apart again; also in `dump`.
    readonly property int overlapMs: 300
    property string overlapVerdict: ""
    property string overlapPair: ""
    property double overlapSince: 0
    // Every overlap verdict since the rig last asked (IPC dump).
    property string overlapSeen: ""

    function overlap(): var {
        const l = root.list;
        const stride = Tokens.sizes.launcher.itemHeight + l.spacing;
        const shown = root.rows().filter(r => r.visible && r.opacity > 0.05 && r.contentOpacity > 0.05 && r.visualY + r.height > l.contentY && r.visualY < l.contentY + l.height);
        shown.sort((a, b) => a.visualY - b.visualY);
        for (let k = 1; k < shown.length; k++)
            if (shown[k].visualY - shown[k - 1].visualY < stride / 2)
                return [shown[k - 1], shown[k]];
        return null;
    }

    Timer {
        interval: 50
        repeat: true
        running: root.launcherOpen && root.list?.state === "clipboard"
        onRunningChanged: {
            root.overlapPair = "";
            root.overlapSince = 0;
        }
        onTriggered: {
            const p = root.overlap();
            const key = p ? `${p[0].index}/${p[1].index}` : "";
            if (key !== root.overlapPair) {
                root.overlapPair = key;
                root.overlapSince = Date.now();
                if (!key)
                    root.overlapVerdict = "";
                return;
            }
            if (!key || root.overlapVerdict || Date.now() - root.overlapSince < root.overlapMs)
                return;
            const l = root.list;
            const c = root.content;
            root.overlapVerdict = `rows ${p[0].index} and ${p[1].index} drawn in one slot for ${Date.now() - root.overlapSince}ms (at ${p[0].visualY.toFixed(1)} and ${p[1].visualY.toFixed(1)})`;
            root.overlapSeen = root.overlapSeen ? `${root.overlapSeen}; ${root.overlapVerdict}` : root.overlapVerdict;
            const rowsTxt = root.rows().map(r => `[${r.index}] y=${r.y.toFixed(1)} drawn=${r.visualY.toFixed(1)} hold=${r.holdY.toFixed(1)} ent=${r.entranceY.toFixed(1)}`).join(" // ");
            const line = `BAD ${root.overlapVerdict} | text="${root.search.text}" count=${l.count} cur=${l.currentIndex} contentY=${l.contentY.toFixed(1)} originY=${l.originY.toFixed(1)} gap=${l.readerGapIndex} reader=${c.readerActive ? "open" : c.readerExiting ? "exiting" : "closed"} // ${rowsTxt}`;
            overlapLogger.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s %s\\n" "$(date -Is)" "$2" >>"$1"', "log", root.logPath, line];
            overlapLogger.running = true;
        }
    }

    Process {
        id: overlapLogger
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
    property var closeStart: ({})

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
            // What moved under the close, for a verdict to be read from the
            // log alone: his 2026-11-19 18:45 line (unscrolled, cur=0, the
            // picture 65px off its row) came with no recording, and the row
            // a stride away says something moved it, not what.
            if (root.closeVerdict) {
                const l = root.list;
                root.closeVerdict += ` (row ${root.closeStart.k}->${l.fullResults.indexOf(root.closeEntry)}, count ${root.closeStart.n}->${l.fullResults.length}, originY ${root.closeStart.oy.toFixed(1)}->${l.originY.toFixed(1)}, contentY ${root.closeStart.cy.toFixed(1)}->${l.contentY.toFixed(1)}, text "${root.closeStart.text}"->"${root.search.text}")`;
            }
            root.poke();
        }
    }

    // -- the open of a picture: it starts from rest --
    //
    // The picture lifting off its row must accelerate into the motion, not
    // jump into it: on the expressive curve the first 6ms frame took a 41px
    // thumbnail to 77x60 at once (3.9% of the whole size change, the crop
    // going from the row's square to nearly the picture's own aspect), which
    // he saw as the image changing "instantly when I click open". Judged on
    // the frames of the open: the first step must be at most half the
    // largest step of the run.
    property string openVerdict: ""
    property var openBoxes: []
    property bool openWatching: false
    property var openEntry: null

    property real openSlot: 0

    function judgeOpen(): string {
        const b = root.openBoxes;
        // Only an open that lifts off the row: a reversal of a close
        // (reenter) carries its speed on purpose, and a morph latched onto
        // the picture mid-flight (a browse during a text open) starts
        // wherever it is. Both start away from the slot.
        if (!b.length || Math.abs(b[0][2] - root.openSlot) > 1 || Math.abs(b[0][3] - root.openSlot) > 1)
            return "";
        const step = (p, q) => Math.max(Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1]), Math.abs(p[2] - q[2]), Math.abs(p[3] - q[3]));
        let first = -1, big = 0;
        for (let i = 1; i < b.length; i++) {
            const d = step(b[i], b[i - 1]);
            if (first < 0 && d > 0.01)
                first = d;
            big = Math.max(big, d);
        }
        if (first < 0 || big < 4)
            return "";
        if (first > 0.5 * big)
            return `image open: first step ${first.toFixed(1)}px of a largest ${big.toFixed(1)}px (does not start from rest)`;
        return "";
    }

    FrameAnimation {
        running: root.openWatching
        onTriggered: {
            const c = root.content;
            const r = root.readerLoader.item;
            if (!c.readerActive || c.readerExiting || !r) {
                root.openWatching = false;
                return;
            }
            if (!root.openEntry) {
                if (!(r.morphIsImage || r.morphIsColour))
                    return;
                root.openEntry = r.morphEntry;
                root.openSlot = r.slotS;
            }
            if (r.morphEntry !== root.openEntry)
                return;
            const m = r.liveMorphRect();
            if (m)
                root.openBoxes.push([m.x, m.y, m.w, m.h]);
            if (!r.morphInFlight && root.openBoxes.length > 2) {
                root.openWatching = false;
                root.openVerdict = root.judgeOpen();
                root.poke();
            }
        }
    }

    Connections {
        function onReaderActiveChanged(): void {
            if (!root.content.readerActive || root.content.readerExiting)
                return;
            root.openVerdict = "";
            root.openBoxes = [];
            root.openEntry = null;
            root.openWatching = true;
        }

        target: root.content
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
            const l = root.list;
            root.closeStart = {
                k: l.fullResults.indexOf(r.morphEntry),
                n: l.fullResults.length,
                oy: l.originY,
                cy: l.contentY,
                text: root.search.text
            };
            root.closeWatching = true;
        }

        target: root.content
    }

    // -- the row it lifts off and lands on, frame by frame --
    //
    // His recording of 2026-11-19 20:09: the wheel had scrolled the list
    // without the selection, so `->` opened the reader on a row above the
    // panel and the picture came in through the panel's top edge; the
    // full-size copy had not been decoded when the open landed, and for the
    // rest of the read the reader drew an empty panel under its header; the
    // close aimed at the row above the view, the re-insert there jumped the
    // list in one frame, and the picture landed a row off, on top of the next
    // row. Each of those is checked on every frame of an open and a close
    // (and for afterCloseMs after one), and logged by name:
    //   - an open starts on a row the panel shows whole, and a close lands
    //     on one (a query typed into the close is exempt: a row it moved
    //     away is left across the panel's edge on purpose);
    //   - the picture, swatch or header never crosses the panel's top edge
    //     (beyond the bounce its own curve or spring gives it there), and is
    //     never more than a row wholly below its bottom edge (same
    //     exemption). Not the bottom edge itself: the panel resizes on its
    //     own curve, so a tall picture folding home is cut there for a moment
    //     by the panel collapsing ahead of it, and one landing on a low row
    //     from a short reader waits a few frames below the edge for the
    //     panel to grow over it (i1/i2 in 20-images: 3.4px) -- whatever row
    //     it lands on;
    //   - while the reader is open on a picture, something draws it: the
    //     morph, the body's full-size copy or its stand-in;
    //   - the list does not move more than a row in one frame during a close
    //     or just after it, unless the query changed.
    readonly property int afterCloseMs: 600
    property string openFlight: ""
    property string closeFlight: ""
    property bool flightStart: false
    property bool afterClose: false
    property real flightLastY: 0
    property string flightLastText: ""
    property double flightOpenAt: 0
    property double blankSince: 0
    property real blankAt: 0
    property real openViewH: 0
    property var flightEntry: null
    property bool flightRequeried: false

    // The close is over: the row it came down on, whole in the view?
    function judgeLanding(): void {
        const l = root.list;
        const e = root.flightEntry;
        root.flightEntry = null;
        if (!l || !e || root.flightRequeried)
            return;
        const k = l.results.indexOf(e);
        if (k < 0)
            return;
        const viewH = Math.min(l.height, l.implicitHeight);
        const it = l.itemAtIndex(k);
        const y = (it && it.modelData === e ? it.visualY : l.originY + k * (Tokens.sizes.launcher.itemHeight + l.spacing)) - l.contentY;
        const slot = 41;
        const top = y + (Tokens.sizes.launcher.itemHeight - slot) / 2;
        if (top < -0.5 || top + slot > viewH + 0.5)
            root.addFlight(false, `close landed on a row outside the view: row at ${y.toFixed(1)}, view 0..${viewH.toFixed(0)} | cur=${l.currentIndex} contentY=${l.contentY.toFixed(1)} originY=${l.originY.toFixed(1)}`);
    }

    function addFlight(open: bool, msg: string): void {
        const cur = open ? root.openFlight : root.closeFlight;
        // The first of each kind per open or close: that is the one with the
        // state worth reading, and a jump repeated over frames is one event.
        const kind = msg.split(":")[0];
        if (cur && cur.split("; ").some(m => m.split(":")[0] === kind))
            return;
        const next = cur ? `${cur}; ${msg}` : msg;
        if (open)
            root.openFlight = next;
        else
            root.closeFlight = next;
        root.poke();
    }

    // Is the reader drawing the picture it is open on, this frame?
    function pictureDrawn(r: var): bool {
        if (r.bodyFade <= 0)
            return false;
        if (r.morphInFlight && r.morphEntry === r.entry && r.morphIsImage) {
            if (r.morphDrawn !== undefined)
                return r.morphDrawn;
            // The overlay draws the row's thumbnail or the full-size copy;
            // the body's probe and image hold the same two pixmaps.
            return !!r.body && (r.body.thumbReady || r.body.imgReady);
        }
        if (r.orphans.some(o => o.entry === r.entry))
            return true;
        const b = r.body;
        if (!b || b.modelData !== r.entry)
            return false;
        if (b.pictureDrawn !== undefined)
            return b.pictureDrawn;
        return b.handedOff && b.imgReady;
    }

    function judgeFlight(): void {
        const c = root.content;
        const r = root.readerLoader.item;
        const l = root.list;
        if (!r || !l)
            return;
        const open = c.readerActive && !c.readerExiting;
        const stride = Tokens.sizes.launcher.itemHeight + l.spacing;
        const viewH = Math.min(l.height, l.implicitHeight);
        const where = () => `cur=${l.currentIndex} contentY=${l.contentY.toFixed(1)} originY=${l.originY.toFixed(1)} panel=${c.height.toFixed(0)}`;

        // The open's first frame: the row it lifts off.
        if (root.flightStart && open) {
            root.flightStart = false;
            // Judged on the row's leading slot, the thing that lifts off: a
            // row the view is still gliding onto after a keypress can be a
            // few px short of whole, and nothing of it is cut.
            const y = c.readerStartY;
            const slot = r.slotS ?? 41;
            const top = y + (Tokens.sizes.launcher.itemHeight - slot) / 2;
            // The view as it was when the key was pressed: by this first
            // frame the panel has begun resizing for the reader.
            if (top < -0.5 || top + slot > root.openViewH + 0.5)
                root.addFlight(true, `open on a row outside the view: row at ${y.toFixed(1)}, view 0..${root.openViewH.toFixed(0)} | ${where()}`);
        }

        // The shared element against the panel's edges.
        if (!c.exitRequeried) {
            if ((r.morphIsImage || r.morphIsColour) && r.morphInFlight) {
                const m = r.liveMorphRect();
                const what = r.morphIsImage ? "picture" : "swatch";
                if (m && m.y < -0.5)
                    root.addFlight(open, `${what} past the panel's top edge: by ${(-m.y).toFixed(1)}px (${open ? "open" : "close"}) | ${where()}`);
                else if (m && m.y > c.height + stride)
                    root.addFlight(open, `${what} below the panel's bottom edge: at ${m.y.toFixed(1)}, panel ${c.height.toFixed(0)} (${open ? "open" : "close"}) | ${where()}`);
            }
            // The header rests on the panel's top and bounces past it: its
            // spring ~2px (ClipReader.exitOvershootPx), the curve a text open
            // runs on 1.39% of the way it came (5.4px from row 6).
            const hy = r.slidePos - r.rowAlignY;
            const bounce = Math.max(3, 0.02 * Math.abs(c.readerStartY));
            if (hy < -bounce)
                root.addFlight(open, `header past the panel's top edge: by ${(-hy).toFixed(1)}px (${open ? "open" : "close"}) | ${where()}`);
            else if (hy > c.height + stride)
                root.addFlight(open, `header below the panel's bottom edge: at ${hy.toFixed(1)}, panel ${c.height.toFixed(0)} (${open ? "open" : "close"}) | ${where()}`);
        }

        // A picture being read with nothing drawn for it.
        if (open && r.entry?.isImage) {
            const now = Date.now();
            if (!root.pictureDrawn(r)) {
                if (!root.blankSince) {
                    root.blankSince = now;
                    root.blankAt = now - root.flightOpenAt;
                }
            } else if (root.blankSince) {
                root.endBlank(now);
            }
        }

        if (c.readerExiting) {
            if (c.exitRequeried)
                root.flightRequeried = true;
            if (c.readerEntry)
                root.flightEntry = c.readerEntry;
        }

        // The list under a close.
        if (c.readerExiting || root.afterClose) {
            const dy = l.contentY - root.flightLastY;
            const text = root.search.text;
            if (Math.abs(dy) > stride && text === root.flightLastText && !c.exitRequeried)
                root.addFlight(false, `list jumped ${dy.toFixed(1)}px in one frame ${c.readerExiting ? "during" : "after"} the close: ${root.flightLastY.toFixed(1)} -> ${l.contentY.toFixed(1)} | ${where()}`);
        }
        root.flightLastY = l.contentY;
        root.flightLastText = root.search.text;
    }

    // Two frames at least: a single frame between two draws is the handoff
    // itself, not a gap anyone can see.
    function endBlank(now: double): void {
        const ms = now - root.blankSince;
        root.blankSince = 0;
        if (ms >= 10)
            root.addFlight(true, `picture blank while the reader is open: ${Math.round(ms)}ms from ${Math.round(root.blankAt)}ms after the open`);
    }

    FrameAnimation {
        running: root.launcherOpen && (root.content.readerActive || root.content.readerExiting || root.afterClose)
        onRunningChanged: {
            if (running)
                root.flightLastY = root.list?.contentY ?? 0;
        }
        onTriggered: root.judgeFlight()
    }

    Timer {
        id: afterCloseTimer

        interval: root.afterCloseMs
        onTriggered: root.afterClose = false
    }

    Connections {
        function onReaderActiveChanged(): void {
            const c = root.content;
            if (!c.readerActive) {
                if (root.blankSince)
                    root.endBlank(Date.now());
                return;
            }
            if (c.readerExiting)
                return;
            root.openFlight = "";
            root.flightStart = true;
            root.openViewH = Math.min(root.list.height, root.list.implicitHeight);
            root.flightOpenAt = Date.now();
            root.blankSince = 0;
        }

        function onReaderExitingChanged(): void {
            if (root.content.readerExiting) {
                root.closeFlight = "";
                root.afterClose = false;
                root.flightEntry = root.content.readerEntry;
                root.flightRequeried = false;
                afterCloseTimer.stop();
            } else if (!root.content.readerActive) {
                // The close is over (not turned into a new open).
                root.afterClose = true;
                afterCloseTimer.restart();
                root.judgeLanding();
            }
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
        // The list and the reader around the morph: what moved them.
        const c = root.content;
        s.cy = Math.round(l.contentY * 10) / 10;
        s.oy = Math.round(l.originY * 10) / 10;
        s.cur = l.currentIndex;
        s.ra = c.readerActive ? 1 : 0;
        s.rx = c.readerExiting ? 1 : 0;
        s.ch = Math.round(c.height * 10) / 10;
        s.hy = Math.round((l.highlightItem?.y ?? -1) * 10) / 10;
        s.lift = l.liftedEntry ? 1 : 0;
        if (r) {
            s.sp = Math.round(r.slidePos * 10) / 10;
            s.xs = Math.round(r.exitScroll * 10) / 10;
            s.bImg = r.body?.imgReady ? 1 : 0;
            s.bHand = r.body?.handedOff ? 1 : 0;
            s.drawn = r.entry?.isImage ? (root.pictureDrawn(r) ? 1 : 0) : -1;
        }
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
            // The same box in the scene, through every transform on the way
            // -- the panel's deform matrix included, which the box above
            // does not see.
            if (m) {
                const a = r.mapToItem(null, m.x, m.y);
                const b = r.mapToItem(null, m.x + m.w, m.y + m.h);
                s.sbox = [a.x, a.y, b.x - a.x, b.y - a.y].map(v => Math.round(v * 1000) / 1000);
            }
        }
        if (l && root.traceEntry) {
            const k = l.results.indexOf(root.traceEntry);
            const it = k >= 0 ? l.itemAtIndex(k) : null;
            if (it && it.leadX !== undefined) {
                s.row = [l.x + it.x + it.leadX, l.y + it.visualY - l.contentY + it.leadY].map(v => Math.round(v * 1000) / 1000);
                const sr = it.mapToItem(null, it.leadX, it.leadY);
                s.srow = [sr.x, sr.y].map(v => Math.round(v * 1000) / 1000);
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

        // The settled check, plus any two-rows-in-one-slot seen since the
        // last call (the rig calls this once per scenario).
        function dump(): string {
            const d = root.dump();
            const seen = root.overlapSeen;
            root.overlapSeen = "";
            if (!seen)
                return d;
            const nl = d.indexOf("\n");
            const head = nl < 0 ? d : d.slice(0, nl);
            const rest = nl < 0 ? "" : d.slice(nl);
            const reasons = head.startsWith("BAD ") ? head.slice(4) : head.replace(/^OK/, "");
            return `BAD ${seen}${reasons.startsWith(" |") ? "" : "; "}${reasons}${rest}`;
        }

        function mid(): string {
            return root.mid();
        }

        // A long trace does not fit one IPC reply: stop, then read it in
        // slices (lib/trace-chunks.sh).
        function traceStop(): int {
            traceAnim.running = false;
            return root.trace.length;
        }

        function traceChunk(from: int, n: int): string {
            return root.trace.slice(from, from + n).map(s => JSON.stringify(s)).join("\n");
        }
    }
}
