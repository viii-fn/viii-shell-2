// File: ~/viii-shell-2/picker/shell.qml
// The theme picker, drawn as a honeycomb.
//
// It is NOT left running: `viii-theme --picker` (your keybind) starts it, it
// scans ~/viii-shell-2/themes, and it quits when you apply or press Esc. While
// closed it uses no memory and no CPU. Pressing the keybind again closes it.
//
// Keys:  ← → ↑ ↓ (or h j k l)  browse        1-9  jump to a theme
//        Enter  apply and close              Space  apply and stay open
//        Esc  close
// Mouse: click a hexagon to select it, click the selected one to apply it,
//        scroll to browse, click the dark background to close.
//
// Needs Qt 6.6+ (Shape.CurveRenderer) and QtQuick.Effects.

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
        readonly property real tw: 128 * u        // tile width
        readonly property real th: tw * 0.866     // tile height (regular hexagon)

        // dark tinted backdrop
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.bgc.r, root.bgc.g, root.bgc.b, 0.82)
            opacity: root.shown
        }

        // faint honeycomb pattern, painted ONCE (no per-frame cost)
        Canvas {
            anchors.fill: parent
            opacity: root.shown * 0.9
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (width < 10 || height < 10) return
                var s = 54, hh = s * Math.sqrt(3) / 2
                var cx = width / 2, cy = height / 2
                var maxd = Math.sqrt(cx * cx + cy * cy)
                ctx.lineWidth = 1
                for (var col = -1; col * 1.5 * s < width + s; col++) {
                    var x = col * 1.5 * s
                    var yoff = (Math.abs(col) % 2 === 1) ? hh : 0
                    for (var y = yoff - 2 * hh; y < height + 2 * hh; y += 2 * hh) {
                        var d = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / maxd
                        ctx.strokeStyle = "rgba(255,255,255," + (0.085 * (1 - d) + 0.012).toFixed(3) + ")"
                        ctx.beginPath()
                        for (var k = 0; k < 6; k++) {
                            var a = Math.PI / 3 * k
                            var px = x + s * Math.cos(a), py = y + s * Math.sin(a)
                            if (k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                        }
                        ctx.closePath()
                        ctx.stroke()
                    }
                }
            }
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

            Column {
                anchors.centerIn: parent
                width: 900 * win.u
                spacing: 16 * win.u

                // ---- caption: THEME · 02 / 05
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.themes.length > 0
                          ? "THEME   ·   " + String(root.sel + 1).padStart(2, "0") + " / " + String(root.themes.length).padStart(2, "0")
                          : "THEME"
                    color: root.fgDim
                    font.pixelSize: 13 * win.u
                    font.letterSpacing: 5
                    font.weight: Font.Medium
                }

                // ---- hero: the selected wallpaper inside a big hexagon
                Item {
                    id: hero
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 640 * win.u
                    height: 380 * win.u

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

                    HexShape {
                        id: heroMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        layer.samples: 4
                        fillColor: "white"
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: heroStack
                        maskEnabled: true
                        maskSource: heroMask
                    }

                    // double outline: a bold one on the edge, a thin one just inside
                    HexShape {
                        anchors.fill: parent
                        strokeColor: root.accent
                        strokeWidth: 2.5
                    }
                    HexShape {
                        anchors.fill: parent
                        anchors.margins: 12 * win.u
                        strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                        strokeWidth: 1
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.loaded && root.themes.length === 0
                        text: "Add a folder with palette.json + bg.jpg to\n~/viii-shell-2/themes"
                        horizontalAlignment: Text.AlignHCenter
                        color: root.fg
                        font.pixelSize: 18 * win.u
                    }
                }

                // ---- name + palette swatches (little hexagons)
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8 * win.u

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.cur.label
                        color: root.fg
                        font.family: "serif"
                        font.pixelSize: 46 * win.u
                        font.letterSpacing: 4
                        font.weight: Font.Medium
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6 * win.u
                        Repeater {
                            model: [root.cur.bg, root.cur.surface, root.cur.accent, root.cur.accentHi]
                            delegate: HexShape {
                                width: 24 * win.u
                                height: 20.8 * win.u
                                fillColor: modelData
                                strokeColor: Qt.rgba(1, 1, 1, 0.25)
                                strokeWidth: 1
                            }
                        }
                    }
                }

                // ---- honeycomb strip: every theme folder as a hexagon, zig-zagged
                ListView {
                    id: strip
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 900 * win.u
                    height: win.th * 1.5 + 22 * win.u
                    orientation: ListView.Horizontal
                    model: root.themes
                    currentIndex: root.sel
                    interactive: false
                    clip: true
                    spacing: -win.tw * 0.25 + 8 * win.u
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: width / 2 - win.tw / 2
                    preferredHighlightEnd: width / 2 + win.tw / 2
                    highlightMoveDuration: 380

                    delegate: Item {
                        id: tile
                        readonly property bool active: index === root.sel
                        width: win.tw
                        height: strip.height
                        z: active ? 10 : 0

                        Item {
                            id: body
                            width: win.tw
                            height: win.th
                            y: 11 * win.u + (index % 2) * win.th / 2
                            scale: tile.active ? 1.14 : 1
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                            Image {
                                id: thumb
                                anchors.fill: parent
                                visible: false
                                source: modelData.image
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 320
                            }

                            HexShape {
                                id: tileMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                layer.samples: 4
                                fillColor: "white"
                            }

                            // flat colour behind the picture while it loads
                            HexShape {
                                anchors.fill: parent
                                fillColor: modelData.bg
                            }

                            MultiEffect {
                                anchors.fill: parent
                                source: thumb
                                maskEnabled: true
                                maskSource: tileMask
                                opacity: tile.active ? 1 : 0.55
                                Behavior on opacity { NumberAnimation { duration: 260 } }
                            }

                            HexShape {
                                anchors.fill: parent
                                strokeColor: tile.active ? modelData.accent : Qt.rgba(1, 1, 1, 0.2)
                                strokeWidth: tile.active ? 3 : 1.5
                            }

                            // small accent hexagon marks the theme that is applied right now
                            HexShape {
                                visible: modelData.name === root.currentName
                                width: 16 * win.u
                                height: 13.9 * win.u
                                x: parent.width / 2 - width / 2
                                y: 8 * win.u
                                fillColor: modelData.accent
                                strokeColor: modelData.bg
                                strokeWidth: 1.5
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: tile.active ? root.apply(true) : root.go(index)
                            }
                        }
                    }
                }

                // ---- footer: hints and status
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "←  →  browse        ↵  apply & close        space  apply        esc  close"
                    color: root.fgDim
                    font.pixelSize: 12 * win.u
                    font.letterSpacing: 1
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8 * win.u
                    HexShape {
                        width: 12 * win.u
                        height: 10.4 * win.u
                        fillColor: root.statusColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.status
                        color: root.fgDim
                        font.pixelSize: 12 * win.u
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
