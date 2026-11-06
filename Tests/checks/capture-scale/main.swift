// CaptureScale and InputLanding (Sources/SillHost/CaptureScale.swift): the pixel scale a capture runs
// at, the Resolution knob held to the display's own (2026-10-27: on an external 2560×1440 display at
// 1x, a window picked at Retina filled the top-left quarter of the picture, and the Desktop was
// captured at 5120×2880); a window's capture size, an odd side rounded up to even where it is drawn
// 1:1 (a 1117-point window on a 1x display was asked 1116 pixels and shrunk into them), and the
// restart rule that compares the same size (no restart at every poll); and where a device's position
// lands on the Mac: at most on the source's last pixel row and column (the picture's bottom edge was
// posted at the row past the display's last); and the size of Sill's virtual display, no side under 800
// points (an iPhone's 754×784 display came up at 1x, five times in Sill.log).
// Compiled with Sources/SillHost/CaptureScale.swift alone (run.sh):
//   swiftc -O Sources/SillHost/CaptureScale.swift Tests/checks/capture-scale/main.swift
// The rule case by case (Sill.log's own sizes among them), then random knobs, displays, windows,
// rectangles and fractions against its properties.
import CoreGraphics
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { print("ok   \(what())") } else { failures += 1; print("FAIL \(what())") }
}
typealias C = CaptureScale
typealias L = InputLanding

/// What `select` asks ScreenCaptureKit for a display, a staged window's crop of Sill's virtual display
/// or the test pattern: the content's points at the capture's pixel scale, down to even (`evenPixels`,
/// CaptureScale.swift's since the window rule; ScreenCaptureKit scales a display to fill any buffer).
func size(_ w: CGFloat, _ h: CGFloat, knob: CGFloat, display: CGFloat?) -> String {
    let s = C.effective(knob: knob, displayScale: display)
    return "\(evenPixels(w * s))×\(evenPixels(h * s))"
}
/// What `select` asks for a window in regular mode (CaptureScale.windowSize).
func window(_ w: CGFloat, _ h: CGFloat, knob: CGFloat, display: CGFloat?) -> String {
    let s = C.windowSize(CGSize(width: w, height: h), knob: knob, displayScale: display)
    return "\(s.width)×\(s.height)"
}
/// The part of each side of the buffer a window fills: ScreenCaptureKit draws it at its display's own
/// scale and never scales it up (the bug: a 2x buffer of a window on a 1x display, a half each way).
func fill(capture: CGFloat, display: CGFloat) -> CGFloat { min(1, display / capture) }

// MARK: - The capture's pixel scale

// Noah's display, 2026-10-27: an external 2560×1440 at 1x, ScreenCaptureKit's "scale 1.0".
check(C.effective(knob: 2, displayScale: 1) == 1, "Retina on a 1x display captures at 1x")
check(C.effective(knob: 1, displayScale: 1) == 1, "Standard on a 1x display captures at 1x")
check(C.effective(knob: 2, displayScale: 2) == 2, "Retina on a 2x display captures at 2x, as before")
check(C.effective(knob: 1, displayScale: 2) == 1, "Standard on a 2x display captures at 1x, as before")
check(C.effective(knob: 2, displayScale: 3) == 2, "never more than the knob, whatever the display")
check(C.effective(knob: 2, displayScale: 1.5) == 1.5, "a display's own scale between the two is its own")
// The software encoder's knob is 1 at most (StreamCoordinator.captureScale).
check(C.effective(knob: 1, displayScale: 1) == 1 && C.effective(knob: 1, displayScale: 2) == 1, "the software encoder's 1x on either display")
// The test pattern has no display: the knob, as before (1512×949 × knob).
check(C.effective(knob: 2, displayScale: nil) == 2 && C.effective(knob: 1, displayScale: nil) == 1, "no display (the test pattern): the knob")
check(size(1512, 949, knob: 2, display: nil) == "3024×1898" && size(1512, 949, knob: 1, display: nil) == "1512×948",
      "the test pattern's sizes as before: 3024×1898 at Retina, 1512×948 at Standard")
// A scale that is none keeps the knob.
for bad: CGFloat in [0, -1, -2, .nan, .infinity, -.infinity] {
    check(C.effective(knob: 2, displayScale: bad) == 2 && C.effective(knob: 1, displayScale: bad) == 1,
          "a display scale of \(bad) is none: the knob")
}
// Sill's own virtual display, made at 2x: a staged window captures at the knob, as before.
check(C.virtualDisplay == 2, "Sill's virtual display is 2x")
check(C.effective(knob: 2, displayScale: C.virtualDisplay) == 2 && C.effective(knob: 1, displayScale: C.virtualDisplay) == 1,
      "a staged window captures at the knob")

// ScreenCaptureKit's `pointPixelScale` (a Float) as a display scale.
check(C.displayScale(pointPixelScale: 1) == 1 && C.displayScale(pointPixelScale: 2) == 2, "pointPixelScale 1.0 and 2.0 read as 1 and 2")
for bad: Float in [0, -2, .nan, .infinity, -.infinity] {
    check(C.displayScale(pointPixelScale: bad) == nil, "pointPixelScale \(bad) is no scale")
}

// Sill.log's own captures, 2026-10-27 and before: what was asked, and what is asked now.
check(size(2560, 1440, knob: 2, display: 1) == "2560×1440",
      "the 1x Desktop: 2560×1440 (Sill.log: 5120×2880, four times the pixels, upscaled)")
check(window(1117, 610, knob: 2, display: 1) == "1118×610",
      "the window on the 1x display: 1118×610, drawn whole (Sill.log: 2234×1220, the window in its top-left quarter; #233: 1116×610, shrunk)")
