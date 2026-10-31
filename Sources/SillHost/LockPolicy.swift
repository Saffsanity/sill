import Foundation
import os
import StreamProtocol

/// A locked Mac (docs/locked-mac-plan.md; Noah's finding of 2026-10-31, and his rule: "When the user is
/// locked, it should only show the lock screen, no virtual desktop, no desktop, no apps, nothing other
/// than the login screen."). What SessionLock's witnesses say of this Mac's console, how they make one
/// reading, and what each reading lets the devices see and do.
///
/// - Three readings (`Reading`): unlocked; this session's screen locked (on the console, the lock screen
///   up); off console (another user's session, the login window, or nobody on the console). An unknown
///   counts as locked: a witness not read yet, one that cannot be read, a read that does not answer
///   within its bound, a lock notification with no unlock yet (`reading`).
/// - The witnesses (`Witnesses`), any one saying locked wins: the console's user (SCDynamicStore), the
///   screen's lock state (notify(3)'s `com.apple.sessionagent.screenIsLocked`), the session dictionary
///   (CGSessionCopyCurrentDictionary, a bounded confirmation read off the main actor), and Sill.app's
///   notifications, which set a reading themselves (`noteNames`). TEST ONLY: a test host's file or
///   variable.
/// - The effective reading (`Reader`): a lock, and a change between the two locked readings, at once;
///   an unlock only once every witness has said unlocked for `settle` seconds and a session read made
///   since confirmed it, so this Mac's own lock a second after every return to the console never lets
///   the windows out for that second. The first reading with every witness read is taken as it is.
/// - What each reading allows (`allowed`): unlocked, everything; screen locked, a placeholder in place of
///   the picture (the display only with `lockScreenStreams`) and input from paired sessions alone (the
///   owner types the password); off console, nothing: no capture, no input, no display activity.
/// - The server's gate (`LockGate`, `withheld`): from the moment a witness says locked, no picture of the
///   Mac but the placeholder, no thumbnail, icon, app list, sound, clipboard, pointer or cursor shape
///   leaves this Mac, whatever the main actor is doing.
/// - A device's requests (`decide`), judged by the more restrictive of the reading at their arrival and
///   now (`restrictive`), so nothing sent while locked acts after the unlock.
/// - The stream (`Restore`): what streamed at the lock comes back after the unlock.
///
/// Unlocked, nothing is changed: the list is the one given, every request is taken, nothing is withheld.
/// Pure (Foundation, os and StreamProtocol's types), checked with swiftc (Tests/checks/lock-policy).
enum LockPolicy {
    // MARK: The readings

    /// What this Mac's console is, in the order of what each keeps from the devices.
    enum Reading: Int, CaseIterable, Comparable, Sendable {
        /// This user's session is on the console and its screen is unlocked.
        case unlocked = 0
        /// This user's session is on the console with its lock screen up.
        case screenLocked = 1
        /// Another user's session, the login window, or no session at all is on the console.
        case offConsole = 2

        static func < (a: Reading, b: Reading) -> Bool { a.rawValue < b.rawValue }
        var locked: Bool { self != .unlocked }
    }

    /// The more restrictive of two readings: a device's request is judged by the reading at its
    /// arrival and the reading now, so nothing sent while the Mac read locked acts after an unlock, and
    /// nothing that arrived unlocked acts after a lock.
    static func restrictive(_ a: Reading, _ b: Reading) -> Reading { max(a, b) }

    // MARK: The witnesses

    /// The console's user (`SCDynamicStoreCopyConsoleUser`, State:/Users/ConsoleUser): this process's
    /// user, another one (loginwindow, uid 0, during a fast user switch), nobody, or no answer.
    enum Console: Equatable, Sendable { case notRead, thisUser, otherUser, nobody, unreadable }

