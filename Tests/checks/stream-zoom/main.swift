// StreamZoom (iOSClient/StreamZoom.swift) on its own: the picture's pinch zoom (issue #65; Noah's
// decisions of 2026-10-19 and 2026-10-20) and who a stroke on the picture belongs to.
//   - The zoom: 1× to 5× (never more, never less), a step of a pinch keeping the point of the picture
//     under the fingers' last midpoint under their midpoint now, the zoomed picture always covering its
//     pane, 1× the whole picture centred, a slight pinch out never back to 1×, the lift's settle only
//     within 2 % of the whole, a pane of another size keeping the zoom and the point at its middle, and
//     the mapping a touch and a scroll go through (back to the picture at 1×), with its inverse.
//   - The stroke: one finger the Mac's; two at 1× the Mac's scroll unless they pinch first (their
//     spacing more than their midpoint); any two on a zoomed picture the picture's; a decided stroke
//     keeping its owner to its last finger (no scroll from a pinch's fingers when one lifts, no zoom from
//     a scroll's when they spread); three fingers the gesture's, the picture back as the stroke found it.
//   - 20,000 random strokes against the invariants.
//   swiftc -O iOSClient/StreamZoom.swift Tests/checks/stream-zoom/main.swift -o .build/checks/stream-zoom/check && .build/checks/stream-zoom/check
import CoreGraphics
import Foundation

typealias Z = StreamZoom
typealias S = StreamZoom.Stroke
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }
func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) <= tolerance }
func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.001) -> Bool { near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) }
func str(_ z: Z) -> String { String(format: "%.3f× (%.2f, %.2f)", z.scale, z.offset.width, z.offset.height) }
func str(_ p: CGPoint) -> String { String(format: "(%.2f, %.2f)", p.x, p.y) }

/// The zoomed picture covers the pane: its top-left corner at or above and left of the pane's, its
/// bottom-right at or below and right of the pane's.
func covers(_ z: Z, _ size: CGSize) -> Bool {
    let tl = z.zoomedPoint(.zero, in: size), br = z.zoomedPoint(CGPoint(x: size.width, y: size.height), in: size)
    return tl.x <= 0.001 && tl.y <= 0.001 && br.x >= size.width - 0.001 && br.y >= size.height - 0.001
}
func inRange(_ z: Z) -> Bool { z.scale >= Z.minScale && z.scale <= Z.maxScale }
func zoomed(_ factor: CGFloat, at p: CGPoint, in size: CGSize) -> Z {
    var z = Z()
    z.pinch(factor: factor, from: p, to: p, in: size)
    return z
}

// MARK: - The zoom: the PR's own checks (addhumal, #196)

let box = CGSize(width: 400, height: 300)
var z = Z()
check("1×, no offset and not zoomed to begin with", z.scale == 1 && z.offset == .zero && !z.isZoomed)
z.pinch(factor: 2.0, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 200, y: 150), in: box)
check("2× at the pane's middle: no offset, zoomed", near(z.scale, 2) && near(z.offset.width, 0) && near(z.offset.height, 0) && z.isZoomed)
z.pinch(factor: 0.75, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 200, y: 150), in: box)
check("a slight pinch out, 2× to 1.5×, stays at 1.5× (no snap back to the whole picture)", near(z.scale, 1.5) && z.isZoomed)
z.pinch(factor: 0.5, from: CGPoint(x: 100, y: 80), to: CGPoint(x: 100, y: 80), in: box)
check("a pinch all the way out: 1×, no offset", z.scale == 1 && z.offset == .zero && !z.isZoomed)
z.pinch(factor: 10, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 200, y: 150), in: box)
check("at most 5×", z.scale == Z.maxScale && Z.maxScale == 5)
z.reset()
check("reset: 1×, no offset", z.scale == 1 && z.offset == .zero && !z.isZoomed)
var zMid = zoomed(2, at: CGPoint(x: 150, y: 120), in: box)
check("2× about (150, 120): that point of the picture stays under it, offset (50, 30)",
      near(zMid.unzoomedPoint(CGPoint(x: 150, y: 120), in: box), CGPoint(x: 150, y: 120))
      && near(zMid.offset.width, 50) && near(zMid.offset.height, 30))
zMid.pinch(factor: 1, from: CGPoint(x: 150, y: 120), to: CGPoint(x: 170, y: 130), in: box)
check("the midpoint moving 20, 10 moves the picture with it", near(zMid.offset.width, 70) && near(zMid.offset.height, 40))
zMid.pinch(factor: 1, from: .zero, to: CGPoint(x: 1000, y: -1000), in: box)
check("the offset kept within ±size·(scale − 1)/2: (200, −150) at 2× in 400×300",
      near(zMid.offset.width, 200) && near(zMid.offset.height, -150))
let d = zMid.unzoomedDelta(CGPoint(x: 40, y: -20))
check("a scroll's movement at 2× is half as far in the picture at 1×", near(d.x, 20) && near(d.y, -10))

// MARK: - The zoom: the scale's range and the whole picture

do {
    let size = CGSize(width: 1000, height: 650)
    var a = zoomed(3, at: CGPoint(x: 700, y: 200), in: size)
    check("3× about (700, 200)", near(a.scale, 3))
    a.pinch(factor: 0.9, from: CGPoint(x: 700, y: 200), to: CGPoint(x: 700, y: 200), in: size)
    check("3× pinched out by a tenth: 2.7×, not the whole picture", near(a.scale, 2.7) && a.isZoomed)
    a.pinch(factor: 0.4, from: CGPoint(x: 700, y: 200), to: CGPoint(x: 700, y: 200), in: size)
    check("2.7× pinched out to 1.08×: still zoomed (only all the way out is the whole picture)", near(a.scale, 1.08) && a.isZoomed)
    a.settle()
    check("the lift at 1.08×: 1.08× (above 1.02)", near(a.scale, 1.08) && a.isZoomed)
    a.pinch(factor: 1.015 / 1.08, from: CGPoint(x: 700, y: 200), to: CGPoint(x: 700, y: 200), in: size)
    check("pinched to 1.015×: zoomed while the fingers are down", near(a.scale, 1.015) && a.isZoomed)
    a.settle()
    check("the lift at 1.015×: the whole picture, centred (within 2 % of it)", a.scale == 1 && a.offset == .zero && !a.isZoomed)
    var b = zoomed(1.02, at: CGPoint(x: 100, y: 100), in: size)
    b.settle()
    check("the lift at exactly 1.02×: stays (the band is under 1.02)", near(b.scale, 1.02) && b.isZoomed)
    var c = zoomed(4, at: CGPoint(x: 900, y: 600), in: size)
    c.pinch(factor: 0.2, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 990, y: 640), in: size)
    check("4× pinched past 1× (to 0.8×): the whole picture, centred, wherever the midpoint went", c.scale == 1 && c.offset == .zero)
    var e = zoomed(4, at: CGPoint(x: 500, y: 300), in: size)
    e.pinch(factor: 1.0002 / 4, from: CGPoint(x: 500, y: 300), to: CGPoint(x: 500, y: 300), in: size)
    check("4× pinched to within a thousandth of 1×: the whole picture", e.scale == 1 && e.offset == .zero)
    var f = zoomed(2, at: CGPoint(x: 500, y: 300), in: size)
    f.pinch(factor: 4, from: CGPoint(x: 500, y: 300), to: CGPoint(x: 500, y: 300), in: size)
    check("2× spread by 4: 5× (capped), not 8×", f.scale == 5)
    f.pinch(factor: 3, from: CGPoint(x: 500, y: 300), to: CGPoint(x: 520, y: 300), in: size)
    check("at 5× a spread moves the picture with the midpoint and scales nothing", f.scale == 5 && near(f.offset.width, 20))
    var g = Z()
    g.pinch(factor: 0.5, from: CGPoint(x: 500, y: 300), to: CGPoint(x: 600, y: 300), in: size)
    check("at 1× a pinch in does nothing (no smaller than the whole picture)", g.scale == 1 && g.offset == .zero)
    var h = Z()
    h.pinch(factor: 2, from: CGPoint(x: 1, y: 1), to: CGPoint(x: 1, y: 1), in: .zero)
    h.pinch(factor: 0, from: CGPoint(x: 1, y: 1), to: CGPoint(x: 1, y: 1), in: size)
    h.pinch(factor: .infinity, from: CGPoint(x: 1, y: 1), to: CGPoint(x: 1, y: 1), in: size)
    h.pinch(factor: -2, from: CGPoint(x: 1, y: 1), to: CGPoint(x: 1, y: 1), in: size)
    check("no pane, a factor of 0, ∞ or below 0: nothing", h == Z())
    var i = zoomed(2.5, at: CGPoint(x: 300, y: 260), in: size)
    i.reset()
    check("reset from 2.5×: the whole picture", i.scale == 1 && i.offset == .zero)
}