check(window(2234, 1220, knob: 2, display: 1) == "2234×1220", "a 2234×1220-point window on the 1x display (Sill.log: 4468×2440)")
check(size(1512, 982, knob: 2, display: 2) == "3024×1964" && size(1512, 982, knob: 1, display: 2) == "1512×982",
      "the Retina Desktop as before: 3024×1964 at Retina, 1512×982 at Standard")
check(window(1091, 753, knob: 2, display: 2) == "2182×1506", "a window on the Retina display as before (Sill.log: 2182×1506)")
check(size(2234, 1220, knob: 2, display: C.virtualDisplay) == "4468×2440" && size(1117, 610, knob: 2, display: C.virtualDisplay) == "2234×1220",
      "staged windows as before (Sill.log: 4468×2440 and 2234×1220 of the virtual display)")

// MARK: - A window's capture size: an odd side rounds up where the window is drawn 1:1

// ScreenCaptureKit draws a window at its display's own scale into the top-left of the buffer and only
// scales it down (`scalesToFit` false). A buffer a pixel short shrinks the window's pixels into one
// fewer; a pixel more leaves one black column (or row) past it and the window 1:1.
/// How a window `pixels` wide (at its display's scale) is drawn into a buffer `buffer` wide: its scale
/// (1: 1:1; below 1: shrunk) and the black past it.
func drawn(_ pixels: CGFloat, into buffer: Int) -> (scale: CGFloat, black: CGFloat) {
    let s = min(1, CGFloat(buffer) / pixels)
    return (s, CGFloat(buffer) - pixels * s)
}
/// Before this rule: every side down to even (`evenPixels` at the capture's scale).
func before(_ points: CGFloat, knob: CGFloat, display: CGFloat?) -> Int {
    evenPixels(points * C.effective(knob: knob, displayScale: display))
}

// Sill.log's odd windows at Aa 1x on the 1x display (2026-10-27), each now drawn whole.
for (w, h, now, then) in [(CGFloat(1117), CGFloat(610), "1118×610", "1116×610"), (818, 565, "818×566", "818×564"),
                          (728, 535, "728×536", "728×534"), (377, 235, "378×236", "376×234")] {
    check(window(w, h, knob: 2, display: 1) == now && "\(before(w, knob: 2, display: 1))×\(before(h, knob: 2, display: 1))" == then,
          "a \(Int(w))×\(Int(h))-point window on a 1x display asks \(now) (it was \(then))")
    let s = C.windowSize(CGSize(width: w, height: h), knob: 2, displayScale: 1)
    let across = drawn(w, into: s.width), down = drawn(h, into: s.height)
    check(across.scale == 1 && down.scale == 1 && across.black <= 1 && down.black <= 1,
          "\(Int(w))×\(Int(h)) drawn 1:1, at most one black column and row past it (\(across.black), \(down.black))")
}
check(drawn(1117, into: 1116).scale < 1 && drawn(1117, into: 1118) == (1, 1),
      "the blur, as ScreenCaptureKit draws it: 1117 columns shrunk into 1116 (#233); into 1118, 1:1 and one black column")
check(C.windowPixels(1117, knob: 1, displayScale: 1) == 1118 && C.windowPixels(611, knob: 1, displayScale: 1) == 612,
      "Standard on a 1x display: the same as Retina there, an odd side up")
check(C.windowPixels(1116, knob: 2, displayScale: 1) == 1116 && C.windowPixels(2560, knob: 2, displayScale: 1) == 2560,
      "an even side on a 1x display as it is: no black column for nothing")
// The software encoder (knob 1) on either display: 1x, so 1:1 on a 1x display, scaled down on a 2x one.
check(window(1117, 611, knob: 1, display: 1) == "1118×612", "the software encoder on a 1x display: drawn whole")
// A 2x display: whole points are always even; a half point rounds up the same way.
check(window(1117, 610, knob: 2, display: 2) == "2234×1220", "a 2x display at Retina as before: 2234×1220")
check(C.windowPixels(1117.5, knob: 2, displayScale: 2) == 2236 && before(1117.5, knob: 2, display: 2) == 2234,
      "a window at a half point on a 2x display: 2236, drawn whole (it was 2234, shrunk)")
check(C.windowPixels(610.5, knob: 2, displayScale: 2) == 1222, "a half point's height on a 2x display: 1222")
// Held below its display's scale, the window is scaled down whatever the buffer: down to even, as before.
check(window(1117, 611, knob: 1, display: 2) == "1116×610", "Standard on a 2x display as before: 1116×610 (scaled down anyway)")
check(C.windowPixels(1117.5, knob: 2, displayScale: 3) == 2234, "a 3x display at Retina: held below it, down to even (2234)")
// A display between the two at its own scale: 1:1, up.
check(C.windowPixels(1117, knob: 2, displayScale: 1.5) == 1676 && C.windowPixels(744.3, knob: 2, displayScale: 1.5) == 1118,
      "a 1.5x display at its own scale: 1675.5 pixels ask 1676, 1116.45 ask 1118 (never fewer than the window's)")
