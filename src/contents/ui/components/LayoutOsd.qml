import "../components" as Components
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore

// Small OSD popup that shows the active layout's tile preview + its name.
// Replaces the generic icon used by the system OSD when cycling layouts so
// the user can see at a glance which arrangement they just switched to.
PlasmaCore.Dialog {
    id: layoutOsd

    property var zones: []
    property string label: ""
    property int hideDelay: 1500
    // Screen the caller wants the popup centred under (e.g. the screen
    // whose active layout just changed). Read at show() time so we don't
    // depend on Workspace.activeScreen, which may not reflect the screen
    // the user just acted on.
    property var targetScreen: null

    function show(zonesArg, labelArg, screenArg) {
        layoutOsd.zones = zonesArg || [];
        layoutOsd.label = labelArg || "";
        layoutOsd.targetScreen = screenArg || Workspace.activeScreen;
        layoutOsd.visible = true;
        Qt.callLater(reposition);
        hideTimer.restart();
    }

    function reposition() {
        const scr = layoutOsd.targetScreen && layoutOsd.targetScreen.geometry;
        if (!scr)
            return ;

        layoutOsd.x = Math.round(scr.x + scr.width / 2 - layoutOsd.width / 2);
        layoutOsd.y = Math.round(scr.y + scr.height - layoutOsd.height - 80);
    }

    type: PlasmaCore.Dialog.OnScreenDisplay
    location: PlasmaCore.Types.Floating
    flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
    hideOnWindowDeactivate: false
    visible: false
    width: osdContent.implicitWidth
    height: osdContent.implicitHeight
    onWidthChanged: reposition()
    onHeightChanged: reposition()
    onVisibleChanged: {
        if (visible)
            reposition();

    }

    Item {
        id: osdContent

        implicitWidth: row.implicitWidth + 24
        implicitHeight: row.implicitHeight + 16

        Timer {
            id: hideTimer

            interval: layoutOsd.hideDelay
            repeat: false
            onTriggered: layoutOsd.visible = false
        }

        Components.ColorHelper {
            id: colorHelper
        }

        RowLayout {
            id: row

            anchors.fill: parent
            anchors.margins: 8
            spacing: 12

            Components.Indicator {
                id: preview

                Layout.preferredWidth: 64
                Layout.preferredHeight: 40
                zones: layoutOsd.zones
                activeZone: -1
                hovering: false
            }

            Text {
                id: labelText

                text: layoutOsd.label
                color: colorHelper.textColor
                verticalAlignment: Text.AlignVCenter
                font.pointSize: 11
                Layout.preferredWidth: implicitWidth
            }

        }

    }

}
