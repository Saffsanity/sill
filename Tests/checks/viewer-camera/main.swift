// iOSClient/ViewerCamera.swift on its own (docs/iphone-viewer-plan.md): where the Full-Screen
// Viewer puts the Mac's picture. Pinned cases on an iPhone 15 Pro and a 17 Pro Max, upright and
// sideways, with a 16:10 and a tall frame (fit, fill, the edge push, a pinch that zooms and pans,
// Fit again, no frame yet), then seeded random sessions of pinches, pointer moves and Fill/Fit over
// many screens and frames, checking the rules after every step: the picture centred along an axis
// where it is smaller than the screen and never leaving a gap where it is larger, the zoom within
// 1 and 8, `center` always what the screen shows, a pinch keeping the frame point under the fingers
// wherever the edges allow, and the pointer at the screen's edge pushed back to the edge band.
//   swiftc -O iOSClient/ViewerCamera.swift Tests/checks/viewer-camera/main.swift -o .build/checks/viewer-camera/check && .build/checks/viewer-camera/check
import CoreGraphics
import Foundation

typealias C = ViewerCamera
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if !ok { fails += 1; print("FAIL", name) } else { passes += 1; if passes <= 400 { print("ok  ", name) } }
}
func near(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat = 0.01) -> Bool { abs(a - b) <= t }
func str(_ r: CGRect) -> String { String(format: "(%.2f, %.2f, %.2f×%.2f)", r.minX, r.minY, r.width, r.height) }

let pro15 = CGSize(width: 393, height: 852)
let pro15Side = CGSize(width: 852, height: 393)
let proMax = CGSize(width: 440, height: 956)
let retina1610 = CGSize(width: 3024, height: 1890)
let tall = CGSize(width: 1200, height: 1800)   // a window taller than wide

func camera(_ screen: CGSize, _ video: CGSize) -> C {
    var c = C(); c.screen = screen; c.video = video; return c
}

/// The rules every state must keep.
func rules(_ c: C, _ tag: String) {
    let r = c.rect
    check("\(tag): zoom within 1…8 (\(c.zoom))", c.zoom >= 1 - 1e-9 && c.zoom <= 8 + 1e-9)
    for (lo, size, screen, axis) in [(r.minX, r.width, c.screen.width, "x"), (r.minY, r.height, c.screen.height, "y")] {
        if size <= screen + C.slack {
            check("\(tag): centred along \(axis) when smaller \(str(r))", near(lo, (screen - size) / 2, 0.001))
        } else {
            check("\(tag): no gap along \(axis) \(str(r))", lo <= 0.001 && lo + size >= screen - 0.001)
        }
    }
    // `center` is what the screen shows: the rect it gives puts that point at the screen's centre
    // (along an axis that is not centred anyway).
    if r.width > c.screen.width + C.slack {
        check("\(tag): center.x shown at the middle", near(r.minX + c.center.x * r.width, c.screen.width / 2, 0.01))
    }
    if r.height > c.screen.height + C.slack {
        check("\(tag): center.y shown at the middle", near(r.minY + c.center.y * r.height, c.screen.height / 2, 0.01))
    }
    let f = c.fitted
    check("\(tag): the size is fitted × zoom", near(r.width, f.width * c.zoom, 0.001) && near(r.height, f.height * c.zoom, 0.001))
}

// MARK: - Fit

do {
    let c = camera(pro15, retina1610)
    // 3024×1890 into 393×852: 393 wide, 245.625 tall, centred.
    check("15 Pro upright: fitted 393×245.6 \(str(c.rect))", near(c.rect.width, 393) && near(c.rect.height, 245.625))
    check("15 Pro upright: centred vertically", near(c.rect.minY, (852 - 245.625) / 2) && near(c.rect.minX, 0))
    check("15 Pro upright: not zoomed in", !c.isZoomedIn)
    rules(c, "fit upright")

    let s = camera(pro15Side, retina1610)
    // Into 852×393: 393 tall, 628.8 wide.
    check("15 Pro sideways: fitted 628.8×393 \(str(s.rect))", near(s.rect.width, 628.8) && near(s.rect.height, 393))
    check("15 Pro sideways: centred horizontally", near(s.rect.minX, (852 - 628.8) / 2))
    rules(s, "fit sideways")

    let t = camera(pro15, tall)
    check("a tall window upright: 393 wide, 589.5 tall", near(t.rect.width, 393) && near(t.rect.height, 589.5))
    rules(t, "fit tall")
}