// No display scale (none, or one that is none): the knob, down to even, as before.
for bad: CGFloat? in [nil, 0, -1, .nan, .infinity] {
    check(C.windowPixels(1117, knob: 1, displayScale: bad) == 1116 && C.windowPixels(1117, knob: 2, displayScale: bad) == 2234,
          "a window with display scale \(bad.map { "\($0)" } ?? "none"): the knob, down to even, as before")
}
// A product's rounding is no reason for a black column.
check(C.windowPixels(1116.0000001, knob: 1, displayScale: 1) == 1116, "1116.0000001 pixels: 1116, no black column for a rounding")
check(C.windowPixels(1117.0000001, knob: 1, displayScale: 1) == 1118, "1117.0000001 pixels: 1118")
check(C.windowPixels(1116.9999999, knob: 1, displayScale: 1) == 1118, "1116.9999999 pixels count as 1117: 1118")
check(C.windowPixels(0, knob: 2, displayScale: 1) == 0, "a window of no width: 0")
check(C.windowSize(CGSize(width: 1117, height: 610), knob: 2, displayScale: 1) == (1118, 610)
      && C.windowSize(CGSize(width: 610, height: 1117), knob: 2, displayScale: 1) == (610, 1118), "width and height each their own side")

// The restart rule (`windowsChanged`, each catalog poll): the size `select` would ask for now, by the
// same rule, against the encoder's.
let oddWindow = CGSize(width: 1117, height: 610)
let started = C.windowSize(oddWindow, knob: 2, displayScale: 1)
check(!C.windowNeedsRestart(encoder: started, points: oddWindow, knob: 2, displayScale: 1),
      "a window whose odd side was rounded up: no restart at the next poll (1118×610 for 1117×610)")
check(before(1117, knob: 2, display: 1) != started.width,
      "the comparison before the rule (down to even) against that encoder: 1116 against 1118, a restart at every poll")
check(!C.windowNeedsRestart(encoder: started, points: CGSize(width: 1118, height: 610), knob: 2, displayScale: 1),
      "1117 to 1118 points: within the rounding, no restart (the buffer holds it whole)")
check(C.windowNeedsRestart(encoder: started, points: CGSize(width: 1119, height: 610), knob: 2, displayScale: 1),
      "1117 to 1119 points: a restart, at 1120")
check(C.windowNeedsRestart(encoder: started, points: CGSize(width: 1117, height: 611), knob: 2, displayScale: 1),
      "610 to 611 points high: a restart, at 612")
check(C.windowNeedsRestart(encoder: started, points: oddWindow, knob: 2, displayScale: 2),
      "the window on a 2x display now: a restart, at 2234×1220")
// Aa asked 1116 and the app kept 1117 (its own size steps): the encoder was started at what the window
// is, and the polls agree with it.
check(!C.windowNeedsRestart(encoder: C.windowSize(oddWindow, knob: 2, displayScale: 1), points: oddWindow, knob: 2, displayScale: 1),
      "a window that keeps an odd size it was not asked for: no restart at any poll")
let standard2x = C.windowSize(CGSize(width: 1117, height: 611), knob: 1, displayScale: 2)
check(standard2x == (1116, 610) && !C.windowNeedsRestart(encoder: standard2x, points: CGSize(width: 1116, height: 610), knob: 1, displayScale: 2),
      "Standard on a 2x display as before: 1116×610 for 1117×611 and for 1116×610, no restart between them")

// What the picture shows: before, a window drawn at 1x into a 2x buffer filled a half each way.
check(fill(capture: 2, display: 1) == 0.5, "the bug as ScreenCaptureKit draws it: a quarter of the picture (a half each way)")
for knob: CGFloat in [1, 2] {
    for display: CGFloat in [1, 2] {
        let e = C.effective(knob: knob, displayScale: display)
        check(fill(capture: e, display: display) == 1, "knob \(knob)x on a \(display)x display: the window fills the picture")
    }
}

// The capture line's words.
check(C.words(knob: 2, displayScale: 1) == "capturing at 1x, the display's own (2x asked)", "the words on a 1x display at Retina")
check(C.words(knob: 2, displayScale: 2) == "capturing at 2x", "the words on a 2x display at Retina")
check(C.words(knob: 1, displayScale: 2) == "capturing at 1x", "Standard on a 2x display: nothing held down")
check(C.words(knob: 1, displayScale: 1) == "capturing at 1x", "Standard on a 1x display: nothing held down")
check(C.words(knob: 2, displayScale: nil) == "capturing at 2x", "no display: the knob")
check(C.times(1) == "1x" && C.times(2) == "2x" && C.times(1.5) == "1.5x", "1x, 2x and 1.5x")

// One pixel of a display, in points.
check(C.pixel(displayScale: 1) == 1 && C.pixel(displayScale: 2) == 0.5, "a pixel is a point at 1x, half a point at 2x")
check(C.pixel(displayScale: nil) == 1, "no scale: a point")
for bad: CGFloat in [0, -1, .nan, .infinity] {
    check(C.pixel(displayScale: bad) == 1, "a scale of \(bad) is none: a point")
}

// MARK: - Where a device's position lands

/// Before: `minY + y × height`, the row past the last for y = 1.
func old(_ x: Double, _ y: Double, _ r: CGRect) -> CGPoint {
    CGPoint(x: r.minX + CGFloat(x) * r.width, y: r.minY + CGFloat(y) * r.height)
}
/// PointerControl.fraction's inside test (Sources/SillHost/PointerControl.swift): the far edges are out.
func inside(_ p: CGPoint, _ r: CGRect) -> Bool {
    let x = (p.x - r.minX) / r.width, y = (p.y - r.minY) / r.height
    return x >= 0 && x < 1 && y >= 0 && y < 1
}

