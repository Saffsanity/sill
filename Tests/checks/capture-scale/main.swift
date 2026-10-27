// CaptureScale and InputLanding (Sources/SillHost/CaptureScale.swift): the pixel scale a capture runs
// at, the Resolution knob held to the display's own (2026-10-27: on an external 2560×1440 display at
// 1x, a window picked at Retina filled the top-left quarter of the picture, and the Desktop was
// captured at 5120×2880), and where a device's position lands on the Mac: at most on the source's
// last pixel row and column (the picture's bottom edge was posted at the row past the display's last).
// Compiled with Sources/SillHost/CaptureScale.swift alone (run.sh):
//   swiftc -O Sources/SillHost/CaptureScale.swift Tests/checks/capture-scale/main.swift
// The rule case by case (Sill.log's own sizes among them), then random knobs, displays, rectangles
// and fractions against its properties.
import CoreGraphics
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { print("ok   \(what())") } else { failures += 1; print("FAIL \(what())") }
}
typealias C = CaptureScale
typealias L = InputLanding

/// WindowCapture.swift's, which needs ScreenCaptureKit and so is not compiled here: HEVC wants even
/// dimensions.
func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) & ~1 }
/// What `select` asks ScreenCaptureKit for: the content's points at the capture's pixel scale.
func size(_ w: CGFloat, _ h: CGFloat, knob: CGFloat, display: CGFloat?) -> String {
    let s = C.effective(knob: knob, displayScale: display)
    return "\(evenPixels(w * s))×\(evenPixels(h * s))"
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
check(size(1117, 610, knob: 2, display: 1) == "1116×610",
      "the window on the 1x display: 1116×610 (Sill.log: 2234×1220, the window in its top-left quarter)")
check(size(2234, 1220, knob: 2, display: 1) == "2234×1220", "a 2234×1220-point window on the 1x display (Sill.log: 4468×2440)")
check(size(1512, 982, knob: 2, display: 2) == "3024×1964" && size(1512, 982, knob: 1, display: 2) == "1512×982",
      "the Retina Desktop as before: 3024×1964 at Retina, 1512×982 at Standard")
check(size(1091, 753, knob: 2, display: 2) == "2182×1506", "a window on the Retina display as before (Sill.log: 2182×1506)")
check(size(2234, 1220, knob: 2, display: C.virtualDisplay) == "4468×2440" && size(1117, 610, knob: 2, display: C.virtualDisplay) == "2234×1220",
      "staged windows as before (Sill.log: 4468×2440 and 2234×1220 of the virtual display)")

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

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
