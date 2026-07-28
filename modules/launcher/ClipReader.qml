pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.services

// Reader mode for the `;` clipboard picker. The launcher morphs into this: a
// selectable, line-numbered view of the highlighted entry's REAL text (list
// previews flatten newlines; `cliphist decode` restores them). Typing while in
// the reader finds within THIS entry (the list filter is frozen meanwhile) and
// scrolls to the first match. Images show their decoded thumbnail; other
// binaries just their descriptor. Decoded text is cached in the Clipboard
// singleton, so browsing (↑/↓) back to an entry is instant and the list's
// "· N lines" stays exact.
Item {
    id: root

    // The ClipEntry currently under the launcher's highlight (from AppList).
    required property var entry
    // Live find term (search text minus the `;` prefix), seeded by the filter.
    property string findTerm: ""

    // Shared-element morph: the header IS the row. It starts at the row's y
    // (startY, from ContentList) and slides to the top; the body is anchored to
    // it, so it unfolds beneath as the header rises. exitTo() runs the reverse
    // and only then lets ContentList swap back to the list.
    property real startY: 0
    property real slideY: 0
    property real slideX: 0
    property bool exiting: false
    property var exitCb: null

    // The header's resting insets differ from the row content's insets in the
    // list (padding.large vs padding.medium horizontally; top padding vs row
    // centring vertically). The slide targets the row CONTENT's exact position
    // so the landing handoff is pixel-true, not "close then snap".
    readonly property real rowAlignY: (Tokens.sizes.launcher.itemHeight - header.implicitHeight) / 2 - Tokens.padding.large
    readonly property real rowAlignX: Tokens.padding.medium - Tokens.padding.large

    function exitTo(targetY: real, cb: var): void {
        // Stop BEFORE storing the callback: stopping a still-running enter
        // slide fires onStopped, which must not consume (and instantly fire)
        // the exit callback.
        slideAnim.stop();
        slideXAnim.stop();
        root.perfStart("CLOSE");
        root.exitCb = cb;
        root.exiting = true;
        slideAnim.from = root.slideY;
        slideAnim.to = targetY + root.rowAlignY;
        slideXAnim.from = root.slideX;
        slideXAnim.to = root.rowAlignX;
        root.morphT = 0;
        slideAnim.start();
        slideXAnim.start();
    }

    // Mid-exit reversal: stop the outbound slide wherever it is and return the
    // header to the top. The pending exit callback is discarded FIRST --
    // stopping fires onStopped, which must not consume (and run) the handoff
    // that would unmask the row under the re-opened reader.
    function reenter(): void {
        root.exitCb = null;
        slideAnim.stop();
        slideXAnim.stop();
        root.exiting = false;
        slideAnim.from = root.slideY;
        slideAnim.to = 0;
        slideXAnim.from = root.slideX;
        slideXAnim.to = 0;
        root.morphT = 1;
        slideAnim.start();
        slideXAnim.start();
    }

    // ---- TEMPORARY INSTRUMENTATION (remove after the old-vs-new comparison) ----
    // Counts frames actually rendered during the open morph and the worst frame
    // interval. A blocked GUI thread shows up as few frames + one huge interval;
    // a smooth morph shows ~N frames at ~16ms. Identical in both arms.
    property real perfT0: 0
    property string perfTag: ""

    FrameAnimation {
        id: perfProbe

        property int frames: 0
        property real worst: 0

        running: false
        onTriggered: {
            frames++;
            const ms = frameTime * 1000;
            if (ms > worst)
                worst = ms;
        }
    }

    function perfStart(tag: string): void {
        root.perfTag = tag;
        root.perfT0 = Date.now();
        perfProbe.frames = 0;
        perfProbe.worst = 0;
        perfProbe.running = true;
    }

    function perfEnd(): void {
        if (!perfProbe.running)
            return;
        perfProbe.running = false;
        const wall = Date.now() - root.perfT0;
        const line = `${root.perfTag} wallMs=${wall} frames=${perfProbe.frames} worstFrameMs=${perfProbe.worst.toFixed(1)} chars=${root.decoded.length} lines=${root.lineCount}`;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" >> /tmp/claude-1000/-home-namealle/c2e20d17-22a1-4c93-9aff-8f0d7261f550/scratchpad/clipperf.log", "p", line]);
    }
    // ---- END TEMPORARY INSTRUMENTATION ----

    Anim {
        id: slideAnim

        target: root
        property: "slideY"
        onStopped: {
            root.perfEnd();
            const cb = root.exitCb;
            root.exitCb = null;
            if (cb)
                cb();
        }
    }

    Anim {
        id: slideXAnim

        target: root
        property: "slideX"
    }

    readonly property bool isImage: root.entry?.isImage ?? false
    readonly property bool isBinary: !!(root.entry?.binMatch)
    // A lone colour (hex/rgb/hsl, parsed by Clipboard.colourOf into Qt's
    // #AARRGGBB) gets its own body: the row's swatch grown, plus the value in
    // every notation worth pasting. It is deliberately NOT a text body -- no
    // decode, no gutter, no find, since the preview IS the whole content. The
    // header still shows the exact string that was copied.
    readonly property string colour: root.entry?.colour ?? ""
    readonly property bool isColour: root.colour.length > 0
    readonly property color colourValue: root.isColour ? root.colour : "transparent"
    readonly property bool isText: !!root.entry && !root.isBinary && !root.isColour
    // Entries whose row draws a SQUARE in the leading slot (image thumbnail,
    // colour swatch) instead of a bare glyph. ClipItem sizes both from the
    // icon's implicitHeight, so the header has to reserve that width too --
    // see headerIcon.
    readonly property bool squareSlot: root.isImage || root.isColour

    // One notation per line. The hex line is always 6 digits: an 8-digit hex
    // would be ambiguous (CSS #RRGGBBAA vs Qt #AARRGGBB), so alpha rides on the
    // other two as rgba()/hsla() instead, and only when there is any.
    readonly property string colourFormats: {
        if (!root.isColour)
            return "";
        const c = root.colourValue;
        const b255 = v => Math.round(v * 255);
        const hex = v => b255(v).toString(16).padStart(2, "0");
        // Qt reports hue -1 for achromatic colours (any grey). 0 is the
        // conventional stand-in and round-trips to the same colour.
        const h = Math.round(Math.max(0, c.hslHue) * 360);
        const rgb = `${b255(c.r)}, ${b255(c.g)}, ${b255(c.b)}`;
        const hsl = `${h}, ${Math.round(c.hslSaturation * 100)}%, ${Math.round(c.hslLightness * 100)}%`;
        const lines = [`#${hex(c.r)}${hex(c.g)}${hex(c.b)}`];
        if (c.a < 1) {
            // parseFloat trims the trailing zero: 0.5, not 0.50.
            const a = parseFloat(c.a.toFixed(2));
            lines.push(`rgba(${rgb}, ${a})`, `hsla(${hsl}, ${a})`);
        } else {
            lines.push(`rgb(${rgb})`, `hsl(${hsl})`);
        }
        return lines.join("\n");
    }
    readonly property string imgCache: root.isImage && root.entry ? `/tmp/caelestia-clip-preview-${root.entry.entryId}.png` : ""

    readonly property int maxWidth: 1000
    readonly property int maxHeight: 640
    readonly property int minWidth: Tokens.sizes.launcher.itemWidth
    // Big enough to actually judge a colour, small enough that the launcher does
    // not become a full-screen flash of it (and the notations stay in view).
    readonly property int swatchHeight: 240

    readonly property string decoded: cache.text
    // One walk over the decoded text producing everything the reader needs to
    // know about its line structure: where each line starts, and the longest.
    //
    // This used to be three passes plus a full duplication of the entry --
    // split() materialising every line as its own string, then a scan over those
    // strings for the longest, then another walk to accumulate offsets. Walking
    // the string once with indexOf and keeping only integers measured 4.8ms ->
    // 0.6ms on a 1M/6395-line entry and 60.8ms -> 7.6ms on a 100k-line one, with
    // identical results.
    readonly property var lineIndex: {
        const s = root.decoded;
        const offsets = [];
        let longest = 0;
        let p = 0;
        for (;;) {
            const nl = s.indexOf("\n", p);
            offsets.push(p);
            const len = (nl < 0 ? s.length : nl) - p;
            if (len > longest)
                longest = len;
            if (nl < 0)
                break;
            p = nl + 1;
        }
        return {
            offsets,
            longest
        };
    }

    readonly property var lineOffsets: root.lineIndex.offsets
    readonly property int lineCount: root.lineIndex.offsets.length
    readonly property int longestLine: root.lineIndex.longest

    // All widths derive from CONTENT (never from the animated laid-out width),
    // so the text lays out once per entry -- not on every frame of the morph.
    readonly property real charWidth: fm.advanceWidth("0")
    readonly property real gutterWidth: fm.advanceWidth(String(Math.max(1, root.lineCount)))
    readonly property real contentW: root.implicitWidth - Tokens.padding.large * 2
    readonly property real textW: root.contentW - root.gutterWidth - Tokens.spacing.medium
    // One lowercased copy per entry rather than one per keystroke: at 1M chars
    // toLowerCase() costs ~9ms, which a held key turns into a stutter.
    readonly property string decodedLower: root.decoded.toLowerCase()

    // -- progressive body --
    // Only a few screens' worth of text is laid out when the reader opens; the
    // rest arrives as it is scrolled towards. The open path therefore costs the
    // same for a 20-line entry and a 100k-line one, instead of the 803ms a full
    // 100k-line layout takes on the GUI thread.
    //
    // Growth is always via insert(), never a text reassign: QTextDocument
    // relayouts only the inserted blocks, so a slab costs the same however much
    // is already loaded (measured over 3.5MB in 50 slabs: 0.9s total via insert,
    // 19s via reassign).
    // Slabs are measured in CHARACTERS, not lines. A line-sized slab does
    // nothing for the shape that hurts most -- a megabyte-long blob is often one
    // logical line, so "load 200 lines" loads all of it and the open path is
    // back to a full layout. Characters bound the work whatever the shape.
    // Slicing on char offsets also means slabs are contiguous, so no separator
    // has to be re-inserted between them.
    readonly property int initialChars: 8192
    readonly property int chunkChars: 32768
    property int loadedChars: 0
    property bool loading: false
    readonly property bool fullyLoaded: root.loadedChars >= root.decoded.length

    // Lines the layout actually knows about. A slab may stop mid-line, in which
    // case that line is partially present and still owns a number.
    readonly property int loadedLines: root.fullyLoaded ? root.lineCount : root.lineOfOffset(root.loadedChars) + 1

    // Qt's word wrap is quadratic in the length of an UNBREAKABLE run: it keeps
    // rescanning for a break opportunity that never comes. One line of random
    // alphanumerics measured 242ms at 100k chars, 3.7s at 400k, 23s at 1M. The
    // same text with WrapAnywhere is linear -- 1M in 92ms. Anything with a line
    // this long is a blob (base64, minified JS, one-line JSON, a hex dump), where
    // character wrapping is also the more readable choice. Note that
    // WrapAtWordBoundaryOrAnywhere is NOT a fix: it tries word boundaries first
    // and pays the identical 23s.
    readonly property int wrapAnywhereAbove: 4000
    readonly property int bodyWrapMode: root.longestLine > root.wrapAnywhereAbove ? TextEdit.WrapAnywhere : TextEdit.Wrap

    function resetBody(): void {
        root.loadedChars = 0;
        root.visibleLines = [];
        bodyText.text = "";
    }

    // Feed decoded[loadedChars, target) into the TextEdit. wrapMode is set BEFORE
    // the first slab: setting it afterwards relayouts the whole document a second
    // time, and the first of those two layouts would be the slow one.
    function loadTo(target: int): void {
        const want = Math.min(target, root.decoded.length);
        if (want <= root.loadedChars || !root.isText)
            return;
        root.loading = true;
        const slab = root.decoded.slice(root.loadedChars, want);
        if (root.loadedChars === 0) {
            bodyText.wrapMode = root.bodyWrapMode;
            bodyText.text = slab;
        } else {
            bodyText.insert(bodyText.length, slab);
        }
        root.loadedChars = want;
        root.loading = false;
    }

    // Pull the next slab once the viewport is within a screen of the end of what
    // is loaded.
    //
    // Measured against bodyText.contentHeight, NOT viewport.contentHeight: the
    // latter reaches the Flickable through a binding on bodyRow.implicitHeight
    // and can still read 0 in the turn right after a slab lands. That made the
    // condition trivially true, so this drained the whole document in one go --
    // progressive in name only. Requiring a real laid-out height is what keeps it
    // honest.
    function maybeLoadMore(): void {
        if (root.fullyLoaded || root.loading || !root.isText)
            return;
        const h = bodyText.contentHeight;
        if (h <= 0)
            return;
        if (viewport.contentY + viewport.height * 2 >= h)
            root.loadTo(root.loadedChars + root.chunkChars);
    }

    // Turns "the character at the top of the viewport" back into a line number
    // without walking the document. Offsets come from lineIndex.
    function lineOfOffset(idx: int): int {
        const o = root.lineOffsets;
        let lo = 0;
        let hi = o.length - 1;
        while (lo < hi) {
            const mid = (lo + hi + 1) >> 1;
            if (o[mid] <= idx)
                lo = mid;
            else
                hi = mid - 1;
        }
        return lo;
    }

    // Line numbers for the rows actually on screen, as {n, y} pairs.
    //
    // The old gutter asked the layout where EVERY logical line landed (100k
    // positionToRectangle calls, measured 697ms) to fill a single Text item
    // 1,800,000px tall, of which 640px is ever visible. This asks only about the
    // ~40 rows in view and repositions them as the viewport moves, so the cost
    // is per-screen instead of per-document. Wrapping still comes from the real
    // layout, so numbers stay glued to their rows.
    property var visibleLines: []

    function updateGutter(): void {
        if (!root.isText || bodyText.length === 0) {
            root.visibleLines = [];
            return;
        }
        const top = viewport.contentY;
        // Measured against maxHeight, NOT viewport.height. The viewport grows on
        // every frame of the opening morph, so using its live height recomputed
        // this set ~88 times per open -- and each assignment below hands the
        // Repeater a new array, which destroys and recreates every delegate.
        // maxHeight is the viewport's resting ceiling, so this window is a stable
        // superset from the first frame; the overlay clips whatever hangs below.
        const bottom = top + root.maxHeight;
        // Start one line early: the line owning the topmost character may have
        // begun above the fold, and its number belongs to its FIRST row.
        let i = Math.max(0, root.lineOfOffset(bodyText.positionAt(0, top)) - 1);
        const out = [];
        // Only numbers lines that are actually loaded -- lineOffsets covers the
        // whole entry, but the layout only knows about what has been fed in.
        while (i < root.loadedLines) {
            const r = bodyText.positionToRectangle(root.lineOffsets[i]);
            if (r.y > bottom)
                break;
            if (r.y + r.height >= top)
                out.push({
                    n: i + 1,
                    y: r.y
                });
            i++;
        }
        // Only reassign when the set actually differs. Comparing ~40 numbers is
        // far cheaper than a full delegate teardown, and it keeps a redundant
        // call (several signals can land in one turn) from churning the overlay.
        if (out.length === root.visibleLines.length) {
            let same = true;
            for (let k = 0; k < out.length; k++) {
                const p = root.visibleLines[k];
                if (p.n !== out[k].n || p.y !== out[k].y) {
                    same = false;
                    break;
                }
            }
            if (same)
                return;
        }
        root.visibleLines = out;
    }

    property string imgSrc: ""

    // Aspect ratio of the current image entry, taken from whichever copy has
    // decoded -- mThumb and mImg are the same picture, so the thumbnail's ratio
    // is the real one, and it is a cache hit from the row (see mThumb) rather
    // than a fresh decode.
    //
    // EVERYTHING that needs the image's final size reads this, not mImg
    // directly. The launcher's own open animation is driven by implicitHeight
    // -> viewport.contentHeight -> image.height; keying that on the full-res
    // decode meant the window sized itself to an EMPTY body, collapsed to a
    // single row, and only grew once the decode landed ~60ms later. The morph
    // was scaling up correctly the whole time -- it was the window around it
    // that was animating to the wrong size and then correcting.
    readonly property bool imgReady: mImg.status === Image.Ready && mImg.implicitHeight > 0
    readonly property bool thumbReady: mThumb.status === Image.Ready && mThumb.implicitHeight > 0
    readonly property real imgArW: root.imgReady ? mImg.implicitWidth : (root.thumbReady ? mThumb.implicitWidth : 0)
    readonly property real imgArH: root.imgReady ? mImg.implicitHeight : (root.thumbReady ? mThumb.implicitHeight : 0)
    // The height the body's aspect-FIT image settles at, known as soon as the
    // ratio is. 0 only while neither copy has decoded.
    readonly property real imgFitH: root.imgArH > 0 ? Math.min(root.maxHeight, root.contentW * root.imgArH / root.imgArW) : 0

    implicitWidth: {
        if (!root.isText)
            return root.minWidth;
        const natural = root.gutterWidth + Tokens.spacing.medium + root.longestLine * root.charWidth;
        return Math.max(root.minWidth, Math.min(root.maxWidth, natural + Tokens.padding.large * 2));
    }
    implicitHeight: header.implicitHeight + Math.min(root.maxHeight, viewport.contentHeight) + Tokens.padding.large * 2 + Tokens.spacing.small

    FontMetrics {
        id: fm
        font: bodyText.font
    }

    QtObject {
        id: cache

        property string text: ""
    }

    // Entry changed while browsing: serve from cache instantly, else debounce the
    // decode so ↑/↓ key-repeat doesn't spawn a process per intermediate row.
    function stage(): void {
        const e = root.entry;
        cache.text = "";
        root.imgSrc = "";
        scrollAnim.stop();
        viewport.contentY = 0;
        if (!e)
            return;
        if (root.isText && Clipboard.decodedText[e.entryId] !== undefined) {
            // onDecodedChanged does the staging (reset, first slab, find).
            cache.text = Clipboard.decodedText[e.entryId];
            return;
        }
        debounce.restart();
    }

    function refresh(): void {
        const e = root.entry;
        if (!e)
            return;
        if (root.isImage) {
            imgDecoder.running = false;
            imgDecoder.running = true;
            return;
        }
        if (!root.isText)
            return;
        // A cliphist reload can destroy the entry object mid-read; its
        // properties all read undefined then. Skip -- the reload will hand the
        // reader a fresh entry.
        const id = e.entryId;
        const raw = e.raw;
        if (id === undefined || raw === undefined)
            return;
        // Already decoded once this session: serve it and skip the process
        // entirely. This used to re-spawn cliphist and re-deliver the whole
        // entry across to the JS engine on EVERY open, only to arrive at a
        // string identical to the one already cached.
        const cached = Clipboard.decodedText[id];
        if (cached !== undefined) {
            cache.text = cached;
            return;
        }
        decoder.running = false;
        decoder.entryId = id;
        decoder.line = raw;
        decoder.running = true;
    }

    // Keyboard scrolling: PgUp/PgDn a viewport at a time, Home/End to the
    // edges -- always animated, never a one-frame jump. Repeated presses
    // accumulate against the in-flight target, not the current frame, so
    // holding the key pages steadily.
    // The laid-out height of the body, read from the item that owns the layout.
    //
    // viewport.contentHeight reaches the Flickable through a binding on
    // bodyRow.implicitHeight, and a positioner's implicitHeight only settles
    // during polish -- so in the same turn as a slab insert it still reports the
    // PREVIOUS height. Scrolling against it made End land at the old end and need
    // a second press to reach the real one. bodyText.contentHeight is updated
    // synchronously by insert(), so every scroll target measures against this.
    readonly property real bodyHeight: root.isText ? bodyText.contentHeight : (root.isColour ? colourBody.implicitHeight : image.height)

    function smoothScrollTo(y: real): void {
        const to = Math.max(0, Math.min(y, Math.max(0, root.bodyHeight - viewport.height)));
        // Retarget in flight -- deliberately no stop() here. Killing the spring
        // would zero its velocity, which is the whole reason a held PgDn used to
        // re-accelerate from a standstill on every repeat.
        scrollAnim.to = to;
        if (to === viewport.contentY && Math.abs(scrollAnim.velocity) < scrollAnim.settleEpsilon)
            return;
        scrollAnim.running = true;
    }

    function scrollPage(dir: int): void {
        const base = scrollAnim.running ? scrollAnim.to : viewport.contentY;
        smoothScrollTo(base + dir * viewport.height * 0.9);
    }

    function scrollEdge(dir: int): void {
        // End means the real end, not the end of whatever happens to be loaded.
        // Measured via bodyHeight so the target reflects the text just inserted,
        // not the height the Flickable still thinks it has.
        if (dir >= 0)
            root.loadTo(root.decoded.length);
        smoothScrollTo(dir < 0 ? 0 : root.bodyHeight);
    }

    // Physics, not a timed curve. Every easing curve has to end at a fixed
    // instant, so its final frame is a velocity discontinuity; with a decel
    // curve that lands exactly where the remaining distance is sub-pixel, which
    // reads as "glides, then stops dead in one frame". A spring is asymptotic
    // instead -- velocity decays continuously and we only snap once the
    // distance AND the speed are both under half a pixel, by which point the
    // snap is genuinely invisible.
    //
    // Deliberately NOT Qt's SpringAnimation: this needs to survive retargeting
    // mid-flight with velocity intact, and hand-integrating is both clearer
    // about that and tunable in Hyprland's stiffness/damping/mass terms.
    FrameAnimation {
        id: scrollAnim

        // damping = 2*sqrt(stiffness*mass) is critical damping: the fastest
        // approach that never overshoots. Overshoot is not an option here --
        // bouncing text was what ruled springs out in the first place. Drop
        // damping below critical only if a little bounce is wanted.
        // stiffness is the only speed knob: omega = sqrt(k/m) = 20/s here, so
        // ~90% of any distance is covered in ~200ms with the rest fading out
        // smoothly. Raise it to go faster -- damping re-derives itself, so it
        // stays overshoot-free at any value.
        property real stiffness: 400
        property real mass: 1
        property real damping: 2 * Math.sqrt(stiffness * mass)
        readonly property real settleEpsilon: 0.5

        property real to: 0
        property real velocity: 0

        running: false
        onRunningChanged: {
            if (!running)
                velocity = 0;
        }

        onTriggered: {
            // Clamp dt: a stalled frame (compositor hiccup, a decode landing)
            // must not integrate one huge step and fling the viewport.
            const dt = Math.min(frameTime, 1 / 30);
            // Substep to at most 1/120s. Explicit integration diverges once the
            // step approaches the spring's period -- without this it silently
            // goes NaN somewhere above stiffness 650 on a clamped 30Hz frame,
            // which would be a nasty trap the first time stiffness gets raised.
            // With it, everything up to stiffness 3000 stays exact.
            const steps = Math.max(1, Math.ceil(dt * 120));
            const h = dt / steps;
            // Semi-implicit Euler -- velocity first, then position from the new
            // velocity. Far more stable than explicit at large dt.
            let next = viewport.contentY;
            for (let i = 0; i < steps; i++) {
                velocity += (-stiffness * (next - to) - damping * velocity) / mass * h;
                next += velocity * h;
            }

            if (Math.abs(next - to) < settleEpsilon && Math.abs(velocity) < settleEpsilon) {
                viewport.contentY = to;
                running = false;
                return;
            }
            viewport.contentY = next;
        }
    }

    // Select the first occurrence of the find term and scroll it into view.
    function applyFind(): void {
        const t = root.findTerm.trim().toLowerCase();
        if (!t || !root.isText || !root.decoded.length) {
            bodyText.deselect();
            return;
        }
        const idx = root.decodedLower.indexOf(t);
        if (idx < 0) {
            bodyText.deselect();
            return;
        }
        // Find searches the WHOLE entry, not just the loaded part, so a match
        // past the loaded end has to be pulled in before select() -- otherwise it
        // would land on an offset the document does not have yet.
        root.loadTo(idx + t.length);
        bodyText.select(idx, idx + t.length);
        const r = bodyText.positionToRectangle(idx);
        smoothScrollTo(r.y - viewport.height / 3);
    }

    onEntryChanged: root.stage()
    onFindTermChanged: root.applyFind()
    // Every path that changes the decoded text lands here: cache hit, fresh
    // decode, or clearing on entry change. Rebuild the body and seed the first
    // few screens.
    onDecodedChanged: {
        root.resetBody();
        if (root.isText && root.decoded.length)
            root.loadTo(root.initialChars);
        Qt.callLater(root.applyFind);
    }
    Component.onCompleted: {
        root.perfStart("OPEN");
        // Start exactly on the row's content, become the header.
        slideY = startY + rowAlignY;
        slideX = rowAlignX;
        slideAnim.from = slideY;
        slideAnim.to = 0;
        slideXAnim.from = slideX;
        slideXAnim.to = 0;
        slideAnim.start();
        slideXAnim.start();
        morphT = 1;
        root.refresh();
    }

    Timer {
        id: debounce

        interval: 140
        onTriggered: root.refresh()
    }

    // Ensures the thumbnail exists on disk (same cache file ClipItem writes),
    // then points the Image at it -- Image won't retry a source that didn't
    // exist when first set.
    Process {
        id: decoder

        property string entryId: ""
        property string line: ""

        command: ["sh", "-c", "printf '%s' \"$1\" | cliphist decode", "clip", decoder.line]
        stdout: StdioCollector {
            onStreamFinished: {
                // Display convention: one trailing newline is not an extra line.
                const t = text.replace(/\n$/, "");
                Clipboard.cacheDecoded(decoder.entryId, t);
                // onDecodedChanged does the staging (reset, first slab, find).
                if (root.entry?.entryId === decoder.entryId)
                    cache.text = t;
            }
        }
    }

    Process {
        id: imgDecoder

        command: ["sh", "-c", "test -s \"$2\" || (printf '%s' \"$1\" | cliphist decode > \"$2\")", "dec", root.entry?.raw ?? "", root.imgCache]
        onExited: {
            if (root.isImage)
                root.imgSrc = `file://${root.imgCache}`;
        }
    }

    // -- header: same icon + title as the row --
    Item {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        // slideY/slideX carry the shared-element motion; the body is anchored
        // below, so it compresses/unfolds with the header rather than being
        // overlapped.
        anchors.topMargin: Tokens.padding.large + root.slideY
        anchors.leftMargin: Tokens.padding.large + root.slideX
        anchors.bottomMargin: 0

        implicitHeight: Math.max(headerIcon.implicitHeight, headerText.implicitHeight)

        MaterialIcon {
            id: headerIcon

            anchors.verticalCenter: parent.verticalCenter
            // A glyph is narrower than its own line height (41 vs 50px at the
            // default icon size), so anchoring the title to the icon's right
            // edge only matches the row for entries whose row also draws a bare
            // glyph. Image and colour rows draw a square of implicitHeight
            // there, and the title has to clear the same width -- otherwise it
            // rides 9px left of the row's title for the whole slide and
            // teleports across when the handoff unmasks the row. Centring the
            // glyph in the wider slot also keeps it under the morph square.
            width: root.squareSlot ? implicitHeight : implicitWidth
            horizontalAlignment: Text.AlignHCenter
            text: root.entry?.icon ?? "content_paste"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        Item {
            id: headerText

            anchors.left: headerIcon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: title.implicitHeight + meta.implicitHeight

            StyledText {
                id: title

                anchors.left: parent.left
                anchors.right: parent.right
                text: root.entry?.name ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: meta

                anchors.left: parent.left
                anchors.top: title.bottom
                text: {
                    if (root.isText && root.decoded.length)
                        return `${root.decoded.length} characters · ${root.lineCount} ${root.lineCount === 1 ? "line" : "lines"}`;
                    return root.entry?.desc ?? "";
                }
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
            }
        }
    }

    // -- body --
    StyledFlickable {
        id: viewport

        // During exit the list is already returning underneath; only the header
        // (the shared element) stays visible for the slide back onto its row.
        visible: !root.exiting

        anchors.top: header.bottom
        anchors.topMargin: Tokens.spacing.small
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.padding.large

        clip: true
        contentWidth: width
        contentHeight: root.isText ? bodyRow.implicitHeight : (root.isColour ? colourBody.implicitHeight : image.height)

        onContentYChanged: {
            Qt.callLater(root.updateGutter);
            Qt.callLater(root.maybeLoadMore);
        }
        // Deliberately NOT hooked to onHeightChanged: the height animates through
        // the whole morph, and the gutter window is now sized from maxHeight so
        // it does not depend on it. See updateGutter.

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: viewport
        }

        // Text entries: line-number gutter + selectable, wrapping monospace text.
        Row {
            id: bodyRow

            visible: root.isText
            width: root.contentW
            spacing: Tokens.spacing.medium

            Item {
                // Reserves the gutter column. The numbers themselves are drawn by
                // the overlay below, outside the Flickable, so the gutter is never
                // itself a document-sized item.
                width: root.gutterWidth
                height: 1
            }

            TextEdit {
                id: bodyText

                width: root.textW
                // NOT bound to root.decoded: text arrives in slabs via loadTo(),
                // which uses insert() to keep each slab's layout cost flat. A
                // binding here would reassign the whole document every time.
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                // Word boundaries; only runs longer than a row split mid-word.
                // The gutter follows the real layout (updateGutter), so it does
                // not need fixed-chars-per-row wrapping.
                wrapMode: TextEdit.Wrap
                onWidthChanged: Qt.callLater(root.updateGutter)
                // A slab has landed and been laid out: renumber the visible rows,
                // then re-check whether the viewport still needs more. Driving
                // load-more from here (rather than from loadTo) is what
                // guarantees the check sees a real contentHeight.
                onContentHeightChanged: {
                    Qt.callLater(root.updateGutter);
                    Qt.callLater(root.maybeLoadMore);
                }
                color: Colours.palette.m3onSurface
                selectionColor: Colours.palette.m3primary
                selectedTextColor: Colours.palette.m3onPrimary
                font: Tokens.font.mono.small
                renderType: Text.NativeRendering
            }
        }

        // Colour entries: the row's swatch at reading size, then the value in
        // every notation -- selectable, so grabbing the format you need is the
        // same mouse-select + Ctrl+C as any other entry.
        Column {
            id: colourBody

            visible: root.isColour
            width: root.contentW
            spacing: Tokens.spacing.medium

            // The swatch's space is reserved by this Item, not by the rect
            // itself: the rect is hidden until the morph overlay lands on it,
            // and a Column would collapse around a hidden child, dragging the
            // notations up through the whole morph.
            Item {
                width: parent.width
                height: root.swatchHeight

                StyledRect {
                    anchors.fill: parent
                    // Hidden while the morph overlay is in flight -- the overlay
                    // lands exactly on this rect, then hands off. See `morphing`
                    // for why the test is the animation and not morphT >= 1.
                    visible: root.morphT >= 1 && !root.morphing
                    radius: Tokens.rounding.small
                    color: root.colourValue
                    // Same 1px outline the row's swatch has, so a colour close
                    // to the surface still reads as a swatch rather than a hole
                    // -- and so the handoff from the morph is pixel-true.
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant
                }
            }

            TextEdit {
                width: parent.width
                text: root.colourFormats
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                color: Colours.palette.m3outline
                selectionColor: Colours.palette.m3primary
                selectedTextColor: Colours.palette.m3onPrimary
                font: Tokens.font.mono.small
                renderType: Text.NativeRendering
            }
        }

        // Image entries: the decoded thumbnail, aspect-fit, height capped.
        Image {
            id: image

            // Hidden while the morph overlay is in flight -- the overlay lands
            // exactly on this rect, then hands off. See `morphing` for why the
            // test is the animation and not morphT >= 1.
            visible: root.isImage && root.morphT >= 1 && !root.morphing
            width: root.contentW
            // Shared ratio, NOT this Image's own status -- this height is what
            // the launcher sizes itself from, and it has to be right before the
            // full-res decode lands. See imgFitH.
            height: root.imgFitH
            source: root.imgSrc
            fillMode: Image.PreserveAspectFit
            // Same url and sourceSize as the morph's mImg, so with caching on
            // at both ends the two share one decode instead of racing two
            // identical ones. That matters on large images: the duplicate was
            // competing for the same CPU and pushing back the moment the morph
            // could show full res.
            cache: true
            asynchronous: true
            sourceSize.width: root.maxWidth
        }
    }

    // -- gutter overlay --
    // Sits over the viewport's left column rather than inside its content, so it
    // holds ~40 small Text items instead of one item as tall as the document.
    // Each number is placed at its row's y, offset by the scroll position.
    Item {
        id: gutter

        x: viewport.x
        y: viewport.y
        width: root.gutterWidth
        height: viewport.height
        clip: true
        visible: root.isText && !root.exiting

        Repeater {
            model: root.visibleLines

            StyledText {
                required property var modelData

                width: root.gutterWidth
                y: modelData.y - viewport.contentY
                text: modelData.n
                font: Tokens.font.mono.small
                color: Colours.palette.m3outlineVariant
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    // -- leading-slot morphs: the row's thumbnail/swatch becomes the body --
    // Second shared elements riding the same slide, one per entry kind that has
    // something in its leading slot. At t=0 both exactly cover the header's
    // material icon slot -- which is pixel-identical to the row's thumbnail /
    // swatch slot, so the icon really is "under" it -- and at t=1 they exactly
    // cover the rect the corresponding body item paints. Every endpoint is a
    // live binding (the slot follows slideX/slideY), so enter, exit and
    // mid-flight reversals all stay glued.
    property real morphT: 0

    Behavior on morphT {
        Anim {
            id: morphAnim
        }
    }

    // The handoff between a morph and the body item it lands on is keyed on the
    // ANIMATION, not on morphT reaching 1 -- the expressive spatial curve
    // overshoots (peak 1.0139), so it crosses 1.0 at only 47% of the duration
    // (243ms of 514ms, measured). Keying on the value handed off there and
    // snapped the last 271ms away invisibly: the morph appeared to arrive early
    // and hard, with none of the overshoot the rest of the launcher has.
    // `running` goes true synchronously with the assignment and stays true
    // across a mid-flight retarget, so this neither flashes at the start nor
    // breaks reenter().
    readonly property bool morphing: morphAnim.running

    // The source slot, shared by both morphs. See headerIcon for why the size is
    // the icon's implicitHeight (a square) and not its glyph width.
    readonly property real slotS: headerIcon.implicitHeight
    readonly property real slotX: Tokens.padding.large + root.slideX
    readonly property real slotY: Tokens.padding.large + root.slideY + (header.implicitHeight - root.slotS) / 2
    // Top of the body's content in root coordinates -- where both morphs land.
    readonly property real bodyTop: Tokens.padding.large + root.slideY + header.implicitHeight + Tokens.spacing.small - viewport.contentY

    StyledClippingRect {
        id: morphImg

        // The rect the body's aspect-FIT image actually paints inside
        // contentW x maxHeight. Only horizontal centring can occur: a capped
        // height caps the box to the same value, so there is no letterbox.
        // Uses the shared ratio (see imgArW), so the box flies to the true
        // shape from frame 1 instead of aiming at a contentW square and then
        // snapping when the full decode arrives.
        readonly property real fitW: root.imgArH > 0 ? Math.min(root.contentW, root.maxHeight * root.imgArW / root.imgArH) : root.contentW
        readonly property real fitH: root.imgArH > 0 ? root.imgFitH : root.contentW
        readonly property real dstX: Tokens.padding.large + (root.contentW - fitW) / 2

        visible: root.isImage && (root.morphing || root.morphT < 1)
        x: root.slotX + (dstX - root.slotX) * root.morphT
        y: root.slotY + (root.bodyTop - root.slotY) * root.morphT
        width: root.slotS + (fitW - root.slotS) * root.morphT
        height: root.slotS + (fitH - root.slotS) * root.morphT
        // Clamped: morphT passes 1 on the overshoot, which would otherwise ask
        // for a negative radius.
        radius: Tokens.rounding.small * Math.max(0, 1 - root.morphT)
        color: Colours.palette.m3surfaceContainerHigh

        // The picture the row was already showing, scaled up. Same url and same
        // sourceSize as ClipItem's `thumb` with caching on at both ends, so
        // this is a synchronous QQuickPixmapCache hit and the morph has real
        // content from its first frame. Blurry at full size, but it is the
        // right image at the right aspect, and mImg fades over it. Underneath
        // sits the rect's surface colour, which now only shows for entries
        // whose row thumbnail has not decoded yet either.
        Image {
            id: mThumb

            anchors.fill: parent
            source: root.imgSrc
            fillMode: Image.PreserveAspectCrop
            cache: true
            asynchronous: true
            sourceSize.width: root.slotS * 2
            sourceSize.height: root.slotS * 2
        }

        Image {
            id: mImg

            anchors.fill: parent
            source: root.imgSrc
            fillMode: Image.PreserveAspectCrop
            // Shares its decode with the body's `image` -- see the note there.
            cache: true
            asynchronous: true
            sourceSize.width: root.maxWidth
            // Cross-fade over the thumbnail rather than popping. Effects-fast,
            // not spatial: the geometry is already animating underneath and a
            // slow fade would just read as the picture arriving late.
            opacity: root.imgReady ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }
    }

    // The colour swatch's morph. Full body width at t=1, so the only endpoint
    // that differs from the slot is the size -- and the radius stays put, since
    // both the row's swatch and the body's use rounding.small. A plain rect,
    // not a clipping one: there is no child to clip, and a Rectangle composites
    // a semi-transparent colour without going through a shader.
    StyledRect {
        id: morphSwatch

        visible: root.isColour && (root.morphing || root.morphT < 1)
        x: root.slotX + (Tokens.padding.large - root.slotX) * root.morphT
        y: root.slotY + (root.bodyTop - root.slotY) * root.morphT
        width: root.slotS + (root.contentW - root.slotS) * root.morphT
        height: root.slotS + (root.swatchHeight - root.slotS) * root.morphT
        radius: Tokens.rounding.small
        color: root.colourValue
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
    }
}