// Noah's Desktop: 2560×1440 points at 1x. A drag to the bottom edge of the picture is y = 1 (the
// portrait trackpad's cursor stops at 1, the iPad's pointer and a Pencil are held to the edge).
let desktop = CGRect(x: 0, y: 0, width: 2560, height: 1440)
check(old(0.5, 1, desktop).y == 1440 && !desktop.contains(old(0.5, 1, desktop)) && !inside(old(0.5, 1, desktop), desktop),
      "before: the bottom edge was posted at y = 1440, the row past the display's last, outside it")
check(L.point(x: 0.5, y: 1, in: desktop, displayScale: 1) == CGPoint(x: 1280, y: 1439), "the bottom edge lands on the last row, y = 1439")
check(L.point(x: 1, y: 0.5, in: desktop, displayScale: 1) == CGPoint(x: 2559, y: 720), "the right edge lands on the last column, x = 2559")
check(L.point(x: 1, y: 1, in: desktop, displayScale: 1) == CGPoint(x: 2559, y: 1439), "the bottom-right corner, (2559, 1439)")
check(L.point(x: 0, y: 0, in: desktop, displayScale: 1) == .zero, "the top-left corner, (0, 0)")
check(L.point(x: 0.5, y: 0.5, in: desktop, displayScale: 1) == CGPoint(x: 1280, y: 720), "the middle, as before")
let edge = L.point(x: 0.37, y: 1, in: desktop, displayScale: 1)
check(desktop.contains(edge) && inside(edge, desktop) && Int(edge.y) == 1439, "the edge's landing is on the display, in its last pixel row")

// A Retina display: the last pixel row is half a point up.
let retina = CGRect(x: 0, y: 0, width: 1512, height: 982)
check(L.point(x: 1, y: 1, in: retina, displayScale: 2) == CGPoint(x: 1511.5, y: 981.5), "a 2x display's last pixel: (1511.5, 981.5)")
let r2 = L.point(x: 0.2, y: 1, in: retina, displayScale: 2)
check(Int((r2.y * 2).rounded(.down)) == 1963 && inside(r2, retina), "on a 2x display the bottom edge is pixel row 1963 of 1964")
check(L.point(x: 0.25, y: 0.5, in: retina, displayScale: 2) == CGPoint(x: 378, y: 491), "inside, as before")

// Displays away from the origin: one to the left, one above.
let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
check(L.point(x: 0, y: 0, in: left, displayScale: 1) == CGPoint(x: -1920, y: 0), "a display to the left: its top-left")
check(L.point(x: 1, y: 1, in: left, displayScale: 1) == CGPoint(x: -1, y: 1079), "a display to the left: its last column is -1, not 0 (the main display's first)")
let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
check(L.point(x: 0.5, y: 1, in: above, displayScale: 1) == CGPoint(x: 1280, y: -1), "a display above: its last row is -1, not 0 (the display below's first)")

// A window (regular mode): its last row and column, never what lies past it.
let window = CGRect(x: 326, y: 220, width: 1117, height: 610)
check(L.point(x: 1, y: 1, in: window, displayScale: 1) == CGPoint(x: 1442, y: 829), "a window's bottom-right lands on it, (1442, 829)")
check(!window.contains(old(1, 1, window)) && window.contains(L.point(x: 1, y: 1, in: window, displayScale: 1)),
      "before, a window's bottom-right was past it; now on it")
let frac = CGRect(x: 100.5, y: 50.25, width: 800, height: 600)
check(L.point(x: 1, y: 1, in: frac, displayScale: 2) == CGPoint(x: 900, y: 649.75), "a window at half points on a 2x display: half a point in")
// A window staged on Sill's virtual display (2x): its crop.
let staged = CGRect(x: -2234, y: 30, width: 1117, height: 610)
check(L.point(x: 1, y: 1, in: staged, displayScale: C.virtualDisplay) == CGPoint(x: -1117.5, y: 639.5), "a staged window's crop: half a point in")

// The test pattern (no display): a point in.
let pattern = CGRect(x: 0, y: 0, width: 1512, height: 949)
check(L.point(x: 1, y: 1, in: pattern, displayScale: nil) == CGPoint(x: 1511, y: 948), "the test pattern: (1511, 948)")
check(L.point(x: 0.5, y: 0.5, in: pattern, displayScale: nil) == CGPoint(x: 756, y: 474.5), "the test pattern's middle, as before")

// Fractions out of 0…1 (no device sends them; a test client can): held to the rectangle.
check(L.point(x: -0.2, y: -3, in: desktop, displayScale: 1) == .zero, "below 0: the first row and column")
check(L.point(x: 1.7, y: 40, in: desktop, displayScale: 1) == CGPoint(x: 2559, y: 1439), "over 1: the last row and column")
check(L.point(x: .nan, y: .nan, in: desktop, displayScale: 1) == .zero, "NaN: the first row and column")
check(L.point(x: .infinity, y: -.infinity, in: desktop, displayScale: 1) == CGPoint(x: 2559, y: 0), "infinities: the edges")
check(L.unit(-1) == 0 && L.unit(0.25) == 0.25 && L.unit(1) == 1 && L.unit(2) == 1 && L.unit(.nan) == 0, "the fraction held to 0…1")
// A rectangle narrower than a pixel keeps its origin, never left of or above it.
let thin = CGRect(x: 10, y: 20, width: 0.3, height: 0.4)
check(L.point(x: 1, y: 1, in: thin, displayScale: 1) == CGPoint(x: 10, y: 20), "a rectangle narrower than a pixel: its origin")
check(L.point(x: 1, y: 1, in: CGRect(x: 5, y: 5, width: 0, height: 0), displayScale: 2) == CGPoint(x: 5, y: 5), "an empty rectangle: its origin")

// MARK: - Random knobs, displays, rectangles and fractions

