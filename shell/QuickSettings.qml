import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 600

    onShownChanged: {
        if (shown) {
            unload.stop()
            alive = true
        } else {
            unload.restart()
            armed = ""
            pendingSsid = ""
        }
    }

    Timer {
        id: unload
        interval: root.closeMs
        onTriggered: root.alive = false
    }

    // Soft fade/slide in and out
    property real enter: shown ? 1 : 0
    Behavior on enter { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    // ── State (filled by quicksettings-report) ──
    property int vol: 0
    property bool muted: false
    property int bri: 0
    property bool hasBri: false
    property int bat: 0
    property string batStatus: ""
    property bool hasBat: false
    property bool wifiOn: false
    property string ssid: ""
    property bool btOn: false
    property string profile: ""

    property string expanded: ""        // "", "wifi" or "bt"
    property var nets: []
    property var btDevs: []
    property string pendingSsid: ""     // network waiting for a password
    property bool rescan: false
    property string armed: ""           // power action waiting for a second tap

    readonly property string report: Quickshell.env("HOME") + "/.local/bin/quicksettings-report"

    readonly property var tiles: {
        const t = [
            { id: "wifi", glyph: "\uf1eb", title: "Wi-Fi", sub: wifiOn ? (ssid !== "" ? ssid : "Not connected") : "Off", on: wifiOn, exp: true },
            { id: "bt", glyph: "\uf293", title: "Bluetooth", sub: btOn ? "On" : "Off", on: btOn, exp: true },
            { id: "air", glyph: "\uf072", title: "Airplane", sub: (!wifiOn && !btOn) ? "On" : "Off", on: !wifiOn && !btOn, exp: false }
        ]
        if (profile !== "")
            t.push({ id: "prof", glyph: "\uf0e7", title: "Power mode", sub: profileLabel(profile), on: profile !== "balanced", exp: false })
        return t
    }

    // ── Helpers ──
    function profileLabel(p) {
        if (p === "power-saver") return "Saver"
        if (p === "performance") return "Performance"
        return "Balanced"
    }
    function batGlyph() {
        if (batStatus === "Charging") return "\uf0e7"
        if (bat > 87) return "\uf240"
        if (bat > 62) return "\uf241"
        if (bat > 37) return "\uf242"
        if (bat > 12) return "\uf243"
        return "\uf244"
    }
    function unesc(s) { return s.replace(/\\:/g, ":") }

    function parseStatus(text) {
        let b = false, bt = false, pr = "", sid = ""
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p[0] === "VOL") { vol = parseInt(p[1]); muted = p[2] === "1" }
            else if (p[0] === "BRI") { bri = parseInt(p[1]); b = true }
            else if (p[0] === "BAT") { bat = parseInt(p[1]); batStatus = p[2]; bt = true }
            else if (p[0] === "WIFI") { wifiOn = p[1] === "enabled"; sid = unesc(p[2] || "") }
            else if (p[0] === "BT") { btOn = p[1] === "yes" }
            else if (p[0] === "PROF") { pr = p[1] || "" }
        }
        hasBri = b
        hasBat = bt
        profile = pr
        ssid = sid
    }
    function parseNets(text) {
        const known = {}
        const map = {}
        for (const line of text.split("\n")) {
            if (line.indexOf("KNOWN\t") === 0) {
                known[unesc(line.slice(6))] = true
            } else if (line.indexOf("NET\t") === 0) {
                const f = line.slice(4).split(":")
                const name = unesc(f.slice(3).join(":"))
                if (name === "") continue
                const sig = parseInt(f[1]) || 0
                const active = f[0] === "*"
                const sec = (f[2] === "--" ? "" : f[2])
                if (!map[name] || active || sig > map[name].sig)
                    map[name] = { ssid: name, sig: sig, active: active, secured: sec !== "", known: known[name] === true }
            }
        }
        nets = Object.keys(map).map(k => map[k]).sort((a, b) => (b.active - a.active) || (b.sig - a.sig))
    }
    function parseBt(text) {
        const d = []
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p[0] === "BTD") d.push({ mac: p[1], connected: p[2] === "1", name: p[3] })
        }
        btDevs = d
    }

    function refresh() { status.running = true }
    function act(cmd) {
        Quickshell.execDetached(cmd)
        settle.restart()
    }
    // After any action: wait a moment, then re-read the real state
    Timer {
        id: settle
        interval: 1200
        onTriggered: {
            status.running = true
            if (root.expanded === "wifi") netsProc.running = true
            if (root.expanded === "bt") btProc.running = true
        }
    }
    // Poll only while the panel is open
    Timer {
        interval: 4000
        repeat: true
        running: root.shown
        onTriggered: if (!status.running) status.running = true
    }
    Timer {
        id: armTimer
        interval: 3000
        onTriggered: root.armed = ""
    }

    function setExpanded(which) {
        pendingSsid = ""
        expanded = (expanded === which) ? "" : which
        if (expanded === "wifi") { rescan = false; netsProc.running = true }
        if (expanded === "bt") btProc.running = true
    }
    function tileClick(id) {
        if (id === "wifi") {
            act(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"])
            wifiOn = !wifiOn
        } else if (id === "bt") {
            act(["bluetoothctl", "power", btOn ? "off" : "on"])
            btOn = !btOn
        } else if (id === "air") {
            act(["rfkill", (!wifiOn && !btOn) ? "unblock" : "block", "all"])
        } else if (id === "prof") {
            const next = { "power-saver": "balanced", "balanced": "performance", "performance": "power-saver" }[profile]
            act(["powerprofilesctl", "set", next])
            profile = next
        }
    }
    function pickNet(n) {
        if (n.active) { act(["nmcli", "connection", "down", "id", n.ssid]); return }
        if (n.known || !n.secured) {
            act(n.known ? ["nmcli", "connection", "up", "id", n.ssid] : ["nmcli", "dev", "wifi", "connect", n.ssid])
            return
        }
        pendingSsid = (pendingSsid === n.ssid) ? "" : n.ssid
    }
    function connectWith(name, pw) {
        if (pw === "") return
        act(["nmcli", "dev", "wifi", "connect", name, "password", pw])
        pendingSsid = ""
    }
    function power(id) {
        if (armed !== id) { armed = id; armTimer.restart(); return }
        armed = ""
        shown = false
        if (id === "suspend") Quickshell.execDetached(["systemctl", "suspend"])
        else if (id === "logout") Quickshell.execDetached(["labwc", "--exit"])
        else if (id === "reboot") Quickshell.execDetached(["systemctl", "reboot"])
        else if (id === "off") Quickshell.execDetached(["systemctl", "poweroff"])
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void {
            root.shown = !root.shown
            if (root.shown) root.refresh()
        }
    }

    Process {
        id: status
        command: [root.report, "status"]
        stdout: StdioCollector { onStreamFinished: root.parseStatus(text) }
    }
    Process {
        id: netsProc
        command: [root.report, "wifi", root.rescan ? "yes" : "auto"]
        stdout: StdioCollector {
            onStreamFinished: { root.parseNets(text); root.rescan = false }
        }
    }
    Process {
        id: btProc
        command: [root.report, "bt"]
        stdout: StdioCollector { onStreamFinished: root.parseBt(text) }
    }

    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Quick Settings"
            implicitWidth: 420
            implicitHeight: 680
            color: "transparent"
            onVisibleChanged: if (!visible) root.shown = false

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }

            ChamferPanel {
                anchors.fill: parent
                cut: 22
                pattern: true
                patternOpacity: 0.05
                fillColor: Theme.panel
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                opacity: root.enter
                transform: Translate { y: (1 - root.enter) * 14 }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    // ── Header ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        HexButton {
                            size: 30
                            glyph: "\uf013"
                            glyphSize: 13
                            outlined: true
                            interactive: false
                            tone: Theme.accentHi
                        }
                        Text {
                            text: "Quick Settings"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: root.hasBat
                            text: root.batGlyph() + "  " + root.bat + "%"
                            color: root.batStatus === "Charging" ? Theme.accentHi : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }
                    }

                    // ── Scrollable body ──
                    Flickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: body.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: body
                            width: flick.width
                            spacing: 14

                            // Sliders
                            ChamferPanel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: sliders.implicitHeight + 28
                                cut: 12
                                fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
                                strokeColor: Theme.line

                                ColumnLayout {
                                    id: sliders
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 8

                                    QsSliderRow {
                                        glyph: root.muted ? "\uf6a9" : "\uf028"
                                        dim: root.muted
                                        value: root.vol / 100
                                        onMoved: (v) => {
                                            root.vol = Math.round(v * 100)
                                            Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)])
                                        }
                                        onIconClicked: {
                                            root.muted = !root.muted
                                            root.act(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
                                        }
                                    }

                                    QsSliderRow {
                                        visible: root.hasBri
                                        glyph: "\uf185"
                                        value: root.bri / 100
                                        onMoved: (v) => {
                                            root.bri = Math.max(1, Math.round(v * 100))
                                            Quickshell.execDetached(["brightnessctl", "set", root.bri + "%"])
                                        }
                                    }
                                }
                            }

                            // Toggle tiles
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 10
                                columnSpacing: 10

                                Repeater {
                                    model: root.tiles

                                    ChamferPanel {
                                        id: tile
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 66
                                        cut: 10
                                        fillColor: modelData.on
                                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                            : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                                        strokeColor: modelData.on
                                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                                            : Theme.line

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.tileClick(tile.modelData.id)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10

                                            HexButton {
                                                size: 34
                                                glyph: tile.modelData.glyph
                                                glyphSize: 14
                                                outlined: !tile.modelData.on
                                                interactive: false
                                                tone: Theme.accentHi
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: tile.modelData.title
                                                    color: Theme.fg
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: tile.modelData.sub
                                                    color: Theme.fgDim
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            HexButton {
                                                visible: tile.modelData.exp
                                                size: 24
                                                glyph: root.expanded === tile.modelData.id ? "\uf077" : "\uf078"
                                                glyphSize: 9
                                                outlined: true
                                                tone: Theme.fgDim
                                                onClicked: root.setExpanded(tile.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Wi-Fi list ──
                            ChamferPanel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: wifiCol.implicitHeight + 28
                                visible: root.expanded === "wifi"
                                cut: 12
                                fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
                                strokeColor: Theme.line

                                ColumnLayout {
                                    id: wifiCol
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Networks"
                                            color: Theme.fg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }
                                        Item { Layout.fillWidth: true }
                                        HexButton {
                                            size: 24
                                            glyph: "\uf021"
                                            glyphSize: 9
                                            outlined: true
                                            tone: Theme.accentHi
                                            onClicked: { root.rescan = true; netsProc.running = true }
                                        }
                                    }

                                    Text {
                                        visible: root.nets.length === 0
                                        text: root.wifiOn ? "No networks found." : "Wi-Fi is off."
                                        color: Theme.fgDim
                                        font.pixelSize: 11
                                    }

                                    Repeater {
                                        model: root.nets.slice(0, 8)

                                        ColumnLayout {
                                            id: nrow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 34
                                                radius: 10
                                                color: nrow.modelData.active
                                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                                    : (nHit.containsMouse ? Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.6) : "transparent")

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    spacing: 8

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: nrow.modelData.ssid
                                                        color: nrow.modelData.active ? Theme.accentHi : Theme.fg
                                                        font.pixelSize: 12
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        visible: nrow.modelData.active
                                                        text: "\uf00c"
                                                        color: Theme.accentHi
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 11
                                                    }
                                                    Text {
                                                        visible: nrow.modelData.secured
                                                        text: "\uf023"
                                                        color: Theme.fgDim
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                    }
                                                    Text {
                                                        text: nrow.modelData.sig + "%"
                                                        color: Theme.fgDim
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                        horizontalAlignment: Text.AlignRight
                                                        Layout.preferredWidth: 34
                                                    }
                                                }
                                                MouseArea {
                                                    id: nHit
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.pickNet(nrow.modelData)
                                                }
                                            }

                                            // Password prompt (only for new secured networks)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 34
                                                visible: root.pendingSsid === nrow.modelData.ssid
                                                radius: 10
                                                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.8)
                                                border.width: 1
                                                border.color: Theme.accent

                                                TextInput {
                                                    id: pw
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    echoMode: TextInput.Password
                                                    color: Theme.fg
                                                    font.pixelSize: 12
                                                    clip: true
                                                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                                                    Keys.onReturnPressed: root.connectWith(nrow.modelData.ssid, text)
                                                    Keys.onEnterPressed: root.connectWith(nrow.modelData.ssid, text)
                                                }
                                                Text {
                                                    visible: pw.text === ""
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 12
                                                    text: "Password, then Enter"
                                                    color: Theme.fgDim
                                                    font.pixelSize: 11
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Bluetooth list ──
                            ChamferPanel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: btCol.implicitHeight + 28
                                visible: root.expanded === "bt"
                                cut: 12
                                fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5)
                                strokeColor: Theme.line

                                ColumnLayout {
                                    id: btCol
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 6

                                    Text {
                                        text: "Paired devices"
                                        color: Theme.fg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        visible: root.btDevs.length === 0
                                        text: root.btOn ? "No paired devices." : "Bluetooth is off."
                                        color: Theme.fgDim
                                        font.pixelSize: 11
                                    }

                                    Repeater {
                                        model: root.btDevs

                                        Rectangle {
                                            id: drow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            radius: 10
                                            color: modelData.connected
                                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                                : (dHit.containsMouse ? Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.6) : "transparent")

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 8
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: drow.modelData.name
                                                    color: drow.modelData.connected ? Theme.accentHi : Theme.fg
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: drow.modelData.connected ? "Connected" : "Tap to connect"
                                                    color: Theme.fgDim
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                }
                                            }
                                            MouseArea {
                                                id: dHit
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.act(["bluetoothctl", drow.modelData.connected ? "disconnect" : "connect", drow.modelData.mac])
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Power row (tap twice to confirm) ──
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 10

                                Repeater {
                                    model: [
                                        { id: "suspend", glyph: "\uf186", label: "Sleep" },
                                        { id: "logout", glyph: "\uf08b", label: "Log out" },
                                        { id: "reboot", glyph: "\uf021", label: "Reboot" },
                                        { id: "off", glyph: "\uf011", label: "Shut down" }
                                    ]

                                    ColumnLayout {
                                        id: pb
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 4

                                        HexButton {
                                            Layout.alignment: Qt.AlignHCenter
                                            size: 38
                                            glyph: pb.modelData.glyph
                                            glyphSize: 14
                                            outlined: root.armed !== pb.modelData.id
                                            tone: Theme.accentHi
                                            onClicked: root.power(pb.modelData.id)
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: root.armed === pb.modelData.id ? "Tap again" : pb.modelData.label
                                            color: root.armed === pb.modelData.id ? Theme.accentHi : Theme.fgDim
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                        }
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 4 }
                        }
                    }
                }
            }
        }
    }
}
