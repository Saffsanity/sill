import CoreGraphics
import Foundation

// Checks SettingsWindowFit (Sources/SillMenuBar/SettingsWindowFit.swift; issue #59,
// docs/settings-window-plan.md): how tall Sill's Settings window may be on a screen, and where it
// goes when Sill changes its size. Compiled alone with swiftc (CoreGraphics only), build.sh:
//   swiftc -O Sources/SillMenuBar/SettingsWindowFit.swift Tests/checks/settings-window/main.swift
// First the cases the issue raises, then seeded random screens, chromes and frames against the
// rules' properties.

typealias Fit = SettingsWindowFit
var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL line \(line): \(what())") }
}
func same(_ got: CGFloat, _ want: CGFloat, _ what: String, line: Int = #line) {
    check(got == want, "\(what): got \(got), want \(want)", line: line)
}
func same(_ got: CGRect, _ want: CGRect, _ what: String, line: Int = #line) {
    check(got == want, "\(what): got \(got), want \(want)", line: line)
}

let m = Fit.margin
same(m, 12, "the margin")
same(Fit.minimumContent, 200, "the least a pane is given")

// The title bar and the toolbar of Sill's Settings window as macOS 27.0.1 draws them: 80 pt
// (-SillSettingsAfter's "chrome"; the plan's probe, with a toolbar of its own, had 88).
let chrome: CGFloat = 80
/// What the window shows of a pane `pane` points tall under a cap `limit`, and its frame height.
func shown(_ pane: CGFloat, _ limit: CGFloat) -> CGFloat { min(pane, limit) }
func windowHeight(_ pane: CGFloat, _ limit: CGFloat) -> CGFloat { shown(pane, limit) + chrome }

// The panes' natural heights: Remote Access's from the previews at 985a733 (pixels ÷ 2), with the
// internet switch on and with Tailscale; the others from the live window in test pattern mode
// (-SillSettingsAfter); and rosstex's window, 951 pt.
let remoteInternet: CGFloat = 983, remoteTailscale: CGFloat = 701, general: CGFloat = 727
let streaming: CGFloat = 568, permissions: CGFloat = 275, rosstexPane: CGFloat = 951 - chrome

// MARK: The cases

// A 14-inch MacBook Pro at its default scaling, 1,512 × 982 pt: 949 under macOS 27's 33-pt menu bar
// (this Mac), the Dock hidden.
let mbp = CGRect(x: 0, y: 0, width: 1512, height: 949)
let mbpLimit = Fit.contentLimit(visible: mbp, chrome: chrome)
same(mbpLimit, 949 - 80 - 24, "14-inch, default scaling, no Dock")
same(windowHeight(remoteInternet, mbpLimit), 925, "Remote Access with the internet switch on: capped, 12 pt clear of each edge")
check(shown(rosstexPane, mbpLimit) < rosstexPane, "rosstex's 951 pt window is capped on a 14-inch")
same(windowHeight(remoteTailscale, mbpLimit), 781, "Remote Access with Tailscale: its natural height")
same(windowHeight(general, mbpLimit), 807, "General: its natural height")

// The same with a Dock at the bottom taking 70 pt.
let mbpDock = CGRect(x: 0, y: 70, width: 1512, height: 879)
let mbpDockLimit = Fit.contentLimit(visible: mbpDock, chrome: chrome)
same(mbpDockLimit, 775, "14-inch, default scaling, Dock")
check(shown(rosstexPane, mbpDockLimit) == 775, "rosstex's pane capped above the Dock")
same(windowHeight(general, mbpDockLimit), 807, "General still fits above the Dock")

