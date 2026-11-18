// CatalogWindows (Sources/SillHost/CatalogWindows.swift): which on-screen windows the catalog lists,
// the tiles in a device's window strip (issue #114), and native tab switches (issue #366).
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

// MARK: Native tab switches (#366): an on-screen window replaced at the same frame by another of the same app

typealias T = CatalogWindows.Tab
let tab1 = T(id: 3508, pid: 900, x: 120, y: 80, width: 1000, height: 700)
let tab2 = T(id: 3509, pid: 900, x: 120, y: 80, width: 1000, height: 700)
let tab2Jitter = T(id: 3509, pid: 900, x: 122, y: 78, width: 998, height: 702)
let tab2Moved = T(id: 3509, pid: 900, x: 123, y: 80, width: 1000, height: 700)
let otherApp = T(id: 4001, pid: 901, x: 120, y: 80, width: 1000, height: 700)
let notes = T(id: 2000, pid: 674, x: 40, y: 40, width: 800, height: 600)
check(CatalogWindows.tabSwaps(from: [notes, tab1], to: [notes, tab2]) == [3508: 3509],
      "#366: a tab that replaces another of the same app at the same frame is a swap")
check(CatalogWindows.tabSwaps(from: [tab1], to: [tab2Jitter]) == [3508: 3509],
      "#366: ±2 pt of frame jitter still counts as the same frame")
check(CatalogWindows.tabSwaps(from: [tab1], to: [tab2Moved]).isEmpty,
      "#366: more than 2 pt away is a new window at another place, not a tab")
check(CatalogWindows.tabSwaps(from: [tab1], to: [otherApp]).isEmpty,
      "#366: another process at the same frame is not a tab of this app")
check(CatalogWindows.tabSwaps(from: [tab1], to: [tab1, tab2]).isEmpty,
      "#366: when the first window stays on screen, a new window at its frame is not a tab swap")
let swappedOrder = CatalogWindows.orderedIDs(seenOrder: [3508, 2000], currentIDs: [2000, 3509], swaps: [3508: 3509])
check(swappedOrder == [3509, 2000], "#366: the new tab keeps the old tab's slot in the bar: \(swappedOrder)")
let plainOrder = CatalogWindows.orderedIDs(seenOrder: [3508, 2000], currentIDs: [2000, 4001], swaps: [:])
check(plainOrder == [2000, 4001], "#366: an ordinary new window still goes at the end of the bar: \(plainOrder)")
check(CatalogWindows.mergedSwaps(existing: [3508: 3509], next: [3509: 3510], onScreen: [2000, 3510], streaming: 3508)
        == [3508: 3510, 3509: 3510],
      "#366: two switches before the coordinator takes the first lead to the newest tab, from either tab before it")
check(CatalogWindows.mergedSwaps(existing: [3508: 3509], next: [:], onScreen: [2000, 3509], streaming: 3508) == [3508: 3509],
      "#366: a look with no switch keeps one not yet followed")

// #368's review: the switches kept are those still to follow, and only those.
check(CatalogWindows.mergedSwaps(existing: [3508: 3509], next: [3509: 3508], onScreen: [2000, 3508], streaming: 3509) == [3509: 3508],
      "#366: a switch right back: the second tab leads back to the first (a device that picked the tab group after a "
      + "switch made while another window streamed follows the switch back)")
check(CatalogWindows.mergedSwaps(existing: [3508: 3509], next: [3509: 3508], onScreen: [3508], streaming: 3508) == [3509: 3508],
      "#366: and nothing from the first tab to itself, while a switch in flight held its follow back")
check(CatalogWindows.mergedSwaps(existing: [3508: 3509], next: [:], onScreen: [2000, 3509, 3508], streaming: 2000).isEmpty,
      "#366: a tab on the screen again (moved into a window of its own) that streams nothing was not replaced: a device "
      + "that picks it follows nothing")
check(CatalogWindows.mergedSwaps(existing: [3508: 3509], next: [:], onScreen: [2000, 3509, 3508], streaming: 3508) == [3508: 3509],
      "#366: but the window that streams keeps the switch owed to it (its follow held back by a switch in flight)")
check(CatalogWindows.mergedSwaps(existing: [3508: 3509], next: [:], onScreen: [2000], streaming: 3508).isEmpty,
      "#366: a tab no longer on the screen (closed, minimized) is nothing to follow")
check(CatalogWindows.mergedSwaps(existing: [108: 107], next: [108: 101], onScreen: [110, 107, 101], streaming: 108) == [108: 107],
      "#366: the switch owed to the window that streams stands against a later one of it (the tab it went to was moved "
      + "into a window of its own meanwhile, and its old tab shown again, then replaced)")
