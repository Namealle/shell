pragma ComponentBehavior: Bound

import QtQuick
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
    readonly property bool isText: !!root.entry && !root.isBinary
    readonly property string imgCache: root.isImage && root.entry ? `/tmp/caelestia-clip-preview-${root.entry.entryId}.png` : ""

    readonly property int maxWidth: 1000
    readonly property int maxHeight: 640
    readonly property int minWidth: Tokens.sizes.launcher.itemWidth

    readonly property string decoded: cache.text
    readonly property var lines: root.decoded.length > 0 ? root.decoded.split("\n") : [""]
    readonly property int lineCount: root.lines.length
    readonly property int longestLine: {
        let m = 0;
        for (const l of root.lines)
            if (l.length > m)
                m = l.length;
        return m;
    }

    // All widths derive from CONTENT (never from the animated laid-out width),
    // so the text lays out once per entry -- not on every frame of the morph.
    readonly property real charWidth: fm.advanceWidth("0")
    readonly property real gutterWidth: fm.advanceWidth(String(Math.max(1, root.lineCount)))
    readonly property real contentW: root.implicitWidth - Tokens.padding.large * 2
    readonly property real textW: root.contentW - root.gutterWidth - Tokens.spacing.medium
    // Rebuilt from the ACTUAL laid-out text (positionToRectangle), not from a
    // chars-per-row estimate: with word wrapping the visual rows per logical
    // line depend on where the words break, so the gutter asks the layout where
    // each line landed and pads blank rows to match.
    property string gutterText: ""

    function rebuildGutter(): void {
        if (!root.isText) {
            root.gutterText = "";
            return;
        }
        const lh = bodyText.positionToRectangle(0).height;
        if (lh <= 0)
            return;
        const out = [];
        let off = 0;
        for (let i = 0; i < root.lines.length; i++) {
            const row = Math.round(bodyText.positionToRectangle(off).y / lh);
            while (out.length < row)
                out.push("");
            out.push(String(i + 1));
            off += root.lines[i].length + 1;
        }
        root.gutterText = out.join("\n");
    }

    property string imgSrc: ""

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
            cache.text = Clipboard.decodedText[e.entryId];
            Qt.callLater(root.applyFind);
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
        decoder.running = false;
        decoder.entryId = id;
        decoder.line = raw;
        decoder.running = true;
    }

    // Keyboard scrolling: PgUp/PgDn a viewport at a time, Home/End to the
    // edges -- always animated, never a one-frame jump. Repeated presses
    // accumulate against the in-flight target, not the current frame, so
    // holding the key pages steadily.
    function smoothScrollTo(y: real): void {
        const to = Math.max(0, Math.min(y, Math.max(0, viewport.contentHeight - viewport.height)));
        const from = viewport.contentY;
        scrollAnim.stop();
        if (to === from)
            return;
        scrollAnim.from = from;
        scrollAnim.to = to;
        scrollAnim.start();
    }

    function scrollPage(dir: int): void {
        const base = scrollAnim.running ? scrollAnim.to : viewport.contentY;
        smoothScrollTo(base + dir * viewport.height * 0.9);
    }

    function scrollEdge(dir: int): void {
        smoothScrollTo(dir < 0 ? 0 : viewport.contentHeight);
    }

    Anim {
        id: scrollAnim

        // Decel, not the spatial default: scrolling must settle exactly on its
        // stop point (overshoot makes the text bounce), and it should ease
        // into the stop rather than end abruptly (standard felt too linear).
        type: Anim.Standard
        easing: Tokens.anim.standardDecel

        target: viewport
        property: "contentY"
    }

    // Select the first occurrence of the find term and scroll it into view.
    function applyFind(): void {
        const t = root.findTerm.trim().toLowerCase();
        if (!t || !root.isText || !root.decoded.length) {
            bodyText.deselect();
            return;
        }
        const idx = root.decoded.toLowerCase().indexOf(t);
        if (idx < 0) {
            bodyText.deselect();
            return;
        }
        bodyText.select(idx, idx + t.length);
        const r = bodyText.positionToRectangle(idx);
        smoothScrollTo(r.y - viewport.height / 3);
    }

    onEntryChanged: root.stage()
    onFindTermChanged: root.applyFind()
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
    }

    Timer {
        id: debounce

        interval: 140
        onTriggered: root.refresh()
    }

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
                if (root.entry?.entryId === decoder.entryId) {
                    cache.text = t;
                    Qt.callLater(root.applyFind);
                }
            }
        }
    }

    // Ensures the thumbnail exists on disk (same cache file ClipItem writes),
    // then points the Image at it -- Image won't retry a source that didn't
    // exist when first set.
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
        contentHeight: root.isText ? bodyRow.implicitHeight : image.height

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: viewport
        }

        // Text entries: line-number gutter + selectable, wrapping monospace text.
        Row {
            id: bodyRow

            visible: root.isText
            width: root.contentW
            spacing: Tokens.spacing.medium

            StyledText {
                id: gutter

                width: root.gutterWidth
                text: root.gutterText
                font: Tokens.font.mono.small
                color: Colours.palette.m3outlineVariant
                horizontalAlignment: Text.AlignRight
            }

            TextEdit {
                id: bodyText

                width: root.textW
                text: root.decoded
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                // Word boundaries; only runs longer than a row split mid-word.
                // The gutter follows the real layout (rebuildGutter), so it no
                // longer needs fixed-chars-per-row wrapping.
                wrapMode: TextEdit.Wrap
                onTextChanged: Qt.callLater(root.rebuildGutter)
                onWidthChanged: Qt.callLater(root.rebuildGutter)
                onContentHeightChanged: Qt.callLater(root.rebuildGutter)
                color: Colours.palette.m3onSurface
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
            // exactly on this rect, then hands off.
            visible: root.isImage && root.morphT >= 1
            width: root.contentW
            height: status === Image.Ready && implicitWidth > 0 ? Math.min(root.maxHeight, width * implicitHeight / implicitWidth) : 0
            source: root.imgSrc
            fillMode: Image.PreserveAspectFit
            cache: false
            asynchronous: true
            sourceSize.width: root.maxWidth
        }
    }

    // -- image morph: the row's thumbnail becomes the reader image --
    // A second shared element for image entries, riding the same slide. At t=0
    // it exactly covers the header's material icon slot -- which is pixel-
    // identical to the row's thumbnail slot, so the icon really is "under" the
    // thumbnail -- and at t=1 it exactly covers the rect the body image paints.
    // Both endpoints are live bindings (the icon slot follows slideX/slideY),
    // so enter, exit and mid-flight reversals all stay glued.
    property real morphT: 0

    Behavior on morphT {
        Anim {}
    }

    StyledClippingRect {
        id: morphImg

        readonly property bool ready: mImg.status === Image.Ready && mImg.implicitWidth > 0 && mImg.implicitHeight > 0
        // The rect the body's aspect-FIT image actually paints inside
        // contentW x maxHeight. Only horizontal centring can occur: a capped
        // height caps the box to the same value, so there is no letterbox.
        readonly property real fitW: ready ? Math.min(root.contentW, root.maxHeight * mImg.implicitWidth / mImg.implicitHeight) : root.contentW
        readonly property real fitH: ready ? fitW * mImg.implicitHeight / mImg.implicitWidth : root.contentW
        readonly property real srcS: headerIcon.implicitHeight
        readonly property real srcX: Tokens.padding.large + root.slideX
        readonly property real srcY: Tokens.padding.large + root.slideY + (header.implicitHeight - srcS) / 2
        readonly property real dstX: Tokens.padding.large + (root.contentW - fitW) / 2
        readonly property real dstY: Tokens.padding.large + root.slideY + header.implicitHeight + Tokens.spacing.small - viewport.contentY

        visible: root.isImage && root.morphT < 1
        x: srcX + (dstX - srcX) * root.morphT
        y: srcY + (dstY - srcY) * root.morphT
        width: srcS + (fitW - srcS) * root.morphT
        height: srcS + (fitH - srcS) * root.morphT
        radius: Tokens.rounding.small * (1 - root.morphT)
        color: Colours.palette.m3surfaceContainerHigh

        Image {
            id: mImg

            anchors.fill: parent
            source: root.imgSrc
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: true
            sourceSize.width: root.maxWidth
        }
    }
}
