import Foundation
import StreamProtocol

/// When the host tells macOS that someone is using the Mac on a device's behalf (issue #134): a Mac
/// whose display is asleep gives the stream black frames until someone wakes the display, so the host
/// declares user activity, what a key press on the Mac does, and DisplayActivity makes the call. The
/// display powers on if it was asleep, and it sleeps again by the Mac's own display-sleep setting,
/// counted from the last declaration, as after the last key press: nothing is held.
///
/// What counts is a person at the device, never the device's own requests (`activity`):
/// - A device's session connecting declares at once, every connection: the wake.
/// - What a person does to the Mac from the device declares when the last declaration is `interval`
///   or more ago: an app opened (kind 7), input (kind 8), a window's button (15), a menu item chosen
///   (25), a trackpad gesture (28). So a stream of input declares at most once every 5 s and keeps
///   the display on as local input would, while a device that sends nothing lets it sleep.
/// - Never a pick (kind 6): the device asks for the Desktop by itself (on a connection's first list,
///   when the Mac stopped the Desktop it streamed, when the watched window closed) and picks again
///   what it watched after a move, with nobody at it; a person's pick is followed by their input.
///   Never the viewport (9), a settings change (17), "show your pairing code" (21), a menu fetched
///   (27), the clipboard (32), a keyframe request (44), input that does not decode, nor any other kind.
/// - Never a bare pointer move within `recentre` after the host's own stream restart or new frame
///   size (`streamChanged`): the device moves its own pointer to the new frame's middle by itself
///   (StreamClient.pointerFrameChanged), with nobody at it.
/// - A left or right press on a display that reads asleep is held back (`pass`, PR #228), and so is
///   its release: the pointer moves there instead, and the press declares at once whatever the
///   interval (`Event.wakingPress`). A tap on a black picture then clicks nothing out of sight; it
///   only wakes the display, as the PR has a click on a sleeping display at the Mac do.
/// - A test host (`--synthetic`: it does not advertise, as `InputInjector.dryRun`) declares nothing:
///   it counts what it would declare (`dryKey` in the stats line), and the Mac's display is never
///   touched.
///
/// One rule for every device: there is one display. The clock is the caller's; one that goes back
/// counts as time passed, so a clock set back never holds a declaration off, and ends the window
/// after a restart. A value type on the main actor (StreamCoordinator); `Report` is DisplayActivity's,
/// on its queue. Pure: Foundation and StreamProtocol's types only, checked with swiftc
/// (Tests/checks/display-wake).
struct DisplayWake {
    /// What the rule hears of a device.
    enum Event: Equatable {
        /// A device's session connected: the coordinator's client-connected path, once per connection.
        case connect
        /// A message from a device's session, every one that reaches the coordinator, with its input
        /// event when it is kind 8 and decodes (nil otherwise).
        case message(StreamMessageKind, InputEvent?)
        /// A device's left or right press that `pass` held back because the display it lands on read
        /// asleep: it declares at once, as a connect does, whatever the interval.
        case wakingPress
    }

    /// A person's activity at the device, which a declaration is made for (and its line says).
    enum Activity: CaseIterable, Equatable {
        case connect
        /// Kind 7: an app opened from the device's Apps list (its first window is then picked for it).
        case launch
        /// Kind 8: a touch, a key, text, a scroll, a pointer move.
        case input
        /// Kind 15: a window's close, minimize or full-screen button, from the bar's long press.
        case windowButton
        /// Kind 25: one of the Mac's menu items chosen.
        case menuItem
        /// Kind 28: a three- or four-finger trackpad gesture.
        case gesture
        /// A press held back on a display that read asleep (`pass`): it only wakes the display.
        case wakingPress
    }

    enum Decision: Equatable {
        /// Not a person's activity, or too soon after the last declaration: the display is already
        /// counted as in use.
        case nothing
        /// Declare user activity (DisplayActivity), for this.
        case declare(Activity)
        /// A test host: count `dryKey` and declare nothing.
        case count
    }

    /// How often a stream of a person's activity declares at most. The display sleeps a minute or more
    /// after the last declaration (macOS's shortest display-sleep setting), so 5 s keeps it on through
    /// any input, and a display put to sleep at the Mac while a device works wakes at the device's
    /// input within 5 s.
    static let interval: TimeInterval = 5

