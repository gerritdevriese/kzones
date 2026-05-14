import "../components" as Components
import QtQuick
import QtQuick.Layouts

Item {
    id: zones

    property var config
    property int currentLayout
    property int highlightedZone
    property int layoutIndex
    property alias repeater: repeater
    // When set, render these zones instead of `config.layouts[layoutIndex].zones`.
    // Lets the fullscreen-drag preview reuse this component with a synthetic
    // single-zone layout covering the whole monitor.
    property var overrideZones: null
    property int overridePadding: -1
    property bool overrideAlwaysActive: false

    function _layout() {
        return config && config.layouts && config.layouts[layoutIndex];
    }

    function _zones() {
        if (overrideZones)
            return overrideZones;

        const l = _layout();
        return (l && l.zones) || [];
    }

    function _padding() {
        if (overridePadding >= 0)
            return overridePadding;

        const l = _layout();
        return (l && l.padding) || 0;
    }

    Repeater {
        id: repeater

        model: zones._zones()

        // zone
        Item {
            id: zone

            property int zoneIndex: index
            property int zonePadding: zones._padding()
            property var renderZones: overrideZones ? overrideZones : (config.zoneOverlayIndicatorDisplay == 1 ? [zones._zones()[index]] : zones._zones())
            property int activeIndex: (overrideZones || config.zoneOverlayIndicatorDisplay == 1) ? 0 : index
            property var indicatorPos: (modelData && modelData.indicator && modelData.indicator.position) || "center"
            property bool active: overrideAlwaysActive || (highlightedZone == zoneIndex && currentLayout == layoutIndex)

            x: ((modelData.x / 100) * (clientArea.width - zonePadding)) + zonePadding
            y: ((modelData.y / 100) * (clientArea.height - zonePadding)) + zonePadding
            implicitWidth: ((modelData.width / 100) * (clientArea.width - zonePadding)) - zonePadding
            implicitHeight: ((modelData.height / 100) * (clientArea.height - zonePadding)) - zonePadding

            // zone indicator
            Rectangle {
                id: zoneIndicator

                width: 160
                height: 100
                color: colorHelper.backgroundColor
                radius: 10
                border.color: colorHelper.getBorderColor(color)
                border.width: 1
                opacity: !showZoneOverlay ? 0 : (zoneSelector.expanded) ? 0 : (active ? 0.6 : 1)
                scale: active ? 1.1 : 1
                visible: config.enableZoneOverlay
                // position
                anchors.left: (indicatorPos === "top-left" || indicatorPos === "left-center" || indicatorPos === "bottom-left") ? parent.left : undefined
                anchors.right: (indicatorPos === "top-right" || indicatorPos === "right-center" || indicatorPos === "bottom-right") ? parent.right : undefined
                anchors.top: (indicatorPos === "top-left" || indicatorPos === "top-center" || indicatorPos === "top-right") ? parent.top : undefined
                anchors.bottom: (indicatorPos === "bottom-left" || indicatorPos === "bottom-center" || indicatorPos === "bottom-right") ? parent.bottom : undefined
                anchors.horizontalCenter: (indicatorPos === "center" || indicatorPos === "top-center" || indicatorPos === "bottom-center") ? parent.horizontalCenter : undefined
                anchors.verticalCenter: (indicatorPos === "center" || indicatorPos === "left-center" || indicatorPos === "right-center") ? parent.verticalCenter : undefined
                // margin
                anchors.leftMargin: (modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.left) || 0
                anchors.rightMargin: (modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.right) || 0
                anchors.topMargin: (modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.top) || 0
                anchors.bottomMargin: (modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.bottom) || 0
                // offset
                anchors.horizontalCenterOffset: ((modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.left) || 0) - ((modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.right) || 0)
                anchors.verticalCenterOffset: ((modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.top) || 0) - ((modelData && modelData.indicator && modelData.indicator.margin && modelData.indicator.margin.bottom) || 0)

                Components.Indicator {
                    zones: renderZones
                    activeZone: activeIndex
                    anchors.centerIn: parent
                    width: parent.width - 20
                    height: parent.height - 20
                    hovering: (active)
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: zoneSelector.expanded ? 0 : 150
                    }

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }

                }

            }

            Components.ZoneHighlight {
                anchors.fill: parent
                active: zone.active
                tint: modelData.color || colorHelper.accentColor
            }

            // indicator shadow
            Components.Shadow {
                target: zoneIndicator
                visible: zoneIndicator.visible
            }

            Components.ColorHelper {
                id: colorHelper
            }

        }

    }

}
