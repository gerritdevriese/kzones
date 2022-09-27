import QtGraphicalEffects 1.0
import QtQuick 2.6
import QtQuick.Controls 1.5
import QtQuick.Layouts 1.2
import org.kde.kirigami 2.5 as Kirigami
import org.kde.kwin 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.core 2.0 as PlasmaCore

PlasmaCore.Dialog {

    id: mainDialog
    location: PlasmaCore.Types.Desktop // on the planar desktop layer, extending across the full screen from edge to edge. 
    backgroundHints: PlasmaCore.Types.NoBackground // not drawing a background under the applet, the applet has its own implementation. 
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    visible: false // hide dialog on startup
    opacity: 0 // hide dialog on startup
    outputOnly: true // makes dialog click-through

    // temp
    property bool inverted: false

    // properties
    property var config: {}
    property bool shown: false
    property bool moving: false
    property bool resizing: false
    property var clientArea: {}
    property int currentLayout: 0
    property int highlightedZone: -1
    property var oldWindowGeometries: []
    property var zonedClients: []
    property int activeScreen: 0

    // colors
    property string color_zone_border: "transparent"
    property string color_zone_border_active: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.9)
    property string color_zone_background: "transparent"
    property string color_zone_background_active: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
    property string color_indicator: '#66555555'
    property string color_indicator_accent: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.9)
    property string color_indicator_shadow: "#55000000"
    property string color_indicator_font: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 1)
    property string color_debug_handle: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.9)    

    function loadConfig() {
        // load values from configuration
        console.log("KZones: Reading config...")

        config = {
            rememberWindowGeometries: KWin.readConfig("rememberWindowGeometries", true), // remember window geometries before snapping to a zone, and restore them when the window is removed from their zone
            alwaysShowLayoutName: KWin.readConfig("alwaysShowLayoutName", false), // always show layout name, or only when switching between them
            pollingRate: KWin.readConfig("pollingRate", 100), // polling rate in milliseconds
            zoneTarget: KWin.readConfig("zoneTarget", 0), // the part of the zone you need to hover over to highlight it
            targetMethod: KWin.readConfig("targetMethod", 0), // method to determine in which zone the window is located
            handleUnitPercent: KWin.readConfig("handleUnitPercent", true), // method to determine in which zone the window is located
            handleUnitPixels: KWin.readConfig("handleUnitPixels", false), // method to determine in which zone the window is located (unused)
            handleSize: KWin.readConfig("handleSize", 100), // set the size of the handle, only applicable when target method is Titlebar or Window
            enableDebugMode: KWin.readConfig("enableDebugMode", false), // enable debug mode
            filterMode: KWin.readConfig("filterMode", 0), // filter mode
            filterList: KWin.readConfig("filterList", ""), // filter list
            fadeDuration: KWin.readConfig("fadeDuration", 150), // animation duration in milliseconds
            osdTimeout: KWin.readConfig("osdTimeout", 2000), // timeout in milliseconds for hiding the OSD after switching layouts
            layouts: JSON.parse(KWin.readConfig("layoutsJson", '[{"name": "Layout 1","padding": 0,"zones": [{"name": "1","x": 0,"y": 0,"height": 100,"width": 25},{"name": "2","x": 25,"y": 0,"height": 100,"width": 50},{"name": "3","x": 75,"y": 0,"height": 100,"width": 25}]}]')), // layouts
            alternateIndicatorStyle: KWin.readConfig("alternateIndicatorStyle", false), // alternate indicator style
        }

        console.log("KZones: Config loaded: " + JSON.stringify(config))
    }

    function show() {
        if (!config.alwaysShowLayoutName) layoutOsd.visible = false
        // refresh client area
        refreshClientArea()
        // update main item size, otherwise at boot it's not correct
        mainItem.width = workspace.displayWidth
        mainItem.height = workspace.displayHeight
        // show OSD
        if (!mainDialog.shown) {
            showAnimation.start()
            mainDialog.shown = true
        }        
    }

    function hide() {
        // hide OSD
        if (mainDialog.shown) {
            hideAnimation.start() 
            mainDialog.shown = false
            mainDialog.outputOnly = true
        }
    }

    function refreshClientArea() {
        activeScreen = workspace.activeScreen
        clientArea = workspace.clientArea(KWin.FullScreenArea, workspace.activeScreen, workspace.currentDesktop)
    }

    function checkZone(x, y, width, height) {
        let arr = []
        for (let i = 0; i < repeater_zones.model.length; i++) {
            let zone
            switch (config.zoneTarget) {
            case 0:
                zone = repeater_zones.itemAt(i).children[0]
                break
            case 1:
                zone = repeater_zones.itemAt(i)
                break
            }
            let zoneItem = zone.mapToItem(null, 0, 0)
            let component = {
                "x": zoneItem.x,
                "y": zoneItem.y,
                "width": zone.width,
                "height": zone.height
            }
            let component2 = {
                "x": x,
                "y": y,
                "width": width,
                "height": height
            }
            arr.push({i, overlap: rectOverlapArea(component, component2)})
        }

        // calculate highest overlap
        let overlaps = arr.map(x => x.overlap)
        let maxOverlap = Math.max(...overlaps)
        if (maxOverlap > 0) {
            highlightedZone = arr[overlaps.indexOf(maxOverlap)].i
        } else {
            highlightedZone = -1
        }

    }

    function getZone(client) {
        const index = zonedClients.findIndex((object) => {
            return object.client.windowId === client.windowId
        })
        if (index > -1) {
            return zonedClients[index].zone
        } else {
            return -1
        }
    }

    function setZone(client, zone) {
        const index = zonedClients.findIndex((object) => {
            return object.client.windowId === client.windowId
        })
        if (index > -1) {
            console.log("KZones: Updating zone for client " + client.windowId + " to " + zone)
            zonedClients[index].zone = zone
        } else {
            console.log("KZones: Adding client " + client.windowId + " to zone " + zone)
            zonedClients.push({client: {windowId: client.windowId}, zone: zone})
        }
    }

    function rectOverlapArea(component1, component2) {
        let x1 = component1.x + clientArea.x
        let y1 = component1.y + clientArea.y
        let x2 = component1.x + component1.width + clientArea.x
        let y2 = component1.y + component1.height + clientArea.y
        let x3 = component2.x + clientArea.x
        let y3 = component2.y + clientArea.y
        let x4 = component2.x + component2.width + clientArea.x
        let y4 = component2.y + component2.height + clientArea.y
        let xOverlap = Math.max(0, Math.min(x2, x4) - Math.max(x1, x3))
        let yOverlap = Math.max(0, Math.min(y2, y4) - Math.max(y1, y3))
        return xOverlap * yOverlap
    }

    function moveClientToZone(client, zone) {

        // block plasmashell from being moved
        if (client.resourceClass.toString() === "plasmashell") return
        
        console.log("KZones: Moving client " + client.resourceClass.toString() + " to zone " + zone)

        // save current geometry
        if (config.rememberWindowGeometries) {
            let geometry = {
                "windowId": client.windowId,
                "x": client.geometry.x,
                "y": client.geometry.y,
                "width": client.geometry.width,
                "height": client.geometry.height
            }
            const index = oldWindowGeometries.findIndex((object) => {
                return object.windowId === client.windowId
            })
            if (highlightedZone != -1) {
                let higlightedZone = repeater_zones.model[highlightedZone]
                geometry.center_x = ((higlightedZone.x / 100) * clientArea.width + clientArea.x) + (higlightedZone.width / 100) * clientArea.width / 2
                geometry.center_y = ((higlightedZone.y / 100) * clientArea.height + clientArea.y) + (higlightedZone.height / 100) * clientArea.height / 2
                geometry.zone_x = ((higlightedZone.x / 100) * clientArea.width + clientArea.x)
                geometry.zone_y = ((higlightedZone.y / 100) * clientArea.height + clientArea.y)
                if (index > -1) {
                    console.log("KZones: Overwriting geometry for " + client.resourceClass.toString() + " " + JSON.stringify(oldWindowGeometries[index]))
                    oldWindowGeometries[index] = geometry
                } else {
                    oldWindowGeometries.push(geometry)
                    console.log("KZones: Saving geometry for " + client.resourceClass.toString() + ", array size: " + oldWindowGeometries.length)
                }
            } else {
                oldWindowGeometries.splice(index, 1)
            }
        }

        // move client to zone
        if (zone != -1) {
            let targetZone = repeater_zones.model[zone]
            let zone_padding = config.layouts[currentLayout].padding || 0
            client.geometry = Qt.rect(((targetZone.x / 100) * (clientArea.width - zone_padding) + (clientArea.x + zone_padding / 2)) + zone_padding / 2, ((targetZone.y / 100) * (clientArea.height - zone_padding) + (clientArea.y + zone_padding / 2)) + zone_padding / 2, ((targetZone.width / 100) * (clientArea.width - zone_padding)) - zone_padding, ((targetZone.height / 100) * (clientArea.height - zone_padding)) - zone_padding)
        }
        
        // save zone
        setZone(client, zone)
    }

    // fade in animation
    NumberAnimation on opacity {
        id: showAnimation
        from: 0
        to: 1
        duration: config.fadeDuration
    }

    // fade out animation
    NumberAnimation on opacity {
        id: hideAnimation
        from: 1
        to: 0
        duration: config.fadeDuration
    }

    Component.onCompleted: {

        // register window
        KWin.registerWindow(mainDialog)

        // refresh client area
        refreshClientArea()

        // delay the initialization of the overlay until the workspace is ready
        delay.setTimeout(function() {
            mainDialog.visible = true
            mainDialog.opacity = 0
            console.log("KZones: Ready!")
        }, 1000)
        
        // shortcut: cycle through layouts
        bindShortcut("Cycle layouts", "Ctrl+Alt+D", function() {
            // reset timer to prevent osd from being hidden when switching layouts
            if (!moving) {
                hideOSD.running = false
                hideOSD.start()
            }

            //cycle through layouts
            currentLayout = (currentLayout + 1) % config.layouts.length
            highlightedZone = -1
            show()
            if (!config.alwaysShowLayoutName) layoutOsd.visible = true
        })

        // shortcut: move to zone (1-9)
        for (let i = 0; i < 9; i++) {
            bindShortcut(`Move active window to zone ${i+1}`, `Ctrl+Alt+Num+${i+1}`, function() {
                moveClientToZone(workspace.activeClient, i)
            })
        }

        // shortcut: move to next zone
        bindShortcut("Move active window to next zone", "Ctrl+Alt+Right", function() {
            moveClientToZone(workspace.activeClient, (getZone(workspace.activeClient) + 1) % config.layouts[currentLayout].zones.length)
        })

        // shortcut: move to previous zone
        bindShortcut("Move active window to previous zone", "Ctrl+Alt+Left", function() {
            moveClientToZone(workspace.activeClient, (getZone(workspace.activeClient) - 1 + config.layouts[currentLayout].zones.length) % config.layouts[currentLayout].zones.length)
        })

        // shortcut: toggle osd
        bindShortcut("Toggle OSD", "Ctrl+Alt+C", function() {
            if (!inverted) {
                if (!shown) {
                    highlightedZone = -1
                    mainDialog.outputOnly = false
                    show()
                } else {
                    moving = false
                    hide()
                }
            } else {
                // inverted mode
            }
            
        })

        mainDialog.loadConfig()
    }

    function bindShortcut(title, sequence, callback) {
        KWin.registerShortcut(`KZones: ${title}`, `KZones: ${title}`, sequence, callback)
    }

    Item {
        id: mainItem
        width: 420
        height: 69

        // xdotool
        PlasmaCore.DataSource {
            id: xdotool
            engine: "executable"
            connectedSources: []

            property int pos_x: 0
            property int pos_y: 0

            onNewData: {
                let data = xdotool.data["xdotool getmouselocation"].stdout.replace(/ /g, '\u003A').split('\u003A')
                if (data.length > 1) {
                    pos_x = Number(data[1])
                    pos_y = Number(data[3])
                } else {
                    console.log("KZones: xdotool is not installed")
                }
                disconnectSource(sourceName)
                checkZone(handle.x, handle.y, handle.width, handle.height)
            }
        }

        // click to exit osd
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPressed: {
                hide()
            }
        }

        // main polling timer
        Timer {
            id: timer
            triggeredOnStart: true
            interval: config.pollingRate
            running: false
            repeat: true

            onTriggered: {
                switch (config.targetMethod) {
                case 0: // titlebar
                case 1: // window
                    checkZone(handle.x, handle.y, handle.width, handle.height)
                    break
                case 2: // cursor
                    xdotool.connectSource('xdotool getmouselocation')
                    break
                default:
                    break
                }
            }
        }

        // debug handle
        Rectangle {
            id: handle
            color: color_debug_handle
            visible: config.enableDebugMode
            width: {
                if (config.targetMethod == 0 || config.targetMethod == 1) {
                    return (config.handleUnitPercent) ? workspace.activeClient.width * (config.handleSize / 100) : config.handleSize
                }
                else {
                    return 8
                }
            }
            height: {
                if (config.targetMethod == 0) {
                    let titlebarHeight = workspace.activeClient.rect.height - workspace.activeClient.clientSize.height
                    return titlebarHeight > 0 ? titlebarHeight : 32
                }
                else if (config.targetMethod == 1) {
                    return (config.handleUnitPercent) ? workspace.activeClient.height * (config.handleSize / 100) : config.handleSize
                } else {
                    return 8
                }
            }
            x: {
                if (config.targetMethod == 0) {
                    return workspace.activeClient.geometry.x + (workspace.activeClient.geometry.width / 2) - (handle.width / 2)
                }
                else if (config.targetMethod == 1) {
                    let centerpadding_width = (config.handleUnitPercent) ? workspace.activeClient.width * (config.handleSize / 100) : config.handleSize
                    return ((workspace.activeClient.x + workspace.activeClient.width / 2)) - centerpadding_width / 2
                } else {
                    return xdotool.pos_x - 4
                }
            }
            y: {
                if (config.targetMethod == 0) {
                    return workspace.activeClient.geometry.y
                }
                else if (config.targetMethod == 1) {
                    let centerpadding_height = (config.handleUnitPercent) ? workspace.activeClient.height * (config.handleSize / 100) : config.handleSize
                    return ((workspace.activeClient.y + workspace.activeClient.height / 2)) - centerpadding_height / 2
                } else {
                    return xdotool.pos_y - 4
                }
            }
        }

        // debug osd
        Rectangle {
            id: debugOsd
            visible: config.enableDebugMode
            x: clientArea.x
            y: clientArea.y
            z: 100
            width: debugOsdText.paintedWidth + debugOsdText.padding * 2
            height: debugOsdText.paintedHeight + debugOsdText.padding * 2
            radius: 5
            color: "#DD333333"

            Text {
                id: debugOsdText
                anchors.fill: parent
                padding: 15
                color: 'white'
                text: {
                    if (config.enableDebugMode) {
                        let t = ""
                        t += `Active: ${workspace.activeClient.caption}\n`
                        t += `Window class: ${workspace.activeClient.resourceClass.toString()}\n`
                        t += `X: ${workspace.activeClient.geometry.x}, Y: ${workspace.activeClient.geometry.y}, Width: ${workspace.activeClient.geometry.width}, Height: ${workspace.activeClient.geometry.height}\n`
                        t += `Previous Zone: ${getZone(workspace.activeClient)}\n`
                        t += `Highlighted Zone: ${highlightedZone}\n`
                        t += `Layout: ${currentLayout}\n`
                        t += `Zones: ${config.layouts[currentLayout].zones.map(z => z.name).join(', ')}\n`
                        t += `Target Method: ${config.targetMethod}\n`
                        t += `Polling Rate: ${config.pollingRate}ms\n`
                        t += `Handle Size: ${(config.handleUnitPercent) ? config.handleSize + "%" : config.handleSize + "px"}\n`
                        t += `Handle X: ${handle.x}, Y: ${handle.y}, Width: ${handle.width}, Height: ${handle.height}\n`
                        t += `Moving: ${moving}\n`
                        t += `Resizing: ${resizing}\n`
                        t += `Old Window Geometries: ${oldWindowGeometries.length}\n`
                        t += `Zoned Clients: ${zonedClients.length}`
                        t += `Active Screen: ${activeScreen}`
                        return t
                    } else {
                        return ""
                    }                 
                }
                font.pixelSize: 14
                font.family: "Hack"
            }
        }

        // layout name
        Rectangle {
            id: layoutOsd
            visible: true
            opacity: config.layouts[currentLayout].name ? 1 : 0
            x: clientArea.x + clientArea.width / 2 - width / 2
            y: clientArea.y + clientArea.height - 150
            width: layoutName.paintedWidth + 30
            height: layoutName.paintedHeight + 15
            radius: 5
            color: color_indicator

            // layout name label
            Text {
                id: layoutName
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: 'white'
                text: config.layouts[currentLayout].name
                font.pixelSize: 24
            }
        }

        // zones
        Repeater {
            id: repeater_zones
            model: config.layouts[currentLayout].zones

            // zone
            Rectangle {
                id: zone
                x: clientArea.x + ((modelData.x / 100) * (clientArea.width - zone_padding)) + zone_padding
                y: clientArea.y + ((modelData.y / 100) * (clientArea.height - zone_padding)) + zone_padding
                implicitWidth: ((modelData.width / 100) * (clientArea.width - zone_padding)) - zone_padding
                implicitHeight: ((modelData.height / 100) * (clientArea.height - zone_padding)) - zone_padding
                color: (highlightedZone == zoneIndex) ? color_zone_background_active : color_zone_background
                radius: 8 // TODO: make configurable (zoneRadius)
                border.color: (highlightedZone == zoneIndex) ? color_zone_border_active : color_zone_border
                border.width: 3

                property int zoneIndex: index
                property int zone_padding: config.layouts[currentLayout].padding || 0

                // zone indicator
                Rectangle {
                    id: indicator
                    width: 160 //180 // TODO: make configurable (indicatorWidth)
                    height: 90 //100 // TODO: make configurable (indicatorHeight)
                    radius: 5
                    color: config.alternateIndicatorStyle ? color_indicator : 'transparent'
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        horizontalCenterOffset: (((modelData || {}).indicator || {}).offset || {}).x || 0
                        verticalCenter: parent.verticalCenter
                        verticalCenterOffset: (((modelData || {}).indicator || {}).offset || {}).y || 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: {
                            moveClientToZone(workspace.activeClient, zone.zoneIndex)
                            hide()
                        }
                        onEntered: {
                            highlightedZone = zone.zoneIndex
                        }
                        onExited: {
                            highlightedZone = -1
                        }
                    }

                    // zone indicator part
                    Repeater {
                        id: indicators
                        model: config.layouts[currentLayout].zones

                        Rectangle {
                            property int padding: config.alternateIndicatorStyle ? 0 : 3
                            radius: 5
                            visible: config.alternateIndicatorStyle ? ((index == zone.zoneIndex) ? true : false) : true
                            x: ((modelData.x / 100) * (indicator.width - padding)) + padding
                            y: ((modelData.y / 100) * (indicator.height - padding)) + padding
                            z: (index == zone.zoneIndex) ? 2 : 1
                            implicitWidth: ((modelData.width / 100) * (indicator.width - padding)) - padding
                            implicitHeight: ((modelData.height / 100) * (indicator.height - padding)) - padding
                            color: (index == zone.zoneIndex) ? color_indicator_accent : color_indicator
                            opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 0.25 // TODO: add opacity to config
                        }
                    }

                    // zone indicator label
                    Text {
                        z: 3
                        anchors.fill: indicator
                        font.pixelSize: 20
                        opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 0.25 // TODO: add opacity to config
                        color: color_indicator_font
                        leftPadding: 30
                        rightPadding: 30
                        topPadding: 30
                        bottomPadding: 30
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.name
                    }
                }

                // zone indicator shadow
                DropShadow {
                    id: rectShadow
                    anchors.fill: indicator
                    cached: true
                    horizontalOffset: 0
                    verticalOffset: 0
                    radius: 16
                    samples: 33
                    color: color_indicator_shadow
                    smooth: true
                    source: indicator
                }

            }

        }

        // workspace connection
        Connections {
            target: workspace

            function onClientActivated(client) {
                if (client) console.log("KZones: Client activated: " + client.resourceClass.toString())
            }
        }

        // options connection
        Connections {
            //! not working at the moment
            target: options

            function onConfigChanged() {
                console.log("KZones: Config changed")
                mainDialog.loadConfig()
            }
        }

        // activeClient connection
        Connections {
            target: workspace.activeClient

            // start moving
            function onClientStartUserMovedResized(client) {
                if (client.resizeable) {
                    if (client.move && checkFilter(client)) {
                        moving = true
                        resizing = false
                        hideOSD.running = false
                        console.log("KZones: Move start " + client.resourceClass.toString())
                        mainDialog.show()
                        timer.running = true
                    }
                    if (client.resize) {
                        moving = false
                        resizing = true
                        // client resizing
                    }
                }
            }

            // is moving
            function onClientStepUserMovedResized(client, r) {
                if (client.resizeable) {
                    if (moving && checkFilter(client)) {
                        // refresh client area
                        refreshClientArea()
                        if (config.rememberWindowGeometries) {
                            const index = oldWindowGeometries.findIndex((object) => {
                                return object.windowId === client.windowId
                            })
                            if (index > -1) {
                                let geometry = oldWindowGeometries[index]
                                client.geometry = Qt.rect((r.x - geometry.zone_x) + (geometry.center_x - geometry.width / 2), r.y, geometry.width, geometry.height)
                            }
                        }
                    }
                    if (resizing) {
                        // client resizing
                    }
                }
            }

            // stop moving
            function onClientFinishUserMovedResized(client) {
                if (moving) {
                    console.log("Kzones: Move end " + client.resourceClass.toString())
                    mainDialog.hide()
                    timer.running = false
                    moveClientToZone(client, highlightedZone)
                    hide()
                }
                if (resizing) {
                    // client resizing
                }
                moving = false
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

        // hide osd timer
        Timer {
            id: hideOSD
            interval: config.osdTimeout
            repeat: false

            onTriggered: {
                hide()
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