import Foundation

/// Where the Apps list finds the Mac's apps: the bundles in each applications folder and in the
/// folders inside it, at any depth. Suites install each app in a folder of its own
/// (/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app), and the list missed every one of
/// them (#76); an app further down, like #135's /Applications/Adobe/Creative Suite/Photo.app, is
/// found too. It never looks inside a bundle, another package or a framework, so an app's own
/// helpers stay out, and never follows a symbolic link it finds in a folder, so a link back up
/// cannot loop (a folder it is given may itself be a link: see `find`).
///
/// Threading: FileManager and Bundle only, so any thread.
enum InstalledApps {
    /// Sorted by display name; when two bundles share an ID, the first folder's wins, and within a
    /// folder the shallower one, then the one whose folders come first by name.
    static func find(in dirs: [String]) -> [(name: String, bundleID: String, path: String)] {
        var seen: Set<String> = []
        var apps: [(name: String, bundleID: String, path: String)] = []
        for dir in dirs {
            // The folder itself may be a link (~/Applications on another disk, say): it is followed, as
            // before; the links inside it are not.
            for url in bundles(in: URL(fileURLWithPath: dir).resolvingSymlinksInPath()) {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                var display = FileManager.default.displayName(atPath: url.path)
                if display.hasSuffix(".app") { display.removeLast(4) }
                apps.append((display, id, url.path))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The .app bundles in `dir` and in its folders at any depth, a level at a time (the bundles
    /// directly in `dir` first), by name within each folder.
    static func bundles(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var found: [URL] = []
        var level = [dir]
        while !level.isEmpty {
            var next: [URL] = []
            for folder in level {
                // Dot names only: macOS flags /Applications/Safari.app, a link into its cryptex, as hidden.
                guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
                else { continue }
                let sorted = entries.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                for url in sorted {
                    if url.pathExtension == "app" { found.append(url); continue }
                    // A plain folder only: not a symbolic link, not a package of another kind, and not a
                    // framework, a bundle that is no package (Sparkle's keeps an Updater.app inside).
                    guard url.pathExtension != "framework", let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isDirectory == true, values.isPackage != true else { continue }
                    next.append(url)
                }
            }
            level = next
        }
        return found
    }
}
