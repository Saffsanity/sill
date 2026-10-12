import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// The few things the session code (StreamClient and its helpers) needs from the platform, so the
// same files build the iOS app and the Mac client (Sources/MacClient, whose Shared folder links to
// these files). Everything else a platform does differently lives in its own views.

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

enum ClientPlatform {
    /// "Noah's iPad", or the Mac's computer name. Main thread first (UIDevice).
    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #endif
    }

    /// What the copy calls this device: "iPhone", "iPad" or "Mac".
    static var deviceWord: String {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        #else
        return "Mac"
        #endif
    }

    /// "iPad14,1", "iPad16,6 simulator" or "Mac14,9": also what a pairing request gives as the model.
    static var hardwareIdentifier: String {
        #if canImport(UIKit)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) simulator"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #else
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
        #endif
    }

    /// Posted when the app comes back to the front after it may have been suspended.
    static var willEnterForeground: Notification.Name {
        #if canImport(UIKit)
        return UIApplication.willEnterForegroundNotification
        #else
        return NSApplication.willBecomeActiveNotification
        #endif
    }

    /// The warning haptic (iPhone) and a VoiceOver announcement: a refused menu choice.
    static func warn(announcing text: String) {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIAccessibility.post(notification: .announcement, argument: text)
        #else
        NSSound.beep()
        if let window = NSApp.keyWindow {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        #endif
    }

    /// The fastest rate this device's screen shows: 120 on ProMotion, 60 elsewhere. Main thread.
    static func screenMaximumFPS() -> Int {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // `connectedScenes` is unordered: prefer the scene the user is looking at.
        let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
        return max(30, screen?.maximumFramesPerSecond ?? 60)
        #else
        let screen = NSApp?.keyWindow?.screen ?? NSScreen.main
        return max(30, screen?.maximumFramesPerSecond ?? 60)
        #endif
    }
}
