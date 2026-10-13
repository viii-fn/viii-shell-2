// File: ~/viii-shell-2/shell/Island.qml
// A glass notch attached to the top edge of the screen: network, battery
// (with the charging sequence), clock, music (only while a player exists)
// and open-window icons. Top corners flare outward into the screen edge,
// bottom corners are rounded.
// Every color comes from Theme.*, so theme switches fade this too.

import Quickshell
import Quickshell.Io                 // Process: run shell commands
import Quickshell.Wayland            // ToplevelManager: list of open windows
import Quickshell.Services.Mpris     // music players
import Quickshell.Services.UPower    // battery + charging state
import QtQuick
import QtQuick.Shapes                // Shape: draws the notch outline
import QtQuick.Effects               // MultiEffect: rounds the album art corners

PanelWindow {
    id: win

    anchors.top: true                // top only = centered horizontally
    WlrLayershell.layer: WlrLayer.Top
    margins.top: 0                   // flush with the screen edge (the notch)
    implicitWidth: 1200              // room for the notch to grow into
    implicitHeight: 44
    color: "transparent"

    // Only the notch catches clicks; the transparent rest lets clicks through.
    mask: Region { item: island }

    readonly property string font: "JetBrainsMono Nerd Font"

    // --- Shape and timing: tweak these -----------------------------------
    readonly property real flare: 30       // how far the top corners flare outward
    readonly property real corner: 16      // roundness of the bottom corners
    readonly property real pad: 10         // inner padding left/right
    readonly property real gap: 30         // space between sections
    readonly property int animMs: 380      // expand/shrink duration

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

    // When the battery state changes, start (or cancel) the charging sequence.
    Connections {
        target: win.bat
        function onStateChanged() {
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
        height: 40

        // Width = sum of each section's final width. It is animated here, and
        // the sections animate with the same duration and curve, so they stay
        // in sync and nothing spills outside.
        width: 2 * win.flare + 2 * win.pad
             + wifiSec.target + batSec.target + chargeSec.target
             + clockSec.target + musicSec.target + winSec.target
        Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

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
                fillColor: Qt.alpha(Theme.panel, 0.72)
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

            // A left-to-right row of sections. Each section's width includes the
            // gap in front of it, so a section that disappears takes its gap with it.
            Row {
                x: win.pad
                height: parent.height
                spacing: 0

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

                // 2. BATTERY: small iOS-style battery, bolt while charging, then the number
                Item {
                    id: batSec
                    readonly property real target: win.gap + batRow.implicitWidth
                    width: target; height: 40
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
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            text: win.pct + "%"
                            color: win.batTone
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

                // 4. CLOCK
                Item {
                    id: clockSec
                    readonly property real target: win.gap + clockText.implicitWidth
                    width: target; height: 40
                    Text {
                        id: clockText
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        color: Theme.fg
                        text: Qt.formatDateTime(clock.date, "HH:mm")
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
            }
        }
    }
}