// MARK: - The zoom: the mapping

do {
    let size = CGSize(width: 1000, height: 650)
    let one = Z()
    check("at 1× a touch is where it is", one.unzoomedPoint(CGPoint(x: 123, y: 456), in: size) == CGPoint(x: 123, y: 456)
          && one.zoomedPoint(CGPoint(x: 123, y: 456), in: size) == CGPoint(x: 123, y: 456))
    check("at 1× a scroll moves as far", one.unzoomedDelta(CGPoint(x: 7, y: -9)) == CGPoint(x: 7, y: -9))
    check("at 1× the whole pane shows", one.visibleRect(in: size) == CGRect(origin: .zero, size: size))
    let a = zoomed(2.5, at: CGPoint(x: 300, y: 260), in: size)
    // A point u of the picture at 1× shows at c + s(u − c) + o.
    let u = CGPoint(x: 420, y: 330)
    let shown = CGPoint(x: 500 + 2.5 * (420 - 500) + a.offset.width, y: 325 + 2.5 * (330 - 325) + a.offset.height)
    check("zoomedPoint: c + scale·(u − c) + offset (scaleEffect about the middle, then offset)", near(a.zoomedPoint(u, in: size), shown))
    check("unzoomedPoint is its inverse", near(a.unzoomedPoint(shown, in: size), u))
    check("the pinch's point (300, 260) shows where it was", near(a.zoomedPoint(CGPoint(x: 300, y: 260), in: size), CGPoint(x: 300, y: 260)))
    let v = a.visibleRect(in: size)
    check("what shows at 2.5×: 400×260 of the picture, from the point under the pane's top-left",
          near(v.width, 400) && near(v.height, 260) && near(v.origin, a.unzoomedPoint(.zero, in: size)))
    check("the visible part's far corner is under the pane's", near(a.zoomedPoint(CGPoint(x: v.maxX, y: v.maxY), in: size), CGPoint(x: 1000, y: 650)))
    check("a scroll at 2.5× moves the picture at 1× by its movement ÷ 2.5", near(a.unzoomedDelta(CGPoint(x: 25, y: -50)), CGPoint(x: 10, y: -20)))
    // Over many zooms: the round trip, coverage, the visible part inside the picture.
    var rng = SystemRandomNumberGenerator()
    var roundTrip = true, cover = true, visible = true
    for _ in 0..<5000 {
        let w = CGFloat.random(in: 200...1400, using: &rng), h = CGFloat.random(in: 150...1000, using: &rng)
        let s = CGSize(width: w, height: h)
        var z = Z()
        for _ in 0..<Int.random(in: 1...5, using: &rng) {
            z.pinch(factor: CGFloat.random(in: 0.5...2.5, using: &rng),
                    from: CGPoint(x: .random(in: -50...w + 50, using: &rng), y: .random(in: -50...h + 50, using: &rng)),
                    to: CGPoint(x: .random(in: -50...w + 50, using: &rng), y: .random(in: -50...h + 50, using: &rng)), in: s)
        }
        let p = CGPoint(x: .random(in: 0...w, using: &rng), y: .random(in: 0...h, using: &rng))
        if !near(z.zoomedPoint(z.unzoomedPoint(p, in: s), in: s), p, 0.01) || !near(z.unzoomedPoint(z.zoomedPoint(p, in: s), in: s), p, 0.01) { roundTrip = false }
        if !covers(z, s) || !inRange(z) { cover = false }
        let r = z.visibleRect(in: s)
        if r.minX < -0.01 || r.minY < -0.01 || r.maxX > w + 0.01 || r.maxY > h + 0.01 { visible = false }
    }
    check("5,000 random zooms: unzoomedPoint and zoomedPoint undo each other", roundTrip)
    check("5,000 random zooms: 1× to 5×, and the zoomed picture covers its pane", cover)
    check("5,000 random zooms: what shows is inside the picture", visible)
}

// MARK: - The zoom: the anchor

do {
    let size = CGSize(width: 1000, height: 650)
    var rng = SystemRandomNumberGenerator()
    var anchored = true, clampedOnlyAtEdges = true
    for _ in 0..<5000 {
        var z = zoomed(CGFloat.random(in: 1.2...4, using: &rng), at: CGPoint(x: .random(in: 0...1000, using: &rng), y: .random(in: 0...650, using: &rng)), in: size)
        let from = CGPoint(x: .random(in: 0...1000, using: &rng), y: .random(in: 0...650, using: &rng))
        let to = CGPoint(x: from.x + .random(in: -30...30, using: &rng), y: from.y + .random(in: -30...30, using: &rng))
        let under = z.unzoomedPoint(from, in: size)
        let was = z
        z.pinch(factor: CGFloat.random(in: 0.8...1.25, using: &rng), from: from, to: to, in: size)
        let maxX = size.width * (z.scale - 1) / 2, maxY = size.height * (z.scale - 1) / 2
        let atEdge = near(abs(z.offset.width), maxX, 0.01) || near(abs(z.offset.height), maxY, 0.01)
        if !z.isZoomed { continue }
        if !atEdge && !near(z.zoomedPoint(under, in: size), to, 0.01) { anchored = false; print("  anchor: \(str(was)) \(str(from))→\(str(to)) gives \(str(z))") }
        if atEdge && near(z.zoomedPoint(under, in: size), to, 0.01) == false {
            // At an edge only the clamped axis may miss.
            let shown = z.zoomedPoint(under, in: size)
            let xOK = near(shown.x, to.x, 0.01) || near(abs(z.offset.width), maxX, 0.01)
            let yOK = near(shown.y, to.y, 0.01) || near(abs(z.offset.height), maxY, 0.01)
            if !(xOK && yOK) { clampedOnlyAtEdges = false }
        }
    }
    check("5,000 pinch steps: the point under the last midpoint is under the midpoint now (Photos' anchor)", anchored)
    check("5,000 pinch steps: where it is not, only an axis held at the pane's edge misses", clampedOnlyAtEdges)
}

// MARK: - The zoom: another pane

do {
    let landscape = CGSize(width: 1000, height: 650), portrait = CGSize(width: 690, height: 450)
    var a = zoomed(2.5, at: CGPoint(x: 300, y: 200), in: landscape)
    let middle = a.unzoomedPoint(CGPoint(x: 500, y: 325), in: landscape)
    let fraction = CGPoint(x: middle.x / landscape.width, y: middle.y / landscape.height)
    a.resized(to: portrait)
    let now = a.unzoomedPoint(CGPoint(x: 345, y: 225), in: portrait)
    check("a turn keeps 2.5×", near(a.scale, 2.5))
    check("a turn keeps the point of the picture at the pane's middle (as a fraction of the pane)",
          near(CGPoint(x: now.x / portrait.width, y: now.y / portrait.height), fraction))
    check("a turn's zoom covers the new pane", covers(a, portrait) && a.pane == portrait)
    a.resized(to: landscape)
    check("and back: the zoom it had", near(a.scale, 2.5) && near(a.offset.width, zoomed(2.5, at: CGPoint(x: 300, y: 200), in: landscape).offset.width)
          && near(a.offset.height, zoomed(2.5, at: CGPoint(x: 300, y: 200), in: landscape).offset.height))
    var b = Z()
    b.resized(to: portrait)
    check("at 1× a new pane is only remembered", b.scale == 1 && b.offset == .zero && b.pane == portrait)
    var c = zoomed(3, at: CGPoint(x: 900, y: 600), in: landscape)
    let was = c
    c.resized(to: .zero)
    c.resized(to: CGSize(width: -10, height: 40))
    check("a pane of no size changes nothing", c == was)
    c.resized(to: landscape)
    check("the same pane again changes nothing", c == was)
    var rng = SystemRandomNumberGenerator()
    var ok = true
    for _ in 0..<5000 {
        let s1 = CGSize(width: .random(in: 200...1400, using: &rng), height: .random(in: 150...1000, using: &rng))
        let s2 = CGSize(width: .random(in: 200...1400, using: &rng), height: .random(in: 150...1000, using: &rng))
        var z = zoomed(.random(in: 1.05...5, using: &rng), at: CGPoint(x: .random(in: 0...s1.width, using: &rng), y: .random(in: 0...s1.height, using: &rng)), in: s1)
        let m1 = z.unzoomedPoint(CGPoint(x: s1.width / 2, y: s1.height / 2), in: s1)
        let scale = z.scale
        z.resized(to: s2)
        let m2 = z.unzoomedPoint(CGPoint(x: s2.width / 2, y: s2.height / 2), in: s2)
        if !covers(z, s2) || !near(z.scale, scale) || !near(m2.x / s2.width, m1.x / s1.width, 0.0001) || !near(m2.y / s2.height, m1.y / s1.height, 0.0001) { ok = false }
    }
    check("5,000 panes of other sizes: the scale, the middle's point and the cover kept", ok)
}