// MARK: - Fill

do {
    var c = camera(pro15, retina1610)
    check("fillZoom upright: 852 / 245.625", near(c.fillZoom, 852 / 245.625, 0.0001))
    c.toggleFill(focus: nil)
    check("Fill upright: the picture covers the screen \(str(c.rect))", c.rect.minX <= 0.001 && c.rect.minY <= 0.001
          && c.rect.maxX >= 393 - 0.001 && near(c.rect.height, 852, 0.01))
    check("Fill upright: centred on the middle without a focus", near(c.rect.midX, 393 / 2, 0.01))
    check("Fill: now zoomed in", c.isZoomedIn)
    rules(c, "fill upright")
    c.toggleFill(focus: CGPoint(x: 0.9, y: 0.9))
    check("Fit: back to zoom 1", c.zoom == 1)
    check("Fit: back to the fitted rect", near(c.rect.width, 393) && near(c.rect.minY, (852 - 245.625) / 2))
    rules(c, "fit again")

    var f = camera(pro15, retina1610)
    f.toggleFill(focus: CGPoint(x: 0.9, y: 0.5))
    let p = f.onScreen(CGPoint(x: 0.9, y: 0.5))
    check("Fill on a focus right of centre moves the picture left \(str(f.rect))", f.rect.minX < -1)
    check("Fill on a focus: the focus in view", p.x >= 0 && p.x <= 393)
    rules(f, "fill on a focus")

    var e = camera(pro15, retina1610)
    e.toggleFill(focus: CGPoint(x: 1, y: 0.5))
    check("Fill on the frame's right edge: the frame's edge at the screen's", near(e.rect.maxX, 393, 0.01))
    rules(e, "fill on an edge")

    // A frame the screen's own shape fills at zoom 1: Fill changes nothing and stays "Fill".
    var same = camera(CGSize(width: 400, height: 250), CGSize(width: 1600, height: 1000))
    check("same shape: fillZoom 1", near(same.fillZoom, 1))
    same.toggleFill(focus: nil)
    check("same shape: Fill keeps zoom 1", same.zoom == 1 && !same.isZoomedIn)

    // A frame 20 times wider than tall: Fill is capped at 8.
    let wide = camera(pro15, CGSize(width: 20000, height: 100))
    check("a very wide frame: fillZoom capped at 8", wide.fillZoom == 8)
}

// MARK: - The edge push

do {
    var c = camera(pro15, retina1610)
    c.toggleFill(focus: nil)
    let before = c
    c.follow(CGPoint(x: 0.5, y: 0.5))
    check("the pointer in the middle moves nothing", c == before)
    // The pointer 10 pt from the left edge: the picture moves right by 34 so it sits 44 in.
    let x10 = (10 - c.rect.minX) / c.rect.width
    let r0 = c.rect
    c.follow(CGPoint(x: x10, y: 0.5))
    check("pushing the left edge moves the picture right by 34 \(str(r0)) → \(str(c.rect))", near(c.rect.minX - r0.minX, 34, 0.01))
    check("…and the pointer then sits 44 pt in", near(c.onScreen(CGPoint(x: x10, y: 0.5)).x, 44, 0.01))
    rules(c, "edge push")
    // Pushed to the frame's own edge: it stops there.
    for _ in 0..<200 { c.follow(CGPoint(x: 0, y: 0.5)) }
    check("the left edge reached: the frame's edge at the screen's", near(c.rect.minX, 0, 0.001))
    rules(c, "edge reached")
    // Zoom 1 upright: the picture is narrower than tall nowhere bigger than the screen: no push.
    var fit = camera(pro15, retina1610)
    let f0 = fit
    fit.follow(CGPoint(x: 0, y: 0))
    check("at fit nothing pushes", fit == f0)
    // Upright at fill the picture is exactly the screen's height: no vertical push.
    var fill = camera(pro15, retina1610)
    fill.toggleFill(focus: nil)
    let y0 = fill.rect.minY
    fill.follow(CGPoint(x: 0.5, y: 0))
    check("at fill upright no vertical push (the height is the screen's)", near(fill.rect.minY, y0, 0.001))
    // A small screen keeps a middle: the band is a quarter of 100, not 44.
    var small = camera(CGSize(width: 100, height: 100), CGSize(width: 100, height: 100))
    small.zoom = 4
    let at20 = (20 - small.rect.minX) / small.rect.width
    small.follow(CGPoint(x: at20, y: 0.5))
    check("a 100 pt screen: the band is 25", near(small.onScreen(CGPoint(x: at20, y: 0.5)).x, 25, 0.01))
}