let stackedFront = T(id: 5001, pid: 900, x: 0, y: 25, width: 1512, height: 920)
let stackedBack = T(id: 5002, pid: 900, x: 0, y: 25, width: 1512, height: 920)
check(CatalogWindows.tabSwaps(from: [stackedFront, stackedBack], to: [stackedBack]).isEmpty,
      "#366: of two windows of one app at one frame (both filling the screen), the one closed was not replaced by the other, there before")
let sameFrameAsTab1 = T(id: 3600, pid: 900, x: 120, y: 80, width: 1000, height: 700)
check(CatalogWindows.tabSwaps(from: [tab1, sameFrameAsTab1], to: [tab2]) == [3508: 3509],
      "#366: one new tab replaces one window, not two")
let groupB1 = T(id: 3700, pid: 900, x: 600, y: 300, width: 900, height: 600)
let groupB2 = T(id: 3701, pid: 900, x: 600, y: 300, width: 900, height: 600)
check(CatalogWindows.tabSwaps(from: [tab1, groupB1], to: [groupB2, tab2]) == [3508: 3509, 3700: 3701],
      "#366: two tab groups of one app switching in one look: each its own")
let chainedOrder = CatalogWindows.orderedIDs(seenOrder: [3509, 2000], currentIDs: [2000, 3510], swaps: [3509: 3510])
check(chainedOrder == [3510, 2000], "#366: and the next tab keeps that slot in turn: \(chainedOrder)")

// MARK: The model (#366, #368's review): a stand-in Mac with tab groups, the catalog's looks and the coordinator's follow

/// A seeded generator (window-restore's), so a failing session can be run again.
struct Dice {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

/// A window of the stand-in Mac as the person sees it: a tab group (a window without tabs is a group of
/// one) of an app, at its place, showing one of its tabs, the only one of them on the screen.
struct TabGroup { var tabs: [UInt32]; var shown: UInt32; var pid: Int32; var x: Double; var y: Double }

/// The catalog's looks with a copy of WindowCatalog.refreshWindows' lines for tab switches (regular mode:
/// nothing staged, so nothing pinned), and the coordinator's with a copy of followTabSwap's rule (from
/// windowsChanged and catalogPolled: the streamed window's switch followed unless a switch is in flight,
/// else a streamed window gone stops the stream), against the window the person expects to stream: the
/// tab group they picked, on the tab it shows, wherever it goes; nothing once it closes.
struct TabModel {
    let seed: UInt64
    var dice: Dice
    var groups: [TabGroup] = []
    var nextID: UInt32 = 100
    var places = 0
    var last: [CatalogWindows.Tab] = []
    var pending: [UInt32: UInt32] = [:]
    var seenOrder: [UInt32] = []
    var listed: [UInt32] = []                   // the last look's windows: the tiles a device picks from
    var active: UInt32? = nil
    var switching = 0                           // looks a switch in flight still takes
    var connected = true                        // the catalog looks only while a device is connected
    var want: UInt32? = nil
    var wantChange = ""
    /// The windows whose stale switch was dropped as they came back on the screen (#368's review).
    var backOnScreen: Set<UInt32> = []
    /// The window that streams, moved out of its tabs while a switch in flight held back its follow:
    /// right too at the next look (`moveTabOut`).
    var eitherOK: UInt32? = nil
    var problems: [String] = []
    var seen: [String: Int] = [:]
    var log: [String] = []

    init(seed: UInt64) {
        self.seed = seed
        dice = Dice(s: seed)
        for pid in [Int32(900), 900, 674] {
            var tabs: [UInt32] = []
            for _ in 0...dice.int(3) { tabs.append(newID()) }
            let (x, y) = place()
            groups.append(TabGroup(tabs: tabs, shown: tabs[dice.int(tabs.count)], pid: pid, x: x, y: y))
        }
    }

    mutating func newID() -> UInt32 { nextID += 1; return nextID }
    /// Each window a place of its own: two windows of one app at one frame that both change within one
    /// look are #366's one ambiguity (`tabSwaps` pairs them in list order), left out here.
    mutating func place() -> (Double, Double) { places += 1; return (Double(40 + 23 * places), Double(30 + 11 * places)) }
    mutating func note(_ s: String) { seen[s, default: 0] += 1 }
    mutating func problem(_ s: String) { if problems.count < 5 { problems.append("seed \(seed): \(s); \(log.suffix(10))") } }
    func group(of id: UInt32) -> Int? { groups.firstIndex { $0.tabs.contains(id) } }

    /// After a change on the Mac, the person expects the tab their window shows now.
    mutating func settle(_ why: String) {
        guard let w = want, let g = group(of: w), groups[g].shown != w else { return }
        want = groups[g].shown
        wantChange = why
    }

