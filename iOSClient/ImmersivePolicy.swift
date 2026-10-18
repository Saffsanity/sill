import Foundation

/// Immersive, the iPad's full-screen stream (docs/immersive-plan.md): with this device's switch on and a
/// hardware keyboard attached, the landscape stream screen drops its top bar, the panel's 8 pt inset,
/// its rounded frame and the status bar, and the picture fills the display edge to edge. The bar comes
/// back over the picture on demand (⌃⌥⌘B, or a swipe down from the top edge) without resizing it.
///
/// Three states. `off`: today's layout. `immersed`: no bar, the panel the whole screen. `revealed`: the
/// bar floating over that same whole-screen panel. Only a move between `off` and the other two changes
/// the panel's size (one viewport to the Mac); revealing and hiding the bar never does.
///
/// The stream screen owns one, tells it whether Immersive applies (`applies(…)`) and whether something
/// open over the stream holds the bar (the Settings panel, the pairing overlay, the tour, the Apps drawer,
/// the Menus pull-down, the Aa ruler, a thumbnail's lights), and runs the auto-hide timer it asks for.
/// Pure: Foundation only, checked in Tests/checks/immersive.
struct ImmersivePolicy: Equatable {
    enum State: String, CaseIterable, Equatable {
        case off, immersed, revealed
    }

    /// What the auto-hide timer does after an event: nothing, (re)start its `autoHide` seconds, or stop.
    enum Timer: String, Equatable {
        case keep, start, stop
    }

    // MARK: When it applies

    /// Immersive applies: the switch on (as it was when the Settings panel opened, while it is open), a
    /// hardware keyboard attached, the iPad held sideways, a window or the Desktop streaming (nothing
    /// streaming keeps the standard layout, so the first picture never lands in a layout that then
    /// flips: Larger Picture's rule), VoiceOver off (every control stays in reach), and Sill filling
    /// the screen (not a Stage Manager or Split View window).
    static func applies(switchOn: Bool, keyboardAttached: Bool, landscape: Bool, streaming: Bool,
                        voiceOver: Bool, fillsScreen: Bool) -> Bool {
        switchOn && keyboardAttached && landscape && streaming && !voiceOver && fillsScreen
    }

    /// Whether a scene of `size` points fills a screen of `screen` points (either way round, within a
    /// point): Stage Manager and Split View windows do not.
    static func fills(size: (width: Double, height: Double), screen: (width: Double, height: Double)) -> Bool {
        guard size.width > 0, size.height > 0, screen.width > 0, screen.height > 0 else { return false }
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1 }
        return (close(size.width, screen.width) && close(size.height, screen.height))
            || (close(size.width, screen.height) && close(size.height, screen.width))
    }

    // MARK: The state

    /// Immersive applies now (`applies(…)`, as the stream screen last said).
    private(set) var applies = false
    /// Something open over the stream holds the bar.
    private(set) var held = false
    /// The bar was revealed on demand (the shortcut, the edge swipe, a holder's closing).
    private(set) var revealed = false

    var state: State {
        guard applies else { return .off }
        return revealed || held ? .revealed : .immersed
    }

    /// The panel fills the screen: no bar beside it, no inset, no frame, no status bar.
    static func fillsScreen(_ state: State) -> Bool { state != .off }
    /// The bar is on screen: beside the panel (`off`) or over it (`revealed`).
    static func barShown(_ state: State) -> Bool { state != .immersed }

    /// The bar, once revealed, hides after this many seconds with nothing touched on it.
    static let autoHide: Double = 4

    // MARK: Events

    /// What applies, and what holds the bar, changed (the stream screen sends both together on any change
    /// of either). Entering hides the bar (the panel grows to the edges in the same motion) unless
    /// something holds it, forgetting any reveal from before. The last holder closing leaves the bar up for
    /// `autoHide` seconds rather than snatching it away under the finger that closed it.
    mutating func update(applies nowApplies: Bool, held nowHeld: Bool) -> Timer {
        let wasApplying = applies, wasHeld = held
        applies = nowApplies
        held = nowHeld
        guard nowApplies else { return .stop }
        if !wasApplying {
            revealed = false
            return .stop
        }
        if nowHeld { return .stop }
        if wasHeld {
            revealed = true
            return .start
        }
        return .keep
    }

    /// The shortcut: reveal or hide the bar. False when Immersive does not apply, and the chord is the
    /// Mac's like any other. While something holds the bar it stays (the chord is still taken, so it
    /// never reaches the Mac half the time).
    mutating func toggle() -> (taken: Bool, timer: Timer) {
        guard applies else { return (false, .keep) }
        guard !held else { return (true, .keep) }
        revealed.toggle()
        return (true, revealed ? .start : .stop)
    }

    /// A swipe down from the top edge: reveals the bar, or keeps a revealed one up longer.
    mutating func edgeSwipe() -> Timer {
        guard applies, !held else { return .keep }
        revealed = true
        return .start
    }

    /// A touch on the revealed bar: its auto-hide starts again.
    func touched() -> Timer {
        applies && revealed && !held ? .start : .keep
    }

    /// The auto-hide timer ran out: the reveal ends (a bar something holds stays, by `state`).
    mutating func timerFired() {
        revealed = false
    }

    // MARK: The shortcut and the edge

    /// HID usage of B (keyboard page).
    static let toggleUsage: UInt16 = 0x05
    /// ⌃⌥⌘, as UIKeyModifierFlags and KeyModifiers carry them: control 1<<18, option 1<<19, command 1<<20.
    static let toggleModifiers: UInt64 = (1 << 18) | (1 << 19) | (1 << 20)
    /// Shift, control, option and command: the flags a chord is told by (caps lock and the keypad bit
    /// are not).
    private static let chordMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)

    /// ⌃⌥⌘B, and only that: not ⇧⌃⌥⌘B, not ⌃⌘B, whatever caps lock says. (⌃⌘F is macOS's own Enter Full
    /// Screen, so it stays the Mac's.)
    static func isToggle(usage: UInt16, modifiers: UInt64) -> Bool {
        usage == toggleUsage && modifiers & chordMask == toggleModifiers
    }

    /// The edge swipe's zone: a drag must start within this many points of the screen's top edge.
    static let edgeZone: Double = 20

    /// A finger drag that started `startY` points from the top edge and has moved `dx`, `dy`: the edge
    /// swipe when it began in the zone and goes mostly down. Anything else (a tap, a sideways drag on
    /// a browser's tabs, a drag that starts lower) stays the Mac's.
    static func revealsFromEdge(startY: Double, dx: Double, dy: Double) -> Bool {
        startY >= 0 && startY <= edgeZone && dy > 0 && dy > abs(dx)
    }
}
