import AppKit

// The iOS client's shared files (StreamClient and its extensions, the stats reporter) speak UIKit in
// a handful of places. On the Mac those names map onto AppKit here, so the shared files need no more
// than an import switch and a few `#if os(macOS)` lines.

typealias UIImage = NSImage

/// The device's name and kind, as `UIDevice.current` gives them on iOS. The Mac's name is the one in
/// System Settings › General › Sharing, which is what the Mac being streamed lists in its Devices.
struct UIDevice {
    enum Idiom { case phone, pad, mac }

    static let current = UIDevice()

    let name: String = Host.current().localizedName ?? "Mac"
    let userInterfaceIdiom: Idiom = .mac
}

/// The one UIApplication notification the shared client listens for. A Mac app is never suspended,
/// so "back to the foreground" is the app becoming active again.
enum UIApplication {
    static let willEnterForegroundNotification = NSApplication.willBecomeActiveNotification
}

/// A refused menu choice's haptic on an iPhone. A Mac has no Taptic Engine in the keyboard; the
/// trackpad's haptic is the nearest thing.
final class UINotificationFeedbackGenerator {
    enum FeedbackType { case success, warning, error }
    func notificationOccurred(_ type: FeedbackType) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

/// VoiceOver's announcements, through AppKit's own.
enum UIAccessibility {
    enum Notification { case announcement }
    static func post(notification: Notification, argument: Any?) {
        guard let text = argument as? String else { return }
        let element: Any = NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
