pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

// Clipboard-history picker backing the `;` launcher mode.
//
// Entries are persistent QtObjects (Variants) returned RANK-ORDERED by the C++
// Search (fuzzyIndices), so search + ListView animations match the apps picker
// without the JS Searcher freezing on 750 long (-preview-width 999) entries.
// Each entry gets a content-aware Material icon via iconFor() (regex, security-
// oriented), image entries show a decoded thumbnail (in ClipItem), and the Del
// key removes an entry via cliphist delete.
Singleton {
    id: root

    // Raw `cliphist list` lines, newest first.
    property var rawEntries: []
    readonly property list<QtObject> entries: variants.instances
    readonly property var previews: root.rawEntries.map(line => {
        const tab = line.indexOf("\t");
        return tab >= 0 ? line.slice(tab + 1) : line;
    })

    function reload(): void {
        listProc.running = true;
    }

    function transformSearch(text: string): string {
        return text.slice(GlobalConfig.launcher.clipboardPrefix.length);
    }

    function query(text: string): var {
        const q = transformSearch(text).trim();
        return Search.fuzzyIndices(root.previews, q, 200).map(i => root.entries[i]);
    }

    function activate(line: string): void {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "clip", line]);
    }

    function deleteEntry(line: string): void {
        delProc.line = line;
        delProc.running = true;
    }

    // Content-aware icon. First match wins; ordered security-specific → tools →
    // data/code → everyday → default. Image entries are handled separately.
    function iconFor(text: string): string {
        const t = text.trim();

        // --- security / identifiers / network ---
        if (/\bCVE-\d{4}-\d{3,}\b/i.test(t))
            return "coronavirus";
        if (/^eyJ[\w-]+\.[\w-]+\.[\w-]+$/.test(t))
            return "token"; // JWT
        if (/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/.test(t) || /\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}\b/.test(t) || /\bsk-[A-Za-z0-9]{20,}\b/.test(t) || /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/.test(t))
            return "key"; // API keys / tokens
        if (/^[a-f0-9]{64}$/i.test(t) || /^[a-f0-9]{40}$/i.test(t) || /^[a-f0-9]{32}$/i.test(t))
            return "fingerprint"; // SHA256 / SHA1 / MD5
        if (/\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b/i.test(t))
            return "settings_ethernet"; // MAC
        if (/\b(?:\d{1,3}\.){3}\d{1,3}\b/.test(t))
            return "lan"; // IPv4
        if (/\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{0,4}\b/i.test(t))
            return "lan"; // IPv6-ish
        if (/^(?:bc1|[13])[a-hj-np-z0-9]{25,39}$/.test(t) || /^0x[a-f0-9]{40}$/i.test(t))
            return "currency_bitcoin"; // crypto address

        // --- URLs / mail / hosts ---
        if (/https?:\/\/\S+/i.test(t))
            return "link";
        if (/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(t))
            return "alternate_email"; // email
        if (/^(?:[a-z0-9-]+\.)+[a-z]{2,}$/i.test(t))
            return "dns"; // bare hostname/domain

        // --- security tools / commands ---
        if (/^(?:sudo\s+)?(?:nmap|masscan|rustscan|amass|subfinder)\b/i.test(t))
            return "radar";
        if (/^(?:sudo\s+)?(?:tshark|tcpdump|wireshark|ngrep|termshark)\b/i.test(t))
            return "network_check";
        if (/^(?:sudo\s+)?(?:hydra|john|hashcat|gobuster|feroxbuster|ffuf|sqlmap|msfconsole|msfvenom|nikto|dirb|wpscan|enum4linux|netexec|crackmapexec|impacket|responder|bloodhound|evil-winrm|smbclient|smbmap)\b/i.test(t))
            return "security";
        if (/^(?:sudo\s+)?(?:ssh|scp|sftp|nc|ncat|socat)\b/i.test(t))
            return "terminal";
        if (/^(?:sudo\s+)?(?:curl|wget|http|httpie)\b/i.test(t))
            return "http";
        if (/^git\s+/i.test(t))
            return "commit";
        if (/^(?:sudo\s+)?(?:docker|kubectl|podman)\b/i.test(t))
            return "deployed_code";
        if (/^(?:sudo|bash|sh|zsh|fish|apt|pacman|yay|dnf|systemctl|chmod|chown|mkdir|rm|cp|mv|grep|awk|sed|export|source)\b/.test(t))
            return "terminal";

        // --- data / code ---
        if (/\b(?:SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER)\b[\s\S]*\b(?:FROM|INTO|TABLE|WHERE|VALUES)\b/i.test(t))
            return "database";
        if (/^\s*[{[][\s\S]*[}\]]\s*$/.test(t))
            return "data_object"; // JSON / array
        if (/^#[0-9a-f]{3,8}$/i.test(t) || /\brgba?\([\d\s,.%]+\)/i.test(t))
            return "palette"; // colour
        if (/^~?(?:\/[\w.@ -]+)+\/?$/.test(t) || /^[A-Za-z]:\\/.test(t))
            return "folder"; // path
        if (/[{}();]|=>|::|\bfunction\b|\bconst\b|\bimport\b|<\/?\w+>/.test(t) && t.length < 400)
            return "code";

        // --- everyday ---
        if (/^\+?[\d][\d\s().-]{6,}$/.test(t))
            return "call"; // phone
        if (/^-?\d+(?:[.,]\d+)?$/.test(t))
            return "tag"; // number
        if (/\n/.test(t))
            return "notes"; // multi-line note
        if (/^\S+$/.test(t))
            return "text_fields"; // single word/token

        return "content_paste";
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

        readonly property string icon: entry.binMatch ? "image" : root.iconFor(entry.preview)
        readonly property string name: entry.binMatch ? "Image" : entry.preview.replace(/\s+/g, " ").trim()
        readonly property string desc: {
            if (entry.binMatch)
                return entry.binMatch[1];
            const n = entry.name.length;
            return `${n} ${n === 1 ? "character" : "characters"}`;
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

        command: ["cliphist", "-preview-width", "999", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.rawEntries = text.split("\n").filter(l => l.length > 0)
        }
    }

    Process {
        id: delProc

        property string line: ""

        command: ["sh", "-c", "printf '%s' \"$1\" | cliphist delete", "del", delProc.line]
        onExited: root.reload()
    }

    Component.onCompleted: root.reload()
}
