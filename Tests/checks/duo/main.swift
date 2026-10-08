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
// The status bar hides while the hinge is open, never on the cover or off the Duo.
check(DuoPosture.hidesStatusBar(.partiallyOpen) && DuoPosture.hidesStatusBar(.fullyOpen), "hidden open")
check(!DuoPosture.hidesStatusBar(.closed) && !DuoPosture.hidesStatusBar(.unknown), "shown closed and off the Duo")
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
func insets(_ s: CGSize) -> [CGFloat]? { DuoPosture.displayInsets(s).map { [$0.top, $0.leading, $0.bottom, $0.trailing] } }
check(insets(book) == [0, 0, 34, 0] && insets(upright) == [0, 0, 34, 0], "the inner display: the home indicator alone")
check(insets(size(466, 678)) == [0, 0, 34, 84] && insets(size(678, 466)) == [0, 84, 34, 0], "the cover: its camera's strip")
check(insets(size(1000, 710)) == nil && insets(size(382, 678)) == nil && insets(size(710, 1000)) == nil, "any other size: none")
// The stand-in through the whole chain gives what the device gave.
for (hinge, s, info) in [(DuoPosture.Hinge.partiallyOpen, book, FoldInfo.known(bookFold)), (.partiallyOpen, upright, .known(laptopFold)),
                         (.fullyOpen, book, .known(nil)), (.fullyOpen, upright, .known(nil))] {
    check(DuoPosture(hinge: hinge, fold: DuoPosture.standInFold(s)).info(in: s) == info, "the stand-in, \(hinge) \(s)")
}

print(failures == 0 ? "ok: \(checks) checks" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
