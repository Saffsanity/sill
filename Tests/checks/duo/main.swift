import Foundation
import CoreGraphics
// DuoPosture (iOSClient/DuoPosture.swift) on its own: the iPhone Duo's posture and the layout rules
// that follow from it (docs/iphone-duo-plan.md). What the iOS 27.1 simulator reported, pose by pose,
// as the inputs; the fold's band; the laptop pose's split at the real fold and open flat's at the
// picture's shape; the book pose's bar (the right group, the strip, the Settings panel) clear of the
// fold; a card, the connect column and the pairing overlay on one page; the inferred rules exactly
// as before iOS 27.1; the harness's stand-in against the device's numbers. Compiled with the file as
// it is:
//   swiftc -O iOSClient/DuoPosture.swift Tests/checks/duo/main.swift -o .build/checks/duo/check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func size(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

// MARK: - The device's numbers (the plan's Facts: the iOS 27.1 simulator, the status bar hidden)

let book = size(951, 669), upright = size(669, 951)
let cover = size(382, 678), coverSide = size(594, 466)          // the stream screen: the cover less its strip
let bookFold = rect(455.5, 0, 40, 669)                           // .division, margins included
let laptopFold = rect(0, 455.5, 669, 40)

let postures: [(DuoPosture, CGSize, DuoPosture.Pose, FoldInfo)] = [
    (DuoPosture(hinge: .partiallyOpen, fold: bookFold), book, .book, .known(bookFold)),
    (DuoPosture(hinge: .partiallyOpen, fold: laptopFold), upright, .laptop, .known(laptopFold)),
    (DuoPosture(hinge: .fullyOpen, fold: bookFold), book, .flatLandscape, .known(nil)),
    (DuoPosture(hinge: .fullyOpen, fold: laptopFold), upright, .flatPortrait, .known(nil)),
    (DuoPosture(hinge: .closed), cover, .closedUpright, .known(nil)),
    (DuoPosture(hinge: .closed), coverSide, .closedSide, .known(nil)),
    (DuoPosture.unknown, size(1000, 710), .unknown, .inferred),
    (DuoPosture.unknown, size(710, 1000), .unknown, .inferred),
]
for (p, s, pose, info) in postures {
    check(p.pose(s) == pose, "\(s): the pose \(p.pose(s)), expected \(pose)")
    check(p.info(in: s) == info, "\(pose): \(p.info(in: s)), expected \(info)")
}
check(DuoPosture.unknown.hinge == .unknown && DuoPosture.unknown.fold == nil && !DuoPosture.unknown.foldActive, "unknown is nothing")
check(DuoPosture(hinge: .partiallyOpen, fold: bookFold).foldActive, "half-folded: the fold in the way")
check(!DuoPosture(hinge: .fullyOpen, fold: bookFold).foldActive, "open flat: the fold reported, not in the way")
check(!DuoPosture(hinge: .partiallyOpen).foldActive && DuoPosture(hinge: .partiallyOpen).info(in: book) == .known(nil),
      "half-folded with no region (another display): nothing in the way, but known")
check(!DuoPosture(hinge: .closed, fold: bookFold).foldActive && DuoPosture(hinge: .closed, fold: bookFold).info(in: book) == .known(nil),
      "closed: never in the way")
check(DuoPosture(hinge: .unknown, fold: bookFold).info(in: book) == .inferred, "no hinge: inferred, whatever a region says")
// The proxy's regions are in its own space and not clipped to it (the probe: a 635 pt reader got the
// 669 pt region): the band is clipped to the screen.
check(DuoPosture(hinge: .partiallyOpen, fold: bookFold).info(in: size(951, 635)) == .known(rect(455.5, 0, 40, 635)), "clipped to the screen")
check(DuoPosture(hinge: .partiallyOpen, fold: rect(1000, 0, 40, 669)).info(in: book) == .known(nil), "a fold off the screen is none")
check(DuoPosture(hinge: .partiallyOpen, fold: rect(951, 0, 40, 669)).info(in: book) == .known(nil), "a fold only touching the screen is none")
// The laptop pose with the status bar shown (a reader at window y 82, 669×869): the fold moved up.
let shownFold = laptopFold.offsetBy(dx: 0, dy: -82)
check(DuoPosture(hinge: .partiallyOpen, fold: shownFold).info(in: size(669, 869)) == .known(rect(0, 373.5, 669, 40)), "in the reader's own space")
check(FoldInfo.known(bookFold).verticalBand == bookFold && FoldInfo.known(bookFold).horizontalBand == nil, "the book pose's fold is vertical")
check(FoldInfo.known(laptopFold).horizontalBand == laptopFold && FoldInfo.known(laptopFold).verticalBand == nil, "the laptop pose's is horizontal")
check(FoldInfo.inferred.band == nil && FoldInfo.known(nil).band == nil && FoldInfo.known(bookFold).band == bookFold, "band")
check(FoldInfo.known(rect(0, 0, 40, 40)).horizontalBand != nil && FoldInfo.known(rect(0, 0, 40, 40)).verticalBand == nil, "a square counts as across")
// The stream screen hides the status bar on the inner display in every pose (Noah's pick,
// 2026-10-09: option 1 of three): upright it would take 82 pt off the picture above the fold,
// sideways an 84 pt strip off the picture's width. It stays on the cover and off the Duo.
check(DuoPosture.hidesStatusBar(.laptop) && DuoPosture.hidesStatusBar(.flatPortrait), "hidden upright on the inner display")
check(DuoPosture.hidesStatusBar(.book) && DuoPosture.hidesStatusBar(.flatLandscape), "hidden sideways too")
check(!DuoPosture.hidesStatusBar(.closedUpright) && !DuoPosture.hidesStatusBar(.closedSide) && !DuoPosture.hidesStatusBar(.unknown),
      "shown on the cover and off the Duo")
// Whichever way it goes, the pose stays: shown upright the stream screen is 669×869, hidden 669×951;
// sideways 867×669 shown, 951×669 hidden. So hiding it never turns the screen and loops.
for (hinge, shown, hidden) in [(DuoPosture.Hinge.partiallyOpen, size(669, 869), upright), (.fullyOpen, size(669, 869), upright),
                               (.partiallyOpen, size(867, 669), book), (.fullyOpen, size(867, 669), book)] {
    let p = DuoPosture(hinge: hinge)
    check(DuoPosture.hidesStatusBar(p.pose(shown)) == DuoPosture.hidesStatusBar(p.pose(hidden)), "\(hinge) \(shown): the same rule either way")
}
check(DuoPosture(hinge: .partiallyOpen).onInnerDisplay && DuoPosture(hinge: .fullyOpen).onInnerDisplay
      && !DuoPosture(hinge: .closed).onInnerDisplay && !DuoPosture.unknown.onInnerDisplay, "the inner display: the hinge open")