// MARK: - The stroke: one finger

/// A stroke, step by step, against a zoom: what the input view does with the stroke observer's touches.
struct Rig {
    var zoom: Z
    var stroke = S()
    var size: CGSize
    /// The finger pan scrolls the Mac (it began while the stroke was the Mac's): what the input view sends.
    var scrolling = false
    var panBegun = false
    init(_ zoom: Z = Z(), size: CGSize = CGSize(width: 1000, height: 650)) { self.zoom = zoom; self.size = size }
    mutating func down(_ id: Int, _ x: CGFloat, _ y: CGFloat) { stroke.down(id, at: CGPoint(x: x, y: y), zoom: zoom) }
    /// One finger moves (a touch event with only its move).
    mutating func move(_ id: Int, _ x: CGFloat, _ y: CGFloat) { stroke.moved([id: CGPoint(x: x, y: y)], zoom: &zoom, in: size) }
    /// Fingers move in one touch event, as UIKit delivers them together.
    mutating func moves(_ m: [Int: (CGFloat, CGFloat)]) { stroke.moved(m.mapValues { CGPoint(x: $0.0, y: $0.1) }, zoom: &zoom, in: size) }
    mutating func up(_ id: Int) { stroke.up(id, zoom: &zoom) }
    /// UIKit's pan begins: the input view asks the rule once.
    mutating func pan() {
        guard !panBegun else { return }
        panBegun = true
        stroke.panBegan()
        scrolling = stroke.scrollsMac
    }
    mutating func silence() { stroke.silenced(zoom: &zoom) }
}

do {
    var r = Rig()
    r.down(0, 500, 300)
    check("one finger down: undecided", r.stroke.owner == .undecided)
    r.move(0, 505, 300); r.move(0, 512, 300); r.pan(); r.move(0, 560, 300)
    check("one finger's pan: the Mac's scroll", r.stroke.owner == .mac && r.scrolling && r.zoom == Z())
    r.up(0)
    check("its lift: the stroke over", r.stroke.owner == .none && r.stroke.fingers == 0)
    var s = Rig(zoomed(3, at: CGPoint(x: 300, y: 300), in: CGSize(width: 1000, height: 650)))
    let was = s.zoom
    s.down(0, 500, 300); s.move(0, 520, 300); s.pan(); s.move(0, 600, 340); s.up(0)
    check("one finger on a zoomed picture: the Mac's scroll, the picture as it was", s.scrolling && s.zoom == was)
    var t = Rig()
    t.down(0, 500, 300); t.up(0)
    check("a tap: undecided to the end, nothing zoomed", t.zoom == Z() && t.stroke.owner == .none)
}

// MARK: - The stroke: two fingers at 1×

do {
    // Two fingers scrolling up in parallel, 80 pt apart: the pan begins at UIKit's hysteresis (10 pt).
    var r = Rig()
    r.down(0, 460, 400); r.down(1, 540, 400)
    check("two fingers down at 1×: undecided", r.stroke.owner == .undecided)
    for k in 1...3 { r.moves([0: (460, 400 - CGFloat(k) * 4), 1: (540, 400 - CGFloat(k) * 4)]) }
    r.pan()
    for k in 4...30 { r.moves([0: (460, 400 - CGFloat(k) * 4), 1: (540, 400 - CGFloat(k) * 4)]) }
    check("two fingers scrolling in parallel: the Mac's scroll, nothing zoomed", r.scrolling && r.stroke.owner == .mac && r.zoom == Z())
    // The same with the fingers drifting 4 pt apart by the pan's start and 30 by the end.
    var s = Rig()
    s.down(0, 460, 400); s.down(1, 540, 400)
    for k in 1...3 { s.moves([0: (460 - CGFloat(k) * 0.66, 400 - CGFloat(k) * 4), 1: (540 + CGFloat(k) * 0.66, 400 - CGFloat(k) * 4)]) }
    s.pan()
    for k in 4...30 { s.moves([0: (460 - CGFloat(k) * 0.5, 400 - CGFloat(k) * 4), 1: (540 + CGFloat(k) * 0.5, 400 - CGFloat(k) * 4)]) }
    check("a two-finger scroll whose fingers drift apart: still the Mac's scroll, nothing zoomed (it never turns into a zoom)",
          s.scrolling && s.stroke.owner == .mac && s.zoom == Z())
    s.up(0); s.up(1)
    check("its lift: over, 1×", s.stroke.owner == .none && s.zoom == Z())
}

do {
    // A spread about a still midpoint: 60 pt apart to 150, in steps of 6 pt each side.
    var r = Rig()
    r.down(0, 470, 300); r.down(1, 530, 300)
    r.moves([0: (466, 300), 1: (534, 300)])
    check("a spread of 8 pt: undecided still", r.stroke.owner == .undecided && r.zoom == Z())
    r.moves([0: (463, 300), 1: (537, 300)])
    check("a spread of 14 pt about a still midpoint: the picture's", r.stroke.owner == .picture && !r.stroke.scrollsMac)
    check("caught up from where the fingers landed: 74 ÷ 60 (the point under them stays under them)", near(r.zoom.scale, 74.0 / 60.0))
    for x in stride(from: 460, through: 425, by: -5) { r.moves([0: (CGFloat(x), 300), 1: (CGFloat(1000 - x), 300)]) }
    r.pan()
    check("a pan that begins later changes nothing: the picture's", r.stroke.owner == .picture && !r.scrolling)
    check("150 ÷ 60 apart: 2.5×", near(r.zoom.scale, 2.5))
    check("about the midpoint (500, 300): no offset but the pane's middle's", near(r.zoom.unzoomedPoint(CGPoint(x: 500, y: 300), in: r.size), CGPoint(x: 500, y: 300)))
    r.up(0)
    check("one finger of the pinch lifts: the picture where it is, still the picture's", near(r.zoom.scale, 2.5) && r.stroke.owner == .picture)
    let held = r.zoom
    for k in 1...20 { r.move(1, 575 + CGFloat(k) * 10, 300 + CGFloat(k) * 5) }
    check("the other finger moving on: nothing zoomed or moved, nothing for the Mac (no stray scroll)", r.zoom == held && !r.scrolling)
    r.up(1)
    check("the last lift: over, 2.5× kept", r.stroke.owner == .none && near(r.zoom.scale, 2.5))
}

