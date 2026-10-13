import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Notifications

// Owns the org.freedesktop.Notifications D-Bus name (the job mako did),
// so notify-send and every app talk to this. Only one daemon can own that
// name, so mako must be stopped first.
Scope {
    id: root

    // Do-not-disturb: while true, everything except critical is dropped.
    property bool dnd: false

    NotificationServer {
        id: server
        keepOnReload: true          // notifications survive a shell reload
        bodySupported: true
        bodyMarkupSupported: true   // <b>, <i> etc. in the body
        actionsSupported: true      // buttons like "Reply"
        imageSupported: true        // avatars / album art sent by apps

        onNotification: n => {
            if (root.dnd && n.urgency !== NotificationUrgency.Critical)
                return
            // "tracked" means: keep it alive and list it in trackedNotifications
            n.tracked = true
        }
    }

    // qs ipc call notifications toggleDnd
    // qs ipc call notifications dismissAll
    IpcHandler {
        target: "notifications"

        function toggleDnd(): void {
            root.dnd = !root.dnd
        }
        function dismissAll(): void {
            // copy first: dismissing changes the model while we loop over it
            const all = [...server.trackedNotifications.values]
            all.forEach(n => n.dismiss())
        }
    }

    PanelWindow {
        id: win

        anchors { top: true; right: true }
        margins { top: 14; right: 14 }

        // 48px wider than a card: slack for the slide-in overshoot
        implicitWidth: 420
        implicitHeight: list.contentHeight
        color: "transparent"
        visible: list.count > 0     // nothing on screen when idle, no idle cost

        exclusionMode: ExclusionMode.Ignore       // don't push other windows around
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "viii-notifications"

        ListView {
            id: list
            anchors { top: parent.top; right: parent.right }
            width: 372
            height: contentHeight
            spacing: 10
            interactive: false

            // ScriptModel + reverse() puts the newest notification on top
            model: ScriptModel {
                values: [...server.trackedNotifications.values].reverse()
            }
            delegate: NotificationCard {}

            // when a card goes away, the ones below slide up smoothly
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }
}
