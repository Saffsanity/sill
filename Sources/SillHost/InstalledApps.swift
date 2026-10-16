import Foundation

/// The Apps drawer's startup scan. FileManager and Bundle only; safe off the main actor.
enum InstalledApps {
    /// Sorted by display name, first bundle ID wins across the supplied roots.
    static func find(in directories: [URL]) -> [(name: String, bundleID: String, path: String)] {
        var seen: Set<String> = []
        var apps: [(name: String, bundleID: String, path: String)] = []
        for directory in directories {
            guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in entries {
                guard url.pathExtension == "app" else { continue }
                // Even an unrecognised or incomplete app is a boundary: its helpers
                // are not independently installed apps. Directory symlinks are not followed.
                entries.skipDescendants()
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                var display = FileManager.default.displayName(atPath: url.path)
                if display.hasSuffix(".app") { display.removeLast(4) }
                apps.append((display, id, url.path))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
