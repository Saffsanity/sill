// CatalogWindows (Sources/SillHost/CatalogWindows.swift): which on-screen windows the catalog lists,
// the tiles in a device's window strip (issue #114).
//
//   swiftc -O Sources/SillHost/CatalogWindows.swift Tests/checks/catalog-windows/main.swift \
//       -o .build/checks/catalog-windows/check && .build/checks/catalog-windows/check
import Foundation

var failures = 0
var cases = 0
func check(_ ok: Bool, _ what: String) {
    cases += 1
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}

let own: Int32 = 4242
typealias W = CatalogWindows.Window
func win(_ title: String?, app: String?, bundle: String?, pid: Int32 = 100, layer: Int = 0,
         _ width: Double = 800, _ height: Double = 600) -> W {
    W(title: title, appName: app, bundleID: bundle, pid: pid, layer: layer, width: width, height: height)
}
func lists(_ w: W) -> Bool { CatalogWindows.lists(w, ownPID: own) }
/// The catalog's filter on main before issue #114 (WindowCatalog.refreshWindows at 35a9c47c).
func listedBefore(_ w: W) -> Bool {
    CatalogWindows.isAppWindow(w, ownPID: own) && !(w.title ?? "").lowercased().contains("layerprobe")
}

// MARK: An app's window: owner, layer, size, process (the filter before #114, unchanged)

let doc = win("Report.pages", app: "Pages", bundle: "com.apple.iWork.Pages")
check(lists(doc), "an app's titled window on layer 0 is listed")
check(!lists(win("Doc", app: nil, bundle: nil)), "a window without an owning application is not")
check(!lists(win("Menubar", app: "", bundle: "", pid: 416, layer: 24, 2560, 30)),
      "the window server's own windows (an owner with no name, macOS 27) are not")
check(!lists(win("Backstop", app: "", bundle: "", pid: 416)),
      "nor on layer 0: the owner's name is what keeps them out")
for (layer, what) in [(-2147483603, "the desktop's icons (Finder)"), (-2147483624, "the wallpaper"),
                      (-2147483601, "widgets"), (20, "the Dock's layer"), (24, "the menu bar's layer"),
                      (2147483630, "the cursor's layer"), (1, "layer 1"), (-1, "layer -1")] {
    check(!lists(win("", app: "Finder", bundle: "com.apple.finder", layer: layer)), "\(what) (\(layer)) is not listed")
}
check(!lists(win("Tiny", app: "Pages", bundle: "com.apple.iWork.Pages", 100, 600)), "100 points wide is too small")
check(lists(win("Tiny", app: "Pages", bundle: "com.apple.iWork.Pages", 101, 600)), "101 points wide is listed")
check(!lists(win("Tiny", app: "Pages", bundle: "com.apple.iWork.Pages", 600, 100)), "100 points tall is too small")
check(lists(win("Tiny", app: "Pages", bundle: "com.apple.iWork.Pages", 600, 101)), "101 points tall is listed")
check(!lists(win("", app: "BetterDisplay", bundle: "pro.betterdisplay.BetterDisplay", 1, 1)),
      "a menu bar app's 1 × 1 window is not")
check(!lists(win("Pair iPad", app: "Sill", bundle: "me.saffer.sill.mac", pid: own)),
      "Sill's own windows (the pairing window with its code) are not")
check(lists(win("Pair iPad", app: "Sill", bundle: "me.saffer.sill.mac", pid: own + 1)),
      "another process's window of the same name is")

// MARK: LayerProbeParent (left out before #114 too)

check(CatalogWindows.helper(win("LayerProbeParent", app: "TextEdit", bundle: "com.apple.TextEdit")) == .layerProbe,
      "LayerProbeParent is a helper's window")
check(!lists(win("LayerProbeParent", app: "TextEdit", bundle: "com.apple.TextEdit")), "and is not listed")
check(!lists(win("xLAYERPROBEx", app: "Notes", bundle: "com.apple.Notes")), "in any case, anywhere in the title")
check(lists(win("Layer Probe notes", app: "Notes", bundle: "com.apple.Notes")), "but not a title that only looks like it")

// MARK: macOS's own interface (#114), whatever the title

let systemOwners = ["com.apple.WindowManager", "com.apple.dock", "com.apple.controlcenter",
                    "com.apple.systemuiserver", "com.apple.notificationcenterui", "com.apple.screencaptureui"]
for id in systemOwners {
    check(CatalogWindows.helper(win("", app: "x", bundle: id)) == .systemInterface, "\(id) is macOS's own interface")
    check(!lists(win("", app: "x", bundle: id)), "an untitled window of \(id) on layer 0 is not listed")
    check(!lists(win("Strip", app: "x", bundle: id)), "nor a titled one of \(id)")
}
check(CatalogWindows.systemInterface.count == systemOwners.count, "the list is those six owners, no more")
check(!lists(win("", app: "Dock", bundle: "COM.APPLE.DOCK")), "bundle identifiers compare without regard to case")
check(lists(win("", app: "Helper", bundle: "com.apple.dock.helper")), "an identifier that only starts with one is no match")
check(lists(win("", app: "Dockside", bundle: "com.example.com.apple.dock")), "nor one that ends with one")
check(lists(win("", app: "Open and Save Panel Service", bundle: "com.apple.appkit.xpc.openAndSavePanelService")),
      "an untitled window of the open and save panel service stays listed (a Save panel someone works in)")
