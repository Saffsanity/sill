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

// What the iOS 27.1 simulator's Duo shows in the laptop pose (669×951, the fold's band 455.5–495.5, the
// controls from 496), the dark keyboard with no predictive bar (the reporter's): UIKit reports every keyboard
// as the whole lower page, (0, 455.5, 669×495.5), whatever it draws: the English keyboard's glass at 555
// (396 pt), the emoji keyboard's, the emoji search's and Pinyin's at 506 (445). The keyboard's own views
// (a look) put English at 555, emoji at 507 (444), the search at 516 (435) and English after the search at
// 564 (387); once the input views were reloaded they are the page (454.7, 455.7). A reload's report begins
// with the keyboard up (0, 555, 669×396; 0, 506, 669×445). Open flat upright every keyboard is reported as
// itself: English (0, 640, 669×311), emoji (0, 553, 669×398), Pinyin (0, 600, 669×351).
let page = rect(0, 455.5, 669, 495.5)
let english = rect(0, 555, 669, 396), emoji = rect(0, 506, 669, 445)
let lookEmoji = rect(0, 507, 669, 444), lookSearch = rect(0, 516, 669, 435), lookEnglishAfterSearch = rect(0, 564, 669, 387)
typealias Glass = DuoPosture.KeyboardGlass
func at(_ top: CGFloat) -> Glass { Glass(top: top) }
let unknown = Glass(top: nil)

// Whether a frame can be the glass.
func plausible(_ f: CGRect?, controls: CGFloat = 496) -> CGFloat? { DuoPosture.plausibleGlass(f, size: upright, controlsTop: controls) }
check(plausible(english) == 555 && plausible(emoji) == 506 && plausible(lookSearch) == 516, "the keyboards are glasses")
check(plausible(page) == nil && plausible(rect(0, 454.7, 669, 496.3)) == nil, "the page is none: its top over the controls' top")
check(plausible(rect(0, 496, 669, 455)) == nil && plausible(rect(0, 496.5, 669, 454.5)) == 496.5, "a top at the controls' top is none; under it, one")
check(plausible(rect(0, 555, 600, 396)) == nil && plausible(rect(0, 555, 668, 396)) == 555 && plausible(rect(0, 555, 670, 396)) == 555
      && plausible(rect(0, 555, 670.5, 396)) == nil, "as wide as the screen, within a point")
check(plausible(rect(0, 555, 669, 394.9)) == nil && plausible(rect(0, 555, 669, 395)) == 555 && plausible(rect(0, 555, 669, 397.1)) == nil,
      "down to the foot, within a point")
check(plausible(nil) == nil && plausible(rect(0, 951, 669, 0)) == nil && plausible(rect(0, 951, 669, 1)) == nil, "nothing, or nothing above the foot: none")
check(plausible(english, controls: 600) == nil && plausible(english, controls: 554) == 555, "under the controls' top given")

// The glass: open flat as reported; in the laptop pose as read.
func glass(_ reported: CGFloat?, read: CGRect? = nil, laptop: Bool = true, controls: CGFloat = 496) -> Glass? {
    DuoPosture.keyboardGlass(reported: reported, read: read, size: upright, controlsTop: controls, laptop: laptop)
}
check(glass(455.5, read: english) == at(555) && glass(455.5, read: emoji) == at(506), "the laptop pose: the glass read, not the page")
check(glass(455.5, read: lookEmoji) == at(507) && glass(455.5, read: lookSearch) == at(516), "a look's glass as it is")
check(glass(455.5) == unknown && glass(455.5, read: page) == unknown && glass(455.5, read: rect(0, 455.7, 669, 495.3)) == unknown,
      "nothing read, or only the page (views that tell nothing): not known")
check(glass(640, read: english) == at(555) && glass(640) == unknown, "folded from open flat (640 still reported): the reading, or not known")
check(glass(nil, read: english) == nil && glass(951, read: english) == nil && glass(960) == nil && glass(nil) == nil,
      "no keyboard reported: none, whatever was read")
check(glass(640, laptop: false, controls: 424) == at(640) && glass(553, read: english, laptop: false, controls: 424) == at(553)
      && glass(600, read: emoji, laptop: false, controls: 506) == at(600) && glass(300, laptop: false, controls: 424) == at(300),
      "open flat: as reported (English 640, emoji 553, Pinyin 600), live, whatever was read")
