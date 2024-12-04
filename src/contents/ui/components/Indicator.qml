import QtQuick
import org.kde.kirigami as Kirigami

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

        Item {
            id: zone
            x: ((modelData.x / 100) * (indicator.width)) 
            y: ((modelData.y / 100) * (indicator.height)) 
            width: ((modelData.width / 100) * (indicator.width)) 
            height: ((modelData.height / 100) * (indicator.height))

            Rectangle {
                property int padding: 2
                anchors.fill: parent
                anchors.margins: padding
                Kirigami.Theme.colorSet: Kirigami.Theme.Button
                Kirigami.Theme.inherit: false
                color: {
                    if (activeZone == index) {
                        return modelData.color ? Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, modelData.color || Qt.rgba(1,1,1), 0.8) : Kirigami.Theme.highlightColor
                    } else {
                        return modelData.color ? Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, modelData.color, 0.2) :  Kirigami.Theme.backgroundColor
                    }
                }
                border.color: Kirigami.ColorUtils.tintWithAlpha(color, Kirigami.Theme.textColor, 0.2)
                border.width: 1
                radius: 5

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }            

        }

    }

}
