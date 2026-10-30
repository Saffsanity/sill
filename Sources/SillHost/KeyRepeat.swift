import Foundation

// A device's key held down, repeated on the Mac as the Mac repeats a key of its own keyboard (#162;
// Noah, 2026-10-27: "same as a regular keyboard, wait times and all … Same as desktop."). The HID
// system repeats a held key of a keyboard it reads; an event posted from a CGEventSource never
// repeats, so a held arrow, Forward Delete or ⌘Z went to the Mac once, however long the device held
// it. InputInjector repeats the key itself, by this rule, for every device and with no wire change:
//   - After the Mac's own Delay Until Repeat (NSEvent.keyRepeatDelay), then at its Key Repeat Rate
//     (NSEvent.keyRepeatInterval), both read at the key's down, so a change in System Settings applies
//     from the next key (`timing`). Each repeat is the key's down again with the autorepeat flag, as a
//     keyboard's repeats are, never a new down: its up is the one the device sends.
//   - Every key repeats but a modifier's own key (the eight), Caps Lock, fn and the media keys
//     (`repeats`, by the Mac's keycode).
//   - One key at a time, the last pressed: another key's down, any device's, stops the one before (and
//     repeats itself if it may), as on a Mac, and the key before does not take over again when the
//     newer one comes up. A modifier's own key going down or up does not stop it: the repeats after it
//     carry the change, what the key's down carried less a modifier let go since, and what the
//     modifier keys down hold now (holding ← and then pressing ⇧ selects, as on a Mac).
//   - It stops at that key's up (whoever lets go of it: the key is up on the Mac), at typed text and
//     at a trackpad gesture's shortcut (both keys too), when its device leaves or the host ends (every
//     key let go), and when input has nowhere to land (the coordinator's `Landing`: nothing streams, or
//     a switch dropped what was held).
//   - It waits while input is held for an app's activation (a repeat must not go out ahead of the
//     input that came before it, the key's own up perhaps among it).
//   - It waits while its device has gone quiet (`silence`; a device pings four times a second), and
//     once the device is heard again it starts over, after the delay: a network can hold a key's up
//     for seconds before the Mac gives the device up (eviction, 4 to 8 s), which a keyboard's cable
//     never does, and a held ⌥⌫ would otherwise go on deleting words through a Wi-Fi stall.
//   - Its first repeat (after the press, and after the device was quiet) waits for a word from its
//     device heard since, and no earlier than `firstWord` before that repeat is due (`firstAfter`), so
//     a key only pressed, its up held back by a stalled link, is not repeated: the link keeps the
//     device's messages in order, so a word that came after the up comes after it, and a ping sent while
//     the key was down for a moment, before its up (a letter typed, a Delete), says nothing of the key
//     half a second on. A held key's pings come every quarter of a second, so the word is there by then
//     (`firstWord` is a ping's interval and a margin): the first repeat waits only for a ping that comes
//     late. With a Delay Until Repeat under `firstWord` any word since the press does.
//
// Pure: Foundation only, checked with swiftc (Tests/checks/key-repeat, with KeyStrokes; its `package`
// access needs -package-name sill). Nothing here posts or sleeps: InputInjector tells it each keyboard
// event it posts (`posted`) and asks it, at the times it names, whether a repeat goes out (`step`).

