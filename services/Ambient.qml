pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import qs.services
import "ambient/rules.js" as Rules
import "ambient/signals.js" as Signals

Singleton {
    id: root

    property bool locked: false
    readonly property var profiles: state.profiles
    readonly property var signals: state.signals
    readonly property var rates: state.rates
    readonly property var valid: state.valid
    readonly property var policy: screenPolicy()
    readonly property bool polling: Starfield.reactive.enabled && Object.keys(policy).some(name => policy[name])
    readonly property bool mediaPlaying: Players.list.some(player => player.isPlaying)

    function forScreen(name: string): var {
        return Object.prototype.hasOwnProperty.call(profiles, name) ? profiles[name] : neutral(true);
    }

    function seedFor(name: string): int {
        return Rules.seedFor(name);
    }

    function sourceTime(): real {
        const monotonic = clock.elapsed();
        const wall = Date.now() / 1000;
        if (state.clockReady) {
            const elapsed = Signals.elapsedStep(state.previousClock, monotonic, state.previousWall, wall);
            state.ageOffset += elapsed.ageAdvance;
            state.resetPending = state.resetPending || elapsed.reset;
        }
        state.clockReady = true;
        state.previousClock = monotonic;
        state.previousWall = wall;
        return monotonic + state.ageOffset;
    }

    function neutral(running: bool): var {
        return {
            birth: Qt.vector4d(0, 0, 0, 0.5),
            live: Qt.vector4d(0.5, 0.5, 0.5, 0.5),
            running: running
        };
    }

    function screenPolicy(): var {
        const result = Object.create(null);
        for (const screen of Screens.screens) {
            if (Starfield.enabledFor(screen.name) && GlobalConfig.forScreen(screen.name).background.enabled)
                result[screen.name] = Rules.runningFor(Hypr.monitorFor(screen), Hypr.toplevels.values, root.locked);
        }
        return result;
    }

    function record(name: string, raw: var, now: real): void {
        Signals.record(state.bank, name, raw, now);
    }

    function recordWeather(): void {
        if (!state.ready)
            return;
        const samples = Signals.weather(Weather.cc);
        const now = sourceTime();
        for (const name of Object.keys(samples))
            record(name, samples[name], now);
    }

    function reconcilePolicy(): void {
        if (!state.ready)
            return;
        const next = Object.create(null);
        const contexts = Object.create(null);
        for (const name of Object.keys(policy)) {
            const previous = forScreen(name);
            next[name] = policy[name] && !Starfield.reactive.enabled ? neutral(true) : {
                birth: previous.birth,
                live: previous.live,
                running: policy[name]
            };
            contexts[name] = state.contexts[name] || Signals.createBank();
        }
        state.contexts = contexts;
        state.profiles = next;
    }

    function configChanged(): void {
        if (!state.ready)
            return;
        state.compiled = Rules.compileMatchers(Starfield.reactive.matchers);
        // Category banks contain numbers only. Drop removed/renamed matchers immediately.
        state.contexts = Object.create(null);
        state.nextContext = 0;
        reconcilePolicy();
        if (!root.polling)
            publish(null, 0, sourceTime());
    }

    function resetSampling(): void {
        state.previousCpu = null;
        state.networkReceipt = -100;
        Signals.reset(state.bank);
        for (const name of Object.keys(state.contexts))
            Signals.reset(state.contexts[name]);
        state.nextCpu = 0;
        state.nextSlow = 0;
        state.nextContext = 0;
        state.nextMinute = 0;
        state.nextAgent = 0;
        state.resumePending = true;
    }

    function stopProcesses(): void {
        state.gpuAttempt = false;
        gpu.running = false;
        agent.running = false;
        uidProbe.running = false;
        hwmonProbe.running = false;
        cpuFile.path = "";
        memoryFile.path = "";
        temperatureFile.path = "";
        state.cpuPending = false;
        state.memoryPending = false;
        state.temperaturePending = false;
    }

    function pollStateChanged(): void {
        if (!state.ready)
            return;
        if (polling) {
            resetSampling();
            state.gpuNext = 0;
            tick();
        } else {
            stopProcesses();
            resetSampling();
        }
        reconcilePolicy();
    }

    function sampleContext(now: real): void {
        record("media", mediaPlaying ? 1 : 0, now);
        record("idle", idle.isIdle ? 1 : 0, now);
        for (const screen of Screens.screens) {
            const name = screen.name;
            if (!policy[name])
                continue;
            const bank = state.contexts[name] || Signals.createBank();
            const strengths = Rules.categories(state.compiled, Hypr.toplevels.values, Hypr.monitorFor(screen), Hypr.activeToplevel);
            for (const category of Object.keys(strengths))
                Signals.record(bank, category, strengths[category], now, 45, 5);
            state.contexts[name] = bank;
        }
    }

    function publish(global: var, dt: real, now: real): void {
        const next = Object.create(null);
        for (const name of Object.keys(policy)) {
            if (!policy[name]) {
                // Preserve vectors while covered, including configuration edits.
                const old = forScreen(name);
                next[name] = {
                    birth: old.birth,
                    live: old.live,
                    running: false
                };
                continue;
            }
            if (!global || !Starfield.reactive.enabled) {
                next[name] = neutral(true);
                continue;
            }
            const bank = state.contexts[name] || Signals.createBank();
            const context = Signals.advance(bank, now, dt);
            const values = Object.assign({}, global.values, context.values);
            Signals.derive(values, Starfield.reactive.processPresenceWeight, state.bank, global.weights);
            const target = Rules.evaluate(Starfield.reactive, values);
            next[name] = {
                birth: Qt.vector4d(target.birth[0], target.birth[1], target.birth[2], target.birth[3]),
                live: Qt.vector4d(target.live[0], target.live[1], target.live[2], target.live[3]),
                running: true
            };
        }
        state.profiles = next;
    }

    function gpuFailed(now: real): void {
        state.gpuAttempt = false;
        gpu.running = false;
        const backoff = [30, 60, 300];
        state.gpuNext = now + backoff[Math.min(state.gpuFailures, 2)];
        state.gpuFailures = Math.min(state.gpuFailures + 1, 3);
    }

    function manageProcesses(now: real): void {
        if (state.gpuAttempt && ((!gpu.running && now - state.gpuStarted > 2) || now - Math.max(state.gpuStarted, state.gpuLastGood) > 20))
            gpuFailed(now);
        if (!gpu.running && !state.gpuAttempt && now >= state.gpuNext) {
            state.gpuAttempt = true;
            state.gpuStarted = now;
            gpu.running = true;
        }
        if (uidProbe.running && now - state.uidStarted > 2)
            uidProbe.running = false;
        if (hwmonProbe.running && now - state.hwmonStarted > 2)
            hwmonProbe.running = false;
        if (agent.running && now - state.agentStarted > 2)
            agent.running = false;
        if (!state.uid && !uidProbe.running && now >= state.uidNext) {
            state.uidStarted = now;
            state.uidNext = now + 300;
            uidProbe.running = true;
        }
        if (!state.temperaturePath && !hwmonProbe.running && now >= state.hwmonNext) {
            state.hwmonStarted = now;
            state.hwmonNext = now + 300;
            hwmonProbe.running = true;
        }
        if (state.uid && !agent.running && now >= state.nextAgent) {
            state.nextAgent = now + 10;
            state.agentStarted = now;
            agent.command = ["pgrep", "-u", state.uid, "-x", "claude|codex"];
            agent.running = true;
        }
    }

    function tick(): void {
        if (!polling)
            return;
        const now = sourceTime();
        const monotonic = clock.elapsed();
        const elapsed = monotonic - state.previousTick;
        // Event receipts also reconcile sleep before timestamping newly arrived samples.
        if (state.resetPending || elapsed < 0 || elapsed > 2) {
            resetSampling();
            stopProcesses();
        }
        state.resetPending = false;
        const dt = state.resumePending ? 0 : elapsed;
        state.resumePending = false;
        state.previousTick = monotonic;
        if (now >= state.nextCpu) {
            state.nextCpu = now + 2;
            if (!state.cpuPending) {
                state.cpuPending = true;
                if (cpuFile.path === "/proc/stat")
                    cpuFile.reload();
                else
                    cpuFile.path = "/proc/stat";
            }
        }
        if (now >= state.nextSlow) {
            state.nextSlow = now + 5;
            if (!state.memoryPending) {
                state.memoryPending = true;
                if (memoryFile.path === "/proc/meminfo")
                    memoryFile.reload();
                else
                    memoryFile.path = "/proc/meminfo";
            }
            if (state.temperaturePath && !state.temperaturePending) {
                state.temperaturePending = true;
                if (temperatureFile.path === state.temperaturePath)
                    temperatureFile.reload();
                else
                    temperatureFile.path = state.temperaturePath;
            }
            if (now - state.networkReceipt <= 20)
                record("network", Signals.network(NetworkUsage.downloadSpeed, NetworkUsage.uploadSpeed), now);
        }
        if (now >= state.nextContext) {
            state.nextContext = now + 1;
            sampleContext(now);
        }
        if (now >= state.nextMinute) {
            state.nextMinute = now + 60;
            record("night", Signals.night(Time.hours, Time.minutes), now);
        }
        manageProcesses(now);
        const global = Signals.advance(state.bank, now, dt);
        Signals.derive(global.values, Starfield.reactive.processPresenceWeight, state.bank, global.weights);
        state.signals = global.values;
        state.rates = global.rates;
        state.valid = global.valid;
        publish(global, dt, now);
    }

    onPolicyChanged: reconcilePolicy()
    onPollingChanged: pollStateChanged()
    onMediaPlayingChanged: {
        if (state.ready && polling)
            record("media", mediaPlaying ? 1 : 0, sourceTime());
    }
    Component.onCompleted: {
        state.previousTick = clock.elapsed();
        state.ready = true;
        configChanged();
        recordWeather();
        pollStateChanged();
    }

    QtObject {
        id: state

        property bool ready: false
        property bool resumePending: true
        property bool clockReady: false
        property bool resetPending: false
        property real ageOffset: 0
        property real previousClock: 0
        property var profiles: ({})
        property var signals: ({})
        property var rates: ({})
        property var valid: ({})
        property var bank: Signals.createBank()
        property var contexts: Object.create(null)
        property var compiled: []
        property var previousCpu: null
        property real previousTick: 0
        property real previousWall: 0
        property real nextCpu: 0
        property real nextSlow: 0
        property real nextContext: 0
        property real nextMinute: 0
        property real nextAgent: 0
        property real networkReceipt: -100
        property bool cpuPending: false
        property bool memoryPending: false
        property bool temperaturePending: false
        property string temperaturePath: ""
        property string uid: ""
        property real uidStarted: 0
        property real uidNext: 0
        property real hwmonStarted: 0
        property real hwmonNext: 0
        property real agentStarted: 0
        property bool gpuAttempt: false
        property real gpuStarted: 0
        property real gpuLastGood: -100
        property real gpuNext: 0
        property int gpuFailures: 0
    }

    ServiceRef {
        service: root.polling ? Cpu : null
    }

    ServiceRef {
        service: root.polling ? Memory : null
    }

    ServiceRef {
        service: root.polling ? NetworkUsage : null
    }

    ElapsedTimer {
        id: clock
    }

    Timer {
        interval: 250
        repeat: true
        running: root.polling
        onTriggered: root.tick()
    }

    IdleMonitor {
        id: idle

        timeout: 120
        respectInhibitors: false
        onIsIdleChanged: {
            if (root.polling)
                root.record("idle", isIdle ? 1 : 0, root.sourceTime());
        }
    }

    Connections {
        target: Starfield

        function onReactiveChanged(): void {
            root.configChanged();
        }
    }

    Connections {
        target: Weather

        function onCcChanged(): void {
            root.recordWeather();
        }
    }

    Connections {
        target: NetworkUsage

        function onChanged(): void {
            if (root.polling)
                state.networkReceipt = root.sourceTime();
        }
    }

    FileView {
        id: cpuFile

        path: ""
        preload: true
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: {
            state.cpuPending = false;
            if (!root.polling)
                return;
            const current = Signals.parseCpu(text());
            const delta = Signals.cpuDelta(state.previousCpu, current);
            state.previousCpu = current;
            // Async receipt supplies freshness and the first-sample/reset guard missing from Cpu.
            if (delta !== null) {
                const shared = Signals.ratio(Cpu.percentage);
                root.record("cpuLoad", shared === null ? delta : shared, root.sourceTime());
            }
        }
        onLoadFailed: {
            state.cpuPending = false;
            state.previousCpu = null;
        }
    }

    FileView {
        id: memoryFile

        path: ""
        preload: true
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: {
            state.memoryPending = false;
            if (!root.polling)
                return;
            const raw = Signals.parseMemory(text());
            if (raw !== null) {
                const shared = Memory.total > 0 ? Signals.ratio(Memory.percentage) : null;
                root.record("ram", shared === null ? raw : shared, root.sourceTime());
            }
        }
        onLoadFailed: state.memoryPending = false
    }

    FileView {
        id: temperatureFile

        path: ""
        preload: true
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: {
            state.temperaturePending = false;
            if (!root.polling)
                return;
            const raw = Signals.parseTemperature(text());
            if (raw !== null) {
                const shared = Signals.heat(Cpu.temperature, 85);
                root.record("cpuHeat", shared === null ? raw : shared, root.sourceTime());
            }
        }
        onLoadFailed: {
            state.temperaturePending = false;
            state.temperaturePath = "";
        }
    }

    Process {
        id: gpu

        command: ["nvidia-smi", "--query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits", "--loop=5"]
        stdout: SplitParser {
            onRead: data => {
                if (!root.polling || !state.gpuAttempt)
                    return;
                const sample = Signals.parseGpu(data);
                const now = root.sourceTime();
                // Single-GPU target: take the first valid row of each batch.
                if (!sample || now - state.gpuLastGood < 2)
                    return;
                state.gpuLastGood = now;
                state.gpuFailures = 0;
                for (const name of Object.keys(sample))
                    root.record(name, sample[name], now);
            }
        }
        stderr: SplitParser {
            onRead: data => {}
        }
        onExited: {
            if (root.polling && state.gpuAttempt)
                root.gpuFailed(root.sourceTime());
        }
    }

    Process {
        id: uidProbe

        command: ["id", "-u"]
        stdout: SplitParser {
            onRead: data => {
                const uid = data.trim();
                if (/^\d{1,10}$/.test(uid))
                    state.uid = uid;
            }
        }
        stderr: SplitParser {
            onRead: data => {}
        }
    }

    Process {
        id: agent

        stdout: SplitParser {
            onRead: data => {}
        }
        stderr: SplitParser {
            onRead: data => {}
        }
        onExited: (exitCode, exitStatus) => {
            if (root.polling && exitStatus === 0 && (exitCode === 0 || exitCode === 1))
                root.record("agentProcess", exitCode === 0 ? 1 : 0, root.sourceTime());
        }
    }

    Process {
        id: hwmonProbe

        // Fixed read-only discovery; neither configuration nor titles enter this command.
        command: ["sh", "-c", "for d in /sys/class/hwmon/hwmon*; do read -r n < \"$d/name\" || continue; [ \"$n\" = k10temp ] || continue; for want in Tdie Tctl; do for f in \"$d\"/temp*_label; do [ -r \"$f\" ] || continue; IFS= read -r label < \"$f\"; if [ \"$label\" = \"$want\" ]; then printf '%s\\n' \"${f%_label}_input\"; exit; fi; done; done; done"]
        stdout: SplitParser {
            onRead: data => {
                const path = data.trim();
                if (/^\/sys\/class\/hwmon\/hwmon[0-9]+\/temp[0-9]+_input$/.test(path))
                    state.temperaturePath = path;
            }
        }
        stderr: SplitParser {
            onRead: data => {}
        }
    }

    // Diagnostics only: `caelestia shell ipc call ambient dump` prints the
    // current per-screen targets and normalised signals. Never includes titles.
    IpcHandler {
        function dump(): string {
            const out = {};
            for (const name of Object.keys(root.profiles)) {
                const p = root.profiles[name];
                out[name] = {
                    running: p.running,
                    birth: [p.birth.x, p.birth.y, p.birth.z, p.birth.w].map(v => Math.round(v * 1000) / 1000),
                    live: [p.live.x, p.live.y, p.live.z, p.live.w].map(v => Math.round(v * 1000) / 1000)
                };
            }
            return JSON.stringify({
                polling: root.polling,
                locked: root.locked,
                profiles: out,
                signals: root.signals,
                valid: root.valid
            });
        }

        target: "ambient"
    }
}
