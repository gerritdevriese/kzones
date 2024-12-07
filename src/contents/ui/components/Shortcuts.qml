import QtQuick
import org.kde.kwin

Item {

    signal cycleLayouts()

    ShortcutHandler {
        name: "KZones: Cycle layouts"
        text: "KZones: Cycle layouts"
        sequence: "Ctrl+Alt+D"
        onActivated: {
            cycleLayouts();
        }
    }

    signal cycleLayoutsReversed()

    ShortcutHandler {
        name: "KZones: Cycle layouts (reversed)"
        text: "KZones: Cycle layouts (reversed)"
        sequence: "Ctrl+Alt+Shift+D"
        onActivated: {
            cycleLayoutsReversed();
        }
    }

    signal moveActiveWindowToNextZone()

    ShortcutHandler {
        name: "KZones: Move active window to next zone"
        text: "KZones: Move active window to next zone"
        sequence: "Ctrl+Alt+Right"
        onActivated: {
            moveActiveWindowToNextZone()
        }
    }

    signal moveActiveWindowToPreviousZone()

    ShortcutHandler {
        name: "KZones: Move active window to previous zone"
        text: "KZones: Move active window to previous zone"
        sequence: "Ctrl+Alt+Left"
        onActivated: {
            moveActiveWindowToPreviousZone()
        }
    }

    signal toggleZoneOverlay()

    ShortcutHandler {
        name: "KZones: Toggle zone overlay"
        text: "KZones: Toggle zone overlay"
        sequence: "Ctrl+Alt+C"
        onActivated: {
            toggleZoneOverlay();
        }
    }

    signal switchToNextWindowInCurrentZone()

    ShortcutHandler {
        name: "KZones: Switch to next window in current zone"
        text: "KZones: Switch to next window in current zone"
        sequence: "Ctrl+Alt+Up"
        onActivated: {
            switchToNextWindowInCurrentZone()
        }
    }

    signal switchToPreviousWindowInCurrentZone()

    ShortcutHandler {
        name: "KZones: Switch to previous window in current zone"
        text: "KZones: Switch to previous window in current zone"
        sequence: "Ctrl+Alt+Down"
        onActivated: {
            switchToPreviousWindowInCurrentZone()
        }
    }

    signal moveActiveWindowToZone(int zone)

    Repeater {
        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]
        delegate: Item {
            ShortcutHandler {
                name: "KZones: Move active window to zone " + modelData
                text: "KZones: Move active window to zone " + modelData
                sequence: "Ctrl+Alt+Num+" + modelData
                onActivated: {
                    moveActiveWindowToZone(modelData - 1)
                }
            }
        }
    }

    signal activateLayout(int layout)

    Repeater {
        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]
        delegate: Item {
            ShortcutHandler {
                name: "KZones: Activate layout " + modelData
                text: "KZones: Activate layout " + modelData
                sequence: "Meta+Num+" + modelData
                onActivated: {
                    activateLayout(modelData - 1)
                }
            }
        }
    }

    signal moveActiveWindowUp()

    ShortcutHandler {
        name: "KZones: Move active window up"
        text: "KZones: Move active window up"
        sequence: "Meta+Up"
        onActivated: {
            moveActiveWindowUp()
        }
    }

    signal moveActiveWindowDown()

    ShortcutHandler {
        name: "KZones: Move active window down"
        text: "KZones: Move active window down"
        sequence: "Meta+Down"
        onActivated: {
            moveActiveWindowDown()
        }
    }

    signal moveActiveWindowLeft()

    ShortcutHandler {
        name: "KZones: Move active window left"
        text: "KZones: Move active window left"
        sequence: "Meta+Left"
        onActivated: {
            moveActiveWindowLeft()
        }
    }

    signal moveActiveWindowRight()

    ShortcutHandler {
        name: "KZones: Move active window right"
        text: "KZones: Move active window right"
        sequence: "Meta+Right"
        onActivated: {
            moveActiveWindowRight()
        }
    }

    signal snapActiveWindow()

    ShortcutHandler {
        name: "KZones: Snap active window"
        text: "KZones: Snap active window"
        sequence: "Meta+Shift+Space"
        onActivated: {
            snapActiveWindow()
        }
    }

    signal snapAllWindows()

    ShortcutHandler {
        name: "KZones: Snap all windows"
        text: "KZones: Snap all windows"
        sequence: "Meta+Space"
        onActivated: {
            snapAllWindows()
        }
    }
}