check(glass(nil, laptop: false) == nil && glass(951, laptop: false) == nil, "open flat, none reported: none")

// A look: the keyboard's own views, found by geometry.
func look(_ frames: [CGRect], reported: CGRect? = page) -> CGRect? { DuoPosture.keyboardLook(frames, reported: reported, screen: upright) }
let wholeWindow = rect(0, 0, 669, 951), container = rect(0, 454.7, 669, 496.3)
check(look([wholeWindow, container, english, english]) == english, "past the window and the page: the keyboard's views")
check(look([wholeWindow, rect(0, 454.7, 669, 496.3), rect(0, 455.7, 669, 495.3)]) == nil, "after a reload the views are the page: nothing")
check(look([lookEmoji, english]) == lookEmoji, "the first that tells, outermost first")
check(look([english], reported: nil) == nil && look([]) == nil, "no keyboard reported, or no views: none")
check(look([rect(0, 555, 300, 396)]) == nil && look([rect(0, 555, 669, 300)]) == nil && look([rect(0, 555, 669, 0)]) == nil,
      "not as wide as the screen, not down to its foot, or of no height: none")
check(look([rect(0, 456.5, 669, 494.5)]) == nil && look([rect(0, 456.6, 669, 494.4)]) == rect(0, 456.6, 669, 494.4),
      "more than a point under the reported top")
check(look([rect(0, 640, 669, 311)], reported: rect(0, 640, 669, 311)) == nil, "open flat the views are where UIKit reports them: no look")

// Looks off: UIKit's report of the keyboard left against the last look.
check(!DuoPosture.keyboardLookIsOff(lastLook: lookEmoji, begin: emoji) && !DuoPosture.keyboardLookIsOff(lastLook: english, begin: english),
      "a look within a point of UIKit's report (507 for 506): not off")
check(DuoPosture.keyboardLookIsOff(lastLook: lookEmoji, begin: english), "into the emoji search (UIKit's stale 555 against the look's 507): off")
check(DuoPosture.keyboardLookIsOff(lastLook: lookSearch, begin: emoji), "after the search (516 looked, 506 reported): off")
check(!DuoPosture.keyboardLookIsOff(lastLook: english, begin: rect(0, 556.5, 669, 394.5))
      && DuoPosture.keyboardLookIsOff(lastLook: english, begin: rect(0, 556.6, 669, 394.4)), "1.5 pt apart: not off; more: off")
check(!DuoPosture.keyboardLookIsOff(lastLook: nil, begin: english) && !DuoPosture.keyboardLookIsOff(lastLook: english, begin: nil)
      && !DuoPosture.keyboardLookIsOff(lastLook: english, begin: rect(0, 0, 0, 0)), "nothing to compare: not off")

// Whether the row fits.
check(DuoPosture.keyboardRowFits(glassTop: 555, controlsTop: 496) && DuoPosture.keyboardRowFits(glassTop: 548, controlsTop: 496)
      && DuoPosture.keyboardRowFits(glassTop: 564, controlsTop: 496), "English (and its look after the search): the row fits")
check(!DuoPosture.keyboardRowFits(glassTop: 547.9, controlsTop: 496) && !DuoPosture.keyboardRowFits(glassTop: 506, controlsTop: 496)
      && !DuoPosture.keyboardRowFits(glassTop: 516, controlsTop: 496) && !DuoPosture.keyboardRowFits(glassTop: 507, controlsTop: 496),
      "under 52 pt (emoji, its search, Pinyin): it does not")
check(DuoPosture.keyboardRowFits(glassTop: 466, controlsTop: 414) && !DuoPosture.keyboardRowFits(glassTop: 465, controlsTop: 414),
      "from any controls' top")

// What a report is: a reload's reading, or a change.
func isReading(_ at: Double, reloadedAt: Double? = 10, hiding: Bool = false, animated: Bool = false, begin: CGRect? = english) -> Bool {
    DuoPosture.keyboardReportIsReading(at: at, reloadedAt: reloadedAt, hiding: hiding, animated: animated, begin: begin)
}
check(isReading(10.03) && isReading(10) && isReading(10.499), "a report within half a second after a reload: its reading")
check(!isReading(10.5) && !isReading(9.99), "half a second after, or before it: a change")
check(!isReading(10.03, hiding: true) && !isReading(10.03, animated: true), "a hide, an animated report (a show): never")
check(!isReading(10.03, begin: nil) && !isReading(10.03, begin: rect(0, 0, 0, 0)) && !isReading(10.03, begin: .null), "no begin frame: never")
check(!isReading(10.03, reloadedAt: nil), "no reload since the change: a change")
check(DuoPosture.keyboardReadWindow == 0.5 && DuoPosture.keyboardSettle == 0.8 && DuoPosture.keyboardSwitchReportWait == 0.4,
      "the window, the settling, the wait for a switch's report")

