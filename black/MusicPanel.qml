// File: ~/.config/quickshell/MusicPanel.qml

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick

Scope {
    id: root
    property bool shown: false

    // Preferred player: Spotify -> Amberol -> Active MPRIS player -> First available
    readonly property var player: {
        const ps = Mpris.players.values
        if (ps.length === 0) return null

        for (let i = 0; i < ps.length; i++) {
            if (ps[i].identity.toLowerCase().indexOf("spotify") >= 0) return ps[i]
        }
        for (let i = 0; i < ps.length; i++) {
            const id = ps[i].identity.toLowerCase()
            if (id.indexOf("amberol") >= 0 || id.indexOf("io.bassi.amberol") >= 0) return ps[i]
        }
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying) return ps[i]
        }
        return ps[0]
    }

    // Normalized title & artist for local media (e.g. Amberol, MPV, VLC)
    readonly property string parsedTitle: {
        if (!player || !player.trackTitle) return ""
        let t = player.trackTitle
        if (t.startsWith("file://")) {
            t = decodeURIComponent(t.substring(t.lastIndexOf("/") + 1))
        }
        t = t.replace(/\.(mp3|flac|m4a|ogg|wav|opus|aac)$/i, "")
        if ((!player.trackArtist || player.trackArtist.length === 0) && t.indexOf(" - ") !== -1) {
            return t.split(" - ").slice(1).join(" - ").trim()
        }
        return t
    }

    readonly property string parsedArtist: {
        if (!player) return ""
        if (player.trackArtist && player.trackArtist.length > 0) return player.trackArtist
        if (player.trackTitle) {
            let t = player.trackTitle
            if (t.startsWith("file://")) {
                t = decodeURIComponent(t.substring(t.lastIndexOf("/") + 1))
            }
            if (t.indexOf(" - ") !== -1) {
                return t.split(" - ")[0].trim()
            }
        }
        return ""
    }

    // --- Lyrics (LRCLIB) ---------------------------------------------------
    property var lines: []
    property string status: ""
    property bool again: false
    readonly property string key: player ? parsedArtist + "|" + parsedTitle : ""

    onKeyChanged: { lines = []; status = key ? "Loading lyrics…" : ""; debounce.restart() }
    Timer { id: debounce; interval: 400; onTriggered: root.fetchLyrics() }

    function fetchLyrics() {
        if (!parsedTitle) return
        if (lrc.running) { again = true; return }

        let args = [
            "curl", "-s", "-G", "-A", "quickshell-player", "https://lrclib.net/api/search",
            "--data-urlencode", "track_name=" + parsedTitle
        ]
        if (parsedArtist) {
            args.push("--data-urlencode", "artist_name=" + parsedArtist)
        }

        lrc.command = args
        lrc.running = true
    }

    Process {
        id: lrc
        stdout: StdioCollector { onStreamFinished: root.parseLyrics(text) }
        onExited: if (root.again) { root.again = false; root.fetchLyrics() }
    }

    function parseLyrics(raw) {
        try {
            const results = JSON.parse(raw)
            let best = null, bestDiff = 1e9
            const len = player ? player.length : 0
            for (const r of results) {
                if (!r.syncedLyrics) continue
                const diff = len > 0 ? Math.abs((r.duration || 0) - len) : 0
                if (diff < bestDiff) { best = r; bestDiff = diff }
            }
            if (!best) { status = "No synced lyrics found"; return }
            const out = []
            for (const l of best.syncedLyrics.split("\n")) {
                const m = l.match(/^\[(\d+):(\d+(?:\.\d+)?)\](.*)$/)
                if (m) out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: m[3].trim() })
            }
            lines = out
            status = out.length ? "" : "No synced lyrics found"
        } catch (e) { status = "No lyrics found" }
    }

    readonly property int idx: {
        const pos = player ? player.position : 0
        let i = -1
        for (let k = 0; k < lines.length; k++) { if (lines[k].t <= pos + 0.3) i = k; else break }
        return i
    }
    function lineAt(i) { return (i >= 0 && i < lines.length) ? lines[i].text : "" }
    function fmt(s) { return Math.floor(s / 60) + ":" + ("0" + Math.floor(s % 60)).slice(-2) }

    Timer {
        interval: 250; repeat: true
        running: root.shown && root.player !== null && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    IpcHandler {
        target: "music"
        function toggle(): void { root.shown = !root.shown }
    }

    component Btn: Item {
        id: btn
        property string glyph: ""
        property bool filled: false
        signal clicked()
        width: 36; height: 36
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: btn.filled ? "#ffffff" : (m.containsMouse ? "#333333" : "transparent")
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
            color: btn.filled ? "#121212" : "#e5e5e5"
        }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
    }

    PanelWindow {
        id: win
        visible: root.shown
        // Full-screen transparent surface; only the card below catches the mouse
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        // Only the card's rectangle receives input; everything else passes through
        mask: Region {
            x: panel.x
            y: panel.y
            width: panel.width
            height: panel.height
        }

        Rectangle {
            id: panel
            x: 12      // starting position; changes as you drag
            y: 54
            width: 580
            height: Math.max(leftCol.implicitHeight, lyricsBox.implicitHeight) + 32
            radius: 24
            color: "#f2121212"
            border.width: 1
            border.color: "#444444"

            // Drag anywhere on empty card space; stays inside the screen
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                drag.target: panel
                drag.minimumX: 0
                drag.maximumX: win.width - panel.width
                drag.minimumY: 0
                drag.maximumY: win.height - panel.height
            }

            Row {
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 20

                // LEFT SIDE: Controls, Album Art & Meta
                Column {
                    id: leftCol
                    width: 180
                    spacing: 10

                    ClippingRectangle {
                        width: parent.width; height: parent.width; radius: 16
                        color: "#262626"
                        Text { anchors.centerIn: parent; text: "♪"; font.pixelSize: 48; color: "#777777"; visible: art.status !== Image.Ready }
                        Image {
                            id: art
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: root.player ? (root.player.trackArtUrl || "") : ""
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; font.weight: Font.Bold
                            color: "#ffffff"
                            text: root.parsedTitle !== "" ? root.parsedTitle : "Nothing playing"
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                            color: "#999999"
                            text: root.parsedArtist
                        }
                    }

                    // Progress bar
                    Column {
                        width: parent.width
                        spacing: 4
                        Rectangle {
                            width: parent.width; height: 5; radius: 3; color: "#2a2a2a"
                            Rectangle {
                                height: parent.height; radius: 3; color: "#cccccc"
                                width: (root.player && root.player.length > 0)
                                     ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                            }
                            MouseArea {
                                anchors.fill: parent; anchors.topMargin: -6; anchors.bottomMargin: -6
                                onClicked: mouse => {
                                    if (root.player && root.player.canSeek)
                                        root.player.position = (mouse.x / width) * root.player.length
                                }
                            }
                        }
                        Item {
                            width: parent.width; height: 12
                            Text { anchors.left: parent.left; font.pixelSize: 10; color: "#888888"
                                   text: root.player ? root.fmt(root.player.position) : "0:00" }
                            Text { anchors.right: parent.right; font.pixelSize: 10; color: "#888888"
                                   text: root.player ? root.fmt(root.player.length) : "0:00" }
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Btn { glyph: "\uf048"; onClicked: if (root.player) root.player.previous() }
                        Btn {
                            width: 42; height: 42; filled: true
                            glyph: (root.player && root.player.isPlaying) ? "\uf04c" : "\uf04b"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: if (root.player) root.player.togglePlaying()
                        }
                        Btn { glyph: "\uf051"; onClicked: if (root.player) root.player.next() }
                    }
                }

                // RIGHT SIDE: Synced Lyrics
                Item {
                    id: lyricsBox
                    width: parent.width - leftCol.width - parent.spacing
                    height: leftCol.implicitHeight
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: root.lines.length === 0
                        text: root.status
                        color: "#888888"; font.pixelSize: 12
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 12
                        visible: root.lines.length > 0

                        Repeater {
                            model: 5
                            delegate: Text {
                                required property int index
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: index === 2 ? 15 : 12
                                font.weight: index === 2 ? Font.Bold : Font.Normal
                                color: index === 2 ? "#ffffff" : "#bbbbbb"
                                opacity: index === 2 ? 1 : (Math.abs(index - 2) === 1 ? 0.45 : 0.2)
                                text: root.lineAt(root.idx + index - 2)
                            }
                        }
                    }
                }
            }
        }
    }
}
