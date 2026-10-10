import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "dpi"
        function toggle(): void { win.visible = !win.visible; if (win.visible) query.running = true }
    }
    id: root
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

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool accent: false
        signal clicked()
        radius: 10
        color: area.containsMouse ? Qt.rgba(255/255, 85/255, 85/255, 0.12) : "transparent"
        border.width: 1
        border.color: b.accent ? "#ff5555" : "#888888"
        Text {
            anchors.centerIn: parent
            text: b.label
            color: b.accent ? "#ff5555" : "#e5e5e5"
            font.pixelSize: 18
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }

    FloatingWindow {
        title: "Display Scale"
        implicitWidth: 340
        implicitHeight: 250
        color: Qt.rgba(24/255, 16/255, 16/255, 0.88)   // Warm dark red-tinted background with transparency
        id: win
        visible: false

        Column {
            anchors.centerIn: parent
            spacing: 18

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "DISPLAY SCALE"
                color: "#888888"
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                Btn { width: 56; height: 56; label: "−"; onClicked: root.nudge(-0.1) }

                Text {
                    width: 120
                    height: 56
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Math.round(root.dpiScale * 100) + "%"
                    color: "#ff5555"
                    font.pixelSize: 34
                    font.bold: true
                }

                Btn { width: 56; height: 56; label: "+"; onClicked: root.nudge(0.1) }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    model: [1.0, 1.25, 1.5, 2.0]
                    Btn {
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
