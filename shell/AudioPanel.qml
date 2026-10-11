// File: ~/viii-shell-2/shell/AudioPanel.qml
// Audio output picker, restyled as a hive. Same logic as before. The window is
// created on the first toggle and destroyed shortly after it closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Scope {
    id: root

    property bool shown: false
    property bool alive: false           // true while the window exists (open + closing)
    readonly property int closeMs: 600

    onShownChanged: {
        if (shown) { unload.stop(); alive = true }
        else unload.restart()
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }

    // Your Intel HDA card (from `pactl list cards`).
    readonly property string card: "alsa_card.pci-0000_00_1b.0"

    // Real output devices only, not per-app playback streams.
    // Only tracked while the panel exists (or a profile switch is settling).
    readonly property var sinks: (alive || settle.running)
        ? Pipewire.nodes.values.filter(n => n.isSink && !n.isStream) : []
    readonly property var current: Pipewire.defaultAudioSink
    readonly property bool onHdmi: current !== null && (current.name || "").indexOf("hdmi") !== -1

    // Your card can only drive analog OR HDMI at once, so switching = changing profile.
    function setProfile(profile) {
        profileProc.command = ["pactl", "set-card-profile", card, profile]
        profileProc.running = true
        settle.restart()
    }

    Process { id: profileProc }

    // After the profile changes the old sink disappears and a new one appears.
    // Wait a moment, then make whatever sink is there the default.
    Timer {
        id: settle
        interval: 700
        onTriggered: {
            if (root.sinks.length > 0)
                Pipewire.preferredDefaultAudioSink = root.sinks[0]
        }
    }

    // Toggle from a keybind: qs ipc call audio toggle
    IpcHandler {
        target: "audio"
        function toggle(): void { root.shown = !root.shown }
    }

    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: w
            title: "Audio Output"
            color: "transparent"
            visible: true
            implicitWidth: 400
            implicitHeight: col.implicitHeight + 48

            // 0 = hidden, 1 = open. Starts at 0 and fades in once created.
            property real appear: 0
            Behavior on appear { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Component.onCompleted: appear = Qt.binding(() => root.shown ? 1 : 0)

            onVisibleChanged: if (!visible) root.shown = false

            PwObjectTracker { objects: root.sinks }

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }

            ChamferPanel {
                anchors.fill: parent
                cut: 16
                pattern: true
                opacity: w.appear

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 24
                    spacing: 10

                    RowLayout {
                        spacing: 8
                        HexShape {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12 / 1.1547
                            Layout.alignment: Qt.AlignVCenter
                            fillColor: Theme.accent
                        }
                        Text {
                            text: "OUTPUT"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.letterSpacing: 4
                        }
                    }

                    // Main switch: speakers/headphones vs TV.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Speakers / headphones", glyph: "\uf025", profile: "output:analog-stereo+input:analog-stereo", hdmi: false },
                                { label: "HDMI (TV)",             glyph: "\uf26c", profile: "output:hdmi-stereo+input:analog-stereo",   hdmi: true }
                            ]

                            delegate: ChamferPanel {
                                id: btn
                                required property var modelData
                                readonly property bool active: root.onHdmi === modelData.hdmi

                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                cut: 10
                                fillColor: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                                  : (btnHover.containsMouse ? Qt.rgba(1, 1, 1, 0.08)
                                                                            : Qt.rgba(1, 1, 1, 0.04))
                                strokeColor: active ? Theme.accent : Theme.line

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    HexButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 24; glyphSize: 11
                                        outlined: true; interactive: false
                                        tone: btn.active ? Theme.accentHi : Theme.fgDim
                                        glyph: btn.modelData.glyph
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: btn.modelData.label
                                        color: btn.active ? Theme.accentHi : Theme.fg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                    }
                                }

                                MouseArea {
                                    id: btnHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setProfile(btn.modelData.profile)
                                }
                            }
                        }
                    }

                    // Individual devices (useful for anything beyond the two above, e.g. Bluetooth).
                    Repeater {
                        model: root.sinks

                        delegate: ChamferPanel {
                            id: row
                            required property var modelData
                            readonly property bool active:
                                root.current !== null && root.current.id === modelData.id

                            Layout.fillWidth: true
                            Layout.preferredHeight: 42
                            cut: 8
                            fillColor: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                            strokeColor: active ? Theme.accent : Theme.line

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                // hexagon marker: filled when this is the active output
                                HexShape {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14 / 1.1547
                                    Layout.alignment: Qt.AlignVCenter
                                    fillColor: row.active ? Theme.accent : "transparent"
                                    strokeColor: row.active ? Theme.accent : Theme.fgDim
                                    strokeWidth: 1
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.description || row.modelData.nickname || row.modelData.name
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }
                            }

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Pipewire.preferredDefaultAudioSink = row.modelData
                            }
                        }
                    }

                    // Volume for whichever output is currently the default.
                    HexSlider {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        visible: root.current !== null && root.current.audio !== null
                        value: root.current && root.current.audio ? root.current.audio.volume : 0
                        tone: root.current && root.current.audio && root.current.audio.muted ? Theme.fgDim : Theme.accent
                        onMoved: v => {
                            if (root.current && root.current.audio)
                                root.current.audio.volume = v
                        }
                    }
                }
            }
        }
    }
}
