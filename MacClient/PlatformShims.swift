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

/// The app's state and the UIApplication notifications the shared client listens for. A Mac app is
/// never suspended: "back to the foreground" is the app becoming active again, "the background" its
/// windows hidden.
final class UIApplication {
    enum State { case active, inactive, background }
    static let shared = UIApplication()
    var applicationState: State { NSApp?.isActive == true ? .active : .inactive }

    static let willEnterForegroundNotification = NSApplication.willBecomeActiveNotification
    static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    static let willResignActiveNotification = NSApplication.willResignActiveNotification
    static let didEnterBackgroundNotification = NSApplication.didHideNotification
}

/// A Mac app has no scenes to activate: the app's own activation (above) stands for them.
enum UIScene {
    static let didActivateNotification = Notification.Name("me.saffer.sill.viewer.noScene")
}

/// The general pasteboard, as the clipboard's shared code (StreamClient+Clipboard) uses UIPasteboard:
/// its change count, whether it holds text, and writing text. Reading the text itself happens only
/// through SwiftUI's PasteButton, on a Mac as on iOS.
final class UIPasteboard {
    struct OptionsKey: Hashable {
        let name: String
        static let localOnly = OptionsKey(name: "localOnly")
        static let expirationDate = OptionsKey(name: "expirationDate")
    }

    static let general = UIPasteboard()
    private let board = NSPasteboard.general

    var changeCount: Int { board.changeCount }
    var hasStrings: Bool { board.availableType(from: [.string]) != nil }

    /// Writes the items' text. `localOnly` and `expirationDate` are iOS's; a Mac's pasteboard keeps
    /// text until something replaces it, and Universal Clipboard only carries what was copied by hand.
    func setItems(_ items: [[String: Any]], options: [OptionsKey: Any] = [:]) {
        board.clearContents()
        for item in items {
            for (_, value) in item {
                if let text = value as? String { board.setString(text, forType: .string) }
            }
        }
    }
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
    static let voiceOverStatusDidChangeNotification = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
    static var isVoiceOverRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }
    static func post(notification: Notification, argument: Any?) {
        guard let text = argument as? String else { return }
        let element: Any = NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The iPad's Settings panel answers whether VoiceOver runs (the clipboard chip's clock stops under
/// it); on a Mac, VoiceOver's own switch.
enum HostSettingsPanel {
    static var voiceOverRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }
}
