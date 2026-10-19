import Foundation
import CoreGraphics

/// Bounded numeric evidence only: no titles, source IDs, images, hosts or network content.
/// The utility queue owns the ring and file, so scene updates never perform disk I/O.
enum VisionGeometryDiagnostics {
    private struct Event: Codable, Sendable {
        let timestamp: Double
        let phase: Int
        let scene: Int
        let sourceKind: Int
        let sourceWidth: Double?
        let sourceHeight: Double?
        let actualWidth: Double?
        let actualHeight: Double?
        let requestedWidth: Double?
        let requestedHeight: Double?
        let restriction: Int?
        let errorCode: Int?
    }
    private static let queue = DispatchQueue(label: "me.saffer.sill.geometry-diagnostics", qos: .utility)
    private static var events: [Event] = [] // Accessed only on queue.
    private static var sceneCounter = 0 // Accessed only on main actor.

    @MainActor static func nextScene() -> Int {
        sceneCounter += 1
        return sceneCounter
    }

    static func record(phase: Int, scene: Int = 0, sourceKind: Int,
                       source: CGSize? = nil, actual: CGSize? = nil, requested: CGSize? = nil,
                       restriction: Int? = nil, errorCode: Int? = nil) {
        func dimension(_ value: CGFloat?) -> Double? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return Double(value)
        }
        let event = Event(timestamp: Date().timeIntervalSince1970, phase: phase, scene: scene,
                          sourceKind: sourceKind, sourceWidth: dimension(source?.width),
                          sourceHeight: dimension(source?.height), actualWidth: dimension(actual?.width),
                          actualHeight: dimension(actual?.height), requestedWidth: dimension(requested?.width),
                          requestedHeight: dimension(requested?.height), restriction: restriction, errorCode: errorCode)
        queue.async {
            events.append(event)
            if events.count > 30 { events.removeFirst(events.count - 30) }
            guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  let data = try? JSONEncoder().encode(events) else { return }
            try? data.write(to: cache.appendingPathComponent("SillWindowGeometry.json"), options: .atomic)
        }
    }
}
