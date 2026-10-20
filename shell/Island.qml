// File: ~/viii-shell-2/shell/Island.qml
// "Contour + Flags"
//   - A slim pill (32px). Its OUTLINE is the battery gauge: the accent stroke
//     runs around the pill and shortens as the charge drops. While charging
//     it turns green and a small light travels around it.
//   - Inside: a wifi dot (pulses red when offline), the clock, music (only
//     while a player exists) and the open-window icons. The active window is
//     "stamped": tilted, with an accent border.
//   - Notifications are FLAGS: small tilted tabs hanging off the pill's lower
//     edge, coloured by app. Tap a flag to unfold that notification. A new
//     notification unfolds itself briefly, then folds back into a flag.
//   - Volume / brightness / wifi changes show as one small tilted tab under
//     the pill (a ruler for volume, a stamp for wifi).
//
//   qs ipc call island notifications      toggle the full list
//   Volume / brightness: the pill shrinks into a square, the icon sits in the
//   middle and the outline thickens to show the level.
//   The outline thickens and pulses twice whenever the battery % changes.
//   Plugging in: the pill grows a "Charging" label and a light circles it.
//   Tap the clock: time -> date -> battery % and time left -> time.
//
// All logic (alerts, IPC, network, OSD, memwatch) is unchanged.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