var seed: UInt64 = 0x5111_CA9E
func next() -> UInt64 {   // a seeded generator, so a failure repeats
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return seed >> 11
}
func unitRandom() -> Double { Double(next() % 1_000_001) / 1_000_000 }
func pick<T>(_ xs: [T]) -> T { xs[Int(next() % UInt64(xs.count))] }

var ruleBad = 0, upscaled = 0, landingOff = 0, outside = 0, notMonotonic = 0, changedInside = 0, edgeNotLast = 0
for _ in 0..<20_000 {
    let knob = pick([CGFloat(1), 2])
    let display: CGFloat? = pick([nil, 1, 2, 3, 1.5, 0, -1, .nan, .infinity])
    let e = C.effective(knob: knob, displayScale: display)
    let valid = display.map { $0.isFinite && $0 > 0 } ?? false
    if e > knob || (valid && e > display!) || (!valid && e != knob) || !(e == knob || e == display) { ruleBad += 1 }
    if valid, fill(capture: e, display: display!) < 1 { upscaled += 1 }

    let scale: CGFloat? = pick([nil, 1, 2])
    let px = C.pixel(displayScale: scale)
    let r = CGRect(x: CGFloat(Int(next() % 10_001) - 5_000) / pick([CGFloat(1), 2, 4]),
                   y: CGFloat(Int(next() % 10_001) - 5_000) / pick([CGFloat(1), 2, 4]),
                   width: CGFloat(1 + Int(next() % 8_000)) / pick([CGFloat(1), 2]),
                   height: CGFloat(1 + Int(next() % 8_000)) / pick([CGFloat(1), 2]))
    // The last pixel column and row, or the origin for a rectangle narrower than a pixel.
    let lastX = max(r.minX, r.maxX - px), lastY = max(r.minY, r.maxY - px)
    let fx = unitRandom() * 2 - 0.5, fy = unitRandom() * 2 - 0.5
    let p = L.point(x: fx, y: fy, in: r, displayScale: scale)
    // On the rectangle, at most its last pixel row and column.
    if p.x < r.minX || p.y < r.minY || p.x > lastX || p.y > lastY { landingOff += 1 }
    if !r.contains(p) || !inside(p, r) { outside += 1 }
    // Away from the far edges, exactly where it landed before.
    let o = old(L.unit(fx), L.unit(fy), r)
    if o.x <= lastX, o.y <= lastY, o != p { changedInside += 1 }
    // Never backwards: a larger fraction lands no nearer the origin.
    let q = L.point(x: fx + 0.01, y: fy + 0.01, in: r, displayScale: scale)
    if q.x < p.x || q.y < p.y { notMonotonic += 1 }
    // The far edges land on the last pixel row and column.
    let corner = L.point(x: 1, y: 1, in: r, displayScale: scale)
    if corner != CGPoint(x: lastX, y: lastY) { edgeNotLast += 1 }
}
check(ruleBad == 0, "20,000 random knobs and displays: the knob held to a real display's own, else the knob (\(ruleBad) not)")
check(upscaled == 0, "a window always fills its picture: never captured above its display's scale (\(upscaled) not)")
check(landingOff == 0, "20,000 random rectangles and fractions: on the rectangle, at most its last pixel row and column (\(landingOff) not)")
check(outside == 0, "every landing is inside the rectangle and by PointerControl's test (\(outside) not)")
check(changedInside == 0, "away from the far edges a position lands where it did before (\(changedInside) moved)")
check(notMonotonic == 0, "a larger fraction never lands nearer the origin (\(notMonotonic))")
check(edgeNotLast == 0, "the far edges land on the last pixel row and column (\(edgeNotLast) not)")

// Random windows: whole, half and odd fractions of points, on displays of each scale, at each knob.
var notEven = 0, cut = 0, tooMuchBlack = 0, notAsBefore = 0, loopsAtOnce = 0, shrinks = 0, pollLoops = 0, restartsMissed = 0
for _ in 0..<20_000 {
    let knob = pick([CGFloat(1), 2])
    let display: CGFloat? = pick([nil, 1, 2, 3, 1.5, 0, .nan])
    let points = CGFloat(Int(next() % 4_000)) + pick([CGFloat(0), 0.5, 0.25, CGFloat(next() % 1_000) / 1_000])
    let p = C.windowPixels(points, knob: knob, displayScale: display)
    let e = C.effective(knob: knob, displayScale: display)
    let valid = display.map { $0.isFinite && $0 > 0 } ?? false
    if p < 0 || p % 2 != 0 { notEven += 1 }
    if valid, e == display! {
        // Drawn 1:1: the buffer holds the whole window, with at most one black column past its last.
        if CGFloat(p) < points * e - 0.001 { cut += 1 }
        if CGFloat(p) - points * e >= 2 { tooMuchBlack += 1 }
    } else if p != evenPixels(points * e) { notAsBefore += 1 }
    // A window a little larger never asks for fewer pixels.
    if C.windowPixels(points + 0.5, knob: knob, displayScale: display) < p { shrinks += 1 }
    // Right after a restart at a size, the same size never restarts again.
    let size = CGSize(width: points, height: CGFloat(Int(next() % 3_000)) + pick([CGFloat(0), 0.5]))
    if C.windowNeedsRestart(encoder: C.windowSize(size, knob: knob, displayScale: display), points: size, knob: knob, displayScale: display) {
        loopsAtOnce += 1
    }
}
// A model of `windowsChanged`: a window resized now and then by a few points, polled every 2 s; the
// encoder restarts only when the rule says so, at the size `select` asks for.
for _ in 0..<2_000 {
    let knob = pick([CGFloat(1), 2]), display: CGFloat? = pick([1, 2, 1.5])
    var size = CGSize(width: CGFloat(200 + Int(next() % 3_000)), height: CGFloat(200 + Int(next() % 2_000)))
    var encoder = C.windowSize(size, knob: knob, displayScale: display)
    for _ in 0..<20 {
        if next() % 3 == 0 {
            size.width += CGFloat(Int(next() % 5) - 2)
            size.height += CGFloat(Int(next() % 5) - 2)
        }
        let want = C.windowSize(size, knob: knob, displayScale: display)
        if C.windowNeedsRestart(encoder: encoder, points: size, knob: knob, displayScale: display) {
            encoder = want
            if C.windowNeedsRestart(encoder: encoder, points: size, knob: knob, displayScale: display) { pollLoops += 1 }
        } else if want != encoder { restartsMissed += 1 }
    }
}
check(notEven == 0, "20,000 random windows: every side even (\(notEven) not)")
check(cut == 0, "a window drawn 1:1 is never cut or shrunk: the buffer holds all its pixels (\(cut) not)")
check(tooMuchBlack == 0, "a window drawn 1:1 has at most one black column or row past it (\(tooMuchBlack) more)")
check(notAsBefore == 0, "a window not drawn 1:1 (held below its display, no display scale) asks what it asked before (\(notAsBefore) not)")
check(shrinks == 0, "a larger window never asks for fewer pixels (\(shrinks))")
check(loopsAtOnce == 0, "right after a restart, the same size never needs another (\(loopsAtOnce) would loop)")
check(pollLoops == 0 && restartsMissed == 0, "2,000 windows resized and polled 20 times: no restart loop, no change of size missed (\(pollLoops), \(restartsMissed))")

