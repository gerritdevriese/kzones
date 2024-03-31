import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kwin
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support

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
            enableZoneSelector: KWin.readConfig("enableZoneSelector", true), // enable zone selector
            zoneSelectorTriggerDistance: KWin.readConfig("zoneSelectorTriggerDistance", 1), // distance from the top of the screen to trigger the zone selector
            enableZoneOverlay: KWin.readConfig("enableZoneOverlay", true), // enable zone overlay
            zoneOverlayShowWhen: KWin.readConfig("zoneOverlayShowWhen", 0), // show zone overlay when
            zoneOverlayHighlightTarget: KWin.readConfig("zoneOverlayHighlightTarget", 0), // highlight target zone
            rememberWindowGeometries: KWin.readConfig("rememberWindowGeometries", true), // remember window geometries before snapping to a zone, and restore them when the window is removed from their zone
            layouts: JSON.parse(KWin.readConfig("layoutsJson", '[{"name":"Priority Grid","padding":0,"zones":[{"x":0,"y":0,"height":100,"width":25},{"x":25,"y":0,"height":100,"width":50},{"x":75,"y":0,"height":100,"width":25}]},{"name":"Quadrant Grid","zones":[{"x":0,"y":0,"height":50,"width":50},{"x":0,"y":50,"height":50,"width":50},{"x":50,"y":50,"height":50,"width":50},{"x":50,"y":0,"height":50,"width":50}]}]')), // layouts
            filterMode: KWin.readConfig("filterMode", 0), // filter mode
            filterList: KWin.readConfig("filterList", ""), // filter list
            pollingRate: KWin.readConfig("pollingRate", 100), // polling rate in milliseconds
            enableDebugMode: KWin.readConfig("enableDebugMode", false), // enable debug mode
        }

        log("Config loaded: " + JSON.stringify(config))
    }

    function log(message) {
        if (!config.enableDebugMode) return
        console.log("KZones: " + message)
    }

    function show() {
        // show OSD
        mainDialog.shown = true
        mainDialog.visible = true

        refreshClientArea()
    }

    function hide() {
        // hide OSD
        mainDialog.shown = false
        mainDialog.visible = false

        zoneSelectorBackground.expanded = false
        zoneSelectorBackground.near = false
        highlightedZone = -1

        showZoneOverlay = config.zoneOverlayShowWhen == 0
    }

    function refreshClientArea() {
        activeScreen = Workspace.activeScreen
        clientArea = Workspace.clientArea(KWin.FullScreenArea, activeScreen, Workspace.currentDesktop)
        displaySize = Workspace.virtualScreenSize
    }

    function isPointInside(x, y, geometry) {
        return x >= geometry.x && x <= geometry.x + geometry.width && y >= geometry.y && y <= geometry.y + geometry.height
    }

    function isHovering(item) {
        let itemGlobal = item.mapToGlobal(Qt.point(0, 0))
        return isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, {x: itemGlobal.x, y: itemGlobal.y, width: item.width * item.scale, height: item.height * item.scale})
    }

    function rectOverlapArea(component1, component2) {
        let x1 = component1.x
        let y1 = component1.y
        let x2 = component1.x + component1.width
        let y2 = component1.y + component1.height
        let x3 = component2.x
        let y3 = component2.y
        let x4 = component2.x + component2.width
        let y4 = component2.y + component2.height
        let xOverlap = Math.max(0, Math.min(x2, x4) - Math.max(x1, x3))
        let yOverlap = Math.max(0, Math.min(y2, y4) - Math.max(y1, y3))
        return xOverlap * yOverlap
    }

    function matchZone(client) {
        client.zone = -1
        // get all zones in the current layout
        let zones = config.layouts[currentLayout].zones
        // loop through zones and compare with the geometries of the client
        for (let i = 0; i < zones.length; i++) {
            let zone = zones[i]
            let zonePadding = config.layouts[currentLayout].padding || 0
            let zoneX = ((zone.x / 100) * (clientArea.width - zonePadding)) + zonePadding
            let zoneY = ((zone.y / 100) * (clientArea.height - zonePadding)) + zonePadding
            let zoneWidth = ((zone.width / 100) * (clientArea.width - zonePadding)) - zonePadding
            let zoneHeight = ((zone.height / 100) * (clientArea.height - zonePadding)) - zonePadding
            if (client.frameGeometry.x == zoneX && client.frameGeometry.y == zoneY && client.frameGeometry.width == zoneWidth && client.frameGeometry.height == zoneHeight) {
                // zone found, set it and exit the loop
                client.zone = i
                client.zone = currentLayout
                break
            }
        }
    }

    function getWindowsInZone(zone, layout) {
        let windows = []
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            let client = Workspace.stackingOrder[i]
            if (client.zone === zone &&
                client.layout === layout &&
                client.desktop === Workspace.currentDesktop &&
                client.activity === Workspace.currentActivity &&
                client.screen === Workspace.activeWindow.screen &&
                client.normalWindow) {
                    windows.push(client)
                }
        }
        return windows
    }

    function switchWindowInZone(zone, layout, reverse) {

        let clientsInZone = getWindowsInZone(zone, layout)

        if (reverse) { clientsInZone.reverse() }

        // cycle through clients in zone
        if (clientsInZone.length > 0) {
            let index = clientsInZone.indexOf(Workspace.activeWindow)
            if (index === -1) {
                Workspace.activeWindow = clientsInZone[0]
            } else {
                Workspace.activeWindow = clientsInZone[(index + 1) % clientsInZone.length]
            }
        }
    }

    function moveClientToZone(client, zone) {

        // block abnormal windows from being moved (like plasmashell, docks, etc...)
        if (!client.normalWindow) return
        
        log("Moving client " + client.resourceClass.toString() + " to zone " + zone)

        clientArea = Workspace.clientArea(KWin.FullScreenArea, client.output, Workspace.currentDesktop)
        saveWindowGeometries(client, zone)

        // move client to zone
        if (zone != -1) {
            let zoneItem = repeaterZones.itemAt(zone)
            let itemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0))
            let newGeometry = Qt.rect(Math.round(itemGlobal.x), Math.round(itemGlobal.y), Math.round(zoneItem.width), Math.round(zoneItem.height))
            log("Moving client " + client.resourceClass.toString() + " to zone " + zone + " with geometry " + JSON.stringify(newGeometry))
            client.frameGeometry = newGeometry
        }
    }

    function saveWindowGeometries(client, zone) {

        log("Saving geometry for client " + client.resourceClass.toString())

        // save current geometry
        if (config.rememberWindowGeometries) {
            let geometry = {
                "x": client.frameGeometry.x,
                "y": client.frameGeometry.y,
                "width": client.frameGeometry.width,
                "height": client.frameGeometry.height
            }
            if (zone != -1) {
                if (client.zone == -1) {
                    client.oldGeometry = geometry
                }                
            }
        }

        // save zone
        client.zone = zone
        client.layout = currentLayout
        client.desktop = Workspace.currentDesktop
        client.activity = Workspace.currentActivity
    }

    Item {
        id: shortcuts

        ShortcutHandler {
            name: "KZones: Cycle layouts"
            text: "KZones: Cycle layouts"
            sequence: "Ctrl+Alt+D"
            onActivated: {
                currentLayout = (currentLayout + 1) % config.layouts.length
                highlightedZone = -1
                osdCmd.exec(config.layouts[currentLayout].name)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to next zone"
            text: "KZones: Move active window to next zone"
            sequence: "Ctrl+Alt+Right"
            onActivated: {
                const client = Workspace.activeWindow
                // TODO: if client.zone = -1 check if client is in a zone by geometry
                const zonesLength = config.layouts[currentLayout].zones.length
                moveClientToZone(client, (client.zone + 1) % zonesLength)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to previous zone"
            text: "KZones: Move active window to previous zone"
            sequence: "Ctrl+Alt+Left"
            onActivated: {
                const client = Workspace.activeWindow
                // TODO: if client.zone = -1 check if client is in a zone by geometry
                const zonesLength = config.layouts[currentLayout].zones.length
                moveClientToZone(client, (client.zone - 1 + zonesLength) % zonesLength)
            }
        }

        ShortcutHandler {
            name: "KZones: Toggle zone overlay"
            text: "KZones: Toggle zone overlay"
            sequence: "Ctrl+Alt+C"
            onActivated: {
                if (!config.enableZoneOverlay) osdCmd.exec("Zone overlay is disabled")
                else if (moving) showZoneOverlay = !showZoneOverlay
                else osdCmd.exec("The overlay can only be shown while moving a window")
            }
        }

        ShortcutHandler {
            name: "KZones: Switch to next window in current zone"
            text: "KZones: Switch to next window in current zone"
            sequence: "Ctrl+Alt+Up"
            onActivated: {
                let zone = Workspace.activeWindow.zone
                let layout = Workspace.activeWindow.layout
                switchWindowInZone(zone, layout)
            }
        }

        ShortcutHandler {
            name: "KZones: Switch to previous window in current zone"
            text: "KZones: Switch to previous window in current zone"
            sequence: "Ctrl+Alt+Down"
            onActivated: {
                let zone = Workspace.activeWindow.zone
                let layout = Workspace.activeWindow.layout
                switchWindowInZone(zone, layout, true)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 1"
            text: "KZones: Move active window to 1"
            sequence: "Ctrl+Alt+Num+1"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 0)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 2"
            text: "KZones: Move active window to 2"
            sequence: "Ctrl+Alt+Num+2"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 1)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 3"
            text: "KZones: Move active window to 3"
            sequence: "Ctrl+Alt+Num+3"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 2)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 4"
            text: "KZones: Move active window to 4"
            sequence: "Ctrl+Alt+Num+4"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 3)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 5"
            text: "KZones: Move active window to 5"
            sequence: "Ctrl+Alt+Num+5"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 4)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 6"
            text: "KZones: Move active window to 6"
            sequence: "Ctrl+Alt+Num+6"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 5)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 7"
            text: "KZones: Move active window to 7"
            sequence: "Ctrl+Alt+Num+7"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 6)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 8"
            text: "KZones: Move active window to 8"
            sequence: "Ctrl+Alt+Num+8"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 7)
            }
        }

        ShortcutHandler {
            name: "KZones: Move active window to 9"
            text: "KZones: Move active window to 9"
            sequence: "Ctrl+Alt+Num+9"
            onActivated: {
                moveClientToZone(Workspace.activeWindow, 8)
            }
        }
    }

    Component.onCompleted: {
        // refresh client area
        refreshClientArea()

        mainDialog.loadConfig()

        // match all clients to zones
        for (var i = 0; i < Workspace.stackingOrder.length; i++) {
            matchZone(Workspace.stackingOrder[i])
        }
    }

    Item {
        id: mainItem

        anchors.fill: parent

        // main polling timer
        Timer {
            id: timer

            triggeredOnStart: true
            interval: config.pollingRate
            running: shown && moving
            repeat: true

            onTriggered: {

                refreshClientArea()

                let hoveringZone = -1
                
                if (config.enableZoneOverlay && showZoneOverlay && !zoneSelectorBackground.expanded) {

                    repeaterZones.model.forEach((zone, zoneIndex) => {
                        if (isHovering(repeaterZones.itemAt(zoneIndex).children[config.zoneOverlayHighlightTarget])) {
                            hoveringZone = zoneIndex
                        }
                    })

                }

                if (config.enableZoneSelector) {
                    if (!zoneSelectorBackground.animating && zoneSelectorBackground.expanded) {

                        repeaterLayouts.model.forEach((layout, layoutIndex) => {
                            let layoutItem = repeaterLayouts.itemAt(layoutIndex)
                            
                            layout.zones.forEach((zone, zoneIndex) => {
                                let zoneItem = layoutItem.children[zoneIndex]
                                if(isHovering(zoneItem)) {
                                    hoveringZone = zoneIndex
                                    currentLayout = layoutIndex
                                }
                            })
                        
                        })

                    }
                    // set zoneSelectorBackground expansion state
                    zoneSelectorBackground.expanded = isHovering(zoneSelectorBackground) && (Workspace.cursorPos.y - clientArea.y) >= 0;
                    // set zoneSelectorBackground near state
                    let triggerDistance = config.zoneSelectorTriggerDistance * 50 + 25
                    zoneSelectorBackground.near = (Workspace.cursorPos.y - clientArea.y) < zoneSelectorBackground.y + zoneSelectorBackground.height + triggerDistance;
                }

                // if hovering zone changed from the last frame
                if (hoveringZone != highlightedZone) {
                    log("Highlighting zone " + hoveringZone + " in layout " + currentLayout)
                    highlightedZone = hoveringZone
                }

            }
        }

        // osd qdbus
        Plasma5Support.DataSource {

            id: osdCmd

            engine: "executable"

            connectedSources: []
            onNewData: {
                disconnectSource(sourceName);
            }
            function exec(text, icon) {
                connectSource(`qdbus org.kde.plasmashell /org/kde/osdService showText "${icon}" "${text}"`);
            }
        }

        Item {
            x: clientArea.x || 0
            y: clientArea.y || 0
            width: clientArea.width || 0
            height: clientArea.height || 0
            clip: true

            // debug osd
            Rectangle {
                id: debugOsd

                visible: config.enableDebugMode
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.top: parent.top
                anchors.topMargin: 20
                z: 100
                width: debugOsdText.paintedWidth + debugOsdText.padding * 2
                height: debugOsdText.paintedHeight + debugOsdText.padding * 2
                radius: 5
                color: Kirigami.Theme.backgroundColor

                Text {
                    id: debugOsdText
                    
                    anchors.fill: parent
                    padding: 15
                    color: Kirigami.Theme.textColor
                    text: {
                        if (config.enableDebugMode) {
                            let t = ""
                            t += `Active: ${Workspace.activeWindow.caption}\n`
                            t += `Window class: ${Workspace.activeWindow.resourceClass.toString()}\n`
                            t += `X: ${Workspace.activeWindow.frameGeometry.x}, Y: ${Workspace.activeWindow.frameGeometry.y}, Width: ${Workspace.activeWindow.frameGeometry.width}, Height: ${Workspace.activeWindow.frameGeometry.height}\n`
                            t += `Previous Zone: ${Workspace.activeWindow.zone}\n`
                            t += `Highlighted Zone: ${highlightedZone}\n`
                            t += `Layout: ${currentLayout}\n`
                            t += `Polling Rate: ${config.pollingRate}ms\n`
                            t += `Moving: ${moving}\n`
                            t += `Resizing: ${resizing}\n`
                            t += `Old Geometry: ${JSON.stringify(Workspace.activeWindow.oldGeometry)}\n`
                            t += `Active Screen: ${activeScreen}\n`
                            return t
                        } else {
                            return ""
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

                    x: ((modelData.x / 100) * (clientArea.width - zonePadding)) + zonePadding
                    y: ((modelData.y / 100) * (clientArea.height - zonePadding)) + zonePadding
                    implicitWidth: ((modelData.width / 100) * (clientArea.width - zonePadding)) - zonePadding
                    implicitHeight: ((modelData.height / 100) * (clientArea.height - zonePadding)) - zonePadding

                    // zone indicator
                    Rectangle {
                        id: zoneIndicator

                        width: 160
                        height: 100
                        color: Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, Qt.rgba(0,0,0), 0.1)
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
                            zones: config.layouts[currentLayout].zones
                            activeZone: index
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
                            if (!running) zoneSelectorBackground.visible = true
                            zoneSelectorBackground.animating = running
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
                    color: Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, Qt.rgba(0,0,0), 0.1)
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

                            Components.Indicator{
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
                // check if new window spawns in a zone
                if (client.zone == undefined || client.zone == -1) {
                    matchZone(client)
                }
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
                log("Config changed")
                mainDialog.loadConfig()
            }
        }

        // activeWindow connection
        Connections {
            target: Workspace.activeWindow

            // FIXME: Is this the desired behaviour?
            function onFullScreenChanged() {
                let client = Workspace.activeWindow
                log("Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + client.fullScreen + ")");
                mainDialog.hide();
            }

            // start moving
            function onInteractiveMoveResizeStarted() {
                let client = Workspace.activeWindow
                if (client.resizeable && client.normalWindow) {
                    if (client.move && checkFilter(client)) {
                        
                        cachedClientArea = clientArea
                        moving = true
                        moved = false
                        resizing = false
                        log("Move start " + client.resourceClass.toString())
                        mainDialog.show()
                    }
                    if (client.resize) {
                        moving = false
                        moved = false
                        resizing = true
                        // client resizing
                    }
                }
            }

            // is moving
            function onInteractiveMoveResizeStepped(r) {
                let client = Workspace.activeWindow
                if (client.resizeable) {
                    if (moving && checkFilter(client)) {
                        moved = true
                        if (config.rememberWindowGeometries && client.zone != -1) {
                            if (client.oldGeometry) {
                                let geometry = client.oldGeometry
                                let zone = config.layouts[client.layout].zones[client.zone]
                                let zoneCenterX = (zone.x + zone.width / 2) / 100 * cachedClientArea.width + cachedClientArea.x
                                let zoneX = ((zone.x / 100) * cachedClientArea.width + cachedClientArea.x)
                                let newGeometry = Qt.rect(Math.round((r.x - zoneX) + (zoneCenterX - geometry.width / 2)), Math.round(r.y), Math.round(geometry.width), Math.round(geometry.height))
                                client.frameGeometry = newGeometry
                            }
                        }
                    }
                    if (resizing) {
                        // client resizing
                    }
                }
            }

            // stop moving
            function onInteractiveMoveResizeFinished() {
                let client = Workspace.activeWindow
                if (moving) {
                    log("Move end " + client.resourceClass.toString())
                    if (moved) {
                        if (shown) {
                            moveClientToZone(client, highlightedZone)
                        } else {
                            saveWindowGeometries(client, -1)
                        }
                    }
                    hide()
                }
                if (resizing) {
                    // client resizing
                }
                moving = false
                moved = false
                resizing = false
            }

            // check filter
            function checkFilter(client) {

                let filter = config.filterList.split(/\r?\n/)

                if (config.filterList.length > 0) {
                    if (config.filterMode == 0) { // include
                        return filter.includes(client.resourceClass.toString())
                    }
                    if (config.filterMode == 1) { // exclude
                        return !filter.includes(client.resourceClass.toString())
                    }
                }
                return true
            }
        }

        // reusable timer
        Timer {
            id: delay

            function setTimeout(callback, timeout) {
                delay.interval = timeout
                delay.repeat = false
                delay.triggered.connect(callback)
                delay.triggered.connect(function release () {
                    delay.triggered.disconnect(callback)
                    delay.triggered.disconnect(release)
                })
                delay.start()
            }
        }

    }

}
