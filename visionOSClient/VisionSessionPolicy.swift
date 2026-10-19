import Foundation

/// Deferred system Paste reads may finish after a session replacement. They belong only to
/// the connected session whose control was presented, never to the next Mac/session.
enum VisionSessionPolicy {
    /// The system has already opened the app. A launch link must not change its session,
    /// selected source, or pending pairing confirmation.
    static func isLaunchURL(_ url: URL) -> Bool {
        switch url.absoluteString.lowercased() {
        case "sill://", "sill:///", "sill://open", "sill://open/": return true
        default: return false
        }
    }

    static func acceptsCompletion(startedAt: Date?, currentAt: Date?, connected: Bool) -> Bool {
        connected && startedAt != nil && startedAt == currentAt
    }
}
