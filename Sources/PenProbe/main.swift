import AppKit
import CoreGraphics
import Darwin
import SillHostCore

// PenProbe: step 0 of docs/pencil-pressure-plan.md (P0). Not shipped.
//
// Do Mac drawing apps take pressure and tilt from tablet events a process synthesizes? Sill would
// post exactly these for an Apple Pencil (PenEvents), so this posts three test strokes where the
// pointer is and you look at what the app drew:
//
//   1. control    a plain mouse drag, what Sill posts today: an even line
//   2. pressure   light → full → light: a line that swells in the middle
//   3. tilt       half pressure, leaning left → right: a tilt brush changes along it
//
//   PenProbe                        says what it would do; posts nothing
//   PenProbe --canvas               a window that draws what it receives and prints each stroke's
//                                   pressure and tilt: a target when no drawing app is at hand
//   PenProbe --canvas --self        that window is handed the strokes in its own process (nothing
//                                   is posted: the pointer does not move and no other app sees
//                                   them), prints what it read and exits: a check of the canvas
//   PenProbe --post-to-this-mac     POSTS REAL INPUT to this Mac after a countdown: three drags
//                                   with the left button, starting where the pointer is, into
//                                   whatever is under it. Needs Accessibility for the terminal.
//     --countdown S                 seconds before it starts (5)
//     --length PT                   each stroke's length in points (400)
//     --only control|pressure|tilt  one stroke instead of three
//     --no-proximity                without the pen's enter and leave events
//     --mouse-pressure              the pressure in the mouse event's own field too (8 bits)

// MARK: - The strokes

enum Stroke: String, CaseIterable {
    case control, pressure, tilt

    var says: String {
        switch self {
        case .control: return "control: a plain mouse drag, what Sill posts today (an even line)"
        case .pressure: return "pressure: light → full → light (a line that swells in the middle)"
        case .tilt: return "tilt: half pressure, leaning left → right (a tilt brush changes along it)"
        }
    }

    /// The pen at `t`, 0…1 along the stroke; nil for the control.
    func point(at t: Double) -> PenEvents.Point? {
        switch self {
        case .control: return nil
        case .pressure: return .init(pressure: 0.02 + 0.98 * (1 - abs(2 * t - 1)), tipDown: true)
        case .tilt: return .init(pressure: 0.5, tiltX: 2 * t - 1, tipDown: true)
        }
    }
}

struct Options {
    var strokes = Stroke.allCases
    var length = 400.0
    var proximity = true
    var mousePressure = false
    /// Samples a stroke, 4 ms apart: 1.2 s at a Pencil's 240 a second.
    var samples = 300
}

/// Set by SIGINT, read between events, so a stroke never ends with the button down.
var interrupted: sig_atomic_t = 0

/// Posts the strokes through `post`, the first starting at `origin` (global points, top-left
/// origin), each 40 pt under the last. Blocks for their length. Returns how many events it posted.
@discardableResult
func run(_ options: Options, from origin: CGPoint, post: (CGEvent) -> Void) -> Int {
    let source = CGEventSource(stateID: .hidSystemState)
    var posted = 0
    var buttonDown = false
    var inProximity = false
    var last = origin

    func mouse(_ type: CGEventType, at p: CGPoint, pen: PenEvents.Point?) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        if type != .mouseMoved { event.setIntegerValueField(.mouseEventClickState, value: 1) }
        event.setIntegerValueField(.mouseEventNumber, value: 0)
        if let pen { PenEvents.stamp(event, with: pen, mousePressureToo: options.mousePressure) }
        post(event); posted += 1; last = p
    }
    func proximity(_ entering: Bool) {
        guard options.proximity, inProximity != entering, let event = PenEvents.proximity(entering: entering, source: source) else { return }
        post(event); posted += 1; inProximity = entering
    }
    /// The button up and the pen out of range, whatever was under way.
    func letGo(pen: Bool) {
        if buttonDown { mouse(.leftMouseUp, at: last, pen: pen ? .init(pressure: 0, tipDown: false) : nil); buttonDown = false }
        proximity(false)
    }

    for (index, stroke) in options.strokes.enumerated() {
        let y = origin.y + Double(index) * 40
        let start = CGPoint(x: origin.x, y: y)
        let isPen = stroke != .control
        print("  \(index + 1) of \(options.strokes.count), \(stroke.says)")
        if isPen { proximity(true) } else { proximity(false) }
        // Up to the start, as a hovering pen (or a mouse) arrives, then a beat for the app to see it.
        mouse(.mouseMoved, at: start, pen: isPen ? .init(pressure: 0, tipDown: false) : nil)
        usleep(60_000)
        mouse(.leftMouseDown, at: start, pen: stroke.point(at: 0)); buttonDown = true
        for i in 1...options.samples {
            if interrupted != 0 { letGo(pen: isPen); return posted }
            let t = Double(i) / Double(options.samples)
            mouse(.leftMouseDragged, at: CGPoint(x: origin.x + options.length * t, y: y), pen: stroke.point(at: t))
            usleep(4_000)
        }
        letGo(pen: isPen)
        usleep(300_000)
    }
    return posted
}

