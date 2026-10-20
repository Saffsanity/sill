import Foundation
import StreamProtocol

// The keys this device sends for a shortcut: the Spotlight key's ⌘Space, the portrait key row's keys
// with whatever is latched, a latched ⌘, ⌃ or ⌥ on the software keyboard (a latched shift with its
// return or tab too), the modifiers the portrait trackpad holds down around a click or a drag, and a
// hardware keyboard's keys (Esc also through a key command, sent once whichever channel iPadOS
// uses). One place, so each goes out the way a keyboard sends it: a shortcut's modifiers pressed
// with their own keys around it, and every key's up after its down (2026-09-27, the stuck command
// after Spotlight). A shortcut sent as one key down and up carrying its modifiers left them set on
// every Mac from before that fix, which posted the up as it came, and the next click there was a
// ⌘-click.
//
// Pure: Foundation and StreamProtocol only, checked with swiftc beside the host's KeyStrokes
// (Tests/checks/key-strokes), which is what the Mac makes of these events.

/// The modifier bits an `InputEvent.key` carries: `UIKeyModifierFlags` raw values, which sit at the
/// same bit positions as the `CGEventFlags` the host posts with, so they travel unchanged.
struct KeyModifiers: OptionSet {
    let rawValue: UInt64

    static let shift   = KeyModifiers(rawValue: 1 << 17)
    static let control = KeyModifiers(rawValue: 1 << 18)
    static let option  = KeyModifiers(rawValue: 1 << 19)
    static let command = KeyModifiers(rawValue: 1 << 20)

    /// The three that make shortcuts instead of characters. Shift is not one of them: it changes
    /// which character the keyboard produces, which the text path already handles.
    static let shortcutMakers: KeyModifiers = [.control, .option, .command]

    /// Each latched modifier as its own key: the HID usage to press, and the bit it contributes.
    /// A pointer event has no modifier field, so a modified click has to hold these down around it.
    var keys: [(usage: UInt16, flag: KeyModifiers)] {
        var out: [(usage: UInt16, flag: KeyModifiers)] = []
        if contains(.control) { out.append((0xE0, .control)) }
        if contains(.shift)   { out.append((0xE1, .shift)) }
        if contains(.option)  { out.append((0xE2, .option)) }
        if contains(.command) { out.append((0xE3, .command)) }
        return out
    }

    /// The modifier a key is (a HID usage: left and right control, shift, option and command, 0xE0 to
    /// 0xE7), or nil for any other key.
    static func flag(forKey usage: UInt16) -> KeyModifiers? {
        switch usage {
        case 0xE0, 0xE4: return .control
        case 0xE1, 0xE5: return .shift
        case 0xE2, 0xE6: return .option
        case 0xE3, 0xE7: return .command
        default: return nil
        }
    }
}

enum KeyChord {
    /// One key with `modifiers`, as a keyboard sends it: each modifier's own key down, the key down
    /// and up carrying them all, each modifier's key up (`modifiersDown`, `modifiersUp`). With nothing
    /// latched, the key alone.
    static func press(_ usage: UInt16, with modifiers: KeyModifiers) -> [InputEvent] {
        modifiersDown(modifiers)
            + [.key(hidUsage: usage, down: true, modifiers: modifiers.rawValue),
               .key(hidUsage: usage, down: false, modifiers: modifiers.rawValue)]
            + modifiersUp(modifiers)
    }

    /// Spotlight on the Mac: exactly ⌘Space, ⌘'s own key down, Space down and up, ⌘ up.
    static let spotlight: [InputEvent] = press(0x2C, with: .command)

    /// Each of `modifiers`' own keys going down, in `KeyModifiers.keys`' order, each carrying the
    /// flags in force once it is down: what a shortcut and the trackpad's modified click or drag
    /// press first.
    static func modifiersDown(_ modifiers: KeyModifiers) -> [InputEvent] {
        var held: KeyModifiers = []
        return modifiers.keys.map { key in
            held.insert(key.flag)
            return .key(hidUsage: key.usage, down: true, modifiers: held.rawValue)
        }
    }

