import Foundation
import CoreGraphics

/// Fresh off-Space windows are eligible only when their state can be identified safely.
enum WindowCatalogPolicy {
    static func includesOffscreen(appHidden: Bool?, minimized: Bool?) -> Bool {
        appHidden == false && minimized == false
    }

    /// Every app gets its own probe, with at most four probes running at once. A slow early
    /// app cannot starve a later app by spending a shared deadline. The probe bounds its own IPC.
    static func scanApps<App: Sendable>(_ apps: [App],
                                       probe: @escaping @Sendable (App) -> Set<UInt32>) async -> Set<UInt32> {
        let workers = min(4, apps.count)
        return await withTaskGroup(of: Set<UInt32>.self) { group in
            for worker in 0..<workers {
                group.addTask {
                    var result = Set<UInt32>()
                    for index in stride(from: worker, to: apps.count, by: workers) {
                        result.formUnion(probe(apps[index]))
                    }
                    return result
                }
            }
            var all = Set<UInt32>()
            for await result in group { all.formUnion(result) }
            return all
        }
    }

    /// Public APIs do not map a window-server ID to an AX element. Only a unique frame match
    /// among a complete set is safe here: minimized state must belong to the actual SCWindow.
    static func uniqueFrameMatch(_ frame: CGRect, in candidates: [CGRect?]) -> Int? {
        guard frame.width > 0, frame.height > 0, !candidates.contains(where: { $0 == nil }) else { return nil }
        let matches = candidates.indices.filter { index in
            guard let other = candidates[index] else { return false }
            return abs(frame.minX - other.minX) <= 4 && abs(frame.minY - other.minY) <= 4
                && abs(frame.width - other.width) <= 4 && abs(frame.height - other.height) <= 4
        }
        return matches.count == 1 ? matches.first : nil
    }
}
