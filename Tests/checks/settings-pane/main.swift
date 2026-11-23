// iOSClient/SettingsPane.swift on its own, with DuoPosture.swift for the fold (docs/settings-pane-plan.md):
// Settings as a whole-screen pane. Where its two parts go at the real sizes (every phone either way round, the
// iPads, the iPhone Duo's displays in every pose, right to left too), then a grid of every width from 200 to
// 1,400 pt at heights from 240 to 1,400, each without a fold, with the book pose's band down it (centred and
// off centre) and with the laptop pose's across it, left to right and right to left: inside the screen and its
// margins, never wider than 600, never on the fold, the Mac's part leading and above, the arrangement exactly
// where its rule says (one column wherever no fold is kept to: Noah, 2026-11-23), each scroll view across its
// page with its column inside it (the whole screen in one column: Noah, 2026-11-23, a drag anywhere scrolls),
// the header over the Mac's column; and what each way of closing it brings.
//   swiftc -O iOSClient/SettingsPane.swift iOSClient/DuoPosture.swift Tests/checks/settings-pane/main.swift -o .build/checks/settings-pane/check
import CoreGraphics
import Foundation

typealias Layout = SettingsPane.Layout
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", name) } else { passes += 1; print("ok  ", name) } }
func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
func str(_ r: CGRect) -> String { String(format: "(%.1f, %.1f, %.1f×%.1f)", r.minX, r.minY, r.width, r.height) }
func size(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
func same(_ a: CGRect, _ b: CGRect) -> Bool { near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height) }
/// Nothing of `a` on `b`: at most an edge shared (a page's scroll view ends where the fold's band begins).
func clear(_ a: CGRect, of b: CGRect) -> Bool {
    a.maxX <= b.minX + 0.001 || b.maxX <= a.minX + 0.001 || a.maxY <= b.minY + 0.001 || b.maxY <= a.minY + 0.001
}

// MARK: - The numbers

check("16 pt margins, a book page's column of 300 at least, 600 at most, pages of 200",
      SettingsPane.margin == 16 && SettingsPane.minColumn == 300 && SettingsPane.maxColumn == 600 && SettingsPane.minPage == 200)
check("under Disconnect: 16 pt at a screen's foot with no home indicator, 12 over the laptop pose's fold",
      SettingsPane.footGap == 16 && SettingsPane.foldGap == 12)

// MARK: - The real sizes
//
// The stream screen: the screen less its top and side safe areas, down to the bottom edge (the bottom inset
// is the home indicator's). The iPhone Duo's from the iOS 27.1 simulator (docs/iphone-duo-plan.md: the
// status bar hidden on the inner display in every pose; the cover less its camera's 84 pt strip).

let bookFold = rect(455.5, 0, 40, 669), laptopFold = rect(0, 455.5, 669, 40)

struct Case {
    let name: String
    let size: CGSize
    let bottom: CGFloat
    let fold: FoldInfo
    let arrangement: Layout.Arrangement
    /// The Mac's column and this device's, x and width (y and height for the pages), left to right.
    let mac: CGRect
    let device: CGRect
    /// Their scroll views, left to right: the page each column is on (the whole screen in one column).
    let macScroll: CGRect
    let deviceScroll: CGRect
}
func one(_ W: CGFloat, _ H: CGFloat) -> CGRect { let w = min(600, W - 32); return rect((W - w) / 2, 0, w, H) }

