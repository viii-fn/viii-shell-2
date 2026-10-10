// File: ~/viii-shell-2/picker/shell.qml
// Theme picker. A big live preview of the selected theme's wallpaper, with a
// row of capsules underneath: the selected capsule stretches to fill the row.
// Needs Qt 6.5+ (QtQuick.Effects) for the rounded preview.
// Controls: scroll / arrows / click a capsule. Applies ~0.7s after you stop,
// or instantly with Enter, the Apply button, or clicking the open capsule.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // ---- edit palette here: accent = highlight, bg = window tint ----
    readonly property var themes: [
        { name: "atmos",   label: "Atmos",   accent: "#6cb4ff", bg: "#0b1320" },
        { name: "black",   label: "Black",   accent: "#e4e4e4", bg: "#0a0a0a" },
        { name: "desert",  label: "Desert",  accent: "#e8b27a", bg: "#1b1510" },
        { name: "redcell", label: "Redcell", accent: "#ff6b70", bg: "#190a0b" },
        { name: "wood",    label: "Wood",    accent: "#d19a5c", bg: "#16100a" }
    ]

    property int sel: 0
    readonly property var current: themes[sel]

    property color accent: current.accent
    property color bgColor: current.bg
    Behavior on accent  { ColorAnimation { duration: 400 } }
    Behavior on bgColor { ColorAnimation { duration: 400 } }

    property string status: "Pick a theme"
    property color statusColor: Qt.rgba(1, 1, 1, 0.35)
    property string lastErr: ""
    property bool queued: false

    function mix(c1, c2, t) {
        return Qt.rgba(c1.r + (c2.r - c1.r) * t, c1.g + (c2.g - c1.g) * t,
                       c1.b + (c2.b - c1.b) * t, c1.a + (c2.a - c1.a) * t)
    }

    function go(i) {
        sel = ((i % 5) + 5) % 5
        applyTimer.restart()
    }

    function apply() {
        applyTimer.stop()
        if (runner.running) { queued = true; return }
        lastErr = ""
        status = "Applying " + current.label + "…"
        statusColor = current.accent
        // through bash so a missing exec bit or PATH problem can't break it
        runner.command = ["bash", home + "/.local/bin/viii-theme", current.name]
        runner.running = true
    }

    Timer { id: applyTimer; interval: 700; onTriggered: root.apply() }

    Process {
        id: runner
        stderr: StdioCollector {
            onStreamFinished: {
                var t = text.trim()
                if (t !== "") {
                    root.lastErr = t
                    root.status = "Error: " + t.split("\n")[0]
                    root.statusColor = "#ff6b70"
                }
            }
        }
        onExited: (code, st) => {
            if (code !== 0 && root.lastErr === "") {
                root.status = "Failed (exit code " + code + ")"
                root.statusColor = "#ff6b70"
            } else if (root.lastErr === "") {
                root.status = "Applied " + root.current.label
                root.statusColor = "#7ee787"
            }
            if (root.queued) { root.queued = false; root.apply() }
        }
    }

    FloatingWindow {
        title: "Theme Picker"
        implicitWidth: 760
        implicitHeight: 560
        color: Qt.rgba(root.bgColor.r, root.bgColor.g, root.bgColor.b, 0.85)

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Left || e.key === Qt.Key_Up)           root.go(root.sel - 1)
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down)   root.go(root.sel + 1)
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.apply()
            }

            MouseArea {
                anchors.fill: parent
                onWheel: (w) => root.go(root.sel + (w.angleDelta.y > 0 ? -1 : 1))
            }

            // ================= hero preview =================
            Item {
                id: hero
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
                height: 330

                // source of the rounded preview: all wallpapers stacked, cross-faded
                Item {
                    id: stack
                    anchors.fill: parent
                    visible: false

                    Rectangle { anchors.fill: parent; color: Qt.lighter(root.bgColor, 1.8) }

                    Repeater {
                        model: root.themes
                        delegate: Image {
                            anchors.fill: parent
                            source: "file://" + root.home + "/viii-shell-2/" + modelData.name + "/bg.jpg"
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 1100
                            opacity: index === root.sel ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
                        }
                    }

                    // bottom scrim so the title stays readable
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: parent.height * 0.62
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.78) }
                        }
                    }
                }

                Rectangle { id: heroMask; anchors.fill: parent; radius: 26; visible: false; layer.enabled: true }

                MultiEffect {
                    anchors.fill: parent
                    source: stack
                    maskEnabled: true
                    maskSource: heroMask
                }

                // thin accent outline that follows the theme
                Rectangle {
                    anchors.fill: parent
                    radius: 26
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                }

                // counter chip, top-left
                Rectangle {
                    anchors { left: parent.left; top: parent.top; margins: 18 }
                    height: 30; width: chipRow.width + 24; radius: 15
                    color: Qt.rgba(0, 0, 0, 0.42)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: root.accent; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "0" + (root.sel + 1) + " / 05"
                            color: "white"
                            font.pixelSize: 12
                            font.letterSpacing: 1.5
                            font.weight: Font.Medium
                        }
                    }
                }

                // theme name, bottom-left
                Column {
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 26; bottomMargin: 22 }
                    spacing: 0
                    Text {
                        text: "THEME"
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 12
                        font.letterSpacing: 4
                        font.weight: Font.Medium
                    }
                    Text {
                        text: root.current.label
                        color: "white"
                        font.pixelSize: 54
                        font.weight: Font.DemiBold
                    }
                }
            }

            // ================= stretching capsules =================
            Item {
                id: bar
                anchors { left: parent.left; right: parent.right; top: hero.bottom; leftMargin: 28; rightMargin: 28; topMargin: 22 }
                height: 60

                readonly property real small: 64
                readonly property real gap: 10
                readonly property real full: width - 4 * small - 4 * gap

                Row {
                    spacing: bar.gap
                    Repeater {
                        model: root.themes
                        delegate: Rectangle {
                            id: pill
                            readonly property bool active: index === root.sel
                            readonly property color accentC: modelData.accent
                            readonly property color bgC: modelData.bg
                            // 0 = collapsed, 1 = fully open (follows the animated width)
                            readonly property real t: Math.max(0, Math.min(1, (width - bar.small) / Math.max(1, bar.full - bar.small)))

                            width: active ? bar.full : bar.small
                            height: 60
                            radius: 30
                            color: root.mix(Qt.rgba(1, 1, 1, 0.07), accentC, t)
                            Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: 18; height: 18; radius: 9
                                color: root.mix(pill.accentC, pill.bgC, pill.t)
                                anchors.verticalCenter: parent.verticalCenter
                                x: 24 + (1 - pill.t) * ((pill.width - 18) / 2 - 24)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 56
                                text: modelData.label
                                color: pill.bgC
                                opacity: pill.t
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                                text: "Apply  ↵"
                                color: pill.bgC
                                opacity: pill.t * 0.65
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pill.active ? root.apply() : root.go(index)
                            }
                        }
                    }
                }
            }

            // ================= footer =================
            Row {
                anchors { left: parent.left; leftMargin: 30; bottom: parent.bottom; bottomMargin: 30 }
                spacing: 10
                Rectangle {
                    width: 9; height: 9; radius: 4.5
                    color: root.statusColor
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    width: 480
                    text: root.status
                    elide: Text.ElideRight
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                anchors { right: parent.right; rightMargin: 28; bottom: parent.bottom; bottomMargin: 20 }
                width: 124; height: 44; radius: 22
                color: root.accent
                Text {
                    anchors.centerIn: parent
                    text: "Apply"
                    color: root.bgColor
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.apply() }
            }
        }
    }
}
