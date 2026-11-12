// TEST ONLY (Tests/touchrig, never in the app): drives the real TrackpadSurface (TrackpadView.swift) and
// InputOverlayView (InputOverlay.swift) with synthesized one- to five-finger touches (TouchSynth), and
// logs every InputEvent each would send to the Mac and every gesture it decides. Nothing leaves the
// process: `send` and `sendGesture` only log. H7 of docs/trackpad-gestures-plan.md runs it twice, on
// the surfaces before the gestures and on this branch's, and compare.py judges the two logs.
//
// Environment (simctl launch's SIMCTL_CHILD_ prefix): RIG_SWITCH=off makes `sendGesture` answer false,
// as StreamClient does with the device's switch off; RIG_TRACE=1 also logs recognizer transitions.
import UIKit
import SwiftUI

// MARK: - Log

final class RigLog {
    static var t0 = CACurrentMediaTime()
    static var lines: [String] = []
    static func log(_ s: String) {
        let ms = Int((CACurrentMediaTime() - t0) * 1000)
        lines.append(String(format: "%5d ", ms) + s)
    }
    static func flush(_ title: String) {
        print("=== \(title)")
        lines.forEach { print($0) }
        lines = []
    }
}

func f(_ d: Double) -> String { String(format: "%.4f", d) }
func describe(_ e: InputEvent) -> String {
    switch e {
    case .pointer(let a, let x, let y): return "pointer.\(a.rawValue)(\(f(x)),\(f(y)))"
    case .scroll(_, _, let dx, let dy): return "scroll(\(f(dx)),\(f(dy)))"
    case .scrollGesture(let p, _, _): return "scrollGesture.\(p.rawValue)"
    case .key(let u, let d, let m): return "key(0x\(String(u, radix: 16)) \(d ? "down" : "up") mods=0x\(String(m, radix: 16)))"
    case .text(let s): return "text(\(s.debugDescription))"
    }
}

// MARK: - Recognizer tracing (RIG_TRACE=1)

final class Tracer: NSObject {
    static let shared = Tracer()
    private var names: [ObjectIdentifier: String] = [:]
    private var observations: [NSKeyValueObservation] = []
    private var last: [ObjectIdentifier: UIGestureRecognizer.State] = [:]
    func trace(_ g: UIGestureRecognizer, as name: String) {
        let id = ObjectIdentifier(g)
        names[id] = name
        observations.append(g.observe(\.state, options: [.new]) { [weak self] g, _ in
            guard let self, self.last[id] != g.state else { return }
            self.last[id] = g.state
            if g.state != .changed { RigLog.log("  [\(self.names[id] ?? "?")] \(g.state.rawValue) n=\(g.numberOfTouches)") }
        })
    }
}

// MARK: - Scenarios

enum Step {
    case begin([CGPoint])
    case move([CGPoint])
    case end([Int])
    case cancel
    case wait(Int)
    /// The picture's zoom (#65): set to `factor` about a point of the overlay (from 1×), and logged.
    case zoom(CGFloat, CGPoint)
    case logZoom
    /// Full screen's flick (docs/full-screen-plan.md): the surfaces against the window's left edge (true), or
    /// back inside their margins; the flick's recognizer listening or not.
    case edgeLayout(Bool)
    case arm(Bool)
    /// The swipe in from the left bezel listening (the controls hidden), or not.
    case reveal(Bool)
    /// A measuring pan on the overlay (beside everything, taking nothing) says where UIKit lets a pan begin.
    case measure(Bool)
}

