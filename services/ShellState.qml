pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import qs.components
import qs.services

Singleton {
    property ShellRoot shellRoot

    function anySidebarOpen(): bool {
        return states.instances.some(s => s.sidebar);
    }

    function forScreen(screen: ShellScreen): ScreenState {
        for (const s of states.instances)
            if (s.modelData === screen)
                return s;
        return null;
    }

    function forActive(): ScreenState {
        const mon = Hypr.focusedMonitor;
        for (const s of states.instances)
            if (Hypr.monitorFor(s.modelData) === mon)
                return s;
        return null;
    }

    function componentsFor(screen: ShellScreen): Components {
        for (const c of components.instances)
            if (c.modelData === screen)
                return c;
        return null;
    }

    function componentsForActive(): Components {
        const mon = Hypr.focusedMonitor;
        for (const c of components.instances)
            if (Hypr.monitorFor(c.modelData) === mon)
                return c;
        return null;
    }

    Variants {
        id: states

        model: Screens.screens

        ScreenState {}
    }

    Variants {
        id: components

        model: Screens.screens

        Components {}
    }

    component Components: QtObject {
        required property ShellScreen modelData

        property var background
        property var rootWindow
        property var interactionWrapper
        property var bar
        property var panels

        function find(name: string, rootItem: Item): var {
            return CUtils.findChild(rootItem ?? rootWindow?.contentItem, name);
        }

        function findAll(name: string, rootItem: Item): var {
            return CUtils.findChildren(rootItem ?? rootWindow?.contentItem, name);
        }

        function findMatching(pattern: string, rootItem: Item): var {
            return CUtils.findChildrenMatching(rootItem ?? rootWindow?.contentItem, pattern);
        }
    }

    component ComponentRef: QtObject {
        required property ShellScreen screen
        required property string slot
        required property var component

        // The screen this ref was created for. When a monitor goes away, Qt
        // moves its window onto a remaining screen before destroying it.
        // Following that move let the dying window claim the survivor's slot
        // and then clear it on destruction, so find() on the survivor returned
        // null until a restart -- one sleep/wake of the second monitor and
        // `launcher open <query>` opened with an empty search bar. Windows are
        // per screen, so a ref never has a reason to change screens.
        //
        // `pinned` is separate from `home` on purpose: an object property
        // pointing at a destroyed screen reads null, and that must mean "my
        // screen is gone" (no target), not "adopt whatever screen comes next".
        property ShellScreen home: null
        property bool pinned: false
        readonly property QtObject target: pinned ? (home ? ShellState.componentsFor(home) : null) : ShellState.componentsFor(screen)

        function claim(): void {
            if (target)
                target[slot] = component;
        }

        function pin(): void {
            if (pinned || !screen)
                return;
            home = screen;
            pinned = true;
        }

        onScreenChanged: pin()
        onTargetChanged: claim()
        // A change handler never runs for a binding's initial value, so a
        // window built while its screen's Components already exist would
        // otherwise never register.
        Component.onCompleted: {
            pin();
            claim();
        }
        Component.onDestruction: {
            if (target && target[slot] === component)
                target[slot] = null;
        }
    }
}
