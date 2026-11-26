import Foundation
import CoreGraphics

// Sill's own Desktop display: its size and rate by default the device's (VirtualDesktopSize; Noah, 2026-11-18: "should
// default to resolution and refresh of client device, not what we originally proposed"), and the guard for #380
// (DisplayMakeGuard: two runs in a row that ended while making a display, and Sill makes none by itself until Try
// Again). Phase 2b: following the device (VirtualDesktopSize.Follow, followStep, the backing, and InPlace, the probes'
// way of 2026-11-23, driven against TestDisplay, the display as P2b, P2c, P3 and P4 measured it), when the Virtual Desktop exists
// (VirtualDesktopLife, 5,000 random sessions against the plan's invariants) and its windows out and back
// (DesktopWindowLedger, over a stand-in Mac). Compiled with Sources/SillHost/VirtualDesktopSize.swift,
// DisplayMakeGuard.swift, VirtualDesktopLife.swift, DesktopWindowLedger.swift and WindowRestore.swift; the guard's Store
// runs in a folder of its own under .build, never Sill.app's.

var checks = 0
var failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { return }
    failures += 1
    if failures <= 30 { print("FAIL: \(what())") }      // a broken rule fails thousands of random cases: the first say why
}

typealias VDS = VirtualDesktopSize
func size(_ w: Int, _ h: Int) -> VDS.Size { VDS.Size(widthPt: w, heightPt: h, scale: 2) }
func panel(_ w: Double, _ h: Double) -> VDS.Size? { VDS.device(space: CGSize(width: w, height: h)) }
extension VirtualDesktopSize.Size {
    /// The same points at another scale (a turn's pixels at 1x: P2c's 1600×2436 @1×).
    func withScale(_ s: Int) -> VirtualDesktopSize.Size { VirtualDesktopSize.Size(widthPt: widthPt, heightPt: heightPt, scale: s) }
}

// MARK: This device: the plan's table (docs/virtual-desktop-plan.md §4, revised 2026-11-18), held sideways and upright

let table: [(String, Double, Double, Int, Int)] = [
    ("iPad Pro 13-inch (M4)", 1376, 1032, 1376, 1032),
    ("iPad Pro 11-inch (M4)", 1210, 834, 1210, 834),
    ("iPad Pro 12.9-inch", 1366, 1024, 1366, 1024),
    ("iPad Air 11-inch, iPad", 1180, 820, 1180, 820),
    ("iPad mini (A17 Pro), grown evenly to 800", 1133, 744, 1218, 800),
    ("iPhone 15 Pro's room clear of the Dynamic Island", 735, 393, 1496, 800),
    ("iPhone 16 Pro's room", 750, 402, 1493, 800),
    ("iPhone Duo's inner display, flat (the harness's)", 951, 669, 1137, 800),
]
for (name, w, h, ew, eh) in table {
    check(panel(w, h) == size(ew, eh), "\(name) sideways: \(Int(w))×\(Int(h)) → \(ew)×\(eh) (\(String(describing: panel(w, h))))")
    check(panel(h, w) == size(eh, ew), "\(name) upright: \(Int(h))×\(Int(w)) → \(eh)×\(ew) (\(String(describing: panel(h, w))))")
}
// Each side to whole points first (a device's points can be fractions: Stage Manager's windows, the Duo's halves).
check(panel(1133.4, 744.4) == size(1218, 800), "fractions rounded first: 1133.4×744.4 as 1133×744")
check(panel(1209.5, 834.4) == size(1210, 834), "a half point rounds up, less rounds down")
check(panel(800, 800) == size(800, 800) && panel(799.6, 800) == size(800, 800), "exactly 800 a side kept; 799.6 is 800")
check(panel(4096, 1000) == size(4096, 1000), "exactly 4096 kept")
// Larger than the ceiling: both sides shrink by one factor (8192 pixels at 2x, VirtualDisplay's).
check(panel(5000, 3000) == size(4096, 2458), "5000×3000 → 4096×2458 (\(String(describing: panel(5000, 3000))))")
check(panel(3000, 8000) == size(1536, 4096), "3000×8000 upright → 1536×4096")
// Grown then shrunk, and a shape no device has gives way to 800…4096 a side.
check(panel(16384, 1000) == size(4096, 800), "16384×1000 (16:1): 4096×800, held")
check(panel(1, 16384) == size(800, 4096), "1×16384: 800×4096, held")
check(panel(1, 1) == size(800, 800), "a point square: 800×800")
check(panel(4096, 800) == size(4096, 800), "5.12:1, the longest shape kept: as it is")
check(panel(500, 100) == size(4000, 800), "5:1 small: grown to 4000×800, the shape kept")
// Rule A (Noah, 2026-11-24): the space the picture has, the viewport's panel, in each layout, as the devices' consoles
// print it ("viewport: W×H pt …", the harness's iPad mini and iPhone 15 Pro), and Full Screen's room; never bars.
let spaces: [(String, Double, Double, Int, Int)] = [
    ("iPad mini sideways, the controls showing (the pane under the bar)", 1117, 618, 1446, 800),
    ("iPad mini sideways, Full Screen (its whole screen)", 1133, 744, 1218, 800),
    ("iPad mini upright, the controls showing (the upper half's pane)", 728, 535, 1089, 800),
    ("iPad mini upright, Full Screen", 744, 1133, 800, 1218),
    ("iPhone 15 Pro upright, the controls showing (its 16:10 pane)", 377, 235, 1283, 800),
    ("iPhone 15 Pro upright, Full Screen (clear of its Dynamic Island): Noah's 800×1614", 393, 793, 800, 1614),
    ("iPhone 15 Pro on its side, the controls showing", 718, 299, 1921, 800),
    ("iPhone 15 Pro on its side, Full Screen: Noah's 1494×800", 734, 393, 1494, 800),
    ("iPhone 12 to 14 on its side, the controls showing: the widest space of any iPhone", 734, 296, 1984, 800),
]
for (name, w, h, ew, eh) in spaces {
    check(panel(w, h) == size(ew, eh), "\(name): \(Int(w))×\(Int(h)) → \(ew)×\(eh) (\(String(describing: panel(w, h))))")
}
// Its shape is the space's, within the rounding of a point: the picture fills it, no bars (the device draws it aspect-fit).
for (name, w, h, _, _) in spaces {
    guard let s = panel(w, h) else { continue }
    let bars = abs(Double(s.widthPt) / Double(s.heightPt) - w / h) / (w / h)
    check(bars < 0.002, "\(name): the picture's shape kept (\(bars))")
}
check(VDS.device(space: nil) == nil, "no viewport: none (the caller's fallback)")
check(VDS.device(space: CGSize(width: 0, height: 0)) == nil, "a space with no area: none")
check(VDS.device(space: CGSize(width: -5, height: 300)) == nil, "a negative side: none")
check(VDS.device(space: CGSize(width: Double.nan, height: 900)) == nil, "NaN: none")
check(VDS.device(space: CGSize(width: Double.infinity, height: 900)) == nil, "an infinite side: none")
check(VDS.fallback == size(1920, 1080), "the fallback with no viewport: #200's 1920×1080 at Retina")
check(VDS.minSide == 800 && VDS.maxSide == 4096 && VDS.scale == 2, "800 to 4096 points a side, at 2x")

// 20,000 random panels within what a host takes (ViewportBounds: 1 to 16384 points a side): every side 800 to 4096 and
// whole, at 2x; a device whose rounded sides are both within 800…4096 gets them exactly; a shape within 800:4096 is kept
// within two points (the shorter side against the longer's factor); never smaller than the device in both sides.
var rng = SystemRandomNumberGenerator()
var shapeChecked = 0
for i in 0..<20_000 {
    let w = i % 4 == 0 ? Double(Int.random(in: 1...16384, using: &rng)) : Double.random(in: 1...16384, using: &rng)
    let h = i % 3 == 0 ? Double.random(in: 300...2000, using: &rng) : Double.random(in: 1...16384, using: &rng)
    guard let s = panel(w, h) else { check(false, "random \(w)×\(h): none"); continue }
    let wr = max(1, w.rounded()), hr = max(1, h.rounded())
    let ok = (800...4096).contains(s.widthPt) && (800...4096).contains(s.heightPt) && s.scale == 2
    if !ok { check(false, "random \(w)×\(h) → \(s): a side out of 800…4096"); continue }
    if (800...4096).contains(wr) && (800...4096).contains(hr) {
        check(s.widthPt == Int(wr) && s.heightPt == Int(hr), "random \(w)×\(h) within bounds → \(s): not its own points")
    }
    let longR = max(wr, hr), shortR = min(wr, hr)
    if longR / shortR <= 4096.0 / 800.0 {
        shapeChecked += 1
        let long = Double(max(s.widthPt, s.heightPt)), short = Double(min(s.widthPt, s.heightPt))
        let landscapeKept = (wr >= hr) == (s.widthPt >= s.heightPt) || wr == hr || s.widthPt == s.heightPt
        check(abs(short - shortR * long / longR) <= 2 && landscapeKept, "random \(w)×\(h) → \(s): the shape not kept")
    }
}
check(shapeChecked > 5000, "the shape judged on enough random panels (\(shapeChecked))")

// MARK: An iPhone: pixel for pixel (Noah, 2026-11-24: "middle one for iPhones, and leaving iPads as they are")

// The device's picture's space (rule A, its viewport's panel) counted in the iPhone's own pixels (its screen's scale) and
// made as a 2x desktop of that many pixels, the spare pixel of an odd side left over; grown evenly where a side would be
// under 540 points or both under 800 (default 47: the least macOS keeps at 2x, as Noah's probes P3 and P4 found it on
// 2026-11-26). The spaces are the devices' own, as their consoles print them (the step file's fifth part): an iPhone 15
// Pro, 393 × 852 points at 3x, 1179 × 2556 pixels; the others from each iPhone's safe area, as below.
func phone(_ w: Double, _ h: Double, scale: Double = 3) -> VDS.Size? {
    VDS.device(space: CGSize(width: w, height: h), screen: VDS.Screen(pixelWidth: 1179, pixelHeight: 2556, scale: scale, phone: true))
}
let phoneSpaces: [(String, Double, Double, Double, Int, Int, Bool)] = [
    ("iPhone 15 Pro upright, Full Screen (393×793, 1179×2379 px)", 393, 793, 3, 589, 1189, true),
    ("iPhone 15 Pro on its side, Full Screen (734×393, 2202×1179 px)", 734, 393, 3, 1101, 589, true),
    ("iPhone 15 Pro on its side, the controls showing (718×299, 2154×897 px): grown to 540 tall, P4's 1297×540", 718, 299, 3, 1297, 540, false),
    ("iPhone 15 Pro upright, the controls showing (its 16:10 pane, 377×235, 1131×705 px): grown to 540 tall, P4's 866×540", 377, 235, 3, 866, 540, false),
    ("iPhone 12 to 14 on its side, the controls showing (734×296, 2202×888 px): grown to 540 tall", 734, 296, 3, 1339, 540, false),
    ("iPhone 12 mini on its side, the controls showing (696×281, 2088×843 px): grown to 540 tall", 696, 281, 3, 1338, 540, false),
    ("iPhone 16 Pro Max on its side, the controls showing (816×346, 2448×1038 px): grown to 540 tall", 816, 346, 3, 1274, 540, false),
    ("iPhone Duo's inner display flat (951×669, 2853×2007 px)", 951, 669, 3, 1426, 1003, true),
    ("iPhone SE upright, Full Screen (375×667 at 2x): its own points, grown to 540 wide", 375, 667, 2, 540, 960, false),
    ("iPhone SE upright, the controls showing (its 16:10 pane, 359×224 at 2x): grown to 540 tall", 359, 224, 2, 865, 540, false),
    ("a wide short pane (734×250 at 3x, 1101×375): grown to 540 tall", 734, 250, 3, 1585, 540, false),
    ("a small square-ish pane (600×450 at 2x): grown to 800 long", 600, 450, 2, 800, 600, false),
    ("fractions (377.3333×235.6667 at 3x is 1132×707 px)", 377.3333, 235.6667, 3, 865, 540, false),
]
for (name, w, h, sc, ew, eh, own) in phoneSpaces {
    let s = phone(w, h, scale: sc)
    check(s == size(ew, eh), "\(name): \(ew)×\(eh) (\(String(describing: s)))")
    check(s.map { VDS.pixelForPixel($0, space: CGSize(width: w, height: h), scale: sc) } == own,
          "\(name): pixel for pixel \(own)")
    // Its shape is the space's within a point either way: no bars beyond a hairline.
    if let s, !own {
        let bars = abs(Double(s.widthPt) / Double(s.heightPt) - w / h) / (w / h)
        check(bars < 0.003, "\(name): grown, the shape kept (\(bars))")
    }
}
check(VDS.pixels(space: CGSize(width: 377.3333, height: 235.6667), scale: 3).map { [$0.width, $0.height] } == [1132, 707],
      "a side within a thousandth of a pixel of a whole number is that number")
// A pane of fractions of a pixel (377.8667 points at 3x is 1133.6 pixels): the whole pixels it holds, never one past its
// edge, which the device would then draw scaled down by a hair.
check(VDS.pixels(space: CGSize(width: 377.8667, height: 793), scale: 3).map { [$0.width, $0.height] } == [1133, 2379]
      && phone(377.8667, 793) == size(566, 1189), "a pane's pixels rounded down: 1133.6 pixels hold 1133, and 566 points at 2x")
check(VDS.phoneShort == 540 && VDS.phoneLong == 800, "an iPhone's desktop: at least 540 points a side and 800 on its longer (P3 and P4's line)")
// The iPad keeps its rule, as before; so does a device that says nothing of its screen, and a size macOS did not keep.
for (name, w, h, _, _) in spaces {
    let pad = VDS.device(space: CGSize(width: w, height: h), screen: VDS.Screen(pixelWidth: 1488, pixelHeight: 2266, scale: 2, phone: false))
    check(pad == panel(w, h), "an iPad's screen, \(name): as before (\(String(describing: pad)))")
    check(VDS.device(space: CGSize(width: w, height: h), screen: nil) == panel(w, h), "no screen, \(name): as before")
}
let upFS = CGSize(width: 393, height: 793), pro = VDS.Screen(pixelWidth: 1179, pixelHeight: 2556, scale: 3, phone: true)
check(VDS.device(space: upFS, screen: pro, refused: ["589x1189@2"]) == size(800, 1614),
      "an iPhone's size macOS did not keep this run: the size that works, 800×1614 (Noah's run 5 size)")
check(VDS.device(space: upFS, screen: pro, refused: ["1101x589@2"]) == size(589, 1189), "another size refused: pixel for pixel still")
check(VDS.device(space: nil, screen: pro) == nil, "no space: none")
check(VDS.phone(space: CGSize(width: 16384, height: 1000), scale: 3) == size(4096, 250), "past 4096 points: shrunk evenly (16384×1000 at 3x)")
// 20,000 random iPhone spaces at 2x and 3x: at 2x always; pixel for pixel (each side half the space's pixels, at most one
// pixel spare) exactly when that is at least 540 a side and 800 on the longer; else grown evenly to them, the shape kept
// within a point; never a side over 4096; and every one a size the said display keeps at 2x (P3 and P4's line), unless
// a shape no iPhone has was held to 4096.
var phoneWrong = 0, phoneBent = 0, phoneOwn = 0, phoneFirst: [String] = []
func phoneNot(_ why: String) { phoneWrong += 1; if phoneFirst.count < 3 { phoneFirst.append(why) } }
for _ in 0..<20_000 {
    let w = Double.random(in: 120...1600, using: &rng), h = Double.random(in: 120...1600, using: &rng)
    let sc: Double = Bool.random(using: &rng) ? 3 : 2
    guard let s = phone(w, h, scale: sc), let px = VDS.pixels(space: CGSize(width: w, height: h), scale: sc) else { phoneNot("\(w)×\(h) at \(sc): none"); continue }
    let half = (w: px.width / 2, h: px.height / 2)
    let fits = min(half.w, half.h) >= 540 && max(half.w, half.h) >= 800
    if s.scale != 2 || max(s.widthPt, s.heightPt) > 4096 { phoneNot("\(w)×\(h) at \(sc): \(s)"); continue }
    if fits {
        phoneOwn += 1
        if s.widthPt != half.w || s.heightPt != half.h || px.width - 2 * s.widthPt > 1 || px.height - 2 * s.heightPt > 1 {
            phoneNot("\(w)×\(h) at \(sc) (\(px.width)×\(px.height) px): \(s), not its own")
        }
    } else {
        phoneBent += 1
        let short = min(s.widthPt, s.heightPt), long = max(s.widthPt, s.heightPt)
        // Each side within half a point of its exact growth: the shape within that rounding. A shape past 4096 : 540
        // (7.59 : 1, no iPhone's) grown to 540 would pass 4096: the ceiling wins, both sides shrunk again by one factor
        // (two roundings), its shorter side then under 540.
        let r = Double(px.width) / Double(px.height)
        let rel = abs(Double(s.widthPt) / Double(s.heightPt) / r - 1)
        let ceiling = long == 4096 && Double(max(px.width, px.height)) / Double(min(px.width, px.height)) > 4096.0 / 540
        if ceiling {
            if short > 540 || rel > 1 / Double(s.widthPt) + 1 / Double(s.heightPt) + 1e-5 {
                phoneNot("\(w)×\(h) at \(sc) (\(px.width)×\(px.height) px): \(s), held to 4096 wrong (\(rel))")
            }
            continue
        } else if short < 540 || long < 800 || (short > 540 && long > 800) || rel > 0.5 / Double(s.widthPt) + 0.5 / Double(s.heightPt) + 1e-5 {
            phoneNot("\(w)×\(h) at \(sc) (\(px.width)×\(px.height) px): \(s), grown wrong (\(rel))")
        }
    }
    if !VDS.TestDisplay.keeps(s, knobs: VDS.TestKnobs()) { phoneNot("\(w)×\(h) at \(sc): \(s), under the line macOS keeps") }
}
check(phoneWrong == 0 && phoneBent > 2000 && phoneOwn > 2000,
      "20,000 random iPhone spaces: pixel for pixel when 540 by 800 or more, else grown to it, shape kept, each kept at 2x (\(phoneWrong) not; \(phoneOwn) own, \(phoneBent) grown; first \(phoneFirst))")
// Every current iPhone's four layouts: Full Screen's room clear of the housing (FullScreenPolicy.room), the pane under the
// landscape bar (its 78 points and the panel's 8-point margins) and the 16:10 pane upright (PhonePortraitLayout), from each
// one's safe area as Apple ships it (an iPhone 15 Pro's four and an iPhone 12's on its side are its console's). Each the
// said display keeps at 2x, pixel for pixel exactly when its own pixels are kept: none under the line, none bent for nothing.
let iPhones: [(String, Double, Double, Double, Double, Double)] = [   // its points wide and high upright, scale, top and side inset
    ("iPhone SE", 375, 667, 2, 0, 0), ("iPhone 12 mini, 13 mini", 375, 812, 3, 50, 50), ("iPhone 12 to 14, 16e, 17e", 390, 844, 3, 47, 47),
    ("iPhone 14 Plus", 428, 926, 3, 47, 47), ("iPhone 15, 15 Pro, 16", 393, 852, 3, 59, 59), ("iPhone 15 Plus, 15 Pro Max, 16 Plus", 430, 932, 3, 59, 59),
    ("iPhone 16 Pro, 17, 17 Pro, 18 Pro", 402, 874, 3, 62, 62), ("iPhone Air", 420, 912, 3, 62, 62), ("iPhone 16 to 18 Pro Max", 440, 956, 3, 62, 62),
]
var layoutsBent = 0, layoutsOwn = 0
for (name, w, h, sc, top, side) in iPhones {
    let pane = w - 16
    for (layout, sw, sh) in [("upright, Full Screen", w, h - top), ("on its side, Full Screen", h - 2 * side, w),
                             ("on its side, its controls", h - 2 * side - 16, w - 94), ("upright, its controls", pane, (pane / 1.6).rounded(.down))] {
        let space = CGSize(width: sw, height: sh)
        guard let s = VDS.phone(space: space, scale: sc), let px = VDS.pixels(space: space, scale: sc) else { check(false, "\(name) \(layout): none"); continue }
        let own = size(px.width / 2, px.height / 2), mine = VDS.pixelForPixel(s, space: space, scale: sc)
        if mine { layoutsOwn += 1 } else { layoutsBent += 1 }
        check(VDS.TestDisplay.keeps(s, knobs: VDS.TestKnobs()) && mine == VDS.TestDisplay.keeps(own, knobs: VDS.TestKnobs()),
              "\(name) \(layout) (\(Int(sw))×\(Int(sh)) pt): \(s), kept at 2x, pixel for pixel exactly when its own \(own) is kept")
    }
}
check(layoutsOwn == 16 && layoutsBent == 20, "with Full Screen every iPhone but the SE pixel for pixel; with its controls every one bent (\(layoutsOwn), \(layoutsBent))")
// The words its lines carry.
check(VDS.pixelWords(size(589, 1189), space: upFS, screen: pro) == "1179×2379 px; pixel for pixel", "the made line's words, pixel for pixel")
check(VDS.pixelWords(size(866, 540), space: CGSize(width: 377, height: 235), screen: pro)
      == "1131×705 px; scaled to fit: an iPhone's desktop is at least 540 pt a side and 800 pt on its longer", "…grown")