// MARK: - Sill's virtual display: no side under 800 points, which macOS kept at 2x

typealias V = VirtualDisplaySize
/// The display VirtualStage.ensureDisplay makes for an envelope (a copy of its arithmetic): the
/// envelope held, its height capped so the menu bar still fits under the ceiling, then the menu bar on
/// top (30 points on this Mac: Sill.log's "menu bar 30 pt").
func display(_ env: CGSize, menuBar: CGFloat = 30) -> CGSize {
    var e = V.clamp(env)
    e.height = min(e.height, V.maxSide - menuBar)
    return CGSize(width: e.width, height: e.height + menuBar)
}
/// Before 2026-10-27: the same with VirtualStage's old floor, 320 points.
func oldDisplay(_ env: CGSize, menuBar: CGFloat = 30) -> CGSize {
    let w = min(max(env.width, 320), 4096), h = min(min(max(env.height, 320), 4096), 4096 - menuBar)
    return CGSize(width: w, height: h + menuBar)
}
func envelope(_ w: CGFloat, _ h: CGFloat) -> CGSize { V.envelope(panel: CGSize(width: w, height: h), windowSize: .zero) }
func text(_ s: CGSize) -> String { "\(Int(s.width))×\(Int(s.height))" }

check(V.minSide == 800 && V.maxSide == 4096, "every side 800 to 4096 points")
// Sill.log's five displays at 1x: an iPhone held upright, its picture 377 (or 381) points wide.
check(text(oldDisplay(CGSize(width: 754, height: 754))) == "754×784" && text(oldDisplay(CGSize(width: 762, height: 762))) == "762×792",
      "before: an iPhone upright's envelope made a 754×784 (or 762×792) display, which macOS ran at 800×832 at 1x")
check(text(envelope(377, 235)) == "800×800" && text(display(envelope(377, 235))) == "800×830",
      "an iPhone 15 Pro upright (377×235): an 800×800 envelope, an 800×830 display")
check(text(display(envelope(381, 238))) == "800×830", "a 381-point picture: 800×830")
check(text(display(envelope(386, 241))) == "800×830" && text(display(envelope(374, 233))) == "800×830",
      "the 18 Pro's 386 and the 17e's 374 points upright: 800×830")
// Large enough already: the same display as before.
check(text(envelope(424, 265)) == "848×848" && text(display(envelope(424, 265))) == "848×878",
      "the Pro Max upright (424×265): 848×878, as before (Sill.log: up at 2x in 379 ms)")
check(text(envelope(1117, 610)) == "2234×2234" && text(display(envelope(1117, 610))) == "2234×2264",
      "the iPad's 1117×610 panel: 2234×2264, as before (Sill.log's most common, 2x)")
check(text(envelope(728, 535)) == "1456×1456" && text(display(envelope(728, 535))) == "1456×1486",
      "a 728×535 panel: 1456×1486, as before (2026-10-27, 2x beside a 1x main display)")
check(text(envelope(535, 728)) == text(envelope(728, 535)), "either orientation: the same envelope")
check(text(envelope(377.3, 235)) == "800×800" && text(envelope(450.2, 300)) == "901×901", "a fraction of a point rounds the side up")
// A window's own size when no viewport has come (the Mac's window as it is), held the same way.
check(text(V.envelope(panel: nil, windowSize: CGSize(width: 230, height: 408))) == "800×800",
      "no viewport: a small window's own size held to 800×800 (Calculator's 230×408)")
check(text(V.envelope(panel: nil, windowSize: CGSize(width: 1512, height: 949))) == "1512×949",
      "no viewport: a window larger than the floor keeps its own size")
check(text(V.envelope(panel: CGSize(width: 0, height: 0), windowSize: CGSize(width: 1000, height: 700))) == "1000×800",
      "a panel with no area counts as none: the window's 1000×700, its height held to 800")
