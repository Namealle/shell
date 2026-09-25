pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

// Clipboard-history picker backing the `;` launcher mode.
//
// Entries are persistent QtObjects (Variants) so the ListView can animate them,
// filtered by case-insensitive SUBSTRING and kept in cliphist order (newest
// first). Each entry gets a content-aware Material icon via iconFor() (regex,
// security-oriented), image entries show a decoded thumbnail (in ClipItem), and
// the Del key removes an entry via cliphist delete.
Singleton {
    id: root

    // -- reader image box geometry --
    //
    // Lives in the service, not in ClipReader, because two places have to agree
    // on it EXACTLY: the reader, which asks QQuickPixmapCache for a decode, and
    // the prefetcher, which warms that same cache. The cache key is url +
    // sourceSize, so a second copy of this formula that drifted by one pixel
    // would silently turn every prefetch into a miss -- and it would fail
    // invisibly, since a miss just looks like the old behaviour.
    // Note the two are not measured the same way: maxWidth caps the WINDOW (the
    // image gets it minus the reader's own padding), maxHeight caps the IMAGE
    // (the header and padding sit on top of it). They read as a pair but only
    // the first is a window dimension.
    readonly property int readerMaxWidth: 1000
    // Editorial, not a fit constraint: the launcher's own ceiling is nearly the
    // whole screen (see Wrapper's maxHeight), so this is only a statement about
    // how much of it a preview should take.
    //
    // Raising it was tried and deliberately not kept. Against maxWidth's 968 of
    // content this box is landscape-shaped, which costs portrait images twice --
    // cut on the axis they are short of, while the axis they have to spare goes
    // unspent, so a 9:16 clip paints 360 wide. At 880 that same clip paints 495
    // and a phone screenshot stops hitting minImageWidth entirely, both strictly
    // better framings; the reason it went back is that a portrait entry then
    // takes ~1030px of window, which is more of the screen than a quick picker
    // should occupy, and the morph has to travel that whole distance out of an
    // 82px row. Landscape entries never notice either value -- anything wider
    // than about 1.5:1 is capped by the width first.
    //
    // Worth revisiting as a config token rather than a constant: the trade is
    // entirely about screen size and how much of it the picker may borrow, which
    // is a preference, not something this file can know.
    readonly property int readerMaxHeight: 640

    // The width the reader's body image is painted at.
    //
    // Two hard ceilings, which nothing may cross:
    //   maxWidth  - the same width text gets, so an image reads at the same
    //               scale as a wide code block rather than staying pinned to
    //               the launcher's list width.
    //   maxHeight - a portrait image that would blow past the height ceiling is
    //               width-limited instead, so it fills the box it is given
    //               rather than being letterboxed inside a too-wide one.
    //
    // Then a floor, the only thing allowed to enlarge past `natW`: fill the body
    // the launcher has at its DEFAULT width, however far past its own pixels
    // that is. Deliberately measured against the list width and not maxWidth --
    // upscaling exists to close the bars in a window that is already there,
    // never to make the window bigger for a picture that has no detail to put in
    // it. So a small image grows to fill 600px of launcher and stops; only real
    // resolution ever pushes past that.
    //
    // There is no ceiling on the enlargement, and a 40x30 clip really is drawn
    // ~14x up. It is soft, unavoidably -- but a preview's job is to answer "is
    // this the thing I copied", and a legible blur answers it where a sharp
    // 40px postage stamp adrift in an empty body does not. The one case this
    // gets wrong is deliberate pixel art, which wants nearest-neighbour rather
    // than a bigger box; if that turns out to matter, it is a filtering
    // decision at the Image, not a sizing one here.
    //
    // `natW` is passed separately from `arW` because they are not always the
    // same measurement: the aspect can be read off an 82px thumbnail, but that
    // thumbnail's WIDTH is not the image's resolution.
    //
    // Returns a WHOLE number of pixels, which is the whole point: the reader
    // paints the image at this size and decodes its texture at this size, and
    // those two only cancel out exactly when both are integers. A box of 764.4
    // against a 765-wide texture is a full bilinear resample of every pixel in
    // the image -- sub-pixel in magnitude, but a resample is a resample, and it
    // costs far more sharpness than its percentage suggests.
    function readerImageWidth(arW: real, arH: real, natW: real): int {
        if (!(arW > 0) || !(arH > 0))
            return 0;
        const pad = Tokens.padding.large * 2;
        const cap = Math.min(root.readerMaxWidth - pad, root.readerMaxHeight * arW / arH);
        const floor = Math.min(Tokens.sizes.launcher.itemWidth - pad, cap);
        return Math.round(Math.max(floor, Math.min(cap, natW)));
    }

    // The sourceSize the reader will ask for -- and therefore the only one worth
    // prefetching. Exactly the resting box, so the image at rest is a true 1:1
    // blit: one texel per pixel, no resample in either direction, which is the
    // sharpest a picture can be drawn.
    //
    // Nothing is added here for the morph's overshoot. That was tried, and it
    // trades one defect for its mirror image: a texture cut for the 1.39% peak
    // leaves the RESTING draw a 1.4% minification, and a permanent softness on
    // the thing you spend all your time looking at is a far worse bargain than a
    // brief one on the thing that is still moving. The morph earns its sharpness
    // a different way -- by not overshooting in size at all, so it only ever
    // minifies from this texture. See morphImg.
    //
    // Falls back to the flat ceiling when the entry carries no dimensions: the
    // box cannot be known ahead of the decode there, so the decode has to pick a
    // size the reader will also pick, and that is the only one left.
    function readerDecodeWidth(dims: var): int {
        const w = dims ? root.readerImageWidth(dims.w, dims.h, dims.w) : 0;
        return w > 0 ? w : root.readerMaxWidth;
    }

    // -- preload --
    //
    // The picker's images are warmed BEFORE they are asked for, in two stages
    // that match the two moments the user commits to something:
    //
    //   launcher opens  -> the row thumbnails, so `;` paints a full list at once
    //                      instead of filling in as each row decodes.
    //   `;` is pressed  -> the reader-size copies, so `→` on any visible row is
    //                      instant rather than paying a 32-53ms decode inside
    //                      the opening morph.
    //
    // Only the rows that can actually be on screen: maxShown is what the list
    // draws, so warming past it buys nothing and costs a full-size pixmap each.
    // Unfiltered and newest-first, which is exactly the list `;` opens on -- a
    // filtered query narrows it, and those rows are warmed by ClipItem as they
    // render.
    //
    // Held for as long as the shell runs rather than expiring on a timer: this
    // set only changes when the clipboard does, re-warming it costs a decode per
    // entry, and the whole point is that the picker is never caught cold. The
    // bound is the count, not a clock -- at most maxShown pictures, ~1.6MB each
    // at the largest, so worst case is around 11MB and typically far less.
    readonly property var preloadEntries: {
        const out = [];
        const n = GlobalConfig.launcher.maxShown;
        for (const e of root.entries) {
            if (out.length >= n)
                break;
            if (e?.isImage && e.entryId)
                out.push(e);
        }
        return out;
    }

    // True while the launcher is actually showing the clipboard picker. Gates the
    // full-size stage, which is the expensive one -- opening the launcher to run
    // an app should not decode a screenful of pictures nobody asked for.
    property bool picking: false

    // The full-size preload waits for this, not for `picking` itself.
    //
    // Qt decodes images on ONE background thread, in request order. Firing a
    // screenful of full-size decodes the instant the picker opens puts 7 jobs of
    // 32-53ms each in front of the row thumbnails, which are what the user is
    // actually looking at -- measured 43-179ms before a thumbnail could paint,
    // i.e. the picker visibly filling in one row at a time. The preload is
    // groundwork for a keypress that has not happened yet; it has no business
    // outranking the frame on screen.
    //
    // A quarter second is long enough for seven small decodes to clear and short
    // enough that `→` is still warm by any human reaction time.
    property bool pickingSettled: false

    onPickingChanged: {
        if (root.picking) {
            settleTimer.restart();
        } else {
            settleTimer.stop();
            root.pickingSettled = false;
        }
    }

    Timer {
        id: settleTimer

        interval: 250
        onTriggered: root.pickingSettled = true
    }

    // -- retained set --
    //
    // Which images are being held decoded, most recently wanted first. The
    // launcher's Wrapper renders one hidden Image per entry here; this list is
    // the bookkeeping, those Images are the memory.
    //
    // Seeded with the visible rows when the picker opens, then moved along by
    // whatever asks for an image: a row rendering, or the reader landing on an
    // entry. So browsing DOWN the list in the reader keeps pulling entries in,
    // and -- because entries are only pushed to the front, never dropped on the
    // way past -- turning around and going back up finds them all still warm.
    // A window of immediate neighbours cannot do that; it forgets everything the
    // moment you leave it, which is exactly when you are most likely to return.
    //
    // Bounded by count rather than a clock. These are capped at the reader's box
    // size (at most ~968x640), so a count is already a bound on memory -- worst
    // case around 25MB, typically far less -- and a timer would either expire
    // mid-browse or keep holding pictures long after the launcher closed.
    readonly property int retainMax: 10

    // FIXED SLOTS, not a most-recent-first list. `retained[i]` is whatever is
    // held in slot i, and a slot's occupant changes only when that particular
    // picture is evicted -- every other slot keeps pointing exactly where it
    // did.
    //
    // The Wrapper renders one warm-copy delegate per SLOT (a constant count),
    // so no retain can create or destroy a delegate. It used to render one per
    // ENTRY off this array, and this array was reassigned on every retain() to
    // move the touched entry to the front -- which is a different array, so a
    // Repeater over it destroyed and rebuilt all ten delegates (twenty Images,
    // and on two monitors twice that) several times per keystroke. That was
    // the typing freeze: measured 12 retains and 336 config warnings per
    // keystroke in the picker, ~90ms of the ~150ms stall.
    property var retained: []

    // The same entries, most-recently-wanted first. Mutated IN PLACE and bound
    // to by nothing, which is the point: bumping recency is the common case
    // (every row that renders, every reader move) and it must cost nothing.
    // Read only to decide which slot to overwrite.
    property var retainOrder: []

    // Decode size for the row thumbnails, shared by the delegate that draws them
    // and the launcher that holds them warm. ONE definition on purpose: it is
    // half of the pixmap cache key, so two copies that drifted would mean the
    // launcher warming an entry the list never asks for -- and it would fail
    // silently, since a miss just looks like a slow row.
    //
    // A flat number rather than the icon slot's measured 1em advance, which is
    // what this used to be. sourceSize is only a decode hint, so it does not
    // have to equal the layout; making it a constant drops a font metric out of
    // a cache key and lets the launcher warm these before any row exists to
    // measure. 96 covers the ~42px slot at 2x with room to spare, and costs 37KB.
    readonly property int thumbSize: 96

    function retain(entry: var): void {
        if (root.noCache || !entry?.isImage || !entry.entryId)
            return;

        const order = root.retainOrder;
        const at = order.indexOf(entry);
        if (at === 0)
            return;
        if (at > 0) {
            // Already held: this is pure recency bookkeeping, so it must not
            // touch `retained` at all.
            order.splice(at, 1);
            order.unshift(entry);
            return;
        }

        order.unshift(entry);
        const next = root.retained.slice();
        if (next.length < root.retainMax) {
            next.push(entry);
        } else {
            // Take over the least-recently-wanted picture's slot. One slot
            // changes; the other nine delegates never learn anything happened.
            const lru = order.pop();
            const slot = next.indexOf(lru);
            next[slot >= 0 ? slot : 0] = entry;
        }
        root.retained = next;
    }

    function seedRetained(): void {
        if (root.noCache)
            return;
        for (const e of root.preloadEntries.slice().reverse())
            root.retain(e);
    }

    // Thumbnails cannot load until the entry has been decoded to its file, and
    // that is normally done per row by ClipItem -- which only runs once the row
    // exists, i.e. too late to help the first paint. One sh for the whole
    // preload set instead of a process per entry, and `test -s` makes it a no-op
    // for everything already on disk, which after the first use is all of it.
    function preloadDecode(): void {
        if (root.noCache || preloadProc.running)
            return;
        const raws = root.preloadEntries.map(e => e.raw);
        if (raws.length === 0)
            return;
        preloadProc.lines = raws;
        preloadProc.running = true;
    }

    // False until the preload set is known to be on disk. The launcher's warm
    // copies wait for it: an Image will not retry a url that was missing when it
    // first tried, so pointing them at files preloadDecode() has not written yet
    // would silently leave them empty for the whole session.
    property bool preloadReady: false

    Process {
        id: preloadProc

        property var lines: []

        onExited: root.preloadReady = true

        command: ["sh", "-c", `for l in "$@"; do id=\${l%%	*}; f=/tmp/caelestia-clip-preview-$id.png; test -s "$f" || printf '%s' "$l" | cliphist decode > "$f"; done`, "preload", ...preloadProc.lines]
    }

    // Raw `cliphist list` lines, newest first.
    property var rawEntries: []
    readonly property list<QtObject> entries: variants.instances

    // Lowercased preview text, parallel to rawEntries. Rebuilt only when
    // rawEntries changes, so a keystroke costs one pass of String.includes and
    // no per-entry work.
    readonly property var searchKeys: root.rawEntries.map(line => {
        const tab = line.indexOf("\t");
        return (tab >= 0 ? line.slice(tab + 1) : line).toLowerCase();
    })

    // Raw line -> entry object.
    //
    // Variants.instances is in CREATION order, not model order: on reload it
    // reuses the existing instances and appends only the new ones. So a fresh
    // clip sits at rawEntries[0] while its instance is last, and indexing into
    // instances with a rawEntries index silently returned a DIFFERENT entry --
    // the list rendered the old items in the old order and new clips never
    // showed up until a shell restart rebuilt every instance in model order.
    // Resolve entries by their raw line instead of by position.
    readonly property var entryFor: {
        const map = {};
        for (const e of root.entries)
            map[e.raw] = e;
        return map;
    }

    // entryId -> { lines, chars } of the DECODED content (list previews flatten
    // newlines, so real counts only exist after a decode). Filled incrementally
    // by lineCountProc in the background; also updated exactly by the reader's
    // own decodes via cacheDecoded(). Reassigned (never mutated) so desc
    // bindings react.
    property var lineCounts: ({})

    // Testing switch: true makes every reader open take the cold path -- no text
    // reuse, no image decode reuse, no pixmap reuse, no prefetch. Only useful
    // for watching the uncached path deliberately; the reader's transition is
    // built on this being false.
    readonly property bool noCache: false

    // entryId -> decoded text (single trailing newline stripped), shared by the
    // reader across open/close so browsing back to an entry is instant.
    //
    // Never invalidated, because a cliphist entry is IMMUTABLE: ids are handed
    // out in sequence and content is only ever added, never rewritten in place
    // (re-copying something identical dedupes to a NEW id). So a decode is good
    // for as long as the id exists, and the only reason to drop one is memory.
    property var decodedText: ({})

    // Bumped whenever decodedText gains an entry. The map is MUTATED in place
    // (see cacheDecoded), which emits no change signal at all -- fine for the
    // old reader, which only ever read the cache at the moment it staged an
    // entry, but not for the rail: a preloaded neighbour is already on screen
    // when its prefetch lands, so it has to be told. Every ClipBody watches this
    // and re-reads its own key.
    //
    // A counter rather than reassigning decodedText: that map holds up to
    // cacheBudget of strings, and copying it on every decode would make the
    // prefetch quadratic in the size of the window it is filling.
    property int decodeGeneration: 0

    // Warm the FULL-RESOLUTION copy for every entry on the rail, not just the
    // one that gets zoomed. Off by default and deliberately not in shell.json:
    // the box-sized decode is ~1.6MB against ~33MB at 4K, on the single Qt
    // decode thread the row thumbnails also queue on, so seven of them would
    // make the list paint slower -- the opposite of what the rail is for. Here
    // to be flipped and felt, not to be shipped on.
    readonly property bool eagerHiRes: false

    // Insertion order of decodedText, oldest first. Only reason this exists is
    // the budget below -- JS objects do not keep insertion order for the
    // numeric-looking keys cliphist hands out, so it cannot be recovered from
    // decodedText itself.
    property var cacheOrder: []
    property int cacheChars: 0
    // Prefetch pulls in entries that were never opened, and a clipboard happily
    // holds megabyte pastes -- a 750-entry history could otherwise sit on
    // hundreds of MB of strings that nothing will ever read again.
    readonly property int cacheBudget: 8 * 1024 * 1024

    function cacheDecoded(entryId: string, text: string): void {
        if (!root.noCache && root.decodedText[entryId] === undefined) {
            root.decodedText[entryId] = text;
            root.cacheOrder.push(entryId);
            root.cacheChars += text.length;
            // Oldest out first. Never down to empty: the entry just decoded is
            // the one about to be read, and on a single paste over budget this
            // would otherwise evict it immediately and decode it again.
            while (root.cacheChars > root.cacheBudget && root.cacheOrder.length > 1) {
                const old = root.cacheOrder.shift();
                root.cacheChars -= root.decodedText[old]?.length ?? 0;
                delete root.decodedText[old];
            }
            root.decodeGeneration++;
        }
        const counts = Object.assign({}, root.lineCounts);
        // Counted by scanning for newlines rather than split().length: the
        // array split() builds is a second full copy of the entry, allocated
        // and thrown away purely to read its length. On a megabyte entry that
        // is measurable on the GUI thread, and it happens on every decode.
        let lines = 1;
        for (let p = text.indexOf("\n"); p >= 0; p = text.indexOf("\n", p + 1))
            lines++;
        counts[entryId] = {
            lines: text.length ? lines : 1,
            chars: text.length
        };
        root.lineCounts = counts;
    }

    // -- prefetch --
    //
    // The reader's transition is only instant if the text is already there when
    // the key is pressed, so decode around the highlight before it is asked for.
    // Entries being immutable (see decodedText) is what makes this safe to do
    // eagerly: there is no invalidation, a prefetch is either wasted or a hit.
    //
    // One entry per process, worked through in order, because the alternative --
    // one sh emitting many entries - needs framing for content that contains
    // every possible delimiter. Order is the whole value here anyway: the queue
    // is REPLACED on every move, so changing direction re-prioritises instantly
    // instead of draining a stale window first.
    property var prefetchQueue: []

    function prefetch(entries: var): void {
        if (root.noCache)
            return;
        const q = [];
        const seen = {};
        for (const e of entries) {
            if (!e)
                continue;
            const id = e.entryId;
            if (!id || seen[id])
                continue;
            seen[id] = true;
            // Images are precached per row by ClipItem, which sees exactly what
            // is on screen; binaries are never read as text.
            if (e.isImage || e.binMatch || root.decodedText[id] !== undefined)
                continue;
            q.push(e);
        }
        root.prefetchQueue = q;
        root.pumpPrefetch();
    }

    function pumpPrefetch(): void {
        while (root.prefetchQueue.length > 0) {
            if (prefetchProc.running)
                return;
            const e = root.prefetchQueue[0];
            root.prefetchQueue = root.prefetchQueue.slice(1);
            // May have been decoded by the reader itself while queued.
            if (!e.entryId || root.decodedText[e.entryId] !== undefined)
                continue;
            prefetchProc.entryId = e.entryId;
            prefetchProc.line = e.raw;
            prefetchProc.running = true;
            return;
        }
    }

    // One background sh for ALL uncounted entries (not a process per row):
    // decodes each unknown non-binary entry and emits "id\tlines\tchars".
    // Chars count the reader's display convention (one trailing newline
    // stripped), so list and reader always agree.
    function updateLineCounts(): void {
        if (lineCountProc.running)
            return;
        lineCountProc.known = " " + Object.keys(root.lineCounts).join(" ") + " ";
        lineCountProc.running = true;
    }

    function reload(): void {
        listProc.running = true;
    }

    // The history read now and applied later: the reader's return folds a
    // clip copied inside it into its own cascade (ContentList.exitReader),
    // which needs the new list the moment the exit starts, not a process
    // round trip after it. Null until read, and again once applied.
    property var stagedEntries: null

    function stage(): void {
        stagedEntries = null;
        stageProc.running = false;
        stageProc.running = true;
    }

    function applyStaged(): bool {
        if (!stagedEntries)
            return false;
        root.rawEntries = stagedEntries;
        stagedEntries = null;
        root.updateLineCounts();
        return true;
    }

    function transformSearch(text: string): string {
        return text.slice(GlobalConfig.launcher.clipboardPrefix.length);
    }

    // Substring match, NOT fuzzy: clipboard entries are arbitrary prose/code, so
    // a fuzzy subsequence match hits almost everything and ranks it by a score
    // that carries no meaning here. Results stay in cliphist order (newest
    // first), which is the useful order for a clipboard.
    //
    // Matched in JS rather than through the C++ Search because those take a
    // QStringList: every keystroke would marshal all previews (~1MB) into C++.
    // Testing the precomputed lowercase keys in place avoids that entirely.
    function query(text: string): var {
        const q = transformSearch(text).trim().toLowerCase();
        const out = [];
        for (let i = 0; i < root.rawEntries.length; i++) {
            if (q && !root.searchKeys[i].includes(q))
                continue;
            const entry = root.entryFor[root.rawEntries[i]];
            if (entry)
                out.push(entry);
        }
        return out;
    }

    function activate(line: string): void {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "clip", line]);
    }

    function deleteEntry(line: string): void {
        delProc.line = line;
        delProc.running = true;
    }

    // -- classification, on demand --
    //
    // An entry's icon and swatch colour are looked up through here rather than
    // being bindings declared on ClipEntry itself.
    //
    // Creating an entry evaluates every binding it declares, and the entries are
    // all created at once, synchronously, the moment `cliphist list` returns.
    // So a classifier binding ran the whole regex battery below 750 times inside
    // that one turn -- measured at 62ms, of which 43ms was iconFor -- and it was
    // paid on the FIRST LAUNCHER OPEN of a session, whether or not the clipboard
    // picker was ever asked for. Opening the launcher to start an app has no
    // business classifying a clipboard.
    //
    // Now only entries that actually render pay, and each pays once. Memoised by
    // id and never invalidated, for exactly the reason decodedText is not: a
    // cliphist entry is immutable, ids are handed out in sequence, and content
    // is only ever added, never rewritten in place.
    //
    // The cache is MUTATED, never reassigned -- that emits no change signal, so
    // a binding that calls in here cannot loop through it.
    property var classifyCache: ({})

    function classify(entry: var): var {
        // Falls back to the raw line for an entry cliphist gave no id, which is
        // the only key left that identifies it.
        const key = entry.entryId || entry.raw;
        let v = root.classifyCache[key];
        if (v === undefined) {
            v = {
                icon: entry.binMatch ? root.iconForBinary(entry.binMatch[1]) : root.iconFor(entry.preview),
                colour: entry.binMatch ? "" : root.colourOf(entry.preview)
            };
            root.classifyCache[key] = v;
        }
        return v;
    }

    function iconOf(entry: var): string {
        return entry ? root.classify(entry).icon : "content_paste";
    }

    // Non-empty when the entry is a lone colour, so the delegate paints a
    // swatch. Named for the entry to keep it clear of colourOf(), which is the
    // string parser this calls into.
    function colourEntryOf(entry: var): string {
        return entry ? root.classify(entry).colour : "";
    }

    // Content-aware Material Symbol for a clipboard entry. FIRST MATCH WINS, so
    // rules are ordered by signal strength: high-entropy secrets/identifiers →
    // network addresses → encoded blobs → Claude Code / AI-session capture →
    // shell-prompt capture → shell/security/build commands → SOC/IDS/DFIR →
    // URLs/mail/hosts → data/code/markup → files/paths → everyday → structural
    // fallback. Commands are matched before URLs so a URL passed as an argument
    // (curl/gobuster) can't hijack the icon; the AI-session and shell-prompt
    // captures sit ahead of the command taxonomy so a whole captured screen reads
    // as one thing rather than being hijacked by an embedded tool name / path.
    // Cybersecurity-leaning but everyday-complete.
    //
    // Called once per entry (stable binding), but clipboard lines can be enormous
    // (`-preview-width 999`, which cuts a preview at 999 chars and appends a
    // trailing '…'), so a length guard short-circuits huge pastes before
    // the full battery runs, and every pattern is anchored/linear (no nested
    // quantifiers) to stay ReDoS-safe on adversarial content.
    function iconFor(text: string): string {
        // Strip a Claude Code bash-mode "! " prefix so "! sudo pacman ..." is
        // classified as the command it runs, not as prose.
        const bashMode = /^!\s+(?=[\w~./])/.test(text.trim());
        const t = text.trim().replace(/^!\s+(?=[\w~./])/, "");
        if (!t)
            return "content_paste";

        // After the bash-mode prefix is stripped, a path-shaped remainder is the
        // command being run (e.g. "! ./run.sh"), not a file reference.
        if (bashMode && /^(?:\.\.?\/|~?\/)\S/.test(t))
            return "terminal";

        // Giant blob: skip the battery, keep only three cheap probes.
        if (t.length > 20000) {
            if (/https?:\/\//i.test(t))
                return "link";
            if (/^\s*[{[]/.test(t) && /[}\]]\s*$/.test(t))
                return "data_object";
            return "notes";
        }

        const oneLine = !/\n/.test(t);

        // A Claude Code / TUI capture glyph can prefix a copied line ("⎿ ", "● ",
        // "> ", "+ "). Stripped only for the anchored secret probes below, so a key
        // pasted out of a transcript still reads as a secret rather than as the
        // session capture the leading glyph would otherwise trigger.
        const unglyph = t.replace(/^(?:⎿|●|>|\+)\s+/, "");

        // Extension → icon for a filename token; "" when the extension is unknown.
        const extIcon = s => {
            if (/\.(?:png|jpe?g|gif|bmp|webp|tiff?|svg|ico|heic|avif)$/i.test(s))
                return "image";
            if (/\.(?:mp3|flac|wav|ogg|opus|aac|m4a|wma|aiff?)$/i.test(s))
                return "music_note";
            if (/\.(?:mp4|mkv|mov|avi|webm|flv|wmv|m4v|mpe?g)$/i.test(s))
                return "movie";
            if (/\.(?:zip|tar|gz|xz|bz2|7z|rar|zst|lz4|tgz|cab|iso)$/i.test(s))
                return "folder_zip";
            if (/\.pdf$/i.test(s))
                return "picture_as_pdf";
            if (/\.(?:docx?|odt|rtf|pages)$/i.test(s))
                return "description";
            if (/\.(?:xlsx?|ods|csv|tsv|numbers)$/i.test(s))
                return "table";
            if (/\.(?:pptx?|odp|key)$/i.test(s))
                return "slideshow";
            if (/\.(?:exe|msi|dmg|deb|rpm|appimage|apk|pkg|flatpak|snap)$/i.test(s))
                return "deployed_code";
            if (/\.(?:py|js|mjs|cjs|ts|mts|cts|tsx|jsx|c|cpp|cc|h|hpp|rs|go|rb|php|java|kt|swift|sh|lua|pl|sql|qml|vue|svelte|html?|xhtml|css|scss)$/i.test(s))
                return "folder_code"; // a source-file reference (path/filename), distinct from a pasted code snippet
            if (/\.(?:json|jsonl|ndjson|ya?ml|toml|ini|conf|cfg|env|xml|ovpn|nix)$/i.test(s))
                return "settings";
            if (/\.(?:patch|diff)$/i.test(s))
                return "difference";
            if (/\.(?:srt|ass|vtt)$/i.test(s))
                return "subtitles";
            if (/\.torrent$/i.test(s))
                return "download";
            if (/\.(?:txt|md|log)$/i.test(s))
                return "description";
            if (/\.(?:pcap|pcapng|cap)$/i.test(s))
                return "network_check"; // packet capture
            if (/\.(?:evtx|etl|dmp|mdmp|mem|vmem|vmsn|e01|ex01|aff|aff4|lime|img|raw|dd|vhdx?|vmdk|qcow2|vdi)$/i.test(s))
                return "storage"; // memory / disk / event-log forensic image
            if (/\.(?:dat|bak|old|tmp|bin|dll|sys|so|lnk|db|sqlite|jar|class|pyc|ko|efi|vacb|swp|orig|rej|lock|pid|service|desktop|timer|socket|gguf|safetensors|onnx)$/i.test(s))
                return "draft"; // generic / opaque file (incl. forensic dump names like .vacb, model weights)
            return "";
        };

        // True when the words after a command name read as an English sentence
        // ("grep is a tool that ...", "caelestia shell is laggy after the update",
        // "kill the process and restart it", "cliphist vs clipman", "hyprctl
        // dispatch not working") and carry no shell shape. Quoted arguments are
        // dropped first, so "grep -rn "is not" src/" is judged on its flags.
        const proseArgs = rest => {
            const r = rest.replace(/(?:^|\s)(["'])[^"'\n]*\1(?=\s|$)/g, " ");
            // A verb, a contraction (apostrophe optional: "cant", "wont") or vs as the
            // first or second word.
            const verb = /^\s+(?:\S+\s+)?(?:is|are|was|were|isn'?t|aren'?t|wasn'?t|weren'?t|has|have|had|does|doesn'?t|did|didn'?t|don'?t|can'?t|won'?t|keeps|kept|feels|felt|seems|looks|crashes|crashed|freezes|froze|lags|lagged|broke|vs|versus)(?=\s|[,.!?](?!\w)|$)/i;
            // A conjunction / adverb / modal / present-tense verb as the first word.
            const opener = /^\s+(?:and|or|but|not|still|also|never|always|really|can|could|should|would|will|works|worked|breaks|stopped|started|needs|uses|using|takes|gets|got)(?=\s|[,.!?](?!\w)|$)/i;
            // A lowercase verb saying what the command does, with more words after it
            // and no dotted file or dir/ among them ("sed replaces text in files",
            // "nmap scans the target network"; not "rg updates src/").
            const describes = /^\s+(?:replaces|searches|changes|makes|creates|deletes|removes|lists|shows|prints|finds|counts|copies|moves|displays|returns|runs|opens|reads|writes|lets|allows|helps|means|handles|converts|extracts|downloads|installs|updates|sends|checks|prevents|filters|outputs|turns|does|scans|enumerates|dumps|fuzzes|sweeps|probes|automates|cracks|captures|sniffs|intercepts|exploits)\s+[a-z]/.test(r) && !/\w[.\/]\w|\w\//.test(r);
            // "not" or a failure verb as the second word ("hyprpm update failed"; as the
            // first it may be a search pattern: "grep failed auth.log"), or a negated
            // verb anywhere ("... not showing", "... doesnt work").
            const negated = /^\s+\S+\s+(?:not|failed|fails)(?=\s|[,.!?](?!\w)|$)|(?:^|\s)(?:(?:does|is|did|do|are|was|were)n'?t|not\s+[a-z]+ing)(?=\s|[,.!?](?!\w)|$)/i;
            // Two or more sentence words: articles, pronouns, auxiliaries -- not
            // prepositions, which CLI grammars use ("ufw allow in on eth0").
            const sentence = (r.match(/(?:^|\s)(?:the|a|an|and|or|but|is|are|was|were|be|been|it|its|i|me|my|you|your|we|our|they|them|their|he|she|his|him|her|this|that|these|those|not|so|if|when|then|than|can|will|do|does|did|have|has|how|what|why|just|too|again|please|very|really|also|there)(?=\s|[,.!?](?!\w)|$)/gi) || []).length >= 2;
            // A flag, path, pipe, &&, file redirect, VAR=value, $VAR or escaped space.
            const shell = /(?:^|\s)(?:--?[A-Za-z]|[~.]{0,2}\/)|(?:^|\s)\|{1,2}\s*\S|&&|\s[12&]?>{1,2}\s*(?:[\/~&$]|[\w-]+\.\w)|\w=\S|\$[A-Za-z_{(]|\\\s/;
            return (verb.test(r) || opener.test(r) || describes || negated.test(r) || sentence) && !shell.test(r);
        };
        // The argument list after an English-word command is a plain run of 2+
        // lowercase words with no CLI token (no flag, path, digit, version, $VAR),
        // so "snap a pic", "go clean my room", "service charge included" read as
        // to-do prose rather than "<tool> <subcommand> <args>".
        const proseWords = rest => /^\s+[a-z]+(?:\s+[a-z]+)+$/i.test(rest);
        // The same run carrying a sentence word ("go get groceries after school",
        // "poetry show at the library"), unlike a package list after a subcommand
        // ("yarn add react axios", "go mod init hello").
        const chatWords = rest => proseWords(rest) && /\s(?:the|a|an|my|your|his|her|our|their|to|of|in|on|at|for|with|after|before|from|and|or|some|this|that|it|me|him|them|us|up|out|home|now|later|first|fast|again|soon|tonight|today|tomorrow)(?=\s|$)/i.test(rest);

        // -- secrets: keys, certs, tokens --
        if (/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/.test(t))
            return "vpn_key"; // PEM private key
        if (/-----BEGIN (?:CERTIFICATE|PUBLIC KEY)-----/.test(t))
            return "verified_user"; // cert / public key
        if (/-----BEGIN PGP (?:MESSAGE|SIGNATURE|SIGNED)/.test(t))
            return "enhanced_encryption"; // PGP block
        if (/^(?:ssh-(?:rsa|dss|ed25519)|ecdsa-sha2-\S+|sk-ssh-\S+)\s+[A-Za-z0-9+/]{20,}/.test(unglyph))
            return "vpn_key"; // SSH public key (also after a leading capture glyph)
        if (/^eyJ[\w-]+\.[\w-]+\.[\w-]+$/.test(unglyph) || /^eyJ[\w-]{8,}\.eyJ[\w-]*(?:\.[\w-]*)?…$/.test(unglyph))
            return "token"; // JWT (second form: cliphist truncated it at 999 chars with a trailing …; also after a capture glyph)
        if (/\b(?:AKIA|ASIA|AIza)[0-9A-Za-z]{16,}\b/.test(t) || /\b(?:gh[posru]|glpat)[-_][A-Za-z0-9_-]{20,}\b/.test(t) || /\b(?:sk|pk|rk)-[A-Za-z0-9]{20,}\b/.test(t) || /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/.test(t))
            return "key"; // AWS / Google / GitHub / GitLab / Stripe / OpenAI / Slack
        if (oneLine && /^(?:export\s+)?[\w.]*(?:PASS(?:WORD|WD)?|SECRET|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY|CREDENTIAL)[\w.]*\s*[:=]\s*\S/i.test(unglyph))
            return "password"; // secret assignment (keyword anywhere in the name, incl. at its start; also after a leading capture glyph)

        // -- vulnerability / hashes --
        if (/\bCVE-\d{4}-\d{3,}\b/i.test(t))
            return "coronavirus";
        if (/^\$(?:2[aby]|argon2(?:id|i|d)?|6|5|1|y)\$/.test(t))
            return "enhanced_encryption"; // bcrypt / argon2 / shadow crypt
        if (/^[^:\s]+:\$?\d*:?[0-9a-f]{32}:[0-9a-f]{32}:?/i.test(t))
            return "fingerprint"; // NTLM / SAM dump line
        if (/^(?:sha(?:1|256|512)|md5)?[:=]?\s*[a-f0-9]{128}$/i.test(t) || /^[a-f0-9]{64}$/i.test(t) || /^[a-f0-9]{40}$/i.test(t) || /^[a-f0-9]{32}$/i.test(t))
            return "fingerprint"; // SHA-512/256/1 / MD5
        if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(t))
            return "badge"; // UUID / GUID (an identifier, not a content hash)

        // -- network addresses (anchored: an IP inside a command must not hijack it) --
        if (/^(?:bc1[a-z0-9]{23,59}|[13][1-9A-HJ-NP-Za-km-z]{25,39})$/.test(t) || /^0x[a-f0-9]{40}$/i.test(t) || /^[LM][a-km-zA-HJ-NP-Z1-9]{26,33}$/.test(t))
            return "currency_bitcoin"; // BTC / ETH / LTC address
        if (/^0x[0-9a-f]{8,16}$/i.test(t))
            return "memory"; // lone kernel / pool memory address or offset (DFIR)
        if (/^(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(t))
            return "settings_ethernet"; // MAC
        if (/^(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?(?:\/\d{1,2})?$/.test(t))
            return "lan"; // IPv4 / socket / CIDR
        if (/^[0-9a-f:]+$/i.test(t) && /:/.test(t) && (/::/.test(t) || /[a-f]/i.test(t) || (t.match(/:/g) || []).length >= 3))
            return "lan"; // IPv6-ish (must contain a colon, plus "::"/hex-letter/3+ colons — so H:M:S times and colon-less hex like an IBAN fall through)

        // -- encoded blobs --
        if (/^H4sI[A-Za-z0-9+/]{8,}={0,2}$/.test(t))
            return "folder_zip"; // gzip stream, base64-encoded (magic 1f 8b -> "H4sI")
        if (oneLine && /^[A-Za-z0-9+/_-]{64,}={0,2}$/.test(t) && /[A-Z]/.test(t) && /[a-z]/.test(t) && /\d/.test(t) && !(/[+/]/.test(t) && /[_-]/.test(t)) && (t.match(/[+/_-]/g) || []).length <= Math.max(5, t.length / 12) && !/^\/(?:home|tmp|usr|var|etc|opt|run|mnt|media|srv|root|snap|proc|sys|dev|boot|lib|Users|Volumes|Applications|Library|System)\//.test(t))
            return "data_array"; // base64 / base64url blob (needs the full class mix and random-looking symbol density: all-lowercase /tmp/<sha256> paths, deep directory paths and snake/kebab slugs fall through; so does anything under a known absolute root like /home/)
        if (oneLine && /^(?:[^%\s]*%[0-9A-Fa-f]{2}){3,}[^%\s]*$/.test(t) && !/^[a-z][\w+.-]*:\/\//i.test(t) && !/^\?/.test(t) && !extIcon(t))
            return "data_array"; // percent-encoded payload (3+ %XX, no whitespace, no URL scheme; a ?query string or an encoded filename goes to its own rule)
        if (/^[0-9a-f]{62}$/i.test(t))
            return "fingerprint"; // JARM TLS fingerprint (62 hex — before the hex-dump rule)
        if (oneLine && /^(?:[0-9a-f]{2}[\s:]?){24,}$/i.test(t))
            return "memory"; // raw hex dump
        if (oneLine && /^(?:0x)?[0-9a-fx]{2}(?:[\s:|][0-9a-fx]{2}){2,}\|?$/i.test(t))
            return "memory"; // short packet byte-string / content bytes (A0 03 02 01 17, XX placeholders)

        // -- Claude Code / AI-assistant TUI capture. Keyed on literal Claude Code
        //    screen strings, never on the ❯ input glyph alone (which is also a
        //    shell prompt). Placed before the shell-prompt rule so a captured ❯
        //    message reads as an assistant session, and after the secret/hash/
        //    address/blob rules so a key pasted into a transcript still wins. --
        if (/Claude Code v\d|^Using (?:Opus|Sonnet|Haiku|Fable) \d+(?:\.\d+)? \(|\/clear to save|⏵⏵|auto mode classifier|⎿|\bRan \d+ (?:shell|bash) commands?\b|\bRan skill\/|\[Image #\d+\]|… \+\d+ lines|… \d+ more lines|\bUpdated \S+ \(\+\d+ -\d+\)|\(ctrl\+[a-z] to (?:expand|run in background|hide|show)\)|\(shift\+tab to cycle\)|for (?:\d+m )?\d+s (?:[·-] done|· ↓)|[✻✢✽✶✳] [A-Z][a-zé]+(?:…|ed for \d)|─{8}\s*❯|^[A-Za-z0-9Ѐ-ӿ](?:[^─]*[?.!]|[^─\s]*(?:\s+[^─\s]+){2,}) ─{20,}$/.test(t))
            return "smart_toy"; // banner "Using <model> <ver> (", exact "(ctrl+x to expand)"-style hints, spinner/done lines, or a message ending in the input box's ─ border: it opens with a letter or digit and ends a sentence or runs 3+ words, so a "// ──" / "# Title ──" divider is not one

        // -- shell prompt capture: a pasted terminal line (leading powerline glyph,
        //    user@host:path ending in a prompt char, or PowerShell prompt). Placed
        //    before the tool taxonomy so the whole line reads as "terminal" instead
        //    of being hijacked by an embedded tool name / URL / path. --
        if (/^(?:[◄❯➜▶►◆»◀○◎⋈]\s|┌──\(|└─|[\w.+-]+@[\w.:~/\[\]+-]*[$#%]\s|PS [A-Za-z]:\\)/.test(t))
            return "terminal";

        // -- security tooling & shell commands (before URLs: a URL arg must not hijack) --
        if (/(?:^|\|\s*|;\s*|&&\s*)(?:bash|sh)\s+-[a-z]*i[a-z]*\s+.*(?:>\s*&\s*)?\/dev\/(?:tcp|udp)\//i.test(t) || /\bnc\b.*-[a-z]*e[a-z]*\s+\/bin\//i.test(t) || /\b(?:rm\s+-rf\s+\/(?:\s|$)|chmod\s+(?:-R\s+)?777|:\(\)\s*\{\s*:\|:)/.test(t))
            return "warning"; // reverse shell / destructive / fork bomb
        // Security tooling is case-sensitive (a lowercase tool name is the command;
        // a capitalised one is a proper noun -- "John", "Hydra", "Argus") and takes
        // a proseArgs guard so a sentence built from the lowercase word ("responder
        // is on the way", "strings are immutable in python") is not classified.
        // A flag-and-file tool whose name is an English word or first name (john,
        // crunch, hydra, strings, ...) also needs something CLI-shaped once it has
        // two or more arguments: a flag, path, file.ext / IP, URL, VAR=, $VAR, pipe,
        // redirect, @-pattern or a leading number ("crunch 8 8 abc"). Short notes
        // with fewer than two sentence words slip past proseArgs otherwise
        // ("crunch time before the exam", "john at the office today").
        const secTool = m => {
            if (!m || proseArgs(t.slice(m[0].length)))
                return false;
            const rest = t.slice(m[0].length);
            return !(/(?:^|\s)(?:john|hydra|medusa|reaver|crunch|fierce|snort|argus|responder|beef|empire|sliver|strings|foremost|havoc|nuclei|amass|bloodhound|rita|arjun)$/.test(m[0]) && /^\s+\S+\s+\S/.test(rest) && !/^\s+\d/.test(rest) && !/(?:^|\s)-{1,2}\w|[\/=$|<>@\\]|\S\.\w/.test(rest))
                // amass / fierce never take a bare single word (they need a subcommand
                // or --domain), so "amass wealth" / "fierce competitor" are prose.
                && !(/(?:^|\s)(?:amass|fierce)$/.test(m[0]) && /^\s+[a-z]+$/.test(rest) && !/^\s+(?:enum|intel|db|viz|track|dns|subs)$/.test(rest));
        };
        const rec =/^(?:sudo\s+)?(?:nmap|masscan|rustscan|zmap|amass|subfinder|assetfinder|shodan|dnsrecon|dnsenum|fierce|theharvester|whatweb|wafw00f)\b/.exec(t);
        if (secTool(rec))
            return "radar"; // recon / scanning
        if (/^(?:Starting Nmap \d+\.\d|Nmap scan report for (?:\d{1,3}(?:\.\d{1,3}){3}|[\w-]+(?:\.[\w-]+)+)|Nmap done: \d+ IP)/.test(t))
            return "radar"; // pasted nmap output (the rule above wants the lowercase command)
        const cap = /^(?:sudo\s+)?(?:tshark|tcpdump|wireshark|ngrep|termshark|dumpcap|tcpflow|bettercap|ettercap|arpspoof|mitmproxy|mitmdump)\b/.exec(t);
        if (secTool(cap))
            return "network_check"; // packet capture / MITM
        const nsm = /^(?:sudo\s+)?(?:snort|suricata|suricatasc|zeek|zeekctl|zeek-cut|broctl|chaosreader|joincap|capinfos|editcap|mergecap|reordercap|tcpick|nfdump|rita|argus|rwfilter|rwstats|stenographer|arkime)\b/.exec(t);
        if (secTool(nsm))
            return "sensors"; // NSM sensors / traffic analysis (Snort, Suricata, Zeek, ...)
        const crk = /^(?:sudo\s+)?(?:hashcat|john|hydra|medusa|ncrack|patator|hcxdumptool|aircrack-ng|airmon-ng|reaver|cewl|crunch)\b/.exec(t);
        if (secTool(crk))
            return "password"; // credential cracking / wireless
        if (/^(?:Hydra v\d[\d.]* \(c\)|John the Ripper \d+\.\d|Using default input encoding: \S+ Loaded \d+ password hash)/.test(t))
            return "password"; // pasted Hydra / John output
        const wfz = /^(?:sudo\s+)?(?:gobuster|feroxbuster|ffuf|dirb|dirbuster|wfuzz|nikto|wpscan|sqlmap|nuclei|arjun|dalfox|commix|xsstrike)\b/.exec(t);
        if (secTool(wfz))
            return "travel_explore"; // web fuzzing / vuln scan
        if (/^(?:=+\s+)?Gobuster v\d+\.\d+(?:\.\d+)? by OJ Reeves/.test(t))
            return "travel_explore"; // pasted gobuster banner
        const expl = /^(?:sudo\s+)?(?:msfconsole|msfvenom|msfdb|meterpreter|searchsploit|setoolkit|beef|empire|sliver|havoc|cobaltstrike)\b/.exec(t);
        if (secTool(expl))
            return "bug_report"; // exploitation / C2 frameworks
        const adt = /^(?:sudo\s+)?(?:enum4linux|netexec|crackmapexec|impacket-\S+|responder|bloodhound|sharphound|evil-winrm|smbclient|smbmap|rpcclient|ldapsearch|kerbrute|certipy|mimikatz|secretsdump)\b/.exec(t);
        if (secTool(adt))
            return "security"; // AD / lateral movement / post-exploitation
        const rev = /^(?:sudo\s+)?(?:gdb|radare2|r2|objdump|readelf|strace|ltrace|checksec|pwndbg|ropper|ROPgadget|volatility3?|binwalk|foremost|steghide|zsteg|exiftool|strings)\b/.exec(t);
        if (secTool(rev))
            return "biotech"; // reversing / forensics / stego
        if (/^(?:sudo\s+)?(?:(?:mkdir|cd)\s+[\w.~\/-]+\s*(?:;|&&)?\s+)?(?:python3?\s+)?(?:vol(?:\.py|3)?|volatility3?)\s+-f\s/.test(t))
            return "biotech"; // Volatility memory-forensics run (needs a target after -f); only a real connector may lead it (sudo, "mkdir x" / "cd x" with or without ;/&&, then optionally python3), never arbitrary words
        if (/^(?:sudo\s+)?python3?\s+(?:-c\s|-m\s+\S|\S+\.py\b)/.test(t))
            return "terminal"; // running a Python script / module / -c one-liner
        const rmt = /^(?:sudo\s+)?(?:ssh|scp|sftp|rsync|nc|ncat|socat|telnet|mosh)\b/.exec(t);
        if ((rmt && !proseArgs(t.slice(rmt[0].length))) || /^(?:ssh|telnet):\/\//i.test(t))
            return "terminal"; // remote / transfer (case-sensitive command names, prose guard)
        const htc = /^(?:sudo\s+)?(?:curl|wget|httpie|xh|aria2c)\b/.exec(t);
        // httpie's bare `http`/`https` verb is case-sensitive (so "HTTP request
        // smuggling" is not it) and must be followed by a request shape: a :PORT, an
        // uppercase METHOD, a host/path, or a bare host (localhost, an IP, a dotted
        // domain) that ends the line or is followed by a request item / flag -- and
        // never a sentence ("http traffic is unencrypted", "http target.htb
        // redirects to login").
        if ((htc && !proseArgs(t.slice(htc[0].length))) || (/^https?\s+(?::\d|[A-Z]+\s|[\w.-]+(?::\d+)?\/|(?:localhost|\d{1,3}(?:\.\d{1,3}){3}|[\w-]+(?:\.[\w-]+)*\.(?!(?:js|ts|py|md|txt|json|html?|php|sh|rb|rs|css|xml|ya?ml|log|pdf|png|jpe?g|zip)\b)[a-z]{2,})(?::\d+)?(?=$|\s+(?:-|@|[\w-]+(?:==?|:=?)\S)))/.test(t) && !proseArgs(t.replace(/^https?/, ""))))
            return "http"; // HTTP clients (httpie `http`/`https` need a space, unlike a URL's `://`)
        if (/^git\s+/i.test(t))
            return "commit";
        const cnt = /^(?:sudo\s+)?(?:docker|docker-compose|kubectl|podman|helm|nerdctl|k9s|minikube)\b/.exec(t);
        if (cnt && !proseArgs(t.slice(cnt[0].length)))
            return "deployed_code"; // containers / orchestration ("Docker is eating my ram" is prose)
        const iac = /^(?:sudo\s+)?(?:terraform|ansible|ansible-playbook|vagrant|packer|pulumi)\b/.exec(t);
        // "packer" is an English word ("packer job at the warehouse"), so it needs a
        // subcommand or a CLI token when its arguments are a plain word run.
        if (iac && !proseArgs(t.slice(iac[0].length)) && !(/(?:^|\s)packer$/.test(iac[0]) && proseWords(t.slice(iac[0].length)) && !/^\s+(?:build|init|validate|fmt|inspect|version|console|plugins|hcl2)\b/i.test(t.slice(iac[0].length))))
            return "cloud"; // IaC / provisioning ("Vagrant is a word ..." is prose)
        const pkg = /^(?:sudo\s+)?(?:apt|apt-get|dpkg|pacman|yay|paru|dnf|yum|zypper|apk|brew|nix-env|snap|flatpak)\b/.exec(t);
        // English-word package tools (apt/snap/brew/yay/apk) need a subcommand or a
        // CLI token when the arguments are a plain word run ("snap a pic", "yay it
        // works now", "apk for spotify premium" are prose).
        if (pkg && !proseArgs(t.slice(pkg[0].length)) && !(/(?:^|\s)(?:apt|snap|brew|yay|apk)$/.test(pkg[0]) && proseWords(t.slice(pkg[0].length)) && !/^\s+(?:install|reinstall|add|remove|rm|del|delete|erase|purge|uninstall|update|upgrade|full|refresh|sync|search|info|show|list|query|clean|autoremove|hold|unhold|mark|pin|depends|files|provides|policy|source|edit|download|changelog|enable|disable|revert|switch|connect|find)\b/i.test(t.slice(pkg[0].length))))
            return "package_2"; // package managers ("Brew some coffee ...", "Snap the photo ..." are prose)
        const lpm = /^(?:sudo\s+)?(?:pip3?|npm|npx|pnpm)\b/.exec(t);
        if (lpm && !proseArgs(t.slice(lpm[0].length)))
            return "package_2"; // JS/Python package managers (prose guard: "pip is so slow today", "npm is broken again")
        const lpc = /^(?:sudo\s+)?(?:cargo(?!\s+build\b)|uv)\b/.exec(t);
        if (lpc && !proseArgs(t.slice(lpc[0].length)) && /^\s+(?:(?:add|remove|rm|run|build|test|check|bench|install|uninstall|update|upgrade|search|init|new|publish|doc|fmt|clippy|clean|fetch|tree|vendor|fix|sync|lock|venv|tool|pip|python|cache|version|show|export|self|help)\b|--?\w|[~.]{0,2}\/|\$)/.test(t.slice(lpc[0].length)))
            return "package_2"; // cargo / uv are English words, so they need a subcommand or shell shape ("cargo pants ...", "uv is the fast ..." stay prose; "cargo build" -> build rule)
        const lpg = /^(?:sudo\s+)?(?:go\s+(?:build|run|get|install|mod|test|vet|fmt|env|version|generate|clean|work|list)|yarn(?:\s+(?:add|install|remove|run|dev|build|start|test|dlx|global|upgrade|init|create)\b|\s*$)|bun\s+(?:add|install|remove|run|dev|build|x|create|test|init|upgrade|pm)|gem\s+(?:install|uninstall|update|list|build|push|search|env)|composer\s+(?:install|require|update|remove|dump-autoload|create-project|init|global)|poetry\s+(?:add|install|remove|run|shell|build|publish|init|new|lock|update|show|env))\b/.exec(t);
        // Even with a valid subcommand ("go get", "poetry show"), a word run with a
        // sentence word after it is prose ("go get groceries after school", "poetry
        // show at the library tonight"); a package list is not ("yarn add react axios").
        // go's run / get / build / test / clean take a path, package path or flag, so
        // any plain word run after them is prose ("go get food later", "go run home").
        const goWords = lpg && /^(?:sudo\s+)?go\s+(?!mod$|work$)\w+$/.test(lpg[0]) && proseWords(t.slice(lpg[0].length));
        if (lpg && !proseArgs(t.slice(lpg[0].length)) && !chatWords(t.slice(lpg[0].length)) && !goWords)
            return "package_2"; // language package managers with an explicit subcommand (prose guard: "composer update of the symphony was amazing")
        const db = /^(?:sudo\s+)?(?:sqlite3?|mysql|mariadb|psql|mongosh?|redis-cli|sqlcmd|duckdb)\b/.exec(t);
        if (db && !proseArgs(t.slice(db[0].length)))
            return "database"; // database client / one-shot SQL command (case-sensitive; before the code catch-all; "mysql is a database engine" is prose)
        if (/\b(?:checking package integrity|looking for conflicting packages|resolving dependencies\.\.\.|(?:pre|post)-transaction hooks|Optional dependencies for \S|Total (?:Installed|Download) Size:|Net Upgrade Size:|Proceed with installation\?|Checking for packaging issues|Creating package "|Finished making:|Stripping unneeded symbols|Generating \.(?:PKGINFO|BUILDINFO|MTREE))/.test(t))
            return "package_2"; // pacman / makepkg transaction output
        const sysm = /^(?:sudo\s+)?(?:systemctl|journalctl|dmesg|service)\b/.exec(t);
        // "service" is an English word ("service charge included", "room service
        // today"); as a command it takes a unit + action or a flag.
        if (sysm && !proseArgs(t.slice(sysm[0].length)) && !(/(?:^|\s)service$/.test(sysm[0]) && proseWords(t.slice(sysm[0].length)) && !/\b(?:start|stop|restart|reload|force-reload|status|try-restart|condrestart|enable|disable|is-active|is-enabled)\b/i.test(t.slice(sysm[0].length))))
            return "settings"; // service / log management (case-sensitive: "Service was great at the hotel" is prose)
        if (/^(?:sudo\s+)?(?:Get-WinEvent|Get-EventLog|Get-WmiObject|Get-CimInstance|gwmi|wmic|wevtutil|logman|auditpol)\b/i.test(t))
            return "fact_check"; // Windows event-log / WMI query (before the PowerShell Get-* rule)
        if (/^(?:powershell(?:\.exe)?|pwsh)\b.*-e(?:nc(?:odedcommand)?|c)\s+[A-Za-z0-9+/]{16,}/i.test(t))
            return "warning"; // PowerShell encoded command (suspicious)
        // Build / compile command (case-sensitive), never when the rest reads as a
        // sentence ("cmake is the build system we use"). cmake, makepkg, gcc, g++,
        // clang++, "cargo build" and ./configure are not words, so any arguments
        // do; make, ninja, meson and clang are ("ninja moves are hard"), so they
        // need a flag / path / source file first, a run of known targets, flags or
        // VAR=value to the end (make also alone), or a meson subcommand.
        const bt = /^(?:sudo\s+)?(?:cmake|makepkg|gcc|g\+\+|clang\+\+|cargo\s+build|\.\/configure|make|ninja|meson|clang)(?=\s|$)/.exec(t);
        if (bt && !proseArgs(t.slice(bt[0].length)) && (/^(?:sudo\s+)?(?:cmake|makepkg|gcc|g\+\+|clang\+\+|cargo|\.\/configure)/.test(t) || /^\s+(?:-|~|\/|\.{1,2}(?:\/|\s|$)|\S+\.(?:c|cc|cpp|cxx|h|hpp|m|mm|s|o|rs|zig)(?:\s|$))/.test(t.slice(bt[0].length)) || /^(?:sudo\s+)?(?:make(?=(?:\s+(?:install|clean|all|check|test|build|uninstall|-\S+|[A-Z_]+=\S*))*\s*(?:$|&&|;|\|))|ninja(?=(?:\s+(?:install|clean|all|check|test|build|uninstall|-\S+|[A-Z_]+=\S*))+\s*(?:$|&&|;|\|))|meson\s+(?:setup|configure|compile|install|test|dist|init|introspect|wrap|subprojects|devenv)\b)/.test(t)))
            return "build"; // build / compile / install command
        // Command shape, shared by the two command rules below. Tool names that are
        // not English words (case-sensitive, so a sentence opening with a
        // capitalised tool name is prose):
        const utName = /^(?:sudo\s+)?(sh|zsh|env|printf|whereis|whoami|nano|vim|vi|emacs|chmod|chown|chgrp|mkdir|rmdir|readlink|realpath|basename|dirname|grep|rg|awk|sed|xargs|fd|gzip|gunzip|unzip|pkill|pgrep|htop|lsblk|lsof|lspci|lsusb|useradd|usermod|chsh|crontab|nslookup|nmcli|iptables|nft|ufw|sysctl|md5sum|sha1sum|sha256sum|sha512sum|base64|xxd|hexdump|openssl|gpg|hyprctl|hyprpm|setsid|nohup|jq|losetup|caelestia|quickshell|qs|cliphist|wl-copy|wl-paste|notify-send|xdg-open|ffmpeg|ffprobe|yt-dlp|tesseract|netstat|ifconfig|nvim|7z|node|mpv|zcat|feh|unrar|zathura)(?=\s|$)/;
        // Commands that are also English words, followed by a space or the end (so a
        // dotted / hyphenated token like a filename is not read as one).
        const ewName = /^(?:sudo\s+)?(ls|pwd|cd|echo|which|man|rm|cp|mv|ln|touch|cat|tee|less|more|tail|head|wc|cut|tr|sort|uniq|find|stat|export|source|alias|kill|ps|top|df|du|free|mount|umount|uname|uptime|sync|dd|su|ip|ping|file|passwd|route|bash|fish|tar|dig|column|ss|sleep|fg|bg|wait|renice|nice|exit|unset)(?=\s|$)/;
        // The tools the other command rules name and utName / ewName do not, less
        // the everyday English words (beef, empire, crunch, service, snap, gem,
        // poetry, ...), plus common terminal programs no rule names (tmux, fzf, ...).
        const toolName = /^(?:sudo|python3?|git|ssh|scp|sftp|rsync|nc|ncat|socat|telnet|mosh|curl|wget|httpie|xh|aria2c|nmap|masscan|rustscan|zmap|amass|subfinder|assetfinder|shodan|dnsrecon|dnsenum|theharvester|whatweb|wafw00f|tshark|tcpdump|wireshark|ngrep|termshark|dumpcap|tcpflow|bettercap|ettercap|arpspoof|mitmproxy|mitmdump|snort|suricata|suricatasc|zeek|zeekctl|zeek-cut|broctl|chaosreader|joincap|capinfos|editcap|mergecap|reordercap|tcpick|nfdump|rwfilter|rwstats|stenographer|arkime|hashcat|john|hydra|ncrack|patator|hcxdumptool|aircrack-ng|airmon-ng|cewl|gobuster|feroxbuster|ffuf|dirb|dirbuster|wfuzz|nikto|wpscan|sqlmap|nuclei|arjun|dalfox|commix|xsstrike|msfconsole|msfvenom|msfdb|meterpreter|searchsploit|setoolkit|cobaltstrike|enum4linux|netexec|crackmapexec|impacket-\S+|bloodhound|sharphound|evil-winrm|smbclient|smbmap|rpcclient|ldapsearch|kerbrute|certipy|mimikatz|secretsdump|gdb|radare2|r2|objdump|readelf|strace|ltrace|checksec|pwndbg|ropper|ROPgadget|volatility3?|binwalk|steghide|zsteg|exiftool|strings|docker|docker-compose|kubectl|podman|helm|nerdctl|k9s|minikube|terraform|ansible|ansible-playbook|vagrant|pulumi|go|yarn|pacman|paru|yay|apt|apt-get|dpkg|dnf|yum|zypper|nix-env|flatpak|pip3?|npm|npx|pnpm|cargo|uv|sqlite3?|mysql|mariadb|psql|mongosh?|redis-cli|sqlcmd|duckdb|systemctl|journalctl|dmesg|cmake|makepkg|make|ninja|gcc|g\+\+|clang|clang\+\+|meson|pwsh|powershell|tmux|fzf|kitty|btop|eza|zoxide|alacritty|wezterm|fastfetch|neofetch)$/;
        // A command name given as an operand ("man tcpdump", "which python3", "nohup
        // python3 server.py").
        const knownCmd = w => utName.test(w) || ewName.test(w) || toolName.test(w);
        // A flag, path, glob, $VAR, quoted arg, VAR=value, dotfile or dotted filename.
        const shaped = s => /^(?:--?\w|-$|[~.]{1,2}(?:\/|$)|\.\w|\/|["'])|\/$|\w\/[\w.-]+\/|\*|\$[A-Za-z_{(]|\w\.\w|\w=/.test(s);
        // First words that open a sentence rather than an argument list.
        const leadWord = /^(?:the|a|an|my|your|his|her|our|their|this|that|these|those|it|them|me|us|him|some|any|all|one|to|of|in|on|at|for|by|with|from|about|out|up|off|over|under|into|and|or|is|are|was)$/i;
        // A pipe, &&, "; cmd", "< file", $(...), escaped space, trailing " -" or " &",
        // or a lone ./..
        const shellOp = /(?:^|\s)\|{1,2}\s*\S|&&|;\s*[a-z]|\s<\s*(?:[\/~$]|[\w-]+\.\w)|\$\(|\\\s|\s[-&]$|(?:^|\s)\.{1,2}(?:\/|\s|$)/;
        // A file redirect, but not an "a > b > c" menu path.
        const redirect = s => /\s[12&]?>{1,2}\s*[\w\/~&$."'-]/.test(s) && !/\s>\s[^>]*\s>\s/.test(s);
        // Shell shape in the words after a command name: a shaped first argument (or
        // second, after a first word that is not a lead word), or an operator or a
        // redirect anywhere.
        const shellShape = rest => {
            const a = /^\s*(\S*)\s*(\S*)/.exec(rest);
            return shaped(a[1]) || (!leadWord.test(a[1]) && shaped(a[2])) || shellOp.test(rest) || redirect(rest);
        };
        // Unambiguous tools: a command unless the rest reads as a sentence. The names
        // that double as topics ("quickshell vs ags", "ffmpeg tutorial for beginners",
        // "caelestia launcher opens slowly") must also stand alone, carry shell shape
        // or open with a known subcommand.
        const ut = utName.exec(t);
        if (ut && !proseArgs(t.slice(ut[0].length))) {
            const name = ut[1], rest = t.slice(ut[0].length);
            const word = /^\s*(\S*)/.exec(rest)[1];
            const topic = /^(?:caelestia|quickshell|qs|tesseract|hyprctl|hyprpm|cliphist|ffmpeg|ffprobe|yt-dlp|jq|setsid|nohup|node|nvim|7z|mpv|zcat|feh|unrar|zathura)$/.test(name);
            const subcommand = /^(?:hyprctl:(?:activewindow|activeworkspace|animations|binds|clients|configerrors|cursorpos|decorations|devices|dismissnotify|dispatch|eval|getoption|getprop|globalshortcuts|hyprpaper|hyprsunset|instances|keyword|kill|layers|layouts|monitors|notify|output|plugin|reload|repl|rollinglog|setcursor|seterror|setprop|splash|status|switchxkblayout|systeminfo|version|workspacerules|workspaces)|hyprpm:(?:add|remove|enable|disable|update|reload|list|purge-cache)|caelestia:(?:shell|scheme|wallpaper|screenshot|record|clipboard|emoji|toggle|resizer|pip|install|update)|cliphist:(?:store|list|decode|delete|delete-query|wipe|version)|(?:qs|quickshell):(?:ipc|kill|list|log)|7z:(?:a|b|d|e|h|i|l|rn|t|u|x))$/.test(name + ":" + word);
            // setsid and nohup run a command line: a known program, a flag / path / bare
            // "--" anywhere ("setsid uwsm app -- kitty"), or up to four lowercase words
            // opening with a program name rather than a topic word ("nohup ollama
            // serve", but not "nohup meaning" or "setsid explained").
            const launches = /^(?:setsid|nohup)$/.test(name) && (knownCmd(word) || /(?:^|\s)(?:--?(?:[A-Za-z]|(?=\s|$))|~?\/|\.{1,2}\/)/.test(rest) || (/^(?:\s+[a-z][\w.:+-]*){1,4}$/.test(rest) && !/^\s+(?:meaning|means|explained|explanation|alternatives?|equivalent|tutorial|examples?|usage|commands?|docs|documentation|guide|help|output|difference|linux|windows|macos|mac|in|on|for|with|without|to|of|the|a|an)(?=\s|$)/.test(rest)));
            // nvim opening "+cmd" or a conventional extension-less file (PKGBUILD,
            // README, Makefile, Dockerfile).
            const edits = name === "nvim" && /^\s+(?:\+|[A-Z]{3,}(?:\s|$)|[A-Z][a-z]+file(?:\s|$))/.test(rest);
            if (!topic || rest === "" || subcommand || launches || edits || shellShape(rest))
                return "terminal"; // shell / net / file utilities whose name is not an English word
        }
        // English-word commands: the rest must not read as a sentence, and the words
        // after the name must carry shell shape or one of the operand shapes below. So
        // "cat is on the mat", "kill it", "top 5" and "find a cheaper one under $30"
        // stay prose.
        const ew = ewName.exec(t);
        if (ew && !proseArgs(t.slice(ew[0].length))) {
            const name = ew[1], rest = t.slice(ew[0].length);
            // The name alone ("ls", "df"), except the words listed only for their
            // number / variable operands.
            const alone = rest === "" && !/^(?:sleep|fg|bg|wait|renice|nice|exit|unset)$/.test(name);
            // echo prints one or two plain words ("echo hello world"); proseArgs has
            // already turned away "echo the build is done", a longer unquoted run is a
            // note ("echo pedal for guitar"), and "echo chamber", the Echo speaker line
            // ("echo dot") and the audio effect ("echo cancellation") are nouns.
            const echoed = name === "echo" && /^(?:\s+\S+){1,2}$/.test(rest) && !/^\s+(?:chambers?|dot|show|studio|buds|frames|spot|pop|hub|cancel(?:lation|l?ing|l?er)?|effects?|pedals?|delay|reverb|location|park)(?=\s|$)/i.test(rest);
            // One or two operands: a lowercase letter, an identifier with a digit / _ / -
            // that is not a Capitalised word ("free V-Bucks", "sort A-Z" are prose), or
            // a number, which only job / process / timer commands take ("kill 1234",
            // "sleep 5", "fg %1" -- not "top 5" or "head 2").
            const operands = /^(?:\s+(?:%?\d+|[a-z]|(?![A-Z])(?=[\w-]*\d|\w+[_-])[\w-]+)){1,2}$/.test(rest) && (/^(?:kill|sleep|fg|bg|wait|renice|nice|exit)$/.test(name) || !/\s%?\d+(?=\s|$)/.test(rest));
            // A bare ALL-CAPS operand is a variable only for unset ("unset HISTFILE")
            // and, when it is a well-known or underscored name, export ("export PATH",
            // "export LD_PRELOAD"); "export CSV" is prose. With "=" or "$" ("export
            // EDITOR=nvim", "echo $HOME") shaped() has already seen it.
            const bareVars = (name === "unset" && /^(?:\s+[A-Z_][A-Z\d_]*){1,3}$/.test(rest)) || (name === "export" && /^(?:\s+(?:[A-Z][A-Z\d]*_[A-Z\d_]*|PATH|HOME|EDITOR|VISUAL|SHELL|TERM|LANG|DISPLAY|USER|PAGER|BROWSER|HISTFILE|HISTSIZE|PS1|TMPDIR|MANPATH|CC|CXX|CFLAGS|LDFLAGS)){1,3}$/.test(rest));
            // A file reader opening a file conventionally named in capitals ("cat
            // README", "less PKGBUILD"); other Capitalised operands stay prose ("cat A").
            const capsFile = /^(?:cat|less|more|head|tail|file|wc|stat|touch)$/.test(name) && /^(?:\s+(?:README|LICEN[CS]E|COPYING|CHANGELOG|CHANGES|NEWS|TODO|INSTALL|AUTHORS|CONTRIBUTORS|NOTICE|PKGBUILD|Makefile|Dockerfile|Containerfile|Vagrantfile|Jenkinsfile|Justfile|Gemfile|Rakefile|Procfile|History|Cookies|Bookmarks|Preferences)){1,2}$/.test(rest);
            // man / which take command names ("man grep", "which python3 node") and man
            // a section number ("man 5 crontab"), not any word ("man city", "which laptop").
            const manPage = (name === "man" || name === "which") && ((/^(?:\s+\S+){1,3}$/.test(rest) && rest.trim().split(/\s+/).every(knownCmd)) || (name === "man" && /^\s+\d\w?\s+\S+$/.test(rest)));
            // After a name that is not an English word, one or two words that are not
            // function words ("cd Downloads", "mv notes old").
            const plainArgs = /^(?:cd|ls|pwd|rm|cp|mv|ln|wc|tr|uniq|df|du|umount|uname|uptime|passwd)$/.test(name) && /^(?:\s+(?!(?:i|is|are|was|were|am|be|it|its|the|an|and|or|but|to|of|on|in|at|for|with|from|this|that|my|your|me|you|we|he|she|they|them|him|her|up|out|off|so|not|no|yes|ok|please|just|all|will|can|do|did|have|has)(?:\s|$))\S+){1,2}$/.test(rest);
            // ps takes one BSD option cluster ("ps aux", "ps axjf"), not a note ("ps
            // call mom").
            const psOptions = name === "ps" && /^\s+[aefjlmruwxHT]{1,5}$/.test(rest);
            // ip object, optionally with an action ("ip addr show", "ip route").
            const ipObject = name === "ip" && /^\s+(?:addr|address|link|route|neigh|rule|netns)(?:\s+(?:show|list|add|del|delete|flush|set|get|replace)\b|$)/.test(rest);
            if (alone || echoed || shellShape(rest) || operands || bareVars || capsFile || manPage || plainArgs || psOptions || ipObject)
                return "terminal"; // English-word command with shell context
        }
        if (/^sudo\s+[\w.\/~!-]/.test(t) && !proseArgs(t.slice(4)))
            return "terminal"; // any other sudo command ("sudo reboot", "sudo -i", "sudo nvim /etc/fstab")
        if (/^(?:powershell|pwsh)\b/i.test(t) || /\b(?:Invoke-(?:Expression|WebRequest|Command)|IEX|Get-\w+|Set-\w+|New-Object)\b/.test(t))
            return "terminal"; // PowerShell

        // -- SOC / IDS / DFIR: detection rules, filters, alerts, hunting queries,
        //    forensic artefacts and IOCs. Placed before URLs/JSON/XML/code so these
        //    structured shapes aren't swallowed by the generic-code catch-all below. --
        if (/"event_type"\s*:\s*"(?:alert|anomaly)"/.test(t))
            return "crisis_alert"; // Suricata EVE-JSON alert event
        if (/\[\*\*\]\s*\[\d+:\d+:\d+\]/.test(t))
            return "crisis_alert"; // fired IDS alert output (Snort / Suricata fast.log)
        if (/^#?\s*(?:alert|drop|reject|pass|sdrop|log|activate|dynamic)\s+(?:tcp|udp|icmp|ip|http2?|tls|ssl|dns|ssh|ftp|smb2?|dcerpc|smtp|imap|pop3|modbus|dnp3|nfs|ikev2|krb5|ntp|dhcp|snmp|tftp|rdp|rfb|mqtt|sip)\s+\S+\s+\S+\s*(?:->|<>)/i.test(t))
            return "policy"; // Snort / Suricata detection rule
        if (/\b(?:sid\s*:\s*\d+|flow\s*:\s*(?:established|stateless|to_server|to_client)|pcre\s*:\s*"|fast_pattern\b|classtype\s*:\s*[\w-]+\s*;|reference\s*:\s*\w+,)/i.test(t))
            return "policy"; // Snort / Suricata rule-option fragment (IDS-specific tokens)
        if (/\brule\s+\w+[^{]*\{/i.test(t) && /\bcondition\s*:/.test(t))
            return "policy"; // YARA rule
        if (/\blogsource\s*:/i.test(t) && /\bdetection\s*:/i.test(t) && /\bcondition\s*:/i.test(t))
            return "policy"; // Sigma rule
        if (/\|(?:[0-9a-f]{2}\s?){2,}\|/i.test(t))
            return "memory"; // pipe-delimited packet content bytes (|24 7b|jndi|)
        if (/<Sysmon\b[^>]*schemaversion/i.test(t) || /<RuleGroup\b[^>]*groupRelation/i.test(t))
            return "sensors"; // Sysmon monitoring config
        if (/^#(?:separator|set_separator|fields|types|path|open|close)\b/i.test(t))
            return "sensors"; // Zeek TSV log header
        if (/^(?:frame|eth|ip|ipv6|arp|tcp|udp|sctp|icmp|icmpv6|http2?|dns|tls|ssl|quic|smb2?|ldap|kerberos|dhcp|ntp|snmp|ssh|ftp|smtp|pop|imap|nbns|mdns|llmnr|radius|sip|rtp|wlan|eapol|dcerpc)\.[\w.]+\s*(?:==|!=|>=|<=|<|>|contains\b|matches\b|in\b|&&|\|\|)/i.test(t) || /^frame\s+contains\s+/i.test(t))
            return "filter_alt"; // Wireshark / tshark display filter
        if (/^(?:tcp|udp|icmp|ip6?|arp|ether|host|net|port|portrange|vlan|src|dst)\b.{0,80}?\b(?:port\s+\d{1,5}|host\s+\d{1,3}\.\d|net\s+\d{1,3}\.\d|portrange\s+\d)/i.test(t))
            return "filter_alt"; // BPF / libpcap capture filter
        if (/^(?:search\s+)?(?:index|source|sourcetype)\s*=\s*\S+.*\|\s*(?:stats|tstats|eval|table|rex|timechart|chart|dedup|sort|where|top|rare|fields|bin|transaction|eventstats|streamstats|lookup)\b/i.test(t) || /^\s*\|\s*(?:tstats|stats|inputlookup|makeresults|metadata|mstats)\b/i.test(t))
            return "query_stats"; // Splunk SPL
        if (/^[A-Z][A-Za-z0-9_]*\s*\|\s*(?:where|summarize|project|extend|join|union|mv-expand|parse|render|count\b|distinct|take|top|order\s+by|evaluate|make-series)\b/.test(t))
            return "query_stats"; // KQL (Sentinel / Defender)
        if (/^(?:sequence\b|(?:process|network|file|registry|authentication|library|dns|any)\s+where\b)/i.test(t))
            return "query_stats"; // EQL
        if (/^(?:HK(?:LM|CU|CR|U|CC)|HKEY_(?:LOCAL_MACHINE|CURRENT_USER|CLASSES_ROOT|USERS|CURRENT_CONFIG))[\\\/]/i.test(t))
            return "app_registration"; // Windows registry path
        if (/\bhxxps?:\/\//i.test(t) || /[\w)]\[\.\][\w(]/.test(t) || /\[(?:at|dot)\]/i.test(t))
            return "gpp_maybe"; // defanged IOC (hxxp://, 1.2.3[.]4, user[at]host)
        if (/^T\d{4}(?:\.\d{3})?\b/.test(t) || /^TA00\d{2}\b/.test(t) || /\bT\d{4}\.\d{3}\b/.test(t))
            return "swords"; // MITRE ATT&CK technique / tactic ID
        if (/^[a-z]\d{2}[a-z]\d{2}[a-z0-9]{2}_[0-9a-f]{12}_[0-9a-f]{12}$/i.test(t))
            return "fingerprint"; // JA4 TLS fingerprint
        if (/^NAME\s*(?::|__|_(?=\s))\s*(?:_+\s*)?(?:PERIOD\b:?\s*(?:_+\s*)?)?DATE(?=[\s:]|_*(?:\s|$))|^NAME\s+(?:DATE\s*:|DATE\s+PERIOD\b|PERIOD\s+DATE\b)|\bDIRECTIONS\s*:/.test(t))
            return "assignment"; // school worksheet header (case-sensitive: NAME: / NAME ___ [PERIOD ___] DATE, or with its blanks stripped "NAME DATE:" / "NAME DATE PERIOD", or DIRECTIONS:; "NAME DATE and ..." is a column list, NAME__DATE.csv a file and DATE_CREATED a field)
        if (/\b(?:Section\s+\d+\s*\/\s*\d+|HTB Academy|Skills Assessment|Go to Questions)\b/i.test(t))
            return "school"; // HTB Academy / course material
        if (/\bSubmit Task\b|\bTask \d{1,2} Hint\b|^Sherlock Scenario\b/.test(t))
            return "flag"; // HTB Sherlock / CTF task page (challenge, not course material)
        if (/\bEvent(?:\s?ID|\s?Code)\s*[:=#]?\s*\d{1,5}\b/i.test(t))
            return "fact_check"; // Windows Event ID reference (broad — kept last in block)

        // -- URLs / mail / hosts --
        if (/\b[a-z2-7]{16,56}\.onion\b/i.test(t))
            return "vpn_lock"; // Tor hidden service
        if (/^magnet:\?/i.test(t) || /\bxt=urn:bt/i.test(t))
            return "download"; // magnet link
        if (/^data:[\w.+-]+\/[\w.+-]+[;,]/i.test(t))
            return "data_object"; // data: URI
        if (/^file:\/\//i.test(t))
            return extIcon(t) || "folder"; // file URI — use the named file's type when known
        if (/^s?ftp:\/\//i.test(t))
            return "folder_shared"; // (s)ftp URL
        if (/^https?:\/\/(?:www\.)?(?:google|bing|duckduckgo|search\.brave|kagi|yandex)\.[a-z.]+\/(?:search|html\/?)?\?(?:\S*&)?q=\S+$/i.test(t))
            return "search"; // search-engine results URL
        if (/^https?:\/\/\S+$/i.test(t))
            return "link"; // the whole entry is one URL — a URL merely embedded in text/code/logs/SQL falls through to those rules
        if (/^mailto:/i.test(t) || /^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(t))
            return "alternate_email"; // email / mailto
        if (oneLine && /^#[\w-]{2,}$/.test(t) && !/^#[0-9a-f]{3,8}$/i.test(t))
            return "tag"; // hashtag (but not a hex colour)
        if (oneLine && /^@[\w.-]{2,}$/.test(t))
            return "alternate_email"; // @mention
        // Scene / fansub release name (no extension needed): an SxxExx episode tag, a
        // scene-only rip tag (WEB-DL WEBRip BDRip BRRip DVDRip HDRip), a source tag
        // (BluRay HDTV) with a codec, or a source / codec marker beside a resolution.
        // A resolution alone is a monitor model or a screenshot name
        // ("panel_1080p_144hz"), HDTV / BluRay alone a product, and two codecs alone
        // an encoder comparison ("x264_vs_x265"). A known non-video extension wins
        // (a release-named .srt / .torrent, a script or preset named after its
        // codec), except an uppercase audio-codec tag ending the name (".FLAC").
        if (oneLine && /^[\w.()\[\]+-]{12,}$/.test(t) && (/^(?:movie)?$/.test(extIcon(t)) || /\.(?:AAC|FLAC)$/.test(t))) {
            const src = /[._-](?:BluRay|HDTV)(?=[._-]|$)/i.test(t);
            const rel = (t.match(/[._-](?:[xh]\.?26[45]|HEVC|XviD|AAC(?:\d\.\d)?|DDP(?:\d\.\d)?|AC3|DTS|FLAC)(?=[._-]|$)/gi) || []).length;
            if (/[._-](?:S\d{2}E\d{2,3}|WEB-?DL|WEBRip|BDRip|BRRip|DVDRip|HDRip)(?:[._-]|$)/i.test(t) || (src && rel) || ((src || rel) && /[._-](?:480|576|720|1080|2160)p(?:[._-]|$)/i.test(t)))
                return "movie";
        }
        // A lone "name.ext" token with a known extension is a filename, not a domain.
        if (oneLine && !/[\s\/:@\\]/.test(t)) {
            const fi = extIcon(t);
            if (fi)
                return fi;
        }
        if ((t.match(/\.(?:png|jpe?g|gif|webp|heic|avif|bmp|tiff?)(?=\s|$)/gi) || []).length >= 3 && !/https?:\/\//i.test(t))
            return "photo_library"; // a listing of 3+ image files
        // A filename with spaces: at most 3 spaces and no lowercase word between two
        // spaces ("notes for class.txt" is prose), except a dated screenshot name,
        // which may use 5 and a "from"/"at" ("Screenshot from 2024-01-02 10-00-00.png").
        // A leading imperative verb before a lowercase name ("Open index.html",
        // "Run setup.exe") is an instruction that names a file, not the file; a
        // title-cased rest ("Start Here.pdf") or "download (1).pdf" stays a file.
        const dated = /\b\d{4}-\d{2}-\d{2}\b/.test(t);
        if (oneLine && t.length <= 80 && /^[\w(][\w .()+-]*\.[A-Za-z0-9]{2,5}$/.test(t) && (t.match(/\s/g) || []).length <= (dated ? 5 : 3) && !(dated ? /\s(?!(?:from|at)\s)[a-z]{2,}\s/ : /\s[a-z]{2,}\s/).test(t) && !(/^(?:Open|Run|Edit|Delete|Remove|Copy|Move|Read|Check|See|Use|Download|Install|Save|Upload|Send|Rename|Launch|Start|Load|Import|Export|Print|View|Try|Find|Get)\s/i.test(t) && /^\S+\s+[a-z_.]/.test(t))) {
            const si = extIcon(t);
            if (si)
                return si; // a single filename that contains spaces (the lone-token check above skips it)
        }
        // Bare hostname / domain: the last label must be a known TLD or a lab / LAN
        // suffix (.htb .local .lan; .in and .am are left out as autotools file
        // suffixes), so a file with an unlisted extension (.jsonl .gguf .ovpn) is not
        // a host. English-word TLDs (.name .email .link .top .home ...) and .id
        // .info .int also name object members (obj.name, row.id, logger.info), so
        // they count only on a 3+ label host (www.example.name), and a self. /
        // this. / cls. reference is never a host. The TLD must be lowercase unless
        // the whole host is uppercase or it is a lab / LAN suffix (AD tools print
        // dc01.CORP.HTB), which keeps a namespace like "System.IO" out; never a
        // hex-offset dump filename.
        if ((/^(?:[a-z0-9-]+\.)+(?:com|org|net|edu|gov|mil|arpa|io|dev|app|ai|co|me|tv|us|uk|ca|de|fr|es|it|nl|be|ch|at|se|no|fi|dk|is|ie|pl|cz|sk|hu|ro|bg|gr|pt|ru|ua|by|kz|lt|lv|ee|md|jp|cn|kr|tw|hk|sg|th|vn|ph|my|au|nz|za|br|ar|mx|cl|tr|il|ae|eu|asia|biz|xyz|gg|so|sh|ly|to|fm|cc|ws|onion|local|localdomain|localhost|lan|internal|htb|thm)$/i.test(t) || /^(?:[a-z0-9-]+\.){2,}(?:pro|site|online|tech|store|shop|cloud|blog|page|link|live|news|wiki|club|space|top|zone|world|today|studio|design|games|media|chat|work|tools|website|digital|lol|social|network|systems|software|codes|corp|example|invalid)$/i.test(t) || /^(?:www|api|app|mail|smtp|imap|pop|ns\d?|mx|dev|stage|staging|cdn|static|web|ftp|vpn|portal|dashboard|admin|docs|status|assets|img|images|media|auth|login|account|secure|support|help|forum|host|gw)\.(?:[a-z0-9-]+\.)+(?:id|info|int|name|email|host|home|test)$/i.test(t)) && (/\.(?:[a-z]+|HTB|THM|LOCAL|LAN|INTERNAL)$/.test(t) || t === t.toUpperCase()) && !/(?:^|\.)0x[0-9a-f]+\./i.test(t) && !/^(?:self|this|cls)\./.test(t))
            return "dns";
        if (oneLine && /^(?:www\.)?(?:[a-z0-9-]+\.)+(?:com|org|net|edu|gov|io|dev|co|us|uk|ca|de|so|app|xyz|info|me|tv)(?::\d{2,5})?\/\S*$/i.test(t))
            return "link"; // scheme-less URL host.tld/path (TLD-restricted so relative paths stay paths)

        // -- data / code / markup --
        // SQL. An uppercase SELECT ... FROM is a query whatever sits between them
        // (TOP n, casts, CASE, implicit aliases, subqueries), and so is an uppercase
        // FROM-less SELECT of functions / @@variables / numbers / NULLs (SELECT
        // version(), UNION SELECT 1,2,3), also after an injection's leading quote
        // ("cn' UNION select ... from ..."), and in any case after UNION or with an
        // @@variable or a bare fn(). Otherwise
        // the keyword, in any case, must sit in statement structure: SELECT <*, t.*,
        // fn(...), 'lit', AS alias, DISTINCT or a comma list> FROM <t> (one bare
        // column only with a following WHERE / JOIN / LIMIT / ORDER BY ... or ";");
        // UPDATE <t> [alias] SET <c> =; DELETE FROM <t>; INSERT [IGNORE] INTO <t>
        // [(...)] VALUES | SELECT; CREATE TABLE <t> ( | AS; CREATE INDEX [<i>] ON
        // <t> (; CREATE VIEW <v> AS; CREATE DATABASE|SCHEMA <d> then end; CREATE
        // FUNCTION <f>(; CREATE TRIGGER / POLICY / EXTENSION; DROP <kind> <n> then
        // end / ; / CASCADE; ALTER TABLE <t> ADD|DROP|...; TRUNCATE TABLE <t>; WITH
        // <n> AS (SELECT; GRANT <privileges> ON <object> TO. The captured name may
        // not be an article, pronoun or preposition. So "select text from the pdf",
        // "create table comparing two cards", "drop database class, not doing it",
        // "insert into oven (preheated)" and "UPDATE: class moved" stay prose.
        if (/^\s*(?:[\w-]*['"]\)*\s*)?(?:select|update|delete|insert|create|drop|alter|truncate|with|grant|union)\s/i.test(t)) {
            const sq = /^\s*(?:[\w-]*['"]\)*\s*)?(?:UNION\s+(?:ALL\s+)?)?SELECT\s[\s\S]{0,400}?\sFROM\s+([\w.`"\[\](]+)/.exec(t) || /^\s*(?:[\w-]*['"]\)*\s*)?union\s+(?:all\s+)?select\s[\s\S]{0,400}?\sfrom\s+([\w.`"\[\](]+)/i.exec(t) || /^\s*(?:[\w-]*['"]\)*\s*)?(?:UNION\s+(?:ALL\s+)?)?SELECT\s+(?:@@[\w.]+|\w+\([^()]{0,80}\)|\d+|NULL)(?:\s*,\s*(?:@@[\w.]+|\w+\([^()]{0,80}\)|\d+|NULL))*\s*(?:;|--.*|#.*)?$/.exec(t) || /^\s*(?:[\w-]*['"]\)*\s*)?(?:union\s+(?:all\s+)?select\s+(?:@@[\w.]+|\w+\([^()]{0,80}\)|\d+|null)|select\s+(?:@@[\w.]+|\w+\(\)))(?:\s*,\s*(?:@@[\w.]+|\w+\([^()]{0,80}\)|\d+|null))*\s*(?:;|--.*|#.*)?$/i.exec(t) || /^\s*(?:select\s+(?!@{0,2}[\w.]+\s+(?:from|into)\s)(?:distinct\s+)?(?:[\w.]*\*|'[^']*'|@{0,2}[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?)(?:\s+as\s+\w+)?(?:\s*,\s*(?:[\w.]*\*|'[^']*'|@{0,2}[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?)(?:\s+as\s+\w+)?)*\s+(?:from|into)\s+([\w.`"\[\]]+)|select\s+[\w.]+\s+(?:from|into)\s+([\w.`"\[\]]+)(?:\s*;|\s+(?:where|join|inner|left|right|full|cross|natural|limit|offset|order\s+by|group\s+by|having|union)\b)|update\s+([\w.`"\[\]]+)(?:\s+(?:as\s+)?\w+)?\s+set\s+[\w.`\"]+\s*=|delete\s+from\s+([\w.`"\[\]]+)(?:\s+(?:as\s+)?\w+(?=\s+(?:where|using)\b))?(?:\s*;|\s*$|\s+(?:where|using|returning|limit|order)\b)|insert\s+(?:(?:or\s+\w+|ignore|low_priority|delayed|high_priority)\s+)?into\s+([\w.`"\[\]]+)\s*(?:\([^()]{0,300}\)\s*)?(?:values|select|default\s+values|set)\b|create\s+(?:(?:or\s+replace|temp|temporary|unlogged|virtual)\s+)?table\s+(?:if\s+not\s+exists\s+)?([\w.`"\[\]]+)\s*(?:\(|(?:as|like)\b)|create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(?:[\w.`"\[\]]+\s+)?on\s+(?:only\s+)?([\w.`"\[\]]+)\s*(?:\(|using\b)|create\s+(?:or\s+replace\s+)?(?:materialized\s+)?view\s+(?:if\s+not\s+exists\s+)?([\w.`"\[\]]+)\s+as\b|create\s+(?:database|schema)\s+(?:if\s+not\s+exists\s+)?([\w.`"\[\]]+)\s*(?:;|$|\s+(?:authorization|owner|with|character|default|encoding)\b)|create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+([\w.`"\[\]]+)\s*\(|create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+([\w.`"\[\]]+)\s+(?:before|after|instead)\b|create\s+policy\s+(\"[^\"]{1,80}\"|[\w.`"\[\]]+)\s+on\b|create\s+extension\s+(?:if\s+not\s+exists\s+)?([\w.`"\[\]]+)\s*(?:;|$|\s+(?:with|schema|cascade)\b)|drop\s+(?:table|database|index|view|schema|function|procedure|trigger|policy|extension|materialized\s+view)\s+(?:if\s+exists\s+)?([\w.`"\[\]]+)\s*(?:[;(]|$|\s+(?:cascade|restrict|on)\b)|alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?([\w.`"\[\]]+)\s+(?:add|drop|alter|rename|modify|change|owner|enable|disable|set|attach|detach)\b|truncate\s+table\s+([\w.`"\[\]]+)\s*(?:;|$|\s+(?:restart|continue|cascade|restrict)\b)|with\s+(?:recursive\s+)?(\w+)\s*(?:\([^()]*\)\s*)?as\s*(?:(?:not\s+)?materialized\s*)?\(\s*(?:select|values|insert|update|delete|with)\b|grant\s+(?:all(?:\s+privileges)?|select|insert|update|delete|usage|execute|create|references|trigger|alter|drop|index|connect)(?:\s*,\s*(?:all(?:\s+privileges)?|select|insert|update|delete|usage|execute|create|references|trigger|alter|drop|index|connect))*\s+on\s+(?:(?:table|schema|database|function|sequence|all\s+(?:tables|sequences|functions)\s+in\s+schema)\s+)?([\w.*`\"\[\]]+)\s+to\b)/i.exec(t);
            // The captured table / CTE name may not be an article, pronoun or
            // preposition, so "select a, b from the list below", "Delete from the list
            // where it says old" and "update the doc set it = done" stay prose. The
            // single letter "a" is the exception: it is the most common throwaway table
            // name (HTB SQLi practice), so "select * from a" and "delete from a where
            // ..." are real queries -- unless a plain word follows it ("Delete from a
            // list where it says old").
            const tbl = sq ? sq.slice(1).find(g => g) || "" : "";
            if (sq && !/^(?:the|an|my|your|his|her|its|our|their|this|that|these|those|each|every|all|any|some|both|here|there|it|them|me|us|him|you|of|for|in|on|at|with|to|from|by|and|or|is)$/i.test(tbl) && !(tbl === "a" && /\b(?:from|into|update)\s+a\s+(?!(?:where|join|inner|left|right|full|cross|natural|limit|offset|order|group|having|union|set|values|as|on|using|select|except|intersect|returning|into|default|[a-z]{1,2})\b)[a-z]/i.test(t)))
                return "database";
        }
        if (/^diff --git\b/m.test(t) || /^@@ -\d+.* \+\d+.* @@/m.test(t) || /^(?:index [0-9a-f]+\.\.|--- a\/|\+\+\+ b\/)/m.test(t))
            return "difference"; // unified diff / patch
        // cron: five fields, each inside its range (minute 0-59, hour 0-23, day 1-31,
        // month 1-12 or JAN-DEC, weekday 0-7 or SUN-SAT; * , - / forms), and a "*"
        // among them or a command after them (a path, $VAR, or a script file,
        // optionally behind its interpreter) -- so dates, fractions, port lists,
        // "1 2 3 4 5" and a product like "2 * 3 * 4" are not schedules.
        if (/^[\d*]/.test(t) && !/^[\d.]+(?:\s+[-+*/]\s+[\d.]+){2,}(?:\s*=.*)?$/.test(t)) {
            const cr = /^([\d*\/,-]+)\s+([\d*\/,-]+)\s+([\d*\/,-]+)\s+([\w*\/,-]+)\s+([\w*\/,-]+)(?:\s+(.*))?$/.exec(t);
            const named = (f, i) => i < 3 ? f : f.replace(/[a-z]{3}/gi, n => {
                const k = (i === 3 ? "janfebmaraprmayjunjulaugsepoctnovdec" : "sunmontuewedthufrisat").indexOf(n.toLowerCase());
                return k % 3 ? "x" : String(k / 3 + (i === 3 ? 1 : 0)); // month names 1-12, weekday names 0-6; anything else fails the field check
            });
            if (cr && [[0, 59], [0, 23], [1, 31], [1, 12], [0, 7]].every(([lo, hi], i) => named(cr[i + 1], i).split(",").every(p => {
                const m = /^(?:\*|(\d{1,2})(?:-(\d{1,2}))?)(?:\/(\d{1,2}))?$/.exec(p);
                return !!m && (m[1] === undefined || (+m[1] >= lo && +m[1] <= hi && (m[2] === undefined || (+m[2] >= lo && +m[2] <= hi)))) && (m[3] === undefined || (+m[3] >= 1 && +m[3] <= hi));
            })) && (cr.slice(1, 6).some(f => f.includes("*")) || /^(?:[a-z_][\w.-]*\s+)?(?:\/|~\/|\.\.?\/|\$\{?[A-Za-z_]|[\w.-]+\.(?:sh|bash|py|pl|rb|js|php)(?:\s|$))/.test(cr[6] || "")))
                return "schedule";
        }
        if (/^@(?:reboot|yearly|monthly|weekly|daily|hourly)\b/.test(t))
            return "schedule"; // cron @-shortcut
        if (/^\s*[{[]/.test(t) && /[}\]]\s*$/.test(t) && /[:,]/.test(t))
            return "data_object"; // JSON / array (cheap start/end probe)
        if (/^\s*<\?xml\b/.test(t) || /^\s*<!DOCTYPE\s+html/i.test(t) || /<html[\s>]/i.test(t))
            return "html"; // XML / HTML document
        if (/^\s*<[a-z][\w-]*(?:\s[^>]*)?>[\s\S]*<\/[a-z][\w-]*>\s*$/i.test(t))
            return "code"; // markup fragment
        if (/[.#][\w-]+\s*\{[^}]*:[^}]*\}/.test(t) || /@(?:media|import|keyframes)\b/.test(t))
            return "css"; // CSS
        if (/^---\s*$/m.test(t) && /^[\w.-]+:\s/m.test(t))
            return "description"; // YAML
        if (/^#{1,6}\s+\S/m.test(t) || /\[[^\]]+\]\([^)]+\)/.test(t) || /^```/m.test(t))
            return "article"; // Markdown
        // Flattened CSV: cliphist joins rows with spaces, so the newline-based
        // detector is dead on real previews. Require many tight commas, few
        // prose-style ", ", and at least two space-separated segments that each
        // carry 2+ commas (i.e. 2+ flattened rows), so a single comma list is out.
        if (oneLine && !/[{}();]/.test(t)) {
            const tight = (t.match(/[^\s,],(?=[^\s,])/g) || []).length;
            if (tight >= 8 && tight >= 4 * (t.match(/, /g) || []).length && t.split(/\s+/).filter(w => (w.match(/,/g) || []).length >= 2).length >= 2)
                return "table";
        }
        if (/^#[0-9a-f]{3,8}$/i.test(t) || /\brgba?\([\d\s,.%]+\)/i.test(t) || /\bhsla?\([\d\s,.%]+\)/i.test(t))
            return "palette"; // colour
        if (/^\/(?:\\.|[^/\\\n]){2,}\/[gimsuy]*$/.test(t))
            return "regular_expression"; // /pattern/flags
        if (/\b(?:Traceback \(most recent call last\)|Exception in thread|at [\w.$]+\([\w.]+:\d+\)|panic:|ECONNREFUSED|Segmentation fault)/.test(t))
            return "bug_report"; // stack trace / crash (no trailing \b — branches ending in ")" or ":" have no boundary there)
        if (/^\[?(?:\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}|\d{2}:\d{2}:\d{2})\b/.test(t) && /\b(?:ERROR|WARN|INFO|DEBUG|TRACE|FATAL)\b/.test(t))
            return "receipt_long"; // log line
        if (/^\S+ \S+ \S+ \[\d{2}\/[A-Z][a-z]{2}\/\d{4}:\d{2}:\d{2}:\d{2} [+-]\d{4}\] "/.test(t) || /^[A-Z][a-z]{2} [ \d]\d \d{2}:\d{2}:\d{2} \S+ [\w.\/-]+(?:\[\d+\])?: /.test(t))
            return "receipt_long"; // web access log (Apache/nginx) or syslog line
        if (oneLine && /^[A-Z][A-Z0-9_]{2,}=\S/.test(t))
            return "settings"; // env / config assignment
        if (/^\[[\w.\- ]+\]$/.test(t))
            return "settings"; // TOML / INI table header
        // Dockerfile: case-sensitive FROM + lowercase image ref (a registry host may
        // lead with digits), then end or another instruction. A lone word needs an
        // image shape (tag, @sha256 digest, registry path, $ARG), a known base image
        // or scratch, an uppercase multi-stage "AS <stage>", or a following
        // instruction -- so "FROM home", "FROM $999" and "FROM 9/24" in a note are
        // not build files.
        if (/^FROM /.test(t)) {
            const df = /^FROM (?:--platform=\S+ )?([a-z$][\w.\/:@${}-]*|\d[\w-]*\.[\w.-]+(?::\d+)?\/[\w.\/:@${}-]+)(?: (AS) \w+| as \w+)?(\s+(?:RUN|COPY|ADD|WORKDIR|ENV|ARG|CMD|ENTRYPOINT|EXPOSE|LABEL|USER|VOLUME|HEALTHCHECK|SHELL|ONBUILD|STOPSIGNAL|MAINTAINER)\b[\s\S]*)?$/.exec(t);
            if (df && (df[2] || df[3] || /[:\/]|@sha256:|^\$\{?[A-Za-z_]/.test(df[1]) || /^(?:scratch|ubuntu|debian|alpine|fedora|archlinux|centos|rockylinux|almalinux|amazonlinux|oraclelinux|busybox|python|node|golang|rust|ruby|php|perl|gcc|openjdk|eclipse-temurin|amazoncorretto|maven|gradle|elixir|erlang|haskell|nginx|httpd|caddy|traefik|haproxy|postgres|mysql|mariadb|mongo|redis|memcached|rabbitmq|elasticsearch|jenkins|wordpress|grafana|influxdb|kalilinux)$/.test(df[1])))
                return "deployed_code";
        }
        if (/^"[\w@/.-]+"\s*:\s*"[~^>=<*]*\d[\w.*-]*",?$/.test(t))
            return "package_2"; // package.json version pin
        if (/^[A-Za-z][\w.-]*(?:\[[\w,]+\])?\s*(?:==|>=|<=|~=|!=)\s*\d+(?:\.\d+){1,2}(?:[-+][\w.]+)?$/.test(t))
            return "package_2"; // requirements.txt / pip version pin (dotted-quad IPs excluded)
        if (/^(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|TRACE|CONNECT)\s+\S+\s+HTTP\/\d/.test(t))
            return "http"; // HTTP request line
        if (/^(?:Authorization|Content-Type|Content-Length|User-Agent|Accept|Accept-Encoding|Accept-Language|Cookie|Set-Cookie|Host|Referer|Origin|Cache-Control|Connection|Location|Server|X-[\w-]+):\s+\S/.test(t))
            return "http"; // HTTP header line
        if (/^\?[\w%.+-]+=[^&\s]*(?:&[\w%.+-]+=[^&\s]*)*$/.test(t))
            return "manage_search"; // URL query string (a leading "?" makes even one key=value pair a query)
        if (/^[\w.-]+=[^;\s]+(?:;\s*[\w.-]+=[^;\s]*)+$/.test(t))
            return "cookie"; // cookie / semicolon key=value list
        if (/\\(?:documentclass|usepackage|begin\{|end\{|section\*?\{|subsection|textbf|item\b)/.test(t))
            return "functions"; // LaTeX
        if (/^@[A-Za-z]+\{[^,\s]+,/.test(t))
            return "menu_book"; // BibTeX entry
        if (/^\.\.\s+[\w-]+::(?:\s|$)/.test(t))
            return "article"; // reStructuredText directive
        if (/^git@[\w.-]+:[\w./~-]+(?:\.git)?$/.test(t))
            return "commit"; // git SSH remote
        if (/^(?:origin|upstream)\/[\w./-]+$/.test(t) || /^refs\/(?:heads|remotes|tags)\/[\w./-]+$/.test(t))
            return "account_tree"; // git ref
        if (/;\s*(?:done|fi|esac)\b/.test(t) && /[$~\/|>&]|;\s*(?:do|then)\b/.test(t))
            return "terminal"; // shell loop / conditional tail ("; done", "; fi", "; esac") with shell context, so "tired; done for today" is prose
        if ((/\banchors\.[a-z]\w*\s*:|\bimplicit(?:Width|Height)\b|\bBehavior on [a-z]\w*\s*\{|\bQt\.(?:alpha|rgba|binding|callLater|darker|lighter)\(|\bTokens\.(?:padding|spacing|margin|radius|animation)\b|\bColours\.palette\./.test(t)) && (t.match(/\b[a-z][\w.]*:\s/g) || []).length >= 2)
            return "widgets"; // QML / Quickshell snippet (with or without braces)
        // Code snippet: a code-shaped token, but NOT prose that merely quotes one.
        // Strong tokens (braces, =>, ::, tags, def/function name(, const|let|var
        // x =, class Name followed by ( { or a ':' that ends the text or opens a
        // Python body, real import / from-import forms, "return x;" not followed
        // by prose) decide unless the text is a prose-dominant paragraph. Weak
        // ones -- an attached arrow into a lowercase member or a method call
        // (a->b, $this->db, p->Get(), ") ->") or a semicolon in code context (not
        // "; word" followed by a comma, a sentence end or another word) -- count
        // only when the text has almost no English function words and is not a
        // "label: value; label: value" list (one opening on a CSS property name,
        // a CSS length or a type annotation excepted), so a UI path
        // "Settings->Display", a sentence with a stray ';' ("persists; weird, ...")
        // and "mon: gym; tue: rest" stay prose while "display: flex;" is code.
        if (t.length < 800) {
            const strongCode = /[{}]|=>|::|<\/?\w+>|\b(?:function|def)\s+\w+\s*\(|\b(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=|\bclass\s+[A-Z_]\w*\s*(?:[({]|:(?:$|\s*(?:pass\b|def\s|@|"""|'''|[A-Za-z_]\w*\s*[=:(])))|^import\s+(?!(?:it|this|that|them|these|those|the|a|an|my|your|all|everything)\b)[\w.]+(?:\s+as\s+\w+)?;?$|^import\s*\{|^import\s+(?:\*\s+as\s+)?[\w$]+\s+from\s+["']|^import\s+["']|\bfrom\s+[\w.]+\s+import\b|\breturn\s+[^\s;]{1,80};(?!\s+(?!(?:done|fi|esac|then|do|else|elif)\b)[A-Za-z]+(?:'[a-z]+)?(?:,|[.!?]+(?:\s|$)|\s+[A-Za-z]|$))/.test(t);
            if (strongCode || /\w->(?:[a-z_$]|[A-Z]\w*\()|\)\s*->|;(?!\s+[A-Za-z]+(?:'[a-z]+)?(?:,|[.!?]+(?:\s|$)|\s+[A-Za-z]|$))\s*(?:$|[}\])"']|[A-Za-z_$])/.test(t) && !(/^[A-Za-z][\w ]*:[^;{}=]*(?:;[\w ]+:[^;{}=]*)*;?$/.test(t) && !/^(?:display|position|top|right|bottom|left|inset|width|height|margin|padding|border|outline|background|color|font|flex|grid|gap|order|float|clear|overflow|opacity|visibility|cursor|content|transform|transition|animation|filter|resize|zoom|appearance|translate|rotate|scale)\s*:|:\s*(?:\d+(?:px|r?em|pt|v[hw])|string|number|boolean|int|str|bool|float)\s*(?:;|$)/.test(t))) {
                const fw = (t.match(/\b(?:the|that|was|were|are|you|your|we|they|there|which|would|should|could|because|have|has|been|when|what|so|but|can|will)\b/gi) || []).length;
                if (fw < (strongCode ? Math.max(6, 2 * (t.match(/[{};]|=>|->|::/g) || []).length) : 3))
                    return "code";
            }
        }

        // -- files & paths (real paths only; bare "name.ext" was handled above) --
        const pathLike = /^~?(?:\/[\w.@ +-]+)+\/?$/.test(t) || /^[A-Za-z]:[\\/]/.test(t) || /^\.\.?\/[\w./ +-]+$/.test(t);
        if (pathLike) {
            if ((t.match(/(?:^|\s)~?\.{0,2}\//g) || []).length >= 3)
                return "folder_copy"; // a space-separated listing of 3+ paths (e.g. find output)
            const pi = extIcon(t);
            if (pi)
                return pi;
            if (/^~/.test(t))
                return "home";
            return "folder";
        }
        // Bare relative path (no leading / ~ ./ ..): only treated as a path when its
        // final segment carries a known extension, so him/her, and/or, 24/7 don't match.
        if (oneLine && /^(?:[\w.@ +-]+\/)+[\w.@ +-]+$/.test(t)) {
            const pi = extIcon(t);
            if (pi)
                return pi;
        }

        // -- everyday --
        if (/^-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+$/.test(t))
            return "location_on"; // lat,long
        if (/^\d{1,6}\s+(?:[NSEW]\.?\s+)?(?:(?!(?:To|For|Of|The|And|In|On|At|A|An)\s)[A-Z][\w'-]*\s+){1,3}(?:St|Street|Rd|Road|Ave|Avenue|Blvd|Boulevard|Dr|Drive|Ln|Lane|Ct|Court|Pl|Place|Way|Pkwy|Parkway|Hwy|Highway|Ter|Terrace|Cir|Circle)\b\.?(?:\s+(?:N|S|E|W|NE|NW|SE|SW))?(?:\s*,.*)?$/.test(t))
            return "location_on"; // US street address (name words skip To/For/Of/The/And/In/On/At/A/An, so a "3 Ways To Drive" title is not one)
        if (/^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?$/.test(t) || /^\d{1,2}\/\d{1,2}\/\d{2,4}$/.test(t) || /^\d{1,2}-\d{1,2}-\d{4}$/.test(t) || /^\d{1,2}\.\d{1,2}\.(?:19|20)\d{2}$/.test(t))
            return "event"; // date / timestamp (ISO, M/D/Y, M-D-YYYY, and dotted D.M.YYYY / M.D.YYYY — year last, so it never collides with a year-first calver version)
        if (/^\d{1,2}:\d{2}(?::\d{2})?\s*(?:[AaPp]\.?[Mm]\.?)?$/.test(t))
            return "schedule"; // time
        if (/^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$/.test(t.replace(/\s/g, "")))
            return "account_balance"; // IBAN
        if (/^(?:\d[ -]?){15,16}$/.test(t) && /^\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{1,4}$/.test(t))
            return "credit_card"; // credit-card number
        if (/^[€$£¥₿]\s?\d[\d,.]*$/.test(t) || /^\d[\d,.]*\s?(?:USD|EUR|GBP|JPY|BTC)$/i.test(t))
            return "payments"; // currency amount (both anchored — unanchored form was O(n²) on comma-heavy input)
        if (/^\d+(?:\.\d+)?\s?%$/.test(t))
            return "percent"; // percentage
        if (/^v?\d+\.\d+\.\d+(?:[-+][\w.]+)?$/.test(t) && !/^\d{3}\.\d{3}\.\d{4}$/.test(t))
            return "sell"; // semver / version tag (a 3-3-4 digit run is a dotted phone number, left to the phone rule)
        const isbnOk = s => {
            const d = s.replace(/[ -]/g, "");
            if (/^\d{9}[\dXx]$/.test(d)) {
                let sum = 0;
                for (let i = 0; i < 10; i++)
                    sum += (10 - i) * (i < 9 ? +d[i] : (/[Xx]/.test(d[9]) ? 10 : +d[9]));
                return sum % 11 === 0;
            }
            if (/^97[89]\d{10}$/.test(d)) {
                let sum = 0;
                for (let i = 0; i < 13; i++)
                    sum += (i % 2 ? 3 : 1) * +d[i];
                return sum % 10 === 0;
            }
            return false;
        };
        const isbn = t.replace(/^ISBN(?:-1[03])?:?\s*/i, "");
        if ((/^97[89]\d{10}$/.test(isbn) || /^(?:97[89][ -])?\d{1,5}[ -]\d{1,7}[ -]\d{1,7}[ -][\dXx]$/.test(isbn) || (isbn !== t && /^\d{9}[\dXx]$/.test(isbn))) && isbnOk(isbn))
            return "menu_book"; // ISBN with a valid checksum: a bare 978/979 ISBN-13, a hyphenated / spaced one ending in its check digit, or an "ISBN"-prefixed ISBN-10 (a bare 10-digit run is far more often an order / account number, and 1 in 11 of them pass the ISBN-10 check)
        if (/^\d{6}$/.test(t) || /^\d{3} \d{3}$/.test(t))
            return "pin"; // six-digit one-time / verification code (before the phone rule, which would take "123 456")
        if (/^\+?\(?\d[\d\s().-]{6,}$/.test(t)) {
            const pg = t.replace(/^\+/, "").split(/[\s().-]+/).filter(g => g);
            const pn = pg.join("").length;
            if (t[0] === "+" ? (pg.length > 1 ? pn >= 7 && pn <= 15 && pg.slice(1).every(g => g.length >= 2) && !pg.every(g => /^(?:19|20)\d\d$/.test(g)) : pn >= 8 && pn <= 15) : (/^(?:1[ .-]?)?(?:\(\d{3}\)[ .-]?|[2-9]\d{2}[ .-])[2-9]\d{2}[ .-]\d{4}$/.test(t) && /[-.]|^\(|^1[ .]/.test(t)) || /^[2-9]\d{2}[-.]\d{4}$/.test(t) || /^1?[2-9]\d{2}[2-9]\d{6}$/.test(t) || (/^380[ .-]/.test(t) && pn === 12) || (/^\(?0\d{2,4}\)?[ -]\d[\d -]*$/.test(t) && pg.length >= 3 && pn >= 10 && pn <= 11 && pg.every(g => g.length >= 2)))
                return "call"; // phone: after "+", 7-15 digits with every group after the first 2+ digits and not all years; without it, a NANP 3-3-4 shape carrying a real marker (parens, a dash/dot, or a leading "1") so a pure-space port triple like "389 636 3268" stays a list, a dash/dot local 555-1234, a 10-digit run, a "380 ..." unprefixed Ukrainian number, or a trunk-prefix local number (020 7946 0958) -- so "22 80 443 8080", "139 445 3389" and "585 352 2400" are lists, not numbers
        }
        if (/^[-+(]?\s*[\d.]+(?:\s*[-+*/^%]\s*[\d.()]+)+$/.test(t))
            return "calculate"; // arithmetic expression
        if (/^(?:true|false|yes|no|on|off|enabled|disabled)$/i.test(t))
            return "toggle_on"; // boolean-ish
        if (/^-?\d+(?:[.,]\d+)?$/.test(t) || /^0x[0-9a-f]+$/i.test(t) || /^0b[01]+$/i.test(t))
            return "tag"; // number
        if (/^["“'][\s\S]+["”']$/.test(t))
            return "format_quote"; // quoted text
        if ((t.match(/(?:^|[.:!?)"]\s)[-•]\s[A-Z("]/g) || []).length >= 2)
            return "format_list_bulleted"; // flattened bullet list (cliphist joins the rows, so the newline form is dead)
        if (t.length > 80 && /^(?:Hi|Hello|Hey|Dear|Good (?:morning|afternoon|evening))\s+(?!(?:Claude|Codex|ChatGPT|GPT|Gemini|Siri|Copilot|Grok|Alexa|Google|World)[\s,])(?:(?:Mr|Mrs|Ms|Mx|Dr|Prof)\.?\s+)?[A-Z][\w'-]*(?:\s+[A-Z][\w'-]*)?\s*,/.test(t))
            return "mail"; // email / letter body (greeting + name + comma; an addressed AI assistant is not a letter recipient)
        if (/^\S+\?\s*$/.test(t) || /^(?:\d{1,3}[.)]\s+)?(?:who|what|when|where|why|how|which|can|does|is|are)\b[\s\S]*\?$/i.test(t))
            return "help"; // question (optionally prefixed with a list number, "1. What ...?")
        if (/^[A-Z][A-Z0-9]{1,9}-\d{1,6}$/.test(t))
            return "confirmation_number"; // issue / ticket key (JIRA-4521)
        if (/^(?:\d{2,5}\s?[x×]\s?\d{2,5}|\d{1,2}:\d{1,2})$/.test(t))
            return "aspect_ratio"; // resolution / aspect ratio
        if (/^\d+(?:\.\d+)?\s?(?:[KMGTP]i?B|[kMGT]B|bytes?|bits?)$/.test(t))
            return "storage"; // data / file size
        if (/^\d+(?:\.\d+)?\s?(?:mm|cm|km|in|inch(?:es)?|ft|yd|mi|kg|mg|lb|oz|ml|cl|px|pt|em|rem|vh|vw|deg|°[CF]?|Hz|kHz|MHz|GHz|fps|dpi|ppi|mph|kmh|bpm|rpm)$/.test(t))
            return "straighten"; // measurement / unit
        if (/^(?:(?:Ctrl|Control|Alt|Shift|Cmd|Command|Super|Win|Meta|Option|Opt|Fn|⌘|⌃|⌥|⇧)\s*\+\s*){1,4}(?:[A-Za-z0-9]|F\d{1,2}|Esc|Escape|Tab|Enter|Return|Space|Del|Delete|Backspace|Ins|Home|End|Up|Down|Left|Right|PgUp|PgDn)$/.test(t))
            return "keyboard"; // keyboard shortcut
        if (/^(?:\uD83C[\uDC00-\uDFFF]|\uD83D[\uDC00-\uDFFF]|\uD83E[\uDD00-\uDFFF]|[☀-➿⬀-⯿]️?|[‍️])+$/.test(t) && /[\uD83C-\uDBFF]|[☀-➿⬀-⯿]/.test(t))
            return "emoji_emotions"; // emoji-only
        if (/^[¡-⯿]$/.test(t) && !/[A-Za-zÀ-ɏͰ-ӿ]/.test(t))
            return "special_character"; // a lone symbol character (arrow, operator)
        if (/[√∛∑∫≈≠≤≥±]/.test(t) && /\d/.test(t) && t.length <= 200 && /[\w)]\s*=\s*[\w(√∛-]|[√∛∑∫]\s*[\d(a-z]|\d\s*[-+*\/×÷^±]\s*\d|(?:^|[\s(])[A-Za-zα-ω]\s*[≈≠≤≥<>]\s*-?\d/.test(t))
            return "calculate"; // worked maths with symbols (needs an equation: "x = √2 ≈ 1.41", "n ≤ 9"; prose using ≈ as shorthand is out)
        // Natural-language prose: a sentence end within the first 1000 chars (the
        // scan restarts at every word, so it is bounded rather than run over a
        // giant paste; the middle class excludes . ! ? so it can't overlap the
        // terminator), no code characters
        // (a prose semicolon "; word" is allowed), and at least one lowercase-
        // initial word so a title/product name like "Acme Widget Co." is out. An
        // abbreviation dot (Co. Inc. Ltd. Mr. Dr. St. vs. etc.) followed by more
        // text is not a sentence end, so "Acme Co. Model X shirt" is not prose.
        if (/(?:^|[^A-Za-z])[A-Za-z]{2}[^{}<>=|\\.!?]*[.!?]["')\]]?(?:\s+[A-Z"'(]|\s*$)/.test(t.slice(0, 1000).replace(/\b(Co|Corp|Inc|Ltd|LLC|Mr|Mrs|Ms|Dr|St|Jr|Sr|Prof|vs|etc)\.(?=\s)/g, "$1")) && !/[{}=<>]|;(?!\s+[A-Za-z]{2,}(?:[\s.,!?]|$))|=>|::|\bfunction\s*[\w$]*\s*\(/.test(t) && /\s/.test(t) && /(?:^|\s)[a-z]{2}/.test(t))
            return "subject"; // natural-language prose / sentences
        // Prose without a sentence terminator: his own lowercase messages, search
        // phrases and clipped sentences. Only reached after every content rule has
        // declined, so it just widens 'subject' -- 6+ words, several function words,
        // and no code/shell/flag/path characters.
        if (oneLine && (t.match(/\s+/g) || []).length >= 5 && !/[{};=<>$\\|]|::|=>|(?:^|\s)--?[A-Za-z]|(?:^|\s)~?\.{0,2}\//.test(t) && (t.match(/\b(?:the|a|an|and|or|but|to|of|in|on|at|for|with|from|is|are|was|were|be|it|i|you|we|my|your|this|that|not|no|so|if|when|then|can|do|does|did|have|has|how|what|why|want|just|about|into|than|also)\b/gi) || []).length >= 4)
            return "subject"; // prose without end punctuation

        // -- structural fallback: unclassified text, keyed on size --
        if (oneLine && /^\S{8,64}$/.test(t) && /[a-z]/.test(t) && /[A-Z]/.test(t) && /\d/.test(t) && /[!#$^&*~?]/.test(t) && !/%[0-9A-Fa-f]{2}|[\/.()]/.test(t)
            && !/^#/.test(t))
            return "password"; // generated password: a lone token with all four character classes (not a leading '#' hashtag; a CamelCase human password like "HelloWorld1!" still counts)
        if (/^[─━═┄┈╌╍╎╏-]{8,}$/.test(t))
            return "horizontal_rule"; // box-drawing / divider line
        if (oneLine && /^\S+$/.test(t) && t.length <= 24)
            return "text_fields"; // a single short token
        if (t.length <= 80)
            return "short_text"; // small
        if (t.length <= 400)
            return "notes"; // medium
        return "article"; // large / document
    }

    // Parses a pure-colour entry (hex / rgb[a] / hsl[a]) into a QML colour string
    // ("#AARRGGBB" when alpha is present, else "#RRGGBB"), or "" if it isn't a lone
    // colour. Lets the delegate paint the real colour as the entry's swatch.
    function colourOf(text: string): string {
        const t = text.trim();
        const clamp = (n, hi) => Math.max(0, Math.min(hi, n));
        const h2 = n => {
            const s = clamp(Math.round(n), 255).toString(16);
            return s.length < 2 ? "0" + s : s;
        };

        let m = t.match(/^#([0-9a-fA-F]{3,8})$/);
        if (m) {
            const h = m[1].toLowerCase();
            if (h.length === 3)
                return "#" + h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
            if (h.length === 6)
                return "#" + h;
            if (h.length === 4) // CSS #rgba -> Qt #aarrggbb
                return "#" + h[3] + h[3] + h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
            if (h.length === 8) // CSS #rrggbbaa -> Qt #aarrggbb
                return "#" + h.slice(6, 8) + h.slice(0, 6);
            return ""; // 5 or 7 digits: not a valid hex colour
        }

        const chan = (v, base) => v.trim().endsWith("%") ? parseFloat(v) / 100 * base : parseFloat(v);
        const alpha = v => h2(v.trim().endsWith("%") ? parseFloat(v) / 100 * 255 : parseFloat(v) * 255);

        m = t.match(/^rgba?\(\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*(?:[,/]\s*([\d.]+%?)\s*)?\)$/i);
        if (m) {
            const rgb = h2(chan(m[1], 255)) + h2(chan(m[2], 255)) + h2(chan(m[3], 255));
            return m[4] === undefined ? "#" + rgb : "#" + alpha(m[4]) + rgb;
        }

        m = t.match(/^hsla?\(\s*([\d.]+)(?:deg)?\s*[, ]\s*([\d.]+)%\s*[, ]\s*([\d.]+)%\s*(?:[,/]\s*([\d.]+%?)\s*)?\)$/i);
        if (m) {
            const hue = (((parseFloat(m[1]) % 360) + 360) % 360) / 360;
            const s = clamp(parseFloat(m[2]) / 100, 1);
            const l = clamp(parseFloat(m[3]) / 100, 1);
            const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            const p = 2 * l - q;
            const comp = tc => {
                tc = tc < 0 ? tc + 1 : (tc > 1 ? tc - 1 : tc);
                if (tc < 1 / 6)
                    return p + (q - p) * 6 * tc;
                if (tc < 1 / 2)
                    return q;
                if (tc < 2 / 3)
                    return p + (q - p) * (2 / 3 - tc) * 6;
                return p;
            };
            const rgb = h2(comp(hue + 1 / 3) * 255) + h2(comp(hue) * 255) + h2(comp(hue - 1 / 3) * 255);
            return m[4] === undefined ? "#" + rgb : "#" + alpha(m[4]) + rgb;
        }

        return "";
    }

    // Type-appropriate icon for a cliphist binary entry, from its descriptor
    // (e.g. "png 1815x596", "1.2 MiB application/pdf"). Images already render a
    // thumbnail; this covers everything else so non-images stop showing "image".
    function iconForBinary(desc: string): string {
        if (/\b(?:png|jpe?g|gif|bmp|webp|tiff?|svg|ico|heic|avif)\b/i.test(desc))
            return "image";
        if (/\b(?:mp3|flac|wav|ogg|opus|aac|m4a|wma|audio)\b/i.test(desc))
            return "music_note";
        if (/\b(?:mp4|mkv|mov|avi|webm|flv|wmv|m4v|mpe?g|video)\b/i.test(desc))
            return "movie";
        if (/\b(?:zip|tar|gz|xz|bz2|7z|rar|zst|gzip|compress)\b/i.test(desc))
            return "folder_zip";
        if (/\bpdf\b/i.test(desc))
            return "picture_as_pdf";
        return "draft"; // unknown binary blob
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

        readonly property int tabIdx: entry.raw.indexOf("\t")
        readonly property string entryId: entry.tabIdx >= 0 ? entry.raw.slice(0, entry.tabIdx) : ""
        readonly property string preview: entry.tabIdx >= 0 ? entry.raw.slice(entry.tabIdx + 1) : entry.raw

        // cliphist renders binaries as "[[ binary data 234 KiB png 1815x596 ]]"
        readonly property var binMatch: entry.preview.match(/^\[\[ binary data (.+) \]\]$/)
        readonly property bool isImage: !!entry.binMatch && /\b(?:png|jpe?g|gif|bmp|webp|tiff?|svg|ico)\b/i.test(entry.binMatch[1])
        // The descriptor already carries the image's pixel size, so the reader
        // knows the real aspect AND the real resolution from frame 0 -- no
        // decode, no waiting. Null when cliphist could not determine it (it
        // omits the WxH for formats it cannot probe, e.g. some svg/ico), in
        // which case the reader falls back to measuring a decoded copy.
        readonly property var imgDims: {
            if (!entry.isImage)
                return null;
            const m = entry.binMatch[1].match(/\b(\d+)x(\d+)\b/);
            if (!m)
                return null;
            const w = parseInt(m[1]);
            const h = parseInt(m[2]);
            return w > 0 && h > 0 ? {
                w,
                h
            } : null;
        }

        readonly property string name: {
            if (entry.binMatch)
                return entry.isImage ? "Image" : "Binary data";
            return entry.preview.replace(/\s+/g, " ").trim();
        }
        // Exact counts from the decoded-content cache when known (previews are
        // truncated at 999 chars, so entry.name.length lies for long clips);
        // preview length as the interim value until the background count lands.
        readonly property string desc: {
            if (entry.binMatch)
                return entry.binMatch[1];
            const cached = root.lineCounts[entry.entryId];
            // Previews are truncated at 999 chars -- until the real count
            // lands, a capped length is a lie, so say so instead.
            if (!cached && entry.name.length >= 999)
                return "999+ characters";
            const n = cached ? cached.chars : entry.name.length;
            let s = `${n} ${n === 1 ? "character" : "characters"}`;
            if (cached)
                s += ` · ${cached.lines} ${cached.lines === 1 ? "line" : "lines"}`;
            return s;
        }

        function onClicked(list: var): void {
            root.activate(entry.raw);
            list.screenState.launcher = false;
        }

        function del(): void {
            root.deleteEntry(entry.raw);
        }
    }

    Process {
        id: stageProc

        command: ["cliphist", "-preview-width", "999", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.stagedEntries = text.split("\n").filter(l => l.length > 0)
        }
    }

    Process {
        id: listProc

        // 999, NOT huge: rows render one elided line and the reader decodes full
        // content itself, so longer previews buy nothing -- but they cost real
        // main-thread time (Text layout of giant single-line strings on every
        // delegate creation, entryFor hashing of giant keys each keystroke),
        // which dropped animation frames and left ghost rows mid-fade.
        command: ["cliphist", "-preview-width", "999", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.rawEntries = text.split("\n").filter(l => l.length > 0);
                root.updateLineCounts();
            }
        }
    }

    Process {
        id: delProc

        property string line: ""

        command: ["sh", "-c", "printf '%s' \"$1\" | cliphist delete", "del", delProc.line]
        onExited: root.reload()
    }

    Process {
        id: prefetchProc

        property string entryId: ""
        property string line: ""

        command: ["sh", "-c", "printf '%s' \"$1\" | cliphist decode", "clip", prefetchProc.line]
        stdout: StdioCollector {
            // Same trailing-newline convention as the reader's own decode, or a
            // prefetched entry would differ from a freshly decoded one by a
            // character and re-lay-out on open.
            onStreamFinished: root.cacheDecoded(prefetchProc.entryId, text.replace(/\n$/, ""))
        }
        onExited: root.pumpPrefetch()
    }

    Process {
        id: lineCountProc

        property string known: " "

        command: ["sh", "-c", `
            cliphist list | while IFS= read -r line; do
                case "$line" in *'[[ binary data'*) continue;; esac
                id=$(printf '%s' "$line" | cut -f1)
                case "$1" in *" $id "*) continue;; esac
                printf '%s' "$line" | cliphist decode | awk -v id="$id" '
                    { n++; c += length($0) }
                    END { if (!n) n = 1; printf "%s\\t%d\\t%d\\n", id, n, c + n - 1 }'
            done`, "lc", lineCountProc.known]
        // Streamed per entry, not collected: cliphist lists newest-first, so
        // the rows actually on screen get exact counts within the first
        // moments instead of after the WHOLE history has been decoded.
        stdout: SplitParser {
            onRead: data => {
                const [id, lines, chars] = data.split("\t");
                if (!id)
                    return;
                const counts = Object.assign({}, root.lineCounts);
                counts[id] = {
                    lines: parseInt(lines, 10),
                    chars: parseInt(chars, 10)
                };
                root.lineCounts = counts;
            }
        }
    }

    Component.onCompleted: root.reload()
}