// The scalings with larger text: 1,352 × 878, 1,147 × 745 and 1,024 × 665 pt, the 33-pt menu bar,
// with and without the Dock.
for (screen, noDock, dock) in [(878.0, 741.0, 671.0), (745.0, 608.0, 538.0), (665.0, 528.0, 458.0)] as [(CGFloat, CGFloat, CGFloat)] {
    let v = CGRect(x: 0, y: 0, width: 1024, height: screen - 33)
    same(Fit.contentLimit(visible: v, chrome: chrome), noDock, "larger text, \(screen) pt tall, no Dock")
    let d = CGRect(x: 0, y: 70, width: 1024, height: screen - 33 - 70)
    same(Fit.contentLimit(visible: d, chrome: chrome), dock, "larger text, \(screen) pt tall, Dock")
}
let small = CGRect(x: 0, y: 70, width: 1024, height: 665 - 33 - 70)   // the smallest: 1,024 × 665 with the Dock
check(shown(general, Fit.contentLimit(visible: small, chrome: chrome)) < general, "General capped at 1,024 × 665 with the Dock")
check(shown(streaming, Fit.contentLimit(visible: small, chrome: chrome)) < streaming, "Streaming capped there too")
check(shown(permissions, Fit.contentLimit(visible: small, chrome: chrome)) == permissions, "Permissions fits there")

// Which pane fits which 14-inch scaling (the plan's "The problem, measured"): General fits at the
// default scaling, Dock or not, and at 1,352 × 878 only with the Dock hidden. Remote Access with the
// internet switch on (909 pt live, 983 at its tallest) and rosstex's 951 pt window fit only at More
// Space, 1,800 × 1,169 (1,136 under the menu bar), where the tallest Remote Access is capped with
// the Dock.
let remoteLive: CGFloat = 909
let at878 = CGRect(x: 0, y: 0, width: 1352, height: 878 - 33)
let at878Dock = CGRect(x: 0, y: 70, width: 1352, height: 878 - 33 - 70)
check(shown(general, Fit.contentLimit(visible: at878, chrome: chrome)) == general, "General fits at 1,352 × 878 with the Dock hidden")
check(shown(general, Fit.contentLimit(visible: at878Dock, chrome: chrome)) < general, "General capped at 1,352 × 878 with the Dock")
for v in [mbp, mbpDock, at878, at878Dock] {
    let limit = Fit.contentLimit(visible: v, chrome: chrome)
    check(shown(remoteLive, limit) < remoteLive, "Remote Access with the internet switch capped below More Space (\(v.height) pt)")
    check(shown(rosstexPane, limit) < rosstexPane, "rosstex's window capped below More Space (\(v.height) pt)")
}
let moreSpace = Fit.contentLimit(visible: CGRect(x: 0, y: 0, width: 1800, height: 1169 - 33), chrome: chrome)
let moreSpaceDock = Fit.contentLimit(visible: CGRect(x: 0, y: 70, width: 1800, height: 1169 - 33 - 70), chrome: chrome)
same(moreSpace, 1032, "More Space, no Dock")
same(moreSpaceDock, 962, "More Space, Dock")
for pane in [remoteLive, remoteInternet, rosstexPane, general] { check(shown(pane, moreSpace) == pane, "More Space: a \(pane) pt pane at its natural height") }
for pane in [remoteLive, rosstexPane, general] { check(shown(pane, moreSpaceDock) == pane, "More Space with the Dock: a \(pane) pt pane at its natural height") }
check(shown(remoteInternet, moreSpaceDock) < remoteInternet, "More Space with the Dock: the tallest Remote Access capped")

// An external 4K display, as the main screen: looking like 1,920 × 1,080 (a 25-pt menu bar), with and
// without the Dock, and like 2,560 × 1,440, where every pane has its natural height.
same(Fit.contentLimit(visible: CGRect(x: 0, y: 0, width: 1920, height: 1055), chrome: chrome), 951, "4K at 1,920 × 1,080")
same(Fit.contentLimit(visible: CGRect(x: 0, y: 70, width: 1920, height: 985), chrome: chrome), 881, "4K at 1,920 × 1,080, Dock")
let k4 = Fit.contentLimit(visible: CGRect(x: 0, y: 0, width: 2560, height: 1415), chrome: chrome)
same(k4, 1311, "4K at 2,560 × 1,440")
for pane in [remoteInternet, rosstexPane, general, streaming] { check(shown(pane, k4) == pane, "4K at 2,560 × 1,440: a \(pane) pt pane at its natural height") }

