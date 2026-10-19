import Foundation
import SwiftUI
import StreamProtocol

/// Scene values contain an opaque random ID only. Trusted connection seeds stay in memory and
/// expire if the system never opens the requested scene. Restored scenes resolve their paired
/// Mac/source descriptor from SceneStorage, never from a persisted connection seed.
@MainActor
final class VisionWindowLaunches {
    static let shared = VisionWindowLaunches()
    private var pending: [UUID: (seed: VisionWindowSeed, created: Date)] = [:]

    func register(_ seed: VisionWindowSeed) -> UUID {
        let now = Date()
        pending = pending.filter { now.timeIntervalSince($0.value.created) < 60 }
        let id = UUID()
        pending[id] = (seed, now)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            pending[id] = nil
        }
        return id
    }

    func seed(for id: UUID) -> VisionWindowSeed? {
        guard let entry = pending[id], Date().timeIntervalSince(entry.created) < 60 else { return nil }
        return entry.seed
    }

    func discard(_ id: UUID) { pending[id] = nil }
}

private struct OpenSpatialSourceKey: EnvironmentKey {
    static let defaultValue: ((StreamSource) -> Void)? = nil
}

private struct SpatialSourceCanOpenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var openSpatialSource: ((StreamSource) -> Void)? {
        get { self[OpenSpatialSourceKey.self] }
        set { self[OpenSpatialSourceKey.self] = newValue }
    }
    var spatialSourceCanOpen: Bool {
        get { self[SpatialSourceCanOpenKey.self] }
        set { self[SpatialSourceCanOpenKey.self] = newValue }
    }
}
