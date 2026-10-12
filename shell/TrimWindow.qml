// File: ~/viii-shell-2/shell/TrimWindow.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell

// Video-first trim workspace, glass style. Created on demand by TrimPanel.qml.
// The selection logic and ffmpeg export behavior remain owned by TrimPanel.
FloatingWindow {
    id: win

    property var panel
    visible: true
    title: "Trim"
    implicitWidth: 900
    implicitHeight: 650
    color: "transparent"

    onVisibleChanged: if (!visible && panel) panel.closeWin()

    MediaPlayer {
        id: player
        source: win.panel ? "file://" + win.panel.file : ""
        videoOutput: out
        audioOutput: AudioOutput {}
        onDurationChanged: if (win.panel && win.panel.endMs === 0) win.panel.endMs = duration
        Component.onCompleted: play()
    }

    Shortcut { sequence: "Escape"; onActivated: if (win.panel) win.panel.closeWin() }
    Shortcut { sequence: "Space"; onActivated: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
    Shortcut { sequence: "I"; onActivated: if (win.panel) win.panel.startMs = player.position }
    Shortcut { sequence: "O"; onActivated: if (win.panel) win.panel.endMs = player.position }
    Shortcut { sequence: "Left"; onActivated: player.position = Math.max(0, player.position - 1000) }
    Shortcut { sequence: "Right"; onActivated: player.position = Math.min(player.duration, player.position + 1000) }

    // Glass body (no radius or border of its own: labwc rounds and outlines the window)
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.panel, 0.82)

        // Specular sheen across the top
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            // ── Header: icon, title + file name, play state ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "\uf03d"
                    color: Theme.accentHi
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Trim"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: win.panel ? win.panel.file.split("/").pop() : "No video selected"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }

                Glass {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 30
                    radius: 15
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: player.playbackState === MediaPlayer.PlayingState ? Theme.good : Theme.fgDim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: player.playbackState === MediaPlayer.PlayingState ? "Playing" : "Ready"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // ── Preview stage ──
            Glass {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 230
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.30)

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    VideoOutput {
                        id: out
                        anchors.fill: parent
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !player.hasVideo
                        text: "Waiting for video…"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }
            }

            // ── Timeline ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Text {
                        text: win.panel ? win.panel.fmt(player.position) + " / " + win.panel.fmt(player.duration) : "00:00.000"
                        color: Theme.accentHi
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                }

                Slider {
                    id: seek
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(1, player.duration)
                    value: player.position
                    onMoved: player.position = value

                    background: Item {
                        x: seek.leftPadding
                        y: seek.topPadding + seek.availableHeight / 2 - 7
                        width: seek.availableWidth
                        height: 14

                        // track
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.12)
                        }
                        // selected range (between IN and OUT)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: player.duration > 0 && win.panel ? parent.width * win.panel.startMs / player.duration : 0
                            width: player.duration > 0 && win.panel
                                ? Math.max(0, parent.width * (win.panel.endMs - win.panel.startMs) / player.duration) : 0
                            height: 6
                            radius: 3
                            color: Qt.alpha(Theme.accent, 0.9)
                        }
                        // IN marker
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: player.duration > 0 && win.panel ? parent.width * win.panel.startMs / player.duration - width / 2 : 0
                            width: 3
                            height: 14
                            radius: 1.5
                            color: Theme.good
                        }
                        // OUT marker
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: player.duration > 0 && win.panel ? parent.width * win.panel.endMs / player.duration - width / 2 : 0
                            width: 3
                            height: 14
                            radius: 1.5
                            color: Theme.bad
                        }
                    }

                    handle: Rectangle {
                        x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                        y: seek.topPadding + seek.availableHeight / 2 - height / 2
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.fg
                        border.width: 2
                        border.color: Theme.accent
                    }
                }

                // IN / OUT / DURATION
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "IN", color: Theme.good, value: win.panel ? win.panel.fmt(win.panel.startMs) : "00:00.000" },
                            { label: "OUT", color: Theme.bad, value: win.panel ? win.panel.fmt(win.panel.endMs) : "00:00.000" },
                            { label: "DURATION", color: Theme.accentHi, value: win.panel ? win.panel.fmt(Math.max(0, win.panel.endMs - win.panel.startMs)) : "00:00.000" }
                        ]
                        delegate: Glass {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 54
                            radius: 16

                            Column {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                spacing: 4
                                Text {
                                    text: modelData.label
                                    color: modelData.color
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }
                                Text {
                                    text: modelData.value
                                    color: Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }

            // ── Controls: transport, set in/out, exact, export ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                IconBtn {
                    width: 38; height: 38; radius: 19
                    glyph: "\uf04a"; glyphSize: 13
                    tone: Theme.fg
                    onClicked: player.position = Math.max(0, player.position - 5000)
                }

                // play / pause: round accent button
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 22
                    color: Theme.accent
                    scale: playHit.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    Text {
                        anchors.centerIn: parent
                        text: player.playbackState === MediaPlayer.PlayingState ? "\uf04c" : "\uf04b"
                        color: Theme.accentText
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15
                    }
                    MouseArea {
                        id: playHit
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                    }
                }

                IconBtn {
                    width: 38; height: 38; radius: 19
                    glyph: "\uf04e"; glyphSize: 13
                    tone: Theme.fg
                    onClicked: player.position = Math.min(player.duration, player.position + 5000)
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 28
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    color: Qt.rgba(1, 1, 1, 0.14)
                }

                PillBtn {
                    text: "SET IN  [I]"
                    onClicked: if (win.panel) win.panel.startMs = player.position
                }
                PillBtn {
                    text: "SET OUT  [O]"
                    onClicked: if (win.panel) win.panel.endMs = player.position
                }

                Item { Layout.fillWidth: true }

                CheckBox {
                    id: exactBox
                    checked: win.panel ? win.panel.exact : false
                    text: "EXACT"
                    onToggled: if (win.panel) win.panel.exact = checked
                    indicator: Rectangle {
                        x: exactBox.leftPadding
                        y: exactBox.height / 2 - height / 2
                        width: 20
                        height: 20
                        radius: 6
                        color: exactBox.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        border.color: exactBox.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
                        Text {
                            anchors.centerIn: parent
                            text: exactBox.checked ? "✓" : ""
                            color: Theme.accentText
                            font.pixelSize: 12
                        }
                    }
                    contentItem: Text {
                        text: exactBox.text
                        color: Theme.fgDim
                        leftPadding: exactBox.indicator.width + 8
                        verticalAlignment: Text.AlignVCenter
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                }

                PillBtn {
                    text: "EXPORT  ↗"
                    primary: true
                    enabled: win.panel ? (!win.panel.exporting && win.panel.endMs > win.panel.startMs) : false
                    onClicked: if (win.panel) win.panel.doExport()
                }
            }

            // ── Export state (visible, never blocks the editor) ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: win.panel && win.panel.exporting ? Theme.accent : Theme.fgDim
                }
                Text {
                    Layout.fillWidth: true
                    text: win.panel && win.panel.status !== "" ? win.panel.status
                          : (win.panel && win.panel.exact
                             ? "Exact mode re-encodes for frame-accurate cuts."
                             : "Fast mode copies streams; cuts may snap to keyframes.")
                    color: win.panel && win.panel.status.indexOf("failed") >= 0 ? Theme.bad : Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }
                Text {
                    text: win.panel && win.panel.exporting ? "Exporting…" : "MP4 / FFMPEG"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
            }
        }
    }
}