// MARK: - The canvas

/// Draws what it receives: a line as wide as the pressure says, its colour from the tilt. Each
/// stroke's readings are printed when the button comes up.
final class Canvas: NSView {
    private struct Segment { var from: NSPoint, to: NSPoint, width: CGFloat, color: NSColor }
    private var segments: [Segment] = []
    private var last: NSPoint?
    private(set) var strokes: [Readings] = []
    private var current = Readings()
    private(set) var proximityEnters = 0, proximityLeaves = 0

    struct Readings {
        var drags = 0, tabletPoints = 0
        var pressures: [Float] = []
        var tiltXs: [CGFloat] = []
        /// Some pressure is no multiple of 1/255: it came from the tablet point's 16 bits, not the
        /// mouse event's 8 (PenEvents.stamp).
        var finerThan8Bits: Bool { pressures.contains { abs(Double($0) * 255 - (Double($0) * 255).rounded()) > 0.01 } }
        var summary: String {
            guard drags > 0 else { return "no drags" }
            let p = "pressure \(String(format: "%.3f", pressures.min() ?? 0))…\(String(format: "%.3f", pressures.max() ?? 0)) (\(finerThan8Bits ? "finer than 8 bits" : "8-bit steps"))"
            guard tabletPoints > 0 else { return "\(drags) drags, none a tablet point, \(p)" }
            return "\(drags) drags, \(tabletPoints) tablet points, \(p), tilt x \(String(format: "%.2f", tiltXs.min() ?? 0))…\(String(format: "%.2f", tiltXs.max() ?? 0))"
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        for s in segments {
            s.color.setStroke()
            let path = NSBezierPath(); path.lineWidth = s.width; path.lineCapStyle = .round
            path.move(to: s.from); path.line(to: s.to); path.stroke()
        }
    }

    /// Where an event is in this view. One that names no window (the self-check's, which never
    /// passed the window server) gives its place on the screen instead.
    private func place(of event: NSEvent) -> NSPoint {
        if event.window != nil { return convert(event.locationInWindow, from: nil) }
        guard let window else { return .zero }
        return convert(window.convertPoint(fromScreen: event.locationInWindow), from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        current = Readings()
        last = place(of: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = place(of: event)
        let isPen = event.subtype == .tabletPoint
        current.drags += 1
        current.pressures.append(event.pressure)
        if isPen { current.tabletPoints += 1; current.tiltXs.append(event.tilt.x) }   // tilt only on a tablet point: it throws on any other event
        let tilt = isPen ? event.tilt.x : 0
        let color = isPen ? NSColor(hue: 0.6 - 0.3 * tilt, saturation: 0.8, brightness: 0.7, alpha: 1) : NSColor.gray
        if let last { segments.append(Segment(from: last, to: p, width: 1 + 24 * CGFloat(event.pressure), color: color)) }
        last = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        last = nil
        strokes.append(current)
        print("  received stroke \(strokes.count): \(current.summary)")
    }

    override func tabletProximity(with event: NSEvent) {
        if event.isEnteringProximity { proximityEnters += 1 } else { proximityLeaves += 1 }
        print("  received proximity \(event.isEnteringProximity ? "enter" : "leave"): pointing device type \(event.pointingDeviceType.rawValue), deviceID \(event.deviceID)")
    }
}

func runCanvas(selfTest: Bool) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 260), styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
    window.title = "PenProbe canvas"
    let canvas = Canvas(frame: window.contentLayoutRect)
    window.contentView = canvas
    window.center()
    window.makeFirstResponder(canvas)
    if selfTest { window.orderFrontRegardless() } else { window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true) }
    print("PenProbe canvas: draws what it receives. Put the pointer near its left edge and run `PenProbe --post-to-this-mac` from another terminal.")