    /// The same keys going up in the reverse order, each carrying the flags still in force after it:
    /// what the shortcut and the click or the drag release after.
    static func modifiersUp(_ modifiers: KeyModifiers) -> [InputEvent] {
        var held = modifiers
        return modifiers.keys.reversed().map { key in
            held.remove(key.flag)
            return .key(hidUsage: key.usage, down: false, modifiers: held.rawValue)
        }
    }
}

/// A hardware keyboard's keys on their way to the Mac (InputOverlayView's pressesBegan, pressesEnded
/// and pressesCancelled, and its Esc key commands: `commanded`, `pressed`, `released`). A key goes to
/// the Mac as a key, or to the text system, when it goes down, and
/// its up follows the same way whatever the modifier flags say by then. Judged again at the release,
/// as before, a key held while ⌘ was let go went up in the text system and stayed down on the Mac, and
/// ⌘'s own release reached the Mac with command still on it, or not at all (UIKit's flags at a
/// modifier's release are those before or after it), so the Mac kept ⌘ held.
///
/// A key's down carries the flags UIKit gives it (the shortcut: ⌘⇧S with shift held for the text
/// system too); a modifier's own key and every up carry only the modifier keys down on the Mac, as a
/// keyboard would leave them, so a Mac from before 2026-09-27, which posts each key's flags as they
/// come, is left with nothing this device does not hold there.
struct ForwardedKeys {
    /// Initial delay and interval when a forwarded key or modified key chord (⌥←, ⌘→, ←) is held
    /// down on a hardware keyboard (#162: UIKit's text system repeats plain characters, while
    /// forwarded keys go through pressesBegan once).
    static let repeatDelay: TimeInterval = 0.4
    static let repeatInterval: TimeInterval = 0.05

    struct Repeating: Equatable {
        let usage: UInt16
        let modifiers: UInt64
    }

    /// The keys whose down went to the Mac and whose up has not, in the order they went down.
    private(set) var down: [UInt16] = []
    /// The non-modifier key currently held down for key repeat, with the modifiers its down carried.
    private(set) var repeating: Repeating?
    var isRepeating: Bool { repeating != nil }
    /// When a key command last sent each key (`commanded`; systemUptime, as UIPress timestamps are),
    /// so the press of the same key that UIKit may hand pressesBegan after it is known for the same
    /// key press.
    private var commandedAt: [UInt16: Double] = [:]
    /// The keys whose press a key command had sent already (`pressed` swallowed it): their up is
    /// swallowed too, never handed to the text system.
    private(set) var swallowed: Set<UInt16> = []

    /// The keys the text system never delivers, which go to the Mac as keys whatever is held: the
    /// arrows, escape, forward delete, home, end, page up and down, F1 to F12, and ⌘, ⌃ and ⌥
    /// themselves (so a click while one is held is a modified click on the Mac).
    static let keyUsages: Set<UInt16> = [
        0x4F, 0x50, 0x51, 0x52,                                                   // right, left, down, up
        0x29, 0x4C, 0x4A, 0x4D, 0x4B, 0x4E,                                       // escape, forward delete, home, end, page up and down
        0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45,   // F1…F12
        0xE0, 0xE2, 0xE3, 0xE4, 0xE6, 0xE7,                                       // control, option, command, left and right
    ]

    /// Return and tab: with shift held they go as keys too. The text system hands them over as
    /// "\n" and "\t" with the shift gone, and the Mac then typed a plain Return (sending a chat
    /// message where ⇧Return means a new line) and a plain Tab (moving focus forward, not back).
    static let shiftedKeyUsages: Set<UInt16> = [0x28, 0x2B]

    /// Whether a key pressed with these modifiers goes to the Mac as a key rather than to the text
    /// system: one of `keyUsages`, return or tab with shift held (`shiftedKeyUsages`), or any key
    /// while ⌘, ⌃ or ⌥ is held, as those make shortcuts (⌘S, ⌃A, ⌥←) and never reach the text
    /// system. Shift alone otherwise makes characters, which the text system composes (shifted,
    /// dead-keyed, from an IME) and sends as text.
    static func goesAsKey(_ usage: UInt16, modifiers: UInt64) -> Bool {
        keyUsages.contains(usage) || modifiers & KeyModifiers.shortcutMakers.rawValue != 0
            || (shiftedKeyUsages.contains(usage) && modifiers & KeyModifiers.shift.rawValue != 0)
    }