// When looks and reloads come.
func same(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.0001 } }
check(same(DuoPosture.keyboardLookDelays, [0.02, 0.06, 0.15, 0.4, 1, 2]), "looks at once and a few times after a change")
check(same(DuoPosture.keyboardReadDelays(after: .animating(0.38)), [0.40, 0.48, 1.5, 2.5]), "a coming keyboard: reloads after its animation")
check(same(DuoPosture.keyboardReadDelays(after: .animated), [0.01, 0.06, 1, 2]), "its animation ended: at once")
check(same(DuoPosture.keyboardReadDelays(after: .other), [0.05, 0.09, 0.13, 0.18, 0.25, 0.32, 1, 2]), "a switch: every 40–70 ms from 50 ms")
check(same(DuoPosture.keyboardReadDelays(after: .fold), [0.15, 0.3, 0.45, 0.6, 0.8, 1, 1.5, 2]), "a fold: every 150–200 ms while the reports are stale")
check(DuoPosture.keyboardSettle(after: .fold) == 1.2 && DuoPosture.keyboardSettle(after: .other) == 0.8 && DuoPosture.keyboardSettle(after: .animated) == 0.8,
      "settling: longer after a fold")
let flatEnglish = rect(0, 640, 669, 311), flatEmoji = rect(0, 553, 669, 398)
check(DuoPosture.keyboardReadingIsStale(flatEnglish, staleFrame: flatEnglish, at: 10.1, staleUntil: 12)
      && DuoPosture.keyboardReadingIsStale(rect(0, 553.3, 669, 397.7), staleFrame: flatEmoji, at: 11.9, staleUntil: 12),
      "folded from open flat: a reading of open flat's keyboard is stale")
check(!DuoPosture.keyboardReadingIsStale(english, staleFrame: flatEnglish, at: 10.1, staleUntil: 12)
      && !DuoPosture.keyboardReadingIsStale(emoji, staleFrame: flatEmoji, at: 10.1, staleUntil: 12),
      "the laptop pose's own keyboard is no stale reading")
check(!DuoPosture.keyboardReadingIsStale(flatEnglish, staleFrame: flatEnglish, at: 12, staleUntil: 12)
      && !DuoPosture.keyboardReadingIsStale(flatEnglish, staleFrame: nil, at: 10, staleUntil: 12), "after two seconds, or with no fold: never stale")
for change in [DuoPosture.KeyboardChange.animating(0.38), .animated, .other, .fold] {
    let delays = DuoPosture.keyboardReadDelays(after: change)
    check(delays == delays.sorted() && delays.filter { $0 >= DuoPosture.keyboardLateRead }.count >= 2,
          "\(change): in order, two late reloads or more at a second or more")
}
check(DuoPosture.keyboardLateRead == 1, "late from a second")
check(DuoPosture.keyboardReadsAgain([], before: english), "nothing read yet: again")
check(DuoPosture.keyboardReadsAgain([english], before: english) && DuoPosture.keyboardReadsAgain([english, english, english], before: english),
      "only the glass before the change: again (a reading equal to the glass on screen changes nothing)")
check(DuoPosture.keyboardReadsAgain([rect(0, 555.4, 669, 395.6)], before: english), "within half a point is the same glass")
check(DuoPosture.keyboardReadsAgain([emoji], before: english) && DuoPosture.keyboardReadsAgain([english, emoji], before: english),
      "the new keyboard once: again, to confirm it")
check(!DuoPosture.keyboardReadsAgain([emoji, emoji], before: english) && !DuoPosture.keyboardReadsAgain([english, emoji, emoji], before: english)
      && !DuoPosture.keyboardReadsAgain([emoji, english], before: english), "confirmed (or contradicted, for the late ones to settle): no more early ones")
