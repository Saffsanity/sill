import Foundation
import StreamProtocol

/// A locked Mac (docs/locked-mac-plan.md; Noah's finding of 2026-10-31): what the devices see and what
/// they may do while this Mac's screen is locked, or another user's session is on its console, or it has
/// no console session at all (SessionLock's reading). As Screen Sharing behaves: the lock screen and
/// nothing else until it is unlocked, and only the owner, a paired device, types at it.
///
/// - Shown while locked (`shown`, `list`): the Desktop alone streams, and it shows the lock screen (or
///   the login window, another user selected); the window list has no windows, says `locked` and no
///   `clipboard`; no thumbnail is taken, no icon and no installed app is sent; the menus have no app;
///   no sound is captured; the pasteboard is neither read nor written.
/// - A device's requests while locked (`decide`): a window picked, an app launched, a window's buttons
///   (kind 15), a menu fetched or chosen (kind 27 with an id, kind 25), a gesture (kind 28) and a
///   device's text for the clipboard are refused; input (kind 8) is taken from a paired session, and
///   from any other only the up of a key or a button it holds down on the Mac (`letGo`); everything
///   else as unlocked.
/// - The stream (`State`): a lock that begins while a window streams switches the stream to the
///   Desktop and remembers the window; while locked any select of a window becomes the Desktop (a
///   restart, a launched app's first window, a switch under way as the lock came), remembering it; the
///   unlock picks the remembered window again if it is still listed, the Desktop still streams and a
///   device is still connected. A pick made after the unlock, and the last device leaving, forget it.
/// - The lines: one at each change, and one per refusal kind a minute at most (the coordinator's
///   RefusalSummary, with `refusedLine`).
///
/// Unlocked, nothing is changed: the list is the one given, every request is taken.
/// Pure (Foundation and StreamProtocol's types), checked with swiftc (Tests/checks/lock-policy).
enum LockPolicy {
    /// How often the coordinator reads the lock while a device is connected (SessionLock: one session
    /// dictionary, and on a test host the TEST ONLY file). Sill.app's notifications come at once.
    static let pollInterval: Double = 1

    // MARK: A device's requests

    /// What a device asks, as the lock weighs it.
    enum Request: Equatable {
        /// Kind 6: a window, the Desktop or nothing.
        case pick(StreamSource)
        /// Kind 7.
        case launch
        /// Kind 15: a window's traffic lights.
        case windowCommand
        /// Kind 27 without an id: the menus' subscription.
        case menuSubscription
        /// Kind 27 with an id, and kind 25: a menu's items, a choice.
        case menuRequest
        /// Kind 28.
        case gesture
        /// Kind 32 with text: a device's Paste.
        case clipboardText
        /// Kind 32 without text: a subscription, or a stop.
        case clipboardSubscription
        /// Kind 8. `letsGo`: it is the up of a key or a button this device holds down on the Mac.
        case input(letsGo: Bool)
        /// Anything else: settings (17), the viewport (9), a keyframe (44), Pair This iPad… (21, whose ask
        /// answers "locked" by itself), pings, stats, the hello.
        case other
    }

    /// What the lock refuses, one line each a minute at most.
    enum Refusal: String, CaseIterable, Equatable {
        case pick, launch, windowCommand, menus, gesture, clipboard, input
    }

    enum Decision: Equatable {
        /// As unlocked.
        case take
        /// Only the up it is, where the pointer is: an unpaired device's key or button already down.
        case letGo
        case refuse(Refusal)
    }

    /// `paired`: the session's key is on the Mac's trust list now (the coordinator's `sessionPaired`).
    static func decide(_ request: Request, locked: Bool, paired: Bool) -> Decision {
        guard locked else { return .take }
        switch request {
        case .pick(.window): return .refuse(.pick)
        case .pick: return .take                       // the Desktop (the lock screen), or nothing
        case .launch: return .refuse(.launch)
        case .windowCommand: return .refuse(.windowCommand)
        case .menuRequest: return .refuse(.menus)
        case .gesture: return .refuse(.gesture)
        case .clipboardText: return .refuse(.clipboard)
        case .input(let letsGo): return paired ? .take : (letsGo ? .letGo : .refuse(.input))
        case .menuSubscription, .clipboardSubscription, .other: return .take
        }
    }

    // MARK: What the devices are shown

    /// What of this Mac reaches the devices besides the window list (`list`).
    struct Shown: Equatable {
        /// The catalog's thumbnails.
        var thumbnails: Bool
        /// The running apps' icons and the installed apps (the drawer's "All apps").
        var appsAndIcons: Bool
        /// An app's menus (kind 24's top level has an app).
        var menus: Bool
        /// The Mac's sound.
        var sound: Bool
        /// The pasteboard read and written for devices.
        var clipboard: Bool
    }

