// File: ~/viii-shell-2/shell/DpiWindow.qml
// The display-scale panel (same wlr-randr logic as before), hive style.
// Created by DpiPanel.qml on the first toggle, destroyed shortly after closing.
import QtQuick
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root
    title: "Display Scale"
    visible: true
    implicitWidth: 340
    implicitHeight: 260
    color: "transparent"

    property bool shown: false           // set by DpiPanel.qml
    signal closeRequested()

    // 0 = hidden, 1 = open. Starts at 0 and fades in once created.
    property real appear: 0
    Behavior on appear { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Component.onCompleted: {
        appear = Qt.binding(() => root.shown ? 1 : 0)
        query.running = true             // read the current scale when the panel opens
    }
    onVisibleChanged: if (!visible) closeRequested()

    property real dpiScale: 1.0
    property var outputs: []

    function clamp(v) { return Math.max(0.5, Math.min(3.0, Math.round(v * 20) / 20)) }
    function nudge(d) { dpiScale = clamp(dpiScale + d); applyTimer.restart() }
    function setTo(v) { dpiScale = v; applyTimer.restart() }

    Process {
        id: query
        command: ["wlr-randr", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const on = JSON.parse(text).filter(o => o.enabled)
                root.outputs = on.map(o => o.name)
                if (on.length > 0) root.dpiScale = on[0].scale
            }
        }
    }

    Process { id: apply }

    Timer {
        id: applyTimer
        interval: 300
        onTriggered: {
            let cmd = ["wlr-randr"]
            for (const n of root.outputs)
                cmd.push("--output", n, "--scale", root.dpiScale.toFixed(2))
            apply.command = cmd
            apply.running = true
        }
    }

    // A chamfered text button (the presets)
    component ChamBtn: ChamferPanel {
        id: b
        property string label: ""
        property bool accent: false
        signal clicked()
        cut: 8
        fillColor: area.containsMouse ? Theme.surface : "transparent"
        strokeColor: b.accent ? Theme.accent : Theme.line
        Text {
            anchors.centerIn: parent
            text: b.label
            color: b.accent ? Theme.accentHi : Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }

    ChamferPanel {
        anchors.fill: parent
        cut: 18
        pattern: true
        opacity: root.appear

        Column {
            anchors.centerIn: parent
            spacing: 20

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                HexShape {
                    width: 12; height: 12 / 1.1547
                    anchors.verticalCenter: parent.verticalCenter
                    fillColor: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DISPLAY SCALE"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.letterSpacing: 3
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                HexButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 58; glyphSize: 26; outlined: true
                    glyph: "−"
                    onClicked: root.nudge(-0.1)
                }

                Text {
                    width: 110
                    height: 58
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Math.round(root.dpiScale * 100) + "%"
                    color: Theme.accentHi
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 32
                    font.bold: true
                }

                HexButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 58; glyphSize: 26; outlined: true
                    glyph: "+"
                    onClicked: root.nudge(0.1)
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    model: [1.0, 1.25, 1.5, 2.0]
                    ChamBtn {
                        required property var modelData
                        width: 62
                        height: 34
                        label: Math.round(modelData * 100) + "%"
                        accent: Math.abs(root.dpiScale - modelData) < 0.01
                        onClicked: root.setTo(modelData)
                    }
                }
            }
        }
    }
}
