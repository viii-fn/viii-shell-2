// File: ~/viii-shell-2/shell/Island.qml
// The notch at the top of the screen, restyled as part of the hive:
//   - the body is a chamfered shape (cut corners at the honeycomb angle)
//   - wifi, clock, music buttons and window chips are hexagons
//   - the battery is a hexagon that fills up like a honeycomb cell
//   - the album art is cropped to a hexagon
//   - a faint honeycomb pattern sits behind everything (painted once)
// Every color comes from Theme.*, so theme switches fade this too.
// The logic (UPower, MPRIS, toplevels, network check, charging sequence) is
// the same as before.

import Quickshell
import Quickshell.Io                 // Process: run shell commands
import Quickshell.Wayland             // ToplevelManager: list of open windows
import Quickshell.Services.Mpris      // music players
import Quickshell.Services.UPower     // battery + charging state
import QtQuick
import QtQuick.Shapes                 // Shape: draws the notch outline
import QtQuick.Effects                // MultiEffect: crops album art to a hexagon

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

    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property string textFont: "JetBrainsMono Nerd Font"

    // --- Shape and timing: tweak these -----------------------------------
    // Slopes are chosen so the cut corners sit at 60 degrees, like a hexagon.
    readonly property real flare: 8        // how far the top "ears" stick out
    readonly property real earH: 14        // how far down the ears slope
    readonly property real chamX: 11.5     // bottom chamfer, horizontal part
    readonly property real chamY: 20       // bottom chamfer, vertical part
    readonly property real pad: 14         // inner padding left/right
    readonly property real gap: 30         // space between sections
    readonly property int animMs: 380      // expand/shrink duration
    readonly property real hexK: 1.1547    // width / height of a regular flat-top hexagon

    // --- Data -------------------------------------------------------------
    readonly property var bat: UPower.displayDevice
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
    readonly property int pct: Math.round(bat.percentage * 100)   // UPower gives 0..1
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    // Battery color: charging = good, low = bad, getting low = accentHi, else normal text.
    readonly property color batTone: charging ? Theme.good
                                   : (pct <= 15 ? Theme.bad
                                   : (pct <= 30 ? Theme.accentHi : Theme.fg))

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
    // Was every 4 s; every 10 s wakes the CPU less often and is plenty for a status icon.
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

    // A hexagon button / icon holder. `size` is its height; the width follows.
    component HexBtn: Item {
        id: btn
        property string glyph: ""
        property int glyphSize: 12
        property real size: 26
        property bool filled: false          // accent fill (the play button)
        property bool outlined: false        // thin outline (status icons)
        property bool interactive: true
        property color tone: Theme.fg
        signal clicked()
        height: size
        width: size * win.hexK

        HexShape {
            anchors.fill: parent
            fillColor: btn.filled ? Theme.accent
                     : ((btn.interactive && hover.containsMouse) ? Theme.surface
                     : (btn.outlined ? Theme.surface : "transparent"))
            strokeColor: btn.outlined ? Theme.line : "transparent"
            strokeWidth: btn.outlined ? 1 : 0
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: win.iconFont
            font.pixelSize: btn.glyphSize
            color: btn.filled ? Theme.accentText : btn.tone
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            enabled: btn.interactive
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

        // The outline: top ears, straight sides, chamfered bottom corners.
        // It starts at the top-left corner and walks clockwise.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.panel
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                strokeWidth: 1
                joinStyle: ShapePath.RoundJoin
                startX: 0; startY: 0

                PathLine { x: island.width; y: 0 }                                              // top edge
                PathLine { x: island.width - win.flare; y: win.earH }                           // right ear
                PathLine { x: island.width - win.flare; y: island.height - win.chamY }          // right side
                PathLine { x: island.width - win.flare - win.chamX; y: island.height }          // bottom-right chamfer
                PathLine { x: win.flare + win.chamX; y: island.height }                         // bottom edge
                PathLine { x: win.flare; y: island.height - win.chamY }                         // bottom-left chamfer
                PathLine { x: win.flare; y: win.earH }                                          // left side
                PathLine { x: 0; y: 0 }                                                         // left ear
            }
        }

        // Faint honeycomb behind the content. The canvas is as wide as the
        // window and painted once; the notch just reveals more of it as it
        // grows, so the cells stay put on screen.
        Item {
            x: win.flare + win.chamX
            width: Math.max(0, island.width - 2 * (win.flare + win.chamX))
            height: island.height
            clip: true
            HexPattern {
                x: (parent.width - width) / 2
                width: win.implicitWidth
                height: island.height
                opacity: 0.07
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
                    readonly property real target: 26 * win.hexK
                    width: target; height: 40
                    HexBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 26
                        outlined: true
                        interactive: false
                        glyphSize: 13
                        glyph: !win.online ? "\uf071" : (win.isWifi ? "\uf1eb" : "\uf0e8")
                        tone: win.online ? Theme.fg : Theme.bad
                    }
                }

                // 2. BATTERY: a hexagon that fills from the bottom, then the number
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
                            id: hexBat
                            width: 28 * win.hexK; height: 28
                            anchors.verticalCenter: parent.verticalCenter

                            HexShape {
                                anchors.fill: parent
                                fillColor: Theme.surface
                                strokeColor: win.batTone
                                strokeWidth: 1.5
                            }
                            // The "honey level": a clip box that grows upward.
                            Item {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                          leftMargin: 4; rightMargin: 4; bottomMargin: 4 }
                                height: (hexBat.height - 8) * Math.max(0, Math.min(1, win.pct / 100))
                                clip: true
                                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                HexShape {
                                    anchors.bottom: parent.bottom
                                    width: hexBat.width - 8
                                    height: hexBat.height - 8
                                    fillColor: win.batTone
                                }
                            }
                        }
                        Text {
                            visible: win.charging
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.iconFont; font.pixelSize: 14
                            text: "\uf0e7"
                            color: Theme.good
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
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
                        font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                        text: "Charging"
                        color: Theme.good
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
                        spacing: 8
                        HexBtn {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 24
                            outlined: true
                            interactive: false
                            glyphSize: 11
                            tone: Theme.accentHi
                            glyph: win.showDate ? "\uf073" : "\uf017"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            color: Theme.fg
                            text: win.showDate ? Qt.formatDateTime(clock.date, "ddd, MMM d")
                                               : Qt.formatDateTime(clock.date, "HH:mm")
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: win.showDate = !win.showDate }
                }

                // 5. MUSIC: hexagon album art, title, prev / play / next
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

                        // Hexagon-cropped album art. It no longer spins: a constant
                        // rotation keeps the GPU busy the whole time music plays.
                        Item {
                            id: artHex
                            width: 30 * win.hexK; height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            visible: musicSec.want       // no offscreen buffers while nothing plays

                            Item {
                                id: artStack
                                anchors.fill: parent
                                visible: false
                                Rectangle { anchors.fill: parent; color: Theme.surface }
                                Text {
                                    anchors.centerIn: parent
                                    text: "♪"; color: Theme.fgDim; font.pixelSize: 14
                                    visible: art.status !== Image.Ready
                                }
                                Image {
                                    id: art
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(64, 64)
                                    source: win.player ? win.player.trackArtUrl : ""
                                }
                            }
                            HexShape {
                                id: artMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                layer.samples: 4
                                fillColor: "white"
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: artStack
                                maskEnabled: true
                                maskSource: artMask
                            }
                            HexShape {
                                anchors.fill: parent
                                strokeColor: Theme.accent
                                strokeWidth: 1.5
                            }
                        }

                        // Song title only (no artist), cut off with "…" if long.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 150)
                            elide: Text.ElideRight
                            font.family: win.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            color: Theme.fg
                            text: win.player ? win.player.trackTitle : ""
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            HexBtn { size: 26; glyph: "\uf048"; onClicked: if (win.player) win.player.previous() }
                            HexBtn {
                                size: 30
                                filled: true
                                glyph: (win.player && win.player.isPlaying) ? "\uf04c" : "\uf04b"
                                onClicked: if (win.player) win.player.togglePlaying()
                            }
                            HexBtn { size: 26; glyph: "\uf051"; onClicked: if (win.player) win.player.next() }
                        }
                    }
                }

                // 6. OPEN WINDOWS (hexagon icon cells, active one outlined in the accent)
                Item {
                    id: winSec
                    readonly property int count: ToplevelManager.toplevels.values.length
                    readonly property real target: count > 0 ? win.gap + 12 + 10 + iconsRow.implicitWidth : 0
                    width: target; height: 40
                    clip: true
                    Behavior on width { NumberAnimation { duration: win.animMs; easing.type: Easing.OutCubic } }

                    Row {
                        x: win.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        // little accent hexagon as the divider
                        HexShape {
                            width: 12; height: 12 / win.hexK
                            anchors.verticalCenter: parent.verticalCenter
                            fillColor: Theme.accent
                            opacity: 0.8
                        }

                        Row {
                            id: iconsRow
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            // Repeater makes one copy of the delegate per window.
                            Repeater {
                                model: ToplevelManager.toplevels
                                delegate: Item {
                                    required property var modelData      // the window this copy represents
                                    width: 30 * win.hexK; height: 30

                                    HexShape {
                                        anchors.fill: parent
                                        visible: modelData.activated
                                        fillColor: Theme.surface
                                        strokeColor: Theme.accent
                                        strokeWidth: 1
                                    }
                                    Image {
                                        anchors.centerIn: parent
                                        width: 20; height: 20
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
