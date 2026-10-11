// File: ~/.config/quickshell/Island.qml

import Quickshell
import Quickshell.Io                 // Process: run shell commands
import Quickshell.Wayland             // ToplevelManager: list of open windows
import Quickshell.Widgets             // ClippingRectangle: crops album art into a circle
import Quickshell.Services.Mpris      // music players
import Quickshell.Services.UPower     // battery + charging state
import QtQuick
import QtQuick.Shapes                 // Shape: lets us draw the notch outline

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

    // --- Theme (Blue) -----------------------------------------------------
    readonly property color bg: Qt.rgba(16/255, 20/255, 28/255, 0.92)         // Warm dark blue background
    readonly property color chip: "#1c243a"         // borders + active-window highlight
    readonly property color fg: "#e5e5e5"
    readonly property color dim: "#8892b0"
    readonly property color green: "#3b82f6"       // charging (blue accent)
    readonly property color warn: "#60a5fa"
    readonly property color crit: "#3b82f6"
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property string textFont: "JetBrainsMono Nerd Font"

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

    property bool showDate: false          // clock toggle: time <-> date
    property bool chargeSpace: false       // step 1: make room for the charging label
    property bool chargeShown: false       // step 2: fade the label in (after the room exists)

    // Network: ask the kernel for the default route. It prints the interface
    // name (wlan0, enp3s0...) or nothing at all when you're offline. This works
    // with NetworkManager, iwd, systemd-networkd, anything.
    property string netIface: ""
    readonly property bool online: netIface !== ""
    readonly property bool isWifi: netIface.startsWith("w")

    Process {
        id: netProc
        command: ["sh", "-c", "ip -o route show default | awk '{print $5; exit}'"]
        stdout: StdioCollector { onStreamFinished: win.netIface = text.trim() }
    }
    Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
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

    // A small button used by the music controls.
    component CtlButton: Item {
        id: btn
        property string glyph: ""
        property int glyphSize: 12
        property bool filled: false
        signal clicked()
        width: 26; height: 26

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: btn.filled ? "#3b82f6" : (hover.containsMouse ? "#1c243a" : "transparent")
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: btn.glyphSize
            color: btn.filled ? "#10141c" : "#e5e5e5"
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }

    // --- The notch ----------------------------------------------------------
    Item {
        id: island
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        height: 40

        // The notch's width is the SUM OF EACH SECTION'S FINAL WIDTH, and it is
        // the only thing animated here. The sections inside animate with the same
        // duration and curve, so they stay in sync and nothing spills outside.
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

        // The outline. It starts at the top-left corner and walks clockwise.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer      // smooth edges
            ShapePath {
                fillColor: win.bg
                strokeColor: win.chip
                strokeWidth: 0
                startX: 0; startY: 0

                PathLine { x: island.width; y: 0 }                                    // top edge
                PathQuad {                                                            // right flare
                    x: island.width - win.flare; y: win.flare
                    controlX: island.width - win.flare; controlY: 0
                }
                PathLine { x: island.width - win.flare; y: island.height - win.corner }   // right side
                PathArc {                                                             // bottom-right corner
                    x: island.width - win.flare - win.corner; y: island.height
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare + win.corner; y: island.height }              // bottom edge
                PathArc {                                                             // bottom-left corner
                    x: win.flare; y: island.height - win.corner
                    radiusX: win.corner; radiusY: win.corner
                    direction: PathArc.Clockwise
                }
                PathLine { x: win.flare; y: win.flare }                                // left side
                PathQuad {                                                            // left flare
                    x: 0; y: 0
                    controlX: win.flare; controlY: 0
                }
            }
        }

        // Everything inside is clipped to the body, so nothing can ever draw
        // outside the notch while it is growing or shrinking.
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

                // 1. WIFI / ETHERNET / OFFLINE
                Item {
                    id: wifiSec
                    readonly property real target: 22
                    width: target; height: 40
                    Text {
                        anchors.centerIn: parent
                        font.family: win.iconFont; font.pixelSize: 18
                        text: !win.online ? "\uf071" : (win.isWifi ? "\uf1eb" : "\uf0e8")
                        color: win.online ? win.fg : win.crit
                    }
                }

                // 2. BATTERY
                Item {
                    id: batSec
                    readonly property real target: win.gap + batRow.implicitWidth
                    width: target; height: 40
                    Row {
                        id: batRow
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.iconFont; font.pixelSize: 18
                            // Pick one of 5 battery glyphs from the percentage.
                            text: ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"][Math.min(4, Math.floor(win.pct / 25))]
                            color: win.charging ? win.green : (win.pct <= 15 ? win.crit : (win.pct <= 30 ? win.warn : win.fg))
                        }
                        Text {
                            visible: win.charging
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.iconFont; font.pixelSize: 14
                            text: "\uf0e7"
                            color: win.green
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            text: win.pct + "%"
                            color: win.charging ? win.green : (win.pct <= 15 ? win.crit : (win.pct <= 30 ? win.warn : win.fg))
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
                        font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                        text: "Charging"
                        color: win.green
                        opacity: win.chargeShown ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                // 4. CLOCK (tap to switch between time and date)
                Item {
                    id: clockSec
                    readonly property real target: win.gap + clockRow.implicitWidth
                    width: target; height: 40
                    clip: true
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                    Row {
                        id: clockRow
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.iconFont; font.pixelSize: 15
                            text: win.showDate ? "\uf073" : "\uf017"
                            color: win.dim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            color: win.fg
                            text: win.showDate ? Qt.formatDateTime(clock.date, "ddd, MMM d")
                                               : Qt.formatDateTime(clock.date, "HH:mm")
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: win.showDate = !win.showDate }
                }

                // 5. MUSIC: spinning album art, title, prev / play / next
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
                        spacing: 8
                        opacity: musicSec.revealed ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Circle-cropped album art that spins while music plays.
                        ClippingRectangle {
                            width: 30; height: 30; radius: 15
                            anchors.verticalCenter: parent.verticalCenter
                            color: win.chip              // shows when there's no art
                            Text {
                                anchors.centerIn: parent
                                text: "♪"; color: win.dim; font.pixelSize: 14
                                visible: art.status !== Image.Ready
                            }
                            Image {
                                id: art
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(64, 64)
                                source: win.player ? win.player.trackArtUrl : ""
                            }
                            // One full turn every 6 seconds; it just pauses when the music pauses.
                            RotationAnimator on rotation {
                                from: 0; to: 360; duration: 6000
                                loops: Animation.Infinite
                                running: win.player !== null && win.player.isPlaying
                            }
                        }

                        // Song title only (no artist), cut off with "…" if long.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 150)
                            elide: Text.ElideRight
                            font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            color: win.fg
                            text: win.player ? win.player.trackTitle : ""
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            CtlButton { glyph: "\uf048"; onClicked: if (win.player) win.player.previous() }
                            CtlButton {
                                width: 30; height: 30
                                filled: true
                                glyph: (win.player && win.player.isPlaying) ? "\uf04c" : "\uf04b"
                                onClicked: if (win.player) win.player.togglePlaying()
                            }
                            CtlButton { glyph: "\uf051"; onClicked: if (win.player) win.player.next() }
                        }
                    }
                }

                // 6. OPEN WINDOWS (larger icons, active one highlighted)
                Item {
                    id: winSec
                    readonly property int count: ToplevelManager.toplevels.values.length
                    readonly property real target: count > 0 ? win.gap + 1 + 10 + iconsRow.implicitWidth : 0
                    width: target; height: 40
                    clip: true
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                    Row {
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Rectangle { width: 1; height: 20; color: win.chip; anchors.verticalCenter: parent.verticalCenter }

                        Row {
                            id: iconsRow
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            // Repeater makes one copy of the delegate per window.
                            Repeater {
                                model: ToplevelManager.toplevels
                                delegate: Item {
                                    required property var modelData      // the window this copy represents
                                    width: 30; height: 30

                                    Rectangle {
                                        anchors.fill: parent; radius: 10
                                        color: win.chip
                                        visible: modelData.activated
                                    }
                                    Image {
                                        anchors.centerIn: parent
                                        width: 22; height: 22
                                        sourceSize: Qt.size(40, 40)
                                        opacity: modelData.activated ? 1 : 0.45
                                        source: Quickshell.iconPath(modelData.appId, "application-x-executable")
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.MiddleButton) modelData.close()
                                            else modelData.activate()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
