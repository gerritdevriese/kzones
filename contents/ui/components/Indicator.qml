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
                Kirigami.Theme.colorSet: Kirigami.Theme.View
                Kirigami.Theme.inherit: false
                color: (activeZone == index) ? Kirigami.Theme.hoverColor : Kirigami.ColorUtils.tintWithAlpha( Kirigami.Theme.backgroundColor, Qt.rgba(1,1,1), 0.1)
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
