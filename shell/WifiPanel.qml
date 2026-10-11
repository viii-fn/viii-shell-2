// File: ~/viii-shell-2/shell/WifiPanel.qml
// Tiny always-present part of the Wi-Fi panel: the IPC target and the lazy
// loader. WifiWindow.qml (the real panel) exists only while it is open.
//   qsctl wifi toggle | show | hide
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property bool shown: false
    property bool alive: false           // true while WifiWindow exists (open + closing)
    readonly property int closeMs: 600   // leave time for the close animation

    onShownChanged: {
        if (shown) { unload.stop(); alive = true }
        else unload.restart()
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }

    IpcHandler {
        target: "wifi"
        function toggle(): void { root.shown = !root.shown }
        function show(): void { root.shown = true }
        function hide(): void { root.shown = false }
    }

    LazyLoader {
        active: root.alive
        WifiWindow {
            shown: root.shown
            onCloseRequested: root.shown = false
        }
    }
}
