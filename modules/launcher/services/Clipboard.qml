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
    // network addresses → shell/security commands → URLs/mail → data/code →
    // files/paths → everyday → structural fallback. Commands are matched before
    // URLs so a URL passed as an argument (curl/gobuster) can't hijack the icon.
    // Cybersecurity-leaning but everyday-complete.
    //
    // Called once per entry (stable binding), but clipboard lines can be enormous
    // (`-preview-width 99999`), so a length guard short-circuits huge pastes before
    // the full battery runs, and every pattern is anchored/linear (no nested
    // quantifiers) to stay ReDoS-safe on adversarial content.
    function iconFor(text: string): string {
        const t = text.trim();
        if (!t)
            return "content_paste";

        // Giant blob: skip the battery, keep only three cheap probes.
        if (t.length > 20000) {
            if (/https?:\/\//i.test(t))
                return "link";
            if (/^\s*[{[]/.test(t) && /[}\]]\s*$/.test(t))
                return "data_object";
            return "notes";
        }

        const oneLine = !/\n/.test(t);

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
            if (/\.(?:py|js|ts|tsx|jsx|c|cpp|cc|h|hpp|rs|go|rb|php|java|kt|swift|sh|lua|pl|sql|qml|vue|svelte)$/i.test(s))
                return "folder_code"; // a source-file reference (path/filename), distinct from a pasted code snippet
            if (/\.(?:json|ya?ml|toml|ini|conf|cfg|env|xml)$/i.test(s))
                return "settings";
            if (/\.(?:txt|md|log)$/i.test(s))
                return "description";
            if (/\.(?:pcap|pcapng|cap)$/i.test(s))
                return "network_check"; // packet capture
            if (/\.(?:evtx|etl|dmp|mdmp|mem|vmem|vmsn|e01|ex01|aff|aff4|lime)$/i.test(s))
                return "storage"; // memory / disk / event-log forensic image
            return "";
        };

        // -- secrets: keys, certs, tokens --
        if (/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/.test(t))
            return "vpn_key"; // PEM private key
        if (/-----BEGIN (?:CERTIFICATE|PUBLIC KEY)-----/.test(t))
            return "verified_user"; // cert / public key
        if (/-----BEGIN PGP (?:MESSAGE|SIGNATURE|SIGNED)/.test(t))
            return "enhanced_encryption"; // PGP block
        if (/^(?:ssh-(?:rsa|dss|ed25519)|ecdsa-sha2-\S+|sk-ssh-\S+)\s+[A-Za-z0-9+/]{20,}/.test(t))
            return "vpn_key"; // SSH public key
        if (/^eyJ[\w-]+\.[\w-]+\.[\w-]+$/.test(t))
            return "token"; // JWT
        if (/\b(?:AKIA|ASIA|AIza)[0-9A-Za-z]{16,}\b/.test(t) || /\b(?:gh[posru]|glpat)[-_][A-Za-z0-9_-]{20,}\b/.test(t) || /\b(?:sk|pk|rk)-[A-Za-z0-9]{20,}\b/.test(t) || /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/.test(t))
            return "key"; // AWS / Google / GitHub / GitLab / Stripe / OpenAI / Slack
        if (oneLine && /^(?:export\s+)?[A-Za-z_][\w.]*(?:PASS(?:WORD|WD)?|SECRET|TOKEN|API[_-]?KEY|PRIVATE[_-]?KEY|CREDENTIAL)[\w.]*\s*[:=]\s*\S/i.test(t))
            return "password"; // secret assignment

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
            return "fingerprint"; // UUID / GUID

        // -- network addresses (anchored: an IP inside a command must not hijack it) --
        if (/^(?:bc1[a-z0-9]{23,59}|[13][1-9A-HJ-NP-Za-km-z]{25,39})$/.test(t) || /^0x[a-f0-9]{40}$/i.test(t) || /^[LM][a-km-zA-HJ-NP-Z1-9]{26,33}$/.test(t))
            return "currency_bitcoin"; // BTC / ETH / LTC address
        if (/^(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(t))
            return "settings_ethernet"; // MAC
        if (/^(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?(?:\/\d{1,2})?$/.test(t))
            return "lan"; // IPv4 / socket / CIDR
        if (/^[0-9a-f:]+$/i.test(t) && /:/.test(t) && (/::/.test(t) || /[a-f]/i.test(t) || (t.match(/:/g) || []).length >= 3))
            return "lan"; // IPv6-ish (must contain a colon, plus "::"/hex-letter/3+ colons — so H:M:S times and colon-less hex like an IBAN fall through)

        // -- encoded blobs --
        if (/^H4sI[A-Za-z0-9+/]{8,}={0,2}$/.test(t))
            return "folder_zip"; // gzip stream, base64-encoded (magic 1f 8b -> "H4sI")
        if (oneLine && /^[A-Za-z0-9+/]{64,}={0,2}$/.test(t))
            return "data_array"; // base64 blob
        if (/^[0-9a-f]{62}$/i.test(t))
            return "fingerprint"; // JARM TLS fingerprint (62 hex — before the hex-dump rule)
        if (oneLine && /^(?:[0-9a-f]{2}[\s:]?){24,}$/i.test(t))
            return "memory"; // raw hex dump
        if (oneLine && /^(?:0x)?[0-9a-fx]{2}(?:[\s:|][0-9a-fx]{2}){2,}\|?$/i.test(t))
            return "memory"; // short packet byte-string / content bytes (A0 03 02 01 17, XX placeholders)

        // -- shell prompt capture: a pasted terminal line (leading powerline glyph,
        //    user@host:path ending in a prompt char, or PowerShell prompt). Placed
        //    before the tool taxonomy so the whole line reads as "terminal" instead
        //    of being hijacked by an embedded tool name / URL / path. --
        if (/^(?:[◄❯➜▶►◆»◀○◎⋈]\s|┌──\(|└─|[\w.+-]+@[\w.:~/\[\]+-]*[$#%]\s|PS [A-Za-z]:\\)/.test(t))
            return "terminal";

        // -- security tooling & shell commands (before URLs: a URL arg must not hijack) --
        if (/(?:^|\|\s*|;\s*|&&\s*)(?:bash|sh)\s+-[a-z]*i[a-z]*\s+.*(?:>\s*&\s*)?\/dev\/(?:tcp|udp)\//i.test(t) || /\bnc\b.*-[a-z]*e[a-z]*\s+\/bin\//i.test(t) || /\b(?:rm\s+-rf\s+\/(?:\s|$)|chmod\s+(?:-R\s+)?777|:\(\)\s*\{\s*:\|:)/.test(t))
            return "warning"; // reverse shell / destructive / fork bomb
        if (/^(?:sudo\s+)?(?:nmap|masscan|rustscan|zmap|amass|subfinder|assetfinder|shodan|dnsrecon|dnsenum|fierce|theharvester|whatweb|wafw00f)\b/i.test(t))
            return "radar"; // recon / scanning
        if (/^(?:sudo\s+)?(?:tshark|tcpdump|wireshark|ngrep|termshark|dumpcap|tcpflow|bettercap|ettercap|arpspoof|mitmproxy|mitmdump)\b/i.test(t))
            return "network_check"; // packet capture / MITM
        if (/^(?:sudo\s+)?(?:snort|suricata|suricatasc|zeek|zeekctl|zeek-cut|broctl|chaosreader|joincap|capinfos|editcap|mergecap|reordercap|tcpick|nfdump|rita|argus|rwfilter|rwstats|stenographer|arkime)\b/i.test(t))
            return "sensors"; // NSM sensors / traffic analysis (Snort, Suricata, Zeek, ...)
        if (/^(?:sudo\s+)?(?:hashcat|john|hydra|medusa|ncrack|patator|hcxdumptool|aircrack-ng|airmon-ng|reaver|cewl|crunch)\b/i.test(t))
            return "password"; // credential cracking / wireless
        if (/^(?:sudo\s+)?(?:gobuster|feroxbuster|ffuf|dirb|dirbuster|wfuzz|nikto|wpscan|sqlmap|nuclei|arjun|dalfox|commix|xsstrike)\b/i.test(t))
            return "travel_explore"; // web fuzzing / vuln scan
        if (/^(?:sudo\s+)?(?:msfconsole|msfvenom|msfdb|meterpreter|searchsploit|setoolkit|beef|empire|sliver|havoc|cobaltstrike)\b/i.test(t))
            return "bug_report"; // exploitation / C2 frameworks
        if (/^(?:sudo\s+)?(?:enum4linux|netexec|crackmapexec|impacket-\S+|responder|bloodhound|sharphound|evil-winrm|smbclient|smbmap|rpcclient|ldapsearch|kerbrute|certipy|mimikatz|secretsdump)\b/i.test(t))
            return "security"; // AD / lateral movement / post-exploitation
        if (/^(?:sudo\s+)?(?:gdb|radare2|r2|objdump|readelf|strace|ltrace|checksec|pwndbg|ropper|ROPgadget|volatility|binwalk|foremost|steghide|zsteg|exiftool|strings)\b/i.test(t))
            return "biotech"; // reversing / forensics / stego
        if (/^(?:sudo\s+)?(?:ssh|scp|sftp|rsync|nc|ncat|socat|telnet|mosh)\b/i.test(t) || /^(?:ssh|telnet):\/\//i.test(t))
            return "terminal"; // remote / transfer
        if (/^(?:sudo\s+)?(?:curl|wget|httpie|xh|aria2c)\b/i.test(t) || /^https?\s+\S/i.test(t))
            return "http"; // HTTP clients (httpie `http`/`https` need a space, unlike a URL's `://`)
        if (/^git\s+/i.test(t))
            return "commit";
        if (/^(?:sudo\s+)?(?:docker|docker-compose|kubectl|podman|helm|nerdctl|k9s|minikube)\b/i.test(t))
            return "deployed_code"; // containers / orchestration
        if (/^(?:sudo\s+)?(?:terraform|ansible|ansible-playbook|vagrant|packer|pulumi)\b/i.test(t))
            return "cloud"; // IaC / provisioning
        if (/^(?:sudo\s+)?(?:apt|apt-get|dpkg|pacman|yay|paru|dnf|yum|zypper|apk|brew|nix-env|snap|flatpak)\b/i.test(t))
            return "package_2"; // package managers
        if (/^(?:sudo\s+)?(?:pip|pip3|npm|npx|pnpm|yarn|bun|cargo|go|gem|composer|poetry|uv)\b/i.test(t))
            return "package_2"; // language package managers
        if (/^(?:sudo\s+)?systemctl\b/i.test(t) || /^(?:sudo\s+)?(?:journalctl|dmesg|service)\b/i.test(t))
            return "settings"; // service / log management
        if (/^(?:sudo\s+)?(?:Get-WinEvent|Get-EventLog|Get-WmiObject|Get-CimInstance|gwmi|wmic|wevtutil|logman|auditpol)\b/i.test(t))
            return "fact_check"; // Windows event-log / WMI query (before the PowerShell Get-* rule)
        if (/^(?:powershell(?:\.exe)?|pwsh)\b.*-e(?:nc(?:odedcommand)?|c)\s+[A-Za-z0-9+/]{16,}/i.test(t))
            return "warning"; // PowerShell encoded command (suspicious)
        if (/^(?:sudo|bash|sh|zsh|fish|env|ls|pwd|cd|echo|printf|which|whereis|whoami|man|nano|vim|vi|emacs|chmod|chown|chgrp|mkdir|rmdir|rm|cp|mv|ln|readlink|realpath|basename|dirname|touch|cat|tee|less|tail|head|wc|grep|rg|awk|sed|cut|tr|sort|uniq|xargs|find|fd|stat|tar|gzip|gunzip|unzip|export|source|alias|kill|pkill|ps|top|htop|df|du|free|mount|umount|lsblk|lsof|lspci|lsusb|uname|uptime|sync|dd|useradd|usermod|passwd|su|chsh|crontab|ping|dig|nslookup|ip|ss|netstat|ifconfig|route|iptables|nft|ufw|sysctl|md5sum|sha1sum|sha256sum|base64|xxd|hexdump|openssl|gpg)\b/.test(t))
            return "terminal"; // generic shell / net / file utilities
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
        if (/\b(?:Section\s+\d+\s*\/\s*\d+|HTB Academy|Skills Assessment|Go to Questions)\b/i.test(t))
            return "school"; // HTB Academy / course material
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
            return "folder"; // file URI
        if (/^s?ftp:\/\//i.test(t))
            return "folder_shared"; // (s)ftp URL
        if (/^https?:\/\/\S+$/i.test(t))
            return "link"; // the whole entry is one URL — a URL merely embedded in text/code/logs/SQL falls through to those rules
        if (/^mailto:/i.test(t) || /^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(t))
            return "alternate_email"; // email / mailto
        if (oneLine && /^#[\w-]{2,}$/.test(t) && !/^#[0-9a-f]{3,8}$/i.test(t))
            return "tag"; // hashtag (but not a hex colour)
        if (oneLine && /^@[\w.-]{2,}$/.test(t))
            return "alternate_email"; // @mention
        // A lone "name.ext" token with a known extension is a filename, not a domain.
        if (oneLine && !/[\s\/:@\\]/.test(t)) {
            const fi = extIcon(t);
            if (fi)
                return fi;
        }
        if (/^(?:[a-z0-9-]+\.)+[a-z]{2,}$/i.test(t))
            return "dns"; // bare hostname / domain

        // -- data / code / markup --
        if (/^\s*(?:SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|WITH|UNION|GRANT|TRUNCATE)\b/i.test(t) && /\b(?:FROM|INTO|TABLE|WHERE|VALUES|JOIN|SET|DATABASE)\b/i.test(t))
            return "database"; // SQL (two linear scans, no greedy bridge)
        if (/^diff --git\b/m.test(t) || /^@@ -\d+.* \+\d+.* @@/m.test(t) || /^(?:index [0-9a-f]+\.\.|--- a\/|\+\+\+ b\/)/m.test(t))
            return "difference"; // unified diff / patch
        if (/^(?:[\d*/,-]+\s+){4}[\d*/,-]+(?:\s|$)/.test(t) || /^@(?:reboot|yearly|monthly|weekly|daily|hourly)\b/.test(t))
            return "schedule"; // cron expression
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
        // CSV / TSV: 2+ rows with the same delimiter count. Tabs count directly;
        // commas/semicolons count only when tightly packed (no adjacent space), so
        // prose like "Well, then, we go" isn't mistaken for a table.
        const rows = t.split("\n").filter(l => l.length > 0);
        if (rows.length >= 2) {
            const cols = l => (l.match(/\t/g) || []).length || (l.match(/[^\s,;][,;][^\s,;]/g) || []).length;
            const c0 = cols(rows[0]);
            if (c0 >= 1 && rows.slice(0, 6).every(l => cols(l) === c0))
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
        if (oneLine && /^[A-Z][A-Z0-9_]{2,}=\S/.test(t))
            return "settings"; // env / config assignment
        if (/^\[[\w.\- ]+\]$/.test(t))
            return "settings"; // TOML / INI table header
        if (/^FROM\s+\S+(?:\s+AS\s+\S+)?/i.test(t) && !/\bfrom\s+\w+\s+(?:import|where|select)/i.test(t))
            return "deployed_code"; // Dockerfile
        if (/^"[\w@/.-]+"\s*:\s*"[~^>=<*]*\d[\w.*-]*",?$/.test(t))
            return "package_2"; // package.json version pin
        if (/^[A-Za-z][\w.-]*(?:\[[\w,]+\])?\s*(?:==|>=|<=|~=|!=)\s*\d+(?:\.\d+){1,2}(?:[-+][\w.]+)?$/.test(t))
            return "package_2"; // requirements.txt / pip version pin (dotted-quad IPs excluded)
        if (/^(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|TRACE|CONNECT)\s+\S+\s+HTTP\/\d/.test(t))
            return "http"; // HTTP request line
        if (/^(?:Authorization|Content-Type|Content-Length|User-Agent|Accept|Accept-Encoding|Accept-Language|Cookie|Set-Cookie|Host|Referer|Origin|Cache-Control|Connection|Location|Server|X-[\w-]+):\s+\S/.test(t))
            return "http"; // HTTP header line
        if (/^\?[\w%.+-]+=[^&\s]*(?:&[\w%.+-]+=[^&\s]*)+$/.test(t))
            return "manage_search"; // URL query string
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
        if (/[{}]|;|=>|->|::|\bfunction\b|\b(?:const|let|var)\b|\bimport\b|\bdef\b|\bclass\b|\breturn\b|<\/?\w+>/.test(t) && t.length < 800)
            return "code";

        // -- files & paths (real paths only; bare "name.ext" was handled above) --
        const pathLike = /^~?(?:\/[\w.@ +-]+)+\/?$/.test(t) || /^[A-Za-z]:[\\/]/.test(t) || /^\.\.?\/[\w./ +-]+$/.test(t);
        if (pathLike) {
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
        if (/^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?$/.test(t) || /^\d{1,2}\/\d{1,2}\/\d{2,4}$/.test(t))
            return "event"; // date / timestamp
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
        if (/^v?\d+\.\d+\.\d+(?:[-+][\w.]+)?$/.test(t))
            return "sell"; // semver / version tag
        if (/^(?:97[89])?\d{9,12}[\dXx]$/.test(t.replace(/[ -]/g, "")) && /^(?:97[89][ -]?)?(?:\d[ -]?){9}[\dXx]$/.test(t))
            return "menu_book"; // ISBN
        if (/^\+?[\d][\d\s().-]{6,}$/.test(t))
            return "call"; // phone
        if (/^[-+(]?\s*[\d.]+(?:\s*[-+*/^%]\s*[\d.()]+)+$/.test(t))
            return "calculate"; // arithmetic expression
        if (/^(?:true|false|yes|no|on|off|enabled|disabled)$/i.test(t))
            return "toggle_on"; // boolean-ish
        if (/^-?\d+(?:[.,]\d+)?$/.test(t) || /^0x[0-9a-f]+$/i.test(t) || /^0b[01]+$/i.test(t))
            return "tag"; // number
        if (/^["“'][\s\S]+["”']$/.test(t))
            return "format_quote"; // quoted text
        if (/^\s*[-*•]\s+\S/m.test(t) && /(?:\n\s*[-*•]\s+\S){1,}/.test(t))
            return "format_list_bulleted"; // bullet list
        if (/^\S+\?\s*$/.test(t) || /^(?:who|what|when|where|why|how|which|can|does|is|are)\b[\s\S]*\?$/i.test(t))
            return "help"; // question
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
        if (/[A-Za-z]{2,}[^{}<>=|\\]*[.!?]["')\]]?(?:\s+[A-Z"'(]|\s*$)/.test(t) && !/[{};=<>]|=>|::|\bfunction\b/.test(t) && /\s/.test(t))
            return "subject"; // natural-language prose / sentences (last content rule)

        // -- structural fallback: unclassified text, keyed on size --
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