    mutating func switchTab() {
        let multi = groups.indices.filter { groups[$0].tabs.count > 1 }
        guard !multi.isEmpty else { return }
        let g = multi[dice.int(multi.count)]
        let others = groups[g].tabs.filter { $0 != groups[g].shown }
        groups[g].shown = others[dice.int(others.count)]
        log.append("switch to \(groups[g].shown) of \(groups[g].tabs)")
        settle("a switch")
    }
    mutating func newTab() {
        guard !groups.isEmpty else { return }
        let g = dice.int(groups.count), id = newID()
        groups[g].tabs.append(id)
        groups[g].shown = id
        log.append("new tab \(id) in \(groups[g].tabs)")
        settle("a new tab")
    }
    mutating func closeTab() {
        guard !groups.isEmpty else { return }
        let g = dice.int(groups.count), gone = groups[g].shown
        if groups.count == 1, groups[g].tabs.count == 1 { return }       // a window of the Mac's stays open
        groups[g].tabs.removeAll { $0 == gone }
        log.append("close tab \(gone)")
        if groups[g].tabs.isEmpty {
            groups.remove(at: g)
            if want == gone { want = nil }
        } else {
            groups[g].shown = groups[g].tabs[dice.int(groups[g].tabs.count)]
            if want == gone { want = groups[g].shown; wantChange = "a tab closed" }
        }
    }
    /// Window › Move Tab to New Window, or a tab dragged out: a window of its own at another place. Looked
    /// at on both sides, the one thing here a look 2 s apart cannot tell from another: a tab moved out and
    /// closed (or picked from a tile drawn before it was hidden, then moved out) within one look is a tab
    /// closed in its group (a tab hidden behind another) to any look, and followed as one.
    mutating func moveTabOut() {
        let multi = groups.indices.filter { groups[$0].tabs.count > 1 }
        guard !multi.isEmpty else { return }
        look()
        defer { look() }
        let g = multi[dice.int(multi.count)]
        let t = groups[g].tabs[dice.int(groups[g].tabs.count)]
        groups[g].tabs.removeAll { $0 == t }
        if groups[g].shown == t { groups[g].shown = groups[g].tabs[dice.int(groups[g].tabs.count)] }
        let (x, y) = place()
        groups.append(TabGroup(tabs: [t], shown: t, pid: groups[g].pid, x: x, y: y))
        log.append("move tab \(t) out of \(groups[g].tabs)")
        // The window that streams, moved out while a switch in flight holds back the follow owed to it:
        // the stream staying with it is as right as the person's tab group (whatever they do next).
        if switching > 0, active == t { eitherOK = t }
        settle("a tab moved out")
    }
    mutating func newWindow() {
        let (x, y) = place()
        let id = newID()
        groups.append(TabGroup(tabs: [id], shown: id, pid: dice.int(2) == 0 ? 900 : 674, x: x, y: y))
        log.append("new window \(id)")
    }
    mutating func closeWindow() {
        guard groups.count > 1 else { return }
        let g = dice.int(groups.count)
        if let w = want, groups[g].tabs.contains(w) { want = nil }
        log.append("close window \(groups[g].tabs)")
        groups.remove(at: g)
    }

    /// A device's pick of a tile from the last look: its tab may since have been hidden behind another
    /// (the person means the window, and it shows another tab now). Never one closed since (a capture of
    /// a window gone fails), and only between switches (one in flight queues it).
    mutating func pick() {
        guard connected, switching == 0, !listed.isEmpty else { return }
        let id = listed[dice.int(listed.count)]
        guard group(of: id) != nil else { return }
        pending[id] = nil               // StreamCoordinator.handlePick: a listed window's held switch goes
        active = id
        want = id
        log.append("pick \(id)")
        if backOnScreen.contains(id) { note("picked a window on the screen again after a stale switch") }
        settle("a pick of a tab hidden since the look")
    }

