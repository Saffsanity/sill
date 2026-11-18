import AppKit
import QuartzCore

// TEST ONLY. The privacy probe's test window (Scripts/privacy-probe/run.sh; docs/privacy-mode-plan.md, G0 step 1): a
// window of another app than the probe's black windows, as a streamed app's window is another app than Sill. Redrawn
// 60 times a second by a timer (a bar that moves at each draw, so every redraw changes pixels and ScreenCaptureKit has a
// frame to send) and, beside it, a layer moved by a display link (NSView.displayLink, macOS 14). Every quarter second it
// prints what it saw in that quarter: whether macOS calls the window and the app visible (occlusionState), how many
// draws and display-link callbacks ran. Never activates, never takes a key or a click, touches nothing else.
// usage: window X Y W H SECONDS   (points from the main screen's top left; it quits after SECONDS, or at SIGTERM, which
//                                  run.sh sends when step 1 is over)
// Prints "ready <pid> <window number>", then lines "q <epoch seconds> occ=<0|1> app=<0|1> draws=<n> link=<n>".

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard args.count == 5 else {
    FileHandle.standardError.write("usage: window X Y W H SECONDS\n".data(using: .utf8)!)
    exit(2)
}
let lifetime = args[4]

final class Counts {
    private let lock = NSLock()
    private var draws = 0, link = 0
    func take() -> (Int, Int) { lock.lock(); defer { draws = 0; link = 0; lock.unlock() }; return (draws, link) }
    func draw() { lock.lock(); draws += 1; lock.unlock() }
    func tick() { lock.lock(); link += 1; lock.unlock() }
}
let counts = Counts()

/// Redrawn by the timer: a dark field and an orange bar one step further at each draw.
final class DrawnView: NSView {
    private var step = 0
    override func draw(_ dirtyRect: NSRect) {
        counts.draw()
        step += 1
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        bounds.fill()
        let x = CGFloat(step % 60) / 60 * (bounds.width - 10)
        NSColor.systemOrange.setFill()
        NSRect(x: x, y: 8, width: 10, height: bounds.height - 16).fill()
    }
}

/// Moved by a display link: a teal bar on black, one step at each callback.
final class LinkedView: NSView {
    private let bar = CALayer()
    private var link: CADisplayLink?
    private var step = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        bar.backgroundColor = NSColor.systemTeal.cgColor
        layer?.addSublayer(bar)
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, link == nil else { return }
        let l = displayLink(target: self, selector: #selector(stepped(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func stepped(_ l: CADisplayLink) {
        counts.tick()
        step += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.frame = CGRect(x: CGFloat(step % 60) / 60 * (bounds.width - 10), y: 8, width: 10, height: bounds.height - 16)
        CATransaction.commit()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let top = NSScreen.screens.first?.frame.maxY ?? 900
let frame = NSRect(x: args[0], y: top - args[1] - args[3], width: args[2], height: args[3])
let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
window.title = "Sill privacy probe: test window"
window.isReleasedWhenClosed = false
let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
let half = frame.height / 2
let drawn = DrawnView(frame: NSRect(x: 0, y: half, width: frame.width, height: half))
let linked = LinkedView(frame: NSRect(x: 0, y: 0, width: frame.width, height: half))
content.addSubview(drawn)
content.addSubview(linked)
window.contentView = content
window.orderFrontRegardless()

let redraw = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in drawn.needsDisplay = true }
RunLoop.main.add(redraw, forMode: .common)

let report = Timer(timeInterval: 0.25, repeats: true) { _ in
    let (d, l) = counts.take()
    let occ = window.occlusionState.contains(.visible) ? 1 : 0
    let shown = app.occlusionState.contains(.visible) ? 1 : 0
    print(String(format: "q %.3f occ=%d app=%d draws=%d link=%d", Date().timeIntervalSince1970, occ, shown, d, l))
}
RunLoop.main.add(report, forMode: .common)

// Quits after its lifetime whatever happens (run.sh ends it sooner).
DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { exit(0) }
DispatchQueue.main.async { print("ready \(getpid()) \(window.windowNumber)") }
app.run()
