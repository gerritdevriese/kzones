import QtQuick
import QtQuick.Layouts
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
    property var errors: []

    location: PlasmaCore.Types.Floating
    type: PlasmaCore.Dialog.OnScreenDisplay
    backgroundHints: PlasmaCore.Types.NoBackground
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
    visible: false
    outputOnly: true
    opacity: 1
    width: displaySize.width
    height: displaySize.height

    function loadConfig() {

        const defaultLayouts = '[{"name":"Priority Grid","padding":0,"zones":[{"x":0,"y":0,"height":100,"width":25},{"x":25,"y":0,"height":100,"width":50},{"x":75,"y":0,"height":100,"width":25}]},{"name":"Quadrant Grid","zones":[{"x":0,"y":0,"height":50,"width":50},{"x":0,"y":50,"height":50,"width":50},{"x":50,"y":50,"height":50,"width":50},{"x":50,"y":0,"height":50,"width":50}]}]'

        let layouts;

        try {
            layouts = JSON.parse(KWin.readConfig("layoutsJson", defaultLayouts));
        } catch (e) {
            errors = errors.concat(`Could not load layouts from configuration, using default layouts.\nError: ${e.message}`);
            layouts = JSON.parse(defaultLayouts);
        }

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
            // track active layout per screen
            trackLayoutPerScreen: KWin.readConfig("trackLayoutPerScreen", false),
            // show osd messages
            showOsdMessages: KWin.readConfig("showOsdMessages", true),
            // fade windows while moving
            fadeWindowsWhileMoving: KWin.readConfig("fadeWindowsWhileMoving", false),
            // auto snap all windows
            autoSnapAllNew: KWin.readConfig("autoSnapAllNew", false),
            // layouts
            layouts: layouts,
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
        zoneSelector.expanded = false;
        zoneSelector.near = false;
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

        if (!client) return false;
        if (!client.normalWindow) return false;
        if (client.popupWindow) return false;
        if (client.skipTaskbar) return false;

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

        refreshClientArea();

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
            if (client.zone === zone && client.layout === layout && client.desktop === Workspace.currentDesktop && client.activity === Workspace.currentActivity && client.screen === Workspace.activeWindow.screen && checkFilter(client)) {
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
        if (!checkFilter(client)) return;

        log("Moving client " + client.resourceClass.toString() + " to zone " + zone);

        refreshClientArea()
        saveClientProperties(client, zone);

        // move client to zone
        if (zone != -1) {
            const zoneItem = zones.repeater.itemAt(zone);
            const itemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0));
            const newGeometry = Qt.rect(Math.round(itemGlobal.x), Math.round(itemGlobal.y), Math.round(zoneItem.width), Math.round(zoneItem.height));
            log("Moving client " + client.resourceClass.toString() + " to zone " + zone + " with geometry " + JSON.stringify(newGeometry));
            client.setMaximize(false, false);
            client.frameGeometry = newGeometry;
        }
    }

    function saveClientProperties(client, zone) {
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
        if (!checkFilter(client)) return null;

        log("Moving client " + client.resourceClass.toString() + " to closest zone");

        refreshClientArea();

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

    function findClientToSpecularZone(client, isHorizontal=false) {
        if (!checkFilter(client)) return null;
        refreshClientArea();
        const centerPointOfClient = {
            x: client.frameGeometry.x + (client.frameGeometry.width / 2),
            y: client.frameGeometry.y + (client.frameGeometry.height / 2)
        };
        const zones = config.layouts[currentLayout].zones;
        let currentZoneIndex = null;
        let closestDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            let zoneCenter = {
                x: (zone.x + zone.width / 2) / 100 * clientArea.width + clientArea.x,
                y: (zone.y + zone.height / 2) / 100 * clientArea.height + clientArea.y
            };
            const distance = Math.sqrt(
                Math.pow(centerPointOfClient.x - zoneCenter.x, 2) +
                Math.pow(centerPointOfClient.y - zoneCenter.y, 2)
            );
            if (distance < closestDistance) {
                currentZoneIndex = i;
                closestDistance = distance;
            }
        }
        if (currentZoneIndex === null) return null;
        const currentZone = zones[currentZoneIndex];
        const currentZoneCenter = {
            x: currentZone.x + currentZone.width / 2,
            y: currentZone.y + currentZone.height / 2
        };
        let specularZoneIndex = null;
        let minDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            if (i === currentZoneIndex) continue;
            const zone = zones[i];
            const zoneCenter = {
                x: zone.x + zone.width / 2,
                y: zone.y + zone.height / 2
            };
            let isSpecular = false;
            if (isHorizontal) {
                isSpecular = Math.abs(zoneCenter.x - currentZoneCenter.x) < 5 &&
                            Math.abs((zoneCenter.y - 50) - (50 - currentZoneCenter.y)) < 5;
            } else {
                isSpecular = Math.abs(zoneCenter.y - currentZoneCenter.y) < 5 &&
                            Math.abs((zoneCenter.x - 50) - (50 - currentZoneCenter.x)) < 5;
            }
            if (isSpecular) {
                const specularPoint = {
                    x: !isHorizontal ? (100 - currentZoneCenter.x) : currentZoneCenter.x,
                    y: isHorizontal ? (100 - currentZoneCenter.y) : currentZoneCenter.y
                };
                const distance = Math.sqrt(
                    Math.pow(zoneCenter.x - specularPoint.x, 2) +
                    Math.pow(zoneCenter.y - specularPoint.y, 2)
                );
                if (distance < minDistance) {
                    specularZoneIndex = i;
                    minDistance = distance;
                }
            }
        }
        return specularZoneIndex !== null ? specularZoneIndex : currentZoneIndex;
    }

    function moveAllClientsToClosestZone() {
        log("Moving all clients to closest zone");
        let count = 0;
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client.move) continue;
            moveClientToClosestZone(client) && count++;
        }
        log("Moved " + count + " clients to closest zone");
        return count;
    }

    function moveClientToNeighbour(client, direction) {
        if (!checkFilter(client)) return null;

        log("Moving client " + client.resourceClass.toString() + " to neighbour " + direction);

        refreshClientArea();

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
        } else {
            let specularZone = -1;
            switch (direction) {
                case "left":
                    specularZone = findClientToSpecularZone(client);
                    Workspace.slotWindowToPrevScreen();
                    moveClientToZone(client, specularZone);
                    break;
                case "right":
                    specularZone = findClientToSpecularZone(client);
                    Workspace.slotWindowToNextScreen();
                    moveClientToZone(client, specularZone);
                    break;
                case "up":
                    specularZone = findClientToSpecularZone(client, true);
                    Workspace.slotWindowToAboveScreen();
                    moveClientToZone(client, specularZone);
                    break;
                case "down":
                    specularZone = findClientToSpecularZone(client, true);
                    Workspace.slotWindowToBelowScreen();
                    moveClientToZone(client, specularZone);
                    break;
            }
        }
        return targetZoneIndex;
    }

    function getCurrentLayout() {
        if (config.trackLayoutPerScreen) {
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
        if (config.trackLayoutPerScreen) screenLayouts[Workspace.activeScreen.name] = layout
        currentLayout = layout
    }

    function connectSignals(client) {

        if (!checkFilter(client)) return;

        log("Connecting signals for client " + client.resourceClass.toString());

        client.onInteractiveMoveResizeStarted.connect(onInteractiveMoveResizeStarted);
        client.onInteractiveMoveResizeStepped.connect(onInteractiveMoveResizeStepped);
        client.onInteractiveMoveResizeFinished.connect(onInteractiveMoveResizeFinished);
        client.onFullScreenChanged.connect(onFullScreenChanged);

        function onInteractiveMoveResizeStarted() {
            log("Interactive move/resize started for client " + client.resourceClass.toString());
            if (client.resizeable && checkFilter(client)) {
                if (client.move && checkFilter(client)) {
                    cachedClientArea = clientArea;

                    if (config.fadeWindowsWhileMoving) {
                        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                            const client = Workspace.stackingOrder[i];
                            client.previousOpacity = client.opacity;
                            if (client.move ||!client.normalWindow) continue;
                            client.opacity = 0.5;
                        }
                    }

                    if (config.rememberWindowGeometries && client.zone != -1) {
                        if (client.oldGeometry) {
                            const geometry = client.oldGeometry;
                            const zone = config.layouts[client.layout].zones[client.zone];
                            const zoneCenterX = (zone.x + zone.width / 2) / 100 * cachedClientArea.width + cachedClientArea.x;
                            const zoneX = ((zone.x / 100) * cachedClientArea.width + cachedClientArea.x);
                            const newGeometry = Qt.rect(Math.round(Workspace.cursorPos.x - geometry.width / 2), Math.round(client.frameGeometry.y), Math.round(geometry.width), Math.round(geometry.height));
                            client.frameGeometry = newGeometry;
                        }
                    }

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

        function onInteractiveMoveResizeStepped() {
            if (client.resizeable) {
                if (moving && checkFilter(client)) {
                    moved = true;
                }
            }
        }

        function onInteractiveMoveResizeFinished() {
            log("Interactive move/resize finished for client " + client.resourceClass.toString());

            if (config.fadeWindowsWhileMoving) {
                for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                    const client = Workspace.stackingOrder[i];
                    client.opacity = client.previousOpacity || 1;
                }
            }

            if (moving) {
                log("Move end " + client.resourceClass.toString());
                if (moved) {
                    if (shown) {
                        moveClientToZone(client, highlightedZone);
                    } else {
                        saveClientProperties(client, -1);
                    }
                }
                hide();
            }
            moving = false;
            moved = false;
            resizing = false;
        }

        // fix from https://github.com/gerritdevriese/kzones/pull/25
        function onFullScreenChanged() {
            log("Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + client.fullScreen + ")");
            mainDialog.hide();
        }

    }

    Components.ColorHelper {
        id: colorHelper
    }

    Components.Shortcuts {
        onCycleLayouts: {
            setCurrentLayout((currentLayout + 1) % config.layouts.length);
            highlightedZone = -1;
            osdDbus.exec(config.trackLayoutPerScreen ? `${config.layouts[currentLayout].name} (${Workspace.activeScreen.name})` : config.layouts[currentLayout].name);
        }

        onCycleLayoutsReversed: {
            setCurrentLayout((currentLayout - 1 + config.layouts.length) % config.layouts.length);
            highlightedZone = -1;
            osdDbus.exec(config.trackLayoutPerScreen ? `${config.layouts[currentLayout].name} (${Workspace.activeScreen.name})` : config.layouts[currentLayout].name);
        }

        onMoveActiveWindowToNextZone: {
            const client = Workspace.activeWindow;
            if (client.zone == -1) moveClientToClosestZone(client);
            const zonesLength = config.layouts[currentLayout].zones.length;
            moveClientToZone(client, (client.zone + 1) % zonesLength);
        }

        onMoveActiveWindowToPreviousZone: {
            const client = Workspace.activeWindow;
            if (client.zone == -1) moveClientToClosestZone(client);
            const zonesLength = config.layouts[currentLayout].zones.length;
            moveClientToZone(client, (client.zone - 1 + zonesLength) % zonesLength);
        }

        onToggleZoneOverlay: {
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

        onSwitchToNextWindowInCurrentZone: {
            switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout);
        }

        onSwitchToPreviousWindowInCurrentZone: {
            switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout, true);
        }

        onMoveActiveWindowToZone: {
            moveClientToZone(Workspace.activeWindow, zone);
        }

        onActivateLayout: {
            if (layout <= config.layouts.length - 1) {
                setCurrentLayout(layout);
                highlightedZone = -1;
                osdDbus.exec(config.trackLayoutPerScreen ? `${config.layouts[currentLayout].name} (${Workspace.activeScreen.name})` : config.layouts[currentLayout].name);
            } else {
                osdDbus.exec(`Layout ${layout + 1} does not exist`);
            }
        }

        onMoveActiveWindowUp: {
            moveClientToNeighbour(Workspace.activeWindow, "up");
        }

        onMoveActiveWindowDown: {
            moveClientToNeighbour(Workspace.activeWindow, "down");
        }

        onMoveActiveWindowLeft: {
            moveClientToNeighbour(Workspace.activeWindow, "left");
        }

        onMoveActiveWindowRight: {
            moveClientToNeighbour(Workspace.activeWindow, "right");
        }

        onSnapActiveWindow: {
            moveClientToClosestZone(Workspace.activeWindow);
        }

        onSnapAllWindows: {
            moveAllClientsToClosestZone();
        }
    }

    Component.onCompleted: {
        // refresh client area
        refreshClientArea();
        mainDialog.loadConfig();

        // match all clients to zones and connect signals
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            matchZone(Workspace.stackingOrder[i]);
            connectSignals(Workspace.stackingOrder[i]);
        }
    }

    Item {
        id: mainItem

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
                if (config.enableZoneOverlay && showZoneOverlay && !zoneSelector.expanded) {
                    zones.repeater.model.forEach((zone, zoneIndex) => {
                        if (isHovering(zones.repeater.itemAt(zoneIndex).children[config.zoneOverlayHighlightTarget])) {
                            hoveringZone = zoneIndex;
                        }
                    });
                }

                // zone selector
                if (config.enableZoneSelector) {
                    if (!zoneSelector.animating && zoneSelector.expanded) {
                        zoneSelector.repeater.model.forEach((layout, layoutIndex) => {
                            const layoutItem = zoneSelector.repeater.itemAt(layoutIndex);
                            layout.zones.forEach((zone, zoneIndex) => {
                                const zoneItem = layoutItem.children[zoneIndex];
                                if (isHovering(zoneItem)) {
                                    hoveringZone = zoneIndex;
                                    setCurrentLayout(layoutIndex);
                                }
                            });
                        });
                    }
                    // set zoneSelector expansion state
                    zoneSelector.expanded = isHovering(zoneSelector) && (Workspace.cursorPos.y - clientArea.y) >= 0;
                    // set zoneSelector near state
                    const triggerDistance = config.zoneSelectorTriggerDistance * 50 + 25;
                    zoneSelector.near = (Workspace.cursorPos.y - clientArea.y) < zoneSelector.y + zoneSelector.height + triggerDistance;
                }

                // edge snapping
                if (config.enableEdgeSnapping) {
                    const triggerDistance = (config.edgeSnappingTriggerDistance + 1) * 10;
                    if (Workspace.cursorPos.x <= clientArea.x + triggerDistance || Workspace.cursorPos.x >= clientArea.x + clientArea.width - triggerDistance || Workspace.cursorPos.y <= clientArea.y + triggerDistance || Workspace.cursorPos.y >= clientArea.y + clientArea.height - triggerDistance) {
                        zones.repeater.model.forEach((zone, zoneIndex) => {
                            const zoneItem = zones.repeater.itemAt(zoneIndex);
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
                if (!config.showOsdMessages) return;
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

            Components.Debug {
                info: ({
                    activeWindow: {
                        caption: Workspace.activeWindow?.caption,
                        resourceClass: Workspace.activeWindow?.resourceClass?.toString(),
                        frameGeometry: {
                            x: Workspace.activeWindow?.frameGeometry?.x,
                            y: Workspace.activeWindow?.frameGeometry?.y,
                            width: Workspace.activeWindow?.frameGeometry?.width,
                            height: Workspace.activeWindow?.frameGeometry?.height
                        },
                        zone: Workspace.activeWindow?.zone
                    },
                    highlightedZone: highlightedZone,
                    moving: moving,
                    resizing: resizing,
                    oldGeometry: Workspace.activeWindow?.oldGeometry,
                    activeScreen: activeScreen?.name,
                    currentLayout: currentLayout,
                    screenLayouts: screenLayouts
                })
                errors: mainDialog.errors
                config: mainDialog.config
            }

            Components.Zones {
                id: zones
                config: mainDialog.config
                currentLayout: mainDialog.currentLayout
                highlightedZone: mainDialog.highlightedZone
             }

            Components.Selector {
                id: zoneSelector
                config: mainDialog.config
                currentLayout: mainDialog.currentLayout
                highlightedZone: mainDialog.highlightedZone
            }
        }

        // workspace connection
        Connections {
            target: Workspace

            function onWindowAdded(client) {

                connectSignals(client);

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
