// InstalledApps (Sources/SillHost/InstalledApps.swift) on a fake applications folder, and on fake volumes (#370):
//
//   swiftc -O Sources/SillHost/InstalledApps.swift Tests/checks/installed-apps/main.swift \
//       -o .build/checks/installed-apps/check && .build/checks/installed-apps/check
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { print((ok ? "ok   " : "FAIL ") + what); if !ok { failures += 1 } }

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("installed-apps-\(UUID().uuidString)")
defer { try? fm.removeItem(at: root) }

/// A bundle Bundle(url:) reads: Contents/Info.plist with an identifier.
func app(_ path: String, id: String) {
    let contents = root.appendingPathComponent(path).appendingPathComponent("Contents")
    try! fm.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
    try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
}

app("Applications/Zed.app", id: "dev.zed")
app("Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app", id: "com.adobe.Photoshop")
app("Applications/Adobe Photoshop 2026/Uninstall Adobe Photoshop 2026.app", id: "com.adobe.uninstall")
app("Applications/Adobe/Creative Suite/Photo.app", id: "two.down")
app("Applications/Copy/Deeper/Zed.app", id: "dev.zed")
app("Applications/Thing.bundle/Inner.app", id: "in.package")
app("Applications/Suite/.Helper.app", id: "dot.app")
// Sparkle's framework keeps an Updater.app inside, and a framework is a bundle that is no package.
app("Applications/Suite/Sparkle.framework/Versions/B/Updater.app", id: "in.framework")
// One app twice at one depth, in sibling folders that APFS lists out of order ("right" first).
app("Applications/Twins/right/Twin.app", id: "twin")
app("Applications/Twins/left/Twin.app", id: "twin")
app("Applications/Zed.app/Contents/Helpers/Zed Helper.app", id: "dev.zed.helper")
app("Applications/.hidden/Secret.app", id: "hidden.app")
app("Applications/Copy/Zed.app", id: "dev.zed")
app("Elsewhere/Linked.app", id: "linked.app")
try! fm.createSymbolicLink(at: root.appendingPathComponent("Applications/Loop"), withDestinationURL: root.appendingPathComponent("Applications"))
try! fm.createSymbolicLink(at: root.appendingPathComponent("Applications/Linked"),
                           withDestinationURL: root.appendingPathComponent("Elsewhere"))
app("More/Alpha.app", id: "alpha")
// Like /Applications/Safari.app: a link to a bundle elsewhere, flagged hidden.
app("Cryptex/Safari.app", id: "com.apple.Safari")
let safari = root.appendingPathComponent("Applications/Safari.app")
try! fm.createSymbolicLink(at: safari, withDestinationURL: root.appendingPathComponent("Cryptex/Safari.app"))
_ = safari.path.withCString { lchflags($0, UInt32(UF_HIDDEN)) }

app("Volume/Apps/Beta.app", id: "beta")
try! fm.createSymbolicLink(at: root.appendingPathComponent("UserApps"), withDestinationURL: root.appendingPathComponent("Volume/Apps"))
let dirs = [root.appendingPathComponent("Applications").path, root.appendingPathComponent("More").path,
            root.appendingPathComponent("Missing").path, root.appendingPathComponent("UserApps").path]
// A home folder of its own: the first look stays out of the real one's rest, wherever TMPDIR is.
let home = root.appendingPathComponent("Home").path
let found = InstalledApps.find(in: dirs, reach: InstalledApps.Reach(home: home))
let ids = found.map(\.bundleID)
print(found.map { "\($0.name) (\($0.bundleID))" }.joined(separator: ", "))

check(ids.contains("dev.zed"), "an app directly in the folder is listed")
check(ids.contains("com.adobe.Photoshop") && ids.contains("com.adobe.uninstall"),
      "apps in a suite's folder one level down are listed (#76)")
