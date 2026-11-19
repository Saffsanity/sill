import SwiftUI

@main
struct SillApp: App {
    /// Only `buildMenu(with:)`: the Mac's menus in the iPad's menu bar on iPadOS 26 (SillAppDelegate).
    @UIApplicationDelegateAdaptor(SillAppDelegate.self) var appDelegate

    init() {
        // What a quit left of the files waiting to go to a Mac (Sill's own copies: DeviceFiles.outbox), and of
        // files from a Mac that never came whole (SillDocuments.incoming).
        DeviceFiles.cleanOutbox()
        DeviceFiles.cleanIncoming()
    }

    var body: some Scene {
        WindowGroup {
            // iOS 27.1 on the iPhone Duo: the hinge for the layouts (DuoPostureReader); nothing
            // before iOS 27.1 or on a device without a hinge.
            ContentView()
                .readsDuoPosture()
        }
    }
}
