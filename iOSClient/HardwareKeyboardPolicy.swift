import Foundation

/// The stream's input view (InputOverlayView) and a hardware keyboard on this device: whether the view
/// holds the keyboard, whose holding it is, and what to do when something changes
/// (docs/hardware-keyboard-plan.md §2). Keys and typed text reach the Mac only while the view is first
/// responder. With a hardware keyboard attached the view takes the keyboard by itself (`automatic`),
/// so typing reaches the Mac without the Keyboard button, after a rotation, a reconnect and whatever
/// took the keyboard meanwhile; the button keeps its meaning for the software keyboard (`own`, the
/// person's).
///
/// Only the person's own holding is the person's: it lights the Keyboard button, and it is what the
/// first-run tour's rule counts as the keyboard being up and its changes as something happening, so a
/// person with a keyboard attached still gets the tour (StreamScreen's `tourBusy`, `noteAction`).
///
/// The stream screen's `InputOverlayProxy` owns one (it outlives a rotation; a new session's screen
/// makes a new one), tells it what happens and does what it answers. Pure: Foundation only, checked
/// in Tests/checks/hardware-keyboard.
struct HardwareKeyboardPolicy: Equatable {
    /// What can be open over the stream that takes the keyboard for itself, or must keep keys from the
    /// Mac: the Settings panel, the pairing overlay (Pair This iPad…, an outside link), the first-run
    /// tour, the Apps drawer (its search field), the Menus pull-down. The Add a Mac card is the connect
    /// screen's, where no input view is on screen.
    enum Taker: String, CaseIterable, Hashable {
        case settings, pairing, tour, drawer, menus
        #if os(visionOS)
        case inactive
        #endif
    }

    /// Who holds the keyboard now: nobody, this rule for the hardware keyboard, or the person.
    enum Hold: String, Equatable {
        case none, automatic, own
    }

    /// What the input view does (the proxy does it).
    enum Action: Equatable, CustomStringConvertible {
        /// Become first responder: for the hardware keyboard (an empty input view, nothing drawn, not
        /// the person's) or as the person's own (the system keyboard).
        case take(automatic: Bool)
        /// Already first responder for the hardware keyboard, now the person's: the system keyboard's
        /// views come back, the Keyboard button lights.
        case makeOwn
        /// Already first responder as the person's, now the hardware keyboard's: the software keyboard
        /// goes, keys still reach the Mac.
        case makeAutomatic
        /// Resign first responder.
        case letGo

        var description: String {
            switch self {
            case .take(let automatic): return automatic ? "take (hardware keyboard)" : "take (the person's)"
            case .makeOwn: return "make it the person's"
            case .makeAutomatic: return "make it the hardware keyboard's"
            case .letGo: return "let go"
            }
        }
    }

    /// Who holds it now, as UIKit has confirmed (`became`, `resigned`), or as `makeOwn` and
    /// `makeAutomatic` set it.
    private(set) var hold: Hold = .none
    /// A hardware keyboard is attached (GameController's coalesced keyboard).
    private(set) var attached: Bool
    /// What is open that takes the keyboard.
    private(set) var takers: Set<Taker> = []
    /// The current input view is in a window: a session's stream screen shows.
    private(set) var onScreen = false
    /// What this view held before it last let go, for a first responder UIKit gives back by itself
    /// (after a presentation): the same again.
    private(set) var lastHeld: Hold = .none

    /// visionOS must never acquire a shared physical keyboard merely because it is connected.
    private let automaticCapture: Bool
    init(attached: Bool = false, automaticCapture: Bool = Self.platformAutomaticCapture) {
        self.attached = attached
        self.automaticCapture = automaticCapture
    }
    static var platformAutomaticCapture: Bool {
        #if os(visionOS)
        return false
        #else
        return true
        #endif
    }

    /// The hardware keyboard's hold is wanted: a session's input view in a window, a keyboard attached,
    /// nothing open that takes the keyboard.
    var wantsAutomatic: Bool { automaticCapture && onScreen && attached && takers.isEmpty }

    /// The person's own keyboard is up: the Keyboard button lights, the tour counts it.
    var isOwn: Bool { hold == .own }

