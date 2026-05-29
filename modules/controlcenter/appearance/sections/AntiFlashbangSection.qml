pragma ComponentBehavior: Bound

import ".."
import "../../components"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

CollapsibleSection {
    id: root

    title: qsTr("Anti-Flashbang")
    description: qsTr("Adapts your screen to sudden bright elements in dark environments")
    showBackground: true

    SwitchRow {
        label: qsTr("Content adjustment")
        checked: AntiFlashbang.shaderEnabled
        onToggled: checked => {
            AntiFlashbang.shaderEnabled = checked;
        }
    }

    SwitchRow {
        label: qsTr("Brightness adjustment")
        checked: AntiFlashbang.physicalEnabled
        onToggled: checked => {
            AntiFlashbang.physicalEnabled = checked;
        }
    }
}
