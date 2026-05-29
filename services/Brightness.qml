pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Caelestia.Config
import qs.components.misc
import qs.services

Singleton {
    id: root

    property list<var> ddcMonitors: []
    readonly property var ddcMonitorMap: {
        const map = {};
        for (const m of ddcMonitors)
            map[m.connector] = m;
        return map;
    }
    readonly property list<Monitor> monitors: variants.instances // qmllint disable incompatible-type
    property bool appleDisplayPresent: false

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.modelData === screen); // qmllint disable missing-property
    }

    function getMonitor(query: string): var {
        if (query === "active") {
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.focused); // qmllint disable missing-property
        }

        if (query.startsWith("model:")) {
            const model = query.slice(6);
            return monitors.find(m => m.modelData.model === model); // qmllint disable missing-property
        }

        if (query.startsWith("serial:")) {
            const serial = query.slice(7);
            return monitors.find(m => m.modelData.serialNumber === serial); // qmllint disable missing-property
        }

        if (query.startsWith("id:")) {
            const id = parseInt(query.slice(3), 10);
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.id === id); // qmllint disable missing-property
        }

        return monitors.find(m => m.modelData.name === query); // qmllint disable missing-property
    }

    property int currentGamma: 100
    readonly property int gammaLowerLimit: 10
    readonly property int gammaStep: 10

    function ensureHyprsunset(): void {
        Quickshell.execDetached(["bash", "-c", "pidof hyprsunset || hyprsunset"]);
    }

    function applyGamma(): void {
        if (currentGamma < 100) {
            ensureHyprsunset();
            Quickshell.execDetached(["hyprctl", "hyprsunset", "gamma", `${currentGamma}`]);
        } else {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        }
    }

    function increaseBrightness(monitor = null): void {
        // if gamma is not yet 100, first increase gamma
        if (currentGamma < 100) {
            currentGamma = Math.min(100, currentGamma + gammaStep);
            applyGamma();
            return;
        }

        monitor = monitor ?? getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
    }

    function decreaseBrightness(monitor = null): void {
        monitor = monitor ?? getMonitor("active");
        if (monitor && monitor.brightness > 0) {
            monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
        } else {
            // if brightness is 0, then decrease gamma
            currentGamma = Math.max(gammaLowerLimit, currentGamma - gammaStep);
            applyGamma();
        }
    }

    onMonitorsChanged: {
        ddcMonitors = [];
        ddcProc.running = true;
    }

    Variants {
        id: variants

        model: Quickshell.screens // Don't respect excluded screens cause ipc

        Monitor {}
    }

    Process {
        running: true
        command: ["sh", "-c", "asdbctl get"] // To avoid warnings if asdbctl is not installed
        stdout: StdioCollector {
            onStreamFinished: root.appleDisplayPresent = text.trim().length > 0
        }
    }

    Process {
        id: ddcProc

        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: root.ddcMonitors = text.trim().split("\n\n").filter(d => d.startsWith("Display ")).map(d => ({
                        busNum: d.match(/I2C bus:[ ]*\/dev\/i2c-([0-9]+)/)[1],
                        connector: d.match(/DRM connector:\s+(.*)/)[1].replace(/^card\d+-/, "") // strip "card1-"
                    }))
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessUp"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessDown"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }

    IpcHandler {
        function get(): real {
            return getFor("active");
        }

        // Allows searching by active/model/serial/id/name
        function getFor(query: string): real {
            return root.getMonitor(query)?.brightness ?? -1;
        }

        function set(value: string): string {
            return setFor("active", value);
        }

        // Handles brightness value like brightnessctl: 0.1, +0.1, 0.1-, 10%, +10%, 10%-
        function setFor(query: string, value: string): string {
            const monitor = root.getMonitor(query);
            if (!monitor)
                return "Invalid monitor: " + query;

            let targetBrightness;
            if (value.endsWith("%-")) {
                const percent = parseFloat(value.slice(0, -2));
                targetBrightness = monitor.brightness - (percent / 100);
            } else if (value.startsWith("+") && value.endsWith("%")) {
                const percent = parseFloat(value.slice(1, -1));
                targetBrightness = monitor.brightness + (percent / 100);
            } else if (value.endsWith("%")) {
                const percent = parseFloat(value.slice(0, -1));
                targetBrightness = percent / 100;
            } else if (value.startsWith("+")) {
                const increment = parseFloat(value.slice(1));
                targetBrightness = monitor.brightness + increment;
            } else if (value.endsWith("-")) {
                const decrement = parseFloat(value.slice(0, -1));
                targetBrightness = monitor.brightness - decrement;
            } else if (value.includes("%") || value.includes("-") || value.includes("+")) {
                return `Invalid brightness format: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;
            } else {
                targetBrightness = parseFloat(value);
            }

            if (isNaN(targetBrightness))
                return `Failed to parse value: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;

            monitor.setBrightness(targetBrightness);

            return `Set monitor ${monitor.modelData.name} brightness to ${+monitor.brightness.toFixed(2)}`;
        }

        target: "brightness"
    }

    component Monitor: QtObject {
        id: monitor

        required property ShellScreen modelData
        readonly property var ddcInfo: root.ddcMonitorMap[modelData.name] ?? null
        readonly property bool isDdc: ddcInfo !== null
        readonly property string busNum: ddcInfo?.busNum ?? ""
        readonly property bool isAppleDisplay: root.appleDisplayPresent && modelData.model.startsWith("StudioDisplay")
        property real brightness
        property real queuedBrightness: NaN
        property real brightnessMultiplier: 1.0
        readonly property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (AntiFlashbang.physicalEnabled ? brightnessMultiplier : 1.0)))
        property bool ready: false

        onMultipliedBrightnessChanged: {
            if (monitor.ready) {
                syncBrightness();
            }
        }

        readonly property Process initProc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    if (monitor.isAppleDisplay) {
                        const val = parseInt(text.trim());
                        monitor.brightness = val / 101;
                    } else {
                        const [, , , cur, max] = text.split(" ");
                        monitor.brightness = parseInt(cur) / parseInt(max);
                    }
                    monitor.ready = true;
                }
            }
        }

        readonly property Timer timer: Timer {
            id: timer
            interval: 500
            onTriggered: {
                if (!isNaN(monitor.queuedBrightness)) {
                    monitor.syncBrightness();
                    monitor.queuedBrightness = NaN;
                }
            }
        }

        readonly property Process writeProc: Process {
            id: writeProc
            onExited: (exitCode, exitStatus) => {
                if (!isNaN(monitor.queuedBrightness)) {
                    settleTimer.restart();
                }
            }
        }

        readonly property Timer settleTimer: Timer {
            id: settleTimer
            interval: 50
            onTriggered: {
                if (!isNaN(monitor.queuedBrightness)) {
                    const nextVal = monitor.queuedBrightness;
                    monitor.queuedBrightness = NaN;
                    monitor.syncBrightness();
                }
            }
        }

        function setBrightness(value: real): void {
            value = Math.max(0, Math.min(1, value));
            brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            brightnessMultiplier = value;
        }

        function syncBrightness(): void {
            const value = multipliedBrightness;
            const rounded = Math.round(value * 100);

            if (isDdc && timer.running) {
                queuedBrightness = value;
                return;
            }

            if (writeProc.running) {
                queuedBrightness = value;
                return;
            }

            let cmd = [];
            if (isAppleDisplay)
                cmd = ["asdbctl", "set", rounded];
            else if (isDdc)
                cmd = ["ddcutil", "-b", busNum, "setvcp", "10", rounded];
            else
                cmd = ["brightnessctl", "s", `${rounded}%`];

            writeProc.command = cmd;
            writeProc.running = true;

            if (isDdc)
                timer.restart();
        }

        function initBrightness(): void {
            if (isAppleDisplay)
                initProc.command = ["asdbctl", "get"];
            else if (isDdc)
                initProc.command = ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"];
            else
                initProc.command = ["sh", "-c", "echo a b c $(brightnessctl g) $(brightnessctl m)"];

            initProc.running = true;
        }

        onBusNumChanged: initBrightness()
        Component.onCompleted: initBrightness()
    }

    // Anti-flashbang screenshot & physical brightness adjustment logic
    property int workspaceAnimationDelay: 400
    property int contentSwitchDelay: 250
    property string screenshotDir: "/tmp/quickshell/brightness/antiflashbang"

    function brightnessMultiplierForLightness(x: real): real {
        // Normalizes ImageMagick lightness to [0, 1] multiplier using exponential curve
        return (6.600135 + 216.360356 * Math.pow(Math.E, -0.0811129189 * x)) / 100.0;
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope

            required property var modelData
            readonly property string screenName: modelData.name

            Connections {
                enabled: AntiFlashbang.physicalEnabled && Colours.currentLight === false // Dark mode only
                target: Hyprland
                function onRawEvent(event: HyprlandEvent): void {
                    if (["activewindowv2"].includes(event.name)) {
                        screenshotTimer.interval = root.contentSwitchDelay;
                        screenshotTimer.restart();
                    } else if (["workspacev2"].includes(event.name)) {
                        screenshotTimer.interval = root.workspaceAnimationDelay;
                        screenshotTimer.restart();
                    }
                }
            }

            Timer {
                id: screenshotTimer
                interval: 700
                onTriggered: {
                    screenshotProc.running = false;
                    screenshotProc.running = true;
                }
            }

            Process {
                id: screenshotProc
                command: ["bash", "-c",
                    `mkdir -p '${root.screenshotDir}'`
                    + ` && grim -o '${screenScope.screenName}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        const lightness = lightnessCollector.text.trim();
                        if (lightness) {
                            const newMultiplier = root.brightnessMultiplierForLightness(parseFloat(lightness));
                            const monitor = root.getMonitorForScreen(screenScope.modelData);
                            if (monitor) {
                                if (Math.abs(newMultiplier - monitor.brightnessMultiplier) > 0.05) {
                                    monitor.setBrightnessMultiplier(newMultiplier);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
