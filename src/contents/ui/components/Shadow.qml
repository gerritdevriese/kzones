import QtQuick
import Qt5Compat.GraphicalEffects

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
    color: '#69000000'
    smooth: true
    source: target
}