var cases: [Case] = []
func add(_ name: String, _ W: CGFloat, _ H: CGFloat, bottom: CGFloat, fold: FoldInfo = .inferred, _ a: Layout.Arrangement,
         mac: CGRect? = nil, device: CGRect? = nil, macScroll: CGRect? = nil, deviceScroll: CGRect? = nil) {
    if a == .oneColumn {
        // One scroll view for both parts, the whole screen: a drag anywhere on it scrolls the rows.
        cases.append(Case(name: name, size: size(W, H), bottom: bottom, fold: fold, arrangement: a, mac: one(W, H), device: one(W, H),
                          macScroll: rect(0, 0, W, H), deviceScroll: rect(0, 0, W, H)))
    } else {
        cases.append(Case(name: name, size: size(W, H), bottom: bottom, fold: fold, arrangement: a, mac: mac!, device: device!,
                          macScroll: macScroll!, deviceScroll: deviceScroll!))
    }
}
// Phones upright: one column, the width less 16 each side.
add("iPhone 18 Pro Max upright", 440, 956 - 62, bottom: 34, .oneColumn)
add("iPhone 15 Pro upright", 393, 852 - 59, bottom: 34, .oneColumn)
add("iPhone 13 mini upright", 375, 812 - 50, bottom: 34, .oneColumn)
add("iPhone SE upright", 375, 667 - 20, bottom: 0, .oneColumn)
add("iPhone SE with Display Zoom upright", 320, 568 - 20, bottom: 0, .oneColumn)
// Phones on their side (the notch's or the island's inset at each side): one column too, 600 pt and centred
// (Noah, 2026-11-23: "Settings should not be 2 columns, please make it 1 column"; until then two columns here).
add("iPhone 18 Pro Max on its side", 956 - 124, 440, bottom: 21, .oneColumn)
add("iPhone 15 Pro on its side", 852 - 118, 393, bottom: 21, .oneColumn)
add("iPhone 13 mini on its side", 812 - 88, 375, bottom: 21, .oneColumn)
add("iPhone SE on its side", 667, 375, bottom: 0, .oneColumn)
add("iPhone SE with Display Zoom on its side", 568, 320, bottom: 0, .oneColumn)
// iPads (the status bar's 24 pt off the top): one column either way round, 600 pt and centred, and in narrow
// windows the window's width less 16 each side.
add("iPad Pro 13-inch sideways", 1376, 1032 - 24, bottom: 20, .oneColumn)
add("iPad Pro 13-inch upright", 1032, 1376 - 24, bottom: 20, .oneColumn)
add("iPad Pro 11-inch upright", 834, 1210 - 24, bottom: 20, .oneColumn)
add("iPad mini sideways", 1133, 744 - 24, bottom: 20, .oneColumn)
add("iPad mini upright", 744, 1133 - 24, bottom: 20, .oneColumn)
add("iPad Pro 13-inch, half of Split View sideways", 683, 1032 - 24, bottom: 20, .oneColumn)
add("iPad Pro 13-inch, half of Split View upright", 507, 1376 - 24, bottom: 20, .oneColumn)
add("iPad in Slide Over", 320, 1000, bottom: 20, .oneColumn)
add("an iPad window 720 pt wide, upright", 720, 900, bottom: 20, .oneColumn)
// The iPhone Duo (iOS 27.1): its folded poses keep to the fold, a column on each page or a page each side of
// it; open flat and closed, one column as any screen.
add("Duo, the book pose", 951, 669, bottom: 34, fold: .known(bookFold), .twoColumns,
    mac: rect(16, 0, 423.5, 669), device: rect(511.5, 0, 423.5, 669),
    macScroll: rect(0, 0, 455.5, 669), deviceScroll: rect(495.5, 0, 455.5, 669))
add("Duo, the laptop pose", 669, 951, bottom: 34, fold: .known(laptopFold), .twoPages,
    mac: rect(34.5, 0, 600, 455.5), device: rect(34.5, 495.5, 600, 455.5),
    macScroll: rect(0, 0, 669, 455.5), deviceScroll: rect(0, 495.5, 669, 455.5))
add("Duo, open flat sideways", 951, 669, bottom: 34, fold: .known(nil), .oneColumn)
add("Duo, open flat upright", 669, 951, bottom: 34, fold: .known(nil), .oneColumn)
add("Duo, the cover upright", 382, 678, bottom: 34, fold: .known(nil), .oneColumn)
add("Duo, the cover on its side", 594, 466, bottom: 34, fold: .known(nil), .oneColumn)
// The harness's first guesses with its stand-in fold (DuoPosture.standInFold).
add("the harness's 1000×710, half", 1000, 710, bottom: 0, fold: .known(rect(480, 0, 40, 710)), .twoColumns,
    mac: rect(16, 0, 448, 710), device: rect(536, 0, 448, 710),
    macScroll: rect(0, 0, 480, 710), deviceScroll: rect(520, 0, 480, 710))
add("the harness's 710×1000, half", 710, 1000, bottom: 0, fold: .known(rect(0, 480, 710, 40)), .twoPages,
    mac: rect(55, 0, 600, 480), device: rect(55, 520, 600, 480),
    macScroll: rect(0, 0, 710, 480), deviceScroll: rect(0, 520, 710, 480))
