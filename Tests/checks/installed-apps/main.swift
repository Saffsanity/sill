// InstalledApps (Sources/SillHost/InstalledApps.swift) on a fake applications folder:
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
let found = InstalledApps.find(in: dirs)
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

// WindowFollowPolicy: RAIL-style child/dialog window following and return-on-close.
do {
    var follow = WindowFollowPolicy()
    let w1: (id: UInt32, bundleID: String) = (101, "com.apple.Safari")
    let w2: (id: UInt32, bundleID: String) = (102, "com.apple.Safari")
    let other: (id: UInt32, bundleID: String) = (201, "com.apple.Terminal")
    check(follow.poll(windows: [w1, other], activeWindowID: 101, now: 10, lastActivityAt: 10) == nil,
          "first poll seeds known windows without switching")
    check(follow.poll(windows: [w1, other, (202, "com.apple.Terminal")], activeWindowID: 101, now: 11, lastActivityAt: 10) == nil,
          "a new window from another app is not followed")
    check(follow.poll(windows: [w1, w2, other], activeWindowID: 101, now: 20, lastActivityAt: 10) == nil,
          "a new window from the same app more than 5 s after device activity is not followed")
    // Seed again with w1 + other, then open w2 within 5 s of activity:
    var activeFollow = WindowFollowPolicy()
    _ = activeFollow.poll(windows: [w1, other], activeWindowID: 101, now: 10, lastActivityAt: 10)
    check(activeFollow.poll(windows: [w1, w2, other], activeWindowID: 101, now: 12, lastActivityAt: 10) == 102,
          "a new window from the streamed app within 5 s of device activity is followed")
    check(activeFollow.parentStack == [101], "the parent window is pushed onto the return stack")
    check(activeFollow.poll(windows: [w1, other], activeWindowID: 102, now: 18, lastActivityAt: 10) == 101,
          "closing the child window returns to the parent window")
    check(activeFollow.parentStack.isEmpty, "the return stack is popped when returning to the parent")
    _ = activeFollow.poll(windows: [w1, w2, other], activeWindowID: 101, now: 20, lastActivityAt: 19)
    activeFollow.reset()
    check(activeFollow.parentStack.isEmpty, "an explicit user pick clears the return stack")
}

// exit() skips the top-level defer, so the fake folder goes first.
try? fm.removeItem(at: root)
if failures > 0 { print("installed-apps: \(failures) failed"); exit(1) }
print("installed-apps: every check passed")
