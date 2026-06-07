import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var list
    required property string clipId
    required property string content

    // Grow to fit content (up to 3 wrapped lines + char count),
    // but never shrink below the standard launcher row height.
    implicitHeight: Math.max(
        Tokens.sizes.launcher.itemHeight,
        textColumn.implicitHeight + Tokens.padding.smaller * 2
    )

    anchors.left: parent?.left
    anchors.right: parent?.right

    function trigger() {
        root.list.visibilities.launcher = false;
        // Decode the selected clip and pipe it to wl-copy
        Quickshell.execDetached(["sh", "-c", `echo -n '${root.clipId}' | cliphist decode | wl-copy`]);
    }

    StateLayer {
        radius: Tokens.rounding.normal
        onClicked: root.trigger()
    }

    function getIconForContent(content) {
        const t = content.trim();
        const len = t.length;
        const firstLine = t.split('\n')[0].trim();
        const isMultiLine = t.includes('\n');
        
        // 1. Binary & Media
        if (t.includes("[[ binary data")) return "image";
        
        // 2. Specific URLs (Video & Meetings)
        if (/^https?:\/\/(www\.)?(youtube\.com|youtu\.be|twitch\.tv|vimeo\.com|spotify\.com|soundcloud\.com|netflix\.com|disneyplus\.com|hbomax\.com|hulu\.com|primevideo\.com|peacocktv\.com)/.test(firstLine)) return "play_circle";
        if (/^https?:\/\/(zoom\.us\/j\/|meet\.google\.com|teams\.microsoft\.com)/.test(firstLine)) return "video_call";
        
        // 3. Generic Networking & Web
        if (/^https?:\/\//.test(firstLine) || /^www\./.test(firstLine)) return "link";
        if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(t)) return "mail";
        if (/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/\d{1,2}$/.test(t)) return "hub"; // CIDR
        if (/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}(:\d{1,5})?$/.test(t)) return "router"; // IP Addresses
        if (/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/.test(t)) return "settings_ethernet"; // MAC Address
        if (/^:\d{2,5}$/.test(t)) return "settings_ethernet"; // Standalone Port
        
        // 4. Security, Crypto, Hashes, Tokens
        if (/^[0-9a-f]{7,12}$/i.test(t)) return "history"; // Short Git Hash
        if (/^T\d{4}(\.\d{3})?$/.test(t)) return "policy"; // MITRE ATT&CK
        if (/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(t)) return "fingerprint"; // UUID
        if (/^S-1-[0-9-]+$/.test(t)) return "fingerprint"; // Windows SID
        if (/^CVE-\d{4}-\d{4,7}$/i.test(t)) return "bug_report"; // CVE
        if (/^[a-f0-9]{32}:[a-f0-9]{32}$/i.test(t)) return "shield"; // NTLM Hash pair
        if (/^[0-9a-fA-F]{64}$/.test(t) || /[0-9a-fA-F]{64}/.test(firstLine)) return "shield"; // SHA256 (anchored or inline for Kibana)
        if (/^[0-9a-fA-F]{40}$/.test(t)) return "tag"; // SHA1
        if (/^[0-9a-fA-F]{32}$/.test(t)) return "tag"; // MD5
        if (/^0x[a-fA-F0-9]{40}$/.test(t) || /^(bc1|[13])[a-zA-HJ-NP-Z0-9]{25,39}$/.test(t)) return "account_balance_wallet"; // Crypto Wallets
        if (/^-----BEGIN .+ (KEY|CERTIFICATE)-----/.test(firstLine)) return "lock"; // SSH/PGP Keys
        if (/^(sekurlsa|lsadump|kerberos|token|vault|privilege|crypto|dpapi|ts|misc|net|process|service|wdigest)::/i.test(firstLine)) return "security"; // Mimikatz
        if (/^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}(-[A-Z0-9]{5})?$/.test(t)) return "vpn_key"; // Serial Keys
        if (/^\w+\/[\w\-\.]+@[\w\-\.]+$/.test(t)) return "vpn_key"; // Kerberos SPN
        if (/^(eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)$/.test(t)) return "key"; // JWT
        if (/^[A-Z]{2}\d{2}[A-Z0-9]{4,30}$/.test(t) && len >= 15 && len <= 34) return "account_balance"; // IBAN
        if (len > 30 && len < 200 && !/\s/.test(t) && /^[a-zA-Z0-9_\-]+$/.test(t) && /[A-Z]/.test(t) && /[a-z]/.test(t) && /[0-9]/.test(t) && (t.match(/[0-9]/g) || []).length >= 4) return "key"; // Generic Tokens
        if (len > 20 && /^[A-Za-z0-9+/]+={0,2}$/.test(t) && !/\s/.test(t)) return "enhanced_encryption"; // Pure Base64
        if (/(-enc\b|-EncodedCommand)\s+[A-Za-z0-9+/]{20,}/i.test(t)) return "enhanced_encryption"; // PS Encoded Command
        if (/^[0-9a-f]{4,16}:?\s+([0-9a-f]{2}\s+){4,}/i.test(firstLine)) return "memory"; // Hex dump
        
        // 5. Splunk / Elastic / Logs / Errors & Data Forms
        if (/Error:|Exception:|Traceback \(most recent|at line |undefined is not|cannot read properties/i.test(firstLine)) return "error"; // Stack traces
        if (/^\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}.*?(INFO|WARN|ERROR|DEBUG|FATAL|CRITICAL)/i.test(firstLine)) return "receipt_long"; // Log entries
        if (/(PORT\s+STATE\s+SERVICE)|(open\|filtered)/.test(t)) return "search"; // Nmap/Scan
        if (/^(tcp|udp|ip|http|dns|arp|icmp|ssl|tls|eth)\.(port|addr|src|dst|request|response|flags|stream)\s*(==|!=|>=|<=|contains|matches)/.test(firstLine)) return "manage_search"; // Wireshark/tcpdump
        if (/\w+\.\w+:[^\s]+ (AND|OR) \w+\.\w+:[^\s]+/.test(t)) return "database"; // KQL
        if (/^(index=|sourcetype=|\| stats|\| rex|\| table|\| search|\| eval|\| bucket|\| eventcount)/.test(firstLine)) return "database"; // Splunk
        if (/^(SELECT|UPDATE|DELETE|INSERT|CREATE) /i.test(firstLine)) return "table_rows";
        if (/^\s*[\{\[]\s*["']/m.test(t) && t.includes('":')) return "data_object"; // JSON Blobs
        const yamlKeyCount = (t.match(/^[\w-]+:\s+\S/mg) || []).length;
        if (isMultiLine && (/^---\s*$/m.test(t) || yamlKeyCount >= 3)) return "data_object"; // YAML
        if (/^\[[\w-]+\]\n[\w-]+\s*=/m.test(t)) return "settings"; // TOML/INI
        if (/^([^,\t\n]+[,|\t]){2,}[^,\t\n]+$/m.test(firstLine) && isMultiLine) return "grid_on"; // CSV/TSV
        if (/^diff --git|^--- |^\+\+\+ |^@@ /.test(firstLine)) return "difference"; // Diff/Patch
        if (/^rule\s+\w+\s*(\{|:)/.test(firstLine)) return "policy"; // YARA rules
        if (isMultiLine && /^title:\s+\S/.test(firstLine) && /^\s*detection:/m.test(t)) return "policy"; // Sigma rules
        if (/^(port|country|org|hostname|os|net|city|product|version|asn|ssl\.cert):\S+/.test(firstLine)) return "travel_explore"; // Shodan/Censys
        if (/^(TCP|UDP)\s+[\d.]+:\d+\s+[\d.*]+:[\d*]*\s*(ESTABLISHED|LISTENING|TIME_WAIT|CLOSE_WAIT|SYN_SENT|FIN_WAIT)/i.test(firstLine)) return "cable"; // Netstat
        
        // 6. Programming, Shell, Git & IT
        if (/^v?\d+\.\d+\.\d+(-[a-zA-Z0-9\.]+)?$/.test(t)) return "new_releases"; // Semver
        if (/git commit|create mode \d{6}|commit [0-9a-f]{7,40}/.test(firstLine)) return "history"; // Git logs (moved BEFORE terminal)
        if (/^hyprctl\s+\w/.test(firstLine)) return "terminal"; // Hyprland config/commands
        if (/^(bind|binde|bindr|bindt|bindrt|bindm)\s*=/.test(firstLine)) return "settings";
        if (/^(exec-once|exec|monitor|workspace|windowrule|layerrule)\s*=/.test(firstLine)) return "settings";
        if (/^(Get|Set|Invoke|New|Remove|Write|ConvertTo|ConvertFrom|Import|Export|Start|Stop|Test|Add|Clear|Enable|Disable|Install|Uninstall|Register|Unregister|Out|Select|Where|Format|Sort|Measure)-\w+/.test(firstLine)) return "terminal"; // PowerShell cmdlets
        if (/^(net\s+(user|group|localgroup|view|share|use|start|stop|accounts)|ipconfig|whoami\s*\/|tasklist|netstat\s+-|arp\s+-[an]|nslookup\s+\S|tracert\s+\S|route\s+(print|add|delete)|sc\s+(query|start|stop|config)|reg\s+(query|add|delete|export)|wmic\s+\w|cmdkey\s+|icacls\s+|cacls\s+)/i.test(firstLine)) return "terminal"; // Windows Recon
        if (/^(\$ |sudo |cd |pacman |yay |paru |systemctl |npm |yarn |cargo |docker |git |cmake |ninja |curl |wget |pip |gem |apt |dnf |brew )/.test(firstLine)) return "terminal"; // Commands
        if (/^(exploit|auxiliary|post|payload|encoder|nop|evasion)\/[\w\/\-]+$/.test(t)) return "dangerous"; // Metasploit modules
        if (/^(CN|DC|OU|O|C)=[^,]+(,(CN|DC|OU|O|C)=[^,]+)+$/i.test(t)) return "account_tree"; // LDAP DN
        if (/^(EventID?|EventCode)\s*[=:]\s*\d{3,5}$/i.test(t)) return "receipt_long"; // Windows Event ID
        if (/^[A-Z0-9][A-Z0-9\-]{1,14}\$$/.test(t)) return "computer"; // Windows Machine Accounts
        if (/^(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_USERS|HKLM|HKCU|HKU|HKCR)[\/\\]/i.test(firstLine)) return "settings"; // Windows Registry
        if (/^[A-Za-z]:\\|^%[A-Z_]+%\\/i.test(firstLine)) return "folder"; // Windows File Paths
        if (/^(\/home\/|\/usr\/|\/etc\/|\/var\/|\/tmp\/|~\/|\/opt\/|\.config\/)/.test(firstLine)) return "folder"; // Linux File Paths
        if (/^[\w\- ]+\.(py|js|ts|cpp|h|rs|go)$/i.test(t)) return "code"; // Code Files
        if (/^[\w\- ]+\.(conf|yaml|yml|toml|ini)$/i.test(t)) return "settings"; // Config Files
        if (/^[\w\- ]+\.sh$/i.test(t)) return "terminal"; // Shell Scripts
        if (/^[\w\- ]+\.(txt|md|log|json|csv)$/i.test(t)) return "description"; // Text/Data Files
        if (/^\$[A-Z_][A-Z0-9_]*$|^\$\{[A-Z_][A-Z0-9_]+\}$|^%[A-Z_][A-Z0-9_]+%$/.test(t)) return "tune"; // Environment Variables
        if (/<[A-Z][A-Za-z0-9]+ \/>|interface [A-Z]|type [A-Z] =/.test(firstLine)) return "code"; // TS/JSX
        if (/function |class |import |export |const |let |=>|#include|def |if \(|for \(|while \(|<\/|{\n/.test(t) || t.includes("::")) return "code"; // Generic Code
        if (/^\/.*\/[gimsuy]*$/.test(t)) return "search"; // Regex patterns
        if (/^#+ |^\*\*|`{1,3}|-\s\[[ x]\]|\[.*\]\(.*\)/m.test(t)) return "markdown"; // Markdown
        if (/^(Ctrl|Alt|Shift|Super|Meta|Win|Cmd|Option)(\+[A-Za-z0-9]|\+F\d{1,2}|\+[A-Z][a-z]+)+$/i.test(t)) return "keyboard"; // Keybinds
        
        // 7. Everyday Consumer Data
        if (/^\+?(\d{1,3})?[-. (]*\d{3}[-. )]*\d{3}[-. ]*\d{4}$/.test(t)) return "call"; // Phone
        if (/^(\$|€|£|¥|₹)\s*\d+(?:[.,]\d+)?$/.test(t)) return "payments"; // Money
        if (/^(?:4[0-9]{12}(?:[0-9]{3})?|[25][1-7][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})$/.test(t.replace(/[\s\-]/g, ''))) return "credit_card"; 
        if (/^1Z[0-9A-Z]{16}$|^\d{20,22}$|^\d{12,14}$/.test(t)) return "local_shipping"; // Tracking
        if (/^\d{5}(-\d{4})?$/.test(t)) return "markunread_mailbox"; // US ZIP Code
        if (/^-?\d{1,3}\.\d{4,},\s*-?\d{1,3}\.\d{4,}$/.test(t)) return "location_on"; // GPS
        if (/^\d+\s+[A-Za-z][\w\s]+\b(Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Drive|Dr|Lane|Ln|Way|Court|Ct|Place|Pl|Highway|Hwy)\b/i.test(firstLine)) return "home"; // Street Addresses
        
        // 8. Formatting & Specific Data Types
        if (/^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/.test(t) || /^(rgb|hsl|oklch|rgba|hwb|color)\(/.test(t) || /^--[a-z0-9-]+$/.test(t)) return "palette"; // Colors & CSS vars
        if (/^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD)\s+\/[^\s]*/.test(firstLine)) return "cloud"; // HTTP requests
        if (/^\/api\/|\/v\d+\//.test(firstLine)) return "cloud"; // API Paths
        if (/^\d+(\.\d+)?%$/.test(t)) return "percent"; // Percentages
        if (/^(\*|[\d,\-\/]+)\s+(\*|[\d,\-\/]+)\s+(\*|[\d,\-\/]+)\s+(\*|[\d,\-\/]+)\s+(\*|[\d,\-\/]+)$/.test(t)) return "schedule"; // Cron
        if (/^[a-z]{2}(-[A-Z]{2})?$/.test(t) && len <= 5) return "translate"; // Locale codes
        if (/^(true|false|null|undefined|None|nil|NaN)$/.test(t)) return "toggle_on"; // Booleans/Nulls
        if (/^[1-5]\d{2}$/.test(t) && len === 3) return "http"; // HTTP Status Codes
        if (/^["'].*["']$/.test(t) && !isMultiLine) return "format_quote"; // Quoted strings
        if (/^\w+\/[\w\-\+\.]+$/.test(t)) return "description"; // MIME types
        if (/^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$/.test(t) && !t.includes(" ")) return "public"; // Domains
        if (/^\p{Emoji}+$/u.test(t)) return "mood"; // Emojis
        if (/^-?\d+(\.\d+)?°[CF]$/.test(t) || /^-?\d+(\.\d+)?\s+degrees?\s+(celsius|fahrenheit)$/i.test(t)) return "thermostat"; // Temperature
        if (/^[\d.]+\s*(B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)\b$/i.test(t)) return "storage"; // File/Data Sizes
        if (/^[\d.]+\s*(km|m|cm|mm|mi|ft|in|kg|lb|oz|g|L|ml|mL|W|kW|V|A|Hz|kHz|MHz|GHz|rpm|psi|bar)\b$/i.test(t)) return "straighten"; // Measurement Values
        if (/^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$/.test(t) && (len === 8 || len === 11)) return "account_balance"; // SWIFT/BIC
        if (/^978[-\s]?\d{1,5}[-\s]?\d{1,7}[-\s]?\d{1,6}[-\s]?\d$/.test(t) || /^97[89]\d{10}$/.test(t)) return "menu_book"; // ISBN
        if (/^[A-HJ-NPR-Z0-9]{17}$/.test(t)) return "directions_car"; // Vehicle VIN
        if (/^WIFI:(T:(WPA2?|WEP|nopass);)?(S:[^;]+;)/.test(t)) return "wifi"; // WiFi QR
        if (/^BEGIN:(VCALENDAR|VEVENT|VTODO|VCARD)/.test(firstLine)) return "event"; // iCal / vCard
        
        // Numeric Dates & Datetimes
        if (/^\d{2,4}[-/\.]\d{1,2}[-/\.]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[aA][mM]|[pP][mM])?)?$/.test(t)) return "calendar_today";
        if (/^(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*,\s*)?(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?(?:,\s*\d{4})?(?:\s+\d{1,2}:\d{2}(?:\s*[aA][mM]|[pP][mM])?)?$/i.test(t)) return "calendar_today";
        if (/^\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)(?:\s+\d{4})?(?:\s+\d{1,2}:\d{2}(?:\s*[aA][mM]|[pP][mM])?)?$/i.test(t)) return "calendar_today";
        if (/^\d{1,2}:\d{2}\s?(AM|PM|am|pm)?$/.test(t)) return "schedule"; // Times
        
        if (/^@[a-zA-Z0-9_]+$/.test(t)) return "alternate_email"; // Social Handles
        if (/^#[a-zA-Z0-9_]+$/.test(t) && !/([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})/.test(t)) return "tag"; // Hashtags
        if (/^[\d\s\+\-\*\/\=\.\(\)]+$/.test(t) && /\d/.test(t) && len < 50) return "calculate"; // Math
        
        // 9. Symbols, Emojis, Short codes
        if (/^[A-Z]{2}\d{1,4}$/.test(t) && len >= 3 && len <= 6) return "flight"; // Flight Numbers
        if (/^\d{6}$|^\d{8}$/.test(t)) return "pin"; // OTP / 2FA
        if (/^[A-Z0-9]{6,20}$/.test(t) && /^[A-Z0-9]+$/.test(t) && !/^\d+$/.test(t)) return "local_offer"; // Promo codes
        
        // 10. Text Sizing Fallbacks
        if (len < 15) {
            if (/^[^\w\s]+$/.test(t)) {
                if (/^[<>\^v]+$/.test(t)) return "keyboard"; // arrows
                if (/^[+\-*/=]+$/.test(t)) return "calculate"; // math operators
                return "text_fields"; // generic symbol
            }
            if (/^\d+$/.test(t)) return "pin"; // generic numbers
            if (/^[a-zA-Z]+$/.test(t)) return "label"; // single word
            return "short_text";
        }
        
        if (isMultiLine && len > 300) {
            if (t.includes("{") || t.includes(";") || t.includes("function") || t.includes("import")) return "code";
            return "article";
        }
        
        return "notes"; // Medium generic text
    }

    function isHexColor(text) {
        return /^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(text.trim());
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger
        anchors.margins: Tokens.padding.smaller

        Item {
            id: iconContainer
            width: 24 // Standard material icon size
            height: 24
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: (Tokens.sizes.launcher.itemHeight - height - (Tokens.padding.smaller * 2)) / 2

            MaterialIcon {
                id: icon
                text: root.getIconForContent(root.content)
                font.pointSize: Tokens.font.size.extraLarge
                color: Colours.palette.m3onSurface
                visible: !root.isHexColor(root.content)
                anchors.centerIn: parent
            }

            Rectangle {
                id: colorPreview
                visible: root.isHexColor(root.content)
                width: icon.width * 0.8
                height: width
                radius: Tokens.rounding.normal
                color: visible ? root.content.trim() : "transparent"

                anchors.horizontalCenter: icon.horizontalCenter
                anchors.verticalCenter: icon.verticalCenter
            }
        }

            Column {
                id: textColumn

                anchors.left: iconContainer.right
                anchors.leftMargin: Tokens.spacing.normal
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: (Tokens.sizes.launcher.itemHeight - (contentText.font.pixelSize + charCountText.font.pixelSize) - (Tokens.padding.smaller * 2)) / 2
                spacing: -2 // Negative spacing to offset font bounding box descent

                StyledText {
                    id: contentText

                    text: root.content
                    font.pointSize: Tokens.font.size.normal
                    lineHeight: 1.2 // Spread wrapped lines out slightly to match the visual gap
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    width: parent.width
                }

            StyledText {
                id: charCountText

                text: root.content.length >= 999 
                      ? "999+ characters"
                      : root.content.length + " characters"
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
                width: parent.width
            }
        }
    }
}
