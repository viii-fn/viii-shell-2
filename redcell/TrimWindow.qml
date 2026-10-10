import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell

// The actual trimmer window. Created by TrimPanel.qml on open and
// destroyed on close, so the player and decoders only exist while it's open.
FloatingWindow {
    id: win

    property var panel   // the TrimPanel scope, passed in at creation

    visible: true
    title: "Trim"
    implicitWidth: 760
    implicitHeight: 540
    color: "#d9121212"   // 85% opacity, same as the other panels

    // Closing with the titlebar X frees everything
    onVisibleChanged: if (!visible && panel) panel.closeWin()

    // Styled button (radius 10, #888 border)
    component TButton: Button {
        id: b
        contentItem: Text {
            text: b.text
            color: "#e5e5e5"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 10
            color: b.down ? "#3a3a3a" : "#262626"
            border.color: "#888888"
            border.width: 1
            opacity: b.enabled ? 1 : 0.4
        }
    }

    MediaPlayer {
        id: player
        source: "file://" + win.panel.file
        videoOutput: out
        audioOutput: AudioOutput {}
        onDurationChanged: if (win.panel.endMs === 0) win.panel.endMs = duration
        Component.onCompleted: play()
    }

    Shortcut { sequence: "Space"; onActivated: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
    Shortcut { sequence: "I"; onActivated: win.panel.startMs = player.position }
    Shortcut { sequence: "O"; onActivated: win.panel.endMs = player.position }
    Shortcut { sequence: "Left"; onActivated: player.position = Math.max(0, player.position - 1000) }
    Shortcut { sequence: "Right"; onActivated: player.position = Math.min(player.duration, player.position + 1000) }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        VideoOutput {
            id: out
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // Seek slider; the green bar shows the selected start..end range
        Slider {
            id: seek
            Layout.fillWidth: true
            from: 0
            to: Math.max(1, player.duration)
            value: player.position
            onMoved: player.position = value

            background: Rectangle {
                x: seek.leftPadding
                y: seek.topPadding + seek.availableHeight / 2 - height / 2
                width: seek.availableWidth
                height: 8
                radius: 4
                color: "#333333"

                Rectangle {
                    height: parent.height
                    radius: 4
                    color: "#98fb98"
                    x: player.duration > 0 ? parent.width * win.panel.startMs / player.duration : 0
                    width: player.duration > 0 ? parent.width * (win.panel.endMs - win.panel.startMs) / player.duration : 0
                }
            }
            handle: Rectangle {
                x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                y: seek.topPadding + seek.availableHeight / 2 - height / 2
                width: 14
                height: 14
                radius: 7
                color: "#e5e5e5"
            }
        }

        Text {
            color: "#e5e5e5"
            text: win.panel.fmt(player.position) + " / " + win.panel.fmt(player.duration)
                  + "     start " + win.panel.fmt(win.panel.startMs)
                  + "   end " + win.panel.fmt(win.panel.endMs)
                  + "   length " + win.panel.fmt(Math.max(0, win.panel.endMs - win.panel.startMs))
        }

        RowLayout {
            spacing: 8

            TButton {
                text: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            }
            TButton { text: "Set start (I)"; onClicked: win.panel.startMs = player.position }
            TButton { text: "Set end (O)"; onClicked: win.panel.endMs = player.position }

            CheckBox {
                id: exactBox
                text: "Exact (re-encode)"
                onToggled: win.panel.exact = checked
                contentItem: Text {
                    text: exactBox.text
                    color: "#e5e5e5"
                    leftPadding: exactBox.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { Layout.fillWidth: true }

            TButton { text: "Export"; enabled: !win.panel.exporting; onClicked: win.panel.doExport() }
        }

        Text {
            color: "#98fb98"
            text: win.panel.status
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }
    }
}