check(VDS.pixelWords(size(800, 1614), space: upFS, screen: pro) == "1179×2379 px; at least 800 pt a side: macOS did not keep it pixel for pixel",
      "…the size that works")
check(VDS.pixelWords(size(1218, 800), space: CGSize(width: 1133, height: 744), screen: VDS.Screen(pixelWidth: 1488, pixelHeight: 2266, scale: 2, phone: false)) == nil
      && VDS.pixelWords(size(800, 1614), space: upFS, screen: nil) == nil, "…none for an iPad's or an older device's")
check(VirtualDesktopLife.madeLine(came: size(589, 1189), asked: size(589, 1189), hz: 120, id: 9, ms: 450, device: "iPhone", space: upFS,
                                  pixels: VDS.pixelWords(size(589, 1189), space: upFS, screen: pro))
      == "Virtual Desktop 589×1189 pt @2× at 120 Hz id 9: made in 450 ms for iPhone (its picture: 393×793 pt, 1179×2379 px; pixel for pixel).",
      "the make's line says the pixel-for-pixel size")
// What a make does with what came up: an iPhone's size macOS did not keep is made again at the size that works (on Noah's
// Mac no iPhone's size needs it since P4; the safety net for a Mac whose line runs elsewhere).
check(VDS.afterMake(asked: size(589, 1189), came: size(589, 1189), works: size(800, 1614)) == .kept, "came as asked: kept")
check(VDS.afterMake(asked: size(1077, 448), came: VDS.Size(widthPt: 2154, heightPt: 896, scale: 1), works: size(1921, 800)) == .again(size(1921, 800)),
      "an iPhone's size at 1x (P3's 1077×448 made: its pixels at 1x): made again at the size that works")
check(VDS.afterMake(asked: size(800, 499), came: VDS.Size(widthPt: 800, heightPt: 499, scale: 1), works: size(1283, 800)) == .again(size(1283, 800)),
      "…at its points at 1x (P3's 800×499)")
check(VDS.afterMake(asked: size(589, 1189), came: size(600, 1189), works: size(800, 1614)) == .again(size(800, 1614)), "…or at another size")
check(VDS.afterMake(asked: size(1218, 800), came: VDS.Size(widthPt: 1218, heightPt: 800, scale: 1), works: size(1218, 800)) == .kept,
      "an iPad's (the size that works asked already): kept as it came, as before")
check(VDS.afterMake(asked: size(1920, 1080), came: VDS.Size(widthPt: 1920, heightPt: 1080, scale: 1), works: nil) == .kept, "a chosen size: kept")
check(VDS.refusedLine(asked: size(800, 499), came: VDS.Size(widthPt: 800, heightPt: 499, scale: 1), works: size(1283, 800), inPlace: false)
      == "Virtual Desktop: macOS did not keep 800×499 pt @2× (it came up at 800×499 pt @1×); made it at 1283×800 pt @2×, the size that works, the picture scaled.",
      "the fall back's one line, at a make (Noah's log of run 6's bend, 2026-11-26)")
check(VDS.refusedLine(asked: size(589, 1189), came: nil, works: size(800, 1614), inPlace: false).contains("@2× (it would not make it); made it at 800×1614"),
      "…a make that threw")
check(VDS.refusedLine(asked: size(1101, 589), came: VDS.Size(widthPt: 1495, heightPt: 800, scale: 1), works: size(1494, 800), inPlace: true)
      == "Virtual Desktop: macOS did not keep 1101×589 pt @2× in place (it went to 1495×800 pt @1× instead); following at 1494×800 pt @2×, the size that works, the picture scaled.",
      "…in place")
check(VDS.refusedLine(asked: size(1077, 448), came: nil, works: size(1921, 800), inPlace: true)
      == "Virtual Desktop: macOS did not keep 1077×448 pt @2× in place; following at 1921×800 pt @2×, the size that works, the picture scaled.",
      "…in place, its 2x mode never listed (Noah's log, 2026-11-26)")
// TEST ONLY: the said display keeps what P3 and P4 saw kept (macOS 27.2.1, 2026-11-26), and does with the rest what they
// saw: made, at 1x (its pixels, or its points at a longer side of 800) or at no mode; in place, at its pixels at 1x, its
// 2x mode never listed (the follows below).
let p4Kept = [size(589, 1189), size(1101, 589), size(1383, 576), size(1345, 560), size(1297, 540), size(945, 589), size(924, 576),
              size(898, 560), size(866, 540), size(800, 540), size(800, 800)]
let p4NotKept = [size(1229, 512), size(1153, 480), size(821, 512), size(1077, 448), size(800, 499), size(499, 1189), size(448, 1077),
                 size(1600, 448), size(754, 784), size(565, 352)]
check(p4Kept.allSatisfy { VDS.TestDisplay.keeps($0, knobs: VDS.TestKnobs()) } && !p4NotKept.contains { VDS.TestDisplay.keeps($0, knobs: VDS.TestKnobs()) },
      "the said display keeps at 2x exactly the sizes P3 and P4 saw kept, of the 21 they tried")
check(VDS.TestDisplay.keeps(VDS.Size(widthPt: 1077, heightPt: 448, scale: 1), knobs: VDS.TestKnobs()) && VDS.TestDisplay.keptShort == VDS.phoneShort
      && VDS.TestDisplay.keptLong == VDS.phoneLong, "…a 1x size always; the bend takes its line")
check(VDS.TestDisplay.madeAt(size(1077, 448), knobs: VDS.TestKnobs()) == VDS.Size(widthPt: 2154, heightPt: 896, scale: 1)
      && VDS.TestDisplay.madeAt(size(800, 499), knobs: VDS.TestKnobs()) == VDS.Size(widthPt: 800, heightPt: 499, scale: 1)
      && VDS.TestDisplay.madeAt(size(565, 352), knobs: VDS.TestKnobs()) == nil,
      "made, as P3 and P4 saw: 1077×448 at its pixels at 1x, 800×499 at its points at 1x, 565×352 at no mode")
check(VDS.TestDisplay.madeAt(size(1297, 540), knobs: VDS.TestKnobs()) == size(1297, 540) && VDS.TestDisplay.madeAt(size(866, 540), knobs: VDS.TestKnobs()) == size(866, 540),
      "…P4's 1297×540 and 866×540 made as they are, at 2x")
var noMode = VDS.TestDisplay(made: size(565, 352), backing: bk(4096, 4096))
check(noMode.read(at: 0) == nil && noMode.read(at: 5) == nil, "…a display made at no mode reads none")
// TEST ONLY: short-1x, the line at 744 (P1's least kept): a Mac where macOS draws it elsewhere, the fall back's case.
let shortK = VDS.TestKnobs(shortOneX: true)
check(!VDS.TestDisplay.keeps(size(589, 1189), knobs: shortK) && !VDS.TestDisplay.keeps(size(1297, 540), knobs: shortK)
      && VDS.TestDisplay.keeps(size(1133, 744), knobs: shortK) && VDS.TestDisplay.keeps(size(800, 1614), knobs: shortK),
      "short-1x: an iPhone's sizes not kept, P1's 1133×744 and the size that works kept")
check(VDS.TestDisplay.madeAt(size(589, 1189), knobs: shortK) == VDS.Size(widthPt: 1178, heightPt: 2378, scale: 1)
      && VDS.TestDisplay.madeAt(size(800, 600), knobs: shortK) == VDS.Size(widthPt: 800, heightPt: 600, scale: 1),
      "…made: at its pixels at 1x (as P3's 1077×448), at its points with a longer side of 800 (as P3's 800×499)")
var shortD = VDS.TestDisplay(made: size(589, 1189), backing: bk(4096, 4096), knobs: shortK)
check(shortD.read(at: 0) == VDS.Size(widthPt: 1178, heightPt: 2378, scale: 1), "…a display made so reads it at once")
var shortF = VDS.TestDisplay(made: size(800, 1614), backing: bk(4096, 4096), knobs: shortK)
_ = shortF.apply(size(1101, 589), at: 0)
check(shortF.read(at: 1) == VDS.Size(widthPt: 2202, heightPt: 1178, scale: 1) && !shortF.lists(size(1101, 589), at: 3),
      "…and a follow to one lands at its pixels at 1x, its 2x mode never listed")
check(VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "short-1x"], on: true).knobs == shortK, "short-1x read from SILL_TEST_VD_STEPS")
// The follow's line says an iPhone's desktop is pixel for pixel; an iPad's line as before.
check(VDS.followLine(device: "iPhone", why: .room(turned: true), from: size(589, 1189), to: size(1101, 589), step: .inPlace,
                     outcome: .done(ms: 650), hz: 120, pixelForPixel: true)
      == "Virtual Desktop: iPhone turned; followed in place in 650 ms: 1101×589 pt @2× at 120 Hz, pixel for pixel.", "the follow's line, pixel for pixel")
check(VDS.followLine(device: "iPad mini", why: .room(turned: true), from: size(1218, 800), to: size(800, 1218), step: .inPlace,
                     outcome: .done(ms: 650), hz: 60)?.hasSuffix(" at 60 Hz.") == true, "…an iPad's as before")

// MARK: The rate: the device's, held to 24 and to the Mac's Frame Rate limit; 60 with no viewport

check(VDS.rate(viewportFPS: 120, limit: 120) == 120, "a ProMotion iPad, the limit 120: 120 Hz")
check(VDS.rate(viewportFPS: 60, limit: 120) == 60, "an iPad mini: 60 Hz")
check(VDS.rate(viewportFPS: nil, limit: 120) == 60, "no viewport: 60")
check(VDS.rate(viewportFPS: 120, limit: 60) == 60, "the Mac's limit 60: 60")
check(VDS.rate(viewportFPS: 120, limit: 30) == 30, "the Mac's limit 30: 30")
check(VDS.rate(viewportFPS: 10, limit: 120) == 24, "a rate under 24: 24")
check(VDS.rate(viewportFPS: 500, limit: 120) == 120, "a rate past the limit: the limit")
check(VDS.rate(viewportFPS: nil, limit: 10) == 24, "a limit under 24 is no limit under 24")

// MARK: Whose viewport sizes it: the asking device's, else the newest, else none

check(VDS.matched(asker: "ipad", newest: "iphone", sent: ["ipad", "iphone"]) == "ipad", "the asker's when it sent one")
check(VDS.matched(asker: "ipad", newest: "iphone", sent: ["iphone"]) == "iphone", "the asker without one: the newest")
check(VDS.matched(asker: nil, newest: "iphone", sent: ["iphone"]) == "iphone", "no asker known: the newest")
check(VDS.matched(asker: "ipad", newest: nil, sent: []) == nil, "nobody sent one: none")
check(VDS.matched(asker: "ipad", newest: "gone", sent: ["ipad"]) == "ipad", "the newest gone: the asker's")
check(VDS.matched(asker: "gone", newest: "gone", sent: ["ipad"]) == nil, "both gone: none")

// MARK: The refresh rate the Desktop's stream is held to (defect 4 of the assessment)

check(VDS.refreshHeld(stop: 75, sills: 60, onSills: false) == 75, "a stop's rate first")
check(VDS.refreshHeld(stop: 75, sills: 60, onSills: true) == 75, "a stop's rate first, always")
check(VDS.refreshHeld(stop: nil, sills: 60, onSills: true) == 60, "on Sill's own display: its rate (a 120 Hz device beside the 60 Hz one it was made for)")
check(VDS.refreshHeld(stop: nil, sills: 60, onSills: false) == nil, "no stop and not on Sill's display (the stand-in): none")
check(VDS.refreshHeld(stop: nil, sills: nil, onSills: true) == nil, "Sill's display with no rate read: none")

// MARK: The creation line: the mode it came up at, what was asked when it differs, whose screen

check(VDS.createdLine(came: size(1218, 800), asked: size(1218, 800), hz: 60, id: 66, device: "iPad mini")
      == "Headless display: created 1218×800 pt @2× at 60 Hz (id 66) for iPad mini, its screen.", "the line as the plan words it")
check(VDS.createdLine(came: VDS.Size(widthPt: 1218, heightPt: 800, scale: 1), asked: size(1218, 800), hz: 60, id: 66, device: "iPad mini")
      == "Headless display: created 1218×800 pt @1× at 60 Hz (asked 1218×800 @2×) (id 66) for iPad mini, its screen.",
      "a mode other than the one asked: both said (#200's line claimed @2× whatever it got)")
check(VDS.createdLine(came: size(1218, 800), asked: size(1218, 800), hz: 60, id: nil, device: "iPad")
      == "Headless display: created 1218×800 pt @2× at 60 Hz (TEST ONLY: none made, SILL_TEST_HEADLESS) for iPad, its screen.",
      "a test host's said display")
check(VDS.createdLine(came: VDS.fallback, asked: VDS.fallback, hz: 60, id: 7, device: nil)
      == "Headless display: created 1920×1080 pt @2× at 60 Hz (id 7) at 1920×1080: no device's screen known yet.",
      "no viewport from any device")

// MARK: The guard for #380 (DisplayMakeGuard)

typealias G = DisplayMakeGuard
check(G.tripAt == 2, "two runs in a row")
check(G.atLaunch(markerFound: true, stops: 0) == 1, "a marker at launch: one stop")
check(G.atLaunch(markerFound: true, stops: 1) == 2, "a second in a row: two")
check(G.atLaunch(markerFound: false, stops: 1) == 1, "no marker: the count as kept")
check(G.atLaunch(markerFound: false, stops: 0) == 0, "no marker, none kept: none")
check(G.atLaunch(markerFound: true, stops: -3) == 1, "a count under 0 kept: taken as 0")
check(!G.holds(stops: 0) && !G.holds(stops: 1) && G.holds(stops: 2) && G.holds(stops: 5), "holds from two")
check(G.afterMake(cameUp: true, stops: 1) == 0 && G.afterMake(cameUp: true, stops: 2) == 0, "a display that came up: 0")
check(G.afterMake(cameUp: false, stops: 1) == 1 && G.afterMake(cameUp: false, stops: 0) == 0, "one that did not: unchanged")
let when = Date(timeIntervalSince1970: 1_795_000_000)
check(G.marker(role: "stage", at: when) == "stage 2026-11-18T11:06:40Z\n", "the marker: its role and the time, UTC (\(G.marker(role: "stage", at: when)))")
check(G.parse(G.marker(role: "desktop", at: when)).map { $0.role == "desktop" && $0.at == when } == true, "a marker read back")
check(G.parse("") == nil && G.parse("stage") == nil && G.parse("window 2026-11-18T11:06:40Z") == nil && G.parse("stage tomorrow") == nil,
      "anything else is no marker's words")
check(G.launchLine(marker: nil, stops: 1) == nil, "no marker: no line")
check(G.launchLine(marker: G.marker(role: "stage", at: when), stops: 1)
      == "Sill stopped while making a display last time (its window display, 2026-11-18T11:06:40Z); after 2 runs in a row it makes none by itself.",
      "one stop: its line (\(G.launchLine(marker: G.marker(role: "stage", at: when), stops: 1) ?? "nil"))")
check(G.launchLine(marker: G.marker(role: "desktop", at: when), stops: 2)
      == "Sill stopped while making a display last time (2 runs in a row: its Desktop display, 2026-11-18T11:06:40Z); it makes none by itself until you choose Try Again in Settings › Virtual Display.",
      "two in a row: it holds, and where Try Again is")
check(G.launchLine(marker: "", stops: 2)
      == "Sill stopped while making a display last time (2 runs in a row); it makes none by itself until you choose Try Again in Settings › Virtual Display.",
      "a marker half written still counts, without its words")

