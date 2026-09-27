import Foundation
import CoreGraphics

// The first-run tour of the stream screen (docs/first-run-walkthrough-plan.md): the rules, pure.
// What each layout's tour teaches and where it points, when it shows by itself, what it remembers,
// where it goes after a rotation, where its card sits, and every word it says. Foundation and
// CoreGraphics only, so it compiles on its own with swiftc (Tests/checks/tour). TourOverlay.swift
// draws it, StreamScreen feeds it.

// MARK: - Steps, layouts and targets

/// One card of the tour: what it teaches. `allCases` is the tour's order, where things are: the
/// picture first, then the bar from left to right, then down the laptop half.
enum TourTopic: String, CaseIterable, Comparable {
    case touch, bar, settings, laptop

    static func < (a: TourTopic, b: TourTopic) -> Bool { a.rank < b.rank }
    private var rank: Int { TourTopic.allCases.firstIndex(of: self) ?? 0 }
}

/// The two layouts the tour knows: the bar over the picture (the Duo's inner and outer displays on
/// their side, phones and iPads held sideways) and the laptop layout (held upright).
enum TourLayout: String, Hashable {
    case landscape, portrait
}

/// What a step lights: each reported by its view as a frame in the stream screen's space.
enum TourTarget: String, CaseIterable, Hashable {
    case stream, strip, textSize, keyboard, settings, keys, trackpad
}

/// What this device remembers (UserDefaults `Sill.tourSeen`, `Sill.tourSkipped`): the steps passed
/// with Next or Done, and whether Skip was ever tapped.
struct TourMemory: Equatable {
    var seen: Set<TourTopic> = []
    var skipped = false

    init(seen: Set<TourTopic> = [], skipped: Bool = false) {
        self.seen = seen
        self.skipped = skipped
    }

    /// From the saved topic names: a name this build does not know is ignored.
    init(names: [String], skipped: Bool) {
        self.init(seen: Set(names.compactMap(TourTopic.init(rawValue:))), skipped: skipped)
    }

    /// What is saved: the topics seen, in the tour's order.
    var names: [String] { TourTopic.allCases.filter { seen.contains($0) }.map(\.rawValue) }
}

// MARK: - When it shows by itself

/// What the rule looks at, at one moment of a session. Times are `ProcessInfo.systemUptime`.
struct TourMoment: Equatable {
    var now: Double
    /// This session's first picture: the Mac's first window list, a frame size and a source.
    var pictureAt: Double?
    /// When the layout on screen (portrait or landscape) began.
    var layoutAt: Double
    /// This session's picture has had its decision.
    var decided: Bool
    /// The last touch anywhere on the screen, or input sent to the Mac.
    var lastActivityAt: Double?
    /// Touches on the screen now.
    var touchesDown: Int
    /// Something open (the Apps list, the Settings panel, a thumbnail's lights, the Aa ruler, the
    /// software keyboard, the pairing overlay or a link's confirmation), or the app not active.
    var busy: Bool
    /// This session has had its decision in this layout.
    var offered: Bool
    var voiceOver: Bool
    /// Release: always; Debug: only with `-SillTourState`.
    var enabled: Bool
}

enum TourReason: String, Equatable {
    /// Nothing to show here: all of it seen, skipped, already decided, or the tour off.
    case nothingOwed
    /// Something was touched or sent since the picture, or since the turn.
    case used
    /// A touch still down, or something open, at the decision.
    case busy
}

enum TourDecision: Equatable {
    /// Show these steps now.
    case show([TourTopic])
    /// Ask again at this time (nil: at the next change).
    case wait(until: Double?)
    /// Not in this session and layout. The caller marks the layout offered and the picture decided
    /// on any pass or show that comes once there is a picture.
    case pass(TourReason)
}

// MARK: - A run of the tour

/// The tour on screen: its steps, the one showing, and those this run has passed.
struct TourRun: Equatable {
    var steps: [TourTopic]
    var at: TourTopic
    var passed: Set<TourTopic> = []
    /// Take the Tour (every step of the layout), not the automatic tour (the steps owed).
    var replay: Bool

    var index: Int { steps.firstIndex(of: at) ?? 0 }
    var count: Int { steps.count }
    var isLast: Bool { at == steps.last }
    /// The laptop card's subtitle is its own only when it starts a run.
    var firstOfRun: Bool { at == steps.first }
}

// MARK: - Where the card goes

struct TourTail: Equatable {
    enum Edge: String, Equatable { case up, down }
    var edge: Edge
    /// The tip's x, in the screen's space.
    var x: CGFloat
}

struct TourPlacement: Equatable {
    var card: CGRect
    var tail: TourTail?
}