PanelWindow {
    id: win

    anchors.top: true
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "island"
    margins.top: 6                    // the pill floats slightly off the edge
    implicitWidth: 1200
    implicitHeight: 440
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 40
    color: "transparent"

    // Only the pill, the flags, the tab and the card catch clicks.
    mask: Region {
        item: island
        regions: [
            Region { item: flagsRow },
            Region { item: toast },
            Region { item: panel }
        ]
    }

    readonly property string font: "JetBrainsMono Nerd Font"

    // --- Tweak these ------------------------------------------------------
    readonly property real pillH: 32
    readonly property real pad: 14
    readonly property real gap: 14
    readonly property int animMs: 380
    readonly property real notifWidth: 340
    readonly property int popupMs: 6000
    readonly property int swapMs: 6000
    readonly property int osdMs: 1500
    readonly property int netMs: 3500
    readonly property int maxFlags: 8
    readonly property real osdSize: 68          // the square for volume / brightness
    readonly property bool osdMorph: osdShown && !panelOpen
    property bool chargeSpace: false            // step 1: make room for the label
    property bool chargeShown: false            // step 2: fade the label in
    property bool cometOn: false                // the light circling the pill

    // --- Data -------------------------------------------------------------
    readonly property var bat: UPower.displayDevice
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
    readonly property int pct: Math.round(bat.percentage * 100)
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    readonly property color batTone: charging ? Theme.good
                                   : (pct <= 15 ? Theme.bad
                                   : (pct <= 30 ? Theme.accentHi : Theme.accent))

    // Clock modes: 0 = time, 1 = date, 2 = battery
    property int clockMode: 0
    readonly property real secsLeft: charging ? bat.timeToFull : bat.timeToEmpty

    function fmtTime(sec) {
        if (!sec || sec <= 0) return "--"
        const m = Math.round(sec / 60)
        const h = Math.floor(m / 60)
        return h > 0 ? h + "h " + ("0" + (m % 60)).slice(-2) + "m" : m + "m"
    }

    Timer {
        id: swapTimer
        interval: win.swapMs
        onTriggered: win.clockMode = 0
    }

    // Flag colour: one stable hue per app, red for critical.
    function flagColor(n) {
        if (n && n.urgency === NotificationUrgency.Critical) return Theme.bad
        const s = (n && n.appName) ? n.appName : "?"
        let h = 0
        for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360
        return Qt.hsla(h / 360, 0.55, 0.62, 1)
    }

    // --- Notification state ---------------------------------------------------
    property var popup: null               // newest notification
    property bool popupShown: false
    property var openNotif: null           // notification unfolded by tapping its flag
    property bool listOpen: false          // full list (IPC)
    readonly property var cardNotif: listOpen ? null
                                   : (openNotif !== null ? openNotif : (popupShown ? popup : null))
    readonly property bool panelOpen: listOpen || cardNotif !== null
    readonly property int notifCount: server.trackedNotifications.values.length

    function closeAll() {
        listOpen = false
        popupShown = false
        openNotif = null
        popupTimer.stop()
    }
    function toggleList() {
        const was = listOpen
        closeAll()
        listOpen = !was
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: (n) => {
            n.tracked = true
            win.popup = n
            n.closed.connect(() => {
                if (win.popup === n) { win.popup = null; win.popupShown = false }
                if (win.openNotif === n) win.openNotif = null
            })
            if (!win.listOpen) {
                win.openNotif = null           // newest wins: show the fresh one
                win.popupShown = true
                popupTimer.restart()
            }
        }
    }

    Timer {
        id: popupTimer
        interval: win.popupMs
        onTriggered: win.popupShown = false
    }

    IpcHandler {
        target: "island"
        function notifications(): void { win.toggleList() }
        function pulse(): void { contour.pulseNow() }     // manual test: qs ipc call island pulse
    }

    // ── OSD: volume + brightness ───────────────────────────────────────────
    property bool osdShown: false
    property string osdIcon: ""
    property real osdValue: 0
    property bool osdMuted: false

    function showOsd(icon, value, muted) {
        osdIcon = icon
        osdValue = value
        osdMuted = muted
        netShown = false
        netTimer.stop()
        osdShown = true
        osdTimer.restart()
    }

    Timer { id: osdTimer; interval: win.osdMs; onTriggered: win.osdShown = false }
    Timer { id: osdArm; interval: 2000; running: true }

    readonly property var sink: Pipewire.defaultAudioSink
    property real lastVol: -1
    property bool lastMuted: false
    onSinkChanged: osdArm.restart()

    PwObjectTracker { objects: [win.sink] }

    Connections {
        target: win.sink ? win.sink.audio : null
        function onVolumeChanged() { win.volEvent() }
        function onMutedChanged() { win.volEvent() }
    }

    function volEvent() {
        const a = sink ? sink.audio : null
        if (!a) return
        const changed = a.volume !== lastVol || a.muted !== lastMuted
        lastVol = a.volume
        lastMuted = a.muted
        if (osdArm.running || !changed) return
        showOsd(a.muted || a.volume === 0 ? "\uf026" : (a.volume > 0.5 ? "\uf028" : "\uf027"),
                a.volume, a.muted)
    }

    property string blPath: ""
    property real blMax: 1
    property real lastBl: -1

    Process {
        running: true
        command: ["sh", "-c", "d=$(ls -d /sys/class/backlight/* 2>/dev/null | head -n1); [ -n \"$d\" ] && echo \"$d $(cat $d/max_brightness)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(" ")
                if (p.length === 2) { win.blMax = parseInt(p[1]); win.blPath = p[0] }
            }
        }
    }

    FileView {
        path: win.blPath !== "" ? win.blPath + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text())
            if (isNaN(v)) return
            const first = win.lastBl < 0
            const changed = v !== win.lastBl
            win.lastBl = v
            if (first || !changed || osdArm.running) return
            win.showOsd("\uf185", v / win.blMax, false)
        }
    }

    // ── Battery alerts at 30 / 20 / 10 % ───────────────────────────────────
    property int lastBatLevel: 0
    function batLevel(p) { return p <= 10 ? 10 : (p <= 20 ? 20 : (p <= 30 ? 30 : 100)) }

    function checkBattery() {
        const p = Math.round(bat.percentage * 100)
        const lvl = batLevel(p)
        if (lastBatLevel !== 0 && !charging && lvl < lastBatLevel) {
            Quickshell.execDetached(["notify-send", "-a", "Battery",
                "-u", lvl <= 10 ? "critical" : "normal",
                "-i", lvl <= 10 ? "battery-empty" : "battery-low",
                "Battery at " + p + "%", "Plug in soon."])
        }
        lastBatLevel = lvl
    }

    // Pulse the outline whenever the whole-number battery % changes.
    // Watching the rounded value (pct) means tiny fractional updates from UPower
    // can't restart the animation over and over.
    property int lastPct: -1
    Component.onCompleted: lastPct = pct
    onPctChanged: {
        if (lastPct > 0 && pct !== lastPct) contour.pulseNow()
        lastPct = pct
        checkBattery()
    }

    Connections {
        target: win.bat
        function onStateChanged() {
            win.checkBattery()
            if (win.charging) chargeSeq.restart()
            else {
                chargeSeq.stop()
                win.chargeShown = false
                win.chargeSpace = false
                win.cometOn = false
                contour.pulseNow()          // unplugging pulses too
            }
        }
    }

    // Plug-in sequence: grow first, THEN fade the label in; on the way out the
    // label fades first, THEN the pill shrinks. The comet only runs ~6 s so it
    // doesn't keep redrawing forever.
    SequentialAnimation {
        id: chargeSeq
        ScriptAction { script: { win.cometOn = true; cometOff.restart(); contour.pulseNow(); win.chargeSpace = true } }
        PauseAnimation { duration: win.animMs }
        ScriptAction { script: win.chargeShown = true }
        PauseAnimation { duration: 3500 }
        ScriptAction { script: win.chargeShown = false }
        PauseAnimation { duration: 250 }
        ScriptAction { script: win.chargeSpace = false }
    }
    Timer { id: cometOff; interval: 6600; onTriggered: win.cometOn = false }

    // ── RAM alert ──────────────────────────────────────────────────────────
    Process {
        running: screen === Quickshell.screens[0]
        command: ["sh", Quickshell.shellPath("scripts/memwatch.sh")]
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("|")
                if (i < 0) return
                Quickshell.execDetached(["notify-send", "-a", "Memory", "-u", "critical",
                    "-i", "dialog-warning", "RAM at " + line.slice(0, i) + "%",
                    "Biggest users:\n" + line.slice(i + 1)])
            }
        }
    }

    // ── Network ────────────────────────────────────────────────────────────
    property string netIface: ""
    property string netSsid: ""
    property bool netKnown: false
    readonly property bool online: netIface !== ""
    readonly property bool isWifi: netIface.startsWith("w")
    property bool netShown: false

    function netUpdate(iface, ssid) {
        const wasOnline = netIface !== ""
        const nowOnline = iface !== ""
        const changed = wasOnline !== nowOnline
            || (nowOnline && (iface !== netIface || (ssid !== "" && ssid !== netSsid)))
        const first = !netKnown
        netIface = iface
        netSsid = ssid
        netKnown = true
        if (first || !changed) return
        osdShown = false
        osdTimer.stop()
        netShown = true
        netTimer.restart()
    }

    Timer { id: netTimer; interval: win.netMs; onTriggered: win.netShown = false }

    Process {
        id: netProc
        command: ["sh", "-c",
            "i=$(ip -o route show default | awk '{print $5; exit}'); "
            + "s=$(iwgetid -r 2>/dev/null || nmcli -t -f active,ssid dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -n1); "
            + "printf '%s\\n%s\\n' \"$i\" \"$s\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n")
                win.netUpdate((l[0] || "").trim(), (l[1] || "").trim())
            }
        }
    }
    Process {
        running: true
        command: ["ip", "monitor", "route"]
        stdout: SplitParser { onRead: netDebounce.restart() }
    }
    Timer {
        id: netDebounce
        interval: 600
        onTriggered: if (!netProc.running) netProc.running = true
    }
    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!netProc.running) netProc.running = true
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ══ FLAGS ═════════════════════════════════════════════════════════════
    // Declared before the pill so the pill draws over their top edge: they
    // look like they hang out from behind it.
    Row {
        id: flagsRow
        opacity: win.osdMorph ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 150 } }
        anchors.top: island.bottom
        anchors.topMargin: -6
        anchors.left: island.left
        anchors.leftMargin: 22
        spacing: 4

        Repeater {
            model: server.trackedNotifications
            delegate: Item {
                id: flag
                required property int index
                required property var modelData
                readonly property bool opened: win.cardNotif === modelData
                visible: index < win.maxFlags
                width: visible ? 16 : 0
                height: 16

                Rectangle {
                    id: tab
                    width: 14; height: 16; radius: 3
                    x: 1
                    y: flag.opened ? 3 : 0
                    color: win.flagColor(flag.modelData)
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                    rotation: flag.index % 2 === 0 ? -6 : 5
                    transformOrigin: Item.Top
                    scale: 0
                    Component.onCompleted: scale = 1
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const same = win.openNotif === flag.modelData
                        win.closeAll()
                        if (!same) win.openNotif = flag.modelData
                    }
                }
            }
        }
        Text {
            visible: win.notifCount > win.maxFlags
            anchors.verticalCenter: undefined
            y: 4
            font.family: win.font; font.pixelSize: 10
            color: Theme.fgDim
            text: "+" + (win.notifCount - win.maxFlags)
        }
    }

    // ══ THE PILL ══════════════════════════════════════════════════════════
    Rectangle {
        id: island
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        height: win.osdMorph ? win.osdSize : win.pillH
        radius: Math.min(height / 2, 22)
        color: Theme.panel
        clip: true
        Behavior on height { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

        readonly property real rowW: 2 * win.pad
             + wifiSec.target + chargeSec.target + clockSec.target + musicSec.target + winSec.target
        width: win.osdMorph ? win.osdSize : rowW
        Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

        // Tapping the empty part of the pill folds any open card.
        MouseArea {
            anchors.fill: parent
            onClicked: if (win.panelOpen) win.closeAll()
        }

        // ── Contour: the outline is a gauge ──
        // At rest it shows the battery (2px). During volume / brightness the
        // island is a square and the outline is 6px and shows that level.
        // It thickens and pulses twice whenever the battery % changes.
        // (dashPattern is measured in stroke widths, hence the / sw.)
        Shape {
            id: contour
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            property real baseSw: win.osdMorph ? 6 : 2
            Behavior on baseSw { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
            property real pulse: 0
            readonly property real sw: baseSw + pulse * 3
            readonly property real inset: sw / 2
            readonly property real cr: island.radius
            readonly property real rc: Math.max(0.5, cr - inset)
            readonly property real perim: 2 * (island.width - 2 * cr) + 2 * (island.height - 2 * cr) + 2 * Math.PI * rc

            property real gauge: win.osdMorph ? Math.min(1, Math.max(0, win.osdValue))
                                              : Math.min(1, Math.max(0, win.pct / 100))
            Behavior on gauge { NumberAnimation { duration: win.osdMorph ? 140 : 600; easing.type: Easing.OutCubic } }
            property color gaugeColor: win.osdMorph ? (win.osdMuted ? Theme.fgDim : Theme.accent) : win.batTone
            Behavior on gaugeColor { ColorAnimation { duration: 250 } }
            property real cometPos: 0

            function pulseNow() { pulseAnim.restart() }
            SequentialAnimation {
                id: pulseAnim
                NumberAnimation { target: contour; property: "pulse"; to: 1;    duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: contour; property: "pulse"; to: 0.25; duration: 160; easing.type: Easing.InOutQuad }
                NumberAnimation { target: contour; property: "pulse"; to: 1;    duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: contour; property: "pulse"; to: 0;    duration: 320; easing.type: Easing.InOutQuad }
            }

            // track: the full outline, faint
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.12)
                strokeWidth: contour.sw
                            startX: island.width / 2; startY: contour.inset
                PathLine { x: island.width - contour.cr; y: contour.inset }
                PathArc { x: island.width - contour.inset; y: contour.cr
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: island.width - contour.inset; y: island.height - contour.cr }
                PathArc { x: island.width - contour.cr; y: island.height - contour.inset
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: contour.cr; y: island.height - contour.inset }
                PathArc { x: contour.inset; y: island.height - contour.cr
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: contour.inset; y: contour.cr }
                PathArc { x: contour.cr; y: contour.inset
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: island.width / 2; y: contour.inset }
            }

            // gauge: the same outline, drawn only as far as the level goes
            ShapePath {
                fillColor: "transparent"
                strokeColor: contour.gaugeColor
                strokeWidth: contour.sw
                capStyle: win.osdMorph ? ShapePath.FlatCap : ShapePath.RoundCap
                strokeStyle: ShapePath.DashLine
                dashPattern: [Math.max(0.01, contour.perim * contour.gauge / contour.sw), contour.perim]
                            startX: island.width / 2; startY: contour.inset
                PathLine { x: island.width - contour.cr; y: contour.inset }
                PathArc { x: island.width - contour.inset; y: contour.cr
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: island.width - contour.inset; y: island.height - contour.cr }
                PathArc { x: island.width - contour.cr; y: island.height - contour.inset
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: contour.cr; y: island.height - contour.inset }
                PathArc { x: contour.inset; y: island.height - contour.cr
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: contour.inset; y: contour.cr }
                PathArc { x: contour.cr; y: contour.inset
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: island.width / 2; y: contour.inset }
            }

            // comet: a short light that circles the pill after plugging in
            ShapePath {
                fillColor: "transparent"
                strokeColor: (win.cometOn && !win.osdMorph) ? Qt.rgba(1, 1, 1, 0.9) : "transparent"
                strokeWidth: contour.sw
                capStyle: ShapePath.RoundCap
                strokeStyle: ShapePath.DashLine
                dashPattern: [16 / contour.sw, Math.max(1, contour.perim / contour.sw - 16 / contour.sw)]
                dashOffset: contour.perim / contour.sw * (1 - contour.cometPos)
                            startX: island.width / 2; startY: contour.inset
                PathLine { x: island.width - contour.cr; y: contour.inset }
                PathArc { x: island.width - contour.inset; y: contour.cr
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: island.width - contour.inset; y: island.height - contour.cr }
                PathArc { x: island.width - contour.cr; y: island.height - contour.inset
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: contour.cr; y: island.height - contour.inset }
                PathArc { x: contour.inset; y: island.height - contour.cr
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: contour.inset; y: contour.cr }
                PathArc { x: contour.cr; y: contour.inset
                          radiusX: contour.rc; radiusY: contour.rc; direction: PathArc.Clockwise }
                PathLine { x: island.width / 2; y: contour.inset }
            }

            NumberAnimation on cometPos {
                from: 0; to: 1
                duration: 2200
                loops: Animation.Infinite
                running: win.cometOn
            }
        }

        // The volume / brightness icon, centred in the square
        Text {
            anchors.centerIn: parent
            font.family: win.font; font.pixelSize: 22
            color: Theme.fg
            text: win.osdIcon
            opacity: win.osdMorph ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        Row {
            x: win.pad
            height: island.height
            spacing: 0
            opacity: win.osdMorph ? 0 : 1
            enabled: !win.osdMorph
            Behavior on opacity { NumberAnimation { duration: 150 } }

            // 1. NETWORK: one dot. Dim = online, pulsing red = offline.
            Item {
                id: wifiSec
                readonly property real target: 8
                width: target; height: island.height
                Rectangle {
                    id: wifiDot
                    anchors.centerIn: parent
                    width: 6; height: 6; radius: 3
                    color: win.online ? Theme.fgDim : Theme.bad
                    SequentialAnimation on opacity {
                        running: !win.online
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 700 }
                        NumberAnimation { to: 1.0; duration: 700 }
                    }
                    opacity: 1
                }
            }

            // 1b. CHARGING LABEL (only takes space during the plug-in sequence)
            Item {
                id: chargeSec
                readonly property real target: win.chargeSpace ? win.gap + chargeLabel.implicitWidth : 0
                width: target; height: island.height
                clip: true
                Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                Text {
                    id: chargeLabel
                    x: win.gap
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: win.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    text: "\uf0e7  Charging"
                    color: Theme.good
                    opacity: win.chargeShown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            // 2. CLOCK: tap cycles time -> date -> battery
            Item {
                id: clockSec
                readonly property real target: win.gap + clockText.implicitWidth
                width: target; height: island.height
                Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                Text {
                    id: clockText
                    x: win.gap
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    font.letterSpacing: 1
                    color: win.clockMode === 2 ? win.batTone : Theme.fg
                    text: win.clockMode === 0 ? Qt.formatDateTime(clock.date, "HH:mm")
                        : (win.clockMode === 1 ? Qt.formatDateTime(clock.date, "ddd d MMM")
                        : win.pct + "%  " + win.fmtTime(win.secsLeft))

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { win.clockMode = (win.clockMode + 1) % 3; swapTimer.restart() }
                    }
                }
            }

            // 3. MUSIC: art, title, play / pause
            Item {
                id: musicSec
                property bool want: win.player !== null
                property bool revealed: false
                readonly property real target: want ? win.gap + musicRow.implicitWidth : 0
                width: target; height: island.height
                clip: true
                Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                onWantChanged: { if (want) revealTimer.restart(); else revealed = false }
                Component.onCompleted: if (want) revealTimer.start()
                Timer { id: revealTimer; interval: win.animMs; onTriggered: musicSec.revealed = true }

                Row {
                    id: musicRow
                    x: win.gap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    opacity: musicSec.revealed ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Item {
                        width: 20; height: 20
                        anchors.verticalCenter: parent.verticalCenter
                        visible: musicSec.want

                        Image {
                            id: art
                            anchors.fill: parent
                            visible: false
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(40, 40)
                            source: win.player ? win.player.trackArtUrl : ""
                        }
                        Rectangle {
                            id: artMask
                            anchors.fill: parent
                            radius: 10
                            visible: false
                            layer.enabled: true
                            color: "white"
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: art
                            maskEnabled: true
                            maskSource: artMask
                            visible: art.status === Image.Ready
                        }
                    }

                    // Title: scrolls back and forth when it is wider than the box,
                    // and only while a track is playing (idle = no animation running).
                    Item {
                        id: titleBox
                        readonly property real overflow: Math.max(0, titleText.implicitWidth - 150)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(titleText.implicitWidth, 150)
                        height: titleText.implicitHeight
                        clip: true

                        Text {
                            id: titleText
                            font.family: win.font; font.pixelSize: 12
                            color: Theme.fg
                            text: win.player ? win.player.trackTitle : ""
                            onTextChanged: x = 0
                        }
                        SequentialAnimation {
                            running: titleBox.overflow > 0 && musicSec.revealed && !win.osdMorph
                                     && win.player !== null && win.player.isPlaying
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) titleText.x = 0
                            PauseAnimation { duration: 1500 }
                            NumberAnimation { target: titleText; property: "x"; to: -titleBox.overflow
                                              duration: Math.max(600, titleBox.overflow * 28) }
                            PauseAnimation { duration: 1200 }
                            NumberAnimation { target: titleText; property: "x"; to: 0
                                              duration: Math.max(600, titleBox.overflow * 28) }
                        }
                    }

                    Rectangle {
                        width: 20; height: 20; radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.accent
                        opacity: playArea.containsMouse ? 0.85 : 1
                        scale: playArea.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: 70 } }
                        Text {
                            anchors.centerIn: parent
                            font.family: win.font; font.pixelSize: 9
                            color: Theme.accentText
                            text: (win.player && win.player.isPlaying) ? "\uf04c" : "\uf04b"
                        }
                        MouseArea {
                            id: playArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: if (win.player) win.player.togglePlaying()
                        }
                    }
                }
            }

            // 4. OPEN WINDOWS: the active one is stamped (tilted, inked border)
            Item {
                id: winSec
                readonly property int count: ToplevelManager.toplevels.values.length
                readonly property real target: count > 0 ? win.gap + iconsRow.implicitWidth : 0
                width: target; height: island.height
                clip: true
                Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                Row {
                    id: iconsRow
                    x: win.gap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: ToplevelManager.toplevels
                        delegate: Rectangle {
                            required property var modelData
                            width: 22; height: 22; radius: 5
                            color: modelData.activated ? Qt.alpha(Theme.accent, 0.14) : "transparent"
                            border.width: modelData.activated ? 1 : 0
                            border.color: Theme.accent
                            rotation: modelData.activated ? -4 : 0
                            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                            Image {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                sourceSize: Qt.size(28, 28)
                                opacity: modelData.activated ? 1 : 0.5
                                source: Quickshell.iconPath(modelData.appId, "application-x-executable")
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: modelData.activate()
                            }
                        }
                    }
                }
            }
        }
    }

    // ══ TOAST TAB: wifi stamp, tilted under the pill ═══════
    Rectangle {
        id: toast
        readonly property bool want: win.netShown && !win.panelOpen && !win.osdMorph
        anchors.top: island.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: island.horizontalCenter
        rotation: -2
        radius: 14
        color: Theme.panel
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        clip: true
        width: netRow.implicitWidth + 28
        height: want ? 28 : 0
        opacity: want ? 1 : 0
        visible: height > 0.5
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // wifi: stamped icon + "Connected name" / "Disconnected"
        Row {
            id: netRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: win.font; font.pixelSize: 13
                text: !win.online ? "\uf071" : (win.isWifi ? "\uf1eb" : "\uf0e8")
                color: win.online ? Theme.good : Theme.bad
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: win.font; font.pixelSize: 12; font.weight: Font.DemiBold
                color: Theme.fg
                text: win.online ? "Connected" : "Disconnected"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.online
                width: Math.min(implicitWidth, 110)
                elide: Text.ElideRight
                font.family: win.font; font.pixelSize: 11
                color: Theme.fgDim
                text: win.netSsid !== "" ? win.netSsid : win.netIface
            }
        }
    }

    // ══ CARD PANEL: one unfolded notification, or the full list ═══════════
    Rectangle {
        id: panel
        anchors.top: island.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: island.horizontalCenter
        width: win.notifWidth + 24
        radius: 20
        color: Theme.panel
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        clip: true

        readonly property real cardH: popupCard.implicitHeight + 20
        readonly property real listH: 44 + (win.notifCount > 0 ? Math.min(300, notifList.contentHeight) : 28) + 12
        height: win.panelOpen ? (win.listOpen ? listH : cardH) : 0
        opacity: win.panelOpen ? 1 : 0
        visible: height > 0.5
        Behavior on height { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Hovering a card pauses its auto-fold.
        HoverHandler {
            onHoveredChanged: {
                if (hovered) popupTimer.stop()
                else if (win.popupShown) popupTimer.restart()
            }
        }

        IslandNotif {
            id: popupCard
            visible: !win.listOpen && win.cardNotif !== null
            x: 12; y: 10
            width: parent.width - 24
            notif: win.cardNotif
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            visible: win.listOpen

            Item {
                id: listHead
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.accentHi
                    font.family: win.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.notifCount > 0
                    text: "Clear all"
                    color: clearArea.containsMouse ? Theme.accentHi : Theme.fgDim
                    font.family: win.font
                    font.pixelSize: 11
                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const all = server.trackedNotifications.values.slice()
                            all.forEach(n => n.dismiss())
                        }
                    }
                }
            }

            Text {
                anchors.top: listHead.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                visible: win.notifCount === 0
                text: "You're all caught up"
                color: Theme.fgDim
                font.family: win.font
                font.pixelSize: 11
            }

            ListView {
                id: notifList
                anchors.top: listHead.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: server.trackedNotifications
                delegate: IslandNotif {
                    required property var modelData
                    width: notifList.width
                    notif: modelData
                }
            }
        }
    }
}