    /// Take it for the hardware keyboard when wanted and nobody holds it.
    private var takeIfWanted: [Action] { hold == .none && wantsAutomatic ? [.take(automatic: true)] : [] }

    // MARK: Events

    /// A new input view joined a window and is now the current one: a session's start, a rotation's
    /// other layout, a reconnect's new screen. It holds nothing yet. The old view's resignation, when it
    /// comes, is the old view's (the proxy does not pass it on).
    mutating func joined() -> [Action] {
        onScreen = true
        hold = .none
        lastHeld = .none
        return takeIfWanted
    }

    /// The current input view left its window (UIKit takes its first responder with it).
    mutating func left() {
        onScreen = false
        hold = .none
    }

    /// A hardware keyboard attached or the last one went. Only a change acts: an attach takes the
    /// keyboard if wanted; a detach lets the hardware keyboard's hold go (the person's own stays: they
    /// asked for the keyboard, and iPadOS now shows its software one).
    mutating func keyboard(attached now: Bool) -> [Action] {
        guard now != attached else { return [] }
        attached = now
        if now { return takeIfWanted }
        return hold == .automatic ? [.letGo] : []
    }

    /// What is open changed. Something open: the hardware keyboard's hold lets go (the person's own
    /// stays, as before: the Settings panel, the tour and the pairing overlay take it down themselves,
    /// the drawer and the Menus pull-down never did). The last one closed: taken for the hardware
    /// keyboard if wanted, unless the person's own came back first.
    mutating func takers(_ now: Set<Taker>) -> [Action] {
        let was = takers
        takers = now
        if !now.isEmpty { return hold == .automatic || (!automaticCapture && hold == .own) ? [.letGo] : [] }
        return was.isEmpty ? [] : takeIfWanted
    }

    /// The Keyboard button (and the portrait key row's keyboard cap). Nobody holds it: the person's
    /// own (the software keyboard; with a hardware keyboard attached, iPadOS's own small bar), while a
    /// view is in a window (between a rotation's two views, nothing). The hardware keyboard holds it:
    /// now the person's. The person holds it: down, and back to the hardware keyboard at once when it
    /// is wanted, so the software keyboard goes and keys still reach the Mac.
    mutating func toggled() -> [Action] {
        switch hold {
        case .none: return onScreen ? [.take(automatic: false)] : []
        case .automatic:
            hold = .own
            return [.makeOwn]
        case .own:
            guard wantsAutomatic else { return [.letGo] }
            hold = .automatic
            return [.makeAutomatic]
        }
    }

    /// `setKeyboard(shown:)`. True: the person's keyboard put back (the Settings panel or the tour
    /// closing over the keyboard they had up, the Menus pull-down after Settings; DEBUG
    /// `-SillKeyboard 1`), while a view is in a window. False: whoever holds it lets go (the Settings
    /// panel, the tour and the pairing overlay opening).
    mutating func shown(_ show: Bool) -> [Action] {
        guard show else { return hold == .none ? [] : [.letGo] }
        switch hold {
        case .none: return onScreen ? [.take(automatic: false)] : []
        case .automatic:
            hold = .own
            return [.makeOwn]
        case .own: return []
        }
    }

    /// The kind a first responder UIKit gives back by itself would be (the view needs it before it
    /// becomes first responder, for its input view): what this view last held, else the hardware
    /// keyboard's when that is wanted, else the person's.
    var unpromptedKind: Hold {
        if lastHeld != .none { return lastHeld }
        return wantsAutomatic ? .automatic : .own
    }

    /// The current view became first responder. `automatic`: what was asked (`take`); nil when UIKit
    /// did it by itself, which counts as `unpromptedKind`. A hardware keyboard's hold that is not
    /// wanted any more lets go at once.
    mutating func became(automatic: Bool?) -> [Action] {
        if let automatic {
            hold = automatic ? .automatic : .own
        } else {
            hold = unpromptedKind
        }
        return hold == .automatic && !wantsAutomatic ? [.letGo] : []
    }

    /// The current view resigned: let go of here, or another responder took the keyboard (a text field
    /// this rule does not know). Not fought: the next moment above takes it back.
    mutating func resigned() {
        if hold != .none { lastHeld = hold }
        hold = .none
    }
}