do {
    // A pinch led by one finger: the thumb still at (500, 400), the finger from (500, 340) up to (500, 160).
    var r = Rig()
    r.down(0, 500, 400); r.down(1, 500, 340)
    let under = r.zoom.unzoomedPoint(CGPoint(x: 500, y: 370), in: r.size)
    r.move(1, 500, 330)
    r.pan()   // its midpoint moved 5: UIKit's pan would not begin yet, but if it did: the spacing moved more
    check("a pinch led by one finger, its pan begun at once: the picture's (spacing 10 > midpoint 5)", r.stroke.owner == .picture && !r.scrolling)
    for y in stride(from: 320, through: 160, by: -10) { r.move(1, 500, CGFloat(y)) }
    check("led by one finger, 60 to 240 apart: 4×", near(r.zoom.scale, 4))
    // The midpoint went from (500, 370) to (500, 280): the point of the picture under the first is under the last.
    check("the picture's point under where the fingers landed is under their midpoint now", near(r.zoom.zoomedPoint(under, in: r.size), CGPoint(x: 500, y: 280), 0.01))
    r.up(0); r.up(1)
}

do {
    // A fast flick: the first touch event already moves the midpoint 30 pt and the spacing 15 (UIKit's pan
    // begins in that event, before or after the observer has seen it): the Mac's, never a zoom.
    var r = Rig()
    r.down(0, 460, 400); r.down(1, 540, 400)
    r.moves([0: (452.5, 370), 1: (547.5, 370)])
    check("a flick's first event, the midpoint 30 and the spacing 15: undecided (more travel than spacing)", r.stroke.owner == .undecided && r.zoom == Z())
    r.pan()
    for k in 1...6 { r.moves([0: (452.5, 370 - CGFloat(k) * 30), 1: (547.5, 370 - CGFloat(k) * 30)]) }
    check("then its pan: the Mac's scroll, nothing zoomed", r.scrolling && r.stroke.owner == .mac && r.zoom == Z())
    var s = Rig()
    s.down(0, 460, 400); s.down(1, 540, 400)
    s.pan()   // its pan's start seen before the event's move
    s.moves([0: (452.5, 370), 1: (547.5, 370)])
    check("the same with the pan's start seen first: the Mac's", s.scrolling && s.zoom == Z())
}

do {
    // A pinch whose fingers moved, then a third finger (not a gesture: they had moved), then one of the
    // pair lifts: the two left take the pinch over.
    var r = Rig()
    r.down(0, 450, 300); r.down(1, 550, 300)
    r.moves([0: (420, 300), 1: (580, 300)])
    check("a pinch: the picture's, 1.6×", r.stroke.owner == .picture && near(r.zoom.scale, 1.6))
    r.down(2, 500, 450)
    r.moves([0: (410, 300), 1: (590, 300), 2: (500, 460)])
    check("a third finger after they moved: ignored, the first two carry on (1.8×)", near(r.zoom.scale, 1.8))
    r.up(0)
    let held = r.zoom
    check("one of the pair lifts: no jump", r.zoom == held && r.stroke.owner == .picture)
    r.moves([1: (590, 300), 2: (500, 520)])
    check("the two left down take the pinch over from where they are", r.zoom.scale > held.scale)
}

do {
    // A tie at the pan's start: one finger 5 pt along, the other 15 (spacing 10, midpoint 10): the Mac's.
    var r = Rig()
    r.down(0, 400, 300); r.down(1, 500, 300)
    r.moves([0: (405, 300), 1: (515, 300)])
    r.pan()
    check("spacing and midpoint both 10 when the pan begins: the Mac's (a tie, as before the zoom)", r.stroke.owner == .mac && r.scrolling)
    var s = Rig()
    s.down(0, 400, 300); s.down(1, 500, 300)
    s.moves([0: (405, 300), 1: (516, 300)])
    s.pan()
    check("spacing 11, midpoint 10.5: the picture's", s.stroke.owner == .picture && !s.scrolling)
}

do {
    // A pinch in at 1×: the picture's stroke, the picture stays whole.
    var r = Rig()
    r.down(0, 400, 300); r.down(1, 600, 300)
    for k in 1...10 { r.moves([0: (400 + CGFloat(k) * 8, 300), 1: (600 - CGFloat(k) * 8, 300)]) }
    check("a pinch in at 1×: the picture's, still the whole picture", r.stroke.owner == .picture && r.zoom.scale == 1 && r.zoom.offset == .zero)
    r.up(0); r.up(1)
    check("its lift: 1×", r.zoom.scale == 1 && r.zoom.offset == .zero)
}

do {
    // One finger scrolling, then a second lands and both spread: a scroll to the end, never a zoom.
    var r = Rig()
    r.down(0, 500, 300)
    for k in 1...4 { r.move(0, 500, 300 - CGFloat(k) * 5) }
    r.pan()
    r.down(1, 600, 280)
    for k in 1...20 { r.moves([0: (500 - CGFloat(k) * 6, 280), 1: (600 + CGFloat(k) * 6, 280)]) }
    check("a scroll that a second finger joins and spreads: the Mac's scroll, nothing zoomed", r.scrolling && r.stroke.owner == .mac && r.zoom == Z())
}

// MARK: - The stroke: two fingers on a zoomed picture

do {
    let size = CGSize(width: 1000, height: 650)
    var r = Rig(zoomed(2, at: CGPoint(x: 500, y: 325), in: size))
    r.down(0, 450, 300); r.down(1, 550, 300)
    check("two fingers on a zoomed picture: the picture's at once", r.stroke.owner == .picture && !r.stroke.scrollsMac)
    for k in 1...10 { r.moves([0: (450 + CGFloat(k) * 5, 300 + CGFloat(k) * 3), 1: (550 + CGFloat(k) * 5, 300 + CGFloat(k) * 3)]) }
    r.pan()
    check("moving them together moves the picture by as much: (50, 30)", near(r.zoom.offset.width, 50) && near(r.zoom.offset.height, 30) && near(r.zoom.scale, 2))
    check("and nothing goes to the Mac", !r.scrolling)
    for k in 11...200 { r.moves([0: (450 + CGFloat(k) * 5, 300 + 30), 1: (550 + CGFloat(k) * 5, 300 + 30)]) }
    check("the picture stops at the pane's edge: 500 at 2× in 1000", near(r.zoom.offset.width, 500) && covers(r.zoom, size))
    r.up(0); r.up(1)
    check("their lift: 2× kept", near(r.zoom.scale, 2))
    // Lifted and put back: the pinch carries on from where it is, no jump.
    var s = Rig(zoomed(2, at: CGPoint(x: 500, y: 325), in: size))
    s.down(0, 450, 300); s.down(1, 550, 300)
    s.moves([0: (440, 300), 1: (560, 300)])
    let mid = s.zoom
    s.up(1)
    s.down(2, 700, 400)
    check("one lifts and another lands: still the picture's, and no jump", s.stroke.owner == .picture && s.zoom == mid)
    s.move(2, 740, 400)
    check("the new pair carries on from where its fingers are", s.zoom.scale > mid.scale)
    // A zoomed picture's stroke that leaves it within 2 % of the whole: the whole one at the lift.
    var t = Rig(zoomed(1.5, at: CGPoint(x: 500, y: 325), in: size))
    t.down(0, 440, 300); t.down(1, 560, 300)   // 120 apart
    t.moves([0: (460.5, 300), 1: (539.5, 300)])  // 79 apart: 1.5 × 79 / 120 = 0.9875 → 1×; then spread to 1.01×
    t.moves([0: (460.5, 300), 1: (540.3, 300)])   // 79.8 apart: 1.0101×
    let during = t.zoom.scale
    t.up(0); t.up(1)
    check("a stroke that leaves the picture at \(String(format: "%.3f", during))×: the whole picture at its lift", during > 1 && during < 1.02 && t.zoom == Z(t.zoom.pane))
}

extension StreamZoom {
    /// The whole picture in a pane of `size` (as `pane` remembers it).
    init(_ size: CGSize) {
        self.init()
        resized(to: size)
    }
}

// MARK: - The stroke: three fingers

