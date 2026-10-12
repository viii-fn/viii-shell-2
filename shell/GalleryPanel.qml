// File: ~/viii-shell-2/shell/GalleryPanel.qml
// Gallery, lightbox style: the picture fills the whole window, everything else floats on it
// and fades away when the mouse is still. Sharp corners, hairlines, small caps.
//   qs ipc call gallery toggle | show | hide
//   qs ipc call gallery open /path/to/folder
// Keys: Left/Right browse, Home/End jump, Enter open in swayimg, C copy path, Esc close

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 600
    readonly property string mono: "JetBrainsMono Nerd Font"

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
    function openExternal() { if (cur) Quickshell.execDetached(["swayimg", cur.path]) }
    function copyPath() {
        if (cur) Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", cur.path])
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
    function pad(n, w) { return ("000" + n).slice(-w) }
    // Big number, small unit
    function sizeHtml(b, ns, us) {
        const num = v => '<span style="font-size:' + ns + 'px; font-weight:600; color:' + hex(Theme.fg) + ';">' + v + '</span>'
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

    // Text button with an underline that draws in on hover
    component Act: Item {
        id: act
        property string label: ""
        property bool strong: false
        signal clicked()
        implicitWidth: lbl.implicitWidth
        implicitHeight: 26
        Text {
            id: lbl
            anchors.verticalCenter: parent.verticalCenter
            text: act.label
            color: (act.strong || hit.containsMouse) ? Theme.accentHi : Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.letterSpacing: 2
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            height: 1
            width: hit.containsMouse ? parent.width : 0
            color: Theme.accentHi
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.clicked()
        }
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
            implicitWidth: 880
            implicitHeight: 700
            color: "transparent"
            onVisibleChanged: if (!visible) root.shown = false

            // Overlay visibility: shows on mouse movement, hides after a pause
            property bool ui: true
            readonly property bool showUi: ui || root.files.length === 0

            Timer {
                id: hideTimer
                interval: 2600
                onTriggered: win.ui = false
            }
            Component.onCompleted: hideTimer.restart()

            Shortcut { sequence: "Home"; onActivated: root.idx = 0 }
            Shortcut { sequence: "End"; onActivated: root.idx = Math.max(0, root.files.length - 1) }
            Shortcut { sequence: "C"; onActivated: root.copyPath() }

            Rectangle {
                id: body
                anchors.fill: parent
                color: Qt.darker(Theme.panel, 1.7)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
                focus: true
                clip: true
                Keys.onEscapePressed: root.shown = false
                Keys.onLeftPressed: root.step(-1)
                Keys.onRightPressed: root.step(1)
                Keys.onReturnPressed: root.openExternal()

                HoverHandler {
                    onPointChanged: { win.ui = true; hideTimer.restart() }
                }
                WheelHandler {
                    onWheel: (e) => { root.step(e.angleDelta.y > 0 ? -1 : 1); win.ui = true; hideTimer.restart() }
                }

                // ── The picture, edge to edge ──
                Image {
                    id: big
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    sourceSize.width: 1800
                    sourceSize.height: 1400
                    source: root.cur ? root.url(root.cur.path) : ""
                    opacity: status === Image.Ready ? 1 : 0
                    scale: status === Image.Ready ? 1 : 1.015
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.files.length === 0
                    text: "NO IMAGES IN  " + root.dir
                    color: Theme.fgDim
                    font.family: root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 3
                }

                // ── Click zones with edge arrows ──
                MouseArea {
                    id: leftZone
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 90
                    anchors.bottomMargin: 200
                    width: 110
                    hoverEnabled: true
                    visible: root.files.length > 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.step(-1)
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf053"
                        color: Theme.fg
                        font.family: root.mono
                        font.pixelSize: 22
                        opacity: leftZone.containsMouse ? 1 : (win.showUi ? 0.35 : 0)
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
                MouseArea {
                    id: rightZone
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 90
                    anchors.bottomMargin: 200
                    width: 110
                    hoverEnabled: true
                    visible: root.files.length > 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.step(1)
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf054"
                        color: Theme.fg
                        font.family: root.mono
                        font.pixelSize: 22
                        opacity: rightZone.containsMouse ? 1 : (win.showUi ? 0.35 : 0)
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }

                // ── Top bar: folder + counter ──
                Item {
                    id: topBar
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 96
                    opacity: win.showUi ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.72) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
                        }
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 28
                        anchors.topMargin: 22
                        spacing: 2
                        Text {
                            text: "GALLERY"
                            color: Theme.accentHi
                            font.family: root.mono
                            font.pixelSize: 9
                            font.letterSpacing: 4
                        }
                        Text {
                            text: root.folderName()
                            color: Theme.fg
                            font.family: root.mono
                            font.pixelSize: 24
                            font.weight: Font.Light
                        }
                    }

                    RowLayout {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 28
                        anchors.topMargin: 26
                        spacing: 22

                        Text {
                            visible: root.files.length > 0
                            textFormat: Text.RichText
                            font.family: root.mono
                            text: '<span style="font-size:24px; font-weight:300; color:' + root.hex(Theme.fg) + ';">'
                                  + root.pad(root.idx + 1, 2)
                                  + '</span><span style="font-size:11px; color:' + root.hex(Theme.fgDim) + ';">&nbsp;/&nbsp;'
                                  + root.pad(root.files.length, 2) + '</span>'
                        }
                        Act { label: "REFRESH"; onClicked: root.reload() }
                    }
                }

                // ── Bottom bar: details, actions, filmstrip ──
                Item {
                    id: bottomBar
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 190
                    opacity: win.showUi ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.72) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
                        }
                    }

                    // Info row
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 28
                        anchors.rightMargin: 28
                        anchors.topMargin: 38
                        spacing: 22
                        visible: root.cur !== null

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: root.cur ? root.base(root.cur.path) : ""
                                color: Theme.fg
                                font.family: root.mono
                                font.pixelSize: 15
                                elide: Text.ElideMiddle
                            }
                            Text {
                                text: root.cur ? root.ago(root.cur.t).toUpperCase() : ""
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 9
                                font.letterSpacing: 2.5
                            }
                        }
                        Text {
                            textFormat: Text.RichText
                            font.family: root.mono
                            text: root.cur ? root.sizeHtml(root.cur.size, 22, 10) : ""
                        }
                        Act { label: "COPY PATH"; onClicked: root.copyPath() }
                        Act { label: "OPEN IN SWAYIMG  \uf08e"; strong: true; onClicked: root.openExternal() }
                    }

                    // Filmstrip: the selected frame opens up, the rest stay narrow
                    ListView {
                        id: strip
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 22
                        height: 56
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: 4
                        model: root.files
                        currentIndex: root.idx
                        highlightMoveDuration: 260
                        preferredHighlightBegin: width / 2 - 42
                        preferredHighlightEnd: width / 2 + 42
                        highlightRangeMode: ListView.ApplyRange
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: th
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === root.idx
                            width: sel ? 84 : 36
                            height: 56
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 180
                                sourceSize.height: 120
                                source: root.url(th.modelData.path)
                                opacity: th.sel ? 1 : (tHit.containsMouse ? 0.85 : 0.45)
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }
                            // Selection underline
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 2
                                color: Theme.accentHi
                                opacity: th.sel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }
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
