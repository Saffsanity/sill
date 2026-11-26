import CoreGraphics

// PictureFit: the picture one for one where it is the pane's own pixels less a hairline (an iPhone's pixel-for-pixel
// Virtual Desktop, 2026-11-25), else aspect-fit in the pane's middle as `resizeAspect` draws it (every picture before).

var checks = 0
var failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { return }
    failures += 1
    if failures <= 30 { print("FAIL: \(what())") }
}
func pane(_ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: 0, y: 0, width: w, height: h) }
func px(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
func near(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 1e-6 && abs(a.minY - b.minY) < 1e-6 && abs(a.width - b.width) < 1e-6 && abs(a.height - b.height) < 1e-6
}
/// Aspect-fit in the middle, as AVSampleBufferDisplayLayer's resizeAspect draws it (the rule before 2026-11-25).
func aspectFit(_ b: CGRect, _ v: CGSize) -> CGRect {
    let s = min(b.width / v.width, b.height / v.height)
    let w = v.width * s, h = v.height * s
    return CGRect(x: b.minX + (b.width - w) / 2, y: b.minY + (b.height - h) / 2, width: w, height: h)
}

// An iPhone 15 Pro (3 pixels a point): its Virtual Desktop pixel for pixel with Full Screen, the spare pixel of an odd
// side a hairline at the right or bottom; with its controls showing grown to the least macOS keeps at 2x (540 points a
// side, Noah's probes P3 and P4, 2026-11-26), so fitted as before.
let fsUp = PictureFit.rect(in: pane(393, 793), videoSize: px(1178, 2378), screenScale: 3)
check(PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1178, 2378), screenScale: 3)
      && near(fsUp, CGRect(x: 0, y: 0, width: 1178.0 / 3, height: 2378.0 / 3)),
      "upright with Full Screen: 1178×2378 in 1179×2379 px, one for one from the top-left (\(fsUp))")
check(PictureFit.oneToOne(in: pane(734, 393), videoSize: px(2202, 1178), screenScale: 3), "on its side with Full Screen: 2202×1178 in 2202×1179")
check(PictureFit.oneToOne(in: pane(718, 299), videoSize: px(2154, 896), screenScale: 3), "a picture one pixel short of its pane: 2154×896 in 2154×897")
check(!PictureFit.oneToOne(in: pane(718, 299), videoSize: px(2594, 1080), screenScale: 3)
      && near(PictureFit.rect(in: pane(718, 299), videoSize: px(2594, 1080), screenScale: 3), aspectFit(pane(718, 299), px(2594, 1080))),
      "on its side with the controls (its desktop grown to 1297×540): fitted as before")
check(!PictureFit.oneToOne(in: pane(377, 235), videoSize: px(1732, 1080), screenScale: 3)
      && near(PictureFit.rect(in: pane(377, 235), videoSize: px(1732, 1080), screenScale: 3), aspectFit(pane(377, 235), px(1732, 1080))),
      "upright with the controls (its desktop grown to 866×540): fitted as before")
check(!PictureFit.oneToOne(in: pane(377, 235), videoSize: px(1600, 998), screenScale: 3)
      && near(PictureFit.rect(in: pane(377, 235), videoSize: px(1600, 998), screenScale: 3), aspectFit(pane(377, 235), px(1600, 998))),
      "…and run 6's 800×499: fitted")
// An origin other than zero: the pane's own top-left.
let off = PictureFit.rect(in: CGRect(x: 8, y: 59, width: 393, height: 793), videoSize: px(1178, 2378), screenScale: 3)
check(near(off, CGRect(x: 8, y: 59, width: 1178.0 / 3, height: 2378.0 / 3)), "the pane's own top-left (\(off))")
// A picture that fills its pane exactly is the same either way (an iPad's own pixels: 2752×2064 in 1376×1032 at 2x).
check(near(PictureFit.rect(in: pane(1376, 1032), videoSize: px(2752, 2064), screenScale: 2), pane(1376, 1032)), "an exact fill: the pane")
check(PictureFit.oneToOne(in: pane(1376, 1032), videoSize: px(2752, 2064), screenScale: 2), "…one for one too")
// Fractions of a point: an iPhone's pane of 377.3333 points at 3x is 1132 pixels.
check(PictureFit.oneToOne(in: pane(377.3333333, 235.6666667), videoSize: px(1132, 706), screenScale: 3), "a pane in fractions of a point")
// Not one for one: larger than the pane, more than two pixels short, another shape, no scale.
check(!PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1180, 2378), screenScale: 3), "a pixel wider than the pane: fitted (scaled down)")
check(!PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1176, 2376), screenScale: 3), "three pixels short: fitted")
check(PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1177, 2377), screenScale: 3), "two pixels short: one for one")
check(!PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1178, 1178), screenScale: 3), "one side far short: fitted")
check(!PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1178, 2378), screenScale: nil)
      && near(PictureFit.rect(in: pane(393, 793), videoSize: px(1178, 2378), screenScale: nil), aspectFit(pane(393, 793), px(1178, 2378))),
      "no scale known: fitted as before")
