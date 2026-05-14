import QtQuick

// Shared visual for an "active" zone area: a soft tinted fill plus a 3px
// accent border. Used by Zones.qml for per-zone highlight and by the
// top-level fullscreen-snap preview so both share one rendering
// definition.
Item {
    id: highlight

    property bool active: false
    property color tint: colorHelper.accentColor
    property real backgroundOpacity: 0.1
    property int borderWidth: 3
    property int cornerRadius: 8

    ColorHelper {
        id: colorHelper
    }

    Rectangle {
        id: highlightBackground

        anchors.fill: parent
        color: tint
        radius: cornerRadius
        opacity: active ? backgroundOpacity : 0
    }

    Rectangle {
        id: highlightBorder

        anchors.fill: parent
        color: "transparent"
        border.color: active ? tint : "transparent"
        border.width: borderWidth
        radius: cornerRadius
    }

}
