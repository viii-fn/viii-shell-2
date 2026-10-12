// File: ~/viii-shell-2/shell/WifiWindow.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root
    title: "wifi"
    visible: true
    implicitWidth: 380
    implicitHeight: 580
    color: "transparent"

    property bool shown: false
    signal closeRequested()

    property real appear: 0
    Behavior on appear { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Component.onCompleted: {
        appear = Qt.binding(() => root.shown ? 1 : 0)
        refresh()
    }
    onVisibleChanged: if (!visible) closeRequested()

    property bool badPassword: false
    property bool wifiOn: true
    property string pendingSsid: ""
    property string status: ""
    property string currentSsid: ""
    property var current: null
    property var saved: ({})

    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function sigHtml(v) {
        return '<span style="font-size:34px; font-weight:600; color:' + hex(Theme.accentHi) + ';">' + v + '</span>'
             + '<span style="font-size:13px; color:' + hex(Theme.fgDim) + ';">%</span>'
    }

    function refresh() {
        radioCheck.running = true
        scan.running = true
        savedList.running = true
    }

    function connectTo(ssid, secured, password) {
        if (connector.running) return
        badPassword = false
        status = "Connecting to " + ssid + "…"
        connector.ssid = ssid
        connector.secured = secured
        connector.password = password
        connector.running = true
    }

    function parse(text) {
        const byName = {}
        for (const line of text.trim().split("\n")) {
            if (!line) continue
            const f = line.replace(/\\:/g, "\u0001").split(":")
                          .map(s => s.replace(/\u0001/g, ":"))
            const ssid = f[1]
            if (!ssid) continue
            const strength = parseInt(f[2]) || 0
            const freq = parseInt(f[4]) || 0
            const row = byName[ssid] || (byName[ssid] = {
                active: false, ssid: ssid, strength: 0, security: f[3] || "", band: ""
            })
            row.active = row.active || f[0] === "*"
            if (strength >= row.strength) {
                row.strength = strength
                row.band = freq >= 5900 ? "6 GHz" : (freq >= 4900 ? "5 GHz" : (freq > 0 ? "2.4 GHz" : ""))
            }
        }
        const rows = Object.values(byName)
        rows.sort((a, b) => b.strength - a.strength)

        const act = rows.find(r => r.active)
        current = act || null
        currentSsid = act ? act.ssid : ""

        networks.clear()
        for (const r of rows) if (!r.active) networks.append(r)
    }

    ListModel { id: networks }

    Timer {
        interval: 10000
        repeat: true
        running: root.shown && root.wifiOn
        onTriggered: if (!scan.running) scan.running = true
    }

    Process {
        id: scan
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ",
                  "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    Process {
        id: savedList
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = {}
                for (const line of text.trim().split("\n")) {
                    if (!line) continue
                    const f = line.replace(/\\:/g, "\u0001").split(":")
                                  .map(x => x.replace(/\u0001/g, ":"))
                    if ((f[1] || "").indexOf("wireless") >= 0) s[f[0]] = true
                }
                root.saved = s
            }
        }
    }

    Process {
        id: radioCheck
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector { onStreamFinished: root.wifiOn = text.trim() === "enabled" }
    }

    Process {
        id: radioSet
        property bool target: true
        command: ["nmcli", "radio", "wifi", target ? "on" : "off"]
        onExited: root.refresh()
    }

    Process {
        id: disconnector
        property string ssid: ""
        command: ["nmcli", "connection", "down", "id", ssid]
        onExited: { root.status = "Disconnected"; scan.running = true }
    }

    Process {
        id: forgetter
        property string ssid: ""
        command: ["nmcli", "connection", "delete", "id", ssid]
        onExited: { root.status = "Forgot " + ssid; root.refresh() }
    }

    Process {
        id: connector
        property string ssid: ""
        property string password: ""
        property bool secured: false
        command: password === ""
            ? ["nmcli", "device", "wifi", "connect", ssid]
            : ["nmcli", "device", "wifi", "connect", ssid, "password", password]
        stderr: StdioCollector { id: connErr }
        onExited: (code) => {
            root.badPassword = false
            if (code === 0) {
                root.status = "Connected to " + ssid
                root.pendingSsid = ""
                savedList.running = true
            } else if (secured) {
                root.pendingSsid = ssid
                root.badPassword = password !== ""
                root.status = password === "" ? "Password needed" : "Wrong password?"
            } else {
                root.status = connErr.text.trim() || "Connection failed"
            }
            scan.running = true
        }
    }

    ChamferPanel {
        anchors.fill: parent
        cut: 20
        pattern: true
        patternOpacity: 0.05
        opacity: root.appear
        focus: true
        Keys.onEscapePressed: root.closeRequested()

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
                    Layout.alignment: Qt.AlignVCenter
                    fillColor: Theme.accent
                }
                Text {
                    text: "Wi-Fi"
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                HexButton {
                    Layout.preferredWidth: 28 * 1.1547
                    Layout.preferredHeight: 28
                    size: 28; glyphSize: 12
                    outlined: true
                    glyph: "\uf021"
                    onClicked: root.refresh()
                }
                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 26
                    radius: 13
                    color: root.wifiOn ? Theme.accent : Theme.surfaceHi
                    Behavior on color { ColorAnimation { duration: 140 } }

                    Rectangle {
                        width: 20; height: 20; radius: 10
                        y: 3
                        x: root.wifiOn ? parent.width - width - 3 : 3
                        color: root.wifiOn ? Theme.accentText : Theme.fgDim
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            radioSet.target = !root.wifiOn
                            radioSet.running = true
                        }
                    }
                }
            }

            // ── Hero: current connection ──
            ChamferPanel {
                Layout.fillWidth: true
                Layout.preferredHeight: 112
                cut: 14
                visible: root.wifiOn
                fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.7)
                strokeColor: root.current
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                    : Theme.line

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    // Big signal bars
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                width: 7
                                height: 10 + index * 7
                                anchors.bottom: parent.bottom
                                radius: 3
                                color: root.current && root.current.strength > index * 25
                                       ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: root.current ? root.current.ssid : "Not connected"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: root.current !== null
                            textFormat: Text.RichText
                            font.family: "JetBrainsMono Nerd Font"
                            text: root.current ? root.sigHtml(root.current.strength) : ""
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.current
                                  ? (root.current.band + (root.current.band !== "" ? " · " : "")
                                     + (root.current.security !== "" ? "Secured" : "Open"))
                                  : "Pick a network below"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        visible: root.current !== null
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: dcText.implicitWidth + 24
                        Layout.preferredHeight: 30
                        radius: 15
                        color: dcHit.containsMouse
                               ? Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, 0.25)
                               : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: dcHit.containsMouse ? Theme.bad : Theme.line
                        Text {
                            id: dcText
                            anchors.centerIn: parent
                            text: "Disconnect"
                            color: dcHit.containsMouse ? Theme.bad : Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: dcHit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                disconnector.ssid = root.current.ssid
                                disconnector.running = true
                            }
                        }
                    }
                }
            }

            // Status line
            Text {
                text: root.status
                color: root.badPassword ? Theme.bad : Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                visible: text !== "" && root.wifiOn
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // List heading
            RowLayout {
                Layout.fillWidth: true
                visible: root.wifiOn
                Text {
                    text: "AVAILABLE"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.letterSpacing: 1.6
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: scan.running ? "scanning…" : networks.count + " found"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                }
            }

            // Off state
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.wifiOn
                spacing: 8
                Item { Layout.fillHeight: true }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "\uf1eb"
                    color: Theme.fgDim
                    opacity: 0.5
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 54
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Wi-Fi is off"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                }
                Item { Layout.fillHeight: true }
            }

            // Network list (the only scrolling part)
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: networks
                visible: root.wifiOn
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row
                    required property string ssid
                    required property int strength
                    required property string security
                    required property string band

                    readonly property bool pending: root.pendingSsid === ssid
                    readonly property bool isSaved: root.saved[ssid] === true
                    property bool reveal: false

                    width: list.width
                    height: 52 + (pending ? 56 : 0)
                    clip: true
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    onPendingChanged: if (pending) { reveal = false; pw.text = ""; pw.forceActiveFocus() }

                    ChamferPanel {
                        anchors.fill: parent
                        cut: 10
                        fillColor: hit.containsMouse || row.pending
                                   ? Theme.surface : Qt.rgba(1, 1, 1, 0.04)
                        strokeColor: row.pending
                                     ? (root.badPassword ? Theme.bad : Theme.accent)
                                     : "transparent"
                    }

                    // Top line
                    Item {
                        id: top
                        width: parent.width
                        height: 52

                        MouseArea {
                            id: hit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.pending) root.pendingSsid = ""
                                else if (row.isSaved || row.security === "") root.connectTo(row.ssid, row.security !== "", "")
                                else root.pendingSsid = row.ssid
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 14
                            spacing: 12

                            Row {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2
                                Repeater {
                                    model: 4
                                    Rectangle {
                                        required property int index
                                        width: 4
                                        height: 6 + index * 4
                                        anchors.bottom: parent.bottom
                                        radius: 2
                                        color: row.strength > index * 25
                                               ? (row.strength >= 50 ? Theme.accent : Theme.fgDim)
                                               : Qt.rgba(1, 1, 1, 0.12)
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: row.ssid
                                    color: Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (row.isSaved ? "saved · " : "")
                                          + (row.security !== "" ? "secured" : "open")
                                          + (row.band !== "" ? " · " + row.band : "")
                                    color: row.isSaved ? Theme.accent : Theme.fgDim
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                visible: row.security !== ""
                                text: "\uf023"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }

                            // Forget saved network
                            Text {
                                visible: row.isSaved
                                text: "\uf1f8"
                                color: forgetHit.containsMouse ? Theme.bad : Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                MouseArea {
                                    id: forgetHit
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        forgetter.ssid = row.ssid
                                        forgetter.running = true
                                    }
                                }
                            }
                        }
                    }

                    // Inline password field
                    Rectangle {
                        visible: row.pending
                        x: 12
                        y: 54
                        width: parent.width - 24
                        height: 40
                        radius: 12
                        color: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.7)
                        border.width: 1
                        border.color: root.badPassword ? Theme.bad : Theme.accent

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Password"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            visible: pw.text === ""
                        }
                        TextInput {
                            id: pw
                            anchors.left: parent.left
                            anchors.right: eye.left
                            anchors.leftMargin: 14
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: row.reveal ? TextInput.Normal : TextInput.Password
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            clip: true
                            onAccepted: root.connectTo(row.ssid, true, text)
                            Keys.onEscapePressed: root.pendingSsid = ""
                        }
                        Text {
                            id: eye
                            anchors.right: joinBtn.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.reveal ? "\uf070" : "\uf06e"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: row.reveal = !row.reveal
                            }
                        }
                        Rectangle {
                            id: joinBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 50
                            height: 30
                            radius: 9
                            color: Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: "Join"
                                color: Theme.accentText
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectTo(row.ssid, true, pw.text)
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: networks.count === 0 && !scan.running
                    text: "No other networks found"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }
            }
        }
    }
}