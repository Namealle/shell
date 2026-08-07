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
        // Drop any dip in flight: the exit collapses the reader to the row, and
        // a held height would be animating against that the whole way down.
        holdTimer.stop();
        maxHold.stop();
        root.heldHeight = 0;
        root.dip = 0;
        // Same for a slide: the body is about to be folded back into the row, and
        // an offset still easing out would ride along inside the shrinking morph.
        // Now that the travel is viewport-sized, leaving it running is visible.
        bodySlideAnim.stop();
        bodyFadeAnim.stop();
        root.bodyOffset = 0;
        root.bodyFade = 1;
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

    Anim {
        id: slideAnim

        target: root
        property: "slideY"
        onStopped: {
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

    // Defined by the Clipboard service, which owns the image box formula so the
    // prefetcher can warm the exact decode this asks for. See readerImageWidth.
    readonly property int maxWidth: Clipboard.readerMaxWidth
    readonly property int maxHeight: Clipboard.readerMaxHeight
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
    // cliphist's own descriptor first: it is exact, it is the TRUE resolution
    // (a decoded copy only ever reports its sourceSize-capped size), and it is
    // there before anything has been decoded at all. The decoded copies remain
    // as the fallback for entries whose descriptor carries no WxH.
    readonly property var imgDims: root.isImage ? (root.entry?.imgDims ?? null) : null
    readonly property real imgArW: root.imgDims ? root.imgDims.w : (root.imgReady ? mImg.implicitWidth : (root.thumbReady ? mThumb.implicitWidth : 0))
    readonly property real imgArH: root.imgDims ? root.imgDims.h : (root.imgReady ? mImg.implicitHeight : (root.thumbReady ? mThumb.implicitHeight : 0))
    // The natural-resolution clamp, which is NOT the same fallback chain as the
    // ratio above: mThumb is an 82px copy, so its width is a valid ratio but a
    // useless resolution, and clamping to it would open every descriptor-less
    // image at thumbnail size and then pop to full size when mImg landed. Only
    // the descriptor and mImg are honest here (mImg's own cap is maxWidth,
    // which is the ceiling anyway); until one of them speaks, don't clamp.
    readonly property real imgNatW: root.imgDims ? root.imgDims.w : (root.imgReady ? mImg.implicitWidth : root.maxWidth)

    // The box the body's image paints in -- the single source of truth for the
    // reader's width, its height, and both of the morph's endpoints. 0 while the
    // ratio is still unknown; callers fall back to minWidth.
    readonly property real imgBoxW: Clipboard.readerImageWidth(root.imgArW, root.imgArH, root.imgNatW)

    // The size to DECODE at, which is now the size it is drawn at rather than a
    // flat ceiling. A texture bigger than its box has to be minified on the way
    // to the screen, and Qt's default filtering there is 4-tap bilinear with no
    // mipmaps -- which cannot represent a large reduction and aliases instead of
    // averaging. A portrait clip used to decode 1000px wide and paint at 360:
    // permanently undersampled, at rest, for no benefit. Matching the two makes
    // the draw exactly 1:1, which is both the sharpest it can be and the least
    // memory it can cost.
    //
    // Computed straight from the descriptor rather than read off imgBoxW, which
    // is what keeps imgNatW's mImg fallback from closing a loop
    // (sourceSize -> implicitWidth -> imgNatW -> imgBoxW -> sourceSize). With a
    // descriptor both paths evaluate the same formula on the same numbers, so
    // the texture still matches the box exactly; without one this is a constant
    // and the loop has nowhere to close.
    readonly property int imgDecodeW: root.imgDims ? Clipboard.readerDecodeWidth(root.imgDims) : root.maxWidth
    // The height that box settles at, known as soon as the ratio is.
    // Whole pixels, for the same reason imgBoxW is: the texture Qt decodes is an
    // integer number of rows, so a fractional painted height resamples the image
    // vertically no matter how exact the width is. The rounding costs at most
    // half a pixel of aspect, which is under a tenth of a percent and invisible;
    // the resample it avoids is not.
    readonly property int imgFitH: root.imgBoxW > 0 ? Math.round(root.imgBoxW * root.imgArH / root.imgArW) : 0

    implicitWidth: {
        // Images size to their content exactly as text does; everything else
        // (colour swatch, bare binary descriptor) has no natural width to grow
        // to and stays at the launcher's list width.
        if (root.isImage)
            return Math.max(root.minWidth, root.imgBoxW + Tokens.padding.large * 2);
        if (!root.isText)
            return root.minWidth;
        const natural = root.gutterWidth + Tokens.spacing.medium + root.longestLine * root.charWidth;
        return Math.max(root.minWidth, Math.min(root.maxWidth, natural + Tokens.padding.large * 2));
    }
    // The height the current content actually wants. implicitHeight only follows
    // it when no swap is in flight -- see heldHeight.
    readonly property real liveHeight: header.implicitHeight + Math.min(root.maxHeight, viewport.contentHeight) + Tokens.padding.large * 2 + Tokens.spacing.small
    // The dip must never eat the header; below this there is nothing left to
    // shrink and it would read as the reader breaking rather than breathing.
    readonly property real minHeight: header.implicitHeight + Tokens.padding.large * 2
    implicitHeight: Math.max(root.minHeight, (root.heldHeight > 0 ? root.heldHeight : root.liveHeight) - root.dip)

    FontMetrics {
        id: fm
        font: bodyText.font
    }

    QtObject {
        id: cache

        property string text: ""
    }

    // -- entry-change transition --
    //
    // Browsing used to animate whatever the data happened to do. stage() blanked
    // the body, so the launcher collapsed towards its minimum and grew back only
    // when the decode landed: the depth and the duration of that move were both
    // functions of decode latency, the whole thing disappeared once an entry was
    // cached, and two entries of equal height swapped with no motion at all.
    // One keypress, three behaviours.
    //
    // The fix is not a nicer wait -- it is not waiting. Clipboard.prefetch keeps
    // the entries around the highlight decoded, so by the time a key is pressed
    // the text is almost always already in hand, and then the reader swaps on
    // that same frame and goes to the new height in ONE continuous move. That is
    // the snappy path, and it is the normal one.
    //
    // What is left is the genuine miss: an entry nothing has decoded yet. There
    // the reader dips by a fraction of its height and holds the old body at the
    // old height until the text lands. So the dip means "working" -- it shows up
    // only when something is actually being waited for, which is also why it is
    // allowed to be latency-shaped. What it must never do is add a pause to a
    // transition that had everything it needed; a dip in front of a ready swap
    // is just a delay wearing an animation's clothes.
    //
    // Holding the old body is what replaced the collapse: the previous entry's
    // height is the honest one until a new one exists, and blanking the body
    // made the window animate to a size that meant nothing.
    //
    // Nothing here animates directly. It steps implicitHeight and lets
    // ContentList's Behavior do the animating, exactly as the blanking did.
    property real dip: 0
    // Implicit height to keep reporting while a swap is in flight; 0 = follow
    // the live content.
    property real heldHeight: 0
    // True means "nothing is holding". Defaults that way deliberately: commit()
    // is gated on it, and the reader must never depend on a kick having run to
    // be able to show its first entry.
    property bool holdElapsed: true
    property var pendingText: null
    property string pendingImgSrc: ""
    // What the body is currently SHOWING (not what `entry` says). Set at commit.
    property string shownType: ""
    // Guard for the reader's own first staging, which runs during creation --
    // the dip must not fire into the open morph.
    property bool opened: false

    readonly property string entryType: root.isImage ? "image" : (root.isColour ? "colour" : (root.isText ? "text" : "other"))
    // Proportional, because a fixed pixel dip is violent on a 200px reader and
    // invisible on a 640px one. Capped so a full-height entry does not swing.
    readonly property real dipFraction: 0.09
    readonly property real dipMax: 44

    // Saturating: a change arriving mid-dip keeps the first depth and only
    // extends the hold, so holding ↑/↓ rests at one steady dip instead of
    // walking the window down a step per row.
    function kick(base: real): void {
        if (!root.opened || root.exiting) {
            // Open path: no dip, and nothing to wait for -- let the first
            // content through as soon as it exists.
            root.holdElapsed = true;
            return;
        }
        if (root.heldHeight <= 0) {
            root.heldHeight = base;
            root.dip = Math.min(root.dipMax, base * root.dipFraction);
            maxHold.restart();
        }
        root.holdElapsed = false;
        holdTimer.restart();
    }

    // Swap the prepared entry in and release the dip. Called from every path
    // that could complete the transition -- the hold expiring, a decode
    // finishing, a cache hit -- and does nothing until both halves are ready.
    function commit(): void {
        if (!root.holdElapsed)
            return;
        // Still no content for the new entry: hold. This is the branch that
        // replaces the old collapse-to-nothing.
        if (root.isText && root.pendingText === null)
            return;
        if (root.isImage && root.pendingImgSrc === "")
            return;
        if (root.pendingText !== null) {
            // onDecodedChanged does the rest (reset, first slab, find).
            cache.text = root.pendingText;
            root.pendingText = null;
        }
        if (root.pendingImgSrc !== "") {
            root.imgSrc = root.pendingImgSrc;
            root.pendingImgSrc = "";
        }
        root.shownType = root.entryType;
        scrollAnim.stop();
        viewport.contentY = 0;
        holdTimer.stop();
        maxHold.stop();
        root.heldHeight = 0;
        root.dip = 0;
        // Last: the swap above is what there is to announce, and slideIn reads
        // nothing that is not already settled by this point.
        root.slideIn();
    }

    // Entry changed while browsing. Prepare the new content, hold the old.
    function stage(): void {
        const e = root.entry;
        if (!e)
            return;
        // Captured BEFORE anything is cleared below -- clearing the body drops
        // the live height, and the whole point is to hold what it was.
        const base = root.liveHeight;
        // Across a type change there is nothing worth holding: a text body under
        // an image entry's header is not continuity, it is a leftover. The
        // HEIGHT is still held either way, which is what stops the collapse.
        if (root.entryType !== root.shownType) {
            cache.text = "";
            root.imgSrc = "";
        }
        root.pendingText = null;
        root.pendingImgSrc = "";
        if (root.isText) {
            const c = Clipboard.decodedText[e.entryId];
            if (c !== undefined)
                root.pendingText = c;
            else
                // Debounced so key-repeat doesn't spawn a process per row.
                debounce.restart();
        } else if (root.isImage) {
            debounce.restart();
        }
        // Already in hand -- and with prefetch running that is the normal case.
        // Straight to the new size in ONE move, starting on this frame. A dip
        // here would only be a delay wearing an animation's clothes: it would
        // put a pause between the keypress and the resize, which is exactly the
        // sluggishness the dip was supposed to be fixing.
        if (root.contentReady()) {
            root.holdElapsed = true;
            root.commit();
            return;
        }
        // Nothing to show yet: dip, and hold the old body at the old height
        // until there is. The dip means "working", not "transitioning" -- it
        // appears only when something is actually being waited for.
        root.kick(base);
    }

    // -- entry-change slide --
    //
    // A same-size swap has nothing to animate: the height does not change, so
    // the body changed under a stationary frame in a single frame and read as a
    // glitch. What was missing there was never motion for its own sake, it was
    // DIRECTION -- nothing told you which way you had moved, so two similar
    // entries left you checking whether the key had registered at all.
    //
    // So the new body enters from the side you came from: ↓ brings it up from
    // below, ↑ brings it down from above. Purely presentational -- the content
    // is already committed and the height is already animating by the time this
    // starts, so it gates nothing and can never make a swap feel slower.
    //
    // Same curve as the launcher's own resize, the reader's header morph and
    // every other spatial move in the shell (DefaultSpatial, the one with the
    // 1.21 overshoot), so the body settles on the same beat as the window around
    // it instead of reading as a separate event. That curve is heavily
    // front-loaded, which is why 500ms nominal still feels immediate: most of
    // the travel is over in the first fifth of it.
    //
    // Deliberately NOT the scroll's spring, even though PgUp/PgDn is right next
    // door. The scroll is a continuous gesture the user steers, so it wants
    // physics that survive retargeting; a swap is a discrete event that should
    // land on the same beat as the frame resizing around it, and the frame is on
    // this curve. Matching the neighbour would have cost matching the parent.
    property int browseStep: 0
    property real bodyOffset: 0
    property real bodyFade: 1
    // Sized to the viewport, not fixed: the travel has to be a real fraction of
    // the body to read as the text MOVING rather than twitching, and a distance
    // that does that in a 640px reader would throw a three-line entry clean off
    // its own frame. Floor so short entries still travel visibly, ceiling so a
    // full-height one does not turn into a page turn.
    //
    // Note this scales the overshoot with it: the curve swings ~21% of the
    // travel past zero before settling, so at the ceiling the body passes about
    // 29px the other way. That is the bounce, and it is why the ceiling is not
    // higher.
    readonly property real slideDist: Math.max(56, Math.min(140, viewport.height * 0.34))

    function slideIn(): void {
        // Never during the open or close morph -- the body is the thing the
        // header is unfolding, and a second motion on top just muddies it.
        if (!root.opened || root.exiting || root.browseStep === 0)
            return;
        // Read BEFORE stopping, which clears it.
        const settled = !bodyFadeAnim.running;
        bodySlideAnim.stop();
        bodyFadeAnim.stop();
        root.bodyOffset = root.browseStep > 0 ? root.slideDist : -root.slideDist;
        // Opacity is only pulled back to 0 when the body is actually settled.
        // Key repeat arrives faster than the fade completes, and yanking it to 0
        // on every row would hold the body dim for as long as the arrow is down.
        // Resuming from where it is means a held key just slides, and the fade
        // goes back to being what it is for: the settle on a single move.
        if (settled)
            root.bodyFade = 0;
        bodySlideAnim.start();
        bodyFadeAnim.start();
    }

    Anim {
        id: bodySlideAnim

        target: root
        property: "bodyOffset"
        to: 0
    }

    // Deliberately NOT the spatial curve: opacity has nowhere to overshoot to,
    // and the fade wants to finish before the slide does so the text is legible
    // while it is still settling rather than only once it stops.
    Anim {
        id: bodyFadeAnim

        target: root
        property: "bodyFade"
        to: 1
        type: Anim.FastEffects
    }

    function contentReady(): bool {
        if (root.isText)
            return root.pendingText !== null;
        if (root.isImage)
            return root.pendingImgSrc !== "";
        return true;
    }

    // A FLOOR on how long a dip is visible, not a delay before the swap. Content
    // that arrives after this commits the moment it lands; this only stops a
    // decode that finishes in 15ms from showing a one-frame flicker of dip.
    Timer {
        id: holdTimer

        interval: 80
        onTriggered: {
            root.holdElapsed = true;
            root.commit();
        }
    }

    // A ceiling on the coalescing above, for a sustained scroll through entries
    // that are all missing: holdTimer keeps being restarted, so without this the
    // header would run through rows over a frozen body for as long as the key is
    // down. Only reachable when prefetch is losing the race.
    Timer {
        id: maxHold

        interval: 500
        onTriggered: {
            root.holdElapsed = true;
            root.commit();
        }
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
            root.pendingText = cached;
            root.commit();
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

    onEntryChanged: {
        // Reading an entry is the strongest possible signal that it is wanted,
        // and browsing past one is what makes the next few worth holding. Keeps
        // the reader's own copy alive independently of whether its row still has
        // a delegate -- the list scrolls underneath and recycles them.
        Clipboard.retain(root.entry);
        root.stage();
    }
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
        // Last: refresh()'s cache-hit path commits synchronously, and that has
        // to happen on the open's terms (no dip) rather than the browse's.
        root.opened = true;
    }

    // Coalesces key-repeat so a held arrow doesn't spawn a decode per row. Only
    // reachable on a prefetch miss now, and it sits directly in front of the dip
    // -- so it is tuned to the shortest interval that still swallows a repeat
    // burst (~40ms at typical repeat rates) rather than to a comfortable margin.
    Timer {
        id: debounce

        interval: 60
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
                // Still the entry being read? Hand it to the transition, which
                // swaps it in once the dip has had its hold.
                if (root.entry?.entryId === decoder.entryId) {
                    root.pendingText = t;
                    root.commit();
                }
            }
        }
    }

    Process {
        id: imgDecoder

        // The `test -s` skip is what makes a reopened image instant; dropping it
        // under noCache re-runs cliphist every open.
        command: Clipboard.noCache ? ["sh", "-c", "printf '%s' \"$1\" | cliphist decode > \"$2\"", "dec", root.entry?.raw ?? "", root.imgCache] : ["sh", "-c", "test -s \"$2\" || (printf '%s' \"$1\" | cliphist decode > \"$2\")", "dec", root.entry?.raw ?? "", root.imgCache]
        onExited: {
            if (root.isImage) {
                root.pendingImgSrc = `file://${root.imgCache}`;
                root.commit();
            }
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
            // Natural width, matching ClipItem's leading slot exactly: the row
            // reserves one 1em square for every entry type, so the header does
            // too, and the title sits at the same x in both. Any mismatch here
            // rides visibly through the whole slide and teleports across when
            // the handoff unmasks the row.
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
                        return `${root.decoded.length} ${root.decoded.length === 1 ? "character" : "characters"} · ${root.lineCount} ${root.lineCount === 1 ? "line" : "lines"}`;
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
            opacity: root.bodyFade

            // A transform, not a y offset: this must not touch the layout the
            // Flickable scrolls, or contentHeight and contentY would move with
            // the animation. The Flickable clips, so the travel stays inside the
            // body and never spills over the header.
            transform: Translate {
                y: root.bodyOffset
            }

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
            opacity: root.bodyFade

            transform: Translate {
                y: root.bodyOffset
            }

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
            opacity: root.bodyFade

            transform: Translate {
                y: root.bodyOffset
            }
            // The painted box, NOT the full content width: PreserveAspectFit
            // fills the item it is given, so a box wider than the image would
            // upscale it rather than leave it alone. Centred, for the case the
            // reader is held at minWidth by an image narrower than the launcher.
            width: root.imgBoxW
            x: (root.contentW - width) / 2
            // Shared ratio, NOT this Image's own status -- this height is what
            // the launcher sizes itself from, and it has to be right before the
            // full-res decode lands. See imgFitH.
            height: root.imgFitH
            source: root.imgSrc
            // Crop, not Fit, and it matters for a reason that has nothing to do
            // with cropping: fillMode is part of the pixmap cache key
            // (QQuickImage::load folds it into providerOptions), so this and
            // mImg only share one decode if they agree on it. They did not --
            // Fit here against Crop there quietly meant two full decodes of the
            // same file, and made both invisible to the launcher's preload.
            //
            // Safe to change because this box is already the image's own shape:
            // width is imgBoxW and height is that times the aspect, so Crop has
            // nothing to crop and lands pixel-identical to Fit.
            fillMode: Image.PreserveAspectCrop
            // Same url and sourceSize as the morph's mImg, so with caching on
            // at both ends the two share one decode instead of racing two
            // identical ones. That matters on large images: the duplicate was
            // competing for the same CPU and pushing back the moment the morph
            // could show full res.
            //
            // mipmap must match mImg's for the same reason it must load the
            // same url at the same size: they share ONE QSGTexture, and a
            // texture cannot have mipmaps for one consumer and not the other --
            // Qt logs "Mipmap settings changed without having image data
            // available" and silently falls back. Free here anyway: this draws
            // at 1:1, where only the base level is ever sampled.
            cache: !Clipboard.noCache
            asynchronous: true
            mipmap: true
            sourceSize.width: root.imgDecodeW
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
        // The numbers live outside the Flickable, so they have to be carried by
        // the same slide -- otherwise the text travels and the line numbers it
        // belongs to stay nailed in place.
        opacity: root.bodyFade

        transform: Translate {
            y: root.bodyOffset
        }

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

    // The source slot, shared by both morphs: the square the ROW draws, which is
    // the icon's 1em advance (see headerIcon and ClipItem). implicitWidth, not
    // implicitHeight -- the line box is 1.2em and a morph starting from it would
    // begin 8px larger than the thumbnail it is supposed to be lifting off.
    //
    // Also fixes the thumbnail sourceSize on both ends at 2x this: ClipItem's
    // `thumb` and this file's `mThumb` load the same url at the same size, which
    // is what makes the morph's first frame a synchronous cache hit rather than
    // an empty rect. They have to move together or that silently stops working.
    readonly property real slotS: headerIcon.implicitWidth
    readonly property real slotX: Tokens.padding.large + root.slideX
    readonly property real slotY: Tokens.padding.large + root.slideY + (header.implicitHeight - root.slotS) / 2
    // Top of the body's content in root coordinates -- where both morphs land.
    readonly property real bodyTop: Tokens.padding.large + root.slideY + header.implicitHeight + Tokens.spacing.small - viewport.contentY

    Item {
        id: morphImg

        // A plain scissor clip, NOT a StyledClippingRect. That type does its
        // rounded clipping by rendering the content into a ShaderEffectSource
        // and sampling the result, and a whole extra texture round-trip costs
        // real detail: measured against the body Image at identical geometry,
        // the picture carried 7% less high-frequency energy inside the
        // ClippingRectangle than outside it, so the handoff at t=1 read as the
        // image suddenly sharpening. Scissor clipping is exact -- with it the
        // two paths measure 0.992 of each other, i.e. the same picture.
        //
        // The cost is that the corners no longer round during the morph (the
        // backing rect below still does, for entries whose thumbnail has not
        // decoded). An 8px radius on a 41px box for the first frames is a
        // cheaper thing to lose than a visible snap on a 968px one.
        clip: true

        // The rect the body's image actually paints -- the same imgBoxW the
        // body Image is sized to, so the handoff at t=1 is exact by
        // construction rather than by two expressions agreeing. Only horizontal
        // centring can occur: the box is the image's own shape, so there is no
        // letterbox. Uses the shared ratio (see imgArW), which now comes from
        // the descriptor, so the box flies to the true shape from frame 1.
        readonly property real fitW: root.imgBoxW > 0 ? root.imgBoxW : root.contentW
        readonly property real fitH: root.imgBoxW > 0 ? root.imgFitH : root.contentW
        readonly property real dstX: Tokens.padding.large + (root.contentW - fitW) / 2

        // POSITION rides the raw curve, including its 1.39% overshoot -- that is
        // the bounce, and it is shared with the header, the window and every
        // other spatial move in the shell.
        //
        // SIZE deliberately does not. The texture is decoded at exactly fitW, so
        // any overshoot past 1 asks the image to be drawn larger than it has
        // pixels for: a magnification, soft for the whole tail of the animation,
        // resolving in one frame the instant the curve settles. Sizing the
        // texture for the peak instead only moves that softness onto the resting
        // image, which is worse. Clamping here means the morph only ever
        // minifies -- the direction with real pixels behind it -- and the last
        // frame of the morph is pixel-identical to the body image it hands off
        // to. The 13px of size bounce this gives up is the cheapest part of the
        // overshoot; the travel still carries it.
        readonly property real sizeT: Math.min(1, root.morphT)

        visible: root.isImage && (root.morphing || root.morphT < 1)
        x: root.slotX + (dstX - root.slotX) * root.morphT
        y: root.slotY + (root.bodyTop - root.slotY) * root.morphT
        width: root.slotS + (fitW - root.slotS) * sizeT
        height: root.slotS + (fitH - root.slotS) * sizeT
        // Clamped: morphT passes 1 on the overshoot, which would otherwise ask
        // for a negative radius.

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.small * Math.max(0, 1 - root.morphT)
            color: Colours.palette.m3surfaceContainerHigh
        }

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
            cache: !Clipboard.noCache
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
            cache: !Clipboard.noCache
            asynchronous: true
            // This is the one that actually needs the mipmaps. The morph draws
            // this texture into a box that starts at slotS (~41px) and grows to
            // imgBoxW, so early frames are a 20x-plus reduction. Four bilinear
            // taps cannot represent that and shimmer instead; a mip chain
            // pre-averages it. The extra softness only exists while the box is
            // tiny, which is exactly when there is no detail to lose.
            mipmap: true
            sourceSize.width: root.imgDecodeW
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
