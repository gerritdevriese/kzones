import QtGraphicalEffects 1.0
import QtQuick 2.15

Rectangle {
    id: indicator
    property int activeZone: 0
    property bool hovering: false
    property var zones: []
    width: parent.width
    height: parent.height
    color: "transparent"
    opacity: 1

    Repeater {
        id: indicators
        model: zones

        Rectangle {
            id: zone
            x: ((modelData.x / 100) * (indicator.width)) 
            y: ((modelData.y / 100) * (indicator.height)) 
            width: ((modelData.width / 100) * (indicator.width)) 
            height: ((modelData.height / 100) * (indicator.height))
            color: "transparent"

            Rectangle {
                property int padding: 2
                anchors.fill: parent
                anchors.margins: padding
                color: (activeZone == index) ? (hovering ? color_indicator_accent : "#666666") : "#333333"
                radius: 5
                border.color: (activeZone == index) ? (hovering ? color_indicator_accent : "#555555") : "#555555"
                border.width: 1

                // z: (activeZone == index) ? 2 : 1
                // scale: (doAnimations) ? ((activeZone == index && hovering) ? 1.1 : 1) : 1
                // Behavior on scale {
                //     NumberAnimation { duration: 150 }
                // }
            }            

        }

    }

}