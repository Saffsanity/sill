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

/// The layouts the tour knows: the bar over the picture (the Duo's inner and outer displays on
/// their side, phones and iPads held sideways); the laptop layout's halves held upright (the Duo's
/// inner display, an iPad, an iPad window narrower than 600 pt), the window bar and the keys under
/// the picture's half; and a phone held upright (`PhonePortraitLayout`: the picture in a 16:10 pane
/// at the top, then row 1 with Apps, Aa, Keyboard, Desktop and Settings, the thumbnails, six keys
/// and the trackpad; the Duo's outer display upright too).
enum TourLayout: String, Hashable {
    case landscape, portrait, phone

    /// Held upright: the halves or a phone's rows, both with the keys and the trackpad.
    var upright: Bool { self != .landscape }
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

/// What the automatic tour decided in a session. It outlives the session's stream screen
/// (StreamClient keeps it), so the automatic reconnect's session can go on with it
/// (`TourPolicy.nextSession`).
struct TourSession: Equatable {
    /// The picture's decision was made.
    var decided = false
    /// The layouts that had their decision.
    var offered: Set<TourLayout> = []
    /// A run is on screen, or put aside under the pairing overlay.
    var running = false
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
    /// The card covers its step's lit part (a room too small beside it): the dim then has no cutout
    /// and no ring, since what is left of them would peek out beside the card as slivers.
    var coversTargets = false
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

    /// The steps only this layout has: all a turn offers. Upright: the keys and the trackpad;
    /// sideways: none.
    static func only(_ layout: TourLayout) -> [TourTopic] {
        layout.upright ? [.laptop] : []
    }