check(DuoPosture.keyboardReadsAgain([english], before: nil) && !DuoPosture.keyboardReadsAgain([english, english], before: nil),
      "nothing before (a show): the first, then one to confirm")

// The hints: what readings teach, and what to assume at once at a show or a switch.
typealias Hints = DuoPosture.KeyboardHints
let enKey = DuoPosture.keyboardHintKey(mode: "en-US", width: 669), zhKey = DuoPosture.keyboardHintKey(mode: "zh-Hans", width: 669)
let wKey = DuoPosture.keyboardWidthKey(669)
check(enKey == "en-US@669" && zhKey == "zh-Hans@669" && wKey == "@669" && DuoPosture.keyboardHintKey(mode: nil, width: 668.6) == "@669",
      "keys: the mode and the width")
check(DuoPosture.sameKeyboard(444, 445) && DuoPosture.sameKeyboard(396, 397.4) && !DuoPosture.sameKeyboard(396, 397.5)
      && !DuoPosture.sameKeyboard(nil, 396) && !DuoPosture.sameKeyboard(396, nil), "one keyboard within 1.5 pt")
func taught(_ h: Hints, _ height: Double, _ cause: DuoPosture.KeyboardCause, before: Double? = nil, key: String = enKey) -> Hints {
    DuoPosture.keyboardHints(h, after: height, cause: cause, before: before, key: key, widthKey: wKey)
}
let none = Hints(), learnedEnglish = Hints(letters: [enKey: 396]), learnedBoth = Hints(letters: [enKey: 396], other: [wKey: 445])
check(taught(none, 396, .show) == learnedEnglish, "a show's reading: the mode's letters keyboard")
check(taught(learnedEnglish, 445, .modeChange, key: zhKey) == Hints(letters: [enKey: 396, zhKey: 445]), "another mode's first reading: its letters keyboard")
check(taught(learnedEnglish, 445, .sameMode, before: 396) == learnedBoth, "a switch within the mode from the letters keyboard: the other keyboard")
check(taught(learnedBoth, 396, .sameMode, before: 445) == learnedBoth, "back to the letters keyboard (ABC): nothing new")
check(taught(learnedEnglish, 396, .sameMode, before: 396) == learnedEnglish && taught(learnedEnglish, 396.5, .sameMode, before: 396) == learnedEnglish,
      "a reading still of the keyboard before the switch teaches nothing")
check(taught(learnedBoth, 435, .sameMode, before: 445) == Hints(letters: [enKey: 396], other: [wKey: 435]), "the search after the emoji keyboard: the other one, as read")
check(taught(learnedBoth, 445, .show) == learnedBoth, "a show that brings back the other keyboard: the letters keyboard kept")
check(taught(learnedBoth, 400, .show) == Hints(letters: [enKey: 400], other: [wKey: 445]), "a show's new letters height replaces the old")
check(taught(learnedBoth, 300, .other) == learnedBoth && taught(none, 300, .other) == none, "after a fold or coming back: nothing")
func assumed(_ cause: DuoPosture.KeyboardCause, current: Double?, _ h: Hints = learnedBoth, key: String = enKey) -> Double? {
    DuoPosture.keyboardPrediction(cause: cause, current: current, hints: h, key: key, widthKey: wKey)
}
check(assumed(.show, current: nil) == 396 && assumed(.show, current: nil, none) == nil, "a show: the letters keyboard as last read, or nothing")
check(assumed(.modeChange, current: 396, key: zhKey) == nil && assumed(.modeChange, current: 396, Hints(letters: [enKey: 396, zhKey: 445]), key: zhKey) == 445,
      "another mode: its letters keyboard as last read, or nothing")
check(assumed(.sameMode, current: 396) == 445 && assumed(.sameMode, current: 395) == 445, "😀 from the letters keyboard: the other one")
check(assumed(.sameMode, current: 445) == 396 && assumed(.sameMode, current: 435) == 396 && assumed(.sameMode, current: nil) == 396,
      "ABC (or the search) from another keyboard: the letters keyboard")
check(assumed(.sameMode, current: 396, learnedEnglish) == nil && assumed(.sameMode, current: 445, none) == nil, "no hint: nothing assumed")
check(assumed(.other, current: 396) == nil, "a fold or coming back: nothing assumed")

