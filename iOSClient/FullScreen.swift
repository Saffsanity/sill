import SwiftUI
import UIKit

// Full screen's glue (docs/full-screen-plan.md): the edge recognizers on the window (EdgeFlickRecognizer.swift)
// and the pointer's dwell at the left edge, whether Sill's window covers the screen, the shake, the hint, and
// the hidden picture as one element for VoiceOver, Switch Control and Voice Control. The rules are
// FullScreenPolicy.swift's; StreamScreen owns the state (`chrome`) and PortraitStreamScreen draws its part.

// MARK: - The window's edges

/// A view with no size and no touch that puts full screen's recognizers on its window, as TouchWatcher puts
/// the tour's: the flick off the left edge (while `flickArmed`), the swipe in from the left bezel (while
/// `revealArmed`), and a hover that sees the iPad's pointer held at the left edge (while hidden). It also says
/// whether the window covers the screen, as it joins a window and at every layout (a Stage Manager window
/// resized, Split View): FullScreenPolicy.offered.
struct FullScreenEdges: UIViewRepresentable {
    var flickArmed: Bool
    var revealArmed: Bool
    /// The flick off the left edge was recognized.
    var onFlick: () -> Void
    /// The swipe in: `.began`, `.changed` with the finger's travel, `.ended` or `.cancelled` with its travel
    /// and speed (points, points a second, rightward).
    var onReveal: (UIGestureRecognizer.State, CGFloat, CGFloat, CGFloat) -> Void
    /// The pointer stayed at the left edge (EdgeDwell).
    var onDwell: () -> Void
    /// The device was shaken while this window was key (UIKit hands a shake to the key window's responders).
    var onShake: () -> Void
    /// Whether the window covers the screen.
    var onCoverage: (Bool) -> Void
    /// The window's safe area, as it changes (the swipe in's preview lands where the shown layout will be,
    /// the status bar's room included).
    var onInsets: (UIEdgeInsets) -> Void = { _ in }

    func makeUIView(context: Context) -> Anchor { Anchor() }

    func updateUIView(_ anchor: Anchor, context: Context) {
        anchor.flick.armed = flickArmed
        anchor.reveal.isEnabled = revealArmed
        anchor.dwellArmed = revealArmed
        anchor.flick.onFlick = onFlick
        anchor.onReveal = onReveal
        anchor.onDwell = onDwell
        anchor.onShake = onShake
        anchor.onCoverage = onCoverage
        anchor.onInsets = onInsets
        #if DEBUG
        anchor.flick.onJudged = { verdict, numbers in
            switch verdict {
            case .hide: print("edge: a flick off the left edge (\(numbers)): hide")
            case .notAFlick(.outsideBand): break      // every touch past the band: too many to print
            case .notAFlick(let why): print("edge: not a flick, \(why.rawValue) (\(numbers)): the stroke goes on")
            case .undecided: break
            }
        }
        #endif
        anchor.reportCoverage()
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: ()) { anchor.detach() }

