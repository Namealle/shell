//@ pragma Env QS_CRASHREPORT_URL=https://github.com/caelestia-dots/shell/issues/new?template=crash.yml
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded

// The sky, in its own Quickshell process.
//
// Run it with `starfield-shell start`, i.e.
//     nice -n 15 qs -p ~/.config/quickshell/caelestia/starfield.qml -n -d
// `-p` on a FILE makes that file's directory the config root, so `qs.services`,
// `qs.components`, `qs.utils` and `Caelestia.*` resolve exactly as they do for
// shell.qml -- this is the same repo, the same branch and the same rebase, just
// a second entry point into it.
//
// Why: Starfield.qml runs particle physics, packing and two Canvas paints per
// output on the engine's main thread at 30 fps. In the shell that thread also
// runs every launcher, bar, notification and drawer animation, which then wait
// on the sky. Two processes get two main threads and two render threads, and
// the kernel spreads them over different cores.
//
// What is NOT here: the desktop clock, the Visualiser, the bar, the lock -- the
// shell keeps all of it and draws it above this, from its own window on the
// BOTTOM layer. This process owns nothing but the background windows.

import "modules/background"
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.utils

ShellRoot {
    id: root

    // The session lock lives in the shell, and it is the one bit of shell state
    // the sky cannot read for itself: Ambient pauses the renderer while the lock
    // is up (rules.js runningFor). shell.qml publishes it to this one-byte file
    // on every lock/unlock; nothing polls it.
    property bool locked: false

    settings.watchFiles: false

    Binding {
        target: Ambient
        property: "locked"
        value: root.locked
    }

    StarfieldWindows {}

    FileView {
        path: `${Paths.state}/starfield-lock`
        watchChanges: true
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.locked = text().trim() === "1"
        onLoadFailed: root.locked = false
    }

    // Ambient's `rain` signal reads Weather.cc, and Weather only fetches when
    // something asks it to (the shell does it from GSFLoader).
    Component.onCompleted: Weather.reload()
}
