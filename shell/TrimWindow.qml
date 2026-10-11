import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell

// Video-first trim workspace. Created on demand by TrimPanel.qml.
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

    component ActionButton: Button {
        id: b
        property bool primary: false
        property bool quiet: false

        implicitHeight: 38
        contentItem: Row {
            spacing: 8
            anchors.centerIn: parent
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: b.text
                color: b.primary ? Theme.accentText : Theme.fg
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
        background: ChamferPanel {
            cut: 8
            fillColor: b.primary ? Theme.accent
                      : (b.down ? Theme.surfaceHi
                      : (b.hovered ? Theme.surface : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55)))
            strokeColor: b.primary ? Theme.accentHi : Theme.line
        }
        opacity: b.enabled ? 1 : 0.42
    }

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

    ChamferPanel {
        id: outer
        anchors.fill: parent
        cut: 22
        pattern: true
        patternOpacity: 0.065
        fillColor: Theme.panel
        strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            // Title/header row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                HexButton {
                    size: 34
                    glyph: "\uf03d"
                    glyphSize: 14
                    outlined: true
                    interactive: false
                    tone: Theme.accentHi
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "FRAME / TRIM"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.5
                    }
                    Text {
                        text: win.panel ? win.panel.file.split("/").pop() : "No video selected"
                        color: Theme.fgDim
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }

                ChamferPanel {
                    Layout.preferredWidth: 106
                    Layout.preferredHeight: 30
                    cut: 8
                    fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.7)
                    strokeColor: Theme.line
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        HexShape {
                            width: 8
                            height: 7
                            anchors.verticalCenter: parent.verticalCenter
                            fillColor: player.playbackState === MediaPlayer.PlayingState ? Theme.good : Theme.fgDim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: player.playbackState === MediaPlayer.PlayingState ? "PLAYING" : "READY"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                    }
                }
            }

            // Preview stage. The preview is framed rather than left floating on the window.
            ChamferPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 230
                cut: 16
                fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.58)
                strokeColor: Theme.line

                Item {
                    anchors.fill: parent
                    anchors.margins: 10

                    VideoOutput {
                        id: out
                        anchors.fill: parent
                    }

                    // Subtle edge marks make the viewing area feel like an editing viewport.
                    Item {
                        anchors.fill: parent
                        visible: player.hasVideo
                        Repeater {
                            model: [
                                { x: 0, y: 0, rot: 0 },
                                { x: 1, y: 0, rot: 90 },
                                { x: 0, y: 1, rot: -90 },
                                { x: 1, y: 1, rot: 180 }
                            ]
                            delegate: Item {
                                required property var modelData
                                width: 20
                                height: 20
                                x: modelData.x === 0 ? 0 : parent.width - width
                                y: modelData.y === 0 ? 0 : parent.height - height
                                rotation: modelData.rot
                                Rectangle {
                                    width: 14
                                    height: 2
                                    color: Theme.accent
                                }
                                Rectangle {
                                    width: 2
                                    height: 14
                                    color: Theme.accent
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !player.hasVideo
                        text: "WAITING FOR VIDEO"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.letterSpacing: 2
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        spacing: 7
                        Repeater {
                            model: ["IN  I", "OUT  O", "SEEK  ← →"]
                            delegate: ChamferPanel {
                                required property string modelData
                                width: keyText.implicitWidth + 14
                                height: 24
                                cut: 6
                                fillColor: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.78)
                                strokeColor: Theme.line
                                Text {
                                    id: keyText
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Theme.fgDim
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }

            // Timeline and selection details.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "TIMELINE"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                    }
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
                        y: seek.topPadding + seek.availableHeight / 2 - 5
                        width: seek.availableWidth
                        height: 14

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 2
                            color: Theme.surface
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: player.duration > 0 && win.panel ? parent.width * win.panel.startMs / player.duration : 0
                            width: player.duration > 0 && win.panel
                                ? Math.max(0, parent.width * (win.panel.endMs - win.panel.startMs) / player.duration) : 0
                            height: 6
                            radius: 2
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.9)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: player.duration > 0 && win.panel ? parent.width * win.panel.startMs / player.duration - width / 2 : 0
                            width: 3
                            height: 14
                            radius: 1
                            color: Theme.good
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: player.duration > 0 && win.panel ? parent.width * win.panel.endMs / player.duration - width / 2 : 0
                            width: 3
                            height: 14
                            radius: 1
                            color: Theme.bad
                        }
                    }

                    handle: HexShape {
                        x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                        y: seek.topPadding + seek.availableHeight / 2 - height / 2
                        width: 17
                        height: 15
                        fillColor: Theme.fg
                        strokeColor: Theme.accent
                        strokeWidth: 1
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "IN", color: Theme.good, value: win.panel ? win.panel.fmt(win.panel.startMs) : "00:00.000" },
                            { label: "OUT", color: Theme.bad, value: win.panel ? win.panel.fmt(win.panel.endMs) : "00:00.000" },
                            { label: "DURATION", color: Theme.accentHi, value: win.panel ? win.panel.fmt(Math.max(0, win.panel.endMs - win.panel.startMs)) : "00:00.000" }
                        ]
                        delegate: ChamferPanel {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 54
                            cut: 9
                            fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                            strokeColor: Theme.line

                            Column {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
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
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }

            // Controls: hexagons for transport, chamfered rectangles for editing actions.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                HexButton {
                    size: 38
                    glyph: "\uf04a"
                    glyphSize: 13
                    outlined: true
                    tone: Theme.fg
                    onClicked: player.position = Math.max(0, player.position - 5000)
                }
                HexButton {
                    size: 44
                    glyph: player.playbackState === MediaPlayer.PlayingState ? "\uf04c" : "\uf04b"
                    glyphSize: 15
                    filled: true
                    onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                }
                HexButton {
                    size: 38
                    glyph: "\uf04e"
                    glyphSize: 13
                    outlined: true
                    tone: Theme.fg
                    onClicked: player.position = Math.min(player.duration, player.position + 5000)
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 32
                    color: Theme.line
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                }

                ActionButton {
                    text: "SET IN  [I]"
                    onClicked: if (win.panel) win.panel.startMs = player.position
                }
                ActionButton {
                    text: "SET OUT  [O]"
                    onClicked: if (win.panel) win.panel.endMs = player.position
                }

                Item { Layout.fillWidth: true }

                CheckBox {
                    id: exactBox
                    checked: win.panel ? win.panel.exact : false
                    text: "EXACT"
                    onToggled: if (win.panel) win.panel.exact = checked
                    indicator: ChamferPanel {
                        x: exactBox.leftPadding
                        y: exactBox.height / 2 - height / 2
                        width: 17
                        height: 17
                        cut: 5
                        fillColor: exactBox.checked ? Theme.accent : Theme.surface
                        strokeColor: exactBox.checked ? Theme.accent : Theme.line
                        Text {
                            anchors.centerIn: parent
                            text: exactBox.checked ? "✓" : ""
                            color: Theme.accentText
                            font.pixelSize: 11
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

                ActionButton {
                    text: "EXPORT  ↗"
                    primary: true
                    enabled: win.panel ? (!win.panel.exporting && win.panel.endMs > win.panel.startMs) : false
                    onClicked: if (win.panel) win.panel.doExport()
                }
            }

            // Export state remains visible and does not block the editor.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                HexShape {
                    Layout.preferredWidth: 9
                    Layout.preferredHeight: 8
                    fillColor: win.panel && win.panel.exporting ? Theme.accent : Theme.fgDim
                }
                Text {
                    Layout.fillWidth: true
                    text: win.panel && win.panel.status !== "" ? win.panel.status
                          : (win.panel && win.panel.exact
                             ? "Exact mode re-encodes for frame-accurate cuts."
                             : "Fast mode copies streams; cuts may snap to keyframes.")
                    color: win.panel && win.panel.status.indexOf("failed") >= 0 ? Theme.bad : Theme.fgDim
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }
                Text {
                    text: win.panel && win.panel.exporting ? "EXPORTING…" : "MP4 / FFMPEG"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }
        }
    }
}