// MARK: - The words

/// A stretch of a row's words; `strong` is a control's name, set semibold.
struct TourSpan: Equatable {
    var text: String
    var strong = false
}

struct TourRow: Equatable {
    /// An SF Symbol (iOS 17.0 or older), decorative: VoiceOver never reads it.
    var symbol: String
    var spans: [TourSpan]
    /// What VoiceOver reads for the row (the key row's caps by their full names).
    var spoken: String
    var text: String { spans.map(\.text).joined() }
}

struct TourCopy: Equatable {
    var title: String
    var subtitle: String?
    var rows: [TourRow]
    /// Where the lit part is, as VoiceOver's hint on the title.
    var hint: String
}

// MARK: - The rules

enum TourPolicy {
    /// A second after the picture, or after a turn, with nothing happening in it.
    static let beat = 1.0

    /// Every step of a layout, in order. Under VoiceOver the picture's step goes: VoiceOver takes
    /// its gestures for itself, and the picture is no accessibility element.
    static func steps(_ layout: TourLayout, voiceOver: Bool) -> [TourTopic] {
        let all: [TourTopic] = layout == .landscape ? [.touch, .bar, .settings] : [.touch, .bar, .settings, .laptop]
        return voiceOver ? all.filter { $0 != .touch } : all
    }

    /// The steps only this layout has: all a turn offers. Portrait: the laptop half; landscape: none.
    static func only(_ layout: TourLayout) -> [TourTopic] {
        layout == .portrait ? [.laptop] : []
    }

    /// What each step lights. Sideways the Keyboard button is in the bar; upright the keyboard is a
    /// cap in the key row, part of `keys`.
    static func targets(_ topic: TourTopic, _ layout: TourLayout) -> [TourTarget] {
        switch topic {
        case .touch: return [.stream]
        case .bar: return layout == .landscape ? [.strip, .textSize, .keyboard] : [.strip, .textSize]
        case .settings: return [.settings]
        case .laptop: return [.keys, .trackpad]
        }
    }

    /// The steps this device is owed in a layout: none once skipped, else those not yet seen.
    static func owed(_ layout: TourLayout, voiceOver: Bool, _ m: TourMemory) -> [TourTopic] {
        if m.skipped { return [] }
        return steps(layout, voiceOver: voiceOver).filter { !m.seen.contains($0) }
    }

    /// The automatic tour's one decision per session and layout (§4): at the picture, or at the
    /// first turn after it, a beat later and only if nothing has happened since.
    static func automatic(_ m: TourMoment, _ layout: TourLayout, _ memory: TourMemory) -> TourDecision {
        guard m.enabled else { return .pass(.nothingOwed) }
        guard !m.offered else { return .pass(.nothingOwed) }
        guard let picture = m.pictureAt else { return .wait(until: nil) }
        // Before the picture's decision every step owed in this layout, from the picture or from
        // a rotation during the beat, which starts it again. After it, a turn: only the steps this
        // layout has alone, from the turn.
        let owedHere = owed(layout, voiceOver: m.voiceOver, memory)
        let list = m.decided ? owedHere.filter { only(layout).contains($0) } : owedHere
        let opens = m.decided ? m.layoutAt : max(picture, m.layoutAt)
        if list.isEmpty { return .pass(.nothingOwed) }
        if let activity = m.lastActivityAt, activity >= opens { return .pass(.used) }
        if m.now < opens + beat { return .wait(until: opens + beat) }
        if m.touchesDown > 0 { return .pass(.busy) }
        if m.busy { return .pass(.busy) }
        return .show(list)
    }

    // MARK: Memory

    /// Next or Done passed a step.
    static func passed(_ t: TourTopic, _ m: TourMemory) -> TourMemory {
        var memory = m
        memory.seen.insert(t)
        return memory
    }

    /// Skip: no automatic tour again on this device. Take the Tour still shows it.
    static func skipped(_ m: TourMemory) -> TourMemory {
        var memory = m
        memory.skipped = true
        return memory
    }

    /// Skip on a card (Esc and VoiceOver's escape gesture are Skip too): in the automatic tour it
    /// turns the tour off for good on this device (`skipped`); in Take the Tour it only closes the
    /// run, since the person asked for that one, and what the automatic tour still owes (the
    /// upright card, a topic a later build adds) stays owed.
    static func skip(_ run: TourRun, _ m: TourMemory) -> TourMemory {
        run.replay ? m : skipped(m)
    }

    // MARK: Runs

