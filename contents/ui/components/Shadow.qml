import QtQuick 2.15
import QtGraphicalEffects 1.0

DropShadow {
    property Item target : null
    anchors.fill: target
    visible: target.visible
    opacity: target.opacity
    scale: target.scale
    cached: true
    horizontalOffset: 0
    verticalOffset: 0
    radius: 32
    samples: (radius*2)+1
    color: color_indicator_shadow
    smooth: true
    source: target
}