// That 4K display above the laptop, its own origin: the limit and the move use its own frame.
let above = CGRect(x: -200, y: 982, width: 2560, height: 1415)
same(Fit.contentLimit(visible: above, chrome: chrome), 1311, "a screen above the laptop: its own height")
same(Fit.placed(CGRect(x: 800, y: 1500, width: 520, height: 1063), in: above),
     CGRect(x: 800, y: 2397 - 12 - 1063, width: 520, height: 1063), "a window whose top is above that screen's: moved down")
same(Fit.placed(CGRect(x: 800, y: 900, width: 520, height: 1063), in: above),
     CGRect(x: 800, y: 982 + 12, width: 520, height: 1063), "a window reaching below that screen: moved up onto it")
// Beside it, to the right of the laptop and lower.
let beside = CGRect(x: 1512, y: -300, width: 1920, height: 1055)
same(Fit.placed(CGRect(x: 1700, y: -500, width: 520, height: 925), in: beside),
     CGRect(x: 1700, y: -300 + 12, width: 520, height: 925), "a screen beside and lower: moved up within it")

// A fractional visible height (a scaled mode can give one): whole points, rounded down.
same(Fit.contentLimit(visible: CGRect(x: 0, y: 0, width: 1800, height: 1136.5), chrome: chrome), 1032, "whole points")

// A screen too short for a usable pane: the least is given, and the window's top stays reachable.
let tiny = CGRect(x: 0, y: 0, width: 800, height: 250)
same(Fit.contentLimit(visible: tiny, chrome: chrome), 200, "a tiny screen still gets 200 pt")
same(Fit.placed(CGRect(x: 100, y: -100, width: 520, height: 280), in: tiny),
     CGRect(x: 100, y: 250 - 280, width: 520, height: 280), "taller than the screen: its top at the top")
same(Fit.placed(CGRect(x: 100, y: 50, width: 520, height: 280), in: tiny),
     CGRect(x: 100, y: 250 - 280, width: 520, height: 280), "taller than the screen, its top below the top: moved up to it")

// MARK: Where the window goes

// Inside the visible frame: left alone, also within the margin of an edge.
let inside = CGRect(x: 300, y: 100, width: 520, height: 600)
same(Fit.placed(inside, in: mbp), inside, "inside: unchanged")
same(Fit.placed(CGRect(x: 300, y: 5, width: 520, height: 600), in: mbp),
     CGRect(x: 300, y: 5, width: 520, height: 600), "inside, 5 pt over the bottom: unchanged")
same(Fit.placed(CGRect(x: 300, y: 300, width: 520, height: 640), in: mbp),
     CGRect(x: 300, y: 300, width: 520, height: 640), "inside, its top 9 pt under the menu bar: unchanged")
same(Fit.placed(CGRect(x: 300, y: 0, width: 520, height: 949), in: mbp),
     CGRect(x: 300, y: 0, width: 520, height: 949), "exactly the visible frame: unchanged")
// Partly off the screen below (a pane grown, or a frame saved by a version before the cap).
same(Fit.placed(CGRect(x: 300, y: -150, width: 520, height: 925), in: mbp),
     CGRect(x: 300, y: 12, width: 520, height: 925), "partly below the screen: up to 12 pt over its bottom")
same(Fit.placed(CGRect(x: 300, y: 40, width: 520, height: 826), in: mbpDock),
     CGRect(x: 300, y: 82, width: 520, height: 826), "partly under the Dock: up to 12 pt over it")
// No room for the margin: as far up as keeps the top inside.
same(Fit.placed(CGRect(x: 300, y: -5, width: 520, height: 940), in: mbp),
     CGRect(x: 300, y: 9, width: 520, height: 940), "940 pt in 949: its top at the top")
// Above the visible frame (moved from a taller screen): down to 12 pt under the menu bar, or as far
// as keeps the bottom inside.
same(Fit.placed(CGRect(x: 300, y: 100, width: 520, height: 925), in: mbp),
     CGRect(x: 300, y: 12, width: 520, height: 925), "its top above the screen's: down to 12 pt under it")
same(Fit.placed(CGRect(x: 300, y: 20, width: 520, height: 940), in: mbp),
     CGRect(x: 300, y: 0, width: 520, height: 940), "940 pt in 949, its top above: its bottom at the bottom")
