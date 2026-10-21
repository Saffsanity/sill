// iOSClient/PictureZoom.swift on its own: the zoom's geometry (zoomedRect) at its edges and in 20,000
// random cases, and the object's rules: follow, the hold while a finger is down, toggle, allowed.
//   swiftc -O iOSClient/PictureZoom.swift Tests/checks/picture-zoom/main.swift -o check && ./check
import CoreGraphics
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1 } else { fails += 1; print("FAIL \(name)") } }
func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.001) -> Bool { abs(a - b) <= e }
func near(_ a: CGRect, _ b: CGRect) -> Bool {
    near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
}
let Z = PictureZoom.zoomedRect
/// What HEVCDisplayView.videoRect gives: `video` fitted in `bounds`, centred.
func HEVCRect(video: CGSize, in bounds: CGRect) -> CGRect {
    let k = min(bounds.width / video.width, bounds.height / video.height)
    let w = video.width * k, h = video.height * k
    return CGRect(x: bounds.minX + (bounds.width - w) / 2, y: bounds.minY + (bounds.height - h) / 2, width: w, height: h)
}

// An iPhone 17 Pro's pane, 386×241, a 16:10 frame filling it.
let pane = CGRect(x: 0, y: 0, width: 386, height: 241)
let full = pane

// MARK: Geometry

check("no zoom: the frame as drawn", Z(full, pane, 1, CGPoint(x: 0.9, y: 0.1)) == full)
check("under 1: as drawn", Z(full, pane, 0.5, CGPoint(x: 0.5, y: 0.5)) == full)
check("no frame: as drawn", Z(.zero, pane, 2, CGPoint(x: 0.5, y: 0.5)) == .zero)
check("2x on the middle: centred",
      near(Z(full, pane, 2, CGPoint(x: 0.5, y: 0.5)), CGRect(x: -193, y: -120.5, width: 772, height: 482)))
check("2x on the top left corner: the frame's corner at the pane's",
      near(Z(full, pane, 2, .zero), CGRect(x: 0, y: 0, width: 772, height: 482)))
check("2x on the bottom right: the frame's far corner at the pane's",
      near(Z(full, pane, 2, CGPoint(x: 1, y: 1)), CGRect(x: -386, y: -241, width: 772, height: 482)))
check("2x at a quarter: the quarter in the middle",
      near(Z(full, pane, 2, CGPoint(x: 0.25, y: 0.25)), CGRect(x: 0, y: 0, width: 772, height: 482)))
check("4x at 0.4: 0.4 in the middle",
      near(Z(full, pane, 4, CGPoint(x: 0.4, y: 0.6)).minX, 193 - 0.4 * 1544)
      && near(Z(full, pane, 4, CGPoint(x: 0.4, y: 0.6)).minY, 120.5 - 0.6 * 964))
// A 16:9 frame in the 16:10 pane: 386×217 with 12 pt bars above and below.
let wide = CGRect(x: 0, y: 12, width: 386, height: 217.125)
let w11 = Z(wide, pane, 1.1, CGPoint(x: 0, y: 0))
check("1.1x of a letterboxed frame: still shorter than the pane, so centred down it",
      near(w11.midY, pane.midY) && near(w11.minX, 0))
check("2x of a letterboxed frame: fills the pane both ways from its corner",
      near(Z(wide, pane, 2, .zero).minY, 0) && near(Z(wide, pane, 2, .zero).minX, 0))
// The pane not at the origin.
let moved = CGRect(x: 8, y: 8, width: 386, height: 241)
check("an offset pane: the frame's corner at the pane's corner",
      near(Z(moved, moved, 3, .zero), CGRect(x: 8, y: 8, width: 1158, height: 723)))

// Random: the magnified frame is `scale` times the drawn one, covers the pane along every axis it is
// longer than, and is centred along one it is not; the focus sits in the pane's middle unless an edge
// stopped it, and then that edge is on the pane's.
var rng = SystemRandomNumberGenerator()
func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &rng) }
var randomOK = true
for _ in 0..<20_000 {
    let bounds = CGRect(x: r(-50, 50), y: r(-50, 50), width: r(50, 600), height: r(50, 600))
    let aspect = r(0.4, 3)
    let s = min(bounds.width / aspect, bounds.height)
    let video = CGRect(x: bounds.midX - s * aspect / 2, y: bounds.midY - s / 2, width: s * aspect, height: s)
    let scale = r(1.01, 5)
    let focus = CGPoint(x: r(0, 1), y: r(0, 1))
    let z = Z(video, bounds, scale, focus)
    var ok = near(z.width, video.width * scale, 0.01) && near(z.height, video.height * scale, 0.01)
    for axis in 0..<2 {
        let (zMin, zLen, bMin, bLen, f) = axis == 0
            ? (z.minX, z.width, bounds.minX, bounds.width, focus.x)
            : (z.minY, z.height, bounds.minY, bounds.height, focus.y)
        if zLen > bLen {
            ok = ok && zMin <= bMin + 0.01 && zMin + zLen >= bMin + bLen - 0.01
            let focusAt = zMin + f * zLen
            let middle = near(focusAt, bMin + bLen / 2, 0.01)
            let stopped = near(zMin, bMin, 0.01) || near(zMin + zLen, bMin + bLen, 0.01)
            ok = ok && (middle || stopped)
        } else {
            ok = ok && near(zMin + zLen / 2, bMin + bLen / 2, 0.01)
        }
    }
    if !ok { randomOK = false; break }
}
check("20,000 random zooms keep the rules", randomOK)

