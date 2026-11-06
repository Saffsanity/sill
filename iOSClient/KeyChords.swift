import Foundation
import StreamProtocol

// The keys this device sends for a shortcut: the Spotlight key's ⌘Space, the portrait key row's keys
// with whatever is latched (held down from the touch to the release: `HeldCap`), a latched ⌘, ⌃ or ⌥
// on the software keyboard (a latched shift with its return or tab too), the modifiers the portrait
// trackpad holds down around a click or a drag, and a hardware keyboard's keys (Esc also through a key
// command, sent once whichever channel iPadOS uses; the letters, digits and the rest too while the Mac types
// them: `KeyTyping`). One place, so each goes out the way a keyboard sends it: a shortcut's modifiers pressed
// with their own keys around it, and every key's up after its down (2026-09-27, the stuck command
// after Spotlight). A shortcut sent as one key down and up carrying its modifiers left them set on
// every Mac from before that fix, which posted the up as it came, and the next click there was a
// ⌘-click.
// The keys this device sends for a shortcut: the Spotlight key's ⌘Space, the clipboard's ⌘V after a
// Paste (paste right away), the portrait key row's keys with whatever is latched, a latched ⌘, ⌃ or
// ⌥ on the software keyboard (a latched shift with its return or tab too), the modifiers the portrait
// trackpad holds down around a click or a drag, and a hardware keyboard's keys (Esc also through a
// key command, sent once whichever channel iPadOS uses). One place, so each goes out the way a
// keyboard sends it: a shortcut's modifiers pressed with their own keys around it, and every key's up
// after its down (2026-09-27, the stuck command after Spotlight). A shortcut sent as one key down and
// up carrying its modifiers left them set on every Mac from before that fix, which posted the up as
// it came, and the next click there was a ⌘-click.
//
// Pure: Foundation, StreamProtocol and TextComposition.swift's KeyTyping only, checked with swiftc beside
// the host's KeyStrokes (Tests/checks/key-strokes), which is what the Mac makes of these events.

/// The modifier bits an `InputEvent.key` carries: `UIKeyModifierFlags` raw values, which sit at the
/// same bit positions as the `CGEventFlags` the host posts with, so they travel unchanged.
struct KeyModifiers: OptionSet {
    let rawValue: UInt64

    static let shift   = KeyModifiers(rawValue: 1 << 17)
    static let control = KeyModifiers(rawValue: 1 << 18)
    static let option  = KeyModifiers(rawValue: 1 << 19)
    static let command = KeyModifiers(rawValue: 1 << 20)
    /// Caps Lock on (UIKeyModifierFlags.alphaShift): a state of the keyboard, never a key the device
    /// holds down for the Mac.
    static let capsLock = KeyModifiers(rawValue: 1 << 16)

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
    /// latched, the key alone. `down` then `up`, at once.
    static func press(_ usage: UInt16, with modifiers: KeyModifiers) -> [InputEvent] {
        down(usage, with: modifiers) + up(usage, with: modifiers)
    }

    /// A key going down with `modifiers`, as a keyboard presses it: each modifier's own key down, then
    /// the key down carrying them all. A key held so is repeated by the Mac (KeyRepeat, on the host)
    /// until its `up`.
    static func down(_ usage: UInt16, with modifiers: KeyModifiers) -> [InputEvent] {
        modifiersDown(modifiers) + [.key(hidUsage: usage, down: true, modifiers: modifiers.rawValue)]
    }

    /// Its release: the key up still carrying `modifiers`, then their own keys up in reverse.
    static func up(_ usage: UInt16, with modifiers: KeyModifiers) -> [InputEvent] {
        [.key(hidUsage: usage, down: false, modifiers: modifiers.rawValue)] + modifiersUp(modifiers)
    }

    /// Spotlight on the Mac: exactly ⌘Space, ⌘'s own key down, Space down and up, ⌘ up.
    static let spotlight: [InputEvent] = press(0x2C, with: .command)