    /// `name` and `uid` as SCDynamicStoreCopyConsoleUser gives them (nil name: nobody), `readable`
    /// false when the dynamic store could not be asked at all. The top-level console user, never the
    /// per-session SessionInfo's kCGSSessionOnConsoleKey, which a fast user switch left at 1 for this
    /// session for a minute (the review, 2026-10-31).
    static func console(name: String?, uid: UInt32, ownUID: UInt32, readable: Bool) -> Console {
        guard readable else { return .unreadable }
        guard let name, !name.isEmpty else { return .nobody }
        // loginwindow is on the console between users (uid 0); any other uid is another user's session.
        return name != "loginwindow" && uid == ownUID ? .thisUser : .otherUser
    }

    /// The screen's lock state (notify(3)): loginwindow sets `screenStateName`'s state to 1 at a lock and
    /// to 0 at the unlock and when this session moves off the console (seen 2026-10-31).
    enum Screen: Equatable, Sendable { case notRead, locked, unlocked, unreadable }
    static let screenStateName = "com.apple.sessionagent.screenIsLocked"

    /// notify_register_dispatch's and notify_get_state's answers (0 is NOTIFY_STATUS_OK) and the state.
    static func screen(registered: UInt32, got: UInt32, state: UInt64) -> Screen {
        guard registered == 0, got == 0 else { return .unreadable }
        return state == 0 ? .unlocked : .locked
    }

    /// CGSessionCopyCurrentDictionary, read with a bound (`sessionBound`) off the main actor.
    enum Session: Equatable, Sendable { case notRead, unlocked, screenLocked, offConsole, noDictionary, unanswered }

    /// The dictionary's reading: none (no GUI session for this process) counts as locked; on the console
    /// only with `kCGSSessionOnConsoleKey` 1; locked with `CGSSessionScreenIsLocked` anything but false.
    static func session(_ d: [String: Any]?) -> Session {
        guard let d else { return .noDictionary }
        guard let onConsole = d["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.boolValue else { return .offConsole }
        if let locked = d["CGSSessionScreenIsLocked"] {
            guard let n = locked as? NSNumber, !n.boolValue else { return .screenLocked }
        }
        return .unlocked
    }

    /// A notification Sill.app hears (`noteNames`), or the TEST ONLY hook's stand-in for one.
    enum Note: Equatable, Sendable { case screenLocked, screenUnlocked, offConsole, onConsole }

    /// The distributed notifications loginwindow posts (registered with `.deliverImmediately`, so none
    /// waits while Sill.app is not active) and NSWorkspace's session notifications, by name.
    static let distributedNames = ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked",
                                   "com.apple.sessionDidMoveOffConsole", "com.apple.sessionDidMoveOnConsole"]
    static let workspaceNames = ["NSWorkspaceSessionDidResignActiveNotification", "NSWorkspaceSessionDidBecomeActiveNotification"]
    static let noteNames: [String: Note] = [
        "com.apple.screenIsLocked": .screenLocked,
        "com.apple.screenIsUnlocked": .screenUnlocked,
        "com.apple.sessionDidMoveOffConsole": .offConsole,
        "com.apple.sessionDidMoveOnConsole": .onConsole,
        "NSWorkspaceSessionDidResignActiveNotification": .offConsole,
        "NSWorkspaceSessionDidBecomeActiveNotification": .onConsole,
    ]

    /// Every witness SessionLock has, as last read.
    struct Witnesses: Equatable, Sendable {
        var console: Console = .notRead
        var screen: Screen = .notRead
        var session: Session = .notRead
        /// `.screenLocked` while a lock notification has had no unlock (nor an unlock seen by `screen`).
        var screenNote: Note?
        /// `.offConsole` while a switch away has had no switch back (nor a return seen by `console`).
        var consoleNote: Note?
        /// TEST ONLY: what a test host's SILL_TEST_LOCKED or SILL_TEST_LOCKED_FILE says, nil for nothing.
        var test: Reading?

        init() {}
    }