    /// What each step lights. Sideways and on a phone upright the Keyboard button is in the bar (a
    /// phone's row 1, over the thumbnails); in the halves the keyboard is a cap in the key row, part
    /// of `keys`.
    static func targets(_ topic: TourTopic, _ layout: TourLayout) -> [TourTarget] {
        switch topic {
        case .touch: return [.stream]
        case .bar: return layout == .portrait ? [.strip, .textSize] : [.strip, .textSize, .keyboard]
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
        // layout has alone, from the turn, or from the picture of a session that went on with an
        // earlier one's decision (the automatic reconnect's: `nextSession`) in a layout that one
        // never decided in.
        let owedHere = owed(layout, voiceOver: m.voiceOver, memory)
        let list = m.decided ? owedHere.filter { only(layout).contains($0) } : owedHere
        let opens = max(picture, m.layoutAt)
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

    // MARK: Sessions

    /// A new session's start. The automatic reconnect's session (a Wi-Fi drop, the Mac waking, an
    /// eviction after a trip to another app, Sill.app relaunched) goes on with the last session's
    /// decisions, so someone who started at once is not walked through the tour when the picture
    /// comes back; unless the last one ended before its picture's decision, or in the middle of a
    /// run, which then comes back with a beat of its own. A session the person starts (a row's
    /// tap, pairing, a link, a launch) decides afresh.
    static func nextSession(after last: TourSession, reconnected: Bool) -> TourSession {
        guard reconnected, last.decided, !last.running else { return TourSession() }
        return TourSession(decided: true, offered: last.offered, running: false)
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
    /// The least room beside its targets a card takes: its footer and a line or two of words at the
    /// largest text size. Only a smaller room (a tiny window) makes a card cover its targets.
    static let minimumRoom: CGFloat = 200

    /// The card's width: 360 pt; 480 on a screen held sideways that is under 520 pt tall (a phone,
    /// the Duo's outer display), where height is what runs out; 560 at accessibility text sizes;
    /// never more than the screen less its margins, nor, across the book pose's fold, than the
    /// wider page (DuoPosture.pageWidth).
    static func width(screen: CGSize, layout: TourLayout, accessibilityText: Bool, fold: FoldInfo = .inferred) -> CGFloat {
        let short = layout == .landscape && screen.height < 520
        let preferred: CGFloat = accessibilityText ? 560 : (short ? 480 : 360)
        let page = DuoPosture.pageWidth(screenWidth: screen.width, margin: margin, fold: fold) ?? .infinity
        return max(0, min(preferred, page, screen.width - 2 * margin))
    }

    /// The crease of the Duo half-folded upright, its laptop pose: on iOS 27.1 the top of the fold's
    /// real band; before it `ConnectLayout.topHalf`'s rule (taller than wide, 600 to 740 pt wide,
    /// under 1100 pt tall), where it is the portrait layout's own split (DuoPosture.crease). Nothing
    /// of the tour crosses it.
    static func crease(_ screen: CGSize, _ fold: FoldInfo = .inferred) -> CGFloat? {
        guard let band = DuoPosture.crease(screen, fold) else { return nil }
        if case .inferred = fold { return band.top.rounded() }
        return band.top
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
    /// - The picture's step: centred in the picture. Too tall for the picture, it grows toward the
    ///   top margin, then, upright without a crease, toward the bottom margin.
    /// - Sideways, a bar step: 12 pt below its targets, centred on them, with a tail up; too tall
    ///   for the room down to the bottom margin, as tall as that room, its words scrolling.
    /// - Upright: in the picture's half, so it never covers the laptop half it is about and never
    ///   crosses the crease; a lower step's bottom 12 pt above the picture's bottom, with a tail
    ///   down only when its targets begin within 48 pt and no crease lies between. Too tall for
    ///   that: it grows toward the top margin, then down to 12 pt above its targets (with a crease,
    ///   the picture's half), the same tail rule, its words scrolling past that.
    /// - A phone held upright has a short picture over its controls, whose rows sit in the middle
    ///   of the screen: a card too tall for the picture's pane stands 12 pt above its targets,
    ///   growing toward the top margin (from the top margin down, it would half cover a row), and
    ///   one that does not fit above them goes 12 pt under them when it fits there, or when the
    ///   room there is the larger (and holds a card), with a tail up, as sideways. The laptop
    ///   card's targets reach the bottom, so it stays above them.
    /// - A card never covers its own step's targets, so the lit control stays in view at every text
    ///   size; only a room beside them smaller than `minimumRoom` makes it grow over them (toward
    ///   the top sideways, toward the bottom margin upright), with no tail, `coversTargets`.
    /// - Past the whole screen less its margins (with a crease, the upper half), a card is as tall
    ///   as the room, and its words scroll.
    /// - The book pose (the Duo half-folded sideways, `info` its fold): a card that would cross the
    ///   fold goes onto the page its middle is on, or the other when only that one holds it.
    static func place(card: CGSize, targets: CGRect?, isStream: Bool, screen: CGSize, layout: TourLayout,
                      stream: CGRect, bottomInset: CGFloat, fold info: FoldInfo = .inferred) -> TourPlacement {
        let w = card.width
        let h = max(0, card.height)
        let top = margin
        let bottom = max(top, screen.height - margin - max(0, bottomInset))
        let fold = crease(screen, info)
        // Upright, how low a card goes while it stays in the picture's half.
        let pictureBottom = min(bottom, max(top, min(stream.maxY - gap, fold.map { $0 - margin } ?? .infinity)))

        func x(centredOn mid: CGFloat) -> CGFloat {
            DuoPosture.offTheFold(x: clamped(mid), width: w, screenWidth: screen.width, margin: margin, fold: info)
        }
        func clamped(_ mid: CGFloat) -> CGFloat {
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
            let reach = layout.upright && fold == nil ? bottom : lowest
            return TourPlacement(card: CGRect(x: cardX, y: top, width: w, height: min(h, reach - top)), tail: nil)
        }

        let cardX = x(centredOn: t.midX)
        let lit = t.insetBy(dx: -cutoutOutset, dy: -cutoutOutset)
        if layout == .landscape {
            // Below the bar's targets, as tall as its words or as the room down to the bottom
            // margin; only a room too small for a card makes it grow toward the top, over them.
            let below = t.maxY + gap
            let room = bottom - below
            if h <= room || room >= minimumRoom {
                let rect = CGRect(x: cardX, y: below, width: w, height: min(h, room))
                return TourPlacement(card: rect, tail: TourTail(edge: .up, x: tip(rect, t.midX)))
            }
            let y = max(top, bottom - h)
            let rect = CGRect(x: cardX, y: y, width: w, height: min(h, bottom - y))
            return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))
        }

        // Upright: a tail down only at targets that begin within 48 pt, with no crease between.
        func tailDown(_ rect: CGRect) -> TourTail? {
            let reaches = t.minY >= rect.maxY && t.minY - rect.maxY <= tailReach
            let noFold = fold.map { !(rect.maxY <= $0 && $0 <= t.minY) } ?? true
            return reaches && noFold ? TourTail(edge: .down, x: tip(rect, t.midX)) : nil
        }
        // Its bottom 12 pt above the picture's bottom while it fits in the picture's half.
        if pictureBottom - h >= top {
            let rect = CGRect(x: cardX, y: pictureBottom - h, width: w, height: h)
            return TourPlacement(card: rect, tail: tailDown(rect))
        }
        // Too tall: from the top margin down to 12 pt above its targets (with a crease, the
        // picture's half); on a phone under its targets when it fits there, or when that room is
        // the larger; only a room too small for a card makes it grow toward the bottom margin, over
        // them.
        let above = fold == nil ? min(bottom, max(top, t.minY - gap)) : pictureBottom
        if layout == .phone && h > above - top {
            let under = t.maxY + gap
            let room = bottom - under
            if h <= room || (room > above - top && room >= minimumRoom) {
                let rect = CGRect(x: cardX, y: under, width: w, height: min(h, room))
                return TourPlacement(card: rect, tail: TourTail(edge: .up, x: tip(rect, t.midX)))
            }
        }
        if fold != nil || h <= above - top || above - top >= minimumRoom {
            // A phone's card stands on its targets; the halves' grows from the top margin, over the
            // picture, which is the most room there is.
            let y = layout == .phone ? max(top, above - h) : top
            let rect = CGRect(x: cardX, y: y, width: w, height: min(h, above - top))
            return TourPlacement(card: rect, tail: tailDown(rect))
        }
        let rect = CGRect(x: cardX, y: top, width: w, height: min(h, bottom - top))
        return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))
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
            let hint: String
            switch layout {
            case .landscape: hint = "The picture of \(mac) fills the screen below the bar."
            case .portrait: hint = "The picture of \(mac) fills the top half of the screen."
            case .phone: hint = "The picture of \(mac) is at the top of the screen."
            }
            return TourCopy(title: "Tap, Hold and Drag", subtitle: "What you do here happens on \(mac).", rows: rows, hint: hint)
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
            // The Keyboard button is the bar's sideways and a phone's upright; the halves' keyboard
            // is a cap, which the laptop card names.
            if layout != .portrait { rows.append(keyboardRow) }
            let hint: String
            switch layout {
            case .landscape: hint = "In the bar at the top, after Apps."
            case .portrait: hint = "In the bar below the picture, after Apps."
            case .phone: hint = "Under the picture: Aa and Keyboard in the first row, the windows in the second."
            }
            return TourCopy(title: "Windows and Text Size", subtitle: nil, rows: rows, hint: hint)
        case .settings:
            var rows = [row("xmark.circle", [strong("Disconnect"), plain(" is at the bottom of Settings.")]),
                        row("questionmark.circle", [strong("Take the Tour"), plain(" is there too, to see this again.")])]
            if layout == .landscape {
                rows.append(row(iPad ? "ipad" : "iphone", [strong("Hold your \(device) upright"), plain(" for a trackpad and keys.")]))
            }
            return TourCopy(title: "Settings", subtitle: nil, rows: rows,
                            hint: layout == .phone ? "The last button in the row under the picture." : "The last button in the bar.")
        case .laptop:
            var rows: [TourRow]
            if voiceOver {
                rows = [row("command", [strong("cmd, opt, ctrl and shift"), plain(" stay on for the next key: cmd, then C, copies.")],
                            spoken: "Command, Option, Control and Shift stay on for the next key: Command, then C, copies.")]
            } else {
                rows = [row("command", [strong("cmd, opt, ctrl and shift"), plain(" stay on for the next key or trackpad click: tap cmd, then C, to copy.")],
                            spoken: "Command, Option, Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.")]
            }
            // A phone's keyboard is row 1's button, which the bar card names; the halves' is a cap.
            if layout != .phone {
                rows.append(row("keyboard", [strong("The keyboard key"), plain(" types on \(mac), on screen or with a hardware keyboard.")]))
            }
            if !voiceOver {
                rows.append(row("cursorarrow.click.2", [strong("Tap with two fingers"), plain(" on the trackpad to right-click.")]))
                rows.append(row("hand.draw", [strong("Touch and hold"), plain(" the trackpad, "), strong("then drag"), plain(", to move a window or select text.")]))
            }
            return TourCopy(title: "Keys and Trackpad", subtitle: firstOfRun ? "Upright, Sill adds keys and a trackpad." : nil,
                            rows: rows, hint: layout == .phone ? "Under the windows: the row of keys, then the trackpad."
                                                               : "Below the bar: the row of keys, then the trackpad.")
        }
    }

    private static func strong(_ text: String) -> TourSpan { TourSpan(text: text, strong: true) }
    private static func plain(_ text: String) -> TourSpan { TourSpan(text: text, strong: false) }
    private static func row(_ symbol: String, _ spans: [TourSpan], spoken: String? = nil) -> TourRow {
        TourRow(symbol: symbol, spans: spans, spoken: spoken ?? spans.map(\.text).joined())
    }
}