// Before the hinge's first report: the fold says which display and whether it is folded.
check(DuoPosture.hinge(reported: .unknown, regionActive: true) == .partiallyOpen, "no report yet, the fold in the way: half-folded")
check(DuoPosture.hinge(reported: .unknown, regionActive: false) == .fullyOpen, "no report yet, the fold flat: open flat")
check(DuoPosture.hinge(reported: .unknown, regionActive: nil) == .unknown, "no report, no fold: unknown (any other device, the cover)")
for reported in [DuoPosture.Hinge.closed, .partiallyOpen, .fullyOpen] {
    for active in [true, false, nil] as [Bool?] {
        check(DuoPosture.hinge(reported: reported, regionActive: active) == reported, "a report wins: \(reported) \(String(describing: active))")
    }
}
check(DuoPosture(hinge: .partiallyOpen, fold: bookFold).describe(book) == "book, the fold x 455.5–495.5 in the way, 951×669", "the console's book")
check(DuoPosture(hinge: .fullyOpen, fold: laptopFold).describe(upright) == "flat-portrait, the fold y 455.5–495.5 flat, 669×951", "the console's flat")
check(DuoPosture(hinge: .closed).describe(cover) == "closed-upright, 382×678", "the console's cover")
check(DuoPosture.Pose.flatLandscape.rawValue == "flat-landscape" && DuoPosture.Pose.closedSide.rawValue == "closed-side"
      && DuoPosture.Pose.closedUpright.rawValue == "closed-upright" && DuoPosture.Pose.flatPortrait.rawValue == "flat-portrait",
      "duorig's words")

// MARK: - The crease (the laptop pose), inferred as before

func topHalf(_ s: CGSize) -> Bool { s.height > s.width && s.width >= 600 && s.width < 740 && s.height < 1100 }   // the rule before iOS 27.1
for w in stride(from: CGFloat(300), through: 1400, by: 7) {
    for h in stride(from: CGFloat(300), through: 1400, by: 11) {
        let s = size(w, h)
        let c = DuoPosture.crease(s, .inferred)
        check((c != nil) == topHalf(s), "inferred crease at \(s)")
        if let c { check(c.top == h / 2 && c.bottom == h / 2, "the inferred crease is the middle at \(s)") }
        let split = DuoPosture.portraitSplit(s, .inferred, aspect: 1.6, controls: 180)
        check(split == DuoPosture.PortraitSplit(picture: (h / 2).rounded(), controls: (h / 2).rounded()), "inferred: the halves at the middle, \(s)")
        check(DuoPosture.columnX(columnWidth: 380, screenWidth: w, fold: .inferred) == max(16, (w - 380) / 2), "inferred: the column centred, \(w)")
    }
}
check(DuoPosture.crease(size(710, 1000), .inferred)! == (500, 500), "the guessed Duo's crease at 500")
check(DuoPosture.crease(upright, .inferred)! == (475.5, 475.5), "the real Duo's size, inferred: 475.5")
check(DuoPosture.crease(upright, .known(laptopFold))! == (455.5, 495.5), "the laptop pose: the fold's band")
check(DuoPosture.crease(upright, .known(nil)) == nil, "open flat upright: no crease")
check(DuoPosture.crease(book, .known(bookFold)) == nil, "the book pose: no crease across")
check(DuoPosture.crease(size(669, 869), .known(rect(0, 373.5, 669, 40)))! == (373.5, 413.5), "the status bar shown: the fold where the reader sees it")

// MARK: - The halves' split (approved (b1) and (b2))

let controls: CGFloat = 12 + 78 + 2 * 10 + 48 + 22     // PortraitMetrics.regular's controls but the trackpad: 180
check(controls == 180, "the regular halves' controls")
// (b1) The laptop pose: the picture above the fold, the controls below it, in whole points.
check(DuoPosture.portraitSplit(upright, .known(laptopFold), aspect: 1.6, controls: controls) == .init(picture: 455, controls: 496),
      "the laptop pose: 455 and 496")
check(DuoPosture.portraitSplit(upright, .known(laptopFold), aspect: 0.5, controls: controls) == .init(picture: 455, controls: 496),
      "the laptop pose: whatever the picture's shape")
check(DuoPosture.portraitSplit(size(669, 869), .known(rect(0, 373.5, 669, 40)), aspect: 1.6, controls: controls) == .init(picture: 373, controls: 414),
      "the status bar shown")
// (b2) Open flat: the pane at the picture's shape across the width, the trackpad takes the rest.
func flat(_ aspect: CGFloat, _ s: CGSize = upright) -> DuoPosture.PortraitSplit {
    DuoPosture.portraitSplit(s, .known(nil), aspect: aspect, controls: controls)
}
check(flat(1.6) == .init(picture: 424, controls: 424), "16:10: 653×408 and its 8 pt")
check(flat(1512.0 / 982) == .init(picture: 440, controls: 440), "a MacBook's Desktop, 1512×982")
check(flat(16.0 / 9) == .init(picture: 383, controls: 383), "16:9")
check(flat(4.0 / 3) == .init(picture: 506, controls: 506), "4:3")
check(flat(0.8) == .init(picture: 571, controls: 571), "a tall window: as tall as leaves the trackpad 200")
check(flat(8) == .init(picture: 160, controls: 160), "a very wide one: never under 160")
check(flat(1.6, size(669, 500)) == .init(picture: 120, controls: 120), "a short screen: the trackpad's 200 first")
check(flat(0) == flat(0.1), "a zero shape is guarded")
for w in stride(from: CGFloat(600), through: 800, by: 13) {
    for h in stride(from: CGFloat(500), through: 1300, by: 17) {
        for aspect in stride(from: CGFloat(0.3), through: 4.0, by: 0.23) {
            let s = size(w, h)
            let f = flat(aspect, s)
            let most = max(0, h - controls - DuoPosture.minimumTrackpad)
            check(f.picture == f.controls, "flat: nothing between, \(s) \(aspect)")
            check(f.picture <= most + 0.001 && f.picture >= min(DuoPosture.minimumPane, most) - 0.001, "flat: within its bounds, \(s) \(aspect)")
            check(f.picture == f.picture.rounded(), "flat: whole points, \(s) \(aspect)")
            let natural = ((w - 16) / aspect).rounded() + 16
            if natural <= most && natural >= DuoPosture.minimumPane { check(f.picture == natural, "flat: the picture's shape, \(s) \(aspect)") }
            if most >= DuoPosture.minimumPane { check(h - f.controls - controls >= DuoPosture.minimumTrackpad - 0.001, "flat: the trackpad's 200, \(s) \(aspect)") }
            // A fold anywhere across: never into it, whole points.
            let band = rect(0, (h / 2 - 20).rounded(.down) + 0.5, w, 40)
            let half = DuoPosture.portraitSplit(s, .known(band), aspect: aspect, controls: controls)
            check(half.picture <= band.minY && half.controls >= band.maxY && half.picture == half.picture.rounded()
                  && half.controls == half.controls.rounded() && half.controls - half.picture <= 41, "half-folded \(s)")
        }
    }
}
// The pane's shape.
check(DuoPosture.paneAspect(video: .zero, fitsWindowToPane: false) == 1.6, "no picture yet: 16:10")
check(DuoPosture.paneAspect(video: size(3024, 1964), fitsWindowToPane: false) == 3024.0 / 1964, "the picture's own")
check(DuoPosture.paneAspect(video: size(3024, 1964), fitsWindowToPane: true) == 1.6, "a window the Mac fits to the pane: 16:10")
check(DuoPosture.paneAspect(video: size(1920, 0), fitsWindowToPane: false) == 1.6 && DuoPosture.paneAspect(video: size(0, 1080), fitsWindowToPane: false) == 1.6,
      "half a size is none")