// The Store, in a folder of its own: a run that ends while making (a crash), the next one, Try Again, a clean quit.
let base = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
    .appendingPathComponent("guard-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: base)
var kept = 0
func store(_ name: String) -> G.Store {
    G.Store(folder: base.appendingPathComponent(name), readStops: { kept }, writeStops: { kept = $0 })
}
try? FileManager.default.createDirectory(at: base.appendingPathComponent("a"), withIntermediateDirectories: true)
var s = store("a")
check(s.stops == 0 && !s.holds && s.launchLine == nil && !s.markerPresent, "a first launch: nothing")
s.willMake("stage", at: when)
check(s.markerPresent, "the marker written before the private calls")
check((try? String(contentsOf: base.appendingPathComponent("a/making-display"), encoding: .utf8)) == "stage 2026-11-18T11:06:40Z\n",
      "…saying what and when")
s.made(cameUp: true)
check(!s.markerPresent && s.stops == 0, "came up: the marker gone, nothing counted")
s.willMake("stage", at: when)                    // and the run ends here: a crash
s = store("a")
check(s.stops == 1 && kept == 1 && !s.holds && s.launchLine?.hasPrefix("Sill stopped while making a display last time (its window display") == true,
      "the next launch: one stop, its line, still making displays")
check(!s.markerPresent, "…and the marker taken")
s.willMake("desktop", at: when)                  // ends again
s = store("a")
check(s.stops == 2 && kept == 2 && s.holds, "two runs in a row: it holds")
check(s.launchLine?.contains("until you choose Try Again") == true, "…and says where Try Again is")
s = store("a")
check(s.stops == 2 && s.holds && s.launchLine == nil, "a launch with no marker keeps holding, with no line")
s.tryAgain()
check(s.stops == 0 && kept == 0 && !s.holds, "Try Again: 0, kept")
s.willMake("desktop", at: when)
s.made(cameUp: false)
check(!s.markerPresent && s.stops == 0, "a make that failed is no stop")
s.willMake("stage", at: when)
s = store("a")
check(s.stops == 1, "one stop")
s.willMake("stage", at: when)
s.made(cameUp: true)
check(s.stops == 0 && kept == 0, "a display that came up resets the count")
s.willMake("stage", at: when)
s.quitting()
s = store("a")
check(s.stops == 0 && s.launchLine == nil, "a clean quit while making is no stop")
// A marker left empty (the run ended mid-write) still counts, and so does one that is no text at all.
FileManager.default.createFile(atPath: base.appendingPathComponent("a/making-display").path, contents: Data())
s = store("a")
check(s.stops == 1 && s.launchLine?.contains("last time;") == true, "an empty marker counts (\(s.launchLine ?? "nil"))")
FileManager.default.createFile(atPath: base.appendingPathComponent("a/making-display").path, contents: Data([0xFF, 0xFE, 0x00, 0xD8]))
s = store("a")
check(s.stops == 2 && s.holds && !s.markerPresent, "a marker that is no text counts too, and is taken (\(s.stops))")
s.tryAgain()
// The TEST ONLY store: the count in a file beside the marker.
let testFolder = base.appendingPathComponent("test")
var t = G.Store.test(folder: testFolder)
check(t.stops == 0 && !t.holds, "a test folder: nothing")
t.willMake("desktop", at: when)
t = G.Store.test(folder: testFolder)
t.willMake("desktop", at: when)
t = G.Store.test(folder: testFolder)
check(t.stops == 2 && t.holds && (try? String(contentsOf: testFolder.appendingPathComponent("display-make-stops"), encoding: .utf8)) == "2\n",
      "the test store's count in its file")
t.tryAgain()
check(G.Store.test(folder: testFolder).stops == 0, "Try Again written to it")

// 2,000 random lives of Sill.app against a model: each run makes displays that come up, fail, or end the run mid-way
// (a crash), quits cleanly or not, and the person may choose Try Again; never a display by itself while it holds.
for life in 0..<2_000 {
    let folder = "life\(life % 4)"
    try? FileManager.default.removeItem(at: base.appendingPathComponent(folder))
    try? FileManager.default.createDirectory(at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
    kept = 0
    var model = 0
    var markerLeft = false
    for _ in 0..<Int.random(in: 1...8, using: &rng) {
        let run = store(folder)
        if markerLeft { model += 1 }                // the model: one more stop for a run that ended while making
        markerLeft = false
        check(run.stops == model && run.holds == (model >= 2), "life \(life): the count \(run.stops), the model \(model)")
        if Bool.random(using: &rng), model >= 2 { run.tryAgain(); model = 0 }
        var crashed = false
        for _ in 0..<Int.random(in: 0...3, using: &rng) {
            if run.holds { check(model >= 2, "life \(life): holds only from two"); break }   // makes none by itself
            run.willMake(Bool.random(using: &rng) ? "stage" : "desktop", at: when)
            switch Int.random(in: 0...2, using: &rng) {
            case 0: run.made(cameUp: true); model = 0
            case 1: run.made(cameUp: false)
            default: crashed = true; markerLeft = true
            }
            if crashed { break }
        }
        if !crashed, Bool.random(using: &rng) { run.quitting() }
        check(run.markerPresent == markerLeft, "life \(life): the marker left only by a run that ended while making")
    }
}
try? FileManager.default.removeItem(at: base)

// MARK: Following the device (VirtualDesktopSize.Follow, followStep, the backing, InPlace, the lines; plan §5)

let mini = size(1218, 800), miniUp = size(800, 1218)
check(mini.turned == miniUp && size(900, 900).turned == size(900, 900) && VDS.Size(widthPt: 3, heightPt: 4, scale: 1).turned.scale == 1,
      "a size turned a quarter, its scale kept")
check(VDS.followWay == .newModes,
      "the probes' verdict (P2b and P2c, 2026-11-23): in place, by applySettings: with the size alone and a switch for a turn")
check(VDS.FollowWay.allCases == [.nextMake, .newModes, .remake], "no way by the modes listed at creation (P2b: refused, complete 1001)")

// The backing: its own pixels; following a device, a square of 4096 pixels (the encoder's widest picture, #295), never
// less than its own, which holds every iPhone's and iPad's space both ways (rule B, Noah's first try of 2026-11-24).
func bk(_ w: Int, _ h: Int) -> VDS.Backing { VDS.Backing(wide: w, high: h) }
check(VDS.backingCap == 4096, "the cap 4096 px")
check(VDS.backing(made: mini, follows: true) == bk(4096, 4096), "an iPad mini's: the cap's square")
check(VDS.backing(made: size(1376, 1032), follows: true) == bk(4096, 4096), "an iPad Pro 13-inch's: the cap's square")
check(VDS.backing(made: size(2600, 800), follows: true) == bk(5200, 4096),
      "a display made past the cap: its own pixels that way, the cap the other (\(VDS.backing(made: size(2600, 800), follows: true)))")
check(VDS.backing(made: size(1920, 1080), follows: false) == bk(3840, 2160), "a chosen size never follows: its own pixels, as every display Sill made")
check(VDS.backing(made: VDS.Size(widthPt: 1920, heightPt: 1080, scale: 1), follows: false) == bk(1920, 1080), "at 1x: its points")
check(VDS.fits(miniUp, bk(3072, 3072)) && VDS.fits(size(1536, 800), bk(3072, 3072)) && !VDS.fits(size(1537, 800), bk(3072, 3072))
      && !VDS.fits(size(800, 1537), bk(3072, 3072)) && VDS.fits(size(1536, 1536), bk(3072, 3072)),
      "fits: its pixels each way inside, to the pixel")
check(VDS.fits(size(1218, 800), bk(2436, 1600)) && !VDS.fits(miniUp, bk(2436, 1600)), "the made size's own backing holds it and not its turn")
// Every space of the table above, and every iPhone's and iPad's in a layout of its own, made for one and followed to by
// any other, either way round: inside the backing made for any of them. Noah's first try: an iPad's display (3072 px)
// and the iPhone upright with Full Screen (800×1614, 3228 px): now inside.
let anyDevice = spaces.compactMap { panel($0.1, $0.2) } + [panel(393, 793)!, size(1376, 1032), size(1032, 1376)]
for made in anyDevice {
    let b = VDS.backing(made: made, follows: true)
    for other in anyDevice {
        check(VDS.fits(other, b) && VDS.fits(other.turned, b), "\(other) both ways inside the backing made for \(made) (\(b))")
    }
}
check(VDS.fits(size(2048, 800), bk(4096, 4096)) && !VDS.fits(size(2049, 800), bk(4096, 4096)) && !VDS.fits(size(800, 2049), bk(4096, 4096)),
      "a shape past 2.56 : 1 (a Stage Manager window wider than any screen) does not fit: the next make")
for _ in 0..<2_000 {
    let made = size(Int.random(in: 800...2600, using: &rng), Int.random(in: 800...2600, using: &rng))
    let other = size(Int.random(in: 800...2048, using: &rng), Int.random(in: 800...2048, using: &rng))
    let b = VDS.backing(made: made, follows: true)
    var ok = b.wide >= made.widthPt * 2 && b.high >= made.heightPt * 2
    ok = ok && b.wide == max(VDS.backingCap, made.widthPt * 2) && b.high == max(VDS.backingCap, made.heightPt * 2)
    ok = ok && VDS.fits(made, b) && VDS.fits(other, b) && VDS.fits(other.turned, b)
    check(ok, "random backing for \(made), another device's \(other): \(b)")
}

// The step: nothing for the size it has, nothing locked; in place for every device (its panel is its space), inside the
// backing.
func step(_ way: VDS.FollowWay, to: VDS.Size = miniUp, backing: VDS.Backing = bk(4096, 4096), headless: Bool = false,
          locked: Bool = false) -> VDS.FollowStep {
    VDS.followStep(to: to, display: mini, backing: backing, way: way, headless: headless, locked: locked)
}
for way in VDS.FollowWay.allCases {
    check(step(way, to: mini) == .nothing && step(way, to: mini, headless: true, locked: true) == .nothing, "\(way): the size it has: nothing")
    check(step(way, locked: true) == .later && step(way, headless: true, locked: true) == .later, "\(way): locked: at the unlock")
}
check(step(.nextMake) == .nextMake && step(.nextMake, headless: true) == .nextMake, "no way in place: the next make")
check(step(.newModes) == .inPlace && step(.newModes, to: size(1496, 800)) == .inPlace && step(.newModes, to: size(800, 1614)) == .inPlace,
      "a turn, another device, the iPhone upright after the iPad: in place inside the backing")
check(step(.newModes, to: size(2100, 800)) == .beyondBacking && step(.newModes, backing: bk(2436, 1600)) == .beyondBacking,
      "beyond the backing: the next make (P2b: never taken)")
check(step(.remake) == .remake, "the remake (phase 3)")
check(step(.remake, headless: true) == .nextMake, "never the headless display: the Mac's only screen is never removed and made again")

// What changed the space: its room (a turn, a fold) or its controls (Full Screen), from two viewports; none known
// without a room.
func cs(_ w: Double, _ h: Double) -> CGSize { CGSize(width: w, height: h) }
let roomL = cs(1133, 744), roomU = cs(744, 1133)
check(VDS.cause(roomBefore: roomL, room: roomL, panelBefore: cs(1117, 618), panel: roomL) == .controls(hidden: true), "Full Screen on: hid")
check(VDS.cause(roomBefore: roomL, room: roomL, panelBefore: roomL, panel: cs(1117, 618)) == .controls(hidden: false), "Full Screen off: showed")
check(VDS.cause(roomBefore: roomL, room: roomL, panelBefore: cs(653, 439), panel: cs(653, 420)) == .controls(hidden: nil),
      "the pane changed under the same room, neither hidden: the pane's own change")
check(VDS.cause(roomBefore: roomL, room: roomL, panelBefore: nil, panel: roomL) == .controls(hidden: nil), "no panel before: not said which")
check(VDS.cause(roomBefore: roomL, room: cs(1133.6, 744.4), panelBefore: cs(1117, 618), panel: cs(1133.6, 744.4)) == .controls(hidden: true),
      "within a point: the same room")
check(VDS.cause(roomBefore: roomL, room: roomU, panelBefore: cs(1117, 618), panel: cs(728, 535)) == .room(turned: true), "a turn, the controls showing")
check(VDS.cause(roomBefore: roomL, room: roomU, panelBefore: roomL, panel: roomU) == .room(turned: true), "a turn, Full Screen on")
check(VDS.cause(roomBefore: cs(393, 793), room: cs(734, 393), panelBefore: cs(377, 235), panel: cs(718, 299)) == .room(turned: true),
      "an iPhone turned (its Dynamic Island's inset moves)")
check(VDS.cause(roomBefore: cs(669, 951), room: cs(669, 496), panelBefore: cs(653, 439), panel: cs(653, 480)) == .room(turned: false),
      "the Duo half folded: its room, not a turn (wider than tall now, its shorter side not the one it had)")
check(VDS.cause(roomBefore: cs(1000, 700), room: cs(1000, 1200), panelBefore: cs(984, 600), panel: cs(984, 1100)) == .room(turned: false),
      "a window resized taller than wide: not a turn")
check(VDS.cause(roomBefore: nil, room: roomL, panelBefore: nil, panel: roomL) == .unknown
      && VDS.cause(roomBefore: roomL, room: nil, panelBefore: roomL, panel: cs(1117, 618)) == .unknown, "no room from it: not known")
check(VDS.Cause.controls(hidden: true).settle == 0 && VDS.Cause.controls(hidden: nil).settle == 0 && VDS.Cause.device.settle == 0,
      "a tap, another device: at once")
check(VDS.Cause.room(turned: true).settle == 1 && VDS.Cause.room(turned: false).settle == 1 && VDS.Cause.unknown.settle == 1
      && VDS.Cause.shown.settle == 1 && VDS.Follow.settle == 1, "a turn of the hand, not known, shown again: 1 s steady")

// The follow over time: at once for a tap, 1 s steady for a turn, never within 1 s of the make or the last follow's end,
// never during a follow, a space back at the size it has or is going to nothing, the newest size winning.
let turnCause = VDS.Cause.room(turned: true), hideCause = VDS.Cause.controls(hidden: true), showCause = VDS.Cause.controls(hidden: false)
check(VDS.Follow.spacing == 1, "1 s from the make or a follow's end")
var follow = VDS.Follow(made: mini, at: 0)
check(follow.due(now: 0) == .nothing && follow.taken == mini && follow.lastChange == 0 && follow.going == nil, "made: nothing due")
follow.saw(mini, cause: turnCause, at: 0.5)
check(follow.due(now: 0.6) == .nothing, "the space it was made for: nothing")
follow.saw(miniUp, cause: turnCause, at: 4)
check(follow.due(now: 4.5) == .wait(until: 5), "turned at 4: 1 s steady (\(follow.due(now: 4.5)))")
follow.saw(miniUp, cause: hideCause, at: 4.6)
check(follow.due(now: 4.7) == .wait(until: 5) && follow.cause == turnCause, "the same space again: the settle and the cause from its first viewport")
check(follow.due(now: 5) == .follow(miniUp, turnCause), "steady 1 s: followed")
follow.started(miniUp)
check(follow.going == miniUp && follow.due(now: 5.1) == .nothing, "under way: nothing more is due")
follow.saw(mini, cause: showCause, at: 5.2)                // back while the turn is under way
check(follow.pending == mini && follow.due(now: 5.3) == .nothing, "a space back at the size it has, during a follow: pending, not due yet")
follow.took(miniUp, at: 5.6)
check(follow.taken == miniUp && follow.going == nil && follow.lastChange == 5.6 && follow.due(now: 5.7) == .wait(until: 6.6),
      "the follow ended: the one back waits 1 s from its end (\(follow.due(now: 5.7)))")
check(follow.due(now: 6.6) == .follow(mini, showCause), "…then followed back: the device's last word stands")
follow.took(mini, at: 7)
follow.saw(miniUp, cause: hideCause, at: 9)
check(follow.due(now: 9) == .follow(miniUp, hideCause), "a tap 2 s after the last follow: at once")
follow.saw(mini, cause: showCause, at: 9.1)
check(follow.due(now: 9.2) == .nothing && follow.pending == nil, "back to the size taken before it was taken: nothing changes")
var fresh = VDS.Follow(made: mini, at: 100)
fresh.saw(miniUp, cause: hideCause, at: 100.2)
check(fresh.due(now: 100.3) == .wait(until: 101) && fresh.due(now: 101) == .follow(miniUp, hideCause), "a tap within 1 s of the make: 1 s from it")
var newest = VDS.Follow(made: mini, at: 0)
newest.saw(miniUp, cause: turnCause, at: 10)
newest.saw(size(1000, 800), cause: turnCause, at: 10.5)
check(newest.due(now: 11) == .wait(until: 11.5) && newest.due(now: 11.5) == .follow(size(1000, 800), turnCause), "the newest size wins, after its own settle")
var closeBy = VDS.Follow(made: size(1446, 800), at: 0)     // made with the controls showing; Full Screen on, then a turn while it is followed
closeBy.saw(size(1218, 800), cause: hideCause, at: 10)
check(closeBy.due(now: 10) == .follow(size(1218, 800), hideCause), "Full Screen on: at once")
closeBy.started(size(1218, 800))
closeBy.saw(miniUp, cause: turnCause, at: 10.2)
closeBy.took(size(1218, 800), at: 10.5)
check(closeBy.pending == miniUp && closeBy.due(now: 11) == .wait(until: 11.5) && closeBy.due(now: 11.5) == .follow(miniUp, turnCause),
      "two changes close together: the turn after the first follow's end, 1 s steady and 1 s after it")
var takeover = VDS.Follow(made: mini, at: 0)
takeover.saw(size(1494, 800), cause: .device, at: 5)
check(takeover.due(now: 5) == .follow(size(1494, 800), .device), "another device: at once")
var shownAgain = VDS.Follow(made: mini, at: 0)
shownAgain.saw(miniUp, cause: .shown, at: 5)
check(shownAgain.due(now: 5.5) == .wait(until: 6) && shownAgain.due(now: 6) == .follow(miniUp, .shown), "shown again: 1 s steady")

// InPlace against the display the probes measured (TestDisplay: P2b, P2c, P3, P4), driven as the coordinator drives it.
typealias IP = VDS.InPlace
struct Drive { var actions: [IP.Action] = []; var end: IP.Action = .wait; var display: VDS.TestDisplay; var machine: IP; var t: Double }
func drive(from: VDS.Size, to: VDS.Size, made: VDS.Size? = nil, at start: VDS.Size? = nil, backing: VDS.Backing = bk(3072, 3072),
           knobs: VDS.TestKnobs = VDS.TestKnobs(), poll: Double = 0.02, blank: Double = 0) -> Drive {
    var d = VDS.TestDisplay(made: made ?? from, backing: backing)
    if let start, start != d.now {        // the display somewhere else first (made lying down, turned since: P2c's way)
        _ = d.apply(start, at: -10)
        var t = -10.0, asked = false
        while d.read(at: t) != start, t < -5 {
            t += 0.02
            if !asked, d.lists(start, at: t) { _ = d.switchTo(start, at: t); asked = true }
        }
    }
    d.knobs = knobs                       // its steps fail from here on, as the test asks
    var m = IP(from: from, to: to, at: 0)
    var r = Drive(display: d, machine: m, t: 0)
    var action = m.first
    var t = 0.0
    var steps = 0
    func reading(_ t: Double) -> VDS.Size? { (blank > 0 && Double.random(in: 0..<1, using: &rng) < blank) ? nil : d.read(at: t) }
    while steps < 2_000 {
        steps += 1
        r.actions.append(action)
        switch action {
        case .apply(let s):
            let answered = d.apply(s, at: t)
            action = m.applied(answered, reading: reading(t), at: t)
        case .switchTo(let s):
            let code = d.switchTo(s, at: t)
            action = m.switched(code, reading: reading(t), at: t)
        case .wait:
            t += poll
            let now = reading(t)
            action = m.saw(now, listed: now == m.goalAtOneX && d.lists(m.goal, at: t), at: t)
        case .done, .fellBack, .remove:
            r.end = action; r.display = d; r.machine = m; r.t = t
            return r
        }
    }
    r.end = .wait; r.display = d; r.machine = m; r.t = t
    return r
}
func applies(_ r: Drive) -> [VDS.Size] { r.actions.compactMap { if case .apply(let s) = $0 { return s } else { return nil } } }
func switches(_ r: Drive) -> [VDS.Size] { r.actions.compactMap { if case .switchTo(let s) = $0 { return s } else { return nil } } }

let iphone = size(1496, 800)
let same = drive(from: iphone, to: mini)
check(applies(same) == [mini] && switches(same).isEmpty, "the same orientation, smaller (P2b step e): applySettings: alone, no switch: \(same.actions.filter { $0 != .wait })")
if case .done(let ms) = same.end { check(ms >= 320 && ms <= 360, "…done when it lands, about 320 ms: \(ms)") } else { check(false, "…done: \(same.end)") }
check(same.display.now == mini, "…the display at it, at 2x")
let bigger = drive(from: mini, to: iphone)
check(applies(bigger) == [iphone] && switches(bigger).isEmpty && bigger.display.now == iphone, "larger inside the backing, the same orientation: one step")
let turn = drive(from: mini, to: miniUp)
check(applies(turn) == [miniUp] && switches(turn) == [miniUp], "a turn (P2c): applySettings: with the turn alone, then the switch: \(turn.actions.filter { $0 != .wait })")
if case .done(let ms) = turn.end { check(ms >= 640 && ms <= 700, "…done in about 650 ms, the two landings: \(ms)") } else { check(false, "…done: \(turn.end)") }
check(turn.display.now == miniUp && turn.display.now?.scale == 2, "…the display at the turn, at 2x")
// The detail line, at P2c's own times (iPad mini, case 1).
var tr = IP(from: mini, to: miniUp, at: 0)
_ = tr.applied(true, reading: mini, at: 0.285)
_ = tr.saw(size(1600, 2436).withScale(1), listed: true, at: 0.318)
_ = tr.switched(0, reading: size(1600, 2436).withScale(1), at: 0.639)
check(tr.saw(miniUp, listed: true, at: 0.650) == .done(ms: 650), "P2c's turn: done at 650 ms")
check(tr.traceLine(said: false) == "Virtual Desktop: in place: applySettings: with 800×1218 alone answered YES at +285 ms; at 1600×2436 @1× at +318 ms; "
      + "800×1218 @2× listed usable at +318 ms; switch to 800×1218 @2×: complete 0 at +639 ms; at 800×1218 @2× at +650 ms.",
      "the turn's detail line: \(tr.traceLine(said: false))")
check(tr.traceLine(said: true).hasPrefix("Virtual Desktop: in place (TEST ONLY: said, the display as the probes measured it): "),
      "a test host's says TEST ONLY")
let back = drive(from: miniUp, to: mini, made: mini, at: miniUp)
check(back.display.made == mini && applies(back) == [mini] && switches(back).isEmpty && back.display.now == mini,
      "back to the made orientation from the turn (P2c's way back): one step, at 2x")
let upUp = drive(from: miniUp, to: size(800, 1496), made: mini, at: miniUp)
check(switches(upUp) == [size(800, 1496)] && upUp.display.now == size(800, 1496), "upright to another upright size: 1x first, then the switch")
let madeUp = drive(from: miniUp, to: mini, made: miniUp)
check(switches(madeUp).isEmpty && applies(madeUp) == [mini] && madeUp.display.now == mini,
      "a display made upright turned to lie down: one step at 2x (P3 and P4: 589×1189 made, then 1101×589 at once)")
let refused = drive(from: mini, to: miniUp, knobs: VDS.TestKnobs(switchRefused: true))
check(refused.end == .fellBack(.switchRefused(1001), ms: refused.machine.ms(refused.t)) && applies(refused) == [miniUp, mini] && refused.display.now == mini,
      "the switch refused: back to the room by applySettings: alone, at 2x, the next make: \(refused.end), \(String(describing: refused.display.now))")
let stuck = drive(from: mini, to: miniUp, knobs: VDS.TestKnobs(switchRefused: true, stuck: true))
check(stuck.end == .remove(.switchRefused(1001)) && stuck.display.now == size(1600, 2436).withScale(1),
      "…and the way back never lands: removed, never left at 1x: \(stuck.end), \(String(describing: stuck.display.now))")
let late = drive(from: mini, to: miniUp, knobs: VDS.TestKnobs(late: true))
if case .fellBack(.late, let ms) = late.end {
    check(applies(late) == [miniUp] && ms >= 2000 && ms <= 2100, "nothing lands: back where it is after 2 s, nothing more asked: \(ms)")
} else { check(false, "nothing lands: fell back late: \(late.end)") }
let beyond = drive(from: mini, to: size(1900, 800))
check(beyond.end == .fellBack(.late, ms: beyond.machine.ms(beyond.t)) && beyond.display.now == mini, "a size beyond the backing asked anyway: never taken, falls back")
let blanks = drive(from: mini, to: miniUp, blank: 0.3)
check(blanks.end == .done(ms: blanks.machine.ms(blanks.t)) && blanks.display.now == miniUp, "a display that reads nothing now and then: still done")
// An iPhone 15 Pro's four layouts followed in place on a display made at 589×1189 in a 4096-pixel backing, as P3 and P4
// did on Noah's Mac: on its side with Full Screen in one step (P3: 324 ms); on its side with its controls, 1297×540, in one
// step; upright with its controls, 866×540, its pixels at 1x first and then the switch (P4: 664 ms, from 898×560); and
// back upright with Full Screen in one step. Then a size under the line (P3's 1077×448): its 2x mode never listed, back.
let upPro = size(589, 1189), sidePro = size(1101, 589), sideBar = size(1297, 540), upBar = size(866, 540)
func doneMs(_ r: Drive) -> Int { if case .done(let ms) = r.end { return ms } else { return -1 } }
let proSide = drive(from: upPro, to: sidePro, made: upPro, backing: bk(4096, 4096))
check(switches(proSide).isEmpty && applies(proSide) == [sidePro] && proSide.display.now == sidePro && (320...360).contains(doneMs(proSide)),
      "iPhone on its side with Full Screen: one step at 2x, about 320 ms (\(doneMs(proSide)))")
let proBar = drive(from: sidePro, to: sideBar, made: upPro, at: sidePro, backing: bk(4096, 4096))
check(switches(proBar).isEmpty && proBar.display.now == sideBar && doneMs(proBar) > 0, "…its controls on its side: 1297×540 in one step (\(proBar.end))")
let proPane = drive(from: sideBar, to: upBar, made: upPro, at: sideBar, backing: bk(4096, 4096))
check(applies(proPane) == [upBar] && switches(proPane) == [upBar] && proPane.display.now == upBar && (640...700).contains(doneMs(proPane)),
      "…upright with its controls: 866×540 at 1732×1080 @1× first, then the switch, about 650 ms (\(proPane.actions.filter { $0 != .wait }), \(doneMs(proPane)))")
let proPaneP4 = drive(from: size(898, 560), to: upBar, made: upPro, at: size(898, 560), backing: bk(4096, 4096))
let p4Steps = drive(from: upPro, to: size(800, 540), made: upPro, backing: bk(4096, 4096))
check(switches(proPaneP4) == [upBar] && switches(p4Steps) == [size(800, 540)] && p4Steps.display.now == size(800, 540),
      "…as P4 did it from 898×560, and 800×540 the same way (P4: 639 ms)")
check(VDS.TestDisplay.oneXFirst(upBar, made: sideBar) && !VDS.TestDisplay.oneXFirst(size(898, 560), made: upPro)
      && !VDS.TestDisplay.oneXFirst(sideBar, made: upPro) && !VDS.TestDisplay.oneXFirst(size(800, 800), made: upPro),
      "…whatever the display was made at; 898×560, 1297×540 and 800×800 at 2x at once (P4)")
let proBack = drive(from: upBar, to: upPro, made: upPro, at: upBar, backing: bk(4096, 4096))
check(switches(proBack).isEmpty && proBack.display.now == upPro && doneMs(proBack) > 0, "…back upright with Full Screen: one step (P3)")
let notKept = drive(from: upPro, to: size(1077, 448), made: upPro, backing: bk(4096, 4096))
if case .fellBack(.notListed, let ms) = notKept.end {
    check(applies(notKept) == [size(1077, 448), upPro] && switches(notKept).isEmpty && notKept.display.now == upPro && (1640...1720).contains(ms),
          "a size under the line (P3's 1077×448): at 2154×896 @1×, its 2x never listed, back at 589×1189 @2× in about 1.7 s (\(ms))")
} else { check(false, "a size under the line: fell back, not listed: \(notKept.end)") }
let notKeptShort = drive(from: size(800, 1614), to: sidePro, made: size(800, 1614), backing: bk(4096, 4096), knobs: VDS.TestKnobs(shortOneX: true))
check(notKeptShort.end == .fellBack(.notListed, ms: notKeptShort.machine.ms(notKeptShort.t)) && notKeptShort.display.now == size(800, 1614),
      "short-1x: an iPhone's size in place falls back the same way (\(notKeptShort.end))")

// By hand: each step refused or late on the way, and the way back that needs the switch too.
var h = IP(from: mini, to: miniUp, at: 0)
check(h.first == .apply(miniUp) && h.goal == miniUp && h.before == mini, "the first step: the size asked, alone")
check(h.applied(false, reading: mini, at: 0.3) == .fellBack(.refused, ms: 300) && h.phase == .ended, "applySettings: NO, the display where it was: fell back, nothing more")
h = IP(from: mini, to: miniUp, at: 0)
check(h.applied(true, reading: mini, at: 0.3) == .wait && h.phase == .land && abs(h.deadline - 2.3) < 1e-9, "YES: it waits for the display, 2 s")
check(h.saw(nil, listed: false, at: 0.5) == .wait && h.saw(mini, listed: false, at: 2.29) == .wait, "nothing read, or unchanged: it waits")
check(h.saw(size(1000, 700), listed: false, at: 0.6) == .apply(mini) && h.goal == mini && h.before == size(1000, 700) && h.failure == .elsewhere(size(1000, 700)),
      "elsewhere: back to where it was")
check(h.applied(true, reading: size(1000, 700), at: 0.9) == .wait && h.saw(mini, listed: false, at: 1.2) == .fellBack(.elsewhere(size(1000, 700)), ms: 1200),
      "…landed back at 2x: fell back, saying why")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
check(h.saw(mini, listed: false, at: 2.31) == .fellBack(.late, ms: 2310) && h.failure == .late, "late, where it was: fell back, nothing asked")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
check(h.saw(size(1600, 2436).withScale(1), listed: false, at: 0.35) == .wait && h.phase == .listing && abs(h.deadline - 1.35) < 1e-9,
      "its 1x: wait for the listing, 1 s")
check(h.saw(size(1600, 2436).withScale(1), listed: false, at: 1.34) == .wait, "…not listed yet: waits")
check(h.saw(size(1600, 2436).withScale(1), listed: false, at: 1.36) == .apply(mini) && h.failure == .notListed, "…never listed: back")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
_ = h.saw(size(1600, 2436).withScale(1), listed: false, at: 0.35)
check(h.saw(size(1600, 2436).withScale(1), listed: true, at: 0.5) == .switchTo(miniUp), "…listed a little later: the switch then")
check(h.saw(miniUp, listed: true, at: 0.6) == .wait, "…and nothing more until the switch answers")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
_ = h.saw(size(1600, 2436).withScale(1), listed: false, at: 0.35)
check(h.saw(miniUp, listed: false, at: 0.5) == .done(ms: 500), "…2x taken by macOS itself while it waits for the listing: done")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
_ = h.saw(size(1600, 2436).withScale(1), listed: false, at: 0.35)
check(h.saw(size(1000, 700), listed: false, at: 0.5) == .apply(mini) && h.failure == .elsewhere(size(1000, 700)), "…elsewhere while it waits: back")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
check(h.saw(size(1600, 2436).withScale(1), listed: true, at: 0.35) == .switchTo(miniUp) && h.phase == .switchAsked, "listed as it lands: the switch")
check(h.saw(miniUp, listed: true, at: 0.4) == .wait, "nothing read while the switch is asked")
check(h.switched(nil, reading: size(1600, 2436).withScale(1), at: 0.4) == .apply(mini) && h.failure == .notListed, "the mode not found: back")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
_ = h.saw(size(1600, 2436).withScale(1), listed: true, at: 0.35)
check(h.switched(0, reading: size(1600, 2436).withScale(1), at: 0.7) == .wait && h.phase == .switching && abs(h.deadline - 2.2) < 1e-9,
      "complete 0: waits 1.5 s for 2x")
check(h.saw(size(1600, 2436).withScale(1), listed: true, at: 2.19) == .wait, "…not yet")
check(h.saw(size(1600, 2436).withScale(1), listed: true, at: 2.21) == .apply(mini) && h.failure == .switchLate, "…never 2x: back")
check(h.applied(true, reading: size(1600, 2436).withScale(1), at: 2.5) == .wait && h.saw(mini, listed: false, at: 2.8) == .fellBack(.switchLate, ms: 2800),
      "…back at the room: fell back")
h = IP(from: mini, to: miniUp, at: 0)
_ = h.applied(true, reading: mini, at: 0.3)
_ = h.saw(size(1600, 2436).withScale(1), listed: true, at: 0.35)
check(h.switched(1001, reading: size(1600, 2436).withScale(1), at: 0.7) == .apply(mini) && h.failure == .switchRefused(1001), "refused: back")
check(h.applied(false, reading: size(1600, 2436).withScale(1), at: 1.0) == .remove(.switchRefused(1001)), "the way back refused too: removed, saying the first why")
// The way back to an upright size needs the switch as well: from 800×1218 (made lying down), a follow that went elsewhere.
h = IP(from: miniUp, to: mini, at: 0)
_ = h.applied(true, reading: miniUp, at: 0.3)
check(h.saw(size(1000, 700), listed: false, at: 0.6) == .apply(miniUp), "an upright display's follow gone elsewhere: back to upright")
_ = h.applied(true, reading: size(1000, 700), at: 0.9)
check(h.saw(size(1600, 2436).withScale(1), listed: true, at: 1.2) == .switchTo(miniUp), "…its 1x, then its switch")
check(h.switched(0, reading: size(1600, 2436).withScale(1), at: 1.5) == .wait && h.saw(miniUp, listed: true, at: 1.6) == .fellBack(.elsewhere(size(1000, 700)), ms: 1600),
      "…back upright at 2x: fell back")
h = IP(from: miniUp, to: mini, at: 0)
_ = h.applied(true, reading: miniUp, at: 0.3)
_ = h.saw(size(1000, 700), listed: false, at: 0.6)
_ = h.applied(true, reading: size(1000, 700), at: 0.9)
check(h.saw(size(1000, 700), listed: false, at: 2.9) == .remove(.elsewhere(size(1000, 700))), "the way back late: removed")
check(h.saw(mini, listed: false, at: 3) == .wait && h.applied(true, reading: mini, at: 3) == .wait, "ended: nothing more")

// 2,000 random follows against the display as measured, its steps refused, late or stuck now and then: it ends in
// bounded time, done only at `to` at 2x, fallen back only at `from` at 2x, never at 1x unless removed, each switch to a
// size macOS listed as it read that size's 1x, each size asked at most once.
let shapes = [mini, miniUp, iphone, iphone.turned, size(1376, 1032), size(1032, 1376), size(1137, 800), size(1900, 800), size(800, 1900)]
for run in 0..<2_000 {
    let made = [mini, miniUp, iphone][run % 3]
    let from = Bool.random(using: &rng) ? made : made.turned
    var to = shapes.randomElement(using: &rng)!
    if to == from { to = from.turned == from ? mini : from.turned }
    let knobs = VDS.TestKnobs(switchRefused: Int.random(in: 0..<5, using: &rng) == 0, stuck: Int.random(in: 0..<3, using: &rng) == 0,
                              late: Int.random(in: 0..<8, using: &rng) == 0)
    let r = drive(from: from, to: to, made: made, at: from, knobs: knobs, poll: Double.random(in: 0.005...0.06, using: &rng),
                  blank: run % 4 == 0 ? 0.2 : 0)
    var bad: String?
    let atOneX = r.display.now?.scale == 1
    switch r.end {
    case .done:
        if r.display.now != to { bad = "done at \(String(describing: r.display.now))" }
    case .fellBack:
        if r.display.now != from { bad = "fell back at \(String(describing: r.display.now))" }
    case .remove:
        if r.display.now == from || r.display.now == to { bad = "removed at \(String(describing: r.display.now))" }
    default:
        bad = "never ended: \(r.end)"
    }
    if bad == nil, atOneX { if case .remove = r.end {} else { bad = "left at 1x: \(String(describing: r.display.now)), \(r.end)" } }
    if bad == nil, r.t > 2 * (IP.landWait + IP.listWait + IP.switchWait) + 0.5 { bad = "took \(r.t) s" }
    let asked = applies(r)
    if bad == nil, asked.filter({ $0 == to }).count > 1 || asked.filter({ $0 == from }).count > 1 || asked.first != to { bad = "asked \(asked)" }
    if bad == nil, switches(r).contains(where: { $0 != to && $0 != from }) { bad = "switched to \(switches(r))" }
    let fitsTo = VDS.fits(to, bk(3072, 3072))
    if bad == nil, !knobs.late, !knobs.switchRefused, fitsTo, r.end != .done(ms: r.machine.ms(r.t)) { bad = "a clean follow inside the backing not done: \(r.end)" }
    if bad == nil, knobs.late, r.end != .fellBack(.late, ms: r.machine.ms(r.t)) { bad = "nothing lands, not fallen back late: \(r.end)" }
    if bad == nil, !fitsTo, case .done = r.end { bad = "beyond the backing, done" }
    check(bad == nil, "random follow \(run) \(from)→\(to) on \(made) \(knobs): \(bad ?? "") \(r.actions.filter { $0 != .wait })")
}

// The lines (the plan's words, Noah's "… turned; followed in place in N ms").
func line(_ why: VDS.Cause, _ step: VDS.FollowStep, _ outcome: IP.Action? = nil, device: String = "iPad mini", to: VDS.Size = miniUp) -> String? {
    VDS.followLine(device: device, why: why, from: mini, to: to, step: step, outcome: outcome, hz: 60, backing: bk(4096, 4096))
}
check(line(turnCause, .inPlace, .done(ms: 650)) == "Virtual Desktop: iPad mini turned; followed in place in 650 ms: 800×1218 pt @2× at 60 Hz.",
      "in place: \(line(turnCause, .inPlace, .done(ms: 650)) ?? "nil")")
check(line(hideCause, .inPlace, .done(ms: 320), to: size(1218, 800)) == "Virtual Desktop: iPad mini hid its controls; followed in place in 320 ms: 1218×800 pt @2× at 60 Hz.",
      "Full Screen on: \(line(hideCause, .inPlace, .done(ms: 320), to: size(1218, 800)) ?? "nil")")
check(line(showCause, .inPlace, .done(ms: 330), to: size(1446, 800)) == "Virtual Desktop: iPad mini showed its controls; followed in place in 330 ms: 1446×800 pt @2× at 60 Hz.",
      "Full Screen off: \(line(showCause, .inPlace, .done(ms: 330), to: size(1446, 800)) ?? "nil")")
for why in [VDS.Cause.room(turned: false), .controls(hidden: nil), .unknown] {
    check(line(why, .inPlace, .done(ms: 300), to: size(1000, 800)) == "Virtual Desktop: iPad mini's picture changed size; followed in place in 300 ms: 1000×800 pt @2× at 60 Hz.",
          "\(why): \(line(why, .inPlace, .done(ms: 300), to: size(1000, 800)) ?? "nil")")
}
check(line(.device, .inPlace, .done(ms: 300), device: "iPhone", to: iphone) == "Virtual Desktop: iPhone shows it now; followed in place in 300 ms: 1496×800 pt @2× at 60 Hz.",
      "another device: \(line(.device, .inPlace, .done(ms: 300), device: "iPhone", to: iphone) ?? "nil")")
check(line(.shown, .inPlace, .done(ms: 640)) == "Virtual Desktop: iPad mini shows it again; followed in place in 640 ms: 800×1218 pt @2× at 60 Hz.",
      "shown again: \(line(.shown, .inPlace, .done(ms: 640)) ?? "nil")")
check(line(turnCause, .inPlace, .fellBack(.switchRefused(1001), ms: 980))
      == "Virtual Desktop: iPad mini turned; not followed in place: macOS refused the switch to its 2x mode (complete 1001); back at 1218×800 pt @2× in 980 ms; the next one is made at 800×1218 pt.",
      "fallen back: \(line(turnCause, .inPlace, .fellBack(.switchRefused(1001), ms: 980)) ?? "nil")")
check(line(turnCause, .inPlace, .remove(.switchRefused(1001)))
      == "Virtual Desktop: iPad mini turned; not followed in place: macOS refused the switch to its 2x mode (complete 1001), and it did not come back to 1218×800 pt @2×; removed it: the next one is made at 800×1218 pt.",
      "removed: \(line(turnCause, .inPlace, .remove(.switchRefused(1001))) ?? "nil")")
check(line(.device, .beyondBacking, device: "iPad", to: size(2200, 800))
      == "Virtual Desktop: iPad shows it now; 2200×800 pt @2× is beyond the backing it was made with (4096×4096 px); the next one is made at 2200×800 pt.",
      "beyond: \(line(.device, .beyondBacking, device: "iPad", to: size(2200, 800)) ?? "nil")")
check(line(turnCause, .nextMake) == "Virtual Desktop: iPad mini turned; the next one is made at 800×1218 pt.", "the next make, as before")
check(line(.room(turned: false), .remake, device: "iPad", to: size(1000, 800)) == "Virtual Desktop: iPad's picture changed size; made again at 1000×800 pt.",
      "a space that is no turn, remade")
check(VDS.followLine("Headless display", device: "iPhone", why: turnCause, from: mini, to: miniUp, step: .inPlace, outcome: .done(ms: 700))
      == "Headless display: iPhone turned; followed in place in 700 ms: 800×1218 pt @2×.", "the headless display's, no rate known")
check(line(turnCause, .nothing) == nil && line(turnCause, .later) == nil && line(turnCause, .inPlace) == nil && line(turnCause, .inPlace, .wait) == nil,
      "nothing done, or not yet: no line")
for (f, w) in [(IP.Failure.refused, "applySettings: answered NO"), (.late, "the display did not change in time"),
               (.elsewhere(size(1000, 700)), "the display went to 1000×700 instead"), (.elsewhere(nil), "the display went to no mode instead"),
               (.notListed, "macOS did not list its 2x mode as usable"), (.switchLate, "the switch did not land in time")] {
    check(IP.failureWords(f) == w, "\(f): \(IP.failureWords(f))")
}

// TEST ONLY: SILL_TEST_VD_STEPS, the said display's steps made to fail.
check(VDS.testSteps(environment: [:], on: true) == (VDS.TestKnobs(), nil), "no variable: as measured, no line")
check(VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "switch-refused"], on: true).knobs == VDS.TestKnobs(switchRefused: true), "switch-refused")
check(VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "switch-refused, Stuck,late"], on: true).knobs == VDS.TestKnobs(switchRefused: true, stuck: true, late: true),
      "all three, spaced and in capitals")