    /// A key pressed, with the modifier flags UIKit gives it: its down, when it goes to the Mac as a
    /// key; nil when the text system takes it.
    mutating func began(_ usage: UInt16, modifiers: UInt64) -> InputEvent? {
        repeating = nil
        guard Self.goesAsKey(usage, modifiers: modifiers) else { return nil }
        if !down.contains(usage) { down.append(usage) }
        let isModifier = KeyModifiers.flag(forKey: usage) != nil
        if !isModifier, usage != 0x29 { repeating = Repeating(usage: usage, modifiers: modifiers | held) }
        return .key(hidUsage: usage, down: true, modifiers: isModifier ? held : modifiers)
    }

    /// A key released, or its press cancelled (the app going to the background, the keyboard gone):
    /// its up, when its down went to the Mac, with the modifier keys still down there; nil when the
    /// text system had it.
    mutating func ended(_ usage: UInt16) -> InputEvent? {
        defer { if repeating?.usage == usage || KeyModifiers.flag(forKey: usage) != nil { repeating = nil } }
        guard let i = down.firstIndex(of: usage) else { return nil }
        down.remove(at: i)
        return .key(hidUsage: usage, down: false, modifiers: held)
    }

    /// The repeat event while the last pressed non-modifier key remains held down; nil otherwise.
    func repeated() -> InputEvent? {
        guard let r = repeating, down.contains(r.usage) else { return nil }
        return .key(hidUsage: r.usage, down: true, modifiers: r.modifiers)
    }

    /// Every key still down on the Mac going up, the last pressed first, each with the modifier keys
    /// still down after it: the overlay no longer taking keys (the Settings panel, the tour) or leaving
    /// the screen, after which UIKit sends it no release.
    mutating func releaseAll() -> [InputEvent] {
        var ups: [InputEvent] = []
        while let usage = down.last, let up = ended(usage) { ups.append(up) }
        swallowed.removeAll()
        repeating = nil
        return ups
    }

    // MARK: A key command's key (Esc)

    // iPadOS can keep a hardware Escape from pressesBegan (#67), so InputOverlayView also has key
    // commands for it, asking for priority over the text system. A key command has no up, so its key
    // goes down and up at once. A device that hands the same press to both must not send it twice:
    // the press came first (its down is in `down`), and the command sends nothing; or the command came
    // first, and the press, no later than the command, is swallowed with its up.

    /// What pressesBegan, pressesEnded and pressesCancelled do with a hardware key.
    enum Press: Equatable {
        /// To the Mac.
        case send(InputEvent)
        /// To the text system (super), which types it.
        case text
        /// Nowhere: a key command sent this press already.
        case swallow
    }

    /// A key command for `usage`, fired at `time` (systemUptime) with its modifiers: the key's down and
    /// up as `began` and `ended` make them. Nothing when the key is down on the Mac already: its press
    /// came first, and that press's own up follows.
    mutating func commanded(_ usage: UInt16, modifiers: UInt64, at time: Double) -> [InputEvent] {
        guard !down.contains(usage), let press = began(usage, modifiers: modifiers) else { return [] }
        commandedAt[usage] = time
        return [press] + (ended(usage).map { [$0] } ?? [])
    }

    /// A key pressed (pressesBegan), with UIKit's modifier flags and its press's timestamp: `began`'s
    /// answer, unless a key command sent the same key press already (the same key, pressed no later than
    /// the command fired), which is swallowed, and its up with it.
    mutating func pressed(_ usage: UInt16, modifiers: UInt64, at time: Double) -> Press {
        if let sent = commandedAt[usage], time <= sent {
            swallowed.insert(usage)
            return .swallow
        }
        return began(usage, modifiers: modifiers).map { .send($0) } ?? .text
    }

    /// A key released or its press cancelled (pressesEnded, pressesCancelled): `ended`'s answer, or
    /// swallowed when its press was.
    mutating func released(_ usage: UInt16) -> Press {
        if swallowed.remove(usage) != nil { return .swallow }
        return ended(usage).map { .send($0) } ?? .text
    }

    /// The modifier flags of the modifier keys down on the Mac.
    private var held: UInt64 { down.reduce(0) { $0 | (KeyModifiers.flag(forKey: $1)?.rawValue ?? 0) } }
}
