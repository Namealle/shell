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

// One clipboard entry, rendered. Everything that is per-entry lives here: the
// decoded text and its line index, the progressive loader, the gutter, the
// colour swatch, the image with its zoom/pan and hi-res copy.
//
// This exists so the reader can hold SEVEN of them at once -- see ClipReader's
// rail. Browsing is then a scroll past live neighbours rather than a swap of
// one body's contents, which is what retires the whole freeze-a-texture-and-
// slide-it machinery the transition used to be.
//
// `active` is the entire cost model, and it is what makes seven affordable:
//
//   |             | active                   | inactive                    |
//   |-------------|--------------------------|-----------------------------|
//   | text        | progressive loadTo       | initialChars only           |
//   | gutter      | recomputed on scroll     | computed once at contentY 0 |
//   | inner scroll| free                     | pinned to 0                 |
//   | hi-res image| on zoom                  | never, unless eagerHiRes    |
//   | cold decode | spawns its own cliphist  | waits for prefetch          |
Item {
    id: root

    // The ClipEntry this body draws. Never null in the rail (the model is the
    // list's fullResults), but the type is `var` because ClipEntry is a plain
    // QtObject built by the Clipboard service.
    required property var entry
    // Live find term, from the reader. Only the active body is ever given one:
    // finding inside an entry you are not reading has nothing to scroll to.
    property string findTerm: ""
    // The one entry under the reader's header. See the table above.
    property bool active: false
    // False only while the reader's leading-slot morph is still in flight
    // towards this body -- the overlay lands exactly on the image/swatch below,
    // so the real one stays hidden until the handoff. Always true for the
    // neighbours, which no morph is aimed at.
    property bool handedOff: true

    readonly property bool isImage: root.entry?.isImage ?? false
    readonly property bool isBinary: !!(root.entry?.binMatch)
    // A lone colour (hex/rgb/hsl, parsed by Clipboard.colourOf into Qt's
    // #AARRGGBB) gets its own body: just the row's swatch grown. It is
    // deliberately NOT a text body -- no decode, no gutter, no find, since the
    // preview IS the whole content. The header still shows the exact string
    // that was copied.
    readonly property string colour: root.entry?.colour ?? ""
    readonly property bool isColour: root.colour.length > 0
    readonly property color colourValue: root.isColour ? root.colour : "transparent"
    readonly property bool isText: !!root.entry && !root.isBinary && !root.isColour

    readonly property string imgCache: root.isImage && root.entry ? `/tmp/caelestia-clip-preview-${root.entry.entryId}.png` : ""

    // Defined by the Clipboard service, which owns the image box formula so the
    // prefetcher can warm the exact decode this asks for. See readerImageWidth.
    readonly property int maxWidth: Clipboard.readerMaxWidth
    readonly property int maxHeight: Clipboard.readerMaxHeight
    readonly property int minWidth: Tokens.sizes.launcher.itemWidth
    // How slim the reader may get for a tall image -- the only content allowed
    // to pull the window in below the list width at all. A portrait image is
    // width-limited by maxHeight (a 4K 9:16 clip paints 360 wide), and holding
    // the window at the list width around it just frames the picture in two
    // dead bars that nothing can ever fill: the image cannot grow into them
    // without growing taller than the height ceiling, which for that aspect
    // means a ~980px body, and for a phone screenshot ~1230px. The free axis is
    // the one to spend, so the window closes on the picture instead.
    //
    // The floor exists because that reasoning runs out: nothing stops an aspect
    // getting narrower, and a 40x2000 sliver would otherwise collapse the
    // launcher into a straw with a header too narrow to read. 0.6 is chosen to
    // clear the 4K portrait case exactly -- the slimmest thing worth fitting --
    // and to leave the header's title a legible run after the icon.
    readonly property int minImageWidth: Math.round(root.minWidth * 0.6)
    // Big enough to actually judge a colour, small enough that the launcher does
    // not become a full-screen flash of it. The body used to be a 240px swatch
    // plus three notation lines; the notations are gone, so the swatch takes the
    // space they occupied and the reader keeps the size it has always had.
    readonly property int swatchHeight: 240 + Tokens.spacing.medium + Math.round(fm.height * 3)

    // -- decoded text --
    //
    // Read from the shared cache rather than owned: Clipboard.decodedText is
    // filled by the prefetcher, which is what makes an arriving neighbour
    // instant. A body only decodes for ITSELF when it is active and the cache
    // missed -- see refresh().
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
    readonly property int charCount: root.decoded.length

    // All widths derive from CONTENT (never from the animated laid-out width),
    // so the text lays out once per entry -- not on every frame of the morph,
    // and not on every frame of a rail move either. The frame animates between
    // two entries' widths while both are on screen, so a body is routinely
    // wider or narrower than the box it is currently in; the reader's clip cuts
    // the difference, exactly as it already did for the old body slide.
    readonly property real charWidth: fm.advanceWidth("0")
    readonly property real gutterWidth: fm.advanceWidth(String(Math.max(1, root.lineCount)))
    readonly property real contentW: root.implicitWidth - Tokens.padding.large * 2
    readonly property real textW: root.contentW - root.gutterWidth - Tokens.spacing.medium

    // Where that content box sits inside the box this body was actually GIVEN.
    //
    // The two are equal at rest -- the frame is cut to the entry being read --
    // but the frame animates between two entries' widths, so for the whole of a
    // move every body on the rail is in a box that is not its own. Left-aligning
    // put all of that difference on one side, which is what a wide entry
    // followed by a tall one shows as a slab of dead space down the right. The
    // difference is real either way; centring is what makes it read as the frame
    // closing in on the picture rather than the picture sliding off-centre.
    //
    // Block content only -- image and swatch. Text stays hard left, because a
    // paragraph that slides sideways on every browse is worse than slack on one
    // side. See bodyRow.
    //
    // x only -- the widths above still come from CONTENT, so nothing relayouts
    // on a frame that is merely moving.
    readonly property real contentX: Math.round((root.width - root.contentW) / 2)
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
    //
    // Only for the entry being read. An inactive body cannot scroll (contentY is
    // pinned to 0), so it has nothing to load towards -- and six neighbours each
    // pulling 32k slabs to fill a viewport they will never show is precisely the
    // cost that would make a rail of live bodies unaffordable.
    function maybeLoadMore(): void {
        // The raw comparison, NOT the fullyLoaded binding. Reading that here put
        // it on the evaluation stack of a call that goes on to write loadedChars
        // -- its own dependency -- which Qt reports as a binding loop on
        // fullyLoaded. The declarative property is for display (loadedLines);
        // the loader reads raw state.
        if (!root.active || root.loading || !root.isText || root.loadedChars >= root.decoded.length)
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
    // decoded. The thumbnail probe below is the same url at the same sourceSize
    // ClipItem's row thumbnail uses, so it is a synchronous pixmap-cache hit and
    // the ratio is known before anything of this entry has been decoded at
    // reader size -- which is what lets a neighbour on the rail report its real
    // height before you ever arrive at it.
    readonly property bool imgReady: image.status === Image.Ready && image.implicitHeight > 0
    readonly property bool thumbReady: ratioProbe.status === Image.Ready && ratioProbe.implicitHeight > 0
    // cliphist's own descriptor first: it is exact, it is the TRUE resolution
    // (a decoded copy only ever reports its sourceSize-capped size), and it is
    // there before anything has been decoded at all. The decoded copies remain
    // as the fallback for entries whose descriptor carries no WxH.
    readonly property var imgDims: root.isImage ? (root.entry?.imgDims ?? null) : null
    readonly property real imgArW: root.imgDims ? root.imgDims.w : (root.imgReady ? image.implicitWidth : (root.thumbReady ? ratioProbe.implicitWidth : 0))
    readonly property real imgArH: root.imgDims ? root.imgDims.h : (root.imgReady ? image.implicitHeight : (root.thumbReady ? ratioProbe.implicitHeight : 0))
    // The natural-resolution clamp, which is NOT the same fallback chain as the
    // ratio above: the probe is a 96px copy, so its width is a valid ratio but a
    // useless resolution, and clamping to it would open every descriptor-less
    // image at thumbnail size and then pop to full size when the real decode
    // landed. Only the descriptor and the body image are honest here (the body's
    // own cap is maxWidth, which is the ceiling anyway); until one of them
    // speaks, don't clamp.
    readonly property real imgNatW: root.imgDims ? root.imgDims.w : (root.imgReady ? image.implicitWidth : root.maxWidth)

    // The box the body's image paints in -- the single source of truth for this
    // entry's width, its height, and both of the reader morph's endpoints. 0
    // while the ratio is still unknown; callers fall back to minWidth.
    //
    // Gated on isImage rather than left to return 0 on its own. That function
    // reads Tokens off the Clipboard SINGLETON, which has no screen, so every
    // call logs a "Tokens.sizes accessed without a screen set" warning -- once
    // per reader before, but seven live bodies re-evaluating it turned that into
    // hundreds. Text and colour entries have no box to compute either way.
    readonly property real imgBoxW: root.isImage ? Clipboard.readerImageWidth(root.imgArW, root.imgArH, root.imgNatW) : 0

    // The size to DECODE at, which is the size it is drawn at rather than a flat
    // ceiling. A texture bigger than its box has to be minified on the way to
    // the screen, and Qt's default filtering there is 4-tap bilinear with no
    // mipmaps -- which cannot represent a large reduction and aliases instead of
    // averaging. A portrait clip used to decode 1000px wide and paint at 360:
    // permanently undersampled, at rest, for no benefit. Matching the two makes
    // the draw exactly 1:1, which is both the sharpest it can be and the least
    // memory it can cost.
    //
    // Computed straight from the descriptor rather than read off imgBoxW, which
    // is what keeps imgNatW's fallback from closing a loop
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

    // -- image zoom / pan --
    //
    // imv's two gestures and nothing else: wheel zooms about the cursor, drag
    // pans, double-click resets. Deliberately a TRANSFORM on the Image and never
    // a change to its width/height -- imgBoxW drives implicitWidth and imgFitH
    // drives contentHeight, so resizing the image here would drag the whole
    // window's geometry along with the gesture.
    //
    // Nothing had to be given up for the wheel: readerImageWidth caps the box by
    // maxHeight (cap = min(maxWidth - pad, maxHeight * ar)), so imgFitH can never
    // exceed the viewport and an image entry's Flickable is never scrollable.
    // The wheel did nothing here before.
    //
    // 1 is the FLOOR, not a midpoint -- there is no zooming out past fit. The
    // window is cut to the picture, so a smaller picture inside it could only
    // ever be the picture plus dead bars, which is the one thing this file's
    // whole sizing chain exists to avoid (see minImageWidth).
    property real zoom: 1
    property real panX: 0
    property real panY: 0

    // 1:1 with the source pixels is the meaningful ceiling, exactly as it is in
    // any viewer: past it there is no more picture to find. The floor of 2 is for
    // images the reader already upscales (a 40x30 clip is drawn ~14x up), where
    // that ratio is below 1 and would otherwise mean no zoom at all -- they have
    // no detail to reveal, but the gesture should still work.
    readonly property real maxZoom: Math.max(2, Math.min(16, root.imgNatW / Math.max(1, root.imgBoxW)))
    readonly property bool zoomed: root.zoom > 1.001

    // Latched rather than bound to `zoomed`, so pinching back to fit and in again
    // does not throw away the full-res decode and pay for it twice. Cleared when
    // the body goes inactive, which is what bounds the cost to one picture at a
    // time even with seven bodies alive.
    property bool wantHiRes: false

    // The image is centred in a viewport it exactly fills, so the overhang on
    // each side is half the growth. At zoom 1 both are 0 -- which is what makes
    // dragging a no-op at rest instead of something that has to be special-cased.
    readonly property real maxPanX: root.imgBoxW * (root.zoom - 1) / 2
    readonly property real maxPanY: root.imgFitH * (root.zoom - 1) / 2

    // Clamped so an edge can never come inside the viewport. Same reasoning as
    // the zoom floor: the picture may leave the frame, the frame may never show
    // anything that is not picture.
    function setPan(x: real, y: real): void {
        root.panX = Math.max(-root.maxPanX, Math.min(root.maxPanX, x));
        root.panY = Math.max(-root.maxPanY, Math.min(root.maxPanY, y));
    }

    function resetZoom(): void {
        root.zoom = 1;
        root.panX = 0;
        root.panY = 0;
        root.wantHiRes = false;
    }

    // Zoom about the cursor: the content point under the pointer must not move.
    // With s = centre + p * zoom + pan, holding s fixed across a zoom change
    // gives pan -= p * dZoom, where p is that point in unscaled image coords.
    //
    // Multiplicative steps, because zoom is perceptually logarithmic -- a fixed
    // +0.25 crawls near 1x and leaps near the ceiling. Scaled by the reported
    // delta so a high-resolution wheel or a touchpad stays proportional instead
    // of jumping a full notch per event.
    function zoomAt(cx: real, cy: real, delta: real): void {
        const from = root.zoom;
        const to = Math.max(1, Math.min(root.maxZoom, from * Math.pow(1.15, delta / 120)));
        if (to === from)
            return;
        const px = (cx - root.imgBoxW / 2 - root.panX) / from;
        const py = (cy - root.imgFitH / 2 - root.panY) / from;
        root.zoom = to;
        if (to > 1)
            root.wantHiRes = true;
        // Re-clamps against the new maxPan, which is what walks the picture back
        // into frame when zooming out rather than leaving a bar behind.
        root.setPan(root.panX - px * (to - from), root.panY - py * (to - from));
    }

    // -- geometry the reader reads --
    //
    // implicitWidth is the whole FRAME width this entry wants (content plus the
    // reader's padding), not the content box -- the reader passes it straight
    // through to its own implicitWidth, and contentW above subtracts the padding
    // back off. One number, defined once, rather than the same sum written at
    // both ends and drifting.
    implicitWidth: {
        // Images size to their content exactly as text does, except that they
        // may also size DOWN past the list width -- see minImageWidth. No test
        // for "is this a tall image" is needed: readerImageWidth's floor already
        // grows every other image to fill the body at the default width, so the
        // only box that can come back narrower than that is one the height
        // ceiling cut down. Everything else (colour swatch, bare binary
        // descriptor) has no natural width to grow to and stays at the list
        // width -- as does an image whose ratio has not landed yet, which would
        // otherwise open slim on a box of 0 and widen once it does.
        if (root.isImage)
            return root.imgBoxW > 0 ? Math.max(root.minImageWidth, root.imgBoxW + Tokens.padding.large * 2) : root.minWidth;
        if (!root.isText)
            return root.minWidth;
        const natural = root.gutterWidth + Tokens.spacing.medium + root.longestLine * root.charWidth;
        return Math.max(root.minWidth, Math.min(root.maxWidth, natural + Tokens.padding.large * 2));
    }

    // A FLOOR, and the whole reason the hold-the-old-height machinery could be
    // deleted. That machinery (heldHeight/dip/kick/holdTimer/maxHold) existed to
    // stop the frame collapsing while a decode was in flight, because the body
    // being swapped into was empty until it landed. On the rail the body you are
    // arriving at has been alive and preloaded for several moves, so it already
    // knows its height -- except for the one case the prefetch window cannot
    // cover, an entry you flew past everything to reach. This is that case, and
    // a floor is the whole fix: the frame opens at a readable size and grows
    // once the text lands, instead of pinching shut and springing back.
    readonly property real minBodyHeight: 96

    // Never below the floor, and never SHRINKING below it either: a body whose
    // content is genuinely shorter than the floor (a two-word clip) reports its
    // real height, so the frame still cuts to its content.
    readonly property real liveHeight: root.isText ? Math.min(root.maxHeight, viewport.contentHeight) : (root.isColour ? root.swatchHeight : (root.isImage ? root.imgFitH : viewport.contentHeight))
    implicitHeight: root.contentKnown ? Math.min(root.maxHeight, root.liveHeight) : root.minBodyHeight

    // Whether this body has anything real to report a height from. False is the
    // cold case above: no decode, no ratio, nothing on disk yet.
    readonly property bool contentKnown: root.isText ? root.decoded.length > 0 : (root.isColour ? true : (root.isImage ? root.imgFitH > 0 : true))

    // Where the active body is scrolled to, for the reader's morph endpoints.
    readonly property real scrollY: viewport.contentY

    // Coalesces the end-of-turn work to one call, exactly as Qt.callLater did --
    // but OWNED by this body, so it dies with it.
    //
    // Qt.callLater does NOT. The rail recycles delegates, so a call queued by a
    // scroll or a slab that was still settling fired into a destroyed context:
    // "QQmlVMEMetaObject: Internal error - attempted to evaluate a function in
    // an invalid context", then "Property 'lineOfOffset' ... is not a function"
    // as every member of the dead object read back undefined. A Timer is a child
    // of this item and is torn down with it, so nothing can fire late.
    Timer {
        id: settle

        interval: 0
        onTriggered: {
            root.updateGutter();
            root.maybeLoadMore();
        }
    }

    // Same ownership reason. Separate from `settle` because it is driven by the
    // decode landing rather than by layout, and it must not be coalesced away by
    // a scroll that happens to arrive in the same turn.
    Timer {
        id: findLater

        interval: 0
        onTriggered: root.applyFind()
    }

    FontMetrics {
        id: fm
        font: bodyText.font
    }

    QtObject {
        id: cache

        property string text: ""
    }

    // -- content --
    //
    // Pulls from the shared decode cache first, always. A body only spawns its
    // own cliphist when it is the one being READ and the cache missed -- six
    // neighbours each forking a process would be a decode storm on every arrow
    // key, and the prefetcher already covers the window the rail instantiates.
    function refresh(): void {
        const e = root.entry;
        if (!e)
            return;
        if (root.isImage) {
            // Images are different: the file has to exist on disk before an
            // Image can show anything at all, and `test -s` makes this a no-op
            // for everything the launcher's preload already wrote. So every
            // image body on the rail runs it, active or not -- otherwise a
            // neighbour would slide past as an empty box.
            imgDecoder.running = false;
            imgDecoder.running = true;
            return;
        }
        if (!root.isText)
            return;
        // A cliphist reload can destroy the entry object mid-read; its
        // properties all read undefined then. Skip -- the reload will hand the
        // rail a fresh entry.
        const id = e.entryId;
        const raw = e.raw;
        if (id === undefined || raw === undefined)
            return;
        const cached = Clipboard.decodedText[id];
        if (cached !== undefined) {
            cache.text = cached;
            return;
        }
        // Cold and not being read: leave it to the prefetcher. The floor on
        // implicitHeight is what keeps this from showing as a collapsed frame.
        if (!root.active)
            return;
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

    onEntryChanged: root.refresh()
    onFindTermChanged: root.applyFind()

    // Leaving an entry rewinds it, OFF SCREEN, so the rewind is never seen.
    //
    // Reading position is deliberately NOT remembered. Every arrival lands at
    // the top of the entry, whether you browsed one step away or nine.
    // Remembering would have meant either a position map keyed by entryId, or a
    // rule that silently changed behaviour once the rail's ListView recycled the
    // delegate. And a neighbour parked mid-document would slide INTO view
    // showing its middle, which is the visual half of the same argument.
    onActiveChanged: {
        if (root.active) {
            // Cold entries wait for the prefetcher while inactive -- now that
            // this is the one being read, it may decode for itself.
            root.refresh();
            root.maybeLoadMore();
            return;
        }
        scrollAnim.running = false;
        scrollAnim.to = 0;
        viewport.contentY = 0;
        root.resetZoom();
        bodyText.deselect();
    }

    // Every path that changes the decoded text lands here: cache hit, fresh
    // decode, or a prefetch landing under a body already on the rail. Rebuild
    // the body and seed the first few screens.
    onDecodedChanged: {
        root.resetBody();
        if (root.isText && root.decoded.length)
            root.loadTo(root.initialChars);
        findLater.restart();
    }

    Component.onCompleted: root.refresh()

    // The prefetcher fills Clipboard.decodedText by MUTATION, which emits no
    // change signal, so a body that came up cold has no other way to learn its
    // text arrived. Cheap: a generation bump per decode, and re-reading a key
    // that is almost always still undefined.
    Connections {
        target: Clipboard

        function onDecodeGenerationChanged(): void {
            if (root.isText && !root.decoded.length)
                root.refresh();
        }
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
                // Still the entry this body draws? A cliphist reload can have
                // swapped it out while the process ran.
                if (root.entry?.entryId === decoder.entryId)
                    cache.text = t;
            }
        }
    }

    Process {
        id: imgDecoder

        // The `test -s` skip is what makes a reopened image instant; dropping it
        // under noCache re-runs cliphist every open.
        command: Clipboard.noCache ? ["sh", "-c", "printf '%s' \"$1\" | cliphist decode > \"$2\"", "dec", root.entry?.raw ?? "", root.imgCache] : ["sh", "-c", "test -s \"$2\" || (printf '%s' \"$1\" | cliphist decode > \"$2\")", "dec", root.entry?.raw ?? "", root.imgCache]
        onExited: {
            if (root.isImage)
                root.imgSrc = `file://${root.imgCache}`;
        }
    }

    // Ratio only. Same url and sourceSize as ClipItem's row thumbnail with
    // caching on at both ends, so this is a synchronous pixmap-cache hit rather
    // than a decode -- which is what lets a body report a truthful height before
    // its reader-sized copy exists. Never painted.
    Image {
        id: ratioProbe

        visible: false
        source: root.isImage ? root.imgSrc : ""
        fillMode: Image.PreserveAspectCrop
        cache: !Clipboard.noCache
        asynchronous: true
        sourceSize.width: Clipboard.thumbSize
        sourceSize.height: Clipboard.thumbSize
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

    StyledFlickable {
        id: viewport

        anchors.fill: parent

        // Flickable does NOT clip by default, and on a rail of live bodies that
        // is not cosmetic: a text entry's height is capped at maxHeight while its
        // contentHeight is the whole loaded document, so everything past the cap
        // was being painted straight over the neighbours below it. Measured on a
        // 640px-capped entry at rail y=0: contentHeight 3249, i.e. it drew across
        // the next eleven entries, which is the ghost text seen sitting on top of
        // a short entry for the length of a move.
        //
        // It also bounds the zoomed image, which grows past its own box by
        // construction (the transform scales about the centre and the box stays
        // imgFitH tall) and had the same freedom to spill.
        //
        // Cheap: the rect is axis-aligned, so this is a scissor, not a texture.
        clip: true

        // Pinned for everything but the entry being read. A neighbour cannot be
        // scrolled by anything -- the rail is programmatic and the wheel only
        // reaches the active body -- but this makes it structural rather than
        // incidental.
        interactive: root.active

        contentWidth: width
        contentHeight: root.isText ? bodyRow.implicitHeight : (root.isColour ? colourBody.implicitHeight : image.height)

        onContentYChanged: settle.restart()
        // Deliberately NOT hooked to onHeightChanged: the height animates through
        // the whole morph, and the gutter window is now sized from maxHeight so
        // it does not depend on it. See updateGutter.

        // Only the entry being read gets a scrollbar. On a neighbour it would be
        // a control for a gesture that cannot happen, sliding past mid-move.
        StyledScrollBar.vertical: StyledScrollBar {
            flickable: viewport
            visible: root.active
        }

        // Text entries: line-number gutter + selectable, wrapping monospace text.
        Row {
            id: bodyRow

            visible: root.isText
            // Left, NOT contentX. Reading starts at a fixed left edge and a
            // paragraph that slid sideways on every browse would be worse than a
            // little slack on the right -- which for text is only ever the
            // gutter's column moving anyway. Centring is for the block content
            // (image, swatch), where the shape IS the thing being framed.
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
                // Only on the entry being read: a drag across a neighbour would
                // otherwise select text in a body that is about to slide away.
                selectByMouse: root.active
                persistentSelection: true
                textFormat: TextEdit.PlainText
                // Word boundaries; only runs longer than a row split mid-word.
                // The gutter follows the real layout (updateGutter), so it does
                // not need fixed-chars-per-row wrapping.
                wrapMode: TextEdit.Wrap
                onWidthChanged: settle.restart()
                // A slab has landed and been laid out: renumber the visible rows,
                // then re-check whether the viewport still needs more. Driving
                // load-more from here (rather than from loadTo) is what
                // guarantees the check sees a real contentHeight.
                onContentHeightChanged: settle.restart()
                color: Colours.palette.m3onSurface
                selectionColor: Colours.palette.m3primary
                selectedTextColor: Colours.palette.m3onPrimary
                font: Tokens.font.mono.small
                renderType: Text.NativeRendering
            }
        }

        // Colour entries: the row's swatch at reading size, nothing else. The
        // header already carries the exact string that was copied.
        Column {
            id: colourBody

            visible: root.isColour
            x: root.contentX
            width: root.contentW

            // The swatch's space is reserved by this Item, not by the rect
            // itself: the rect is hidden until the morph overlay lands on it,
            // and a Column would collapse around a hidden child -- taking the
            // body height (and so the reader's own height) to zero for the
            // whole morph.
            Item {
                width: parent.width
                height: root.swatchHeight

                StyledRect {
                    anchors.fill: parent
                    // Hidden while the reader's morph overlay is in flight -- it
                    // lands exactly on this rect, then hands off. Always true on
                    // a neighbour, which no morph is aimed at.
                    visible: root.handedOff
                    radius: Tokens.rounding.small
                    color: root.colourValue
                    // Same 1px outline the row's swatch has, so a colour close
                    // to the surface still reads as a swatch rather than a hole
                    // -- and so the handoff from the morph is pixel-true.
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant
                }
            }
        }

        // Image entries: the decoded thumbnail, aspect-fit, height capped.
        Image {
            id: image

            // Hidden while the reader's morph overlay is in flight -- it lands
            // exactly on this rect, then hands off.
            visible: root.isImage && root.handedOff

            // Scale first, about the centre, then translate -- so panX/panY are
            // plain screen-space offsets and the clamp in setPan can be written
            // against the overhang directly. Neither touches the layout the
            // Flickable measures: contentHeight stays imgFitH at every zoom, so
            // the window does not breathe while you scroll.
            transform: [
                Scale {
                    origin.x: image.width / 2
                    origin.y: image.height / 2
                    xScale: root.zoom
                    yScale: root.zoom
                },
                Translate {
                    x: root.panX
                    y: root.panY
                }
            ]

            // Deliberately unanimated. A Behavior here would ease `zoom` while
            // zoomAt has already written the pan for the final value, so the
            // point under the cursor would drift and settle rather than stay
            // pinned -- and imv's zoom is instant anyway. The 1.15 steps are
            // small enough to read as smooth on their own.
            //
            // Gated on `active` like every other gesture here: the wheel belongs
            // to the entry being read, not to whichever neighbour happens to be
            // under the pointer mid-move.
            WheelHandler {
                enabled: root.active
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => root.zoomAt(event.x, event.y, event.angleDelta.y)
            }

            // target: null -- this drives root.panX/panY through the clamp rather
            // than letting the handler move the item, which would bypass it and
            // let the picture be dragged clean off its own frame.
            DragHandler {
                id: panHandler

                property real fromX: 0
                property real fromY: 0

                target: null
                enabled: root.active && root.zoomed
                cursorShape: Qt.ClosedHandCursor

                onActiveChanged: {
                    if (active) {
                        fromX = root.panX;
                        fromY = root.panY;
                    }
                }
                // translationChanged, not activeTranslationChanged: that IS
                // activeTranslation's NOTIFY signal (it is shared with
                // persistentTranslation), and naming the real signal avoids
                // leaning on QML's property-handler mapping for a rename.
                onTranslationChanged: root.setPan(fromX + activeTranslation.x, fromY + activeTranslation.y)
            }

            HoverHandler {
                enabled: root.active && root.zoomed && !panHandler.active
                cursorShape: Qt.OpenHandCursor
            }

            TapHandler {
                enabled: root.active
                onDoubleTapped: root.resetZoom()
            }

            // The full-resolution copy, decoded only once you have actually
            // zoomed -- and never held for an entry you have not.
            //
            // A child, so it inherits the transform above rather than restating
            // the geometry. It fades in OVER the base image, which keeps
            // painting underneath the whole time: the sharpening is the only
            // thing you see, never a blank frame.
            //
            // Why not just raise the base image's sourceSize instead: that is
            // part of the pixmap cache key, so it would fork this Image off the
            // decode it shares with the reader's morph copy and blank the body
            // until the new one landed -- mid-gesture, which is the worst
            // possible moment.
            //
            // And why not decode everything full-size up front: that is exactly
            // what Clipboard.eagerHiRes turns on, and why it defaults off. At
            // the box size a copy is ~1.6MB; at 4K it is ~33MB, on the one
            // decode thread the row thumbnails also queue on. Seven of those
            // would make the list paint slower, which is the opposite of what
            // the rail is for.
            Image {
                anchors.fill: parent

                // Exactly what maxZoom can ask for and no more -- past 1:1 with
                // the source there is nothing further to resolve, so a bigger
                // decode would be memory spent on nothing.
                readonly property int hiResW: Math.round(root.imgBoxW * root.maxZoom)

                visible: root.isImage
                // Cleared with wantHiRes when the body goes inactive, which is
                // what frees the pixmap: `cache: false` means nothing outlives
                // this source.
                source: root.wantHiRes || (Clipboard.eagerHiRes && root.isImage) ? root.imgSrc : ""
                sourceSize.width: hiResW
                // Matches the base image for the same reason the base matches
                // the morph copy: same url and fillMode or the two are separate
                // decodes.
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // The one image in this file that must NOT be retained. It is
                // the largest thing the reader ever decodes and it is wanted for
                // exactly one entry, so leaving it in Qt's cache would undo the
                // bound the box-sized decodes are chosen to keep.
                cache: false
                // Drawn magnified when it matters, so unlike the base image this
                // one really does sample below the base level.
                mipmap: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }
            }
            // The painted box, NOT the full content width: PreserveAspectFit
            // fills the item it is given, so a box wider than the image would
            // upscale it rather than leave it alone. Still centred, for the one
            // case that survives the window closing on the picture: an aspect
            // narrow enough to hit minImageWidth, where the bars are the floor's
            // doing and cannot be closed.
            width: root.imgBoxW
            // Centred in the box this body was GIVEN, not in its own content box
            // -- see contentX. Those coincide at rest; they do not for the whole
            // of a move between two differently-shaped pictures, which is where
            // the off-centre bars were.
            x: root.contentX + (root.contentW - width) / 2
            // Shared ratio, NOT this Image's own status -- this height is what
            // the launcher sizes itself from, and it has to be right before the
            // full-res decode lands. See imgFitH.
            height: root.imgFitH
            source: root.imgSrc
            // Crop, not Fit, and it matters for a reason that has nothing to do
            // with cropping: fillMode is part of the pixmap cache key
            // (QQuickImage::load folds it into providerOptions), so this and the
            // reader's morph copy only share one decode if they agree on it.
            // They did not -- Fit here against Crop there quietly meant two full
            // decodes of the same file, and made both invisible to the
            // launcher's preload.
            //
            // Safe because this box is already the image's own shape: width is
            // imgBoxW and height is that times the aspect, so Crop has nothing
            // to crop and lands pixel-identical to Fit.
            fillMode: Image.PreserveAspectCrop
            // Same url and sourceSize as the reader's morph copy, so with
            // caching on at both ends the two share one decode instead of racing
            // two identical ones. That matters on large images: the duplicate was
            // competing for the same CPU and pushing back the moment the morph
            // could show full res.
            //
            // mipmap must match it for the same reason it must load the same url
            // at the same size: they share ONE QSGTexture, and a texture cannot
            // have mipmaps for one consumer and not the other -- Qt logs "Mipmap
            // settings changed without having image data available" and silently
            // falls back. Free here anyway: this draws at 1:1, where only the
            // base level is ever sampled.
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

        // Left, with the text it numbers -- see bodyRow.
        x: viewport.x
        y: viewport.y
        width: root.gutterWidth
        height: viewport.height
        clip: true
        visible: root.isText

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
}