// MARK: The object

let zoom = PictureZoom()
zoom.touchFollowDelay = 0      // the delay has its own checks below
var changes: [Bool] = []
zoom.onChange = { changes.append($0) }
zoom.scale = 2
check("not offered: no zoom applies", zoom.effectiveScale == 1)
check("not offered: the frame as drawn", zoom.rect(video: full, bounds: pane) == full)
zoom.offered()
check("offered: 2x", zoom.effectiveScale == 2)
zoom.offered(); zoom.withdrawn()
check("a second arrangement that comes and goes keeps it offered", zoom.effectiveScale == 2)
zoom.withdrawn()
check("the last one gone: none", zoom.effectiveScale == 1)
zoom.withdrawn()
check("withdrawn too often: still none, and offering again works", { zoom.offered(); return zoom.effectiveScale == 2 }())

zoom.follow(CGPoint(x: 0.1, y: 0.2))
check("follow: the focus", zoom.focus == CGPoint(x: 0.1, y: 0.2))
zoom.follow(CGPoint(x: -1, y: 3))
check("follow: clamped to the frame", zoom.focus == CGPoint(x: 0, y: 1))
changes = []
zoom.follow(CGPoint(x: 0.01, y: 0.99))
check("a small step: drawn without animation", changes == [false])
changes = []
zoom.follow(CGPoint(x: 0.9, y: 0.1))
check("a jump: animated", changes == [true])

zoom.touchesBegan(1)
zoom.follow(CGPoint(x: 0.5, y: 0.5))
check("a finger down: the focus holds", zoom.focus == CGPoint(x: 0.9, y: 0.1))
zoom.touchesBegan(1)
zoom.touchesEnded(1)
check("one of two lifted: still holds", zoom.focus == CGPoint(x: 0.9, y: 0.1))
zoom.touchesEnded(1)
check("the last lifted: the focus taken", zoom.focus == CGPoint(x: 0.5, y: 0.5))
zoom.touchesEnded(3)
zoom.follow(CGPoint(x: 0.3, y: 0.3))
check("more lifts than touches: never stuck holding", zoom.focus == CGPoint(x: 0.3, y: 0.3))
zoom.touchesBegan(1)
zoom.follow(CGPoint(x: 0.7, y: 0.7))
check("after extra lifts, the next finger down still holds", zoom.focus == CGPoint(x: 0.3, y: 0.3))
zoom.touchesEnded(1)
check("and lifting it takes the focus", zoom.focus == CGPoint(x: 0.7, y: 0.7))

zoom.toggle()
check("toggle: off", zoom.scale == 1)
zoom.toggle()
check("toggle: back to the last zoom", zoom.scale == 2)
zoom.scale = 4
zoom.scale = 1
zoom.toggle()
check("toggle: the last zoom chosen", zoom.scale == 4)
let fresh = PictureZoom()
fresh.toggle()
check("toggle on a fresh zoom: the default", fresh.scale == PictureZoom.defaultZoom)
check("the steps start at 1 and rise", PictureZoom.steps.first == 1 && PictureZoom.steps == PictureZoom.steps.sorted())

// MARK: A finger's click waits out the double-click time

let slow = PictureZoom()
slow.touchFollowDelay = 0.2
slow.offered()
slow.scale = 2
slow.touchesBegan(1)
slow.follow(CGPoint(x: 0.9, y: 0.9))
slow.touchesEnded(1)
check("a tap: not followed as the finger lifts", slow.focus == CGPoint(x: 0.5, y: 0.5))
slow.follow(CGPoint(x: 0.8, y: 0.8))
check("a click answered after the lift: still waits", slow.focus == CGPoint(x: 0.5, y: 0.5))
slow.touchesBegan(1)
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
check("a second finger down in time: still waits", slow.focus == CGPoint(x: 0.5, y: 0.5))
slow.touchesEnded(1)
RunLoop.main.run(until: Date().addingTimeInterval(0.35))
check("after the double-click time: the last click followed", slow.focus == CGPoint(x: 0.8, y: 0.8))
slow.follow(CGPoint(x: 0.1, y: 0.1))
check("the Mac's arrow later: followed at once", slow.focus == CGPoint(x: 0.1, y: 0.1))
slow.touchesBegan(1)
slow.offered()
slow.follow(CGPoint(x: 0.3, y: 0.3))
check("a touch lost as a new arrangement shows holds nothing", slow.focus == CGPoint(x: 0.3, y: 0.3))
slow.touchesBegan(1)
slow.withdrawn()
slow.follow(CGPoint(x: 0.4, y: 0.4))
check("a touch lost as the old arrangement goes holds nothing", slow.focus == CGPoint(x: 0.4, y: 0.4))