// MARK: - The book pose's bar (approved (a))

func bar(_ w: CGFloat, _ fold: FoldInfo, regular: Bool = true, buttons: Int = 5) -> DuoPosture.BookBar {
    regular ? DuoPosture.bookBar(width: w, fold: fold, padding: 22, gap: 12, buttonWidth: 66, compactButtonWidth: 64, buttons: buttons, panelWidth: 360)
            : DuoPosture.bookBar(width: w, fold: fold, padding: 14, gap: 12, buttonWidth: 64, compactButtonWidth: 64, buttons: buttons, panelWidth: 340)
}
func groupStart(_ w: CGFloat, _ b: DuoPosture.BookBar, padding: CGFloat = 22, buttons: Int = 5) -> CGFloat {
    w - padding - CGFloat(buttons) * b.buttonWidth - CGFloat(buttons - 1) * b.gap
}
// At 951 pt the regular group begins at 551, 55.5 pt past the fold: it keeps its size; the strip
// ends 12 pt short of the fold.
let b951 = bar(951, .known(bookFold))
check(b951 == DuoPosture.BookBar(buttonWidth: 66, gap: 12, stripWidth: 343.5, panelWidth: 360, clears: true), "951: \(b951)")
check(groupStart(951, b951) == 551 && 22 + 66 + 12 + b951.stripWidth! + 12 == 455.5, "951: the group at 551, the strip to 443.5")
// The status bar shown (867 pt): the compact width, then a 7 pt gap: Menus at 497.
let b867 = bar(867, .known(bookFold))
check(b867 == DuoPosture.BookBar(buttonWidth: 64, gap: 7, stripWidth: 355.5, panelWidth: 349.5, clears: true), "867: \(b867)")
check(groupStart(867, b867) == 497, "867: Menus clears the fold")
// The approved step alone, where it is enough (885.5 to 895.5 pt).
let b890 = bar(890, .known(bookFold))
check(b890.buttonWidth == 64 && b890.gap == 12 && groupStart(890, b890) == 500 && b890.clears, "890: compact, the gaps kept: \(b890)")
let b880 = bar(880, .known(bookFold))
check(b880.buttonWidth == 64 && b880.gap == 10 && groupStart(880, b880) == 498 && b880.clears, "880: compact, then 10 pt gaps: \(b880)")
// Nothing to clear: the bar as before.
let unchanged = DuoPosture.BookBar(buttonWidth: 66, gap: 12, stripWidth: nil, panelWidth: 360, clears: true)
check(bar(951, .inferred) == unchanged && bar(951, .known(nil)) == unchanged, "no fold: as before")
check(bar(669, .known(laptopFold)) == unchanged, "a fold across: not the book pose's bar")
check(bar(951, .known(rect(100, 300, 600, 40))) == unchanged, "a fold across, however placed: not the book pose's bar")
check(bar(951, .known(rect(10, 0, 40, 669))) == unchanged && bar(951, .known(rect(915, 0, 40, 669))) == unchanged, "a fold at the bar's ends: as before")
check(bar(594, .known(nil), regular: false) == DuoPosture.BookBar(buttonWidth: 64, gap: 12, stripWidth: nil, panelWidth: 340, clears: true), "the cover on its side: as before")
// Too narrow for any step: the strip still ends short of the fold, and it says so.
let b700 = bar(700, .known(rect(330, 0, 40, 500)))
check(b700.buttonWidth == 64 && b700.gap == 6 && !b700.clears && 22 + 64 + 6 + b700.stripWidth! + 6 == 330, "700: \(b700)")
check(bar(951, .known(bookFold), buttons: 0) == unchanged, "no buttons: nothing to place")
check(bar(951, .known(bookFold), buttons: 1).clears && bar(951, .known(bookFold), buttons: 1).gap == 12, "one button")
for w in stride(from: CGFloat(700), through: 1400, by: 1) {
    for width in [CGFloat(40), 60] {
        let band = rect((w / 2 - width / 2), 0, width, 669)
        for buttons in 1...6 {
            let b = bar(w, .known(band), buttons: buttons)
            let start = groupStart(w, b, buttons: buttons)
            check(b.stripWidth != nil, "\(w): a strip width")
            check(b.buttonWidth == 66 || b.buttonWidth == 64, "\(w): a bar button's width")
            check(b.gap >= DuoPosture.minimumGap && b.gap <= 12, "\(w): the gap within 6 and 12")
            check(b.clears == (start >= band.maxX), "\(w): clears says what is")
            if b.clears { check(start >= band.maxX, "\(w) \(buttons): the group past the fold") }
            // The regular group kept wherever it begins past the fold; the compact step only otherwise.
            let regularStart = w - 22 - CGFloat(buttons) * 66 - CGFloat(buttons - 1) * 12
            check((regularStart >= band.maxX) == (b.buttonWidth == 66 && b.gap == 12), "\(w) \(buttons): the regular group kept iff it clears")
            check(b.stripWidth! >= 0 && 22 + b.buttonWidth + b.gap + b.stripWidth! + b.gap <= band.minX + 0.001, "\(w): the strip ends short of the fold")
            check(b.stripWidth == 0 || 22 + b.buttonWidth + b.gap + b.stripWidth! + b.gap == band.minX, "\(w): the strip reaches the fold's edge less a gap")
            check(b.panelWidth <= 360 && (b.panelWidth == 0 || w - 22 - b.panelWidth >= band.maxX - 0.001), "\(w): the panel past the fold")
            check(b.panelWidth == min(360, w - 22 - band.maxX), "\(w): the panel as wide as it may be")
        }
    }
}

// MARK: - One page: a tour card, the connect column, the pairing overlay