do {
    let size = CGSize(width: 1000, height: 650)
    // Two fingers pinch, then a third lands before 24 pt (TrackpadGestures silences): back as it was.
    let start = zoomed(1.5, at: CGPoint(x: 400, y: 300), in: size)
    var r = Rig(start)
    r.down(0, 450, 300); r.down(1, 550, 300)
    r.moves([0: (440, 300), 1: (560, 300)])
    check("a pinch moved the picture before the third finger", r.zoom != start)
    r.silence(); r.down(2, 500, 380)
    check("three fingers: the gesture's, the picture back as the stroke found it", r.stroke.owner == .gesture && r.zoom == start)
    r.moves([0: (400, 300), 1: (600, 300), 2: (500, 420)])
    r.pan()
    check("then nothing more zooms, and nothing for the Mac's scroll", r.zoom == start && !r.scrolling)
    r.up(0); r.up(1); r.up(2)
    check("their lift: over, the picture as it was", r.stroke.owner == .none && r.zoom == start)
    // Three fingers at once at 1×: nothing.
    var s = Rig()
    s.down(0, 400, 300); s.down(1, 500, 300); s.silence(); s.down(2, 600, 300)
    for k in 1...10 { s.moves([0: (400 - CGFloat(k) * 5, 300), 1: (500, 300 - CGFloat(k) * 5), 2: (600 + CGFloat(k) * 5, 300)]) }
    check("a three-finger spread at 1×: the gesture's, the picture whole", s.stroke.owner == .gesture && s.zoom == Z())
    // The zoom changed by something else meanwhile (another source): not put back.
    var t = Rig(start)
    t.down(0, 450, 300); t.down(1, 550, 300)
    t.moves([0: (430, 300), 1: (570, 300)])
    t.zoom.reset()   // StreamScreen: another source
    t.silence()
    check("a zoom changed meanwhile by something else is left as it is", t.zoom.scale == 1 && t.stroke.owner == .gesture)
}

// MARK: - The stroke: odd orders

do {
    var r = Rig()
    r.pan()
    check("a pan with no finger seen: the Mac's, as before the zoom, and no owner left behind", r.scrolling && r.stroke.owner == .none)
    r.down(0, 400, 300); r.down(1, 500, 300)
    check("the next stroke starts undecided", r.stroke.owner == .undecided)
    var s = Rig()
    s.down(0, 400, 300); s.down(1, 500, 300)
    s.up(0)
    s.move(1, 520, 300); s.move(1, 540, 300)
    s.pan()
    check("two down, one lifts before anything: the other's pan is the Mac's", s.scrolling && s.zoom == Z())
    var t = Rig()
    t.down(0, 400, 300); t.down(1, 500, 300)
    t.move(5, 900, 900)
    t.stroke.up(9, zoom: &t.zoom)
    check("a touch the stroke never saw changes nothing", t.stroke.owner == .undecided && t.stroke.fingers == 2)
    var u = Rig()
    u.down(0, 400, 300); u.down(1, 400.5, 300)
    u.move(1, 430, 300)
    check("two fingers on top of each other: no scale read from them", u.zoom == Z())
}

// MARK: - The stroke under Zoom on ‹Mac›: the Mac's own pinch and turn (PR #261; Stroke.Target)

/// A stroke as the input view feeds it under Pinch's Zoom on ‹Mac› (`Target.mac`): every call's steps for the
/// Mac collected in order, as the input view sends them after each call.
struct MacRig {
    var r: Rig
    let target: S.Target
    var steps: [S.MacStep] = []
    init(turns: Bool, zoom: Z = Z()) { r = Rig(zoom); target = .mac(turns: turns) }
    mutating func take() { steps += r.stroke.macSteps }
    mutating func down(_ id: Int, _ x: CGFloat, _ y: CGFloat) { r.stroke.down(id, at: CGPoint(x: x, y: y), zoom: r.zoom, target: target); take() }
    mutating func moves(_ m: [Int: (CGFloat, CGFloat)]) { r.moves(m); take() }
    mutating func up(_ id: Int) { r.up(id); take() }
    mutating func pan() { r.pan(); take() }
    mutating func silence() { r.silence(); take() }
    var magnify: [(S.MacStep.Phase, Double)] { steps.compactMap { if case .magnify(let p, let v) = $0 { return (p, v) }; return nil } }
    var rotate: [(S.MacStep.Phase, Double)] { steps.compactMap { if case .rotate(let p, let v) = $0 { return (p, v) }; return nil } }
    /// The pinch's changes multiplied: the spacing's ratio over the whole pinch.
    var scale: Double { magnify.filter { $0.0 == .changed }.reduce(1) { $0 * (1 + $1.1) } }
    /// The turn's changes added up, in the Mac's degrees.
    var degrees: Double { rotate.filter { $0.0 == .changed }.reduce(0) { $0 + $1.1 } }
}
func phases(_ s: [(S.MacStep.Phase, Double)]) -> [S.MacStep.Phase] { s.map(\.0) }
func nearD(_ a: Double, _ b: Double, _ tolerance: Double = 0.0005) -> Bool { abs(a - b) <= tolerance }
/// Two fingers `spacing` apart about `c`, at `angle` (radians, the pane's: clockwise on screen as it grows).
func pair(_ c: CGPoint, _ spacing: CGFloat, _ angle: CGFloat) -> [Int: (CGFloat, CGFloat)] {
    let dx = cos(angle) * spacing / 2, dy = sin(angle) * spacing / 2
    return [0: (c.x - dx, c.y - dy), 1: (c.x + dx, c.y + dy)]
}

do {
    check("a stroke's pinch is the picture's unless told (the default target)", S().target == .picture)
    // A spread about a still midpoint, 60 pt apart to 150: the Mac's pinch, the picture as it was.
    var m = MacRig(turns: false)
    m.down(0, 470, 300); m.down(1, 530, 300)
    m.moves([0: (466, 300), 1: (534, 300)])
    check("Zoom on Mac: a spread of 8 pt: undecided still, nothing for the Mac", m.r.stroke.owner == .undecided && m.steps.isEmpty)
    m.moves([0: (463, 300), 1: (537, 300)])
    check("Zoom on Mac: a spread of 14 pt about a still midpoint: the Mac's pinch, never the picture's", m.r.stroke.owner == .macPinch && !m.r.stroke.scrollsMac)
    check("Zoom on Mac: the pinch begins, then catches up from where the fingers landed (74 ÷ 60)",
          phases(m.magnify) == [.began, .changed] && m.magnify[0].1 == 0 && nearD(m.magnify[1].1, 74.0 / 60.0 - 1))
    check("Zoom on Mac: at the point between the fingers where they landed", m.r.stroke.macAt == CGPoint(x: 500, y: 300))
    check("Zoom on Mac: the picture untouched", m.r.zoom == Z())
    for x in stride(from: 460, through: 425, by: -5) { m.moves([0: (CGFloat(x), 300), 1: (CGFloat(1000 - x), 300)]) }
    check("Zoom on Mac: each step its own change, together the whole spread (150 ÷ 60)", nearD(m.scale, 150.0 / 60.0) && m.r.zoom == Z())
    check("Zoom on Mac: no turn with Rotate off", m.rotate.isEmpty)
    m.pan()
    check("Zoom on Mac: the pan beginning late changes nothing (the stroke is the pinch's: no scroll)", !m.r.scrolling && m.r.stroke.owner == .macPinch)
    m.up(0)
    check("Zoom on Mac: one of the pair lifting ends the pinch", phases(m.magnify).last == .ended && phases(m.magnify).filter { $0 == .ended }.count == 1)
    m.up(1)
    check("Zoom on Mac: the last lift: over, nothing more, the picture still whole",
          m.r.stroke.owner == .none && phases(m.magnify).filter { $0 == .ended }.count == 1 && m.r.zoom == Z() && m.r.stroke.macAt == nil)
    // A pinch in, the last step's lift ending it.
    var n = MacRig(turns: false)
    n.down(0, 400, 300); n.down(1, 600, 300)
    for k in 1...10 { n.moves([0: (400 + CGFloat(k) * 5, 300), 1: (600 - CGFloat(k) * 5, 300)]) }
    n.up(1); n.up(0)
    check("Zoom on Mac: a pinch in: smaller (100 ÷ 200), began…ended", nearD(n.scale, 0.5) && phases(n.magnify).first == .began && phases(n.magnify).last == .ended)
    check("Zoom on Mac: every change a number, none zero", n.magnify.filter { $0.0 == .changed }.allSatisfy { $0.1.isFinite && $0.1 != 0 })
}