check(VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "switch-refused"], on: true).line
      == "Test Virtual Desktop: its said display's steps: switch-refused (SILL_TEST_VD_STEPS), not as the probes measured them.", "its line")
check(VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "switch-refused,sideways"], on: true).knobs == VDS.TestKnobs()
      && VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "sideways"], on: true).line?.contains("ignored: it takes switch-refused, stuck, late and short-1x") == true,
      "an unknown word: ignored whole, said")
check(VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "late"], on: false).knobs == VDS.TestKnobs()
      && VDS.testSteps(environment: ["SILL_TEST_VD_STEPS": "late"], on: false).line?.contains("ignored: it needs a test host's Virtual Desktop") == true,
      "without the test host's Virtual Desktop: ignored, said")

// 2,000 random spaces, each change a tap or a turn, the follows in place taking a random while: a follow only to a size
// the space has kept for its cause's settle (none for a tap, 1 s for a turn), 1 s after the make or the last follow's end,
// never while one is under way, never to the size the display has; always once those have passed; and the display ends
// at the space's last size once the device keeps still.
let rooms = [mini, miniUp, size(1446, 800), size(1089, 800), size(1000, 800), size(1494, 800), size(800, 1614)]
for run in 0..<2_000 {
    var tracker = VDS.Follow(made: mini, at: 0)
    var room = mini, roomSince = 0.0, cause = VDS.Cause.device, last = 0.0, taken = mini, t = 0.0
    var going: (size: VDS.Size, until: Double)?
    var bad: String?
    while t < 40, bad == nil {
        t += Double.random(in: 0.05...0.7, using: &rng)
        if let g = going, t >= g.until { tracker.took(g.size, at: t); taken = g.size; last = t; going = nil }
        if t < 30, Double.random(in: 0..<1, using: &rng) < (run % 3 == 0 ? 0.5 : 0.15) {
            let next = rooms.randomElement(using: &rng)!
            let c: VDS.Cause = Bool.random(using: &rng) ? .controls(hidden: Bool.random(using: &rng)) : .room(turned: Bool.random(using: &rng))
            if next != room { room = next; roomSince = t; cause = c }
        }
        tracker.saw(room, cause: cause, at: t)
        switch tracker.due(now: t) {
        case .follow(let s, let c):
            if going != nil { bad = "followed \(s) at \(t) while one is under way" }
            if s != room || s == taken || t - roomSince < c.settle - 1e-9 || t - last < 1 - 1e-9 || c != cause {
                bad = "followed \(s) (\(c)) at \(t): the space \(room) (\(cause)) since \(roomSince), the last change \(last)"
            }
            tracker.started(s)
            going = (s, t + Double.random(in: 0.3...0.8, using: &rng))
        case .wait(let until):
            if going != nil || room == taken || until <= t { bad = "a wait at \(t) until \(until) for \(room), \(taken) taken" }
            if until > max(roomSince + cause.settle, last + 1) + 1e-9 { bad = "waits past its time at \(t): \(until)" }
        case .nothing:
            if going == nil, room != taken { bad = "nothing at \(t) with \(room) since \(roomSince), \(taken) taken" }
        }
    }
    if bad == nil, going == nil, taken != room { bad = "ended at \(taken), the space \(room)" }
    check(bad == nil, "random spaces \(run): \(bad ?? "")")
}