    /// One look of the catalog, then the coordinator.
    mutating func look() {
        guard connected else { return }
        var current = groups.map { CatalogWindows.Tab(id: $0.shown, pid: $0.pid, x: $0.x, y: $0.y, width: 1000, height: 700) }
        // ScreenCaptureKit's order is not front to back and shuffles between looks.
        for i in stride(from: current.count - 1, to: 0, by: -1) { current.swapAt(i, dice.int(i + 1)) }
        let ids = current.map(\.id), onScreen = Set(ids)
        // WindowCatalog.refreshWindows.
        let swaps = CatalogWindows.tabSwaps(from: last, to: current)
        let before = pending
        pending = CatalogWindows.mergedSwaps(existing: pending, next: swaps, onScreen: onScreen, streaming: active)
        let oldOrder = seenOrder
        seenOrder = CatalogWindows.orderedIDs(seenOrder: seenOrder, currentIDs: ids, swaps: swaps)
        last = current
        listed = ids
        for (old, new) in before where pending[old] == nil && swaps[old] == nil {
            if onScreen.contains(old), !swaps.values.contains(old) {
                note("a stale switch dropped: its window on the screen again, not by a switch back")
                backOnScreen.insert(old)
            } else if !onScreen.contains(new) {
                note("a stale switch dropped: its tab gone")
            }
        }
        // The bar: every window once, and a new tab in its old tab's slot among the windows on both sides.
        if seenOrder.count != ids.count || Set(seenOrder) != onScreen { problem("the bar \(seenOrder) is not the windows \(ids)") }
        for (old, new) in swaps {
            guard let o = oldOrder.firstIndex(of: old), let n = seenOrder.firstIndex(of: new) else { continue }
            note("a new tab in its old tab's slot")
            for other in seenOrder where other != new {
                if let a = oldOrder.firstIndex(of: other), (a < o) != (seenOrder.firstIndex(of: other)! < n) {
                    problem("tab \(new) is not in \(old)'s slot: \(oldOrder) → \(seenOrder)")
                }
            }
        }
        // StreamCoordinator: nothing while a switch is in flight; then followTabSwap, else a window gone stops.
        if switching > 0 { switching -= 1; return }
        if let id = active {
            if let next = pending[id], onScreen.contains(next) {
                pending[id] = nil
                note("followed \(wantChange)")
                if swaps[id] == nil { note("followed a switch from an earlier look (one was in flight)") }
                if before[next] == id { note("followed a switch back after one made while another window streamed") }
                active = next
            } else if !onScreen.contains(id) {
                note(want == nil ? "the stream stopped: its window closed" : "the stream stopped")
                active = nil
            }
        }
        if active != want, let e = eitherOK, active == e {
            note("stayed with the window that streams, moved out while its follow was held back")
            want = active
        }
        if active != want { problem("streams \(active.map(String.init) ?? "nothing") where the person expects \(want.map(String.init) ?? "nothing")") }
        if switching == 0 { eitherOK = nil }
    }

    mutating func step() {
        switch dice.int(100) {
        case 0..<22: switchTab()
        case 22..<28: newTab()
        case 28..<34: closeTab()
        case 34..<40: moveTabOut()
        case 40..<44: newWindow()
        case 44..<47: closeWindow()
        case 47..<60: pick()
        case 60..<62:
            if connected { active = nil; want = nil; log.append("pick desktop") }
        case 62..<66:
            if connected, active != nil, switching == 0 { switching = 1 + dice.int(3); log.append("a switch in flight for \(switching) looks") }
        case 66..<68:
            if connected { connected = false; active = nil; want = nil; switching = 0; log.append("the last device left") }
            else {
                // WindowCatalog.startPolling: no look from before, and one at once (the device's list).
                connected = true; last = []; log.append("a device connected")
                note("a device connected again")
                look()
            }
        default:
            look()
        }
    }
}

let tabSessions = 4_000
var tabProblems: [String] = []
var tabSeen: [String: Int] = [:]
var tabProblemCount = 0
for n in 0..<tabSessions {
    var m = TabModel(seed: UInt64(n) &* 7919 &+ 366)
    for _ in 0..<(40 + m.dice.int(80)) { m.step() }
    tabProblemCount += m.problems.count
    if tabProblems.count < 5 { tabProblems += m.problems.prefix(5 - tabProblems.count) }
    for (k, v) in m.seen { tabSeen[k, default: 0] += v }
}
for p in tabProblems { print("     \(p)") }
check(tabProblemCount == 0, "#366: the model, \(tabSessions) sessions: the stream on the window the person expects, the bar in order "
      + "(\(tabProblemCount) problems)")
let tabNeeded = ["followed a switch", "followed a new tab", "followed a tab closed", "followed a pick of a tab hidden since the look",
                 "followed a switch from an earlier look (one was in flight)",
                 "followed a switch back after one made while another window streamed",
                 "a stale switch dropped: its window on the screen again, not by a switch back",
                 "picked a window on the screen again after a stale switch", "a stale switch dropped: its tab gone",
                 "the stream stopped: its window closed", "a new tab in its old tab's slot", "a device connected again"]
for k in tabNeeded { check((tabSeen[k] ?? 0) > 0, "#366: the model came to: \(k) (\(tabSeen[k] ?? 0))") }

print("catalog-windows: \(cases) checks, \(failures) failed")
if failures > 0 { exit(1) }
