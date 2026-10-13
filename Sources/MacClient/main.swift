import AppKit

// Sill Viewer: an AppKit app, not a SwiftUI one, so its menu bar is its own to fill with the
// controlled app's menus (MainMenu) and its windows are the other Mac's windows (StreamWindows).
// Sill's own controls live in the menu bar's status item (StatusMenu). With the remote apps' own
// Dock icons (DockProxies, on by default) it has none itself: they stand for its windows in the Dock
// and in ⌘Tab, minimised ones included (StreamWindows.park), and a Desktop window minimises as any
// window does.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(DockProxies.enabled ? .accessory : .regular)
app.run()