// MARK: The person's choice of its size and rate (Noah, 2026-11-18: "allow the user to select resolution")

typealias VS = VirtualDesktopSize
check(VS.choice("device") == .device && VS.choice("main") == .main, "This device and Same as main display by their ids")
check(VS.choiceIDs.first == "device" && VS.choiceIDs.dropFirst().first == "main" && VS.choiceIDs.count == VS.offered.count + 2,
      "the pickers' order: This device, Same as main display, then the list")
check(Set(VS.choiceIDs).count == VS.choiceIDs.count, "no id twice")
for s in VS.offered {
    check(VS.choice(VS.id(s)) == .fixed(s), "\(VS.id(s)) chosen by its id")
    check([1, 2].contains(s.scale) && (s.scale == 1 || min(s.widthPt, s.heightPt) >= VS.minSide) && max(s.widthPt, s.heightPt) <= VS.maxSide
          && s.widthPt * s.scale <= 8192 && s.heightPt * s.scale <= 8192, "\(VS.id(s)) within Sill's own bounds")
}
check(VS.offered.contains(VS.Size(widthPt: 1920, heightPt: 1080, scale: 2)) && VS.offered.contains(VS.Size(widthPt: 3440, heightPt: 1440, scale: 1)),
      "4K at Retina and the 34-inch ultrawide at 1x among them")
for bad in ["", "Device", "1920x1080", "1920x1080@3", " main", "8192x8192@2", "300x300@2", "700x700@2", "639x800@1", "8193x800@1",
            "01920x1080@1", "+1920x1080@1", "1920x1080@01", "1920x-1080@1", "1920×1080@1"] {
    check(VS.choice(bad) == nil, "\(bad.debugDescription): neither offered nor a size that can be a display")
}
check(VS.id(VS.Size(widthPt: 1920, heightPt: 1080, scale: 2)) == "1920x1080@2", "an id, as VirtualDesktopState.size writes a size")
check(VS.words("device") == "Match the device" && VS.words("main") == "Same as main display" && VS.words("1920x1080@2") == "1920 × 1080 (Retina)"
      && VS.words("3440x1440@1") == "3440 × 1440" && VS.words("nonsense") == "Match the device", "the choices' words")
check(VS.rateChoices == [0, 30, 60, 120] && VS.rateWords(0) == "Match the device" && VS.rateWords(120) == "120 Hz" && VS.rateWords(75) == "75 Hz"
      && VS.rateWords(23) == "Match the device" && VS.rateWords(121) == "Match the device", "the rates and their words (a typed one too)")
check(VS.rate(choice: 0, viewportFPS: 120, limit: 120) == 120 && VS.rate(choice: 0, viewportFPS: nil, limit: 120) == 60,
      "the rate: the device's by default")
check(VS.rate(choice: 30, viewportFPS: 120, limit: 120) == 30 && VS.rate(choice: 120, viewportFPS: 60, limit: 120) == 120,
      "…a chosen rate, whatever the device's")
check(VS.rate(choice: 120, viewportFPS: 60, limit: 60) == 60, "…held to the Frame Rate limit")
check(VS.rate(choice: 75, viewportFPS: 120, limit: 120) == 75 && VS.rate(choice: 24, viewportFPS: 120, limit: 120) == 24,
      "…one typed, 24 to 120 Hz, as it is")
check(VS.rate(choice: 23, viewportFPS: 120, limit: 120) == 120 && VS.rate(choice: 121, viewportFPS: 60, limit: 120) == 60,
      "…one outside them is the device's")
check(VS.rateAllowed(0) && VS.rateAllowed(24) && VS.rateAllowed(90) && VS.rateAllowed(120) && !VS.rateAllowed(23) && !VS.rateAllowed(121)
      && !VS.rateAllowed(-60), "the rates allowed: the device's, or 24 to 120 Hz")
// The CLI's --virtual-desktop=VALUE.
check(VS.flag("device")! == ("device", 0) && VS.flag("main")! == ("main", 0) && VS.flag("1920x1080@2")! == ("1920x1080@2", 0),
      "the CLI's flag: a size choice alone, the device's rate")
check(VS.flag("device:120")! == ("device", 120) && VS.flag("3440x1440@1:60")! == ("3440x1440@1", 60) && VS.flag("main:30")! == ("main", 30),
      "…with a rate after a colon")
for bad in ["", "Device", "1920x1080", "device:", "device:0", "device:121", "device:23", "device:060", "device:60:60", "8K", ":60", "1920x1080@2:x"] {
    check(VS.flag(bad) == nil, "the CLI's flag refuses \(bad.debugDescription)")
}
check(VS.flag("device:75")! == ("device", 75) && VS.flag("2752x2064@2:120")! == ("2752x2064@2", 120) && VS.flag("7680x2160@1")! == ("7680x2160@1", 0),
      "…a typed rate, and a typed size (part B)")
// Same as main display, the 11-12 plan's §2 table.
let mainRows: [(String, CGSize, Int, VS.Size)] = [
    ("14-inch MacBook Pro", CGSize(width: 1512, height: 982), 2, VS.Size(widthPt: 1512, heightPt: 982, scale: 2)),
    ("16-inch MacBook Pro", CGSize(width: 1728, height: 1117), 2, VS.Size(widthPt: 1670, heightPt: 1080, scale: 2)),
    ("Studio Display (5K)", CGSize(width: 2560, height: 1440), 2, VS.Size(widthPt: 1920, heightPt: 1080, scale: 2)),
    ("Pro Display XDR (6K)", CGSize(width: 3008, height: 1692), 2, VS.Size(widthPt: 1920, heightPt: 1080, scale: 2)),
    ("24-inch iMac (4.5K)", CGSize(width: 2240, height: 1260), 2, VS.Size(widthPt: 1920, heightPt: 1080, scale: 2)),
    ("a 34-inch ultrawide", CGSize(width: 3440, height: 1440), 1, VS.Size(widthPt: 3440, heightPt: 1440, scale: 1)),
    ("a 49-inch ultrawide", CGSize(width: 5120, height: 1440), 1, VS.Size(widthPt: 3840, heightPt: 1080, scale: 1)),
    ("a 1080p monitor", CGSize(width: 1920, height: 1080), 1, VS.Size(widthPt: 1920, heightPt: 1080, scale: 1)),
    ("a 4K monitor upright", CGSize(width: 1080, height: 1920), 2, VS.Size(widthPt: 1080, heightPt: 1920, scale: 2)),
    ("a small Retina mode", CGSize(width: 1024, height: 640), 2, VS.Size(widthPt: 1280, heightPt: 800, scale: 2)),
]
for (name, points, scale, want) in mainRows {
    let got = VS.main(points: points, scale: scale)
    check(got == want, "Same as main display on \(name): \(String(describing: got)), want \(want)")
}
check(VS.main(points: .zero, scale: 2) == nil && VS.main(points: CGSize(width: Double.nan, height: 900), scale: 2) == nil, "no size: none")
for _ in 0..<2_000 {
    let w = Double.random(in: 320...7000, using: &rng).rounded(), h = Double.random(in: 320...7000, using: &rng).rounded()
    let scale = Bool.random(using: &rng) ? 2 : 1
    guard let m = VS.main(points: CGSize(width: w, height: h), scale: scale) else { check(false, "main of \(w)×\(h): none"); continue }
    let wide = w >= h
    var ok = m.scale == scale
    if scale == 2 {
        ok = ok && min(m.widthPt, m.heightPt) >= VS.minSide && max(m.widthPt, m.heightPt) <= VS.maxSide
    } else {
        ok = ok && m.widthPt * 1 <= (wide ? 3840 : 2160) && m.heightPt * 1 <= (wide ? 2160 : 3840)
    }
    // Inside the box at its scale whenever no floor grew it; the shape kept within the rounding.
    let grown = scale == 2 && min(w, h) * min(1, (wide ? 3840 : 2160) / (w * 2), (wide ? 2160 : 3840) / (h * 2)) < Double(VS.minSide)
    if !grown { ok = ok && m.widthPt * m.scale <= (wide ? 3840 : 2160) && m.heightPt * m.scale <= (wide ? 2160 : 3840) }
    // Each side its own share of the box, whole points, rounded down: the shape kept within a point a side.
    let fit = min(1, (wide ? 3840 : 2160) / (w * Double(scale)), (wide ? 2160 : 3840) / (h * Double(scale)))
    if !grown { ok = ok && abs(Double(m.widthPt) - w * fit) < 1.0001 && abs(Double(m.heightPt) - h * fit) < 1.0001 }
    check(ok, "main \(w)×\(h)@\(scale): \(m)")
}

// MARK: Custom sizes and each device's budget (part B, 2026-11-25; Noah, 2026-11-24: "up to 2x native resolution of device
// panel and 120Hz ... any resolution/refresh rate that is less than 2726461440 pixels per second")

typealias VB = VirtualDesktopBudget
// A size typed in pixels, as its id: what can be a display (each side 640 to 8192 pixels; at 2x at least 1600 one way and
// 1080 the other: the least macOS keeps at 2x, 800 × 540 points, P3 and P4's line).
for (id, want) in [("2752x2064@2", VS.Size(widthPt: 2752, heightPt: 2064, scale: 2)), ("7680x2160@1", VS.Size(widthPt: 7680, heightPt: 2160, scale: 1)),
                   ("640x640@1", VS.Size(widthPt: 640, heightPt: 640, scale: 1)), ("8192x640@1", VS.Size(widthPt: 8192, heightPt: 640, scale: 1)),
                   ("4096x4096@2", VS.Size(widthPt: 4096, heightPt: 4096, scale: 2)), ("800x540@2", VS.Size(widthPt: 800, heightPt: 540, scale: 2)),
                   ("540x800@2", VS.Size(widthPt: 540, heightPt: 800, scale: 2)),
                   ("1280x720@2", VS.Size(widthPt: 1280, heightPt: 720, scale: 2)), ("999x999@2", VS.Size(widthPt: 999, heightPt: 999, scale: 2))] {
    check(VS.custom(id) == want && VS.choice(id) == .fixed(want), "\(id): a size typed, \(want)")
}
check(VS.custom("4097x800@2") == nil && VS.custom("799x799@2") == nil && VS.custom("320x319@2") == nil && VS.custom("8192x639@1") == nil
      && VS.custom("800x539@2") == nil && VS.custom("539x800@2") == nil && VS.custom("1600x448@2") == nil && VS.custom("800x320@2") == nil,
      "past 8192 pixels, a Retina desktop under 1600 on both sides or under 1080 on one (P4's 1600×448 points), under 640 pixels: none")
check(VS.words("2752x2064@2") == "Custom: 5504 × 4128 pixels, Retina" && VS.words("7680x2160@1") == "Custom: 7680 × 2160 pixels"
      && VS.words("1920x1080@2") == "1920 × 1080 (Retina)", "a typed size's words: its pixels; the list's as before")
// What an older Sill for Mac does with a saved typed size: its `choice` knew the list alone, so validated took This device.
func olderChoice(_ id: String) -> VS.Choice? {
    if id == "device" { return .device }
    if id == "main" { return .main }
    return VS.offered.first { VS.id($0) == id }.map { .fixed($0) }
}
check(olderChoice("2752x2064@2") == nil && olderChoice("1920x1080@2") != nil && VS.choice("2752x2064@2") != nil,
      "an older Sill for Mac reads a typed size as none of its choices: Match the device, never a crash (HostConfig.validated)")
check(VS.rateAllowed(90) && ![0, 30, 60, 120].contains(90), "…and a typed rate as none of its rates: the device's")

// The budget: twice each way at 120 Hz, for every current iPhone's and iPad's screen (Xcode 27.1's simulator profiles).
let budgets: [(String, Int)] = [
    ("iPhone 15 Pro", 1_446_491_520), ("iPhone 16", 1_446_491_520), ("iPhone 16 Plus", 1_731_283_200), ("iPhone 16e", 1_421_971_200),
    ("iPhone 17e", 1_421_971_200), ("iPhone 17", 1_517_823_360), ("iPhone Air", 1_654_732_800), ("iPhone 17 Pro", 1_517_823_360),
    ("iPhone 17 Pro Max", 1_817_164_800), ("iPhone 18 Pro", 1_517_823_360), ("iPhone 18 Pro Max", 1_817_164_800), ("iPhone SE", 480_240_000),
    ("iPhone Duo, outer screen", 1_364_895_360), ("iPhone Duo, inner screen", 2_748_466_080), ("iPad mini", 1_618_467_840),
    ("iPad", 1_857_792_000), ("iPad Air 11-inch", 1_857_792_000), ("iPad Air 13-inch", 2_685_665_280), ("iPad Pro 11-inch", 1_937_548_800),
    ("iPad Pro 13-inch", 2_726_461_440),
]
check(VB.current.count == budgets.count, "every current iPhone and iPad listed (\(VB.current.count))")
for (name, want) in budgets {
    let d = VB.current.first { $0.name == name }
    check(d.map(VB.budget) == want, "\(name)'s budget: \(want) pixels a second (\(d.map(VB.budget).map(String.init) ?? "missing"))")
}
check(VB.budget(VB.largestIPad) == 2_726_461_440 && VB.budget(pixelWidth: 2064, pixelHeight: 2752) == 5504 * 4128 * 120,
      "an iPad Pro 13-inch: 5504 × 4128 at 120 Hz, 2,726,461,440 pixels a second (Noah's number)")
check(VB.current.allSatisfy { $0.phone == $0.name.hasPrefix("iPhone") } && VB.current.allSatisfy { [60, 120].contains($0.fps) },
      "each an iPhone's or an iPad's, at 60 or 120 Hz")
// The ceiling: the largest budget this Mac knows, else the largest current iPad's (the Duo's inner screen is larger).
let iPhone15 = VB.current.first { $0.name == "iPhone 15 Pro" }!, miniDevice = VB.current.first { $0.name == "iPad mini" }!
let duoIn = VB.current.first { $0.name == "iPhone Duo, inner screen" }!
check(VB.ceiling(known: []) == VB.largestIPad && VB.ceiling(known: [iPhone15, miniDevice]) == miniDevice && VB.ceiling(known: [iPhone15]) == iPhone15
      && VB.ceiling(known: [miniDevice, duoIn, iPhone15]) == duoIn, "the ceiling: the largest budget known, else the largest current iPad's")
// The entry: what may be typed, and its one sentence.
func typed(_ w: Int?, _ h: Int?, _ retina: Bool = false, _ hz: Int? = 0, _ ceiling: VB.Device = VB.largestIPad) -> String {
    switch VB.entry(width: w, height: h, retina: retina, hz: hz, ceiling: ceiling) {
    case .success(let e): return "\(VS.id(e.size)):\(e.hz)"
    case .failure(let r): return VB.sentence(r)
    }
}
check(typed(5504, 4128, true, 120) == "2752x2064@2:120", "Noah's 5504 × 4128 at 120 Hz, Retina: taken (at the ceiling, which it includes)")
check(typed(5504, 4128, false, 120) == "5504x4128@1:120" && typed(4128, 5504, false, 120) == "4128x5504@1:120", "…at 1x, and upright")
check(typed(5504, 4130, false, 120).hasPrefix("That’s more than Sill sends to iPad Pro 13-inch: up to 5504 × 4128 at 120 Hz"),
      "two pixels past the ceiling at 120 Hz: refused, the ceiling named in its device's terms")
check(typed(3840, 2160, true, 120) == "1920x1080@2:120" && typed(7680, 2160, false, 120) == "7680x2160@1:120" && typed(7680, 4320, false, 60) == "7680x4320@1:60",
      "4K at 120, a 32:9 ultrawide at 120, 8K at 60: within (Noah's examples)")
check(typed(7680, 4320, false, 120).hasPrefix("That’s more than Sill sends to iPad Pro 13-inch"), "8K at 120: over")
check(typed(7680, 4320, false, 0).hasPrefix("That’s more"), "the device's rate counts as 120 Hz, the most it may be")
check(typed(3840, 2160, false, 120, iPhone15) == "3840x2160@1:120" && typed(5504, 4128, true, 120, iPhone15).hasPrefix("That’s more than Sill sends to iPhone 15 Pro: up to 5112 × 2358 at 120 Hz"),
      "known an iPhone 15 Pro alone: its budget the ceiling (5112 × 2358 at 120 Hz)")
check(typed(nil, 1080) == "Type a width and a height in pixels." && typed(1920, nil) == "Type a width and a height in pixels.", "a side not typed")
check(typed(639, 1080) == "Each side needs at least 640 pixels." && typed(8193, 1080) == "Each side can be at most 8192 pixels."
      && typed(1080, 639) == "Each side needs at least 640 pixels." && typed(1080, 8193) == "Each side can be at most 8192 pixels.",
      "the floor and the ceiling of each side")
check(typed(1600, 639, true) == "Each side needs at least 640 pixels." && typed(639, 1600, true) == "Each side needs at least 640 pixels."
      && typed(1600, 8193, true) == "Each side can be at most 8192 pixels.", "a side out of bounds said before a Retina side's evenness")
check(typed(1921, 1080, true) == "A Retina desktop needs an even number of pixels each way."
      && typed(1920, 1081, true) == "A Retina desktop needs an even number of pixels each way." && typed(1921, 1081, false) == "1921x1081@1:0",
      "an odd Retina side, either; at 1x any count")
check(typed(1598, 1598, true) == "A Retina desktop needs at least 1600 pixels on one side and 1080 on the other: macOS shows a smaller one at standard resolution."
      && typed(1600, 1078, true) == "A Retina desktop needs at least 1600 pixels on one side and 1080 on the other: macOS shows a smaller one at standard resolution."
      && typed(3200, 896, true) == "A Retina desktop needs at least 1600 pixels on one side and 1080 on the other: macOS shows a smaller one at standard resolution."
      && typed(1600, 1080, true) == "800x540@2:0" && typed(1080, 1600, true) == "540x800@2:0" && typed(1600, 640, false) == "1600x640@1:0",
      "a Retina desktop under 1600 pixels on both sides, or under 1080 on one (P4's 1600×448 points): refused; 1600 × 1080 either way: taken; at 1x any")
