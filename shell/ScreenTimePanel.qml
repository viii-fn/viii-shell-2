import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // The controller stays resident for IPC. The expensive window is lazy-loaded.
    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 600

    onShownChanged: {
        if (shown) {
            unload.stop()
            alive = true
        } else {
            unload.restart()
        }
    }

    Timer {
        id: unload
        interval: root.closeMs
        onTriggered: root.alive = false
    }

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
    readonly property var palette: Theme.chart

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
        if (root.shown) refresh()
    }

    IpcHandler {
        target: "screentime"
        function toggle(): void {
            root.shown = !root.shown
            if (root.shown) root.refresh()
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
                if (root.shown) anim.restart()
            }
        }
    }

    component RangeTab: Item {
        id: tab
        property string label: ""
        property bool active: false
        signal clicked()
        implicitWidth: labelText.implicitWidth + 22
        implicitHeight: 30

        ChamferPanel {
            anchors.fill: parent
            cut: 7
            fillColor: tab.active
                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.17)
                : (hit.containsMouse ? Theme.surfaceHi : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55))
            strokeColor: tab.active ? Theme.accent : Theme.line
        }
        Text {
            id: labelText
            anchors.centerIn: parent
            text: tab.label
            color: tab.active ? Theme.accentHi : Theme.fgDim
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.clicked()
        }
    }

    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Screen Time"
            implicitWidth: 490
            implicitHeight: 690
            color: "transparent"
            onVisibleChanged: if (!visible) { anim.stop(); root.shown = false }

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }

            ChamferPanel {
                id: frame
                anchors.fill: parent
                cut: 20
                pattern: true
                patternOpacity: 0.075
                fillColor: Theme.panel
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    // Compact identity row: small hex marker, title, and range controls.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        HexButton {
                            size: 30
                            glyph: "\uf1da"
                            glyphSize: 13
                            outlined: true
                            interactive: false
                            tone: Theme.accentHi
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "SCREEN TIME"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                font.letterSpacing: 2
                            }
                            Text {
                                text: root.range === 7 ? "YOUR LAST SEVEN DAYS"
                                      : (root.offset === 1 ? "YESTERDAY'S ACTIVITY" : "TODAY'S ACTIVITY")
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.letterSpacing: 1.2
                            }
                        }

                        RowLayout {
                            spacing: 5
                            RangeTab {
                                label: "Today"
                                active: root.range === 1 && root.offset === 0
                                onClicked: root.setView(1, 0)
                            }
                            RangeTab {
                                label: "Yesterday"
                                active: root.range === 1 && root.offset === 1
                                onClicked: root.setView(1, 1)
                            }
                            RangeTab {
                                label: "7 days"
                                active: root.range === 7
                                onClicked: root.setView(7, 0)
                            }
                        }
                    }

                    // Hero total: visual anchor for the panel.
                    ChamferPanel {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 128
                        cut: 16
                        fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
                        strokeColor: Theme.line
                        pattern: true
                        patternOpacity: 0.055

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: "TOTAL ACTIVE TIME"
                                    color: Theme.fgDim
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.5
                                }
                                Text {
                                    text: root.fmt(Math.round(root.totalSecs * root.progress))
                                    color: Theme.accentHi
                                    font.pixelSize: 39
                                    font.weight: Font.DemiBold
                                    font.family: "JetBrainsMono Nerd Font"
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: root.apps.length + (root.apps.length === 1 ? " tracked app" : " tracked apps")
                                    color: Theme.fgDim
                                    font.pixelSize: 11
                                }
                            }

                        }
                    }

                    // Seven-day chart remains a conventional chart for easy reading.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "DAILY RHYTHM"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.letterSpacing: 1.6
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "PEAK " + root.fmt(root.maxDay)
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                        }

                        Item {
                            id: chart
                            Layout.fillWidth: true
                            Layout.preferredHeight: 148

                            Row {
                                anchors.fill: parent
                                spacing: 8

                                Repeater {
                                    model: root.days

                                    Item {
                                        id: dayCol
                                        required property var modelData
                                        required property int index
                                        width: chart.width / Math.max(1, root.days.length) - 8
                                        height: chart.height
                                        readonly property real local: root.lp(index, root.days.length)
                                        readonly property bool selectedDay: root.range === 1
                                            ? index === root.days.length - 1 - root.offset
                                            : index === root.days.length - 1

                                        Text {
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.fmt(Math.round(dayCol.modelData.secs * dayCol.local))
                                            color: dayCol.selectedDay ? Theme.accentHi : Theme.fgDim
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            opacity: (dayCol.selectedDay || root.hoverIdx === dayCol.index) ? 1 : 0
                                        }

                                        Rectangle {
                                            id: track
                                            anchors.top: parent.top
                                            anchors.topMargin: 24
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 25
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: Math.min(18, dayCol.width * 0.45)
                                            radius: 3
                                            color: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.8)

                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: parent.width
                                                height: dayCol.modelData.secs > 0
                                                    ? Math.max(3, track.height * dayCol.modelData.secs / root.maxDay * dayCol.local)
                                                    : 0
                                                radius: 3
                                                color: dayCol.selectedDay ? Theme.accent : root.palette[dayCol.index % root.palette.length]
                                                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            }
                                        }

                                        Text {
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: dayCol.modelData.label
                                            color: dayCol.selectedDay ? Theme.fg : Theme.fgDim
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: root.hoverIdx = dayCol.index
                                            onExited: if (root.hoverIdx === dayCol.index) root.hoverIdx = -1
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.line
                        opacity: 0.8
                    }

                    // Distribution bar and app rows use ordinary shapes, not hexagons.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "APP BREAKDOWN"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.letterSpacing: 1.6
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.apps.length + " ITEMS"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.apps.length === 0
                            text: "No activity recorded for this period.\nThe tracker logs active applications once a minute."
                            color: Theme.fgDim
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Item {
                            id: share
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            visible: root.apps.length > 0

                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: Theme.surface
                            }
                            Row {
                                anchors.fill: parent
                                spacing: 2
                                Repeater {
                                    model: root.apps
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        height: share.height
                                        radius: 2
                                        width: Math.max(0, (modelData.secs / root.denom)
                                            * (share.width - 2 * Math.max(0, root.apps.length - 1)) * root.progress)
                                        visible: width > 1
                                        color: root.palette[index % root.palette.length]
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 9

                            Repeater {
                                model: root.apps.slice(0, 6)

                                Item {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    readonly property real local: root.lp(index, Math.min(6, root.apps.length))
                                    opacity: local

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 10

                                        HexShape {
                                            Layout.preferredWidth: 13
                                            Layout.preferredHeight: 11
                                            fillColor: root.palette[index % root.palette.length]
                                            strokeWidth: 0
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.pretty(modelData.name)
                                                color: Theme.fg
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 3
                                                radius: 2
                                                color: Theme.surface
                                                Rectangle {
                                                    width: parent.width * Math.min(1, modelData.secs / root.maxDay)
                                                    height: parent.height
                                                    radius: 2
                                                    color: root.palette[index % root.palette.length]
                                                }
                                            }
                                        }

                                        Text {
                                            text: Math.round(modelData.secs / root.denom * 100 * root.progress) + "%"
                                            color: Theme.fgDim
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: 36
                                        }
                                        Text {
                                            text: root.fmt(Math.round(modelData.secs * local))
                                            color: Theme.fg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: 62
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "VII / ACTIVITY LOG"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                        Item { Layout.fillWidth: true }
                        HexButton {
                            size: 26
                            glyph: "\uf021"
                            glyphSize: 11
                            outlined: true
                            tone: Theme.accentHi
                            onClicked: root.refresh()
                        }
                    }
                }
            }
        }
    }
}
