import SwiftUI

@main
struct SillApp: App {
    /// Only `buildMenu(with:)`: the Mac's menus in the iPad's menu bar on iPadOS 26 (SillAppDelegate).
    @UIApplicationDelegateAdaptor(SillAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