check(typed(1920, 1080, false, 23) == "The refresh rate can be 24 to 120 Hz." && typed(1920, 1080, false, 121) == "The refresh rate can be 24 to 120 Hz."
      && typed(1920, 1080, false, nil) == "The refresh rate can be 24 to 120 Hz." && typed(1920, 1080, false, 24) == "1920x1080@1:24",
      "a rate out of 24 to 120 Hz, or not a number")
check(typed(1920, 1080, false, 90) == "1920x1080@1:90", "90 Hz, which no picker offers: taken")
// The list's sizes: each one a person could type too, at 120 Hz within the largest current iPad's ceiling (so an iPad Pro
// 13-inch takes every one of them as it is), and the nine of the plan.
for s in VS.offered {
    check(typed(s.widthPt * s.scale, s.heightPt * s.scale, s.scale == 2, 120) == "\(VS.id(s)):120", "\(VS.id(s)) of the list: within the ceiling at 120 Hz")
}
check(VS.offered.map(VS.id) == ["1440x900@2", "1512x982@2", "1728x1117@2", "1920x1080@2", "1920x1200@2", "2560x1440@2", "1920x1080@1", "2560x1440@1", "3440x1440@1"],
      "the list: the nine sizes of the plan, in its order")
// Every typed size the entry takes is a size VirtualDesktopSize takes as saved, and the other way round within the ceiling.
var entryWrong = 0
for _ in 0..<20_000 {
    let w = Int.random(in: 500...8400, using: &rng), h = Int.random(in: 500...8400, using: &rng), r = Bool.random(using: &rng)
    let hz = [0, 24, 30, 60, 90, 120, 23, 121][Int.random(in: 0...7, using: &rng)]
    let result = VB.entry(width: w, height: h, retina: r, hz: hz, ceiling: VB.largestIPad)
    let displayable = (640...8192).contains(w) && (640...8192).contains(h) && (!r || (w % 2 == 0 && h % 2 == 0 && max(w, h) >= 1600 && min(w, h) >= 1080))
    let rateOK = hz == 0 || (24...120).contains(hz)
    let within = w * h * (hz == 0 ? 120 : hz) <= 2_726_461_440
    switch result {
    case .success(let e):
        if !(displayable && rateOK && within) || VS.custom(VS.id(e.size)) != e.size || e.size.widthPt * e.size.scale != w || e.hz != hz { entryWrong += 1 }
    case .failure:
        if displayable && rateOK && within { entryWrong += 1 }
    }
}
check(entryWrong == 0, "20,000 random entries: taken exactly when they can be a display at a rate of 24 to 120 Hz within the ceiling, as saved (\(entryWrong) not)")
check(VB.fields("2752x2064@2").map { [$0.width, $0.height, $0.retina ? 1 : 0] } == [5504, 4128, 1] && VB.fields("device") == nil
      && VB.fields("1920x1080@1").map { [$0.width, $0.height, $0.retina ? 1 : 0] } == [1920, 1080, 0], "the entry's fields from a size in use")
check(VB.upTo(VB.largestIPad, known: []) == "No device has connected yet: up to 5504 × 4128 at 120 Hz, the largest current iPad’s, or as many pixels a second at a lower rate."
      && VB.upTo(iPhone15, known: [iPhone15]) == "Up to 5112 × 2358 at 120 Hz for iPhone 15 Pro, or as many pixels a second at a lower rate.", "what may be typed, said")
// A device as Settings names it: a device of Sill's calls itself "iPad (iPad16,6)" (its kind and model identifier), which
// is "your iPad", whole while another of its kind is known.
let ownPro = VB.Device(name: "iPad (iPad16,6)", pixelWidth: 2064, pixelHeight: 2752, phone: false, fps: 120)
let ownMini = VB.Device(name: "iPad (iPad14,1)", pixelWidth: 1488, pixelHeight: 2266, phone: false, fps: 60)
let ownPhone = VB.Device(name: "iPhone (iPhone16,1)", pixelWidth: 1179, pixelHeight: 2556, phone: true, fps: 120)
check(VB.shownName(ownPro, among: [ownPro, ownPhone]) == "your iPad" && VB.shownName(ownPhone, among: [ownPro, ownPhone], start: true) == "Your iPhone"
      && VB.shownName(ownPro, among: []) == "your iPad", "a device of Sill's: \"your iPad\", \"Your iPhone\" at a line's start")
check(VB.shownName(ownPro, among: [ownPro, ownMini, ownPhone]) == "your iPad (iPad16,6)" && VB.shownName(ownMini, among: [ownPro, ownMini], start: true) == "Your iPad (iPad14,1)"
      && VB.shownName(ownPhone, among: [ownPro, ownMini, ownPhone]) == "your iPhone", "two iPads known: each whole, so they read apart; the iPhone alone of its kind")
check(VB.shownName(VB.largestIPad, among: [ownPro]) == "iPad Pro 13-inch" && VB.shownName(VB.largestIPad, among: [], start: true) == "iPad Pro 13-inch"
      && VB.shownName(VB.Device(name: "(iPad16,6)", pixelWidth: 1, pixelHeight: 1, phone: false, fps: 60), among: []) == "(iPad16,6)"
      && VB.shownName(VB.Device(name: " (iPad16,6)", pixelWidth: 1, pixelHeight: 1, phone: false, fps: 60), among: []) == " (iPad16,6)"
      && VB.shownName(VB.Device(name: "iPad (mine", pixelWidth: 1, pixelHeight: 1, phone: false, fps: 60), among: []) == "iPad (mine",
      "a name with no identifier as it is: the table's, one with nothing before it, one never closed")
check(VB.upTo(ownPro, known: [ownPro, ownPhone]) == "Up to 5504 × 4128 at 120 Hz for your iPad, or as many pixels a second at a lower rate."
      && VB.sentence(.ceiling(ownPro), known: [ownPro, ownMini]) == "That’s more than Sill sends to your iPad (iPad16,6): up to 5504 × 4128 at 120 Hz, or as many pixels a second at a lower rate."
      && VB.sentence(.ceiling(ownPro)) == "That’s more than Sill sends to your iPad: up to 5504 × 4128 at 120 Hz, or as many pixels a second at a lower rate.",
      "what may be typed and the ceiling's sentence, of a device this Mac knows")
// The CLI: no device known, so the largest current iPad's ceiling.
check(VB.flagRefusal("2752x2064@2:120") == nil && VB.flagRefusal("device") == nil && VB.flagRefusal("1920x1080@2:60") == nil, "the CLI takes them")
check(VB.flagRefusal("3840x2160@2:120")?.hasPrefix("That’s more than Sill sends to iPad Pro 13-inch") == true, "…refuses 7680 × 4320 at 120 Hz with the ceiling's sentence")
check(VB.flagRefusal("8K")?.hasPrefix("--virtual-desktop=… takes device, main, a size of Sill for Mac's list (") == true
      && VB.flagRefusal("device:150")?.hasPrefix("--virtual-desktop=… takes") == true, "…and says its forms for anything else")
check(VB.flagRefusal("1920x1080@2:150") == "The refresh rate can be 24 to 120 Hz."
      && VB.flagRefusal("700x700@2") == "A Retina desktop needs at least 1600 pixels on one side and 1080 on the other: macOS shows a smaller one at standard resolution."
      && VB.flagRefusal("1600x448@2") == "A Retina desktop needs at least 1600 pixels on one side and 1080 on the other: macOS shows a smaller one at standard resolution."
      && VB.flagRefusal("9000x800@1") == "Each side can be at most 8192 pixels.", "…and a size of its own written right that cannot be, its own sentence")
// What a device gets: its own rate, the picture as it is within its budget, else scaled down evenly to it.
check(VB.view(width: 5504, height: 4128, hz: 120, device: VB.largestIPad) == VB.View(width: 5504, height: 4128, hz: 120, scaled: false),
      "an iPad Pro 13-inch: 5504 × 4128 at 120 Hz as it is")
let phoneView = VB.view(width: 5504, height: 4128, hz: 120, device: iPhone15)
check(phoneView.scaled && phoneView.hz == 120 && phoneView.width * phoneView.height * 120 <= 1_446_491_520 && phoneView.width % 2 == 0
      && phoneView.height % 2 == 0 && abs(Double(phoneView.width) / Double(phoneView.height) - 5504.0 / 4128) < 0.002 && phoneView.width >= 3990,
      "an iPhone 15 Pro: scaled down evenly to its budget at 120 Hz (\(phoneView))")
check(VB.view(width: 5504, height: 4128, hz: 120, device: miniDevice) == VB.View(width: 5504, height: 4128, hz: 60, scaled: false),
      "an iPad mini: at its own 60 Hz, the same picture is within its budget")
check(VB.deviceLine(width: 5504, height: 4128, hz: 120, device: VB.largestIPad) == "iPad Pro 13-inch shows it at full size, 120 Hz."
      && VB.deviceLine(width: 5504, height: 4128, hz: 120, device: iPhone15) == "iPhone 15 Pro shows it scaled down to \(phoneView.width) × \(phoneView.height), 120 Hz."
      && VB.deviceLine(width: 1920, height: 1080, hz: 0, device: miniDevice) == "iPad mini shows it at full size, 60 Hz.", "Settings' lines beside it")
check(VB.deviceLine(width: 5504, height: 4128, hz: 120, device: ownPro, among: [ownPro, ownPhone]) == "Your iPad shows it at full size, 120 Hz."
      && VB.deviceLine(width: 5504, height: 4128, hz: 120, device: ownPhone, among: [ownPro, ownPhone]) == "Your iPhone shows it scaled down to \(phoneView.width) × \(phoneView.height), 120 Hz."
      && VB.deviceLine(width: 1920, height: 1080, hz: 0, device: ownMini, among: [ownPro, ownMini]) == "Your iPad (iPad14,1) shows it at full size, 60 Hz.",
      "…named as a device of Sill's names itself")
var fitWrong = 0
for _ in 0..<20_000 {
    let w = Int.random(in: 640...8192, using: &rng), h = Int.random(in: 640...8192, using: &rng), fps = [24, 30, 60, 90, 120][Int.random(in: 0...4, using: &rng)]
    let budget = VB.budget(VB.current[Int.random(in: 0..<VB.current.count, using: &rng)])
    guard let f = VB.fitted(width: w, height: h, fps: fps, budget: budget) else {
        if w * h * fps > budget { fitWrong += 1 }
        continue
    }
    let shape = abs(Double(f.width) / Double(f.height) / (Double(w) / Double(h)) - 1)
    if w * h * fps <= budget || f.width * f.height * fps > budget || f.width % 2 != 0 || f.height % 2 != 0 || f.width > w || f.height > h
        || shape > 2.0 / Double(f.width) + 2.0 / Double(f.height) + 1e-6 || (f.width + 4) * (f.height + 4) * fps <= budget { fitWrong += 1 }
}
check(fitWrong == 0, "20,000 random sizes and budgets: scaled only past the budget, then within it, even, the shape kept, the largest such (\(fitWrong) not)")
// What this Mac's encoder carries, beside a chosen size (Noah's agreed point 2), from what Sill measured at run time.
check(VB.encoderNote(width: 5504, height: 4128, hz: 120, encoder: VB.Encoder()) == nil, "nothing known: no note")
check(VB.encoderNote(width: 3840, height: 2160, hz: 60, encoder: VB.Encoder(fps: 90)) == nil, "it carries it: no note")
check(VB.encoderNote(width: 3840, height: 2160, hz: 120, encoder: VB.Encoder(fps: 61.7)) == "This Mac streams this at about 61 frames a second.",
      "slower than asked: about how fast")
check(VB.encoderNote(width: 5120, height: 2880, hz: 60, encoder: VB.Encoder(widest: 4096)) == "This Mac’s video encoder takes at most 4096 pixels a side: Sill streams this scaled down to 4096 × 2304.",
      "wider than its hardware takes: scaled down (#295's 5K)")
check(VB.encoderNote(width: 7680, height: 4320, hz: 60, encoder: VB.Encoder(widest: 4096, fps: 38))
      == "This Mac’s video encoder takes at most 4096 pixels a side: Sill streams this scaled down to 4096 × 2304, at about 38 frames a second.", "both")
check(VB.encoderNote(width: 4000, height: 2000, hz: 60, encoder: VB.Encoder(widest: 4096)) == nil, "within its widest: no note")
check(VB.encoderNote(width: 2880, height: 5120, hz: 60, encoder: VB.Encoder(widest: 4096)) == "This Mac’s video encoder takes at most 4096 pixels a side: Sill streams this scaled down to 2304 × 4096.",
      "upright too: its longer side held")
check(VB.encoderNote(width: 1920, height: 1080, hz: 60, encoder: VB.Encoder(software: true))?.hasPrefix("This Mac streams on its software encoder") == true,
      "on the software encoder: that")
check(VB.encoderNote(width: 1920, height: 1080, hz: 60, encoder: VB.Encoder(fps: 58.5)) == nil, "within two frames of the rate: no note")
// TEST ONLY: SILL_TEST_ENCODER, a test host's encoder said.
check(VB.testEncoder(environment: [:], testHost: true) == (nil, nil), "no variable: none")
check(VB.testEncoder(environment: ["SILL_TEST_ENCODER": "widest=4096,fps=31"], testHost: true).encoder == VB.Encoder(widest: 4096, fps: 31),
      "widest and fps")
check(VB.testEncoder(environment: ["SILL_TEST_ENCODER": "widest=4096"], testHost: false).encoder == nil
      && VB.testEncoder(environment: ["SILL_TEST_ENCODER": "widest=4096"], testHost: false).line?.contains("ignored: only a --synthetic test host") == true,
      "never Sill.app's")
check(VB.testEncoder(environment: ["SILL_TEST_ENCODER": "wide=4096"], testHost: true).encoder == nil
      && VB.testEncoder(environment: ["SILL_TEST_ENCODER": "fps=-1"], testHost: true).encoder == nil, "a word it does not know, or a rate that is none: ignored")

// MARK: VirtualDesktopLife: when the Virtual Desktop exists (plan §6 and §10)

typealias Life = VirtualDesktopLife
var asked = Life.Seen()
asked.switchOn = true
asked.shown = true
check(Life.grace == 30 && Life.spacing == 3 && Life.perMinute == 10 && Life.minute == 60 && Life.mainAfter == 2,
      "30 s after the last show, one change every 3 s and ten a minute, 2 s of a real screen")
// Made, kept while shown, 30 s after the last show, removed.
var life = Life()
check(life.look(Life.Seen(), at: 0) == .idle, "off: nothing")
var seen = asked
check(life.look(seen, at: 1) == .make, "shown, on, a real screen, unlocked, on the console: made")
life.made(.virtualDesktop, at: 1)
seen.exists = true
check(life.look(seen, at: 2) == .keep(until: nil) && life.role == .virtualDesktop, "shown: kept, nothing to look at later")
seen.shown = false
check(life.look(seen, at: 10) == .keep(until: 40), "stepped away at 10: kept until 40, 30 s from the look that found it no longer shown")
check(life.look(seen, at: 39.9) == .keep(until: 40), "…still at 39.9")
check(life.look(seen, at: 40) == .remove(.grace), "…removed at 40")
life.removed(at: 40)
seen.exists = false
check(life.look(seen, at: 41) == .idle && life.role == nil, "gone: nothing until shown again")
// Never made but when asked, with everything it needs.
let blocks: [(String, (inout Life.Seen) -> Void)] = [
    ("switched off", { $0.switchOn = false }), ("not shown", { $0.shown = false }), ("unavailable", { $0.available = false }),
    ("the guard holds", { $0.guardHolds = true }), ("no real screen (the headless role's)", { $0.realScreens = 0 }),
    ("locked", { $0.locked = true }), ("off console", { $0.offConsole = true }),
]
for (name, block) in blocks {
    var l = Life()
    var s = asked
    block(&s)
    check(l.look(s, at: 0) == .idle, "never made: \(name)")
}
// Locked: kept past its 30 s until the unlock, then 30 s from it; a switch changed meanwhile waits too.
var locked = Life()
var ls = asked
_ = locked.look(ls, at: 0)
locked.made(.virtualDesktop, at: 0)
ls.exists = true
ls.shown = false
check(locked.look(ls, at: 5) == .keep(until: 35), "stepped away at 5")
ls.locked = true
check(locked.look(ls, at: 20) == .keep(until: nil), "locked: kept, with no time to look again")
check(locked.look(ls, at: 50) == .keep(until: nil), "locked past its 30 s: kept until the unlock")
ls.switchOn = false
check(locked.look(ls, at: 55) == .keep(until: nil), "switched off while locked: waits for the unlock")
ls.switchOn = true
ls.locked = false
check(locked.look(ls, at: 60) == .keep(until: 90) && locked.unlockedAt == 60, "unlocked at 60: 30 s from the unlock")
check(locked.look(ls, at: 90) == .remove(.grace), "…then it goes")
var lockedOff = Life()
var lo = asked
_ = lockedOff.look(lo, at: 0)
lockedOff.made(.virtualDesktop, at: 0)
lo.exists = true
lo.locked = true
lo.shown = false
lo.switchOn = false
check(lockedOff.look(lo, at: 10) == .keep(until: nil), "off while locked: kept")
lo.locked = false
check(lockedOff.look(lo, at: 20) == .remove(.switchedOff), "…removed at the unlock")
// Switched off: removed, but never sooner than 3 s after the last change; the newest request wins.
var off = Life()
var os = asked
_ = off.look(os, at: 0)
off.made(.virtualDesktop, at: 0)
os.exists = true
os.switchOn = false
check(off.look(os, at: 1) == .spaced(.remove(.switchedOff), until: 3), "off 1 s after its make: waits for the spacing")
os.switchOn = true
check(off.look(os, at: 2) == .keep(until: nil), "on again before then: kept (the newest wins)")
check(off.look(os, at: 3) == .keep(until: nil), "…and nothing is removed at 3")
os.switchOn = false
check(off.look(os, at: 4) == .remove(.switchedOff), "off past the spacing: removed at once")
off.removed(at: 4)
os.exists = false
os.switchOn = true
check(off.look(os, at: 5) == .spaced(.make, until: 7), "on again 1 s after the removal: made 3 s after it")
check(off.look(os, at: 7) == .make, "…then")
// Off console: removed at once, the spacing or not.
var console = Life()
var cs = asked
_ = console.look(cs, at: 0)
console.made(.virtualDesktop, at: 0)
cs.exists = true
cs.offConsole = true
cs.shown = false
check(console.look(cs, at: 0.5) == .remove(.offConsole), "off console half a second after its make: removed at once")
// Never the main display beside a real screen.
var main = Life()
var ms = asked
_ = main.look(ms, at: 0)
main.made(.virtualDesktop, at: 0)
ms.exists = true
ms.isMain = true
check(main.look(ms, at: 1) == .keep(until: 2), "main, a real screen working since 0: 2 s of it first")
check(main.look(ms, at: 2) == .spaced(.remove(.main), until: 3), "…then removed, after the spacing")
ms.locked = true
ms.shown = false
check(main.look(ms, at: 3) == .remove(.main), "…locked or not")
// The headless release's 2 s (HeadlessDesktopPolicy.Watch.hysteresis, VirtualDisplay.swift, which this check does not
// compile), read as text from the repository this file is in.
let watchSource = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../Sources/SillHost/VirtualDisplay.swift")
let hysteresis = ((try? String(contentsOf: watchSource, encoding: .utf8)) ?? "").split(separator: "\n")
    .first { $0.contains("static let hysteresis: Double = ") }
    .flatMap { Double($0.components(separatedBy: "= ").last!.trimmingCharacters(in: .whitespaces)) }
