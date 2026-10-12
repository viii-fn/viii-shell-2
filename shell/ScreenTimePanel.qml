import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

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

    // Daily goal that drives the ring (6h). Change to taste.
    readonly property int goalDay: 6 * 3600
    readonly property int goal: range === 7 ? goalDay * 7 : goalDay

    property int totalSecs: {
        if (days.length === 0) return 0
        if (range === 1) return days[Math.max(0, days.length - 1 - offset)].secs
        return days.reduce((s, x) => s + x.secs, 0)
    }
    property int maxDay: Math.max(1, ...days.map(x => x.secs))
    property int denom: Math.max(1, totalSecs)
    property int avgDay: days.length > 0 ? Math.round(days.reduce((s, x) => s + x.secs, 0) / days.length) : 0
    // Compared with the average day: +12 means 12% above.
    property int deltaPct: {
        if (range === 7 || avgDay <= 0) return 0
        return Math.round((totalSecs - avgDay) / avgDay * 100)
    }
    readonly property var palette: Theme.chart
    readonly property var views: [
        { label: "Today", r: 1, o: 0 },
        { label: "Yesterday", r: 1, o: 1 },
        { label: "7 days", r: 7, o: 0 }
    ]

    function fmt(s) {
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m"
        return s + "s"
    }
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function numHtml(v, ns, nc) {
        return '<span style="font-size:' + ns + 'px; font-weight:600; color:' + hex(nc) + ';">' + v + '</span>'
    }
    // Big digits, small units, shared baseline.
    function durHtml(s, ns, us, nc, uc) {
        const num = v => '<span style="font-size:' + ns + 'px; font-weight:600; color:' + hex(nc) + ';">' + v + '</span>'
        const unit = v => '<span style="font-size:' + us + 'px; color:' + hex(uc) + ';">' + v + '</span>'
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (h > 0) return num(h) + unit("h") + "&nbsp;" + num(m) + unit("m")
        if (m > 0) return num(m) + unit("m")
        return num(s) + unit("s")
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

    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Screen Time"
            implicitWidth: 480
            implicitHeight: 700
            color: "transparent"
            onVisibleChanged: if (!visible) { anim.stop(); root.shown = false }

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }

            ChamferPanel {
                anchors.fill: parent
                cut: 22
                pattern: true
                patternOpacity: 0.05
                fillColor: Theme.panel
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 14

                    // ── Fixed header: always reachable ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        HexButton {
                            size: 30
                            glyph: "\uf1da"
                            glyphSize: 13
                            outlined: true
                            interactive: false
                            tone: Theme.accentHi
                        }
                        Text {
                            text: "Screen Time"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        HexButton {
                            size: 28
                            glyph: "\uf021"
                            glyphSize: 11
                            outlined: true
                            tone: Theme.accentHi
                            onClicked: root.refresh()
                        }
                    }

                    // ── Fixed segmented switcher ──
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 12
                        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.7)
                        border.width: 1
                        border.color: Theme.line

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 3

                            Repeater {
                                model: root.views

                                Item {
                                    id: seg
                                    required property var modelData
                                    readonly property bool active: root.range === modelData.r && root.offset === modelData.o
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 9
                                        color: seg.active
                                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                            : (segHit.containsMouse ? Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.6) : "transparent")
                                        border.width: seg.active ? 1 : 0
                                        border.color: Theme.accent
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: seg.modelData.label
                                        color: seg.active ? Theme.accentHi : Theme.fgDim
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: seg.active ? Font.DemiBold : Font.Normal
                                    }
                                    MouseArea {
                                        id: segHit
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setView(seg.modelData.r, seg.modelData.o)
                                    }
                                }
                            }
                        }
                    }

                    // ── Scrollable body: nothing can ever be cut off ──
                    Flickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: body.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: body
                            width: flick.width
                            spacing: 16

                            // Goal ring with the total in its center
                            Item {
                                id: ringBox
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 6
                                Layout.preferredWidth: 210
                                Layout.preferredHeight: 210

                                Canvas {
                                    id: ring
                                    anchors.fill: parent
                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.reset()
                                        const lw = 15
                                        const cx = width / 2
                                        const cy = height / 2
                                        const r = width / 2 - lw
                                        ctx.lineWidth = lw
                                        ctx.lineCap = "round"
                                        ctx.strokeStyle = Theme.surfaceHi
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                        ctx.stroke()
                                        const frac = Math.min(1, root.totalSecs / root.goal * root.progress)
                                        if (frac > 0.002) {
                                            ctx.strokeStyle = Theme.accent
                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac)
                                            ctx.stroke()
                                        }
                                    }
                                    Connections {
                                        target: root
                                        function onProgressChanged() { ring.requestPaint() }
                                        function onTotalSecsChanged() { ring.requestPaint() }
                                        function onRangeChanged() { ring.requestPaint() }
                                    }
                                    Connections {
                                        target: Theme
                                        function onAccentChanged() { ring.requestPaint() }
                                        function onSurfaceHiChanged() { ring.requestPaint() }
                                    }
                                    Component.onCompleted: requestPaint()
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.range === 7 ? "Last seven days"
                                              : (root.offset === 1 ? "Yesterday" : "Today")
                                        color: Theme.fgDim
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        textFormat: Text.RichText
                                        font.family: "JetBrainsMono Nerd Font"
                                        text: root.durHtml(Math.round(root.totalSecs * root.progress), 46, 15, Theme.accentHi, Theme.fgDim)
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "of " + root.fmt(root.goal) + " goal"
                                        color: Theme.fgDim
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }
                                }
                            }

                            // Insight line
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                text: {
                                    if (root.apps.length === 0) return "Nothing tracked yet."
                                    const top = root.pretty(root.apps[0].name)
                                    const share = Math.round(root.apps[0].secs / root.denom * 100)
                                    let s = top + " took " + share + "% of your time"
                                    if (root.range === 1 && root.avgDay > 0 && root.deltaPct !== 0)
                                        s += " · " + (root.deltaPct > 0 ? "+" : "") + root.deltaPct + "% vs your average"
                                    return s
                                }
                            }

                            // Stat chips
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Repeater {
                                    model: [
                                        { k: "PEAK DAY", h: root.durHtml(root.maxDay > 1 ? root.maxDay : 0, 24, 11, Theme.fg, Theme.fgDim) },
                                        { k: "DAILY AVG", h: root.durHtml(root.avgDay, 24, 11, Theme.fg, Theme.fgDim) },
                                        { k: "APPS", h: root.numHtml(root.apps.length, 24, Theme.fg) }
                                    ]

                                    Rectangle {
                                        id: chip
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 70
                                        radius: 16
                                        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                                        border.width: 1
                                        border.color: Theme.line

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: chip.modelData.k
                                                color: Theme.fgDim
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                                font.letterSpacing: 1.2
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                textFormat: Text.RichText
                                                font.family: "JetBrainsMono Nerd Font"
                                                text: chip.modelData.h
                                            }
                                        }
                                    }
                                }
                            }

                            // Weekly chart
                            ChamferPanel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 160
                                cut: 14
                                fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
                                strokeColor: Theme.line

                                Item {
                                    id: chart
                                    anchors.fill: parent
                                    anchors.margins: 16

                                    Row {
                                        anchors.fill: parent
                                        spacing: 10

                                        Repeater {
                                            model: root.days

                                            Item {
                                                id: dayCol
                                                required property var modelData
                                                required property int index
                                                width: (chart.width - 10 * (Math.max(1, root.days.length) - 1)) / Math.max(1, root.days.length)
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
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                }

                                                Rectangle {
                                                    id: track
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 20
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: 22
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: Math.min(28, dayCol.width * 0.6)
                                                    radius: 7
                                                    color: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.7)

                                                    Rectangle {
                                                        anchors.bottom: parent.bottom
                                                        width: parent.width
                                                        height: dayCol.modelData.secs > 0
                                                            ? Math.max(4, track.height * dayCol.modelData.secs / root.maxDay * dayCol.local)
                                                            : 0
                                                        radius: 7
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

                            // Top apps
                            Text {
                                text: "Top apps"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.apps.length === 0
                                text: "No activity recorded for this period.\nThe tracker logs active applications once a minute."
                                color: Theme.fgDim
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: root.apps.length > 0

                                Repeater {
                                    model: root.apps.slice(0, 8)

                                    ChamferPanel {
                                        id: row
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        cut: 9
                                        fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, row.index === 0 ? 0.75 : 0.45)
                                        strokeColor: row.index === 0
                                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                                            : Theme.line
                                        readonly property real local: root.lp(index, Math.min(8, root.apps.length))
                                        opacity: local

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 10

                                            HexShape {
                                                Layout.preferredWidth: 12
                                                Layout.preferredHeight: 11
                                                fillColor: root.palette[row.index % root.palette.length]
                                                strokeWidth: 0
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.pretty(row.modelData.name)
                                                color: Theme.fg
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: Math.round(row.modelData.secs / root.denom * 100 * root.progress) + "%"
                                                color: Theme.fgDim
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                horizontalAlignment: Text.AlignRight
                                                Layout.preferredWidth: 34
                                            }
                                            Text {
                                                textFormat: Text.RichText
                                                font.family: "JetBrainsMono Nerd Font"
                                                horizontalAlignment: Text.AlignRight
                                                Layout.preferredWidth: 82
                                                text: root.durHtml(Math.round(row.modelData.secs * row.local), 22, 10, Theme.fg, Theme.fgDim)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 4
                                Layout.bottomMargin: 6
                                text: "Logged every minute"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                        }
                    }
                }
            }
        }
    }
}