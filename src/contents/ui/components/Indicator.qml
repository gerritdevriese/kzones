import QtQuick
import "../components" as Components

Rectangle {
    id: indicator

    property alias repeater: indicators
    property int activeZone: 0
    property bool hovering: false
    property var zones: []
    property color cardColor: "transparent"

    implicitWidth: 120
    implicitHeight: 75
    width: parent ? parent.width : implicitWidth
    height: parent ? parent.height : implicitHeight
    color: cardColor
    radius: 6
    border.color: hovering ? colorHelper.accentColor : (cardColor != "transparent" ? colorHelper.getBorderColor(color) : "transparent")
    border.width: hovering ? 2 : 1
    opacity: 1

    Repeater {
        id: indicators

        model: zones

        Item {
            id: zone

            x: ((modelData.x / 100) * (indicator.width))
            y: ((modelData.y / 100) * (indicator.height))
            width: ((modelData.width / 100) * (indicator.width))
            height: ((modelData.height / 100) * (indicator.height))
            z: activeZone == index ? 1 : 0

            Rectangle {
                property int padding: 2

                anchors.fill: parent
                anchors.margins: padding
                color: {
                    if (activeZone == index)
                        return modelData.color ? colorHelper.tintWithAlpha(colorHelper.buttonColor, modelData.color, 0.6) : colorHelper.accentColor;
                    else
                        return modelData.color ? colorHelper.tintWithAlpha(colorHelper.buttonColor, modelData.color, 0.2) : colorHelper.buttonColor;
                }
                border.color: colorHelper.getBorderColor(color)
                border.width: 1
                radius: 4

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }
        }
    }

    Components.ColorHelper {
        id: colorHelper
    }
}
