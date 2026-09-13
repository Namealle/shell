//@ pragma Env QS_CRASHREPORT_URL=https://github.com/caelestia-dots/shell/issues/new?template=crash.yml
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services as Services
import qs.utils

ShellRoot {
    id: root

    settings.watchFiles: false

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    // The sky pauses while the session is locked (rules.js runningFor), and
    // which process needs to hear that depends on where the sky runs. In-shell
    // it is a plain binding; out of process (the default) it is the one-byte
    // file starfield.qml watches. Naming Ambient only in the in-shell branch is
    // what keeps the whole reactive poller -- a 250 ms timer, /proc reads,
    // nvidia-smi -- out of this process while the sky is elsewhere.
    Binding {
        target: Services.Starfield.inShell ? Ambient : null
        property: "locked"
        value: lock.lock.locked
    }

    FileView {
        id: lockState

        path: `${Paths.state}/starfield-lock`
        printErrors: false
    }

    QtObject {
        id: lockPublisher

        readonly property bool locked: lock.lock.locked

        onLockedChanged: lockState.setText(locked ? "1" : "0")
        // A shell that died while locked would otherwise leave the sky paused.
        Component.onCompleted: lockState.setText(locked ? "1" : "0")
    }

    GSFLoader {}
    ServiceLoader {}

    Background {}
    Drawers {}
    AreaPicker {}
    Lock {
        id: lock
    }

    Shortcuts {}
    UserShortcuts {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