func standIn(_ g: Glass?, controls: CGFloat = 496, fold: FoldInfo = .known(laptopFold), size s: CGSize = upright,
             standard: CGFloat = 148, settling: Bool = false) -> DuoPosture.KeyboardStandIn? {
    DuoPosture.keyboardStandIn(size: s, fold: fold, controlsTop: controls, glass: g, standardRows: standard, sides: 14, settling: settling)
}
func row(_ y: CGFloat, _ caps: CGFloat) -> DuoPosture.KeyboardStandIn { .init(row: rect(14, y, 641, caps), toggle: false) }
let toggleAlone = DuoPosture.KeyboardStandIn(row: nil, toggle: true)
let nothingYet = DuoPosture.KeyboardStandIn(row: nil, toggle: false)
func standInAssumed(_ height: Double) -> String {
    let s = standIn(glass(455.5, read: rect(0, 951 - CGFloat(height), 669, CGFloat(height))))
    return s?.row != nil ? "row" : s?.toggle == true ? "toggle" : "none"
}
// Through the stand-in: what is assumed decides like a reading, until a reading replaces it.
check(standInAssumed(396) == "row" && standInAssumed(445) == "toggle", "assumed English: the row; assumed emoji: the toggle")
// Noah's numbers (2026-10-27, "A"): under the fold the caps the room less 8, at most 58, the black above
// and below alike.
check(standIn(at(555)) == row(500, 51), "the Duo's keyboard: 4 + 51 + 4, \(String(describing: standIn(at(555))))")
check(standIn(at(570)) == row(504, 58), "a 381 pt keyboard: 8 + 58 + 8")
check(standIn(at(571)) == row(504, 58), "75 pt: 58 caps, 8 above and 9 below (within a point)")
check(standIn(at(552)) == row(500, 48), "56 pt: the halves' own 48 pt caps")
check(standIn(at(643)) == row(540, 58), "147 pt: 58 caps in the middle")
check(standIn(at(644)) == nil && standIn(at(700)) == nil, "148 pt and more: the window bar and the key row in view, as they are")
check(standIn(nil) == nil && standIn(at(951)) == nil && standIn(at(1000)) == nil, "no keyboard: as they are")
check(standIn(at(951), standard: 1000) == nil && standIn(at(960), standard: 1000) == nil, "a keyboard at or below the foot is none, whatever the rows take")
check(standIn(at(555), fold: .inferred) == nil && standIn(at(555), fold: .known(bookFold)) == nil
      && standIn(unknown, fold: .inferred) == nil && standIn(at(506), fold: .inferred) == nil && standIn(unknown, fold: .inferred, settling: true) == nil,
      "off the inner display upright's known fold (before iOS 27.1, an iPad): as they are")
check(standIn(at(300), fold: .known(bookFold), size: book) == nil && standIn(unknown, fold: .known(bookFold), size: book) == nil
      && standIn(at(300), fold: .known(nil), size: book) == nil && standIn(at(300), fold: .known(nil), size: size(669, 669)) == nil,
      "sideways (the book pose, open flat sideways) and square: as they are")
// The tall keyboards (Noah, 2026-11-10: "If for some reason that would be covered up (i.e. emoji keyboard)
// surface a small toggle on the top screen for the keyboard, and thats it. No full row."): under the fold
// while the room holds caps of 44 pt with the 8 of black (52 pt), else the toggle alone.
check(DuoPosture.keyboardRowLeast == 44 && DuoPosture.keyboardToggleSize == 44 && DuoPosture.keyboardToggleInset == 8,
      "the least caps 44, the toggle 44 and 8 above the pane's foot")
check(standIn(at(548)) == row(500, 44), "52 pt: the least caps under the fold, 4 + 44 + 4")
check(standIn(at(548.5)) == row(500, 44.5), "52.5 pt: 44.5 pt caps, 4 + 44.5 + 4")
check(standIn(at(547.5)) == toggleAlone && standIn(at(547)) == toggleAlone, "under 52 pt: the toggle, no row")
check(standIn(at(506)) == toggleAlone && standIn(at(507)) == toggleAlone && standIn(at(516)) == toggleAlone,
      "the emoji keyboard, its search, Pinyin (read at 506, looked at 507 and 516): the toggle")
check(standIn(at(496.5)) == toggleAlone && standIn(at(496)) == toggleAlone && standIn(at(480)) == toggleAlone,
      "a keyboard at or over the fold's edge: the toggle")