    /// The automatic tour: the steps owed, from the first.
    static func run(owed list: [TourTopic]) -> TourRun? {
        guard let first = list.first else { return nil }
        return TourRun(steps: list, at: first, replay: false)
    }

    /// Take the Tour: every step of the layout on screen (under VoiceOver, less what it leaves out),
    /// from `start` when the layout has it, else from the first.
    static func replay(_ layout: TourLayout, voiceOver: Bool, from start: TourTopic? = nil) -> TourRun? {
        let list = steps(layout, voiceOver: voiceOver)
        guard let first = list.first else { return nil }
        let at = start.flatMap { list.contains($0) ? $0 : nil } ?? first
        return TourRun(steps: list, at: at, replay: true)
    }

    /// Next or Done: the step showing is passed; the next step, or nil when that was the last.
    static func next(_ run: TourRun) -> TourRun? {
        var moved = run
        moved.passed.insert(run.at)
        guard let i = run.steps.firstIndex(of: run.at), i + 1 < run.steps.count else { return nil }
        moved.at = run.steps[i + 1]
        return moved
    }

    /// A layout change mid-run (a rotation, a resize, the Duo folded): the run as the new layout
    /// has it, or nil when that layout has nothing left of it (the tour ends, nothing more saved).
    /// Its steps are the new layout's (Take the Tour: all of them; the automatic tour: those owed,
    /// and those this run passed, so the count goes on where it was). The step on screen stays
    /// when the new layout has it; otherwise the next step after it that this run has not passed.
    static func carry(_ run: TourRun, to layout: TourLayout, voiceOver: Bool, memory: TourMemory) -> TourRun? {
        let all = steps(layout, voiceOver: voiceOver)
        let list = run.replay ? all : all.filter { !memory.seen.contains($0) || run.passed.contains($0) }
        var carried = run
        carried.steps = list
        if list.contains(run.at) { return carried }
        guard let next = list.first(where: { $0 > run.at && !run.passed.contains($0) }) else { return nil }
        carried.at = next
        return carried
    }

    // MARK: Where the card goes

    /// From the screen's edges; the bottom one sits above the home indicator.
    static let margin: CGFloat = 16
    /// Between a card and the targets it sits beside.
    static let gap: CGFloat = 12
    static let tailSize = CGSize(width: 16, height: 7)
    /// The tail's tip keeps this far from the card's corners, so its base stays on the straight edge.
    static let tailCorner: CGFloat = 28
    /// Upright, a tail points down only at targets that begin this close below the card.
    static let tailReach: CGFloat = 48
    /// The cutout is this much larger than its targets all round.
    static let cutoutOutset: CGFloat = 4

    /// The card's width: 360 pt; 480 on a screen held sideways that is under 520 pt tall (a phone,
    /// the Duo's outer display), where height is what runs out; 560 at accessibility text sizes;
    /// never more than the screen less its margins.
    static func width(screen: CGSize, layout: TourLayout, accessibilityText: Bool) -> CGFloat {
        let short = layout == .landscape && screen.height < 520
        let preferred: CGFloat = accessibilityText ? 560 : (short ? 480 : 360)
        return max(0, min(preferred, screen.width - 2 * margin))
    }

    /// The crease of the Duo half-folded, or in its laptop posture: `ConnectLayout.topHalf`'s rule
    /// (taller than wide, 600 to 740 pt wide, under 1100 pt tall), where it is the portrait
    /// layout's own split. Nothing of the tour crosses it.
    static func crease(_ screen: CGSize) -> CGFloat? {
        guard screen.height > screen.width, screen.width >= 600, screen.width < 740, screen.height < 1100 else { return nil }
        return (screen.height / 2).rounded()
    }

    /// The lit part: the step's targets as one rectangle, `cutoutOutset` larger all round and
    /// clipped to the screen.
    static func cutout(_ targets: [CGRect], screen: CGSize) -> CGRect? {
        let found = targets.filter { !$0.isNull && !$0.isEmpty }
        guard let first = found.first else { return nil }
        let union = found.dropFirst().reduce(first) { $0.union($1) }
        let lit = union.insetBy(dx: -cutoutOutset, dy: -cutoutOutset).intersection(CGRect(origin: .zero, size: screen))
        return lit.isNull || lit.isEmpty ? nil : lit
    }

    /// The cutout's corner radius: the picture's 12 plus the outset; the bar's buttons and the
    /// laptop half's caps and pad, 20.
    static func radius(_ topic: TourTopic) -> CGFloat {
        topic == .touch ? 16 : 20
    }

