#if DEBUG
import AppKit
import Network

/// DEBUG `-SillInputTest 1`: once, a second after the first frame, synthetic NSEvents go through the
/// stream view's own handlers (a move, a click, a double click, a right click, a drag, a trackpad
/// scroll with momentum, a mouse wheel's step, ⌘C, a shift key, a gesture), so the mapping can be
/// checked end to end against a host's input log (`SILL_TEST_INPUT_LOG=1 SillHost --synthetic`).
/// Only to a host whose window list has no version (never Sill.app, which would post it), on this
/// Mac's loopback or at the address `-SillInputTestHost` names. The console says what ran ("input test: …").
enum MacInputTest {
    static var done = false
    static var dropDone = false

    static func runIfAsked(_ view: StreamInputView) {
        // -SillDropTest <path>: once, 3 s after the first frame, that file dropped in the middle of the
        // focused window, as a drag from Finder would (the host's app there takes it).
        if let path = UserDefaults.standard.string(forKey: "SillDropTest"), !dropDone {
            dropDone = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                FileHandle.standardError.write(Data("drop test: \(path) on \(view.client.active)\n".utf8))
                StreamInputView.send([URL(fileURLWithPath: path)], at: CGPoint(x: 0.5, y: 0.6), client: view.client)
            }
        }
        guard UserDefaults.standard.bool(forKey: "SillInputTest"), !done else { return }
        // A test host on this Mac's loopback, or the one host `-SillInputTestHost <address>` names (a
        // synthetic host on another Mac, for a test between two Macs); never one with a version.
        let named = UserDefaults.standard.string(forKey: "SillInputTestHost")
        guard view.client.hostVersion == nil, case .hostPort(let host, _)? = view.client.connection?.endpoint,
              let address = "\(host)".split(separator: "%").first.map(String.init),
              ["127.0.0.1", "::1", "localhost"].contains(address) || address == named else {
            print("input test: refused: only a test host on this Mac's loopback, or the one -SillInputTestHost names")
            done = true
            return
        }
        done = true
        let steps: [(Double, String, () -> Void)] = [
            (0.0, "move to the middle", { mouse(view, .mouseMoved, 0.5, 0.5) }),
            (0.3, "click at 0.25, 0.25", { mouse(view, .leftMouseDown, 0.25, 0.25); mouse(view, .leftMouseUp, 0.25, 0.25) }),
            (0.6, "double click at 0.3, 0.3", {
                mouse(view, .leftMouseDown, 0.3, 0.3, clicks: 1); mouse(view, .leftMouseUp, 0.3, 0.3, clicks: 1)
                mouse(view, .leftMouseDown, 0.3, 0.3, clicks: 2); mouse(view, .leftMouseUp, 0.3, 0.3, clicks: 2)
            }),
            (1.0, "right click at 0.75, 0.5", { mouse(view, .rightMouseDown, 0.75, 0.5); mouse(view, .rightMouseUp, 0.75, 0.5) }),
            (1.15, "middle click at 0.5, 0.5 (sent only if the host takes it)", {
                mouse(view, .otherMouseDown, 0.5, 0.5); mouse(view, .otherMouseUp, 0.5, 0.5)
            }),
            (1.3, "drag 0.2,0.2 → 0.6,0.6, past the edge to 1.2", {
                mouse(view, .leftMouseDown, 0.2, 0.2)
                mouse(view, .leftMouseDragged, 0.6, 0.6)
                mouse(view, .leftMouseDragged, 1.2, 0.6)
                mouse(view, .leftMouseUp, 1.2, 0.6)
            }),
            (1.8, "trackpad scroll: began, 3 deltas, ended, momentum", {
                scroll(view, phase: .began, momentum: [], dy: 0)
                for _ in 0..<3 { scroll(view, phase: .changed, momentum: [], dy: 20) }
                scroll(view, phase: .ended, momentum: [], dy: 0)
                scroll(view, phase: [], momentum: .began, dy: 10)
                scroll(view, phase: [], momentum: .changed, dy: 5)
                scroll(view, phase: [], momentum: .ended, dy: 0)
            }),
            (2.3, "mouse wheel: one line", { scroll(view, phase: [], momentum: [], dy: 1, precise: false) }),
            (2.6, "⌘C", {
                view.forward(.flagsChanged, keyCode: 55, flags: .command, isRepeat: false)
                view.forward(.keyDown, keyCode: 8, flags: .command, isRepeat: false)
                view.forward(.keyUp, keyCode: 8, flags: .command, isRepeat: false)
                view.forward(.flagsChanged, keyCode: 55, flags: [], isRepeat: false)
            }),
            (2.9, "shift, then a, then the keyboard let go with shift held", {
                view.forward(.flagsChanged, keyCode: 56, flags: .shift, isRepeat: false)
                view.forward(.keyDown, keyCode: 0, flags: .shift, isRepeat: false)
                view.letGo()
            }),
            (3.2, "gesture: Mission Control", { view.client.sendGesture(.swipeUp, fingers: 3) }),
        ]
        for (at, what, run) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + at) {
                print("input test: \(what)")
                run()
            }
        }
    }

    /// A mouse event at a fraction of the picture.
    private static func mouse(_ view: StreamInputView, _ type: NSEvent.EventType, _ fx: CGFloat, _ fy: CGFloat, clicks: Int = 1) {
        let rect = view.display.videoRect
        let local = CGPoint(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height)
        let inWindow = view.convert(local, to: nil)
        guard let made = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: 0,
                                             windowNumber: view.window?.windowNumber ?? 0, context: nil,
                                             eventNumber: 0, clickCount: clicks, pressure: 1) else { return }
        // NSEvent.mouseEvent makes button 0 for any type; an other-button event says which.
        let event = type == .otherMouseDown || type == .otherMouseUp
            ? (made.cgEvent.flatMap { cg -> NSEvent? in cg.setIntegerValueField(.mouseEventButtonNumber, value: 2); return NSEvent(cgEvent: cg) } ?? made)
            : made
        switch type {
        case .mouseMoved: view.mouseMoved(with: event)
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseUp: view.mouseUp(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        case .rightMouseDown: view.rightMouseDown(with: event)
        case .rightMouseUp: view.rightMouseUp(with: event)
        case .otherMouseDown: view.otherMouseDown(with: event)
        case .otherMouseUp: view.otherMouseUp(with: event)
        default: break
        }
    }

    /// A scroll event over the middle of the picture, with the trackpad's phase fields.
    private static func scroll(_ view: StreamInputView, phase: NSEvent.Phase, momentum: NSEvent.Phase, dy: Int32, precise: Bool = true) {
        let rect = view.display.videoRect
        let local = CGPoint(x: rect.midX, y: rect.midY)
        guard let window = view.window,
              let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2, wheel1: dy, wheel2: 0, wheel3: 0) else { return }
        let screen = window.convertPoint(toScreen: view.convert(local, to: nil))
        let height = NSScreen.screens.first?.frame.height ?? 0
        cg.location = CGPoint(x: screen.x, y: height - screen.y)
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentumPhase(momentum)))
        guard let event = NSEvent(cgEvent: cg) else { return }
        view.scrollWheel(with: event)
    }

    /// CGMomentumScrollPhase's values (begin 1, continue 2, end 3), which NSEvent maps to its phases.
    private static func momentumPhase(_ p: NSEvent.Phase) -> Int {
        if p.contains(.began) { return 1 }
        if p.contains(.changed) { return 2 }
        if p.contains(.ended) { return 3 }
        return 0
    }
}