// Never sideways, wherever it is across.
same(Fit.placed(CGRect(x: 1300, y: -100, width: 520, height: 600), in: mbp),
     CGRect(x: 1300, y: 12, width: 520, height: 600), "partly off to the right: only moved up")
same(Fit.placed(CGRect(x: -400, y: 500, width: 520, height: 600), in: mbp),
     CGRect(x: -400, y: 349 - 12, width: 520, height: 600), "partly off to the left: only moved down")

// MARK: The screen

let laptop = Fit.Screen(visible: mbp, sillVirtual: false)
let external = Fit.Screen(visible: above, sillVirtual: false)
let sillVirtual = Fit.Screen(visible: CGRect(x: 4000, y: 0, width: 1920, height: 1200), sillVirtual: true)
check(Fit.screenIndex(windowOn: 0, screens: [laptop, sillVirtual]) == 0, "on the laptop: the laptop")
check(Fit.screenIndex(windowOn: 1, screens: [laptop, external]) == 1, "on an external display: that display")
check(Fit.screenIndex(windowOn: 1, screens: [laptop, sillVirtual]) == 0, "on Sill's virtual display: the first other screen")
check(Fit.screenIndex(windowOn: nil, screens: [laptop, sillVirtual]) == 0, "on no screen: the first")
check(Fit.screenIndex(windowOn: 0, screens: [sillVirtual, external, laptop]) == 1, "the virtual display listed first: never it")
check(Fit.screenIndex(windowOn: nil, screens: [sillVirtual, laptop]) == 1, "on no screen, the virtual display first: the next")
check(Fit.screenIndex(windowOn: 7, screens: [laptop, external]) == 0, "an index no screen has: the first")
check(Fit.screenIndex(windowOn: -1, screens: [laptop]) == 0, "a negative index: the first")
check(Fit.screenIndex(windowOn: 0, screens: [sillVirtual]) == nil, "only the virtual display: none")
check(Fit.screenIndex(windowOn: nil, screens: []) == nil, "no screen: none")

// MARK: The test height (-SillTestScreenHeight)

same(Fit.visible(mbp, testHeight: 700), CGRect(x: 0, y: 249, width: 1512, height: 700), "700 pt: the top 700 of the visible frame")
same(Fit.contentLimit(visible: Fit.visible(mbp, testHeight: 700), chrome: chrome), 596, "700 pt: the limit, as the live window showed")
same(Fit.visible(mbpDock, testHeight: 700), CGRect(x: 0, y: 249, width: 1512, height: 700), "with the Dock: still the top 700")
same(Fit.visible(above, testHeight: 700), CGRect(x: -200, y: 1697, width: 2560, height: 700), "another screen: its own top")
same(Fit.visible(mbp, testHeight: nil), mbp, "no test")
same(Fit.visible(mbp, testHeight: 0), mbp, "0: no test")
same(Fit.visible(mbp, testHeight: -5), mbp, "negative: no test")
same(Fit.visible(mbp, testHeight: 949), mbp, "the screen's own height: no test")
same(Fit.visible(mbp, testHeight: 2000), mbp, "taller than the screen: no test")

// MARK: Random screens, chromes and frames

/// A fixed sequence (SplitMix64), so a failure comes back the same.
struct Seeded {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    /// Whole or half points in `range`.
    mutating func half(_ range: ClosedRange<Int>) -> CGFloat { CGFloat(int((range.lowerBound * 2)...(range.upperBound * 2))) / 2 }
}

