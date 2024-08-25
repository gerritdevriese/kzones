import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kwin
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import "components" as Components

PlasmaCore.Dialog {

    // api documentation
    // https://api.kde.org/frameworks/plasma-framework/html/classPlasmaQuick_1_1Dialog.html
    // https://api.kde.org/frameworks/plasma-framework/html/classPlasma_1_1Types.html
    // https://develop.kde.org/docs/getting-started/kirigami/style-colors/

    id: mainDialog

    // properties
    property bool shown: false
    property bool moving: false
    property bool moved: false
    property bool resizing: false
    property var clientArea: ({})
    property var cachedClientArea: ({})
    property var displaySize: ({})
    property int currentLayout: 0
    property var screenLayouts: ({})
    property int highlightedZone: -1
    property var activeScreen: null
    property var config: ({})
    property bool showZoneOverlay: config.zoneOverlayShowWhen == 0

    location: PlasmaCore.Types.Floating
    type: PlasmaCore.Dialog.OnScreenDisplay
    backgroundHints: PlasmaCore.Types.NoBackground
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Popup
    Kirigami.Theme.colorSet: Kirigami.Theme.View
    visible: false
    outputOnly: true
    opacity: 1
    width: displaySize.width
    height: displaySize.height

    function loadConfig() {

        // load values from configuration
        config = {
            // enable zone selector
            enableZoneSelector: KWin.readConfig("enableZoneSelector", true),
            // distance from the top of the screen to trigger the zone selector
            zoneSelectorTriggerDistance: KWin.readConfig("zoneSelectorTriggerDistance", 1),
            // enable zone overlay
            enableZoneOverlay: KWin.readConfig("enableZoneOverlay", true),
            // show zone overlay when
            zoneOverlayShowWhen: KWin.readConfig("zoneOverlayShowWhen", 0),
            // highlight target zone
            zoneOverlayHighlightTarget: KWin.readConfig("zoneOverlayHighlightTarget", 0),
            // zone overlay indicator display
            zoneOverlayIndicatorDisplay: KWin.readConfig("zoneOverlayIndicatorDisplay", 0),
            // enable edge snapping
            enableEdgeSnapping: KWin.readConfig("enableEdgeSnapping", false),
            // distance from the edge of the screen to trigger the edge snapping
            edgeSnappingTriggerDistance: KWin.readConfig("edgeSnappingTriggerDistance", 1),
            // remember window geometries before snapping to a zone, and restore them when the window is removed from their zone
            rememberWindowGeometries: KWin.readConfig("rememberWindowGeometries", true),
            // layout per monitor
            layoutPerMonitor: KWin.readConfig("layoutPerMonitor", false),
            // auto snap all windows
            autoSnapAllNew: KWin.readConfig("autoSnapAllNew", false),
            // layouts
            layouts: JSON.parse(KWin.readConfig("layoutsJson", '[{"name":"Priority Grid","padding":0,"zones":[{"x":0,"y":0,"height":100,"width":25},{"x":25,"y":0,"height":100,"width":50},{"x":75,"y":0,"height":100,"width":25}]},{"name":"Quadrant Grid","zones":[{"x":0,"y":0,"height":50,"width":50},{"x":0,"y":50,"height":50,"width":50},{"x":50,"y":50,"height":50,"width":50},{"x":50,"y":0,"height":50,"width":50}]}]')),
            // filter mode
            filterMode: KWin.readConfig("filterMode", 0),
            // filter list
            filterList: KWin.readConfig("filterList", ""),
            // polling rate in milliseconds
            pollingRate: KWin.readConfig("pollingRate", 100),
            // enable debug logging
            enableDebugLogging: KWin.readConfig("enableDebugLogging", false),
            // enable debug overlay
            enableDebugOverlay: KWin.readConfig("enableDebugOverlay", false)
        };
        log("Config loaded: " + JSON.stringify(config));
    }

    function log(message) {
        if (!config.enableDebugLogging) return;
        console.log("KZones: " + message);
    }

    function show() {
        // show OSD
        mainDialog.shown = true;
        mainDialog.visible = true;
        refreshClientArea();
    }

    function hide() {
        // hide OSD
        mainDialog.shown = false;
        mainDialog.visible = false;
        zoneSelectorBackground.expanded = false;
        zoneSelectorBackground.near = false;
        highlightedZone = -1;
        showZoneOverlay = config.zoneOverlayShowWhen == 0;
    }

    function refreshClientArea() {
        activeScreen = Workspace.activeScreen;
        clientArea = Workspace.clientArea(KWin.FullScreenArea, activeScreen, Workspace.currentDesktop);
        displaySize = Workspace.virtualScreenSize;
        currentLayout = getCurrentLayout();
    }

    function isPointInside(x, y, geometry) {
        return x >= geometry.x && x <= geometry.x + geometry.width && y >= geometry.y && y <= geometry.y + geometry.height;
    }

    function isHovering(item) {
        const itemGlobal = item.mapToGlobal(Qt.point(0, 0));
        return isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, {
            x: itemGlobal.x,
            y: itemGlobal.y,
            width: item.width * item.scale,
            height: item.height * item.scale
        });
    }

    function checkFilter(client) {
        const filter = config.filterList.split(/\r?\n/);
        if (config.filterList.length > 0) {
            if (config.filterMode == 0) {
                // include
                return filter.includes(client.resourceClass.toString());
            }
            if (config.filterMode == 1) {
                // exclude
                return !filter.includes(client.resourceClass.toString());
            }
        }
        return true;
    }

    function matchZone(client) {
        client.zone = -1;
        // get all zones in the current layout
        const zones = config.layouts[currentLayout].zones;
        // loop through zones and compare with the geometries of the client
        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            const zonePadding = config.layouts[currentLayout].padding || 0;
            const zoneX = ((zone.x / 100) * (clientArea.width - zonePadding)) + zonePadding;
            const zoneY = ((zone.y / 100) * (clientArea.height - zonePadding)) + zonePadding;
            const zoneWidth = ((zone.width / 100) * (clientArea.width - zonePadding)) - zonePadding;
            const zoneHeight = ((zone.height / 100) * (clientArea.height - zonePadding)) - zonePadding;
            if (client.frameGeometry.x == zoneX && client.frameGeometry.y == zoneY && client.frameGeometry.width == zoneWidth && client.frameGeometry.height == zoneHeight) {
                // zone found, set it and exit the loop
                client.zone = i;
                client.zone = currentLayout;
                break;
            }
        }
    }

    function getWindowsInZone(zone, layout) {
        const windows = [];
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client.zone === zone && client.layout === layout && client.desktop === Workspace.currentDesktop && client.activity === Workspace.currentActivity && client.screen === Workspace.activeWindow.screen && client.normalWindow) {
                windows.push(client);
            }
        }
        return windows;
    }

    function switchWindowInZone(zone, layout, reverse) {
        const clientsInZone = getWindowsInZone(zone, layout);
        if (reverse) clientsInZone.reverse();
        

        // cycle through clients in zone
        if (clientsInZone.length > 0) {
            const index = clientsInZone.indexOf(Workspace.activeWindow);
            if (index === -1) {
                Workspace.activeWindow = clientsInZone[0];
            } else {
                Workspace.activeWindow = clientsInZone[(index + 1) % clientsInZone.length];
            }
        }
    }

    function moveClientToZone(client, zone) {
        // block abnormal windows from being moved (like plasmashell, docks, etc...)
        if (!client.normalWindow || !checkFilter(client)) return;
        log("Moving client " + client.resourceClass.toString() + " to zone " + zone);
        clientArea = Workspace.clientArea(KWin.FullScreenArea, client.output, Workspace.currentDesktop);
        saveWindowGeometries(client, zone);

        // move client to zone
        if (zone != -1) {
            const zoneItem = repeaterZones.itemAt(zone);
            const itemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0));
            const newGeometry = Qt.rect(Math.round(itemGlobal.x), Math.round(itemGlobal.y), Math.round(zoneItem.width), Math.round(zoneItem.height));
            log("Moving client " + client.resourceClass.toString() + " to zone " + zone + " with geometry " + JSON.stringify(newGeometry));
            client.setMaximize(false, false);
            client.frameGeometry = newGeometry;
        }
    }

    function saveWindowGeometries(client, zone) {
        log("Saving geometry for client " + client.resourceClass.toString());

        // save current geometry
        if (config.rememberWindowGeometries) {
            const geometry = {
                "x": client.frameGeometry.x,
                "y": client.frameGeometry.y,
                "width": client.frameGeometry.width,
                "height": client.frameGeometry.height
            };
            if (zone != -1) {
                if (client.zone == -1) {
                    client.oldGeometry = geometry;
                }
            }
        }

        // save zone
        client.zone = zone;
        client.layout = currentLayout;
        client.desktop = Workspace.currentDesktop;
        client.activity = Workspace.currentActivity;
    }

    function moveClientToClosestZone(client) {
        if (!client.normalWindow || !checkFilter(client)) return null;

        log("Moving client " + client.resourceClass.toString() + " to closest zone");

        const centerPointOfClient = {
            x: client.frameGeometry.x + (client.frameGeometry.width / 2),
            y: client.frameGeometry.y + (client.frameGeometry.height / 2)
        };

        const zones = config.layouts[currentLayout].zones;
        let closestZone = null;
        let closestDistance = Infinity;

        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            const zoneCenter = {
                x: (zone.x + zone.width / 2) / 100 * clientArea.width + clientArea.x,
                y: (zone.y + zone.height / 2) / 100 * clientArea.height + clientArea.y
            };
            const distance = Math.sqrt(Math.pow(centerPointOfClient.x - zoneCenter.x, 2) + Math.pow(centerPointOfClient.y - zoneCenter.y, 2));
            if (distance < closestDistance) {
                closestZone = i;
                closestDistance = distance;
            }
        }

        if (client.zone !== closestZone || client.layout !== currentLayout) moveClientToZone(client, closestZone);
        return closestZone;
    }

    function moveAllClientsToClosestZone() {
        log("Moving all clients to closest zone");
        let count = 0;
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            moveClientToClosestZone(client) && count++;
        }
        log("Moved " + count + " clients to closest zone");
        return count;
    }

    function moveClientToNeighbour(client, direction) {
        if (!client.normalWindow || !checkFilter(client)) return null;
        
        log("Moving client " + client.resourceClass.toString() + " to neighbour " + direction);

        const zones = config.layouts[currentLayout].zones;

        if (client.zone === -1 || client.layout !== currentLayout) moveClientToClosestZone(client);

        const currentZone = zones[client.zone];
        let targetZoneIndex = -1;

        let minDistance = Infinity;

        for (let i = 0; i < zones.length; i++) {
            if (i === client.zone) continue;

            const zone = zones[i];
            let isNeighbour = false;
            let distance = Infinity;

            switch (direction) {
                case "left":
                    if (zone.x + zone.width <= currentZone.x && 
                        zone.y < currentZone.y + currentZone.height && 
                        zone.y + zone.height > currentZone.y) {
                        isNeighbour = true;
                        distance = currentZone.x - (zone.x + zone.width);
                    }
                    break;
                case "right":
                    if (zone.x >= currentZone.x + currentZone.width && 
                        zone.y < currentZone.y + currentZone.height && 
                        zone.y + zone.height > currentZone.y) {
                        isNeighbour = true;
                        distance = zone.x - (currentZone.x + currentZone.width);
                    }
                    break;
                case "up":
                    if (zone.y + zone.height <= currentZone.y && 
                        zone.x < currentZone.x + currentZone.width && 
                        zone.x + zone.width > currentZone.x) {
                        isNeighbour = true;
                        distance = currentZone.y - (zone.y + zone.height);
                    }
                    break;
                case "down":
                    if (zone.y >= currentZone.y + currentZone.height && 
                        zone.x < currentZone.x + currentZone.width && 
                        zone.x + zone.width > currentZone.x) {
                        isNeighbour = true;
                        distance = zone.y - (currentZone.y + currentZone.height);
                    }
                    break;
            }

            if (isNeighbour && distance < minDistance) {
                minDistance = distance;
                targetZoneIndex = i;
            }
        }

        if (targetZoneIndex !== -1) {
            moveClientToZone(client, targetZoneIndex);
        }

        return targetZoneIndex;
    }

    function getCurrentLayout() {
        if (config.layoutPerMonitor) {
            const screenLayout = screenLayouts[Workspace.activeScreen.name]
            if (!screenLayout) {
                screenLayouts[Workspace.activeScreen.name] = 0
            }
            return screenLayouts[Workspace.activeScreen.name];
        } else {
            return currentLayout;
        }
    }

    function setCurrentLayout(layout) {
        if (config.layoutPerMonitor) screenLayouts[Workspace.activeScreen.name] = layout
        currentLayout = layout
    }


    Item {
        id: shortcuts

        ShortcutHandler {
            name: "KZones: Cycle layouts"
            text: "KZones: Cycle layouts"
            sequence: "Ctrl+Alt+D"
            onActivated: {
                setCurrentLayout((currentLayout + 1) % config.layouts.length);

                highlightedZone = -1;
                osdDbus.exec(config.layouts[currentLayout].name);
            }
        }

        ShortcutHandler {
            name: "KZones: Cycle layouts (reversed)"
            text: "KZones: Cycle layouts (reversed)"
            sequence: "Ctrl+Alt+Shift+D"
            onActivated: {
                setCurrentLayout((currentLayout - 1 + config.layouts.length) % config.layouts.length);
                highlightedZone = -1;
                osdDbus.exec(config.layouts[currentLayout].name);
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to next zone"
            text: "KZones: Move active window to next zone"
            sequence: "Ctrl+Alt+Right"
            onActivated: {
                const client = Workspace.activeWindow;
                if (client.zone == -1) moveClientToClosestZone(client);
                const zonesLength = config.layouts[currentLayout].zones.length;
                moveClientToZone(client, (client.zone + 1) % zonesLength);
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to previous zone"
            text: "KZones: Move active window to previous zone"
            sequence: "Ctrl+Alt+Left"
            onActivated: {
                const client = Workspace.activeWindow;
                if (client.zone == -1) moveClientToClosestZone(client);
                const zonesLength = config.layouts[currentLayout].zones.length;
                moveClientToZone(client, (client.zone - 1 + zonesLength) % zonesLength);
            }
        }

        ShortcutHandler {
            name: "KZones: Toggle zone overlay"
            text: "KZones: Toggle zone overlay"
            sequence: "Ctrl+Alt+C"
            onActivated: {
                if (!config.enableZoneOverlay) {
                    osdDbus.exec("Zone overlay is disabled");
                }
                else if (moving) {
                    showZoneOverlay = !showZoneOverlay;
                }
                else {
                    osdDbus.exec("The overlay can only be shown while moving a window");
                }
            }
        }

        ShortcutHandler {
            name: "KZones: Switch to next window in current zone"
            text: "KZones: Switch to next window in current zone"
            sequence: "Ctrl+Alt+Up"
            onActivated: {
                switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout);
            }
        }

        ShortcutHandler {
            name: "KZones: Switch to previous window in current zone"
            text: "KZones: Switch to previous window in current zone"
            sequence: "Ctrl+Alt+Down"
            onActivated: {
                switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout, true);
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
                        moveClientToZone(Workspace.activeWindow, modelData - 1);
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
                        if (modelData <= config.layouts.length) {
                            setCurrentLayout(modelData - 1)
                            highlightedZone = -1;
                            osdDbus.exec(config.layouts[currentLayout].name);
                        } else {
                            osdDbus.exec("Layout " + modelData + " does not exist");
                        }
                    }
                }
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window up"
            text: "KZones: Move active window up"
            sequence: "Meta+Up"
            onActivated: {
                moveClientToNeighbour(Workspace.activeWindow, "up");
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window down"
            text: "KZones: Move active window down"
            sequence: "Meta+Down"
            onActivated: {
                moveClientToNeighbour(Workspace.activeWindow, "down");
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window left"
            text: "KZones: Move active window left"
            sequence: "Meta+Left"
            onActivated: {
                moveClientToNeighbour(Workspace.activeWindow, "left");
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window right"
            text: "KZones: Move active window right"
            sequence: "Meta+Right"
            onActivated: {
                moveClientToNeighbour(Workspace.activeWindow, "right");
            }
        }

        ShortcutHandler {
            name: "KZones: Snap active window"
            text: "KZones: Snap active window"
            sequence: "Meta+Shift+Space"
            onActivated: {
                moveClientToClosestZone(Workspace.activeWindow);
            }
        }

        ShortcutHandler {
            name: "KZones: Snap all windows"
            text: "KZones: Snap all windows"
            sequence: "Meta+Space"
            onActivated: {
                moveAllClientsToClosestZone();
            }
        }
    }

    Component.onCompleted: {
        // refresh client area
        refreshClientArea();
        mainDialog.loadConfig();

        // match all clients to zones
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            matchZone(Workspace.stackingOrder[i]);
        }
    }

    Rectangle {
        id: mainItem

        anchors.fill: parent

        color: "transparent"
        border.width: config.enableDebugOverlay ? 1 : 0
        border.color: config.enableDebugOverlay ? Kirigami.Theme.hoverColor : "transparent"

        // main polling timer
        Timer {
            id: timer

            triggeredOnStart: true
            interval: config.pollingRate
            running: shown && moving
            repeat: true

            onTriggered: {
                refreshClientArea();

                let hoveringZone = -1;

                // zone overlay
                if (config.enableZoneOverlay && showZoneOverlay && !zoneSelectorBackground.expanded) {
                    repeaterZones.model.forEach((zone, zoneIndex) => {
                        if (isHovering(repeaterZones.itemAt(zoneIndex).children[config.zoneOverlayHighlightTarget])) {
                            hoveringZone = zoneIndex;
                        }
                    });
                }

                // zone selector
                if (config.enableZoneSelector) {
                    if (!zoneSelectorBackground.animating && zoneSelectorBackground.expanded) {
                        repeaterLayouts.model.forEach((layout, layoutIndex) => {
                            const layoutItem = repeaterLayouts.itemAt(layoutIndex);
                            layout.zones.forEach((zone, zoneIndex) => {
                                const zoneItem = layoutItem.children[zoneIndex];
                                if (isHovering(zoneItem)) {
                                    hoveringZone = zoneIndex;
                                    setCurrentLayout(layoutIndex);
                                }
                            });
                        });
                    }
                    // set zoneSelectorBackground expansion state
                    zoneSelectorBackground.expanded = isHovering(zoneSelectorBackground) && (Workspace.cursorPos.y - clientArea.y) >= 0;
                    // set zoneSelectorBackground near state
                    const triggerDistance = config.zoneSelectorTriggerDistance * 50 + 25;
                    zoneSelectorBackground.near = (Workspace.cursorPos.y - clientArea.y) < zoneSelectorBackground.y + zoneSelectorBackground.height + triggerDistance;
                }

                // edge snapping
                if (config.enableEdgeSnapping) {
                    const triggerDistance = (config.edgeSnappingTriggerDistance + 1) * 10;
                    if (Workspace.cursorPos.x <= clientArea.x + triggerDistance || Workspace.cursorPos.x >= clientArea.x + clientArea.width - triggerDistance || Workspace.cursorPos.y <= clientArea.y + triggerDistance || Workspace.cursorPos.y >= clientArea.y + clientArea.height - triggerDistance) {
                        repeaterZones.model.forEach((zone, zoneIndex) => {
                            const zoneItem = repeaterZones.itemAt(zoneIndex);
                            const itemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0));
                            const zoneGeometry = {
                                x: itemGlobal.x,
                                y: itemGlobal.y,
                                width: zoneItem.width,
                                height: zoneItem.height
                            };
                            if (isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, zoneGeometry)) {
                                hoveringZone = zoneIndex;
                            }
                        });
                    }
                }

                // if hovering zone changed from the last frame
                if (hoveringZone != highlightedZone) {
                    log("Highlighting zone " + hoveringZone + " in layout " + currentLayout);
                    highlightedZone = hoveringZone;
                }

                
            }
        }

        DBusCall {
            id: osdDbus

            service: "org.kde.plasmashell"
            path: "/org/kde/osdService"
            method: "showText"

            function exec(text, icon = "preferences-desktop-virtual") {
                this.arguments = [icon, text];
                this.call();
            }
        }

        Item {
            x: clientArea.x || 0
            y: clientArea.y || 0
            width: clientArea.width || 0
            height: clientArea.height || 0
            clip: true

            // debug overlay
            Rectangle {
                id: debugOverlay

                visible: config.enableDebugOverlay
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.top: parent.top
                anchors.topMargin: 20
                z: 100
                width: debugOverlayText.paintedWidth + debugOverlayText.padding * 2
                height: debugOverlayText.paintedHeight + debugOverlayText.padding * 2
                radius: 5
                color: Kirigami.Theme.backgroundColor

                Text {
                    id: debugOverlayText

                    anchors.fill: parent
                    padding: 15
                    color: Kirigami.Theme.textColor
                    text: {
                        if (config.enableDebugOverlay) {
                            let t = "";
                            t += `Active: ${Workspace.activeWindow?.caption}\n`;
                            t += `Window class: ${Workspace.activeWindow?.resourceClass?.toString()}\n`;
                            t += `X: ${Workspace.activeWindow?.frameGeometry?.x}, Y: ${Workspace.activeWindow?.frameGeometry?.y}, Width: ${Workspace.activeWindow?.frameGeometry?.width}, Height: ${Workspace.activeWindow?.frameGeometry?.height}\n`;
                            t += `Previous Zone: ${Workspace.activeWindow?.zone}\n`;
                            t += `Highlighted Zone: ${highlightedZone}\n`;
                            t += `Polling Rate: ${config?.pollingRate}ms\n`;
                            t += `Moving: ${moving}\n`;
                            t += `Resizing: ${resizing}\n`;
                            t += `Old Geometry: ${JSON.stringify(Workspace.activeWindow?.oldGeometry)}\n`;
                            t += `Active Screen: ${activeScreen.name}\n`;
                            t += `Current layout: ${currentLayout}\n`;
                            t += `Screen layouts: ${JSON.stringify(screenLayouts, null, 4)}\n`;
                            return t;
                        } else {
                            return "";
                        }
                    }
                    font.pixelSize: 14
                    font.family: "Hack"
                }
            }

            // zones
            Repeater {
                id: repeaterZones

                model: config.layouts[currentLayout].zones

                // zone
                Item {
                    id: zone

                    property int zoneIndex: index
                    property int zonePadding: config.layouts[currentLayout].padding || 0
                    property var renderZones: config.zoneOverlayIndicatorDisplay == 1 ? [config.layouts[currentLayout].zones[index]] : config.layouts[currentLayout].zones
                    property int activeIndex: config.zoneOverlayIndicatorDisplay == 1 ? 0 : index

                    x: ((modelData.x / 100) * (clientArea.width - zonePadding)) + zonePadding
                    y: ((modelData.y / 100) * (clientArea.height - zonePadding)) + zonePadding
                    implicitWidth: ((modelData.width / 100) * (clientArea.width - zonePadding)) - zonePadding
                    implicitHeight: ((modelData.height / 100) * (clientArea.height - zonePadding)) - zonePadding

                    // zone indicator
                    Rectangle {
                        id: zoneIndicator

                        width: 160
                        height: 100
                        color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Qt.rgba(0, 0, 0), 0.1)
                        radius: 10
                        border.color: Kirigami.ColorUtils.tintWithAlpha(color, Kirigami.Theme.textColor, 0.2)
                        border.width: 1
                        anchors.centerIn: parent
                        opacity: !showZoneOverlay ? 0 : (zoneSelectorBackground.expanded) ? 0 : (highlightedZone == zoneIndex ? 0.6 : 1)
                        scale: highlightedZone == zoneIndex ? 1.1 : 1
                        visible: config.enableZoneOverlay

                        Behavior on scale {
                            NumberAnimation {
                                duration: zoneSelectorBackground.expanded ? 0 : 150
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }

                        Components.Indicator {
                            zones: renderZones
                            activeZone: activeIndex
                            anchors.centerIn: parent
                            width: parent.width - 20
                            height: parent.height - 20
                            hovering: (highlightedZone == zoneIndex)
                        }
                    }

                    // zone background
                    Rectangle {
                        id: zoneBackground

                        anchors.fill: parent
                        color: (highlightedZone == zoneIndex) ? Qt.rgba(Kirigami.Theme.hoverColor.r, Kirigami.Theme.hoverColor.g, Kirigami.Theme.hoverColor.b, 0.1) : "transparent"
                        border.color: (highlightedZone == zoneIndex) ? Kirigami.Theme.hoverColor : "transparent"
                        border.width: 3
                        radius: 8
                    }

                    // indicator shadow
                    Components.Shadow {
                        target: zoneIndicator
                        visible: zoneIndicator.visible
                    }
                }
            }

            // zone selector
            Item {
                id: zoneSelectorBackground

                property bool expanded: false
                property bool near: false
                property bool animating: false

                visible: false
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: expanded ? 0 : (near ? -height + 30 : -height)

                Behavior on anchors.topMargin {
                    NumberAnimation {
                        duration: 150
                        onRunningChanged: {
                            if (!running) zoneSelectorBackground.visible = true;
                            zoneSelectorBackground.animating = running;
                        }
                    }
                }

                width: zoneSelector.width + 30
                height: zoneSelector.height + 40

                Rectangle {
                    id: zoneSelector

                    width: row.implicitWidth + row.spacing * 2
                    height: row.implicitHeight + row.spacing * 2
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 15
                    color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Qt.rgba(0, 0, 0), 0.1)
                    radius: 10
                    border.color: Kirigami.ColorUtils.tintWithAlpha(color, Kirigami.Theme.textColor, 0.2)
                    border.width: 1

                    RowLayout {
                        id: row

                        spacing: 15
                        anchors.fill: parent
                        anchors.margins: spacing

                        Repeater {
                            id: repeaterLayouts

                            model: config.layouts

                            Components.Indicator {
                                zones: modelData.zones
                                activeZone: (currentLayout == index) ? highlightedZone : -1
                                width: 160 - 30
                                height: 100 - 30
                                hovering: (currentLayout == index)
                            }
                        }
                    }
                }

                Components.Shadow {
                    target: zoneSelector
                    visible: true
                }
            }
        }

        // workspace connection
        Connections {
            target: Workspace

            function onWindowAdded(client) {
                // check if client is in a zone application list
                config.layouts[currentLayout].zones.forEach((zone, zoneIndex) => {
                    if (zone.applications && zone.applications.includes(client.resourceClass.toString())) {
                        moveClientToZone(client, zoneIndex);
                        return;
                    }
                });

                // auto snap to closest zone
                if (config.autoSnapAllNew && checkFilter(client)) {
                    moveClientToClosestZone(client);
                }

                // check if new window spawns in a zone
                if (client.zone == undefined || client.zone == -1) matchZone(client);
                
            }

            // unused, but may be useful in the future
            // function onClientActivated(client) {
            //     if (client) {
            //         console.log("KZones: Client activated: " + client.resourceClass.toString() + " (zone " + client.zone + ")");
            //     }
            // }
            // function onVirtualScreenSizeChanged(){ }
        }

        // options connection
        Connections {
            //! not working at the moment
            target: Options

            function onConfigChanged() {
                log("Config changed");
                mainDialog.loadConfig();
            }
        }

        // activeWindow connection
        Connections {
            target: Workspace.activeWindow

            // fix from https://github.com/gerritdevriese/kzones/pull/25
            function onFullScreenChanged() {
                const client = Workspace.activeWindow;
                log("Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + client.fullScreen + ")");
                mainDialog.hide();
            }

            // start moving
            function onInteractiveMoveResizeStarted() {
                const client = Workspace.activeWindow;
                if (client.resizeable && client.normalWindow) {
                    if (client.move && checkFilter(client)) {
                        cachedClientArea = clientArea;
                        moving = true;
                        moved = false;
                        resizing = false;
                        log("Move start " + client.resourceClass.toString());
                        mainDialog.show();
                    }
                    if (client.resize) {
                        moving = false;
                        moved = false;
                        resizing = true;
                    }
                }
            }

            // is moving
            function onInteractiveMoveResizeStepped(r) {
                const client = Workspace.activeWindow;
                if (client.resizeable) {
                    if (moving && checkFilter(client)) {
                        moved = true;
                        if (config.rememberWindowGeometries && client.zone != -1) {
                            if (client.oldGeometry) {
                                const geometry = client.oldGeometry;
                                const zone = config.layouts[client.layout].zones[client.zone];
                                const zoneCenterX = (zone.x + zone.width / 2) / 100 * cachedClientArea.width + cachedClientArea.x;
                                const zoneX = ((zone.x / 100) * cachedClientArea.width + cachedClientArea.x);
                                const newGeometry = Qt.rect(Math.round((r.x - zoneX) + (zoneCenterX - geometry.width / 2)), Math.round(r.y), Math.round(geometry.width), Math.round(geometry.height));
                                client.frameGeometry = newGeometry;
                            }
                        }
                    }
                }
            }

            // stop moving
            function onInteractiveMoveResizeFinished() {
                const client = Workspace.activeWindow;
                if (moving) {
                    log("Move end " + client.resourceClass.toString());
                    if (moved) {
                        if (shown) {
                            moveClientToZone(client, highlightedZone);
                        } else {
                            saveWindowGeometries(client, -1);
                        }
                    }
                    hide();
                }
                moving = false;
                moved = false;
                resizing = false;
            }
        }

        // reusable timer
        Timer {
            id: delay

            function setTimeout(callback, timeout) {
                delay.interval = timeout;
                delay.repeat = false;
                delay.triggered.connect(callback);
                delay.triggered.connect(function release() {
                    delay.triggered.disconnect(callback);
                    delay.triggered.disconnect(release);
                });
                delay.start();
            }
        }
    }
}
