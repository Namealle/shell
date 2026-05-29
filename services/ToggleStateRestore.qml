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
        interval: 3000 // 3 seconds — enough for BlueZ and PipeWire to initialize
        running: true
        repeat: false

        onTriggered: {
            // Restore Bluetooth state
            const savedBt = GlobalConfig.services.bluetoothEnabled ?? true;
            const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
            if (adapter && adapter.enabled !== savedBt) {
                adapter.enabled = savedBt;
            }

            // Restore Mic mute state
            const savedMicMuted = GlobalConfig.services.micMuted ?? false;
            const audio = Audio.source?.audio;
            if (audio && audio.muted !== savedMicMuted) {
                audio.muted = savedMicMuted;
            }

            // Restore Game Mode state
            const savedGameMode = GlobalConfig.services.gameModeEnabled ?? false;
            if (GameMode.enabled !== savedGameMode) {
                GameMode.enabled = savedGameMode;
            }

            // Restore DND state
            const savedDnd = GlobalConfig.services.dndEnabled ?? false;
            if (Notifs.dnd !== savedDnd) {
                Notifs.dnd = savedDnd;
            }
        }
    }
}
