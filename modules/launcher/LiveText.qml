pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

// Text you can select in a picture, the screenshot editor's Live Text for the
// reader's image body. Tesseract reads the image once (per-character boxes,
// hOCR); a drag over text then selects it as in a text view: one click a
// caret, two a word, three a line. No button, no mode: a press anywhere else
// is left to the gestures underneath (pan, double-click to reset the zoom).
//
// Sits in the image's own coordinates (a child of the Image, filling it), so
// it inherits the zoom and pan transform and the highlight stays on the
// letters at any zoom.
//
// Geometry is kept in the page's own pixels (tesseract's) and scaled to this
// item when drawn or hit: the box it is drawn in changes size with the
// reader, and a copy of every box per size would go stale.
Item {
    id: root

    // The image file to read, and whether to read it (the entry is the one
    // being read). Tesseract is not asked until `active` has held a moment:
    // stepping through the rail must not start a read per entry.
    property string source
    property bool active
    // The picture is zoomed: off text, the cursor is the pan hand
    property bool zoomed

    // One entry per character in reading order ({c, x, w, word, line}), the
    // space between two words and the break between two lines as entries of
    // their own, so a selection is a pair of offsets into it
    property var chars: []
    // {first, last} character ranges, for double-click
    property var words: []
    // {first, last, x, y, w, h}: the line's characters and its box
    property var lines: []
    property real pageW: 0
    property string readFor
    readonly property bool busy: ocr.running
    readonly property real pageScale: pageW > 0 ? width / pageW : 1

    property int selA: -1
    property int selB: -1
    readonly property int selLo: Math.min(selA, selB)
    readonly property int selHi: Math.max(selA, selB)
    readonly property bool hasSelection: selA >= 0 && selB >= 0 && selA !== selB
    property int selUnit: 1
    property int anchorLo: -1
    property int anchorHi: -1
    // A drag that started on text, still going
    property bool selecting

    readonly property var selRects: {
        if (!hasSelection)
            return [];
        const out = [];
        for (const line of lines) {
            const a = Math.max(line.first, selLo);
            const b = Math.min(line.last + 1, selHi);
            if (a >= b)
                continue;
            const x0 = chars[a].x;
            const last = chars[b - 1];
            // A line's trailing break has no width: stop at the last glyph
            const x1 = last.c === "\n" || last.c === "\n\n" ? line.x + line.w : last.x + last.w;
            out.push(Qt.rect(x0 * pageScale, line.y * pageScale, Math.max(1, x1 - x0) * pageScale, line.h * pageScale));
        }
        return out;
    }

    onSourceChanged: reset()
    onActiveChanged: {
        if (active)
            readLater.restart();
        else
            readLater.stop();
    }

    function reset(): void {
        ocr.running = false;
        chars = [];
        words = [];
        lines = [];
        pageW = 0;
        readFor = "";
        selA = selB = anchorLo = anchorHi = -1;
        selecting = false;
        if (active)
            readLater.restart();
    }

    function read(): void {
        if (!source || readFor === source || ocr.running)
            return;
        ocr.path = source;
        ocr.running = true;
    }

    // The selected text, copied. False when there is none, so the key goes on
    // to whatever it did before.
    function copy(): bool {
        if (!hasSelection)
            return false;
        const text = chars.slice(selLo, selHi).map(c => c.c).join("").trim();
        if (!text)
            return false;
        Quickshell.execDetached(["wl-copy", "--", text]);
        return true;
    }

    function clearSelection(): void {
        selA = selB = anchorLo = anchorHi = -1;
    }

    // ---------------------------------------------------------------- reading

    function decodeEntities(t: string): string {
        return t.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (m, e) => {
            if (e[0] === "#")
                return String.fromCodePoint(e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
            return {
                amp: "&",
                lt: "<",
                gt: ">",
                quot: "\"",
                apos: "'"
            }[e.toLowerCase()];
        });
    }

    // hOCR with per-character boxes: page > carea > par > line > word > cinfo.
    // The editor's parser (ShotEditor.parseOcr), kept in page pixels.
    function parse(hocr: string): void {
        const page = /class='ocr_page'[^>]*?bbox (\d+) (\d+) (\d+) (\d+)/.exec(hocr);
        const cs = [], ws = [], ls = [];
        let para = 0;
        let line = null;
        let word = null;

        const flushWord = () => {
            if (!word || !line || !word.chars.length)
                return;
            const text = word.chars.map(c => c.c).join("");
            // Tesseract reads icons and noise as short junk: drop the unsure
            // words with no letter or digit in them. Requiring three letters
            // in a row (as this did) threw away real text read at low
            // confidence: dates like 10-04, numbers like 4.
            // (Explicit ranges: Qt's JS engine rejects \p{L} as an invalid
            // regular expression, and the filter then dropped every unsure
            // word, **Next and **Open among them.)
            if (word.conf < 40 && !/[0-9A-Za-z\u00C0-\u024F\u0400-\u04FF]/.test(text))
                return;
            if (line.chars.length) {
                const prev = line.chars[line.chars.length - 1];
                const right = prev.x + prev.w;
                line.chars.push({
                    c: " ",
                    x: right,
                    w: Math.max(0, word.chars[0].x - right),
                    y: prev.y,
                    b: prev.b,
                    word: -1
                });
            }
            const wi = line.words.length;
            for (const c of word.chars) {
                c.word = wi;
                line.chars.push(c);
            }
            line.words.push(wi);
        };
        const flushLine = () => {
            flushWord();
            word = null;
            if (!line || !line.chars.length)
                return;
            // A gap well past the line's own word spacing and wider than an
            // em is a column: a tab in the copy
            const gaps = line.chars.filter(c => c.c === " ").map(c => c.w).sort((a, b) => a - b);
            if (gaps.length) {
                const em = line.xs || 16;
                const small = gaps.filter(w => w < em);
                const base = small.length ? small[Math.floor((small.length - 1) / 2)] : 0;
                const limit = Math.max(base * 2.5, em * (small.length ? 1 : 1.5));
                for (const c of line.chars)
                    if (c.c === " " && c.w > limit)
                        c.c = "\t";
            }
            const li = ls.length;
            if (li > 0)
                cs.push({
                    c: "\n",
                    x: ls[li - 1].x + ls[li - 1].w,
                    w: 0,
                    word: -1,
                    line: li - 1
                });
            const first = cs.length;
            const wordBase = ws.length;
            let top = 1e9, bottom = -1e9;
            for (const c of line.chars) {
                if (c.word >= 0) {
                    const wi = wordBase + c.word;
                    if (!ws[wi])
                        ws[wi] = {
                            first: cs.length,
                            last: cs.length
                        };
                    ws[wi].last = cs.length;
                    c.word = wi;
                }
                c.line = li;
                top = Math.min(top, c.y);
                bottom = Math.max(bottom, c.b);
                cs.push(c);
            }
            const last = cs.length - 1;
            const h = bottom - top;
            ls.push({
                first,
                last,
                x: cs[first].x,
                w: cs[last].x + cs[last].w - cs[first].x,
                y: top - h * 0.15,
                h: h * 1.3,
                top,
                bottom,
                xs: line.xs || h
            });
            // A blank line in the copy only where the picture has a gap
            if (li > 0 && top - ls[li - 1].bottom > ls[li - 1].xs * 0.9)
                cs[first - 1].c = "\n\n";
            line = null;
        };

        const re = /<(?:div|p|span) class='(ocr_par|ocr_line|ocr_textfloat|ocr_header|ocr_caption|ocrx_word|ocrx_cinfo)'[^>]*?title=['"]([^'"]*)['"][^>]*>([^<]*)/g;
        let m;
        while ((m = re.exec(hocr)) !== null) {
            const cls = m[1];
            if (cls === "ocr_par") {
                flushLine();
                para++;
            } else if (cls === "ocrx_word") {
                flushWord();
                const conf = /x_wconf (\d+)/.exec(m[2]);
                word = {
                    conf: conf ? +conf[1] : 0,
                    chars: []
                };
            } else if (cls === "ocrx_cinfo") {
                const box = /x_bboxes (-?\d+) (-?\d+) (-?\d+) (-?\d+)/.exec(m[2]);
                if (!word || !box)
                    continue;
                word.chars.push({
                    c: decodeEntities(m[3]),
                    x: +box[1],
                    w: Math.max(0, +box[3] - +box[1]),
                    y: +box[2],
                    b: +box[4],
                    word: -1
                });
            } else {
                flushLine();
                const xs = /x_size ([\d.]+)/.exec(m[2]);
                line = {
                    para,
                    xs: xs ? +xs[1] : 0,
                    chars: [],
                    words: []
                };
            }
        }
        flushLine();
        evenLines(cs, ls);
        // Overlapping neighbours share the space between them at the middle,
        // so their highlights tile instead of covering each other
        for (let i = 1; i < ls.length; i++) {
            const a = ls[i - 1], b = ls[i];
            const side = a.x < b.x + b.w && b.x < a.x + a.w;
            if (!side || a.y + a.h <= b.y || b.top < a.bottom)
                continue;
            const mid = (a.bottom + b.top) / 2;
            a.h = mid - a.y;
            b.h = b.y + b.h - mid;
            b.y = mid;
        }
        clearSelection();
        pageW = page ? +page[3] : 0;
        lines = ls;
        words = ws;
        chars = cs;
    }

    // Even bands, as a text view draws a selection. Tesseract's glyph extents
    // change with what a line holds (capitals, a slash, descenders or none):
    // on one screenshot they ran 16 to 22 px while the baselines sat exactly
    // 29 px apart, so boxes built from them came out uneven. Each line now
    // hangs off its baseline (the median bottom of its letters, which the few
    // descenders do not move) at the text's own line pitch, the same height
    // and the same gap for every line. A line far off the common size (a
    // heading, small print) keeps a pitch of its own.
    function evenLines(cs: var, ls: var): void {
        const med = a => {
            const s = a.slice().sort((x, y) => x - y);
            return s.length ? s[Math.floor((s.length - 1) / 2)] : 0;
        };
        for (const l of ls)
            l.base = med(cs.slice(l.first, l.last + 1).filter(c => c.word >= 0).map(c => c.b));
        const medH = med(ls.map(l => l.bottom - l.top));
        const pitches = [];
        for (let i = 1; i < ls.length; i++) {
            const d = ls[i].base - ls[i - 1].base;
            if (d > medH * 0.9 && d < medH * 2.2)
                pitches.push(d);
        }
        const pitch = pitches.length ? med(pitches) : medH * 1.35;
        for (const l of ls) {
            const h = l.bottom - l.top;
            const p = h > medH * 1.6 || h < medH * 0.55 ? h * 1.35 : pitch;
            const gap = p * 0.06;
            l.y = l.base - p * 0.78 + gap;
            l.h = p - gap * 2;
        }
    }

    // ---------------------------------------------------------------- hitting
    // All in page pixels: `p` comes in item coordinates and is divided once

    function toPage(x: real, y: real): point {
        return Qt.point(x / pageScale, y / pageScale);
    }

    function lineAt(p: point): int {
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            if (p.y >= l.y && p.y <= l.y + l.h && p.x >= l.x - l.h * 0.4 && p.x <= l.x + l.w + l.h * 0.4)
                return i;
        }
        return -1;
    }

    // The line a drag at `p` reaches: the one under it, else the nearest,
    // weighted to prefer lines level with the pointer
    function lineNear(p: point): int {
        let li = lineAt(p);
        if (li >= 0)
            return li;
        let best = 1e18;
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            const dy = p.y < l.y ? l.y - p.y : p.y > l.y + l.h ? p.y - l.y - l.h : 0;
            const dx = p.x < l.x ? l.x - p.x : p.x > l.x + l.w ? p.x - l.x - l.w : 0;
            const d = dy * dy * 4 + dx * dx;
            if (d < best) {
                best = d;
                li = i;
            }
        }
        return li;
    }

    // Caret offset nearest `p`: before a character when left of its middle
    function caretAt(p: point): int {
        const li = lineNear(p);
        if (li < 0)
            return -1;
        const l = lines[li];
        for (let i = l.first; i <= l.last; i++)
            if (p.x < chars[i].x + chars[i].w / 2)
                return i;
        return l.last + 1;
    }

    function charAt(p: point): int {
        const li = lineNear(p);
        if (li < 0)
            return -1;
        const l = lines[li];
        for (let i = l.first; i <= l.last; i++)
            if (p.x < chars[i].x + chars[i].w)
                return i;
        return l.last;
    }

    function unitRange(ci: int, unit: int): var {
        const c = chars[ci];
        if (!c)
            return [Math.max(0, ci), Math.max(0, ci)];
        if (unit >= 3) {
            const l = lines[c.line];
            return [l.first, l.last + 1];
        }
        if (unit === 2 && c.word >= 0)
            return [words[c.word].first, words[c.word].last + 1];
        return [ci, ci + 1];
    }

    function begin(p: point, clicks: int, extend: bool): void {
        selUnit = Math.min(3, clicks);
        if (extend && selA >= 0) {
            anchorLo = anchorHi = selA;
            drag(p);
            return;
        }
        if (selUnit === 1) {
            anchorLo = anchorHi = caretAt(p);
        } else {
            const r = unitRange(charAt(p), selUnit);
            anchorLo = r[0];
            anchorHi = r[1];
        }
        selA = anchorLo;
        selB = anchorHi;
    }

    function drag(p: point): void {
        if (selUnit === 1) {
            selA = anchorLo;
            selB = caretAt(p);
            return;
        }
        const r = unitRange(charAt(p), selUnit);
        selA = Math.min(anchorLo, r[0]);
        selB = Math.max(anchorHi, r[1]);
    }

    // ---------------------------------------------------------------- parts

    Timer {
        id: readLater

        interval: 300
        onTriggered: root.read()
    }

    Process {
        id: ocr

        property string path

        // At twice the size, and light-on-dark turned dark-on-light, which is
        // what tesseract is built for: on a dark terminal shot it read 10-03
        // as 10-83 and 10-04 as 18-84 at 1x, all three dates right at 2x,
        // and faster (431 against 478 ms). The page it reports is then 2x;
        // pageScale takes that as it is. Plain tesseract without ImageMagick.
        command: ["sh", "-c", "if command -v magick >/dev/null; then neg=$(magick \"$1\" -alpha off -colorspace Gray -format '%[fx:mean<0.5?1:0]' info:); magick \"$1\" -alpha off -resize 200% $([ \"$neg\" = 1 ] && echo -negate) png:- | tesseract stdin - -c hocr_char_boxes=1 hocr; else tesseract \"$1\" - -c hocr_char_boxes=1 hocr; fi", "ocr", path]
        stdout: StdioCollector {
            onStreamFinished: {
                // A newer image arrived while this one was being read
                if (ocr.path !== root.source)
                    return;
                root.readFor = ocr.path;
                root.parse(text);
            }
        }
    }

    // The highlight: drawn opaque and faded as one layer, so where two line
    // rects meet the tint stays even instead of doubling up
    Item {
        anchors.fill: parent
        opacity: 0.38
        layer.enabled: root.hasSelection
        visible: root.hasSelection

        Repeater {
            model: root.selRects

            Rectangle {
                required property rect modelData

                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                radius: Math.min(height / 5, 3)
                color: Colours.palette.m3primary
            }
        }
    }

    // Takes a press only on text; anywhere else it declines and the press
    // goes on to the pan and the double-click reset underneath
    MouseArea {
        id: area

        property int clicks: 1
        property real lastPress
        property point lastAt

        readonly property bool overText: root.lines.length > 0 && containsMouse && root.lineAt(root.toPage(mouseX, mouseY)) >= 0

        anchors.fill: parent
        enabled: root.active
        hoverEnabled: true
        preventStealing: true
        cursorShape: overText || root.selecting ? Qt.IBeamCursor : root.zoomed ? Qt.OpenHandCursor : Qt.ArrowCursor

        onPressed: mouse => {
            const p = root.toPage(mouse.x, mouse.y);
            if (mouse.button !== Qt.LeftButton || root.lineAt(p) < 0) {
                root.clearSelection();
                mouse.accepted = false;
                return;
            }
            // Clicks in quick succession on the same spot count up: a word,
            // then a line. MouseArea's own double-click would not see a third.
            const now = Date.now();
            const near = Math.abs(mouse.x - lastAt.x) < 6 && Math.abs(mouse.y - lastAt.y) < 6;
            clicks = now - lastPress < 400 && near ? clicks + 1 : 1;
            lastPress = now;
            lastAt = Qt.point(mouse.x, mouse.y);
            root.selecting = true;
            root.begin(p, clicks, mouse.modifiers & Qt.ShiftModifier);
        }
        onPositionChanged: mouse => {
            if (root.selecting)
                root.drag(root.toPage(mouse.x, mouse.y));
        }
        onReleased: root.selecting = false
        onCanceled: root.selecting = false
    }
}
