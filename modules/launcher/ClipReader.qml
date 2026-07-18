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
    readonly property int cols: Math.max(1, Math.floor(root.textW / root.charWidth))
    readonly property string gutterText: {
        let s = "";
        for (let i = 0; i < root.lines.length; i++) {
            if (i > 0)
                s += "\n";
            s += (i + 1);
            const extra = Math.ceil(root.lines[i].length / root.cols) - 1;
            for (let k = 0; k < extra; k++)
                s += "\n";
        }
        return s;
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
        viewport.contentY = Math.max(0, Math.min(r.y - viewport.height / 3, Math.max(0, viewport.contentHeight - viewport.height)));
    }

    onEntryChanged: root.stage()
    onFindTermChanged: root.applyFind()
    Component.onCompleted: root.refresh()

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
                // WrapAnywhere so a wrapped row is exactly `cols` chars -- keeps
                // the gutter's blank-line padding aligned with the visual rows.
                wrapMode: TextEdit.WrapAnywhere
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

            visible: root.isImage
            width: root.contentW
            height: status === Image.Ready && implicitWidth > 0 ? Math.min(root.maxHeight, width * implicitHeight / implicitWidth) : 0
            source: root.imgSrc
            fillMode: Image.PreserveAspectFit
            cache: false
            asynchronous: true
            sourceSize.width: root.maxWidth
        }
    }
}
