import QtQuick
import QtQuick.Layouts

import "../components" as Components

ColumnLayout {
    property var config: {}
    property var info: {}
    property var errors: []
    
    z: 100
    anchors.left: parent.left
    anchors.leftMargin: 20
    anchors.top: parent.top
    anchors.topMargin: 20
    spacing: 10

    Rectangle {
        visible: config.enableDebugOverlay
        Layout.preferredWidth: children[0].paintedWidth + children[0].padding * 2
        Layout.preferredHeight: children[0].paintedHeight + children[0].padding * 2
        color: colorHelper.backgroundColor
        radius: 5

        Text {
            anchors.fill: parent
            padding: 15
            color: colorHelper.textColor
            text: JSON.stringify(info, null, 2)
            font.pixelSize: 14
            font.family: "Hack"
        }
    }

    Repeater {
        model: errors

        Rectangle {
        
            Layout.preferredWidth: children[0].paintedWidth + children[0].padding * 2
            Layout.preferredHeight: children[0].paintedHeight + children[0].padding * 2
            color: colorHelper.backgroundColor
            radius: 5

            Text {
                anchors.fill: parent
                padding: 15
                color: "red"
                text: modelData
                font.pixelSize: 14
                font.family: "Hack"
            }
        }
    }

    Components.ColorHelper {
        id: colorHelper
    }

}