    /// The witnesses' reading: off console when any console witness says so or the console's user is
    /// unknown; else locked when any screen witness says so or one is unknown; else unlocked. A test
    /// host's file or variable adds its reading, the more restrictive one winning.
    static func reading(_ w: Witnesses) -> Reading {
        var r = w.test ?? .unlocked
        if w.console != .thisUser { r = max(r, .offConsole) }
        if w.consoleNote == .offConsole { r = max(r, .offConsole) }
        switch w.session {
        case .unlocked: break
        case .offConsole: r = max(r, .offConsole)
        case .notRead, .screenLocked, .noDictionary, .unanswered: r = max(r, .screenLocked)
        }
        if w.screen != .unlocked { r = max(r, .screenLocked) }
        if w.screenNote == .screenLocked { r = max(r, .screenLocked) }
        return r
    }

    /// Whether a session read could change the reading now: every other witness says unlocked, so the
    /// dictionary is what confirms it.
    static func wantsSessionRead(_ w: Witnesses) -> Bool {
        var others = w
        others.session = .unlocked
        return reading(others) == .unlocked
    }

    /// Whether SessionLock reads the session dictionary at a look (one read at a time): before it was
    /// ever read, whatever the others say, so a host that starts while the Mac reads locked has its first
    /// reading at once (and the settle for its unlock); after that only to confirm an unlock.
    static func readsSession(_ w: Witnesses) -> Bool {
        w.session == .notRead || wantsSessionRead(w)
    }

    // MARK: The effective reading

    /// A change of the effective reading. `from` nil: the first reading with every witness read.
    struct Change: Equatable, Sendable {
        let from: Reading?
        let to: Reading
    }

    /// SessionLock's: the witnesses, and the reading the gate and the coordinator go by.
    struct Reader: Equatable, Sendable {
        private(set) var witnesses = Witnesses()
        /// Nil until the first look with every witness read: counts as off console (`gate`).
        private(set) var effective: Reading?
        /// Every witness has said unlocked since then, while `effective` is a locked reading.
        private(set) var unlockedSince: Double?
        /// When the newest session read that answered was started.
        private(set) var sessionReadAt: Double?

        /// How long every witness must say unlocked, with a session read made meanwhile confirming it,
        /// before a locked Mac counts as unlocked: this Mac locks itself 1 to 1.6 s after each return
        /// to the console (loginwindow, 2026-10-28, 29 and 31).
        static let settle: Double = 2

        init() {}

        /// What the gate reads: unknown counts as off console.
        var gate: Reading { effective ?? .offConsole }
        var established: Bool { effective != nil }
        /// When a look would end the settle (SessionLock looks then, after a session read).
        var settleEndsAt: Double? { unlockedSince.map { $0 + Self.settle } }

        /// The console's user as just read. Back to this user after another or nobody: the switch back
        /// is seen, so a switch-away notification whose switch-back was lost no longer counts.
        mutating func console(_ c: Console) {
            if c == .thisUser, witnesses.console == .otherUser || witnesses.console == .nobody { witnesses.consoleNote = nil }
            witnesses.console = c
        }

        /// The screen's lock state as just read. Unlocked after locked: the unlock is seen, so a lock
        /// notification whose unlock was lost no longer counts.
        mutating func screen(_ s: Screen) {
            if s == .unlocked, witnesses.screen == .locked { witnesses.screenNote = nil }
            witnesses.screen = s
        }

        /// A session read's answer, or `.unanswered` when its bound passed first; `startedAt`: when it
        /// was started (a read's own time, which the settle's confirmation needs).
        mutating func session(_ s: Session, startedAt: Double) {
            witnesses.session = s
            if s != .unanswered, s != .notRead { sessionReadAt = max(sessionReadAt ?? startedAt, startedAt) }
        }

        /// A notification: a lock or a switch away holds the reading locked from the look that follows (in
        /// SessionLock's handler, under the same lock, so the gate has it before any other work); an unlock
        /// or a switch back only takes that back, and never unlocks by itself.
        mutating func note(_ n: Note) {
            switch n {
            case .screenLocked: witnesses.screenNote = .screenLocked
            case .screenUnlocked: witnesses.screenNote = nil
            case .offConsole: witnesses.consoleNote = .offConsole
            case .onConsole: witnesses.consoleNote = nil
            }
        }

