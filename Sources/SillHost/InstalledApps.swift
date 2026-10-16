import Foundation

/// Where the Apps list finds the Mac's apps: the bundles in each applications folder and in the
/// folders inside it, one level down, the way Launchpad and Spotlight show them. Suites install
/// each app in a folder of its own (/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app),
/// and the list missed every one of them (#76). It never looks inside a bundle, so an app's own
/// helpers stay out, and a folder deeper than one level is left alone.
///
/// Threading: FileManager and Bundle only, so any thread.
enum InstalledApps {
    /// Sorted by display name; when two bundles share an ID, the first folder's wins.
    static func find(in dirs: [String]) -> [(name: String, bundleID: String, path: String)] {
        var seen: Set<String> = []
        var apps: [(name: String, bundleID: String, path: String)] = []
        for dir in dirs {
            for url in bundles(in: URL(fileURLWithPath: dir)) {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                var display = FileManager.default.displayName(atPath: url.path)
                if display.hasSuffix(".app") { display.removeLast(4) }
                apps.append((display, id, url.path))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The .app bundles directly in `dir` first, then those in its folders, by name.
    static func bundles(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        // Dot names only: macOS flags /Applications/Safari.app, a link into its cryptex, as hidden.
        guard let top = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])
        else { return [] }
        let sorted = top.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var direct: [URL] = []
        var nested: [URL] = []
        for url in sorted {
            if url.pathExtension == "app" { direct.append(url); continue }
            // A plain folder only: not a symbolic link, not a package of another kind.
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isPackage != true else { continue }
            let inner = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
            nested += inner.filter { $0.pathExtension == "app" && !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return direct + nested
    }
}
