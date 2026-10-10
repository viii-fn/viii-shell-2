import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Scope {
    id: root

    property bool shown: false

    // Your Intel HDA card (from `pactl list cards`).
    readonly property string card: "alsa_card.pci-0000_00_1b.0"

    // Real output devices only, not per-app playback streams.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)
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
        active: root.shown

        FloatingWindow {
            title: "Audio Output"
            color: "transparent"
            visible: true
            implicitWidth: 380
            implicitHeight: col.implicitHeight + 32

            onVisibleChanged: if (!visible) root.shown = false

            PwObjectTracker { objects: root.sinks }

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(16/255, 20/255, 28/255, 0.88)   // Warm dark blue-tinted background with transparency

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        text: "Output"
                        color: "#e5e5e5"
                        font.family: "monospace"
                        font.pixelSize: 13
                        opacity: 0.6
                    }

                    // Main switch: speakers/headphones vs TV.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Speakers / headphones", profile: "output:analog-stereo+input:analog-stereo", hdmi: false },
                                { label: "HDMI (TV)",             profile: "output:hdmi-stereo+input:analog-stereo",   hdmi: true }
                            ]

                            delegate: Rectangle {
                                id: btn
                                required property var modelData
                                readonly property bool active: root.onHdmi === modelData.hdmi

                                Layout.fillWidth: true
                                implicitHeight: 48
                                radius: 6
                                color: active ? Qt.rgba(59/255, 130/255, 246/255, 0.15)
                                              : (btnHover.containsMouse ? Qt.rgba(255, 255, 255, 0.08)
                                                                        : Qt.rgba(255, 255, 255, 0.04))
                                border.width: 1
                                border.color: active ? "#3b82f6" : "#888888"

                                Text {
                                    anchors.centerIn: parent
                                    text: btn.modelData.label
                                    color: btn.active ? "#60a5fa" : "#e5e5e5"
                                    font.family: "monospace"
                                    font.pixelSize: 13
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

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool active:
                                root.current !== null && root.current.id === modelData.id

                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: 6
                            color: hover.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04)
                            border.width: 1
                            border.color: active ? "#3b82f6" : "#888888"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: row.active ? "#3b82f6" : "transparent"
                                    border.width: 1
                                    border.color: row.active ? "#3b82f6" : "#888888"
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.description || row.modelData.nickname || row.modelData.name
                                    color: "#e5e5e5"
                                    elide: Text.ElideRight
                                    font.family: "monospace"
                                    font.pixelSize: 13
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
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        implicitHeight: 8
                        radius: 4
                        color: Qt.rgba(255, 255, 255, 0.1)
                        visible: root.current !== null && root.current.audio !== null

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.current && root.current.audio ? root.current.audio.volume : 0))
                            height: parent.height
                            radius: 4
                            color: root.current && root.current.audio && root.current.audio.muted ? "#888888" : "#3b82f6"
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.topMargin: -8
                            anchors.bottomMargin: -8
                            preventStealing: true
                            function setVol(x) {
                                if (root.current && root.current.audio)
                                    root.current.audio.volume = Math.max(0, Math.min(1, x / width))
                            }
                            onPressed: mouse => setVol(mouse.x)
                            onPositionChanged: mouse => setVol(mouse.x)
                        }
                    }
                }
            }
        }
    }
}