do {
    // Two fingers scrolling in parallel: the Mac's scroll, as before, and nothing for its pinch.
    var m = MacRig(turns: true)
    m.down(0, 460, 400); m.down(1, 540, 400)
    for k in 1...3 { m.moves([0: (460, 400 - CGFloat(k) * 4), 1: (540, 400 - CGFloat(k) * 4)]) }
    m.pan()
    for k in 4...30 { m.moves([0: (460, 400 - CGFloat(k) * 4), 1: (540, 400 - CGFloat(k) * 4)]) }
    m.up(0); m.up(1)
    check("Zoom on Mac: two fingers scrolling in parallel: the Mac's scroll, no pinch, no turn", m.r.scrolling && m.steps.isEmpty)
    // The same with the fingers drifting apart, and turning a little, once it scrolls.
    var d = MacRig(turns: true)
    d.down(0, 460, 400); d.down(1, 540, 400)
    for k in 1...3 { d.moves([0: (460 - CGFloat(k) * 0.66, 400 - CGFloat(k) * 4), 1: (540 + CGFloat(k) * 0.66, 400 - CGFloat(k) * 4)]) }
    d.pan()
    for k in 4...30 { d.moves([0: (460 - CGFloat(k) * 0.5, 400 - CGFloat(k) * 4 + CGFloat(k) * 0.3), 1: (540 + CGFloat(k) * 0.5, 400 - CGFloat(k) * 4 - CGFloat(k) * 0.3)]) }
    check("Zoom on Mac: a scroll whose fingers drift apart and turn: still the Mac's scroll, never its pinch (one or the other)",
          d.r.scrolling && d.r.stroke.owner == .mac && d.steps.isEmpty)
    // One finger: the Mac's, as ever.
    var o = MacRig(turns: true)
    o.down(0, 500, 300); o.moves([0: (520, 300)]); o.pan(); o.moves([0: (600, 340)]); o.up(0)
    check("Zoom on Mac: one finger: the Mac's scroll, nothing for its pinch", o.r.scrolling && o.steps.isEmpty)
}

do {
    // A turn about a still midpoint, 100 pt apart, 2° a step clockwise on screen.
    let c = CGPoint(x: 500, y: 300)
    var off = MacRig(turns: false)
    off.down(0, 450, 300); off.down(1, 550, 300)
    for k in 1...30 { off.moves(pair(c, 100, CGFloat(k) * 2 * .pi / 180)) }
    check("Rotate off: a turn about a still midpoint stays undecided and sends nothing", off.r.stroke.owner == .undecided && off.steps.isEmpty)
    var on = MacRig(turns: true)
    on.down(0, 450, 300); on.down(1, 550, 300)
    for k in 1...6 { on.moves(pair(c, 100, CGFloat(k) * 2 * .pi / 180)) }
    check("Rotate on: 12° turned (each finger 10.5 pt round): undecided still", on.r.stroke.owner == .undecided && on.steps.isEmpty)
    on.moves(pair(c, 100, 14 * .pi / 180))
    check("Rotate on: 14° (12.2 pt round): the Mac's pinch, by its turn", on.r.stroke.owner == .macPinch && !on.r.stroke.scrollsMac)
    check("Rotate on: the turn begins and catches up: clockwise on screen is the Mac's negative, 14°",
          phases(on.rotate) == [.began, .changed] && nearD(on.rotate[1].1, -14, 0.001))
    check("Rotate on: a turn alone opens no pinch", on.magnify.isEmpty)
    for k in 8...45 { on.moves(pair(c, 100, CGFloat(k) * 2 * .pi / 180)) }
    check("Rotate on: the turn's changes add up to the whole turn, 90° clockwise: -90", nearD(on.degrees, -90, 0.001))
    on.up(0); on.up(1)
    check("Rotate on: the lift ends the turn once", phases(on.rotate).filter { $0 == .ended }.count == 1 && phases(on.rotate).last == .ended && on.r.zoom == Z())
    // A turn whose midpoint moves as the pan begins: the pan's start decides it by the turn too, with Rotate on.
    var t = MacRig(turns: true)
    t.down(0, 450, 300); t.down(1, 550, 300)
    t.moves(pair(CGPoint(x: 500, y: 290), 100, 12 * .pi / 180))   // each finger 10.5 pt round, the midpoint 10 up
    check("Rotate on: a turn of 10.5 pt moving 10: undecided as it moves", t.r.stroke.owner == .undecided)
    t.pan()
    check("Rotate on: the pan's start with the turn more than the midpoint moved: the Mac's pinch, no scroll", t.r.stroke.owner == .macPinch && !t.r.scrolling)
    var u = MacRig(turns: false)
    u.down(0, 450, 300); u.down(1, 550, 300)
    u.moves(pair(CGPoint(x: 500, y: 290), 100, 12 * .pi / 180))
    u.pan()
    check("Rotate off: the same stroke is the Mac's scroll", u.r.stroke.owner == .mac && u.r.scrolling && u.steps.isEmpty)
    // Counterclockwise on screen: the Mac's positive.
    var ccw = MacRig(turns: true)
    ccw.down(0, 450, 300); ccw.down(1, 550, 300)
    for k in 1...20 { ccw.moves(pair(c, 100, -CGFloat(k) * 2 * .pi / 180)) }
    check("Rotate on: counterclockwise on screen is the Mac's positive (40°)", nearD(ccw.degrees, 40, 0.001))
    // Across the pair's ±180°: the right finger first (id 0 on the right), turning through the left-pointing angle.
    var wrap = MacRig(turns: true)
    wrap.down(0, 550, 300); wrap.down(1, 450, 300)
    for k in 1...20 { wrap.moves([0: (c.x + 50 * cos(CGFloat(k) * 2 * .pi / 180), c.y + 50 * sin(CGFloat(k) * 2 * .pi / 180)),
                                  1: (c.x - 50 * cos(CGFloat(k) * 2 * .pi / 180), c.y - 50 * sin(CGFloat(k) * 2 * .pi / 180))]) }
    check("Rotate on: a pair whose angle crosses ±180° turns the short way: -40, every step small",
          nearD(wrap.degrees, -40, 0.001) && wrap.rotate.allSatisfy { abs($0.1) < 20 })
    // The other way across it: landed just past -180° (1° round), turning back through +180°.
    var back = MacRig(turns: true)
    func turnedTo(_ deg: CGFloat) -> [Int: (CGFloat, CGFloat)] {
        let a = deg * .pi / 180
        return [0: (c.x + 50 * cos(a), c.y + 50 * sin(a)), 1: (c.x - 50 * cos(a), c.y - 50 * sin(a))]
    }
    back.down(0, turnedTo(1)[0]!.0, turnedTo(1)[0]!.1); back.down(1, turnedTo(1)[1]!.0, turnedTo(1)[1]!.1)
    for k in 1...20 { back.moves(turnedTo(1 - CGFloat(k) * 2)) }
    check("Rotate on: the other way across ±180°: +40 (counterclockwise on screen), every step small",
          nearD(back.degrees, 40, 0.001) && back.rotate.allSatisfy { abs($0.1) < 20 })
    // (Not an infinite angle here: were its guard gone, the check itself would never end.)
    check("a turn between angles that are not numbers is none; a whole turn none; the short way round",
          S.turned(from: 0, to: .nan) == 0 && S.turned(from: .nan, to: 1) == 0
          && near(S.turned(from: 3, to: 3 + 2 * .pi), 0) && near(S.turned(from: 3.1, to: -3.1), 2 * .pi - 6.2))
}

