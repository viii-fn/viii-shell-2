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

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    property int range: 1
    property int offset: 0
    property var days: []
    property var apps: []
    property real progress: 0
    property int hoverIdx: -1

    // Heatmap data (built in buildHeat)
    readonly property int heatWeeks: 17          // columns in the heatmap
    property var heat: []                        // [{ label, days: [{ date, secs, future, ago }] }]
    property var heatStats: ({ active: 0, total: 0, current: 0, longest: 0, bestSecs: 0, bestDate: "" })
    property string heatTip: "Hover a hex for details"

    // Daily goal (6h). Change to taste.
    readonly property int goalDay: 6 * 3600
    readonly property int goal: range === 7 ? goalDay * 7 : goalDay
    readonly property real goalFrac: totalSecs / goal

    property int totalSecs: {
        if (days.length === 0) return 0
        if (range === 1) return days[Math.max(0, days.length - 1 - offset)].secs
        return days.reduce((s, x) => s + x.secs, 0)
    }
    property int maxDay: Math.max(1, ...days.map(x => x.secs))
    property int denom: Math.max(1, totalSecs)
    property int avgDay: days.length > 0 ? Math.round(days.reduce((s, x) => s + x.secs, 0) / days.length) : 0
    property int goalHit: days.filter(x => x.secs >= goalDay).length
    property int deltaPct: {
        if (range === 7 || avgDay <= 0) return 0
        return Math.round((totalSecs - avgDay) / avgDay * 100)
    }
    readonly property bool canOlder: range === 1 && days.length > 0 && offset < days.length - 1
    readonly property bool canNewer: range === 1 && offset > 0
    readonly property var palette: Theme.chart
    readonly property var views: [
        { label: "Day", r: 1 },
        { label: "Week", r: 7 }
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
    function suffixHtml(v, us, uc) {
        return '<span style="font-size:' + us + 'px; color:' + hex(uc) + ';">' + v + '</span>'
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
    function viewTitle() {
        if (range === 7) return "LAST 7 DAYS"
        if (offset === 0) return "TODAY"
        if (offset === 1) return "YESTERDAY"
        const i = days.length - 1 - offset
        if (i >= 0 && days[i]) return days[i].label.toUpperCase() + " · " + offset + " DAYS AGO"
        return offset + " DAYS AGO"
    }
    function isoDate(dt) {
        return dt.getFullYear() + "-" + ("0" + (dt.getMonth() + 1)).slice(-2) + "-" + ("0" + dt.getDate()).slice(-2)
    }
    // How bright a heatmap hex is, relative to the daily goal.
    function heatOpacity(s) {
        if (s <= 0) return 0
        const r = s / goalDay
        if (r < 0.25) return 0.3
        if (r < 0.5) return 0.5
        if (r < 0.9) return 0.75
        return 1
    }
    // Turn { "2026-10-12": secs, ... } into week columns (Sunday on top) plus streak stats.
    function buildHeat(h) {
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const start = new Date(today)
        start.setDate(today.getDate() - today.getDay() - (heatWeeks - 1) * 7)

        const weeks = []
        let prevMonth = -1
        let active = 0, total = 0, run = 0, longest = 0, bestSecs = 0, bestDate = ""

        for (let w = 0; w < heatWeeks; w++) {
            const wd = []
            let label = ""
            for (let d = 0; d < 7; d++) {
                const dt = new Date(start)
                dt.setDate(start.getDate() + w * 7 + d)
                const iso = isoDate(dt)
                const future = dt > today
                const secs = future ? 0 : (h[iso] || 0)

                if (d === 0 && dt.getMonth() !== prevMonth) {
                    label = Qt.formatDate(dt, "MMM")
                    prevMonth = dt.getMonth()
                }
                if (!future) {
                    total++
                    if (secs > 0) {
                        active++
                        run++
                        if (run > longest) longest = run
                    } else {
                        run = 0
                    }
                    if (secs > bestSecs) { bestSecs = secs; bestDate = iso }
                }
                wd.push({ date: iso, secs: secs, future: future, ago: Math.round((today - dt) / 86400000) })
            }
            weeks.push({ label: label, days: wd })
        }

        // Current streak: walk back from today (an empty today doesn't break it yet)
        let current = 0
        for (let i = 0; i < heatWeeks * 7; i++) {
            const dt = new Date(today)
            dt.setDate(today.getDate() - i)
            const s = h[isoDate(dt)] || 0
            if (s > 0) current++
            else if (i > 0) break
        }

        heat = weeks
        heatStats = { active: active, total: total, current: current, longest: longest, bestSecs: bestSecs, bestDate: bestDate }
    }
    function parse(text) {
        const d = [], a = [], h = {}
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p.length < 3) continue
            if (p[0] === "DAY") d.push({ label: dayName(p[1]), secs: parseInt(p[2]) })
            else if (p[0] === "APP") a.push({ name: p[1], secs: parseInt(p[2]) })
            else if (p[0] === "HIST") h[p[1]] = parseInt(p[2])
        }
        days = d
        apps = a
        buildHeat(h)
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
    // d = +1 goes one day older, d = -1 one day newer
    function stepDay(d) {
        if (range !== 1) return
        const n = offset + d
        if (n < 0 || n > days.length - 1) return
        setView(1, n)
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
        command: [Quickshell.env("HOME") + "/.local/bin/screentime-report", String(root.range), String(root.offset), String(root.heatWeeks)]
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
            implicitHeight: 760
            color: "transparent"
            onVisibleChanged: if (!visible) { anim.stop(); root.shown = false }

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }
            Shortcut { sequence: "Left"; onActivated: root.stepDay(1) }
            Shortcut { sequence: "Right"; onActivated: root.stepDay(-1) }
            Shortcut { sequence: "R"; onActivated: root.refresh() }

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

                    // ── Header: title, clock + date, refresh ──
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
                        ColumnLayout {
                            spacing: 0
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: Qt.formatDateTime(clock.date, "HH:mm")
                                color: Theme.accentHi
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: Qt.formatDateTime(clock.date, "ddd, d MMM yyyy")
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }
                        HexButton {
                            size: 28
                            glyph: "\uf021"
                            glyphSize: 11
                            outlined: true
                            tone: Theme.accentHi
                            onClicked: root.refresh()
                        }
                    }

                    // ── Day / Week switcher ──
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
                                    readonly property bool active: root.range === modelData.r
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
                                        onClicked: if (root.range !== seg.modelData.r) root.setView(seg.modelData.r, 0)
                                    }
                                }
                            }
                        }
                    }

                    // ── Scrollable body ──
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

                            // Hero: date navigation
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 8
                                spacing: 18

                                HexButton {
                                    size: 28
                                    glyph: "\uf053"
                                    glyphSize: 11
                                    outlined: true
                                    tone: Theme.accentHi
                                    opacity: root.canOlder ? 1 : 0.3
                                    onClicked: root.stepDay(1)
                                }
                                Text {
                                    Layout.preferredWidth: 190
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.viewTitle()
                                    color: Theme.fgDim
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    font.letterSpacing: 2.5
                                    elide: Text.ElideRight
                                }
                                HexButton {
                                    size: 28
                                    glyph: "\uf054"
                                    glyphSize: 11
                                    outlined: true
                                    tone: Theme.accentHi
                                    opacity: root.canNewer ? 1 : 0.3
                                    onClicked: root.stepDay(-1)
                                }
                            }

                            // Hero: the big number
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                textFormat: Text.RichText
                                font.family: "JetBrainsMono Nerd Font"
                                text: root.durHtml(Math.round(root.totalSecs * root.progress), 92, 28, Theme.accentHi, Theme.fgDim)
                            }

                            // Hero: change vs average
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                visible: root.range === 1 && root.avgDay > 0 && root.deltaPct !== 0
                                text: (root.deltaPct > 0 ? "▲ " : "▼ ") + Math.abs(root.deltaPct) + "% vs your daily average"
                                color: root.deltaPct > 0 ? Theme.accentHi : Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }

                            // Goal honeycomb strip: 10 hexes, each 10% of the goal
                            Item {
                                id: strip
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                Layout.topMargin: 4

                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: 10

                                        Item {
                                            id: cell
                                            required property int index
                                            width: (strip.width - 6 * 9) / 10
                                            height: 30

                                            HexShape {
                                                anchors.fill: parent
                                                fillColor: Theme.surfaceHi
                                                strokeWidth: 0
                                            }
                                            HexShape {
                                                anchors.fill: parent
                                                fillColor: Theme.accent
                                                strokeWidth: 0
                                                opacity: Math.max(0, Math.min(1, root.goalFrac * root.progress * 10 - cell.index))
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                text: root.totalSecs >= root.goal
                                    ? "Goal of " + root.fmt(root.goal) + " passed by " + root.fmt(root.totalSecs - root.goal)
                                    : Math.round(root.goalFrac * 100) + "% of your " + root.fmt(root.goal) + " goal"
                            }

                            // Insight line
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                text: {
                                    if (root.apps.length === 0) return "Nothing tracked yet."
                                    const top = root.pretty(root.apps[0].name)
                                    const share = Math.round(root.apps[0].secs / root.denom * 100)
                                    return top + " took " + share + "% of your time"
                                }
                            }

                            // Stat chips (2x2)
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 10
                                columnSpacing: 10

                                Repeater {
                                    model: [
                                        { k: "PEAK DAY", h: root.durHtml(root.maxDay > 1 ? root.maxDay : 0, 24, 11, Theme.fg, Theme.fgDim) },
                                        { k: "DAILY AVG", h: root.durHtml(root.avgDay, 24, 11, Theme.fg, Theme.fgDim) },
                                        { k: "GOAL DAYS", h: root.numHtml(root.goalHit, 24, Theme.fg) + root.suffixHtml("&nbsp;/ " + root.days.length, 11, Theme.fgDim) },
                                        { k: "APPS USED", h: root.numHtml(root.apps.length, 24, Theme.fg) }
                                    ]

                                    Rectangle {
                                        id: chip
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 66
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

                            // Weekly chart: click a bar to jump to that day
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
                                                    cursorShape: Qt.PointingHandCursor
                                                    onEntered: root.hoverIdx = dayCol.index
                                                    onExited: if (root.hoverIdx === dayCol.index) root.hoverIdx = -1
                                                    onClicked: root.setView(1, root.days.length - 1 - dayCol.index)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Activity heatmap: git-graph style, hex cells, Sunday on top ──
                            Text {
                                text: "Activity"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            ChamferPanel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: heatCol.implicitHeight + 32
                                cut: 14
                                fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
                                strokeColor: Theme.line

                                ColumnLayout {
                                    id: heatCol
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 8

                                    // Cell size derived from the available width (16 = day-label column + gap)
                                    readonly property real cw: Math.max(8, Math.floor((width - 16 - (root.heatWeeks - 1) * 3) / root.heatWeeks))
                                    readonly property real ch: Math.round(cw * 0.92)

                                    Row {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 4

                                        // Day labels (M / W / F)
                                        Column {
                                            spacing: 3
                                            width: 12
                                            Item { width: 12; height: 14 }
                                            Repeater {
                                                model: 7
                                                Item {
                                                    id: dl
                                                    required property int index
                                                    width: 12
                                                    height: heatCol.ch
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: dl.index === 1 ? "M" : dl.index === 3 ? "W" : dl.index === 5 ? "F" : ""
                                                        color: Theme.fgDim
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 8
                                                    }
                                                }
                                            }
                                        }

                                        // Week columns
                                        Row {
                                            spacing: 3
                                            Repeater {
                                                model: root.heat

                                                Column {
                                                    id: wk
                                                    required property var modelData
                                                    required property int index
                                                    spacing: 3

                                                    Item {
                                                        width: heatCol.cw
                                                        height: 14
                                                        Text {
                                                            text: wk.modelData.label
                                                            color: Theme.fgDim
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 8
                                                        }
                                                    }

                                                    Repeater {
                                                        model: wk.modelData.days

                                                        Item {
                                                            id: hc
                                                            required property var modelData
                                                            width: heatCol.cw
                                                            height: heatCol.ch
                                                            opacity: hc.modelData.future ? 0 : 1

                                                            HexShape {
                                                                anchors.fill: parent
                                                                fillColor: Theme.surfaceHi
                                                                strokeWidth: 0
                                                                opacity: 0.55
                                                            }
                                                            HexShape {
                                                                anchors.fill: parent
                                                                fillColor: hc.modelData.ago === 0 ? Theme.accentHi : Theme.accent
                                                                strokeWidth: 0
                                                                opacity: root.heatOpacity(hc.modelData.secs) * root.lp(wk.index, root.heatWeeks)
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                enabled: !hc.modelData.future
                                                                cursorShape: hc.modelData.ago <= 6 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                                onEntered: root.heatTip = Qt.formatDate(new Date(hc.modelData.date + "T00:00:00"), "ddd d MMM yyyy")
                                                                    + "  ·  " + (hc.modelData.secs > 0 ? root.fmt(hc.modelData.secs) : "no activity")
                                                                onExited: root.heatTip = "Hover a hex for details"
                                                                onClicked: if (hc.modelData.ago <= 6) root.setView(1, hc.modelData.ago)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Hover details
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.heatTip
                                        color: Theme.accentHi
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }

                                    // Streaks and best day
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                        color: Theme.fgDim
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        text: root.heatStats.total === 0 ? "No history yet."
                                            : "Streak " + root.heatStats.current + "d  ·  Longest " + root.heatStats.longest + "d  ·  Active "
                                              + root.heatStats.active + "/" + root.heatStats.total + " days"
                                              + (root.heatStats.bestSecs > 0
                                                  ? "\nBest day: " + Qt.formatDate(new Date(root.heatStats.bestDate + "T00:00:00"), "ddd d MMM") + " (" + root.fmt(root.heatStats.bestSecs) + ")"
                                                  : "")
                                    }

                                    // Legend
                                    Row {
                                        Layout.alignment: Qt.AlignRight
                                        spacing: 4

                                        Text {
                                            text: "less"
                                            color: Theme.fgDim
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Repeater {
                                            model: [0, 0.3, 0.5, 0.75, 1]

                                            Item {
                                                id: lg
                                                required property real modelData
                                                width: 11
                                                height: 10
                                                HexShape {
                                                    anchors.fill: parent
                                                    fillColor: Theme.surfaceHi
                                                    strokeWidth: 0
                                                    opacity: 0.55
                                                }
                                                HexShape {
                                                    anchors.fill: parent
                                                    fillColor: Theme.accent
                                                    strokeWidth: 0
                                                    opacity: lg.modelData
                                                }
                                            }
                                        }
                                        Text {
                                            text: "more"
                                            color: Theme.fgDim
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }

                            // Breakdown bar: top 6 apps as one stacked bar
                            Text {
                                text: "Breakdown"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                visible: root.apps.length > 0
                            }

                            Item {
                                id: shareHost
                                Layout.fillWidth: true
                                Layout.preferredHeight: 12
                                visible: root.apps.length > 0

                                Row {
                                    spacing: 2
                                    Repeater {
                                        model: root.apps.slice(0, 6)

                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            height: 12
                                            radius: 6
                                            width: Math.max(0, (shareHost.width - 2 * 5) * (modelData.secs / root.denom) * root.progress)
                                            color: root.palette[index % root.palette.length]
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
                                        Layout.preferredHeight: 50
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
                                            anchors.bottomMargin: 8
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

                                        // Thin usage bar, relative to the #1 app
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 36
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 8
                                            width: Math.max(0, (parent.width - 36 - 14) * (row.modelData.secs / Math.max(1, root.apps[0].secs)) * root.progress)
                                            height: 3
                                            radius: 2
                                            color: root.palette[row.index % root.palette.length]
                                            opacity: 0.8
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 4
                                Layout.bottomMargin: 6
                                text: "Logged every minute  ·  ← → change day  ·  R refresh"
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