check(!PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1178, 2378), screenScale: 0)
      && !PictureFit.oneToOne(in: pane(393, 793), videoSize: px(1178, 2378), screenScale: .nan), "a scale of 0 or NaN: fitted")
// A window on an iPad (2x): its capture a pixel or two short of the pane drawn one for one, sharper than a hair's scale.
check(PictureFit.oneToOne(in: pane(1117, 618), videoSize: px(2232, 1236), screenScale: 2), "an iPad's window two pixels narrow: one for one")
check(!PictureFit.oneToOne(in: pane(1117, 618), videoSize: px(1920, 1080), screenScale: 2), "a 1080p window on an iPad: fitted")
// No picture, no pane.
check(PictureFit.rect(in: pane(393, 793), videoSize: .zero, screenScale: 3) == .zero, "no picture yet: .zero")
check(PictureFit.rect(in: pane(0, 0), videoSize: px(1178, 2378), screenScale: 3) == .zero, "no pane: .zero")
check(PictureFit.rect(in: pane(393, 793), videoSize: px(.nan, 2378), screenScale: 3) == .zero, "a NaN picture: .zero")
check(PictureFit.spare == 2, "two pixels to spare a side")

// 50,000 random panes and pictures: one for one exactly when each side of the picture is at most the pane's pixels and at
// most two short; then its own size at the pane's top-left, inside the pane; else the old aspect-fit exactly.
var wrong = 0, ones = 0
var rng = SystemRandomNumberGenerator()
for i in 0..<50_000 {
    let s: CGFloat = [1, 2, 3][Int.random(in: 0...2, using: &rng)]
    let bw = CGFloat(Int.random(in: 50...1500, using: &rng)) + (i % 3 == 0 ? CGFloat(Int.random(in: 0...2, using: &rng)) / 3 : 0)
    let bh = CGFloat(Int.random(in: 50...1500, using: &rng))
    let b = CGRect(x: CGFloat(Int.random(in: 0...60, using: &rng)), y: CGFloat(Int.random(in: 0...60, using: &rng)), width: bw, height: bh)
    let near1 = i % 2 == 0
    let vw = near1 ? (bw * s).rounded(.down) - CGFloat(Int.random(in: -1...3, using: &rng)) : CGFloat(Int.random(in: 2...5000, using: &rng))
    let vh = near1 ? (bh * s).rounded(.down) - CGFloat(Int.random(in: -1...3, using: &rng)) : CGFloat(Int.random(in: 2...5000, using: &rng))
    guard vw > 0, vh > 0 else { continue }
    let v = px(vw, vh)
    let paneW = bw * s, paneH = bh * s
    let expect = vw <= paneW + 0.001 && vh <= paneH + 0.001 && paneW - vw <= 2.002 && paneH - vh <= 2.002
    let one = PictureFit.oneToOne(in: b, videoSize: v, screenScale: s)
    let r = PictureFit.rect(in: b, videoSize: v, screenScale: s)
    if one != expect { wrong += 1; continue }
    if one {
        ones += 1
        if !near(r, CGRect(x: b.minX, y: b.minY, width: vw / s, height: vh / s)) || r.maxX > b.maxX + 1e-6 || r.maxY > b.maxY + 1e-6 { wrong += 1 }
    } else if !near(r, aspectFit(b, v)) { wrong += 1 }
}
check(wrong == 0 && ones > 5000, "50,000 random panes and pictures: one for one exactly where it should be, else as before (\(wrong) not; \(ones) one for one)")

print("picture-fit: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