// MARK: - Pinch

do {
    var c = camera(pro15Side, retina1610)
    let mid = CGPoint(x: 426, y: 196.5)
    let fracBefore = CGPoint(x: (mid.x - c.rect.minX) / c.rect.width, y: (mid.y - c.rect.minY) / c.rect.height)
    c.pinch(scale: 2, from: mid, to: mid)
    check("a pinch ×2 at the middle: zoom 2", near(c.zoom, 2))
    let p = c.onScreen(fracBefore)
    check("…the point under the fingers stays under them", near(p.x, mid.x, 0.01) && near(p.y, mid.y, 0.01))
    rules(c, "pinch")
    // The fingers move while pinching: the point follows them.
    let from = CGPoint(x: 400, y: 200), to = CGPoint(x: 420, y: 190)
    let f = CGPoint(x: (from.x - c.rect.minX) / c.rect.width, y: (from.y - c.rect.minY) / c.rect.height)
    c.pinch(scale: 1.1, from: from, to: to)
    let q = c.onScreen(f)
    check("a pinch that moves: the point under the fingers follows them", near(q.x, to.x, 0.01) && near(q.y, to.y, 0.01))
    rules(c, "pinch moving")
    // Out past 1: back at fit, centred.
    c.pinch(scale: 0.01, from: mid, to: mid)
    check("pinched out past fit: zoom 1", c.zoom == 1)
    check("…centred", near(c.rect.midX, 426, 0.01) && near(c.rect.midY, 196.5, 0.01))
    // In past 8: capped.
    for _ in 0..<20 { c.pinch(scale: 1.5, from: mid, to: mid) }
    check("pinched in past 8: capped at 8", c.zoom == 8)
    rules(c, "pinch capped")
    // A zero or negative scale (never from UIKit) changes nothing.
    let before = c
    c.pinch(scale: 0, from: mid, to: mid)
    check("scale 0: nothing", c == before)
}

// MARK: - Before the first frame

do {
    var c = C()
    check("no screen, no frame: an empty rect", c.rect.width == 0 && c.rect.height == 0)
    c.pinch(scale: 2, from: .zero, to: .zero)
    c.follow(CGPoint(x: 0.5, y: 0.5))
    c.toggleFill(focus: nil)
    check("no screen: nothing breaks (\(c.zoom))", c.zoom >= 1 && c.center.x.isFinite && c.center.y.isFinite)
    var s = camera(pro15, .zero)
    check("no frame yet: the screen itself", near(s.rect.width, 393) && near(s.rect.height, 852))
    check("no frame yet: fillZoom 1", s.fillZoom == 1)
    s.pinch(scale: 2, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 100))
    rules(s, "no frame, pinched")
    // The frame arriving (or changing shape) after a zoom: the rules hold at once.
    s.layout(screen: s.screen, video: retina1610)
    rules(s, "the frame arrives zoomed")
    // A rotation while zoomed.
    s.layout(screen: pro15Side, video: s.video)
    rules(s, "rotated while zoomed")
}

// MARK: - Random sessions

var rng = SystemRandomNumberGeneratorSeeded(seed: 0x5111)
struct SystemRandomNumberGeneratorSeeded: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &rng) }