check(hysteresis != nil && Life.mainAfter == hysteresis, "the same 2 s as the headless release, Watch.hysteresis (\(String(describing: hysteresis)))")
// The roles change hands with no second display.
var roles = Life()
var rs = asked
_ = roles.look(rs, at: 0)
roles.made(.virtualDesktop, at: 0)
rs.exists = true
rs.realScreens = 0
rs.isMain = true
check(roles.look(rs, at: 10) == .headless && roles.role == .headless, "the last real screen gone: it is the headless display (Watch's)")
rs.switchOn = false
rs.shown = false
check(roles.look(rs, at: 11) == .headless, "…kept by Watch, whatever the Virtual Desktop's switch")
rs.switchOn = true
rs.shown = true
rs.realScreens = 1
check(roles.look(rs, at: 20) == .headless, "a real screen back while it is the main display: the headless release")
rs.isMain = false
check(roles.look(rs, at: 20.5) == .keep(until: nil) && roles.role == .virtualDesktop,
      "an extra display again, shown, the switch on: the Virtual Desktop again")
var release = Life()
var hs = asked
hs.exists = true
hs.realScreens = 0
hs.isMain = true
release.made(.headless, at: 0)
check(release.look(hs, at: 1) == .headless, "the headless display: Watch's")
hs.realScreens = 1
hs.isMain = false
hs.shown = false
check(release.look(hs, at: 5) == .headless, "a real screen back, nobody shows it: the headless release")
hs.shown = true
hs.switchOn = false
check(release.look(hs, at: 6) == .headless, "…shown, but the switch off: the headless release")
hs.switchOn = true
hs.locked = true
check(release.look(hs, at: 7) == .headless, "…locked: the headless release")
var untold = Life()
var us = asked
us.exists = true
check(untold.look(us, at: 0) == .headless && untold.role == .headless, "a display Sill was not told it made: Watch's, never removed here")
check(untold.look(us, at: 1) == .keep(until: nil) && untold.role == .virtualDesktop, "…shown, the switch on, an extra display: the Virtual Desktop")
// Made and never shown (a takeover's display, a coordinator's make): 30 s from the make.
var never = Life()
var ns = Life.Seen()
ns.switchOn = true
ns.exists = true
never.made(.virtualDesktop, at: 0)
check(never.look(ns, at: 1) == .keep(until: 30) && never.madeAt == 0, "made and never shown: 30 s from its make")
// The spacing's minute: ten changes, then a minute after the first of them; ten kept.
var minute = Life()
for i in 0..<10 { minute.removed(at: Double(i) * 3) }
check(minute.nextAllowed == 60 && minute.changes.count == 10, "ten changes in 27 s: the next a minute after the first (\(minute.nextAllowed))")
minute.removed(at: 60)
check(minute.nextAllowed == 63 && minute.changes.first == 3, "then 3 s after the last, and a minute after the tenth last")
for i in 0..<5 { minute.removed(at: 70 + Double(i)) }
check(minute.changes.count == 10 && minute.changes.last == 74, "only the last ten kept")
check(Life().nextAllowed == -Double.infinity, "no change yet: any time")
// The lines.
check(Life.removedLine(.grace, moved: 3, of: 3, to: "Built-in Retina Display")
      == "Virtual Desktop: no device has shown it for 30 s; moved 3 windows to Built-in Retina Display and removed it.", "the grace's line, as the plan words it")
check(Life.removedLine(.main, moved: 0, of: 0, to: "DELL U2723QE")
      == "Virtual Desktop: it was the main display and a real screen works again; removed it.", "the main display's")
check(Life.removedLine(.switchedOff, moved: 1, of: 1, to: "DELL U2723QE") == "Virtual Desktop: turned off; moved 1 window to DELL U2723QE and removed it.",
      "switched off, one window")
check(Life.removedLine(.offConsole, moved: 1, of: 2, to: "Built-in Retina Display")
      == "Virtual Desktop: this session is off the console; moved 1 of 2 windows to Built-in Retina Display (the rest go where macOS puts them) and removed it.",
      "off console, a window not moved")
check(Life.keptLockedLine == "Virtual Desktop: kept while this Mac is locked; it goes 30 s after the unlock unless a device shows it.", "kept locked")
check(Life.waitedLine(.make, waited: 2.1, fullMinute: false) == "Virtual Desktop: waited 2.1 s before making it (3 s since the last change).",
      "a make that waited")
check(Life.waitedLine(.remove(.grace), waited: 12.04, fullMinute: true) == "Virtual Desktop: waited 12.0 s before removing it (10 changes in a minute).",
      "a removal held by the minute")
check(Life.lockedLine(grace: 30) == Life.keptLockedLine && Life.lockedLine(grace: 3).contains("it goes 3 s after the unlock"),
      "the kept-locked line with a test host's grace")
check(Life.removedLine(.grace, moved: 0, of: 0, to: "x", grace: 4) == "Virtual Desktop: no device has shown it for 4 s; removed it.",
      "the grace's line with a test host's grace")
check(Life.words(.grace) == "no device has shown it for 30 s" && Life.words(.switchedOff, grace: 4) == "turned off", "the words, the grace's own")
// The make's line (the coordinator's), from the mode it came up at.
let made = VirtualDesktopSize.Size(widthPt: 1218, heightPt: 800, scale: 2)
check(Life.madeLine(came: made, asked: made, hz: 60, id: 7, ms: 412, device: "iPad mini", space: CGSize(width: 1133, height: 744))
      == "Virtual Desktop 1218×800 pt @2× at 60 Hz id 7: made in 412 ms for iPad mini (its picture: 1133×744 pt).", "the make's line, with the space it is sized to")
check(Life.madeLine(came: made, asked: made, hz: 60, id: 7, ms: 412, device: "iPad mini")
      == "Virtual Desktop 1218×800 pt @2× at 60 Hz id 7: made in 412 ms for iPad mini.", "…a size the person chose: no space")
check(Life.madeLine(came: made, asked: made, hz: 60, id: 7, ms: 412, device: "iPad mini", space: CGSize(width: 1116.6, height: Double.nan))
      == "Virtual Desktop 1218×800 pt @2× at 60 Hz id 7: made in 412 ms for iPad mini.", "…a side that is no number: none said, no trap")
check(Life.madeLine(came: VirtualDesktopSize.Size(widthPt: 1218, heightPt: 800, scale: 1), asked: made, hz: 60, id: 7, ms: 9, device: nil)
      == "Virtual Desktop 1218×800 pt @1× at 60 Hz (asked 1218×800 @2×) id 7: made in 9 ms at 1920×1080: no device's screen known yet.",
      "…the mode it came up at, the one asked too, and no device known")
check(Life.madeLine(came: made, asked: made, hz: 120, id: nil, ms: 0, device: "sillclient", space: CGSize(width: 1133.4, height: 743.6))
      == "Virtual Desktop 1218×800 pt @2× at 120 Hz: said, never made (TEST ONLY, SILL_TEST_VIRTUAL_DESKTOP), for sillclient (its picture: 1133×744 pt).",
      "…a test host's, said and never made")
// A test host's grace (SILL_TEST_VD_GRACE): the same rules, its seconds.
var quick = Life(grace: 3)
check(quick.graceSeconds == 3 && Life().graceSeconds == 30, "a grace of its own, 30 s by default")
var qs = asked
_ = quick.look(qs, at: 0)
quick.made(.virtualDesktop, at: 0)
qs.exists = true
qs.shown = false
check(quick.look(qs, at: 5) == .keep(until: 8) && quick.look(qs, at: 8) == .remove(.grace), "a 3 s grace: kept 3 s, then removed")
// The TEST ONLY hook: honoured only by a test host with SILL_TEST_DISPLAYS' stops.
let hookOn = Life.testHook(environment: ["SILL_TEST_VIRTUAL_DESKTOP": "1", "SILL_TEST_VD_GRACE": "3"], testHost: true, stops: true)
check(hookOn.on && hookOn.grace == 3 && hookOn.lines == ["Test Virtual Desktop: this host can have it and only says it makes it, never makes one (SILL_TEST_VIRTUAL_DESKTOP); its grace 3 s."],
      "the hook on a test host with stops: on, its grace, one line: \(hookOn.lines)")
let none = Life.testHook(environment: [:], testHost: true, stops: true)
check(!none.on && none.grace == nil && none.lines.isEmpty, "no variable: off, no line (the CLI's output as before)")
let app = Life.testHook(environment: ["SILL_TEST_VIRTUAL_DESKTOP": "1"], testHost: false, stops: true)
check(!app.on && app.grace == nil && app.lines.count == 1 && app.lines[0].contains("ignored: only a --synthetic test host"), "Sill.app, or a host that advertises: ignored, said once")
let noStops = Life.testHook(environment: ["SILL_TEST_VIRTUAL_DESKTOP": "1"], testHost: true, stops: false)
check(!noStops.on && noStops.lines.count == 1 && noStops.lines[0].contains("they need SILL_TEST_DISPLAYS"), "no test stops: ignored, said")
let graceAlone = Life.testHook(environment: ["SILL_TEST_VD_GRACE": "3"], testHost: true, stops: true)
check(!graceAlone.on && graceAlone.grace == nil && graceAlone.lines.count == 1, "the grace alone: ignored, said")
for bad in ["0", "0.5", "121", "nan", "inf", "-3", "x", "3s"] {
    let h = Life.testHook(environment: ["SILL_TEST_VIRTUAL_DESKTOP": "1", "SILL_TEST_VD_GRACE": bad], testHost: true, stops: true)
    check(h.on && h.grace == nil && h.lines.count == 2 && h.lines[0] == "SILL_TEST_VD_GRACE=\(bad) ignored: seconds from 1 to 120."
          && h.lines[1].hasSuffix("its grace 30 s."), "a grace of \(bad): ignored, the 30 s kept")
}
for good in ["1", "120", "2.5"] {
    let h = Life.testHook(environment: ["SILL_TEST_VIRTUAL_DESKTOP": "1", "SILL_TEST_VD_GRACE": good], testHost: true, stops: true)
    check(h.on && h.grace == Double(good) && h.lines.count == 1, "a grace of \(good) s: taken")
}
check(!Life.testHook(environment: ["SILL_TEST_VIRTUAL_DESKTOP": "0"], testHost: true, stops: true).on
      && !Life.testHook(environment: ["SILL_TEST_VIRTUAL_DESKTOP": ""], testHost: true, stops: true).on, "0 or empty: off")

// MARK: VirtualDesktopWords: why this Mac cannot make it now (kind 16's note, Sill for Mac's Settings › Displays)

typealias Words = VirtualDesktopWords
check(Words.name == "Virtual Desktop" && Words.name == DesktopDisplays.virtualDesktopName, "its name, one word for both apps and the stop's")
func note(test: Bool = false, loop: Bool = true, api: String? = nil, sr: Bool = true, failure: String? = nil, held: Bool = false,
          off: Bool = false) -> String? {
    Words.note(testHost: test, appKitLoop: loop, apiProblem: api, screenRecording: sr, failure: failure, guardHolds: held, offConsole: off)
}
check(note() == nil, "everything it needs: no note, it can be made")
check(note(test: true, loop: false, api: "x", sr: false, failure: "y", held: true, off: true) == "Not on a test host.", "a test host first")
check(note(loop: false, api: "x", sr: false, failure: "y", held: true, off: true) == "Start SillHost with --virtual-desktop to use it.",
      "then the CLI without its AppKit loop")
check(note(api: "private class CGVirtualDisplay not found", sr: false, failure: "y", held: true, off: true)
      == "Not available on this version of macOS: private class CGVirtualDisplay not found", "then the private API")
check(note(sr: false, failure: "y", held: true, off: true) == "Needs Screen Recording.", "then Screen Recording")
check(note(failure: "it never came up", held: true, off: true) == "Off for this session: it never came up. Turn it off and on to try again.",
      "then a make that failed this run")
check(note(held: true, off: true) == "Off for now: Sill stopped while making a display, twice in a row.", "then the guard for #380")
check(note(off: true) == "Not while another user is on this Mac’s screen.", "then the console")
// A device's Settings panel (the Mac's group, after Virtual Display).
check(Words.panelFootnote(on: false, mac: "Mac mini", size: (1218, 800), hz: 60)
      == "A desktop of its own for your devices, after Mac mini’s screens. Turning it on shows it.", "the panel, off: what it is, no size")
check(Words.panelFootnote(on: true, mac: "Mac mini", size: (1218, 800), hz: 60)
      == "Tap Desktop to step to it. It is here only while a device shows it. Its size: 1218 × 800 at 60 Hz.", "on: how to reach it, its size and rate")
check(Words.panelFootnote(on: true, mac: "Mac mini", size: nil, hz: 60) == "Tap Desktop to step to it. It is here only while a device shows it.",
      "on with no size said: no size")
check(Words.sizeLine(widthPt: 800, heightPt: 1218, hz: nil) == "Its size: 800 × 1218.", "a size with no rate")
check(Words.unpaired(mac: "Mac mini") == "Only a device paired with Mac mini can change this.", "unpaired: why the switch is disabled")
// Sill for Mac: Settings › Displays' status, the menu's subtitle, the card.
check(Words.status(widthPt: 1218, heightPt: 800, hz: 60, device: "iPad mini", shown: true) == "Showing on iPad mini: 1218 × 800, 60 Hz",
      "the status while a device shows it, as the plan words it")
check(Words.status(widthPt: 1218, heightPt: 800, hz: 60, device: "iPad mini", shown: false)
      == "1218 × 800, 60 Hz, for iPad mini, until no device has shown it for 30 seconds", "…made and kept, no device showing it")
check(Words.status(widthPt: 1920, heightPt: 1080, hz: 60, device: nil, shown: true) == "Showing: 1920 × 1080, 60 Hz", "…no device known")
check(Words.menuSubtitle(on: false, note: "x", shownOn: "iPad mini", size: (1218, 800), hz: 60) == "A desktop for your devices, after your screens",
      "the menu, off: what it is, whatever else")
check(Words.menuSubtitle(on: true, note: "Needs Screen Recording.", shownOn: nil, size: nil, hz: nil) == "Needs Screen Recording.",
      "…on where it cannot be made: why")
check(Words.menuSubtitle(on: true, note: nil, shownOn: "iPad mini", size: (1218, 800), hz: 60) == "On iPad mini: 1218 × 800, 60 Hz",
      "…shown: on which device, its size and rate")
check(Words.menuSubtitle(on: true, note: nil, shownOn: nil, size: nil, hz: nil) == "Tap Desktop on your device to step to it", "…on, not shown")
check(Words.cardTitle(widthPt: 1218, heightPt: 800) == "Virtual Desktop · 1218×800", "the card's source row")
check(Words.macSwitch == "Add a desktop for your devices" && Words.macFootnote.contains("30 seconds") && Words.pickersFootnote.contains("next time"),
      "Settings › Displays' switch and footnotes")

// 5,000 random sessions: devices showing it and stepping away, the switch flipped (a fifth of them as fast as a device
// can, a fifth with the switch on and a device stepping onto it now and then), locks, user switches, monitors coming and going, macOS or the person making it the main display, the guard and
// the private API; the headless role played by a model of Watch (made 2 s after the last real screen went while a device
// wants the Desktop, locked or not; released 2 s after one works, or at once off console). Judged against the plan's
// sentences, kept by the check's own records (never Life's): never two; made only when shown, on, unlocked, on the
// console, available, the guard clear and a real screen working, and always then once the spacing allows; at most one
// change every 3 s and ten a minute, but off console's; the headless role Watch's alone; gone at once off console; never
// the main display beside a real screen past its 2 s and the spacing; none for nobody past the grace (from the unlock, after
// a lock) and none switched off, but while locked; nothing removed while locked but the main display.
var tally: [String: Int] = [:]
let invariants = ["never two", "made only when asked", "made when asked", "spacing", "headless is Watch's", "off console at once",
                  "never main", "none for nobody", "switched off goes", "locked keeps", "removal reasons", "answers"]
for session in 0..<5_000 {
    var l = Life()
    var s = Life.Seen()
    s.realScreens = Int.random(in: 0...2, using: &rng)
    let churn = session % 5 == 0                    // a device flipping the switch and stepping as fast as it can
    let quiet = session % 5 == 1                    // the switch on, a device stepping on and off it now and then
    s.switchOn = quiet || Bool.random(using: &rng)
    let showRate = churn ? 1.5 : quiet ? 0.03 : [0.05, 0.2, 0.5].randomElement(using: &rng)!
    let switchRate = churn ? 0.8 : quiet ? 0 : [0.0, 0.02, 0.1].randomElement(using: &rng)!
    let realRate = churn ? 0.05 : quiet ? 0.004 : 0.02
    let lockRate = quiet ? 0.005 : 0.02, consoleRate = quiet ? 0.002 : 0.01, mainRate = quiet ? 0.002 : 0.01
    var wants = Bool.random(using: &rng)            // a device on the Desktop (the headless role's ask)
    var exists = false, role: Life.Role?
    var changes: [Double] = []
    var lastShown: Double?, wasShown = false, lastUnlock: Double?, wasLocked = false, madeAt = 0.0
    var realSince: Double?, realGone: Double?            // set by the first look, as Life's are
    var offSince: Double? = s.switchOn ? nil : 0
    var prevReal = s.realScreens
    var t = 0.0
    let end = quiet ? Double.random(in: 150...400, using: &rng) : Double.random(in: 40...240, using: &rng)
    var bad: [String: String] = [:]
    func v(_ name: String, _ detail: @autoclosure () -> String) { if bad[name] == nil { bad[name] = "t=\(String(format: "%.2f", t)) \(detail())" } }
    func allowed() -> Double {
        var a = -Double.infinity
        if let last = changes.last { a = last + 3 }
        if changes.count >= 10 { a = max(a, changes[changes.count - 10] + 60) }
        return a
    }
    while t < end {
        let dt = Double.random(in: 0.05...0.6, using: &rng)
        t += dt
        func happens(_ rate: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < rate * dt }
        if happens(lockRate), !s.offConsole { s.locked.toggle() }
        if happens(consoleRate) { s.offConsole.toggle(); if s.offConsole { s.locked = false } }
        if happens(showRate) { s.shown.toggle() }
        if happens(0.2) { wants.toggle() }
        if s.locked || s.offConsole { s.shown = false }          // locked or off console, only the main display streams
        if happens(switchRate) { s.switchOn.toggle() }
        if happens(realRate) { s.realScreens = Int.random(in: 0...2, using: &rng) }
        if happens(0.004) { s.available.toggle() }
        if happens(0.004) { s.guardHolds.toggle() }
        if exists {
            if s.realScreens == 0 { s.isMain = true }
            else if prevReal == 0 { s.isMain = Bool.random(using: &rng) }   // macOS may leave it the main display, or not
            else if happens(mainRate) { s.isMain.toggle() }                 // the person in System Settings › Displays
        } else { s.isMain = false }
        prevReal = s.realScreens
        // The check's own records, in the plan's words.
        if s.shown || wasShown { lastShown = t }
        wasShown = s.shown
        if wasLocked, !s.locked { lastUnlock = t }
        wasLocked = s.locked
        if s.realScreens > 0 { if realSince == nil { realSince = t }; realGone = nil } else { realSince = nil; if realGone == nil { realGone = t } }
        if s.switchOn { offSince = nil } else if offSince == nil { offSince = t }
        if exists, s.realScreens == 0 { role = .headless }
        if exists, role == .headless, s.realScreens > 0, s.switchOn, s.shown, !s.isMain, !s.locked, !s.offConsole {
            role = .virtualDesktop
            tally["taken over", default: 0] += 1
        }
        let canMake = s.shown && s.switchOn && s.available && !s.guardHolds && !s.locked && !s.offConsole && s.realScreens > 0
        let free = allowed()
        s.exists = exists
        let d = l.look(s, at: t)
        // The answer, against the records.
        if !exists, canMake, t >= free, d != .make { v("made when asked", "\(d) for \(s)") }
        if s.realScreens == 0, d != .idle, d != .headless { v("headless is Watch's", "\(d) with no real screen") }
        switch d {
        case .make:
            tally["made", default: 0] += 1
            if exists { v("never two", "a make while one exists") }
            if !canMake { v("made only when asked", "\(s)") }
            if t < free - 1e-9 { v("spacing", "a make at \(t), the next allowed at \(free)") }
            exists = true; role = .virtualDesktop; madeAt = t
            s.isMain = Double.random(in: 0..<1, using: &rng) < 0.02
            l.made(.virtualDesktop, at: t)
            changes.append(t)
        case .remove(let why):
            tally["removed \(why)", default: 0] += 1
            if !exists || role != .virtualDesktop { v("answers", "a removal of \(String(describing: role))") }
            if why != .offConsole, t < free - 1e-9 { v("spacing", "a removal (\(why)) at \(t), the next allowed at \(free)") }
            if s.locked, why != .main { v("locked keeps", "removed (\(why)) while locked") }
            switch why {
            case .grace:
                if s.shown || (lastShown.map { t - $0 < 30 - 1e-9 } ?? false) || (lastUnlock.map { t - $0 < 30 - 1e-9 } ?? false) || t - madeAt < 30 - 1e-9 {
                    v("removal reasons", "the grace's removal, last shown \(String(describing: lastShown)), unlocked \(String(describing: lastUnlock))")
                }
            case .switchedOff: if s.switchOn { v("removal reasons", "removed as off while on") }
            case .offConsole: if !s.offConsole { v("removal reasons", "removed as off console while on it") }
            case .main:
                if !s.isMain || s.realScreens == 0 || (realSince.map { t - $0 < 2 - 1e-9 } ?? true) { v("removal reasons", "removed as main: \(s), real since \(String(describing: realSince))") }
            }
            exists = false; role = nil; s.isMain = false
            l.removed(at: t)
            changes.append(t)
        case .spaced(let c, let until):
            tally[free > (changes.last ?? -Double.infinity) + 3 + 1e-9 ? "spaced by the minute" : "spaced", default: 0] += 1
            if abs(until - free) > 1e-9 || until <= t { v("answers", "spaced \(c) until \(until), allowed \(free)") }
            if case .remove(.offConsole) = c { v("off console at once", "off console waits") }
        case .keep(let until):
            tally[s.locked ? "kept locked" : "kept", default: 0] += 1
            if !exists || role != .virtualDesktop { v("answers", "kept \(String(describing: role))") }
            if let until, until <= t { v("answers", "a keep until \(until)") }
        case .headless:
            if !exists || role != .headless { v("answers", "headless for \(String(describing: role)), exists \(exists)") }
            // The model of Watch: released 2 s after a real screen works, at once off console.
            if s.offConsole || (realSince.map { t - $0 >= 2 } ?? false) {
                tally["headless released", default: 0] += 1
                exists = false; role = nil; s.isMain = false
                l.removed(at: t)
                changes.append(t)
            }
        case .idle:
            if exists { v("answers", "idle with one") }
            // The model of Watch: made 2 s after the last real screen went, for a device on the Desktop, locked or not.
            if s.realScreens == 0, wants, !s.offConsole, s.available, !s.guardHolds, let gone = realGone, t - gone >= 2 {
                tally["headless made", default: 0] += 1
                exists = true; role = .headless; s.isMain = true; madeAt = t
                l.made(.headless, at: t)
                changes.append(t)
            }
        }
        // After the look (and what it changed): the spacing as it stands now.
        let freeAfter = allowed()
        if exists, s.offConsole { v("off console at once", "still there off console") }
        if exists, s.isMain, s.realScreens > 0, let r = realSince, t - r >= 2, t >= freeAfter { v("never main", "the main display beside a real screen since \(r)") }
        if exists, role == .virtualDesktop, !s.locked, !s.offConsole, !s.isMain, t >= freeAfter {
            let from = max(lastShown ?? madeAt, lastUnlock ?? -Double.infinity, madeAt)
            if !s.shown, t - from >= 30 { v("none for nobody", "not shown since \(from)") }
            if let o = offSince, o < t { v("switched off goes", "off since \(o)") }
        }
    }
    for name in invariants { check(bad[name] == nil, "session \(session) (\(churn ? "churn" : quiet ? "quiet" : "calm")): \(name): \(bad[name] ?? "")") }
}
// Each rule was exercised, so a broken one shows.
// (Each floor is about a third of what a run does: 2026-11-19, three runs, 6,200–6,600 made, 250–300 by the grace, 3,600–3,900
// switched off, 730–800 off console, 800–910 main, 21,000–23,000 spaced, 2,800–3,500 by the minute, 99,000–102,000 kept
// locked, 2,600–2,700 headless made, 2,300–2,400 released, 290–310 taken over.)
for (what, least) in [("made", 2_000), ("removed grace", 80), ("removed switchedOff", 1_200), ("removed offConsole", 200), ("removed main", 250),
                      ("spaced", 7_000), ("spaced by the minute", 800), ("kept locked", 30_000), ("headless made", 800),
                      ("headless released", 700), ("taken over", 90)] {
    check((tally[what] ?? 0) >= least, "the random sessions did \(what) \(tally[what] ?? 0) times, under \(least)")
}