check(ids.contains("two.down"), "an app two folders down is listed (#135's /Applications/Adobe/Creative Suite/Photo.app)")
check(!ids.contains("in.package"), "nothing inside a package of another kind is listed")
check(!ids.contains("in.framework"), "nothing inside a framework is listed")
check(!ids.contains("dot.app"), "a bundle whose name starts with a dot is skipped, at any depth")
check(!ids.contains("dev.zed.helper"), "nothing inside a bundle is listed")
check(!ids.contains("hidden.app"), "a folder whose name starts with a dot is skipped")
check(ids.contains("com.apple.Safari"), "a link to an app, flagged hidden like Safari's, is listed")
check(!ids.contains("linked.app"), "a symbolic link to a folder is not followed")
check(ids.filter { $0 == "dev.zed" }.count == 1, "two bundles with one ID are listed once")
check(found.first { $0.bundleID == "dev.zed" }?.path.hasSuffix("Applications/Zed.app") == true,
      "of two bundles with one ID, the one directly in the folder wins")
check(found.first { $0.bundleID == "twin" }?.path.hasSuffix("Twins/left/Twin.app") == true,
      "of two bundles with one ID at one depth, the one in the folder first by name wins")
check(ids.contains("alpha"), "every folder given is searched; a missing one is skipped")
check(ids.contains("beta"), "a folder given that is itself a link, as ~/Applications can be, is searched")
check(found.map(\.name) == found.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
      "sorted by display name")
check(found.first { $0.bundleID == "com.adobe.Photoshop" }?.name == "Adobe Photoshop 2026", "the name drops .app")
check(InstalledApps.find(in: [root.appendingPathComponent("Missing").path]).isEmpty, "a missing folder gives nothing")