check(text(V.envelope(panel: CGSize(width: -5, height: 300), windowSize: CGSize(width: 900, height: 900))) == "900×900",
      "a negative panel counts as none")
// The grow path's envelope (an app's minimum) and the ceiling.
check(text(V.clamp(CGSize(width: 754, height: 979))) == "800×979", "Sill.log's 754×979 display (2x then) is 800 wide now")
check(text(V.clamp(CGSize(width: 9000, height: 5000))) == "4096×4096", "the ceiling: 4096 points a side")
check(text(display(CGSize(width: 9000, height: 9000))) == "4096×4096", "at the ceiling the menu bar still fits under 4096")
check(text(envelope(3000, 2000)) == "4096×4096", "a panel too big for the ceiling: 4096")
// Never smaller than before: the floor only ever adds.
check(V.clamp(CGSize(width: 2234, height: 2234)) == CGSize(width: 2234, height: 2234), "a display over the floor is left as it is")

// Random panels, windows and menu bars: every display's side 800 or more (macOS kept every such
// display at 2x), at most the ceiling; a square envelope that holds the panel at Aa's smallest step,
// either way round; never smaller than the old rule's; the window's own size when there is no panel.
var under800 = 0, overCeiling = 0, notSquare = 0, panelDoesNotFit = 0, smallerThanBefore = 0, notMonotonicEnv = 0, noPanelWrong = 0
for _ in 0..<20_000 {
    let w = CGFloat(next() % 3_000) / pick([CGFloat(1), 2, 3]), h = CGFloat(next() % 3_000) / pick([CGFloat(1), 2, 3])
    let menuBar = pick([CGFloat(24), 30, 37, 40])
    let env = envelope(w, h)
    let d = display(env, menuBar: menuBar)
    if d.width < 800 || d.height < 800 { under800 += 1 }
    if d.width > 4096 || d.height > 4096 { overCeiling += 1 }
    if w > 0, h > 0 {
        if env.width != env.height { notSquare += 1 }
        let need = max(w, h) / 0.5
        if need <= 4096, env.width < need || env.height < need { panelDoesNotFit += 1 }
        if env.width < min(max(ceil(need), 320), 4096) { smallerThanBefore += 1 }
        let bigger = envelope(w + 1, h + 1)
        if bigger.width < env.width { notMonotonicEnv += 1 }
    }
    let own = CGSize(width: w * 2, height: h * 2)
    let byWindow = V.envelope(panel: nil, windowSize: own)
    if byWindow != CGSize(width: min(max(own.width, 800), 4096), height: min(max(own.height, 800), 4096)) { noPanelWrong += 1 }
}
check(under800 == 0, "20,000 random panels and menu bars: every display side 800 points or more (\(under800) not)")
check(overCeiling == 0, "every display within 4096 points, the menu bar included (\(overCeiling) not)")
check(notSquare == 0, "a panel's envelope is a square (\(notSquare) not)")
check(panelDoesNotFit == 0, "the panel fits at Aa's smallest step, either way round (\(panelDoesNotFit) not)")
check(smallerThanBefore == 0, "never smaller than before (\(smallerThanBefore))")
check(notMonotonicEnv == 0, "a larger panel never gets a smaller envelope (\(notMonotonicEnv))")
check(noPanelWrong == 0, "no panel: the window's own size, held to 800…4096 (\(noPanelWrong) not)")

// MARK: - The window's size on Sill's virtual display: held to 1…65536 points, the most a host takes

/// Before 2026-10-29 (VirtualStage.windowSize, a copy): the panel ÷ the scale, unheld, so a viewport
/// of 1e300 points, or a scale of 1e-300, gave a side no Int holds, and the "insists on …" line's
/// Int() trapped (security scan, finding 4).
func oldWindowSize(panel: CGSize?, scale: CGFloat?, own: CGSize) -> CGSize {
    guard let panel, panel.width > 0, panel.height > 0 else { return own }
    let s = (scale ?? 1) > 0 ? (scale ?? 1) : 1
    return CGSize(width: (panel.width / s).rounded(), height: (panel.height / s).rounded())
}
/// Int() of a side traps: no Int holds it.
func traps(_ s: CGSize) -> Bool {
    Int(exactly: Double(s.width).rounded(.towardZero)) == nil || Int(exactly: Double(s.height).rounded(.towardZero)) == nil
}
let ownSize = CGSize(width: 640, height: 480)
func staged(_ w: CGFloat, _ h: CGFloat, _ s: CGFloat?) -> CGSize { V.windowSize(panel: CGSize(width: w, height: h), scale: s, own: ownSize) }

check(text(staged(1117, 610, 1)) == "1117×610" && text(staged(1117, 610, 0.5)) == "2234×1220",
      "the iPad's 1117×610 panel: 1117×610 at Aa 1x, 2234×1220 at 0.5x, as before")
check(text(staged(1117, 610, 1.5)) == "745×407" && text(staged(377, 235, 0.5)) == "754×470",
      "1.5x rounds to whole points (745×407), an iPhone upright at 0.5x 754×470, as before")
