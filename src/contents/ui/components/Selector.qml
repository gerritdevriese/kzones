import QtQuick
import QtQuick.Layouts
import "../components" as Components

Item {
    id: selector

    property var config
    property int currentLayout
    property int highlightedZone
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

        width: grid.implicitWidth + 30
        height: grid.implicitHeight + 30
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 15
        color: colorHelper.backgroundColor
        radius: 12
        border.color: colorHelper.getBorderColor(color)
        border.width: 1

        GridLayout {
            id: grid

            columns: 4
            rowSpacing: 10
            columnSpacing: 10
            anchors.centerIn: parent

            Repeater {
                id: repeater

                model: config.layouts

                Components.Indicator {
                    zones: modelData.zones
                    activeZone: (currentLayout == index) ? highlightedZone : -1
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 75
                    width: 120
                    height: 75
                    cardColor: (currentLayout == index) ? colorHelper.tintWithAlpha(colorHelper.backgroundColor, colorHelper.accentColor, 0.2) : colorHelper.tintWithAlpha(colorHelper.backgroundColor, colorHelper.buttonColor, 0.3)
                    hovering: (currentLayout == index)
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