// Before iOS 27.1 the crease is only inferred: never kept to by the pane (no device folds there).
add("an inferred crease (710×1000)", 710, 1000, bottom: 0, fold: .inferred, .oneColumn)

for c in cases {
    for rtl in [false, true] {
        let l = Layout(size: c.size, bottomInset: c.bottom, fold: c.fold, rightToLeft: rtl)
        let dir = rtl ? ", right to left" : ""
        check("\(c.name)\(dir): \(c.arrangement.rawValue) (\(l.description))", l.arrangement == c.arrangement)
        // Left to right the leading space is the screen's; right to left, its mirror. The Duo's folds are centred,
        // so the same columns either way round on the screen, the Mac's on the leading side.
        let mac = l.onScreen(l.mac), device = l.onScreen(l.device)
        let wantMac = rtl && c.arrangement == .twoColumns ? c.device : c.mac
        let wantDevice = rtl && c.arrangement == .twoColumns ? c.mac : c.device
        check("\(c.name)\(dir): the Mac's part at \(str(wantMac)), this device's at \(str(wantDevice))",
              near(mac.minX, wantMac.minX) && near(mac.width, wantMac.width) && near(mac.minY, wantMac.minY) && near(mac.height, wantMac.height)
                && near(device.minX, wantDevice.minX) && near(device.width, wantDevice.width)
                && near(device.minY, wantDevice.minY) && near(device.height, wantDevice.height))
        // Each scroll view across its page, its column inside it: a drag beside the rows scrolls them too (Noah,
        // 2026-11-23: "on iPad in landscape, you have to touch the middle 3rd of the display to scroll instead of
        // anywhere on the screen").
        let macScroll = l.onScreen(l.macScroll), deviceScroll = l.onScreen(l.deviceScroll)
        let wantMacScroll = rtl && c.arrangement == .twoColumns ? c.deviceScroll : c.macScroll
        let wantDeviceScroll = rtl && c.arrangement == .twoColumns ? c.macScroll : c.deviceScroll
        check("\(c.name)\(dir): the Mac's part scrolls across \(str(wantMacScroll)), this device's across \(str(wantDeviceScroll)), "
                + "each column inside its own",
              same(macScroll, wantMacScroll) && same(deviceScroll, wantDeviceScroll)
                && macScroll.insetBy(dx: -0.001, dy: -0.001).contains(mac) && deviceScroll.insetBy(dx: -0.001, dy: -0.001).contains(device))
        check("\(c.name)\(dir): the bottom inset kept, \(c.bottom)", l.bottom == c.bottom)
        // Disconnect clear of the home indicator (its room, 16 pt at least), or 12 pt over the laptop pose's fold.
        let foot: CGFloat = c.arrangement == .twoPages ? 12 : max(16, c.bottom)
        check("\(c.name)\(dir): \(String(format: "%g", Double(foot))) pt under Disconnect, "
                + (c.arrangement == .twoPages ? "over the fold" : "at the screen's foot"),
              l.footBottom == foot)
    }
}

// The book pose: nothing on the band, the header's words on the leading page and Done on the trailing one.
let bookL = Layout(size: size(951, 669), bottomInset: 34, fold: .known(bookFold))
check("the book pose: the band 455.5–495.5 kept, between the columns",
      bookL.band == bookFold && bookL.mac.maxX <= 455.5 - 16 && bookL.device.minX >= 495.5 + 16)
check("the book pose: the header from 16 to 935, its words 415.5 pt wide (to 435.5, short of the fold)",
      bookL.header.x == 16 && bookL.header.width == 919 && bookL.headerWords == 415.5
        && bookL.header.x + Layout.headerInset + bookL.headerWords! <= 455.5)
check("the book pose: Done, at the header's trailing end, on the trailing page",
      bookL.header.x + bookL.header.width - Layout.headerInset > 495.5 + 44)
let laptopL = Layout(size: size(669, 951), bottomInset: 34, fold: .known(laptopFold))
check("the laptop pose: the header over the upper page's column, beside Done",
      laptopL.header.x == 34.5 && laptopL.header.width == 600 && laptopL.headerWords == nil)