check(standIn(unknown) == toggleAlone, "not known: the toggle")
check(standIn(unknown, settling: true) == nothingYet, "not known while a reading is on its way: nothing in place yet, the controls hidden")
check(standIn(at(555), settling: true) == row(500, 51) && standIn(at(506), settling: true) == toggleAlone && standIn(nil, settling: true) == nil,
      "settling changes nothing once the glass is known, or with no keyboard")
// The status bar shown (669×869): the fold 82 pt higher, the controls from 414.
let shownBand = rect(0, 373.5, 669, 40)
check(standIn(at(473), controls: 414, fold: .known(shownBand), size: size(669, 869)) == row(418, 51), "the status bar shown: 4 + 51 + 4 from 414")
check(standIn(at(424), controls: 414, fold: .known(shownBand), size: size(669, 869)) == toggleAlone, "the status bar shown, a tall keyboard: the toggle")
// The whole chain in the laptop pose, as the device reports and Sill reads.
check(standIn(glass(455.5, read: english)) == row(500, 51), "English read: the row 500–551 over the glass at 555")
check(standIn(glass(455.5, read: emoji)) == toggleAlone && standIn(glass(455.5, read: lookEmoji)) == toggleAlone
      && standIn(glass(455.5, read: lookSearch)) == toggleAlone, "emoji, read or looked, and the search looked: the toggle")
check(standIn(glass(455.5)) == toggleAlone && standIn(glass(455.5), settling: true) == nothingYet && standIn(glass(455.5, read: page)) == toggleAlone,
      "nothing read: the toggle (after the settling); the page read: the toggle")
check(standIn(glass(640, read: english)) == row(500, 51) && standIn(glass(640, read: emoji)) == toggleAlone,
      "folded from open flat with the keyboard up: as read")
// Open flat (no fold across; the controls from the picture pane's foot): the row 4 pt above the glass, 51 pt.
check(DuoPosture.keyboardRowFlat == 51 && DuoPosture.keyboardRowGlassGap == 4, "open flat: 51 pt caps, 4 above the glass")
let flat = FoldInfo.known(nil)
check(standIn(at(640), controls: 424, fold: flat) == nil, "open flat, the English keyboard at 640 under 16:10's controls (424 + 148): as they are")
check(standIn(at(553), controls: 424, fold: flat) == row(498, 51), "open flat, the emoji keyboard at 553: the row 498–549")
check(standIn(at(600), controls: 506, fold: flat) == row(545, 51), "open flat, Pinyin at 600 under a 4:3 picture's controls (506): the row 545–596")
check(standIn(at(571.9), controls: 424, fold: flat) == row(516.9, 51) && standIn(at(572), controls: 424, fold: flat) == nil,
      "open flat: a row exactly while the keyboard covers some of the rows")
check(standIn(at(479), controls: 424, fold: flat) == row(424, 51) && standIn(at(478), controls: 424, fold: flat) == row(424, 50),
      "open flat: never above the controls' top (the picture's pane), the caps shorter down to 44")
check(standIn(at(472), controls: 424, fold: flat) == row(424, 44) && standIn(at(471.9), controls: 424, fold: flat) == toggleAlone,
      "open flat: 48 pt over the controls' top holds 44 pt caps; less, the toggle")
check(standIn(at(300), controls: 424, fold: flat) == toggleAlone, "open flat, a keyboard over the picture's foot: the toggle")
// The toggle's place: inside the pane (its foot at 447 in the laptop pose), its trailing edge on the row's.
check(DuoPosture.keyboardToggle(paneBottom: 447, width: 669, sides: 14) == rect(611, 395, 44, 44), "the toggle at 611,395, 44 pt")
check(DuoPosture.keyboardToggle(paneBottom: 365, width: 669, sides: 14) == rect(611, 313, 44, 44), "the status bar shown: 8 above the pane's foot at 365")
// Twelve caps (the Desktop: Spotlight's too) and eleven across the row.
check(abs(DuoPosture.keyboardRowCap(count: 12, width: 641) - 47.917) < 0.001, "twelve caps ≈ 48 pt wide")
check(abs(DuoPosture.keyboardRowCap(count: 11, width: 641) - 52.818) < 0.001 && DuoPosture.keyboardRowCap(count: 0, width: 641) == 0,
      "eleven caps (a window: no Spotlight) ≈ 53; none: none")