/// UIKit's own pan threshold, measured: a pan beside every other recognizer, taking no touch, that logs its
/// translation as it begins (full screen's flick lets a drag right go after 6 pt and a steep one after 8, which
/// is before a pan would begin, so those drags are not even late: docs/full-screen-plan.md).
final class PanProbe: NSObject, UIGestureRecognizerDelegate {
    let pan = UIPanGestureRecognizer()
    override init() {
        super.init()
        pan.addTarget(self, action: #selector(moved))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        pan.isEnabled = false
    }
    @objc func moved() {
        if pan.state == .began {
            let t = pan.translation(in: pan.view)
            RigLog.log(String(format: "[measure] a pan begins at %.1f pt (%.1f, %.1f)", hypot(t.x, t.y), t.x, t.y))
        }
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
let panProbe = PanProbe()

enum Gesture {
    static let spacing: CGFloat = 62

    static func fingers(_ n: Int, around c: CGPoint) -> [CGPoint] {
        // A slight arc, as fingers of one hand land.
        let offsets: [CGPoint]
        switch n {
        case 5: offsets = [CGPoint(x: -2, y: 0.4), CGPoint(x: -1, y: 0.2), CGPoint(x: 0, y: -0.15), CGPoint(x: 1, y: 0.1), CGPoint(x: 2, y: 0.5)]
        case 4: offsets = [CGPoint(x: -1.5, y: 0.25), CGPoint(x: -0.5, y: -0.15), CGPoint(x: 0.5, y: -0.2), CGPoint(x: 1.5, y: 0.2)]
        case 3: offsets = [CGPoint(x: -1, y: 0.2), CGPoint(x: 0, y: -0.15), CGPoint(x: 1, y: 0.1)]
        case 2: offsets = [CGPoint(x: -0.5, y: 0), CGPoint(x: 0.5, y: -0.1)]
        default: offsets = [.zero]
        }
        return offsets.map { CGPoint(x: c.x + $0.x * spacing, y: c.y + $0.y * spacing) }
    }

    /// Lands `start` one finger per `stagger` frames (0: all in one event), holds `hold` frames, moves
    /// every finger to `end` over `frames` frames, then lifts one per `liftStagger` frames.
    static func stroke(_ start: [CGPoint], to end: [CGPoint], frames: Int, stagger: Int = 1, hold: Int = 0,
                       liftStagger: Int = 1) -> [Step] {
        var steps: [Step] = []
        if stagger == 0 { steps.append(.begin(start)) } else {
            for (i, p) in start.enumerated() {
                steps.append(.begin([p]))
                if i < start.count - 1, stagger > 1 { steps.append(.wait(stagger - 1)) }
            }
        }
        if hold > 0 { steps.append(.wait(hold)) }
        for k in 1...max(frames, 1) {
            let t = CGFloat(k) / CGFloat(max(frames, 1))
            steps.append(.move(zip(start, end).map { CGPoint(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }))
        }
        if liftStagger == 0 { steps.append(.end(Array(0..<start.count))) } else {
            for i in 0..<start.count {
                steps.append(.end([0]))
                if i < start.count - 1, liftStagger > 1 { steps.append(.wait(liftStagger - 1)) }
            }
        }
        return steps
    }

    static func swipe(_ n: Int, at c: CGPoint, dx: CGFloat, dy: CGFloat, frames: Int = 10, stagger: Int = 1,
                      hold: Int = 0, liftStagger: Int = 1) -> [Step] {
        let s = fingers(n, around: c)
        return stroke(s, to: s.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }, frames: frames, stagger: stagger,
                      hold: hold, liftStagger: liftStagger)
    }

    static func pinch(_ n: Int, at c: CGPoint, scale: CGFloat, frames: Int = 12, stagger: Int = 1) -> [Step] {
        let s = fingers(n, around: c)
        let centroid = CGPoint(x: s.map(\.x).reduce(0, +) / CGFloat(n), y: s.map(\.y).reduce(0, +) / CGFloat(n))
        let e = s.map { CGPoint(x: centroid.x + ($0.x - centroid.x) * scale, y: centroid.y + ($0.y - centroid.y) * scale) }
        return stroke(s, to: e, frames: frames, stagger: stagger)
    }

    static func tap(_ n: Int, at c: CGPoint, holdFrames: Int = 4) -> [Step] {
        let s = fingers(n, around: c)
        return [.begin(s), .wait(holdFrames), .end(Array(0..<n))]
    }
}

/// Every scenario, the same on both surfaces: the one- and two-finger strokes whose events must not
/// change, and the three-, four- and five-finger strokes of the plan's §2.1 table.
func scenarios(_ c: CGPoint) -> [(String, [Step])] {
    var out: [(String, [Step])] = [
        ("1-finger tap", Gesture.tap(1, at: c)),
        ("1-finger drag right 120", Gesture.swipe(1, at: c, dx: 120, dy: 0, frames: 12)),
        ("1-finger hold 0.6 s, then move 60 and lift", Gesture.swipe(1, at: c, dx: 60, dy: 30, frames: 10, hold: 36)),
        ("2-finger scroll up 150 (flick)", Gesture.swipe(2, at: c, dx: 0, dy: -150, frames: 8)),
        ("2-finger scroll down 90, slowly", Gesture.swipe(2, at: c, dx: 0, dy: 90, frames: 40)),
        ("2-finger tap", Gesture.tap(2, at: c)),
        ("3-finger swipe up, landing 16 ms apart", Gesture.swipe(3, at: c, dx: 0, dy: -180, frames: 10)),
        ("3-finger swipe up, landing together", Gesture.swipe(3, at: c, dx: 0, dy: -180, frames: 10, stagger: 0, liftStagger: 0)),
        ("3-finger swipe left, landing 16 ms apart", Gesture.swipe(3, at: c, dx: -200, dy: 0, frames: 10)),
        ("3-finger swipe right, landing 16 ms apart", Gesture.swipe(3, at: c, dx: 200, dy: 0, frames: 10)),
        ("3-finger swipe down, landing 50 ms apart", Gesture.swipe(3, at: c, dx: 0, dy: 180, frames: 10, stagger: 3)),
        ("3-finger pinch in (to 0.45)", Gesture.pinch(3, at: c, scale: 0.45)),
        ("3-finger spread (to 1.8)", Gesture.pinch(3, at: c, scale: 1.8)),
        ("3-finger rest 0.6 s, then swipe up", Gesture.swipe(3, at: c, dx: 0, dy: -180, frames: 10, stagger: 1, hold: 36)),
        ("3-finger tap", Gesture.tap(3, at: c)),
    ]
    let f3 = Gesture.fingers(3, around: c)
    var nudge: [Step] = [.begin([f3[0]])]
    for k in 1...3 { nudge.append(.move([CGPoint(x: f3[0].x, y: f3[0].y - CGFloat(k) * 4)])) }
    nudge.append(.begin([f3[1]])); nudge.append(.begin([f3[2]]))
    for k in 1...10 {
        nudge.append(.move([CGPoint(x: f3[0].x, y: f3[0].y - 12 - CGFloat(k) * 17), CGPoint(x: f3[1].x, y: f3[1].y - CGFloat(k) * 17),
                            CGPoint(x: f3[2].x, y: f3[2].y - CGFloat(k) * 17)]))
    }
    nudge += [.end([0]), .end([0]), .end([0])]
    out.append(("3-finger swipe up, first finger moves 12 pt before the others land", nudge))
    // Two scrolling, then a third lands 133 ms after the first and all carry on: never a gesture.
    let two = Gesture.fingers(2, around: c)
    let third = CGPoint(x: c.x + 1.5 * Gesture.spacing, y: c.y)
    var late: [Step] = [.begin([two[0]]), .begin([two[1]])]
    for k in 1...6 { late.append(.move(two.map { CGPoint(x: $0.x, y: $0.y - CGFloat(k) * 10) })) }
    late.append(.begin([CGPoint(x: third.x, y: third.y - 60)]))
    for k in 1...10 {
        let d = 60 + CGFloat(k) * 12
        late.append(.move((two + [third]).map { CGPoint(x: $0.x, y: $0.y - d) }))
    }
    late += [.end([0]), .end([0]), .end([0])]
    out.append(("2 fingers scroll 60, a 3rd lands 133 ms after the first, all move 120 more", late))
    // Three moving, one lifts, two carry on: the lift decides.
    var r: [Step] = [.begin([f3[0]]), .begin([f3[1]]), .begin([f3[2]])]
    for k in 1...5 { r.append(.move(f3.map { CGPoint(x: $0.x, y: $0.y - CGFloat(k) * 12) })) }
    r.append(.end([2]))
    for k in 1...10 { r.append(.move(f3.prefix(2).map { CGPoint(x: $0.x, y: $0.y - 60 - CGFloat(k) * 12) })) }
    r += [.end([0]), .end([0])]
    out.append(("3 fingers move 60, one lifts, two move 120 more", r))
    out.append(("4-finger swipe up, landing 16 ms apart", Gesture.swipe(4, at: c, dx: 0, dy: -180, frames: 10)))
    out.append(("5-finger swipe up, landing 16 ms apart", Gesture.swipe(5, at: c, dx: 0, dy: -180, frames: 10)))
    out.append(("3-finger swipe up then cancelled mid-way", Array(Gesture.swipe(3, at: c, dx: 0, dy: -180, frames: 10).prefix(8)) + [.cancel]))
    return out + reviewScenarios(c, nudge: nudge)
}

#if ZOOM
/// The picture's zoom (#65, #196), the overlay only: who two fingers belong to (the Mac's scroll or the
/// picture), the zoom each stroke leaves (`zoom:` lines), and what reaches the Mac meanwhile.
func zoomScenarios(_ c: CGPoint) -> [(String, [Step])] {
    var out: [(String, [Step])] = []
    let two = Gesture.fingers(2, around: c)
    out.append(("2-finger spread to 2.5 about a still midpoint", [.zoom(1, c)] + Gesture.pinch(2, at: c, scale: 2.5) + [.logZoom]))
    out.append(("zoomed 2x: 2-finger scroll up 150", [.zoom(2, c)] + Gesture.swipe(2, at: c, dx: 0, dy: -150, frames: 8) + [.logZoom]))
    out.append(("zoomed 2x: 1-finger drag right 120", [.zoom(2, c)] + Gesture.swipe(1, at: c, dx: 120, dy: 0, frames: 12) + [.logZoom]))
    out.append(("zoomed 2x: 1-finger tap", [.zoom(2, c)] + Gesture.tap(1, at: CGPoint(x: c.x + 40, y: c.y - 30)) + [.logZoom]))
    out.append(("at 2.5x: 2-finger pinch in to 0.3 (all the way out)", [.zoom(2.5, c)] + Gesture.pinch(2, at: c, scale: 0.3) + [.logZoom]))
    // A two-finger scroll whose fingers drift 8 pt apart over 150: the Mac's, as before.
    let drift = [CGPoint(x: two[0].x - 4, y: two[0].y - 150), CGPoint(x: two[1].x + 4, y: two[1].y - 150)]
    out.append(("at 1x: 2-finger scroll up 150, the fingers drifting 8 pt apart", [.zoom(1, c)] + Gesture.stroke(two, to: drift, frames: 8) + [.logZoom]))
    // A pinch led by one finger: one still, the other 120 pt further away.
    let led = [two[0], CGPoint(x: two[1].x + 120, y: two[1].y)]
    out.append(("at 1x: a spread led by one finger, 120 pt", [.zoom(1, c)] + Gesture.stroke(two, to: led, frames: 12) + [.logZoom]))
    // A spread to 2, then one finger lifts and the other moves 100 pt: nothing for the Mac (#196's first version
    // scrolled it by the pan's whole translation, outside a gesture).
    let spread = two.map { CGPoint(x: c.x + ($0.x - c.x) * 2, y: c.y + ($0.y - c.y) * 2) }
    var lift: [Step] = [.zoom(1, c)] + Array(Gesture.stroke(two, to: spread, frames: 10).dropLast(2))
    lift.append(.end([0]))
    for k in 1...10 { lift.append(.move([CGPoint(x: spread[1].x - CGFloat(k) * 10, y: spread[1].y - CGFloat(k) * 4)])) }
    lift += [.end([0]), .logZoom]
    out.append(("at 1x: a spread to 2, one finger lifts, the other moves 100", lift))
    out.append(("zoomed 2x: 3-finger spread (to 1.8)", [.zoom(2, c)] + Gesture.pinch(3, at: c, scale: 1.8) + [.logZoom]))
    // One finger scrolling 30 pt, then a second lands and both spread: a scroll, never a zoom.
    var join: [Step] = [.zoom(1, c), .begin([two[0]])]
    for k in 1...3 { join.append(.move([CGPoint(x: two[0].x, y: two[0].y - CGFloat(k) * 10)])) }
    join.append(.begin([CGPoint(x: two[1].x, y: two[1].y - 30)]))
    for k in 1...10 { join.append(.move([CGPoint(x: two[0].x - CGFloat(k) * 8, y: two[0].y - 30), CGPoint(x: two[1].x + CGFloat(k) * 8, y: two[1].y - 30)])) }
    join += [.end([0]), .end([0]), .logZoom]
    out.append(("at 1x: a 1-finger scroll of 30, a 2nd lands, both spread", join))
    out.append(("at 1.5x: 2-finger pinch in to 0.675 (1.01x) and lift", [.zoom(1.5, c)] + Gesture.pinch(2, at: c, scale: 0.675) + [.logZoom]))
    // A two-finger scroll whose fingers drift 30 pt apart over 150: the Mac's still.
    let wide = [CGPoint(x: two[0].x - 15, y: two[0].y - 150), CGPoint(x: two[1].x + 15, y: two[1].y - 150)]
    out.append(("at 1x: 2-finger scroll up 150, the fingers drifting 30 pt apart", [.zoom(1, c)] + Gesture.stroke(two, to: wide, frames: 8) + [.logZoom]))
    // A spread led by one finger (its midpoint moves, so the finger pan begins too), then the still finger lifts and
    // the other moves on 100 pt: nothing for the Mac (#196's first version sent the pan's whole translation).
    var ledLift: [Step] = [.zoom(1, c)] + Array(Gesture.stroke(two, to: led, frames: 12).dropLast(2))
    ledLift.append(.end([0]))
    for k in 1...10 { ledLift.append(.move([CGPoint(x: led[1].x - CGFloat(k) * 4, y: led[1].y - CGFloat(k) * 10)])) }
    ledLift += [.end([0]), .logZoom]
    out.append(("at 1x: a spread led by one finger, the still one lifts, the other moves on 100", ledLift))
    return out
}
#endif

/// Full screen's flick off the left edge (docs/full-screen-plan.md, EdgeFlickRecognizer.swift), the same on
/// both surfaces, laid against the window's left edge so x is the screen's: `EDGE HIDE` strokes must hide and
/// send nothing; `EDGE ON` strokes start in the band (or end at the edge) and must go on whole, in order, as the
/// surfaces before the flick send them (compare.py --edge); `EDGE DISARMED` is a flick while the recognizer
/// does not listen, the surfaces' own as before.
func edgeScenarios(_ y: CGFloat) -> [(String, [Step])] {
    func path(_ xs: [CGFloat], dy: CGFloat = 0, rest: Int = 0) -> [Step] {
        var steps: [Step] = [.begin([CGPoint(x: xs[0], y: y)])]
        if rest > 0 { steps.append(.wait(rest)) }
        for (i, x) in xs.dropFirst().enumerated() { steps.append(.move([CGPoint(x: x, y: y + dy * CGFloat(i + 1))])) }
        return steps + [.end([0])]
    }
    var out: [(String, [Step])] = []
    // The strokes that go on come first: the trackpad's pointer is relative, so every stroke before them is the
    // same on both builds; then the hides, which move nothing; then the flick while the recognizer does not listen.
    out.append(("EDGE ON a tap in the band", Gesture.tap(1, at: CGPoint(x: 20, y: y))))
    out.append(("EDGE ON a long press in the band, 0.6 s", [.begin([CGPoint(x: 24, y: y)]), .wait(36), .end([0])]))
    out.append(("EDGE ON a drag right from the band", Gesture.swipe(1, at: CGPoint(x: 20, y: y), dx: 120, dy: 0, frames: 12)))
    out.append(("EDGE ON a drag down in the band", Gesture.swipe(1, at: CGPoint(x: 24, y: y), dx: 2, dy: 150, frames: 12)))
    out.append(("EDGE ON a drag up in the band", Gesture.swipe(1, at: CGPoint(x: 24, y: y), dx: -2, dy: -150, frames: 12)))
    out.append(("EDGE ON a slow drag left to the edge (40 pt in 0.5 s)", Gesture.swipe(1, at: CGPoint(x: 44, y: y), dx: -40, dy: 0, frames: 30)))
    out.append(("EDGE ON a quick drag left lifted 26 pt in", path([48, 40, 32, 26])))
    out.append(("EDGE ON two fingers from the band, up 150", Gesture.stroke([CGPoint(x: 20, y: y), CGPoint(x: 80, y: y)],
                                                                             to: [CGPoint(x: 20, y: y - 150), CGPoint(x: 80, y: y - 150)], frames: 8)))
    out.append(("EDGE ON a scroll from the middle off the left edge", Gesture.swipe(1, at: CGPoint(x: 300, y: y), dx: -300, dy: 0, frames: 10)))
    out.append(("EDGE ON a grip resting at the edge, a tap elsewhere", [.begin([CGPoint(x: 6, y: y + 60)]), .wait(18),
                                                                       .begin([CGPoint(x: 300, y: y)]), .wait(4), .end([1]), .wait(10), .end([0])]))
    out.append(("EDGE HIDE a flick off the edge from 30 pt", path([30, 15, 2])))
    out.append(("EDGE HIDE a flick stopped by a case's lip 22 pt in", path([46, 34, 22])))
    out.append(("EDGE HIDE a flick 45° down from 40 pt", path([40, 26, 12, 2], dy: 13)))
    out.append(("EDGE HIDE a flick after a 0.1 s rest", path([36, 24, 12, 2], rest: 6)))
    out.append(("EDGE DISARMED a flick off the edge from 30 pt", [.arm(false)] + path([30, 15, 2]) + [.wait(60), .arm(true)]))
    // The controls hidden: the flick does not listen, the swipe in from the bezel does (RevealEdgePan). A swipe
    // in is the controls' and nothing else; a stroke elsewhere on the picture is the Mac's, whole.
    func hiddenRun(_ steps: [Step]) -> [Step] { [.arm(false), .reveal(true)] + steps + [.wait(60), .reveal(false), .arm(true)] }
    out.append(("EDGE REVEAL a swipe in from the bezel", hiddenRun(path([0.5, 30, 70, 120, 180, 240]))))
    out.append(("EDGE REVEALOFF a tap in the middle while hidden", hiddenRun(Gesture.tap(1, at: CGPoint(x: 300, y: y)))))
    out.append(("EDGE REVEALOFF a drag right in the middle while hidden", hiddenRun(Gesture.swipe(1, at: CGPoint(x: 300, y: y), dx: 120, dy: 0, frames: 12))))
    out.append(("EDGE REVEALOFF a drag left near the edge while hidden", hiddenRun(Gesture.swipe(1, at: CGPoint(x: 60, y: y), dx: -50, dy: 0, frames: 8))))
    out.append(("EDGE REVEALOFF a tap 20 pt from the edge while hidden", hiddenRun(Gesture.tap(1, at: CGPoint(x: 20, y: y)))))
    out.append(("EDGE REVEALOFF a long press 20 pt from the edge while hidden", hiddenRun([.begin([CGPoint(x: 20, y: y)]), .wait(36), .end([0])])))
    out.append(("EDGE REVEALOFF a drag down 20 pt from the edge while hidden", hiddenRun(Gesture.swipe(1, at: CGPoint(x: 20, y: y), dx: 0, dy: 150, frames: 12))))
    return out
}

/// The review's strokes (2026-09-27): fingers placed slowly, a thumb resting on the glass, a pinch led by
/// the thumb, the Mac's own thumb-and-three-finger pinch, a brief extra contact, and one- and two-finger
/// strokes made right after a gesture on the same surface (compare.py holds them to the same strokes made
/// fresh).
func reviewScenarios(_ c: CGPoint, nudge: [Step]) -> [(String, [Step])] {
    var out: [(String, [Step])] = []
    let f3 = Gesture.fingers(3, around: c)
    // Placed slowly: the third finger lands 200 ms after the first (100 ms apart).
    out.append(("3-finger pinch in (to 0.45), landing 100 ms apart", Gesture.pinch(3, at: c, scale: 0.45, stagger: 6)))
    out.append(("3-finger swipe up 180, landing 100 ms apart", Gesture.swipe(3, at: c, dx: 0, dy: -180, frames: 10, stagger: 6)))
    // A thumb resting 0.3 s (under the long press's 0.45 s), then three fingers land 16 ms apart.
    let thumb = CGPoint(x: c.x - 160, y: c.y + 90)
    var rest: [Step] = [.begin([thumb]), .wait(18)]
    for p in f3 { rest.append(.begin([p])) }
    for k in 1...10 { rest.append(.move([thumb] + f3.map { CGPoint(x: $0.x, y: $0.y - CGFloat(k) * 18) })) }
    rest += [.end([1]), .end([1]), .end([1]), .end([0])]
    out.append(("a thumb resting 0.3 s, then three fingers swipe up 180", rest))
    var restPinch: [Step] = [.begin([thumb]), .wait(18)]
    for p in f3 { restPinch.append(.begin([p])) }
    let centre = CGPoint(x: f3.map(\.x).reduce(0, +) / 3, y: f3.map(\.y).reduce(0, +) / 3)
    for k in 1...12 {
        let s = 1 - 0.55 * CGFloat(k) / 12
        restPinch.append(.move([thumb] + f3.map { CGPoint(x: centre.x + ($0.x - centre.x) * s, y: centre.y + ($0.y - centre.y) * s) }))
    }
    restPinch += [.end([1]), .end([1]), .end([1]), .end([0])]
    out.append(("a thumb resting 0.3 s, then three fingers pinch in (to 0.45)", restPinch))
    // Two fingers resting half a second, then a third: silent, and nothing to decide.
    let two = Gesture.fingers(2, around: c)
    var restTwo: [Step] = [.begin([two[0]]), .begin([two[1]]), .wait(30), .begin([CGPoint(x: c.x + 1.5 * Gesture.spacing, y: c.y)])]
    for k in 1...10 { restTwo.append(.move((two + [CGPoint(x: c.x + 1.5 * Gesture.spacing, y: c.y)]).map { CGPoint(x: $0.x, y: $0.y - CGFloat(k) * 18) })) }
    restTwo += [.end([0]), .end([0]), .end([0])]
    out.append(("2 fingers resting 0.5 s, a 3rd lands, all swipe up 180", restTwo))
    // A pinch led by the thumb: two fingers 100 pt apart stay, the thumb 150 pt below travels up 130; and a
    // spread, the thumb 30 pt below travelling down 150.
    let fa = CGPoint(x: c.x - 50, y: c.y - 60), fb = CGPoint(x: c.x + 50, y: c.y - 60)
    let th = CGPoint(x: c.x, y: c.y + 90)
    var led: [Step] = [.begin([fa]), .begin([fb]), .begin([th])]
    for k in 1...12 { led.append(.move([fa, fb, CGPoint(x: th.x, y: th.y - 130 * CGFloat(k) / 12)])) }
    led += [.end([0]), .end([0]), .end([0])]
    out.append(("thumb-led pinch: the thumb up 130 to two still fingers", led))
    let near = CGPoint(x: c.x, y: c.y - 30)
    var ledOut: [Step] = [.begin([fa]), .begin([fb]), .begin([near])]
    for k in 1...12 { ledOut.append(.move([fa, fb, CGPoint(x: near.x, y: near.y + 150 * CGFloat(k) / 12)])) }
    ledOut += [.end([0]), .end([0]), .end([0])]
    out.append(("thumb-led spread: the thumb down 150 from two still fingers", ledOut))
    // The Mac's own pinch: three fingers land, then the thumb below them; the fingers come down 60 and in
    // 20, the thumb up 60. The thumb 110 pt below the fingers stays on the surface on a phone too (at 150
    // an iPhone 17 Pro Max's half-window surface never saw it).
    let macThumb = CGPoint(x: c.x + 20, y: c.y + 110)
    var mac: [Step] = f3.map { .begin([$0]) } + [.begin([macThumb])]
    for k in 1...12 {
        let t = CGFloat(k) / 12
        let fingers = [CGPoint(x: f3[0].x + 20 * t, y: f3[0].y + 60 * t), CGPoint(x: f3[1].x, y: f3[1].y + 60 * t),
                       CGPoint(x: f3[2].x - 20 * t, y: f3[2].y + 60 * t)]
        mac.append(.move(fingers + [CGPoint(x: macThumb.x, y: macThumb.y - 60 * t)]))
    }
    mac += [.end([0]), .end([0]), .end([0]), .end([0])]
    out.append(("4-finger pinch, the thumb landing last (the Mac's pinch)", mac))
    // A slow three-finger swipe up 120 (5 pt a frame, 300 pt/s), with a fourth contact that lands on the
    // second frame and lifts, still, after 25 pt; and the same swipe alone.
    let fourth = CGPoint(x: c.x - 170, y: c.y + 100)
    var brief: [Step] = f3.map { .begin([$0]) } + [.begin([fourth])]
    for k in 1...24 {
        let pts = f3.map { CGPoint(x: $0.x, y: $0.y - CGFloat(k) * 5) }
        brief.append(.move(k <= 5 ? pts + [fourth] : pts))
        if k == 5 { brief.append(.end([3])) }
    }
    brief += [.end([0]), .end([0]), .end([0])]
    out.append(("slow 3-finger swipe up 120 with a brief 4th contact lifting 25 pt in", brief))
    var alone: [Step] = f3.map { .begin([$0]) }
    for k in 1...24 { alone.append(.move(f3.map { CGPoint(x: $0.x, y: $0.y - CGFloat(k) * 5) })) }
    alone += [.end([0]), .end([0]), .end([0])]
    out.append(("slow 3-finger swipe up 120", alone))
    // One- and two-finger strokes half a second after a gesture on the same surface.
    let swipeUp = Gesture.swipe(3, at: c, dx: 0, dy: -180, frames: 10)
    out.append(("after a 3-finger swipe up whose first finger moved 12 pt first: 1-finger drag right 120",
                nudge + [.wait(30)] + Gesture.swipe(1, at: c, dx: 120, dy: 0, frames: 12)))
    out.append(("after a 3-finger swipe up: 2-finger scroll up 150 (flick)", swipeUp + [.wait(30)] + Gesture.swipe(2, at: c, dx: 0, dy: -150, frames: 8)))
    out.append(("after a 3-finger pinch in (to 0.45): 1-finger tap", Gesture.pinch(3, at: c, scale: 0.45) + [.wait(30)] + Gesture.tap(1, at: c)))
    out.append(("after a 3-finger swipe up: 2-finger tap", swipeUp + [.wait(30)] + Gesture.tap(2, at: c)))
    out.append(("after a thumb-led pinch: 1-finger tap", led + [.wait(30)] + Gesture.tap(1, at: c)))
    return out
}

// MARK: - The runner

final class Runner {
    #if ZOOM
    static func zoomText(_ z: StreamZoom) -> String { String(format: "%.3fx offset (%.1f, %.1f)", z.scale, z.offset.width, z.offset.height) }
    #endif
    let window: UIWindow
    let synth: TouchSynth
    /// The rig's root, for the edge layout.
    weak var root: Root?
    var queue: [(String, UIView, [Step])] = []
    var steps: [Step] = []
    var view: UIView!
    var title = ""
    var timer: Timer?
    var done: () -> Void = {}
    var waitLeft = 0

    init(window: UIWindow) {
        self.window = window
        synth = TouchSynth(window: window)
    }

    func add(_ title: String, _ view: UIView, _ steps: [Step]) { queue.append((title, view, steps)) }

    func start(done: @escaping () -> Void) {
        self.done = done
        next()
    }

    private func next() {
        guard !queue.isEmpty else { done(); return }
        let (t, v, s) = queue.removeFirst()
        title = t; view = v
        // Settle 20 frames before and 150 after: momentum, recognizers resetting.
        steps = [.wait(20)] + s + [.wait(150)]
        RigLog.lines = []
        RigLog.t0 = CACurrentMediaTime() + 20.0 / 60
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if waitLeft > 0 { waitLeft -= 1; return }
        guard !steps.isEmpty else {
            timer?.invalidate(); timer = nil
            if synth.activeCount > 0 { synth.cancelAll() }
            RigLog.flush(title)
            next()
            return
        }
        let step = steps.removeFirst()
        func w(_ p: [CGPoint]) -> [NSValue] { p.map { NSValue(cgPoint: view.convert($0, to: window)) } }
        switch step {
        case .begin(let p): synth.begin(at: w(p)); RigLog.log("[touch] begin \(p.count) → \(synth.activeCount) down")
        case .move(let p):
            // A move names every active finger; a scenario that lifted some moves the rest.
            let active = Int(synth.activeCount)
            synth.move(to: w(Array(p.suffix(active))))
        case .end(let idx): synth.end(IndexSet(idx)); RigLog.log("[touch] end \(idx.count) → \(synth.activeCount) down")
        case .cancel: synth.cancelAll(); RigLog.log("[touch] cancel all")
        case .wait(let n): waitLeft = n - 1
        case .zoom(let factor, let at):
            #if ZOOM
            if let overlay = view as? InputOverlayView {
                var z = StreamZoom()
                z.pinch(factor: factor, from: at, to: at, in: overlay.bounds.size)
                overlay.zoom = z
                RigLog.log("[zoom] set " + Runner.zoomText(overlay.zoom))
            }
            #endif
        case .logZoom:
            #if ZOOM
            if let overlay = view as? InputOverlayView { RigLog.log("zoom: " + Runner.zoomText(overlay.zoom)) }
            #endif
        case .edgeLayout(let on):
            root?.edge = on
            root?.view.setNeedsLayout()
            root?.view.layoutIfNeeded()
        case .arm(let on):
            #if EDGEFLICK
            edgeFlick.armed = on
            RigLog.log("[edge] armed \(on)")
            #endif
        case .reveal(let on):
            #if EDGEFLICK
            edgeReveal.isEnabled = on
            RigLog.log("[edge] reveal listening \(on)")
            #endif
        case .measure(let on):
            panProbe.pan.isEnabled = on
        }
    }
}

// MARK: - The app

@objc(RigAppDelegate)
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: session.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

#if EDGEFLICK
/// Full screen's flick off the left edge, on the rig's window as the app puts it on Sill's (FullScreenEdges): it
/// listens, and says what it decided (a hide; a stroke let go, but for every touch past the band).
let edgeFlick = EdgeFlickRecognizer()
/// The swipe in from the left bezel, as the app has it while its controls are hidden: off but for the
/// REVEAL strokes.
let edgeReveal = RevealEdgePan(target: nil, action: nil)
final class RevealLog: NSObject {
    @objc func changed(_ g: UIScreenEdgePanGestureRecognizer) {
        switch g.state {
        case .began: RigLog.log("[edge] reveal began")
        case .ended: RigLog.log(String(format: "[edge] reveal ended at %.0f pt", g.translation(in: g.view).x))
        case .cancelled, .failed: RigLog.log("[edge] reveal cancelled")
        default: break
        }
    }
}
let revealLog = RevealLog()
#endif

/// A SwiftUI button at the left edge, as the bar's Apps button and the phone's row 1 have one there: a flick
/// that starts on it must hide and never press it (BUTTON EDGE strokes).
struct RigButton: View {
    var body: some View {
        Button { RigLog.log("[button] pressed") } label: {
            Text("Apps").frame(width: 96, height: 56).background(Color.gray.opacity(0.4))
        }
        .buttonStyle(.plain)
    }
}

final class Root: UIViewController {
    let trackpad = TrackpadSurface(frame: .zero)
    let overlay = InputOverlayView(frame: .zero)
    let button = UIHostingController(rootView: RigButton())
    /// The surfaces laid against the window's left edge, for the EDGE strokes.
    var edge = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        trackpad.backgroundColor = UIColor(white: 0.12, alpha: 1)
        overlay.backgroundColor = UIColor(white: 0.2, alpha: 1)
        view.addSubview(trackpad)
        view.addSubview(overlay)
        addChild(button)
        button.view.backgroundColor = .clear
        view.addSubview(button.view)
        button.didMove(toParent: self)
        overlay.addGestureRecognizer(panProbe.pan)
        trackpad.send = { RigLog.log("trackpad send \(describe($0))") }
        overlay.send = { RigLog.log("overlay  send \(describe($0))") }
        overlay.videoSize = CGSize(width: 1512, height: 948)
        #if GESTURES
        let on = ProcessInfo.processInfo.environment["RIG_SWITCH"] != "off"
        trackpad.sendGesture = { g, n in RigLog.log("trackpad gesture \(g.rawValue) fingers \(n)" + (on ? "" : " (switch off: not sent)")); return on }
        overlay.sendGesture = { g, n in RigLog.log("overlay  gesture \(g.rawValue) fingers \(n)" + (on ? "" : " (switch off: not sent)")); return on }
        #endif
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var b = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 16, dy: 16)
        if edge { b = CGRect(x: 0, y: b.minY, width: view.bounds.width, height: b.height) }
        let h = (b.height - 16) / 2
        trackpad.frame = CGRect(x: b.minX, y: b.minY, width: b.width, height: h)
        overlay.frame = CGRect(x: b.minX, y: b.minY + h + 16, width: b.width, height: h)
        // Over the overlay's top-left corner, against the window's edge only for the edge strokes.
        button.view.frame = CGRect(x: edge ? 0 : b.minX, y: overlay.frame.minY + 20, width: 96, height: 56)
    }
}

@objc(RigSceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var runner: Runner?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        let root = Root()
        w.rootViewController = root
        w.makeKeyAndVisible()
        window = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.run(root, w) }
    }

    func run(_ root: Root, _ w: UIWindow) {
        print("RIG selfCheck: \(TouchSynth.selfCheck())")
        #if GESTURES
        print("RIG surfaces: with the gestures, switch \(ProcessInfo.processInfo.environment["RIG_SWITCH"] == "off" ? "off" : "on")")
        #else
        print("RIG surfaces: without the gestures")
        #endif
        print("RIG iOS \(UIDevice.current.systemVersion), window \(w.bounds.size), trackpad \(root.trackpad.frame), overlay \(root.overlay.frame)")
        if ProcessInfo.processInfo.environment["RIG_TRACE"] == "1" {
            for g in root.trackpad.gestureRecognizers ?? [] { Tracer.shared.trace(g, as: "T.\(type(of: g))") }
            for g in root.overlay.gestureRecognizers ?? [] { Tracer.shared.trace(g, as: "O.\(type(of: g))") }
        }
        #if EDGEFLICK
        edgeFlick.armed = true
        edgeFlick.onFlick = { RigLog.log("[edge] hide") }
        edgeFlick.trace = { RigLog.log("[edge] trace " + $0) }
        edgeFlick.onJudged = { verdict, numbers in
            if case .notAFlick(.outsideBand) = verdict { return }
            RigLog.log("[edge] \(verdict) (\(numbers))")
        }
        w.addGestureRecognizer(edgeFlick)
        edgeReveal.addTarget(revealLog, action: #selector(RevealLog.changed(_:)))
        edgeReveal.isEnabled = false
        w.addGestureRecognizer(edgeReveal)
        print("RIG edge: the flick off the left edge on the window, listening; the swipe in, off but for REVEAL strokes")
        #endif
        let runner = Runner(window: w)
        runner.root = root
        self.runner = runner
        let tc = CGPoint(x: root.trackpad.bounds.midX, y: root.trackpad.bounds.midY + 60)
        let oc = CGPoint(x: root.overlay.bounds.midX, y: root.overlay.bounds.midY + 60)
        // RIG_ONLY=zoom: the overlay's zoom strokes alone (#65), a minute instead of five; edge: the strokes at the
        // left edge alone.
        let only = ProcessInfo.processInfo.environment["RIG_ONLY"] ?? ""
        if only.isEmpty {
            for (title, steps) in scenarios(tc) { runner.add("TRACKPAD \(title)", root.trackpad, steps) }
            for (title, steps) in scenarios(oc) { runner.add("OVERLAY \(title)", root.overlay, steps) }
        }
        #if ZOOM
        if only.isEmpty || only == "zoom" {
            for (title, steps) in zoomScenarios(oc) { runner.add("OVERLAY ZOOM \(title)", root.overlay, steps) }
        }
        #endif
        // At the left edge: the surfaces laid against it first (each stroke's first step), back after the last.
        if only.isEmpty || only == "edge" {
            let ty = root.trackpad.bounds.midY, oy = root.overlay.bounds.midY
            for (title, steps) in edgeScenarios(ty) { runner.add("TRACKPAD \(title)", root.trackpad, [.edgeLayout(true)] + steps) }
            for (title, steps) in edgeScenarios(oy) { runner.add("OVERLAY \(title)", root.overlay, [.edgeLayout(true)] + steps) }
            // UIKit's pan threshold, measured on the overlay's middle: one point a frame, right, left, down.
            let mid = CGPoint(x: root.overlay.bounds.midX, y: oy)
            for (name, dx, dy) in [("right", 1.0, 0.0), ("left", -1.0, 0.0), ("down", 0.0, 1.0)] as [(String, CGFloat, CGFloat)] {
                var steps: [Step] = [.edgeLayout(false), .measure(true), .begin([mid])]
                for k in 1...30 { steps.append(.move([CGPoint(x: mid.x + dx * CGFloat(k), y: mid.y + dy * CGFloat(k))])) }
                steps += [.end([0]), .wait(30), .measure(false)]
                runner.add("MEASURE the pan threshold, a drag \(name) one point a frame", root.overlay, steps)
            }
            // The button: a tap presses it; a flick from it hides and presses nothing (y: the button's middle).
            let by: CGFloat = 28
            runner.add("BUTTON EDGE ON a tap on the button at the edge", root.button.view,
                       [.edgeLayout(true)] + Gesture.tap(1, at: CGPoint(x: 30, y: by)))
            runner.add("BUTTON EDGE HIDE a flick off the edge from the button", root.button.view,
                       [.edgeLayout(true), .begin([CGPoint(x: 30, y: by)]), .move([CGPoint(x: 15, y: by)]),
                        .move([CGPoint(x: 2, y: by)]), .end([0])])
        }
        runner.start { print("RIG done"); exit(0) }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