    static func shown(locked: Bool) -> Shown {
        Shown(thumbnails: !locked, appsAndIcons: !locked, menus: !locked, sound: !locked, clipboard: !locked)
    }

    /// The window list a device is sent: while locked no windows, no `clipboard` (a device sends no
    /// kind 32 then, and offers no Paste), and `locked` true; unlocked, `list` as it is, `locked` left
    /// out, so the bytes are what they were before this change.
    static func list(_ list: WindowList, locked: Bool) -> WindowList {
        guard locked else { return list }
        var l = list
        l.windows = []
        l.clipboard = nil
        l.locked = true
        return l
    }

    // MARK: The stream

    /// A reading that changed.
    enum Change: Equatable { case locked, unlocked }

    /// What `select` does with the source it was asked for.
    enum Select: Equatable {
        /// What was asked.
        case proceed
        /// The Desktop instead: it shows the lock screen.
        case desktop
        /// Nothing: the Desktop streams already.
        case stay
    }

    /// The coordinator's: the last reading, and the window to pick again at the unlock.
    struct State: Equatable {
        private(set) var locked = false
        /// The window that streamed when the lock began, or that a select while locked would have
        /// streamed; picked again at the unlock (`afterUnlock`).
        private(set) var comesBack: UInt32?

        init() {}

        /// A reading of the console: the change, nil for none.
        mutating func read(locked now: Bool) -> Change? {
            guard now != locked else { return nil }
            locked = now
            return now ? .locked : .unlocked
        }

        /// `select` was asked for `source` while `active` streams. `pick`: a pick (a device's, the
        /// command line's, a launched app's first window), not a restart. Locked, a window becomes the
        /// Desktop, and it is what comes back; unlocked, a pick forgets what would have come back.
        mutating func select(_ source: StreamSource, active: StreamSource, pick: Bool) -> Select {
            guard locked else {
                if pick { comesBack = nil }
                return .proceed
            }
            guard case .window(let id) = source else { return .proceed }
            comesBack = id
            return active == .desktop ? .stay : .desktop
        }

        /// After the unlock, once the catalog has been looked at: the window to pick again, once. Nil
        /// when none is remembered, it is no longer listed, something else than the Desktop streams, no
        /// device is connected, or the Mac is locked again.
        mutating func afterUnlock(listed: [UInt32], active: StreamSource, devices: Int) -> UInt32? {
            defer { if !locked { comesBack = nil } }
            guard !locked, let id = comesBack, listed.contains(id), active == .desktop, devices > 0 else { return nil }
            return id
        }

        /// The last device left: nothing comes back for the next one.
        mutating func devicesLeft() { comesBack = nil }
    }

    // MARK: The TEST ONLY hook

    /// SILL_TEST_LOCKED_FILE's contents, on a test host: "1" (and white space) says locked; anything
    /// else, or no file, says nothing, and the session's own witness decides.
    static func fileSaysLocked(_ contents: String?) -> Bool {
        contents?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    // MARK: The lines

    static let lockedLine = "Locked: this Mac's screen is locked; devices see the lock screen until it is unlocked."
    static let unlockedLine = "Unlocked: this Mac's screen is unlocked; devices see its windows again."

    /// The menus' note for a fetch or a choice refused while locked.
    static let menuNote = "The Mac is locked."

    /// One kind's refusals of the last minute (RefusalSummary: the first at once).
    static func refusedLine(_ kind: Refusal, count: Int) -> String {
        let n = max(1, count)
        let what: String
        switch kind {
        case .pick: what = n == 1 ? "a window pick" : "\(n) window picks"
        case .launch: what = n == 1 ? "an app launch" : "\(n) app launches"
        case .windowCommand: what = n == 1 ? "a window's button" : "\(n) presses of windows' buttons"
        case .menus: what = n == 1 ? "a menu request" : "\(n) menu requests"
        case .gesture: what = n == 1 ? "a gesture" : "\(n) gestures"
        case .clipboard:
            return "Locked: dropped " + (n == 1 ? "a device's clipboard text" : "\(n) clipboard texts from devices")
                + "; the clipboard waits for this Mac to be unlocked."
        case .input:
            return "Locked: dropped " + (n == 1 ? "an input event" : "\(n) input events") + " from unpaired devices"
                + "; only a paired device types at a locked Mac."
        }
        return "Locked: refused \(what); devices see only the lock screen until this Mac is unlocked."
    }
}
