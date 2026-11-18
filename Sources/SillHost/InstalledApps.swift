import Foundation
import IOKit

/// Where the Apps list finds the Mac's apps: the bundles in each applications folder and in the
/// folders inside it, at any depth. Suites install each app in a folder of its own
/// (/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app), and the list missed every one of
/// them (#76); an app further down, like #135's /Applications/Adobe/Creative Suite/Photo.app, is
/// found too. It never looks inside a bundle, another package or a framework, so an app's own
/// helpers stay out, and never walks into a symbolic link or a Finder alias it finds in a folder,
/// so a link back up cannot loop (a folder it is given may itself be a link: see `find`). A link or
/// an alias that points at an app lists that app (`app(at:reach:)`; #370: an alias in /Applications
/// to an app on another disk).
///
/// The Mac's other disks (#370): the App Store's "Download and install large apps to a separate
/// disk" puts them in an Applications folder at the top of that disk, /Volumes/Drive/Applications.
/// `volumes` says which volumes are read, and `applicationFolders(on:)` which of their folders. The
/// catalog looks twice (WindowCatalog): first at this Mac's own disk alone (`Reach()`), then with
/// the volumes too, so a volume that is slow, asleep, or waits on macOS asking whether Sill may read
/// a removable volume never holds up the list of the Mac's own apps. The second look waits for a
/// device to connect (`secondLookDue`): the app asks for nothing at launch.
///
/// Threading: FileManager, Bundle, the mount table and the I/O Registry only, so any thread.
enum InstalledApps {
    typealias App = (name: String, bundleID: String, path: String)