    /// Where the card goes, in the screen's space (§6.3). `card` is its width and the height its
    /// words want there; `targets` the union of what its step lights (nil before they are
    /// measured: centred in the picture); `stream` the picture's panel.
    ///
    /// - The picture's step: centred in the picture.
    /// - Sideways, a bar step: 12 pt below its targets, centred on them, with a tail up.
    /// - Upright: in the picture's half, so it never covers the laptop half it is about and never
    ///   crosses the crease; a lower step's bottom 12 pt above the picture's bottom, with a tail
    ///   down only when its targets begin within 48 pt and no crease lies between.
    /// - Too tall for that: it grows toward the top margin, then, upright without a crease, toward
    ///   the bottom margin, over its own targets if it must, and has no tail. Past the whole screen
    ///   less its margins (with a crease, the upper half), it is as tall as the room, and its words
    ///   scroll.
    static func place(card: CGSize, targets: CGRect?, isStream: Bool, screen: CGSize, layout: TourLayout,
                      stream: CGRect, bottomInset: CGFloat) -> TourPlacement {
        let w = card.width
        let h = max(0, card.height)
        let top = margin
        let bottom = max(top, screen.height - margin - max(0, bottomInset))
        let fold = crease(screen)
        // Upright, how low a card goes while it stays in the picture's half.
        let pictureBottom = min(bottom, max(top, min(stream.maxY - gap, fold.map { $0 - margin } ?? .infinity)))

        func x(centredOn mid: CGFloat) -> CGFloat {
            let lo = margin, hi = screen.width - margin - w
            return hi < lo ? (screen.width - w) / 2 : min(max(mid - w / 2, lo), hi)
        }
        func tip(_ card: CGRect, _ mid: CGFloat) -> CGFloat {
            card.width < 2 * tailCorner ? card.midX : min(max(mid, card.minX + tailCorner), card.maxX - tailCorner)
        }

        guard !isStream, let t = targets, !t.isNull, !t.isEmpty else {
            // The picture's step (or targets not measured yet): centred in the picture, then
            // toward the top; upright on a screen without a crease, also toward the bottom.
            let lowest = layout == .landscape ? bottom : pictureBottom
            let cardX = x(centredOn: stream.midX)
            if lowest - h >= top {
                let y = min(max(stream.midY - h / 2, top), lowest - h)
                return TourPlacement(card: CGRect(x: cardX, y: y, width: w, height: h), tail: nil)
            }
            let reach = layout == .portrait && fold == nil ? bottom : lowest
            return TourPlacement(card: CGRect(x: cardX, y: top, width: w, height: min(h, reach - top)), tail: nil)
        }

        let cardX = x(centredOn: t.midX)
        if layout == .landscape {
            // Below the bar's targets while it fits there; else it grows toward the top, over them.
            let below = t.maxY + gap
            if below + h <= bottom {
                let rect = CGRect(x: cardX, y: below, width: w, height: h)
                return TourPlacement(card: rect, tail: TourTail(edge: .up, x: tip(rect, t.midX)))
            }
            let y = max(top, bottom - h)
            return TourPlacement(card: CGRect(x: cardX, y: y, width: w, height: min(h, bottom - y)), tail: nil)
        }

        // Upright: its bottom 12 pt above the picture's bottom while it fits in the picture's half.
        if pictureBottom - h >= top {
            let rect = CGRect(x: cardX, y: pictureBottom - h, width: w, height: h)
            let reaches = t.minY >= rect.maxY && t.minY - rect.maxY <= tailReach
            let noFold = fold.map { !(rect.maxY <= $0 && $0 <= t.minY) } ?? true
            return TourPlacement(card: rect, tail: reaches && noFold ? TourTail(edge: .down, x: tip(rect, t.midX)) : nil)
        }
        let reach = fold == nil ? bottom : pictureBottom
        return TourPlacement(card: CGRect(x: cardX, y: top, width: w, height: min(h, reach - top)), tail: nil)
    }

    // MARK: The words (§7)

    static let skipTitle = "Skip"
    static let nextTitle = "Next"
    static let doneTitle = "Done"
    static let skipHint = "Ends the tour. Take the Tour in Settings shows it again."
    /// The Settings panel's last row.
    static let takeTourTitle = "Take the Tour"
    static func takeTourFootnote(device: String) -> String { "A short tour of Sill’s controls on this \(device)." }
    static func takeTourHint(device: String) -> String { "Shows how to use Sill on this \(device)." }

    /// The title as VoiceOver reads it: its place in the run, when the run has more than one card.
    static func spokenTitle(_ copy: TourCopy, index: Int, count: Int) -> String {
        count > 1 ? "\(copy.title), step \(index + 1) of \(count)" : copy.title
    }

