pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components.misc

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

    function increaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.pendingBrightness + GlobalConfig.services.brightnessIncrement);
    }

    function decreaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.pendingBrightness - GlobalConfig.services.brightnessIncrement);
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
            return root.getMonitor(query)?.pendingBrightness ?? -1;
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
                targetBrightness = monitor.pendingBrightness - (percent / 100);
            } else if (value.startsWith("+") && value.endsWith("%")) {
                const percent = parseFloat(value.slice(1, -1));
                targetBrightness = monitor.pendingBrightness + (percent / 100);
            } else if (value.endsWith("%")) {
                const percent = parseFloat(value.slice(0, -1));
                targetBrightness = percent / 100;
            } else if (value.startsWith("+")) {
                const increment = parseFloat(value.slice(1));
                targetBrightness = monitor.pendingBrightness + increment;
            } else if (value.endsWith("-")) {
                const decrement = parseFloat(value.slice(0, -1));
                targetBrightness = monitor.pendingBrightness - decrement;
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

        // The value a relative adjustment should build on. DDC writes are
        // throttled to one per 500ms, and while that timer runs `brightness`
        // holds the last value actually written -- not where we are heading.
        // Stepping off `brightness` therefore makes every adjustment inside a
        // single throttle window compute the same result, so a fast scroll or
        // knob spin collapses into one step instead of accumulating.
        readonly property real pendingBrightness: isNaN(queuedBrightness) ? brightness : queuedBrightness

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
                }
            }
        }

        // Some panels acknowledge a DDC write and then sit at a different value
        // -- the MSI QD-OLED does this, and it also fails `ddcutil capabilities`
        // outright, so its DDC implementation is simply unreliable. Once the
        // value has settled, read the monitor back and re-send if it disagrees,
        // backing off each time and eventually giving up rather than fighting a
        // panel that is never going to comply.
        //
        // Deliberately NOT reusing initProc: that one assigns `brightness` from
        // the hardware, which would accept a failed write as the new truth.
        readonly property int verifyRetries: 3
        readonly property int verifyDelay: 800 // comfortably > one ~430ms DDC transaction
        property int verifyAttempt: 0

        readonly property Timer verifyTimer: Timer {
            interval: monitor.verifyDelay
            // A queued value means another write is still coming; verifying now
            // would read an intermediate state and re-send a stale value.
            onTriggered: {
                if (monitor.isDdc && isNaN(monitor.queuedBrightness) && !monitor.verifyProc.running)
                    monitor.verifyProc.running = true;
            }
        }

        readonly property Process verifyProc: Process {
            command: ["ddcutil", "-b", monitor.busNum, "getvcp", "10", "--brief"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const actual = parseInt(text.trim().split(" ")[3]);
                    if (isNaN(actual))
                        return; // read failed -- don't guess, leave it alone

                    const want = Math.round(monitor.brightness * 100);
                    if (actual === want) {
                        monitor.verifyAttempt = 0;
                        return;
                    }

                    if (monitor.verifyAttempt >= monitor.verifyRetries)
                        return; // panel won't take it; stop rather than loop forever

                    monitor.verifyAttempt++;
                    Quickshell.execDetached(["ddcutil", "-b", monitor.busNum, "setvcp", "10", want]);
                    // Back off 1600/3200/6400ms: if it missed twice the bus is
                    // busy or the panel is stuck, and retrying harder won't help.
                    monitor.verifyTimer.interval = monitor.verifyDelay * Math.pow(2, monitor.verifyAttempt);
                    monitor.verifyTimer.restart();
                }
            }
        }

        readonly property Timer timer: Timer {
            interval: 500
            onTriggered: {
                if (!isNaN(monitor.queuedBrightness)) {
                    // Clear before re-entering: setBrightness compares against
                    // pendingBrightness, which reads this very value while set.
                    const queued = monitor.queuedBrightness;
                    monitor.queuedBrightness = NaN;
                    monitor.setBrightness(queued);
                }
            }
        }

        function setBrightness(value: real): void {
            value = Math.max(0, Math.min(1, value));
            const rounded = Math.round(value * 100);
            // Compare against where we are heading, not where we last wrote --
            // otherwise a step that lands back on the last written value is
            // dropped while a contradicting queued value is still pending.
            if (Math.round(pendingBrightness * 100) === rounded)
                return;

            if (isDdc && timer.running) {
                queuedBrightness = value;
                return;
            }

            brightness = value;

            if (isAppleDisplay)
                Quickshell.execDetached(["asdbctl", "set", rounded]);
            else if (isDdc)
                Quickshell.execDetached(["ddcutil", "-b", busNum, "setvcp", "10", rounded]);
            else
                Quickshell.execDetached(["brightnessctl", "s", `${rounded}%`]);

            if (isDdc) {
                timer.restart();
                // Fresh intent: drop any retry budget spent on the old value and
                // re-arm the check, so it only runs once writes have settled.
                verifyAttempt = 0;
                verifyTimer.interval = verifyDelay;
                verifyTimer.restart();
            }
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
}
