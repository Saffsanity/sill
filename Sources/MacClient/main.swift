import AppKit

// Sill Viewer: an AppKit app, not a SwiftUI one, so its menu bar is its own to fill with the
// controlled app's menus (MainMenu) and its windows are the other Mac's windows (StreamWindows).
// Sill's own controls live in the menu bar's status item (StatusMenu).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