        mutating func test(_ r: Reading?) { witnesses.test = r }

        /// The witnesses as they are at `now`: the effective reading's change, if any. A lock, and a
        /// change between the locked readings, at once; an unlock once the settle is over and a session
        /// read started since it began answered.
        mutating func look(at now: Double) -> Change? {
            let raw = LockPolicy.reading(witnesses)
            guard let current = effective else {
                let ready = witnesses.console != .notRead && witnesses.screen != .notRead && witnesses.session != .notRead
                guard ready else { return nil }
                effective = raw
                unlockedSince = nil
                return Change(from: nil, to: raw)
            }
            guard raw == .unlocked else {
                unlockedSince = nil
                guard raw != current else { return nil }
                effective = raw
                return Change(from: current, to: raw)
            }
            guard current != .unlocked else { unlockedSince = nil; return nil }
            let since = unlockedSince ?? now
            unlockedSince = since
            guard now - since >= Self.settle, let read = sessionReadAt, read >= since else { return nil }
            unlockedSince = nil
            effective = .unlocked
            return Change(from: current, to: .unlocked)
        }
    }

    // MARK: When SessionLock reads

    /// How often the witnesses are read while a device is connected (the event-driven ones change it at
    /// once; this catches the session dictionary and the TEST ONLY file).
    static let pollInterval: Double = 1
    static func polls(devices: Int) -> Bool { devices > 0 }
    /// How long a session read may take before it counts as unanswered (locked): the review measured
    /// a median of 0.21 ms, a p99 of 4 ms and a maximum of 12 ms.
    static let sessionBound: Double = 0.5

    // MARK: What each reading allows

    /// Whether the Desktop's display streams while this session's screen is locked (it would show the
    /// lock screen), instead of the placeholder. Off until a test on a Mac shows that a capture of a
    /// locked display is the lock screen and nothing else (docs/locked-mac-plan.md, open question 1).
    static let lockScreenStreams = false

    /// Who types at the Mac.
    enum Input: Equatable, Sendable {
        case everyone
        /// Only a paired session: the owner types the password at the lock screen.
        case paired
        case nobody
    }

    struct Allowed: Equatable, Sendable {
        /// The Desktop's display (or the test pattern) streams; else the placeholder, a black frame.
        var display: Bool
        /// Windows: listed, picked, captured, staged, sized, their thumbnails, buttons and menus.
        var windows: Bool
        var appsAndIcons: Bool
        var launches: Bool
        var sound: Bool
        var clipboard: Bool
        /// The Mac's pointer (kind 26) and its cursor shape (kind 14), and reading either.
        var pointer: Bool
        var gestures: Bool
        /// Sill's virtual display may be made.
        var virtualDisplay: Bool
        var input: Input
        /// A device's session connecting declares user activity (it wakes the display).
        var wakeOnConnect: Bool
        /// A person's activity a device sends, once taken, declares it.
        var wakeOnActivity: Bool
    }

    static func allowed(_ r: Reading) -> Allowed {
        switch r {
        case .unlocked:
            return Allowed(display: true, windows: true, appsAndIcons: true, launches: true, sound: true, clipboard: true,
                           pointer: true, gestures: true, virtualDisplay: true, input: .everyone,
                           wakeOnConnect: true, wakeOnActivity: true)
        case .screenLocked:
            return Allowed(display: lockScreenStreams, windows: false, appsAndIcons: false, launches: false, sound: false,
                           clipboard: false, pointer: false, gestures: false, virtualDisplay: false, input: .paired,
                           wakeOnConnect: lockScreenStreams, wakeOnActivity: true)
        case .offConsole:
            return Allowed(display: false, windows: false, appsAndIcons: false, launches: false, sound: false, clipboard: false,
                           pointer: false, gestures: false, virtualDisplay: false, input: .nobody,
                           wakeOnConnect: false, wakeOnActivity: false)
        }
    }