    /// Paste on the Mac (the clipboard's Paste right away, once the Mac has the text: ClipboardPolicy's
    /// `pastesOnReceipt`): exactly ⌘V, ⌘'s own key down, V down and up, ⌘ up, whatever is latched.
    static let paste: [InputEvent] = press(ClipboardPolicy.pasteKey, with: .command)

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

/// The portrait key row's esc, tab and arrows, held (#162): a cap's key goes down when a finger lands on
/// it and comes up when the finger lifts, slides off or is cancelled, so the Mac repeats it while it is
/// held, after its own Delay Until Repeat and at its Key Repeat Rate, as it repeats a key of its own
/// keyboard (KeyRepeat, on the host: an event Sill posts never repeats by itself). What is latched goes
/// down with it, its modifiers' own keys first (`KeyChord.down`), and is spent at the touch, so a
/// modifier latched while the cap is held waits for the next key (the caller spends the latch when a
/// key goes down with it: `spendsLatch`). One cap at a time, as the Mac repeats one key at a time: a
/// finger on a second cap lets the first come up first. The cap's own action, which its Button sends as
/// the finger lifts on it, sends nothing more, or the up of a press whose end was not told yet (so a
/// release the press's end missed still lets the key up); a cap activated with no touch (VoiceOver,
/// Switch Control, Voice Control, Full Keyboard Access) sends its whole press at once, as every cap did
/// before. The latching modifiers, the Keyboard cap and Spotlight are taps, as before.
struct HeldCap {
    /// The cap whose key is down on the Mac, with the modifiers it went down with.
    private(set) var down: (usage: UInt16, modifiers: KeyModifiers)?
    /// A finger's press on a cap whose action has not come: when the finger left it (nil while it is
    /// still on it). The cap's action then, or within `actionWindow` of the finger leaving, is its own.
    private struct Touch { var endedAt: Double? }
    private var touches: [UInt16: Touch] = [:]
    /// How long after the finger leaves a cap its Button's action counts as the touch's own: SwiftUI
    /// sends it as the press ends, just before or just after.
    static let actionWindow = 0.5

    /// A finger landed on cap `usage` at `time` (systemUptime) with `latched` latched: the cap held
    /// before it comes up, then this cap's key goes down with `latched`; nothing when this cap is down
    /// already.
    mutating func touchDown(_ usage: UInt16, latched: KeyModifiers, at time: Double) -> [InputEvent] {
        touches[usage] = Touch(endedAt: nil)
        if down?.usage == usage { return [] }
        let before = releaseAll()
        down = (usage, latched)
        return before + KeyChord.down(usage, with: latched)
    }

    /// The finger left cap `usage` at `time` (lifted, slid off, cancelled): its key up, with the
    /// modifiers it went down with, if it is the cap down.
    mutating func touchUp(_ usage: UInt16, at time: Double) -> [InputEvent] {
        if touches[usage]?.endedAt == nil { touches[usage]?.endedAt = time }
        guard let held = down, held.usage == usage else { return [] }
        down = nil
        return KeyChord.up(usage, with: held.modifiers)
    }

    /// Cap `usage`'s action at `time`: after a touch, nothing (its key went down and up with it), or the
    /// up of the press if its end was not told yet: the action comes with the release; with no touch, the
    /// whole press with `latched`.
    mutating func activated(_ usage: UInt16, latched: KeyModifiers, at time: Double) -> [InputEvent] {
        if let touch = touches.removeValue(forKey: usage), time - (touch.endedAt ?? time) <= Self.actionWindow {
            return down?.usage == usage ? touchUp(usage, at: time) : []
        }
        return KeyChord.press(usage, with: latched)
    }

    /// Whether what a cap sent spent the latch: a key went down with it (a touch's down, a whole press).
    static func spendsLatch(_ events: [InputEvent]) -> Bool {
        events.contains { if case .key(_, true, _) = $0 { return true } else { return false } }
    }

