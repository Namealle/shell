pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Local additions to the shell's IPC surface. Kept out of Shortcuts.qml so
// upstream changes there never conflict with these.
Scope {
    id: root

    property string pendingQuery
    property int tries

    function searchBar(): Item {
        return ShellState.componentsForActive()?.find("launcherSearch") ?? null;
    }

    function applyQuery(): bool {
        const bar = root.searchBar();
        if (!bar)
            return false;
        bar.text = root.pendingQuery;
        bar.cursorPosition = bar.text.length;
        bar.forceActiveFocus();
        return true;
    }

    // Opens the launcher on the focused screen with `query` already typed in.
    // Repeating the bind while that same query is showing closes the launcher
    // again, matching the toggle the fuzzel pickers used to give.
    function openWithQuery(query: string): void {
        const screenState = ShellState.forActive();
        if (!screenState)
            return;

        if (screenState.launcher && root.searchBar()?.text === query) {
            screenState.launcher = false;
            return;
        }

        root.pendingQuery = query;
        screenState.launcher = true;

        // The launcher builds its search bar in a Loader, so on the first open
        // it may not exist yet; poll briefly rather than guess a delay.
        if (!root.applyQuery()) {
            root.tries = 0;
            retry.start();
        }
    }

    Timer {
        id: retry

        interval: 16
        repeat: true

        // ~2s of grace: the first open on a freshly started shell builds the
        // launcher while the apps list is still loading.
        onTriggered: {
            if (root.applyQuery() || !ShellState.forActive()?.launcher || ++root.tries > 120)
                stop();
        }
    }

    IpcHandler {
        function open(query: string): void {
            root.openWithQuery(query);
        }

        target: "launcher"
    }
}
