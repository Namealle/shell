pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services

Singleton {
    id: root

    property alias shaderEnabled: props.shaderEnabled
    property alias physicalEnabled: props.physicalEnabled

    readonly property string shaderPath: Quickshell.shellPath("services/hyprlandAntiFlashbangShader/anti-flashbang.glsl")

    function enableShader(): void {
        Hypr.extras.batchMessage([
            "keyword decoration:screen_shader " + shaderPath,
            "keyword debug:damage_tracking 1"
        ]);
    }

    function disableShader(): void {
        Hypr.extras.batchMessage([
            "keyword debug:damage_tracking 2"
        ]);
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    onShaderEnabledChanged: {
        if (shaderEnabled) {
            enableShader();
        } else {
            disableShader();
        }
        // Persist to shell.json
        GlobalConfig.services.antiFlashbangShader = shaderEnabled;
    }

    onPhysicalEnabledChanged: {
        if (!physicalEnabled) {
            // Reset multipliers back to normal when turned off
            for (let i = 0; i < Brightness.monitors.length; i++) {
                Brightness.monitors[i].setBrightnessMultiplier(1.0);
            }
        }
        // Persist to shell.json
        GlobalConfig.services.antiFlashbangPhysical = physicalEnabled;
    }

    PersistentProperties {
        id: props

        property bool shaderEnabled: false
        property bool physicalEnabled: false

        reloadableId: "antiFlashbang"
    }

    // Restore persisted state from shell.json on startup
    Component.onCompleted: {
        const savedShader = GlobalConfig.services.antiFlashbangShader ?? false;
        const savedPhysical = GlobalConfig.services.antiFlashbangPhysical ?? false;

        if (savedShader) {
            root.shaderEnabled = true;
        }
        if (savedPhysical) {
            root.physicalEnabled = true;
        }
    }

    Connections {
        function onConfigReloaded(): void {
            if (props.shaderEnabled) {
                root.enableShader();
            }
        }

        target: Hypr
    }

    IpcHandler {
        target: "antiFlashbang"

        function getShaderEnabled(): bool {
            return root.shaderEnabled;
        }

        function getPhysicalEnabled(): bool {
            return root.physicalEnabled;
        }

        function setShaderEnabled(value: bool): void {
            root.shaderEnabled = value;
        }

        function setPhysicalEnabled(value: bool): void {
            root.physicalEnabled = value;
        }
    }
}
