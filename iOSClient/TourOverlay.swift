import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// The first-run tour over the stream screen (docs/first-run-walkthrough-plan.md): the dim with the
// lit part cut out of it, the card, what reports where the lit parts are, what the tour remembers,
// and the watcher that tells the rule whether anything was touched. The rules themselves are
// TourPolicy's. A view in the stream screen's hierarchy, like the Settings panel and the pairing
// overlay: never a sheet, a popover or TipKit (the Duo harness could not hold a presentation, and
// one could cross the half-folded crease). It sends nothing to the Mac.

// MARK: - Targets

/// The stream screen's coordinate space (`StreamScreen` names it): every target's frame, the dim's
/// and the card's are in it.
enum TourSpace {
    static let name = "sill.screen"
}

/// Where each of the tour's targets is on the screen now.
struct TourTargetsKey: PreferenceKey {
    static let defaultValue: [TourTarget: CGRect] = [:]
    static func reduce(value: inout [TourTarget: CGRect], nextValue: () -> [TourTarget: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame, less `inset`, as one of the tour's targets. A clear background:
    /// nothing drawn, nothing hit-tested.
    func tourTarget(_ target: TourTarget, inset: EdgeInsets = EdgeInsets()) -> some View {
        background {
            GeometryReader { g in
                let f = g.frame(in: .named(TourSpace.name))
                Color.clear.preference(key: TourTargetsKey.self, value: [target: CGRect(
                    x: f.minX + inset.leading, y: f.minY + inset.top,
                    width: max(0, f.width - inset.leading - inset.trailing),
                    height: max(0, f.height - inset.top - inset.bottom))])
            }
        }
    }
}

// MARK: - What it remembers

/// `Sill.tourSeen` (the topics passed with Next or Done) and `Sill.tourSkipped`, in the app's own
/// defaults: per device, not per Mac (the privacy manifest's UserDefaults reason covers them).
///
/// DEBUG: the automatic tour runs only with `-SillTourState fresh|landscape|done|skipped|saved`
/// (otherwise no harness photo and no other feature's live test ever gets a tour over it); `fresh`
/// is nothing seen, `landscape` the three sideways steps seen, `done` all four, `skipped` Skip
/// tapped, each for this run only and never written back; `saved` reads and writes the saved keys,
/// as a Release build does. The mock harness writes nothing unless `saved` says so.
final class TourStore {
    static let seenKey = "Sill.tourSeen"
    static let skippedKey = "Sill.tourSkipped"

    private(set) var memory: TourMemory
    /// Whether the automatic tour runs at all (Release: always).
    let automatic: Bool
    private let persists: Bool

    init(defaults: UserDefaults = .standard) {
        let saved = TourMemory(names: defaults.stringArray(forKey: Self.seenKey) ?? [],
                               skipped: defaults.bool(forKey: Self.skippedKey))
        #if DEBUG
        let state = defaults.string(forKey: "SillTourState")
        let mock = defaults.string(forKey: "SillLayout") != nil && !defaults.bool(forKey: "SillLive")
        automatic = state != nil
        switch state {
        case "fresh": memory = TourMemory(); persists = false
        case "landscape": memory = TourMemory(seen: [.touch, .bar, .settings]); persists = false
        case "done": memory = TourMemory(seen: Set(TourTopic.allCases)); persists = false
        case "skipped": memory = TourMemory(skipped: true); persists = false
        case "saved": memory = saved; persists = true
        default: memory = saved; persists = !mock
        }
        #else
        automatic = true
        memory = saved
        persists = true
        #endif
    }

    /// Next, Done and Skip save as they go, so a session that ends mid-tour keeps what was passed.
    func save(_ m: TourMemory) {
        memory = m
        guard persists else { return }
        UserDefaults.standard.set(m.names, forKey: Self.seenKey)
        UserDefaults.standard.set(m.skipped, forKey: Self.skippedKey)
    }

    /// Whether what is saved outlives this run, for the console.
    var writes: Bool { persists }
}

// MARK: - Every touch, taken by none

/// What the watcher saw: touches down now, and when the last one began or ended (systemUptime).
/// A plain object, so a touch never re-renders the stream screen. Main thread.
final class TouchWatch {
    var down = 0
    var lastTouchAt: Double?
}

/// Adds a watcher to the stream screen's window while the screen is up: every touch on the
/// screen, the bar's, the picture's, the thumbnail strip's scrolling, the Pencil's and the iPad
/// trackpad's or mouse's clicks, counts as something happening (§6.6). A zero-size view that finds
/// its window, as `EscapeKey` finds its view controller.
struct TouchWatcher: UIViewRepresentable {
    let watch: TouchWatch

    func makeUIView(context: Context) -> Anchor { Anchor(watch: watch) }
    func updateUIView(_ anchor: Anchor, context: Context) { anchor.recognizer.watch = watch }
    static func dismantleUIView(_ anchor: Anchor, coordinator: ()) { anchor.detach() }

    final class Anchor: UIView {
        let recognizer = TouchWatchRecognizer()
        private weak var host: UIWindow?

        init(watch: TouchWatch) {
            super.init(frame: .zero)
            recognizer.watch = watch
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { detach(); return }
            guard host !== window else { return }
            detach()
            window.addGestureRecognizer(recognizer)
            host = window
        }

        func detach() {
            host?.removeGestureRecognizer(recognizer)
            host = nil
        }
    }
}

/// A recognizer that never recognizes: it counts the touches it sees and fails when the last one
/// ends. It delays nothing, cancels nothing, prevents nothing and is simultaneous with everything,
/// so no gesture of the stream, the bar or SwiftUI waits for it or loses a touch to it.
final class TouchWatchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var watch: TouchWatch?
    private var tracked = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        allowedTouchTypes = [UITouch.TouchType.direct, .indirect, .pencil, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        tracked += touches.count
        stamp()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        tracked = max(0, tracked - touches.count)
        stamp()
        if tracked == 0 { state = .failed }
    }

    private func stamp() {
        watch?.down = tracked
        watch?.lastTouchAt = ProcessInfo.processInfo.systemUptime
    }

    override func reset() {
        super.reset()
        tracked = 0
        watch?.down = 0
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

// MARK: - The overlay

/// The tour on screen: the dim over the whole screen with the step's cutout and ring, then the
/// card. It takes every touch (the stream screen's layouts stop hit-testing while it shows), so a
/// gesture tried on the dim never reaches the Mac; a tap outside the card nudges Next.
struct TourOverlay: View {
    let run: TourRun
    let copy: TourCopy
    let layout: TourLayout
    let targets: [TourTarget: CGRect]
    /// The stream screen's size, and the home indicator's inset its frame runs under.
    let screen: CGSize
    let bottomInset: CGFloat
    let next: () -> Void
    let skip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where the card is (reported by the card): the dim's tap area leaves it out.
    @State private var card: TourCardReport? = nil
    @State private var nudges = 0

    private var stepTargets: [CGRect] { TourPolicy.targets(run.at, layout).compactMap { targets[$0] } }

    private var geometry: TourGeometry {
        let found = stepTargets
        let union = found.first.map { first in found.dropFirst().reduce(first) { $0.union($1) } }
        return TourGeometry(screen: screen, layout: layout, stream: targets[.stream] ?? CGRect(origin: .zero, size: screen),
                            bottomInset: bottomInset, targets: union, isStream: run.at == .touch,
                            width: TourPolicy.width(screen: screen, layout: layout, accessibilityText: typeSize.isAccessibilitySize))
    }

    var body: some View {
        let g = geometry
        ZStack(alignment: .topLeading) {
            TourDim(cutout: TourPolicy.cutout(stepTargets, screen: screen), radius: TourPolicy.radius(run.at),
                    card: card?.frame, step: run.at, nudge: nudge)
                // Reduce Motion: the lit part cross-fades to the next instead of travelling.
                .id(reduceMotion ? run.at.rawValue : "dim")
                .transition(.opacity)
            TourCardLayout {
                TourCard(copy: copy, run: run, geometry: g, nudges: nudges, next: next, skip: skip)
                    .layoutValue(key: TourGeometryKey.self, value: g)
                    .id(reduceMotion ? run.at.rawValue : "card")
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(TourCardReportKey.self) { report in
            card = report
            #if DEBUG
            if let r = report { print("tour: " + Self.describe(r, screen: screen, layout: layout)) }
            #endif
        }
        // Esc is Skip, or Done on the last card; the newest EscapeKey answers first.
        .background(EscapeKey(action: run.isLast ? next : skip))
        // VoiceOver stays in the tour while it shows; the escape gesture skips, Magic Tap goes on.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if run.isLast { next() } else { skip() } }
        .accessibilityAction(.magicTap) { next() }
    }

    /// A tap outside the card: nothing, but Next draws the eye.
    private func nudge() { nudges += 1 }

    #if DEBUG
    /// "screen 1000×710 (landscape); card 281,94 360×230, tail up at 461"
    static func describe(_ r: TourCardReport, screen: CGSize, layout: TourLayout) -> String {
        func n(_ v: CGFloat) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
        let tail = r.tail.map { ", tail \($0.edge.rawValue) at \(n($0.x))" } ?? ", no tail"
        return "screen \(n(screen.width))×\(n(screen.height)) (\(layout.rawValue)); card \(n(r.frame.minX)),\(n(r.frame.minY)) \(n(r.frame.width))×\(n(r.frame.height))" + tail
    }
    #endif
}

/// Where a card sits and what it is placed against: carried to the layout (and to the card's own
/// tail) as a layout value, so the card lands in its place on the first frame.
struct TourGeometry: Equatable {
    var screen: CGSize
    var layout: TourLayout
    var stream: CGRect
    var bottomInset: CGFloat
    var targets: CGRect?
    var isStream: Bool
    var width: CGFloat

    func place(height: CGFloat) -> TourPlacement {
        TourPolicy.place(card: CGSize(width: width, height: height), targets: targets, isStream: isStream,
                         screen: screen, layout: layout, stream: stream, bottomInset: bottomInset)
    }
}

private struct TourGeometryKey: LayoutValueKey {
    static let defaultValue = TourGeometry(screen: .zero, layout: .landscape, stream: .zero, bottomInset: 0,
                                           targets: nil, isStream: true, width: 0)
}

/// Measures each card at its width and puts it where TourPolicy.place says: as tall as its words,
/// or as the room allows (its words then scroll). Two cards only while Reduce Motion cross-fades
/// one step into the next, each where its own step puts it.
private struct TourCardLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for card in subviews {
            let g = card[TourGeometryKey.self]
            let wanted = card.sizeThatFits(ProposedViewSize(width: g.width, height: nil)).height
            let p = g.place(height: wanted)
            card.place(at: CGPoint(x: bounds.minX + p.card.minX, y: bounds.minY + p.card.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: p.card.width, height: p.card.height))
        }
    }
}

/// The card's frame on the screen and its tail, as placed.
struct TourCardReport: Equatable {
    var frame: CGRect
    var tail: TourTail?
}

private struct TourCardReportKey: PreferenceKey {
    static let defaultValue: TourCardReport? = nil
    static func reduce(value: inout TourCardReport?, nextValue: () -> TourCardReport?) {
        value = nextValue() ?? value
    }
}

// MARK: - The dim

/// Black at 0.58 (the Apps list's dim) over the whole screen, its safe areas included, with the
/// step's cutout clear and ringed in the accent. The targets are measured in the stream screen's
/// space, whose origin sits inside the top and side safe areas, so the dim reads its own frame in
/// that space and moves the cutout by it: unmoved, the ring would sit an inset away from its
/// controls on every phone. Its tap area is the screen less the card, so it can never take a tap
/// meant for the card's buttons (a backdrop's tap gesture did, in the pairing overlay).
private struct TourDim: View {
    let cutout: CGRect?
    let radius: CGFloat
    let card: CGRect?
    let step: TourTopic
    let nudge: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .named(TourSpace.name)).origin
            let hole = cutout?.offsetBy(dx: -origin.x, dy: -origin.y)
            let cardHere = card?.offsetBy(dx: -origin.x, dy: -origin.y)
            ZStack(alignment: .topLeading) {
                DimShape(hole: hole ?? .zero, radius: radius, open: hole != nil)
                    .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                if let hole {
                    RingShape(hole: hole, radius: radius)
                        .stroke(Palette.accent, lineWidth: 2)
                        .modifier(RingPulse(hole: hole, size: g.size, step: step, on: !reduceMotion))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(TapArea(card: cardHere), eoFill: true)
            .onTapGesture(perform: nudge)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The screen with a rounded hole in it (even-odd). Animatable, so the hole travels to the next
/// step's targets.
private struct DimShape: Shape {
    var hole: CGRect
    var radius: CGFloat
    var open: Bool

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, radius) }
        set { hole.animatableData = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if open { path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous) }
        return path
    }
}

/// The ring: 2 pt inside the hole's edge, travelling with it.
private struct RingShape: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, radius) }
        set { hole.animatableData = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = max(0, radius - 1)
        return Path(roundedRect: hole.insetBy(dx: 1, dy: 1), cornerSize: CGSize(width: r, height: r), style: .continuous)
    }
}

