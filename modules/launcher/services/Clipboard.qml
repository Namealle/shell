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
            // Images decode to a file cache of their own; binaries are never
            // read as text.
            if (!e || e.isImage || e.binMatch)
                continue;
            const id = e.entryId;
            if (!id || seen[id] || root.decodedText[id] !== undefined)
                continue;
            seen[id] = true;
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

        // Non-empty when the entry is a lone colour → delegate paints a swatch.
        readonly property string colour: entry.binMatch ? "" : root.colourOf(entry.preview)
        readonly property string icon: entry.binMatch ? root.iconForBinary(entry.binMatch[1]) : root.iconFor(entry.preview)
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
