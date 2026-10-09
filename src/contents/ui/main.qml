import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kwin
import "../code/core.mjs" as Core
import "../code/utils.mjs" as Utils
import "../code/sticky.mjs" as Sticky
import "components" as Components

Item {
    id: root

    property var config: new Object()
    property bool moving: false
    property bool moved: false
    property bool resizing: false
    property var clientArea: new Object()
    property var cachedClientArea: new Object()
    property var displaySize: new Object()
    property int currentLayout: 0
    property var screenLayouts: new Object()
    property int highlightedZone: -1
    property var activeScreen: null
    property bool showZoneOverlay: config.zoneOverlayShowWhen == 0

    function isSnapAssistEnabled() {
        return config.enableSnapAssist !== false;
    }

    function refreshClientArea() {
        activeScreen = Workspace.activeScreen;
        clientArea = Workspace.clientArea(KWin.FullScreenArea, activeScreen, Workspace.currentDesktop);
        displaySize = Workspace.virtualScreenSize;
        currentLayout = getCurrentLayout();
    }

    function findMatchingZone(client, layoutIndex) {
        if (!client || !client.frameGeometry || !config.layouts[layoutIndex])
            return -1;

        const layout = config.layouts[layoutIndex];
        const zones = layout.zones || [];
        const zonePadding = layout.padding || 0;
        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            const zoneX = clientArea.x + ((zone.x / 100) * (clientArea.width - zonePadding)) + zonePadding;
            const zoneY = clientArea.y + ((zone.y / 100) * (clientArea.height - zonePadding)) + zonePadding;
            const zoneWidth = ((zone.width / 100) * (clientArea.width - zonePadding)) - zonePadding;
            const zoneHeight = ((zone.height / 100) * (clientArea.height - zonePadding)) - zonePadding;
            if (client.frameGeometry.x === Math.round(zoneX) && client.frameGeometry.y === Math.round(zoneY) && client.frameGeometry.width === Math.round(zoneWidth) && client.frameGeometry.height === Math.round(zoneHeight))
                return i;
        }
        return -1;
    }

    function matchZone(client) {
        refreshClientArea();
        client.zone = findMatchingZone(client, currentLayout);
        if (client.zone !== -1)
            client.layout = currentLayout;
    }

    function isClientOnScreen(c, screen) {
        if (!c || screen === undefined || screen === null)
            return true;

        const clientOutput = c.output !== undefined ? c.output : c.screen;
        if (clientOutput !== undefined && clientOutput !== null) {
            if (clientOutput === screen)
                return true;

            if (clientOutput.name && screen.name && clientOutput.name === screen.name)
                return true;

            if (typeof clientOutput === "number" && typeof screen === "number")
                return clientOutput === screen;
        }
        if (screen.geometry && c.frameGeometry) {
            const sg = screen.geometry;
            const cg = c.frameGeometry;
            const centerX = cg.x + cg.width / 2;
            const centerY = cg.y + cg.height / 2;
            return centerX >= sg.x && centerX < sg.x + sg.width && centerY >= sg.y && centerY < sg.y + sg.height;
        }
        return true;
    }

    function isSameScreen(c1, c2) {
        if (!c1 || !c2)
            return true;

        const o1 = c1.output !== undefined ? c1.output : c1.screen;
        const o2 = c2.output !== undefined ? c2.output : c2.screen;
        if (o1 !== undefined && o1 !== null && o2 !== undefined && o2 !== null) {
            if (o1 === o2)
                return true;

            if (o1.name && o2.name && o1.name === o2.name)
                return true;

            if (typeof o1 === "number" && typeof o2 === "number")
                return o1 === o2;

            return false;
        }
        return true;
    }

    function isClientOnCurrentDesktop(c) {
        if (!c)
            return false;

        if (c.onAllDesktops)
            return true;

        if (c.onCurrentDesktop !== undefined)
            return c.onCurrentDesktop;

        if (c.desktops && Workspace.currentDesktop) {
            for (let i = 0; i < c.desktops.length; i++) {
                if (c.desktops[i] === Workspace.currentDesktop || (c.desktops[i].id && c.desktops[i].id === Workspace.currentDesktop.id))
                    return true;

            }
            if (c.desktops.length > 0)
                return false;
        }
        if (c.desktop !== undefined && Workspace.currentDesktop !== undefined) {
            if (c.desktop === Workspace.currentDesktop || (c.desktop.id && c.desktop.id === Workspace.currentDesktop.id))
                return true;

            if (typeof c.desktop === "number" && typeof Workspace.currentDesktop === "number")
                return c.desktop === Workspace.currentDesktop;
        }
        return true;
    }

    function getWindowsInZone(zone, layout) {
        const windows = [];
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client.zone === zone && client.layout === layout && isClientOnCurrentDesktop(client) && client.activity === Workspace.currentActivity && isSameScreen(client, Workspace.activeWindow) && checkFilter(client))
                windows.push(client);

        }
        return windows;
    }

    function switchWindowInZone(zone, layout, reverse) {
        const clientsInZone = getWindowsInZone(zone, layout);
        if (reverse)
            clientsInZone.reverse();

        // cycle through clients in zone
        if (clientsInZone.length > 0) {
            const index = clientsInZone.indexOf(Workspace.activeWindow);
            if (index === -1)
                Workspace.activeWindow = clientsInZone[0];
            else
                Workspace.activeWindow = clientsInZone[(index + 1) % clientsInZone.length];
        }
    }

    function restoreWindowGeometry(client) {
        if (!checkFilter(client))
            return;

        if (config.rememberWindowGeometries && client.zone != -1 && client.oldGeometry) {
            Utils.log("Restoring geometry for client " + client.resourceClass.toString());
            client.frameGeometry = client.oldGeometry;
        }
    }

    function moveClientToZone(client, zone) {
        if (!checkFilter(client))
            return ;

        Utils.log("Moving client " + client.resourceClass.toString() + " to zone " + zone);
        refreshClientArea();
        saveClientProperties(client, zone);
        // move client to zone
        if (zone != -1) {
            const currentZones = repeaterLayout.itemAt(currentLayout);
            const zoneItem = currentZones.repeater.itemAt(zone);
            const itemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0));
            const newGeometry = Qt.rect(Math.round(itemGlobal.x), Math.round(itemGlobal.y), Math.round(zoneItem.width), Math.round(zoneItem.height));
            Utils.log("Moving client " + client.resourceClass.toString() + " to zone " + zone + " with geometry " + JSON.stringify(newGeometry));
            client.setMaximize(false, false);
            client.frameGeometry = newGeometry;
        }
    }

    function saveClientProperties(client, zone) {
        Utils.log("Saving geometry for client " + client.resourceClass.toString());
        // save current geometry
        if (config.rememberWindowGeometries) {
            const geometry = {
                "x": client.frameGeometry.x,
                "y": client.frameGeometry.y,
                "width": client.frameGeometry.width,
                "height": client.frameGeometry.height
            };
            if (zone != -1) {
                if (client.zone == -1)
                    client.oldGeometry = geometry;

            }
        }
        // save zone
        client.zone = zone;
        client.layout = currentLayout;
        client.desktop = Workspace.currentDesktop;
        client.activity = Workspace.currentActivity;
    }

    function triggerSnapAssist(layoutIndex, justFilledZone) {
        Utils.log("Snap Assist requested for layout " + layoutIndex + ", filled zone " + justFilledZone + ", enabled=" + isSnapAssistEnabled());
        if (!isSnapAssistEnabled()) {
            Utils.log("Snap Assist skipped: disabled in config");
            return;
        }

        refreshClientArea();
        if (!config.layouts || !config.layouts[layoutIndex]) {
            Utils.log("Snap Assist skipped: layout " + layoutIndex + " is unavailable");
            return;
        }

        const layout = config.layouts[layoutIndex];
        if (!layout.zones || layout.zones.length <= 1) {
            Utils.log("Snap Assist skipped: layout has fewer than two zones");
            return;
        }

        const occupiedZones = {};
        if (justFilledZone !== undefined && justFilledZone !== null && justFilledZone >= 0)
            occupiedZones[justFilledZone] = true;

        const allClients = Workspace.stackingOrder || Workspace.windows || [];
        for (let i = 0; i < allClients.length; i++) {
            const client = allClients[i];
            if (!client || !checkFilter(client) || client.minimized || client.fullScreen)
                continue;
            if (!isClientOnScreen(client, activeScreen))
                continue;
            if (!isClientOnCurrentDesktop(client))
                continue;

            const clientZone = findMatchingZone(client, layoutIndex);
            if (clientZone !== -1)
                occupiedZones[clientZone] = true;
        }

        const unoccupiedZones = [];
        for (let z = 0; z < layout.zones.length; z++) {
            if (!occupiedZones[z])
                unoccupiedZones.push(z);
        }

        if (unoccupiedZones.length === 0) {
            Utils.log("Snap Assist skipped: every zone is occupied");
            snapAssistDialog.hide();
            return;
        }

        const targetZoneIndex = unoccupiedZones[0];
        const zone = layout.zones[targetZoneIndex];
        const zonePadding = layout.padding || 0;

        const targetRect = Qt.rect(
            Math.round(clientArea.x + ((zone.x / 100) * (clientArea.width - zonePadding)) + zonePadding),
            Math.round(clientArea.y + ((zone.y / 100) * (clientArea.height - zonePadding)) + zonePadding),
            Math.round(((zone.width / 100) * (clientArea.width - zonePadding)) - zonePadding),
            Math.round(((zone.height / 100) * (clientArea.height - zonePadding)) - zonePadding)
        );

        const candidates = [];
        const excluded = {
            filter: 0,
            screen: 0,
            desktop: 0,
            fullscreen: 0,
            occupied: 0
        };
        for (let i = allClients.length - 1; i >= 0; i--) {
            const client = allClients[i];
            if (!client)
                continue;
            if (!checkFilter(client)) {
                excluded.filter++;
                continue;
            }
            if (!isClientOnScreen(client, activeScreen)) {
                excluded.screen++;
                continue;
            }
            if (!isClientOnCurrentDesktop(client)) {
                excluded.desktop++;
                continue;
            }
            if (client.fullScreen) {
                excluded.fullscreen++;
                continue;
            }

            const clientZone = findMatchingZone(client, layoutIndex);
            if (!client.minimized && clientZone !== -1 && occupiedZones[clientZone]) {
                excluded.occupied++;
                continue;
            }

            candidates.push(client);
        }

        Utils.log("Snap Assist candidates: " + candidates.length + " of " + allClients.length + " windows; excluded " + JSON.stringify(excluded) + "; target zone " + targetZoneIndex);
        if (candidates.length === 0) {
            Utils.log("Snap Assist skipped: no eligible candidate windows");
            snapAssistDialog.hide();
            return;
        }

        snapAssistItem.targetRect = targetRect;
        snapAssistItem.targetZoneIndex = targetZoneIndex;
        snapAssistItem.candidates = candidates;
        snapAssistDialog.show();
    }

    function moveClientToClosestZone(client) {
        if (!checkFilter(client))
            return null;

        Utils.log("Moving client " + client.resourceClass.toString() + " to closest zone");
        refreshClientArea();
        const centerPointOfClient = {
            "x": client.frameGeometry.x + (client.frameGeometry.width / 2),
            "y": client.frameGeometry.y + (client.frameGeometry.height / 2)
        };
        const zones = config.layouts[currentLayout].zones;
        let closestZone = null;
        let closestDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            const zoneCenter = {
                "x": (zone.x + zone.width / 2) / 100 * clientArea.width + clientArea.x,
                "y": (zone.y + zone.height / 2) / 100 * clientArea.height + clientArea.y
            };
            const distance = Math.sqrt(Math.pow(centerPointOfClient.x - zoneCenter.x, 2) + Math.pow(centerPointOfClient.y - zoneCenter.y, 2));
            if (distance < closestDistance) {
                closestZone = i;
                closestDistance = distance;
            }
        }
        if (client.zone !== closestZone || client.layout !== currentLayout)
            moveClientToZone(client, closestZone);

        return closestZone;
    }

    function findClientSpecularZone(client, isVerticalAxis = false) {
        if (!checkFilter(client))
            return null;

        refreshClientArea();
        const centerPointOfClient = {
            "x": client.frameGeometry.x + (client.frameGeometry.width / 2),
            "y": client.frameGeometry.y + (client.frameGeometry.height / 2)
        };
        const zones = config.layouts[currentLayout].zones;
        let currentZoneIndex = null;
        let closestDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            let zoneCenter = {
                "x": (zone.x + zone.width / 2) / 100 * clientArea.width + clientArea.x,
                "y": (zone.y + zone.height / 2) / 100 * clientArea.height + clientArea.y
            };
            const distance = Math.sqrt(Math.pow(centerPointOfClient.x - zoneCenter.x, 2) + Math.pow(centerPointOfClient.y - zoneCenter.y, 2));
            if (distance < closestDistance) {
                currentZoneIndex = i;
                closestDistance = distance;
            }
        }
        if (currentZoneIndex === null)
            return null;

        const currentZone = zones[currentZoneIndex];
        const currentZoneCenter = {
            "x": currentZone.x + currentZone.width / 2,
            "y": currentZone.y + currentZone.height / 2
        };
        let specularZoneIndex = null;
        let minDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            if (i === currentZoneIndex)
                continue;

            const zone = zones[i];
            const zoneCenter = {
                "x": zone.x + zone.width / 2,
                "y": zone.y + zone.height / 2
            };
            let isSpecular = false;
            if (isVerticalAxis)
                isSpecular = Math.abs(zoneCenter.x - currentZoneCenter.x) < 5 && Math.abs((zoneCenter.y - 50) - (50 - currentZoneCenter.y)) < 5;
            else
                isSpecular = Math.abs(zoneCenter.y - currentZoneCenter.y) < 5 && Math.abs((zoneCenter.x - 50) - (50 - currentZoneCenter.x)) < 5;
            if (isSpecular) {
                const specularPoint = {
                    "x": !isVerticalAxis ? (100 - currentZoneCenter.x) : currentZoneCenter.x,
                    "y": isVerticalAxis ? (100 - currentZoneCenter.y) : currentZoneCenter.y
                };
                const distance = Math.sqrt(Math.pow(zoneCenter.x - specularPoint.x, 2) + Math.pow(zoneCenter.y - specularPoint.y, 2));
                if (distance < minDistance) {
                    specularZoneIndex = i;
                    minDistance = distance;
                }
            }
        }
        return specularZoneIndex !== null ? specularZoneIndex : currentZoneIndex;
    }

    function moveAllClientsToClosestZone() {
        Utils.log("Moving all clients to closest zone");
        let count = 0;
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client.move)
                continue;

            moveClientToClosestZone(client) && count++;
        }
        Utils.log("Moved " + count + " clients to closest zone");
        return count;
    }

    function moveClientToNeighbour(client, direction) {
        if (!checkFilter(client))
            return null;

        Utils.log("Moving client " + client.resourceClass.toString() + " to neighbour " + direction);
        refreshClientArea();
        const zones = config.layouts[currentLayout].zones;
        if (client.zone === -1 || client.layout !== currentLayout) {
            moveClientToClosestZone(client);
            return client.zone;
        }
        const currentZone = zones[client.zone];
        let targetZoneIndex = -1;
        let minDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            if (i === client.zone)
                continue;

            const zone = zones[i];
            let isNeighbour = false;
            let distance = Infinity;
            switch (direction) {
            case "left":
                if (zone.x + zone.width <= currentZone.x && zone.y < currentZone.y + currentZone.height && zone.y + zone.height > currentZone.y) {
                    isNeighbour = true;
                    distance = currentZone.x - (zone.x + zone.width);
                }
                break;
            case "right":
                if (zone.x >= currentZone.x + currentZone.width && zone.y < currentZone.y + currentZone.height && zone.y + zone.height > currentZone.y) {
                    isNeighbour = true;
                    distance = zone.x - (currentZone.x + currentZone.width);
                }
                break;
            case "up":
                if (zone.y + zone.height <= currentZone.y && zone.x < currentZone.x + currentZone.width && zone.x + zone.width > currentZone.x) {
                    isNeighbour = true;
                    distance = currentZone.y - (zone.y + zone.height);
                }
                break;
            case "down":
                if (zone.y >= currentZone.y + currentZone.height && zone.x < currentZone.x + currentZone.width && zone.x + zone.width > currentZone.x) {
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
        } else if (!config.trackLayoutPerScreen) {
            const toScreenMap = {
                "left": "slotWindowToPrevScreen",
                "right": "slotWindowToNextScreen",
                "up": "slotWindowToAboveScreen",
                "down": "slotWindowToBelowScreen"
            };
            if (Workspace[toScreenMap[direction]]) {
                const isVerticalAxis = direction === "up" || direction === "down";
                const specularZone = findClientSpecularZone(client, isVerticalAxis);
                Workspace[toScreenMap[direction]]();
                moveClientToZone(client, specularZone);
            }
        }
        return targetZoneIndex;
    }

    function getLayoutKey() {
        const parts = [];
        if (config.trackLayoutPerScreen)
            parts.push(Workspace.activeScreen.name);

        if (config.trackLayoutPerDesktop)
            parts.push(Workspace.currentDesktop.id);

        return parts.join(':');
    }

    function getCurrentLayout() {
        if (config.trackLayoutPerScreen || config.trackLayoutPerDesktop) {
            const key = getLayoutKey();
            if (!screenLayouts[key])
                screenLayouts[key] = 0;

            return screenLayouts[key];
        }
        return currentLayout;
    }

    function setCurrentLayout(layout) {
        if (config.trackLayoutPerScreen || config.trackLayoutPerDesktop)
            screenLayouts[getLayoutKey()] = layout;

        currentLayout = layout;
    }

    function osdLayoutName() {
        const name = config.layouts[currentLayout].name;
        const parts = [];
        if (config.trackLayoutPerScreen)
            parts.push(Workspace.activeScreen.name);

        if (config.trackLayoutPerDesktop)
            parts.push(Workspace.currentDesktop.name);

        if (parts.length > 0)
            return `${name} (${parts.join(' / ')})`;

        return name;
    }

    function checkFilter(client) {
        // filter out abnormal windows like docks, panels, etc...
        if (!client)
            return false;

        if (!client.normalWindow)
            return false;

        if (client.popupWindow)
            return false;

        if (client.skipTaskbar)
            return false;

        // read filter from config and check if the client's resource class matches the filter
        const filter = config.filterList.split(/\r?\n/);
        if (config.filterList.length > 0) {
            if (config.filterMode == 0)
                return filter.includes(client.resourceClass.toString());

            if (config.filterMode == 1)
                return !filter.includes(client.resourceClass.toString());

        }
        return true;
    }

    function connectSignals(client) {
        function onInteractiveMoveResizeStarted() {
            Utils.log("Interactive move/resize started for client " + client.resourceClass.toString());
            snapAssistDialog.hide();
            if (client.resizeable && checkFilter(client)) {
                if (client.move && checkFilter(client)) {
                    cachedClientArea = clientArea;
                    if (config.fadeWindowsWhileMoving) {
                        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                            const client = Workspace.stackingOrder[i];
                            client.previousOpacity = client.opacity;
                            if (client.move || !client.normalWindow)
                                continue;

                            client.opacity = 0.5;
                        }
                    }
                    if (config.rememberWindowGeometries && client.zone != -1) {
                        if (client.oldGeometry) {
                            const geometry = client.oldGeometry;
                            const zone = config.layouts[client.layout].zones[client.zone];
                            const newGeometry = Qt.rect(Math.round(Workspace.cursorPos.x - geometry.width / 2), Math.round(client.frameGeometry.y), Math.round(geometry.width), Math.round(geometry.height));
                            client.frameGeometry = newGeometry;
                        }
                    }
                    moving = true;
                    moved = false;
                    resizing = false;
                    Utils.log("Move start " + client.resourceClass.toString());
                    mainDialog.show();
                }
                if (client.resize) {
                    moving = false;
                    moved = false;
                    resizing = true;
                    Sticky.startResize(client, Workspace, config, function(otherClient) {
                        return root.checkFilter(otherClient);
                    });
                }
            }
        }

        function onInteractiveMoveResizeStepped(rect) {
            if (client.resizeable) {
                if (moving && checkFilter(client))
                    moved = true;
                if (resizing && checkFilter(client))
                    Sticky.stepResize(client, rect || client.frameGeometry, config);
            }
        }

        function onInteractiveMoveResizeFinished() {
            Utils.log("Interactive move/resize finished for " + client.resourceClass.toString() + "; moving=" + moving + ", moved=" + moved + ", highlightedZone=" + highlightedZone + ", overlayVisible=" + mainDialog.visible + ", snapAssistEnabled=" + isSnapAssistEnabled());
            if (config.fadeWindowsWhileMoving) {
                for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                    const client = Workspace.stackingOrder[i];
                    client.opacity = client.previousOpacity || 1;
                }
            }
            if (moving) {
                Utils.log("Move end " + client.resourceClass.toString());
                let targetZone = -1;
                if (moved) {
                    if (mainDialog.visible && highlightedZone !== -1) {
                        targetZone = highlightedZone;
                        moveClientToZone(client, targetZone);
                    } else {
                        matchZone(client);
                        if (client.zone !== -1) {
                            targetZone = client.zone;
                        } else {
                            saveClientProperties(client, -1);
                        }
                    }
                }
                mainDialog.hide();
                if (targetZone !== -1 && isSnapAssistEnabled())
                    triggerSnapAssist(currentLayout, targetZone);
            } else if (resizing) {
                Sticky.finishResize();
                matchZone(client);
                Utils.log("Resizing end: Matched client " + client.resourceClass.toString() + " to layout.zone " + client.layout + " " + client.zone);
                saveClientProperties(client, client.zone);
            }
            moving = false;
            moved = false;
            resizing = false;
        }

        // fix from https://github.com/gerritdevriese/kzones/pull/25
        function onFullScreenChanged() {
            Utils.log("Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + client.fullScreen + ")");
            if (client.fullScreen == true) {
                Utils.log("onFullscreenChanged: Client zone: " + client.zone + " layout: " + client.layout);
                if (client.zone != -1 && client.layout != -1) {
                    //check if fullscreen is enabled for layout or for zone
                    const layout = config.layouts[client.layout];
                    const zone = layout.zones[client.zone];
                    Utils.log("Layout.fullscreen: " + layout.fullscreen + " Zone.fullscreen: " + zone.fullscreen);
                    if (layout.fullscreen == true || zone.fullscreen == true) {
                        const currentZones = repeaterLayout.itemAt(client.layout);
                        const zoneItem = currentZones.repeater.itemAt(client.zone);
                        const itemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0));
                        const newGeometry = Qt.rect(Math.round(itemGlobal.x), Math.round(itemGlobal.y), Math.round(zoneItem.width), Math.round(zoneItem.height));
                        Utils.log("Fullscreen client " + client.resourceClass.toString() + " to zone " + client.zone + " with geometry " + JSON.stringify(newGeometry));
                        client.setMaximize(false, false);
                        client.frameGeometry = newGeometry;
                    }
                }
            }
            mainDialog.hide();
        }

        if (!checkFilter(client))
            return ;

        Utils.log("Connecting signals for client " + client.resourceClass.toString());
        client.onInteractiveMoveResizeStarted.connect(onInteractiveMoveResizeStarted);
        client.onInteractiveMoveResizeStepped.connect(onInteractiveMoveResizeStepped);
        client.onInteractiveMoveResizeFinished.connect(onInteractiveMoveResizeFinished);
        client.onFullScreenChanged.connect(onFullScreenChanged);
    }

    Component.onCompleted: {
        Utils.log("Loading script (" + Qt.resolvedUrl("./main.qml") + ")");
        Core.init(KWin, Workspace);
        Core.registerQMLComponent("root", root);
        Core.loadConfig();
        refreshClientArea();
        // match all clients to zones and connect signals
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            matchZone(Workspace.stackingOrder[i]);
            connectSignals(Workspace.stackingOrder[i]);
        }
        Utils.log("Everything loaded successfully");
    }

    PlasmaCore.Dialog {
        id: snapAssistDialog

        function show() {
            refreshClientArea();
            snapAssistDialog.x = 0;
            snapAssistDialog.y = 0;
            snapAssistDialog.width = Workspace.virtualScreenSize.width;
            snapAssistDialog.height = Workspace.virtualScreenSize.height;
            snapAssistDialog.setWidth(Workspace.virtualScreenSize.width);
            snapAssistDialog.setHeight(Workspace.virtualScreenSize.height);
            snapAssistDialog.visible = true;
            snapAssistDialog.requestActivate();
            Utils.log("Snap Assist dialog shown at " + snapAssistItem.x + "," + snapAssistItem.y + " size " + snapAssistItem.width + "x" + snapAssistItem.height + " with " + snapAssistItem.candidates.length + " candidates");
        }

        function hide() {
            snapAssistDialog.visible = false;
            snapAssistItem.candidates = [];
            snapAssistItem.targetZoneIndex = -1;
        }

        title: "KZones Snap Assist"
        location: PlasmaCore.Types.Floating
        type: PlasmaCore.Dialog.Normal
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.BypassWindowManagerHint
        hideOnWindowDeactivate: false
        visible: false
        outputOnly: false
        width: displaySize.width
        height: displaySize.height

        Item {
            id: snapAssistRoot

            width: snapAssistDialog.width
            height: snapAssistDialog.height

            MouseArea {
                anchors.fill: parent
                onClicked: snapAssistDialog.hide()
            }

            Components.SnapAssist {
                id: snapAssistItem

                property int targetZoneIndex: -1

                onWindowSelected: function(client) {
                    if (!client)
                        return;

                    const targetZone = targetZoneIndex;
                    if (client.minimized)
                        client.minimized = false;

                    moveClientToZone(client, targetZone);
                    Workspace.activeWindow = client;
                    triggerSnapAssist(currentLayout, targetZone);
                }
                onDismissed: {
                    snapAssistDialog.hide();
                }
            }

        }

    }

    PlasmaCore.Dialog {
        id: mainDialog

        function show() {
            mainDialog.visible = true;
            mainDialog.setWidth(Workspace.virtualScreenSize.width);
            mainDialog.setHeight(Workspace.virtualScreenSize.height);
            refreshClientArea();
        }

        function hide() {
            mainDialog.visible = false;
            zoneSelector.expanded = false;
            zoneSelector.near = false;
            highlightedZone = -1;
            showZoneOverlay = config.zoneOverlayShowWhen == 0;
        }

        title: "KZones Overlay"
        location: PlasmaCore.Types.Desktop
        type: PlasmaCore.Dialog.OnScreenDisplay
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
        hideOnWindowDeactivate: true
        visible: false
        outputOnly: true
        opacity: 1
        width: displaySize.width
        height: displaySize.height

        Item {
            id: mainItem

            property alias repeaterLayout: repeaterLayout

            width: mainDialog.width
            height: mainDialog.height

            // main polling timer
            Timer {
                id: timer

                triggeredOnStart: true
                interval: config.pollingRate
                running: mainDialog.visible
                repeat: true
                onTriggered: {
                    refreshClientArea();
                    let hoveringZone = -1;
                    // zone overlay
                    const currentZones = repeaterLayout.itemAt(currentLayout);
                    if (config.enableZoneOverlay && showZoneOverlay && !zoneSelector.expanded)
                        currentZones.repeater.model.forEach((zone, zoneIndex) => {
                        if (Utils.isHovering(currentZones.repeater.itemAt(zoneIndex).children[config.zoneOverlayHighlightTarget]))
                            hoveringZone = zoneIndex;

                    });

                    // zone selector
                    if (config.enableZoneSelector) {
                        if (!zoneSelector.animating && zoneSelector.expanded) {
                            zoneSelector.repeater.model.forEach((layout, layoutIndex) => {
                                const layoutItem = zoneSelector.repeater.itemAt(layoutIndex);
                                if (layoutItem) {
                                    layout.zones.forEach((zone, zoneIndex) => {
                                        const zoneItem = layoutItem.repeater ? layoutItem.repeater.itemAt(zoneIndex) : layoutItem.children[zoneIndex];
                                        if (zoneItem && Utils.isHovering(zoneItem)) {
                                            hoveringZone = zoneIndex;
                                            setCurrentLayout(layoutIndex);
                                        }
                                    });
                                }
                            });
                        }
                        // set zoneSelector expansion state
                        zoneSelector.expanded = Utils.isHovering(zoneSelector) && (Workspace.cursorPos.y - clientArea.y) >= 0;
                        // set zoneSelector near state
                        const triggerDistance = config.zoneSelectorTriggerDistance * 50 + 25;
                        zoneSelector.near = (Workspace.cursorPos.y - clientArea.y) < zoneSelector.y + zoneSelector.height + triggerDistance;
                    }
                    // edge snapping
                    if (config.enableEdgeSnapping) {
                        const triggerDistance = (config.edgeSnappingTriggerDistance + 1) * 10;
                        if (Workspace.cursorPos.x <= clientArea.x + triggerDistance || Workspace.cursorPos.x >= clientArea.x + clientArea.width - triggerDistance || Workspace.cursorPos.y <= clientArea.y + triggerDistance || Workspace.cursorPos.y >= clientArea.y + clientArea.height - triggerDistance) {
                            const padding = config.layouts[currentLayout].padding || 0;
                            const halfPadding = padding / 2;
                            currentZones.repeater.model.forEach((zone, zoneIndex) => {
                                const zoneItem = currentZones.repeater.itemAt(zoneIndex);
                                const itemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0));
                                let zoneGeometry = {
                                    "x": itemGlobal.x - padding / 2,
                                    "y": itemGlobal.y - padding / 2,
                                    "width": zoneItem.width + padding,
                                    "height": zoneItem.height + padding
                                };
                                //adjust most left edge
                                if (zoneGeometry.x <= halfPadding) {
                                    zoneGeometry.x = 0;
                                    zoneGeometry.width += padding;
                                }
                                //adjust most top edge
                                if (zoneGeometry.y <= halfPadding) {
                                    zoneGeometry.y = 0;
                                    zoneGeometry.height += padding;
                                }
                                //adjust most right edge
                                if (zoneGeometry.x + zoneGeometry.width >= clientArea.width - halfPadding)
                                    zoneGeometry.width += halfPadding;

                                //adjust most bottom edge
                                if (zoneGeometry.y + zoneGeometry.height >= clientArea.height - halfPadding)
                                    zoneGeometry.height += halfPadding;

                                // check if cursor is inside the zone geometry
                                if (Utils.isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, zoneGeometry))
                                    hoveringZone = zoneIndex;

                            });
                        }
                    }
                    // if hovering zone changed from the last frame
                    if (hoveringZone != highlightedZone) {
                        Utils.log("Highlighting zone " + hoveringZone + " in layout " + currentLayout);
                        highlightedZone = hoveringZone;
                    }
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
                        "activeWindow": {
                            "caption": Workspace.activeWindow && Workspace.activeWindow.caption,
                            "resourceClass": Workspace.activeWindow && Workspace.activeWindow.resourceClass && Workspace.activeWindow.resourceClass.toString(),
                            "frameGeometry": {
                                "x": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.x,
                                "y": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.y,
                                "width": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.width,
                                "height": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.height
                            },
                            "zone": Workspace.activeWindow && Workspace.activeWindow.zone
                        },
                        "highlightedZone": highlightedZone,
                        "moving": moving,
                        "resizing": resizing,
                        "oldGeometry": Workspace.activeWindow && Workspace.activeWindow.oldGeometry,
                        "activeScreen": activeScreen && activeScreen.name,
                        "currentLayout": currentLayout,
                        "screenLayouts": screenLayouts
                    })
                    config: root.config
                }

                Repeater {
                    id: repeaterLayout

                    model: config.layouts

                    Components.Zones {
                        id: zones

                        config: root.config
                        currentLayout: root.currentLayout
                        highlightedZone: root.highlightedZone
                        layoutIndex: index
                        visible: index == root.currentLayout
                    }

                }

                Components.Selector {
                    id: zoneSelector

                    config: root.config
                    currentLayout: root.currentLayout
                    highlightedZone: root.highlightedZone
                }

            }

        }

    }

    Components.Shortcuts {
        onCycleLayouts: {
            snapAssistDialog.hide();
            setCurrentLayout((currentLayout + 1) % config.layouts.length);
            highlightedZone = -1;
            Utils.osd(osdLayoutName());
        }
        onCycleLayoutsReversed: {
            snapAssistDialog.hide();
            setCurrentLayout((currentLayout - 1 + config.layouts.length) % config.layouts.length);
            highlightedZone = -1;
            Utils.osd(osdLayoutName());
        }
        onMoveActiveWindowToNextZone: {
            const client = Workspace.activeWindow;
            if (client.zone == -1)
                moveClientToClosestZone(client);

            const zonesLength = config.layouts[currentLayout].zones.length;
            const targetZone = (client.zone + 1) % zonesLength;
            moveClientToZone(client, targetZone);
            if (isSnapAssistEnabled())
                triggerSnapAssist(currentLayout, targetZone);
        }
        onMoveActiveWindowToPreviousZone: {
            const client = Workspace.activeWindow;
            if (client.zone == -1)
                moveClientToClosestZone(client);

            const zonesLength = config.layouts[currentLayout].zones.length;
            const targetZone = (client.zone - 1 + zonesLength) % zonesLength;
            moveClientToZone(client, targetZone);
            if (isSnapAssistEnabled())
                triggerSnapAssist(currentLayout, targetZone);
        }
        onToggleZoneOverlay: {
            if (!config.enableZoneOverlay)
                Utils.osd("Zone overlay is disabled");
            else if (moving)
                showZoneOverlay = !showZoneOverlay;
            else
                Utils.osd("The overlay can only be shown while moving a window");
        }
        onSwitchToNextWindowInCurrentZone: {
            switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout);
        }
        onSwitchToPreviousWindowInCurrentZone: {
            switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout, true);
        }
        onMoveActiveWindowToZone: {
            moveClientToZone(Workspace.activeWindow, zone);
            if (isSnapAssistEnabled())
                triggerSnapAssist(currentLayout, zone);
        }
        onActivateLayout: {
            snapAssistDialog.hide();
            if (layout <= config.layouts.length - 1) {
                setCurrentLayout(layout);
                highlightedZone = -1;
                Utils.osd(osdLayoutName());
            } else {
                Utils.osd(`Layout ${layout + 1} does not exist`);
            }
        }
        onMoveActiveWindowUp: {
            const targetZone = moveClientToNeighbour(Workspace.activeWindow, "up");
            if (targetZone !== -1 && targetZone !== null && isSnapAssistEnabled())
                triggerSnapAssist(currentLayout, targetZone);
        }
        onMoveActiveWindowDown: {
            const targetZone = moveClientToNeighbour(Workspace.activeWindow, "down");
            if (targetZone !== -1 && targetZone !== null && isSnapAssistEnabled())
                triggerSnapAssist(currentLayout, targetZone);
        }
        onMoveActiveWindowLeft: {
            const targetZone = moveClientToNeighbour(Workspace.activeWindow, "left");
            if (targetZone !== -1 && targetZone !== null && isSnapAssistEnabled())
                triggerSnapAssist(currentLayout, targetZone);
        }
        onMoveActiveWindowRight: {
            const targetZone = moveClientToNeighbour(Workspace.activeWindow, "right");
            if (targetZone !== -1 && targetZone !== null && isSnapAssistEnabled())
                triggerSnapAssist(currentLayout, targetZone);
        }
        onSnapActiveWindow: {
            const zone = moveClientToClosestZone(Workspace.activeWindow);
            Utils.log("Snap active shortcut resolved zone " + zone + "; Snap Assist enabled=" + root.isSnapAssistEnabled());
            if (zone !== null && root.isSnapAssistEnabled())
                root.triggerSnapAssist(currentLayout, zone);
        }
        onSnapAllWindows: {
            moveAllClientsToClosestZone();
        }
        onRestoreActiveWindow: {
            restoreWindowGeometry(Workspace.activeWindow);
        }
    }

    DBusCall {
        id: dbusCall

        function exec(service, path, method, arguments = []) {
            this.service = service;
            this.path = path;
            this.method = method;
            this.arguments = arguments;
            this.call();
        }

        Component.onCompleted: {
            Core.registerQMLComponent("dbusCall", dbusCall);
        }
    }

    // workspace connection
    Connections {
        function onCurrentDesktopChanged() {
            snapAssistDialog.hide();
            if (config.trackLayoutPerDesktop)
                currentLayout = getCurrentLayout();

        }

        function onWindowAdded(client) {
            connectSignals(client);
            // check if client is in a zone application list
            config.layouts[currentLayout].zones.forEach((zone, zoneIndex) => {
                if (zone.applications && zone.applications.includes(client.resourceClass.toString())) {
                    moveClientToZone(client, zoneIndex);
                    return ;
                }
            });
            // auto snap to closest zone
            if (config.autoSnapAllNew && checkFilter(client))
                moveClientToClosestZone(client);

            // check if new window spawns in a zone
            if (client.zone == undefined || client.zone == -1)
                matchZone(client);

        }

        target: Workspace
    }

    Connections {
        //! still not working, hopefully it will at some point 😐
        function onConfigChanged() {
            Core.loadConfig();
        }

        target: Options
    }

}
