import SwiftUI

@main
struct SillApp: App {
    /// Only `buildMenu(with:)`: the Mac's menus in the iPad's menu bar on iPadOS 26 (SillAppDelegate).
    @UIApplicationDelegateAdaptor(SillAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            // iOS 27.1 on the iPhone Duo: the hinge for the layouts (DuoPostureReader); nothing
            // before iOS 27.1 or on a device without a hinge.
            ContentView()
                .readsDuoPosture()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowButton()
            }
        }
    }
}

private struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") { openWindow(id: "main") }
            .keyboardShortcut("n", modifiers: .command)
    }
}
