import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property int range: 1
    property int offset: 0
    property var days: []
    property var apps: []
    property real progress: 0
    property int hoverIdx: -1

    property int totalSecs: {
        if (days.length === 0) return 0
        if (range === 1) return days[Math.max(0, days.length - 1 - offset)].secs
        return days.reduce((s, x) => s + x.secs, 0)
    }
    property int maxDay: Math.max(1, ...days.map(x => x.secs))
    property int denom: Math.max(1, totalSecs)
    readonly property var palette: ["#3b82f6", "#7fd4ff", "#ffd479", "#ff9fb2", "#c3a6ff", "#ffb07a", "#e5e5e5", "#888888"]

    function fmt(s) {
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m"
        return s + "s"
    }
    function dayName(iso) {
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][new Date(iso + "T00:00:00").getDay()]
    }
    function pretty(n) {
        const p = n.split(".")
        const last = p[p.length - 1]
        return last.charAt(0).toUpperCase() + last.slice(1)
    }
    function parse(text) {
        const d = [], a = []
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p.length < 3) continue
            if (p[0] === "DAY") d.push({ label: dayName(p[1]), secs: parseInt(p[2]) })
            else if (p[0] === "APP") a.push({ name: p[1], secs: parseInt(p[2]) })
        }
        days = d
        apps = a
    }
    function lp(i, n) {
        return Math.max(0, Math.min(1, progress * (1 + 0.08 * (n - 1)) - i * 0.08))
    }
    function refresh() {
        anim.stop()
        progress = 0
        report.running = true
    }

    function setView(r, o) {
        range = r
        offset = o
        if (win.visible) refresh()
    }

    IpcHandler {
        target: "screentime"
        function toggle(): void {
            win.visible = !win.visible
            if (win.visible) root.refresh()
            else anim.stop()
        }
    }

    NumberAnimation {
        id: anim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 1300
        easing.type: Easing.OutCubic
    }

    Process {
        id: report
        command: [Quickshell.env("HOME") + "/.local/bin/screentime-report", String(root.range), String(root.offset)]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parse(text)
                if (win.visible) anim.restart()
            }
        }
    }

    component Tab: Rectangle {
        id: t
        property string label: ""
        property bool active: false
        signal clicked()
        radius: 10
        width: 74
        height: 28
        color: "transparent"
        border.width: 1
        border.color: t.active ? "#3b82f6" : "#888888"
        Text {
            anchors.centerIn: parent
            text: t.label
            color: t.active ? "#60a5fa" : "#e5e5e5"
            font.pixelSize: 12
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: t.clicked()
        }
    }

    FloatingWindow {
        id: win
        visible: false
        title: "Screen Time"
        implicitWidth: 440
        implicitHeight: 640
        color: Qt.rgba(16/255, 20/255, 28/255, 0.88)   // Warm dark blue-tinted background with transparency
        onVisibleChanged: if (!visible) anim.stop()

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SCREEN TIME"
                    color: "#888888"
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Tab { label: "Today"; active: root.range === 1 && root.offset === 0; onClicked: root.setView(1, 0) }
                    Tab { label: "Yesterday"; active: root.range === 1 && root.offset === 1; onClicked: root.setView(1, 1) }
                    Tab { label: "7 days"; active: root.range === 7; onClicked: root.setView(7, 0) }
                }
            }

            Text {
                text: root.fmt(Math.round(root.totalSecs * root.progress))
                color: "#60a5fa"
                font.pixelSize: 40
                font.bold: true
            }

            Item {
                id: chart
                width: parent.width
                height: 140

                Row {
                    anchors.fill: parent
                    spacing: 8

                    Repeater {
                        model: root.days
                        readonly property bool isToday: root.range === 1
                            ? index === root.days.length - 1 - root.offset
                            : index === root.days.length - 1

                        Item {
                            id: col
                            width: (chart.width - 48) / 7
                            height: chart.height
                            readonly property real local: root.lp(index, root.days.length)
                            readonly property bool isToday: index === root.days.length - 1

                            Text {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.fmt(Math.round(modelData.secs * col.local))
                                color: col.isToday ? "#60a5fa" : "#e5e5e5"
                                font.pixelSize: 10
                                opacity: (col.isToday || root.hoverIdx === index) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            Rectangle {
                                id: track
                                anchors.top: parent.top
                                anchors.topMargin: 22
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 10
                                height: 92
                                radius: 5
                                color: Qt.rgba(255, 255, 255, 0.06)

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: modelData.secs > 0
                                        ? track.height * Math.max(0.05, modelData.secs / root.maxDay) * col.local
                                        : 0
                                    radius: Math.min(5, height / 2)
                                    color: col.isToday ? "#3b82f6" : "#888888"
                                }
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: "#888888"
                                font.pixelSize: 11
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.hoverIdx = index
                                onExited: if (root.hoverIdx === index) root.hoverIdx = -1
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#888888"; opacity: 0.4 }

            Text {
                text: "MOST USED"
                color: "#888888"
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Text {
                visible: root.apps.length === 0
                text: "No data yet. The tracker logs once a minute."
                color: "#888888"
                font.pixelSize: 13
            }

            Item {
                id: share
                visible: root.apps.length > 0
                width: parent.width
                height: 10

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: Qt.rgba(255, 255, 255, 0.06)
                }

                Row {
                    spacing: 2
                    height: parent.height

                    Repeater {
                        model: root.apps

                        Rectangle {
                            height: share.height
                            radius: 5
                            width: (modelData.secs / root.denom)
                                   * (share.width - 2 * Math.max(0, root.apps.length - 1))
                                   * root.progress
                            visible: width > 1
                            color: root.palette[index % root.palette.length]
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10

                Repeater {
                    model: root.apps

                    Item {
                        id: row
                        width: parent.width
                        height: 20
                        readonly property real local: root.lp(index, root.apps.length)
                        opacity: local

                        Rectangle {
                            id: dot
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.palette[index % root.palette.length]
                        }
                        Text {
                            anchors.left: dot.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.pretty(modelData.name)
                            color: "#e5e5e5"
                            font.pixelSize: 14
                        }
                        Text {
                            id: timeText
                            width: 70
                            horizontalAlignment: Text.AlignRight
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fmt(Math.round(modelData.secs * row.local))
                            color: "#e5e5e5"
                            font.pixelSize: 14
                        }
                        Text {
                            width: 40
                            horizontalAlignment: Text.AlignRight
                            anchors.right: timeText.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(modelData.secs / root.denom * 100 * row.local) + "%"
                            color: "#888888"
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}
