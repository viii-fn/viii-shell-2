// File: ~/viii-shell-2/shell/Island.qml
// A glass notch attached to the top edge of the screen: network, battery
// (with the charging sequence), clock, music (only while a player exists),
// open-window icons and a notification bell. Top corners flare outward into
// the screen edge, bottom corners are rounded.
// It also IS the notification center: new notifications stretch it downward
// (same shape, just taller), and the bell opens the full list.
//   qs ipc call island notifications      toggle the list
// Tap the clock for the date, tap the battery percent for time left.
// Every color comes from Theme.*, so theme switches fade this too.
//
// Alerts (all signal driven, nothing polls from QML):
//   volume / brightness  -> slim OSD that stretches the notch down briefly
//   battery 30/20/10 %   -> notification (UPower percentageChanged signal)
//   RAM over 85 %        -> notification with the top memory users
//                           (scripts/memwatch.sh prints a line only on crossing)

import Quickshell
import Quickshell.Io                 // Process, IpcHandler, FileView, SplitParser
import Quickshell.Wayland            // ToplevelManager: list of open windows
import Quickshell.Services.Mpris     // music players
import Quickshell.Services.UPower    // battery + charging state
import Quickshell.Services.Pipewire  // volume signals
import Quickshell.Services.Notifications   // NotificationServer
import QtQuick
import QtQuick.Shapes                // Shape: draws the notch outline
import QtQuick.Effects               // MultiEffect: rounds the album art corners

