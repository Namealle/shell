pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property alias enabled: props.enabled
    readonly property alias enabledSince: props.enabledSince

    // PersistentProperties only survives a hot reload; a shell restart is a new process. The state
    // file lives in the runtime dir: it outlives the shell, not the login session.
    property bool loaded

    function save(): void {
        if (loaded)
            storage.setText(JSON.stringify({
                enabled: props.enabled,
                enabledSince: props.enabledSince.getTime()
            }));
    }

    onEnabledChanged: {
        if (!loaded)
            return;
        if (enabled)
            props.enabledSince = new Date();
        save();
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-idle-inhibitor.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                props.enabled = data.enabled === true;
                if (data.enabledSince)
                    props.enabledSince = new Date(data.enabledSince);
            } catch (e) {
                console.warn("IdleInhibitor: unreadable state file:", e);
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    PersistentProperties {
        id: props

        property bool enabled
        property date enabledSince

        reloadableId: "idleInhibitor"
    }

    IdleInhibitor {
        enabled: props.enabled
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            mask: Region {}
        }
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        target: "idleInhibitor"
    }
}