    final class Anchor: UIView, UIGestureRecognizerDelegate {
        let flick = EdgeFlickRecognizer()
        let reveal = RevealEdgePan(target: nil, action: nil)
        let hover = UIHoverGestureRecognizer(target: nil, action: nil)
        var dwellArmed = false {
            didSet {
                guard dwellArmed != oldValue, !dwellArmed else { return }
                dwell.ended()
                dwellCheck?.invalidate()
                dwellCheck = nil
            }
        }
        var onReveal: (UIGestureRecognizer.State, CGFloat, CGFloat, CGFloat) -> Void = { _, _, _, _ in }
        var onDwell: () -> Void = {}
        var onShake: () -> Void = {}
        var onCoverage: (Bool) -> Void = { _ in }
        var onInsets: (UIEdgeInsets) -> Void = { _ in }
        private var insets: UIEdgeInsets?
        private var shakes: NSObjectProtocol?
        private var dwell = EdgeDwell()
        private var dwellCheck: Timer?
        private var covers: Bool?
        private weak var host: UIWindow?

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            reveal.addTarget(self, action: #selector(revealChanged))
            reveal.isEnabled = false
            hover.addTarget(self, action: #selector(hovered))
            hover.delegate = self
            // A shake reaches the window it was given to (UIWindow.motionEnded, below): this one's only.
            shakes = NotificationCenter.default.addObserver(forName: .sillDeviceShaken, object: nil, queue: .main) { [weak self] note in
                guard let self, let window = self.window, note.object as? UIWindow === window else { return }
                self.onShake()
            }
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        deinit { if let shakes { NotificationCenter.default.removeObserver(shakes) } }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { detach(); return }
            reportCoverage()
            guard host !== window else { return }
            detach()
            window.addGestureRecognizer(flick)
            window.addGestureRecognizer(reveal)
            window.addGestureRecognizer(hover)
            host = window
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportCoverage()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            reportCoverage()
        }

        func detach() {
            for recognizer in [flick, reveal, hover] as [UIGestureRecognizer] { host?.removeGestureRecognizer(recognizer) }
            host = nil
            dwellCheck?.invalidate()
            dwellCheck = nil
        }

        /// Whether the window covers its screen, and its safe area, each said when it changes.
        func reportCoverage() {
            guard let window, let screen = window.windowScene?.screen else { return }
            if window.safeAreaInsets != insets {
                insets = window.safeAreaInsets
                let report = onInsets, now = window.safeAreaInsets
                DispatchQueue.main.async { report(now) }
            }
            let frame = window.convert(window.bounds, to: screen.coordinateSpace)
            let now = FullScreenPolicy.offered(window: frame, screen: screen.bounds)
            guard now != covers else { return }
            covers = now
            let report = onCoverage
            DispatchQueue.main.async { report(now) }
        }

        @objc private func revealChanged() {
            let travel = reveal.translation(in: window).x
            let speed = reveal.velocity(in: window).x
            onReveal(reveal.state, travel, speed, window?.bounds.width ?? 0)
        }

        // The pointer at the left edge (EdgeDwell): hovering only, a Pencil never.
        @objc private func hovered() {
            guard dwellArmed, let window else { return }
            switch hover.state {
            case .began, .changed:
                let pencil = hover.zOffset > 0 || hover.altitudeAngle > 0
                let x = Double(hover.location(in: window).x)
                if dwell.hover(x: x, t: ProcessInfo.processInfo.systemUptime, pencil: pencil) {
                    onDwell()
                } else if dwell.since != nil, !dwell.fired, dwellCheck == nil {
                    // A pointer held still sends nothing more: look again when the dwell has run.
                    dwellCheck = Timer.scheduledTimer(withTimeInterval: EdgeDwell.dwell + 0.01, repeats: false) { [weak self] _ in
                        guard let self else { return }
                        self.dwellCheck = nil
                        if self.dwellArmed, self.dwell.check(t: ProcessInfo.processInfo.systemUptime) { self.onDwell() }
                    }
                }
            default:
                dwell.ended()
                dwellCheck?.invalidate()
                dwellCheck = nil
            }
        }

        // The hover only watches: beside the picture's own hover, never in its way.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    }
}

// MARK: - The shake

extension Notification.Name {
    /// The device was shaken (UIKit's motion event, from the window: `UIWindow.motionEnded`).
    static let sillDeviceShaken = Notification.Name("SillDeviceShaken")
}

/// UIKit hands a shake to the first responder (the stream's input view, while a keyboard holds it), which
/// passes it up its responder chain to the window, or straight to the key window when nothing is first
/// responder: here, then, it is seen either way, and passed on as UIKit would (its next responder). While the
/// interface is hidden the stream screen turns iOS's Shake to Undo off for the app
/// (`applicationSupportsShakeToEdit`), so the shake brings Sill's controls back and never an Undo alert.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .sillDeviceShaken, object: self) }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - The hint

/// As the interface hides, the first few times (FullScreenPolicy.showsHint): how to bring it back, by the left
/// edge where the swipe starts, for `hintSeconds`, then it fades. It takes no touch; VoiceOver hears it as an
/// announcement every time instead (StreamScreen), so it is hidden from it here.
struct FullScreenHint: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Capsule().fill(Palette.accent).frame(width: 3, height: 22)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(FullScreenPolicy.Copy.hintTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Text(FullScreenPolicy.Copy.hintLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.bar.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .frame(maxWidth: 340, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The swipe in's preview

/// The swipe in's preview of the shown interface (StreamScreen's `revealPreview`) has no picture of its own
/// (there is one picture view, the hidden one): its picture pane is this, which says where it is, so the
/// preview is cut away there (RevealMask) and the hidden picture shows through.
struct RevealHoleKey: PreferenceKey {
    /// The preview's own space, in which the hole is given.
    static let space = "sill.reveal"
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

struct RevealHole: View {
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: RevealHoleKey.self, value: g.frame(in: .named(RevealHoleKey.space)))
        }
        .allowsHitTesting(false)
    }
}

/// Everything but the hole, rounded as the picture's pane is.
struct RevealMask: View {
    let hole: CGRect?
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
            if let hole {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
}

// MARK: - The hidden picture for assistive technologies

/// While hidden, the picture is the only thing on the screen, and the stream's input view is not an element
/// (it would read as an unlabeled text field): one element over it, named for the Mac, whose activation, its
/// Show Controls action and VoiceOver's escape gesture bring the controls back, and which Voice Control knows
/// as "Show Controls". It takes no touch. While the controls show it is hidden from every assistive
/// technology, and the screen reads as before.
struct HiddenPictureElement: View {
    let hidden: Bool
    let mac: String
    let show: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(FullScreenPolicy.Copy.pictureLabel(mac: mac))
            .accessibilityAddTraits(.isButton)
            .accessibilityInputLabels(FullScreenPolicy.Copy.inputLabels)
            .accessibilityAction { show() }
            .accessibilityAction(named: FullScreenPolicy.Copy.action) { show() }
            .accessibilityAction(.escape) { show() }
            .accessibilityHidden(!hidden)
    }
}

// MARK: - DEBUG

#if DEBUG
/// The harness's full screen (ContentView's contract): `-SillFullScreen 1` hidden from the start (in the mock
/// and live), `-SillFullScreenReveal P` with it, the swipe in caught at P of the way (0…1) for a photo,
/// `-SillFullScreenHint 1` the hint every time it hides (`hold`: and kept up, for a photo),
/// `-SillFullScreenRoom screen|housing|safe` where the hidden picture goes (FullScreenPolicy.Room),
/// `-SillFullScreenToggle <s>[,<s>…]` hidden or shown at those seconds after the stream screen shows (as a
/// flick and the swipe in do), `-SillFullScreenSwipe <s>[,<s>…]` a swipe in from the left edge played at those
/// seconds (its progress in steps, then its lift), and `-SillShakeAt <s>[,<s>…]` a shake (the window's
/// notification) at those seconds.
struct FullScreenDebug {
    enum Hint { case off, every, hold }
    var startHidden = false
    var reveal: CGFloat? = nil
    var hint: Hint = .off
    var room: FullScreenPolicy.Room? = nil
    var toggles: [Double] = []
    var swipes: [Double] = []
    var shakes: [Double] = []

    static let current: FullScreenDebug = {
        let d = UserDefaults.standard
        func seconds(_ key: String) -> [Double] {
            (d.string(forKey: key) ?? "").split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        }
        var debug = FullScreenDebug()
        debug.startHidden = d.bool(forKey: "SillFullScreen")
        if let raw = d.string(forKey: "SillFullScreenReveal"), let p = Double(raw) { debug.reveal = CGFloat(min(max(p, 0), 1)) }
        switch d.string(forKey: "SillFullScreenHint") {
        case "hold"?: debug.hint = .hold
        case let v? where v != "0": debug.hint = .every
        default: break
        }
        debug.room = d.string(forKey: "SillFullScreenRoom").flatMap(FullScreenPolicy.Room.init(rawValue:))
        debug.toggles = seconds("SillFullScreenToggle")
        debug.swipes = seconds("SillFullScreenSwipe")
        debug.shakes = seconds("SillShakeAt")
        return debug
    }()
}
#endif
