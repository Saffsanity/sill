import SwiftUI

@main
struct SillApp: App {
    /// Only `buildMenu(with:)`: the Mac's menus in the iPad's menu bar on iPadOS 26 (SillAppDelegate).
    @UIApplicationDelegateAdaptor(SillAppDelegate.self) var appDelegate

    init() {
        // Share Camera starts off at every launch: the camera runs only after the person turned it on since Sill
        // launched (StreamClient+Camera; the 2026-11-18 overview's decision 4).
        StreamClient.resetShareCameraAtLaunch()
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