    /// Sorted by display name; when two bundles share an ID, the first folder's wins, and within a
    /// folder the shallower one, then the one whose folders come first by name.
    static func find(in dirs: [String], reach: Reach = Reach()) -> [App] {
        var seen: Set<String> = []
        var apps: [App] = []
        for dir in dirs {
            // The folder itself may be a link (~/Applications on another disk, say): it is followed, as
            // before; the links inside it are not walked into. One that leads into the volumes waits
            // for the look that reads them.
            let folder = URL(fileURLWithPath: dir).resolvingSymlinksInPath()
            if reach.volumes == nil && inside(folder.path, reach.volumesRoot) { continue }
            for url in bundles(in: folder, reach: reach) {
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
    /// directly in `dir` first), by name within each folder; for a link or an alias, the app it
    /// points at.
    static func bundles(in dir: URL, reach: Reach = Reach()) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isAliasFileKey]
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
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    // A symbolic link or a Finder alias (macOS counts both as aliases): never walked into.
                    if values?.isAliasFile == true {
                        if let app = app(at: url, reach: reach) { found.append(app) }
                        continue
                    }
                    if url.pathExtension == "app" { found.append(url); continue }
                    // A plain folder only: not a package of another kind, and not a framework, a bundle
                    // that is no package (Sparkle's keeps an Updater.app inside).
                    guard url.pathExtension != "framework", let values,
                          values.isDirectory == true, values.isPackage != true else { continue }
                    next.append(url)
                }
            }
            level = next
        }
        return found
    }

    /// The app a link or an alias points at, at its own path with its links resolved, else nil. Where
    /// it points is read from the link or the alias itself first (`pointsAt`), so one that points
    /// where `reach` does not go is never looked up there: a disk asleep, a network share, a removable
    /// volume macOS has not let Sill read yet. An alias is resolved without UI and without mounting
    /// anything, so one whose disk is away is skipped at once.
    static func app(at link: URL, reach: Reach) -> URL? {
        guard let named = pointsAt(link), reach.allows(named),
              let resolved = try? URL(resolvingAliasFileAt: link, options: [.withoutUI, .withoutMounting])
        else { return nil }
        let target = resolved.resolvingSymlinksInPath()
        return target.pathExtension == "app" && reach.allows(target.path) ? target : nil
    }

    /// Where a link or an alias points, from it alone: a link's text (against its folder), an alias's
    /// bookmark's path. Nothing on the volume it names is looked up.
    static func pointsAt(_ link: URL) -> String? {
        if let text = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
            return URL(fileURLWithPath: text, relativeTo: link.deletingLastPathComponent()).standardizedFileURL.path
        }
        guard let bookmark = try? URL.bookmarkData(withContentsOf: link) else { return nil }
        return URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path
    }

    /// Which volumes a look reads. A volume is whatever is mounted in `volumesRoot` (/Volumes; a
    /// temporary folder in the check); anywhere else is this Mac's own disk, which every look reads.
    struct Reach {
        var volumesRoot = "/Volumes"
        /// The volumes read, by mount point (`volumes(_:root:)`). Nil for the first look, which reads
        /// none: a folder it is given that leads into `volumesRoot` waits for the second.
        var volumes: [String]?

        /// Whether a link or an alias found in a folder is followed to `path`.
        func allows(_ path: String) -> Bool {
            guard InstalledApps.inside(path, volumesRoot) else { return true }
            return volumes?.contains { InstalledApps.inside(path, $0) } == true
        }
    }

    /// Whether the second look is due (WindowCatalog asks at its start, when a device connects, and 2 s
    /// after a volume mounts, unmounts or is renamed): only while a device is connected, and only when
    /// the volumes of one's own (`own`, `volumes(_:root:)`) are not the ones the last second look was
    /// asked with (`asked`, nil before the first). Reading a removable volume can make macOS ask whether
    /// Sill may, and the app asks for nothing at launch (docs/steps/2026-09-23-menu-bar-app.md, "TCC:"):
    /// the question follows a device connecting, as Screen Recording's does. A disk image, a share or
    /// Time Machine's hourly snapshots coming and going bring none, and with no device connected no disk
    /// is read: a volume mounted meanwhile is read when the next device connects.
    static func secondLookDue(devices: Int, own: [String], asked: [String]?) -> Bool {
        devices > 0 && own != asked
    }

    /// `path` is `folder` or inside it, by name alone (nothing is looked up).
    static func inside(_ path: String, _ folder: String) -> Bool {
        let p = plain(path), f = plain(folder)
        return p == f || p.hasPrefix(f.hasSuffix("/") ? f : f + "/")
    }

    /// One name for one folder: a bookmark keeps /private/var/…, where Foundation's resolved links give
    /// /var/… as often.
    static func plain(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }

    // MARK: The Mac's other volumes (#370)

    /// A mounted volume, as the kernel's mount table gives it (`mounted()`).
    struct Volume: Equatable {
        var path: String        // where it is mounted
        var local: Bool         // on this Mac (MNT_LOCAL), not a network share
        var readOnly: Bool      // MNT_RDONLY: a disk image, a sealed system, a disc
        var browsable: Bool     // shown in Finder (no MNT_DONTBROWSE): Recovery and macOS's own are not
        var roles: [String]     // its APFS roles (System, Data, Recovery, Backup…); none for a volume of one's own
    }

    /// The volumes of one's own, which the second look reads, by mount point, sorted: each mounted
    /// directly in `root` under a name with no dot, local, writable, shown in Finder and with no APFS
    /// role. So never a network share, a disk image (an installer's is read-only), a disc, Recovery,
    /// macOS's own volumes, another Mac's system or data volume, or a Time Machine backup. From the
    /// mount table alone: nothing on a volume is read.
    static func volumes(_ mounted: [Volume], root: String = "/Volumes") -> [String] {
        mounted.filter { volume in
            let mount = URL(fileURLWithPath: volume.path)
            return plain(mount.deletingLastPathComponent().path) == plain(root) && !mount.lastPathComponent.hasPrefix(".")
                && volume.local && !volume.readOnly && volume.browsable && volume.roles.isEmpty
        }.map(\.path).sorted()
    }

    /// The Applications folder at the top of each of `volumes`, where it is a folder (an installer's
    /// disk image keeps a link to /Applications there) on a volume with no macOS of its own (an older
    /// Mac's disk, whose Applications are that Mac's).
    static func applicationFolders(on volumes: [String]) -> [String] {
        volumes.compactMap { volume in
            let folder = volume + "/Applications"
            var info = stat()
            guard lstat(folder, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  !FileManager.default.fileExists(atPath: volume + "/System/Library/CoreServices/SystemVersion.plist")
            else { return nil }
            return folder
        }
    }

    /// The kernel's mount table as it stands (getfsstat with MNT_NOWAIT: no file system is asked, so a
    /// network share that stopped answering holds nothing up), with each APFS volume's roles from the
    /// I/O Registry. Reads nothing on any volume.
    static func mounted() -> [Volume] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        let capacity = Int(count) + 8                  // room for a volume mounted meanwhile
        let table = UnsafeMutablePointer<statfs>.allocate(capacity: capacity)
        defer { table.deallocate() }
        let got = getfsstat(table, Int32(capacity * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        return UnsafeBufferPointer(start: table, count: Int(max(got, 0))).map { entry in
            let from = text(entry.f_mntfromname)
            return Volume(path: text(entry.f_mntonname), local: entry.f_flags & UInt32(MNT_LOCAL) != 0,
                          readOnly: entry.f_flags & UInt32(MNT_RDONLY) != 0,
                          browsable: entry.f_flags & UInt32(MNT_DONTBROWSE) == 0,
                          roles: from.hasPrefix("/dev/") ? roles(of: String(from.dropFirst("/dev/".count))) : [])
        }
    }

    /// A C string the mount table keeps in an array of fixed size.
    private static func text<T>(_ chars: T) -> String {
        withUnsafeBytes(of: chars) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// An APFS volume's roles, the I/O Registry's "Role" on its media (disk3s5: Data); none for any other.
    private static func roles(of bsdName: String) -> [String] {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return [] }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)   // consumes `matching`
        guard media != 0 else { return [] }
        defer { IOObjectRelease(media) }
        return IORegistryEntryCreateCFProperty(media, "Role" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String] ?? []
    }
}