check(text(staged(1117, 610, nil)) == "1117×610", "no scale (Aa never touched) counts as 1")
for bad: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
    check(text(staged(1117, 610, bad)) == "1117×610", "a scale of \(bad) counts as 1")
}
check(V.windowSize(panel: nil, scale: 1, own: ownSize) == ownSize, "no viewport yet: the window's own size, as before")
for (w, h) in [(CGFloat(0), CGFloat(610)), (1117, 0), (-5, 610), (.nan, 610), (1117, .infinity), (-.infinity, 610)] {
    check(V.windowSize(panel: CGSize(width: w, height: h), scale: 1, own: ownSize) == ownSize,
          "a panel of \(w)×\(h) counts as none: the window's own size")
}
// The scan's viewport and its kin: before, a size no Int holds; now the ceiling.
check(V.maxWindowSide == 65536, "the ceiling: 65536 points a side, the largest viewport a host takes (16384 points at 0.25)")
check(traps(oldWindowSize(panel: CGSize(width: 1e300, height: 1e300), scale: 1, own: ownSize)) && text(staged(1e300, 1e300, 1)) == "65536×65536",
      "1e300 points: before 1e300, which the \"insists on\" line's Int() trapped on; now 65536×65536")
check(traps(oldWindowSize(panel: CGSize(width: 1000, height: 1000), scale: 1e-300, own: ownSize)) && text(staged(1000, 1000, 1e-300)) == "65536×65536",
      "1000 points at a scale of 1e-300: before 1e303; now 65536×65536")
check(oldWindowSize(panel: CGSize(width: 1e300, height: 1e300), scale: 1e-300, own: ownSize).width.isInfinite
      && text(staged(1e300, 1e300, 1e-300)) == "65536×65536", "1e300 at 1e-300: before infinite; now 65536×65536")
check(text(staged(16384, 16384, 0.25)) == "65536×65536" && staged(16384, 16384, 0.25) == oldWindowSize(panel: CGSize(width: 16384, height: 16384), scale: 0.25, own: ownSize),
      "the largest viewport a host takes (16384 at 0.25): 65536×65536, as before")
check(text(staged(1, 1, 4)) == "1×1" && oldWindowSize(panel: CGSize(width: 1, height: 1), scale: 4, own: ownSize) == .zero,
      "the smallest (1 point at 4x, a quarter point): 1×1, where it was 0×0")
// A panel past the display keeps its size, so its shape: the placement fits the window to the display
// (VirtualStage.prepare's `dest`), and a full-screen window's crop takes this size's shape. Held at the
// display's 4096 (the review of finding 4), a 2560×1400 panel at 0.5x was asked 4096×2800, 1.46:1 for a
// 1.83:1 panel, and a full-screen video's crop came out that shape, black bars on the device.
check(text(staged(2560, 1400, 0.5)) == "5120×2800" && text(staged(5000, 300, 1)) == "5000×300",
      "a panel past the display, an iPad's Stage Manager window at 0.5x (5120×2800) or 5000×300 at 1x: as asked, the panel's shape kept")
check(text(staged(1e5, 300, 0.25)) == "65536×1200", "each side held on its own")

// Every viewport a host takes (ViewportBounds: each side 1 to 16384 points, a scale 0.25 to 4 or none):
// the size it was before the hold, a side under half a point aside (1, not 0), so the same shape.
var takenNotAsBefore = 0
for _ in 0..<50_000 {
    let w = 1 + CGFloat(next() % 1_638_301) / 100, h = 1 + CGFloat(next() % 1_638_301) / 100   // 1 to 16384
    let s: CGFloat? = next() % 2 == 0 ? pick([nil, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 4]) : 0.25 + CGFloat(next() % 3_751) / 1_000
    let then = oldWindowSize(panel: CGSize(width: w, height: h), scale: s, own: ownSize)
    let now = V.windowSize(panel: CGSize(width: w, height: h), scale: s, own: ownSize)
    if now != CGSize(width: max(then.width, 1), height: max(then.height, 1)) { takenNotAsBefore += 1 }
}
check(takenNotAsBefore == 0, "50,000 viewports a host takes: each window asked for as before (\(takenNotAsBefore) not)")

// Random panels and scales, real and hostile: every size finite, 1 to 65536 points or the window's own,
// never one Int() traps on, and the same as before wherever before was already within 1…65536.
var stageUnheld = 0, stageNotAsBefore = 0, stageNotOwn = 0
let wildSides: [CGFloat] = [0, -1, 0.3, 1, 4096, 4097, 16384, 16385, 65536, 65537, 1e18, 1e300, .nan, .infinity, -.infinity]
let wildScales: [CGFloat?] = [nil, 0, -1, 1e-300, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 4, 1e300, .nan, .infinity]
for _ in 0..<20_000 {
    let w: CGFloat = next() % 3 == 0 ? pick(wildSides) : CGFloat(next() % 3_000) / pick([CGFloat(1), 2, 3])
    let h: CGFloat = next() % 3 == 0 ? pick(wildSides) : CGFloat(next() % 3_000) / pick([CGFloat(1), 2, 3])
    let s: CGFloat? = pick(wildScales)
    let panel = CGSize(width: w, height: h)
    let now = V.windowSize(panel: panel, scale: s, own: ownSize)
    if w.isFinite, h.isFinite, w > 0, h > 0 {
        if traps(now) || now.width < 1 || now.width > 65536 || now.height < 1 || now.height > 65536 { stageUnheld += 1 }
        let then = oldWindowSize(panel: panel, scale: s, own: ownSize)
        if then.width >= 1, then.width <= 65536, then.height >= 1, then.height <= 65536, then != now { stageNotAsBefore += 1 }
    } else if now != ownSize { stageNotOwn += 1 }
}
check(stageUnheld == 0, "20,000 random panels and scales: every window 1 to 65536 points a side, never a size Int() traps on (\(stageUnheld) not)")
check(stageNotAsBefore == 0, "wherever the old size was within 1…65536, the same as before (\(stageNotAsBefore) not)")
check(stageNotOwn == 0, "a panel whose sides are not positive numbers: the window's own size (\(stageNotOwn) not)")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