    if selfTest {
        print("Handing three strokes to this window in its own process (nothing is posted; the pointer does not move).")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // The canvas's top-left corner area in global points (top-left origin), where events are placed.
            let frame = window.convertToScreen(canvas.convert(canvas.bounds, to: nil))
            let top = NSScreen.screens.first?.frame.height ?? frame.maxY
            let origin = CGPoint(x: frame.minX + 60, y: top - frame.maxY + 60)
            // Each event goes through its serialized form and AppKit's conversion, as `SillHost
            // --pen-selftest` reads them, and then straight to the canvas's own handlers: this
            // checks what the canvas reads and draws, not delivery. Delivery is what
            // --post-to-this-mac is for. (Posted to this process with `postToPid`, or handed to
            // `NSApp.sendEvent`, the proximity events arrived and the mouse events did not: the
            // window server is what gives a mouse event its window.)
            DispatchQueue.global(qos: .userInitiated).async {
                var options = Options(); options.length = 480
                run(options, from: origin) { event in
                    guard let data = event.data, let copy = CGEvent(withDataAllocator: nil, data: data) else { return }
                    DispatchQueue.main.async {
                        guard let ns = NSEvent(cgEvent: copy) else { return }
                        switch ns.type {
                        case .leftMouseDown: canvas.mouseDown(with: ns)
                        case .leftMouseDragged: canvas.mouseDragged(with: ns)
                        case .leftMouseUp: canvas.mouseUp(with: ns)
                        case .tabletProximity: canvas.tabletProximity(with: ns)
                        default: break
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let s = canvas.strokes
                    var ok = s.count == 3
                    func check(_ pass: Bool, _ what: String) { print("  \(pass ? "ok  " : "FAIL") \(what)"); if !pass { ok = false } }
                    check(s.count == 3, "three strokes received (\(s.count))")
                    if s.count == 3 {
                        check(s[0].tabletPoints == 0, "the control is no pen's: \(s[0].summary)")
                        check(s[1].tabletPoints == s[1].drags && (s[1].pressures.max() ?? 0) > 0.99 && (s[1].pressures.min() ?? 1) < 0.05
                              && s[1].finerThan8Bits, "pressure arrives, finer than 8 bits: \(s[1].summary)")
                        check(s[2].tabletPoints == s[2].drags && (s[2].tiltXs.min() ?? 0) < -0.95 && (s[2].tiltXs.max() ?? 0) > 0.95,
                              "tilt arrives, left to right: \(s[2].summary)")
                    }
                    check(canvas.proximityEnters >= 1 && canvas.proximityLeaves >= 1,
                          "proximity arrives (\(canvas.proximityEnters) enter, \(canvas.proximityLeaves) leave)")
                    exit(ok ? 0 : 1)
                }
            }
        }
    }
    app.run()
    exit(0)
}

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())
func value(after flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

if arguments.contains("--canvas") {
    runCanvas(selfTest: arguments.contains("--self"))
}

var options = Options()
if let only = value(after: "--only") {
    guard let stroke = Stroke(rawValue: only) else { print("--only: control, pressure or tilt, not \(only)"); exit(2) }
    options.strokes = [stroke]
}
if let length = value(after: "--length") {
    guard let points = Double(length), points >= 50, points <= 3000 else { print("--length: 50 to 3000 points"); exit(2) }
    options.length = points
}
options.proximity = !arguments.contains("--no-proximity")
options.mousePressure = arguments.contains("--mouse-pressure")
var countdown = 5
if let seconds = value(after: "--countdown") {
    guard let s = Int(seconds), s >= 1, s <= 60 else { print("--countdown: 1 to 60 seconds"); exit(2) }
    countdown = s
}

guard arguments.contains("--post-to-this-mac") else {
    print("""
    PenProbe: do Mac apps take pressure and tilt from synthesized tablet events? (docs/pencil-pressure-plan.md, P0)

    With --post-to-this-mac it POSTS REAL INPUT to this Mac: after a \(countdown) s countdown, \(options.strokes.count) left-button drag(s) \
    of \(Int(options.length)) pt to the right, 40 pt apart, starting where the pointer is, into whatever is under it:
    \(options.strokes.enumerated().map { "  \($0.offset + 1). \($0.element.says)" }.joined(separator: "\n"))
    Open a drawing app, pick a brush whose size follows pressure, and put the pointer at the left of an empty canvas first.

      PenProbe --post-to-this-mac [--countdown S] [--length PT] [--only control|pressure|tilt] [--no-proximity] [--mouse-pressure]
      PenProbe --canvas            a window that draws and prints what it receives, to aim at instead of an app
      PenProbe --canvas --self     hands that window the strokes in its own process (nothing posted) and prints what it read

    Nothing was posted.
    """)
    exit(0)
}

guard CGPreflightPostEventAccess() else {
    _ = CGRequestPostEventAccess()
    print("Posting input needs Accessibility for the app this was launched from (Terminal, iTerm, …): System Settings › Privacy & Security › Accessibility. Then run it again. Nothing was posted.")
    exit(1)
}

signal(SIGINT) { _ in interrupted = 1 }
print("PenProbe will post real input to this Mac. Bring the drawing app to the front and put the pointer at the left of an empty canvas. Ctrl-C stops it.")
for remaining in stride(from: countdown, to: 0, by: -1) {
    if interrupted != 0 { print("Stopped. Nothing was posted."); exit(130) }
    print("  \(remaining)…")
    sleep(1)
}
guard let origin = CGEvent(source: nil)?.location else { print("Could not read the pointer's position. Nothing was posted."); exit(1) }
print("Starting at \(Int(origin.x)),\(Int(origin.y))\(options.proximity ? "" : ", without proximity events")\(options.mousePressure ? ", the mouse event's pressure set too" : ""):")
let posted = run(options, from: origin) { $0.post(tap: .cghidEventTap) }
print(interrupted != 0 ? "Stopped after \(posted) events; the button is up." : "Posted \(posted) events.")
print("Line 2 swelling in the middle means the app takes pressure; line 3 changing along its length means it takes tilt; line 1 is the control.")
exit(interrupted != 0 ? 130 : 0)