    /// The cap down comes up: the key row leaving the screen, after which no release comes.
    mutating func releaseAll() -> [InputEvent] {
        guard let held = down else { return [] }
        down = nil
        return KeyChord.up(held.usage, with: held.modifiers)
    }
}

/// A hardware keyboard's keys on their way to the Mac (InputOverlayView's pressesBegan, pressesEnded
/// and pressesCancelled, and its Esc key commands: `commanded`, `pressed`, `released`). A key goes to
/// the Mac as a key, or to the text system, when it goes down (by its usage, the modifier flags and who
/// types the characters then: `goesAsKey`, `KeyTyping`), and its up follows the same way whatever the
/// modifier flags or the typing say by then. Judged again at the release, as before, a key held while ⌘
/// was let go went up in the text system and stayed down on the Mac, and ⌘'s own release reached the
/// Mac with command still on it, or not at all (UIKit's flags at a modifier's release are those before
/// or after it), so the Mac kept ⌘ held.
///
/// A key's down carries the flags UIKit gives it (the shortcut: ⌘⇧S with shift held, whether Shift's own
/// key went to the Mac or to the text system; and Shift for a letter typed with Caps Lock on: `carried`);
/// a modifier's own key and every up carry only the modifier keys down on the Mac, as a keyboard would
/// leave them, so a Mac from before 2026-09-27, which posts each key's flags as they come, is left with
/// nothing this device does not hold there.
struct ForwardedKeys {
    /// The keys whose down went to the Mac and whose up has not, in the order they went down.
    private(set) var down: [UInt16] = []
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

    /// The keys a keyboard types characters with, which go to the Mac as keys while the Mac types them
    /// (`KeyTyping.keys`), as from a keyboard plugged into it, so it repeats a held one and its own layout
    /// and dead keys apply: the letters, the digits, Return, Delete, Tab, Space, the punctuation keys
    /// every layout has (- = [ ] \ ; ' ` , . /), and Shift's two keys, so the Mac knows Shift is held
    /// (a held letter's repeats follow it, and a click with it held is a shift-click). Every one is a key
    /// every Sill for Mac answers to (KeyStrokes.virtualKeys), so a Mac from before key repeat types them
    /// too, once each. The keypad, the ISO keyboards' two extra keys (Non-US # and \) and Caps Lock stay
    /// the text system's whoever types: no Sill for Mac before this one has the first two, and Caps Lock's
    /// state is the iPad's (a letter typed with it on carries Shift: `carried`).
    static let characterUsages: Set<UInt16> = Set(0x04...0x28).union([0x2A, 0x2B, 0x2C]).union(0x2D...0x31)
        .union(0x33...0x38).union([0xE1, 0xE5])

    /// The letters A to Z, by their keys' places (HID usages 0x04 to 0x1D).
    static let letterUsages: ClosedRange<UInt16> = 0x04...0x1D

    /// Whether a key pressed with these modifiers goes to the Mac as a key rather than to the text
    /// system: one of `keyUsages`, return or tab with shift held (`shiftedKeyUsages`), any key
    /// while ⌘, ⌃ or ⌥ is held, as those make shortcuts (⌘S, ⌃A, ⌥←) and never reach the text
    /// system, and, while the Mac types the characters (`KeyTyping.keys`), every key that types one
    /// (`characterUsages`). Otherwise shift alone makes characters, which the text system composes
    /// (shifted, dead-keyed, from an IME) and sends as text.
    static func goesAsKey(_ usage: UInt16, modifiers: UInt64, typing: KeyTyping) -> Bool {
        keyUsages.contains(usage) || modifiers & KeyModifiers.shortcutMakers.rawValue != 0
            || (shiftedKeyUsages.contains(usage) && modifiers & KeyModifiers.shift.rawValue != 0)
            || (typing == .keys && characterUsages.contains(usage))
    }