func page(_ x: CGFloat, _ w: CGFloat, _ fold: FoldInfo, screen: CGFloat = 951) -> CGFloat {
    DuoPosture.offTheFold(x: x, width: w, screenWidth: screen, margin: 16, fold: fold)
}
check(page(295.5, 360, .known(bookFold)) == 95.5, "the picture's card, centred on the fold: the leading page, against the fold")
check(page(482, 360, .known(bookFold)) == 495.5, "Aa's card: the trailing page")
check(page(91.75, 360, .known(bookFold)) == 91.75 && page(575, 360, .known(bookFold)) == 575, "clear of the fold: where it was")
check(page(100, 360, .known(bookFold)) == 95.5, "a hair over: back to the fold's edge")
check(page(100, 440, .known(bookFold)) == 100, "no page holds 440: as it was")
check(page(300, 360, .inferred) == 300 && page(300, 360, .known(nil)) == 300 && page(300, 360, .known(laptopFold)) == 300, "no vertical fold: as it was")
// A fold off the middle: a card on the narrow side that only the wide page holds goes there.
let offMiddle = FoldInfo.known(rect(300, 0, 40, 669))
check(page(50, 360, offMiddle) == 340, "its middle on the leading page, too narrow: the trailing one")
check(page(200, 360, offMiddle) == 340, "its middle on the trailing page: there")
check(page(500, 360, .known(rect(651, 0, 40, 669))) == 291, "the trailing page too narrow: the leading one")
for x in stride(from: CGFloat(-50), through: 1000, by: 3.5) {
    for w in stride(from: CGFloat(100), through: 600, by: 20) {
        for fold in [FoldInfo.known(bookFold), offMiddle, .known(rect(600, 0, 40, 669))] {
            let band = fold.verticalBand!
            let moved = page(x, w, fold)
            let crossed = x < band.maxX && x + w > band.minX
            let held = w <= band.minX - 16 || w <= 951 - 16 - band.maxX
            if !crossed { check(moved == x, "clear: unchanged \(x) \(w)") }
            if crossed && held {
                check(moved + w <= band.minX + 0.001 || moved >= band.maxX - 0.001, "never across the fold: \(x) \(w) \(band) → \(moved)")
                check(moved >= 16 - 0.001 && moved + w <= 951 - 16 + 0.001, "within the margins: \(x) \(w) → \(moved)")
            }
            if crossed && !held { check(moved == x, "no page holds it: unchanged \(x) \(w)") }
        }
    }
}
check(DuoPosture.pageWidth(screenWidth: 951, margin: 16, fold: .known(bookFold)) == 439.5, "the book pose's page: 439.5")
check(DuoPosture.pageWidth(screenWidth: 951, margin: 16, fold: offMiddle) == 595, "the wider page")
// The page a card's targets are on: with the status bar shown (867 pt) the trailing page is 355.5,
// so a card about Settings stays beside it rather than go to the far page.
let settingsButton = rect(781, 10, 64, 66), stripTargets = rect(93, 5, 355.5, 77)
check(DuoPosture.pageWidth(screenWidth: 867, margin: 16, fold: .known(bookFold), for: settingsButton) == 355.5, "867: Settings' page, 355.5")
check(DuoPosture.pageWidth(screenWidth: 867, margin: 16, fold: .known(bookFold), for: stripTargets) == 439.5, "867: the strip's page, 439.5")
check(DuoPosture.pageWidth(screenWidth: 867, margin: 16, fold: .known(bookFold)) == 439.5, "867, no target: the wider page")
check(DuoPosture.pageWidth(screenWidth: 951, margin: 16, fold: .known(bookFold), for: rect(8, 94, 935, 567)) == 439.5
      && DuoPosture.pageWidth(screenWidth: 867, margin: 16, fold: .known(bookFold), for: rect(455.5, 94, 40, 567)) == 439.5,
      "a target centred on the fold: the leading page, as offTheFold's tie")
check(DuoPosture.pageWidth(screenWidth: 951, margin: 16, fold: .known(bookFold), for: rect(476, 0, 10, 10)) == 439.5, "past the middle: the trailing page")
check(DuoPosture.pageWidth(screenWidth: 951, margin: 16, fold: .known(bookFold), for: .null) == 439.5, "a null target: as none")
check(DuoPosture.pageWidth(screenWidth: 669, margin: 16, fold: .known(laptopFold), for: settingsButton) == nil, "no vertical fold: no page")
// A card as wide as its targets' page, placed on it, never goes to the far page.
for w in stride(from: CGFloat(800), through: 1000, by: 1) {
    let fold = FoldInfo.known(rect(455.5, 0, 40, 669))
    for target in [rect(w - 22 - 64, 10, 64, 66), rect(22, 10, 64, 66), rect(500, 10, 64, 66), rect(380, 10, 64, 66)] {
        let width = min(360, DuoPosture.pageWidth(screenWidth: w, margin: 16, fold: fold, for: target)!)
        let centred = min(max(target.midX - width / 2, 16), w - 16 - width)
        let x = page(centred, width, fold, screen: w)
        let onTargetsPage = target.midX <= 475.5 ? x + width <= 455.5 + 0.001 : x >= 495.5 - 0.001
        check(onTargetsPage, "\(w): a card about \(target) on its page (at \(x), \(width) wide)")
    }
}
check(DuoPosture.pageWidth(screenWidth: 951, margin: 16, fold: .inferred) == nil && DuoPosture.pageWidth(screenWidth: 669, margin: 16, fold: .known(laptopFold)) == nil,
      "no vertical fold: no page")
// The connect column: centred in the leading page while it holds it with 16 pt each side.
check(DuoPosture.columnX(columnWidth: 380, screenWidth: 951, fold: .known(bookFold)) == 37.75, "the book pose: the leading page")
check(DuoPosture.columnX(columnWidth: 380, screenWidth: 951, fold: .known(nil)) == 285.5, "open flat: centred")
check(DuoPosture.columnX(columnWidth: 380, screenWidth: 951, fold: .known(rect(400, 0, 40, 669))) == 285.5, "a page too narrow: centred")
check(DuoPosture.columnX(columnWidth: 380, screenWidth: 951, fold: .known(rect(412, 0, 40, 669))) == 16, "a page just wide enough")
check(DuoPosture.columnX(columnWidth: 380, screenWidth: 669, fold: .known(laptopFold)) == 144.5, "the laptop pose: centred (it goes above the fold)")
check(DuoPosture.leadingPage(.known(bookFold)) == 455.5 && DuoPosture.leadingPage(.known(laptopFold)) == nil
      && DuoPosture.leadingPage(.inferred) == nil && DuoPosture.leadingPage(.known(nil)) == nil, "the leading page")
check(DuoPosture.leadingPage(.known(rect(-10, 0, 40, 669))) == 0, "never negative")
// The connect screen's room above the laptop pose's fold: only where the device said.
check(DuoPosture.roomAboveFold(upright, .known(laptopFold)) == 455.5, "the laptop pose: 455.5 above the fold")
check(DuoPosture.roomAboveFold(size(669, 835), .known(rect(0, 373.5, 669, 40))) == 373.5, "with the status bar: 373.5")
check(DuoPosture.roomAboveFold(size(710, 1000), .inferred) == nil && DuoPosture.roomAboveFold(upright, .inferred) == nil,
      "the inferred crease: none (only centred in the top half, as before)")
check(DuoPosture.roomAboveFold(upright, .known(nil)) == nil && DuoPosture.roomAboveFold(book, .known(bookFold)) == nil, "open flat, the book pose: none")

