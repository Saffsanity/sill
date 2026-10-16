// InstalledApps (Sources/SillHost/InstalledApps.swift) on a fake applications folder:
//
//   swiftc -O Sources/SillHost/InstalledApps.swift Tests/checks/installed-apps/main.swift \
//       -o .build/checks/installed-apps/check && .build/checks/installed-apps/check
import Foundation

func check(_ ok: Bool, _ what: String) { print((ok ? "ok   " : "FAIL ") + what); if !ok { exit(1) } }

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
app("Applications/Microsoft/Office/Word.app", id: "too.deep")
app("Applications/Zed.app/Contents/Helpers/Zed Helper.app", id: "dev.zed.helper")
app("Applications/.hidden/Secret.app", id: "hidden.app")
app("Applications/Copy/Zed.app", id: "dev.zed")
app("Elsewhere/Linked.app", id: "linked.app")
try! fm.createSymbolicLink(at: root.appendingPathComponent("Applications/Linked"),
                           withDestinationURL: root.appendingPathComponent("Elsewhere"))
app("More/Alpha.app", id: "alpha")
// Like /Applications/Safari.app: a link to a bundle elsewhere, flagged hidden.
app("Cryptex/Safari.app", id: "com.apple.Safari")
let safari = root.appendingPathComponent("Applications/Safari.app")
try! fm.createSymbolicLink(at: safari, withDestinationURL: root.appendingPathComponent("Cryptex/Safari.app"))
_ = safari.path.withCString { lchflags($0, UInt32(UF_HIDDEN)) }

let dirs = [root.appendingPathComponent("Applications").path, root.appendingPathComponent("More").path,
            root.appendingPathComponent("Missing").path]
let found = InstalledApps.find(in: dirs)
let ids = found.map(\.bundleID)
print(found.map { "\($0.name) (\($0.bundleID))" }.joined(separator: ", "))

check(ids.contains("dev.zed"), "an app directly in the folder is listed")
check(ids.contains("com.adobe.Photoshop") && ids.contains("com.adobe.uninstall"),
      "apps in a suite's folder one level down are listed (#76)")
check(!ids.contains("too.deep"), "a folder two levels down is left alone")
check(!ids.contains("dev.zed.helper"), "nothing inside a bundle is listed")
check(!ids.contains("hidden.app"), "a folder whose name starts with a dot is skipped")
check(ids.contains("com.apple.Safari"), "a link to an app, flagged hidden like Safari's, is listed")
check(!ids.contains("linked.app"), "a symbolic link to a folder is not followed")
check(ids.filter { $0 == "dev.zed" }.count == 1, "two bundles with one ID are listed once")
check(found.first { $0.bundleID == "dev.zed" }?.path.hasSuffix("Applications/Zed.app") == true,
      "of two bundles with one ID, the one directly in the folder wins")
check(ids.contains("alpha"), "every folder given is searched; a missing one is skipped")
check(found.map(\.name) == found.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
      "sorted by display name")
check(found.first { $0.bundleID == "com.adobe.Photoshop" }?.name == "Adobe Photoshop 2026", "the name drops .app")
check(InstalledApps.find(in: [root.appendingPathComponent("Missing").path]).isEmpty, "a missing folder gives nothing")
print("installed-apps: every check passed")
