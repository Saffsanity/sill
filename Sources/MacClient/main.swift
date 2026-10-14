import AppKit

// Sill Viewer: an AppKit app, not a SwiftUI one; its windows are the other Mac's windows
// (StreamWindows), and Sill's own controls live in the menu bar's status item (StatusMenu). With the
// remote apps' own Dock icons (DockProxies, on by default) it has no Dock icon or menu bar itself:
// they stand for its windows in the Dock and in ⌘Tab, minimised ones included (StreamWindows.park),
// and hold each app's menus. Without them its own menu bar has them (MainMenu).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(DockProxies.enabled ? .accessory : .regular)
app.run()