// The window lights' menu: as before where nothing folds; beside the book pose's fold onto a page,
// and below its thumbnail in the laptop pose, whose window bar sits just under the fold.
func lights(_ x: CGFloat, below: Bool, _ thumb: CGRect, _ fold: FoldInfo, screen: CGFloat = 951) -> (x: CGFloat, y: CGFloat, below: Bool) {
    DuoPosture.lightsMenu(x: x, below: below, thumbnail: thumb, size: size(214, 62), gap: 8, screenWidth: screen, fold: fold)
}
let barThumb = rect(108, 518, 104, 58), stripThumb = rect(348, 15, 104, 66)
for fold in [FoldInfo.inferred, .known(nil)] {
    let up = lights(160, below: false, barThumb, fold), down = lights(400, below: true, stripThumb, fold)
    check(up.x == 160 && up.y == 518 - 8 - 31 && !up.below, "\(fold): above, as before")
    check(down.x == 400 && down.y == 81 + 8 + 31 && down.below, "\(fold): below, as before")
}
let flipped = lights(160, below: false, barThumb, .known(laptopFold), screen: 669)
check(flipped.x == 160 && flipped.y == 576 + 8 + 31 && flipped.below, "the laptop pose: below the thumbnail, off the fold: \(flipped)")
let clearAbove = lights(160, below: false, rect(108, 700, 104, 58), .known(laptopFold), screen: 669)
check(clearAbove.y == 700 - 8 - 31 && !clearAbove.below, "the laptop pose, a thumbnail far under the fold: above, as before")
let paged = lights(400, below: true, stripThumb, .known(bookFold))
check(paged.x == 348.5 && paged.y == 120 && paged.below, "the book pose: onto the leading page: \(paged)")
check(lights(250, below: true, stripThumb, .known(bookFold)).x == 250, "the book pose, clear of the fold: where it was")
for x in stride(from: CGFloat(115), through: 836, by: 7) {
    for y in stride(from: CGFloat(0), through: 900, by: 23) {
        let t = rect(x - 52, y, 104, 58)
        for (fold, screen) in [(FoldInfo.known(bookFold), CGFloat(951)), (.known(laptopFold), 669)] {
            guard x <= screen - 115 else { continue }
            for below in [false, true] {
                let m = lights(x, below: below, t, fold, screen: screen)
                let r = rect(m.x - 107, m.y - 31, 214, 62)
                if let band = fold.verticalBand { check(!r.intersects(band), "never across the book pose's fold: \(x),\(y) \(r)") }
                if let band = fold.horizontalBand, !below, !rect(x - 107, t.maxY + 8, 214, 62).intersects(band) {
                    check(!r.intersects(band), "never on the laptop pose's fold where below is clear: \(x),\(y) \(r)")
                }
                if below { check(m.below && m.y == t.maxY + 8 + 31, "below stays below") }
            }
        }
    }
}

// MARK: - The harness's stand-in

check(DuoPosture.hinge(argument: "closed") == .closed && DuoPosture.hinge(argument: "half") == .partiallyOpen
      && DuoPosture.hinge(argument: "flat") == .fullyOpen && DuoPosture.hinge(argument: "HALF") == .partiallyOpen, "-SillHinge")
check(DuoPosture.hinge(argument: nil) == nil && DuoPosture.hinge(argument: "open") == nil && DuoPosture.hinge(argument: "") == nil, "-SillHinge: nothing else")
check(DuoPosture.standInFold(book) == bookFold && DuoPosture.standInFold(upright) == laptopFold, "the stand-in is the device's fold")
check(DuoPosture.standInFold(size(1000, 710)) == rect(480, 0, 40, 710) && DuoPosture.standInFold(size(710, 1000)) == rect(0, 480, 710, 40), "at any size")
check(DuoPosture.displaySpace == "sill.display", "the fake display's space")
func insets(_ s: CGSize, hidden: Bool = false) -> [CGFloat]? {
    DuoPosture.displayInsets(s, statusBarHidden: hidden).map { [$0.top, $0.leading, $0.bottom, $0.trailing] }
}
check(insets(book) == [0, 0, 34, 84] && insets(upright) == [82, 0, 34, 0], "the inner display with its status bar: 84 at the side, 82 at the top")
check(insets(book, hidden: true) == [0, 0, 34, 0] && insets(upright, hidden: true) == [0, 0, 34, 0], "hidden: the home indicator alone")
check(insets(size(466, 678)) == [0, 0, 34, 84] && insets(size(678, 466)) == [0, 84, 34, 0]
      && insets(size(466, 678), hidden: true) == [0, 0, 34, 84] && insets(size(678, 466), hidden: true) == [0, 84, 34, 0],
      "the cover: its camera's strip, either way")
check(insets(size(1000, 710)) == nil && insets(size(382, 678)) == nil && insets(size(710, 1000)) == nil, "any other size: none")
// The stand-in through the whole chain gives what the device gave.
for (hinge, s, info) in [(DuoPosture.Hinge.partiallyOpen, book, FoldInfo.known(bookFold)), (.partiallyOpen, upright, .known(laptopFold)),
                         (.fullyOpen, book, .known(nil)), (.fullyOpen, upright, .known(nil))] {
    check(DuoPosture(hinge: hinge, fold: DuoPosture.standInFold(s)).info(in: s) == info, "the stand-in, \(hinge) \(s)")
}

// MARK: - The inner display upright with the software keyboard up: the key row alone, or the toggle (#215)

// What UIKit reported on the iOS 27.1 simulator's Duo in the laptop pose, the dark keyboard with no
// predictive bar (the reporter's): shown, the whole lower page from the fold's top edge (0, 455.5,
// 669×495.5); going, its own frame (0, 555, 669×396), whose top is the glass's edge in a screenshot (the
// reporter's too: the glass at 555, the keys from 568). The Chinese (Pinyin) and emoji keyboards: shown, the
// same page; going, (0, 506, 669×445). A switch while it is up (2026-11-10): UITextInputMode's notification,
// then the keyboard's, its begin the keyboard left (0, 555, 669×396 or 0, 506, 669×445), its end the page
// again. Open flat upright every keyboard is reported as itself: English (0, 640, 669×311), emoji (0, 553,
// 669×398), Pinyin (0, 600, 669×351).
let deckTop: CGFloat = 455.5, glassTop: CGFloat = 555
typealias Glass = DuoPosture.KeyboardGlass
func glass(_ reported: CGFloat?, letters: CGFloat? = 396, plane: DuoPosture.KeyboardPlane = .letters, laptop: Bool = true,
           height: CGFloat = 951, controls: CGFloat = 496) -> Glass? {
    DuoPosture.keyboardGlass(reported: reported, screenHeight: height, controlsTop: controls, laptop: laptop, plane: plane, letters: letters)
}
func sure(_ top: CGFloat) -> Glass { Glass(top: top, sure: true) }
func assumed(_ top: CGFloat) -> Glass { Glass(top: top, sure: false) }
check(DuoPosture.laptopKeyboardHeight == 396, "the Duo's keyboard upright: 396 pt, the glass from 555")
check(DuoPosture.measuredLaptopKeyboard(mode: "en-US") == 396 && DuoPosture.measuredLaptopKeyboard(mode: "en-GB") == 396
      && DuoPosture.measuredLaptopKeyboard(mode: "en") == 396, "the English keyboards measured: 396")
check(DuoPosture.measuredLaptopKeyboard(mode: "zh-Hans") == 445, "Pinyin measured: 445")
check(DuoPosture.measuredLaptopKeyboard(mode: "ja-JP") == nil && DuoPosture.measuredLaptopKeyboard(mode: "fr-FR") == nil
      && DuoPosture.measuredLaptopKeyboard(mode: "zh-Hant") == nil && DuoPosture.measuredLaptopKeyboard(mode: nil) == nil
      && DuoPosture.measuredLaptopKeyboard(mode: "eng") == nil && DuoPosture.measuredLaptopKeyboard(mode: "emoji") == nil,
      "any other input mode: not measured")
