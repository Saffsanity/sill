// TEST ONLY (Tests/touchrig, never in the app): drives the real TrackpadSurface (TrackpadView.swift) and
// InputOverlayView (InputOverlay.swift) with synthesized one- to five-finger touches (TouchSynth), and
// logs every InputEvent each would send to the Mac and every gesture it decides. Nothing leaves the
// process: `send` and `sendGesture` only log. H7 of docs/trackpad-gestures-plan.md runs it twice, on
// the surfaces before the gestures and on this branch's, and compare.py judges the two logs.
//
// Environment (simctl launch's SIMCTL_CHILD_ prefix): RIG_SWITCH=off makes `sendGesture` answer false,
// as StreamClient does with the device's switch off; RIG_TRACE=1 also logs recognizer transitions.
import UIKit

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
}

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
    return out
}

// MARK: - The runner

final class Runner {
    let window: UIWindow
    let synth: TouchSynth
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

final class Root: UIViewController {
    let trackpad = TrackpadSurface(frame: .zero)
    let overlay = InputOverlayView(frame: .zero)
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        trackpad.backgroundColor = UIColor(white: 0.12, alpha: 1)
        overlay.backgroundColor = UIColor(white: 0.2, alpha: 1)
        view.addSubview(trackpad)
        view.addSubview(overlay)
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
        let b = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 16, dy: 16)
        let h = (b.height - 16) / 2
        trackpad.frame = CGRect(x: b.minX, y: b.minY, width: b.width, height: h)
        overlay.frame = CGRect(x: b.minX, y: b.minY + h + 16, width: b.width, height: h)
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
        let runner = Runner(window: w)
        self.runner = runner
        let tc = CGPoint(x: root.trackpad.bounds.midX, y: root.trackpad.bounds.midY + 60)
        let oc = CGPoint(x: root.overlay.bounds.midX, y: root.overlay.bounds.midY + 60)
        for (title, steps) in scenarios(tc) { runner.add("TRACKPAD \(title)", root.trackpad, steps) }
        for (title, steps) in scenarios(oc) { runner.add("OVERLAY \(title)", root.overlay, steps) }
        runner.start { print("RIG done"); exit(0) }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
