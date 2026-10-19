import Foundation

/// Numeric evidence only. No native/logical IDs, Mac identity, source title, routes, or keys.
/// The serial queue owns the bounded ring and atomic cache writes, off the UI thread.
enum VisionSceneRecoveryDiagnostics {
    enum Kind: Int {
        case processStart = 0, connect = 1, activate = 2, background = 3, disconnect = 4
        case discard = 5, settled = 6, saveAccepted = 7, saveDeclined = 8, clear = 9
        case reopenCycle = 10, replayAttempt = 11, replayRequested = 12, replayDeclined = 13
        case replayDeferred = 14, replayAccepted = 15
        case unmatchedActivate = 16, unmatchedBackground = 17, unmatchedDisconnect = 18, unmatchedInactive = 19
    }
    private struct Event: Codable, Sendable {
        var timestamp: Double
        var event: Int
        var secondary: Bool
        var members: Int
        var descriptors: Int
        var foreground: Int
        var bound: Int
        var error: Int?
    }
    private static let queue = DispatchQueue(label: "me.saffer.sill.scene-recovery-diagnostics", qos: .utility)
    private static var events: [Event] = []
    static func record(_ kind: Kind, secondary: Bool, members: Int, descriptors: Int,
                       foreground: Int, bound: Int, error: Int?) {
        let event = Event(timestamp: Date().timeIntervalSince1970, event: kind.rawValue,
                          secondary: secondary, members: members, descriptors: descriptors,
                          foreground: foreground, bound: bound, error: error)
        queue.async {
            if events.isEmpty, let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
               let data = try? Data(contentsOf: cache.appendingPathComponent("SillSceneRecovery.json")),
               let old = try? JSONDecoder().decode([Event].self, from: data) { events = Array(old.suffix(59)) }
            events.append(event)
            if events.count > 60 { events.removeFirst(events.count - 60) }
            guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  let data = try? JSONEncoder().encode(events) else { return }
            try? data.write(to: cache.appendingPathComponent("SillSceneRecovery.json"), options: .atomic)
        }
    }
}