check("the laptop pose: the upper page ends at the fold's top, the lower begins at its foot",
      laptopL.mac.maxY == 455.5 && laptopL.device.minY == 495.5 && laptopL.device.maxY == 951 && laptopL.band == laptopFold)
// A fold whose pages could not hold the columns is not kept to (no device has one).
check("a book band whose pages hold columns of 274 pt: not kept to, one column as without a fold",
      Layout(size: size(652, 500), bottomInset: 0, fold: .known(rect(306, 0, 40, 500))).arrangement == .oneColumn
        && Layout(size: size(652, 500), bottomInset: 0, fold: .known(rect(306, 0, 40, 500))).band == nil
        && Layout(size: size(652, 500), bottomInset: 0, fold: .known(rect(306, 0, 40, 500))).mac == rect(26, 0, 600, 500))
check("a book band whose pages hold columns of 300 pt: kept to; of 299.5: one column",
      Layout(size: size(704, 500), bottomInset: 0, fold: .known(rect(332, 0, 40, 500))).arrangement == .twoColumns
        && Layout(size: size(704, 500), bottomInset: 0, fold: .known(rect(332, 0, 40, 500))).mac == rect(16, 0, 300, 500)
        && Layout(size: size(703, 500), bottomInset: 0, fold: .known(rect(331.5, 0, 40, 500))).arrangement == .oneColumn)
check("a laptop band 150 pt from the top: one column, no fold kept",
      Layout(size: size(669, 951), bottomInset: 34, fold: .known(rect(0, 150, 669, 40))).arrangement == .oneColumn)
check("a laptop band whose lower page is 200 pt over the home indicator: two pages; 199: one column",
      Layout(size: size(669, 951), bottomInset: 34, fold: .known(rect(0, 677, 669, 40))).arrangement == .twoPages
        && Layout(size: size(669, 951), bottomInset: 34, fold: .known(rect(0, 678, 669, 40))).arrangement == .oneColumn)
check("a laptop band whose upper page is 200 pt: two pages; 199.5: one column",
      Layout(size: size(669, 951), bottomInset: 0, fold: .known(rect(0, 200, 669, 40))).arrangement == .twoPages
        && Layout(size: size(669, 951), bottomInset: 0, fold: .known(rect(0, 199.5, 669, 40))).arrangement == .oneColumn)

// Without a fold to keep to, one column however wide the screen and whichever way round (Noah, 2026-11-23:
// "Settings should not be 2 columns, please make it 1 column"): two columns came from 652 pt sideways and 732
// upright until then.
check("without a fold, one column where two came until 2026-11-23: 652 pt sideways, 732 upright, a square, an iPad",
      [size(652, 400), size(732, 1000), size(700, 700), size(1376, 1008), size(1032, 1352)].allSatisfy { s in
          [FoldInfo.inferred, .known(nil)].allSatisfy { Layout(size: s, bottomInset: 0, fold: $0).arrangement == .oneColumn }
      })
check("without a fold, one column on screens wider than any device's: 2,732 by 2,048, either way round",
      [size(2732, 2048), size(2048, 2732)].allSatisfy { s in
          [FoldInfo.inferred, .known(nil)].allSatisfy { Layout(size: s, bottomInset: 20, fold: $0).arrangement == .oneColumn }
      })
check("600 pt at most, centred: an iPad Pro 13-inch sideways gives one column of 600 at 388",
      Layout(size: size(1376, 1008), bottomInset: 20, fold: .inferred).mac == rect(388, 0, 600, 1008)
        && Layout(size: size(1376, 1008), bottomInset: 20, fold: .inferred).device == rect(388, 0, 600, 1008))