let screens = [pro15, pro15Side, proMax, CGSize(width: 956, height: 440), CGSize(width: 320, height: 568), CGSize(width: 375, height: 667)]
let videos = [retina1610, tall, CGSize(width: 1920, height: 1080), CGSize(width: 800, height: 600), CGSize(width: 6016, height: 3384)]
var steps = 0
let savedPasses = passes
for session in 0..<2000 {
    var c = camera(screens[session % screens.count], videos[(session / screens.count) % videos.count])
    for step in 0..<40 {
        let tag = "session \(session) step \(step)"
        switch Int.random(in: 0..<10, using: &rng) {
        case 0...4:
            let from = CGPoint(x: r(0, c.screen.width), y: r(0, c.screen.height))
            let to = CGPoint(x: from.x + r(-30, 30), y: from.y + r(-30, 30))
            let rect = c.rect
            let frac = CGPoint(x: (from.x - rect.minX) / rect.width, y: (from.y - rect.minY) / rect.height)
            let wanted = min(C.maxZoom, max(1, c.zoom * r(0.7, 1.4)))
            c.pinch(scale: wanted / c.zoom, from: from, to: to)
            // Wherever the edges allow, the frame point is under the fingers: when the rect is not
            // against an edge along that axis (and larger than the screen), exactly.
            let p = c.onScreen(frac)
            let rr = c.rect
            if rr.width > c.screen.width + 1, rr.minX < -0.5, rr.maxX > c.screen.width + 0.5, frac.x >= 0, frac.x <= 1 {
                check("\(tag): pinch keeps x under the fingers", near(p.x, to.x, 0.05))
            }
            if rr.height > c.screen.height + 1, rr.minY < -0.5, rr.maxY > c.screen.height + 0.5, frac.y >= 0, frac.y <= 1 {
                check("\(tag): pinch keeps y under the fingers", near(p.y, to.y, 0.05))
            }
        case 5...7:
            let p = CGPoint(x: r(0, 1), y: r(0, 1))
            let before = c.onScreen(p)
            c.follow(p)
            let after = c.onScreen(p)
            let ex = min(C.edge, c.screen.width / 4), ey = min(C.edge, c.screen.height / 4)
            // Never pushed further than the band, and never moved the wrong way.
            if c.rect.width > c.screen.width + C.slack {
                // Pushed to the band exactly, unless the frame's own edge came first.
                if before.x < ex { check("\(tag): left push to the band", near(after.x, ex, 0.01) || near(c.rect.minX, 0, 0.01)) }
                else if before.x > c.screen.width - ex { check("\(tag): right push to the band", near(after.x, c.screen.width - ex, 0.01) || near(c.rect.maxX, c.screen.width, 0.01)) }
                else { check("\(tag): no horizontal move in the middle", near(after.x, before.x, 0.01)) }
            }
            if c.rect.height > c.screen.height + C.slack {
                if before.y < ey { check("\(tag): top push to the band", near(after.y, ey, 0.01) || near(c.rect.minY, 0, 0.01)) }
                else if before.y > c.screen.height - ey { check("\(tag): bottom push to the band", near(after.y, c.screen.height - ey, 0.01) || near(c.rect.maxY, c.screen.height, 0.01)) }
                else { check("\(tag): no vertical move in the middle", near(after.y, before.y, 0.01)) }
            }
        case 8:
            let was = c.isZoomedIn
            c.toggleFill(focus: Bool.random(using: &rng) ? CGPoint(x: r(0, 1), y: r(0, 1)) : nil)
            check("\(tag): Fill/Fit toggles (or stays fit when Fill is 1)", was ? c.zoom == 1 : (near(c.zoom, c.fillZoom) ))
        default:
            // A rotation, or the Mac's frame changing shape.
            if Bool.random(using: &rng) { c.layout(screen: CGSize(width: c.screen.height, height: c.screen.width), video: c.video) }
            else { c.layout(screen: c.screen, video: videos.randomElement(using: &rng)!) }
        }
        rules(c, tag)
        steps += 1
    }
}
print("random sessions: 2000, \(steps) steps, \(passes - savedPasses) checks")
// The keyboard reduces the camera's room, including at Fit. Follow uses that same room.
var keyboardCamera = camera(proMax, retina1610)
let room = CGSize(width: proMax.width, height: 390)
keyboardCamera.layout(screen: room, video: retina1610)
check("keyboard: Fit stays entirely above the keyboard", keyboardCamera.rect.minY >= 0 && keyboardCamera.rect.maxY <= room.height)
keyboardCamera.pinch(scale: 2, from: CGPoint(x: 220, y: 195), to: CGPoint(x: 220, y: 195))
keyboardCamera.follow(CGPoint(x: 0.5, y: 0.8))
check("keyboard: follow brings the pointer above its lower edge", keyboardCamera.onScreen(CGPoint(x: 0.5, y: 0.8)).y <= room.height - C.edge + 0.01)
keyboardCamera.zoom = 1
keyboardCamera.layout(screen: proMax, video: retina1610)
check("keyboard: closing restores Fit in the full screen", near(keyboardCamera.rect.midY, proMax.height / 2))
print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