check(lists(win("", app: "Universal Control", bundle: "com.apple.universalcontrol")),
      "an Apple helper outside the list stays listed (nothing is left out on a guess)")

// MARK: An untitled window of a process with no bundle (#114)

let tool = win(nil, app: "borders", bundle: "", pid: 777)
check(CatalogWindows.helper(tool) == .untitledWithoutBundle, "an untitled window of a tool with no bundle is a helper's")
check(!lists(tool), "and is not listed")
check(!lists(win("", app: "borders", bundle: "", pid: 777)), "an empty title is untitled")
check(!lists(win("   ", app: "borders", bundle: "", pid: 777)), "so is one of spaces")
check(!lists(win("\n\t", app: "borders", bundle: "", pid: 777)), "and one of a newline and a tab")
check(!lists(win(nil, app: "borders", bundle: nil, pid: 777)), "a bundle identifier of nil is none")
check(lists(win("ReadMe.md", app: "python3", bundle: "", pid: 778)), "a titled window of a tool with no bundle is listed")
check(lists(win(" x ", app: "python3", bundle: "", pid: 778)), "a title with spaces around it is a title")
check(lists(win("", app: "Terminal", bundle: "com.apple.Terminal")), "an untitled window of an app with a bundle is listed")
check(lists(win(nil, app: "Slack", bundle: "com.tinyspeck.slackmacgap")), "an Electron app's untitled window is listed")
check(lists(win("", app: "Finder", bundle: "com.apple.finder")), "an untitled Finder window on layer 0 is listed")
check(CatalogWindows.helper(doc) == nil, "an app's titled window is no helper's")

// MARK: This Mac's list (2026-10-29, macOS 27.0.1 26A434, Stage Manager off, two displays)
// As ScreenCaptureKit listed it to a read-only probe: each window's owner, layer, size and whether it
// had a title, with stand-in titles (the probe printed none) and the apps' own windows replaced by
// stand-ins of the same shape (titled, layer 0, bundled). `probeWindow` is the probe's own test window
// (a tool with no bundle: transparent, untitled, behind everything), as it was listed too.

let thisMac: [W] = [
    win("Desktop Picture", app: "", bundle: "", pid: 416, layer: -2147483626, 1920, 1080),
    win("Desktop Picture", app: "", bundle: "", pid: 416, layer: -2147483626, 2560, 1440),
    win("Wallpaper", app: "WindowManager", bundle: "com.apple.WindowManager", pid: 652, layer: -2147483624, 1920, 1080),
    win("Wallpaper", app: "WindowManager", bundle: "com.apple.WindowManager", pid: 652, layer: -2147483624, 2560, 1440),
    win("", app: "Finder", bundle: "com.apple.finder", pid: 717, layer: -2147483603, 1920, 1080),
    win("", app: "Finder", bundle: "com.apple.finder", pid: 717, layer: -2147483603, 2560, 1440),
    win("Backstop M", app: "", bundle: "", pid: 416, layer: -2147483602, 1920, 91),
    win("Widget", app: "Notification Center", bundle: "com.apple.notificationcenterui", pid: 806, layer: -2147483601, 360, 360),
    win("Window 1", app: "Notes", bundle: "com.apple.Notes", pid: 674, 1024, 800),
    win("", app: "Menu Bar Tool", bundle: "com.example.menubar", pid: 1041, 1, 1),
    win("Window 2", app: "Mail", bundle: "com.apple.mail", pid: 23511, 1920, 1050),
    win("Home", app: "Finder", bundle: "com.apple.finder", pid: 717, 1763, 632),
    win("Window 3", app: "Safari", bundle: "com.apple.Safari", pid: 61613, 2560, 1410),
    win("Window 4", app: "Keychain Access", bundle: "com.apple.keychainaccess", pid: 37987, 1436, 598),
    win("Window 5", app: "Terminal", bundle: "com.apple.Terminal", pid: 712, 597, 385),
    win("Window 6", app: "Xcode", bundle: "com.apple.dt.Xcode", pid: 60750, 838, 452),
    win("Menubar", app: "", bundle: "", pid: 416, layer: 24, 2560, 30),
    win("", app: "Screenshot", bundle: "com.apple.screencaptureui", pid: 36962, layer: 24, 2560, 1440),
    win("Cursor", app: "", bundle: "", pid: 416, layer: 2147483630, 28, 28),
]
let probeWindow = win("", app: "testwin", bundle: "", pid: 50624, 400, 332)
check(thisMac.filter(listedBefore).count == 7, "before #114 this Mac's list gave seven tiles")
check(thisMac.filter(lists) == thisMac.filter(listedBefore), "and gives the same seven now")
var named = Set<String>()
check(CatalogWindows.leftOutLines(thisMac, ownPID: own, named: &named).isEmpty,
      "with no line: WindowManager's wallpaper and the screenshot tool were never listed")
