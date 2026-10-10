import QtQuick
import Quickshell
import Quickshell.Io

// Lightweight controller: state, IPC and ffmpeg only.
// No QtMultimedia here. The video window lives in TrimWindow.qml,
// which is only created when you open a file.
Scope {
    id: root

    property string file: ""
    property real startMs: 0
    property real endMs: 0
    property bool exact: false
    property string status: ""
    property bool exporting: ff.running
    property var win: null   // the open TrimWindow, or null when closed

    // 83250 ms -> "01:23.250"
    function fmt(ms) {
        var t = Math.max(0, Math.floor(ms))
        var m = Math.floor(t / 60000)
        var s = Math.floor((t % 60000) / 1000)
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
             + "." + String(t % 1000).padStart(3, "0")
    }

    // video.mp4 -> video_trim.mp4 (saved next to the original)
    function outPath() {
        return file.replace(/(\.[^./]+)$/, "_trim$1")
    }

    function closeWin() {
        if (win) {
            var w = win
            win = null          // clear first so onVisibleChanged can't re-enter
            w.destroy()
        }
    }

    function openFile(p) {
        closeWin()
        file = p
        startMs = 0
        endMs = 0
        status = ""
        // Compiled only now, so QtMultimedia loads on first open, not at login
        var c = Qt.createComponent("TrimWindow.qml")
        if (c.status === Component.Ready)
            win = c.createObject(root, { panel: root })
        else
            console.log("TrimWindow error:", c.errorString())
    }

    function doExport() {
        if (endMs <= startMs) { status = "End must be after start"; return }
        var ss = (startMs / 1000).toFixed(3)
        var dur = ((endMs - startMs) / 1000).toFixed(3)
        var cmd = ["ffmpeg", "-y", "-ss", ss, "-i", file, "-t", dur]
        if (exact)
            cmd = cmd.concat(["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-c:a", "aac"])
        else
            cmd = cmd.concat(["-c", "copy"])   // instant + lossless, snaps to keyframes
        cmd.push(outPath())
        ff.command = cmd
        status = "Exporting..."
        ff.running = true
    }

    Process {
        id: ff
        onExited: (code, st) => {
            root.status = code === 0 ? "Saved: " + root.outPath() : "ffmpeg failed (code " + code + ")"
        }
    }

    // File picker, only runs when you press the keybind with nothing open
    Process {
        id: picker
        command: ["zenity", "--file-selection", "--title=Pick a video"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim()
                if (p !== "") root.openFile(p)
            }
        }
    }

    // qs ipc call trim toggle        -> pick a file, or close if open
    // qs ipc call trim open <path>   -> open a specific file
    IpcHandler {
        target: "trim"
        function toggle(): void {
            if (root.win) root.closeWin()
            else picker.running = true
        }
        function open(path: string): void {
            root.openFile(path)
        }
    }
}