// #370: the Mac's other volumes, mounted in a fake root/Volumes, and links and Finder aliases to apps.
// Nothing here touches the real /Volumes: every volume is a folder in the temporary directory, and the
// mount table is a list made up below.
let volumesRoot = root.appendingPathComponent("Volumes").path
func volume(_ name: String) -> String { volumesRoot + "/" + name }
/// A Finder alias as Finder makes one: a bookmark file.
func alias(_ path: String, to target: String) {
    let bookmark = try! root.appendingPathComponent(target)
        .bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
    try! URL.writeBookmarkData(bookmark, to: root.appendingPathComponent(path))
}
func link(_ path: String, to target: String) {
    let at = root.appendingPathComponent(path)
    try! fm.createDirectory(at: at.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! fm.createSymbolicLink(atPath: at.path, withDestinationPath: target)
}

app("Volumes/Drive/Applications/Ext.app", id: "ext.drive")
app("Volumes/Drive/Applications/Games/Deep.app", id: "ext.deep")
app("Volumes/Drive/Applications/Zed.app", id: "dev.zed")                 // this Mac's own copy wins
app("Volumes/Drive/Applications/Both.app", id: "both")
app("Volumes/Another/Applications/Both.app", id: "both")                // the volume first by name wins
app("Volumes/Drive/Elsewhere/Loose.app", id: "ext.loose")               // reached only through an alias
app("Volumes/Drive/MyApps/Mine.app", id: "ext.mine")                    // through a folder given as a link
app("Volumes/NoApps/Tools/Tool.app", id: "ext.tool")                    // a volume with no Applications folder
app("Volumes/Share/Applications/Net.app", id: "net.app")                 // a network share
app("Volumes/ReadOnly/Applications/RO.app", id: "ro.app")
app("Volumes/Installer/Installer.app", id: "installer.app")              // an installer's disk image: read-only,
link("Volumes/Installer/Applications", to: root.appendingPathComponent("Applications").path)   // a link to Applications
app("ImageApps/LinkedOnly.app", id: "image.linked")
link("Volumes/Writable Image/Applications", to: root.appendingPathComponent("ImageApps").path)  // writable; a link all the same
app("Volumes/Old Mac/Applications/OldOnly.app", id: "old.mac")           // an older Mac's disk, with its macOS
try! fm.createDirectory(at: root.appendingPathComponent("Volumes/Old Mac/System/Library/CoreServices"), withIntermediateDirectories: true)
try! Data().write(to: root.appendingPathComponent("Volumes/Old Mac/System/Library/CoreServices/SystemVersion.plist"))
app("Volumes/Old Mac - Data/Applications/DataOnly.app", id: "old.data")  // another Mac's data volume
app("Volumes/Backup/Applications/Backed.app", id: "backup.app")          // a Time Machine backup
app("Volumes/Recovery/Applications/Rec.app", id: "recovery.app")         // not shown in Finder
app("Volumes/.hidden/Applications/Dot.app", id: "dot.volume")
app("Volumes/Nested/Deeper/Applications/NestedApp.app", id: "nested.volume")   // mounted deeper than root/Volumes
app("Mnt/Applications/MntApp.app", id: "mnt.volume")                     // mounted outside it

// In this Mac's own folders: links and aliases.
app("Elsewhere2/Home.app", id: "home.alias")
alias("Applications/Home alias", to: "Elsewhere2/Home.app")
app("Elsewhere2/HomeLinked.app", id: "home.link")
link("Applications/HomeLink", to: "../Elsewhere2/HomeLinked.app")
app("Elsewhere2/Named.app", id: "named.alias")
alias("Applications/Named.app", to: "Elsewhere2/Named.app")                // an alias named like an app
app("Elsewhere2/Inner.app", id: "inner.alias")
alias("Applications/Suite/Inner alias", to: "Elsewhere2/Inner.app")       // a folder down
app("Elsewhere2/Plugin.bundle", id: "a.plugin")
alias("Applications/Plugin alias", to: "Elsewhere2/Plugin.bundle")        // a bundle that is no app
alias("Applications/Folder alias", to: "Elsewhere")                       // a folder (Linked.app is in it)
app("Elsewhere2/Gone.app", id: "gone.alias")
alias("Applications/Gone alias", to: "Elsewhere2/Gone.app")
try! fm.removeItem(at: root.appendingPathComponent("Elsewhere2/Gone.app"))  // its app deleted since
alias("Applications/Ext alias", to: "Volumes/Drive/Applications/Ext.app")  // the app the drive's folder lists too
alias("Applications/Loose alias", to: "Volumes/Drive/Elsewhere/Loose.app")
alias("Applications/Net alias", to: "Volumes/Share/Applications/Net.app")
link("Applications/Tool link", to: volume("NoApps/Tools/Tool.app"))
// An alias made to an app on the drive whose app moved to this Mac's disk since: the alias's own
// record names the drive, which decides before anything is resolved (resolving finds it moved).
app("Volumes/Drive/Elsewhere/Moved.app", id: "moved.alias")
alias("Applications/Moved alias", to: "Volumes/Drive/Elsewhere/Moved.app")
try! fm.moveItem(at: root.appendingPathComponent("Volumes/Drive/Elsewhere/Moved.app"),
                 to: root.appendingPathComponent("Elsewhere2/Moved.app"))
// A link whose text names the drive and leads back to this Mac's disk through a link there, and one
// whose text names this Mac's disk and leads onto the drive.
link("Volumes/Drive/Hop", to: root.appendingPathComponent("Elsewhere2").path)
app("Elsewhere2/HopApp.app", id: "hop.app")
link("Applications/Hop link", to: volume("Drive/Hop/HopApp.app"))
link("Elsewhere2/ToDrive", to: volume("Drive/Elsewhere"))
app("Volumes/Drive/Elsewhere/Via.app", id: "via.app")
link("Applications/Via link", to: root.appendingPathComponent("Elsewhere2/ToDrive/Via.app").path)
// ~/Applications on the drive: a folder given that is a link into the volumes.
link("HomeApps", to: volume("Drive/MyApps"))
// The home folder: the first look reads its Applications folder alone. A link or an alias into the rest of
// it (Desktop, Documents, Downloads, iCloud Drive: macOS may ask whether Sill may, or fetch from the cloud)
// waits for the second look, as does a folder given that leads there.
app("Home/Applications/Kept.app", id: "home.kept")
link("Applications/Kept link", to: home + "/Applications/Kept.app")
app("Home/Downloads/Dl.app", id: "home.downloads")
alias("Applications/Dl alias", to: "Home/Downloads/Dl.app")
app("Home/Developer/Built.app", id: "home.built")
link("Applications/Built.app", to: home + "/Developer/Built.app")      // named like an app: main read it at launch
app("Home/Library/CloudStorage/Apps/Cloud.app", id: "home.cloud")
link("CloudApps", to: home + "/Library/CloudStorage/Apps")

func mount(_ path: String, local: Bool = true, readOnly: Bool = false, browsable: Bool = true,
           roles: [String] = []) -> InstalledApps.Volume {
    InstalledApps.Volume(path: path, local: local, readOnly: readOnly, browsable: browsable, roles: roles)
}
// Out of order on purpose: the volumes come back sorted.
let mounted = [
    mount("/", readOnly: true), mount(volume("Drive")), mount(volume("Share"), local: false),
    mount(volume("ReadOnly"), readOnly: true), mount(volume("Installer"), readOnly: true), mount(volume("Writable Image")),
    mount(volume("Old Mac")), mount(volume("Old Mac - Data"), roles: ["Data"]), mount(volume("Backup"), roles: ["Backup"]),
    mount(volume("Recovery"), browsable: false), mount(volume(".hidden")), mount(volume("Nested/Deeper")),
    mount(root.appendingPathComponent("Mnt").path), mount(volume("NoApps")), mount(volume("Another")),
]
let own = InstalledApps.volumes(mounted, root: volumesRoot)
let read = InstalledApps.applicationFolders(on: own)
let given = [root.appendingPathComponent("Applications").path, root.appendingPathComponent("HomeApps").path,
             root.appendingPathComponent("CloudApps").path]
let first = InstalledApps.find(in: given, reach: InstalledApps.Reach(volumesRoot: volumesRoot, home: home))
let second = InstalledApps.find(in: given + read, reach: InstalledApps.Reach(volumesRoot: volumesRoot, home: home, volumes: own))
let firstIDs = Set(first.map(\.bundleID)), secondIDs = second.map(\.bundleID)
print("first look: " + first.map(\.bundleID).joined(separator: ", "))
print("second look: " + secondIDs.joined(separator: ", "))
func path(_ id: String, in apps: [InstalledApps.App]) -> String { apps.first { $0.bundleID == id }?.path ?? "none" }

check(own == ["Another", "Drive", "NoApps", "Old Mac", "Writable Image"].map(volume),
      "the volumes of one's own: directly in /Volumes, no dot name, local, writable, shown in Finder, no APFS role; sorted")
check(read == [volume("Another/Applications"), volume("Drive/Applications")],
      "their Applications folders: a folder, not a link, on a volume with no macOS of its own")
check(secondIDs.contains("ext.drive") && secondIDs.contains("ext.deep"),
      "the apps in a volume's Applications folder are listed, at any depth (#370)")
let offVolumes = ["ext.drive", "ext.deep", "ext.loose", "ext.tool", "ext.mine", "moved.alias", "hop.app", "via.app"]
check(firstIDs.isDisjoint(with: offVolumes), "the first look reads nothing on another volume")
check(["home.alias", "home.link", "named.alias", "inner.alias"].allSatisfy { firstIDs.contains($0) },
      "an alias or a link to an app on this Mac's disk lists it, a folder down too, an alias named like an app too")
check(path("home.alias", in: first).hasSuffix("Elsewhere2/Home.app") && path("home.link", in: first).hasSuffix("Elsewhere2/HomeLinked.app"),
      "listed at the app's own path")
check(secondIDs.contains("ext.loose") && secondIDs.contains("ext.tool"),
      "an alias or a link to an app on a volume of one's own lists it, with or without an Applications folder there")
check(secondIDs.contains("ext.mine"), "a folder given that leads into the volumes is read by the second look")
check(secondIDs.filter { $0 == "ext.drive" }.count == 1 && path("ext.drive", in: second).hasSuffix("Volumes/Drive/Applications/Ext.app"),
      "an app reached by its folder and by an alias is listed once, at its own path")
check(!path("dev.zed", in: second).contains("/Volumes/"), "of one app on this Mac and on a volume, this Mac's copy wins")
check(path("both", in: second).contains("/Volumes/Another/"), "of one app on two volumes, the volume first by name wins")
check(!firstIDs.contains("moved.alias") && secondIDs.contains("moved.alias"),
      "where an alias points is read from the alias before it is resolved: not on the first look")
check(!firstIDs.contains("hop.app") && secondIDs.contains("hop.app"),
      "where a link points is read from its text before it is resolved: not on the first look")
check(!firstIDs.contains("via.app") && secondIDs.contains("via.app"), "where a link resolves to counts too")
let never = ["net.app", "ro.app", "installer.app", "image.linked", "old.mac", "old.data", "backup.app", "recovery.app",
             "dot.volume", "nested.volume", "mnt.volume"]
check(firstIDs.isDisjoint(with: never) && Set(secondIDs).isDisjoint(with: never),
      "nothing on a share, a read-only, hidden or nested volume, one with a role or a macOS, or behind a link at the top")
check(!secondIDs.contains("a.plugin") && !secondIDs.contains("linked.app") && !secondIDs.contains("gone.alias"),
      "an alias to a bundle that is no app, to a folder, or whose app is gone lists nothing")
check(firstIDs.contains("home.kept"), "the first look follows a link into the home folder's Applications folder")
check(!firstIDs.contains("home.downloads") && secondIDs.contains("home.downloads"),
      "an alias into the rest of the home folder (Downloads) waits for the second look: nothing asked at launch")
check(!firstIDs.contains("home.built") && secondIDs.contains("home.built"), "so does a link there named like an app")
check(!firstIDs.contains("home.cloud") && secondIDs.contains("home.cloud"),
      "a folder given that leads into the home folder past its Applications folder is read by the second look")
check(InstalledApps.mounted().contains { $0.path == "/" && $0.local }, "the kernel's mount table is read: / is there, local")

// When the second look is due: it can make macOS ask whether Sill may read a removable volume, and the
// app asks for nothing at launch, so it follows a device connecting; then only when the volumes changed.
let drive = [volume("Drive")], both = [volume("Another"), volume("Drive")]
check(!InstalledApps.secondLookDue(devices: 0, own: drive, asked: nil),
      "no second look before a device connects: nothing is asked at launch")
check(InstalledApps.secondLookDue(devices: 1, own: drive, asked: nil), "the first device to connect brings it")
check(InstalledApps.secondLookDue(devices: 1, own: [], asked: nil),
      "also with no volume of one's own (a folder given may lead into the volumes)")
check(!InstalledApps.secondLookDue(devices: 2, own: drive, asked: drive),
      "a device, a disk image, a share or a Time Machine snapshot that leaves the volumes as they were brings none")
check(InstalledApps.secondLookDue(devices: 1, own: [], asked: drive) && InstalledApps.secondLookDue(devices: 1, own: both, asked: drive),
      "a volume gone or mounted while a device is connected brings one")
check(!InstalledApps.secondLookDue(devices: 0, own: both, asked: drive),
      "a volume mounted with no device connected waits for the next device (no disk read meanwhile)")
// exit() skips the top-level defer, so the fake folder goes first.
try? fm.removeItem(at: root)
if failures > 0 { print("installed-apps: \(failures) failed"); exit(1) }
print("installed-apps: every check passed")