check(listedBefore(probeWindow) && !lists(probeWindow), "the probe's untitled window of a tool was a tile, and is none now")
check(CatalogWindows.leftOutLines(thisMac + [probeWindow], ownPID: own, named: &named)
        == ["Catalog: leaving out the untitled windows of testwin (no bundle identifier): a helper's, not an app's."],
      "and Sill.log names it once")

// MARK: Stage Manager's strip (#114's likely cause, not seen here: Stage Manager is off on this Mac)

let strip = (0..<4).map { i in win(i % 2 == 0 ? "" : "Stage \(i)", app: "WindowManager", bundle: "com.apple.WindowManager",
                                    pid: 652, 180, 140) }
check(strip.allSatisfy(listedBefore), "a strip of WindowManager windows on layer 0 would have been four tiles")
check(!strip.contains(where: lists), "and is none now")
named = []
let stripLines = CatalogWindows.leftOutLines(thisMac + strip, ownPID: own, named: &named)
check(stripLines == ["Catalog: leaving out the windows of WindowManager (com.apple.WindowManager): they are macOS's own, not an app's."],
      "one line names WindowManager, for all four")
check(CatalogWindows.leftOutLines(thisMac + strip, ownPID: own, named: &named).isEmpty, "and the next look prints none")

// MARK: The lines: once per owner, never for what was left out before

named = []
let mixed = [win("", app: "Dock", bundle: "com.apple.dock", pid: 300), tool,
             win("", app: "Dock", bundle: "com.apple.dock", pid: 300, 900, 700),
             win("LayerProbeParent", app: "TextEdit", bundle: "com.apple.TextEdit"),
             win("", app: "Dock", bundle: "com.apple.dock", pid: 300, layer: 20, 2560, 80),
             win(nil, app: "borders", bundle: "", pid: 777, 900, 700), doc]
check(CatalogWindows.leftOutLines(mixed, ownPID: own, named: &named) == [
        "Catalog: leaving out the windows of Dock (com.apple.dock): they are macOS's own, not an app's.",
        "Catalog: leaving out the untitled windows of borders (no bundle identifier): a helper's, not an app's."],
      "one line per owner, in the order the look found them; none for LayerProbeParent, the Dock's own layer or a tile")
check(named.count == 2, "two owners named")
var tools = Set<String>()
check(CatalogWindows.leftOutLines([tool, win("", app: "highlight", bundle: "", pid: 779)], ownPID: own, named: &tools).count == 2,
      "two tools with no bundle: a line each")
check(CatalogWindows.leftOutLines(mixed, ownPID: own, named: &named).isEmpty, "a second look names nobody again")
check(CatalogWindows.leftOutLines([win("", app: "borders", bundle: "", pid: own)], ownPID: own, named: &named).isEmpty,
      "nor a window of this process (never listed)")
var fresh = Set<String>()
check(CatalogWindows.leftOutLines([win("", app: "Dock", bundle: "com.apple.dock", pid: 300, 100, 600)], ownPID: own, named: &fresh).isEmpty,
      "nor a helper's window too small to have been a tile")

// MARK: 20,000 seeded random windows against the rule as written out here

struct Rand {   // SplitMix64: the same windows on every run
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
}
var rng = Rand(state: 114)
let titles: [String?] = [nil, "", " ", "\n", "Doc", "LayerProbeParent", "layerprobe", "Untitled", " x "]
let apps: [String?] = [nil, "", "Finder", "borders", "WindowManager"]
let bundles: [String?] = [nil, "", "com.apple.WindowManager", "com.apple.windowmanager", "COM.APPLE.DOCK", "com.apple.dock",
                          "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.notificationcenterui",
                          "com.apple.screencaptureui", "com.apple.finder", "com.apple.appkit.xpc.openAndSavePanelService",
                          "com.apple.dock.helper", " "]
let layers = [0, 0, 0, -2147483603, 24, 1]
let sizes: [Double] = [1, 99, 100, 101, 400]
let system = Set(systemOwners.map { $0.lowercased() })
var disagree = 0
for _ in 0..<20_000 {
    let w = win(rng.pick(titles), app: rng.pick(apps), bundle: rng.pick(bundles), pid: rng.pick([own, 100, 777]),
                layer: rng.pick(layers), rng.pick(sizes), rng.pick(sizes))
    let title = w.title ?? "", id = (w.bundleID ?? "").lowercased()
    let model = !(w.appName ?? "").isEmpty && w.layer == 0 && w.width > 100 && w.height > 100 && w.pid != own
        && !title.lowercased().contains("layerprobe") && !system.contains(id)
        && !(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && id.isEmpty)
    if lists(w) != model { disagree += 1 }
}
check(disagree == 0, "20,000 seeded random windows: the rule and its words agree (\(disagree) disagreements)")

print("catalog-windows: \(cases) checks, \(failures) failed")
if failures > 0 { exit(1) }