var rng = Seeded(state: 59)
var capped = 0, moved = 0, kept = 0
for _ in 0..<20_000 {
    let visible = CGRect(x: rng.half(-3000...3000), y: rng.half(-2000...2000), width: rng.half(800...6000), height: rng.half(150...3000))
    let ch = rng.half(28...140)
    let limit = Fit.contentLimit(visible: visible, chrome: ch)
    check(limit == limit.rounded(.down), "whole points: \(limit) for \(visible), chrome \(ch)")
    check(limit >= Fit.minimumContent, "never under the least: \(limit)")
    let room = visible.height - ch - 2 * m
    if room >= Fit.minimumContent {
        check(limit + ch + 2 * m <= visible.height, "fits with its margins: \(limit) + \(ch) in \(visible.height)")
        check(limit + ch + 2 * m > visible.height - 1, "uses the room to within a point: \(limit) + \(ch) in \(visible.height)")
    } else {
        check(limit == Fit.minimumContent, "too short a screen gives the least: \(limit) for \(visible.height), chrome \(ch)")
    }
    let taller = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height + rng.half(0...400))
    check(Fit.contentLimit(visible: taller, chrome: ch) >= limit, "a taller screen never gives less")
    check(Fit.contentLimit(visible: visible, chrome: ch + rng.half(0...60)) <= limit, "more chrome never gives more")

    // A window whose pane is capped by that limit, anywhere around the screen.
    let pane = rng.half(100...2600)
    let h = min(pane, limit) + ch
    if pane > limit { capped += 1 }
    let frame = CGRect(x: rng.half(-4000...6000), y: visible.minY + rng.half(-2500...2500), width: 520, height: h)
    let p = Fit.placed(frame, in: visible)
    check(p.size == frame.size, "never resized: \(frame) → \(p)")
    check(p.minX == frame.minX, "never moved sideways: \(frame) → \(p)")
    check(Fit.placed(p, in: visible) == p, "placed twice is placed once: \(frame) in \(visible)")
    let wasInside = frame.minY >= visible.minY && frame.maxY <= visible.maxY
    if wasInside { check(p == frame, "inside: unchanged: \(frame) in \(visible)"); kept += 1 } else { moved += 1 }
    if h <= visible.height {
        check(p.minY >= visible.minY && p.maxY <= visible.maxY, "a window that fits ends inside: \(frame) → \(p) in \(visible)")
        if !wasInside && h + m <= visible.height {
            if frame.minY < visible.minY { same(p.minY, visible.minY + m, "moved up to the margin: \(frame) in \(visible)") }
            if frame.maxY > visible.maxY && frame.minY >= visible.minY { same(p.maxY, visible.maxY - m, "moved down to the margin: \(frame) in \(visible)") }
        }
        if room >= Fit.minimumContent && !wasInside {
            check(p.minY >= visible.minY + m || p.maxY <= visible.maxY - m, "a capped window keeps a margin on the side it was moved from")
        }
    } else {
        same(p.maxY, visible.maxY, "taller than the screen: its top at the top: \(frame) in \(visible)")
    }

    // A screen list: never the virtual display, the window's own screen when it is a real one.
    let count = rng.int(0...4)
    let screens = (0..<count).map { _ in Fit.Screen(visible: visible, sillVirtual: rng.int(0...2) == 0) }
    let on: Int? = rng.int(0...5) == 0 ? nil : rng.int(-1...5)
    let index = Fit.screenIndex(windowOn: on, screens: screens)
    if let index {
        check(screens.indices.contains(index) && !screens[index].sillVirtual, "a real screen: \(index) of \(screens.map(\.sillVirtual))")
        if let on, screens.indices.contains(on), !screens[on].sillVirtual { check(index == on, "the window's own screen: \(on), got \(index)") }
        else { check(index == screens.firstIndex { !$0.sillVirtual }, "the first real screen: got \(index) of \(screens.map(\.sillVirtual))") }
    } else {
        check(screens.allSatisfy(\.sillVirtual), "none only when every screen is the virtual display: \(screens.map(\.sillVirtual))")
    }
    let test = rng.half(-100...3200)
    let tv = Fit.visible(visible, testHeight: test)
    if test > 0 && test < visible.height {
        same(tv.maxY, visible.maxY, "a test height keeps the top")
        same(tv.height, test, "a test height is that tall")
        check(tv.minX == visible.minX && tv.width == visible.width, "a test height keeps the width")
    } else {
        same(tv, visible, "no test")
    }
}
check(capped > 1_000 && moved > 1_000 && kept > 1_000, "the random runs reach every branch: \(capped) capped, \(moved) moved, \(kept) left alone")

print("settings-window: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
