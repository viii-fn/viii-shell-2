// File: ~/viii-shell-2/shell/WifiWindow.qml
// The Wi-Fi panel (same nmcli logic as before), hive style. Created by
// WifiPanel.qml on the first toggle and destroyed shortly after it closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root
    title: "wifi"
    visible: true
    implicitWidth: 360
    implicitHeight: 480
    color: "transparent"

    property bool shown: false           // set by WifiPanel.qml
    signal closeRequested()              // Escape or the window manager closing us

    // 0 = hidden, 1 = open. Starts at 0 and fades in once created.
    property real appear: 0
    Behavior on appear { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Component.onCompleted: {
        appear = Qt.binding(() => root.shown ? 1 : 0)
        refresh()
    }
    onVisibleChanged: if (!visible) closeRequested()

    property bool badPassword: false

    property bool wifiOn: true
    property string pendingSsid: ""   // network waiting for a password
    property string status: ""
    property string currentSsid: ""

    function refresh() {
        radioCheck.running = true
        scan.running = true
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

    // Turn nmcli's terse output into rows for the list
    // Merge duplicate SSIDs (2.4/5 GHz) so the one we're connected to isn't lost
    function parse(text) {
        const byName = {}
        for (const line of text.trim().split("\n")) {
            if (!line) continue
            const f = line.replace(/\\:/g, "\u0001").split(":")
                          .map(s => s.replace(/\u0001/g, ":"))
            const ssid = f[1]
            if (!ssid) continue
            const row = byName[ssid] || (byName[ssid] = {
                active: false, ssid: ssid, strength: 0, security: f[3] || ""
            })
            row.active = row.active || f[0] === "*"
            row.strength = Math.max(row.strength, parseInt(f[2]) || 0)
        }
        // Connected network first, then strongest signal
        const rows = Object.values(byName)
        rows.sort((a, b) => (b.active - a.active) || (b.strength - a.strength))

        networks.clear()
        currentSsid = ""
        for (const r of rows) {
            networks.append(r)
            if (r.active) currentSsid = r.ssid
        }
    }

    ListModel { id: networks }

    Process {
        id: scan
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
                  "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
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
            } else if (secured) {
                // No saved profile or wrong password: ask for one
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
        cut: 18
        pattern: true
        opacity: root.appear
        focus: true
        Keys.onEscapePressed: root.closeRequested()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12

            // Header: title, refresh, on/off switch
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                HexShape {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14 / 1.1547
                    Layout.alignment: Qt.AlignVCenter
                    fillColor: Theme.accent
                }
                Text {
                    text: "WI-FI"
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.bold: true
                    font.letterSpacing: 4
                    Layout.fillWidth: true
                }
                HexButton {
                    Layout.preferredWidth: 30 * 1.1547
                    Layout.preferredHeight: 30
                    size: 30; glyphSize: 13
                    outlined: true
                    glyph: "\uf021"
                    onClicked: root.refresh()
                }
                // On/off switch: chamfered track with a hexagon knob
                ChamferPanel {
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 26
                    cut: 7
                    fillColor: root.wifiOn ? Theme.accent : Theme.surface
                    strokeColor: root.wifiOn ? Theme.accent : Theme.line

                    HexShape {
                        width: 18 * 1.1547; height: 18
                        y: 4
                        x: root.wifiOn ? parent.width - width - 5 : 5
                        fillColor: root.wifiOn ? Theme.accentText : Theme.fgDim
                        Behavior on x { NumberAnimation { duration: 120 } }
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

            // Password prompt, shown only when a network needs one
            ChamferPanel {
                id: pwBox
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                cut: 9
                fillColor: Theme.surface
                strokeColor: root.badPassword ? Theme.bad : Theme.accent
                visible: root.pendingSsid !== ""
                onVisibleChanged: if (visible) { pwField.text = ""; pwField.forceActiveFocus() }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    text: "Password for " + root.pendingSsid
                    color: Theme.fgDim
                    visible: pwField.text === ""
                    elide: Text.ElideRight
                }
                TextInput {
                    id: pwField
                    anchors.fill: parent
                    anchors.margins: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Theme.fg
                    clip: true
                    onAccepted: root.connectTo(root.pendingSsid, true, text)
                    Keys.onEscapePressed: root.pendingSsid = ""
                }
            }

            Text {
                text: root.status
                color: root.badPassword ? Theme.bad : Theme.fgDim
                visible: text !== ""
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: "Wi-Fi is off"
                color: Theme.fgDim
                visible: !root.wifiOn
                Layout.alignment: Qt.AlignHCenter
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: networks
                visible: root.wifiOn

                delegate: ChamferPanel {
                    id: row
                    required property bool active
                    required property string ssid
                    required property int strength
                    required property string security

                    width: list.width
                    height: 48
                    cut: 9
                    fillColor: hover.containsMouse ? Theme.surface : Qt.rgba(1, 1, 1, 0.04)
                    strokeColor: active ? Theme.accent : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        // Signal strength: four little hexagons, filled from the left
                        Row {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: 4
                                HexShape {
                                    required property int index
                                    width: 9; height: 9 / 1.1547 + 2
                                    fillColor: row.strength > index * 25
                                               ? (row.strength >= 50 ? Theme.accent : Theme.fgDim)
                                               : Qt.rgba(1, 1, 1, 0.12)
                                }
                            }
                        }

                        Text {
                            text: row.ssid
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: row.active ? "connected" : (row.security !== "" ? "secured" : "open")
                            color: row.active ? Theme.accent : Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.active) {
                                disconnector.ssid = row.ssid
                                disconnector.running = true
                            } else {
                                root.connectTo(row.ssid, row.security !== "", "")
                            }
                        }
                    }
                }
            }
        }
    }
}
