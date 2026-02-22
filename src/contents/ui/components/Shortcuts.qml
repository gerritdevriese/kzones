import QtQuick
import org.kde.kwin

Item {
    signal cycleLayouts()
    signal cycleLayoutsReversed()
    signal moveActiveWindowToNextZone()
    signal moveActiveWindowToPreviousZone()
    signal toggleZoneOverlay()
    signal switchToNextWindowInCurrentZone()
    signal switchToPreviousWindowInCurrentZone()
    signal moveActiveWindowToZone(int zone)
    signal activateLayout(int layout)
    signal moveActiveWindowUp()
    signal moveActiveWindowDown()
    signal moveActiveWindowLeft()
    signal moveActiveWindowRight()
    signal snapActiveWindow()
    signal snapAllWindows()

    ShortcutHandler {
        name: "KZones: Cycle layouts"
        text: "KZones: Cycle layouts"
        sequence: "Ctrl+Alt+D"
        onActivated: {
            cycleLayouts();
        }
    }

    ShortcutHandler {
        name: "KZones: Cycle layouts (reversed)"
        text: "KZones: Cycle layouts (reversed)"
        sequence: "Ctrl+Alt+Shift+D"
        onActivated: {
            cycleLayoutsReversed();
        }
    }

    ShortcutHandler {
        name: "KZones: Move active window to next zone"
        text: "KZones: Move active window to next zone"
        sequence: "Ctrl+Alt+Right"
        onActivated: {
            moveActiveWindowToNextZone();
        }
    }

    ShortcutHandler {
        name: "KZones: Move active window to previous zone"
        text: "KZones: Move active window to previous zone"
        sequence: "Ctrl+Alt+Left"
        onActivated: {
            moveActiveWindowToPreviousZone();
        }
    }

    ShortcutHandler {
        name: "KZones: Toggle zone overlay"
        text: "KZones: Toggle zone overlay"
        sequence: "Ctrl+Alt+C"
        onActivated: {
            toggleZoneOverlay();
        }
    }

    ShortcutHandler {
        name: "KZones: Switch to next window in current zone"
        text: "KZones: Switch to next window in current zone"
        sequence: "Ctrl+Alt+Up"
        onActivated: {
            switchToNextWindowInCurrentZone();
        }
    }

    ShortcutHandler {
        name: "KZones: Switch to previous window in current zone"
        text: "KZones: Switch to previous window in current zone"
        sequence: "Ctrl+Alt+Down"
        onActivated: {
            switchToPreviousWindowInCurrentZone();
        }
    }

    Repeater {
        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]

        delegate: Item {
            ShortcutHandler {
                name: "KZones: Move active window to zone " + modelData
                text: "KZones: Move active window to zone " + modelData
                sequence: "Ctrl+Alt+Num+" + modelData
                onActivated: {
                    moveActiveWindowToZone(modelData - 1);
                }
            }

        }

    }

    Repeater {
        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]

        delegate: Item {
            ShortcutHandler {
                name: "KZones: Activate layout " + modelData
                text: "KZones: Activate layout " + modelData
                sequence: "Meta+Num+" + modelData
                onActivated: {
                    activateLayout(modelData - 1);
                }
            }

        }

    }

    ShortcutHandler {
        name: "KZones: Move active window up"
        text: "KZones: Move active window up"
        sequence: "Meta+Up"
        onActivated: {
            moveActiveWindowUp();
        }
    }

    ShortcutHandler {
        name: "KZones: Move active window down"
        text: "KZones: Move active window down"
        sequence: "Meta+Down"
        onActivated: {
            moveActiveWindowDown();
        }
    }

    ShortcutHandler {
        name: "KZones: Move active window left"
        text: "KZones: Move active window left"
        sequence: "Meta+Left"
        onActivated: {
            moveActiveWindowLeft();
        }
    }

    ShortcutHandler {
        name: "KZones: Move active window right"
        text: "KZones: Move active window right"
        sequence: "Meta+Right"
        onActivated: {
            moveActiveWindowRight();
        }
    }

    ShortcutHandler {
        name: "KZones: Snap active window"
        text: "KZones: Snap active window"
        sequence: "Meta+Shift+Space"
        onActivated: {
            snapActiveWindow();
        }
    }

    ShortcutHandler {
        name: "KZones: Snap all windows"
        text: "KZones: Snap all windows"
        sequence: "Meta+Space"
        onActivated: {
            snapAllWindows();
        }
    }

}