    /// Whether a session's input lands (whole, downs too) at `r`. `paired`: its key is on the trust
    /// list now (the coordinator's `sessionPaired`).
    static func takesInput(_ r: Reading, paired: Bool) -> Bool {
        switch allowed(r).input {
        case .everyone: return true
        case .paired: return paired
        case .nobody: return false
        }
    }

    // MARK: The server's gate

    /// What a frame (kinds 0 and 1) shows: the placeholder, the Desktop's display (or the test
    /// pattern), or a window.
    enum Picture: Equatable, Sendable { case placeholder, display, window }

    /// What the server drops at `r`: every picture of the Mac but the placeholder (the display too,
    /// unless it streams at a locked screen), its thumbnails, icons and installed apps, its sound, its
    /// clipboard, its pointer and cursor shape. The window list, settings, the Mac's identity, the
    /// menus' answers (none has items while locked), pongs and ticks go as ever.
    static func withheld(_ kind: StreamMessageKind, picture: Picture?, reading r: Reading) -> Bool {
        guard r.locked else { return false }
        switch kind {
        case .frame, .parameterSets:
            switch picture ?? .window {
            case .placeholder: return false
            case .display: return !allowed(r).display
            case .window: return true
            }
        case .thumbnail, .appIcon, .appList, .audio, .clipboard, .cursorShape, .macPointer:
            return true
        default:
            return false
        }
    }

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
        /// Anything else: settings (17), the viewport (9), a keyframe (44), Pair This iPad… (21, whose
        /// ask answers "locked" by itself), pings, stats, the hello.
        case other
    }

    /// What the lock refuses, one line each a minute at most.
    enum Refusal: String, CaseIterable, Equatable {
        case pick, launch, windowCommand, menus, gesture, clipboard, input
    }

    enum Decision: Equatable {
        case take
        /// Only the up it is, where the pointer is: a key or a button already down on the Mac.
        case letGo
        case refuse(Refusal)
    }

    /// `paired`: the session's key is on the Mac's trust list now. Locked, a pick of the Desktop (the
    /// placeholder, which a device asks for by itself) or of nothing is taken; input from whom the
    /// reading lets type; the subscriptions and the rest; nothing else.
    static func decide(_ request: Request, reading r: Reading, paired: Bool) -> Decision {
        guard r.locked else { return .take }
        switch request {
        case .pick(.window): return .refuse(.pick)
        case .pick: return .take
        case .launch: return .refuse(.launch)
        case .windowCommand: return .refuse(.windowCommand)
        case .menuRequest: return .refuse(.menus)
        case .gesture: return .refuse(.gesture)
        case .clipboardText: return .refuse(.clipboard)
        case .input(let letsGo): return takesInput(r, paired: paired) ? .take : (letsGo ? .letGo : .refuse(.input))
        case .menuSubscription, .clipboardSubscription, .other: return .take
        }
    }

    // MARK: What the devices are shown

    /// The window list a device is sent: locked, no windows, no `clipboard` (a device sends no kind 32
    /// then, and offers no Paste), `locked` true and, off console, `offConsole` true; unlocked, `list`
    /// as it is, both left out, so the bytes are what they were before this change.
    static func list(_ list: WindowList, reading r: Reading) -> WindowList {
        guard r.locked else { return list }
        var l = list
        l.windows = []
        l.clipboard = nil
        l.locked = true
        l.offConsole = r == .offConsole ? true : nil
        return l
    }

    /// The placeholder's size in pixels: the display's own size in points (its shape, so a paired
    /// device's taps land where they would on it), even, at least 64 on a side; 1280×800 without a
    /// display (a test host's).
    static func placeholderSize(display: (width: Int, height: Int)?) -> (width: Int, height: Int) {
        guard let d = display, d.width > 0, d.height > 0 else { return (1280, 800) }
        return (max(64, d.width & ~1), max(64, d.height & ~1))
    }

    // MARK: The stream

    /// What streams, as `reconciles` weighs it.
    enum Streams: Equatable, Sendable { case nothing, placeholder, display, window }

    /// Whether the coordinator acts at `r` although the reading it last acted on is `r` too: its changes
    /// coalesce (a lock and an unlock, or an unlock and a lock, both before it ran), and a select that
    /// finished in between started what `r` does not allow (a window or the display while locked; the
    /// placeholder while unlocked), or a locked list went out meanwhile.
    static func reconciles(_ r: Reading, streams: Streams, lockedListSent: Bool) -> Bool {
        if r.locked {
            switch streams {
            case .window: return true
            case .display: return !allowed(r).display
            case .nothing, .placeholder: return false
            }
        }
        return streams == .placeholder || lockedListSent
    }

    /// What `select` does with the source it was asked for.
    enum Select: Equatable {
        /// What was asked (the Desktop streams the placeholder while locked).
        case proceed
        /// The Desktop instead: a window asked for while locked.
        case desktop
        /// Nothing: the Desktop streams already.
        case stay
    }

    /// The coordinator's: the window to pick again after the unlock.
    struct Restore: Equatable {
        /// The window that streamed when the lock began, or that a select while locked would have
        /// streamed (a restart, a launched app's first window, a switch under way).
        private(set) var comesBack: UInt32?

        init() {}

        /// The lock began with `active` streaming: a window is what comes back.
        mutating func lockBegan(active: StreamSource) {
            if case .window(let id) = active { comesBack = id }
        }

        /// `select` was asked for `source` while `active` streams, at `r`. `pick`: a pick (a device's,
        /// the command line's, a launched app's first window), not a restart. Locked, a window becomes the
        /// Desktop and is what comes back; unlocked, a pick forgets what would have come back.
        mutating func select(_ source: StreamSource, active: StreamSource, pick: Bool, reading r: Reading) -> Select {
            guard r.locked else {
                if pick { comesBack = nil }
                return .proceed
            }
            guard case .window(let id) = source else { return .proceed }
            comesBack = id
            return active == .desktop ? .stay : .desktop
        }

        /// After the unlock, the catalog looked at again: what to stream instead of the placeholder,
        /// once. The remembered window if it is still listed, else the Desktop; nil when the placeholder
        /// no longer streams (something was picked since), no device is connected, or the Mac reads
        /// locked again (then what comes back is kept for the next unlock).
        mutating func afterUnlock(listed: [UInt32], active: StreamSource, placeholder: Bool, devices: Int, reading r: Reading) -> StreamSource? {
            guard !r.locked else { return nil }
            defer { comesBack = nil }
            guard devices > 0, placeholder, active == .desktop else { return nil }
            if let id = comesBack, listed.contains(id) { return .window(id) }
            return .desktop
        }

        /// The last device left: nothing comes back for the next one.
        mutating func devicesLeft() { comesBack = nil }
    }

    // MARK: The TEST ONLY hooks

    /// SILL_TEST_LOCKED_FILE's contents on a test host: "1" says this session's screen is locked, "2"
    /// that it is off console (white space around either); anything else, or no file, says nothing.
    static func fileReading(_ contents: String?) -> Reading? {
        switch contents?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1": return .screenLocked
        case "2": return .offConsole
        default: return nil
        }
    }

    /// SILL_TEST_LOCK_NOTIFY: a notify(3) name of the test's own for the screen's lock state, read in
    /// place of `screenStateName` so a test sets it (notify_set_state, notify_post); only a name under
    /// this prefix, never one another process listens to.
    static let testNotifyPrefix = "me.saffer.sill.test."
    static func testNotifyName(_ raw: String?) -> String? {
        guard let raw, raw.hasPrefix(testNotifyPrefix), raw.count > testNotifyPrefix.count, raw.count <= 128 else { return nil }
        return raw
    }

    /// SILL_TEST_LOCK_NOTE: "<s> <name>[; <s> <name>]", each name delivered to SessionLock's handler s
    /// seconds after it starts, as that notification would be (nothing is posted). A name is one of
    /// `noteNames`' or its short form ("screenIsLocked", "sessionDidResignActive"). Nil when any part
    /// does not parse.
    static func testNotes(_ raw: String?) -> [(at: Double, name: String)]? {
        guard let raw else { return nil }
        var out: [(Double, String)] = []
        for part in raw.split(separator: ";") {
            let words = part.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count == 2, let at = Double(words[0]), at >= 0, at.isFinite, let name = noteName(String(words[1])) else { return nil }
            out.append((at, name))
        }
        return out.isEmpty ? nil : out
    }

    /// A notification's full name from its own or its short form.
    static func noteName(_ s: String) -> String? { noteNames[s] != nil ? s : shortNoteNames[s] }
    static let shortNoteNames: [String: String] = [
        "screenIsLocked": "com.apple.screenIsLocked", "screenIsUnlocked": "com.apple.screenIsUnlocked",
        "sessionDidMoveOffConsole": "com.apple.sessionDidMoveOffConsole", "sessionDidMoveOnConsole": "com.apple.sessionDidMoveOnConsole",
        "sessionDidResignActive": "NSWorkspaceSessionDidResignActiveNotification",
        "sessionDidBecomeActive": "NSWorkspaceSessionDidBecomeActiveNotification",
    ]

    // MARK: The lines

    /// The line for a change of the effective reading; none for the first reading when it is unlocked
    /// (a host that starts on an unlocked Mac says nothing new).
    static func line(_ c: Change) -> String? {
        switch c.to {
        case .unlocked:
            return c.from == nil ? nil : unlockedLine
        case .screenLocked:
            return "Locked: this Mac's screen is locked; devices see none of it until it is unlocked, and only a paired device types at it."
        case .offConsole:
            return "Locked: another user, or the login window, is on this Mac's screen; devices see none of this session, and nothing they send is posted, until it is back."
        }
    }

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
            return "Locked: dropped " + (n == 1 ? "an input event" : "\(n) input events")
                + "; only a paired device types at a locked Mac, and no device at one switched to another user."
        }
        return "Locked: refused \(what); devices see none of this Mac until it is unlocked."
    }

    /// TEST ONLY (SILL_TEST_LOCK_LOG): one reading with its witnesses.
    static func testLogLine(_ w: Witnesses, raw: Reading, gate: Reading, established: Bool, cause: String) -> String {
        func name(_ r: Reading) -> String { r == .unlocked ? "unlocked" : r == .screenLocked ? "screen locked" : "off console" }
        let notes = [w.screenNote.map { _ in "screen locked" }, w.consoleNote.map { _ in "off console" }].compactMap { $0 }
        return "Test lock: \(cause): reads \(name(raw)), gate \(established ? name(gate) : "unknown (off console)")"
            + " (console \(w.console), screen \(w.screen), session \(w.session), notes \(notes.isEmpty ? "none" : notes.joined(separator: " and "))"
            + (w.test.map { ", test hook \(name($0))" } ?? "") + ")"
    }
}

/// The reading the server, the doors and the coordinator go by, set the moment SessionLock's witnesses
/// change it (LockPolicy.Reader) and read on any queue: the network queue drops what `withholds` says
/// from that moment, whatever the main actor is doing. A gate made unestablished reads off console
/// until its first reading (SessionLock's); the server's own default never locks (its harnesses).
final class LockGate: @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(reading: LockPolicy.Reading, established: Bool)>

    init(_ reading: LockPolicy.Reading = .unlocked, established: Bool = true) {
        state = OSAllocatedUnfairLock(initialState: (reading, established))
    }

    var reading: LockPolicy.Reading { state.withLock { $0.reading } }
    var established: Bool { state.withLock { $0.established } }
    var locked: Bool { reading.locked }

    func set(_ reading: LockPolicy.Reading) { state.withLock { $0 = (reading, true) } }

    /// The server's rule (LockPolicy.withheld) at the reading now.
    func withholds(_ kind: StreamMessageKind, picture: LockPolicy.Picture? = nil) -> Bool {
        LockPolicy.withheld(kind, picture: picture, reading: reading)
    }
}
