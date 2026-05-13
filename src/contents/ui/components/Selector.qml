import "../components" as Components
import QtQuick
import QtQuick.Layouts

Item {
    id: selector

    property var config
    property int currentLayout
    property int highlightedZone
    // [{ layout, index }, ...] — the layouts to display for the active screen.
    // `index` is the position in the unfiltered config.layouts.
    property var availableLayouts: []
    property bool expanded: false
    property bool near: false
    property bool animating: false
    property alias repeater: repeater

    visible: false
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: expanded ? 0 : (near ? -height + 30 : -height)
    width: background.width + 30
    height: background.height + 40

    Rectangle {
        id: background

        width: row.implicitWidth + row.spacing * 2
        height: row.implicitHeight + row.spacing * 2
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 15
        color: colorHelper.backgroundColor
        radius: 10
        border.color: colorHelper.getBorderColor(color)
        border.width: 1

        RowLayout {
            id: row

            spacing: 15
            anchors.fill: parent
            anchors.margins: spacing

            Repeater {
                id: repeater

                model: availableLayouts

                Components.Indicator {
                    zones: modelData.layout.zones
                    activeZone: (currentLayout === modelData.index) ? highlightedZone : -1
                    width: 160 - 30
                    height: 100 - 30
                    hovering: (currentLayout === modelData.index)
                }

            }

        }

    }

    Components.Shadow {
        target: background
        visible: true
    }

    Components.ColorHelper {
        id: colorHelper
    }

    Behavior on anchors.topMargin {
        NumberAnimation {
            duration: 150
            onRunningChanged: {
                if (!running)
                    selector.visible = true;

                selector.animating = running;
            }
        }

    }

}