    /// How long after the host's own stream restart or new frame size a bare pointer move is taken
    /// for the device's own: it moves its pointer to the middle of a new frame as the new parameter
    /// sets arrive (a round trip after they go out), and a person's next move after it counts again.
    static let recentre: TimeInterval = 2

    /// The name `pmset -g assertions` shows beside the UserIsActive assertion (IOPMLib.h: at most 128
    /// characters).
    static let assertionName = "Sill: a device is using this Mac"

    /// The stats line's keys, each only in a second it happened: a declaration made, a test host's
    /// that was not, and a press held back on a display that read asleep (`pass`, on any host).
    static let declaredKey = "disp.wake"
    static let dryKey = "disp.wakeDry"
    static let heldKey = "disp.heldPress"

    /// `--synthetic`: count, never declare.
    let testHost: Bool
    /// When the last declaration (or a test host's count) was made; nil before the first.
    private(set) var lastDeclared: TimeInterval?
    /// When the host last restarted its stream or sent a new frame size (`streamChanged`); nil before.
    private(set) var streamChangedAt: TimeInterval?

    init(testHost: Bool) { self.testHost = testHost }

    /// The host restarted its stream or sent a new frame size: the coordinator calls it when a new
    /// stream's first parameter sets go out, and when parameter sets that differ from the last ones
    /// do (a device moves its own pointer to the new frame's middle as they arrive).
    mutating func streamChanged(at now: TimeInterval) { streamChangedAt = now }

    /// Whose `event` at `now` is: a person's activity, or nil for the device's own requests and for
    /// what does not act on the Mac. The kinds are the whole rule; the coordinator only forwards.
    func activity(_ event: Event, at now: TimeInterval) -> Activity? {
        switch event {
        case .connect:
            return .connect
        case .wakingPress:
            return .wakingPress
        case .message(let kind, let input):
            switch kind {
            case .launchApp: return .launch
            case .input:
                guard let input else { return nil }      // it does not decode: it acts on nothing
                if case .pointer(.move, _, _) = input, let changed = streamChangedAt, now >= changed,
                   now - changed < Self.recentre {
                    return nil                           // the device's own move to the new frame's middle
                }
                return .input
            case .windowCommand: return .windowButton
            case .pressMenuItem: return .menuItem
            case .gesture: return .gesture
            default: return nil                          // a pick (6), the viewport (9), settings (17), …
            }
        }
    }

    /// What `event` at `now` does. A declaration (or count) restarts the interval; nothing does not.
    mutating func decide(_ event: Event, at now: TimeInterval) -> Decision {
        guard let activity = activity(event, at: now) else { return .nothing }
        if activity != .connect, activity != .wakingPress, let last = lastDeclared, now >= last, now - last < Self.interval {
            return .nothing
        }
        lastDeclared = now
        return testHost ? .count : .declare(activity)
    }

    // MARK: - The waking click (PR #228)

    /// How long presses on a display that keeps reading asleep are held back, from the first of them:
    /// past it the display is taken for one a press does not wake, or one whose picture is live while
    /// macOS reads it asleep, and its presses go on to the Mac as they did before. A gap this long
    /// between presses starts afresh (the display may have woken and slept again since).
    static let wakeGrace: TimeInterval = 5

    /// A device's mouse button.
    enum Button: Hashable { case left, right }

    /// What `pass` makes of an input event.
    struct Passed: Equatable {
        /// What goes on to the Mac: the event as it came, a held-back press's pointer move, or nil.
        let event: InputEvent?
        /// A press held back on a display that read asleep: it wakes the display (`Event.wakingPress`).
        let waking: Bool
    }

    /// Each device's presses held back whose releases have not come (the coordinator's device key).
    private(set) var heldBack: [ObjectIdentifier: Set<Button>] = [:]
    /// The presses on a display that kept reading asleep, the first and the latest (held back, or
    /// past `wakeGrace` gone on); nil once a press read it awake.
    private(set) var asleepPresses: (first: TimeInterval, last: TimeInterval)?