check("one column 600 at most, centred", Layout(size: size(669, 951), bottomInset: 0, fold: .known(nil)).mac == rect(34.5, 0, 600, 951))
// The scroll view across the whole screen, not the column alone (Noah, 2026-11-23, of the first build with one
// column: "on iPad in landscape, you have to touch the middle 3rd of the display to scroll instead of anywhere on
// the screen"): his iPad mini on its side, an iPad Pro 13-inch, an iPhone 15 Pro on its side.
let wideScreens: [(name: String, size: CGSize, bottom: CGFloat, column: CGRect)] = [
    ("an iPad mini on its side", size(1133, 720), 20, rect(266.5, 0, 600, 720)),
    ("an iPad Pro 13-inch on its side", size(1376, 1008), 20, rect(388, 0, 600, 1008)),
    ("an iPhone 15 Pro on its side", size(734, 393), 21, rect(67, 0, 600, 393)),
]
for (name, s, bottom, column) in wideScreens {
    let l = Layout(size: s, bottomInset: bottom, fold: .inferred)
    check("\(name): the rows' column at \(str(column)), their scroll view the whole screen, 0–\(Int(s.width)), so a drag at "
            + "either edge scrolls them",
          l.mac == column && l.macScroll == rect(0, 0, s.width, s.height) && l.deviceScroll == l.macScroll)
}
check("the lines for the console, with the scroll views and the bottom the pane was given",
      bookL.description == "two columns 423.5 pt wide, the Mac's at 16, this device's at 511.5, their scroll views 0–455.5 and 495.5–951, "
            + "the fold 455.5–495.5 between (951×669, 34 pt kept at the bottom)"
        && laptopL.description == "two pages 600 pt wide at 34.5, the Mac's to 455.5, this device's from 495.5, their scroll views 0–669 "
            + "(669×951, 34 pt kept at the bottom)"
        && Layout(size: size(393, 793), bottomInset: 34, fold: .inferred).description
            == "one column 361 pt wide at 16, its scroll view 0–393 (393×793, 34 pt kept at the bottom)"
        && Layout(size: size(734, 393), bottomInset: 21, fold: .inferred).description
            == "one column 600 pt wide at 67, its scroll view 0–734 (734×393, 21 pt kept at the bottom)"
        && Layout(size: size(1376, 1008), bottomInset: 20, fold: .inferred, rightToLeft: true).description
            == "one column 600 pt wide at 388, its scroll view 0–1376 (1376×1008, 20 pt kept at the bottom, right to left)")
check("the line without a bottom: nothing said (an iPhone SE on its side)",
      Layout(size: size(667, 375), bottomInset: 0, fold: .inferred).description == "one column 600 pt wide at 33.5, its scroll view 0–667 (667×375)")

// MARK: - The grid

final class Rule {
    let name: String
    var firstFailure: String?
    init(_ name: String) { self.name = name }
    func expect(_ ok: @autoclosure () -> Bool, _ what: @autoclosure () -> String) {
        guard firstFailure == nil else { return }
        if !ok() { firstFailure = what() }
    }
}
let inside = Rule("every part inside the screen, 16 pt from its sides (a screen wider than 32 pt)")
let widest = Rule("no part wider than 600 pt")
let decided = Rule("the arrangement is the rule's: two pages for a laptop band with pages of 200, two columns on a book band's pages of 300 or more each, else one column")
let offFold = Rule("nothing on a fold's band: the columns on its pages, 16 pt from them; the pages above and below it")
let leadingMac = Rule("the Mac's part leading (its column first in the leading-edge space) or above, this device's trailing or below")
let foldsOnly = Rule("two columns or two pages only around a fold kept to (a book band, a laptop band): every other screen one column, however wide and whichever way round (Noah, 2026-11-23)")
let single = Rule("one column: both parts in it, min(600, W − 32) wide, centred, the screen's height")
let headerRule = Rule("the header over the Mac's part (in the book pose out to the trailing page's column's edge, its words the leading page's column less 8)")
let mirrored = Rule("right to left mirrors left to right: the same rects on the screen, mirrored, the Mac's part on the leading side")
let footRule = Rule("Disconnect clear of the home indicator: at the screen's foot its room, 16 pt at least; 12 over the laptop pose's fold")
let scrolls = Rule("each scroll view across its page, its column inside it: in one column one scroll view, the whole screen; in the book pose "
                   + "each page from the screen's edge to the band, never on it; in the laptop pose the screen's width above the band and below it")
let rules = [inside, widest, decided, offFold, leadingMac, foldsOnly, single, headerRule, mirrored, footRule, scrolls]

func mirror(_ r: CGRect, _ W: CGFloat) -> CGRect { rect(W - r.maxX, r.minY, r.width, r.height) }

