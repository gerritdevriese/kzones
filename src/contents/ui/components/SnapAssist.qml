import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

Item {
    id: snapAssist

    property var targetRect: Qt.rect(0, 0, 400, 300)
    property var candidates: []
    signal windowSelected(var client)
    signal dismissed()

    x: targetRect ? targetRect.x : 0
    y: targetRect ? targetRect.y : 0
    width: targetRect ? targetRect.width : 400
    height: targetRect ? targetRect.height : 300
    visible: width > 50 && height > 50

    Shortcut {
        sequence: "Escape"
        onActivated: snapAssist.dismissed()
    }

    // Prevent clicks inside the card from falling through to the dismiss backdrop
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    Rectangle {
        id: card

        anchors.fill: parent
        anchors.margins: 8
        color: colorHelper.tintWithAlpha(colorHelper.backgroundColor, "black", 0.45)
        radius: 10
        border.color: colorHelper.getBorderColor(color)
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Kirigami.Icon {
                    source: "window-duplicate"
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                }

                Text {
                    text: "Snap Assist"
                    font.bold: true
                    font.pixelSize: 13
                    color: colorHelper.textColor
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: closeMouse.containsMouse ? colorHelper.accentColor : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 12
                        color: colorHelper.textColor
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: snapAssist.dismissed()
                    }
                }
            }

            // Candidates grid
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: snapAssist.candidates
                boundsBehavior: Flickable.StopAtBounds

                readonly property int cols: {
                    if (candidates.length <= 1) return 1;
                    if (grid.width > 700 && candidates.length >= 3) return 3;
                    if (grid.width > 350 && candidates.length >= 2) return 2;
                    return 1;
                }

                cellWidth: grid.width / Math.max(1, cols)
                cellHeight: {
                    const rows = Math.max(1, Math.ceil(candidates.length / Math.max(1, cols)));
                    const idealH = grid.height / rows;
                    return Math.min(240, Math.max(120, idealH));
                }

                delegate: Item {
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: itemCard
                        anchors.fill: parent
                        anchors.margins: 6
                        color: itemMouse.containsMouse
                            ? colorHelper.tintWithAlpha(colorHelper.backgroundColor, colorHelper.accentColor, 0.25)
                            : colorHelper.tintWithAlpha(colorHelper.backgroundColor, colorHelper.buttonColor, 0.35)
                        radius: 8
                        border.color: itemMouse.containsMouse ? colorHelper.accentColor : colorHelper.getBorderColor(color)
                        border.width: itemMouse.containsMouse ? 2 : 1
                        clip: true
                        scale: itemMouse.containsMouse ? 1.02 : 1.0

                        Behavior on scale {
                            NumberAnimation { duration: 100 }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            // Window title bar inside card
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Kirigami.Icon {
                                    source: modelData.icon || "applications-other"
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                }

                                Text {
                                    text: modelData.caption || "Window"
                                    elide: Text.ElideRight
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: colorHelper.textColor
                                    Layout.fillWidth: true
                                }
                            }

                            // Window thumbnail / preview
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                KWinComponents.WindowThumbnail {
                                    anchors.fill: parent
                                    client: modelData
                                    wId: modelData.internalId !== undefined ? modelData.internalId : (modelData.windowId !== undefined ? modelData.windowId : 0)
                                    visible: !modelData.minimized
                                }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 48
                                    height: 48
                                    source: modelData.icon || "applications-other"
                                    visible: modelData.minimized
                                }
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                snapAssist.windowSelected(modelData);
                            }
                        }
                    }
                }
            }
        }
    }

    ColorHelper {
        id: colorHelper
    }
}