do {
    // A pinch that turns as it spreads, Rotate on: both, each from where the pair landed, the pinch first in a step.
    let c = CGPoint(x: 500, y: 300)
    var m = MacRig(turns: true)
    m.down(0, 450, 300); m.down(1, 550, 300)
    for k in 1...20 { m.moves(pair(c, 100 + CGFloat(k) * 4, CGFloat(k) * 1.5 * .pi / 180)) }
    check("Rotate on, a spread that turns: the Mac's pinch, both open", m.r.stroke.owner == .macPinch && phases(m.magnify).first == .began && phases(m.rotate).first == .began)
    check("Rotate on, a spread that turns: the whole spread (180 ÷ 100) and the whole turn (-30°)", nearD(m.scale, 1.8) && nearD(m.degrees, -30, 0.001))
    let firstTurn = m.steps.firstIndex { if case .rotate = $0 { return true }; return false }!
    let firstPinch = m.steps.firstIndex { if case .magnify = $0 { return true }; return false }!
    check("Rotate on, a spread that turns: the pinch opened first (its 12 pt came first)", firstPinch < firstTurn)
    m.silence()
    check("three fingers: both end, the pinch first, and the picture as it was",
          Array(m.steps.suffix(2)) == [.magnify(.ended, amount: 0), .rotate(.ended, degrees: 0)] && m.r.stroke.owner == .gesture && m.r.zoom == Z())
    m.moves([0: (300, 300), 1: (700, 300)])
    m.up(0); m.up(1)
    check("three fingers: nothing more for the Mac, to the stroke's end", phases(m.magnify).filter { $0 == .ended }.count == 1 && phases(m.rotate).filter { $0 == .ended }.count == 1)
    // Rotate off, a spread that turns: the pinch, and no turn at all.
    var spreadOff = MacRig(turns: false)
    spreadOff.down(0, 450, 300); spreadOff.down(1, 550, 300)
    for k in 1...20 { spreadOff.moves(pair(c, 100 + CGFloat(k) * 4, CGFloat(k) * 1.5 * .pi / 180)) }
    check("Rotate off, a spread that turns: the pinch alone, no turn", !spreadOff.magnify.isEmpty && spreadOff.rotate.isEmpty)
    // Rotate on, a spread alone: no turn.
    var s = MacRig(turns: true)
    s.down(0, 450, 300); s.down(1, 550, 300)
    for k in 1...20 { s.moves([0: (450 - CGFloat(k) * 3, 300), 1: (550 + CGFloat(k) * 3, 300)]) }
    check("Rotate on, a spread alone: the pinch, no turn", !s.magnify.isEmpty && s.rotate.isEmpty)
}

do {
    // One of the pair lifts and another lands: the pinch ends, then begins afresh from the new pair's landing, at the
    // stroke's place.
    var m = MacRig(turns: false)
    m.down(0, 470, 300); m.down(1, 530, 300)
    m.moves([0: (460, 300), 1: (540, 300)])
    check("a new pair: the first pinch open", phases(m.magnify) == [.began, .changed])
    m.up(0)
    check("a new pair: its lift ends it", phases(m.magnify) == [.began, .changed, .ended])
    m.down(2, 300, 500)
    m.moves([1: (540, 300), 2: (300, 500)])
    check("a new pair: nothing until it pinches", phases(m.magnify).count == 3)
    m.moves([1: (560, 300), 2: (280, 500)])
    check("a new pair: it pinches: a new began and its catch-up, at the stroke's place",
          phases(m.magnify) == [.began, .changed, .ended, .began, .changed] && m.r.stroke.macAt == CGPoint(x: 500, y: 300))
    m.up(1); m.up(2)
    check("a new pair: the lift ends it: two of each", phases(m.magnify).filter { $0 == .began }.count == 2 && phases(m.magnify).filter { $0 == .ended }.count == 2)
    // A pinch whose midpoint moves as it begins: the pan's start decides it by the same rule.
    var p = MacRig(turns: false)
    p.down(0, 470, 300); p.down(1, 530, 300)
    p.moves([0: (461, 306), 1: (539, 306)])   // spacing +18, midpoint 6
    check("a pinch moving as it spreads: decided as it moves", p.r.stroke.owner == .macPinch)
    var q = MacRig(turns: false)
    q.down(0, 470, 300); q.down(1, 530, 300)
    q.moves([0: (464.5, 290), 1: (535.5, 290)])   // spacing +11, midpoint 10: undecided as it moves
    check("a pinch of 11 pt moving 10: undecided as it moves", q.r.stroke.owner == .undecided)
    q.pan()
    check("the pan's start with the spacing changed more than the midpoint moved: the Mac's pinch, no scroll, nothing sent yet (under 12 pt)",
          q.r.stroke.owner == .macPinch && !q.r.scrolling && q.steps.isEmpty)
    q.moves([0: (450, 290), 1: (550, 290)])
    check("…and it opens once it has pinched 12 pt", phases(q.magnify) == [.began, .changed] && nearD(q.scale, 100.0 / 60.0))
    // Zoom on Mac on a zoomed picture (the choice made while zoomed: StreamScreen undoes the zoom, but were it not):
    // two fingers are not the picture's at once, and nothing zooms.
    let start = zoomed(2, at: CGPoint(x: 300, y: 300), in: CGSize(width: 1000, height: 650))
    var z = MacRig(turns: false, zoom: start)
    z.down(0, 460, 400); z.down(1, 540, 400)
    check("Zoom on Mac on a zoomed picture: two fingers undecided, not the picture's", z.r.stroke.owner == .undecided)
    for k in 1...20 { z.moves([0: (460 - CGFloat(k) * 3, 400), 1: (540 + CGFloat(k) * 3, 400)]) }
    z.up(0); z.up(1)
    check("Zoom on Mac on a zoomed picture: the pinch is the Mac's and the zoom stays as it was", z.r.zoom == start && !z.magnify.isEmpty)
}

do {
    // 20,000 random strokes under Zoom on ‹Mac›, turns or not: the invariants of a stroke that sends the Mac's pinch.
    var rng = SystemRandomNumberGenerator()
    var ok1 = true, ok2 = true, ok3 = true, ok4 = true, ok5 = true, ok6 = true
    var pinched = 0, turned = 0, scrolled = 0
    for _ in 0..<20_000 {
        let turns = Bool.random(using: &rng)
        var m = MacRig(turns: turns)
        let fingers = Int.random(in: 1...3, using: &rng)
        let landed: [CGPoint] = (0..<fingers).map { _ in CGPoint(x: .random(in: 100...900, using: &rng), y: .random(in: 100...550, using: &rng)) }
        let dir = CGPoint(x: .random(in: -8...8, using: &rng), y: .random(in: -8...8, using: &rng))
        let spread = CGFloat.random(in: 0.9...1.1, using: &rng)
        let spin = CGFloat.random(in: -0.08...0.08, using: &rng)
        let kind = Int.random(in: 0...2, using: &rng)   // 0 parallel, 1 spread, 2 turn and spread
        for (i, p) in landed.enumerated() {
            if i == 2 { m.silence() }
            m.down(i, p.x, p.y)
        }
        let c = CGPoint(x: landed.map(\.x).reduce(0, +) / CGFloat(fingers), y: landed.map(\.y).reduce(0, +) / CGFloat(fingers))
        let steps = Int.random(in: 1...30, using: &rng)
        let lift = Int.random(in: 0...steps, using: &rng)
        var lifted: Set<Int> = []
        var positions = landed
        for step in 1...steps {
            if step == lift, fingers >= 2 { lifted.insert(0); m.up(0) }
            var event: [Int: (CGFloat, CGFloat)] = [:]
            for i in 0..<fingers where !lifted.contains(i) {
                let v = CGPoint(x: landed[i].x - c.x, y: landed[i].y - c.y)
                let a = spin * CGFloat(step), s = pow(spread, CGFloat(step))
                let p: CGPoint
                switch kind {
                case 0: p = CGPoint(x: landed[i].x + dir.x * CGFloat(step), y: landed[i].y + dir.y * CGFloat(step))
                case 1: p = CGPoint(x: c.x + v.x * s, y: c.y + v.y * s)
                default: p = CGPoint(x: c.x + (v.x * cos(a) - v.y * sin(a)) * s, y: c.y + (v.x * sin(a) + v.y * cos(a)) * s)
                }
                positions[i] = p
                event[i] = (p.x, p.y)
            }
            m.moves(event)
            let down = (0..<fingers).filter { !lifted.contains($0) }
            if !down.isEmpty {
                let now = CGPoint(x: down.map { positions[$0].x }.reduce(0, +) / CGFloat(down.count), y: down.map { positions[$0].y }.reduce(0, +) / CGFloat(down.count))
                let then = CGPoint(x: down.map { landed[$0].x }.reduce(0, +) / CGFloat(down.count), y: down.map { landed[$0].y }.reduce(0, +) / CGFloat(down.count))
                if hypot(now.x - then.x, now.y - then.y) >= 10 { m.pan() }
            }
            if m.r.stroke.owner == .picture { ok1 = false }
        }
        for i in 0..<fingers where !lifted.contains(i) { m.up(i) }
        // 1: never the picture's, and the picture never changes.
        if m.r.zoom != Z() { ok1 = false }
        // 2: a stroke is the Mac's scroll or its pinch, never both.
        if m.r.scrolling && !m.steps.isEmpty { ok2 = false }
        // 3: each of the two in order (began, changed…, ended), every began ended by the stroke's end.
        for list in [m.magnify, m.rotate] {
            var open = false
            for (phase, _) in list {
                switch phase {
                case .began: if open { ok3 = false }; open = true
                case .changed: if !open { ok3 = false }
                case .ended: if !open { ok3 = false }; open = false
                }
            }
            if open { ok3 = false }
        }
        // 4: no turn with Rotate off.
        if !turns && !m.rotate.isEmpty { ok4 = false }
        // 5: every value a number; a began and an ended carry 0.
        if !m.steps.allSatisfy({ s in
            switch s {
            case .magnify(let p, let v), .rotate(let p, let v): return v.isFinite && (p == .changed || v == 0)
            }
        }) { ok5 = false }
        // 6: three fingers send the Mac no pinch: whatever a third finger found open ends, and nothing begins after.
        if fingers == 3 && !m.steps.allSatisfy({ s in
            switch s { case .magnify(let p, _), .rotate(let p, _): return p != .began && p != .changed }
        }) { ok6 = false }
        if m.r.stroke.owner != .none { ok2 = false }
        if !m.magnify.isEmpty { pinched += 1 }
        if !m.rotate.isEmpty { turned += 1 }
        if m.r.scrolling { scrolled += 1 }
    }
    print("  (Zoom on Mac: \(pinched) strokes pinched, \(turned) turned, \(scrolled) the Mac's scroll)")
    check("20,000 random strokes under Zoom on Mac: never the picture's, the picture never changed", ok1)
    check("20,000 random strokes under Zoom on Mac: the Mac's scroll or its pinch, never both, and over at the last lift", ok2)
    check("20,000 random strokes under Zoom on Mac: each gesture began, changed…, ended, and ended by the stroke's end", ok3)
    check("20,000 random strokes under Zoom on Mac: no turn with Rotate off", ok4)
    check("20,000 random strokes under Zoom on Mac: every value a number, a began's and an ended's 0", ok5)
    check("20,000 random strokes under Zoom on Mac: three fingers (silenced before they move) send no pinch", ok6)
    check("20,000 random strokes under Zoom on Mac: some pinched, some turned, some scrolled", pinched > 1000 && turned > 500 && scrolled > 1000)
}