package struct KeyRepeat: Sendable {
    /// A device's connection (KeyStrokes.Device): whose key repeats, and whose silence stops it.
    package typealias Device = ObjectIdentifier

    /// The Mac's two settings as the repeat takes them: the wait before the first repeat and the time
    /// between repeats, in seconds.
    package struct Timing: Equatable, Sendable {
        package var delay: Double
        package var interval: Double
        package init(delay: Double, interval: Double) { self.delay = delay; self.interval = interval }
    }

    /// The shortest wait before a key's first repeat: a shorter Delay Until Repeat (one set with
    /// `defaults`; System Settings' shortest is 0.25 s) counts as this, so a tap whose up the network
    /// holds back a moment never repeats.
    package static let shortestDelay = 0.1
    /// The shortest time between two repeats (System Settings' fastest is 1/30 s, `defaults` can set
    /// 1/60 s): a shorter Key Repeat Rate counts as this.
    package static let shortestInterval = 0.015
    /// A wait or an interval this long or longer repeats nothing: no keyboard's repeat waits a minute,
    /// and System Settings' Key Repeat Rate "Off" is, by report, stored as a far longer wait (not checked
    /// here: no setting of this Mac was changed).
    package static let off = 60.0
    /// How long a device may say nothing before its key stops repeating: a device pings every 0.25 s
    /// (StreamClient.pingInterval), so this is two pings missed.
    package static let silence = 0.5
    /// How long before a key's first repeat is due (after its press, or after its device was quiet) its
    /// device must have been heard, at the earliest, for that repeat to go out (`Held.firstAfter`): a ping's
    /// interval (0.25 s) and 50 ms for its lateness, so a key held down has its word in time, and a key
    /// pressed for a moment (a letter typed, up a tenth of a second later) whose up a stalled link holds
    /// back has none: the pings sent while it was down came before.
    package static let firstWord = 0.3
    /// How soon a held key that is waiting (its device quiet, or input held for an activation) is
    /// looked at again, at most.
    package static let lookAgain = 0.05
    /// What this host says of it in every window list (`WindowList.keyRepeat`): 1, a held key repeated as
    /// above. A device sends a hardware keyboard's characters as keys (letters, digits, Space, Delete…)
    /// only to a host that says so, since a Mac that repeats none would type each of them once, where
    /// iPadOS's text system repeats Delete and Space itself.
    package static let generation = 1

    /// The Mac's settings (NSEvent.keyRepeatDelay and keyRepeatInterval) as the repeat takes them, or
    /// nil for no repeat: Off, or nonsense (zero or less, not a number, infinite: each fails these).
    package static func timing(delay: Double, interval: Double) -> Timing? {
        guard delay > 0, interval > 0, delay < off, interval < off else { return nil }
        return Timing(delay: max(delay, shortestDelay), interval: max(interval, shortestInterval))
    }

    /// The modifiers' own keys (Carbon's kVK_*: right command, command, shift, option, control, right
    /// shift, right option, right control) and the flag each holds (CGEventFlags' masks, as KeyStrokes
    /// has them).
    package static let modifierKeys: [UInt16: UInt64] = [
        54: 0x10_0000, 55: 0x10_0000, 56: 0x02_0000, 60: 0x02_0000,
        58: 0x08_0000, 61: 0x08_0000, 59: 0x04_0000, 62: 0x04_0000,
    ]
    /// The keys a Mac never repeats: the modifiers' own, Caps Lock (57), fn (63), and the media keys
    /// volume up, volume down and mute (72, 73, 74).
    package static let neverRepeat: Set<UInt16> = Set(modifierKeys.keys).union([57, 63, 72, 73, 74])

    /// Whether a key repeats while held, by its Mac keycode.
    package static func repeats(virtualKey: UInt16) -> Bool { !neverRepeat.contains(virtualKey) }

    /// The key that repeats: the last key pressed that may, whose down was posted and whose up has not
    /// been.
    package struct Held: Equatable, Sendable {
        package var virtualKey: UInt16
        /// The device that pressed it, whose silence stops it.
        package var device: Device
        /// The flags its down carried, less the modifiers whose keys went up since.
        package var carried: UInt64
        package var timing: Timing
        /// When its down was posted (InputInjector's clock: seconds of system uptime).
        package var pressedAt: Double
        /// When its next repeat is due.
        package var due: Double
        /// While its device is quiet: when that device was last heard before it went quiet, so its next
        /// word starts the repeat over.
        package var quietSince: Double?
        /// Before the first repeat after its press (or after its device was quiet): its device must be heard
        /// after this time for that repeat to go out, the later of the press (or the device heard again) and
        /// `firstWord` before the repeat is due; nil once it went out.
        package var firstAfter: Double?
    }

    package private(set) var held: Held?

    package init() {}

    /// A keyboard event InputInjector posted (KeyStrokes': a device's key, a modifier's own, the ups it
    /// lets go of), with the device whose key it is and, for a down, the Mac's settings now (`timing`,
    /// nil: no repeat). A modifier's own key never starts or stops the repeat; its up takes its flag
    /// out of what the repeats carry (another key of the same modifier still down holds it again).
    /// Any other key's down replaces the repeat with its own (none for a key that never repeats, with
    /// no device or no timing); the repeating key's up stops it.
    package mutating func posted(virtualKey: UInt16, down: Bool, flags: UInt64, by device: Device?, at now: Double,
                                 timing: Timing?) {
        if let flag = Self.modifierKeys[virtualKey] {
            if !down { held?.carried &= ~flag }
            return
        }
        guard down else {
            if held?.virtualKey == virtualKey { held = nil }
            return
        }
        guard let device, let timing, Self.repeats(virtualKey: virtualKey) else { held = nil; return }
        held = Held(virtualKey: virtualKey, device: device, carried: flags, timing: timing, pressedAt: now,
                    due: now + timing.delay, quietSince: nil, firstAfter: now + max(0, timing.delay - Self.firstWord))
    }

    /// No key repeats any more: typed text or a trackpad gesture's shortcut went out (keys of their
    /// own), input has nowhere to land, or the host is going.
    package mutating func stop() { held = nil }

    /// Where a repeat would land now (the coordinator's, as its input handler judges a device's input):
    /// on the streamed source, held behind input waiting for an app's activation, or nowhere (nothing
    /// streams, or the source's rectangle cannot be read).
    package enum Landing: Equatable, Sendable { case lands, held, nowhere }

    /// What InputInjector does at a step.
    package enum Step: Equatable, Sendable {
        /// Posts the key's down again, the autorepeat flag set, with these flags; then steps again at `next`.
        case post(virtualKey: UInt16, flags: UInt64, next: Double)
        /// Posts nothing, and steps again at this time.
        case wait(until: Double)
        /// Nothing repeats: no more steps until a key is pressed.
        case idle
    }

    /// The step at `now`: `heard`, when the held key's device was last heard from (nil: not at all),
    /// `landing`, where a repeat would land, and `holding`, the flags the modifier keys down hold now
    /// (KeyStrokes.heldFlags). The repeats keep their cadence (each due an interval after the one
    /// before), but a late one goes out once, never a burst to catch up, and the next comes at least
    /// half an interval after it.
    package mutating func step(at now: Double, heard: Double?, landing: Landing, holding: UInt64) -> Step {
        guard var h = held else { return .idle }
        if landing == .nowhere { held = nil; return .idle }
        let look = now + min(h.timing.interval, Self.lookAgain)
        if let quiet = h.quietSince {
            // Its device went quiet: heard again, the repeat starts over after the delay.
            guard let heard, heard > quiet else { return .wait(until: look) }
            h.quietSince = nil
            h.due = now + h.timing.delay
            h.firstAfter = now + max(0, h.timing.delay - Self.firstWord)
            held = h
            return .wait(until: h.due)
        }
        if now < h.due { return .wait(until: h.due) }
        guard let heard, now - heard <= Self.silence else {
            h.quietSince = heard ?? -Double.greatestFiniteMagnitude
            held = h
            return .wait(until: look)
        }
        // The first repeat: only once the device is heard late enough to say the key is still down.
        if let after = h.firstAfter, heard <= after { return .wait(until: look) }
        if landing == .held { return .wait(until: look) }
        h.firstAfter = nil
        h.due = max(h.due + h.timing.interval, now + h.timing.interval / 2)
        held = h
        return .post(virtualKey: h.virtualKey, flags: h.carried | holding, next: h.due)
    }
}
