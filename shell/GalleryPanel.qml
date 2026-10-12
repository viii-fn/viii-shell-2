// File: ~/viii-shell-2/shell/GalleryPanel.qml
//   qs ipc call gallery toggle
//   qs ipc call gallery open /path/to/folder
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 600

    property string dir: Quickshell.env("HOME") + "/Pictures"
    property var files: []
    property int idx: 0
    readonly property var cur: files.length > 0 ? files[Math.max(0, Math.min(idx, files.length - 1))] : null

    onShownChanged: {
        if (shown) { unload.stop(); alive = true; scan.running = true }
        else unload.restart()
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }

    IpcHandler {
        target: "gallery"
        function toggle(): void { root.shown = !root.shown }
        function show(): void { root.shown = true }
        function hide(): void { root.shown = false }
        function open(path: string): void {
            root.dir = path
            root.shown = true
            root.reload()
        }
    }

    function reload() { root.idx = 0; scan.running = true }
    function step(d) {
        if (files.length === 0) return
        idx = ((idx + d) % files.length + files.length) % files.length
    }
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function url(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }
    function base(p) { return p.split("/").pop() }
    function folderName() {
        const p = dir.split("/").filter(x => x !== "")
        return p.length > 0 ? p[p.length - 1] : "/"
    }
    // Big number, small unit
    function sizeHtml(b, ns, us) {
        const num = v => '<span style="font-size:' + ns + 'px; font-weight:600; color:' + hex(Theme.accentHi) + ';">' + v + '</span>'
        const unit = v => '<span style="font-size:' + us + 'px; color:' + hex(Theme.fgDim) + ';">' + v + '</span>'
        if (b >= 1048576) return num((b / 1048576).toFixed(1)) + unit("&nbsp;MB")
        return num(Math.max(1, Math.round(b / 1024))) + unit("&nbsp;KB")
    }
    function ago(t) {
        const s = Math.max(0, Date.now() / 1000 - t)
        if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m ago"
        if (s < 86400) return Math.floor(s / 3600) + "h ago"
        if (s < 86400 * 30) return Math.floor(s / 86400) + "d ago"
        return new Date(t * 1000).toISOString().slice(0, 10)
    }

    Process {
        id: scan
        command: ["find", root.dir, "-maxdepth", "2", "-type", "f",
                  "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                  "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", "-o", "-iname", "*.bmp", ")",
                  "-printf", "%T@\t%s\t%p\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const p = line.split("\t")
                    if (p.length < 3) continue
                    out.push({ t: parseFloat(p[0]), size: parseInt(p[1]), path: p.slice(2).join("\t") })
                }
                out.sort((a, b) => b.t - a.t)
                root.files = out
                root.idx = 0
            }
        }
    }

    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Gallery"
            implicitWidth: 720
            implicitHeight: 700
            color: "transparent"
            onVisibleChanged: if (!visible) root.shown = false

            ChamferPanel {
                anchors.fill: parent
                cut: 22
                pattern: true
                patternOpacity: 0.05
                fillColor: Theme.panel
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                focus: true
                Keys.onEscapePressed: root.shown = false
                Keys.onLeftPressed: root.step(-1)
                Keys.onRightPressed: root.step(1)
                Keys.onReturnPressed: if (root.cur) Quickshell.execDetached(["swayimg", root.cur.path])

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    // ── Header ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        HexShape {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16 / 1.1547
                            fillColor: Theme.accent
                        }
                        Text {
                            text: "Gallery"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "/ " + root.folderName()
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        HexButton {
                            Layout.preferredWidth: 28 * 1.1547
                            Layout.preferredHeight: 28
                            size: 28; glyphSize: 12
                            outlined: true
                            glyph: "\uf021"
                            onClicked: root.reload()
                        }
                    }

                    // ── Preview ──
                    ChamferPanel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        cut: 16
                        fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.55)
                        strokeColor: Theme.line

                        WheelHandler {
                            onWheel: (e) => root.step(e.angleDelta.y > 0 ? -1 : 1)
                        }

                        Image {
                            id: big
                            anchors.fill: parent
                            anchors.margins: 14
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            sourceSize.width: 1400
                            sourceSize.height: 1000
                            source: root.cur ? root.url(root.cur.path) : ""
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.files.length === 0
                            text: "No images in " + root.dir
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }

                        // Prev / next
                        HexButton {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34 * 1.1547; height: 34
                            size: 34; glyphSize: 13
                            outlined: true
                            visible: root.files.length > 1
                            glyph: "\uf053"
                            onClicked: root.step(-1)
                        }
                        HexButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34 * 1.1547; height: 34
                            size: 34; glyphSize: 13
                            outlined: true
                            visible: root.files.length > 1
                            glyph: "\uf054"
                            onClicked: root.step(1)
                        }
                    }

                    // ── Info + actions ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: root.cur ? root.base(root.cur.path) : "—"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideMiddle
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.cur
                                      ? root.ago(root.cur.t) + "  ·  " + (root.idx + 1) + " / " + root.files.length
                                      : ""
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            textFormat: Text.RichText
                            font.family: "JetBrainsMono Nerd Font"
                            text: root.cur ? root.sizeHtml(root.cur.size, 30, 12) : ""
                        }

                        Rectangle {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 36
                            radius: 18
                            visible: root.cur !== null
                            color: cpHit.containsMouse ? Theme.surfaceHi : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: Theme.line
                            Text {
                                anchors.centerIn: parent
                                text: "\uf0c5"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: cpHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", root.cur.path])
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: openText.implicitWidth + 32
                            Layout.preferredHeight: 36
                            radius: 18
                            visible: root.cur !== null
                            color: openHit.containsMouse ? Theme.accentHi : Theme.accent
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: openText
                                anchors.centerIn: parent
                                text: "Open in swayimg"
                                color: Theme.accentText
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: openHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["swayimg", root.cur.path])
                            }
                        }
                    }

                    // ── Thumbnail strip ──
                    ListView {
                        id: strip
                        Layout.fillWidth: true
                        Layout.preferredHeight: 92
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: 8
                        model: root.files
                        currentIndex: root.idx
                        highlightMoveDuration: 220
                        preferredHighlightBegin: width / 2 - 46
                        preferredHighlightEnd: width / 2 + 46
                        highlightRangeMode: ListView.ApplyRange
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: th
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === root.idx
                            width: 92
                            height: 92

                            ChamferPanel {
                                anchors.fill: parent
                                cut: 10
                                fillColor: th.sel
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                    : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                                strokeColor: th.sel ? Theme.accent : Theme.line
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 6
                                radius: 6
                                color: "transparent"
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 160
                                    sourceSize.height: 160
                                    source: root.url(th.modelData.path)
                                    opacity: th.sel || tHit.containsMouse ? 1 : 0.72
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }
                            }
                            scale: th.sel ? 1 : 0.94
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                            MouseArea {
                                id: tHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.idx = th.index
                                onDoubleClicked: Quickshell.execDetached(["swayimg", th.modelData.path])
                            }
                        }
                    }
                }
            }
        }
    }
}