PanelWindow {
    id: win

    anchors.top: true                // top only = centered horizontally
    WlrLayershell.layer: WlrLayer.Top
    margins.top: 0                   // flush with the screen edge (the notch)
    implicitWidth: 1200              // room for the notch to grow into
    implicitHeight: 440              // room for the notch to stretch down
    // Keep reserving only the bar's height, not the whole tall window.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 44
    color: "transparent"

    // Only the notch catches clicks; the transparent rest lets clicks through.
    mask: Region { item: island }

    readonly property string font: "JetBrainsMono Nerd Font"

    // --- Shape and timing: tweak these -----------------------------------
    readonly property real glassAlpha: 0.90   // 1.0 = solid, lower = more see-through
    readonly property real flare: 30       // how far the top corners flare outward
    readonly property real corner: 16      // roundness of the bottom corners
    readonly property real pad: 10         // inner padding left/right
    readonly property real gap: 30         // space between sections
    readonly property int animMs: 380      // expand/shrink duration
    readonly property real notifWidth: 340 // width of the notification area
    readonly property int popupMs: 6000    // how long a popup stays
    readonly property int swapMs: 6000     // how long date / time-left stays
    readonly property int osdMs: 1500      // how long the volume/brightness bar stays
    readonly property real osdWidth: 260   // width of the volume/brightness bar area
    // True while only the popup card is showing (icons hidden, card fills the notch)
    readonly property bool popupOnly: popupShown && popup !== null && !listOpen && !osdShown

    // --- Data -------------------------------------------------------------
    readonly property var bat: UPower.displayDevice
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
    readonly property int pct: Math.round(bat.percentage * 100)   // UPower gives 0..1
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    // Battery color: charging = good, low = bad, getting low = accentHi, else normal text.
    readonly property color batTone: charging ? Theme.good
                                   : (pct <= 15 ? Theme.bad
                                   : (pct <= 30 ? Theme.accentHi : Theme.fg))

    property bool chargeSpace: false       // step 1: make room for the charging label
    property bool chargeShown: false       // step 2: fade the label in (after the room exists)

    // Tap-to-swap state
    property bool showDate: false          // clock shows the date instead of the time
    property bool showRemain: false        // battery shows time left instead of percent
    readonly property real secsLeft: charging ? bat.timeToFull : bat.timeToEmpty

    function fmtTime(sec) {
        if (!sec || sec <= 0) return "--"
        const m = Math.round(sec / 60)
        const h = Math.floor(m / 60)
        return h > 0 ? h + "h " + ("0" + (m % 60)).slice(-2) + "m" : m + "m"
    }
    function swapped() { swapTimer.restart() }

    Timer {
        id: swapTimer
        interval: win.swapMs
        onTriggered: { win.showDate = false; win.showRemain = false }
    }

    // Notification state
    property var popup: null               // newest notification, shown in the popup card
    property bool popupShown: false
    property bool listOpen: false          // full list open
    readonly property bool wantOpen: listOpen || (popupShown && popup !== null)
    readonly property int notifCount: server.trackedNotifications.values.length

    function toggleList() {
        listOpen = !listOpen
        popupShown = false
        popupTimer.stop()
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: (n) => {
            n.tracked = true                       // keep it so it appears in the list
            win.popup = n
            n.closed.connect(() => {
                if (win.popup === n) { win.popup = null; win.popupShown = false }
            })
            if (!win.listOpen) {
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
        osdShown = true
        osdTimer.restart()
    }

    Timer { id: osdTimer; interval: win.osdMs; onTriggered: win.osdShown = false }

    // Ignore the values that load when the shell starts or the audio sink changes.
    Timer { id: osdArm; interval: 2000; running: true }

    // Volume: PipeWire emits signals when it changes, nothing polls.
    readonly property var sink: Pipewire.defaultAudioSink
    property real lastVol: -1
    property bool lastMuted: false
    onSinkChanged: osdArm.restart()

    PwObjectTracker { objects: [win.sink] }       // makes the sink's audio properties live

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

    // Brightness: find the backlight once, then let inotify report changes.
    // (Fires when something writes the file: brightnessctl, light, compositor binds.)
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
    // Driven by UPower's percentageChanged signal. Notifies once per level on
    // the way down, never while charging; charging re-arms the levels.
    property int lastBatLevel: 0           // 0 = not known yet
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

    // ── RAM alert: memwatch.sh prints one line only when usage crosses 75 % ─
    Process {
        // Only the Island on the first screen runs the watcher, so with
        // several monitors you still get exactly one script and one card.
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

    // Network: ask the kernel for the default route. It prints the interface
    // name (wlan0, enp3s0...) or nothing when offline. Works with any network manager.
    property string netIface: ""
    readonly property bool online: netIface !== ""
    readonly property bool isWifi: netIface.startsWith("w")

    Process {
        id: netProc
        command: ["sh", "-c", "ip -o route show default | awk '{print $5; exit}'"]
        stdout: StdioCollector { onStreamFinished: win.netIface = text.trim() }
    }
    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: netProc.running = true
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // Battery signals: percentage drives the low-battery alerts; a state change
    // starts (or cancels) the charging sequence.
    Connections {
        target: win.bat
        function onPercentageChanged() { win.checkBattery() }
        function onStateChanged() {
            win.checkBattery()
            if (win.charging) chargeSeq.restart()
            else {
                chargeSeq.stop()
                win.chargeShown = false
                win.chargeSpace = false
            }
        }
    }

    // --- The notch ----------------------------------------------------------
    Item {
        id: island
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        // Height: popup = just the card; list = bar + list; OSD = bar + slim bar;
        // otherwise the 40px bar.
        readonly property real panelH: 36 + (win.notifCount > 0 ? Math.min(320, notifList.contentHeight) : 44) + 14
        height: win.popupOnly ? popupCard.implicitHeight + 24
                              : 40 + (win.listOpen ? panelH : (win.osdShown ? 44 : 0))
        Behavior on height { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

        // Width = sum of each section's final width (or the notification / OSD
        // width when that is wider). It is animated here, and the sections animate
        // with the same duration and curve, so they stay in sync.
        readonly property real rowW: 2 * win.flare + 2 * win.pad
             + wifiSec.target + batSec.target + chargeSec.target
             + clockSec.target + musicSec.target + winSec.target + bellSec.target
        width: Math.max(rowW,
                        win.wantOpen ? 2 * win.flare + 2 * win.pad + win.notifWidth : 0,
                        win.osdShown ? 2 * win.flare + 2 * win.pad + win.osdWidth : 0)
        Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

        // Hovering a popup pauses its timer.
        HoverHandler {
            onHoveredChanged: {
                if (hovered) popupTimer.stop()
                else if (win.popupShown) popupTimer.restart()
            }
        }

        // Plug-in sequence: grow first, THEN fade the text in. On the way out the
        // text fades first, THEN the notch shrinks.
        SequentialAnimation {
            id: chargeSeq
            ScriptAction { script: win.chargeSpace = true }
            PauseAnimation { duration: win.animMs }          // wait for the growth to finish
            ScriptAction { script: win.chargeShown = true }
            PauseAnimation { duration: 3500 }                // how long it stays expanded
            ScriptAction { script: win.chargeShown = false }
            PauseAnimation { duration: 250 }                 // wait for the fade-out
            ScriptAction { script: win.chargeSpace = false }
        }

        // Glass body drawn as one Shape with three layers:
        // 1) translucent fill, 2) specular sheen, 3) thin border (sides only,
        // so no line runs along the screen edge).
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer      // smooth edges

            // 1) glass fill
            ShapePath {
                strokeWidth: -1                       // fill only
                fillColor: Qt.alpha(Theme.panel, win.glassAlpha)
                startX: 0; startY: 0

                PathLine { x: island.width; y: 0 }                                        // top edge
                PathQuad { x: island.width - win.flare; y: win.flare
                           controlX: island.width - win.flare; controlY: 0 }               // right flare
                PathLine { x: island.width - win.flare; y: island.height - win.corner }   // right side
                PathArc {
                    x: island.width - win.flare - win.corner; y: island.height
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare + win.corner; y: island.height }                  // bottom edge
                PathArc {
                    x: win.flare; y: island.height - win.corner
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare; y: win.flare }                                   // left side
                PathQuad { x: 0; y: 0; controlX: win.flare; controlY: 0 }                 // left flare
            }

            // 2) sheen: a soft highlight fading down from the top edge
            ShapePath {
                strokeWidth: -1                       // fill only
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: island.height
                    GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.14) }
                    GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0.0) }
                }
                startX: 0; startY: 0

                PathLine { x: island.width; y: 0 }                                        // top edge
                PathQuad { x: island.width - win.flare; y: win.flare
                           controlX: island.width - win.flare; controlY: 0 }               // right flare
                PathLine { x: island.width - win.flare; y: island.height - win.corner }   // right side
                PathArc {
                    x: island.width - win.flare - win.corner; y: island.height
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare + win.corner; y: island.height }                  // bottom edge
                PathArc {
                    x: win.flare; y: island.height - win.corner
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare; y: win.flare }                                   // left side
                PathQuad { x: 0; y: 0; controlX: win.flare; controlY: 0 }                 // left flare
            }

            // 3) border: same outline but open at the top (starts at the right
            // top corner and ends at the left one)
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.16)
                strokeWidth: 1
                startX: island.width; startY: 0

                PathQuad {
                    x: island.width - win.flare; y: win.flare
                    controlX: island.width - win.flare; controlY: 0
                }
                PathLine { x: island.width - win.flare; y: island.height - win.corner }
                PathArc {
                    x: island.width - win.flare - win.corner; y: island.height
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare + win.corner; y: island.height }
                PathArc {
                    x: win.flare; y: island.height - win.corner
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare; y: win.flare }
                PathQuad { x: 0; y: 0; controlX: win.flare; controlY: 0 }
            }
        }

        // Everything inside is clipped to the straight-sided body (the flares
        // are decoration only), so nothing draws outside the notch.
        Item {
            x: win.flare
            width: island.width - 2 * win.flare
            height: island.height
            clip: true

            // A left-to-right row of sections, centered in the notch (so it stays
            // centered when the notch is wider because of a notification).
            // Each section's width includes the gap in front of it, so a section
            // that disappears takes its gap with it.
            Row {
                x: Math.max(win.pad, (parent.width - width) / 2)
                height: 40
                spacing: 0
                opacity: win.popupOnly ? 0 : 1
                enabled: !win.popupOnly          // invisible icons shouldn't catch clicks
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // 1. NETWORK: wifi / ethernet / offline warning
                Item {
                    id: wifiSec
                    readonly property real target: 18
                    width: target; height: 40
                    Text {
                        anchors.centerIn: parent
                        font.family: win.font; font.pixelSize: 14
                        text: !win.online ? "\uf071" : (win.isWifi ? "\uf1eb" : "\uf0e8")
                        color: win.online ? Theme.fg : Theme.bad
                    }
                }

                // 2. BATTERY: small iOS-style battery, bolt while charging, then the
                // number. Tap the number to swap it for the time left.
                Item {
                    id: batSec
                    readonly property real target: win.gap + batRow.implicitWidth
                    width: target; height: 40
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
                    Row {
                        id: batRow
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 12

                            Rectangle {                                   // outline
                                width: 23; height: 12; radius: 4
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.alpha(win.batTone, 0.6)

                                Rectangle {                               // level
                                    x: 2; y: 2
                                    height: parent.height - 4
                                    width: Math.max(0, (parent.width - 4) * Math.min(1, win.pct / 100))
                                    radius: 2
                                    color: win.batTone
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                            Rectangle {                                   // little nub on the right
                                x: 24; anchors.verticalCenter: parent.verticalCenter
                                width: 2; height: 5; radius: 1
                                color: Qt.alpha(win.batTone, 0.6)
                            }
                        }
                        Text {
                            visible: win.charging
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.font; font.pixelSize: 13
                            text: "\uf0e7"
                            color: Theme.good
                        }
                        Text {
                            id: batText
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            text: win.showRemain ? win.fmtTime(win.secsLeft) : win.pct + "%"
                            color: win.batTone

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { win.showRemain = !win.showRemain; win.swapped() }
                            }
                        }
                    }
                }

                // 3. CHARGING LABEL (only takes space during the plug-in sequence)
                Item {
                    id: chargeSec
                    readonly property real target: win.chargeSpace ? win.gap + chargeLabel.implicitWidth : 0
                    width: target; height: 40
                    clip: true
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                    Text {
                        id: chargeLabel
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        text: "Charging"
                        color: Theme.good
                        opacity: win.chargeShown ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                // 4. CLOCK: tap to swap the time for the date
                Item {
                    id: clockSec
                    readonly property real target: win.gap + clockText.implicitWidth
                    width: target; height: 40
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
                    Text {
                        id: clockText
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        color: Theme.fg
                        text: Qt.formatDateTime(clock.date, win.showDate ? "ddd d MMM" : "HH:mm")

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { win.showDate = !win.showDate; win.swapped() }
                        }
                    }
                }

                // 5. MUSIC: rounded album art, title, prev / play / next
                Item {
                    id: musicSec
                    property bool want: win.player !== null
                    property bool revealed: false        // true once the notch has finished growing
                    readonly property real target: want ? win.gap + musicRow.implicitWidth : 0
                    width: target; height: 40
                    clip: true
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                    // Fade the content in only after the growth animation is done.
                    onWantChanged: { if (want) revealTimer.restart(); else revealed = false }
                    Component.onCompleted: if (want) revealTimer.start()
                    Timer { id: revealTimer; interval: win.animMs; onTriggered: musicSec.revealed = true }

                    Row {
                        id: musicRow
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        opacity: musicSec.revealed ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Album art with rounded corners (the mask is a white rounded square).
                        Item {
                            width: 24; height: 24
                            anchors.verticalCenter: parent.verticalCenter
                            visible: musicSec.want       // no offscreen buffers while nothing plays

                            Image {
                                id: art
                                anchors.fill: parent
                                visible: false           // shown through the MultiEffect below
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(48, 48)
                                source: win.player ? win.player.trackArtUrl : ""
                            }
                            Rectangle {
                                id: artMask
                                anchors.fill: parent
                                radius: 7
                                visible: false
                                layer.enabled: true      // the mask has to be a texture
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

                        // Song title, cut off with "…" if long.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 140)
                            elide: Text.ElideRight
                            font.family: win.font; font.pixelSize: 13
                            color: Theme.fg
                            text: win.player ? win.player.trackTitle : ""
                        }

                        // Prev / play-pause (round accent button) / next.
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Repeater {
                                model: ["prev", "play", "next"]
                                delegate: Item {
                                    id: ctl
                                    required property string modelData
                                    readonly property bool isPlay: modelData === "play"
                                    width: 24; height: 24

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: ctl.isPlay ? Theme.accent
                                                          : Qt.rgba(1, 1, 1, ctlArea.containsMouse ? 0.16 : 0)
                                        opacity: ctl.isPlay && ctlArea.containsMouse ? 0.85 : 1
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        font.family: win.font; font.pixelSize: 10
                                        color: ctl.isPlay ? Theme.accentText : Theme.fg
                                        text: ctl.modelData === "prev" ? "\uf048"
                                            : (ctl.isPlay ? ((win.player && win.player.isPlaying) ? "\uf04c" : "\uf04b")
                                                          : "\uf051")
                                    }
                                    MouseArea {
                                        id: ctlArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (!win.player) return
                                            if (ctl.modelData === "prev") win.player.previous()
                                            else if (ctl.isPlay) win.player.togglePlaying()
                                            else win.player.next()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 6. OPEN WINDOWS: one icon per window, the active one gets a glass capsule
                Item {
                    id: winSec
                    readonly property int count: ToplevelManager.toplevels.values.length
                    readonly property real target: count > 0 ? win.gap + iconsRow.implicitWidth : 0
                    width: target; height: 40
                    clip: true
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                    Row {
                        id: iconsRow
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        // Repeater makes one copy of the delegate per window.
                        Repeater {
                            model: ToplevelManager.toplevels
                            delegate: Rectangle {
                                required property var modelData      // the window this copy represents
                                width: 28; height: 28; radius: 10
                                color: modelData.activated ? Qt.rgba(1, 1, 1, 0.16) : "transparent"

                                Image {
                                    anchors.centerIn: parent
                                    width: 18; height: 18
                                    sourceSize: Qt.size(36, 36)
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

                // 7. NOTIFICATION BELL: shows while notifications are waiting (or the
                // list is open). Tap to open / close the list.
                Item {
                    id: bellSec
                    readonly property bool want: win.notifCount > 0 || win.listOpen
                    readonly property real target: want ? win.gap + bellRow.implicitWidth : 0
                    width: target; height: 40
                    clip: true
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                    Row {
                        id: bellRow
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.font; font.pixelSize: 13
                            text: "\uf0f3"
                            color: win.listOpen ? Theme.accentHi : Theme.fg
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: win.notifCount > 0
                            font.family: win.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            text: win.notifCount
                            color: win.listOpen ? Theme.accentHi : Theme.fg
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.toggleList()
                    }
                }
            }

            // ── OSD bar: volume / brightness, sits under the bar row ──
            Item {
                id: osdArea
                x: win.pad
                y: 40
                width: parent.width - 2 * win.pad
                height: 44
                opacity: win.osdShown && !win.listOpen && !win.popupOnly ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                Text {
                    id: osdIc
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    font.family: win.font; font.pixelSize: 15
                    color: Theme.fg
                    text: win.osdIcon
                }
                Text {
                    id: osdPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    horizontalAlignment: Text.AlignRight
                    font.family: win.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: Theme.fg
                    text: win.osdMuted ? "mute" : Math.round(win.osdValue * 100) + "%"
                }
                Rectangle {
                    anchors.left: osdIc.right; anchors.leftMargin: 10
                    anchors.right: osdPct.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4; radius: 2
                    color: Qt.rgba(1, 1, 1, 0.16)

                    Rectangle {
                        height: parent.height; radius: 2
                        width: parent.width * Math.min(1, Math.max(0, win.osdValue))
                        color: win.osdMuted ? Theme.fgDim : Theme.accent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
            }

            // ── Notification area: sits under the bar and is revealed as the notch stretches ──
            Item {
                id: notifArea
                x: win.pad
                y: win.popupOnly ? 10 : 40
                Behavior on y { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }
                width: parent.width - 2 * win.pad
                height: Math.max(0, parent.height - y)
                clip: true
                opacity: win.wantOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }

                // Popup: just the newest notification
                IslandNotif {
                    id: popupCard
                    visible: win.popupShown && !win.listOpen && win.popup !== null
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    width: parent.width
                    notif: win.popup
                }

                // Full list
                Item {
                    anchors.fill: parent
                    visible: win.listOpen

                    Item {
                        id: listHead
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "NOTIFICATIONS"
                            color: Theme.accentHi
                            font.family: win.font
                            font.pixelSize: 9
                            font.letterSpacing: 4
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: win.notifCount > 0
                            text: "CLEAR ALL"
                            color: clearArea.containsMouse ? Theme.accentHi : Theme.fg
                            font.family: win.font
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            MouseArea {
                                id: clearArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // copy first: dismissing changes the live list
                                    const all = server.trackedNotifications.values.slice()
                                    all.forEach(n => n.dismiss())
                                }
                            }
                        }
                    }

                    Text {
                        anchors.top: listHead.bottom
                        anchors.topMargin: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: win.notifCount === 0
                        text: "NO NOTIFICATIONS"
                        color: Theme.fgDim
                        font.family: win.font
                        font.pixelSize: 10
                        font.letterSpacing: 3
                    }

                    ListView {
                        id: notifList
                        anchors.top: listHead.bottom
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
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
    }
}