/// DEBUG `-SillResizeTest 1`: the focused stream window is set to four content sizes of different
/// shapes, 2.5 s apart; 2 s after each the console says whether the picture fits it ("resize test:
/// … ok" or "… FAIL"): drawn at the frame's own shape, centred, touching both edges along one axis,
/// and the viewport sent with the window's size. Sends no input.
enum MacResizeTest {
    static func run() {
        setvbuf(stdout, nil, _IOLBF, 0)   // each line as it is printed, to a file too
        let sizes = [NSSize(width: 1200, height: 800), NSSize(width: 800, height: 900),
                     NSSize(width: 1600, height: 600), NSSize(width: 520, height: 420)]
        for (i, size) in sizes.enumerated() {
            let at = 2.0 + Double(i) * 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                guard let window = NSApp.windows.first(where: { $0 is StreamWindow && $0.isVisible }) else {
                    print("resize test: FAIL no stream window"); return
                }
                window.setContentSize(size)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + at + 2) { check(size) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + 2.5 * Double(sizes.count)) { print("resize test: done") }
    }

    private static func check(_ asked: NSSize) {
        guard let window = NSApp.windows.first(where: { $0 is StreamWindow && $0.isVisible }),
              let input = find(in: window.contentView) else { print("resize test: FAIL no stream view"); return }
        let view = input.display
        let b = view.bounds, v = view.videoSize, r = view.videoRect
        var problems: [String] = []
        if abs(b.width - asked.width) > 1 || abs(b.height - asked.height) > 1 { problems.append("view \(b.size) not \(asked)") }
        if v.width <= 0 || v.height <= 0 { problems.append("no video") } else {
            if abs(r.width / r.height - v.width / v.height) > 0.01 { problems.append("shape \(r.size) vs frame \(v)") }
            let fillsW = abs(r.width - b.width) < 1, fillsH = abs(r.height - b.height) < 1
            if !fillsW && !fillsH { problems.append("touches neither edge") }
            if abs(r.midX - b.midX) > 1 || abs(r.midY - b.midY) > 1 { problems.append("not centred") }
        }
        let vp = input.client.lastViewport
        if let vp, abs(vp.width - Double(b.width)) > 1 || abs(vp.height - Double(b.height)) > 1 {
            problems.append("viewport \(vp.width)×\(vp.height)")
        } else if vp == nil { problems.append("no viewport sent") }
        print("resize test: \(Int(asked.width))×\(Int(asked.height)) frame \(Int(v.width))×\(Int(v.height)) drawn \(Int(r.width))×\(Int(r.height)) at \(Int(r.minX)),\(Int(r.minY)) "
              + (problems.isEmpty ? "ok" : "FAIL " + problems.joined(separator: "; ")))
    }

    private static func find(in view: NSView?) -> StreamInputView? {
        guard let view else { return nil }
        if let v = view as? StreamInputView { return v }
        for sub in view.subviews { if let f = find(in: sub) { return f } }
        return nil
    }
}
#endif
