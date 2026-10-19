import SwiftUI

@main
struct SillVisionApp: App {
    @UIApplicationDelegateAdaptor(VisionSceneSetAppDelegate.self) private var appDelegate
    private var initialSize: CGSize {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SillNativeRestore1") {
            return CGSize(width: 2400, height: 1350)
        }
        if let spec = LayoutHarness.Spec.fromLaunchArguments { return spec.size }
        #endif
        return VisionWindowSizePolicy.login
    }

    var body: some Scene {
        WindowGroup(id: "sill-main") {
            VisionSessionView()
        }
        .windowStyle(.plain)
        .defaultSize(width: initialSize.width, height: initialSize.height)

        WindowGroup("Sill", id: "sill-session", for: UUID.self) { $windowID in
            VisionSessionView(windowID: windowID, isSecondary: true)
                .id(windowID)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1200, height: 800)
    }
}