// MARK: DesktopWindowLedger: windows off the Virtual Desktop and back (plan §7)

typealias DWL = DesktopWindowLedger
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
let vdArea = r(1512, 25, 1376, 1007)               // the Virtual Desktop right of a 1512-point main display, under its menu bar
let mainArea = r(0, 38, 1512, 944)                 // the main display's visible area (a notched MacBook's menu bar)
check(DWL.place(r(1600.3, 100.7, 800, 600), from: vdArea, to: vdArea) == r(1600.3, 100.7, 800, 600), "the same area: as it was, exactly")
check(DWL.place(r(1512, 25, 800, 600), from: vdArea, to: mainArea) == r(0, 38, 800, 600), "top-left stays top-left")
check(DWL.place(r(2088, 432, 800, 600), from: vdArea, to: mainArea) == r(712, 382, 800, 600), "flush right and bottom stay so")
check(DWL.place(r(1800, 228.5, 800, 600), from: vdArea, to: mainArea) == r(356, 210, 800, 600),
      "the middle stays the middle (\(DWL.place(r(1800, 228.5, 800, 600), from: vdArea, to: mainArea)))")
check(DWL.place(r(1700, 100, 1600, 1000), from: vdArea, to: mainArea) == r(0, 38, 1600, 1000), "larger than the area: its size kept, its corner at the area's")
check(DWL.place(r(1400, -50, 800, 600), from: vdArea, to: mainArea) == r(0, 38, 800, 600), "partly off the area: held at its edge")
check(DWL.place(r(2700, 1200, 800, 600), from: vdArea, to: mainArea) == r(712, 382, 800, 600), "past the far edges: held at them")
check(DWL.place(r(1600.4, 100.6, 800, 600), from: vdArea, to: mainArea) == r(109, 102, 800, 600), "whole points (\(DWL.place(r(1600.4, 100.6, 800, 600), from: vdArea, to: mainArea)))")
check(DWL.place(r(1600, 100, 1376, 1007), from: vdArea, to: mainArea) == r(0, 38, 1376, 1007), "exactly the area's size: at its corner")
let mainD = r(0, 0, 1512, 982), vdD = r(1512, 0, 1376, 1032), both = [mainD, vdD]
check(DWL.isOn(r(1600, 100, 800, 600), vdD, among: both) && !DWL.isOn(r(1600, 100, 800, 600), mainD, among: both), "wholly on it")
check(!DWL.isOn(r(100, 100, 800, 600), vdD, among: both), "on the main display")
check(DWL.isOn(r(1400, 100, 800, 600), vdD, among: both) && !DWL.isOn(r(1000, 100, 800, 600), vdD, among: both), "mostly on one: that one")
check(DWL.isOn(r(1112, 100, 800, 600), vdD, among: both) && DWL.isOn(r(1112, 100, 800, 600), mainD, among: both), "half and half: on both")
check(!DWL.isOn(r(5000, 5000, 100, 100), vdD, among: both) && !DWL.isOn(r(5000, 5000, 100, 100), vdD, among: [vdD]), "on no display: on none")
// Back: where Sill put it, within 2 points, or the person's.
let entry = DWL.Entry(was: r(1600, 100, 800, 600), area: vdArea, put: r(88, 113, 800, 600))
check(DWL.back(entry, current: nil, fullScreen: false, area: vdArea) == .gone, "closed: forgotten")
check(DWL.back(entry, current: r(88, 113, 800, 600), fullScreen: true, area: vdArea) == .fullScreen, "in full screen now: left")
check(DWL.back(entry, current: r(90, 111, 802, 598), fullScreen: false, area: vdArea) == .put(r(1600, 100, 800, 600)),
      "within 2 points of where Sill put it: back to its place, exactly")
check(DWL.back(entry, current: r(88, 113, 803, 600), fullScreen: false, area: vdArea) == .resized, "3 points wider: resized on the Mac")
check(DWL.back(entry, current: r(88, 113, 800, 597), fullScreen: false, area: vdArea) == .resized, "3 points shorter: resized")
check(DWL.back(entry, current: r(91, 113, 800, 600), fullScreen: false, area: vdArea) == .moved, "3 points along: moved on the Mac")
check(DWL.back(entry, current: r(88, 110, 800, 600), fullScreen: false, area: vdArea) == .moved, "3 points up: moved")
check(DWL.back(entry, current: r(300, 300, 900, 700), fullScreen: false, area: vdArea) == .resized, "moved and resized: resized")
let upArea = r(1512, 25, 1032, 1351)               // the Virtual Desktop made again turned
check(DWL.back(entry, current: r(88, 113, 800, 600), fullScreen: false, area: upArea) == .put(r(1547, 163, 800, 600)),
      "scaled into the area it has now (\(DWL.back(entry, current: r(88, 113, 800, 600), fullScreen: false, area: upArea)))")

// The moves over a stand-in Mac: what Accessibility would read and write.
struct StandIn: DesktopWindowLedger.Access {
    struct Win {
        var own: CGRect?                // its frame out of full screen; nil: closed
        var fullScreen = false
        var screen = r(1512, 0, 1376, 1032)   // its full-screen frame
        var listed = true               // the window server lists it
        var answers = true              // its app answers Accessibility
        var leaves = true               // it leaves full screen when asked
        var refuses = false             // it refuses to be moved
        var snap: CGFloat = 0           // the app moves itself this far right of where it was put (keeping itself on screen)
    }
    var wins: [Int: Win] = [:]
    var log: [String] = []
    mutating func frame(_ w: Int) -> CGRect? {
        log.append("frame \(w)")
        guard let x = wins[w], x.answers, let own = x.own else { return nil }
        return x.fullScreen ? x.screen : own
    }
    mutating func isFullScreen(_ w: Int) -> Bool { wins[w]?.fullScreen ?? false }
    mutating func isListed(_ w: Int) -> Bool { (wins[w]?.listed ?? false) && wins[w]?.own != nil }
    mutating func visibleArea(around r: CGRect) -> CGRect? { nil }
    mutating func setPosition(_ w: Int, _ p: CGPoint) -> WindowRestore.Write { .done }
    mutating func setSize(_ w: Int, _ s: CGSize) -> WindowRestore.Write { .done }
    mutating func put(_ w: Int, at frame: CGRect) -> Bool {
        log.append("put \(w)")
        guard var x = wins[w], x.own != nil, x.answers, !x.refuses, !x.fullScreen else { return false }
        x.own = frame.offsetBy(dx: x.snap, dy: 0)
        wins[w] = x
        return true
    }
    func name(_ w: Int) -> String { "window \(w)" }
    mutating func leaveFullScreen(_ w: Int) -> Bool {
        log.append("leave \(w)")
        guard var x = wins[w], x.leaves else { return false }
        x.fullScreen = false
        wins[w] = x
        return true
    }
}
var mac = StandIn()
mac.wins[1] = StandIn.Win(own: r(1600, 100, 800, 600))
mac.wins[2] = StandIn.Win(own: r(1700, 200, 600, 400), fullScreen: true)
mac.wins[3] = StandIn.Win(own: r(1700, 200, 600, 400), fullScreen: true, leaves: false)
mac.wins[4] = StandIn.Win(own: r(2088, 432, 800, 600), snap: 5)
mac.wins[5] = StandIn.Win(own: r(1600, 300, 500, 500), refuses: true)
mac.wins[6] = StandIn.Win(own: nil, listed: false)
var book = DWL.Book<Int>()
let out = DWL.moveAllOut((1...6).map { (id: CGWindowID($0), w: $0) }, area: vdArea, mainArea: mainArea, on: &mac, into: &book)
check(out.moved == 3 && out.of == 6, "out: three moved of six (\(out))")
check(book.count == 3 && Set(book.items.keys) == [1, 2, 4], "the book keeps the three moved")
check(book.items[1]?.entry == DWL.Entry(was: r(1600, 100, 800, 600), area: vdArea, put: r(109, 101, 800, 600)), "a window out: what it was and where it went")
check(mac.wins[2]?.own == r(221, 195, 600, 400), "out of full screen, then moved by its own frame (\(String(describing: mac.wins[2]?.own)))")
check(mac.log.firstIndex(of: "leave 2") ?? 99 < mac.log.firstIndex(of: "frame 2") ?? -1, "full screen left before its frame is read")
check(book.items[2]?.entry.was == r(1700, 200, 600, 400), "its own frame kept, not the full screen's")
check(mac.wins[3]?.fullScreen == true && mac.wins[3]?.own == r(1700, 200, 600, 400), "one that will not leave full screen: left to macOS")
check(book.items[4]?.entry.put == r(717, 382, 800, 600) && mac.wins[4]?.own == r(717, 382, 800, 600), "where the app took it, read back")
check(mac.wins[5]?.own == r(1600, 300, 500, 500), "one that refuses: left")
// Window 1 left alone, window 2 moved on the Mac, window 4 where its app keeps it, a window closed, one not answering.
mac.wins[2]?.own = r(400, 400, 600, 400)
var later = book
mac.wins[7] = StandIn.Win(own: r(10, 10, 300, 300))
later.movedOut(7, handle: 7, entry: DWL.Entry(was: r(1600, 500, 300, 300), area: vdArea, put: r(10, 10, 300, 300)))
mac.wins[7]?.own = nil
mac.wins[7]?.listed = false
mac.wins[8] = StandIn.Win(own: r(20, 20, 300, 300), answers: false)
later.movedOut(8, handle: 8, entry: DWL.Entry(was: r(1600, 600, 300, 300), area: vdArea, put: r(20, 20, 300, 300)))
mac.wins[9] = StandIn.Win(own: r(30, 30, 300, 300), refuses: true)
later.movedOut(9, handle: 9, entry: DWL.Entry(was: r(1600, 700, 300, 300), area: vdArea, put: r(30, 30, 300, 300)))
let came = DWL.bringBack(&later, area: vdArea, on: &mac)
check(came == DWL.BackCount(of: 6, back: 2, moved: 1, resized: 0, closed: 1, fullScreen: 0, failed: 2), "back: two of six (\(came))")
check(mac.wins[9]?.own == r(30, 30, 300, 300), "one whose app refuses the move back: left")
check(mac.wins[1]?.own == r(1600, 100, 800, 600), "window 1 at its place on the Virtual Desktop, as it was")
check(mac.wins[4]?.own == r(2093, 432, 800, 600), "window 4 back (its app's 5 points with it)")
check(mac.wins[2]?.own == r(400, 400, 600, 400), "window 2, moved on the Mac, stays")
check(later.isEmpty, "the book emptied")
check(DWL.backLine(came) == "Virtual Desktop: 2 of 6 windows back in their places (1 was moved on the Mac, 1 was closed, 2 could not be moved).",
      "the line (\(DWL.backLine(came) ?? "nil"))")
check(DWL.backLine(DWL.BackCount(of: 3, back: 2, moved: 1)) == "Virtual Desktop: 2 of 3 windows back in their places (1 was moved on the Mac).",
      "the plan's line")
check(DWL.backLine(DWL.BackCount(of: 3, back: 3)) == "Virtual Desktop: 3 windows back in their places." &&
      DWL.backLine(DWL.BackCount(of: 1, back: 1)) == "Virtual Desktop: 1 window back in its place.", "all back")
check(DWL.backLine(DWL.BackCount(of: 4, back: 0, moved: 1, resized: 2, fullScreen: 1))
      == "Virtual Desktop: 0 of 4 windows back in their places (3 were moved or resized on the Mac, 1 is in full screen).", "none back")
check(DWL.backLine(DWL.BackCount(of: 1, resized: 1)) == "Virtual Desktop: 0 of 1 windows back in their places (1 was resized on the Mac)." &&
      DWL.backLine(DWL.BackCount()) == nil, "resized; nothing kept: no line")
var full = StandIn()
full.wins[1] = StandIn.Win(own: r(1600, 100, 800, 600))
var fullBook = DWL.Book<Int>()
_ = DWL.moveOut(1, 1, area: vdArea, mainArea: mainArea, on: &full, into: &fullBook)
full.wins[1]?.fullScreen = true
check(DWL.bringBack(&fullBook, area: vdArea, on: &full) == DWL.BackCount(of: 1, fullScreen: 1), "in full screen on the Mac now: left")

// 2,000 random windows out and back: out, inside the main display's area when it fits, its size kept, in whole points,
// flush edges kept flush; back to the same area, exactly where it was (Noah: "the display, size and position they were
// in"); back to a new area, inside it when it fits, its size kept; moved or resized on the Mac, left.
for run in 0..<2_000 {
    func area() -> CGRect {
        r(CGFloat(Int.random(in: -3000...3000, using: &rng)), CGFloat(Int.random(in: -1500...1500, using: &rng)),
          CGFloat(Int.random(in: 800...4096, using: &rng)), CGFloat(Int.random(in: 600...2400, using: &rng)))
    }
    let a = area(), m = area(), b = area()
    let w = CGFloat(Int.random(in: 200...2600, using: &rng)), h = CGFloat(Int.random(in: 150...1800, using: &rng))
    var x = a.minX + CGFloat.random(in: -100...max(-100, a.width + 100 - w), using: &rng)
    if run % 7 == 0 { x = a.maxX - w }                                     // flush right
    if run % 11 == 0 { x = a.minX }                                        // flush left
    let wasFrame = r(x.rounded(), (a.minY + CGFloat.random(in: 0...max(0, a.height - h), using: &rng)).rounded(), w, h)
    var m2 = StandIn()
    m2.wins[1] = StandIn.Win(own: wasFrame, snap: run % 13 == 0 ? 3 : 0)
    var b2 = DWL.Book<Int>()
    guard case .moved(let took) = DWL.moveOut(1, 1, area: a, mainArea: m, on: &m2, into: &b2) else { check(false, "random \(run): not moved"); continue }
    let put = m2.wins[1]!.own!.offsetBy(dx: -(m2.wins[1]!.snap), dy: 0)
    var ok = put.size == wasFrame.size && put.minX == put.minX.rounded() && put.minY == put.minY.rounded() && took == m2.wins[1]!.own!
    if w <= m.width { ok = ok && put.minX >= m.minX && put.maxX <= m.maxX } else { ok = ok && put.minX == m.minX }
    if h <= m.height { ok = ok && put.minY >= m.minY && put.maxY <= m.maxY } else { ok = ok && put.minY == m.minY }
    if w < a.width, w < m.width, wasFrame.maxX == a.maxX { ok = ok && put.maxX == m.maxX }
    if wasFrame.minX <= a.minX { ok = ok && put.minX == m.minX }
    check(ok, "random \(run): out \(wasFrame) in \(a) to \(put) in \(m)")
    var again = b2
    let same = DWL.bringBack(&again, area: a, on: &m2)
    check(same.back == 1 && m2.wins[1]!.own! == wasFrame.offsetBy(dx: m2.wins[1]!.snap, dy: 0), "random \(run): back to \(wasFrame), at \(m2.wins[1]!.own!)")
    m2.wins[1]!.own = took
    var turned = b2
    _ = DWL.bringBack(&turned, area: b, on: &m2)
    let at = m2.wins[1]!.own!.offsetBy(dx: -(m2.wins[1]!.snap), dy: 0)
    var inB = at.size == wasFrame.size
    if w <= b.width { inB = inB && at.minX >= b.minX && at.maxX <= b.maxX }
    if h <= b.height { inB = inB && at.minY >= b.minY && at.maxY <= b.maxY }
    check(inB, "random \(run): back into a new area \(b): \(at)")
    m2.wins[1]!.own = took.offsetBy(dx: CGFloat(Int.random(in: 3...50, using: &rng)), dy: 0)
    var moved = b2
    check(DWL.bringBack(&moved, area: a, on: &m2) == DWL.BackCount(of: 1, moved: 1), "random \(run): moved on the Mac: left")
}

print("virtual-desktop: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
