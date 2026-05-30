pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Caelestia.Config
import qs.services

// Restores persisted quick toggle states from shell.json on shell startup.
// Uses a delayed timer to ensure underlying services (BlueZ, PipeWire, etc.)
// have fully initialized before we apply saved states.
Singleton {
    id: root

    Timer {
        id: restoreTimer
        interval: 2000
        running: true
        repeat: true
        property int attempts: 0
        property bool btRestored: false
        property bool micRestored: false

        onTriggered: {
            attempts++;

            // Restore Bluetooth state
            if (!btRestored) {
                const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
                if (adapter) {
                    const savedBt = GlobalConfig.services.bluetoothEnabled ?? true;
                    if (adapter.enabled !== savedBt) {
                        adapter.enabled = savedBt;
                    }
                    btRestored = true;
                }
            }

            // Restore Mic mute state
            if (!micRestored) {
                const audio = Audio.source?.audio;
                if (audio) {
                    const savedMicMuted = GlobalConfig.services.micMuted ?? false;
                    if (audio.muted !== savedMicMuted) {
                        audio.muted = savedMicMuted;
                    }
                    micRestored = true;
                }
            }

            // GameMode and DND are fast, restore immediately on first tick
            if (attempts === 1) {
                const savedGameMode = GlobalConfig.services.gameModeEnabled ?? false;
                if (GameMode.enabled !== savedGameMode) {
                    GameMode.enabled = savedGameMode;
                }

                const savedDnd = GlobalConfig.services.dndEnabled ?? false;
                if (Notifs.dnd !== savedDnd) {
                    Notifs.dnd = savedDnd;
                }
            }

            // Stop timer once slow daemons are initialized or we give up after 20 seconds
            if ((btRestored && micRestored) || attempts >= 10) {
                running = false;
            }
        }
    }
}