    /// The modifiers a key's down carries to the Mac: UIKit's flags, and Shift with them for a letter typed
    /// with Caps Lock on and neither ⌘, ⌃ nor ⌥ held (one goes to the Mac as a key only while the Mac
    /// types the characters), so the Mac types it in capitals whatever it makes of the caps lock flag a
    /// posted event carries: Caps Lock is the iPad's own (its key stays the text system's, and the Mac's
    /// caps lock is never turned on). A shortcut keeps its flags as they are: ⌘A with Caps Lock on is ⌘A,
    /// not ⌘⇧A.
    static func carried(_ usage: UInt16, modifiers: UInt64) -> UInt64 {
        guard letterUsages.contains(usage), modifiers & KeyModifiers.capsLock.rawValue != 0,
              modifiers & KeyModifiers.shortcutMakers.rawValue == 0 else { return modifiers }
        return modifiers | KeyModifiers.shift.rawValue
    }

    /// A key pressed, with the modifier flags UIKit gives it and who types the characters now: its down,
    /// when it goes to the Mac as a key; nil when the text system takes it.
    mutating func began(_ usage: UInt16, modifiers: UInt64, typing: KeyTyping) -> InputEvent? {
        guard Self.goesAsKey(usage, modifiers: modifiers, typing: typing) else { return nil }
        if !down.contains(usage) { down.append(usage) }
        let isModifier = KeyModifiers.flag(forKey: usage) != nil
        return .key(hidUsage: usage, down: true, modifiers: isModifier ? held : Self.carried(usage, modifiers: modifiers))
    }

    /// A key released, or its press cancelled (the app going to the background, the keyboard gone):
    /// its up, when its down went to the Mac, with the modifier keys still down there; nil when the
    /// text system had it.
    mutating func ended(_ usage: UInt16) -> InputEvent? {
        guard let i = down.firstIndex(of: usage) else { return nil }
        down.remove(at: i)
        return .key(hidUsage: usage, down: false, modifiers: held)
    }

    /// Every key still down on the Mac going up, the last pressed first, each with the modifier keys
    /// still down after it: the overlay no longer taking keys (the Settings panel, the tour) or leaving
    /// the screen, after which UIKit sends it no release.
    mutating func releaseAll() -> [InputEvent] {
        var ups: [InputEvent] = []
        while let usage = down.last, let up = ended(usage) { ups.append(up) }
        swallowed.removeAll()
        return ups
    }

    /// iPadOS took a key's press for its own switch between keyboards (⌃Space with keyboards in two
    /// languages: TextInputRules.isKeyboardSwitch), a key down the Mac never hears. On a Mac a key's down
    /// stops the key repeating before it (KeyRepeat, on the host), so every key down on the Mac but the
    /// modifiers' own comes up now, the last pressed first, each with the modifier keys still down there;
    /// a modifier's own key stays down for its own release (⌃'s, the switch's own). A key let go here has
    /// its release go to the text system later, as after `releaseAll`. Without it a letter or an arrow held
    /// across ⌃Space went on repeating on the Mac, with control while ⌃ was down (⌃P, a line up; ⌃→, the
    /// next Space), then plain, until it came up.
    mutating func keyboardSwitch() -> [InputEvent] {
        var ups: [InputEvent] = []
        for usage in down.reversed() where KeyModifiers.flag(forKey: usage) == nil {
            if let up = ended(usage) { ups.append(up) }
        }
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
    /// came first, and that press's own up follows. A key command's key (Esc) is a key whoever types the
    /// characters (`keyUsages`).
    mutating func commanded(_ usage: UInt16, modifiers: UInt64, at time: Double) -> [InputEvent] {
        guard !down.contains(usage), let press = began(usage, modifiers: modifiers, typing: .text) else { return [] }
        commandedAt[usage] = time
        return [press] + (ended(usage).map { [$0] } ?? [])
    }

    /// A key pressed (pressesBegan), with UIKit's modifier flags, its press's timestamp and who types the
    /// characters now: `began`'s answer, unless a key command sent the same key press already (the same
    /// key, pressed no later than the command fired), which is swallowed, and its up with it.
    mutating func pressed(_ usage: UInt16, modifiers: UInt64, at time: Double, typing: KeyTyping) -> Press {
        if let sent = commandedAt[usage], time <= sent {
            swallowed.insert(usage)
            return .swallow
        }
        return began(usage, modifiers: modifiers, typing: typing).map { .send($0) } ?? .text
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
