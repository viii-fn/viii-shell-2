import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root
    title: "wifi"
    visible: false
    implicitWidth: 360
    implicitHeight: 480
    color: Qt.rgba(22/255, 20/255, 16/255, 0.88)   // Warm dark yellow-tinted background with transparency

    readonly property color fg: "#e5e5e5"
    readonly property color dim: "#b0a088"      // low signal / disabled
    readonly property color accent: "#ffd700"   // high signal / enabled (Yellow)
    readonly property color bad: "#ffd700"      // wrong password only

    property bool badPassword: false

    property bool wifiOn: true
    property string pendingSsid: ""   // network waiting for a password
    property string status: ""
    property string currentSsid: ""

    onVisibleChanged: if (visible) refresh()

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

    IpcHandler {
        target: "wifi"
        function toggle(): void { root.visible = !root.visible }
        function show(): void { root.visible = true }
        function hide(): void { root.visible = false }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.visible = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Header: title, refresh, on/off switch
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Wi-Fi"
                    color: root.fg
                    font.pixelSize: 20
                    font.bold: true
                    Layout.fillWidth: true
                }
                Text {
                    text: "↻"
                    color: root.fg
                    font.pixelSize: 20
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refresh()
                    }
                }
                Rectangle {
                    width: 44; height: 24; radius: 12
                    color: root.wifiOn ? root.accent : root.dim
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        y: 3
                        x: root.wifiOn ? 23 : 3
                        color: "#161410"
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
            Rectangle {
                id: pwBox
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: "#3a351c"
                border.width: 1
                border.color: root.badPassword ? root.bad : root.accent
                visible: root.pendingSsid !== ""
                onVisibleChanged: if (visible) { pwField.text = ""; pwField.forceActiveFocus() }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: "Password for " + root.pendingSsid
                    color: root.dim
                    visible: pwField.text === ""
                    elide: Text.ElideRight
                }
                TextInput {
                    id: pwField
                    anchors.fill: parent
                    anchors.margins: 12
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: root.fg
                    clip: true
                    onAccepted: root.connectTo(root.pendingSsid, true, text)
                    Keys.onEscapePressed: root.pendingSsid = ""
                }
            }

            Text {
                text: root.status
                color: root.badPassword ? root.bad : root.dim
                visible: text !== ""
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: "Wi-Fi is off"
                color: root.dim
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

                delegate: Rectangle {
                    id: row
                    required property bool active
                    required property string ssid
                    required property int strength
                    required property string security

                    width: list.width
                    height: 48
                    radius: 10
                    color: hover.containsMouse ? "#3a351c" : Qt.rgba(255, 255, 255, 0.04)
                    border.width: active ? 1 : 0
                    border.color: root.accent

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        // Signal bars
                        Row {
                            spacing: 3
                            Repeater {
                                model: 4
                                Item {
                                    required property int index
                                    width: 4; height: 18
                                    Rectangle {
                                        width: 4
                                        height: 6 + parent.index * 4
                                        anchors.bottom: parent.bottom
                                        radius: 1
                                        color: row.strength > parent.index * 25
                                               ? (row.strength >= 50 ? root.accent : root.dim)
                                               : "#333333"
                                    }
                                }
                            }
                        }

                        Text {
                            text: row.ssid
                            color: root.fg
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: row.active ? "connected" : (row.security !== "" ? "secured" : "open")
                            color: row.active ? root.accent : root.dim
                            font.pixelSize: 12
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