    /// A device's input event on its way to the Mac. A left or right press on a display that reads
    /// asleep (`asleep`, asked only for a press: the display the press lands on) is held back: the
    /// pointer moves there instead and the press wakes the display (`waking`), so nothing is clicked
    /// where nobody can see. Its release is held
    /// back too, whenever it comes and whatever the display reads by then, and the moves between them
    /// are plain moves (the Mac has no button down). A press on a display that reads awake goes on,
    /// and so does a release whose press went on. Each device's own, so another device's release is
    /// never taken for this one's. While the display keeps reading asleep, presses are held back for
    /// `wakeGrace` from the first, and then go on; a press `wakeGrace` or more after the last press
    /// on it starts afresh, and so does a clock set back. Keys, text, scrolls and moves go on as
    /// they are, and `asleep` is not asked for them.
    mutating func pass(_ event: InputEvent, from device: ObjectIdentifier, at now: TimeInterval,
                       asleep: () -> Bool) -> Passed {
        guard case .pointer(let action, let x, let y) = event, action != .move else { return Passed(event: event, waking: false) }
        let button: Button = action == .leftDown || action == .leftUp ? .left : .right
        if action == .leftUp || action == .rightUp {
            guard heldBack[device]?.contains(button) == true else { return Passed(event: event, waking: false) }
            letGo(button, of: device)
            return Passed(event: nil, waking: false)
        }
        if asleep() {
            var run = asleepPresses ?? (now, now)
            if now < run.last || now - run.last >= Self.wakeGrace { run = (now, now) }    // afresh
            run.last = now
            asleepPresses = run
            if now - run.first < Self.wakeGrace {
                heldBack[device, default: []].insert(button)
                return Passed(event: .pointer(.move, x: x, y: y), waking: true)
            }
        } else {
            asleepPresses = nil
        }
        letGo(button, of: device)            // this press goes on: one of that button held back before is over
        return Passed(event: event, waking: false)
    }

    /// A device left: its presses held back are forgotten.
    mutating func forget(_ device: ObjectIdentifier) { heldBack[device] = nil }

    private mutating func letGo(_ button: Button, of device: ObjectIdentifier) {
        heldBack[device]?.remove(button)
        if heldBack[device]?.isEmpty == true { heldBack[device] = nil }
    }

    // MARK: - What DisplayActivity says

    /// How long after a declaration the main display is read again: asleep before and on by then is a
    /// wake, worth its line.
    static let secondLook: TimeInterval = 0.5
    /// A declaration that woke nothing says so at most once in this long.
    static let declaredLineInterval: TimeInterval = 60

    /// What the activity was, in a line's words.
    static func why(_ activity: Activity) -> String {
        switch activity {
        case .connect: return "connected"
        case .launch: return "opened an app"
        case .input: return "sent input"
        case .windowButton: return "pressed a window’s button"
        case .menuItem: return "chose a menu item"
        case .gesture: return "made a trackpad gesture"
        case .wakingPress: return "clicked while the display was asleep; the click was held back"
        }
    }

    /// The display read asleep just before a declaration and on `secondLook` later: "Woke the display
    /// for iPad (iPad14,1), which connected." The device's name as the Mac's card has it (cleaned),
    /// else its address.
    static func wokeLine(device: String, activity: Activity) -> String {
        "Woke the display for \(device), which \(why(activity))."
    }

    /// Any other declaration that went through, at most once a minute: the display was on already, or
    /// woken for a declaration made before this one (whose line it is), or it read asleep `secondLook`
    /// later (a closed lid, a display slow to wake).
    static func declaredLine(device: String, activity: Activity, asleepNow: Bool) -> String {
        "Declared activity for \(device), which \(why(activity))"
            + (asleepNow ? ", but the display read asleep \(secondLook) s later." : ".")
    }

    /// IOKit refused a declaration (it needs no privilege, so this should never show).
    static func failedLine(_ result: Int32) -> String {
        "Could not wake the display: macOS refused to declare user activity (IOKit error 0x"
            + String(UInt32(bitPattern: result), radix: 16)
            + "). A sleeping display stays dark until someone wakes it at the Mac."
    }

    /// kIOReturnSuccess (KERN_SUCCESS), without importing IOKit here.
    static let success: Int32 = 0