// MARK: - 20,000 random strokes

do {
    var rng = SystemRandomNumberGenerator()
    let size = CGSize(width: 1000, height: 650)
    var i1 = true, i2 = true, i3 = true, i4 = true, i5 = true, i6 = true, i7 = true
    var pinches = 0, scrolls = 0, gestures = 0
    for _ in 0..<20_000 {
        let start: Z = Bool.random(using: &rng) ? Z() : zoomed(.random(in: 1.1...5, using: &rng), at: CGPoint(x: .random(in: 0...1000, using: &rng), y: .random(in: 0...650, using: &rng)), in: size)
        var r = Rig(start)
        let fingers = Int.random(in: 1...3, using: &rng)
        let parallel = Bool.random(using: &rng)
        var positions: [CGPoint] = (0..<fingers).map { _ in CGPoint(x: .random(in: 100...900, using: &rng), y: .random(in: 100...550, using: &rng)) }
        let landed = positions
        let dir = CGPoint(x: .random(in: -8...8, using: &rng), y: .random(in: -8...8, using: &rng))
        let spread = CGFloat.random(in: 0.9...1.1, using: &rng)
        var owners: [S.Owner] = []
        for (i, p) in positions.enumerated() {
            if i == 2 { r.silence() }   // a third finger: TrackpadGestures silences (it landed before any moved 24 pt)
            r.down(i, p.x, p.y)
        }
        let steps = Int.random(in: 1...30, using: &rng)
        let lift = Int.random(in: 0...steps, using: &rng)
        var lifted: Set<Int> = []
        for step in 1...steps {
            let before = r.zoom, owner = r.stroke.owner
            if step == lift, fingers >= 2 { lifted.insert(0); r.up(0) }
            var event: [Int: (CGFloat, CGFloat)] = [:]
            for i in 0..<fingers where !lifted.contains(i) {
                let c = CGPoint(x: landed.map(\.x).reduce(0, +) / CGFloat(fingers), y: landed.map(\.y).reduce(0, +) / CGFloat(fingers))
                let target = parallel
                    ? CGPoint(x: landed[i].x + dir.x * CGFloat(step), y: landed[i].y + dir.y * CGFloat(step))
                    : CGPoint(x: c.x + (landed[i].x - c.x) * pow(spread, CGFloat(step)), y: c.y + (landed[i].y - c.y) * pow(spread, CGFloat(step)))
                positions[i] = target
                event[i] = (target.x, target.y)
            }
            r.moves(event)
            // UIKit's pan begins once the midpoint of the fingers down has moved 10 pt.
            let down = (0..<fingers).filter { !lifted.contains($0) }
            if !down.isEmpty {
                let now = CGPoint(x: down.map { positions[$0].x }.reduce(0, +) / CGFloat(down.count), y: down.map { positions[$0].y }.reduce(0, +) / CGFloat(down.count))
                let then = CGPoint(x: down.map { landed[$0].x }.reduce(0, +) / CGFloat(down.count), y: down.map { landed[$0].y }.reduce(0, +) / CGFloat(down.count))
                if hypot(now.x - then.x, now.y - then.y) >= 10 { r.pan() }
            }
            // I1: the zoom changes only while the picture owns the stroke.
            if r.zoom != before && !(owner == .picture || r.stroke.owner == .picture) { i1 = false }
            // I2: 1× to 5×, and the picture covers its pane.
            if !inRange(r.zoom) || !covers(r.zoom, size) { i2 = false }
            owners.append(r.stroke.owner)
        }
        // I3: a stroke the Mac's pan began in never zooms.
        if r.scrolling && r.zoom != start { i3 = false }
        // I4: a stroke three fingers took leaves the picture as it found it.
        if fingers == 3 && r.zoom != start { i4 = false }
        // I5: one finger never zooms.
        if fingers == 1 && (r.zoom != start || !r.scrolling && r.panBegun) { i5 = false }
        // I6: once the Mac's or the picture's, the stroke stays so (or goes to the gesture).
        var decided: S.Owner? = nil
        for o in owners where o == .mac || o == .picture || o == .gesture {
            if let d = decided, d != o, o != .gesture { i6 = false }
            decided = o
        }
        // I7: two fingers in parallel on the whole picture are never the picture's.
        if fingers == 2 && parallel && !start.isZoomed && owners.contains(.picture) { i7 = false }
        for i in 0..<fingers where !lifted.contains(i) { r.up(i) }
        if r.stroke.owner != .none { i6 = false }
        if owners.contains(.picture) { pinches += 1 }
        if r.scrolling { scrolls += 1 }
        if fingers == 3 { gestures += 1 }
    }
    print("  (\(pinches) strokes the picture's, \(scrolls) the Mac's scroll, \(gestures) three-finger)")
    check("20,000 random strokes: the zoom changes only while the picture owns the stroke", i1)
    check("20,000 random strokes: 1× to 5×, the picture covering its pane", i2)
    check("20,000 random strokes: a stroke the Mac's scroll began in never zooms", i3)
    check("20,000 random strokes: three fingers leave the picture as they found it", i4)
    check("20,000 random strokes: one finger never zooms and its pan is always the Mac's", i5)
    check("20,000 random strokes: a decided stroke keeps its owner to its last finger, and then it is over", i6)
    check("20,000 random strokes: two fingers in parallel on the whole picture are never the picture's", i7)
}

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
