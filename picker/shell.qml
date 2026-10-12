// File: ~/viii-shell-2/picker/shell.qml
// The theme picker, glass style.
//
// It is NOT left running: `viii-theme --picker` (your keybind) starts it, it
// scans ~/viii-shell-2/themes, and it quits when you apply or press Esc. While
// closed it uses no memory and no CPU. Pressing the keybind again closes it.
//
// Keys:  ← → ↑ ↓ (or h j k l)  browse        1-9  jump to a theme
//        Enter  apply and close              Space  apply and stay open
//        Esc  close
// Mouse: click a card to select it, click the selected one to apply it,
//        scroll to browse, click the dark background to close.
//
// Needs Qt 6.6+ and QtQuick.Effects.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string themesDir: home + "/viii-shell-2/themes"
    readonly property string switcher: home + "/.local/bin/viii-theme"
    readonly property string mono: "JetBrainsMono Nerd Font"

    // Spring ("liquid stretch") settings. The picker is a separate shell and can't read
    // Theme.qml, so keep these equal to springStiffness / springDamping there.
    readonly property real springK: 3.2
    readonly property real springD: 0.30

    // ------------------------------------------------------------ theme list
    // Filled by `viii-theme --scan`: one JSON line per theme folder.
    property var themes: []
    property var pending: []
    property string currentName: ""
    property bool loaded: false
    property int sel: 0
    property int prev: 0

    readonly property var fallback: ({
        name: "", label: "No themes found", image: "",
        bg: "#10141c", surface: "#1c243a", line: "#2b4560",
        fg: "#e5e5e5", fgDim: "#8892b0", accent: "#3b82f6", accentHi: "#60a5fa"
    })
    readonly property var cur: themes.length > 0 ? themes[Math.min(sel, themes.length - 1)] : fallback

    // Everything in the picker is tinted with the theme you are previewing.
    property color accent: cur.accent
    property color bgc: cur.bg
    property color fg: cur.fg
    property color fgDim: cur.fgDim
    Behavior on accent { ColorAnimation { duration: 450 } }
    Behavior on bgc    { ColorAnimation { duration: 450 } }
    Behavior on fg     { ColorAnimation { duration: 450 } }
    Behavior on fgDim  { ColorAnimation { duration: 450 } }

    property string status: "Pick a theme"
    property color statusColor: Qt.rgba(1, 1, 1, 0.4)
    property string lastErr: ""
    property bool closeAfterApply: false

    // fade in on open, fade out before quitting
    property real shown: 0
    property bool closing: false
    Behavior on shown { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Component.onCompleted: shown = 1

    // -------------------------------------------------------------- actions
    function onScanLine(line) {
        var o
        try { o = JSON.parse(line) } catch (e) { return }
        if (o.current !== undefined) { currentName = o.current; return }
        if (!o.name) return
        var p = o.p || {}
        pending.push({
            name: o.name,
            label: p.label || o.name,
            image: o.bg ? "file://" + themesDir + "/" + o.name + "/" + o.bg : "",
            bg: p.bg || "#10141c",
            surface: p.surface || "#1c243a",
            line: p.line || "#2b4560",
            fg: p.fg || "#e5e5e5",
            fgDim: p.fgDim || "#8892b0",
            accent: p.accent || "#3b82f6",
            accentHi: p.accentHi || p.accent || "#60a5fa"
        })
    }

    function finishScan() {
        themes = pending
        for (var i = 0; i < themes.length; i++) {
            if (themes[i].name === currentName) { sel = i; prev = i }
        }
        loaded = true
        if (themes.length === 0) status = "No theme folders with a palette.json in " + themesDir
    }

    function go(i) {
        var n = themes.length
        if (n === 0) return
        prev = sel
        sel = ((i % n) + n) % n
    }

    function apply(closeWhenDone) {
        if (themes.length === 0 || closing || runner.running) return
        lastErr = ""
        closeAfterApply = closeWhenDone
        status = "Applying " + cur.label + "…"
        statusColor = cur.accent
        runner.command = ["bash", switcher, cur.name]
        runner.running = true
    }

    function dismiss() {
        if (closing) return
        closing = true
        shown = 0
        quitTimer.start()
    }

    Timer { id: quitTimer; interval: 260; onTriggered: Qt.quit() }

    // `qs -p ~/viii-shell-2/picker ipc call picker dismiss` closes it (the keybind toggle uses this)
    IpcHandler {
        target: "picker"
        function dismiss(): void { root.dismiss() }
    }

    Process {
        id: scanner
        command: ["bash", root.switcher, "--scan"]
        running: true
        stdout: SplitParser { onRead: (line) => root.onScanLine(line) }
        onExited: root.finishScan()
    }

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
                root.currentName = root.cur.name
                root.status = "Applied " + root.cur.label
                root.statusColor = "#7ee787"
                if (root.closeAfterApply) root.dismiss()
            }
        }
    }

    // ----------------------------------------------------------------- window
    PanelWindow {
        id: win

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "viii-picker"
        color: "transparent"

        // one scale factor for everything, so it fits small and large screens
        readonly property real u: Math.max(0.6, Math.min(1.4, Math.min(width / 1600, height / 900)))
        readonly property real tw: 150 * u        // card width in the strip
        readonly property real th: 94 * u         // card height in the strip

        // dark tinted backdrop
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.bgc.r, root.bgc.g, root.bgc.b, 0.78)
            opacity: root.shown
        }

        // click the backdrop to close, scroll to browse
        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
            onWheel: (w) => root.go(root.sel + (w.angleDelta.y > 0 ? -1 : 1))
        }

        Item {
            id: stage
            anchors.fill: parent
            focus: true
            opacity: root.shown
            scale: 0.96 + 0.04 * root.shown
            Component.onCompleted: forceActiveFocus()

            Keys.onPressed: (e) => {
                var k = e.key
                if (k === Qt.Key_Escape) root.dismiss()
                else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_H || k === Qt.Key_K) root.go(root.sel - 1)
                else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_L || k === Qt.Key_J) root.go(root.sel + 1)
                else if (k === Qt.Key_Home) root.go(0)
                else if (k === Qt.Key_End) root.go(root.themes.length - 1)
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.apply(true)
                else if (k === Qt.Key_Space) root.apply(false)
                else if (k >= Qt.Key_1 && k <= Qt.Key_9 && k - Qt.Key_1 < root.themes.length) root.go(k - Qt.Key_1)
            }

            // The glass card holding everything
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 960 * win.u
                height: col.implicitHeight + 64 * win.u
                radius: 36 * win.u
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                // Specular sheen across the top
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
                        GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                // Clicks on the card itself must not reach the "click background to close" area.
                MouseArea {
                    anchors.fill: parent
                    onWheel: (w) => root.go(root.sel + (w.angleDelta.y > 0 ? -1 : 1))
                }

                Column {
                    id: col
                    anchors.centerIn: parent
                    width: 896 * win.u
                    spacing: 16 * win.u

                    // ---- caption: THEME · 02 / 05
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.themes.length > 0
                              ? "THEME   ·   " + String(root.sel + 1).padStart(2, "0") + " / " + String(root.themes.length).padStart(2, "0")
                              : "THEME"
                        color: root.fgDim
                        font.family: root.mono
                        font.pixelSize: 12 * win.u
                        font.letterSpacing: 4
                    }

                    // ---- hero: the selected wallpaper in a big rounded card
                    Item {
                        id: hero
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 620 * win.u
                        height: 350 * win.u

                        // Stretch: on every change it squeezes in sideways (and grows a little
                        // taller), then springs back, like a blob of liquid being poked.
                        property real pop: 1
                        Behavior on pop { SpringAnimation { spring: root.springK; damping: root.springD; epsilon: 0.001 } }
                        transform: Scale {
                            origin.x: hero.width / 2
                            origin.y: hero.height / 2
                            xScale: hero.pop
                            yScale: 1 + (1 - hero.pop) * 0.5
                        }
                        Connections {
                            target: root
                            function onSelChanged() { hero.pop = 0.95; popRelease.restart() }
                        }
                        Timer { id: popRelease; interval: 70; onTriggered: hero.pop = 1 }

                        Item {
                            id: heroStack
                            anchors.fill: parent
                            visible: false

                            Rectangle { anchors.fill: parent; color: Qt.lighter(root.bgc, 1.6) }

                            // only the selected wallpaper (and the one fading out) are decoded
                            Repeater {
                                model: root.themes
                                delegate: Image {
                                    anchors.fill: parent
                                    source: (index === root.sel || index === root.prev) ? modelData.image : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 1000
                                    opacity: index === root.sel ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
                                }
                            }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: parent.height * 0.4
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                                }
                            }
                        }

                        // rounded-corner mask for the picture
                        Rectangle {
                            id: heroMask
                            anchors.fill: parent
                            radius: 28 * win.u
                            visible: false
                            layer.enabled: true
                            layer.samples: 4
                            color: "white"
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: heroStack
                            maskEnabled: true
                            maskSource: heroMask
                        }

                        // thin light edge on top of the picture
                        Rectangle {
                            anchors.fill: parent
                            radius: 28 * win.u
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.22)
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.loaded && root.themes.length === 0
                            text: "Add a folder with palette.json + bg.jpg to\n~/viii-shell-2/themes"
                            horizontalAlignment: Text.AlignHCenter
                            color: root.fg
                            font.family: root.mono
                            font.pixelSize: 16 * win.u
                        }
                    }

                    // ---- theme dots: one dot per theme in its accent color. The active dot springs open into a
                    // pill with the name; a ring marks the theme that is applied right now.
                    Item {
                        id: dots
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 896 * win.u
                        height: 48 * win.u

                        Row {
                            anchors.centerIn: parent
                            spacing: 12 * win.u

                            Repeater {
                                model: root.themes
                                delegate: Item {
                                    id: dt
                                    readonly property bool active: index === root.sel
                                    readonly property bool applied: modelData.name === root.currentName
                                    width: pill.width
                                    height: dots.height

                                    Rectangle {
                                        id: pill
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: dt.active ? lab.implicitWidth + 44 * win.u : 16 * win.u
                                        height: dt.active ? 38 * win.u : 16 * win.u
                                        radius: height / 2
                                        color: modelData.accent
                                        clip: true
                                        border.width: (dt.applied && !dt.active) ? 2 : 0
                                        border.color: root.fg
                                        Behavior on width { SpringAnimation { spring: root.springK; damping: root.springD; epsilon: 0.5 } }
                                        Behavior on height { SpringAnimation { spring: root.springK * 0.8; damping: root.springD * 0.85; epsilon: 0.5 } }

                                        Text {
                                            id: lab
                                            anchors.centerIn: parent
                                            text: modelData.label + (dt.applied ? "  ✓" : "")
                                            color: modelData.bg
                                            font.family: root.mono
                                            font.pixelSize: 15 * win.u
                                            font.weight: Font.DemiBold
                                            opacity: dt.active ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 180 } }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6 * win.u
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: dt.active ? root.apply(true) : root.go(index)
                                    }
                                }
                            }
                        }
                    }

                    // ---- palette of the selected theme
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8 * win.u
                        Repeater {
                            model: [root.cur.bg, root.cur.surface, root.cur.accent, root.cur.accentHi]
                            delegate: Rectangle {
                                width: 12 * win.u
                                height: 12 * win.u
                                radius: width / 2
                                color: modelData
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.25)
                            }
                        }
                    }

                    // ---- footer: hints and status
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "←  →  browse        ↵  apply & close        space  apply        esc  close"
                        color: root.fgDim
                        font.family: root.mono
                        font.pixelSize: 11 * win.u
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8 * win.u
                        Rectangle {
                            width: 8 * win.u
                            height: 8 * win.u
                            radius: width / 2
                            color: root.statusColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.status
                            color: root.fgDim
                            font.family: root.mono
                            font.pixelSize: 11 * win.u
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}