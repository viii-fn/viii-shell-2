import Quickshell
import Quickshell.Io                  // IpcHandler: lets No running instances for "/home/viii_fn/.config/quickshell/shell.qml"
import Quickshell.Wayland             // WlSessionLock
import Quickshell.Services.Pam        // PamContext: real password checking
import QtQuick

Scope {
    id: root
    property string password: ""
    property bool failed: false

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // Lets you run:  qs ipc call lock lock
    IpcHandler {
        target: "lock"
        function lock(): void { sessionLock.locked = true }
    }

    PamContext {
        id: pam
        // PAM asks "I need the password" by setting responseRequired = true.
        onResponseRequiredChanged: if (responseRequired) respond(root.password)

        // "result =>" is a lambda, like (result) => ... in C#.
        onCompleted: result => {
            if (result === PamResult.Success) sessionLock.locked = false  // unlock
            else root.failed = true
            root.password = ""
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        // One surface is created per monitor, covering the whole screen.
        WlSessionLockSurface {
            color: "#1a1410"

            Column {
                anchors.centerIn: parent
                spacing: 20

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#ebdbb2"; font.pixelSize: 72
                    text: Qt.formatDateTime(clock.date, "hh:mm")
                }

                Rectangle {
                    width: 280; height: 44; radius: 22
                    color: "#33ebdbb2"
                    border.width: 2
                    border.color: root.failed ? "#fb4934" : "#d79921"

                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 12
                        horizontalAlignment: TextInput.AlignHCenter
                        color: "#ebdbb2"; font.pixelSize: 18
                        echoMode: TextInput.Password
                        focus: true
                        text: root.password
                        onTextEdited: { root.password = text; root.failed = false }
                        onAccepted: if (!pam.active) pam.start()   // Enter = try to log in
                    }
                }
            }
        }
    }
}