// MARK: Full Screen draws the frame against the top

let top = PictureZoom()
top.touchFollowDelay = 0
top.offered()
let room = CGRect(x: 0, y: 0, width: 390, height: 600)
let short = HEVCRect(video: CGSize(width: 1600, height: 1000), in: room)
check("not aligned: a short frame in the room's middle", near(top.rect(video: short, bounds: room).midY, 300))
top.alignTop = true
check("aligned: against the room's top", near(top.rect(video: short, bounds: room).minY, 0))
top.scale = 2
check("aligned and zoomed past the room: the zoom's own rule", top.rect(video: short, bounds: room).height > 600 || near(top.rect(video: short, bounds: room).minY, 0))

// MARK: Aa's Auto

check("auto: a window the size asked fits", AutoFit.fits(window: CGSize(width: 390, height: 650), room: CGSize(width: 390, height: 650), scale: 1))
check("auto: a window wider than asked (the app's minimum) does not", !AutoFit.fits(window: CGSize(width: 500, height: 650), room: CGSize(width: 390, height: 650), scale: 1))
check("auto: at 0.75 the room is a third larger", AutoFit.fits(window: CGSize(width: 520, height: 866), room: CGSize(width: 390, height: 650), scale: 0.75))
check("auto: a window taller than asked (an app's minimum height) does not",
      !AutoFit.fits(window: CGSize(width: 390, height: 800), room: CGSize(width: 390, height: 650), scale: 1))
check("auto: a few points either way still fit", AutoFit.fits(window: CGSize(width: 393, height: 653), room: CGSize(width: 390, height: 650), scale: 1))
check("auto: smaller than asked fits (no black at its sides is Sill's)", AutoFit.fits(window: CGSize(width: 300, height: 400), room: CGSize(width: 390, height: 650), scale: 1))
check("auto: 1, then 0.75, then 0.5, then none", AutoFit.steps.first == 1 && AutoFit.next(after: 1) == 0.75 && AutoFit.next(after: 0.75) == 0.5 && AutoFit.next(after: 0.5) == nil)
check("auto: no room, nothing to judge", AutoFit.fits(window: CGSize(width: 900, height: 900), room: .zero, scale: 1))

// MARK: Fill and the zoom of each source

check("fill: a 16:10 frame in a tall screen grows to its height",
      near(PictureZoom.fillScale(video: CGRect(x: 0, y: 300, width: 390, height: 243.75),
                                 bounds: CGRect(x: 0, y: 0, width: 390, height: 844)), 844 / 243.75))
check("fill: a frame that already covers needs nothing", PictureZoom.fillScale(video: full, bounds: pane) == 1)
check("fill: no frame, nothing", PictureZoom.fillScale(video: .zero, bounds: pane) == 1)

let tall = CGRect(x: 0, y: 0, width: 390, height: 844)
let tallVideo = CGRect(x: 0, y: 300.125, width: 390, height: 243.75)
let filled = PictureZoom()
filled.touchFollowDelay = 0
filled.offered()
_ = filled.rect(video: tallVideo, bounds: tall)
check("fill off: nothing grows", filled.effectiveScale == 1)
filled.fill = true
let f = filled.rect(video: tallVideo, bounds: tall)
check("fill on: the frame as tall as the screen", near(f.height, 844, 0.01) && near(f.minY, 0, 0.01))
check("fill on: the trackpad slows by it", near(filled.effectiveScale, 844 / 243.75))
filled.scale = 2
_ = filled.rect(video: tallVideo, bounds: tall)
check("fill and a zoom: the two multiply", near(filled.effectiveScale, 2 * 844 / 243.75))
filled.withdrawn()
check("fill where it is not offered: nothing", filled.effectiveScale == 1)

let perSource = PictureZoom()
perSource.touchFollowDelay = 0
perSource.source("desktop")
perSource.scale = 3
perSource.source("window:7")
check("a new window: no zoom", perSource.scale == 1)
perSource.scale = 1.5
perSource.source("desktop")
check("back to the Desktop: its zoom", perSource.scale == 3)
perSource.source("window:7")
check("back to the window: its own", perSource.scale == 1.5)
perSource.follow(CGPoint(x: 0.9, y: 0.9))
perSource.source("window:8")
check("another source: the focus back in the middle", perSource.focus == CGPoint(x: 0.5, y: 0.5))
perSource.source("window:8")
check("the same source again: nothing changes", perSource.scale == 1)

print("picture-zoom: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