check(glass(deckTop) == sure(glassTop), "the lower page reported, the English keyboard: the glass 396 above the foot, 555, sure")
check(glass(deckTop, letters: 420) == sure(531), "a taller letters keyboard learned: its glass")
check(glass(deckTop, letters: 445) == sure(506), "Pinyin (measured or learned): its glass at 506")
check(glass(deckTop, letters: nil) == assumed(glassTop), "an input mode not measured: the glass assumed at 555, not sure")
check(glass(deckTop, letters: 454) == sure(497) && glass(deckTop, letters: 455) == assumed(glassTop) && glass(deckTop, letters: 495.5) == assumed(glassTop)
      && glass(deckTop, letters: 600) == assumed(glassTop) && glass(deckTop, letters: 0) == assumed(glassTop) && glass(deckTop, letters: -10) == assumed(glassTop),
      "a height that would put the glass at or above the fold's edge is none: 396 assumed")
check(glass(500, height: 600, controls: 550) == assumed(500) || glass(500, height: 600, controls: 550) == sure(500),
      "never above the report (a screen too short for the measured keyboard)")
check(glass(400, letters: 445) == sure(506), "a report over the page: the glass its height gives")
check(glass(496) == sure(glassTop) && glass(495.9) == sure(glassTop), "a report at the fold's lower edge is the page too")
check(glass(530) == sure(530) && glass(496.5) == sure(496.5) && glass(700, letters: 100) == sure(700) && glass(554.5) == sure(554.5),
      "a report under the fold's edge and over the glass its height gives: the keyboard as itself")
check(glass(570) == sure(glassTop) && glass(555) == sure(glassTop) && glass(950) == sure(glassTop),
      "a report under the glass its height gives: that glass, never lower")
check(glass(640) == sure(glassTop) && glass(640, letters: 445) == sure(506) && glass(640, letters: 311) == sure(640),
      "folded from open flat with the keyboard up (640 reported, the keyboard 396): 555")
check(glass(nil) == nil && glass(951) == nil && glass(960) == nil && glass(nil, laptop: false) == nil && glass(951, laptop: false) == nil,
      "none up, or one gone below the foot: none")
check(glass(373.5, height: 869, controls: 414) == sure(473), "the status bar shown (669×869): the page from 373.5, the glass at 473")
// Another keyboard of the mode in the laptop pose: its glass is never reported there.
check(glass(deckTop, plane: .other) == Glass(top: nil, sure: false) && glass(640, plane: .other) == Glass(top: nil, sure: false)
      && glass(deckTop, letters: nil, plane: .other) == Glass(top: nil, sure: false),
      "the emoji keyboard (another of the mode) in the laptop pose: no glass known")
check(glass(nil, plane: .other) == nil && glass(951, plane: .other) == nil, "another of the mode gone: none")
// Open flat: the report is the glass, whatever the plane and the learned heights.
check(glass(640, laptop: false, controls: 424) == sure(640) && glass(553, laptop: false, controls: 424) == sure(553)
      && glass(600, letters: nil, plane: .other, laptop: false, controls: 424) == sure(600) && glass(300, laptop: false, controls: 424) == sure(300),
      "open flat: the keyboard as reported (English 640, emoji 553, Pinyin 600), live")

// The height KeyboardFrameMonitor remembers from a hide or a switch: the frame the keyboard leaves (the
// begin), only where UIKit reported it from above that while it was up (the laptop pose's lower page). Open
// flat upright UIKit reports the English keyboard as itself, (0, 640, 669×311): nothing to learn there, and
// learning it put the laptop pose's row at 539–597 over a glass at 555 (the iOS 27.1 simulator, 2026-11-09).
let page = rect(0, 455.5, 669, 495.5), screen = rect(0, 0, 669, 951)
func learned(_ begin: CGRect?, shown: CGRect? = page, screen s: CGRect? = screen) -> CGFloat? {
    DuoPosture.keyboardHeightToLearn(leaving: begin, shown: shown, screen: s)
}
check(learned(rect(0, 555, 669, 396)) == 396, "the laptop pose, the English keyboard going: 396")
check(learned(rect(0, 506, 669, 445)) == 445, "the laptop pose, the Chinese or emoji keyboard going: 445")
check(learned(rect(0, 640, 669, 311), shown: rect(0, 640, 669, 311)) == nil, "open flat, reported as itself: nothing")
check(learned(rect(0, 640, 669, 311), shown: rect(0, 639.8, 669, 311.2)) == nil, "reported as itself to within half a point: nothing")
check(learned(rect(0, 555, 669, 396), shown: rect(0, 554.5, 669, 396.5)) == nil && learned(rect(0, 555, 669, 396), shown: rect(0, 554.4, 669, 396.6)) == 396,
      "reported from more than half a point above its glass: learned")
check(learned(rect(0, 555, 669, 396), shown: nil) == nil, "nothing reported while it was up: nothing")
check(learned(rect(0, 555, 669, 396), shown: rect(0, 951, 669, 396)) == nil && learned(rect(0, 555, 669, 396), shown: rect(0, 640, 669, 311)) == nil,
      "a report under its glass (at the foot, or a shorter keyboard's): nothing")
check(learned(rect(0, 788.9, 669, 162.1), screen: rect(0, 0, 951, 669)) == nil, "the fold to the book pose (the screen turned first): nothing")
check(learned(rect(0, 555, 669, 396), screen: rect(0, 0, 700, 951)) == nil && learned(rect(0, 555, 600, 396)) == nil,
      "a frame not across the screen (another width), down to its foot all the same: nothing")
check(learned(rect(0, 500, 669, 300)) == nil && learned(rect(0, 555, 669, 395)) == nil, "not down to the foot: nothing")
check(learned(rect(0, 951, 669, 0)) == nil && learned(nil) == nil && learned(rect(0, 555, 669, 396), screen: nil) == nil,
      "no height, no frame, no screen: nothing")
check(learned(rect(0, 473, 669, 396), shown: rect(0, 373.5, 669, 495.5), screen: rect(0, 0, 669, 869)) == 396, "the status bar shown: 396")
check(glass(deckTop, letters: learned(rect(0, 640, 669, 311), shown: rect(0, 640, 669, 311))) == assumed(glassTop),
      "open flat then the laptop pose: the glass at 555, not 640 (assumed: nothing learned, no input mode measured)")

// The plane after a switch while the keyboard is up (2026-11-10, the iOS 27.1 simulator).
func plane(modeChanged: Bool = false, shown: CGRect? = page, begin: CGRect?, end: CGRect? = page, letters: CGFloat? = 396,
           lettersShown: CGFloat? = nil) -> DuoPosture.KeyboardPlane {
    DuoPosture.planeAfterSwitch(modeChanged: modeChanged, shown: shown, begin: begin, end: end, letters: letters, lettersShown: lettersShown)
}
let english = rect(0, 555, 669, 396), emoji = rect(0, 506, 669, 445)
check(plane(begin: english) == .other, "the laptop pose, 😀 from the English keyboard (the 396 left): another")
check(plane(begin: emoji) == .letters, "the laptop pose, ABC from the emoji keyboard (the 445 left): the letters keyboard again")
check(plane(begin: english, end: page) == .other, "the laptop pose, the emoji search from the emoji keyboard (reported as the 396 left): another")
check(plane(begin: emoji, letters: 445) == .other && plane(begin: emoji, letters: 444) == .other && plane(begin: emoji, letters: 443.9) == .letters,
      "the one left must be more than a point taller than the letters keyboard: Pinyin's 445 and its emoji keyboard's: another")
