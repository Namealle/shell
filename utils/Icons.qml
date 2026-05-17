pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Caelestia.Config

Singleton {
    id: root

    readonly property var weatherIcons: ({
            "0": "clear_day",
            "1": "clear_day",
            "2": "partly_cloudy_day",
            "3": "cloud",
            "45": "foggy",
            "48": "foggy",
            "51": "rainy",
            "53": "rainy",
            "55": "rainy",
            "56": "rainy",
            "57": "rainy",
            "61": "rainy",
            "63": "rainy",
            "65": "rainy",
            "66": "rainy",
            "67": "rainy",
            "71": "cloudy_snowing",
            "73": "cloudy_snowing",
            "75": "snowing_heavy",
            "77": "cloudy_snowing",
            "80": "rainy",
            "81": "rainy",
            "82": "rainy",
            "85": "cloudy_snowing",
            "86": "snowing_heavy",
            "95": "thunderstorm",
            "96": "thunderstorm",
            "99": "thunderstorm"
        })

    readonly property var categoryIcons: ({
            WebBrowser: "web",
            Printing: "print",
            Security: "security",
            Network: "chat",
            Archiving: "archive",
            Compression: "archive",
            Development: "code",
            IDE: "code",
            TextEditor: "edit_note",
            Audio: "music_note",
            Music: "music_note",
            Player: "music_note",
            Recorder: "mic",
            Game: "sports_esports",
            FileTools: "files",
            FileManager: "files",
            Filesystem: "files",
            FileTransfer: "files",
            Settings: "settings",
            DesktopSettings: "settings",
            HardwareSettings: "settings",
            TerminalEmulator: "terminal",
            ConsoleOnly: "terminal",
            Utility: "build",
            Monitor: "monitor_heart",
            Midi: "graphic_eq",
            Mixer: "graphic_eq",
            AudioVideoEditing: "video_settings",
            AudioVideo: "music_video",
            Video: "videocam",
            Building: "construction",
            Graphics: "photo_library",
            "2DGraphics": "photo_library",
            RasterGraphics: "photo_library",
            TV: "tv",
            System: "host",
            Office: "content_paste"
        })

    readonly property var keybindIcons: ({
            workspace: "workspaces",
            movetoworkspace: "arrow_circle_right",
            movetoworkspacesilent: "open_in_new",
            togglespecialworkspace: "bookmark",
            killactive: "close",
            fullscreen: "fullscreen",
            fakefullscreen: "fullscreen",
            togglefloating: "layers",
            pin: "push_pin",
            pseudo: "dashboard",
            togglesplit: "view_quilt",
            bringactivetotop: "flip_to_front",
            movewindow: "open_with",
            moveactive: "drag_pan",
            swapwindow: "swap_horiz",
            focuswindow: "flip_to_front",
            movefocus: "arrow_forward",
            cyclenext: "navigate_next",
            cycleprev: "navigate_before",
            resizeactive: "aspect_ratio",
            focusmonitor: "monitor",
            togglegroup: "tab_group",
            changegroupactive: "tab",
            movecurrentworkspacetomonitor: "monitor",
            submap: "keyboard_command_key",
            overview: "grid_view",
            dpms: "power_settings_new",
            exit: "logout",
            fallback: "keyboard",
            moveoutofgroup: "logout",
            lockactivegroup: "lock",
            movewindoworgroup: "open_with",
            setignoregrouplock: "no_encryption",
        })

    // Checks if a name matches an icon config. Icon configs can have the following keys:
    // - name: The exact name of the icon
    // - regex: A regex to match against the name (takes priority over name)
    // - flags: The regex flags (only used if regex is set)
    // - icon: The icon to use
    function matchIconConfig(name: string, iconConfig: var): bool {
        if (!iconConfig.icon)
            return false;

        if (iconConfig.regex) {
            const re = new RegExp(iconConfig.regex, iconConfig.flags ?? "");
            if (re.test(name))
                return true;
        } else if (iconConfig.name === name) {
            return true;
        }

        return false;
    }

    function getAppIcon(name: string, fallback: string): string {
        const icon = DesktopEntries.heuristicLookup(name)?.icon;
        if (fallback !== "undefined")
            return Quickshell.iconPath(icon, fallback);
        return Quickshell.iconPath(icon);
    }

    function getAppCategoryIcon(name: string, fallback: string): string {
        for (const iconConfig of GlobalConfig.bar.workspaces.windowIcons)
            if (matchIconConfig(name, iconConfig))
                return iconConfig.icon;

        const categories = DesktopEntries.heuristicLookup(name)?.categories;

        if (categories)
            for (const [key, value] of Object.entries(categoryIcons))
                if (categories.includes(key))
                    return value;
        return fallback;
    }

    function getNetworkIcon(strength: int, isSecure = false): string {
        if (isSecure) {
            if (strength >= 80)
                return "network_wifi_locked";
            if (strength >= 60)
                return "network_wifi_3_bar_locked";
            if (strength >= 40)
                return "network_wifi_2_bar_locked";
            if (strength >= 20)
                return "network_wifi_1_bar_locked";
            return "signal_wifi_0_bar";
        } else {
            if (strength >= 80)
                return "network_wifi";
            if (strength >= 60)
                return "network_wifi_3_bar";
            if (strength >= 40)
                return "network_wifi_2_bar";
            if (strength >= 20)
                return "network_wifi_1_bar";
            return "signal_wifi_0_bar";
        }
    }

    function getBluetoothIcon(icon: string): string {
        if (icon.includes("headset") || icon.includes("headphones"))
            return "headphones";
        if (icon.includes("audio"))
            return "speaker";
        if (icon.includes("phone"))
            return "smartphone";
        if (icon.includes("mouse"))
            return "mouse";
        if (icon.includes("keyboard"))
            return "keyboard";
        return "bluetooth";
    }

    function getWeatherIcon(code: string): string {
        if (weatherIcons.hasOwnProperty(code))
            return weatherIcons[code];
        return "air";
    }

    function getNotifIcon(summary: string, urgency: int): string {
        summary = summary.toLowerCase();
        if (summary.includes("reboot"))
            return "restart_alt";
        if (summary.includes("recording"))
            return "screen_record";
        if (summary.includes("battery"))
            return "power";
        if (summary.includes("screenshot"))
            return "screenshot_monitor";
        if (summary.includes("welcome"))
            return "waving_hand";
        if (summary.includes("time") || summary.includes("a break"))
            return "schedule";
        if (summary.includes("installed"))
            return "download";
        if (summary.includes("update"))
            return "update";
        if (summary.includes("unable to"))
            return "deployed_code_alert";
        if (summary.includes("profile"))
            return "person";
        if (summary.includes("file"))
            return "folder_copy";
        if (urgency === NotificationUrgency.Critical)
            return "release_alert";
        return "chat";
    }

    function getVolumeIcon(volume: real, isMuted: bool): string {
        if (isMuted)
            return "no_sound";
        if (volume >= 0.5)
            return "volume_up";
        if (volume > 0)
            return "volume_down";
        return "volume_mute";
    }

    function getMicVolumeIcon(volume: real, isMuted: bool): string {
        if (!isMuted && volume > 0)
            return "mic";
        return "mic_off";
    }

    function getSpecialWsIcon(name: string): string {
        name = name.toLowerCase().slice("special:".length);

        for (const iconConfig of GlobalConfig.bar.workspaces.specialWorkspaceIcons)
            if (matchIconConfig(name, iconConfig))
                return iconConfig.icon;

        if (name === "special")
            return "star";
        if (name === "communication")
            return "forum";
        if (name === "music")
            return "music_cast";
        if (name === "todo")
            return "checklist";
        if (name === "sysmon")
            return "monitor_heart";
        return name[0].toUpperCase();
    }

    function getTrayIcon(id: string, icon: string): string {
        for (const sub of GlobalConfig.bar.tray.iconSubs)
            if (sub.id === id)
                return sub.image ? Qt.resolvedUrl(sub.image) : Quickshell.iconPath(sub.icon);

        if (icon.includes("?path=")) {
            const [name, path] = icon.split("?path=");
            icon = Qt.resolvedUrl(`${path}/${name.slice(name.lastIndexOf("/") + 1)}`);
        }
        return icon;
    }

    function getBatteryIcon(charge: int): string {
        if (charge > 0 && charge < 5)
            return "battery_0_bar";
        if (charge >= 5 && charge < 20)
            return "battery_1_bar";
        if (charge >= 20 && charge < 35)
            return "battery_2_bar";
        if (charge >= 35 && charge < 50)
            return "battery_3_bar";
        if (charge >= 50 && charge < 65)
            return "battery_4_bar";
        if (charge >= 65 && charge < 80)
            return "battery_5_bar";
        if (charge >= 80 && charge < 95)
            return "battery_6_bar";
        if (charge >= 95)
            return "battery_full";
        return "battery_alert";
    }

    function getKeybindIcon(dispatcher: string, arg: string): string {
        if (dispatcher !== "exec") {
            const isBack = /(\s|^)(-\d|prev|l\b|left)/.test(arg);
            const isForward = /(\s|^)(\+\d|next|r\b|right)/.test(arg);
            const isUp = /(\s|^)(u\b|up)/.test(arg);
            const isDown = /(\s|^)(d\b|down)/.test(arg);

            if (dispatcher === "workspace" || dispatcher === "movetoworkspace" || dispatcher === "movetoworkspacesilent") {
                if (isBack)    return "arrow_back";
                if (isForward) return "arrow_forward";
                return "workspaces";
            }

            if (dispatcher === "movefocus" || dispatcher === "movewindow") {
                if (isBack)    return "arrow_back";
                if (isForward) return "arrow_forward";
                if (isUp)      return "arrow_upward";
                if (isDown)    return "arrow_downward";
            }

            if (dispatcher === "layoutmsg") {
                if (arg.includes("togglesplit") || arg.includes("split")) return "view_quilt";
                if (arg.includes("swap"))     return "swap_horiz";
                if (arg.includes("preselect") || arg.includes("next")) return "arrow_forward";
                if (arg.includes("prev"))     return "arrow_back";
                return keybindIcons.fallback;
            }

            if (dispatcher === "resizeactive") {
                const parts = arg.trim().split(/\s+/);
                const x = parseFloat(parts[0]) || 0;
                const y = parseFloat(parts[1]) || 0;
                if (x < 0) return "arrow_back";
                if (x > 0) return "arrow_forward";
                if (y < 0) return "arrow_upward";
                if (y > 0) return "arrow_downward";
                return "aspect_ratio";
            }

            if (dispatcher === "cyclenext")
                return arg.includes("prev") ? "arrow_back" : "arrow_forward";

            if (dispatcher === "changegroupactive")
                return arg.includes("b") ? "arrow_back" : "arrow_forward";

            return keybindIcons[dispatcher] ?? keybindIcons.fallback;
        }

        const keywords = [
            ["workspace",      "workspaces"],
            ["movetoworkspace","arrow_circle_right"],
            ["screenshot",     "screenshot_monitor"],
            ["record",         "screen_record"],
            ["clipboard",      "content_paste"],
            ["emoji",          "emoji_emotions"],
            ["volume",         "volume_up"],
            ["brightness",     "brightness_6"],
            ["bluetooth",      "bluetooth"],
            ["wifi",           "wifi"],
            ["network",        "lan"],
            ["suspend",        "bedtime"],
            ["hibernate",      "bedtime"],
            ["shutdown",       "power_settings_new"],
            ["reboot",         "restart_alt"],
            ["logout",         "logout"],
            ["lock",           "lock"],
            ["notify",         "notifications"],
            ["wallpaper",      "wallpaper"],
            ["music",          "music_note"],
            ["playerctl",      "music_note"],
            ["media",          "play_circle"],
            ["sysmon",         "monitor_heart"],
            ["todo",           "checklist"],
            ["communication",  "forum"],
            ["specialws",      "bookmark"],
            ["pip",            "picture_in_picture"],
            ["picker",         "colorize"],
            ["colour",         "colorize"],
            ["color",          "colorize"],
            ["power",          "power_settings_new"],
        ];

        for (const [keyword, icon] of keywords)
            if (arg.includes(keyword))
                return icon;

        if (arg.includes(" -- ")) {
            const appName = arg.split(" -- ")[1].trim().split(/\s+/)[0];
            if (appName) {
                const entry = DesktopEntries.heuristicLookup(appName);
                if (entry?.icon) {
                    const path = Quickshell.iconPath(entry.icon, "");
                    if (path) return path;
                }
                return "image_not_supported";
            }
            return keybindIcons.fallback;
        }

        if (!/[|;&]/.test(arg)) {
            const skipList = ["bash","sh","fish","zsh","python","python3","node",
                "pkill","kill","killall","notify-send","grim","slurp","wl-copy",
                "wl-paste","cliphist","ydotool","xdotool","sleep","echo","cat",
                "hyprctl","wpctl","systemctl","loginctl","pactl","qs","app2unit",
                "caelestia","hyprpicker"];

            const binary = arg.trim().split(/\s+/)[0].split("/").pop();
            if (binary && !skipList.includes(binary)) {
                const entry = DesktopEntries.heuristicLookup(binary);
                if (entry?.icon) {
                    const path = Quickshell.iconPath(entry.icon, "");
                    if (path) return path;
                }
                return "image_not_supported";
            }
        }

        return keybindIcons.fallback;
    }

}