/// Next: once the ring has arrived, it grows 4 pt all round and back, once. Nothing under Reduce
/// Motion, and nothing repeats.
private struct RingPulse: ViewModifier {
    let hole: CGRect
    let size: CGSize
    let step: TourTopic
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.phaseAnimator([0.0, 1.0, 0.0], trigger: step) { ring, phase in
                ring.scaleEffect(x: 1 + 8 * phase / max(hole.width, 1), y: 1 + 8 * phase / max(hole.height, 1),
                                 anchor: UnitPoint(x: hole.midX / max(size.width, 1), y: hole.midY / max(size.height, 1)))
            } animation: { phase in
                phase == 1 ? .easeOut(duration: 0.15).delay(0.3) : .easeIn(duration: 0.15)
            }
        } else {
            content
        }
    }
}

/// The dim's tap area: the screen less the card.
private struct TapArea: Shape {
    var card: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let card { path.addRoundedRect(in: card, cornerSize: CGSize(width: 20, height: 20), style: .continuous) }
        return path
    }
}

// MARK: - The card

/// One step's card, in the drawer's and the panel's material: the title, a subtitle on two cards,
/// the rows (a symbol, then words with the control's name semibold), and Skip, the dots and Next
/// or Done. Only the title and rows scroll, when the card is taller than its room; the footer stays
/// in reach. Every text size, the accessibility sizes included.
private struct TourCard: View {
    let copy: TourCopy
    let run: TourRun
    let geometry: TourGeometry
    let nudges: Int
    let next: () -> Void
    let skip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var titleFocused: Bool
    @ScaledMetric(relativeTo: .subheadline) private var symbolWidth: CGFloat = 22
    @State private var appeared = false

    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .vertical) {
                words
                ScrollView { words.padding(.bottom, 16) }
                    .scrollIndicatorsFlash(onAppear: true)
                    .scrollBounceBehavior(.basedOnSize)
                    // Words that run on under the footer fade out instead of being cut mid-line.
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 16)
                        }
                    }
            }
            footer
                .padding(.top, 14)
        }
        .padding(14)
        .background(Self.shape.fill(Palette.bar))
        .overlay(Self.shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 30, x: 0, y: 24)
        .overlay { tail }
        .contentShape(Self.shape)
        .tint(Palette.accent)
        // In: from 0.94 about where its tail is, as the panel grows from its button.
        .scaleEffect(appeared || reduceMotion ? 1 : 0.94, anchor: appearAnchor)
        .onAppear {
            withAnimation(.spring(duration: 0.25, bounce: 0.15)) { appeared = true }
            titleFocused = true
        }
        // Each step: VoiceOver's focus on the new title, and a tick on an iPhone.
        .onChange(of: run.at) { _, _ in
            titleFocused = true
            AccessibilityNotification.LayoutChanged().post()
        }
        .sensoryFeedback(.selection, trigger: run.at)
    }

    private var appearAnchor: UnitPoint {
        if geometry.isStream { return .center }
        return geometry.layout == .landscape ? .top : .bottom
    }

    // MARK: Words

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(copy.title)
                .font(.headline)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityLabel(TourPolicy.spokenTitle(copy, index: run.index, count: run.count))
                .accessibilityHint(copy.hint)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            if let subtitle = copy.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(copy.rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A symbol, then the words; at accessibility sizes the symbol above them. Read by VoiceOver as
    /// its words alone.
    @ViewBuilder private func rowView(_ row: TourRow) -> some View {
        let text = Text(Self.attributed(row))
            .font(.subheadline)
            .foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    symbol(row)
                    text
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    symbol(row).frame(width: symbolWidth)
                    text
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }

    private func symbol(_ row: TourRow) -> some View {
        Image(systemName: row.symbol)
            .font(.subheadline)
            .foregroundStyle(Palette.accent)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: run.at)
            .symbolEffectsRemoved(reduceMotion)
            .accessibilityHidden(true)
    }

    /// The row's words with its control's name semibold: attributes on plain text, never Markdown,
    /// so the Mac's name is shown as it is.
    static func attributed(_ row: TourRow) -> AttributedString {
        var out = AttributedString()
        for span in row.spans {
            var piece = AttributedString(span.text)
            if span.strong { piece.font = .subheadline.weight(.semibold) }
            out += piece
        }
        return out
    }

    // MARK: Footer

    /// Skip, the dots and Next or Done on one line while it fits; else Next over Skip, full width.
    /// The buttons' words never wrap (fixed size), so the line is measured as it would draw, and a
    /// line that would squeeze them gives way to the stack.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                // Kept on the last card, hidden, so the dots stay where they were.
                skipButton
                    .opacity(run.isLast ? 0 : 1)
                    .disabled(run.isLast)
                    .accessibilityHidden(run.isLast)
                Spacer(minLength: 4)
                dots
                Spacer(minLength: 4)
                nextButton(wide: false)
            }
            VStack(spacing: 4) {
                nextButton(wide: true)
                if !run.isLast { skipButton.frame(maxWidth: .infinity) }
            }
        }
    }

    private var skipButton: some View {
        Button(action: skip) {
            Text(TourPolicy.skipTitle)
                .font(.body)
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(TourPolicy.skipHint)
    }

    private func nextButton(wide: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: next) {
            Text(run.isLast ? TourPolicy.doneTitle : TourPolicy.nextTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 4)
                .frame(minWidth: 88, minHeight: 44)
                .frame(maxWidth: wide ? .infinity : nil)
                .padding(.horizontal, 12)
                .background(shape.fill(Palette.accent))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        // A tap on the dim: Next grows a little and back (brightens, under Reduce Motion).
        .phaseAnimator([0.0, 1.0, 0.0], trigger: nudges) { button, phase in
            button
                .scaleEffect(reduceMotion ? 1 : 1 + 0.06 * phase)
                .brightness(reduceMotion ? 0.15 * phase : 0)
        } animation: { _ in
            .easeInOut(duration: 0.125)
        }
    }

    /// The step's place in the run: none on a one-card run. The title says it to VoiceOver.
    @ViewBuilder private var dots: some View {
        if run.count > 1 {
            HStack(spacing: 6) {
                ForEach(0..<run.count, id: \.self) { i in
                    Circle()
                        .fill(i == run.index ? Palette.accent : Palette.muted.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Tail

    /// The tail, when the card sits where its step wants it (TourPolicy.place: never on a card
    /// that had to grow over its targets), drawn with the card so it moves with it. Also reports
    /// where the card is, for the dim's tap area and the console. Both come from the card's laid
    /// out height, not from its frame on screen, which the appear animation's scale changes every
    /// frame: placed again at the height it was given, a card lands where TourCardLayout put it
    /// (as tall as its words, or as the room, which place() hands back unchanged).
    private var tail: some View {
        GeometryReader { g in
            let placed = geometry.place(height: g.size.height)
            ZStack(alignment: .topLeading) {
                if let tail = placed.tail {
                    TailFill(tipX: tail.x - placed.card.minX, up: tail.edge == .up)
                        .fill(Palette.bar)
                    TailEdge(tipX: tail.x - placed.card.minX, up: tail.edge == .up)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .preference(key: TourCardReportKey.self, value: TourCardReport(frame: placed.card, tail: placed.tail))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The tail's fill: 16 pt at its base, 7 pt tall, over the card's border where it leaves the card.
private struct TailFill: Shape {
    let tipX: CGFloat
    let up: Bool

    func path(in rect: CGRect) -> Path {
        let half = TourPolicy.tailSize.width / 2, h = TourPolicy.tailSize.height
        let base = up ? rect.minY + 1 : rect.maxY - 1
        let tip = up ? rect.minY - h : rect.maxY + h
        var path = Path()
        path.move(to: CGPoint(x: tipX - half, y: base))
        path.addLine(to: CGPoint(x: tipX, y: tip))
        path.addLine(to: CGPoint(x: tipX + half, y: base))
        path.closeSubpath()
        return path
    }
}

/// The tail's two slanted edges, in the card border's colour.
private struct TailEdge: Shape {
    let tipX: CGFloat
    let up: Bool

    func path(in rect: CGRect) -> Path {
        let half = TourPolicy.tailSize.width / 2, h = TourPolicy.tailSize.height
        let base = up ? rect.minY + 0.5 : rect.maxY - 0.5
        let tip = up ? rect.minY - h : rect.maxY + h
        var path = Path()
        path.move(to: CGPoint(x: tipX - half, y: base))
        path.addLine(to: CGPoint(x: tipX, y: tip))
        path.addLine(to: CGPoint(x: tipX + half, y: base))
        return path
    }
}

// MARK: - DEBUG stand-ins

#if DEBUG
/// The harness's stand-ins for what the gates may not do (tap, touch, turn on VoiceOver), read once
/// from the launch arguments (ContentView's contract):
/// `-SillTour touch|bar|settings|laptop` starts the tour at that step, as Take the Tour does, at the
/// first picture (the mock's is at once); `-SillTourPress next@S|skip@S` presses Next (Done on the
/// last card) S seconds after each card appears, or Skip once; `-SillTourActivityAt S` is a touch S
/// seconds after the picture; `-SillTakeTourAt S` opens the Settings panel S seconds after the
/// picture and presses its Take the Tour a second later; `-SillTourVoiceOver 1` gives the run and
/// its words as under VoiceOver.
struct TourDebug {
    enum Press: Equatable { case next(Double), skip(Double) }
    let start: TourTopic?
    let press: Press?
    let activityAt: Double?
    let takeTourAt: Double?
    let voiceOver: Bool

    static let current: TourDebug = {
        let d = UserDefaults.standard
        func seconds(_ key: String) -> Double? { d.object(forKey: key) == nil ? nil : d.double(forKey: key) }
        var press: Press?
        if let raw = d.string(forKey: "SillTourPress") {
            let parts = raw.split(separator: "@")
            if parts.count == 2, let s = Double(parts[1]) {
                press = parts[0] == "skip" ? .skip(s) : parts[0] == "next" ? .next(s) : nil
            }
        }
        return TourDebug(start: d.string(forKey: "SillTour").flatMap(TourTopic.init(rawValue:)), press: press,
                         activityAt: seconds("SillTourActivityAt"), takeTourAt: seconds("SillTakeTourAt"),
                         voiceOver: d.bool(forKey: "SillTourVoiceOver"))
    }()
}
#endif