check(plane(begin: emoji, letters: nil) == .other, "an input mode not measured: never the letters keyboard by a switch")
check(plane(modeChanged: true, begin: english) == .letters && plane(modeChanged: true, begin: nil, end: nil) == .letters,
      "another input mode (the Globe key): its letters keyboard")
check(plane(begin: nil, end: nil) == .other && plane(begin: emoji, end: nil) == .other && plane(begin: nil) == .other,
      "no keyboard notification after the input mode's (the emoji search back to the emoji keyboard): another")
check(plane(begin: rect(0, 951, 669, 0)) == .other && plane(begin: emoji, end: rect(0, 951, 669, 0)) == .other, "frames of no height: another")
// Open flat: reported as itself.
let flatEnglish = rect(0, 640, 669, 311), flatEmoji = rect(0, 553, 669, 398)
check(plane(shown: flatEnglish, begin: flatEnglish, end: flatEmoji, lettersShown: 311) == .other, "open flat, 😀: the emoji keyboard, another")
check(plane(shown: flatEmoji, begin: flatEmoji, end: flatEnglish, lettersShown: 311) == .letters, "open flat, ABC: the letters keyboard, at its 311 again")
check(plane(shown: flatEmoji, begin: flatEmoji, end: rect(0, 640.4, 669, 310.6), lettersShown: 311) == .letters
      && plane(shown: flatEmoji, begin: flatEmoji, end: rect(0, 641, 669, 310), lettersShown: 311) == .other,
      "open flat: the letters keyboard's height to within half a point")
check(plane(shown: flatEmoji, begin: flatEmoji, end: flatEnglish, lettersShown: nil) == .other, "open flat, no letters height seen: another")
check(plane(shown: rect(0, 554.6, 669, 396.4), begin: english, end: page, lettersShown: 311) == .other,
      "reported from within half a point of the glass left: as itself, and the page is not the letters keyboard's height")
// A fold from open flat with the emoji keyboard up, then ABC in the laptop pose: the report still the open flat
// keyboard's (553) when the switch comes would be read as itself; after the page has come, as the page.
check(plane(shown: page, begin: rect(0, 504, 669, 447), lettersShown: 495.5) == .letters, "the page shown, the 447 left: the letters keyboard")

func standIn(_ g: Glass?, controls: CGFloat = 496, fold: FoldInfo = .known(laptopFold), size s: CGSize = upright,
             standard: CGFloat = 148) -> DuoPosture.KeyboardStandIn? {
    DuoPosture.keyboardStandIn(size: s, fold: fold, controlsTop: controls, glass: g, standardRows: standard, sides: 14)
}
func row(_ y: CGFloat, _ caps: CGFloat) -> DuoPosture.KeyboardStandIn { .init(row: rect(14, y, 641, caps), toggle: false) }
func rowAndToggle(_ y: CGFloat, _ caps: CGFloat) -> DuoPosture.KeyboardStandIn { .init(row: rect(14, y, 641, caps), toggle: true) }
let toggleAlone = DuoPosture.KeyboardStandIn(row: nil, toggle: true)
// Noah's numbers (2026-10-27, "A"): under the fold the caps the room less 8, at most 58, the black above
// and below alike.
check(standIn(sure(glassTop)) == row(500, 51), "the Duo's keyboard: 4 + 51 + 4, \(String(describing: standIn(sure(glassTop))))")
check(standIn(sure(570)) == row(504, 58), "a 381 pt keyboard: 8 + 58 + 8")
check(standIn(sure(571)) == row(504, 58), "75 pt: 58 caps, 8 above and 9 below (within a point)")
check(standIn(sure(552)) == row(500, 48), "56 pt: the halves' own 48 pt caps")
check(standIn(sure(643)) == row(540, 58), "147 pt: 58 caps in the middle")
check(standIn(sure(644)) == nil && standIn(sure(700)) == nil, "148 pt and more: the window bar and the key row in view, as they are")
check(standIn(nil) == nil && standIn(sure(951)) == nil && standIn(sure(1000)) == nil, "no keyboard: as they are")
check(standIn(sure(951), standard: 1000) == nil && standIn(sure(960), standard: 1000) == nil, "a keyboard at or below the foot is none, whatever the rows take")
check(standIn(sure(glassTop), fold: .inferred) == nil && standIn(sure(glassTop), fold: .known(bookFold)) == nil
      && standIn(Glass(top: nil, sure: false), fold: .inferred) == nil && standIn(sure(506), fold: .inferred) == nil,
      "off the inner display upright's known fold (before iOS 27.1, an iPad): as they are")
check(standIn(sure(300), fold: .known(bookFold), size: book) == nil && standIn(Glass(top: nil, sure: false), fold: .known(bookFold), size: book) == nil
      && standIn(sure(300), fold: .known(nil), size: book) == nil && standIn(sure(300), fold: .known(nil), size: size(669, 669)) == nil,
      "sideways (the book pose, open flat sideways) and square: as they are")
// The tall keyboards (Noah, 2026-11-10: "If for some reason that would be covered up (i.e. emoji keyboard)
// surface a small toggle on the top screen for the keyboard, and thats it. No full row."): under the fold
// while the room holds caps of 44 pt with the 8 of black (52 pt), else the toggle alone.
check(DuoPosture.keyboardRowLeast == 44 && DuoPosture.keyboardToggleSize == 44 && DuoPosture.keyboardToggleInset == 8,
      "the least caps 44, the toggle 44 and 8 above the pane's foot")
check(standIn(sure(548)) == row(500, 44), "52 pt: the least caps under the fold, 4 + 44 + 4")
check(standIn(sure(548.5)) == row(500, 44.5), "52.5 pt: 44.5 pt caps, 4 + 44.5 + 4")
check(standIn(sure(547.5)) == toggleAlone && standIn(sure(547)) == toggleAlone, "under 52 pt: the toggle, no row")
check(standIn(sure(506)) == toggleAlone, "the 445 pt keyboards (Pinyin; the glass at 506, 10 pt): the toggle")
check(standIn(sure(496.5)) == toggleAlone && standIn(sure(496)) == toggleAlone && standIn(sure(480)) == toggleAlone,
      "a keyboard at or over the fold's edge: the toggle")
check(standIn(Glass(top: nil, sure: false)) == toggleAlone, "another keyboard of the mode (the emoji keyboard): the toggle at once")
check(standIn(assumed(glassTop)) == rowAndToggle(500, 51), "an input mode not measured: the row where 396 leaves it, and the toggle")
check(standIn(assumed(506)) == toggleAlone, "assumed and no room: the toggle alone")
// The status bar shown (669×869): the fold 82 pt higher, the controls from 414.
let shownBand = rect(0, 373.5, 669, 40)
check(standIn(sure(473), controls: 414, fold: .known(shownBand), size: size(669, 869)) == row(418, 51), "the status bar shown: 4 + 51 + 4 from 414")
check(standIn(sure(424), controls: 414, fold: .known(shownBand), size: size(669, 869)) == toggleAlone, "the status bar shown, a tall keyboard: the toggle")
// The whole chain in the laptop pose, as the device reports it.
check(standIn(glass(deckTop)) == row(500, 51), "the English keyboard: the row 500–551 over the glass at 555")
check(standIn(glass(deckTop, letters: 445)) == toggleAlone, "Pinyin: the toggle")
check(standIn(glass(deckTop, plane: .other)) == toggleAlone, "the emoji keyboard: the toggle")
check(standIn(glass(deckTop, letters: 403)) == row(500, 44) && standIn(glass(deckTop, letters: 403.5)) == toggleAlone,
      "a keyboard 403 pt tall: the least row under the fold; 403.5: the toggle")
