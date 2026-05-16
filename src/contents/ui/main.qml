import "../code/core.mjs" as Core
import "../code/meta-arrow/geometry.mjs" as MetaGeom
import "../code/meta-arrow/move-memory.mjs" as MoveMemory
import "../code/meta-arrow/snap-executor.mjs" as SnapExecutor
import "../code/meta-arrow/snap-planner.mjs" as SnapPlanner
import "../code/pristine-geometry.mjs" as Pristine
import "../code/utils.mjs" as Utils
import QtQuick
import QtQuick.Layouts
import "components" as Components
import org.kde.kwin
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore

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
    property bool fullscreenPendingSnap: false
    property var activeScreen: null
    // [{ layout, index }, ...] — layouts visible on activeScreen. `index` is
    // the position in the unfiltered config.layouts so existing references
    // (client.layout, repeaterLayout.itemAt(...), etc.) stay valid.
    property var availableLayouts: []
    property bool showZoneOverlay: config.zoneOverlayShowWhen == 0
    property var lastActiveWindow: null

    function refreshClientArea() {
        activeScreen = Workspace.activeScreen;
        clientArea = Workspace.clientArea(KWin.FullScreenArea, activeScreen, Workspace.currentDesktop);
        displaySize = Workspace.virtualScreenSize;
        refreshAvailableLayouts();
        currentLayout = getCurrentLayout();
    }

    function getScreenAtCursor() {
        const cp = Workspace.cursorPos;
        if (!cp)
            return null;

        const screens = rawScreensList();
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (!s || !s.geometry)
                continue;

            const g = s.geometry;
            if (cp.x >= g.x && cp.x <= g.x + g.width && cp.y >= g.y && cp.y <= g.y + g.height)
                return s;

        }
        return null;
    }

    function refreshClientAreaForScreen(screen) {
        if (!screen) {
            refreshClientArea();
            return ;
        }
        activeScreen = screen;
        clientArea = Workspace.clientArea(KWin.FullScreenArea, screen, Workspace.currentDesktop);
        displaySize = Workspace.virtualScreenSize;
        refreshAvailableLayouts();
        currentLayout = getCurrentLayout();
    }

    function refreshAvailableLayouts() {
        availableLayouts = Core.getLayoutsForScreen(Core.getScreenId(activeScreen));
    }

    function firstAvailableIndex() {
        return availableLayouts.length > 0 ? availableLayouts[0].index : 0;
    }

    function isLayoutAvailable(idx) {
        for (let i = 0; i < availableLayouts.length; i++) if (availableLayouts[i].index === idx) {
            return true;
        }
        return false;
    }

    // Pristine-geometry state derivation. Used by every signal that may
    // trigger a floating <-> non-floating transition. Geometry-driven (not
    // client.zone-driven) so externally-snapped windows are classified
    // correctly.
    function computeWindowState(client) {
        if (!client) return Pristine.FLOATING;
        if (client.fullScreen) return Pristine.FULLSCREEN;
        if (client.maximizeMode !== undefined && client.maximizeMode !== null && client.maximizeMode !== 0)
            return Pristine.FULLSCREEN;
        if (MoveMemory.isFullscreenSized(client, clientArea)) return Pristine.FULLSCREEN;
        if (frameGeometryMatchesAnyZone(client)) return Pristine.SNAPPED;
        return Pristine.FLOATING;
    }

    function frameGeometryMatchesAnyZone(client) {
        if (!client || !client.frameGeometry || !clientArea || !clientArea.width || !clientArea.height) return false;
        const g = client.frameGeometry;
        const TOL = 4;
        const layouts = config.layouts || [];
        for (let li = 0; li < layouts.length; li++) {
            const layout = layouts[li];
            if (!layout || !layout.zones) continue;
            for (let zi = 0; zi < layout.zones.length; zi++) {
                const z = layout.zones[zi];
                const zx = clientArea.x + (z.x / 100) * clientArea.width;
                const zy = clientArea.y + (z.y / 100) * clientArea.height;
                const zw = (z.width  / 100) * clientArea.width;
                const zh = (z.height / 100) * clientArea.height;
                if (Math.abs(g.x - zx) <= TOL
                 && Math.abs(g.y - zy) <= TOL
                 && Math.abs(g.width  - zw) <= TOL
                 && Math.abs(g.height - zh) <= TOL) return true;
            }
        }
        return false;
    }

    // Clip a pristine rect to the currently active screen's client area so a
    // restore on a different (or smaller) monitor doesn't put the window
    // off-screen.
    function clipPristineToActiveScreen(rect) {
        if (!rect) return rect;
        const a = clientArea;
        if (!a || !a.width || !a.height) return rect;
        let x = rect.x, y = rect.y, w = rect.width, h = rect.height;
        if (w > a.width)  w = a.width;
        if (h > a.height) h = a.height;
        if (x < a.x) x = a.x;
        if (x + w > a.x + a.width)  x = a.x + a.width  - w;
        if (y < a.y) y = a.y;
        if (y + h > a.y + a.height) y = a.y + a.height - h;
        return { x: x, y: y, width: w, height: h };
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
                client.layout = currentLayout;
                break;
            }
        }
    }

    function getWindowsInZone(zone, layout) {
        const windows = [];
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client.zone === zone && client.layout === layout && client.desktop === Workspace.currentDesktop && client.activity === Workspace.currentActivity && client.screen === Workspace.activeWindow.screen && checkFilter(client))
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
        client.zone = zone;
        client.layout = currentLayout;
        client.desktop = Workspace.currentDesktop;
        client.activity = Workspace.currentActivity;
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

    function rawScreensList() {
        const out = [];
        try {
            if (Array.isArray(Workspace.screens))
                return Workspace.screens.slice();

            if (Workspace.screens && typeof Workspace.screens.length === "number") {
                for (let i = 0; i < Workspace.screens.length; i++) out.push(Workspace.screens[i])
                return out;
            }
            if (typeof Workspace.numScreens === "number" && typeof Workspace.screenAt === "function") {
                for (let i = 0; i < Workspace.numScreens; i++) out.push(Workspace.screenAt(i))
                return out;
            }
        } catch (e) {
            Utils.log("rawScreensList enumeration failed: " + e);
        }
        return out;
    }

    function getClientAreaForScreen(screenName) {
        const screens = rawScreensList();
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (s && String(s.name) === String(screenName)) {
                const ca = Workspace.clientArea(KWin.FullScreenArea, s, Workspace.currentDesktop);
                return {
                    "x": ca.x,
                    "y": ca.y,
                    "width": ca.width,
                    "height": ca.height
                };
            }
        }
        return null;
    }

    function getScreenForClient(client, direction) {
        if (!client)
            return null;

        const screens = rawScreensList();
        const g = client.frameGeometry;
        // Pick screen with the largest overlap area against the window's rect.
        // Ignores a tiny sliver bleeding onto an adjacent monitor.
        let best = null;
        let bestOverlap = -1;
        const overlaps = [];
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (!s || !s.geometry) {
                overlaps.push({
                    "name": s ? String(s.name || "?") : "null",
                    "overlap": -1
                });
                continue;
            }
            const sg = s.geometry;
            const ox = Math.max(0, Math.min(g.x + g.width, sg.x + sg.width) - Math.max(g.x, sg.x));
            const oy = Math.max(0, Math.min(g.y + g.height, sg.y + sg.height) - Math.max(g.y, sg.y));
            const overlap = ox * oy;
            overlaps.push({
                "name": String(s.name || "?"),
                "overlap": overlap,
                "geom": {
                    "x": sg.x,
                    "y": sg.y,
                    "w": sg.width,
                    "h": sg.height
                }
            });
            if (overlap > bestOverlap) {
                best = s;
                bestOverlap = overlap;
            }
        }
        // Tie-break by direction of travel only when there's a non-`best`
        // screen with the SAME overlap as best.
        if (direction && best) {
            const bg = best.geometry;
            for (let i = 0; i < screens.length; i++) {
                const cand = screens[i];
                if (!cand || cand === best || !cand.geometry)
                    continue;

                if (overlaps[i].overlap !== bestOverlap || bestOverlap <= 0)
                    continue;

                const cg = cand.geometry;
                if (direction === "left" && cg.x + cg.width <= bg.x + 1)
                    return cand;

                if (direction === "right" && cg.x >= bg.x + bg.width - 1)
                    return cand;

                if (direction === "up" && cg.y + cg.height <= bg.y + 1)
                    return cand;

                if (direction === "down" && cg.y >= bg.y + bg.height - 1)
                    return cand;

            }
        }
        if (best)
            return best;

        return Workspace.activeScreen;
    }

    function smartSnapMetaArrow(client, direction) {
        if (!checkFilter(client))
            return ;

        const screen = getScreenForClient(client, direction);
        const screenName = (screen && screen.name) ? String(screen.name) : "";
        const clientAreaForSrc = getClientAreaForScreen(screenName);
        if (!clientAreaForSrc) {
            Utils.log("smartSnapMetaArrow: no client area for " + screenName);
            return ;
        }
        const screensList = rawScreensList();
        const sourcePct = MetaGeom.clientToSourcePct(client, clientAreaForSrc);
        const action = SnapPlanner.planSnap({
            "client": client,
            "source": sourcePct,
            "clientArea": clientAreaForSrc,
            "dir": direction,
            "screens": screensList,
            "currentScreen": screen,
            "layouts": config.layouts
        });
        Utils.log("smartSnapMetaArrow: dir=" + direction + " mem=" + JSON.stringify(MoveMemory.getMoveMemory(client) || null) + " action=" + JSON.stringify(action));
        // Silently sync the active layout to whichever layout the snapped
        // zone came from. Keeps the layout pool + overlay consistent with
        // the geometry the user just locked into, without showing an OSD.
        applyActiveLayoutForAction(action, screensList, screen);
        SnapExecutor.executeSnap(action, client, {
            "getClientAreaForScreen": getClientAreaForScreen,
            "getFullscreenPadding": function() {
                return config.fullscreenSnapPadding || 0;
            },
            "getLayoutPadding": function(layoutIndex) {
                if (layoutIndex == null || layoutIndex < 0 || !config.layouts[layoutIndex])
                    return 0;

                return config.layouts[layoutIndex].padding || 0;
            },
            "getZoneRef": function(layoutIndex, zoneIndex) {
                if (layoutIndex == null || layoutIndex < 0)
                    return null;

                const l = config.layouts[layoutIndex];
                if (!l || !l.zones || !l.zones[zoneIndex])
                    return null;

                const z = l.zones[zoneIndex];
                return {
                    "x": +z.x,
                    "y": +z.y,
                    "w": +z.width,
                    "h": +z.height,
                    "sourceLayoutIndex": layoutIndex,
                    "sourceZoneIndex": zoneIndex,
                    "padding": l.padding || 0
                };
            },
            "setMaximize": function(c, h, v) {
                c.setMaximize(h, v);
            },
            "setFrameGeometry": function(c, r) {
                c.frameGeometry = Qt.rect(r.x, r.y, r.width, r.height);
            },
            "saveClientProperties": function(c, layoutIndex, zoneIndex) {
                c.zone = zoneIndex;
                c.layout = (layoutIndex !== -1) ? layoutIndex : c.layout;
                c.desktop = Workspace.currentDesktop;
                c.activity = Workspace.currentActivity;
            },
            "log": Utils.log
        }, direction);
    }

    function clearMetaArrowMemory(client) {
        MoveMemory.clearMemory(client);
    }

    function applyActiveLayoutForAction(action, screensList, sourceScreen) {
        if (!action)
            return ;

        let layoutIndex = -1;
        let screenName = "";
        if (action.type === "zone") {
            layoutIndex = action.layoutIndex;
            screenName = action.screenName;
        } else if (action.type === "jump" && action.nextAction && action.nextAction.type === "zone") {
            layoutIndex = action.nextAction.layoutIndex;
            screenName = action.nextAction.screenName;
        } else {
            return ;
        }
        if (layoutIndex == null || layoutIndex < 0)
            return ;

        let targetScreen = sourceScreen;
        if (screenName && (!targetScreen || String(targetScreen.name) !== screenName)) {
            for (let i = 0; i < screensList.length; i++) {
                const s = screensList[i];
                if (s && String(s.name) === screenName) {
                    targetScreen = s;
                    break;
                }
            }
        }
        refreshClientAreaForScreen(targetScreen);
        setCurrentLayout(layoutIndex);
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
            if (screenLayouts[key] === undefined || !isLayoutAvailable(screenLayouts[key]))
                screenLayouts[key] = firstAvailableIndex();

            return screenLayouts[key];
        }
        if (!isLayoutAvailable(currentLayout))
            return firstAvailableIndex();

        return currentLayout;
    }

    function setCurrentLayout(layout) {
        if (!isLayoutAvailable(layout))
            return ;

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
                }
            }
        }

        function onInteractiveMoveResizeStepped() {
            if (client.resizeable) {
                if (moving && checkFilter(client))
                    moved = true;

            }
        }

        function onInteractiveMoveResizeFinished() {
            Utils.log("Interactive move/resize finished for client " + client.resourceClass.toString());
            if (config.fadeWindowsWhileMoving) {
                for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                    const client = Workspace.stackingOrder[i];
                    client.opacity = client.previousOpacity || 1;
                }
            }
            if (moving) {
                Utils.log("Move end " + client.resourceClass.toString());
                if (moved) {
                    if (mainDialog.visible) {
                        if (fullscreenPendingSnap) {
                            const fsPad = config.fullscreenSnapPadding || 0;
                            if (fsPad === 0) {
                                client.setMaximize(true, true);
                            } else {
                                client.setMaximize(false, false);
                                client.frameGeometry = Qt.rect(clientArea.x + fsPad, clientArea.y + fsPad, Math.max(0, clientArea.width - 2 * fsPad), Math.max(0, clientArea.height - 2 * fsPad));
                            }
                            client.zone = -2;
                            client.layout = currentLayout;
                            client.desktop = Workspace.currentDesktop;
                            client.activity = Workspace.currentActivity;
                        } else {
                            moveClientToZone(client, highlightedZone);
                        }
                    } else {
                        saveClientProperties(client, -1);
                    }
                }
                mainDialog.hide();
            } else if (resizing) {
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

        function onInteractiveMoveResizeStartedClearMemory() {
            // User started dragging / resizing — the undo memory becomes
            // stale the moment they move off our snapped rect. Clear up front.
            clearMetaArrowMemory(client);
        }

        function onMinimizedChanged() {
            clearMetaArrowMemory(client);
            // Pristine is intentionally preserved across minimize: geometry
            // doesn't change, and the user should still be able to un-minimize
            // and drag-away to the original size.
        }

        // ── pristine-geometry wiring ──────────────────────────────────────
        const pristineDeps = {
            "computeState": function(c) { return computeWindowState(c); },
            "applyFrame": function(c, rect) {
                const clipped = clipPristineToActiveScreen(rect);
                c.setMaximize(false, false);
                c.frameGeometry = Qt.rect(clipped.x, clipped.y, clipped.width, clipped.height);
            },
            "unmaximize": function(c) {
                c.setMaximize(false, false);
            },
            "log": Utils.log
        };

        function onFrameGeometryChangedForPristine(oldGeom) {
            // Gate: skip while a user-initiated interactive drag/resize is in
            // flight. Those phases are handled explicitly by onInteractiveStart
            // / onInteractiveEnd to avoid the mid-drag applyFrame we issue from
            // here cascading back into another state-transition.
            if (moving || resizing) return;
            Pristine.onStateMaybeChanged(client, oldGeom, pristineDeps);
        }

        function onInteractiveStartedForPristine() {
            Pristine.onInteractiveStart(client, client.frameGeometry, pristineDeps);
        }

        function onInteractiveFinishedForPristine() {
            Pristine.onInteractiveEnd(client, resizing, pristineDeps);
        }

        function onClosedForPristine() {
            Pristine.clear(client);
        }
        // ──────────────────────────────────────────────────────────────────

        if (!checkFilter(client))
            return ;

        Utils.log("Connecting signals for client " + client.resourceClass.toString());
        client.onInteractiveMoveResizeStarted.connect(onInteractiveMoveResizeStarted);
        client.onInteractiveMoveResizeStarted.connect(onInteractiveMoveResizeStartedClearMemory);
        client.onInteractiveMoveResizeStepped.connect(onInteractiveMoveResizeStepped);
        client.onInteractiveMoveResizeFinished.connect(onInteractiveMoveResizeFinished);
        client.onFullScreenChanged.connect(onFullScreenChanged);
        if (client.minimizedChanged)
            client.minimizedChanged.connect(onMinimizedChanged);

        if (config.rememberWindowGeometries) {
            if (client.frameGeometryChanged)
                client.frameGeometryChanged.connect(onFrameGeometryChangedForPristine);
            client.onInteractiveMoveResizeStarted.connect(onInteractiveStartedForPristine);
            client.onInteractiveMoveResizeFinished.connect(onInteractiveFinishedForPristine);
            if (client.closed)
                client.closed.connect(onClosedForPristine);
        }

    }

    function showLayoutOsd() {
        if (!config.showOsdMessages)
            return ;

        const idx = currentLayout;
        const layout = config.layouts[idx];
        if (!layout)
            return ;

        layoutOsd.show(layout.zones, osdLayoutName(), activeScreen);
    }

    Component.onCompleted: {
        Utils.log("Loading script (" + Qt.resolvedUrl("./main.qml") + ")");
        Core.init(KWin, Workspace);
        Core.registerQMLComponent("root", root);
        Core.loadConfig();
        Pristine.setConfigGate(function() { return config.rememberWindowGeometries; });
        refreshClientArea();
        // match all clients to zones and connect signals
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            matchZone(Workspace.stackingOrder[i]);
            connectSignals(Workspace.stackingOrder[i]);
        }
        Utils.log("Everything loaded successfully");
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
            fullscreenPendingSnap = false;
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
                            zoneSelector.repeater.model.forEach((entry, repeaterIndex) => {
                                const layoutItem = zoneSelector.repeater.itemAt(repeaterIndex);
                                entry.layout.zones.forEach((zone, zoneIndex) => {
                                    const zoneItem = layoutItem.children[zoneIndex];
                                    if (Utils.isHovering(zoneItem)) {
                                        hoveringZone = zoneIndex;
                                        setCurrentLayout(entry.index);
                                    }
                                });
                            });
                        }
                        // set zoneSelector expansion state
                        zoneSelector.expanded = Utils.isHovering(zoneSelector) && (Workspace.cursorPos.y - clientArea.y) >= 0;
                        // set zoneSelector near state
                        const triggerDistance = config.zoneSelectorTriggerDistance * 50 + 25;
                        zoneSelector.near = (Workspace.cursorPos.y - clientArea.y) < zoneSelector.y + zoneSelector.height + triggerDistance;
                    }
                    // edge snapping
                    let pendingFullscreenSnap = false;
                    if (config.enableEdgeSnapping) {
                        const triggerDistance = (config.edgeSnappingTriggerDistance + 1) * 10;
                        // Cursor flicked beyond the top of the workspace (into
                        // the panel area) means the user wants a full-monitor
                        // toss snap, not a top-edge tile. Detected purely by
                        // position — no velocity tracking.
                        if (config.enableFullscreenSnap && Workspace.cursorPos.y < clientArea.y)
                            pendingFullscreenSnap = true;

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
                    // Fullscreen toss takes priority over any in-layout zone
                    // we may have just highlighted.
                    if (pendingFullscreenSnap)
                        hoveringZone = -1;

                    if (root.fullscreenPendingSnap !== pendingFullscreenSnap)
                        root.fullscreenPendingSnap = pendingFullscreenSnap;

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
                        "screenLayouts": screenLayouts,
                        "availableLayouts": availableLayouts.map((e) => {
                            return e.index + ":" + e.layout.name;
                        })
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
                        visible: index === root.currentLayout && root.isLayoutAvailable(index) && !root.fullscreenPendingSnap
                    }

                }

                // Fullscreen-drag preview: reuses the standard Zones renderer
                // with a synthetic single-zone layout covering the entire
                // client area, so the user sees the same indicator card +
                // highlight they get for a normal drag-snap.
                Components.Zones {
                    id: fullscreenSnapPreview

                    visible: root.fullscreenPendingSnap
                    config: root.config
                    currentLayout: -1
                    highlightedZone: -1
                    layoutIndex: -1
                    overrideZones: [{
                        "x": 0,
                        "y": 0,
                        "width": 100,
                        "height": 100
                    }]
                    overridePadding: config.fullscreenSnapPadding || 0
                    overrideAlwaysActive: root.fullscreenPendingSnap
                    z: 50
                }

                Components.Selector {
                    id: zoneSelector

                    config: root.config
                    currentLayout: root.currentLayout
                    highlightedZone: root.highlightedZone
                    availableLayouts: root.availableLayouts
                }

            }

        }

    }

    Components.LayoutOsd {
        id: layoutOsd
    }

    Components.Shortcuts {
        onCycleLayouts: {
            clearMetaArrowMemory(Workspace.activeWindow);
            refreshClientAreaForScreen(getScreenAtCursor());
            if (availableLayouts.length === 0)
                return ;

            const pos = availableLayouts.findIndex((e) => {
                return e.index === currentLayout;
            });
            const next = availableLayouts[(pos + 1) % availableLayouts.length].index;
            setCurrentLayout(next);
            highlightedZone = -1;
            showLayoutOsd();
        }
        onCycleLayoutsReversed: {
            clearMetaArrowMemory(Workspace.activeWindow);
            refreshClientAreaForScreen(getScreenAtCursor());
            if (availableLayouts.length === 0)
                return ;

            const pos = availableLayouts.findIndex((e) => {
                return e.index === currentLayout;
            });
            const prev = availableLayouts[(pos - 1 + availableLayouts.length) % availableLayouts.length].index;
            setCurrentLayout(prev);
            highlightedZone = -1;
            showLayoutOsd();
        }
        onMoveActiveWindowToNextZone: {
            const client = Workspace.activeWindow;
            clearMetaArrowMemory(client);
            if (client.zone == -1)
                moveClientToClosestZone(client);

            const zonesLength = config.layouts[currentLayout].zones.length;
            moveClientToZone(client, (client.zone + 1) % zonesLength);
        }
        onMoveActiveWindowToPreviousZone: {
            const client = Workspace.activeWindow;
            clearMetaArrowMemory(client);
            if (client.zone == -1)
                moveClientToClosestZone(client);

            const zonesLength = config.layouts[currentLayout].zones.length;
            moveClientToZone(client, (client.zone - 1 + zonesLength) % zonesLength);
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
            clearMetaArrowMemory(Workspace.activeWindow);
            moveClientToZone(Workspace.activeWindow, zone);
        }
        onActivateLayout: {
            clearMetaArrowMemory(Workspace.activeWindow);
            refreshClientAreaForScreen(getScreenAtCursor());
            if (layout >= 0 && layout < availableLayouts.length) {
                setCurrentLayout(availableLayouts[layout].index);
                highlightedZone = -1;
                showLayoutOsd();
            } else {
                const screenName = activeScreen && activeScreen.name ? activeScreen.name : "this screen";
                Utils.osd(`Layout ${layout + 1} does not exist on ${screenName}`);
            }
        }
        onMoveActiveWindowUp: {
            if (config.smartHotkeys)
                smartSnapMetaArrow(Workspace.activeWindow, "up");
            else
                moveClientToNeighbour(Workspace.activeWindow, "up");
        }
        onMoveActiveWindowDown: {
            if (config.smartHotkeys)
                smartSnapMetaArrow(Workspace.activeWindow, "down");
            else
                moveClientToNeighbour(Workspace.activeWindow, "down");
        }
        onMoveActiveWindowLeft: {
            if (config.smartHotkeys)
                smartSnapMetaArrow(Workspace.activeWindow, "left");
            else
                moveClientToNeighbour(Workspace.activeWindow, "left");
        }
        onMoveActiveWindowRight: {
            if (config.smartHotkeys)
                smartSnapMetaArrow(Workspace.activeWindow, "right");
            else
                moveClientToNeighbour(Workspace.activeWindow, "right");
        }
        onSnapActiveWindow: {
            clearMetaArrowMemory(Workspace.activeWindow);
            moveClientToClosestZone(Workspace.activeWindow);
        }
        onSnapAllWindows: {
            for (let i = 0; i < Workspace.stackingOrder.length; i++) clearMetaArrowMemory(Workspace.stackingOrder[i])
            moveAllClientsToClosestZone();
        }
        onShowDetectedMonitors: {
            const screens = Core.getDetectedScreens();
            if (screens.length === 0) {
                Utils.osd("KZones: no monitors detected");
                return ;
            }
            const summary = screens.map((s) => {
                return `${s.name} (${s.width}x${s.height})`;
            }).join("   ");
            Utils.osd("Monitors: " + summary);
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
            if (config.trackLayoutPerDesktop)
                currentLayout = getCurrentLayout();

        }

        function onActiveScreenChanged() {
            refreshClientArea();
        }

        function onScreensChanged() {
            refreshClientArea();
        }

        function onWindowActivated(client) {
            if (lastActiveWindow && lastActiveWindow !== client)
                clearMetaArrowMemory(lastActiveWindow);

            lastActiveWindow = client;
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