    /// What DisplayActivity says about its declarations, all on its queue: for one that went through, a
    /// second look `secondLook` later says "Woke the display …" when the display read asleep before
    /// and on then, once for one wake (two declarations made before the panel came on share it), else
    /// "Declared activity …" at most once a minute (a woke line counts as that minute's line); a
    /// refusal's line the first time, and again only after a declaration has gone through since.
    struct Report {
        /// A declaration that went through, until its second look.
        struct Look: Equatable {
            let device: String
            let activity: Activity
            let wasAsleep: Bool
            /// How many woke lines had been said when it was made: a wake said since is not its own.
            let wakesBefore: Int
        }

        private(set) var saidFailure = false
        private(set) var wakesSaid = 0
        /// When the last woke or declared line was said; nil before the first.
        private(set) var lastLineAt: TimeInterval?

        /// Right after the call: the refusal's line (or nothing), and for a declaration that went
        /// through, the look to take `secondLook` later.
        mutating func declared(device: String, activity: Activity, wasAsleep: Bool, result: Int32) -> (line: String?, look: Look?) {
            guard result == DisplayWake.success else {
                if saidFailure { return (nil, nil) }
                saidFailure = true
                return (DisplayWake.failedLine(result), nil)
            }
            saidFailure = false
            return (nil, Look(device: device, activity: activity, wasAsleep: wasAsleep, wakesBefore: wakesSaid))
        }

        /// The second look: whether the main display reads asleep now, at `now`.
        mutating func looked(_ look: Look, asleepNow: Bool, at now: TimeInterval) -> String? {
            if look.wasAsleep, !asleepNow, look.wakesBefore == wakesSaid {
                wakesSaid += 1
                lastLineAt = now
                return DisplayWake.wokeLine(device: look.device, activity: look.activity)
            }
            if let last = lastLineAt, now >= last, now - last < DisplayWake.declaredLineInterval { return nil }
            lastLineAt = now
            return DisplayWake.declaredLine(device: look.device, activity: look.activity, asleepNow: asleepNow)
        }
    }

    // MARK: - TEST ONLY: a test host's display asleep

    /// TEST ONLY: a test host's display (the test pattern's, which never sleeps) reads asleep while
    /// the file this variable names exists, so a test client's press shows what `pass` does: in the
    /// dry run's input log (SILL_TEST_INPUT_LOG=1) a pointer move where the press was and no release,
    /// and a `disp.wakeDry` at the press. Honoured only by a test host; a real host reads its displays.
    static let displayAsleepVariable = "SILL_TEST_DISPLAY_ASLEEP"

    /// The file the variable names, and the one line it prints at start (nil when it is not set).
    static func testDisplayAsleep(environment: [String: String], testHost: Bool) -> (path: String?, line: String?) {
        guard let value = environment[displayAsleepVariable], !value.isEmpty else { return (nil, nil) }
        guard testHost else { return (nil, "\(displayAsleepVariable) ignored: only a --synthetic host takes it.") }
        return (value, "Test display: the test pattern's display reads asleep while the file \(displayAsleepVariable) names exists.")
    }

    // MARK: - TEST ONLY: the user's location

    /// TEST ONLY: `remote` declares the user as connected over the network (kIOPMUserActiveRemote)
    /// instead of in front of the Mac (kIOPMUserActiveLocal), for Noah to see on a real Mac whether
    /// that also wakes the panel (IOPMLib.h: "various components of the system are maintained at
    /// different power levels depending on user location"). Read by every real host, Sill.app
    /// included (it lets nobody in, as the encoder's variables); a test host declares nothing.
    static let userActiveVariable = "SILL_TEST_USER_ACTIVE"

    /// What the variable says, and the one line it prints at start (nil when it is not set). The
    /// value is never echoed: a line of the log is not the environment's to write.
    static func userActive(environment: [String: String], testHost: Bool) -> (remote: Bool, line: String?) {
        guard let value = environment[userActiveVariable], !value.isEmpty else { return (false, nil) }
        guard !testHost else {
            return (false, "\(userActiveVariable) ignored: a test host declares no user activity (it counts \(dryKey)).")
        }
        switch value {
        case "remote":
            return (true, "TEST: user activity is declared as remote (kIOPMUserActiveRemote), not local (\(userActiveVariable)=remote).")
        case "local":
            return (false, "TEST: user activity is declared as local (kIOPMUserActiveLocal), as without \(userActiveVariable).")
        default:
            return (false, "\(userActiveVariable) ignored: it takes local or remote; user activity is declared as local.")
        }
    }
}