var gridLayouts = 0
for w in stride(from: 200, through: 1400, by: 1) {
    for h in stride(from: 240, through: 1400, by: 20) {
        let W = CGFloat(w), H = CGFloat(h)
        let bottom: CGFloat = h % 40 == 0 ? 34 : 0
        // No fold; a book band centred and one off centre; a laptop band across the middle; the Duo's widths.
        let folds: [FoldInfo] = [.inferred, .known(nil), .known(rect(W / 2 - 20, 0, 40, H)), .known(rect(W * 0.4 - 20, 0, 40, H)),
                                 .known(rect(0, H / 2 - 20, W, 40))]
        for fold in folds {
            var both: [Layout] = []
            for rtl in [false, true] {
                let l = Layout(size: size(W, H), bottomInset: bottom, fold: fold, rightToLeft: rtl)
                both.append(l)
                gridLayouts += 1
                let at = "\(w)×\(h), \(fold), \(rtl ? "right to left" : "left to right"): \(l.description)"
                let mac = l.onScreen(l.mac), device = l.onScreen(l.device)
                for r in [mac, device] {
                    inside.expect(r.minX >= -0.001 && r.maxX <= W + 0.001 && r.minY >= 0 && r.maxY <= H + 0.001
                                  && (W <= 32 || (r.minX >= 16 - 0.001 && r.maxX <= W - 16 + 0.001)), at)
                    widest.expect(r.width <= 600 + 0.001, at)
                }
                // The rule, restated.
                let m: CGFloat = 16
                var want: Layout.Arrangement
                if let b = fold.horizontalBand, b.minY >= 200, H - b.maxY - bottom >= 200 {
                    want = .twoPages
                } else if let b = fold.verticalBand, b.minX - 2 * m >= 300, W - b.maxX - 2 * m >= 300 {
                    want = .twoColumns
                } else {
                    want = .oneColumn
                }
                decided.expect(l.arrangement == want, at + ", expected \(want.rawValue)")
                // Whatever the thresholds: two parts side by side or one above the other only with a fold's band
                // between them, of the fold's own kind; no band, one column.
                foldsOnly.expect((l.arrangement == .oneColumn) == (l.band == nil)
                                 && (l.arrangement != .twoColumns || fold.verticalBand != nil)
                                 && (l.arrangement != .twoPages || fold.horizontalBand != nil), at)
                footRule.expect(l.arrangement == .twoPages ? l.footBottom == 12 : l.footBottom == max(16, bottom) && l.footBottom >= bottom,
                                at + ", \(l.footBottom) under Disconnect")
                // The scroll views, on the screen: each holds its column, and spans its page.
                let macScroll = l.onScreen(l.macScroll), deviceScroll = l.onScreen(l.deviceScroll)
                let scrollsAt = { at + ", the scroll views \(str(macScroll)) and \(str(deviceScroll))" }   // only on a failure
                scrolls.expect(macScroll.insetBy(dx: -0.001, dy: -0.001).contains(mac)
                               && deviceScroll.insetBy(dx: -0.001, dy: -0.001).contains(device), scrollsAt())
                switch l.arrangement {
                case .oneColumn:
                    scrolls.expect(same(macScroll, rect(0, 0, W, H)) && same(deviceScroll, macScroll), scrollsAt())
                case .twoColumns:
                    if let band = l.band.map(l.onScreen) {
                        let left = rect(0, 0, band.minX, H), right = rect(band.maxX, 0, W - band.maxX, H)
                        scrolls.expect(same(macScroll, rtl ? right : left) && same(deviceScroll, rtl ? left : right)
                                       && clear(macScroll, of: band) && clear(deviceScroll, of: band), scrollsAt())
                    } else {
                        scrolls.expect(false, scrollsAt() + ", two columns without a band")
                    }
                case .twoPages:
                    if let band = l.band.map(l.onScreen) {
                        scrolls.expect(same(macScroll, rect(0, 0, W, band.minY)) && same(deviceScroll, rect(0, band.maxY, W, H - band.maxY))
                                       && clear(macScroll, of: band) && clear(deviceScroll, of: band), scrollsAt())
                    } else {
                        scrolls.expect(false, scrollsAt() + ", two pages without a band")
                    }
                }
                if let band = l.band.map(l.onScreen) {
                    offFold.expect(!mac.intersects(band) && !device.intersects(band), at)
                    if l.arrangement == .twoColumns {
                        // Each column centred on its page, 16 pt from its edges (or 600 wide at most).
                        let pages = [rect(0, 0, band.minX, H), rect(band.maxX, 0, W - band.maxX, H)]
                        for (r, page) in [(mac, pages.first { $0.contains(CGPoint(x: mac.midX, y: 1)) }),
                                          (device, pages.first { $0.contains(CGPoint(x: device.midX, y: 1)) })] {
                            offFold.expect(page != nil && near(r.midX, page!.midX) && near(r.width, min(600, page!.width - 32)), at)
                        }
                    } else {
                        offFold.expect(near(mac.maxY, band.minY) && near(device.minY, band.maxY) && near(device.maxY, H), at)
                    }
                } else {
                    offFold.expect(fold.horizontalBand == nil || l.arrangement != .twoPages, at)
                }
                switch l.arrangement {
                case .twoColumns:
                    leadingMac.expect(l.mac.maxX <= l.device.minX && (rtl ? mac.minX > device.minX : mac.minX < device.minX), at)
                    headerRule.expect(near(l.header.x, l.mac.minX) && near(l.header.width, l.device.maxX - l.mac.minX)
                                      && l.headerWords != nil && near(l.headerWords!, l.mac.width - 8), at)
                case .twoPages:
                    leadingMac.expect(l.mac.maxY <= l.device.minY && near(l.mac.minY, 0), at)
                    headerRule.expect(near(l.header.x, l.mac.minX) && near(l.header.width, l.mac.width) && l.headerWords == nil, at)
                case .oneColumn:
                    single.expect(l.mac == l.device && near(l.mac.width, min(600, max(0, W - 32))) && near(mac.minX, W - mac.maxX)
                                  && l.mac.minY == 0 && l.mac.height == H, at)
                    headerRule.expect(near(l.header.x, l.mac.minX) && near(l.header.width, l.mac.width) && l.headerWords == nil, at)
                }
            }
            let rtl = both[1]
            // The mirror: right to left, each part is where the mirror of the same screen with the mirrored fold puts it.
            let mirroredFold: FoldInfo = fold.band.map { .known(mirror($0, W)) } ?? fold
            let ltrOfMirror = Layout(size: size(W, H), bottomInset: bottom, fold: mirroredFold, rightToLeft: false)
            mirrored.expect(rtl.arrangement == ltrOfMirror.arrangement
                            && same(rtl.onScreen(rtl.mac), mirror(ltrOfMirror.onScreen(ltrOfMirror.mac), W))
                            && same(rtl.onScreen(rtl.device), mirror(ltrOfMirror.onScreen(ltrOfMirror.device), W))
                            && same(rtl.onScreen(rtl.macScroll), mirror(ltrOfMirror.onScreen(ltrOfMirror.macScroll), W))
                            && same(rtl.onScreen(rtl.deviceScroll), mirror(ltrOfMirror.onScreen(ltrOfMirror.deviceScroll), W)),
                            "\(w)×\(h), \(fold): right to left \(rtl.description), the mirror's left to right \(ltrOfMirror.description)")
        }
    }
}
for rule in rules {
    check("\(rule.name) (\(gridLayouts) layouts)" + (rule.firstFailure.map { ": first at \($0)" } ?? ""), rule.firstFailure == nil)
}

// MARK: - Closing

typealias Close = SettingsPane.Close
check("Done (and Esc, ⌘., the escape gesture) and the harness's stand-in go back to the stream: the keyboard, VoiceOver's reading",
      Close.done.backToStream && Close.harness.backToStream)
check("the overlay, the tour, full screen and a bar's control take over: no keyboard, no reading",
      [Close.overlay, .tour, .fullScreen, .bar].allSatisfy { !$0.backToStream })
check("the tour and full screen wait for the pane's motion; nothing else does",
      Close.allCases.filter(\.waitsForClose) == [.tour, .fullScreen])
check("six ways", Close.allCases.count == 6)
check("the motion: 0.35 s up, 0.25 s down", SettingsPane.openSeconds == 0.35 && SettingsPane.closeSeconds == 0.25)

print(fails == 0 ? "settings-pane: all \(passes) checks pass" : "settings-pane: \(fails) of \(fails + passes) checks FAILED")
exit(fails == 0 ? 0 : 1)
