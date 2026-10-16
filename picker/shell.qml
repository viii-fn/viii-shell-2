// File: ~/viii-shell-2/picker/shell.qml
// The theme picker, dial style (same shape language as the launcher).
//
// It is NOT left running: `viii-theme --picker` (your keybind) starts it, it
// scans ~/viii-shell-2/themes, and it quits when you apply or press Esc. While
// closed it uses no memory and no CPU. Pressing the keybind again closes it.
//
// Keys:  ← → ↑ ↓ (or h j k l)  browse        1-9  jump to a theme
//        Enter  apply and close              Space  apply and stay open
//        Esc  close
// Mouse: click a tile to select it, click the selected tile or the center to apply,
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

    // Unwrapped dial position: grows past the list length so the ring always turns the short way.
    property int dialIdx: 0
    property real pos: dialIdx
    Behavior on pos { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

    readonly property var fallback: ({
        name: "", label: "No themes found", image: "",
        bg: "#10141c", surface: "#1c243a", line: "#2b4560",
        fg: "#e5e5e5", fgDim: "#8892b0", accent: "#3b82f6", accentHi: "#60a5fa"
    })
    readonly property var cur: themes.length > 0 ? themes[Math.min(sel, themes.length - 1)] : fallback

    // Everything in the picker is tinted with the theme you are previewing.
    property color accent: cur.accent
    property color accentHi: cur.accentHi
    property color bgc: cur.bg
    property color fg: cur.fg
    property color fgDim: cur.fgDim
    Behavior on accent   { ColorAnimation { duration: 450 } }
    Behavior on accentHi { ColorAnimation { duration: 450 } }
    Behavior on bgc      { ColorAnimation { duration: 450 } }
    Behavior on fg       { ColorAnimation { duration: 450 } }
    Behavior on fgDim    { ColorAnimation { duration: 450 } }

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
        dialIdx = sel
        loaded = true
        if (themes.length === 0) status = "No theme folders with a palette.json in " + themesDir
    }

    function go(i) {
        var n = themes.length
        if (n === 0) return
        var target = ((i % n) + n) % n
        // shortest way round the ring
        var delta = target - sel
        if (delta > n / 2) delta -= n
        if (delta < -n / 2) delta += n
        prev = sel
        sel = target
        dialIdx += delta
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

            // ── The glass panel (launcher shape: header, dial, footer) ──
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 560 * win.u
                height: col.implicitHeight + 44 * win.u
                radius: 36 * win.u
                color: Qt.alpha(Qt.darker(root.bgc, 1.3), 0.82)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                // Specular sheen across the top
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
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
                    width: 516 * win.u
                    spacing: 8 * win.u

                    // ---- header: title left, count right
                    Item {
                        width: parent.width
                        height: 24 * win.u

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Theme"
                            color: root.fg
                            font.family: root.mono
                            font.pixelSize: 16 * win.u
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.themes.length + " themes"
                            color: root.fgDim
                            font.family: root.mono
                            font.pixelSize: 10 * win.u
                        }
                    }

                    // ── The dial ──
                    Item {
                        id: dial
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 480 * win.u
                        height: 480 * win.u

                        readonly property real rad: 176 * win.u
                        readonly property int n: root.themes.length
                        readonly property real step: n > 0 ? 360 / n : 0

                        // Rotating tick ring (4 ticks per detent group)
                        Repeater {
                            model: 48
                            Item {
                                required property int index
                                anchors.centerIn: parent
                                width: 1
                                height: 1
                                rotation: index * 7.5 - root.pos * dial.step
                                Rectangle {
                                    readonly property real h: (index % 4 === 0 ? 10 : 5) * win.u
                                    x: -1
                                    y: -(dial.rad + 36 * win.u + h)
                                    width: 2
                                    height: h
                                    radius: 1
                                    color: index % 4 === 0 ? root.fgDim : Qt.rgba(1, 1, 1, 0.14)
                                }
                            }
                        }

                        // Fixed pointer at the top: a small accent pill
                        Rectangle {
                            x: dial.width / 2 - 8 * win.u
                            y: 8 * win.u
                            width: 16 * win.u
                            height: 5 * win.u
                            radius: height / 2
                            color: root.accent
                        }

                        // Track the themes ride on
                        Rectangle {
                            anchors.centerIn: parent
                            width: dial.rad * 2
                            height: dial.rad * 2
                            radius: dial.rad
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.14)
                        }

                        // Theme tiles on the ring
                        Repeater {
                            model: root.themes
                            delegate: Item {
                                id: slot
                                required property int index
                                required property var modelData

                                readonly property int n: dial.n
                                // distance from the top, wrapped so it is always the short way round
                                readonly property real off: {
                                    var d = index - root.pos
                                    return n > 0 ? d - n * Math.round(d / n) : d
                                }
                                readonly property bool isSel: Math.abs(off) < 0.5
                                readonly property bool applied: modelData.name === root.currentName
                                readonly property real a: (-90 + off * dial.step) * Math.PI / 180

                                width: 56 * win.u
                                height: 56 * win.u
                                x: dial.width / 2 + dial.rad * Math.cos(a) - width / 2
                                y: dial.height / 2 + dial.rad * Math.sin(a) - height / 2
                                scale: 1 + 0.45 * Math.max(0, 1 - Math.abs(off))
                                z: isSel ? 2 : 1

                                // glass tile (rounded square, like an app icon)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 18 * win.u
                                    color: slot.isSel
                                        ? Qt.alpha(slot.modelData.accent, 0.30)
                                        : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: slot.isSel
                                        ? Qt.alpha(slot.modelData.accent, 0.60)
                                        : Qt.rgba(1, 1, 1, 0.10)
                                }
                                // the theme's accent swatch
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 26 * win.u
                                    height: 26 * win.u
                                    radius: width / 2
                                    color: slot.modelData.accent
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.30)
                                }
                                // applied marker: small check dot in the corner
                                Rectangle {
                                    visible: slot.applied
                                    x: parent.width - width * 0.7
                                    y: -height * 0.3
                                    width: 16 * win.u
                                    height: 16 * win.u
                                    radius: width / 2
                                    color: "#7ee787"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: "#10141c"
                                        font.family: root.mono
                                        font.pixelSize: 10 * win.u
                                        font.weight: Font.Bold
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: slot.isSel ? root.apply(true) : root.go(slot.index)
                                }
                            }
                        }

                        // ── Center core: the selected wallpaper as a disc ──
                        Item {
                            id: hero
                            anchors.centerIn: parent
                            width: 250 * win.u
                            height: 250 * win.u

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

                            // soft accent glow ring behind the disc
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + 10 * win.u
                                height: parent.height + 10 * win.u
                                radius: width / 2
                                color: "transparent"
                                border.width: 2 * win.u
                                border.color: Qt.alpha(root.accent, 0.35)
                            }

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
                                        sourceSize.width: 600
                                        sourceSize.height: 600
                                        opacity: index === root.sel ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
                                    }
                                }

                                // darken the bottom so it blends into the disc edge
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: parent.height * 0.4
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                                    }
                                }
                            }

                            // circular mask for the picture
                            Rectangle {
                                id: heroMask
                                anchors.fill: parent
                                radius: width / 2
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

                            // soft highlight across the top of the disc
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: width / 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.14) }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                                }
                            }

                            // glass edge
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: 1.5
                                border.color: Qt.alpha(root.accent, 0.55)
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.loaded && root.themes.length === 0
                                text: "Add a folder with\npalette.json + bg.jpg to\n~/viii-shell-2/themes"
                                horizontalAlignment: Text.AlignHCenter
                                color: root.fg
                                font.family: root.mono
                                font.pixelSize: 12 * win.u
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.apply(true)
                            }
                        }
                    }

                    // ---- selected theme: name + index
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 400 * win.u
                        horizontalAlignment: Text.AlignHCenter
                        text: root.cur.label + (root.cur.name !== "" && root.cur.name === root.currentName ? "  ✓" : "")
                        color: root.fg
                        font.family: root.mono
                        font.pixelSize: 15 * win.u
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.themes.length > 0 ? (root.sel + 1) + " / " + root.themes.length : ""
                        color: root.accent
                        font.family: root.mono
                        font.pixelSize: 9 * win.u
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

                    // ---- footer pill: hints (same pill shape as the launcher search bar)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: 42 * win.u
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: "← → browse  ·  ↵ apply & close  ·  space apply  ·  esc close"
                            color: root.fgDim
                            font.family: root.mono
                            font.pixelSize: 11 * win.u
                        }
                    }

                    // ---- status
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