check(standIn(glass(640)) == row(500, 51) && standIn(glass(640, plane: .other)) == toggleAlone,
      "folded from open flat with the keyboard up: the row over the laptop pose's glass, or for the emoji keyboard the toggle")
// Open flat (no fold across; the controls from the picture pane's foot): the row 4 pt above the glass, 51 pt.
check(DuoPosture.keyboardRowFlat == 51 && DuoPosture.keyboardRowGlassGap == 4, "open flat: 51 pt caps, 4 above the glass")
let flat = FoldInfo.known(nil)
check(standIn(sure(640), controls: 424, fold: flat) == nil, "open flat, the English keyboard at 640 under 16:10's controls (424 + 148): as they are")
check(standIn(sure(553), controls: 424, fold: flat) == row(498, 51), "open flat, the emoji keyboard at 553: the row 498–549")
check(standIn(sure(600), controls: 506, fold: flat) == row(545, 51), "open flat, Pinyin at 600 under a 4:3 picture's controls (506): the row 545–596")
check(standIn(sure(571.9), controls: 424, fold: flat) == row(516.9, 51) && standIn(sure(572), controls: 424, fold: flat) == nil,
      "open flat: a row exactly while the keyboard covers some of the rows")
check(standIn(sure(479), controls: 424, fold: flat) == row(424, 51) && standIn(sure(478), controls: 424, fold: flat) == row(424, 50),
      "open flat: never above the controls' top (the picture's pane), the caps shorter down to 44")
check(standIn(sure(472), controls: 424, fold: flat) == row(424, 44) && standIn(sure(471.9), controls: 424, fold: flat) == toggleAlone,
      "open flat: 48 pt over the controls' top holds 44 pt caps; less, the toggle")
check(standIn(sure(300), controls: 424, fold: flat) == toggleAlone, "open flat, a keyboard over the picture's foot: the toggle")
// The toggle's place: inside the pane (its foot at 447 in the laptop pose), its trailing edge on the row's.
check(DuoPosture.keyboardToggle(paneBottom: 447, width: 669, sides: 14) == rect(611, 395, 44, 44), "the toggle at 611,395, 44 pt")
check(DuoPosture.keyboardToggle(paneBottom: 365, width: 669, sides: 14) == rect(611, 313, 44, 44), "the status bar shown: 8 above the pane's foot at 365")
// Twelve caps (the Desktop: Spotlight's too) and eleven across the row.
check(abs(DuoPosture.keyboardRowCap(count: 12, width: 641) - 47.917) < 0.001, "twelve caps ≈ 48 pt wide")
check(abs(DuoPosture.keyboardRowCap(count: 11, width: 641) - 52.818) < 0.001 && DuoPosture.keyboardRowCap(count: 0, width: 641) == 0,
      "eleven caps (a window: no Spotlight) ≈ 53; none: none")
check(DuoPosture.keyboardRowGap == 6 && DuoPosture.keyboardRowMost == 58 && DuoPosture.keyboardRowMargins == 8,
      "the row's numbers")
// Every keyboard top, every controls' top (the fold's band 40 pt above it, as on the Duo), sure or not: the rules hold.
for controls in [CGFloat(414), 496, 500.5, 600] {
    let band = rect(0, controls - 40.5, 669, 40)
    for top in stride(from: controls - 60, through: 960, by: 0.5) {
        for isSure in [true, false] {
            let s = standIn(Glass(top: top, sure: isSure), controls: controls, fold: .known(band))
            let room = top - controls
            check((s == nil) == (top >= 951 || room >= 148), "\(controls) \(top): a stand-in exactly while the keyboard covers the key row")
            guard let s else { continue }
            check((s.row == nil) == (room < 52), "\(controls) \(top): the row exactly while 44 pt caps fit with their black")
            check(s.toggle == (!isSure || room < 52), "\(controls) \(top) \(isSure): the toggle exactly while the row is not known to be in view")
            guard let r = s.row else { continue }
            check(r.minX == 14 && r.width == 641, "\(controls) \(top): the row's sides")
            let caps = min(58, room - 8)
            check(r.height == caps && caps >= 44, "\(controls) \(top): the caps the room less 8, 44 to 58")
            check(r.minY >= controls, "\(controls) \(top): never onto the fold")
            let above = r.minY - controls, below = top - r.maxY
            check(above == above.rounded() && below - above >= 0 && below - above < 2 && (room != room.rounded() || below - above <= 1),
                  "\(controls) \(top): the black above and below alike, the odd point below (\(above), \(below))")
            check(above >= 4, "\(controls) \(top): 4 of black at least above, and so below")
            if room <= 66 { check(above == 4, "\(controls) \(top): 4 above while the caps fill") }
        }
        check(standIn(Glass(top: nil, sure: false), controls: controls, fold: .known(band)) == toggleAlone, "\(controls): another keyboard: the toggle")
    }
    // Open flat: the row hugs the glass, never above the controls' top.
    for top in stride(from: controls - 60, through: 960, by: 0.5) {
        let s = standIn(sure(top), controls: controls, fold: flat)
        let room = top - controls
        check((s == nil) == (top >= 951 || room >= 148), "flat \(controls) \(top): a stand-in exactly while the keyboard covers the rows")
        guard let s else { continue }
        check((s.row == nil) == (room < 48) && s.toggle == (room < 48), "flat \(controls) \(top): the row while 44 pt caps fit 4 above the glass, else the toggle")
        guard let r = s.row else { continue }
        check(r.maxY == top - 4 && r.minY >= controls && r.height == min(51, room - 4) && r.minX == 14 && r.width == 641,
              "flat \(controls) \(top): 4 above the glass, under the pane, 44 to 51 pt")
    }
}
// Every keyboard height the monitor can learn (and none): the row, wherever it is, is never under the
// keyboard's glass and never over the picture; a row under a glass that is only assumed comes with the toggle.
for own in [nil] + stride(from: CGFloat(0), through: 960, by: 0.5).map(Optional.some) {
    guard let g = glass(deckTop, letters: own), let s = standIn(g) else { continue }
    if let r = s.row, let top = g.top {
        check(r.maxY <= top, "\(String(describing: own)): the row \(r.minY)–\(r.maxY) above the glass at \(top)")
        check(r.minY >= laptopFold.minY, "\(String(describing: own)): the row never over the picture")
    }
    check(s.row != nil || s.toggle, "\(String(describing: own)): the row or the toggle, never neither")
}

print(failures == 0 ? "ok: \(checks) checks" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
