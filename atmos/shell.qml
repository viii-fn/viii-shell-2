// File: ~/.config/quickshell/shell.qml

import Quickshell

ShellRoot {
    // One Island per monitor. Quickshell.screens is the list of connected screens.
    Variants {
        model: Quickshell.screens

        Island {
            // Variants hands each copy the screen it belongs to as "modelData".
            required property var modelData
            screen: modelData       // tells this copy which monitor to appear on
        }
    }

    // Lock is not wrapped: WlSessionLock already makes a lock surface per monitor by itself.
    MusicPanel {}
    WifiPanel {}
    AudioPanel {}
    ScreenTimeLogger {}
    DpiPanel {}
    ScreenTimePanel {}
    TrimPanel {}
}