    /// A step's card. ‹Mac› is the Mac's name ("your Mac" when there is none yet); ‹device› is
    /// "iPad" or "iPhone". Under VoiceOver the rows that name a gesture say VoiceOver's way instead,
    /// and the trackpad's rows go (the trackpad is no accessibility element).
    static func copy(_ t: TourTopic, _ layout: TourLayout, mac: String, device: String,
                     voiceOver: Bool, firstOfRun: Bool) -> TourCopy {
        let mac = mac.isEmpty ? "your Mac" : mac
        let iPad = device == "iPad"
        let keyboardRow = row("keyboard", [strong("Keyboard"), plain(" types on \(mac), on screen or with a hardware keyboard.")])
        switch t {
        case .touch:
            var rows = [row("hand.tap", [strong("Tap"), plain(" to click.")]),
                        row("contextualmenu.and.cursorarrow", [strong("Touch and hold"), plain(" to right-click.")]),
                        row("hand.draw", [strong("Drag"), plain(" to scroll.")])]
            if iPad { rows.append(row("applepencil", [strong("Apple Pencil"), plain(" works as a mouse.")])) }
            return TourCopy(title: "Tap, Hold and Drag", subtitle: "What you do here happens on \(mac).", rows: rows,
                            hint: layout == .landscape ? "The picture of \(mac) fills the screen below the bar."
                                                       : "The picture of \(mac) fills the top half of the screen.")
        case .bar:
            var rows: [TourRow]
            // Aa sizes a window, never the Desktop (the Mac ignores a viewport's scale for it), and
            // the first picture is the Desktop: the rows say whose text it is.
            if voiceOver {
                rows = [row("hand.point.up.left", [strong("Each window"), plain(" has actions: close, minimize, full screen, and move left or right. Swipe up or down to hear them.")]),
                        row("textformat.size", [strong("Text size"), plain(" makes a window’s text on \(mac) larger or smaller. Swipe up or down on it.")])]
            } else {
                rows = [row("hand.point.up.left", [strong("Touch and hold"), plain(" a window to close, minimize or go full screen. Keep holding and drag to move it.")]),
                        row("textformat.size", [strong("Aa"), plain(": touch it and slide to make a window’s text larger or smaller.")])]
            }
            if layout == .landscape { rows.append(keyboardRow) }
            return TourCopy(title: "Windows and Text Size", subtitle: nil, rows: rows,
                            hint: layout == .landscape ? "In the bar at the top, after Apps." : "In the bar below the picture, after Apps.")
        case .settings:
            var rows = [row("xmark.circle", [strong("Disconnect"), plain(" is at the bottom of Settings.")]),
                        row("questionmark.circle", [strong("Take the Tour"), plain(" is there too, to see this again.")])]
            if layout == .landscape {
                rows.append(row(iPad ? "ipad" : "iphone", [strong("Hold your \(device) upright"), plain(" for a trackpad and keys.")]))
            }
            return TourCopy(title: "Settings", subtitle: nil, rows: rows, hint: "The last button in the bar.")
        case .laptop:
            var rows: [TourRow]
            if voiceOver {
                rows = [row("command", [strong("cmd, opt, ctrl and shift"), plain(" stay on for the next key: cmd, then C, copies.")],
                            spoken: "Command, Option, Control and Shift stay on for the next key: Command, then C, copies.")]
            } else {
                rows = [row("command", [strong("cmd, opt, ctrl and shift"), plain(" stay on for the next key or trackpad click: tap cmd, then C, to copy.")],
                            spoken: "Command, Option, Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.")]
            }
            rows.append(row("keyboard", [strong("The keyboard key"), plain(" types on \(mac), on screen or with a hardware keyboard.")]))
            if !voiceOver {
                rows.append(row("cursorarrow.click.2", [strong("Tap with two fingers"), plain(" on the trackpad to right-click.")]))
                rows.append(row("hand.draw", [strong("Touch and hold"), plain(" the trackpad, "), strong("then drag"), plain(", to move a window or select text.")]))
            }
            return TourCopy(title: "Keys and Trackpad", subtitle: firstOfRun ? "Upright, Sill adds keys and a trackpad." : nil,
                            rows: rows, hint: "Below the bar: the row of keys, then the trackpad.")
        }
    }

    private static func strong(_ text: String) -> TourSpan { TourSpan(text: text, strong: true) }
    private static func plain(_ text: String) -> TourSpan { TourSpan(text: text, strong: false) }
    private static func row(_ symbol: String, _ spans: [TourSpan], spoken: String? = nil) -> TourRow {
        TourRow(symbol: symbol, spans: spans, spoken: spoken ?? spans.map(\.text).joined())
    }
}