check(DuoPosture.keyboardRowGap == 6 && DuoPosture.keyboardRowMost == 58 && DuoPosture.keyboardRowMargins == 8,
      "the row's numbers")
// Every keyboard top, every controls' top (the fold's band 40 pt above it, as on the Duo): the rules hold, and
// the row fits exactly where keyboardRowFits says.
for controls in [CGFloat(414), 496, 500.5, 600] {
    let band = rect(0, controls - 40.5, 669, 40)
    for top in stride(from: controls - 60, through: 960, by: 0.5) {
        for settling in [false, true] {
            let s = standIn(at(top), controls: controls, fold: .known(band), settling: settling)
            let room = top - controls
            check((s == nil) == (top >= 951 || room >= 148), "\(controls) \(top): a stand-in exactly while the keyboard covers the key row")
            guard let s else { continue }
            check((s.row == nil) == (room < 52), "\(controls) \(top): the row exactly while 44 pt caps fit with their black")
            check((s.row != nil) == DuoPosture.keyboardRowFits(glassTop: top, controlsTop: controls), "\(controls) \(top): as keyboardRowFits says")
            check(s.toggle == (room < 52), "\(controls) \(top): the toggle exactly while the row does not fit")
            guard let r = s.row else { continue }
            check(r.minX == 14 && r.width == 641, "\(controls) \(top): the row's sides")
            let caps = min(58, room - 8)
            check(r.height == caps && caps >= 44, "\(controls) \(top): the caps the room less 8, 44 to 58")
            check(r.minY >= controls && r.maxY <= top, "\(controls) \(top): never onto the fold, never under the glass")
            let above = r.minY - controls, below = top - r.maxY
            check(above == above.rounded() && below - above >= 0 && below - above < 2 && (room != room.rounded() || below - above <= 1),
                  "\(controls) \(top): the black above and below alike, the odd point below (\(above), \(below))")
            check(above >= 4, "\(controls) \(top): 4 of black at least above, and so below")
            if room <= 66 { check(above == 4, "\(controls) \(top): 4 above while the caps fill") }
        }
        check(standIn(unknown, controls: controls, fold: .known(band)) == toggleAlone
              && standIn(unknown, controls: controls, fold: .known(band), settling: true) == nothingYet, "\(controls): not known: the toggle, or nothing yet")
    }
    // Open flat: the row hugs the glass, never above the controls' top.
    for top in stride(from: controls - 60, through: 960, by: 0.5) {
        let s = standIn(at(top), controls: controls, fold: flat)
        let room = top - controls
        check((s == nil) == (top >= 951 || room >= 148), "flat \(controls) \(top): a stand-in exactly while the keyboard covers the rows")
        guard let s else { continue }
        check((s.row == nil) == (room < 48) && s.toggle == (room < 48), "flat \(controls) \(top): the row while 44 pt caps fit 4 above the glass, else the toggle")
        guard let r = s.row else { continue }
        check(r.maxY == top - 4 && r.minY >= controls && r.height == min(51, room - 4) && r.minX == 14 && r.width == 641,
              "flat \(controls) \(top): 4 above the glass, under the pane, 44 to 51 pt")
    }
}
// Every reading Sill can make in the laptop pose, plausible or not, through the whole chain: the row is never
// under the glass read, never over the picture, and with a keyboard up there is always the row or the toggle
// (but while settling).
for y in stride(from: CGFloat(400), through: 960, by: 0.5) {
    for h in [CGFloat(0), 1, 100, 951 - y, 951 - y + 2] {
        let reading = rect(0, y, 669, h)
        guard let g = glass(455.5, read: reading) else { check(false, "\(y) \(h): a keyboard is reported"); continue }
        check(g.top == nil || (g.top! > 496 && g.top! < 951 && abs(reading.maxY - 951) <= 1), "\(y) \(h): a glass only from a plausible reading")
        guard let s = standIn(g) else { check(g.top.map { $0 - 496 >= 148 } == true, "\(y) \(h): as they are only while the rows are in view"); continue }
        if let r = s.row, let top = g.top {
            check(r.maxY <= top && r.minY >= 496, "\(y) \(h): the row \(r.minY)–\(r.maxY) between the fold's edge and the glass at \(top)")
        }
        check(s.row != nil || s.toggle, "\(y) \(h): the row or the toggle, never neither")
    }
}

print(failures == 0 ? "ok: \(checks) checks" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
