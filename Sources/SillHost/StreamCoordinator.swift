import Foundation
import AppKit
import Network
import ScreenCaptureKit
import StreamProtocol

/// Owns the pipeline for the life of the process and points it at whatever source the client
/// picks. Threading: this class is main-actor; frames flow capture queue → VT thread → network
/// queue without touching it. Network callbacks hop here with Task { @MainActor }.
@MainActor
package final class StreamCoordinator {
    /// The knobs (HostConfig.swift): the CLI's `standard` values and flag, or the app's Settings.
    /// A new value is taken only between pipelines, inside `select` (see `setTarget`), so one
    /// pipeline never mixes two. The knob properties below read it, so every existing read keeps
    /// its text.
    package private(set) var config: HostConfig
    /// Settings from the app or a device that wait for the next `select` (a restart, or a switch in
    /// flight). This, else `config`, is the `target`: what the Mac's menu and the devices show.
    private var pendingConfig: HostConfig?
    /// Ceiling for the stream rate (HostConfig). Each device asks for its own panel's rate
    /// through the viewport: 120 on ProMotion, 60 elsewhere, 60 while Low Power Mode caps it.
    private var maxFPS: Int { config.maxFPS }
    /// The rate the current pipeline runs at, re-read from `wantedFPS` at every select. Capture
    /// interval, encoder session and virtual display refresh all follow it.
    private(set) var fps: Int = 60
    /// Each connected client's wanted rate (60 for one that has not said). The stream runs at the
    /// highest, so a ProMotion device is not held to a 60 Hz one beside it; a re-sent viewport
    /// from either is then a no-op instead of a restart. Cleared when the client leaves.
    private var clientFPS: [ObjectIdentifier: Int] = [:]
    private var wantedFPS: Int { min(maxFPS, max(24, clientFPS.values.max() ?? 60)) }
    /// What the next pipeline will run at: the software encoder is not asked for more than 60.
    private var effectiveFPS: Int { useSoftwareEncoder ? min(wantedFPS, 60) : wantedFPS }
    /// The rate the next pipeline for `source` runs at: the devices' (`wanted`, `effectiveFPS` unless
    /// said), and the Desktop's held to its stop's refresh rate (DesktopDisplays.rate): a 60 Hz monitor's
    /// Desktop streams at 60, at the 60 fps bitrate, to a 120 Hz iPad, since its capture gives no more; on Sill's
    /// own display (a Mac with no working screen: no stop), to that display's (VirtualDesktopSize.refreshHeld). A
    /// test host's test pattern only under SILL_TEST_DISPLAYS, whose stops say their rate, or once SILL_TEST_HEADLESS's
    /// display was said to be made, at the rate said.
    private func streamRate(for source: StreamSource, wanted: Int? = nil) -> Int {
        let wanted = wanted ?? effectiveFPS
        guard source == .desktop, !synthetic || catalog.testDisplays != nil || testHeadlessMade else { return wanted }
        return DesktopDisplays.rate(wanted, refreshHz: VirtualDesktopSize.refreshHeld(stop: catalog.desktopStop?.refreshHz, sills: headlessHz,
                                                                                         onSills: desktopOnSills(catalog.display?.displayID)))
    }

    /// Whether the Desktop's display `id` is Sill's own (a test host: once its display was said to be made, the test
    /// pattern stands for it; under SILL_TEST_VIRTUAL_DESKTOP, its stop among the test's).
    private func desktopOnSills(_ id: UInt32?) -> Bool {
        if testVirtualDesktop, testHeadlessFile == nil { return displays.isSaid(.desktop) && id == Self.testVirtualDesktopID }
        if testHeadlessMade { return true }
        guard let made = headlessDisplay?.displayID, made != 0 else { return false }
        return id == made
    }
    /// The bitrate knob is per 60 fps; a faster stream gets proportionally more so each frame
    /// keeps its share of bits.
    private var streamBitrate: Int { bitrate * fps / 60 }
    /// The quality the pipeline runs: the away pair while it runs the away quality (`awayRunning`),
    /// else the home pair (HostConfig.effective).
    private var scale: CGFloat { config.effective(away: awayRunning).captureScale }
    private var bitrate: Int { config.effective(away: awayRunning).bitrate }
    private var prioritizeSpeed: Bool { config.prioritizeSpeed }

    let server: StreamServer

    /// Holds (or releases) new sessions at every door, and says how many are connected now
    /// (StreamServer.holdNewSessions): the automatic update's last look before it installs.
    package func holdNewSessions(_ hold: Bool) -> Int { server.holdNewSessions(hold) }
    /// A sleeping display gives the stream black frames (issue #134): a device's session connecting,
    /// and what a person does to the Mac from it, are user activity on the Mac, declared as a key press
    /// would be (`deviceActive`). DisplayWake alone decides which messages count and when (`handle`
    /// forwards every one); DisplayActivity makes the call, off the main actor. Nothing is held: the
    /// display sleeps again by the Mac's own setting once no device uses it. A test host
    /// (`--synthetic`, as `injector.dryRun`) only counts `disp.wakeDry`.
    private var displayWake: DisplayWake
    private let displayActivity: DisplayActivity
    /// The parameter sets that last went out, forgotten as each stream starts (`select`): a stream's
    /// first, and any that differ, are a new frame size for the devices (`parameterSetsSent`).
    private var lastParameterSets: Data?
    let catalog = WindowCatalog()
    let capture = WindowCapture()
    /// `--synthetic`: the Desktop source streams a test pattern instead of the screen.
    let synthetic: Bool
    let syntheticCapture = SyntheticCapture()
    /// A locked Mac's placeholder (LockPolicy): a black still, no ScreenCaptureKit.
    let stillCapture = StillCapture()
    let injector = InputInjector()
    let sizer = WindowSizer()
    /// The Mac's pointer (PointerWatch): who moves it, and where it is in the streamed source, for
    /// the devices that are not moving it (kind 26, sent by StreamServer). Its geometry follows the
    /// source (`pointerGeometry`); InputInjector and VirtualStage note Sill's own motion there.
    let pointer: PointerWatch
    /// The test pattern's size in points (a synthetic host's Desktop), and the space the TEST ONLY
    /// scripted pointer moves in.
    static let testPatternRect = CGRect(x: 0, y: 0, width: 1512, height: 949)
    /// TEST ONLY (SILL_TEST_SOFTWARE_ENCODER=1, a synthetic host): every stream runs on the software
    /// encoder, the launch probe never runs and the re-check never starts, so no test touches the
    /// Mac's one hardware encoder while Noah streams (PointerTestHooks).
    private let softwareOnly: Bool
    /// The TEST ONLY hooks' lines (PointerTestHooks, InputInjector.testInputLog, `keyframeIgnoreHook`,
    /// FirewallCheck.TestHook), printed as `start` begins; empty without them.
    private let testHookLines: [String]
    /// The macOS firewall (FirewallRule, a user's report of 2026-10-29): the paths a rule may name
    /// for this process, the TEST ONLY answers a test host takes instead of asking, and one check at
    /// a time (`checkFirewall`), with one more after it when asked meanwhile.
    private let firewallPaths: FirewallRule.Paths
    private let firewallHook: FirewallCheck.TestHook?
    private var firewallChecking = false
    private var firewallAgain = false
    /// A picked window streams from its own HiDPI display (see VirtualStage): the CLI's
    /// `--virtual-display`, or the app's setting. Every branch this adds is behind this flag;
    /// without it the coordinator behaves as before. It changes only inside `select` (`adopt`).
    private var virtualDisplay: Bool { config.virtualDisplay }
    /// This process runs NSApplication's event loop (the app always, the CLI under
    /// --virtual-display), so `NSWorkspace.frontmostApplication` is current (see `activePID`).
    /// The virtual display needs that loop too: without it the setting is forced off.
    private let appKitLoop: Bool
    /// Every display Sill makes (SillDisplays, docs/virtual-desktop-plan.md §9): the stage's and the Desktop's.
    let displays: SillDisplays
    let stage: VirtualStage
    /// What the menu bar app shows. Written here, at the moment things happen; never read back.
    package let status: HostStatus
    /// Lock this Mac when the last device leaves (PrivacyLock, PrivacyPolicy; docs/privacy-mode-plan.md, part 1): the
    /// server's count of registered sessions, each session's route as it registers, the switches (at once, from
    /// `setTarget`), the lock's reading and a quit go to it. Only Sill.app's own (`testHooks` false, not `synthetic`:
    /// PrivacyPolicy.locksForReal) locks; the CLI's, the bare SillMenuBar binary's and a test host's lock nothing and
    /// put no display to sleep: they say what they would do.
    private let privacy: PrivacyLock
    /// Set by the signal handler: a select in flight when Ctrl-C lands must not stage anything new.
    private var shuttingDown = false
    private var stageLosses = 0
    /// The private CGVirtualDisplay API is checked once per run, the first time the mode is on.
    private var apiChecked = false
    /// Why that check failed, if it did: the virtual display then stays off for the whole run.
    private var apiProblem: String?
    private var encoder: HEVCEncoder? { didSet { encoderBox.current = encoder } }
    /// The display's own pixel scale under the running pipeline (CaptureScale): ScreenCaptureKit's for
    /// its filter (`pointPixelScale`), Sill's virtual display's (2) for a staged window, nil for the
    /// test pattern. Set with `active` as a pipeline starts (`startPipeline`); the injector lands
    /// input on that display's last pixel row and column at most (InputLanding).
    private var streamDisplayScale: CGFloat?
    /// Hardware HEVC normally. When a hardware session stops returning frames, or the launch probe
    /// gets no answer, the stream runs on the software encoder at 1x (Standard: half the scale each
    /// way on a Retina display, the hardware's own on a 1x one) and up to 60 fps, slow but alive
    /// (`enterSoftwareFallback`), until a re-check finds the hardware keeping up with the stream
    /// again (`recheckLoop`, `hardwareIsBack`). The hardware has been stuck for hours (2026-09-22)
    /// and busy for seconds (2026-09-24, when this used to last until the host relaunched: 3 h at
    /// half resolution, a Retina display's Standard, after a 1.8 s stall).
    private var useSoftwareEncoder = false
    private var softwareRestarts = 0
    private var lastSoftwareHangAt: CFAbsoluteTime = 0
    /// The re-check while on the software encoder. It runs only while a device is connected, so an
    /// idle host opens no hardware session. Only the task itself clears it, when its loop has ended
    /// (`stopRecheck` only cancels), so there is never a second loop, and never two tests at once;
    /// `recheckToken` keeps an ended task from clearing a newer one.
    private var recheckTask: Task<Void, Never>?
    private var recheckToken = 0
    /// Seconds from one re-check to the next: 30 at first, doubled up to 300 by a check where the
    /// hardware did not keep up (no answer, or too slow) or by a hardware hang within 5 min of a
    /// return (the busy spell was still on), and back to 30 when a return had lasted 10 min.
    private var recheckInterval = StreamCoordinator.recheckFirstInterval
    /// When the next re-check may run, and when the last one ran (or the fallback began).
    private var recheckDue: CFAbsoluteTime = 0
    private var lastRecheck: CFAbsoluteTime = 0
    /// The re-check found `maxStuckProbes` probes still stuck and said so; cleared by a return.
    private var recheckHeldBack = false
    /// When the stream last went back to the hardware encoder (0: never), and the newest encoder
    /// at that moment: a hang reported by an encoder no newer than that is stale and must not put
    /// the host back on the software encoder.
    private var lastReturnAt: CFAbsoluteTime = 0
    private var returnSerial = 0
    /// 30 s, and 300 s at most. TEST ONLY: `SILL_TEST_RECHECK_SECONDS=N` makes them N and 10 N, so
    /// the backoff and the stuck-probe limit can be run through in a minute.
    private static let recheckFirstInterval = TimeInterval(ProcessInfo.processInfo.environment["SILL_TEST_RECHECK_SECONDS"] ?? "") ?? 30
    private static let recheckMaxInterval = recheckFirstInterval * 10
    /// A hang this soon after a return doubles the interval; a return that lasted this long resets it.
    private static let returnDidNotLast: TimeInterval = 300
    private static let returnLasted: TimeInterval = 600
    /// What the encoder engine does alone, in pixels a second, for the rate a return needs
    /// (`EncoderProbe.returnBar`): the best any re-check's test measured this run, and until then
    /// an assumed rate below what this Mac's engine does.
    private var enginePixelRate = EncoderProbe.assumedEnginePixelRate
    /// TEST ONLY. `SILL_TEST_PROBE_SIZE=WxH`: the re-check tests this size instead of the stream's,
    /// as for a Retina 5K or 6K Desktop on a smaller screen. Read once; nil without it.
    private static let testProbeSize: (width: Int, height: Int)? = {
        let parts = (ProcessInfo.processInfo.environment["SILL_TEST_PROBE_SIZE"] ?? "").split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] >= 64, parts[1] >= 64 else { return nil }
        return (parts[0] & ~1, parts[1] & ~1)
    }()
    /// Probes whose frame never came back each hold a blocked thread (a stuck encoder never lets
    /// go); with this many out, the re-check stops probing until one comes back. A busy encoder
    /// hands them back within seconds, so only a stuck one reaches it (after 22–28 min of checks
    /// with no answer).
    private static let maxStuckProbes = 8
    /// The current encoder, readable off the main actor: the network queue asks it for a keyframe
    /// after dropping a delta. A lock instead of an actor hop keeps that request immediate.
    private let encoderBox = EncoderBox()
    private final class EncoderBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: HEVCEncoder?
        var current: HEVCEncoder? {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }
    package private(set) var active: StreamSource = .none {
        didSet {
            if case .window(let id) = active { catalog.activeWindowID = id } else { catalog.activeWindowID = nil }
            if active == .none { status.update { $0.stream = nil } }
            server.setStreaming(active != .none)   // link keepalive ticks while a source is live
            // The Mac's cursor shape, never while it is locked (LockPolicy: another user's, or the lock screen's).
            cursorShapes.running = active != .none && lockAllowed.pointer
            pointer.setGeometry(pointerGeometry(), fps: fps)   // also on a restart of the same source
            menuTargetChanged()                     // the menus' app follows the source (only for devices that asked)
            audioFollow()                           // and the sound (the same app keeps its stream)
        }
    }
    private var rectCache: (id: CGWindowID, rect: CGRect, at: CFAbsoluteTime)?
    private var pendingLaunch: String?
    private var switching = false
    /// Fallback virtual display created for Desktop mode on a headless Mac or closed-lid MacBook (#61): the Desktop
    /// role's display, made and removed by SillDisplays, as every display of Sill's.
    private var headlessDisplay: VirtualDisplay? { displays.display(.desktop) }
    private var releasingHeadless = false
    /// The displays as this session has looked at them, and the rules for making Sill's display and for its going
    /// (HeadlessDesktopPolicy.Watch: Noah's test of 2026-11-12). Fed by macOS's reconfiguration callback, the
    /// Desktop's select, the lock's changes and a wake (`lookAtDisplays`).
    private var displayWatch = HeadlessDesktopPolicy.Watch()
    /// The look `Watch.release` asked for, at the end of a real screen's two seconds (`scheduleReleaseCheck`).
    private var releaseCheck: Task<Void, Never>?
    /// What macOS last said of the screens: asleep (NSWorkspace's screensDidSleep; a test host's `screens asleep` line
    /// coming) until it says they woke (screensDidWake; the line going), a person at a device has activity declared
    /// (it wakes them: `personDeclared`), a look finds a real display working, or this session is unlocked or back on
    /// the console (each needs them awake). Sill's display waits for the wake (HeadlessDesktopPolicy.screensAsleep,
    /// Watch.make).
    private var screensSaidAsleep = false
    /// The last look's counts (`displaysNow`), for the line a Desktop prints when the screens are asleep, not gone.
    private var lastDisplaysSeen: (active: Int, online: Int, lidClosed: Bool)?
    /// The two lines of the screens' sleep, each once: "asleep, not gone" until a real display works again, "none
    /// made until they wake" until they wake.
    private var saidAsleepNotGone = false
    private var saidWaitsForWake = false
    /// TEST ONLY. `SILL_TEST_HEADLESS=<file>` on a --synthetic host: its displays are what the file lists
    /// (HeadlessDesktopPolicy.testHeadlessList), so the rules and their looks run for real against a scripted list, and
    /// Sill's display is only said to be made (`testHeadlessMade`) and removed, never made. Nil otherwise.
    private let testHeadlessFile: String?
    /// TEST ONLY: the display a test host with SILL_TEST_HEADLESS said it made (listed as Sill's, active): SillDisplays'
    /// said Desktop display (`say`), never made.
    private var testHeadlessMade: Bool { displays.isSaid(.desktop) }
    /// Sill's display exists (or, on a test host, was said to be made).
    private var hasHeadlessDisplay: Bool { displays.exists(.desktop) }
    /// Each connection's last viewport and whose came last, and the device that asked for the Desktop last (its pick of
    /// it, or a step: kind 47): Sill's display is that device's size and rate (VirtualDesktopSize.matched, Noah's decision
    /// of 2026-11-18), never only the last viewport any device sent.
    private var viewports: [ObjectIdentifier: Viewport] = [:]
    private var newestViewport: ObjectIdentifier?
    private var desktopAsker: ObjectIdentifier?
    /// Sill's display's refresh rate as it came up (its mode's; a test host's said one): the Desktop's rate is held to it
    /// while the Desktop shows it (`streamRate`, VirtualDesktopSize.refreshHeld).
    private var headlessHz: Double?
    /// The guard for #380 (DisplayMakeGuard): Sill.app's marker in Application Support and its count, or a test host's
    /// under SILL_TEST_MAKE_GUARD; nil in the CLI, which keeps none.
    private let displayGuard: DisplayMakeGuard.Store?
    /// Its line for a Desktop with no real screen, once a run.
    private var saidGuardHolds = false
    /// The line for a Desktop with no real screen while the person's switch is off (HostConfig.headlessDisplay), once
    /// until it is turned on again.
    private var saidSwitchedOff = false
    // The Virtual Desktop (phase 2b of docs/virtual-desktop-plan.md as revised 2026-11-18; HostConfig.virtualDesktop, off by
    // default): the last of the Desktop's stops, Sill's Desktop display (SillDisplays' `.desktop`, the same identity as a
    // Mac with no screen's: one display in two roles), made when a device shows its stop, kept while shown and 30 s
    // after, its windows moved to the main display as it goes and back as it returns. `lookAtVirtualDesktop` asks its rule.
    /// When it exists (VirtualDesktopLife): told of every make and removal of the Desktop's display, either role.
    private var desktopLife: VirtualDesktopLife
    /// The windows Sill moved off it, back when it returns in this run (DesktopWindowLedger, memory only).
    private var desktopBook = DesktopWindowLedger.Book<WindowSizer.Placement>()
    /// Its matched device's space over time (VirtualDesktopSize.Follow), from its make; nil while it does not exist.
    private var desktopFollow: VirtualDesktopSize.Follow?
    /// What it is now (nil while it does not exist).
    private var virtualDesktopNow: VirtualDesktopNow?
    private struct VirtualDesktopNow {
        /// Its size and rate: as it came up, or as a follow in place left it.
        var size: VirtualDesktopSize.Size
        var hz: Int
        /// The most it can take in place (VirtualDesktopSize.backing; the display's own, VirtualDisplay.backing).
        var backing: VirtualDesktopSize.Backing
        /// The device it is for (plan §5's matched device: the one it was made for, or that stepped onto it since; once
        /// that one left, the one the make's rule names next: `adoptVirtualDesktopDevice`); nil while none, and from the
        /// moment that one leaves (a later connection's object may take the same address, and so the same identifier).
        var device: ObjectIdentifier?
        var deviceName: String?
        /// Whether it showed the last look: a device that shows it again has its space looked at again (`.shown`).
        var shown = true
    }
    /// A follow in place under way (`followVirtualDesktopInPlace`): the Desktop's display follower waits for its end, which
    /// restarts the Desktop once, at the size it ends at (probe P2c: a turn is two reconfigurations, 1x then 2x).
    private var virtualDesktopResizing = false
    /// An iPhone's pixel-for-pixel sizes macOS did not keep this run (VirtualDesktopSize.id; at a make, or in place): each
    /// is asked as the size that works from then on (VirtualDesktopSize.device(space:screen:refused:), its line once).
    private var phoneRefused: Set<String> = []
    /// TEST ONLY: a test host's said Virtual Desktop as Noah's probes measured a display (VirtualDesktopSize.TestDisplay),
    /// and SILL_TEST_VD_STEPS' knobs for it.
    private var testVirtualDisplay: VirtualDesktopSize.TestDisplay?
    private let testVirtualDesktopKnobs: VirtualDesktopSize.TestKnobs
    /// The one look scheduled (the grace's end, the spacing's, a real screen's 2 s, a follow's settle), replaced by each look.
    private var virtualDesktopCheck: Task<Void, Never>?
    /// A make or a removal under way (their awaits): a look meanwhile is left to its end, which looks again.
    private var virtualDesktopChanging = false
    /// A make or a removal the spacing holds back, since when, and whether ten changes in a minute hold it (its line once done).
    private var virtualDesktopWaited: (since: Double, fullMinute: Bool)?
    /// A make that failed this run (the error, or that it never came up): no more tries until its switch is turned off and
    /// on (VirtualDesktopWords.failed), as the stage's failures.
    private var virtualDesktopFailure: String?
    /// The kept-while-locked line, once a lock.
    private var saidVirtualDesktopKept = false
    /// The device that switched it on, shown it once its switch is taken (open decision 12 (a): `virtualDesktopSwitched`).
    private var showVirtualDesktopTo: ObjectIdentifier?
    /// TEST ONLY (SILL_TEST_VIRTUAL_DESKTOP with SILL_TEST_DISPLAYS on a test host, VirtualDesktopLife.testHook): this host can
    /// have the Virtual Desktop and only says it makes it, listed as one more test stop (`testVirtualDesktopID`).
    private let testVirtualDesktop: Bool
    private static let testVirtualDesktopID: UInt32 = 0x5D
    /// The Desktop's display size in points as its capture was built (`desktopCapture`).
    private var desktopStreamPoints: CGSize?
    /// A restart of the active source is in flight (a settings change, a resize, a rate change,
    /// the encoder fallback, a lost display): the source being restarted. Nil during a switch to
    /// another source.
    private var restartOf: StreamSource?
    /// A device's pick of a different source that came in during that restart (`handlePick`);
    /// taken by select's defer. Never set during a switch to another source: the device's automatic
    /// Desktop request can land then (StreamClient's window list handling) and must not override
    /// the user's pick.
    private var pickArrivedWhileSwitching: StreamSource?
    /// The display the Desktop's capture was built on (`desktopCapture`). When the catalog's Desktop
    /// display moves off it (the display a device stepped to plugged in again, a new ID after a sleep),
    /// the Desktop restarts there, so input never lands on a display the devices are not shown.
    private var desktopStreamDisplay: UInt32?
    /// TEST ONLY (SILL_TEST_DISPLAYS, DesktopDisplaysHook): each test stop's pixel scale, for the test
    /// pattern's size. Empty on every other host.
    private var testDisplayScales: [UInt32: CGFloat] = [:]
    /// The client's last stream panel size and text scale. One stream, so with several clients
    /// the last one to report wins. Only ever one a host takes (ViewportBounds); a refused one
    /// leaves it as it was.
    private var viewport: Viewport?
    /// When each connection's last "Viewport from … refused" line was printed: one a second at most.
    private var viewportRefusedLineAt: [ObjectIdentifier: CFAbsoluteTime] = [:]
    /// Each connection's last viewport scale, nil for none: Aa going from a scale to Off puts the windows back.
    private var fitScales: [ObjectIdentifier: Double] = [:]
    /// The windows Sill sized for a device in regular mode, each with its way back (WindowRestore,
    /// issue #57): recorded at the first fit (`fitToViewport`), put back when the window stops
    /// streaming (`restoreFits`), handed to the virtual display's stage when it takes the window.
    private var fits = WindowRestore.Ledger<WindowSizer.Placement>()
    /// The window streaming in regular mode was in full screen when the catalog last listed it (its
    /// frame covered a display), or when it was picked: off the list, it may be leaving full screen
    /// (`windowsChanged`, WindowRestore.keepsStreaming).
    private var listedFullScreen: CGWindowID?
    /// The app of the window `select` last resolved, so the sound still finds it while a regular-mode
    /// window streams on off the catalog's list (`windowsChanged`'s looks, issue #57; `audioKey`).
    private var streamedPID: (window: CGWindowID, pid: pid_t)?
    /// Each connection's kind 17 changes of the last second (applied or refused), and when its
    /// "ignored" line was last printed: `settingsPerSecond` a second, one line a second at most.
    private var settingsArrivals: [ObjectIdentifier: [CFAbsoluteTime]] = [:]
    private var settingsIgnoredLineAt: [ObjectIdentifier: CFAbsoluteTime] = [:]
    static let settingsPerSecond = 4
    /// Trackpad gestures (kind 28, docs/trackpad-gestures-plan.md §7): the view Sill's last gesture
    /// opened, which the opposite gesture closes (GestureChords), and each connection's gestures of
    /// the last second: `gesturesPerSecond` a second, the rest dropped with one line a minute.
    private var gestureChords = GestureChords()
    private var gestureArrivals: [ObjectIdentifier: [CFAbsoluteTime]] = [:]
    static let gesturesPerSecond = 4
    private lazy var gestureDrops = RefusalSummary(queue: .main, categories: ["gestures"]) { counts in
        "Gestures ignored: \(counts["gestures"] ?? 0) in a minute, from devices sending more than \(StreamCoordinator.gesturesPerSecond) a second."
    }
    /// A device's keyframe requests (kind 44, issue #101: its picture was interrupted): when each
    /// connection's last one was taken, at most one a second, the rest dropped with one line a minute.
    /// A device asks once per interruption, again only when the keyframe has not come in 4 s or more,
    /// 2 s apart at least (KeyframeRecovery), and each costs a keyframe to every device.
    private var keyframeRequestAt: [ObjectIdentifier: CFAbsoluteTime] = [:]
    /// TEST ONLY. `SILL_TEST_KEYFRAME_IGNORE=<n>` on a --synthetic host: the first n keyframe requests
    /// it takes are ignored, with a line each, as a Mac from before kind 44 skips every one, so a
    /// device's ask again after its wait runs for real (`keyframeIgnoreHook`). Zero otherwise.
    private var keyframeRequestsToIgnore: Int
    /// TEST ONLY. `SILL_TEST_DISPLAY_ASLEEP=<file>` on a --synthetic host: its display reads asleep
    /// while the file exists, so a test client's press shows DisplayWake.pass at work
    /// (`pressLandsAsleep`). Nil otherwise: a test host's display never reads asleep.
    private let testDisplayAsleepFile: String?
    /// TEST ONLY. `SILL_TEST_DESKTOP_FAIL=<n>` on a --synthetic host: the first n starts of the
    /// Desktop's capture fail, as ScreenCaptureKit's "Start stream failed … The stream is nil" did on
    /// 2026-10-28 (CatalogLook), so the host's one more try (n = 1) and a device's second ask (n = 2:
    /// the try fails too) run for real (`desktopFailHook`). Zero otherwise.
    private var desktopStartsToFail: Int
    static let keyframeRequestSpacing: CFTimeInterval = 1
    private lazy var keyframeRequestDrops = RefusalSummary(queue: .main, categories: ["keyframes"]) { counts in
        "Keyframe requests ignored: \(counts["keyframes"] ?? 0) in a minute, from devices asking more than once a second."
    }
    /// Gestures waiting for a switch in flight to finish, in arrival order, with the connection that
    /// sent each, and the task posting them.
    private var pendingGestures: [(gesture: TrackpadGesture, device: String, id: ObjectIdentifier)] = []
    private var gestureDrain: Task<Void, Never>?
    /// A host that does not advertise (the synthetic test hosts, which tests reach by port) posts no
    /// gesture's chord: it logs the one it would post, "(not posted: a test host)", and counts
    /// `in.gestureDry`, so a test can send gestures without touching this Mac.
    private let gesturesDry: Bool
    /// TEST ONLY: a test host's SILL_TEST_HOTKEYS table (GestureChords.testTable), used instead of
    /// this Mac's Keyboard Shortcuts; nil on every other host.
    private let testHotKeys: [Int: HotKey]?
    /// This macOS had no getters for its Keyboard Shortcuts at a gesture: said once.
    private var saidHotKeysMissing = false
    /// A viewport that came in mid-switch, when `active` still names the old source: applied once
    /// the switch is done, so a rotation during a restart is not lost.
    private var viewportArrivedWhileSwitching = false
    /// The last client left mid-switch, when `select(.none)` would have been refused (or `active`
    /// still named the old source): applied once the switch settles, if the room is still empty.
    /// Matters most with `--virtual-display`, where a switch can take seconds and would otherwise
    /// leave the window on the virtual display, streaming to nobody.
    private var deselectWhenSettled = false
    /// The Mac's cursor shape, streamed to the clients that draw the pointer themselves.
    let cursorShapes = CursorShapeWatcher()
    private let macName = Host.current().localizedName ?? "Mac"
    /// In every window list (`WindowList.launchID`): a device moving its session from AWDL to the
    /// network checks that the new connection reaches this same running host, since the Bonjour
    /// name it found it by can belong to another Mac too. Per launch, so nothing is stored.
    private let launchID: String
    /// In every window list (`WindowList.hostVersion`, with `protocol`): Sill.app's version; nil
    /// from the CLI, which has no bundle. For later devices, which can then say which Mac to update.
    private let hostVersion: String?
    /// Remote access (RemoteAccess): Sill.app always, SillHost only with --remote or --pairing
    /// (with --pairing alone, an identity for the TLS home door and no remote door). Nil: no
    /// identity, no TXT tag, no kind 18, no remote door, no `away` in kind 16: exactly the host
    /// as before.
    package let remote: RemoteAccess?
    /// Each admitted connection's route (home and its origin, or the remote door's), from the server.
    private var routes: [ObjectIdentifier: ClientRoute] = [:]
    /// Connections the Mac no longer serves (StreamServer.closeSessions: a pairing removed, Remote
    /// Access or internet access off, Require pairing on), from the moment the server marks them until
    /// they leave: nothing they send lands but the up of a key or a button they hold down on the Mac
    /// (RevokedInput), whether it comes now, waits in the input held for an activation or waits for a
    /// switch (a gesture). Security scan finding 10.
    private var revoked: Set<ObjectIdentifier> = []
    /// This Mac's screen locked, or another user, the login window or nobody on its console (LockPolicy,
    /// docs/locked-mac-plan.md, Noah's finding of 2026-10-31): SessionLock's gate has the reading, set the
    /// moment a witness changes it on SessionLock's own queue, and every decision here reads it then
    /// (`lockReading`); `lockActedOn` is the reading `lockChanged` last acted on, `restore` the window
    /// that streamed when the lock began, picked again after the unlock.
    private let lockGate = SessionLock.shared.gate
    private var lockActedOn: LockPolicy.Reading?
    /// The off-console view `lockChanged` last acted on (docs/off-console-plan.md).
    private var lockActedView = false
    private var restore = LockPolicy.Restore()
    /// The Desktop streams the placeholder (a black still, no capture: StillCapture), not the display:
    /// what a locked Mac streams.
    private var placeholderStreams = false
    /// The last window list built was a locked one (`listMessage`): an unlock `lockChanged` missed (its
    /// changes coalesced) still sends the devices the unlocked one.
    private var lockedListSent = false
    /// The connections whose catalog brought the icons and the installed apps (`sendCatalog` while
    /// unlocked): one that connected while this Mac was locked gets all of them at the unlock.
    private var appsAndIconsSent: Set<ObjectIdentifier> = []
    /// The requests the lock refused: one line a minute at most for each kind, the first at once.
    private lazy var lockRefusals: [LockPolicy.Refusal: RefusalSummary] = Dictionary(uniqueKeysWithValues:
        LockPolicy.Refusal.allCases.map { kind in
            (kind, RefusalSummary(queue: .main, categories: [kind.rawValue]) { counts in
                LockPolicy.refusedLine(kind, count: counts[kind.rawValue] ?? 0)
            })
        })
    /// Away from home (docs/remote-bundle-plan.md §5; AwayPolicy): every connected device is away,
    /// so the away quality is the target. Kept while no device is connected; the next to register
    /// decides (`routesChanged`). What the Mac's card, menu and every device are told.
    private var awayWanted = false
    /// The away quality runs: the value the last `select` (or `adopt`) took. The pipeline reads it.
    private(set) var awayRunning = false
    /// A device that joined and flipped `awayWanted` (`routesChanged`): its first viewport, which
    /// carries its rate and which a device sends as soon as it is connected, takes the flip in the
    /// same restart as the rate; without one within a second (a test client), the flip goes alone.
    /// Nothing else applies the flip meanwhile but a `select` that runs anyway, which takes it.
    private var flipWait: ObjectIdentifier?
    private var flipWaitToken = 0
    /// Each connection whose catalog went out (`sendCatalog`): the ones settings states reach.
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Each connection's link while it does not keep up (LinkJudge, docs/remote-bundle-plan.md §6.5):
    /// its kind 16's `link`, and the card's. A state leaves out a report whose bitrate (the running
    /// one when it was judged) is no longer the target's, so the answer to the pick that lowers it
    /// already carries none (the restart's reset follows). The bitrate alone: a change of the capture
    /// scale alone may restart nothing (the software encoder runs at points).
    private var linkReports: [ObjectIdentifier: LinkReport] = [:]
    /// The quality the devices' links are judged at: the running stream's (`select`'s commit), nil
    /// while nothing streams. A restart that keeps it keeps their judgement (LinkJudge.judgedAfresh).
    private var judgedQuality: LinkJudge.Quality?
    /// When each connection last asked for a pairing code (kind 21): once per 30 s.
    private var lastPairingWanted: [ObjectIdentifier: CFAbsoluteTime] = [:]
    /// The streamed app's menus, for the devices that asked for them (kinds 24, 25 and 27,
    /// MenuMirror). Reads and presses nothing for a device that never asked.
    let menus: MenuMirror
    /// The clipboard both ways (kind 32, HostClipboard; docs/clipboard-plan.md), for the devices that
    /// subscribed, while Share clipboard with devices (`HostConfig.shareClipboard`) is on. Looks at
    /// nothing while nobody subscribes.
    let clipboard: HostClipboard
    /// The Mac's sound (kind 43, AudioPipeline): the sound of what streams, to the devices that play
    /// it, while Send Audio is on. It follows the source from `active`'s didSet, as the pointer and
    /// the menus do, so the picture always starts first, and nothing of it waits on the picture or the
    /// other way round.
    let audio = AudioPipeline()
    /// Connected devices that play the sound (the server's count, from their hellos).
    private var audioListeners = 0
    /// TEST ONLY. `SILL_TEST_MENU_PID=<pid>` on a --synthetic host: the test pattern's menus are that
    /// process's (the gates' fixture, Scripts/menufixture.swift), read and pressed through the same
    /// code, never activated (the Desktop's rule). Nil otherwise; `testMenuLine` is what `start`
    /// prints about it, only when the variable is set.
    private let testMenuPID: pid_t?
    private let testMenuLine: String?
    /// The Desktop's frontmost app is looked at again 0.3 s after a device's click or key, at most
    /// once per 0.5 s (a click on another app's window activates it 50–200 ms later).
    private var menuFrontCheckAt: CFAbsoluteTime = 0
    private var menuFrontCheckPending = false
    /// Under the AppKit loop, while a device subscribes: app activations on the Mac.
    private var frontmostObserver: NSObjectProtocol?

    /// `config` is validated, and its virtual display forced off without the AppKit loop, which
    /// the display needs (VirtualDisplay.swift, "Event loop"). `appKitLoop`: see the property.
    /// `homePairing`: the home door speaks TLS with `remote`'s identity and trust list
    /// (docs/home-pairing-plan.md §4.9; Sill.app, SillHost --pairing), or has no listener at all
    /// when that identity could not be loaded; without it the home door is plain, as before (the
    /// CLI's default). `testHooks`: false for Sill.app's own executable, which honours no TEST ONLY
    /// hook that bears on who gets in or what pairing needs (§4.3): with it false, or on a host
    /// that advertises, those hooks are ignored with one line each. `hostVersion`: Sill.app's
    /// version for the window lists, when it has one that parses. `displayGuard`: keep the guard for #380 in
    /// Application Support (DisplayMakeGuard: Sill.app's; the CLI keeps none).
    package init(config: HostConfig, synthetic: Bool = false, appKitLoop: Bool, remote: RemoteAccess? = nil,
                 homePairing: Bool = false, testHooks: Bool = true, hostVersion: String? = nil, displayGuard: Bool = false) throws {
        var config = config.validated()
        if !appKitLoop { config.virtualDisplay = false }
        self.config = config
        self.synthetic = synthetic
        self.appKitLoop = appKitLoop
        self.hostVersion = hostVersion
        let env = ProcessInfo.processInfo.environment
        let path = PointerTestHooks.pointerPath(synthetic: synthetic, environment: env)
        let software = PointerTestHooks.softwareEncoder(synthetic: synthetic, environment: env)
        let inputLog = InputInjector.testInputLog(synthetic: synthetic, environment: env)
        let noScreen = PointerTestHooks.noScreen(synthetic: synthetic, environment: env)
        WindowCatalog.screenless = noScreen.on
        let keyframeIgnore = Self.keyframeIgnoreHook(synthetic: synthetic, environment: env)
        let desktopFail = Self.desktopFailHook(synthetic: synthetic, environment: env)
        let displaysHook = DesktopDisplaysHook.read(testHost: DoorPolicy.isTestHost(advertises: !synthetic, bundled: !testHooks),
                                                    environment: env)
        pointer = PointerWatch(synthetic: synthetic, path: path.path)
        softwareOnly = software.on
        let userActive = DisplayWake.userActive(environment: env, testHost: synthetic)
        displayActivity = DisplayActivity(remote: userActive.remote)
        keyframeRequestsToIgnore = keyframeIgnore.count
        let displayAsleep = DisplayWake.testDisplayAsleep(environment: env, testHost: synthetic)
        testDisplayAsleepFile = displayAsleep.path
        let testHeadless = HeadlessDesktopPolicy.testHeadless(environment: env,
                                                              testHost: DoorPolicy.isTestHost(advertises: !synthetic, bundled: !testHooks))
        testHeadlessFile = testHeadless.path
        // The guard for #380: Sill.app's, else a test host's own folder (TEST ONLY, never Sill.app's).
        let guardHook = Self.makeGuardHook(environment: env, testHost: DoorPolicy.isTestHost(advertises: !synthetic, bundled: !testHooks))
        self.displayGuard = displayGuard ? DisplayMakeGuard.Store.app() : guardHook.store
        // TEST ONLY: the Virtual Desktop said, never made, on a test host with SILL_TEST_DISPLAYS' stops, and its grace.
        let vdHook = VirtualDesktopLife.testHook(environment: env, testHost: DoorPolicy.isTestHost(advertises: !synthetic, bundled: !testHooks),
                                                 stops: displaysHook.stops != nil)
        testVirtualDesktop = vdHook.on
        desktopLife = VirtualDesktopLife(grace: vdHook.grace ?? VirtualDesktopLife.grace)
        let vdSteps = VirtualDesktopSize.testSteps(environment: env, on: vdHook.on)
        testVirtualDesktopKnobs = vdSteps.knobs
        // The firewall's TEST ONLY answers, for a test host alone (StreamServer's own rule).
        let firewallTest = FirewallCheck.TestHook.read(testHost: DoorPolicy.isTestHost(advertises: !synthetic, bundled: !testHooks),
                                                       environment: env)
        firewallHook = firewallTest.hook
        firewallPaths = FirewallRule.paths(executable: FirewallCheck.executablePath())
        desktopStartsToFail = desktopFail.count
        testHookLines = [path.line, software.line, inputLog.line, userActive.line, keyframeIgnore.line, desktopFail.line,
                         noScreen.line, firewallTest.line, displayAsleep.line, displaysHook.line, testHeadless.line,
                         guardHook.line].compactMap { $0 } + vdHook.lines + [vdSteps.line].compactMap { $0 }
        status = HostStatus()
        privacy = PrivacyLock(on: config.lockAfterSession, sleeps: config.lockSleepsDisplay, onlyAway: config.lockOnlyAfterAway,
                              real: PrivacyPolicy.locksForReal(synthetic: synthetic, bundled: !testHooks),
                              testHost: DoorPolicy.isTestHost(advertises: !synthetic, bundled: !testHooks),
                              status: status, gate: SessionLock.shared.gate)
        var home = StreamServer.HomeDoorMode.plain
        if homePairing, let remote {
            if let identity = remote.identity {
                home = .tls(StreamServer.HomeTLS(identity: identity, trust: remote.trust))
            } else {
                home = .closed("Sill couldn’t use its key \(remote.keyPlace) (\(remote.identityProblem ?? "no identity"))")
            }
        }
        // The test pattern is for test clients, not devices.
        server = try StreamServer(advertise: !synthetic, home: home, testHooks: testHooks)
        server.macName = macName                           // the update goodbye names this Mac (DeviceGate)
        TestHooks.reportIgnored(testHost: server.isTestHost)
        // A host that does not advertise, `--synthetic` in the CLI and in the app alike (as
        // `injector.dryRun` below), not `server.isTestHost`, which also leaves out Sill.app's own
        // executable: that narrowing is for the door and pairing hooks (TestHooks), and a gesture's
        // chord must never be posted from the test pattern.
        gesturesDry = synthetic                            // a test host never posts a gesture (§7.4)
        displayWake = DisplayWake(testHost: synthetic)     // nor declares user activity (issue #134)
        testHotKeys = synthetic ? Self.testHotKeyTable() : nil
        menus = MenuMirror(server: server)
        let launch = UUID().uuidString
        launchID = launch
        // A synthetic host shares a pasteboard of its own, never this Mac's clipboard.
        clipboard = HostClipboard(server: server, enabled: config.shareClipboard, launchID: launch, synthetic: synthetic)
        let hook = Self.testMenuHook(synthetic: synthetic)
        testMenuPID = hook.pid
        testMenuLine = hook.line
        self.remote = remote
        // Direct Wireless is the listener's: built with it at start, replaced when it changes (adopt).
        server.setPeerToPeer(config.directWireless)
        displays = SillDisplays(catalog: catalog)
        stage = VirtualStage(sizer: sizer, catalog: catalog, displays: displays)
        // Sill's own motion is Sill's: the server counts each device's input, the injector notes
        // each post just before it (and a synthetic host posts nothing: the test pattern is not the
        // screen, docs/pointer-visibility-plan.md Q10), the stage its warp home.
        server.pointerWatch = pointer
        injector.watch = pointer
        injector.dryRun = synthetic
        injector.testLog = synthetic && inputLog.on
        // A held key repeats (KeyRepeat) only while its device is heard from: a network can hold the
        // key's up back for seconds before the device is given up.
        injector.heardFrom = { [server] id in server.lastHeard(from: id) }
        stage.onWarp = { [pointer] in pointer.sillMoved() }
        // A locked Mac (LockPolicy, docs/locked-mac-plan.md): SessionLock's gate is what the server drops
        // by on its own queue, and what each part that reads or posts on this Mac's behalf asks first,
        // whatever the main actor is doing. Its witnesses start now, before any door opens: until their
        // first reading the gate reads off console.
        let gate = lockGate
        server.lockGate = gate
        // Show this account while another user is on the screen (docs/off-console-plan.md): the gate has the
        // switch before its first reading, so that reading's line and the first frames already follow it.
        gate.setOffConsoleView(config.offConsoleView)
        // An icon or the apps that raced the lock (the gate withheld them on the network queue after this
        // side had sent them): the device they were for gets every icon and the apps at the unlock.
        server.onCatalogWithheld = { [weak self] id in
            Task { @MainActor in
                guard let self else { return }
                if let id { self.appsAndIconsSent.remove(id) } else { self.appsAndIconsSent.removeAll() }
            }
        }
        catalog.isLocked = { !gate.allowed.windows }    // the off-console view lists windows and takes thumbnails
        // TEST ONLY: a test host's stops in place of this Mac's displays (SILL_TEST_DISPLAYS).
        if let stops = displaysHook.stops {
            catalog.testDisplays = stops.map(\.display)
            testDisplayScales = Dictionary(stops.map { ($0.display.id, $0.scale) }, uniquingKeysWith: { a, _ in a })
        }
        clipboard.isLocked = { gate.locked }
        menus.isLocked = { gate.locked }
        injector.lockReading = { gate.reading }
        stage.mayWarp = { gate.reading != .offConsole }       // the cursor is the console's then, never moved from here
        stage.mayMakeDisplay = { !gate.locked }
        displays.makeGuard = self.displayGuard
        catalog.remembersBuiltIn = displayGuard        // Sill.app's preference alone (#200's defect 10)
        SessionLock.shared.onChange = { [weak self] in Task { @MainActor in await self?.lockChanged() } }
        SessionLock.shared.start(testHost: server.isTestHost)
        // The identity's TXT record (its tag, and `p` on a TLS home door) must be in the first
        // registration: set before `server.start()`.
        remote?.attach(server: server, status: status, macName: macName, requirePairing: config.requirePairing)
        stage.onLost = { [weak self] in Task { @MainActor in await self?.stageLost() } }
        // macOS removed Sill's Desktop display on its own (a sleep, display arbitration), in either role: counted gone, and a
        // Desktop that showed it starts again on what is left (SillDisplays already forgot it).
        displays.onLost[.desktop] = { [weak self] in self?.desktopDisplayLost() }
        let guardHeld = self.displayGuard?.holds ?? false
        status.update { $0.synthetic = synthetic; $0.virtualDisplayOn = config.virtualDisplay; $0.displayMakeHeld = guardHeld }
        // Every change of the snapshot re-publishes the devices' settings state (deduplicated, so
        // the once-a-second stats send nothing). One before `server.start()` reaches nobody, and
        // every device gets a fresh state in `sendCatalog`, so early calls are harmless.
        status.onChange = { [weak self] in self?.publishSettings() }
        injector.repeatLanding = { [weak self] in self?.keyRepeatLanding() ?? .nowhere }
        menus.prepare = { [weak self] in await self?.focusForMenus() ?? true }
        menus.currentTarget = { [weak self] in self?.menuTarget() }
        menus.onSubscribersChanged = { [weak self] any in self?.watchFrontmostApp(any) }
        catalog.onPolled = { [weak self] in self?.catalogPolled() }
        // The sound's messages go straight from its queue to the network queue; its status to the Mac's.
        let server = self.server
        audio.onFormat = { data, epoch in server.broadcastAudio(format: data, epoch: epoch) }
        audio.onPackets = { data, epoch in server.broadcastAudio(packets: data, epoch: epoch) }
        audio.onStatus = { [weak self] _ in self?.showAudio() }
        // A sound that failed or ended by itself, due to be tried again (issue #365): what it should be of
        // now, from the source, the display and the lock as they are (`audioKey`), never the key it had. Not
        // during a switch, whose end asks anyway (`active`'s didSet, set on every path of `select`), and
        // whose stage may have just taken the display that sound was built on away.
        audio.onRetry = { [weak self] in
            guard let self, !self.switching else { return }
            self.audioFollow()
        }
        server.onAudioListenersChanged = { [weak self] count in
            Task { @MainActor in
                guard let self else { return }
                self.audioListeners = count
                self.audioFollow()
                self.showAudio()
            }
        }

        server.onClientConnected = { [weak self] connection, route, link in
            Task { @MainActor in
                guard let self else { return }
                let id = ObjectIdentifier(connection)
                self.routes[id] = route
                // Lock this Mac when the last device leaves, Only after a device away from home: this visit had one
                // (after the count that took it, which the server reported first).
                self.privacy.joined(away: route.isAway)
                // A paired device shows its paired name until its own stats arrive, and a remote one
                // its route; a home device its link (Wired, Wi-Fi, Direct) as soon as it is known.
                self.status.update {
                    $0.devices.append(HostStatusSnapshot.Device(id: id, endpoint: "\(connection.endpoint)", name: route.pairedName,
                                                                route: link, remoteRoute: route.label))
                }
                // Admitted while the Mac was deciding a change that cuts it off (Remove, Require pairing,
                // Remote Access or internet access: the decision saved it, a keychain write or its prompt,
                // while this registration waited behind it, out of `cutOff`'s sight): cut off now, before
                // any message of it, which all come after this (security scan finding 10, the review of
                // PR #254). The server says goodbye to it as to the others. Nothing of it wakes the display
                // or counts as the paired device's last connection.
                if let remote = self.remote, !remote.stillServes(route) { self.markRevoked(id) }
                let cut = self.revoked.contains(id)
                // A paired key's session, at either door: the pane's "last connected", and over the
                // cable the iPhone or iPad the key runs on (learned once).
                if !cut, let fp = route.fingerprint, route.pairedName != nil {
                    let words = route.label ?? Self.homeRouteWords(route, link: link)
                    self.remote?.sessionStarted(fingerprint: fp, route: words, cableDevice: route.cableDevice)
                }
                // A device got in from the network while the firewall's verdict said none could:
                // that verdict is stale (FirewallRule.asksAgain). One through a relay on this Mac came
                // from this Mac itself, as one over loopback does, which says nothing of the firewall.
                if FirewallRule.asksAgain(after: self.status.snapshot.firewall, fromLoopback: route.origin == .loopback || route.origin == .relay) {
                    self.checkFirewall()
                }
                // Home or away before its catalog: its settings state says which quality it sets.
                self.routesChanged(joined: id, endpoint: "\(connection.endpoint)")
                // A sleeping display gives black frames: the session's start wakes it, as a key would
                // (not at a locked Mac, which streams none of it: DisplayWake's gate in `deviceActive`).
                if !cut { self.deviceActive(.connect, connection) }
                // Catalog first: the client's UI needs it even if the keyframe is slow to come. A locked
                // Mac's has no windows, icons or apps from the first (the gate's reading now, LockPolicy).
                self.catalog.thumbnailsWanted = true
                self.sendCatalog(to: connection)
                self.encoder?.requestKeyframe()
            }
        }
        // A device the Mac no longer serves: from now on nothing of it lands but what lets go of what it
        // holds (RevokedInput), in the same order as its messages, which the server hands on after this.
        server.onClientRevoked = { [weak self] connection in
            Task { @MainActor in self?.clientRevoked(connection) }
        }
        // The same devices, marked as the Mac decides (RemoteAccess, on the main actor): before any of
        // their messages already waiting here, which the server's mark above would only follow.
        remote?.onCutOff = { [weak self] matching in self?.cutOff(matching) }
        // Each device's link (LinkJudge): the report its kind 16 carries, the card's row, one line.
        server.onClientLinkChanged = { [weak self] connection, verdict in
            let id = ObjectIdentifier(connection)
            Task { @MainActor in self?.linkChanged(id, verdict) }
        }
        server.onKeyframeNeeded = { [weak self] in
            // Network queue → encoder lock: the next repaint carries the keyframe, or the last frame is
            // re-encoded once the window has been still for 50 ms (HEVCEncoder.requestKeyframe).
            self?.encoderBox.current?.requestKeyframe()
        }
        server.onClientDisconnected = { [weak self] connection in
            Task { @MainActor in
                guard let self else { return }
                self.clientFPS[ObjectIdentifier(connection)] = nil
                self.fitScales[ObjectIdentifier(connection)] = nil
                self.settingsArrivals[ObjectIdentifier(connection)] = nil
                self.settingsIgnoredLineAt[ObjectIdentifier(connection)] = nil
                let id = ObjectIdentifier(connection)
                self.gestureArrivals[id] = nil
                self.keyframeRequestAt[id] = nil
                self.viewportRefusedLineAt[id] = nil
                self.viewports[id] = nil
                if self.newestViewport == id { self.newestViewport = nil }
                if self.desktopAsker == id { self.desktopAsker = nil }
                // The Virtual Desktop's matched device left: its size stays, until the device the make's rule names next
                // asks for the Desktop on it (adoptVirtualDesktopDevice), or it is made again (plan §5).
                if self.virtualDesktopNow?.device == id { self.virtualDesktopNow?.device = nil }
                if self.showVirtualDesktopTo == id { self.showVirtualDesktopTo = nil }
                self.routes[id] = nil
                self.lastPairingWanted[id] = nil
                self.connections[id] = nil
                self.appsAndIconsSent.remove(id)
                self.lastPublished[id] = nil
                self.linkReports[id] = nil
                if self.flipWait == id { self.flipWait = nil }
                self.menus.clientLeft(connection)
                self.clipboard.clientLeft(connection)
                self.displayWake.forget(id)
                // Its keys go up, and its buttons when the Mac no longer served it (`revoked`, read before
                // it is forgotten below). Its input still held for an activation is judged as a departed
                // device's from here on (`gone`: `leftWhileHeld`), and an identifier a later connection
                // takes is never revoked.
                self.releaseKeys(of: id)
                self.revoked.remove(id)
                self.status.update { $0.devices.removeAll { $0.id == id } }
                // The last device at home left devices away behind: the away quality, at once.
                let flipped = self.routesChanged(joined: nil, endpoint: nil)
                // A 120 Hz device left a 60 Hz one behind: come down to its rate. The restart takes
                // the flip too (select's commit), so a device that leaves costs one.
                if self.active != .none, self.catalog.clientCount > 1, self.streamRate(for: self.active) != self.fps {
                    await self.select(self.active)
                } else if flipped {
                    await self.applyPending()
                }
            }
        }
        server.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                guard let self else { return }
                let wasEmpty = self.catalog.clientCount == 0
                // Lock this Mac when the last device leaves: every registered session counts, and only those (a
                // pairing connection, one the device gate refuses and one an update's hold sends away never are).
                self.privacy.sessions(count)
                // SessionLock looks once a second while someone watches, and at once as the first comes.
                SessionLock.shared.devices(count)
                self.catalog.clientCount = count          // the catalog idles itself at 0
                // Nobody is watching: stop capturing and encoding. The next client picks afresh.
                // The fallback display stays between devices while no real screen works, and goes once one has
                // worked two seconds (HeadlessDesktopPolicy.Watch), devices or not; when the last leaves, after
                // `select(.none)` has stopped the capture.
                if count == 0 { self.viewport = nil; self.clientFPS = [:]; self.fitScales = [:] }   // the next device starts from scratch
                if count == 0 { self.viewports = [:]; self.newestViewport = nil; self.desktopAsker = nil }
                if count == 0 { self.gestureChords.forget() }                 // and did not open a view it could close
                // On the software encoder, the hardware is checked only while someone watches.
                if count == 0 { self.stopRecheck() } else { self.devicesPresent(firstArrived: wasEmpty) }
                // With nobody left, no window comes back at the unlock (LockPolicy.Restore).
                if count == 0 { self.restore.devicesLeft() }
                if count > 0 {
                    self.deselectWhenSettled = false
                } else if self.switching {
                    self.deselectWhenSettled = true     // `select` would refuse it now; its tail applies it
                } else {
                    if self.active != .none { await self.select(.none) }
                    if self.catalog.clientCount == 0 { self.releaseHeadlessDisplayIfDone() }
                }
                // The Virtual Desktop: shown no more once the last device left (its grace starts), or by a device that came.
                self.lookAtVirtualDesktop()
            }
        }
        cursorShapes.onChange = { [weak self] blob in
            self?.server.broadcast(StreamMessage(kind: .cursorShape, timestamp: Date().timeIntervalSince1970,
                                                 isKeyframe: false, payload: blob))
        }
        catalog.onInstalledAppsReady = { [weak self] apps in
            guard let self else { return }
            self.server.broadcast(StreamMessage(kind: .appList, timestamp: Date().timeIntervalSince1970,
                                                isKeyframe: false, payload: Wire.encode(apps)))
        }
        // Each message with the gate's reading as it arrived (the network queue's): judged by the more
        // restrictive of that and the reading when it is handled (LockPolicy.restrictive).
        server.onMessage = { [weak self] message, connection, arrived in
            Task { @MainActor in await self?.handle(message, from: connection, arrived: arrived) }
        }
        catalog.onWindowsChanged = { [weak self] infos in
            Task { @MainActor in await self?.windowsChanged(infos) }
        }
        catalog.onDesktopDisplaysChanged = { [weak self] in
            guard let self else { return }
            self.broadcastList()
            Task { @MainActor in await self.followDesktopDisplay() }
        }
        catalog.onThumbnail = { [weak self] id, jpeg in
            self?.server.broadcast(StreamMessage(kind: .thumbnail, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                                 payload: ImageBlob.encodeThumbnail(windowID: id, jpeg: jpeg)))
        }
        catalog.onNewIcon = { [weak self] id, png in
            self?.server.broadcast(StreamMessage(kind: .appIcon, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                                 payload: ImageBlob.encodeIcon(bundleID: id, png: png)))
        }
        capture.onStopped = { [weak self] error in
            print("Capture stopped: \(error.localizedDescription)")
            // A user switch takes this session's displays away before its notifications arrive (0.12 s on
            // 2026-11-01), and a device asks for the Desktop again the moment nothing streams: the lock is
            // read again first, so that pick meets the new reading (LockPolicy; the placeholder off console).
            SessionLock.shared.lookNow(cause: "the capture stopped")
            Task { @MainActor in await self?.select(.none) }
        }
        // Status for the menu bar app. The server's callbacks hop here from its network queue; the
        // stats tick runs on the main queue, which under the CLI's dispatchMain is drained by a
        // worker thread, so it hops too instead of assuming main-actor isolation (that traps).
        server.onListenerState = { [weak self] state in
            let network: HostStatusSnapshot.Network
            switch state {
            case .ready: network = .registering          // refined in `listenerChanged`
            case .waiting(let e): network = .waiting("\(e)")
            case .failed(let e): network = .failed("\(e)")
            default: return
            }
            Task { @MainActor in self?.listenerChanged(network) }
        }
        server.onServiceRegistered = { [weak self] name in
            Task { @MainActor in self?.serviceRegistered(name) }
        }
        // Display only: the menu card's word for how the device reaches this Mac.
        server.onClientRouteChanged = { [weak self] connection, route in
            let id = ObjectIdentifier(connection)
            Task { @MainActor in
                self?.status.update {
                    guard let i = $0.devices.firstIndex(where: { $0.id == id }) else { return }
                    $0.devices[i].route = route
                }
            }
        }
        // A device's hello names it before its first stats (a second later): the card shows
        // "iPad (iPad14,1)" from the first moment instead of an address. Its stats replace it, as
        // they always did; a remote device keeps its paired name meanwhile.
        server.onClientHello = { [weak self] connection, hello in
            let id = ObjectIdentifier(connection)
            // A device that shows the off-console view (docs/off-console-plan.md): its hello is read after its first
            // window list went out (the plain one: the server knew no better yet), so while the view applies it is
            // sent the view's list now (StreamServer picks it by the hello, as every list from here on).
            if (hello.offConsoleView ?? 0) >= LockedMac.viewGeneration {
                Task { @MainActor in
                    guard let self, let view = self.listMessages().view else { return }
                    self.server.send(view, to: connection)
                }
            }
            let name = SafeText.label(hello.device ?? "")
            guard !name.isEmpty else { return }
            Task { @MainActor in
                self?.status.update {
                    guard let i = $0.devices.firstIndex(where: { $0.id == id }), $0.devices[i].name == nil else { return }
                    $0.devices[i].name = name
                }
            }
        }
        server.onClientStats = { [weak self] connection, stats in
            let id = ObjectIdentifier(connection)
            // The device's own words, cleaned before the menu, Settings or a log line shows them.
            let name = SafeText.label(stats.device)
            Task { @MainActor in
                self?.status.update {
                    guard let i = $0.devices.firstIndex(where: { $0.id == id }) else { return }
                    $0.devices[i].name = name.isEmpty ? nil : name
                    $0.devices[i].fps = stats.fps
                    $0.devices[i].frameAgeMs = stats.frameAgeMs
                    $0.devices[i].rttMs = stats.rttMs
                }
                // How long this device waits for a menu (the second's worst round trip; the median
                // from an older device): a request whose turn comes later is not read.
                self?.menus.clientStats(connection, rttMs: stats.rttMaxMs ?? stats.rttMs)
            }
        }
        Stats.shared.onTick = { [weak self] counts in
            let encoded = counts["enc.out"] ?? 0
            Task { @MainActor in self?.status.update { $0.encodedFPS = encoded } }
        }
        // A check's frame came back late (on a utility queue): the encoder may not be stuck after all.
        EncoderProbe.onStalledProbeBack = { [weak self] seconds in
            Task { @MainActor in self?.stalledProbeCameBack(after: seconds) }
        }
    }

    /// How the Devices pane says a paired device last connected at home: "over the USB cable",
    /// "on this Mac", "directly" (peer-to-peer Wi-Fi), "over Wi‑Fi", "over Ethernet", else "at home".
    static func homeRouteWords(_ route: ClientRoute, link: ClientLink.Route?) -> String {
        if route.cableDevice != nil { return "over the USB cable" }
        if route.origin == .loopback { return "on this Mac" }
        switch link {
        case .direct?: return "directly"
        case .wifi?: return "over Wi\u{2011}Fi"
        case .wired?: return "over Ethernet"
        case nil: return route.origin == .direct ? "directly" : "at home"
        }
    }

    /// The listener is up, waiting or failed. Up means registering until Bonjour confirms a name,
    /// or not advertised at all in synthetic mode; a late "ready" never undoes a registered name.
    private func listenerChanged(_ network: HostStatusSnapshot.Network) {
        status.update {
            guard network == .registering else { $0.network = network; return }
            if synthetic {
                $0.network = .notAdvertised(port: Int(server.port ?? 0))
            } else if case .advertising = $0.network {
                return
            } else {
                $0.network = .registering
            }
        }
        // The listener is up, at launch or replaced (Direct Wireless): whether the macOS firewall
        // lets devices reach it.
        if network == .registering { checkFirewall() }
    }

    /// Bonjour registered this name (nil: the registration went away, to come back).
    private func serviceRegistered(_ name: String?) {
        status.update {
            if let name {
                $0.network = .advertising(name)
            } else if case .advertising = $0.network {
                $0.network = .registering
            }
        }
    }

    // MARK: The macOS firewall

    /// Asks the macOS firewall, read-only, whether it blocks this process (FirewallCheck, then
    /// FirewallRule's verdict into the status: Sill.app's Settings › General and its menu say so), and
    /// prints one line when the verdict changes (none for a first one that blocks nothing). At launch,
    /// whenever the listener comes up, when Sill.app's status menu opens (a block that came after
    /// launch; the menu is built before the answer, so its item shows from the next opening), when
    /// its Settings › General opens or Sill becomes active over it, and when a device gets in from
    /// the network while the verdict says none can; never on a timer. One check at a time: one asked
    /// for meanwhile runs once more after it, so its answer is never older than the request.
    package func checkFirewall() {
        guard !firewallChecking else { firewallAgain = true; return }
        firewallChecking = true
        let paths = firewallPaths, hook = firewallHook
        Task { @MainActor in
            let raw = await FirewallCheck.read(paths, hook: hook)
            let verdict = FirewallRule.verdict(raw, paths: paths)
            if let line = FirewallRule.Copy.logLine(from: status.snapshot.firewall, to: verdict) { print(line) }
            status.update { $0.firewall = verdict }
            firewallChecking = false
            if firewallAgain {
                firewallAgain = false
                checkFirewall()
            }
        }
    }

    /// `preselect` is the optional command-line match; without it nothing streams until a client picks.
    /// `promptForPermissions: false` (the app) asks for nothing at launch: no Accessibility alert,
    /// and no window list before Screen Recording is granted, because the first ScreenCaptureKit
    /// call raises the system's Screen Recording alert. That should follow a click in Settings or
    /// a device connecting, not a login.
    package func start(preselect: String?, promptForPermissions: Bool = true) async {
        for line in testHookLines { print(line) }
        if let line = clipboard.testHookLine { print(line) }   // TEST ONLY, and only with one of its variables set
        // TEST ONLY, on a test host with one of SessionLock's variables set.
        for line in SessionLock.testHookLines(testHost: server.isTestHost, environment: ProcessInfo.processInfo.environment) { print(line) }
        // Show this account while another user is on the screen (docs/off-console-plan.md): one line, only when on.
        if config.offConsoleView { print(LockPolicy.offConsoleViewStartLine) }
        // Lock this Mac when the last device leaves: a test host's hooks, and one line, only when on.
        for line in privacy.startLines { print(line) }
        // The guard for #380: one line, only when the last run ended while making a display.
        if let line = displayGuard?.launchLine { print(line) }
        checkFirewall()                                         // at launch, beside the listener's own check
        watchDisplayChanges()                                   // the fallback display goes when a real one is back
        watchWakes()                                            // a wake: the displays may still be changing
        watchTestHeadless()                                     // TEST ONLY: SILL_TEST_HEADLESS's changes, as macOS's
        lookAtDisplays()                                        // what the displays are now, before any change
        refreshVirtualDesktop()                                 // the Virtual Desktop's stop, and whether it can be made
        if !synthetic, promptForPermissions { InputInjector.ensureAccessibility() }   // prompts once; input is dropped silently without it
        if softwareOnly {
            // TEST ONLY: a gate that must never touch the Mac's one hardware encoder (Noah may be
            // streaming): the software encoder from the start, no probe, no re-check.
            useSoftwareEncoder = true
            status.update { $0.softwareEncoder = true }
        } else {
            // One small frame through the hardware encoder before anything streams. If the Mac's
            // hardware encoder is stuck or busy, start on the software encoder now, instead of
            // hanging the first stream for 1.5 s and restarting it; the re-check comes back to the
            // hardware once it answers.
            let hardwareResponds = await Task.detached(priority: .userInitiated) { EncoderProbe.hardwareResponds() }.value
            if !hardwareResponds { enterSoftwareFallback(afterHang: false) }
        }
        if virtualDisplay { enableVirtualDisplay() }
        // The Apps list: this Mac's own disk at once; its other volumes too once a device connects
        // (#370: macOS may ask whether Sill may read one, and nothing is asked at launch), never on a
        // test host; under the AppKit loop again as they come and go while a device is connected.
        catalog.start(volumes: !synthetic)
        if appKitLoop && !synthetic { catalog.watchVolumes() }
        // The only startup line Direct Wireless adds, and only when it is on: the default path
        // prints what it always printed.
        if config.directWireless {
            print("Direct wireless connection on: also advertised over peer-to-peer Wi-Fi (AWDL), which takes this Mac's Wi-Fi off its channel for up to ~100 ms twice a second.")
        }
        if let testMenuLine { print(testMenuLine) }   // TEST ONLY, and only with SILL_TEST_MENU_PID set
        if config.sendAudio { audio.prepare() }       // the codec, loaded before the first chunk needs it
        server.start()
        remote?.apply(config)        // the remote door, when Remote Access is on (or a pairing window opens later)
        if promptForPermissions || CGPreflightScreenCaptureAccess() { await catalog.refreshWindows() }
        if let match = preselect?.lowercased(),
           let w = catalog.infos.first(where: { $0.appName.lowercased().contains(match) || $0.title.lowercased().contains(match) }) {
            await select(.window(w.id), bringForward: true)   // a pick, made on the command line
        }
    }

    // MARK: Settings (the app's menu and Settings window, and devices through .changeSettings, on both hosts)

    /// The virtual display's parts, for the CLI's flag at launch or the app's setting turning on.
    /// The private API is checked on the first call only, printing what the CLI always printed.
    /// Every call clears a run-level disable left by repeated display losses (the app's Try
    /// Again); a missing API stays a disable for the whole run.
    private func enableVirtualDisplay() {
        if !apiChecked {
            apiChecked = true
            // Decide once whether the private API is there; a picked window falls back to plain
            // window capture (with a log line) when it is not.
            let problems = VirtualDisplay.checkPrivateAPI()
            if problems.isEmpty {
                print("Virtual display: private CGVirtualDisplay API present (\(VirtualDisplay.privateAPISurface.count) selectors); a picked window streams from its own HiDPI display.")
            } else {
                apiProblem = problems.joined(separator: "; ")
                print("Virtual display unavailable: \(apiProblem!). Streaming real windows as before.")
            }
        }
        stageLosses = 0
        stage.disabledReason = apiProblem
        status.update {
            $0.virtualDisplayProblem = apiProblem
            $0.virtualDisplayAPIMissing = apiProblem != nil
        }
    }

    /// What the host is set to: a value still waiting for its restart, else the running one. What
    /// the Mac's menu checks and what devices are told. (Private: the app merges over its own
    /// settings, never over this.)
    private var target: HostConfig { pendingConfig ?? config }

    /// Who keeps the settings when a device changes one. Sill.app lays the change over its
    /// HostSettings (saved, shown in its menu and Settings) and returns the result: over the away
    /// quality (`applyingAway`) for a device away from home (`away`), else over the home one
    /// (`applying`). Unset (the CLI): the change lands on `target` the same way and lasts until the
    /// process ends. Set it before `start`.
    package var onDeviceSettingsChange: (@MainActor (HostSettingsChange, _ away: Bool) -> HostConfig)?

    /// New settings from the app or a device, applied live. Synchronous: validated, the virtual
    /// display kept off without the AppKit loop, compared with the target, told to every device.
    /// The pipeline takes them in a Task: at once when nothing streaming depends on what changed,
    /// otherwise through one restart of the current source, `select` taking them between the old
    /// pipeline and the new one. A value that arrives mid-switch waits (select's defer comes back
    /// to `applyPending`), and a newer value replaces one still waiting, so requests that arrive
    /// out of order still converge on the last. Returns whether the target moved.
    ///
    /// Why the pipeline work is scheduled rather than awaited: the device handler must answer
    /// before any await; a burst of changes that arrives before the Task runs is one restart; and
    /// `applyPending` tolerates repeated calls (it returns while switching, and a later Task finds
    /// `pendingConfig` already consumed).
    @discardableResult
    package func setTarget(_ requested: HostConfig) -> Bool {
        guard !shuttingDown else { return false }
        var new = requested.validated()
        if !appKitLoop { new.virtualDisplay = false }
        // Share clipboard with devices, at once rather than between pipelines: off must stop what goes
        // out now, not after a restart. The lists say `clipboard` again (or no longer).
        if clipboard.setEnabled(new.shareClipboard) { broadcastList() }
        // Show this account while another user is on the screen (docs/off-console-plan.md), at once too: the
        // gate takes it now (off stops this session's pictures before the next frame), the stream follows.
        let view = lockGate.setOffConsoleView(new.offConsoleView)
        if view.was != view.now {
            print(LockPolicy.viewChangedLine(view.now))
            Task { @MainActor in await self.lockChanged() }
        }
        // Lock this Mac when the last device leaves and its two switches, at once too: off ends a wait under way now.
        privacy.switched(on: new.lockAfterSession, sleeps: new.lockSleepsDisplay, onlyAway: new.lockOnlyAfterAway)
        guard new != target else { return false }
        pendingConfig = new
        publishSettings()
        Task { @MainActor in await self.applyPending() }   // a burst before it runs is one restart
        return true
    }

    /// Takes what waits for the pipeline: settings (`pendingConfig`), and a flip between the home and
    /// the away quality (`awayWanted` against `awayRunning`) unless it waits for a joined device's
    /// first viewport (`flipWait`), which then brings both in one restart. At once when nothing
    /// streaming depends on it, else through one restart of the current source.
    private func applyPending() async {
        let flip = awayWanted != awayRunning && flipWait == nil
        guard pendingConfig != nil || flip, !switching, !shuttingDown else { return }   // select's defer calls it again
        let new = pendingConfig ?? config
        // A flip still waiting for its viewport stays out of a settings change that needs no restart;
        // a restart takes it anyway (select's commit).
        let away = flipWait == nil ? awayWanted : awayRunning
        guard restartNeeded(for: new, away: away) else { pendingConfig = nil; adopt(new, away: away); return }
        // A restart, not a pick. Turning the virtual display off still brings the staged window
        // forward as it comes home: select's commit decides that, from the value it actually takes.
        await select(active)   // committed inside select
    }

    /// Home or away (docs/remote-bundle-plan.md §5.4): a device registered (`joined`, before its
    /// catalog) or one left (nil). The away quality becomes the target once every connected device
    /// is away, the home one once any is at home; with nobody connected the flag stays (AwayPolicy).
    /// A flip prints its line; one from a device that joined waits for that device's first viewport
    /// (`flipAwaits`), one from a device that left is the caller's to apply. Returns whether it
    /// flipped.
    @discardableResult
    private func routesChanged(joined: ObjectIdentifier?, endpoint: String?) -> Bool {
        let before = awayWanted
        awayWanted = AwayPolicy.wanted(devicesAway: routes.values.map(\.isAway), current: awayWanted)
        let flipped = awayWanted != before
        if flipped {
            print(awayWanted ? AwayPolicy.awayLine(target) : AwayPolicy.homeLine(target, endpoint: endpoint ?? "a device"))
            if let joined { flipAwaits(joined) } else { flipWait = nil }
        }
        status.update { $0.away = awayWanted && !routes.isEmpty }   // publishes (status.onChange)
        return flipped
    }

    /// The flip waits for `id`'s first viewport, which carries its rate, so the two go in one
    /// restart; after a second without one (a test client) it goes alone.
    private func flipAwaits(_ id: ObjectIdentifier) {
        flipWaitToken += 1
        let token = flipWaitToken
        flipWait = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard self.flipWaitToken == token, self.flipWait == id else { return }
            self.flipWait = nil
            await self.applyPending()
        }
    }

    /// Whether the running pipeline would come out different under `new` with the home or the away
    /// quality (`away`): its rate (the devices' highest under the new limit, 60 at most on the
    /// software encoder), capture scale and bitrate (the pair `away` picks), encoder speed, or, for a
    /// window, the virtual display. The Desktop never uses the display. Direct Wireless is
    /// deliberately absent: it is the listener's (`adopt` hands it over). The capture scale is the
    /// knob's: on a 1x display Retina and Standard are one capture (CaptureScale), and a change between
    /// them still restarts once, to the same size, so the devices' links are judged afresh at a new
    /// setting as everywhere else (`judgeLinks`).
    ///
    /// A new bitrate needs a new encoder session. VideoToolbox accepts AverageBitRate on a live
    /// session and reads it back, but the hardware HEVC encoder's rate control does not follow it
    /// (measured 2026-09-25 on this M2 Pro, 1512×948 at 60 fps: raised from 8 to 40 Mbps the output
    /// stayed at 9.6 Mbps for 5 s and across a keyframe, against 28 Mbps for a session made at 40;
    /// lowered from 40 to 8 it dropped 41 of the next 60 frames). Only the software encoder and
    /// low-latency rate control follow a live change.
    private func restartNeeded(for new: HostConfig, away: Bool) -> Bool {
        guard active != .none else { return false }
        let wanted = min(new.maxFPS, max(24, clientFPS.values.max() ?? 60))
        let newFPS = streamRate(for: active, wanted: useSoftwareEncoder ? min(wanted, 60) : wanted)
        let pair = new.effective(away: away)
        let newScale = useSoftwareEncoder ? min(pair.captureScale, 1.0) : pair.captureScale
        if newFPS != fps || newScale != captureScale { return true }
        if pair.bitrate != bitrate || new.prioritizeSpeed != config.prioritizeSpeed { return true }
        if new.virtualDisplay != config.virtualDisplay, case .window = active { return true }
        return false
    }

    /// Makes `next` the running settings, and `away` the quality the pipeline runs, inside `select`
    /// or at once when nothing running depends on what changed. Logs one "Settings:" line when the
    /// settings changed; a flip alone prints nothing here (`routesChanged` said it).
    private func adopt(_ next: HostConfig, away: Bool) {
        awayRunning = away
        let old = config
        guard next != old else { return }
        config = next
        // The listener's, not the pipeline's: StreamServer replaces it and connected devices keep streaming.
        if old.directWireless != next.directWireless { server.setPeerToPeer(next.directWireless) }
        // The doors', not the pipeline's: RemoteAccess starts, stops or moves the remote door, and
        // Require pairing changes who the home door admits (and its TXT record).
        if old.remoteAccess != next.remoteAccess || old.remotePort != next.remotePort || old.internetAccess != next.internetAccess
            || old.requirePairing != next.requirePairing {
            remote?.apply(next)
        }
        if old.virtualDisplay && !next.virtualDisplay {
            stage.release()        // idempotent: select has already sent a staged window home
            status.update { $0.lastStageFailure = nil }
        }
        if !old.virtualDisplay && next.virtualDisplay { enableVirtualDisplay() }
        status.update { $0.virtualDisplayOn = next.virtualDisplay }
        print("Settings: " + old.changes(to: next))
        // The sound's own stream's, not the pipeline's: at once when nothing is switching; inside a
        // select, `active`'s didSet follows once the picture has started. Turned on, the codec loads
        // in the background, before the first chunk needs it.
        if !old.sendAudio, next.sendAudio { audio.prepare() }
        if old.sendAudio != next.sendAudio, !switching { audioFollow() }
        // A Mac with no screen's switch (Settings › Virtual Display), Sill's display's alone, never the pipeline's.
        if old.headlessDisplay != next.headlessDisplay { headlessSwitched(on: next.headlessDisplay) }
        // The Virtual Desktop's switch (Settings › Displays, the menu, a paired device): its stop and its display, at once.
        if old.virtualDesktop != next.virtualDesktop { virtualDesktopSwitched(on: next.virtualDesktop) }
    }

    /// The person turned "Make a display when this Mac has no screen" off or on (HostConfig.headlessDisplay; Sill.app's
    /// alone at run time). Off: Sill's display goes at once, and a Desktop on it starts again on what macOS shows
    /// (`removeHeadlessAtOnce`). On: a Desktop streaming with no real screen and no Sill's display asks again, so it is
    /// made as `Watch` says, as after Try Again. A switch under way first, at most 5 s.
    private func headlessSwitched(on: Bool) {
        saidSwitchedOff = false
        Task { @MainActor in
            guard on else {
                await self.removeHeadlessAtOnce(line: HeadlessDesktopPolicy.switchedOffRemovedLine) { !self.config.headlessDisplay }
                return
            }
            for _ in 0..<100 where self.switching { try? await Task.sleep(for: .milliseconds(50)) }
            guard self.config.headlessDisplay, self.active == .desktop, !self.switching, !self.shuttingDown,
                  !self.hasHeadlessDisplay, !self.releasingHeadless else { return }
            self.lookAtDisplays()
            guard self.displayWatch.real == 0, self.headlessGateAllows() else { return }
            await self.select(.desktop)
        }
    }

    /// Settings › Virtual Display › Try Again: clear a run-level disable, and stage the streamed
    /// window again.
    package func retryVirtualDisplay() async {
        enableVirtualDisplay()
        if virtualDisplay, case .window = active { await select(active) }
    }

    /// The app keeps running when the Bonjour listener fails, with the failure in its menu; the
    /// CLI exits as it always has. Call before `start`.
    package func keepRunningOnListenerFailure() {
        server.onListenerFailed = { [weak self] error in
            Task { @MainActor in self?.status.update { $0.network = .failed("\(error)") } }
        }
    }

    /// Windows in the catalog's last look, for the CLI's startup line.
    package var windowCount: Int { catalog.infos.count }

    /// A window is staged on the virtual display and in a full-screen Space there. The app's Quit
    /// takes it out of full screen first (`beginLeavingFullScreenForQuit`), or it cannot go home.
    package var stagedWindowIsFullScreen: Bool {
        guard let p = stage.placement else { return false }
        return WindowSizer.isFullScreen(p.element)
    }

    /// Presses the staged window's full-screen button; the app's Quit then waits for
    /// `stagedWindowSettled`.
    package func beginLeavingFullScreenForQuit() {
        guard let p = stage.placement else { return }
        _ = WindowSizer.perform(.fullScreen, element: p.element)
    }

    /// The staged window (if any) is out of full screen and back on a window list, so it can be
    /// put back where it was. Leaving full screen, a window is off every list for about a second;
    /// the same test as `VirtualStage.leaveFullScreenIfNeeded`.
    package var stagedWindowSettled: Bool {
        guard let p = stage.placement else { return true }
        return !WindowSizer.isFullScreen(p.element) && WindowSizer.liveBounds(of: p.windowID) != nil
    }

    /// Whether `id` is one of Sill's virtual displays (the stage's or the Desktop's), which the app keeps its own
    /// windows off. Sill's display rules tell the two apart by role (WindowCatalog.headlessKind, DesktopDisplays.role).
    package nonisolated static func isSillVirtualDisplay(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == VirtualStage.vendorID
    }

    /// Sill's display for the Desktop when no real screen is online (a closed lid and no monitor, a headless Mac; issue
    /// #61; a monitor asleep counts: HeadlessDesktopPolicy.realDisplays), made only once the displays have settled and
    /// while the screens are awake: HeadlessDesktopPolicy.Watch says when, and this looks again then
    /// (`headlessDisplaySettled`), making it on that look alone. Returns at once while a real screen is there.
    private func ensureHeadlessDisplayIfNeeded() async {
        lookAtDisplays()
        // The lid closed and the monitors asleep, not gone (macOS's display sleep): they count as real screens, and a
        // person's tap on a device wakes them (DisplayWake). 0.6.1 (1414) made Sill's display here; one line says
        // what is done instead, once until a real display works again.
        if !saidAsleepNotGone, let seen = lastDisplaysSeen,
           let asleep = HeadlessDesktopPolicy.asleepNotGone(lidClosed: seen.lidClosed, online: seen.online, active: seen.active),
           headlessGateAllows(screens: false) {
            print(HeadlessDesktopPolicy.asleepNotGoneLine(asleep: asleep))
            saidAsleepNotGone = true
        }
        guard displayWatch.real == 0, headlessGateAllows() else {
            // No real screen, and only the person's switch (Settings › Virtual Display, --no-headless-display), or the
            // guard for #380, keeps Sill's display from being made: one line, the switch's until it is turned on again,
            // the guard's once a run.
            if displayWatch.real == 0, !config.headlessDisplay {
                if !saidSwitchedOff, headlessGateAllows(guardHolds: false, switchOn: true) {
                    print(HeadlessDesktopPolicy.switchedOffLine)
                    saidSwitchedOff = true
                }
            } else if displayWatch.real == 0, displayGuard?.holds == true, !saidGuardHolds, headlessGateAllows(guardHolds: false) {
                print(DisplayMakeGuard.headlessHeldLine)
                saidGuardHolds = true
            }
            return
        }
        // The system removed it on its own (sleep and wake can, as VirtualStage's `onLost` knows): made again, not
        // kept as a display that is no longer there, with the Desktop on macOS's stand-in until Sill quits.
        if let d = headlessDisplay, CGDisplayIsOnline(d.displayID) == 0 {
            print("Headless display: the virtual Desktop display (id \(d.displayID)) is gone; making it again.")
            displays.remove(.desktop)
            desktopLife.removed(at: CFAbsoluteTimeGetCurrent())
            headlessHz = nil
            status.update { $0.sillDisplay = nil }
        }
        if !hasHeadlessDisplay {
            guard await headlessDisplaySettled() else { return }
            // The device's size and refresh rate (Noah, 2026-11-18): the device that asked for the Desktop, else the one
            // whose viewport came last, else #200's 1920×1080 at 60 (VirtualDesktopSize). Decided here, once: never
            // resized while it is the Mac's only display (phase 2b follows a device's turn, in place and unlocked).
            let matched = VirtualDesktopSize.matched(asker: desktopAsker, newest: newestViewport, sent: Set(viewports.keys))
            let vp = matched.flatMap { viewports[$0] }
            let asked = VirtualDesktopSize.device(space: vp.map(Self.space)) ?? VirtualDesktopSize.fallback
            let hz = VirtualDesktopSize.rate(viewportFPS: vp?.fps, limit: maxFPS)
            let device = vp == nil ? nil : matched.map { deviceName(id: $0) }
            // The guard's marker from just before the private calls until the display is up or failed (#380; SillDisplays:
            // `make`'s throw, `waitUntilOnline`, a test host's `say`).
            displays.willMake(.desktop)
            if testHeadlessFile != nil {
                // TEST ONLY: said, never made (SillDisplays.say); listed as Sill's from now on (`displaysNow`), at the size and
                // rate a Mac's would be asked for.
                displays.say(.desktop)
                desktopLife.made(.headless, at: CFAbsoluteTimeGetCurrent())   // a change of the Desktop's display, for the spacing
                headlessHz = Double(hz)
                catalog.keepsSills = true
                print(VirtualDesktopSize.createdLine(came: asked, asked: asked, hz: hz, id: nil, device: device))
                status.update { $0.sillDisplay = HostStatusSnapshot.SillDisplay(widthPt: asked.widthPt, heightPt: asked.heightPt, scale: asked.scale, hz: hz, device: device) }
                lookAtDisplays(changed: true)
                return
            }
            let d: VirtualDisplay
            do {
                // Made where every display of Sill's is (SillDisplays): the Desktop's identity ("Sill Desktop", 0x5111,
                // 0x0002, serial 2: DesktopDisplays.role's `.sillDesktop`).
                d = try displays.make(.desktop, widthPt: asked.widthPt, heightPt: asked.heightPt, scale: asked.scale,
                                      refreshHz: Double(hz))
            } catch {
                print("Headless display: could not create virtual display (\(error)).")
                return
            }
            desktopLife.made(.headless, at: CFAbsoluteTimeGetCurrent())   // a change of the Desktop's display, for the spacing
            catalog.keepsSills = true
            _ = await displays.waitUntilOnline(d, timeout: 3)
            // Removed meanwhile (its switch turned off, this session off the console, Quit): SillDisplays destroyed it at
            // once, and the line that removed it said so.
            guard headlessDisplay === d else { return }
            let b = d.bounds
            guard b.width > 0 else {
                // It never came up: nothing to show on it. Removed; the Desktop stays on what macOS shows.
                displays.remove(.desktop)
                desktopLife.removed(at: CFAbsoluteTimeGetCurrent())
                catalog.keepsSills = false
                print("Headless display: it never came up (asked \(asked.widthPt)×\(asked.heightPt) @\(asked.scale)× at \(hz) Hz); removed it.")
                return
            }
            // The mode it came up at, not the one asked for (the stage's rule since 2026-10-27; #200's line said "@2×"
            // whatever macOS made it), and the rate it reads, which the Desktop's rate is held to.
            let came = VirtualDesktopSize.Size(widthPt: Int(b.width), heightPt: Int(b.height), scale: d.currentScale)
            let cameHz = CGDisplayCopyDisplayMode(d.displayID).map { Int($0.refreshRate.rounded()) }.flatMap { $0 > 0 ? $0 : nil } ?? hz
            headlessHz = Double(cameHz)
            print(VirtualDesktopSize.createdLine(came: came, asked: asked, hz: cameHz, id: d.displayID, device: device))
            status.update { $0.sillDisplay = HostStatusSnapshot.SillDisplay(widthPt: came.widthPt, heightPt: came.heightPt, scale: came.scale, hz: cameHz, device: device) }
        }
        guard headlessDisplay != nil else { return }      // a test host's said display has no look to wait for
        // Until the catalog's look has it (macOS's stand-in may still be listed beside it).
        let made = headlessDisplay?.displayID
        let onIt = { [catalog] in made != nil && catalog.display?.displayID == made }
        let deadline = Date().addingTimeInterval(3)
        while !onIt(), Date() < deadline {
            await catalog.refreshWindows()
            if onIt() { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Waits as `Watch.make` says and looks again each time it said to: true when Sill's display is to be made on the
    /// look just taken, false once a real screen works again, the screens sleep (the wake asks again:
    /// `screensWoke`) or the gate closed meanwhile (the last device left, this session off the console). The first
    /// answer is a wait, of a second at least, so the display is never made on the look that first wanted it. Inside
    /// the Desktop's `select`: three seconds at most (`settleCap`).
    private func headlessDisplaySettled() async -> Bool {
        let wanted = CFAbsoluteTimeGetCurrent()
        var waited = false
        while true {
            switch displayWatch.make(wantedSince: wanted, now: CFAbsoluteTimeGetCurrent()) {
            case .no:
                if waited { print("Headless display: a real screen works again; none made.") }
                return false
            case .asleep:
                if !saidWaitsForWake { print(HeadlessDesktopPolicy.waitsForWakeLine); saidWaitsForWake = true }
                return false
            case .make:
                return true
            case .wait(let until):
                let wait = max(0, until - CFAbsoluteTimeGetCurrent())
                if !waited { print("Headless display: no real screen; looking again in \(String(format: "%.1f", wait)) s before making one.") }
                waited = true
                try? await Task.sleep(for: .seconds(wait))
                guard !shuttingDown else { return false }
                lookAtDisplays()
                // A real screen back: the rule's own `.no` next, with its line. Else the gate again (the last device
                // left, this session off the console).
                guard displayWatch.real > 0 || headlessGateAllows() else { return false }
            }
        }
    }

    /// What `needsVirtualDesktop` asks of this host now, from the watch's last look (`screens`: whether a real screen
    /// counts as there; `false` asks what it would say with none; `guardHolds` and `switchOn` likewise, for the lines that
    /// say which keeps it from being made). A test host with SILL_TEST_HEADLESS stands in for a Mac with an AppKit loop,
    /// the private API and Screen Recording: it makes no display, only says so.
    private func headlessGateAllows(screens: Bool? = nil, guardHolds: Bool? = nil, switchOn: Bool? = nil) -> Bool {
        let scripted = testHeadlessFile != nil
        return HeadlessDesktopPolicy.needsVirtualDesktop(
            hasDisplay: screens ?? (displayWatch.real > 0),
            clientCount: catalog.clientCount,
            appKitLoop: appKitLoop || scripted,
            synthetic: synthetic && !scripted,
            apiAvailable: scripted || VirtualDisplay.checkPrivateAPI().isEmpty,
            screenRecording: scripted || CGPreflightScreenCaptureAccess(),  // never a display without it (VirtualStage.prepare's rule)
            onConsole: LockPolicy.makesDesktopDisplay(lockReading),         // locked too (#298); never off console
            guardHolds: guardHolds ?? (displayGuard?.holds ?? false),       // two runs in a row ended making one (#380)
            switchOn: switchOn ?? config.headlessDisplay                    // the person's switch, on by default
        )
    }

    /// A device's name as the card has it (its ClientStats), for Sill's display's line; "a device" before it said.
    private func deviceName(id: ObjectIdentifier) -> String {
        status.snapshot.devices.first { $0.id == id }?.name ?? "a device"
    }

    /// The Desktop's rate on the display it streams, judged once that display is known (a look during the awaits can
    /// have moved it to a stop of another rate, or onto Sill's own display just made): the stop's refresh rate, else
    /// Sill's display's while the Desktop is on it (VirtualDesktopSize.refreshHeld); judged at the rate it runs.
    private func holdDesktopRate(onDisplay id: UInt32?) {
        let stop = catalog.desktopCandidates.first { $0.id == id }?.refreshHz
        let rate = DesktopDisplays.rate(effectiveFPS, refreshHz: VirtualDesktopSize.refreshHeld(stop: stop, sills: headlessHz,
                                                                                                    onSills: desktopOnSills(id)))
        if rate != fps {
            fps = rate
            judgeLinks(LinkJudge.Quality(bitrate: bitrate, fps: fps, captureScale: Double(captureScale)))
        }
    }

    /// Try Again, from Settings › Virtual Display while the guard for #380 holds: Sill makes its displays again, and a
    /// Desktop streaming with no real screen asks for Sill's display at once.
    package func tryDisplaysAgain() {
        guard let displayGuard, displayGuard.holds else { return }
        displayGuard.tryAgain()
        saidGuardHolds = false
        print(DisplayMakeGuard.tryAgainLine)
        status.update { $0.displayMakeHeld = false }
        refreshVirtualDesktop()          // the Virtual Desktop's stop back in the cycle, when its switch is on
        guard active == .desktop, !switching, !shuttingDown else { return }
        Task { @MainActor in
            self.lookAtDisplays()
            guard self.displayWatch.real == 0, self.active == .desktop, !self.switching else { return }
            await self.select(.desktop)
        }
    }

    /// A look at the displays, for the watch (HeadlessDesktopPolicy.Watch): `changed` when macOS said the
    /// configuration changed (its callback, or a TEST ONLY file's change). A look that finds the screens awake after
    /// asleep is their wake (`screensWoke`).
    private func lookAtDisplays(changed: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        if changed { displayWatch.changed(at: now) }
        let seen = displaysNow()
        lastDisplaysSeen = (seen.active, seen.online, seen.lidClosed)
        if seen.active > 0 { screensSaidAsleep = false; saidAsleepNotGone = false }   // a real display works: awake
        let wasAsleep = displayWatch.asleep
        displayWatch.saw(real: seen.real, list: seen.list, asleep: seen.asleep, at: now)
        if wasAsleep, !displayWatch.asleep { screensWoke() }
    }

    /// The real screens as `HeadlessDesktopPolicy.realDisplays` counts them (macOS's stand-in and Sill's own are
    /// none; an asleep one counts), whether the screens sleep (`screensAsleep`: what macOS said, and no real display or
    /// stand-in working), the real ones active and online and the lid, and the whole list (each display's ID, kind and
    /// state). A test host with SILL_TEST_HEADLESS reads its file instead, with the display it said it made as Sill's.
    private func displaysNow() -> (real: Int, list: [String], asleep: Bool, active: Int, online: Int, lidClosed: Bool) {
        if let path = testHeadlessFile {
            let scripted = HeadlessDesktopPolicy.testHeadlessList((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
            let displays = scripted.displays + (testHeadlessMade ? [HeadlessDesktopPolicy.TestDisplay(kind: .sills, active: true)] : [])
            let real = displays.filter { $0.kind == .real }
            let active = real.filter(\.active).count
            let working = scripted.displays.filter { $0.active && $0.kind != .sills }.count
            let count = HeadlessDesktopPolicy.realDisplays(active: active, online: real.count, lidClosed: scripted.lidClosed)
            return (count, displays.enumerated().map { "\($0.offset):\($0.element.kind):\($0.element.active ? "active" : "asleep")" },
                    HeadlessDesktopPolicy.screensAsleep(said: screensSaidAsleep, active: working), active, real.count,
                    scripted.lidClosed)
        }
        let online = WindowCatalog.onlineDisplayIDs()
        let active = WindowCatalog.activeDisplayIDs()
        // By role (WindowCatalog.headlessKind): the stage's display and Sill's own are no screen, and an ID listed
        // online is there now.
        let kind = { (id: UInt32) in HeadlessDesktopPolicy.kind(self.catalog.role(of: id), online: true) }
        let real = { (ids: [UInt32]) in ids.filter { kind($0) == .real }.count }
        let working = active.filter { [.real, .standIn].contains(kind($0)) }.count     // the real ones and macOS's stand-in
        let lidClosed = WindowCatalog.lidClosed()
        let count = HeadlessDesktopPolicy.realDisplays(active: real(active), online: real(online), lidClosed: lidClosed)
        let list = online.map { id in
            "\(id):\(kind(id)):\(active.contains(id) ? "active" : CGDisplayIsAsleep(id) != 0 ? "asleep" : "online")"
        }.sorted()
        return (count, list, HeadlessDesktopPolicy.screensAsleep(said: screensSaidAsleep, active: working), real(active),
                real(online), lidClosed)
    }

    /// A person at a device had activity declared (DisplayWake: a connect, a tap, a key…; a test host's count), which
    /// wakes the screens: if macOS last said they slept, this is their wake, two seconds from now (`Watch.cameBack`),
    /// and a look finds it (`screensWoke`), so Sill's display, which waited for it, is made then if no real screen came
    /// back. Nothing when macOS said nothing: an awake Mac's timings are as before.
    private func personDeclared() {
        guard screensSaidAsleep else { return }
        screensSaidAsleep = false
        displayWatch.cameBack(at: CFAbsoluteTimeGetCurrent())
        lookAtDisplays()
    }

    // MARK: Each device's link (docs/remote-bundle-plan.md §6)

    /// The stream's quality as `select` commits it (nil: nothing streams). The devices' links are
    /// judged afresh when it changes (LinkJudge.judgedAfresh: another bitrate, rate or resolution, or
    /// no stream), and keep their judgement through a restart that keeps it, so a device's report,
    /// line and callout neither go nor come back for a window picked or a rotation.
    private func judgeLinks(_ quality: LinkJudge.Quality?) {
        if LinkJudge.judgedAfresh(from: judgedQuality, to: quality) { server.resetLinks() }
        judgedQuality = quality
    }

    /// A device's link changed: behind or stalled becomes its report (the running quality, what was
    /// withheld, the carried rate and what would fit at the running pair and the stream's rate), a
    /// line when the state is new, and the card's row; a report that only moves the carried rate
    /// prints nothing, and changes nothing unless it changes the suggestion; fine clears it, with
    /// "keeping up again" only for a judged recovery, never for a restart's reset. The snapshot
    /// change publishes, and each connection's state carries its own.
    private func linkChanged(_ id: ObjectIdentifier, _ v: LinkJudge.Verdict) {
        guard routes[id] != nil else { return }       // gone meanwhile
        let device = status.snapshot.devices.first { $0.id == id }
        let who = device?.name ?? device?.endpoint ?? "a device"
        switch v.state {
        case .fine:
            let had = linkReports.removeValue(forKey: id) != nil
            status.update {
                guard let i = $0.devices.firstIndex(where: { $0.id == id }) else { return }
                $0.devices[i].link = nil
            }
            if had, !v.reset { print(LinkJudge.fineLine(device: who)) }
        case .behind, .stalled:
            let behind = v.state == .behind
            let fps = status.snapshot.stream?.fps ?? self.fps
            // Against what the capture runs at: on a 1x display Standard would change nothing.
            let suggestion = LinkJudge.suggestion(carriedKbps: v.carriedKbps, bitrate: bitrate, fps: fps, captureScale: Double(streamPixelScale))
            let report = LinkReport(state: behind ? LinkReport.behind : LinkReport.stalled, withheldPerSecond: v.withheld,
                                    bitrate: bitrate, carriedKbps: v.carriedKbps,
                                    suggestedBitrate: suggestion?.bitrate, suggestedCaptureScale: suggestion?.captureScale)
            let previous = linkReports[id]
            // The same state with the same suggestion (the judge reporting its rate as it moves): the
            // device and the card have nothing new to show, so nothing is published.
            if let previous, previous.state == report.state, previous.suggestedBitrate == report.suggestedBitrate,
               previous.suggestedCaptureScale == report.suggestedCaptureScale { return }
            linkReports[id] = report
            let shown = HostStatusSnapshot.LinkStatus(state: behind ? .behind : .stalled, withheld: v.withheld, bitrate: bitrate,
                                                      carriedKbps: v.carriedKbps, suggestedBitrate: suggestion?.bitrate,
                                                      suggestedCaptureScale: suggestion?.captureScale)
            status.update {
                guard let i = $0.devices.firstIndex(where: { $0.id == id }) else { return }
                $0.devices[i].link = shown
            }
            guard previous?.state != report.state else { return }
            print(behind ? LinkJudge.behindLine(device: who, bitrate: bitrate, withheld: v.withheld, offered: v.offered,
                                                carriedKbps: v.carriedKbps, suggestion: suggestion)
                         : LinkJudge.stalledLine(device: who, waiting: v.waiting))
        }
    }

    // MARK: Client messages

    /// `arrived`: the lock's reading as the network queue read the message (StreamServer.onMessage).
    private func handle(_ message: StreamMessage, from connection: NWConnection, arrived: LockPolicy.Reading) async {
        // Input decoded once, for the display's rule and for its case below.
        let input = message.kind == .input ? Wire.decode(InputEvent.self, from: message.payload) : nil
        // A device the Mac no longer serves (`revoked`): only the up of a key or a button it holds down
        // on the Mac still goes, where the pointer is; nothing else of it acts, wakes the display or
        // raises a window. Its connection closes within 0.25 s.
        let sender = ObjectIdentifier(connection)
        if revoked.contains(sender) {
            if let input, injector.releasesWhatItHolds(input, from: sender) {
                deliver(input, in: .null, from: sender)
            } else if message.kind == .input || message.kind == .gesture {
                Stats.shared.bump("in.revoked")
            }
            return
        }
        // A locked Mac (LockPolicy, docs/locked-mac-plan.md), judged by the more restrictive of the gate's
        // reading as the message arrived and now, so nothing sent while the Mac read locked acts after an
        // unlock: a window picked, an app launched, a window's buttons, a menu fetched or chosen, a gesture
        // and a device's clipboard text are refused; input lands only from whom the reading lets type (a
        // paired session at a locked screen, nobody off console), and from any other only the up of what
        // it holds down, where the pointer is. What the lock refuses wakes nothing either.
        let reading = LockPolicy.restrictive(arrived, lockReading)
        switch lockDecision(message, input: input, from: sender, arrived: arrived) {
        case .take:
            break
        case .letGo:
            if let input { deliver(input, in: .null, from: sender) }
            return
        case .refuse(let why):
            refusedWhileLocked(why, message, from: connection)
            return
        }
        // A press on a display that reads asleep wakes it and goes no further, nor does its release
        // (DisplayWake.pass, PR #228): a tap on a black picture clicks nothing out of sight. Only input the
        // lock took gets here, so what the lock refuses or lets go is never held back.
        let passed = input.map { event in
            displayWake.pass(event, from: sender, at: CFAbsoluteTimeGetCurrent(),
                             asleep: { pressLandsAsleep(event) })
        }
        if passed?.waking == true { Stats.shared.bump(DisplayWake.heldKey) }
        // Every message goes to DisplayWake, which alone says which of them is a person at the device
        // (a pick never is: the device asks for the Desktop by itself), issue #134; a press held back
        // declares at once; at the lock's reading.
        deviceActive(passed?.waking == true ? .wakingPress : .message(message.kind, input), connection, reading: reading)
        switch message.kind {
        case .selectSource:
            guard let source = Wire.decode(StreamSource.self, from: message.payload) else { return }
            // A window picked comes forward on the Mac, which closes a view a gesture opened; the
            // Desktop picked (as a device does before a gesture made over a window) leaves it.
            if case .window = source { gestureChords.forget() }
            // The Desktop asked by this device: Sill's own display, if one is made for it, is this device's size.
            if source == .desktop { desktopAsker = ObjectIdentifier(connection) }
            // A pick from the device's switcher, or the device's own request (StreamClient's window
            // list: the Desktop at a connection's start or once the Mac stopped it, and after a move
            // what it watched, the Desktop or a window).
            await handlePick(source)
        case .nextDisplay:
            // The Desktop button tapped while the Desktop streams (DesktopDisplays). A synthetic host's
            // Desktop is the test pattern, which has stops only under SILL_TEST_DISPLAYS.
            guard !synthetic || catalog.testDisplays != nil else { return }
            desktopAsker = ObjectIdentifier(connection)
            await nextDesktopDisplay(askedBy: deviceName(connection))
        case .windowCommand:
            // The bar's long-press menu: the window's own traffic lights, pressed through
            // Accessibility. The staged window's element is already matched; others are looked up.
            guard let cmd = Wire.decode(WindowCommand.self, from: message.payload) else { return }
            gestureChords.forget()              // a window's own button: a view a gesture opened is left behind
            let outcome: WindowSizer.CommandOutcome
            if virtualDisplay, let p = stage.placement, p.windowID == cmd.id {
                outcome = WindowSizer.perform(cmd.action, element: p.element)
            } else if let w = catalog.window(id: cmd.id) {
                outcome = sizer.perform(cmd.action, on: w)
            } else {
                outcome = .refused
            }
            print("Window \(cmd.id) \(cmd.action.rawValue): \(outcome.words(for: cmd.action))")
            Stats.shared.bump("win.\(cmd.action.rawValue)")
            await catalog.refreshWindows()      // show the result now, not at the next poll
        case .launchApp:
            // Launch Services' copy of the app, as always; else the one the Apps list found, such as an
            // app on another disk Launch Services never registered (#370).
            guard let req = Wire.decode(LaunchApp.self, from: message.payload),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: req.bundleID)
                    ?? catalog.installedAppURL(for: req.bundleID) else { return }
            gestureChords.forget()              // the app comes forward, which closes a view a gesture opened
            pendingLaunch = req.bundleID
            let config = NSWorkspace.OpenConfiguration()
            // The launch itself takes no focus on the Mac. Its first window is then picked for the
            // device (`windowsChanged`), which in regular mode brings it forward like any pick.
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { print("Launch failed: \(error.localizedDescription)") }
            }
        case .input:
            guard let event = passed?.event else { return }     // it does not decode, or a release held back
            let device = ObjectIdentifier(connection)
            guard let rect = currentSourceRect() else {
                // Nothing streams (between sources, or the stream stopped: the window closed under a
                // drag): input has nowhere to land. The up of a key or a button the Mac has down still
                // goes (DroppedInput), a button's where the pointer is (`.null`), so no modifier this
                // device pressed stays down to make a later click a ⌘-click, and no button to make
                // every later move a drag. A held key no longer repeats (KeyRepeat).
                injector.stopRepeating()
                if injector.isUpOfSomethingDown(event) { deliver(event, in: .null, from: device) }
                return
            }
            // A click, a key or text may close a view a gesture opened; a move or a scroll does not.
            gestureChords.input(Self.gestureInput(event))
            // A synthetic host acts on nothing: it posts no event (InputInjector.dryRun), so it
            // activates and raises nothing either.
            if !synthetic { raiseIfInteracting(event) }
            deliver(event, in: rect, from: device)
            desktopInputMayActivate(event)
        case .gesture:
            // A three- or four-finger gesture (docs/trackpad-gestures-plan.md §7.4), which the Mac
            // turns into its own shortcut. At most `gesturesPerSecond` a second per connection: a
            // stroke makes one, so more is a runaway or hostile client.
            guard let gesture = Wire.decode(TrackpadGesture.self, from: message.payload) else { return }
            let id = ObjectIdentifier(connection)
            let now = CFAbsoluteTimeGetCurrent()
            var recent = (gestureArrivals[id] ?? []).filter { now - $0 < 1 }
            guard recent.count < Self.gesturesPerSecond else {
                gestureArrivals[id] = recent
                gestureDrops.count("gestures")
                return
            }
            recent.append(now)
            gestureArrivals[id] = recent
            queueGesture(gesture, from: deviceName(connection), id: id)
        case .keyframeRequest:
            // A device's picture was interrupted (its display layer failed, or iOS stopped it while
            // Sill was away) and waits for a keyframe, which a still window never sends. The encoder
            // makes one from the next repaint, or encodes a still window's last frame again
            // (HEVCEncoder.requestKeyframe); every device gets it, as when a device joins. Never a
            // restart or a pick: nothing else streams again and no window comes forward.
            let id = ObjectIdentifier(connection)
            let now = CFAbsoluteTimeGetCurrent()
            if let last = keyframeRequestAt[id], now >= last, now - last < Self.keyframeRequestSpacing {
                keyframeRequestDrops.count("keyframes")
                return
            }
            keyframeRequestAt[id] = now
            if keyframeRequestsToIgnore > 0 {      // TEST ONLY: SILL_TEST_KEYFRAME_IGNORE
                keyframeRequestsToIgnore -= 1
                print("Test keyframes: ignored a keyframe request from \(deviceName(connection)) (\(keyframeRequestsToIgnore) more to ignore).")
                return
            }
            guard active != .none, let encoder else { return }     // nothing streams: the next stream starts with one
            print("Keyframe for \(deviceName(connection)): its picture was interrupted.")
            encoder.requestKeyframe()
        case .viewport:
            // A device's panel and text scale. One outside what a host takes (ViewportBounds), or a
            // payload that does not decode, is refused whole, with a line: the last viewport stands and
            // nothing of the message is taken, its rate neither. Until 2026-10-29 a side of 1e300 points
            // reached the window's fit and the virtual display's window size, whose lines trapped in
            // Int(), and the host died with every device's session (security scan, finding 4).
            guard let v = Wire.decode(Viewport.self, from: message.payload) else {
                refuseViewport("it does not decode as a viewport", from: connection)
                return
            }
            if let why = ViewportBounds.refusal(v) {
                refuseViewport(why, from: connection)
                return
            }
            let id = ObjectIdentifier(connection)
            // Aa set to Off by the device that had fitted a window: the windows Sill sized go back to
            // their own frames now, as when they stop streaming, not at the end of the session (#179).
            // Per connection: another device's viewport without a scale ends nobody's fit.
            let previousScale = fitScales[id]
            fitScales[id] = v.scale
            var restored = false
            if TextScale.endsFit(from: previousScale, to: v.scale) {
                Stats.shared.bump("win.fitOff")
                restored = restoreFits(keeping: nil)
            }
            viewport = v
            let before = viewports[id]
            viewports[id] = v; newestViewport = id      // Sill's own display is sized to a device's (VirtualDesktopSize)
            virtualDesktopViewport(v, before: before, from: id)   // the Virtual Desktop follows its matched device's space (rule A)
            clientFPS[id] = v.fps ?? 60
            // The flip its connection made waited for this, its rate (`flipAwaits`): the restart the
            // rate needs takes the flip too, and the flip alone restarts once when the rate needs none.
            let flipWaited = flipWait == id
            if flipWaited { flipWait = nil }
            if switching { viewportArrivedWhileSwitching = true; return }   // select's defer applies both
            // The streamed window went back to its own size: the stream restarts at it now, as after a
            // fit (`applyViewportToActiveWindow`), not at the catalog's next look up to 2 s later.
            if restored { await catalog.refreshWindows() }
            await applyViewportToActiveWindow()
            if flipWaited { await applyPending() }
        case .pairingWanted:
            // "Show your pairing code" (Pair This iPad…): only from a device near the Mac (the home
            // door, from loopback, this network or peer-to-peer Wi-Fi), once per 30 s per connection.
            // At a TLS home door only from an unpaired session (Require pairing off), which goes
            // through the ask rule; a paired session's is ignored.
            let id = ObjectIdentifier(connection)
            guard let remote, case .home(let origin, let peer)? = routes[id], [.loopback, .lan, .direct].contains(origin) else { return }
            if server.homeTLS, peer.map({ remote.isPaired($0.fingerprint) }) ?? true { return }
            let now = CFAbsoluteTimeGetCurrent()
            if let last = lastPairingWanted[id], now - last < 30 { return }
            lastPairingWanted[id] = now
            var session: (fingerprint: Data, source: String, display: String, from: String, fromThisMac: Bool)?
            if server.homeTLS, let peer, let s = Door.source(of: connection) {
                let thisMac = DoorPolicy.isFromThisMac(source: s.bytes, ownAddresses: InterfaceSnapshot.ownAddresses())
                let source: String
                if case .hostPort(let host, _) = connection.endpoint { source = StreamServer.addressText(host).text } else { source = s.display }
                session = (peer.fingerprint, source, s.display,
                           origin == .direct ? "nearby" : (thisMac || origin == .loopback ? "on this Mac" : "on this network"), thisMac)
            }
            remote.pairingWanted(by: deviceName(connection), session: session)
        case .changeSettings:
            // A device's settings control. No `await` in this case: the answer leaves in request
            // order, per device and across devices, and before any restart (setTarget schedules the
            // pipeline work). Malformed JSON has no token to answer, so it gets nothing.
            guard let change = Wire.decode(HostSettingsChange.self, from: message.payload) else { return }
            let who = deviceName(connection)
            // At most `settingsPerSecond` changes a second per connection: a panel's control sends
            // one per tap, so more is a runaway or hostile client, and each could cost a restart.
            // The excess applies nothing and is answered with the state as it stands, so the
            // device's ledger still hears back.
            let id = ObjectIdentifier(connection)
            let now = CFAbsoluteTimeGetCurrent()
            var recent = (settingsArrivals[id] ?? []).filter { now - $0 < 1 }
            if recent.count >= Self.settingsPerSecond {
                settingsArrivals[id] = recent
                if now - (settingsIgnoredLineAt[id] ?? 0) >= 1 {
                    settingsIgnoredLineAt[id] = now
                    print("Settings from \(who) ignored: more than \(Self.settingsPerSecond) changes a second.")
                }
                server.send(settingsMessage(settingsState(for: id, answering: change.token)), to: connection)
                return
            }
            recent.append(now)
            settingsArrivals[id] = recent
            // A connection whose route is not known (never: it is set before any message is
            // handled) counts as remote and unpaired, so nothing it sends can widen exposure. Paired:
            // its key on the trust list as the Mac's status has it now (`sessionPaired`).
            // The Virtual Desktop: an "on" only while this Mac can make it now (VirtualDesktopWords.note: the private API, the
            // AppKit loop, Screen Recording, the console, the guard for #380), from a paired session alone.
            refreshVirtualDesktop()
            let (ok, refused) = DeviceSettings.accepted(change, virtualDisplayAvailable: appKitLoop,
                                                        virtualDesktopAvailable: status.snapshot.virtualDesktop.available,
                                                        fromRemote: routes[id].map { $0.isRemote } ?? true,
                                                        paired: sessionPaired(id))
            if !refused.isEmpty { print("Settings from \(who) refused: \(refused.joined(separator: ", "))") }
            if !ok.isEmpty, !shuttingDown {
                let before = target
                // A device away from home sets the away quality, never the home one (§5.1).
                let away = routes[id]?.isAway ?? false
                // The Virtual Desktop turned on from this device: shown to it at once, once its switch is taken (open
                // decision 12 (a), `virtualDesktopSwitched`).
                if ok.virtualDesktop == true, !before.virtualDesktop { showVirtualDesktopTo = id }
                // The app: the hook assigns its settings, whose didSet has already set the target
                // (this call then finds it equal). The CLI: the change lands on the target.
                setTarget(onDeviceSettingsChange?(ok, away) ?? (away ? before.applyingAway(ok) : before.applying(ok)))
                if target != before { print("Settings from \(who): " + before.changes(to: target)) }
            }
            // Exactly one answer, to this device alone: the settings as they now stand, so a
            // refused or ignored field goes back to the Mac's value on the device.
            server.send(settingsMessage(settingsState(for: id, answering: change.token)), to: connection)
        case .fetchMenu:
            // The Mac's menus (MenuMirror): no `await` here either; the mirror schedules its reads
            // and answers this device alone. JSON that does not decode has no token to answer.
            guard let r = Wire.decode(FetchMenu.self, from: message.payload) else { return }
            menus.fetch(r, from: connection, who: deviceName(connection))
        case .clipboard:
            // The clipboard (HostClipboard): a subscription, a device's text, or its stop. No `await`:
            // it reads and writes the pasteboard at once, and says nothing per copy. A text that came while
            // this Mac read locked was refused above; one the gate turned locked since, HostClipboard
            // drops itself (its own look at the gate), said here, a line a minute at most.
            if !clipboard.received(message.payload, from: connection, who: deviceName(connection)) {
                refusedWhileLocked(.clipboard, message, from: connection)
            }
        case .pressMenuItem:
            guard let r = Wire.decode(PressMenuItem.self, from: message.payload) else { return }
            // One of the Mac's menu items chosen from a device acts as a click on it would, and may
            // bring a window forward: a view a gesture opened is left behind, as after a click.
            gestureChords.forget()
            menus.press(r, from: connection, who: deviceName(connection))
        default:
            break
        }
    }

    /// A device's session connected, or it sent a message: DisplayWake says whether someone is using
    /// the Mac from it, as a key press on it would say (issue #134), and whether this one declares it;
    /// DisplayActivity makes the call on its own queue and says "Woke the display for …" only when the
    /// display read asleep before and on half a second later. A test host counts `disp.wakeDry` and
    /// touches nothing. A locked Mac (LockPolicy.allowed, at `reading`, by default the gate's now): off
    /// console nothing is declared (the console and its display are another user's); at a locked screen a
    /// session's start declares nothing (none of the screen streams), a person's activity a paired
    /// session's taken input brought still does, as the Mac's own keyboard would.
    private func deviceActive(_ event: DisplayWake.Event, _ connection: NWConnection, reading: LockPolicy.Reading? = nil) {
        let allowed = LockPolicy.allowed(reading ?? lockReading, offConsoleView: lockGate.offConsoleView)
        if case .connect = event { guard allowed.wakeOnConnect else { return } } else { guard allowed.wakeOnActivity else { return } }
        switch displayWake.decide(event, at: CFAbsoluteTimeGetCurrent()) {
        case .nothing: break
        case .count: Stats.shared.bump(DisplayWake.dryKey); personDeclared()
        // The line reads the display the devices are shown: the Desktop's stop, else the main display.
        case .declare(let activity):
            displayActivity.declare(for: deviceName(connection), activity,
                                    display: active == .desktop && !placeholderStreams ? desktopStreamDisplay : nil)
            personDeclared()
        }
    }

    /// Whether the display a device's press lands on reads asleep (DisplayWake.pass asks only for a
    /// press): the display under the press in the streamed source, the virtual display when a window
    /// is staged there, as CoreGraphics reads it; the main display when nothing streams or the press
    /// lands on no display. A test host never reads a display: its test pattern never sleeps, but
    /// under SILL_TEST_DISPLAY_ASLEEP while that file exists.
    private func pressLandsAsleep(_ event: InputEvent) -> Bool {
        if synthetic { return testDisplayAsleepFile.map { FileManager.default.fileExists(atPath: $0) } ?? false }
        guard case .pointer(_, let x, let y) = event, let rect = currentSourceRect(), !rect.isNull else {
            return CGDisplayIsAsleep(CGMainDisplayID()) != 0
        }
        var display = CGDirectDisplayID(0)
        var count: UInt32 = 0
        let point = InputLanding.point(x: x, y: y, in: rect, displayScale: nil)
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count == 1 else {
            return CGDisplayIsAsleep(CGMainDisplayID()) != 0
        }
        return CGDisplayIsAsleep(display) != 0
    }

    /// Parameter sets went out at `time` (the encoder's callback, hopped here). A stream's first, and
    /// any that differ from the last, are a new frame size for the devices, which move their own
    /// pointer to its middle as they arrive (DisplayWake.recentre).
    private func parameterSetsSent(_ sets: Data, at time: CFAbsoluteTime) {
        guard sets != lastParameterSets else { return }
        lastParameterSets = sets
        displayWake.streamChanged(at: time)
    }

    // MARK: A locked Mac (LockPolicy; docs/locked-mac-plan.md)
    //
    // While this Mac's screen is locked, or another user, the login window or nobody is on its console,
    // the devices see none of it: a placeholder (a black still, no capture) streams in place of the
    // Desktop, and nothing else of the Mac goes out; a paired device types at a locked screen, nobody at
    // a Mac off console. SessionLock reads the witnesses on its own queue and sets the gate the moment
    // one says locked: the server withholds by it from then on, and every decision here reads it then
    // (`lockReading`). `lockChanged` follows each change: what the devices are shown, and the stream.
    // Unlocked, nothing here prints or changes anything.

    /// The gate's reading now (SessionLock's, set on its own queue).
    private var lockReading: LockPolicy.Reading { lockGate.reading }
    /// What the lock lets the devices see and do now: the gate's reading with the off-console view, the Mac's
    /// switch Show this account while another user is on the screen (LockPolicy.allowed; docs/off-console-plan.md).
    private var lockAllowed: LockPolicy.Allowed { lockGate.allowed }

    /// The gate changed (SessionLock.onChange, hopped here): what the devices are shown follows the reading
    /// as it is now, once per change however many came meanwhile. SessionLock printed its line already.
    /// Locked: the window list without windows, no thumbnail, icon or installed app, no menus' app, no
    /// sound, the clipboard paused, no pointer or cursor shape, and the placeholder in place of what
    /// streamed (`enforceLock`), whose window is remembered; unlocked (after the settle), the catalog
    /// looked at again and what streamed back (`afterUnlock`).
    private func lockChanged() async {
        // A lock Sill asked for (Lock this Mac when the last device leaves) is confirmed by the reading's change.
        privacy.readingChanged()
        let now = lockReading
        guard lockGate.established else { return }
        let was = lockActedOn, wasView = lockActedView
        let view = lockGate.offConsoleView
        lockActedOn = now
        lockActedView = view
        // Back on the console, or unlocked: the displays this session sees may still be changing (Noah's test of
        // 2026-11-12: back from a fast user switch, macOS's stand-in alone for about a second), and Sill's display
        // waits for them (HeadlessDesktopPolicy.Watch). Either needs the screens awake, so a wake macOS did not say
        // (screensDidWake) holds Sill's display back no longer.
        if let was, was != now, was == .offConsole || now == .unlocked {
            displayWatch.cameBack(at: CFAbsoluteTimeGetCurrent())
            screensSaidAsleep = false
        }
        // Changes coalesce (a lock and an unlock both before this ran): it acts on the reading as it is,
        // and also when nothing changed but what streams or was listed does not fit it: a select that
        // finished while the gate read locked (the placeholder) or unlocked (a window, the display) in
        // between, or a locked list sent meanwhile (LockPolicy.reconciles).
        let streams: LockPolicy.Streams = placeholderStreams ? .placeholder : Self.isWindow(active) ? .window
            : active == .desktop ? .display : .nothing
        guard now != was || view != wasView
              || LockPolicy.reconciles(now, streams: streams, lockedListSent: lockedListSent, offConsoleView: view) else { return }
        let allowed = LockPolicy.allowed(now, offConsoleView: view)
        let catalogWithheld = catalog.locked
        catalog.locked = !allowed.windows
        // Locked, or another user on the screen: the Desktop's one stop is the main display, whose lock
        // screen takes the password (DesktopDisplays); the stop a device chose comes back after the unlock.
        // A Desktop on another display moves now (`followDesktopDisplay`, from the catalog's change).
        catalog.mainOnly = now.locked
        status.update { $0.offConsoleView = view }      // the card's subtitle
        clipboard.setLocked(!allowed.clipboard)
        cursorShapes.running = active != .none && allowed.pointer
        pointer.setGeometry(pointerGeometry(), fps: fps)     // nothing of the pointer read while locked
        if now.locked {
            pendingLaunch = nil              // a launch asked for before the lock picks nothing now
            injector.stopRepeating()         // a held key repeats no more
        }
        // Off console (another user, or the login window, on the screen): Sill's own Desktop display goes at once
        // (LockPolicy.makesDesktopDisplay: never off console).
        if now == .offConsole, hasHeadlessDisplay {
            await removeHeadlessAtOnce(line: "Headless display: this session is off the console; removed Sill's display (it would be the displays of the user on the screen).") {
                self.lockReading == .offConsole
            }
        }
        // The Virtual Desktop (VirtualDesktopLife): kept while locked until the unlock, removed at once off console; its stop
        // and whether it can be made follow the reading.
        if !now.locked { saidVirtualDesktopKept = false }
        refreshVirtualDesktop()
        lookAtVirtualDesktop()
        menuTargetChanged()                  // no app's menus while locked, the source's again after
        audioFollow()                        // and no sound
        broadcastList()                      // the windows go now; they come back once looked at
        // The off-console view began after a lock (the switch on while off console, or the console's witness
        // after a note): what the lock withheld of the icons and the installed apps goes now; the catalog takes
        // every thumbnail again by itself.
        if now.locked, catalogWithheld, !catalog.locked { sendWithheldAppsAndIcons() }
        if now.locked {
            restore.lockBegan(active: active)    // a window streaming now is what comes back
            await enforceLock()
        } else if was != nil || catalog.clientCount > 0 {
            await afterUnlock()
        }
    }

    /// Locked: no picture of this Mac streams. A window gives way (it goes home: the stage's way on the
    /// virtual display, WindowRestore's in regular mode), and so does the display unless it may stream at
    /// this reading (`LockPolicy.lockScreenStreams`), to the placeholder: `select`'s Desktop makes it while
    /// locked, and its keyframe replaces every device's last picture, older devices' too. With a device
    /// connected and nothing streaming, the placeholder too. A switch under way calls this again at its end.
    private func enforceLock() async {
        // With no device left, the client count's own select(.none) stops the stream instead.
        guard lockReading.locked, !switching, catalog.clientCount > 0 else { return }
        let allowed = lockAllowed
        // The off-console view (docs/off-console-plan.md): a window streams on, never from Sill's virtual display,
        // which would join the other user's displays: a staged one is restarted where it is (`select`).
        if Self.isWindow(active), allowed.windows {
            if virtualDisplay, stage.isStaged, !allowed.virtualDisplay { await select(active) }
            return
        }
        // The Desktop already as this reading has it (the placeholder, or the display where it may stream:
        // a locked screen with `LockPolicy.lockScreenStreams`); else the Desktop again, so another user
        // taking the console turns the display into the placeholder, and this session back on it, locked,
        // turns the placeholder into the lock screen.
        // The display only on the main display (DesktopDisplays: `mainOnly`), whatever stop was chosen.
        if active == .desktop, placeholderStreams != allowed.display, placeholderStreams || desktopOnItsStop { return }
        await select(.desktop)
    }

    /// The Desktop's capture runs on the stop the catalog shows (a test host's test pattern without
    /// SILL_TEST_DISPLAYS has none, and is on it).
    private var desktopOnItsStop: Bool {
        if synthetic, catalog.testDisplays == nil { return true }
        return desktopStreamDisplay == catalog.desktopDisplayID
    }

    /// A switch to a window found this Mac locked just before the window would be staged or its pipeline
    /// started: no frame of the window goes out, no virtual display is made. Nothing streams for a moment,
    /// the window goes home (the stage's way here, WindowRestore's in `select`'s defer), the placeholder
    /// follows at once, and the window is what comes back after the unlock (unless no device is left, as
    /// `LockPolicy.Restore.devicesLeft` says). The caller returns from `select`.
    private func lockedMidSwitch(_ source: StreamSource) async {
        if catalog.clientCount > 0 { _ = restore.select(source, active: active, pick: false, reading: lockReading) }
        if virtualDisplay { await stage.releaseHome() }
        active = .none
        placeholderStreams = false
        broadcastList()
        Task { @MainActor in
            guard self.catalog.clientCount > 0 else { return }   // nobody left to stream the placeholder to
            await self.select(.desktop)
        }
    }

    /// Unlocked (SessionLock's settle over): the catalog looked at afresh; the icons and the installed apps
    /// a locked Mac withheld, and the window list, to every device (the thumbnails follow: the catalog takes
    /// every one again); then, in place of the placeholder, the window that streamed at the lock, picked
    /// again as a restart is (nothing comes forward on the Mac), if it is still listed, else the Desktop.
    /// Nothing when something else was picked since. A switch under way is waited for.
    private func afterUnlock() async {
        guard catalog.clientCount > 0 else { return }
        await catalog.refreshWindows()
        let deadline = CFAbsoluteTimeGetCurrent() + 2
        while switching, CFAbsoluteTimeGetCurrent() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        guard !lockReading.locked, !shuttingDown else { return }
        guard !switching else {
            // Still switching after 2 s: look again in a moment, the placeholder must not outlast the lock.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                await self.afterUnlock()
            }
            return
        }
        sendWithheldAppsAndIcons()
        broadcastList()
        if let next = restore.afterUnlock(listed: catalog.infos.map(\.id), active: active, placeholder: placeholderStreams,
                                          devices: catalog.clientCount, reading: lockReading) {
            await select(next)
        }
    }

    /// The icons and the installed apps a locked Mac withheld: all of them to a device that connected while
    /// it was locked, and to the others what came while it was (WindowCatalog.takeWithheld).
    private func sendWithheldAppsAndIcons() {
        let withheld = catalog.takeWithheld()
        let now = Date().timeIntervalSince1970
        let apps = StreamMessage(kind: .appList, timestamp: now, isKeyframe: false, payload: Wire.encode(catalog.installedApps))
        func icon(_ i: (bundleID: String, png: Data)) -> StreamMessage {
            StreamMessage(kind: .appIcon, timestamp: now, isKeyframe: false, payload: ImageBlob.encodeIcon(bundleID: i.bundleID, png: i.png))
        }
        var messages: [(NWConnection, StreamMessage)] = []
        for (id, connection) in connections {
            if appsAndIconsSent.insert(id).inserted {
                messages += catalog.allIcons.map { (connection, icon($0)) } + [(connection, apps)]
            } else {
                messages += withheld.icons.map { (connection, icon($0)) }
                if withheld.apps { messages.append((connection, apps)) }
            }
        }
        if !messages.isEmpty { server.send(each: messages) }
    }

    /// What the lock makes of a device's message at `reading` (LockPolicy.decide). Unlocked, nothing is
    /// decoded or looked up; locked, whether the session is paired is (input comes up to 120 times a
    /// second, and only while locked does it matter).
    private func lockDecision(_ message: StreamMessage, input: InputEvent?, from id: ObjectIdentifier,
                              arrived: LockPolicy.Reading) -> LockPolicy.Decision {
        let now = lockReading
        guard arrived.locked || now.locked else { return .take }
        let request: LockPolicy.Request
        switch message.kind {
        case .input:
            guard let input else { return .take }    // one that does not decode is dropped below
            request = .input(letsGo: injector.releasesWhatItHolds(input, from: id))
        case .selectSource:
            request = .pick(Wire.decode(StreamSource.self, from: message.payload) ?? .none)
        case .nextDisplay:
            request = .nextDisplay
        case .launchApp:
            request = .launch
        case .windowCommand:
            request = .windowCommand
        case .fetchMenu:
            request = Wire.decode(FetchMenu.self, from: message.payload)?.id == nil ? .menuSubscription : .menuRequest
        case .pressMenuItem:
            request = .menuRequest
        case .gesture:
            request = .gesture
        case .clipboard:
            request = Wire.decode(Clipboard.self, from: message.payload)?.text != nil ? .clipboardText : .clipboardSubscription
        default:
            return .take
        }
        // At the reading as it arrived and now, the off-console view as it is now: the stricter answer.
        return LockPolicy.decide(request, arrived: arrived, now: now, paired: sessionPaired(id), offConsoleView: lockGate.offConsoleView)
    }

    /// A request the lock refused: counted, a line a minute at most for its kind (the first at once), and
    /// a menu's fetch or choice answered at once with the menus' note, so the device waits for nothing.
    /// A pick, a launch, a window's buttons and a gesture are quiet on the device: its list is empty.
    private func refusedWhileLocked(_ why: LockPolicy.Refusal, _ message: StreamMessage, from connection: NWConnection) {
        Stats.shared.bump(why == .input ? "in.locked" : "lock.refused")
        lockRefusals[why]?.count(why.rawValue)
        switch message.kind {
        case .fetchMenu:
            if let r = Wire.decode(FetchMenu.self, from: message.payload) { menus.refuse(r, from: connection, note: LockPolicy.menuNote) }
        case .pressMenuItem:
            if let r = Wire.decode(PressMenuItem.self, from: message.payload) { menus.refuse(r, from: connection, note: LockPolicy.menuNote) }
        default:
            break
        }
    }

    private static func isWindow(_ source: StreamSource) -> Bool {
        if case .window = source { return true }
        return false
    }

    // MARK: Where input lands

    /// The active source's rectangle on screen, in CG global points (top-left origin), which is
    /// what the injector maps the client's fractions onto. Nil when nothing is streaming, so
    /// input that arrives between sources is dropped rather than poked at the wrong window.
    private func currentSourceRect() -> CGRect? {
        switch active {
        case .none:
            return nil
        case .desktop:
            // The test pattern with the TEST ONLY scripted pointer: its own space, where a test
            // client's input moves that pointer (a synthetic host posts nothing). Under SILL_TEST_DISPLAYS
            // the shown stop's own space instead, so the dry run's log shows where input lands on each.
            if synthetic, pointer.hasTestPointer, catalog.testDisplays == nil { return Self.testPatternRect }
            return desktopFrame
        case .window(let id):
            // On the virtual display the video is the captured crop, not the whole window: an app
            // that took a larger size than asked overhangs the display and the overhang is not shown.
            if virtualDisplay, stage.isStaged, let onScreen = stage.captureRectOnScreen { return onScreen }
            // The catalog only refreshes every 2 s, so ask the window server for live bounds —
            // but cache them briefly, or a 120 Hz Pencil drag hits it on every single event.
            let now = CFAbsoluteTimeGetCurrent()
            if let cached = rectCache, cached.id == id, now - cached.at < 0.1 { return cached.rect }
            guard let rect = Self.liveBounds(of: id) ?? catalog.window(id: id)?.frame else { return nil }
            rectCache = (id, rect, now)
            return rect
        }
    }

    /// The Desktop's rectangle: the stop its capture runs on (DesktopDisplays.landing), else the
    /// catalog's display (a test host's stop under SILL_TEST_DISPLAYS).
    private var desktopFrame: CGRect? {
        DesktopDisplays.landing(streaming: desktopStreamDisplay, among: catalog.desktopCandidates)
            ?? (catalog.testDisplays != nil ? catalog.desktopStop?.frame : catalog.display?.frame)
    }

    private static func liveBounds(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    // MARK: The Mac cursor
    //
    // The video never carries the Mac cursor. The client draws the pointer where its trackpad or
    // Pencil says it is (no round trip), and `cursorShapes` streams the Mac's current cursor image
    // so that pointer takes the right shape. Toggling `showsCursor` on a running SCStream with
    // `updateConfiguration` wedged the capture on macOS 27, so it is fixed at start.
    //
    // While the Mac (its own mouse or trackpad), or another device, moves the pointer, the devices
    // draw it from where the host says it is (kind 26: `pointer`, StreamServer), in the same shape.

    /// What the Mac's pointer is judged against (docs/pointer-visibility-plan.md §4.7): the streamed
    /// source's rectangle in global points, the injector's own (`currentSourceRect`). The Desktop:
    /// its display. A window on the virtual display: the crop, or the full-screen band. A window in
    /// regular mode: its live bounds, which the watch re-reads, and it must be on screen. A
    /// synthetic host has one only for the test pattern under the TEST ONLY scripted pointer, so it
    /// never reads the real pointer (a real window picked there included).
    private func pointerGeometry() -> PointerWatch.Geometry? {
        // A locked Mac's pointer is never read (LockPolicy): off console it is the console's, another user's.
        guard lockAllowed.pointer else { return nil }
        switch active {
        case .none:
            return nil
        case .desktop:
            if synthetic { return pointer.hasTestPointer ? .rect(Self.testPatternRect) : nil }
            return desktopFrame.map { .rect($0) }
        case .window(let id):
            guard !synthetic else { return nil }
            if virtualDisplay, stage.isStaged, let onScreen = stage.captureRectOnScreen { return .rect(onScreen) }
            return currentSourceRect().map { .window(id, $0) }
        }
    }

    // MARK: Fitting the window to the client

    /// Resizes the streamed window to the client's panel at its text scale, if one is set and the
    /// window is not already there. Returns the size the window actually took, or nil if nothing
    /// changed. Mac points throughout: the panel in device points divided by the scale (device
    /// points per Mac point). Scale nil means leave the window alone, and so is a window in full
    /// screen (WindowRestore.fit). Every resize the app took, or left unanswered (a busy app may take
    /// it later), is a fit for `fits`: the window goes back to its own frame when it stops streaming
    /// (`restoreFits`, issue #57). None once the host is shutting down: nothing would put it back.
    private func fitToViewport(_ window: SCWindow) -> CGSize? {
        guard !shuttingDown, let v = viewport, let textScale = v.scale, textScale > 0, v.width > 0, v.height > 0 else { return nil }
        let target = CGSize(width: (v.width / textScale).rounded(), height: (v.height / textScale).rounded())
        let current = Self.liveBounds(of: window.windowID)?.size ?? window.frame.size
        if abs(current.width - target.width) <= 2, abs(current.height - target.height) <= 2 { return nil }
        guard let fit = sizer.resize(window: window, to: target) else { return nil }
        fits.fitted(window.windowID, handle: fit.placement, before: fit.before, after: fit.after, asked: target)
        let actual = fit.after.size
        // Asked again for a size the app already refused (its minimum): nothing moved.
        guard abs(actual.width - current.width) >= 1 || abs(actual.height - current.height) >= 1 else { return nil }
        Stats.shared.bump("win.resized")
        // ViewportBounds.whole prints as Int() did, without its trap (finding 4: 1e300 points got here).
        print("Resized \(window.owningApplication?.applicationName ?? "?") to \(ViewportBounds.whole(actual)) pt "
              + "(asked \(ViewportBounds.whole(target)) for a \(ViewportBounds.whole(CGSize(width: v.width, height: v.height))) panel at \(textScale)×)")
        return actual
    }

    /// A device's viewport refused (ViewportBounds; `why` its words, or that it does not decode):
    /// counted (`vp.refused` in the stats line) and said in a line that names the device, at once and
    /// then at most once a second per connection, so a device that sends nothing else costs a line a
    /// second, not one per message.
    private func refuseViewport(_ why: String, from connection: NWConnection) {
        Stats.shared.bump("vp.refused")
        let id = ObjectIdentifier(connection)
        let now = CFAbsoluteTimeGetCurrent()
        if let last = viewportRefusedLineAt[id], now >= last, now - last < 1 { return }
        viewportRefusedLineAt[id] = now
        print("Viewport from \(deviceName(connection)) refused: \(why)")
    }

    /// A new viewport while a window streams. The encoder is fixed to the old size, but the
    /// catalog's resize check (`windowsChanged`) already restarts the pipeline when the window's
    /// size changes; refreshing now just saves waiting up to two seconds for its next poll.
    /// The desktop and nothing-streaming ignore viewports.
    private func applyViewportToActiveWindow() async {
        // A different rate (a ProMotion device joined, Low Power Mode toggled) needs a new capture
        // interval and encoder session: one restart, whatever the source.
        if active != .none, streamRate(for: active) != fps { await select(active); return }
        if virtualDisplay, stage.isStaged, case .window(let id) = active {
            // One restart: prepare re-places the window on the same display (the display is only
            // recreated if the envelope grew). The client's identical re-send after a switch is a
            // no-op through the 2 pt compare.
            var found = catalog.window(id: id)
            if found == nil { found = await catalog.resolveWindow(id: id) }
            // The lookup may have suspended for up to 3 s with `switching` clear, so another
            // select can have run to completion meanwhile: only restart if `id` is still active.
            guard let w = found, case .window(let now) = active, now == id else { return }
            let want = wantedStage(for: w)
            if stage.matches(windowID: id, size: want.size) { return }
            await select(.window(id))
            return
        }
        // A locked Mac sizes no window (LockPolicy): the one streaming at the lock gives way to the placeholder.
        // Nor does the off-console view (Accessibility acts in a session nobody at the device can use).
        guard case .window(let id) = active, lockAllowed.actsOnWindows, let w = catalog.window(id: id) else { return }
        if fitToViewport(w) != nil { await catalog.refreshWindows() }
    }

    /// `--virtual-display`: how big the window should be on the virtual display and how big the
    /// display must be, from the last viewport (or the window's own size before any arrived).
    private func wantedStage(for w: SCWindow) -> (size: CGSize, envelope: CGSize) {
        let own = Self.liveBounds(of: w.windowID)?.size ?? w.frame.size
        let size = VirtualStage.windowSize(for: viewport, own: own)
        // The envelope also covers the window's current size: an app's minimum is never larger
        // than what it shows now, so the "insists on a larger size, grow the display" recreate
        // (seen twice per rotation for Chrome and Claude) does not happen.
        var env = VirtualStage.envelope(for: viewport, windowSize: size)
        // Not while the window is full screen: its frame is the whole display, and growing the
        // envelope to it would recreate the display under the full-screen Space.
        if !(stage.isStaged && stage.windowStillFullScreen) {
            env = CGSize(width: max(env.width, own.width), height: max(env.height, own.height))
        }
        return (size, env)
    }

    // MARK: Source switching

    /// A pick from a device's switcher, and one that waited out a restart (select's defer): one
    /// rule for both, so a queued pick is not lost to a select that starts before its Task runs.
    /// While the active source restarts (a settings change, a resize, a rate change, the encoder
    /// fallback, a lost display), the pick waits for it and runs once it is done: the newest
    /// wins, and a pick of the source being restarted needs nothing. During a switch to another
    /// source it is dropped, as before this rule existed: the device's automatic Desktop request
    /// can land then and must not override the user's pick.
    ///
    /// The host cannot tell that request from a Desktop tap. The device holds it back when the
    /// user has picked since the watched window closed (StreamClient's window list); an older
    /// device, or a pick made before the device heard of the close, can still let it land during
    /// a restart that follows the user's pick, and then it is queued like the user's own.
    private func handlePick(_ source: StreamSource) async {
        if switching {
            if let r = restartOf, source != r { pickArrivedWhileSwitching = source }
            return
        }
        // A pick of a window the catalog lists is the person's choice of it as it shows now: a tab switch
        // still held for it (owed while it streamed, its follow held back by a switch in flight) is not
        // followed after the pick (#368's review). One the catalog no longer lists (hidden behind another
        // tab since the device's list) keeps it, and the stream follows to the tab that shows.
        if case .window(let id) = source, catalog.window(id: id) != nil { catalog.tabSwaps[id] = nil }
        await select(source, bringForward: true)
    }

    /// Streams `source` in place of whatever streams now. Also how the host restarts the current
    /// source (a resize, a rate change, the encoder fallback, a lost virtual display).
    /// `bringForward` marks a pick instead: the device's switcher, the command line, an app
    /// launched from the device. In regular mode a picked window comes forward on the Mac, and a
    /// pick that falls back from the virtual display to the real window counts as regular mode;
    /// restarts leave Mac focus where it is, and so does staging a window on the virtual display.
    /// One exception: a staged window that comes home because the virtual display was turned off
    /// comes forward too, whichever select commits that change (see `cameHome`).
    ///
    /// While this Mac is locked no picture of it streams (LockPolicy, docs/locked-mac-plan.md): a window
    /// asked for here (a restart, a launched app's first window, a pick queued before the lock) becomes the
    /// Desktop and is what comes back after the unlock; with the Desktop streaming already, nothing
    /// happens; the Desktop itself is the placeholder, a black still with no capture. A device's own pick
    /// of a window never gets here while locked (`handle` refuses it). The gate is read again after each
    /// await that could let a lock in: before a window is staged and before any capture starts. Unlocked,
    /// a pick forgets the window that would have come back.
    func select(_ source: StreamSource, bringForward: Bool = false) async {
        guard !switching, !shuttingDown else { return }
        var source = source
        switch restore.select(source, active: active, pick: bringForward, reading: lockReading, offConsoleView: lockGate.offConsoleView) {
        case .proceed: break
        case .desktop: source = .desktop
        case .stay: return
        }
        switching = true
        if source != active { missingPolls = 0 }    // a window's looks off the list are its own
        restartOf = (source == active && source != .none) ? source : nil
        defer {
            switching = false
            restartOf = nil
            var pick = pickArrivedWhileSwitching
            pickArrivedWhileSwitching = nil
            // Requests that arrived mid-switch, applied now that `switching` is clear again (every
            // return path, including the early ones). A last client leaving wins over a viewport
            // and over a queued pick: there is nobody left to fit the window to or stream to.
            if deselectWhenSettled {
                deselectWhenSettled = false
                if catalog.clientCount == 0 {
                    viewportArrivedWhileSwitching = false
                    Task { @MainActor in
                        if self.active != .none { await self.select(.none) }
                        if self.catalog.clientCount == 0 { self.releaseHeadlessDisplayIfDone() }
                    }
                }
            }
            if catalog.clientCount == 0 { pick = nil }
            if let pick, pick != active {
                // The pick's own select fits the latest viewport. Run after it has started, the
                // viewport tail would resize the old window, which `active` still names mid-switch.
                viewportArrivedWhileSwitching = false
                // Through the handler's rule again, not straight to `select`: another restart can
                // start before this Task runs (a viewport's new rate, an encoder hang, a lost
                // display), and `select` would drop the pick; the rule queues it behind that one.
                Task { @MainActor in await self.handlePick(pick) }
            } else if viewportArrivedWhileSwitching {
                viewportArrivedWhileSwitching = false
                Task { @MainActor in await self.applyViewportToActiveWindow() }
            }
            // Settings, or a flip between the home and the away quality, that came in meanwhile; a
            // no-op when the pick's select commits them first.
            if pendingConfig != nil || (awayWanted != awayRunning && flipWait == nil) { Task { @MainActor in await self.applyPending() } }
            // A stream that did not start (its window gone, capture refused): nothing streams, so
            // the links have nothing to be judged at, and a window sized for it goes back.
            if active == .none { judgeLinks(nil); restoreFits(keeping: nil) }
            // Locked while this switch was under way, and what started is a picture of the Mac (a window,
            // the display): the placeholder now (LockPolicy). The gate withheld its frames meanwhile.
            // The off-console view: the placeholder that started meanwhile gives way to this session's picture.
            if lockReading.locked, active != .none, !placeholderStreams || lockGate.offConsoleView { Task { @MainActor in await self.enforceLock() } }
            // The Virtual Desktop: shown now or no longer (its grace starts), looked at once this switch is over.
            Task { @MainActor in self.lookAtVirtualDesktop() }
        }

        await capture.stop()
        await syntheticCapture.stop()
        await stillCapture.stop()
        // Every queue drained: let the old encoder go.
        capture.onFrame = nil; syntheticCapture.onFrame = nil; stillCapture.onFrame = nil
        placeholderStreams = false
        rectCache = nil
        // Input held for the old source must not replay into the new one, but what acts on the whole
        // Mac still goes, in order: a gesture's chord held behind it, and the up of a key or a button
        // the Mac has down (DroppedInput: a modifier left down makes the next click a ⌘-click, a
        // button every move a drag), a button's where the pointer is (`.null`), not where the old
        // source would have put it. The keys of devices that left meanwhile go up after them.
        // A device the Mac no longer serves, or one that left meanwhile, gets only the up of what it
        // holds down itself (RevokedInput), and none of its gestures; so does an unpaired one while this
        // Mac is locked, and nobody's gesture goes then (LockPolicy).
        let dropped = heldInput
        heldInput = []; holdUntil = 0
        for item in dropped {
            switch item {
            case .input(let event, _, let device):
                if (gone(device) || lockedOut(device)) ? injector.releasesWhatItHolds(event, from: device) : injector.isUpOfSomethingDown(event) {
                    injector.apply(event, in: .null, from: device)
                }
            case .chord(let keyCode, let flags, let device):
                if gone(device) { Stats.shared.bump("in.revoked"); continue }
                if !lockAllowed.gestures { Stats.shared.bump("in.locked"); continue }
                injector.chord(keyCode: keyCode, flags: flags)
            }
        }
        releaseKeysOfDevicesThatLeft()
        injector.stopRepeating()            // nor does a held key repeat into the next source (KeyRepeat)
        encoder = nil                  // deinit invalidates the VT session
        server.resetForNewStream()          // every client waits for the next parameter sets + keyframe
        lastParameterSets = nil             // and the new stream's first go out as a new frame (DisplayWake)
        // New settings take effect here, between pipelines, before the rate, the scale and the
        // stage are worked out for the next one.
        var leftStage = false
        // The virtual display turned off (from the Mac or a device) sends a staged window home, and
        // it comes forward the way a pick does in regular mode (Q3). Decided here, from the value
        // this commit takes, not by the caller: any select can take that change, a restart
        // included (a newer value replaces the one that started it during the awaits above), and
        // a restart raises nothing on its own.
        var cameHome = false
        if let first = pendingConfig {
            if config.virtualDisplay && !first.virtualDisplay {
                // The virtual display block below is skipped once the flag reads off: send the
                // window home now, and re-read the catalog so the .window lookup below gets its
                // home frame, not the staged one.
                cameHome = stage.isStaged
                await stage.leaveFullScreenIfNeeded(); await stage.releaseHome()
                if case .window = source { await catalog.refreshWindows() }
                leftStage = true
            }
            // The newest value: another may have arrived during those awaits.
            let next = pendingConfig ?? first
            pendingConfig = nil
            adopt(next, away: awayWanted)
        } else if awayWanted != awayRunning {
            // Home or away changed (a device joined or left): the pipeline takes the other pair.
            adopt(config, away: awayWanted)
        }
        // The devices' panel rate (highest), or 60 before any has said; the Desktop's held to its stop's
        // refresh rate (the stop as the last look has it, the main display while locked: checked again once
        // the capture is built).
        catalog.mainOnly = lockReading.locked
        fps = streamRate(for: source)
        // The devices' links: judged afresh when the stream comes back at another quality or not at
        // all, kept through a restart that keeps it (a window picked, a rotation, a resize).
        judgeLinks(source == .none ? nil : LinkJudge.Quality(bitrate: bitrate, fps: fps, captureScale: Double(captureScale)))
        let comeForward = bringForward || cameHome

        if virtualDisplay {
            // The stage follows the selection. A different window sends the staged one home first
            // and keeps the display for the newcomer; the same window keeps its place (prepare then
            // skips the move); none or desktop puts the window back and removes the display.
            if case .window(let id) = source {
                if let staged = stage.placement, staged.windowID != id {
                    await stage.leaveFullScreenIfNeeded()
                    stage.releaseWindow()
                }
            } else {
                // The display goes once the window server shows the window home (StageRelease: as it went in the
                // same millisecond, macOS moved a window still committing its move to the main display, 2026-11-12).
                await stage.leaveFullScreenIfNeeded()
                await stage.releaseHome()
            }
        }
        // In regular mode, every window Sill sized but the one about to stream goes back to its own
        // frame (WindowRestore, issue #57): another window or the Desktop picked, `.none` when the
        // last device leaves or the stream stops. A restart of the same window keeps it fitted.
        if case .window(let next) = source { restoreFits(keeping: next) } else { restoreFits(keeping: nil) }
        // The catalog's look, before a capture is built from it (CatalogLook): after a spell with no
        // device it can be hours old and its display gone (the black screen of 2026-10-28), so it is
        // looked at again first. The Desktop reads its display after this and after its own await.
        // Locked, or another user on the screen: the Desktop's stop is the main display (DesktopDisplays),
        // before the look below is taken, so its line never takes the lock for a change of displays.
        catalog.mainOnly = lockReading.locked
        let lookBefore = (display: catalog.display?.displayID, age: catalog.lookAge)
        if source != .none, !(synthetic && source == .desktop) {
            await lookAgainIfStale()
            guard !shuttingDown else { active = .none; broadcastList(); return }
        }

        var filter: SCContentFilter?     // nil only for the synthetic test pattern
        var sourceRect: CGRect? = nil    // set only when the window streams from the virtual display
        var picked: SCWindow?            // the resolved window, for the fallback after a failed start
        // The source's display's own pixel scale (CaptureScale): its filter's, the virtual display's
        // for a staged window, none for the test pattern. The capture runs at the knob held to it.
        var displayScale: CGFloat? = nil
        var width = 0, height = 0
        var describe = ""
        var title = ""                   // for the app's menu: "Safari — Apple Developer", "Whole Desktop"
        var kind = HostStatusSnapshot.Stream.Kind.window
        // What the frames show, for the server's gate (LockPolicy.withheld): a window's, the display's
        // (or the test pattern's), or a locked Mac's placeholder.
        var picture = LockPolicy.Picture.window
        switch source {
        case .none:
            active = .none
            broadcastList()
            return
        case .window(let id):
            // The off-console view (docs/off-console-plan.md): never Sill's virtual display; a window staged there
            // goes home first (Sill's own staging undone) and streams where it is.
            if virtualDisplay, lockAllowed.windows, !lockAllowed.virtualDisplay, stage.isStaged {
                await stage.leaveFullScreenIfNeeded(); await stage.releaseHome(); await catalog.refreshWindows(); leftStage = true
            }
            // On the virtual display the window may have left the on-screen list; look it up fully.
            var found = catalog.window(id: id)
            if found == nil, virtualDisplay || leftStage { found = await catalog.resolveWindow(id: id) }
            guard let w = found else {
                if virtualDisplay { await stage.releaseHome() }
                active = .none; broadcastList(); return
            }
            // Locked during this switch's awaits: nothing of the window is staged, sized, raised or
            // captured (LockPolicy), but in the off-console view, which captures it where it is.
            if !lockAllowed.windows { await lockedMidSwitch(source); return }
            print("Selecting window \(w.windowID) \(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "") frame \(w.frame) onScreen \(w.isOnScreen) active \(w.isActive)")
            picked = w
            listedFullScreen = WindowRestore.coversDisplay(w.frame, WindowSizer.displayFrames()) ? id : nil
            streamedPID = w.owningApplication.map { (window: id, pid: $0.processID) }
            title = Self.menuTitle(for: w)
            var size = w.frame.size
            if virtualDisplay, stage.disabledReason == nil, lockAllowed.virtualDisplay {
                let want = wantedStage(for: w)
                // A window Sill sized in regular mode (the virtual display turned on while it
                // streamed): the stage keeps the frame it would have gone back to as its way home.
                let home = stageHome(for: id)
                do {
                    // Sill's own display is 2x: the knob, as before (CaptureScale.virtualDisplay).
                    let stageScale = CaptureScale.effective(knob: captureScale, displayScale: CaptureScale.virtualDisplay)
                    let prepared = try await stage.prepare(window: w, wanted: want.size, envelope: want.envelope, captureScale: stageScale,
                                                           refreshHz: fps, home: home)
                    _ = fits.take(id)     // the stage puts it back from now on; a staging that failed keeps the record
                    guard !shuttingDown else { stage.release(); active = .none; broadcastList(); return }
                    filter = prepared.filter
                    sourceRect = prepared.sourceRect
                    displayScale = CaptureScale.virtualDisplay
                    size = prepared.outputSize ?? prepared.sourceRect.size
                    describe = prepared.describe + (useSoftwareEncoder ? " (software encoder)" : "")
                    status.update { $0.lastStageFailure = nil }
                } catch {
                    // Locked while the window was being staged: no display was made (or it goes now), and
                    // nothing of the window streams in its place (LockPolicy).
                    if !lockAllowed.windows { await lockedMidSwitch(source); return }
                    print("Virtual display fallback for \(w.owningApplication?.applicationName ?? "?"): \(error). Streaming the real window instead.")
                    Stats.shared.bump("vd.fallback")
                    await stage.releaseHome()
                    // For the menu: why this window streams in place, and whether the stage gave up
                    // for the run (it does after repeated display creation failures).
                    let why = (error as? VirtualStage.Failure)?.summary ?? "\(error)"
                    status.update {
                        $0.lastStageFailure = why
                        if let off = stage.disabledReason { $0.virtualDisplayProblem = off }
                    }
                }
            }
            if sourceRect == nil {
                // Locked while the stage tried (its awaits): nothing raised or sized either. The off-console view
                // captures the window where it is, and raises and sizes nothing (LockPolicy.Allowed.actsOnWindows).
                if !lockAllowed.windows { await lockedMidSwitch(source); return }
                let acts = lockAllowed.actsOnWindows
                if virtualDisplay, !lockAllowed.virtualDisplay { status.update { $0.lastStageFailure = "another user is on the screen" } }
                // Today's path: capture the window where it is, at most at its display's own scale
                // (a window on a 1x display drawn at 1x into a 2x buffer filled its top-left quarter).
                let windowFilter = SCContentFilter(desktopIndependentWindow: w)
                filter = windowFilter
                displayScale = Self.displayScale(of: windowFilter)
                // Regular mode raises the picked window (2026-09-23, Noah: the Mac must show the
                // picked window). A covered window stops repainting, so it would stream frozen, and
                // keys go to the active app's key window. Done before capture starts, so the first
                // frames already show it uncovered. The virtual display's fallback lands here too.
                if comeForward, !shuttingDown, acts { activateAndRaise(window: w) }
                // Fit the window to the client's panel before capture starts, so the stream comes up
                // at the new size instead of restarting once the catalog notices. `w` is a snapshot
                // with the old frame; the window server has the new one.
                if acts, let resized = fitToViewport(w) { size = Self.liveBounds(of: id)?.size ?? resized }
                describe = "\(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "")\(useSoftwareEncoder ? " (software encoder)" : "")"
            }
            if sourceRect == nil {
                // The window as it is, drawn 1:1 at its display's scale: an odd side rounds up, one black
                // column or row past the window, never its pixels shrunk into one fewer (CaptureScale.windowPixels).
                let pixels = CaptureScale.windowSize(size, knob: captureScale, displayScale: displayScale)
                width = pixels.width; height = pixels.height
            } else {
                // A crop of Sill's virtual display, which ScreenCaptureKit scales to the buffer, as a display.
                let pixelScale = CaptureScale.effective(knob: captureScale, displayScale: displayScale)
                width = evenPixels(size.width * pixelScale); height = evenPixels(size.height * pixelScale)
            }
            // Staged on the virtual display, nothing is activated or raised on select: the window
            // cannot be covered there, and the AX moves that put it there touch no focus.
        case .desktop:
            // The Desktop asked for on the Virtual Desktop's stop: made first, so its capture is built on it (phase 2b; the
            // spacing may hold it back, and the Desktop shows the main display meanwhile).
            await ensureVirtualDesktop()
            if !lockAllowed.display {
                // A locked Mac's Desktop (LockPolicy): the placeholder, a black still and no capture.
                (width, height) = placeholderSize()
                picture = .placeholder
                describe = "a placeholder (this Mac is locked: nothing of it is captured)"
                title = "Locked"; kind = .desktop
            } else if synthetic, let stop = testStop() {
                // TEST ONLY (SILL_TEST_DISPLAYS): the test pattern at the shown stop's size and scale, with
                // its number and name drawn on it, its rate held to the stop's (`streamRate`).
                desktopStreamDisplay = stop.display.id
                let pixelScale = CaptureScale.effective(knob: captureScale, displayScale: stop.scale)
                width = evenPixels(stop.display.frame.width * pixelScale); height = evenPixels(stop.display.frame.height * pixelScale)
                describe = "a synthetic test pattern of \(stop.words)\(useSoftwareEncoder ? " (software encoder)" : "")"
                title = "Test Pattern"; kind = .testPattern
                picture = .display
                syntheticCapture.label = stop.words
                let rate = DesktopDisplays.rate(effectiveFPS, refreshHz: stop.display.refreshHz)
                if rate != fps {
                    fps = rate
                    judgeLinks(LinkJudge.Quality(bitrate: bitrate, fps: fps, captureScale: Double(captureScale)))
                }
            } else if synthetic {
                // TEST ONLY: with SILL_TEST_HEADLESS, Sill's display is judged on the file's list as on a Mac's, and
                // only said to be made; the test pattern streams either way.
                if testHeadlessFile != nil {
                    await ensureHeadlessDisplayIfNeeded()
                    holdDesktopRate(onDisplay: nil)
                }
                // A 1512×949-point test pattern: the same size as a typical streamed window, so the
                // encoder and the fallback see realistic load without Screen Recording.
                width = evenPixels(1512 * captureScale); height = evenPixels(949 * captureScale)
                describe = "a synthetic test pattern\(useSoftwareEncoder ? " (software encoder)" : "")"
                title = "Test Pattern"; kind = .testPattern
                picture = .display
            } else {
                // No real screen online (a closed lid and no monitor, a headless Mac; macOS's 1x stand-in is none, an
                // asleep monitor is one): Sill's own Retina display first (#61), once the displays have settled and the
                // screens are awake (Watch).
                await ensureHeadlessDisplayIfNeeded()
                // The display as the newest look has it, read after every await (`desktopCapture`).
                guard let plan = await desktopCapture() else { active = .none; broadcastList(); return }
                if let line = CatalogLook.desktopLine(was: lookBefore.display, now: plan.displayID, age: lookBefore.age) { print(line) }
                filter = plan.filter
                displayScale = plan.displayScale
                width = plan.width; height = plan.height
                describe = "the whole desktop\(useSoftwareEncoder ? " (software encoder)" : "")"
                title = "Whole Desktop"; kind = .desktop
                picture = .display
                // The stop's own refresh rate, now that its display is known (a look during the awaits can
                // have moved the Desktop to a stop of another rate), or Sill's own display's: judged at the rate it runs.
                holdDesktopRate(onDisplay: plan.displayID)
            }
        }

        // Locked while this switch was under way (the gate set during its awaits): no frame of a window
        // goes out (`lockedMidSwitch`), and the display gives way to the placeholder (LockPolicy).
        if case .window = source, !lockAllowed.windows { await lockedMidSwitch(source); return }
        if picture == .display, !lockAllowed.display {
            filter = nil; displayScale = nil
            (width, height) = placeholderSize()
            picture = .placeholder
            describe = "a placeholder (this Mac is locked: nothing of it is captured)"
            title = "Locked"; kind = .desktop
        }

        do {
            try await startPipeline(source: source, filter: filter, sourceRect: sourceRect, displayScale: displayScale,
                                    width: width, height: height, describe: describe, title: title, kind: kind, picture: picture)
        } catch {
            // `picked`, not a catalog lookup: a staged window may have left the on-screen list.
            if virtualDisplay, stage.isStaged, let w = picked {
                // The display filter failed to start: send the window home and stream it there.
                print("Capture on the virtual display failed: \(error); retrying with the real window.")
                status.update { $0.lastStageFailure = "capture on the display failed" }
                await stage.releaseHome()
                if comeForward, !shuttingDown, lockAllowed.actsOnWindows { activateAndRaise(window: w) }   // regular mode now: a pick comes forward
                let fallback = "\(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "")\(useSoftwareEncoder ? " (software encoder)" : "")"
                let windowFilter = SCContentFilter(desktopIndependentWindow: w)
                let windowScale = Self.displayScale(of: windowFilter)
                let pixels = CaptureScale.windowSize(w.frame.size, knob: captureScale, displayScale: windowScale)
                if !lockAllowed.windows { await lockedMidSwitch(source); return }   // locked meanwhile: no frame of it either
                do {
                    try await startPipeline(source: source, filter: windowFilter, sourceRect: nil, displayScale: windowScale,
                                            width: pixels.width, height: pixels.height,
                                            describe: fallback, title: title, kind: kind, picture: .window)
                } catch {
                    print("Could not start streaming \(fallback): \(error)")
                    active = .none
                }
            } else if picture == .placeholder {
                // The placeholder's encoder refused (no capture to retry): nothing streams; the device asks
                // for the Desktop again.
                print("Could not start streaming \(describe): \(error)")
                active = .none
            } else if source == .desktop {
                // One more try, from a new look at the displays, with one line (CatalogLook.retryLine).
                await startDesktopAgain(after: error, describe: describe, title: title, kind: kind,
                                        testPattern: (width: width, height: height))
            } else {
                print("Could not start streaming \(describe): \(error)")
                if virtualDisplay { await stage.releaseHome() }   // nothing streams: never leave a window on the virtual display
                active = .none
            }
        }
        broadcastList()
        // Mid-switch requests (a viewport, the last client leaving) are applied by the defer.
    }

    /// Kind 47: the Desktop on the Mac's next stop (DesktopDisplays: the main display first, then each
    /// display to its right, wrapping round), worked out from a fresh look at the displays, then the Mac's
    /// pointer to its centre so the device's arrow shows at once. Ignored unless the Desktop streams, and
    /// mid-switch, so a second quick tap never skips a stop. A step whose stop does not stream goes back to
    /// the choice before it. A test host steps through its SILL_TEST_DISPLAYS and never moves the pointer.
    private func nextDesktopDisplay(askedBy who: String) async {
        guard active == .desktop, !switching else { return }
        // A fresh look at the displays before every step, whatever the last one's age: a display that went since (the
        // stage's, removed as the Desktop came back: "display 1 of 3" with two screens, 2026-11-12) is no stop.
        if !synthetic { await catalog.refreshWindows() }
        let previous = catalog.desktopDisplayUUID
        // Locked during that look (LockPolicy refused kind 47 only as it was read on arrival): no step.
        guard active == .desktop, !switching, !shuttingDown, !lockReading.locked,
              let next = catalog.chooseNextDesktopDisplay() else { return }
        let candidates = catalog.desktopCandidates
        let name = Self.displayName(next)
        print("Desktop: display \(DesktopDisplays.number(of: next.id, in: candidates) ?? 0) of \(candidates.count) (\(name)), asked by \(who).")
        Stats.shared.bump("desk.next")
        await select(.desktop)
        guard !shuttingDown else { return }
        let streamed = active == .desktop
        catalog.chooseDesktopDisplay(DesktopDisplays.afterStep(stepped: next.uuid, previous: previous, streamed: streamed))
        if !streamed {
            // Its start and the one more try failed: the Desktop goes back to the stop it was on, rather
            // than staying black where the button can no longer step from.
            print("Desktop: \(name) did not stream; back to the display it was on.")
            await select(.desktop)
            return
        }
        // A step onto the Virtual Desktop: it is for the device that stepped (plan §5), which it follows in place.
        if catalog.desktopDisplayUUID == DesktopDisplays.virtualDesktopChoice, let asker = desktopAsker {
            adoptVirtualDesktopDevice(stepper: asker)
            lookAtVirtualDesktop()
        }
        // Never a test host's pointer (it posts nothing: the test pattern is not the screen), nor while
        // locked or off console (the console's pointer: the stage's `mayWarp`). The stop as the Desktop shows it now: the
        // Virtual Desktop's has its display (and its frame) only once the step made it.
        guard !synthetic, let shown = catalog.desktopStop, shown.uuid == next.uuid, !lockReading.locked,
              let to = DesktopDisplays.pointerTarget(pointer: CGEvent(source: nil)?.location, on: shown.frame) else { return }
        pointer.sillMoved()
        CGWarpMouseCursorPosition(to)
    }

    /// A stop's name for the log and the devices (NSScreen's, cleaned), else "display 3".
    private static func displayName(_ d: DesktopDisplays.Display) -> String {
        let name = SafeText.label(d.name ?? "", limit: 64)
        return name.isEmpty ? "display \(d.id)" : name
    }

    /// TEST ONLY (SILL_TEST_DISPLAYS, DesktopDisplaysHook): the stop a test host's Desktop shows, its scale
    /// and its words ("display 2 of 3 (DELL U2723QE)"); nil on every other host.
    private func testStop() -> (display: DesktopDisplays.Display, scale: CGFloat, words: String)? {
        guard synthetic, catalog.testDisplays != nil, let stop = catalog.desktopStop,
              let n = DesktopDisplays.number(of: stop.id, in: catalog.desktopCandidates) else { return nil }
        return (stop, testDisplayScales[stop.id] ?? 1, "display \(n) of \(catalog.desktopCandidates.count) (\(Self.displayName(stop)))")
    }

    /// The Desktop follows its display, one follower for every trigger, so one display change restarts it once (the
    /// assessment of 2026-11-18, defect 7: opening the lid restarted it twice, #355's stop follower and #200's size
    /// follower each on its own, the second comparing a size it had read before the first restart). It restarts when it
    /// streams a display other than the stop the catalog shows now (a step, the stop unplugged or back, the main display
    /// changed, this Mac locked or unlocked: `mainOnly`), else when the display it streams changed size under it (the lid
    /// opened: the built-in screen at its default for a moment, then at the person's own; a resolution changed in System
    /// Settings), rather than streaming it scaled into the old size. `look`: macOS's reconfiguration callback, which looks
    /// at the displays first. Both are judged after that look, against what streams then, so a restart made meanwhile is
    /// never made again. Not the placeholder, which captures no display; not mid-switch, whose own end decides; not while
    /// Sill's display is being released, whose own restart moves the Desktop; a test host's test pattern only under
    /// SILL_TEST_DISPLAYS, and never for a size. Not while the Virtual Desktop follows its device in place, whose end
    /// restarts the Desktop once, at the size it ends at (`restartDesktopOnVirtualDesktop`).
    private func followDesktopDisplay(look: Bool = false) async {
        guard active == .desktop, !switching, !shuttingDown, !placeholderStreams, !releasingHeadless, !virtualDesktopResizing,
              synthetic ? catalog.testDisplays != nil : true else { return }
        if look { await catalog.refreshWindows() }
        guard active == .desktop, !switching, !shuttingDown, !placeholderStreams, !releasingHeadless,
              let streams = desktopStreamDisplay else { return }
        if streams != catalog.desktopDisplayID { await select(.desktop); return }
        guard !synthetic, let was = desktopStreamPoints, let d = catalog.display, d.displayID == streams,
              CGSize(width: d.width, height: d.height) != was else { return }
        print("Desktop: the display is \(d.width)×\(d.height) pt now (was \(Int(was.width))×\(Int(was.height))); restarting at its size.")
        await select(.desktop)
    }

    /// The catalog's look, before a capture is built from it (CatalogLook): looked at once more when it
    /// is old (the first pick after a spell with no device), there was none, or its display is no
    /// longer among the active ones. Nil when the last look will do, else why it looked again. One
    /// ScreenCaptureKit call, about 50 ms; while a device keeps the catalog polling, a pick needs none.
    @discardableResult
    private func lookAgainIfStale() async -> CatalogLook.Why? {
        guard let why = CatalogLook.lookAgain(age: catalog.lookAge, display: catalog.display?.displayID,
                                              displaysNow: WindowCatalog.activeDisplayIDs(),
                                              pollInterval: CatalogLook.seconds(WindowCatalog.pollInterval)) else { return nil }
        await catalog.refreshWindows()
        return why
    }

    /// The Desktop's capture as the catalog's newest look has it: its display's filter, with Sill's
    /// own windows left out, the display's scale and the size. The display is read after this
    /// function's own await, so a look that landed meanwhile is the one used: on 2026-10-28 the filter
    /// was built on a display read before an await, which the look that landed during it had replaced
    /// (CatalogLook). Nil when the catalog has no display, or the host is quitting.
    private func desktopCapture() async -> (filter: SCContentFilter, displayID: UInt32, displayScale: CGFloat?, width: Int, height: Int)? {
        // Locked, or another user on the screen, the Desktop is the main display (DesktopDisplays): its lock
        // screen, whatever stop a device chose, which comes back after the unlock. Read now, ahead of the
        // lock's own change (`lockChanged`), so no other display's lock screen is ever built on.
        catalog.mainOnly = lockReading.locked
        guard catalog.display != nil else { return nil }
        // Sill's own windows (Settings, Log, the pairing window with its code) never go out
        // in a Desktop stream. Fixed here at pipeline start: a running SCStream is never
        // reconfigured, so a host that can show a pairing code (remote access) looks for
        // Sill among every window when the last on-screen look missed it; excluding nothing
        // would let a pairing window opened later reach the devices. Without Sill anywhere
        // (the CLI has no windows), as before.
        var resolved: SCRunningApplication? = nil
        if catalog.ownApplication == nil, remote != nil {
            resolved = await catalog.resolveOwnApplication()
            guard !shuttingDown else { return nil }
        }
        guard let d = catalog.display else { return nil }
        let own = catalog.ownApplication ?? resolved      // the newest look's, read with its display
        let displayFilter = own.map { SCContentFilter(display: d, excludingApplications: [$0], exceptingWindows: []) }
            ?? SCContentFilter(display: d, excludingWindows: [])
        // At most the display's own scale: ScreenCaptureKit scales a display up to fill a larger
        // buffer (5120×2880 for a 1x 2560×1440 display: four times the pixels to encode).
        let scale = Self.displayScale(of: displayFilter)
        let pixelScale = CaptureScale.effective(knob: captureScale, displayScale: scale)
        desktopStreamDisplay = d.displayID
        desktopStreamPoints = CGSize(width: d.width, height: d.height)
        return (displayFilter, d.displayID, scale, evenPixels(CGFloat(d.width) * pixelScale), evenPixels(CGFloat(d.height) * pixelScale))
    }

    /// The Desktop's one more try, after a start that failed: from a new look at the displays (the
    /// test pattern has none, so the same start again), with one line (CatalogLook.retryLine). A second
    /// failure is the line as before, and nothing streams; `select` broadcasts either way. On
    /// 2026-10-28 the first start failed on a display gone since the last look, and the host never
    /// tried again.
    private func startDesktopAgain(after error: Error, describe: String, title: String, kind: HostStatusSnapshot.Stream.Kind,
                                   testPattern: (width: Int, height: Int)) async {
        var plan: (filter: SCContentFilter?, displayID: UInt32?, displayScale: CGFloat?, width: Int, height: Int)
            = (nil, nil, nil, testPattern.width, testPattern.height)
        if !synthetic {
            await catalog.refreshWindows()
            guard !shuttingDown, let next = await desktopCapture() else {
                if !shuttingDown { print("Could not start streaming \(describe): \(error)") }   // no display in the new look
                active = .none
                return
            }
            plan = (next.filter, next.displayID, next.displayScale, next.width, next.height)
        }
        // Locked during those awaits (LockPolicy): the placeholder, never the display.
        let locked = !lockAllowed.display
        if locked { plan = (nil, nil, nil, placeholderSize().width, placeholderSize().height) }
        print(CatalogLook.retryLine(source: describe, error: "\(error)", display: plan.displayID))
        do {
            try await startPipeline(source: .desktop, filter: plan.filter, sourceRect: nil, displayScale: plan.displayScale,
                                    width: plan.width, height: plan.height,
                                    describe: locked ? "a placeholder (this Mac is locked: nothing of it is captured)" : describe,
                                    title: locked ? "Locked" : title, kind: kind, picture: locked ? .placeholder : .display)
        } catch {
            print("Could not start streaming \(describe): \(error)")
            active = .none
        }
    }

    /// Encoder, then capture (ScreenCaptureKit for a filter, the test pattern without one), then
    /// `active`. Throws with `active` untouched if either refuses; the caller decides what to do.
    /// `title` and `kind` describe the stream in the app's menu. `displayScale`: the source's display's
    /// own pixel scale (nil for the test pattern), which `width` and `height` were held to
    /// (CaptureScale) and the injector lands input by (InputLanding). `picture`: what the frames show, for
    /// the server's gate (LockPolicy.withheld), which drops a window's and the display's from the moment
    /// the Mac reads locked; the placeholder's (a locked Mac's black still, `StillCapture`) always go.
    private func startPipeline(source: StreamSource, filter: SCContentFilter?, sourceRect: CGRect?, displayScale: CGFloat?,
                               width: Int, height: Int, describe: String,
                               title: String, kind: HostStatusSnapshot.Stream.Kind, picture: LockPolicy.Picture) async throws {
        let asked = (width: width, height: height)
        var width = width, height = height
        if !useSoftwareEncoder {
            let fit = Self.hardwareFit(width, height)
            if fit != asked {
                print("This Mac's hardware video encoder doesn’t take \(width)×\(height): streaming \(describe) at \(fit.width)×\(fit.height), scaled down.")
                (width, height) = fit
            }
        }
        let enc = try HEVCEncoder(width: width, height: height, fps: fps, bitrate: streamBitrate, prioritizeSpeed: prioritizeSpeed,
                                  software: useSoftwareEncoder)
        enc.onHung = { [weak self, weak enc] in
            Task { @MainActor in
                guard let enc else { return }
                await self?.encoderHung(enc)
            }
        }
        let server = self.server
        enc.onEncoded = { [weak self] data, isKey, parameterSets in
            let now = Date().timeIntervalSince1970
            if let ps = parameterSets {
                let sets = ps.encoded()
                server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: sets), picture: picture)
                // Every keyframe repeats them; a new frame size goes out with the first that differ.
                let sentAt = CFAbsoluteTimeGetCurrent()
                Task { @MainActor in self?.parameterSetsSent(sets, at: sentAt) }
            }
            server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: isKey, payload: data), picture: picture)
        }
        if source == .desktop, picture != .placeholder, desktopStartsToFail > 0 {
            // TEST ONLY (SILL_TEST_DESKTOP_FAIL, a --synthetic host): this start fails where the capture
            // would start, after the encoder was made, as ScreenCaptureKit's did on 2026-10-28.
            desktopStartsToFail -= 1
            throw NSError(domain: "CoreGraphicsErrorDomain", code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Start stream failed (TEST ONLY: SILL_TEST_DESKTOP_FAIL)"])
        }
        if picture == .placeholder {
            // A locked Mac: a black still, no ScreenCaptureKit, nothing of the Mac (StillCapture).
            stillCapture.onFrame = { pixelBuffer, pts in enc.encode(pixelBuffer, pts: pts) }
            stillCapture.start(width: width, height: height)
        } else if let filter {
            capture.onFrame = { pixelBuffer, pts in enc.encode(pixelBuffer, pts: pts) }
            try await capture.start(filter: filter, width: width, height: height, fps: fps, showsCursor: false, sourceRect: sourceRect,
                                    scaleWords: CaptureScale.words(knob: captureScale, displayScale: displayScale))
        } else {
            syntheticCapture.onFrame = { pixelBuffer, pts in enc.encode(pixelBuffer, pts: pts) }
            syntheticCapture.start(width: width, height: height, fps: fps)
        }
        encoder = enc
        encoderAsked = asked
        placeholderStreams = picture == .placeholder
        active = source
        streamDisplayScale = displayScale
        injector.displayScale = displayScale
        print("Streaming \(describe) at \(width)×\(height), \(fps) fps, \(streamBitrate / 1_000_000) Mbps")
        // The card names Sill's own display when the Desktop shows it (a Mac with no working screen).
        let onSills = kind == .desktop && picture == .display && headlessDisplay != nil && desktopOnSills(desktopStreamDisplay)
        status.update {
            $0.stream = HostStatusSnapshot.Stream(kind: kind, title: title, width: width, height: height, fps: fps,
                                                  mbps: streamBitrate / 1_000_000, onVirtualDisplay: sourceRect != nil,
                                                  softwareEncoder: useSoftwareEncoder, onSillDisplay: onSills)
        }
        // Frames can reach the encoder while `capture.start` is still awaiting, so its watchdog
        // may already have fired, and that report was ignored (no current encoder yet).
        if enc.isDead { Task { @MainActor in await self.encoderHung(enc) } }
    }

    // MARK: Bringing the target forward
    //
    // On select, regular mode raises the picked window (`activateAndRaise`, 2026-09-23, Noah: the
    // Mac must show the picked window). A window staged on the virtual display never touches Mac
    // focus on select (a pick that falls back to the real window is regular mode), and neither do
    // the host's own restarts. On interaction, both modes do what a real click does: a click,
    // keystroke or typed text into the streamed window first activates its app, because keys go to
    // the active app's key window and a first click into an inactive app is otherwise eaten as
    // "activate". On the regular path the window is also raised when another window covers the
    // click or scroll point, so the event reaches it and it repaints; on the virtual display a
    // cover can only be a stranger, which is moved off instead. Activation is Accessibility only
    // (the direct NSRunningApplication call is refused from a background process since macOS 14,
    // and a Launch Services "open" trips app-based Focus automations); the app comes up a moment
    // later, so the events that triggered it are held and replayed in order once it is up. A pick always goes
    // through Accessibility. Interaction stays cheap: one frontmost lookup per half second at
    // most, and Accessibility only when the app is not active or a cover is found. An app that
    // lets the activation run into its timeout (a beach ball) gets no further AX calls from
    // either: each would hold the main actor for another second.
    /// Consecutive catalog polls the streamed window has been missing from the list while it may be
    /// entering or leaving full screen: the staged full-screen window, or in regular mode one that was
    /// full screen when last listed or that Sill fitted (`windowsChanged`).
    private var missingPolls = 0
    private var lastRaiseCheck: CFAbsoluteTime = 0
    private var lastActivationAt: CFAbsoluteTime = 0
    /// Input held for an activation, replayed in order once the app is up, each with the device that
    /// sent it (its keys are its own, KeyStrokes); a gesture's chord that arrives meanwhile waits
    /// behind it, so a click just before the gesture lands first. A device the Mac no longer serves, or
    /// one that left while it waited (`gone`), gets only the up of what it holds down (RevokedInput)
    /// and none of its chords.
    private enum Held { case input(InputEvent, CGRect, KeyStrokes.Device), chord(keyCode: UInt16, flags: UInt64, device: KeyStrokes.Device) }
    private var heldInput: [Held] = []
    private var holdUntil: CFAbsoluteTime = 0
    /// Devices that left while input was held: their keys go up after it (`releaseKeys`), and the
    /// buttons of one the Mac no longer served (`revoked`).
    private var leftWhileHeld: [(device: KeyStrokes.Device, revoked: Bool)] = []
    /// How long held input waits for the app to become frontmost before it is replayed anyway.
    private static let activationTimeout: TimeInterval = 0.6

    private func deliver(_ event: InputEvent, in rect: CGRect, from device: KeyStrokes.Device) {
        // Queue while holding, and while anything is still queued, so order is never inverted.
        if !heldInput.isEmpty || CFAbsoluteTimeGetCurrent() < holdUntil { heldInput.append(.input(event, rect, device)); return }
        logClick(event, in: rect)
        injector.apply(event, in: rect, from: device)
    }

    private func releaseHeldInput() {
        holdUntil = 0
        let held = heldInput
        heldInput = []
        for item in held {
            switch item {
            case .input(let event, let rect, let device):
                // Held for the streamed window's app, which a locked Mac no longer streams (LockPolicy):
                // whoever sent it, only the up of what it holds down still goes, where the pointer is.
                if gone(device) || lockReading.locked {
                    if injector.releasesWhatItHolds(event, from: device) { injector.apply(event, in: .null, from: device) }
                    else { Stats.shared.bump(gone(device) ? "in.revoked" : "in.locked") }
                    continue
                }
                logClick(event, in: rect); injector.apply(event, in: rect, from: device)
            case .chord(let keyCode, let flags, let device):
                if gone(device) { Stats.shared.bump("in.revoked"); continue }
                if !lockAllowed.gestures { Stats.shared.bump("in.locked"); continue }   // no gesture at a locked Mac
                injector.chord(keyCode: keyCode, flags: flags)
            }
        }
        releaseKeysOfDevicesThatLeft()
    }

    /// A device the Mac no longer serves (`revoked`), or one that left while input was held
    /// (`leftWhileHeld`): of what it sent, only the up of a key or a button it holds down still goes.
    private func gone(_ device: KeyStrokes.Device) -> Bool {
        revoked.contains(device) || leftWhileHeld.contains { $0.device == device }
    }

    /// A device the lock's reading does not let type (LockPolicy.takesInput: an unpaired one at a locked
    /// screen, every one off console): of its input only the up of a key or a button it holds down still
    /// goes, as of a device the Mac no longer serves.
    private func lockedOut(_ device: KeyStrokes.Device) -> Bool {
        let r = lockReading
        return r.locked && !LockPolicy.takesInput(r, paired: sessionPaired(device))
    }

    /// StreamServer marked this device revoked (`closeSessions`). Ignored once it has left (no route):
    /// its identifier may be a later connection's by then.
    private func clientRevoked(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard routes[id] != nil else { return }
        markRevoked(id)
    }

    /// RemoteAccess cut these devices off (Remove, Require pairing turned on, Remote Access or internet
    /// access turned off), on the main actor as it decided: each connection whose route `matching`
    /// names is marked now, so its messages still waiting for the main actor (read off the network
    /// while the Mac saved the change, the keychain's write) land nothing either. The server marks each
    /// again as it says goodbye (`clientRevoked`). A connection whose registration still waits here (one
    /// admitted while the Mac was saving the change) is marked as it registers, before any message of it
    /// (RemoteAccess.stillServes, `onClientConnected`).
    private func cutOff(_ matching: (ClientRoute) -> Bool) {
        for (id, route) in routes where matching(route) { markRevoked(id) }
    }

    private func markRevoked(_ id: ObjectIdentifier) {
        guard revoked.insert(id).inserted else { return }
        // A menu choice or fetch of it still waiting for its turn is neither made nor read.
        menus.clientRevoked(id)
        // TEST ONLY (SILL_TEST_INPUT_LOG, a synthetic host): where its input stops landing, so a test
        // reads what was posted for it after this line.
        if injector.testLog {
            let device = status.snapshot.devices.first { $0.id == id }
            print("Test input: \(device?.name ?? device?.endpoint ?? "a device") is no longer served: only the up of a key or a button it holds down goes from here on.")
        }
    }

    /// A device left: the keys it still holds down on the Mac go up (InputInjector.releaseKeys), and
    /// the buttons of one the Mac no longer served (`revoked`: RevokedInput.buttonsLetGo), after
    /// whatever of its input is still held for an activation, so no up of its own is overtaken and no
    /// down of its own comes after.
    private func releaseKeys(of device: KeyStrokes.Device) {
        let wasRevoked = revoked.contains(device)
        if !heldInput.isEmpty || CFAbsoluteTimeGetCurrent() < holdUntil { leftWhileHeld.append((device, wasRevoked)); return }
        injector.releaseKeys(of: device, revoked: wasRevoked)
    }

    private func releaseKeysOfDevicesThatLeft() {
        let left = leftWhileHeld
        leftWhileHeld = []
        for (device, wasRevoked) in left { injector.releaseKeys(of: device, revoked: wasRevoked) }
    }

    /// Where a held key's repeat would land now (InputInjector.repeatLanding, KeyRepeat), as a
    /// device's input lands: nowhere while it has nowhere to land (nothing streams, or the source's
    /// rectangle cannot be read: the repeat stops), held while input waits for an app's activation (a
    /// repeat must not go out ahead of it), else on the source.
    private func keyRepeatLanding() -> KeyRepeat.Landing {
        guard currentSourceRect() != nil else { return .nowhere }
        if !heldInput.isEmpty || CFAbsoluteTimeGetCurrent() < holdUntil { return .held }
        return .lands
    }

    private func raiseIfInteracting(_ event: InputEvent) {
        // Nothing mid-switch, pick or restart: `active` names the old source until capture has
        // started, and by then a pick has already raised the new window. Raising or activating
        // the old one here would put it back in front of the pick (a flick's momentum scroll keeps
        // arriving through a tap on the switcher). The event itself is still delivered, so no
        // key-up or button-up goes missing.
        guard !switching, case .window(let id) = active else { return }
        // Scroll routes to the window under the cursor whatever the active app is: it only needs
        // uncovering (regular path). Clicks, keys and text need the app active and the window key.
        let needsFocus: Bool
        switch event {
        case .pointer(let action, _, _): guard action == .leftDown || action == .rightDown else { return }; needsFocus = true
        case .scroll: needsFocus = false
        case .scrollGesture(let phase, _, _): guard phase == .began else { return }; needsFocus = false
        case .key(_, let down, _): guard down else { return }; needsFocus = true
        case .text: needsFocus = true
        }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRaiseCheck > 0.5 else { return }     // a burst of keys or scroll ticks is one check
        lastRaiseCheck = now
        let staged = virtualDisplay && stage.isStaged
        guard let pid = staged ? stage.placement?.pid : catalog.window(id: id)?.owningApplication?.processID else { return }
        // `NSWorkspace.frontmostApplication` is stale in a process without an AppKit run loop
        // (measured: it named an app that had not been active for minutes), so it is only used
        // under that loop (the app; the CLI's --virtual-display). Otherwise the active app is read
        // off the window list: the owner of the topmost layer-0 window. Covered = another app's
        // window under the click point.
        let point = injectorProbePoint(event)
        let cover = point.flatMap { Self.topmostWindow(at: $0) }
        let covered = cover != nil && cover?.id != id && !(staged && cover?.pid == pid)   // on the stage, the app's own sheet or new tab (#366) is not a stranger
        // On the virtual display a cover is a stranger (a window left there by an earlier run):
        // move it off, then the click lands.
        if staged, covered { stage.evictForeignWindows() }
        let notActive = needsFocus && Self.activePID(trustAppKit: appKitLoop) != pid
        guard notActive || covered else { return }
        // A failed activation must not stall every later interaction: one attempt per 2 s.
        guard now - lastActivationAt > 2 else { return }
        lastActivationAt = now
        // An app that let the activation run into its timeout gets no more AX calls, each of which
        // would wait out another second; the hold below still applies.
        let answered = notActive ? activate(pid: pid) : true
        // The streamed window must also be the app's key window, or its first click only makes it
        // key (acceptsFirstMouse is false for most controls). Raising lifts it above the cover.
        // One window lookup serves both.
        if answered {
            if staged, let element = stage.placement?.element {
                if needsFocus { WindowSizer.makeKey(element) }
            } else if let w = catalog.window(id: id), let element = sizer.element(for: w) {
                if needsFocus { WindowSizer.makeKey(element) }
                if covered, WindowSizer.raise(element) { Stats.shared.bump("win.raised") }
            }
        }
        holdUntil = now + Self.activationTimeout
        Task { @MainActor in
            // Replay as soon as our window is the one under the click (usually 50–200 ms), or at
            // the timeout. On the virtual display nothing can cover it: wait for activation only.
            let deadline = CFAbsoluteTimeGetCurrent() + Self.activationTimeout
            while CFAbsoluteTimeGetCurrent() < deadline {
                let active = Self.activePID(trustAppKit: self.appKitLoop) == pid
                let onTop = staged || point.flatMap { Self.topmostWindow(at: $0) }?.pid == pid
                if active && onTop { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            self.releaseHeldInput()
        }
    }

    /// A pick in regular mode: the window comes forward on the Mac as if clicked there. Its app is
    /// activated, the window raised to the front and made key, so capture starts on an uncovered
    /// window and typed keys go to it. `raiseIfInteracting`'s throttle is left alone: a click
    /// right after a pick that finds the app not up yet still activates and holds as usual.
    /// Every AX call here is synchronous on the main actor, and a hung app (a beach ball, a
    /// debugger pause) holds every device's input and the catalog for a second per call: raise
    /// and key share one window lookup, and none is made once the activation ran into its timeout.
    private func activateAndRaise(window w: SCWindow) {
        guard let pid = w.owningApplication?.processID else { return }
        guard activate(pid: pid) else {
            print("\(w.owningApplication?.applicationName ?? "?") is not answering Accessibility; its window is not raised.")
            return
        }
        guard let element = sizer.element(for: w) else { return }
        if WindowSizer.raise(element) { Stats.shared.bump("win.raised") }
        WindowSizer.makeKey(element)
    }

    /// Makes `pid` the active app, through Accessibility only: synchronous, and it touches only this
    /// app's ordering. Never through Launch Services: "opening" an already-running app that way
    /// counts as opening it, and it switched on Noah's Work Focus (an app-based Focus automation)
    /// every time (2026-09-22 and 23). If AX refuses, the app stays where it is and the raise below
    /// still runs. False when the app did not answer at all, so the caller makes no further AX
    /// calls into it. Only a call that ran out the whole timeout counts: `.cannotComplete` is also
    /// a quick refusal from a live app, whose window may still take a raise.
    private func activate(pid: pid_t) -> Bool {
        let timeout: Float = 1.0
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        let started = CFAbsoluteTimeGetCurrent()
        let err = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if err == .success {
            Stats.shared.bump("win.activated")
            return true
        }
        Stats.shared.bump("win.activateRefused")
        let timedOut = err == .cannotComplete && CFAbsoluteTimeGetCurrent() - started >= Double(timeout) * 0.9
        if timedOut { Stats.shared.bump("win.axTimeout") }
        return !timedOut
    }

    /// One line per second at most: where a click lands on the Mac and which window is there,
    /// against the one being streamed. The quickest way to see a mapping or ordering problem.
    private var lastClickLog: CFAbsoluteTime = 0
    private func logClick(_ event: InputEvent, in rect: CGRect) {
        guard case .pointer(let action, let x, let y) = event, action == .leftDown || action == .rightDown,
              case .window(let id) = active else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastClickLog > 1 else { return }
        lastClickLog = now
        let p = InputLanding.point(x: x, y: y, in: rect, displayScale: streamDisplayScale)
        let top = Self.topmostWindow(at: p)
        let verdict = top?.id == id ? "the streamed window" : "window \(top.map { String($0.id) } ?? "none"), not the streamed \(id)"
        print("Click at (\(Int(p.x)),\(Int(p.y))) in (\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width))×\(Int(rect.height))) → \(verdict)")
    }

    /// The screen point an interaction lands on (for the topmost-window check); nil for keys.
    private func injectorProbePoint(_ event: InputEvent) -> CGPoint? {
        guard let rect = currentSourceRect() else { return nil }
        switch event {
        case .pointer(_, let x, let y), .scroll(let x, let y, _, _), .scrollGesture(_, let x, let y):
            return InputLanding.point(x: x, y: y, in: rect, displayScale: streamDisplayScale)
        default: return nil
        }
    }

    /// The on-screen layer-0 window under `point` (any point when nil, i.e. the frontmost normal
    /// window on screen) and its owner, or nil when unknown.
    private static func topmostWindow(at point: CGPoint?) -> (id: CGWindowID, pid: pid_t)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {   // front to back
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,   // invisible overlays are not covers
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if let point, !rect.contains(point) { continue }
            return (id, pid)
        }
        return nil
    }

    /// The active app's pid. AppKit's answer only when this process runs the AppKit loop (the
    /// app, or the CLI's --virtual-display); otherwise the owner of the frontmost normal window,
    /// which is what the window server considers active for input.
    private static func activePID(trustAppKit: Bool) -> pid_t? {
        if trustAppKit, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { return pid }
        return topmostWindow(at: nil)?.pid
    }

    /// The Resolution knob of the pair that runs: Retina normally; points when the software encoder is
    /// carrying the stream. A capture runs at it held to its display's own scale (CaptureScale).
    private var captureScale: CGFloat { useSoftwareEncoder ? min(scale, 1.0) : scale }

    /// The pixels a point the running pipeline captures at: the knob held to its display's own scale.
    private var streamPixelScale: CGFloat { CaptureScale.effective(knob: captureScale, displayScale: streamDisplayScale) }

    /// A filter's display scale as ScreenCaptureKit gives it (`pointPixelScale`: the scale it draws that
    /// content at), nil when it gives none.
    private static func displayScale(of filter: SCContentFilter) -> CGFloat? {
        CaptureScale.displayScale(pointPixelScale: filter.pointPixelScale)
    }

    /// The display scale ScreenCaptureKit has for `w` as it is, in regular mode: its filter's, made afresh.
    private static func displayScale(of w: SCWindow) -> CGFloat? {
        displayScale(of: SCContentFilter(desktopIndependentWindow: w))
    }

    /// The pixels a point a capture of `w` would run at now, in regular mode: the knob held to the
    /// scale ScreenCaptureKit has for the window as it is.
    private func capturePixelScale(of w: SCWindow) -> CGFloat {
        CaptureScale.effective(knob: captureScale, displayScale: Self.displayScale(of: w))
    }

    /// "Safari — Apple Developer" for the app's menu; just the app for an untitled window.
    private static func menuTitle(for w: SCWindow) -> String {
        let app = w.owningApplication?.applicationName ?? "?"
        let title = w.title ?? ""
        return title.isEmpty ? app : "\(app) — \(title)"
    }

    // MARK: The Mac's menus (MenuMirror; docs/menu-bar-plan.md §4.5)
    //
    // Which app's menus a device is shown: the streamed window's, or on the Desktop the frontmost
    // app's (never Sill's own: a device's "Quit Sill" would end the host). The mirror hears of a
    // change only while a device subscribes; with none, `menuTargetChanged` is one comparison.

    /// The app behind the current source, for the menus: nil for nothing streaming and for Sill, and
    /// while this Mac is locked (LockPolicy: a subscriber's top level is then empty).
    private func menuTarget() -> MenuMirror.Target? {
        guard lockAllowed.actsOnWindows else { return nil }      // none in the off-console view either
        switch active {
        case .none:
            return nil
        case .window(let id):
            if virtualDisplay, let p = stage.placement, p.windowID == id {
                return p.pid == WindowCatalog.ownPID ? nil : Self.menuTarget(pid: p.pid, window: id)
            }
            guard let app = catalog.window(id: id)?.owningApplication, app.processID != WindowCatalog.ownPID else { return nil }
            return Self.menuTarget(pid: app.processID, window: id)
        case .desktop:
            return desktopMenuTarget()
        }
    }

    /// The Desktop's: the frontmost app (AppKit's under its loop, else the owner of the topmost
    /// window; see `activePID`). A synthetic host has none, but for the TEST ONLY hook's process.
    private func desktopMenuTarget() -> MenuMirror.Target? {
        if synthetic {
            guard let pid = testMenuPID, MenuReader.alive(pid) else { return nil }
            return Self.menuTarget(pid: pid)
        }
        guard let pid = Self.activePID(trustAppKit: appKitLoop), pid != WindowCatalog.ownPID else { return nil }
        return Self.menuTarget(pid: pid)
    }

    /// One name for an app whichever source names it (the window list's and AppKit's can differ).
    private static func menuTarget(pid: pid_t, window: CGWindowID? = nil) -> MenuMirror.Target {
        let app = NSRunningApplication(processIdentifier: pid)
        return MenuMirror.Target(pid: pid, app: app?.localizedName ?? "pid \(pid)", bundleID: app?.bundleIdentifier, window: window)
    }

    /// The source, or the Desktop's frontmost app, may have changed.
    private func menuTargetChanged() {
        guard menus.hasSubscribers else { return }
        menus.setTarget(menuTarget())
    }

    /// Every catalog poll (2 s) while a device is connected: the menus, and a window streaming in
    /// regular mode that moved onto a display of another scale. That keeps its size in points, so the
    /// list does not change and `windowsChanged` never hears of it, and its capture would go on at the
    /// old display's scale (from a 2x display onto a 1x one at Retina: the window in the top-left
    /// quarter of the picture). Only the scale is compared here, never the size, which a list read
    /// before a fit landed can still give at its old value; a resize is `windowsChanged`'s.
    private func catalogPolled() {
        menusPolled()
        if !switching, !shuttingDown, case .window(let id) = active, catalog.tabSwaps[id] != nil {
            Task { @MainActor in _ = await self.followTabSwap(for: id) }
            return
        }
        guard !switching, !shuttingDown, case .window(let id) = active, !(virtualDisplay && stage.isStaged),
              let w = catalog.window(id: id), capturePixelScale(of: w) != streamPixelScale else { return }
        Task { @MainActor in
            guard !self.switching, self.active == .window(id) else { return }
            await self.select(.window(id))
        }
    }

    /// Sill's display goes once a real screen has worked two seconds (HeadlessDesktopPolicy.Watch.release), the lid
    /// closed and a device connected too: it exists only while no real screen works. Asked at every display change
    /// (macOS's reconfiguration callback, which fires with no device connected too), when the last device leaves, and
    /// at the end of the two seconds (`scheduleReleaseCheck`). The Desktop restarts on the real screen first, so its
    /// capture never loses the display under it, then Sill's display goes and macOS brings the windows it moved there
    /// back. Removing it is a display change, which macOS may lock a closed-lid Mac on (the reason the rule before
    /// this kept it while a device worked with the lid shut); a real screen works then, so the password typed on a
    /// device works there as in 0.6.1.
    private func releaseHeadlessDisplayIfDone() {
        // The Virtual Desktop's own rules govern it while it is that (VirtualDesktopLife: a real screen works then).
        guard hasHeadlessDisplay, !releasingHeadless, !shuttingDown, desktopLife.role != .virtualDesktop else { return }
        lookAtDisplays()
        switch displayWatch.release(now: CFAbsoluteTimeGetCurrent()) {
        case .keep:
            releaseCheck?.cancel(); releaseCheck = nil
            return
        case .wait(let until):
            scheduleReleaseCheck(at: until)
            return
        case .release:
            releaseCheck?.cancel(); releaseCheck = nil
        }
        releasingHeadless = true
        Task { @MainActor in
            defer { self.releasingHeadless = false; self.catalog.keepsSills = self.hasHeadlessDisplay }
            // A switch under way first (a pick, a restart): `select` would return at once, and the display
            // would go from under the capture that switch starts. At most 5 s.
            for _ in 0..<100 where self.switching { try? await Task.sleep(for: .milliseconds(50)) }
            // Looked at again after the wait: a screen that went meanwhile keeps the display, and the Desktop on it.
            guard self.releaseStillDue() else { return }
            // Only while the Desktop streams does the capture move to the real screen first; otherwise nothing
            // captures Sill's display.
            if self.active == .desktop {
                self.catalog.keepsSills = false
                // The look first: a fresh one still has the fallback display as the Desktop's (11:38:45, 2026-11-02).
                await self.catalog.refreshWindows()
                for _ in 0..<100 where self.switching { try? await Task.sleep(for: .milliseconds(50)) }
                if self.active == .desktop, self.releaseStillDue() {
                    await self.select(.desktop)
                }
            }
            guard self.hasHeadlessDisplay, self.releaseStillDue() else {
                // Kept after all (the screen went again during the restart): the Desktop goes back to it.
                self.catalog.keepsSills = self.hasHeadlessDisplay
                for _ in 0..<100 where self.switching { try? await Task.sleep(for: .milliseconds(50)) }
                if self.active == .desktop { await self.catalog.refreshWindows(); await self.select(.desktop) }
                return
            }
            self.removeHeadlessDisplay()
        }
    }

    /// The release's rule on a fresh look; never for the Virtual Desktop (a device may have stepped onto it meanwhile).
    private func releaseStillDue() -> Bool {
        lookAtDisplays()
        lookAtVirtualDesktop()
        return desktopLife.role != .virtualDesktop && displayWatch.release(now: CFAbsoluteTimeGetCurrent()) == .release
    }

    /// One look at `time`, the end of a real screen's two seconds (`Watch.release`'s wait); a newer ask replaces it.
    private func scheduleReleaseCheck(at time: Double) {
        releaseCheck?.cancel()
        releaseCheck = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, time - CFAbsoluteTimeGetCurrent()) + 0.01))
            guard !Task.isCancelled else { return }
            self.releaseCheck = nil
            self.releaseHeadlessDisplayIfDone()
        }
    }

    private func removeHeadlessDisplay(line: String = "Headless display: a display is online again; removed the virtual Desktop display.") {
        let said = testHeadlessMade && headlessDisplay == nil
        displays.remove(.desktop)
        desktopLife.removed(at: CFAbsoluteTimeGetCurrent())     // a change of the Desktop's display, for the spacing
        headlessHz = nil
        status.update { $0.sillDisplay = nil }
        lookAtDisplays(changed: true)
        print(line + (said ? " (TEST ONLY: none was made.)" : ""))
    }

    /// Sill's display goes at once, not after a real screen's two seconds (`Watch.release`), with `line`, while `still`
    /// holds after a switch under way (at most 5 s); never while its release is under way, which ends it anyway:
    /// - off console (docs/virtual-desktop-plan.md §2 and §10, LockPolicy.makesDesktopDisplay): it would be the displays
    ///   of the user now on the screen, and a Sill in their session would make one of its own beside it, of the same
    ///   identity. Off console the Desktop streams the placeholder, which captures no display; with the off-console view
    ///   it streams the main display, so it starts again, once, on what is left. Back on the console with no screen, the
    ///   Desktop asks for it again and it is made two seconds after the return (`Watch.cameBack`);
    /// - its switch turned off in Settings › Virtual Display (`headlessSwitched`): the Desktop starts again, once, on what
    ///   macOS shows (its stand-in on a Mac with no screen), and none is made until the switch is on again.
    private func removeHeadlessAtOnce(line: String, still: () -> Bool) async {
        for _ in 0..<100 where switching { try? await Task.sleep(for: .milliseconds(50)) }
        // Not the Virtual Desktop: its own rules remove it (off console at once, its switch: `lookAtVirtualDesktop`).
        guard hasHeadlessDisplay, !releasingHeadless, !shuttingDown, desktopLife.role != .virtualDesktop, still() else { return }
        releaseCheck?.cancel(); releaseCheck = nil
        catalog.keepsSills = false
        removeHeadlessDisplay(line: line)
        guard active == .desktop, !placeholderStreams, !switching else { return }
        await catalog.refreshWindows()
        await select(.desktop)
    }

    /// macOS's display changes (the lid opened, a monitor plugged in, back from a user switch), for the watch, for
    /// `releaseHeadlessDisplayIfDone` and for the Desktop's display (`followDesktopDisplay`): SillDisplays' one
    /// reconfiguration callback, never removed, its context unretained: safe only while one coordinator (and its
    /// SillDisplays) lives as long as the process, which AppModel and the CLI each make once (the assessment of
    /// 2026-11-18, note 11); a second coordinator would need it undone first.
    private func watchDisplayChanges() {
        displays.watchReconfiguration { [weak self] in
            guard let self else { return }
            self.lookAtDisplays(changed: true)
            self.lookAtVirtualDesktop()             // its role, the never-main rule (VirtualDesktopLife)
            self.releaseHeadlessDisplayIfDone()
            await self.followDesktopDisplay(look: true)
        }
    }

    /// A wake (the Mac, or its displays): what this session sees may still be changing, so Sill's display waits
    /// (`Watch.cameBack`). The screens' sleep and wake (macOS's display sleep, NSWorkspace's screensDidSleep and
    /// screensDidWake): Sill's display is never made while they sleep, and the wake asks again (`Watch.make`'s
    /// `.asleep`, `screensWoke`). A test host with SILL_TEST_HEADLESS takes its screens from its file alone, never
    /// from this Mac's. Never removed, as `watchDisplayChanges`.
    private func watchWakes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.screensDidSleepNotification] {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sleep = note.name == NSWorkspace.screensDidSleepNotification
                let screens = sleep || note.name == NSWorkspace.screensDidWakeNotification
                Task { @MainActor in
                    guard let self, self.testHeadlessFile == nil else { return }
                    if !sleep { self.displayWatch.cameBack(at: CFAbsoluteTimeGetCurrent()) }
                    guard screens else { return }
                    self.screensSaidAsleep = sleep
                    self.lookAtDisplays()
                }
            }
        }
    }

    /// The screens woke (a look found them awake after asleep: NSWorkspace's screensDidWake, a test host's file). A
    /// Desktop that streams with no real screen and no Sill's display (macOS's stand-in: Sill's display waited for the
    /// wake, `Watch.Make.asleep`) starts again, so Sill's display is made two seconds after the wake if no real screen
    /// came back with it (HeadlessDesktopPolicy.desktopAgainAtWake). Nothing streaming is left to the device's own
    /// requests. A switch under way first, at most 5 s: its select may have judged before the wake.
    private func screensWoke() {
        saidWaitsForWake = false
        Task { @MainActor in
            for _ in 0..<100 where self.switching { try? await Task.sleep(for: .milliseconds(50)) }
            guard !self.switching, !self.shuttingDown, !self.releasingHeadless else { return }
            self.lookAtDisplays()           // after the wait: the displays as they are now
            guard HeadlessDesktopPolicy.desktopAgainAtWake(streamsDesktop: self.active == .desktop, sills: self.hasHeadlessDisplay,
                                                           gate: self.headlessGateAllows()) else { return }
            await self.select(.desktop)
        }
    }

    /// TEST ONLY (SILL_TEST_HEADLESS): a change of the test's file is a display change, as macOS's callback says one
    /// (none fires for a file): read every 0.1 s on a test host that has the file, never on any other.
    private func watchTestHeadless() {
        guard let path = testHeadlessFile else { return }
        // The `screens asleep` line's coming and going are macOS's two notifications (screensDidSleep, screensDidWake):
        // read once now, before the first look, then at each change.
        let initial = HeadlessDesktopPolicy.testHeadlessList((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").screensAsleep
        screensSaidAsleep = initial
        Task { @MainActor in
            var last: String?
            var saidAsleep = initial
            while !self.shuttingDown {
                let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                if let last, last != text {
                    let said = HeadlessDesktopPolicy.testHeadlessList(text).screensAsleep
                    if said != saidAsleep { saidAsleep = said; self.screensSaidAsleep = said }
                    self.lookAtDisplays(changed: true)
                    self.lookAtVirtualDesktop()
                    self.releaseHeadlessDisplayIfDone()
                }
                last = text
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Every catalog poll (2 s) while a device is connected.
    private func menusPolled() {
        guard menus.hasSubscribers else { return }
        if active == .desktop { menuTargetChanged() }
        menus.catalogPolled()
    }

    /// A device's click or key on the Desktop can bring another app forward (50–200 ms later): its
    /// menus are looked at again 0.3 s after, at most once per 0.5 s.
    private func desktopInputMayActivate(_ event: InputEvent) {
        guard active == .desktop, menus.hasSubscribers, !menuFrontCheckPending else { return }
        switch event {
        case .pointer(let action, _, _): guard action == .leftDown || action == .rightDown else { return }
        case .key(_, let down, _): guard down else { return }
        default: return
        }
        menuFrontCheckPending = true
        let wait = max(0.3, menuFrontCheckAt + 0.5 - CFAbsoluteTimeGetCurrent())
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            self.menuFrontCheckPending = false
            self.menuFrontCheckAt = CFAbsoluteTimeGetCurrent()
            if self.active == .desktop { self.menuTargetChanged() }
        }
    }

    /// Under the AppKit loop (Sill.app, the CLI's --virtual-display), while a device subscribes:
    /// the Desktop's menus follow an app activated on the Mac at once, not at the next poll.
    private func watchFrontmostApp(_ on: Bool) {
        guard appKitLoop else { return }
        if on, frontmostObserver == nil {
            frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.active == .desktop else { return }
                    self.menuTargetChanged()
                }
            }
        } else if !on, let observer = frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontmostObserver = nil
        }
    }

    /// Before a menu of a window source is read or one of its items pressed: its app active and the
    /// window key, as a click from the device makes them (`raiseIfInteracting`: Accessibility only,
    /// one activation attempt per 2 s, never Launch Services). An inactive app's states differ (its
    /// Copy, Close and Minimize read disabled: the probe), and a press must act on the streamed
    /// window, not another of the app's. No raise: a menu needs the app active, not the window
    /// uncovered. True when the app is frontmost as this returns. The Desktop's app is frontmost
    /// already, and a synthetic host's hook is never activated: true at once for both and for
    /// nothing. During a switch (`active` still names the old source) nothing is activated.
    private func focusForMenus() async -> Bool {
        guard case .window(let id) = active else { return true }
        let staged = virtualDisplay && stage.isStaged
        guard let pid = staged ? stage.placement?.pid : catalog.window(id: id)?.owningApplication?.processID else { return false }
        let frontmost = Self.activePID(trustAppKit: appKitLoop) == pid
        if switching { return frontmost }
        var answered = true
        if !frontmost {
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastActivationAt > 2 else { return false }
            lastActivationAt = now
            answered = activate(pid: pid)
        }
        // An app that let the activation run into its timeout gets no more AX calls from here.
        guard answered else { return false }
        if staged, let element = stage.placement?.element {
            WindowSizer.makeKey(element)
        } else if let w = catalog.window(id: id), let element = sizer.element(for: w) {
            WindowSizer.makeKey(element)
        }
        if frontmost { return true }
        let deadline = CFAbsoluteTimeGetCurrent() + Self.activationTimeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            if Self.activePID(trustAppKit: appKitLoop) == pid { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return Self.activePID(trustAppKit: appKitLoop) == pid
    }

    /// TEST ONLY: `SILL_TEST_KEYFRAME_IGNORE=<n>`, honoured only by a --synthetic host, with the one
    /// line `start` prints about it. Nothing, and no line, without it.
    static func keyframeIgnoreHook(synthetic: Bool, environment env: [String: String]) -> (count: Int, line: String?) {
        guard let raw = env["SILL_TEST_KEYFRAME_IGNORE"], !raw.isEmpty else { return (0, nil) }
        let shown = SafeText.label(raw, limit: 32)
        guard synthetic else { return (0, "SILL_TEST_KEYFRAME_IGNORE=\(shown) ignored: only a --synthetic host takes it.") }
        guard let n = Int(raw), n > 0 else { return (0, "SILL_TEST_KEYFRAME_IGNORE=\(shown) ignored: a number of requests, 1 or more.") }
        let which = n == 1 ? "the first keyframe request (kind 44)" : "the first \(n) keyframe requests (kind 44)"
        return (n, "Test keyframes: \(which) ignored, as a Mac from before kind 44 skips every one (SILL_TEST_KEYFRAME_IGNORE).")
    }

    /// TEST ONLY: `SILL_TEST_DESKTOP_FAIL=<n>`, honoured only by a --synthetic host, with the one line
    /// `start` prints about it. Nothing, and no line, without it.
    static func desktopFailHook(synthetic: Bool, environment env: [String: String]) -> (count: Int, line: String?) {
        guard let raw = env["SILL_TEST_DESKTOP_FAIL"], !raw.isEmpty else { return (0, nil) }
        let shown = SafeText.label(raw, limit: 32)
        guard synthetic else { return (0, "SILL_TEST_DESKTOP_FAIL=\(shown) ignored: only a --synthetic host takes it.") }
        guard let n = Int(raw), n > 0 else { return (0, "SILL_TEST_DESKTOP_FAIL=\(shown) ignored: a number of starts, 1 or more.") }
        let which = n == 1 ? "the first start of the Desktop's capture fails" : "the first \(n) starts of the Desktop's capture fail"
        return (n, "Test Desktop: \(which), as ScreenCaptureKit's \"The stream is nil\" did on 2026-10-28 (SILL_TEST_DESKTOP_FAIL).")
    }

    /// TEST ONLY: `SILL_TEST_MAKE_GUARD=<folder>` gives a test host the guard for #380 (DisplayMakeGuard) in a folder of
    /// its own, the count in a file beside the marker, so a gate trips it with a marker it writes there and never
    /// touches Sill.app's; with SILL_TEST_HEADLESS its said display is made inside the marker as Sill.app's would be.
    /// Honoured only by a test host (DoorPolicy.isTestHost); anywhere else one line says it is ignored.
    static func makeGuardHook(environment env: [String: String], testHost: Bool) -> (store: DisplayMakeGuard.Store?, line: String?) {
        guard let raw = env["SILL_TEST_MAKE_GUARD"], !raw.isEmpty else { return (nil, nil) }
        guard testHost else { return (nil, "SILL_TEST_MAKE_GUARD ignored: only a --synthetic test host takes it, never Sill.app.") }
        let store = DisplayMakeGuard.Store.test(folder: URL(fileURLWithPath: raw, isDirectory: true))
        return (store, "Test guard: the guard for #380 keeps its marker and count in \(raw) (SILL_TEST_MAKE_GUARD); "
                    + "\(store.stops) stop\(store.stops == 1 ? "" : "s") in a row\(store.holds ? ": it holds" : "").")
    }

    /// TEST ONLY: `SILL_TEST_MENU_PID`, honoured only by a --synthetic host (which does not
    /// advertise), with the one line `start` prints about it. Nothing, and no line, without it.
    private static func testMenuHook(synthetic: Bool) -> (pid: pid_t?, line: String?) {
        guard let raw = ProcessInfo.processInfo.environment["SILL_TEST_MENU_PID"] else { return (nil, nil) }
        let shown = SafeText.label(raw, limit: 32)
        guard synthetic else { return (nil, "SILL_TEST_MENU_PID=\(shown) ignored: only a --synthetic host takes it.") }
        guard let pid = pid_t(raw), pid > 0, MenuReader.alive(pid) else {
            return (nil, "SILL_TEST_MENU_PID=\(shown) ignored: not a running process.")
        }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName.map { SafeText.label($0) } ?? "no app name"
        return (pid, "Test menus: the test pattern's menus are pid \(pid)'s (\(name)); read and pressed without activating it.")
    }

    // MARK: The Mac's sound (AudioPipeline; docs/audio-plan.md §4.7)
    //
    // One function decides what the sound is of, from Send Audio, the devices that play it, the
    // source, the display an app's sound is built on, the lock and whether Sill is quitting, and hands
    // it to the pipeline, which keeps the same app's stream through the picture's restarts (on the same
    // display) and starts another for another source. It runs in `active`'s didSet (set on every path
    // of `select`, once the picture has started, or to none), when the count of devices that play it
    // changes, in `adopt` when Send Audio changed outside a select, when the pipeline's own retry is
    // due outside a select (`onRetry`, issue #365), and at quit. The sound adds no device → host kind
    // and no per-connection state here: the server keeps each device's codec and epoch.

    /// What the sound should be of now, and why none when none: the log's reason.
    private func audioKey() -> (AudioKey, String) {
        if shuttingDown { return (.none, "Sill is quitting") }
        guard config.sendAudio else { return (.none, "Send Audio is off") }
        guard audioListeners > 0 else { return (.none, "no connected device plays sound") }
        guard lockAllowed.sound else { return (.none, "this Mac is locked") }
        switch active {
        case .none:
            return (.none, "nothing streams")
        case .desktop:
            // A filter of the same kind as the picture's; a synthetic host's Desktop is the test pattern,
            // and its sound the test tone.
            return (synthetic ? .test : .desktop, "")
        case .window(let id):
            // A synthetic host never captures a real app's sound: its tests hear only the tone.
            if synthetic { return (.none, "a test host sends only its test tone") }
            let pid: pid_t
            if virtualDisplay, let p = stage.placement, p.windowID == id {
                pid = p.pid
            } else if let app = catalog.window(id: id)?.owningApplication {
                pid = app.processID
            } else if let s = streamedPID, s.window == id {
                pid = s.pid    // off the list for a few looks (`windowsChanged`), still streaming
            } else {
                return (.none, "the streamed window's app is not known")
            }
            // Sill's own sound never goes out (and the capture leaves this process out anyway).
            guard pid != WindowCatalog.ownPID else { return (.none, "Sill's own window streams") }
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? catalog.window(id: id)?.owningApplication?.applicationName ?? "pid \(pid)"
            return (.app(pid: pid, display: appAudioDisplay?.displayID ?? 0, name: SafeText.label(name)), "")
        }
    }

    /// The display an app's sound filter is built on (issue #365): Sill's virtual display while the
    /// streamed window is staged there (the app may have no window on the main display, and when Sill's
    /// display appears or goes a filter on the main display can fail or end with -3815), else the main
    /// display.
    private var appAudioDisplay: SCDisplay? {
        if case .window(let id) = active, virtualDisplay, stage.isStaged, stage.placement?.windowID == id,
           let d = stage.scDisplay {
            return d
        }
        return catalog.mainDisplay
    }

    /// Hands the pipeline what the sound should be of now.
    private func audioFollow() {
        let (key, reason) = audioKey()
        audio.follow(key, reason: reason) { [weak self] key in
            await self?.makeAudioSource(key) ?? .failed("the host is shutting down")
        }
    }

    /// The source for `key`: ScreenCaptureKit's sound of one app (on Sill's virtual display while its
    /// window is staged there, else on the main display: `appAudioDisplay`), or of every app but Sill's
    /// on the main display whatever stop the Desktop shows, so a step to another stop keeps the sound
    /// running (DesktopDisplays); or a synthetic host's test tone.
    private func makeAudioSource(_ key: AudioKey) async -> AudioPipeline.Made {
        switch key {
        case .none:
            return .failed("nothing to capture")
        case .test:
            return .source(SyntheticAudio(queue: audio.queue), line: "Audio: a test tone (440 Hz at -30 dBFS, a click at each second).")
        case .desktop:
            guard let display = catalog.mainDisplay else { return .failed("no display to capture from") }
            let filter: SCContentFilter
            if let own = catalog.ownApplication {
                filter = SCContentFilter(display: display, excludingApplications: [own], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])   // the CLI: no Sill app to leave out
            }
            return .source(AudioCapture(filter: filter, queue: audio.queue), line: "Audio: capturing the whole Mac's sound (every app but Sill).")
        case .app(let pid, let displayID, let name):
            // The display the key names while it is still Sill's, else the one `appAudioDisplay` gives now.
            guard let display = (stage.scDisplay.flatMap { $0.displayID == displayID ? $0 : nil }) ?? appAudioDisplay else { return .failed("no display to capture from") }
            let onStage = display.displayID == stage.scDisplay?.displayID ? " on virtual display \(display.displayID)" : ""
            guard let app = await runningApplication(pid) else { return .failed("\(name) is not among the apps ScreenCaptureKit lists") }
            let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            return .source(AudioCapture(filter: filter, queue: audio.queue), line: "Audio: capturing \(name)'s sound (every window of it)\(onStage).")
        }
    }

    /// The app with this pid as ScreenCaptureKit lists it: from the catalog's last look, else from one
    /// bounded look at every window and app (a window staged on the virtual display, or a minimized
    /// app's, can be off the on-screen list).
    private func runningApplication(_ pid: pid_t) async -> SCRunningApplication? {
        if let app = catalog.windows.first(where: { $0.owningApplication?.processID == pid })?.owningApplication { return app }
        guard let all = await WindowCatalog.shareableContent(excludingDesktopWindows: false, onScreenWindowsOnly: false, timeout: 2) else { return nil }
        return all.applications.first { $0.processID == pid }
    }

    /// The Mac's status of the sound, from the pipeline's and the devices' count.
    private func showAudio() {
        let s = audio.status
        status.update {
            $0.audio = s.map { HostStatusSnapshot.Audio(source: $0.source, devices: $0.capturing && $0.problem == nil ? audioListeners : 0,
                                                        problem: $0.problem) }
        }
    }

    // MARK: Virtual display lifecycle

    /// The window server removed the virtual display (sleep/wake, display arbitration). The stage
    /// has already put the window back; stage it again, or after repeated losses give up on the
    /// virtual display for this run and stream the real window.
    private func stageLost() async {
        stageLosses += 1
        print("The system removed the virtual display; the window is back on a real display.")
        if stageLosses > 2 {
            stage.disabledReason = "the system removed the virtual display \(stageLosses) times"
            status.update { $0.virtualDisplayProblem = stage.disabledReason }
        }
        if case .window = active { await select(active) }
    }

    /// Called by HostShutdown on the main queue just before `exit` (or, for the app's Quit, just
    /// before AppKit exits): every key and button a device holds down on the Mac goes up (a modifier
    /// left down would outlive Sill: the Mac's next click a ⌘-click), every connected device hears why
    /// (kind 22 "quit", at most 0.1 s), then a window Sill sized goes back to its own frame
    /// (`restoreFits`), the staged window home, display gone. Capture and encoder need no stop; the
    /// process is about to end. The CLI without --virtual-display lets go of the keys, puts a sized
    /// window back and dies of the signal with no goodbye (`releaseKeysForExit`): its devices notice
    /// by liveness.
    package func shutdownForExit() {
        privacy.quit()       // nothing locks this Mac from here on (a wait under way says so)
        injector.releaseAll()
        server.goodbyeAll(Goodbye(reason: Goodbye.quit), within: 0.1)
        shuttingDown = true
        audio.shutdown()   // "Audio stopped: Sill is quitting."
        restoreFits(keeping: nil)
        stage.release()
        releaseCheck?.cancel()
        virtualDesktopCheck?.cancel()
        // The Virtual Desktop's windows to the main display first, synchronously (a window in full screen left to macOS).
        if desktopLife.role == .virtualDesktop { _ = moveVirtualDesktopWindowsOut(waitsForFullScreen: false) }
        displays.removeAll()             // the Desktop's display (the stage's went with its window, above)
        displayGuard?.quitting()         // a clean quit while a display was being made is no stop (#380's guard)
    }

    // MARK: The Virtual Desktop (phase 2b of docs/virtual-desktop-plan.md as revised 2026-11-18)
    //
    // A display of Sill's own after the Mac's screens, the Desktop's last stop (DesktopDisplays.candidates' `virtualDesktop`),
    // while its switch is on (HostConfig.virtualDesktop: Settings › Displays, the menu, a paired device's panel) and this Mac
    // can make it. Its rule is VirtualDesktopLife's (made when a device shows its stop, kept while shown and its grace after,
    // kept while locked until the unlock, removed at once off console, switched off or at the grace's end, at most one change
    // of the Desktop's display every 3 s and ten a minute, never the main display beside a real screen); its size and rate
    // VirtualDesktopSize's (the matched device's room at Retina, followed after a turn the way probe P2 allows: `followWay`);
    // its windows DesktopWindowLedger's. It is Sill's Desktop display (SillDisplays' `.desktop`), the one a Mac with no
    // screen gets: with no real screen it is that display (HeadlessDesktopPolicy.Watch's), and back to the Virtual Desktop
    // when one works while a device shows it. A test host under SILL_TEST_VIRTUAL_DESKTOP only says it makes it, as one more
    // of SILL_TEST_DISPLAYS' stops. Main actor, as every display of Sill's.

    /// Whether this host can make it now, and why not (VirtualDesktopWords.note): the test hook stands for a Mac's AppKit
    /// loop, private API and Screen Recording. The private API is looked up once a run, and only on a host that could use it.
    /// `ownRules`: leave out the guard for #380 and the console, which VirtualDesktopLife weighs itself.
    private func virtualDesktopNote(ownRules: Bool = false) -> String? {
        let real = appKitLoop && !synthetic
        return VirtualDesktopWords.note(testHost: synthetic && !testVirtualDesktop, appKitLoop: appKitLoop || testVirtualDesktop,
                                        apiProblem: real ? virtualDesktopAPIProblem : nil,
                                        screenRecording: testVirtualDesktop || CGPreflightScreenCaptureAccess(),
                                        failure: virtualDesktopFailure, guardHolds: !ownRules && displayGuard?.holds == true,
                                        offConsole: !ownRules && lockReading == .offConsole)
    }

    /// The private CGVirtualDisplay API's problems, looked up once (nil: every class and method is there).
    private lazy var virtualDesktopAPIProblem: String? = {
        let problems = VirtualDisplay.checkPrivateAPI()
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }()

    /// The Virtual Desktop's stop and its status, from the switch and whether it can be made now: the catalog lists the stop
    /// (and the window list `desktopVirtual`) while both hold, and Sill.app and kind 16 say why not. Cheap; called at every
    /// change that bears on it (start, a setting, the lock, Try Again, each look and switch).
    private func refreshVirtualDesktop() {
        let note = virtualDesktopNote()
        catalog.virtualDesktopStop = config.virtualDesktop && note == nil
        let shown = virtualDesktopShown && displays.exists(.desktop) && desktopLife.role == .virtualDesktop
        status.update { $0.virtualDesktop = HostStatusSnapshot.VirtualDesktop(available: note == nil, note: note, shown: shown) }
    }

    /// A device streams the Desktop on the Virtual Desktop's stop now: it chose that stop, it is listed, the Desktop streams
    /// (not a locked Mac's placeholder), a device is connected.
    private var virtualDesktopShown: Bool {
        catalog.clientCount > 0 && active == .desktop && !placeholderStreams && !lockReading.locked && catalog.virtualDesktopStop
            && catalog.desktopDisplayUUID == DesktopDisplays.virtualDesktopChoice
    }

    /// What VirtualDesktopLife sees now (`shown`: the Desktop's select asking for the stop says so itself).
    private func virtualDesktopSeen(shown: Bool? = nil) -> VirtualDesktopLife.Seen {
        var s = VirtualDesktopLife.Seen()
        s.switchOn = config.virtualDesktop
        s.shown = shown ?? virtualDesktopShown
        s.locked = lockReading == .screenLocked
        s.offConsole = lockReading == .offConsole
        s.available = virtualDesktopNote(ownRules: true) == nil      // the guard and the console are the rule's own
        s.guardHolds = displayGuard?.holds ?? false
        s.exists = displays.exists(.desktop)
        // A test host's said display is one more test stop, never its main display (the first stop is).
        s.isMain = !testVirtualDesktop && headlessDisplay.map { $0.displayID != 0 && CGMainDisplayID() == $0.displayID } ?? false
        // A test host's screens are SILL_TEST_DISPLAYS' stops, unless SILL_TEST_HEADLESS scripts them.
        if testVirtualDesktop, testHeadlessFile == nil, let stops = catalog.testDisplays {
            s.realScreens = stops.filter { $0.role == .screen && $0.online }.count
        } else {
            s.realScreens = displayWatch.real
        }
        return s
    }

    /// The Virtual Desktop's rule now (VirtualDesktopLife.look), and what it says done: a removal, a make (through the
    /// Desktop's select, which builds its capture on it), or a look again later (the grace's end, the spacing's, a real
    /// screen's 2 s). Asked at each display change, lock change, device come or gone, switch, step and switch of source,
    /// and at the time it said. Acts on nothing while a switch or a make or removal is under way (each looks again at its
    /// end), nor at Quit; the role it finds is kept either way (one display in two roles).
    private func lookAtVirtualDesktop() {
        guard !shuttingDown else { return }
        refreshVirtualDesktop()                         // its stop as the switch and this Mac say now
        let roleBefore = desktopLife.role
        let now = CFAbsoluteTimeGetCurrent()
        let seen = virtualDesktopSeen()
        let decision = desktopLife.look(seen, at: now)
        if desktopLife.role != roleBefore { virtualDesktopRoleChanged(from: roleBefore) }
        refreshVirtualDesktop()                         // whether it shows, by the role the look found
        adoptVirtualDesktopDevice()                     // the one it was for left: the device the make's rule names now
        guard !switching, !virtualDesktopChanging, !releasingHeadless else { return }
        var next: Double?
        switch decision {
        case .idle, .headless:
            virtualDesktopWaited = nil
        case .keep(let until):
            virtualDesktopWaited = nil
            next = until
            // Locked past its grace: kept until the unlock, said once a lock.
            if seen.locked, desktopLife.role == .virtualDesktop, !seen.shown, let shownAt = desktopLife.lastShown {
                let end = shownAt + desktopLife.graceSeconds
                if now >= end {
                    if !saidVirtualDesktopKept { print(VirtualDesktopLife.lockedLine(grace: desktopLife.graceSeconds)); saidVirtualDesktopKept = true }
                } else {
                    next = end
                }
            }
        case .make:
            // Made inside the Desktop's select, which builds its capture on it (the Desktop shows the stop already: `shown`).
            Task { @MainActor in
                guard self.active == .desktop, !self.switching else { return }
                await self.select(.desktop)
            }
        case .remove:
            Task { @MainActor in await self.removeVirtualDesktop() }
        case .spaced(let change, let until):
            noteVirtualDesktopWait(change, now: now)
            next = until
        }
        if let due = followDue(now: now) { next = min(next ?? due, due) }
        if let next { scheduleVirtualDesktopCheck(at: next) } else { virtualDesktopCheck?.cancel(); virtualDesktopCheck = nil }
    }

    /// One look at `time`, replacing any other scheduled.
    private func scheduleVirtualDesktopCheck(at time: Double) {
        virtualDesktopCheck?.cancel()
        virtualDesktopCheck = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, time - CFAbsoluteTimeGetCurrent()) + 0.01))
            guard !Task.isCancelled else { return }
            self.virtualDesktopCheck = nil
            self.followVirtualDesktop()
            self.lookAtVirtualDesktop()
        }
    }

    /// A make or a removal the spacing holds back: when it began, for the line once it is done.
    private func noteVirtualDesktopWait(_ change: VirtualDesktopLife.Change, now: Double) {
        guard virtualDesktopWaited == nil else { return }
        let c = desktopLife.changes
        let fullMinute = c.count >= VirtualDesktopLife.perMinute
            && c[c.count - VirtualDesktopLife.perMinute] + VirtualDesktopLife.minute > (c.last ?? -Double.infinity) + VirtualDesktopLife.spacing
        virtualDesktopWaited = (now, fullMinute)
    }

    /// The waited line, once a make or removal the spacing held back is done.
    private func sayVirtualDesktopWaited(_ change: VirtualDesktopLife.Change, now: Double) {
        guard let w = virtualDesktopWaited else { return }
        virtualDesktopWaited = nil
        print(VirtualDesktopLife.waitedLine(change, waited: now - w.since, fullMinute: w.fullMinute))
    }

    /// The Desktop asked for on the Virtual Desktop's stop (a step onto it, its switch turned on from a device, the Desktop
    /// coming back to it within the session span): made now when its rule says so, inside the Desktop's select, so the
    /// capture that follows is built on it. The spacing may hold it back: the Desktop shows the main display meanwhile
    /// (DesktopDisplays.streamed), and the look at the spacing's end makes it and moves the Desktop there.
    private func ensureVirtualDesktop() async {
        guard catalog.virtualDesktopStop, catalog.desktopDisplayUUID == DesktopDisplays.virtualDesktopChoice, !lockReading.locked,
              catalog.clientCount > 0, !virtualDesktopChanging, !shuttingDown else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if !testVirtualDesktop { lookAtDisplays() }     // its real screens now (a test host's are its stops)
        switch desktopLife.look(virtualDesktopSeen(shown: true), at: now) {
        case .make: await makeVirtualDesktop(at: now)
        case .spaced(let change, let until):
            noteVirtualDesktopWait(change, now: now)
            scheduleVirtualDesktopCheck(at: until)
        default: break
        }
    }

    /// Makes the Virtual Desktop (its rule said `.make`): at the matched device's size and rate (VirtualDesktopSize.device
    /// and rate: the device that asked for the Desktop, else the one whose viewport came last, else #200's 1920×1080 at 60),
    /// with the modes P2's way needs (none by default); waited for until it is online and ScreenCaptureKit lists it; the
    /// catalog looked at again, so its stop has its display; the windows Sill moved off it before back in their places. A
    /// make that fails, or a display that never comes up, turns it off for this run (VirtualDesktopWords.failed); an iPhone's
    /// pixel-for-pixel size that macOS would not make, or did not keep, is made again at once at the size that works (the
    /// 800-point floor), one line, and never asked again this run (`notKeptAtMake`). A test host only says it makes it
    /// (SillDisplays.say), as one more of its stops.
    private func makeVirtualDesktop(at now: Double) async {
        virtualDesktopChanging = true
        defer { virtualDesktopChanging = false }
        let matched = VirtualDesktopSize.matched(asker: desktopAsker, newest: newestViewport, sent: Set(viewports.keys))
        let vp = matched.flatMap { viewports[$0] }
        let (asked, hz) = virtualDesktopWanted(target: config, viewport: vp)
        let device = vp == nil ? nil : matched.map { deviceName(id: $0) }
        // This device follows its device in place (the probes' way), inside a backing that holds every iPhone's and iPad's
        // space both ways (VirtualDesktopSize.backing); a size the person chose is made as every display Sill makes.
        let follows = VirtualDesktopSize.choice(config.virtualDesktopSize) == .device
        let backing = VirtualDesktopSize.backing(made: asked, follows: follows)
        let space = follows ? vp.map(Self.space) : nil
        // An iPhone's: made pixel for pixel, and the size that works if macOS does not keep that (Noah, 2026-11-24).
        let screen = follows ? vp.flatMap(Self.screen) : nil
        let works = follows ? vp.flatMap(worksSize) : nil
        let pixels = VirtualDesktopSize.pixelWords(asked, space: space, screen: screen)
        sayVirtualDesktopWaited(.make, now: now)
        // The guard's marker from just before the private calls until the display is up or failed (#380; SillDisplays).
        displays.willMake(.desktop)
        let t0 = CFAbsoluteTimeGetCurrent()
        if testVirtualDesktop {
            // TEST ONLY: said, never made (SillDisplays.say); one more test stop, at the size and rate a Mac's would be asked for.
            displays.say(.desktop)
            desktopLife.made(.virtualDesktop, at: now)
            testVirtualDisplay = VirtualDesktopSize.TestDisplay(made: asked, backing: backing, knobs: testVirtualDesktopKnobs)
            if let came = testVirtualDisplay?.read(at: now), await notKeptAtMake(asked, came: came, works: works) { return }
            addTestVirtualStop(asked, hz: hz)
            print(VirtualDesktopLife.madeLine(came: asked, asked: asked, hz: hz, id: nil, ms: 0, device: device, space: space, pixels: pixels))
            virtualDesktopMade(asked, hz: hz, backing: backing, device: vp == nil ? nil : matched, name: device, at: now)
            return
        }
        let newDisplay: VirtualDisplay
        do {
            newDisplay = try displays.make(.desktop, widthPt: asked.widthPt, heightPt: asked.heightPt, scale: asked.scale, refreshHz: Double(hz),
                                           backing: (backing.wide, backing.high))
        } catch {
            if await notKeptAtMake(asked, came: nil, works: works) { return }
            virtualDesktopFailed("\(error)")
            return
        }
        desktopLife.made(.virtualDesktop, at: now)
        _ = await displays.waitUntilOnline(newDisplay, timeout: 3)
        // Removed meanwhile (switched off, off console, Quit, macOS): that removal said so.
        guard headlessDisplay === newDisplay else { return }
        let b = newDisplay.bounds
        guard b.width > 0 else {
            displays.remove(.desktop)
            desktopLife.removed(at: CFAbsoluteTimeGetCurrent())
            if await notKeptAtMake(asked, came: nil, works: works) { return }
            virtualDesktopFailed("it never came up (asked \(asked.widthPt)×\(asked.heightPt) @\(asked.scale)× at \(hz) Hz)")
            return
        }
        let came = VirtualDesktopSize.Size(widthPt: Int(b.width), heightPt: Int(b.height), scale: newDisplay.currentScale)
        if await notKeptAtMake(asked, came: came, works: works) { return }
        let cameHz = CGDisplayCopyDisplayMode(newDisplay.displayID).map { Int($0.refreshRate.rounded()) }.flatMap { $0 > 0 ? $0 : nil } ?? hz
        _ = await displays.waitUntilListed(newDisplay, as: .desktop, timeout: 3)
        guard headlessDisplay === newDisplay, !shuttingDown else { return }
        print(VirtualDesktopLife.madeLine(came: came, asked: asked, hz: cameHz, id: newDisplay.displayID,
                                          ms: Int((CFAbsoluteTimeGetCurrent() - t0) * 1000), device: device, space: space, pixels: pixels))
        virtualDesktopMade(came, hz: cameHz, backing: VirtualDesktopSize.Backing(wide: newDisplay.backing.wide, high: newDisplay.backing.high),
                           device: vp == nil ? nil : matched, name: device, at: now)
        // Its stop gets its display: the catalog keeps it beside the real screens and looks again.
        catalog.sillsAsVirtualDesktop = true
        catalog.keepsSills = false
        await catalog.refreshWindows()
        // The windows Sill moved off it before, back in their places (or the same share of its new area).
        bringVirtualDesktopWindowsBack(to: b)
    }

    /// An iPhone's pixel-for-pixel size macOS would not make (`came` nil) or did not keep (it came up at `came`), the size
    /// that works being `works` (VirtualDesktopSize.afterMake): that size never asked again this run, one line, the display
    /// that came up removed (nothing is on it yet), and the Virtual Desktop made again at once at the size that works (the
    /// make's own rule then gives it), so the Desktop never goes without one. False, and nothing done, otherwise: an iPad's,
    /// an older device's or a chosen size keeps what came, as before, and a make that fails at the size that works fails.
    private func notKeptAtMake(_ asked: VirtualDesktopSize.Size, came: VirtualDesktopSize.Size?, works: VirtualDesktopSize.Size?) async -> Bool {
        let after = came.map { VirtualDesktopSize.afterMake(asked: asked, came: $0, works: works) }
            ?? works.flatMap { $0 != asked ? .again($0) : nil }
        guard case .again(let size)? = after, !phoneRefused.contains(VirtualDesktopSize.id(asked)) else { return false }
        phoneRefused.insert(VirtualDesktopSize.id(asked))
        print(VirtualDesktopSize.refusedLine(asked: asked, came: came, works: size, inPlace: false))
        if displays.exists(.desktop) {
            displays.remove(.desktop)
            desktopLife.removed(at: CFAbsoluteTimeGetCurrent())
        }
        testVirtualDisplay = nil
        await makeVirtualDesktop(at: CFAbsoluteTimeGetCurrent())
        return true
    }

    /// The size that works for viewport `v`'s space when macOS does not keep an iPhone's pixel-for-pixel one: the 800-point
    /// floor (VirtualDesktopSize.device(space:)), which macOS has always kept at 2x.
    private func worksSize(_ v: Viewport) -> VirtualDesktopSize.Size? {
        VirtualDesktopSize.device(space: Self.space(v))
    }

    /// The space a device's picture has now (VirtualDesktopSize's rule A, Noah 2026-11-24): its viewport's panel, the
    /// rectangle the stage fits a window to (VirtualStage.windowSize), never its room (Full Screen's, whether the controls
    /// show or not), which only tells a turn from a tap (VirtualDesktopSize.cause).
    private static func space(_ v: Viewport) -> CGSize { CGSize(width: v.width, height: v.height) }

    /// The screen a device's picture is on, as its viewport says (Viewport.screen, within ViewportBounds.screen): an
    /// iPhone's has its Virtual Desktop made pixel for pixel (Noah, 2026-11-24); nil from a device that says nothing
    /// (every build before 2026-11-25), sized as before.
    private static func screen(_ v: Viewport) -> VirtualDesktopSize.Screen? {
        guard let s = v.screen.flatMap({ ViewportBounds.screen($0) }) else { return nil }
        return VirtualDesktopSize.Screen(pixelWidth: s.pixelWidth, pixelHeight: s.pixelHeight, scale: s.scale, phone: s.phone == true)
    }

    /// The Virtual Desktop Match the device gives viewport `v`: an iPhone's pixel for pixel (but a size macOS did not keep
    /// this run), an iPad's and an older device's at least 800 points a side (VirtualDesktopSize.device(space:screen:refused:)).
    private func deviceSize(_ v: Viewport) -> VirtualDesktopSize.Size? {
        VirtualDesktopSize.device(space: Self.space(v), screen: Self.screen(v), refused: phoneRefused)
    }

    /// The size and rate the Virtual Desktop has when it is made now, by the person's choice (`t`'s virtualDesktopSize and
    /// virtualDesktopHz; Sill.app's Settings › Displays, the CLI's --virtual-desktop=…): This device's (the space its picture
    /// has, at Retina, VirtualDesktopSize.device, for viewport `vp`; #200's 1920×1080 with none), the main display's mode
    /// (VirtualDesktopSize.main), or a fixed size; the rate the chosen one, else the device's, held to the Frame Rate limit.
    private func virtualDesktopWanted(target t: HostConfig, viewport vp: Viewport?) -> (size: VirtualDesktopSize.Size, hz: Int) {
        let hz = VirtualDesktopSize.rate(choice: t.virtualDesktopHz, viewportFPS: vp?.fps, limit: t.maxFPS)
        switch VirtualDesktopSize.choice(t.virtualDesktopSize) ?? .device {
        case .device:
            return (vp.flatMap(deviceSize) ?? VirtualDesktopSize.fallback, hz)
        case .fixed(let size):
            return (size, hz)
        case .main:
            let m = mainDisplayMode()
            return (m.flatMap { VirtualDesktopSize.main(points: $0.points, scale: $0.scale) } ?? VirtualDesktopSize.fallback, hz)
        }
    }

    /// The main display's mode as the person set it (its "looks like" points and its pixels a point), for "Same as main
    /// display"; a test host's first stop under SILL_TEST_DISPLAYS. Nil with none.
    private func mainDisplayMode() -> (points: CGSize, scale: Int)? {
        if synthetic {
            guard let first = catalog.testDisplays?.first else { return nil }
            return (first.frame.size, Int(testDisplayScales[first.id] ?? 1))
        }
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()), mode.width > 0 else { return nil }
        return (CGSize(width: mode.width, height: mode.height), max(1, Int((Double(mode.pixelWidth) / Double(mode.width)).rounded())))
    }

    /// What the Virtual Desktop now is, for following its device, kind 16, Sill.app's card and the Desktop's rate.
    private func virtualDesktopMade(_ size: VirtualDesktopSize.Size, hz: Int, backing: VirtualDesktopSize.Backing, device: ObjectIdentifier?,
                                    name: String?, at now: Double) {
        virtualDesktopNow = VirtualDesktopNow(size: size, hz: hz, backing: backing, device: device, deviceName: name)
        desktopFollow = VirtualDesktopSize.Follow(made: size, at: now)
        headlessHz = Double(hz)
        status.update {
            $0.sillDisplay = HostStatusSnapshot.SillDisplay(widthPt: size.widthPt, heightPt: size.heightPt, scale: size.scale, hz: hz,
                                                            device: name, virtualDesktop: true)
        }
    }

    /// A make that failed: one line, no more tries this run until its switch is turned off and on; the stop leaves the cycle
    /// and the Desktop shows the main display.
    private func virtualDesktopFailed(_ why: String) {
        print("Virtual Desktop: could not make it (\(why)); off until it is turned off and on again.")
        virtualDesktopFailure = why
        refreshVirtualDesktop()
    }

    /// The Virtual Desktop goes, when its rule says so on a fresh look once a switch under way is over (a removal asked by an
    /// older look never acts on a newer state): the Desktop off it first, to the stop the catalog shows without it (the main
    /// display), so its capture never loses the display under it; its windows to the main display (DesktopWindowLedger,
    /// through Accessibility; off console none, the screen being another user's); then the display, and one line.
    private func removeVirtualDesktop() async {
        guard !virtualDesktopChanging else { return }
        virtualDesktopChanging = true
        defer {
            virtualDesktopChanging = false
            Task { @MainActor in self.lookAtVirtualDesktop() }
        }
        for _ in 0..<100 where switching { try? await Task.sleep(for: .milliseconds(50)) }
        let now = CFAbsoluteTimeGetCurrent()
        guard displays.exists(.desktop), desktopLife.role == .virtualDesktop, !shuttingDown,
              case .remove(let why) = desktopLife.look(virtualDesktopSeen(), at: now) else { return }
        sayVirtualDesktopWaited(.remove(why), now: now)
        _ = await takeVirtualDesktopAway(movesWindows: why != .offConsole) { moved, said in
            VirtualDesktopLife.removedLine(why, moved: moved.moved, of: moved.of, to: moved.to, grace: self.desktopLife.graceSeconds)
                + (said ? " (TEST ONLY: none was made.)" : "")
        }
    }

    /// The Virtual Desktop taken away (a removal its rule said, or a follow in place that could not put it back at 2x):
    /// the Desktop off it first, to the stop the catalog shows without it (the main display), so its capture never loses the
    /// display under it; its windows to the main display (`movesWindows`; off console none, the screen being another
    /// user's); then the display, and the line `line` gives for the windows moved (`said`: a test host's, none made).
    /// False when it went meanwhile, or Sill quits. The caller holds `virtualDesktopChanging`.
    private func takeVirtualDesktopAway(movesWindows: Bool, line: ((moved: Int, of: Int, to: String), Bool) -> String) async -> Bool {
        let made = headlessDisplay?.displayID
        catalog.sillsAsVirtualDesktop = false
        removeTestVirtualStop()
        if active == .desktop, !placeholderStreams, desktopOnSills(desktopStreamDisplay) {
            await catalog.refreshWindows()
            for _ in 0..<100 where switching { try? await Task.sleep(for: .milliseconds(50)) }
            if active == .desktop, !switching { await select(.desktop) }
            for _ in 0..<100 where switching { try? await Task.sleep(for: .milliseconds(50)) }
        }
        guard displays.exists(.desktop), !shuttingDown, headlessDisplay?.displayID == made else { return false }
        let moved = !movesWindows ? (moved: 0, of: 0, to: "") : moveVirtualDesktopWindowsOut(waitsForFullScreen: true)
        displays.remove(.desktop)
        desktopLife.removed(at: CFAbsoluteTimeGetCurrent())
        virtualDesktopGone()
        print(line(moved, made == nil))
        lookAtDisplays(changed: true)
        refreshVirtualDesktop()
        return true
    }

    /// Forgotten as it goes (removed, or by macOS): what it was, its follow, its rate, its status.
    private func virtualDesktopGone() {
        virtualDesktopNow = nil
        desktopFollow = nil
        testVirtualDisplay = nil
        headlessHz = nil
        catalog.sillsAsVirtualDesktop = false
        status.update { $0.sillDisplay = nil }
    }

    /// The display changed roles (VirtualDesktopLife): the last real screen went while it was the Virtual Desktop, and it is
    /// a Mac with no screen's now (HeadlessDesktopPolicy.Watch's, kept first in the Desktop's pool); or a real screen came
    /// back while a device showed it with the switch on, and it is the Virtual Desktop again, beside the real screens.
    private func virtualDesktopRoleChanged(from before: VirtualDesktopLife.Role?) {
        guard let now = desktopLife.role, before != nil else { return }
        if now == .headless {
            catalog.sillsAsVirtualDesktop = false
            catalog.keepsSills = true
            desktopFollow = nil
            status.update { $0.sillDisplay?.virtualDesktop = false }
            print("Virtual Desktop: no real screen works now; it is this Mac's only display until one does.")
        } else {
            catalog.sillsAsVirtualDesktop = true
            catalog.keepsSills = false
            if let s = status.snapshot.sillDisplay {
                let size = VirtualDesktopSize.Size(widthPt: s.widthPt, heightPt: s.heightPt, scale: s.scale)
                // The headless display was made at its own size alone (2a): its backing is its own pixels, so a size the
                // device asks for later is taken at the next make.
                let own = headlessDisplay?.backing ?? (wide: size.widthPt * size.scale, high: size.heightPt * size.scale)
                virtualDesktopNow = VirtualDesktopNow(size: size, hz: s.hz, backing: VirtualDesktopSize.Backing(wide: own.wide, high: own.high),
                                                      device: nil, deviceName: s.device)
                desktopFollow = VirtualDesktopSize.Follow(made: size, at: CFAbsoluteTimeGetCurrent())
            }
            status.update { $0.sillDisplay?.virtualDesktop = true }
            print("Virtual Desktop: a real screen works again; Sill's display stays as the Virtual Desktop, which a device shows.")
        }
    }

    /// The windows on the Virtual Desktop now, to the main display (DesktopWindowLedger.moveAllOut): each app's window of
    /// layer 0 on screen, not Sill's own, more of it there than on any other display (`isOn`), matched to its Accessibility
    /// window by its app and frame (as the stage finds a stranger on its display), moved to the same share of the main
    /// display's visible area, its size kept, and kept in the book to come back. Synchronous, so Quit and the signals run
    /// it. Without Accessibility none moves: macOS moves them as the display goes. The main display while the Virtual
    /// Desktop is it (the never-main rule): the first real screen. How many moved, of how many, and where.
    private func moveVirtualDesktopWindowsOut(waitsForFullScreen: Bool) -> (moved: Int, of: Int, to: String) {
        guard let d = headlessDisplay, d.displayID != 0 else { return (0, 0, "") }
        let bounds = CGDisplayBounds(d.displayID)
        let target = CGMainDisplayID() != d.displayID ? CGMainDisplayID()
            : (catalog.desktopCandidates.first { $0.role == .screen && $0.id != d.displayID }?.id ?? CGMainDisplayID())
        let name = SafeText.label(VirtualStage.screen(for: target)?.localizedName ?? "the main display", limit: 64)
        let targetBounds = CGDisplayBounds(target)
        // Each display's visible area as AppKit has it, or its bounds where NSScreen does not list it: never another's.
        let area = WindowSizer.visibleArea(around: bounds).flatMap { $0.intersects(bounds) ? $0 : nil } ?? bounds
        guard AXIsProcessTrusted(), !targetBounds.isEmpty, !targetBounds.intersects(bounds) else { return (0, 0, name) }
        let mainArea = WindowSizer.visibleArea(around: targetBounds).flatMap { $0.intersects(targetBounds) ? $0 : nil } ?? targetBounds
        let screens = WindowSizer.displayFrames()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return (0, 0, name)
        }
        var windows: [(id: CGWindowID, w: WindowSizer.Placement)] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
                  DesktopWindowLedger.isOn(rect, bounds, among: screens),
                  let ax = WindowSizer.axWindow(pid: pid, frame: rect) else { continue }
            AXUIElementSetMessagingTimeout(ax, 1.0)
            // No title: Sill.log names no window (the plan's privacy rule); the app's name alone.
            windows.append((id, WindowSizer.Placement(windowID: id, pid: pid, element: ax, originalFrame: rect,
                                                      appName: (info[kCGWindowOwnerName as String] as? String) ?? "?", title: "")))
        }
        var access = WindowSizer.DesktopWindows(ax: WindowSizer.AXWindows(sizer: sizer), fullScreenWait: waitsForFullScreen ? 2 : 0)
        let n = DesktopWindowLedger.moveAllOut(windows, area: area, mainArea: mainArea, on: &access, into: &desktopBook)
        return (n.moved, n.of, name)
    }

    /// The windows Sill moved off the Virtual Desktop, back now that it returned (DesktopWindowLedger.bringBack): each still
    /// where Sill put it goes back to its place, scaled into its new area when that changed; one line.
    private func bringVirtualDesktopWindowsBack(to bounds: CGRect) {
        guard !desktopBook.isEmpty, AXIsProcessTrusted() else { return }
        // Its visible area as AppKit has it, or its bounds while NSScreen does not list it yet (just made): never another
        // display's area, which would leave each window where it is and forget it.
        let area = WindowSizer.visibleArea(around: bounds).flatMap { $0.intersects(bounds) ? $0 : nil } ?? bounds
        var access = WindowSizer.DesktopWindows(ax: WindowSizer.AXWindows(sizer: sizer))
        let n = DesktopWindowLedger.bringBack(&desktopBook, area: area, on: &access)
        if let line = DesktopWindowLedger.backLine(n) { print(line) }
    }

    /// The Virtual Desktop's switch turned on or off (`adopt`). On: its stop joins the cycle, and the device that turned it
    /// on is shown it at once (open decision 12 (a)): the Desktop on its stop, which makes it. Off: the stop leaves (a
    /// Desktop on it goes to the main display) and the display goes as its rule says (`.switchedOff`, spaced).
    private func virtualDesktopSwitched(on: Bool) {
        if on { virtualDesktopFailure = nil }          // turned off and on: a failed make is tried again
        refreshVirtualDesktop()
        let shows = showVirtualDesktopTo
        showVirtualDesktopTo = nil
        if on, let id = shows, connections[id] != nil, catalog.virtualDesktopStop, !lockReading.locked {
            desktopAsker = id
            catalog.chooseDesktopDisplay(DesktopDisplays.virtualDesktopChoice)
            print("Desktop: \(VirtualDesktopWords.name), turned on by \(deviceName(id: id)).")
            Task { @MainActor in await self.handlePick(.desktop) }
            return
        }
        Task { @MainActor in self.lookAtVirtualDesktop() }
    }

    /// A viewport from a device (`before`: its last one, nil for its first): the Virtual Desktop follows the space of the
    /// device it is for while it shows (rule A): the size the space asks for now (VirtualDesktopSize.device), taken at once
    /// for a tap on its controls and after 1 s steady for a turn of the hand (`Follow`, `VirtualDesktopSize.cause`). Never
    /// while it does not show: the phone's arrangement and the Duo's pane follow a window's shape then. And while its switch
    /// is on, each device's own state says the size the Virtual Desktop would have for it (kind 16).
    private func virtualDesktopViewport(_ v: Viewport, before: Viewport?, from id: ObjectIdentifier) {
        if target.virtualDesktop { publishSettings() }
        adoptVirtualDesktopDevice()                     // the one it was for left: this device's space may be the one now
        // Only This device follows a device (a size the person chose, or the main display's, stays as chosen).
        guard VirtualDesktopSize.choice(config.virtualDesktopSize) == .device, virtualDesktopShown,
              var follow = desktopFollow, virtualDesktopNow?.device == id, desktopLife.role == .virtualDesktop,
              let size = deviceSize(v) else { return }
        let cause = VirtualDesktopSize.cause(roomBefore: before?.room.map { CGSize(width: $0.width, height: $0.height) },
                                             room: v.room.map { CGSize(width: $0.width, height: $0.height) },
                                             panelBefore: before.map(Self.space), panel: Self.space(v))
        follow.saw(size, cause: cause, at: CFAbsoluteTimeGetCurrent())
        desktopFollow = follow
        followVirtualDesktop()
        if let due = followDue(now: CFAbsoluteTimeGetCurrent()) { scheduleVirtualDesktopCheck(at: due) }
    }

    /// Plan §5's matched device, kept as devices come and go: a device that steps onto the Virtual Desktop's stop
    /// (`stepper`, kind 47) is the one it is for; once the one it was for left, the device the make's own rule names now
    /// (VirtualDesktopSize.matched: the one that asked for the Desktop last, as each device does as it connects, else the
    /// one whose viewport came last), while a device shows it. Its space then feeds the follow (`Follow.saw`, `.device`),
    /// taken in place at once when it fits the backing; the caller's look schedules it. And the one it is for showing it
    /// again (back from a window or another stop): the space it has now (`.shown`), which may have changed meanwhile, taken
    /// after 1 s steady (what streams may still change its arrangement). Only This device follows a device.
    private func adoptVirtualDesktopDevice(stepper: ObjectIdentifier? = nil) {
        guard var vd = virtualDesktopNow, var follow = desktopFollow, desktopLife.role == .virtualDesktop,
              VirtualDesktopSize.choice(config.virtualDesktopSize) == .device else { return }
        let shown = virtualDesktopShown
        let wasShown = vd.shown
        vd.shown = shown
        virtualDesktopNow = vd
        // Whose space it follows now: a device that stepped onto it; else, once the one it was for left, the make's rule's.
        var id = stepper
        if id == nil, vd.device == nil, shown {
            id = VirtualDesktopSize.matched(asker: desktopAsker, newest: newestViewport, sent: Set(viewports.keys))
        }
        if let id, id != vd.device, let v = viewports[id], let size = deviceSize(v) {
            vd.device = id
            vd.deviceName = deviceName(id: id)
            virtualDesktopNow = vd
            follow.saw(size, cause: .device, at: CFAbsoluteTimeGetCurrent())
            desktopFollow = follow
            return
        }
        // The one it is for shows it again: the space it has now.
        guard shown, !wasShown, let mine = vd.device, let v = viewports[mine],
              let size = deviceSize(v) else { return }
        follow.saw(size, cause: .shown, at: CFAbsoluteTimeGetCurrent())
        desktopFollow = follow
    }

    /// When the follow is next due, if one waits (now, if it is due already).
    private func followDue(now: Double) -> Double? {
        switch desktopFollow?.due(now: now) {
        case .wait(let until)?: return until
        case .follow?: return now
        default: return nil
        }
    }

    /// A follow due now (`Follow.due`), the way Noah's probes of 2026-11-23 allow (`VirtualDesktopSize.followStep`): in place
    /// on the live display, inside its backing (`followVirtualDesktopInPlace`, which restarts the Desktop once, at the size
    /// it ends at); else at its next make, with one line (a size beyond the backing). Nothing while the Mac is locked (asked
    /// again at the unlock's look), while it does not show (asked again when it shows), nor while a make, a removal or
    /// another follow is under way (each looks again at its end).
    private func followVirtualDesktop() {
        guard !virtualDesktopChanging, !shuttingDown, var follow = desktopFollow, let vd = virtualDesktopNow,
              desktopLife.role == .virtualDesktop, virtualDesktopShown,
              case .follow(let size, let why) = follow.due(now: CFAbsoluteTimeGetCurrent()) else { return }
        let from = vd.size
        let step = VirtualDesktopSize.followStep(to: size, display: from, backing: vd.backing, way: VirtualDesktopSize.followWay,
                                                 headless: false, locked: lockReading.locked)
        let name = vd.deviceName ?? "its device"
        switch step {
        case .later:
            return
        case .inPlace:
            // The rate the device asks for (as at a make: the person's choice, else the device's, held to the Frame Rate limit).
            let hz = virtualDesktopWanted(target: config, viewport: vd.device.flatMap { viewports[$0] }).hz
            virtualDesktopChanging = true               // a look meanwhile is left to its end, which looks again
            virtualDesktopResizing = true               // and the Desktop's display follower too
            follow.started(size)                        // a space back at the size it has meanwhile is followed after it
            desktopFollow = follow
            Task { @MainActor in
                await self.followVirtualDesktopInPlace(to: size, from: from, why: why, hz: (to: hz, from: vd.hz), name: name)
            }
        case .nothing, .nextMake, .beyondBacking, .remake:
            // Phase 3's way (removed and made again, its windows kept) is not in 2b: the next make takes the size.
            let done: VirtualDesktopSize.FollowStep = step == .remake ? .nextMake : step
            if let line = VirtualDesktopSize.followLine(device: name, why: why, from: from, to: size, step: done, backing: vd.backing) {
                print(line)
            }
            follow.took(size, at: CFAbsoluteTimeGetCurrent())
            desktopFollow = follow
        }
    }

    /// The follow in place (VirtualDesktopSize.InPlace, P2b's and P2c's way): applySettings: with the size alone, and a
    /// CoreGraphics switch when it lands at 1x, each step read back with a bounded wait; a step refused or late, back to
    /// the size it had, at 2x (the next make takes the new one, as before); and when even that does not land, the display
    /// goes, its windows first to the main display, and the Desktop that still shows its stop makes it again at the new
    /// size. The Desktop's capture restarts once, at the size it ends at (`virtualDesktopResizing` held the display's
    /// follower meanwhile). A test host drives its said display, as the probes measured one (`testVirtualDisplay`).
    /// Threading: the main actor, as every display's make, wait and removal: applySettings: holds it about 0.3 s and the
    /// switch's CGCompleteDisplayConfiguration about 0.33 s (P2b, P2c), twice 0.3 s for a turn, as a make's own calls do.
    /// The private object has only ever been called on the main thread (the probes too), so it stays there.
    private func followVirtualDesktopInPlace(to size: VirtualDesktopSize.Size, from: VirtualDesktopSize.Size, why: VirtualDesktopSize.Cause,
                                             hz: (to: Int, from: Int), name: String) async {
        let display = headlessDisplay
        var machine = VirtualDesktopSize.InPlace(from: from, to: size, at: CFAbsoluteTimeGetCurrent())
        let outcome = await driveInPlace(&machine, display: display, hz: hz)
        virtualDesktopResizing = false
        defer {
            virtualDesktopChanging = false
            Task { @MainActor in self.lookAtVirtualDesktop() }
        }
        // Gone meanwhile (macOS removed it, switched off, Quit): its own line said so.
        guard let outcome, !shuttingDown, displays.exists(.desktop), desktopLife.role == .virtualDesktop, headlessDisplay === display else { return }
        print(machine.traceLine(said: display == nil))
        let now = CFAbsoluteTimeGetCurrent()
        let backing = virtualDesktopNow?.backing
        switch outcome {
        case .done:
            let cameHz = display?.reading?.hz ?? hz.to
            virtualDesktopNow?.size = size
            virtualDesktopNow?.hz = cameHz
            headlessHz = Double(cameHz)
            status.update {
                $0.sillDisplay?.widthPt = size.widthPt
                $0.sillDisplay?.heightPt = size.heightPt
                $0.sillDisplay?.hz = cameHz
                $0.sillDisplay?.device = name
            }
            if testVirtualDesktop { addTestVirtualStop(size, hz: cameHz) }
            if let line = VirtualDesktopSize.followLine(device: name, why: why, from: from, to: size, step: .inPlace, outcome: outcome,
                                                        hz: cameHz, backing: backing, pixelForPixel: pixelForPixel(size)) { print(line) }
            desktopFollow?.took(size, at: now)
            if target.virtualDesktop { publishSettings() }
            await restartDesktopOnVirtualDesktop(size)
        case .fellBack(let failure, _):
            if let line = VirtualDesktopSize.followLine(device: name, why: why, from: from, to: size, step: .inPlace, outcome: outcome,
                                                        backing: backing) { print(line) }
            desktopFollow?.took(size, at: now)
            phoneSizeNotKept(size, failure: failure, why: why, at: now)
            // A Mac's display went through other sizes on the way: compared, and restarted only if its size is not the
            // capture's. A test host's said display never changed size.
            if !testVirtualDesktop { await restartDesktopOnVirtualDesktop(from) }
        case .remove(let failure):
            let line = VirtualDesktopSize.followLine(device: name, why: why, from: from, to: size, step: .inPlace, outcome: outcome,
                                                     backing: backing) ?? ""
            phoneSizeNotKept(size, failure: failure, why: why, at: now)
            _ = await takeVirtualDesktopAway(movesWindows: true) { moved, said in
                line + (moved.moved > 0 ? " Moved \(moved.moved) of \(moved.of) windows to \(moved.to) first." : "")
                    + (said ? " (TEST ONLY: none was made.)" : "")
            }
        case .apply, .switchTo, .wait:
            break
        }
    }

    /// Whether `size` is the device it is for's own pixels (an iPhone's, VirtualDesktopSize.pixelForPixel), for the follow's line.
    private func pixelForPixel(_ size: VirtualDesktopSize.Size) -> Bool {
        guard let id = virtualDesktopNow?.device, let v = viewports[id], let screen = Self.screen(v), screen.phone else { return false }
        return VirtualDesktopSize.pixelForPixel(size, space: Self.space(v), scale: screen.scale)
    }

    /// A follow in place to an iPhone's pixel-for-pixel size `size` that did not land (`failure`; macOS refusing a size
    /// that short, as probe P3 asks): that size is never asked again this run, one line, and the size that works for the
    /// device's space now (the 800-point floor) is its next follow, in place, after the spacing. Nothing for an iPad's, an
    /// older device's or a chosen size (the next make takes the new size, as before).
    private func phoneSizeNotKept(_ size: VirtualDesktopSize.Size, failure: VirtualDesktopSize.InPlace.Failure, why: VirtualDesktopSize.Cause,
                                  at now: Double) {
        guard let id = virtualDesktopNow?.device, let v = viewports[id], Self.screen(v)?.phone == true, let works = worksSize(v),
              works != size, !phoneRefused.contains(VirtualDesktopSize.id(size)) else { return }
        phoneRefused.insert(VirtualDesktopSize.id(size))
        var came: VirtualDesktopSize.Size?
        if case .elsewhere(let s) = failure { came = s }
        print(VirtualDesktopSize.refusedLine(asked: size, came: came, works: works, inPlace: true))
        desktopFollow?.saw(works, cause: why, at: now)
    }

    /// Drives `machine` against the Desktop's display: a Mac's (`display`: VirtualDisplay's applyModes, reading,
    /// listsUsable and switchToListed, `hz.to` asked with the new size and `hz.from` with the way back) or a test host's
    /// said one (`testVirtualDisplay`). Looks every 20 ms. Nil when the display went meanwhile (macOS removed it, switched
    /// off, Quit), whose own line says so.
    private func driveInPlace(_ machine: inout VirtualDesktopSize.InPlace, display: VirtualDisplay?,
                              hz: (to: Int, from: Int)) async -> VirtualDesktopSize.InPlace.Action? {
        func mode(_ s: VirtualDesktopSize.Size) -> VirtualDisplay.ModeSize { VirtualDisplay.ModeSize(width: s.widthPt, height: s.heightPt) }
        func read() -> VirtualDesktopSize.Size? {
            if let d = display {
                return d.reading.map { VirtualDesktopSize.Size(widthPt: $0.widthPt, heightPt: $0.heightPt, scale: $0.scale) }
            }
            return testVirtualDisplay?.read(at: CFAbsoluteTimeGetCurrent())
        }
        var action = machine.first
        while true {
            guard !shuttingDown, displays.exists(.desktop), headlessDisplay === display else { return nil }
            switch action {
            case .apply(let s):
                let rate = s == machine.to ? hz.to : hz.from
                let answered: Bool
                if let d = display {
                    answered = (try? d.applyModes([mode(s)], refreshHz: Double(rate))) ?? false
                } else {
                    answered = testVirtualDisplay?.apply(s, at: CFAbsoluteTimeGetCurrent()) ?? false
                }
                action = machine.applied(answered, reading: read(), at: CFAbsoluteTimeGetCurrent())
            case .switchTo(let s):
                let code = display.map { $0.switchToListed(mode(s)) } ?? testVirtualDisplay?.switchTo(s, at: CFAbsoluteTimeGetCurrent())
                action = machine.switched(code, reading: read(), at: CFAbsoluteTimeGetCurrent())
            case .wait:
                try? await Task.sleep(for: .milliseconds(20))
                let now = read()
                let goal = machine.goal
                let listed = now == machine.goalAtOneX
                    && (display.map { $0.listsUsable(mode(goal)) } ?? testVirtualDisplay?.lists(goal, at: CFAbsoluteTimeGetCurrent()) ?? false)
                action = machine.saw(now, listed: listed, at: CFAbsoluteTimeGetCurrent())
            case .done, .fellBack, .remove:
                return action
            }
        }
    }

    /// After a follow in place: the Desktop's capture once, at the size the display has now (`size`), if the Desktop
    /// streams it. A Mac's display: once ScreenCaptureKit lists it at that size (a moment after CoreGraphics, at most 1.5
    /// s), the display follower compares and restarts it ("Desktop: the display is … now; restarting at its size."). A
    /// test host's said display: its test stop has the new size, and the Desktop on it starts again.
    private func restartDesktopOnVirtualDesktop(_ size: VirtualDesktopSize.Size) async {
        guard active == .desktop, !placeholderStreams, !shuttingDown else { return }
        if testVirtualDesktop {
            guard catalog.desktopDisplayUUID == DesktopDisplays.virtualDesktopChoice, catalog.virtualDesktopStop, !switching else { return }
            await select(.desktop)
            return
        }
        if let d = headlessDisplay {
            _ = await displays.waitUntilListed(d, as: .desktop, timeout: 1.5, points: (width: size.widthPt, height: size.heightPt))
        }
        await followDesktopDisplay(look: true)
    }

    /// TEST ONLY (SILL_TEST_VIRTUAL_DESKTOP): the said Virtual Desktop as one more of SILL_TEST_DISPLAYS' stops, to the right of
    /// the rightmost, at its size, scale and rate, so the test pattern shows it as a Mac's Desktop would show it.
    private func addTestVirtualStop(_ size: VirtualDesktopSize.Size, hz: Int) {
        guard testVirtualDesktop, var stops = catalog.testDisplays else { return }
        stops.removeAll { $0.id == Self.testVirtualDesktopID }
        let right = stops.map(\.frame.maxX).max() ?? 0
        stops.append(DesktopDisplays.Display(id: Self.testVirtualDesktopID, uuid: "TEST-VIRTUAL-DESKTOP",
                                             frame: CGRect(x: right, y: 0, width: CGFloat(size.widthPt), height: CGFloat(size.heightPt)),
                                             role: .sillDesktop, refreshHz: Double(hz), name: SillDisplayRole.desktop.name))
        testDisplayScales[Self.testVirtualDesktopID] = CGFloat(size.scale)
        catalog.testDisplays = stops
    }

    /// TEST ONLY: the said Virtual Desktop's test stop gone with it.
    private func removeTestVirtualStop() {
        guard testVirtualDesktop, let stops = catalog.testDisplays, stops.contains(where: { $0.id == Self.testVirtualDesktopID }) else { return }
        catalog.testDisplays = stops.filter { $0.id != Self.testVirtualDesktopID }
    }

    /// macOS removed Sill's Desktop display on its own (its termination handler; SillDisplays forgot it), in either role:
    /// one line, counted gone, and a Desktop that showed it starts again on what is left (a Mac with no screen gets its
    /// display again as HeadlessDesktopPolicy.Watch says). Its windows are where macOS put them.
    private func desktopDisplayLost() {
        let wasVirtual = desktopLife.role == .virtualDesktop
        desktopLife.removed(at: CFAbsoluteTimeGetCurrent())
        if wasVirtual { virtualDesktopGone() } else { headlessHz = nil; status.update { $0.sillDisplay = nil } }
        catalog.keepsSills = false
        print(wasVirtual ? "Virtual Desktop: macOS removed it; its windows are where macOS put them."
                         : "Headless display: macOS removed Sill's display; the Desktop starts again on what is left.")
        lookAtDisplays(changed: true)
        refreshVirtualDesktop()
        Task { @MainActor in
            for _ in 0..<100 where self.switching { try? await Task.sleep(for: .milliseconds(50)) }
            guard self.active == .desktop, !self.placeholderStreams, !self.switching, !self.shuttingDown else {
                self.lookAtVirtualDesktop()
                return
            }
            await self.catalog.refreshWindows()
            await self.select(.desktop)
        }
    }

    /// The CLI's default path at a signal (HostShutdown.installKeyRelease), just before it dies of it:
    /// every key and button a device holds down on the Mac goes up, and a window Sill sized for a
    /// device goes back to its own frame (a line each, only when a window was sized); nothing else
    /// happens (no goodbye), as before, but that a lock's wait under way ends with its line (only a
    /// --synthetic host with --lock-after-session has one).
    package func releaseKeysForExit() {
        privacy.quit()       // nothing locks this Mac from here on (a wait under way says so)
        injector.releaseAll()
        restoreFits(keeping: nil)
    }

    /// Sill.app's Quit began (applicationShouldTerminate, before an update's install step or a full-screen window
    /// makes it wait): Lock this Mac when the last device leaves locks nothing from here on, as at a signal.
    package func quitBegins() {
        privacy.quit()
    }

    /// Settings › Devices opened: Lock this Mac when the last device leaves looks again at whether this Mac has a
    /// display to type its password at (a monitor plugged in or out since), for the warning under its switch.
    package func lookAtDisplaysForLock() {
        privacy.lookAtDisplays()
    }

    // MARK: A window Sill sized goes back (WindowRestore, issue #57)

    /// Puts back every window Sill sized but `keep` (nil: every one) as it stops streaming
    /// (`WindowRestore.Ledger.restore`, which runs `WindowRestore.stop` for each): WindowRestore decides
    /// from its frame now (gone, already home, left as it is because it is full screen or was resized on
    /// the Mac, or restored: its whole original frame, or its own size where it was moved), and it is
    /// moved through the element its first fit matched, as the virtual display's restore moves a window.
    /// A window the virtual display holds goes home with the stage, to the frame `stageHome` gave it:
    /// only when Quit or a signal lands while `select` waits in `prepare`. One line for each window acted
    /// on; none for one gone or already home. Returns whether a window was put back (a restore that
    /// went through), for Aa's Off, after which the stream restarts at the window's own size.
    @discardableResult
    private func restoreFits(keeping keep: CGWindowID?) -> Bool {
        var windows = WindowSizer.AXWindows(sizer: sizer)
        var putBack = false
        for s in fits.restore(keeping: keep, staged: stage.placement?.windowID, on: &windows) {
            if case .restore = s.decision {
                Stats.shared.bump(s.done ? "win.restored" : "win.restoreFailed")
                putBack = putBack || s.done
            }
            if let line = s.line { print(line) }
        }
        return putBack
    }

    /// Where a window Sill sized would go back to now, for the virtual display's stage to keep as its
    /// way home when it takes the window (`VirtualStage.prepare(…, home:)`); nil when it has no
    /// record, or would stay as it is.
    private func stageHome(for id: CGWindowID) -> CGRect? {
        guard let entry = fits.entries[id] else { return nil }
        var windows = WindowSizer.AXWindows(sizer: sizer)
        return WindowRestore.stageHome(entry.handle, entry.record, on: &windows)
    }

    /// An encoder's watchdog fired. A hardware hang is remembered whichever encoder reports it, as
    /// long as that encoder is newer than the last return to the hardware (an older one's report
    /// is stale and must not undo the return), but only the encoder carrying the stream may
    /// restart it: a replaced encoder whose frame is still stuck inside VideoToolbox times out
    /// later, and must not disturb its successor. A hardware hang: switch to the software encoder
    /// and restart the source; the re-check brings it back. If even the software encoder dies
    /// repeatedly, stop streaming rather than loop.
    private func encoderHung(_ enc: HEVCEncoder, attempt: Int = 0) async {
        if !enc.software, !useSoftwareEncoder, enc.serial > returnSerial {
            enterSoftwareFallback(afterHang: true)
        }
        guard enc === encoder, active != .none else { return }
        if switching {
            // Reported in the tail of a switch: `select` would drop it. Try again once it has settled.
            guard attempt < 50 else { print("Encoder hang report could not be applied: a switch never finished."); return }
            try? await Task.sleep(for: .milliseconds(100))
            await encoderHung(enc, attempt: attempt + 1)
            return
        }
        if enc.software {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastSoftwareHangAt > 60 { softwareRestarts = 0 }   // three hangs within a minute stop the stream
            lastSoftwareHangAt = now
            softwareRestarts += 1
            guard softwareRestarts <= 3 else {
                print("Software encoder hung too; stopping the stream.")
                await select(.none)
                return
            }
        }
        await select(active)
    }

    // MARK: The software fallback and the way back

    /// From here the software encoder carries every stream, at 1x (its knob is 1 at most: half the
    /// scale each way on a Retina display, the hardware's own on a 1x one) and up to 60 fps: a
    /// hardware session stopped returning frames (`afterHang`), or the launch probe got no
    /// answer. Busy or stuck cannot be told apart yet (a busy engine's frame comes back seconds
    /// later, and the encoder's deinit says so), so both start the re-check. A hang soon after a
    /// return means the busy spell is still on: the next check waits longer.
    private func enterSoftwareFallback(afterHang: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        if lastReturnAt > 0 {
            let lasted = now - lastReturnAt
            if lasted < Self.returnDidNotLast {
                recheckInterval = min(recheckInterval * 2, Self.recheckMaxInterval)
            } else if lasted >= Self.returnLasted {
                recheckInterval = Self.recheckFirstInterval
            }
        }
        useSoftwareEncoder = true
        status.update { $0.softwareEncoder = true }
        Stats.shared.bump("enc.fallback")
        lastRecheck = now
        recheckDue = now + recheckInterval
        let next = Int(recheckInterval)
        // The scale the software encoder captures at, in the capture line's words ("capturing at 1x"):
        // `captureScale` is its knob from here, held to the stream's display (nothing streams yet at launch).
        let at = CaptureScale.words(knob: captureScale, displayScale: streamDisplayScale)
        if afterHang {
            print("Hardware HEVC encoder is not returning frames (busy or stuck); switching to the software encoder, \(at), until the hardware keeps up again (next check in \(next) s).")
        } else {
            print("The Mac's hardware video encoder is not answering; streaming with the software encoder, \(at), until a check finds it keeping up (every \(next) s while a device is connected).")
        }
        startRecheck()
    }

    /// A device connected (`firstArrived`: the first after none). On the software encoder a check
    /// runs at once if the last one is 30 s old, so a stream that starts now can start on the
    /// hardware, then the re-check goes on while devices stay.
    private func devicesPresent(firstArrived: Bool) {
        guard useSoftwareEncoder else { return }
        if firstArrived {
            recheckDue = min(recheckDue, max(CFAbsoluteTimeGetCurrent(), lastRecheck + Self.recheckFirstInterval))
        }
        startRecheck()
    }

    private func startRecheck() {
        guard useSoftwareEncoder, !softwareOnly, !shuttingDown, recheckTask == nil, catalog.clientCount > 0 else { return }
        recheckToken += 1
        let token = recheckToken
        recheckTask = Task { @MainActor [weak self] in
            await self?.recheckLoop()
            guard let self, self.recheckToken == token else { return }
            self.recheckTask = nil
            // A device that connected while this cancelled loop finished its test or its sleep, a
            // wake (`stalledProbeCameBack`), a fallback that came as it ended; a no-op otherwise.
            self.startRecheck()
        }
    }

    /// The last device left: no hardware session is opened while nobody watches. A test already
    /// running cannot be cut short, so the task stays `recheckTask` until its loop has ended: a
    /// device that connects meanwhile gets no second loop (two tests at once split the engine,
    /// and each backed off for the other), and the ending task's tail starts one for it.
    private func stopRecheck() {
        recheckTask?.cancel()
    }

    /// Main actor. Waits for `recheckDue`, runs a short test of the hardware at the stream's size
    /// off the main actor (`EncoderProbe.throughput`: no line, no counter), and goes back to it when
    /// it keeps up. A check where it does not (no answer, or too slow: busy) prints one line and
    /// doubles the wait. Ends when cancelled (no device), when the hardware is back, or when the
    /// host shuts down. A test running when the loop is cancelled goes on to its end: a return is
    /// still taken, and anything else is dropped without a line when no device is left.
    private func recheckLoop() async {
        while !Task.isCancelled, useSoftwareEncoder, !shuttingDown {
            let wait = recheckDue - CFAbsoluteTimeGetCurrent()
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                continue      // look again: cancelled, back already, or the due time moved
            }
            let stuck = EncoderProbe.stuckProbes
            if stuck >= Self.maxStuckProbes {
                // Every further probe of a stuck encoder would block one more thread for good. The
                // menu says so: a restart of the Mac, not waiting, fixes this one.
                if !recheckHeldBack {
                    recheckHeldBack = true
                    print("Hardware encoder: \(stuck) checks never got their frame back, so it is stuck, not busy; no more checks until one comes back. Restarting the Mac fixes a stuck encoder.")
                }
                status.update { $0.hardwareEncoderStuck = true }
                recheckDue = CFAbsoluteTimeGetCurrent() + Self.recheckMaxInterval
                continue      // until then, unless a frame comes back first (`stalledProbeCameBack`)
            }
            leaveStuck(cameBackAfter: nil)   // a probe came back while this loop slept: checking again
            // At the size the stream would have on the hardware, and fast enough for it: a small
            // frame answers even while a busy engine starves a stream (EncoderProbe), and a large
            // one is asked no more than a free engine gives at its size (`returnBar`).
            let size = hardwareProbeSize
            let pixels = size.width * size.height
            let needed = EncoderProbe.returnBar(streamFPS: wantedFPS, pixels: pixels, enginePixelRate: enginePixelRate)
            let result = await withCheckedContinuation { (c: CheckedContinuation<(ok: Bool, fps: Double?, ms: Int), Never>) in
                // The probe waits on a semaphore, up to 1 s a frame: a GCD thread, not the main
                // actor or a Swift concurrency thread. Not utility: the software encoder keeps the
                // CPU busy meanwhile, and a late wake-up between frames would count against the engine.
                DispatchQueue.global(qos: .userInitiated).async {
                    c.resume(returning: EncoderProbe.throughput(width: size.width, height: size.height))
                }
            }
            let now = CFAbsoluteTimeGetCurrent()
            lastRecheck = now
            guard useSoftwareEncoder, !shuttingDown else { return }
            if result.ok, let fps = result.fps { enginePixelRate = max(enginePixelRate, fps * Double(pixels)) }
            let measured = result.fps.map { "\(Int($0.rounded())) fps at \(size.width)×\(size.height)" } ?? "answered at \(size.width)×\(size.height)"
            if result.ok, (result.fps ?? .infinity) >= needed {
                // Taken even if the last device left meanwhile: the next stream then starts on it.
                // In a task of its own, which cancelling the re-check cannot reach: the restart's
                // own waits (Task.sleep in the stage and here) must not end early.
                let back = await Task { @MainActor in await self.hardwareIsBack(measured: measured, needed: needed) }.value
                // Back: the loop ends, unless the restart's new session already hung and set the
                // flag and the next check again (then it goes on). A later hang starts a new
                // re-check (startRecheck).
                if !back { recheckDue = CFAbsoluteTimeGetCurrent() + recheckInterval }   // a switch never settled; try later
                continue
            }
            if catalog.clientCount == 0 {
                // The last device left while the test ran (this loop is cancelled): no line and no
                // backoff for a check nobody waits for. The next device's check comes 30 s after
                // this one at the earliest (`devicesPresent`).
                recheckDue = now + recheckInterval
                return
            }
            recheckInterval = min(recheckInterval * 2, Self.recheckMaxInterval)
            recheckDue = now + recheckInterval
            if result.ok {
                print("Hardware encoder answers but is busy (\(measured) in a test, under the \(Int(needed.rounded())) fps a return needs; another app is using it); next check in \(Int(recheckInterval)) s.")
            } else {
                print("Hardware encoder still not answering after \(result.ms) ms; next check in \(Int(recheckInterval)) s.")
            }
        }
    }

    /// `width`×`height`, or held to EncoderLimit when this Mac's hardware encoder makes no session of
    /// that size (#278).
    private static func hardwareFit(_ width: Int, _ height: Int) -> (width: Int, height: Int) {
        guard let held = EncoderLimit.held(width: width, height: height),
              !HEVCEncoder.hardwareTakes(width: width, height: height) else { return (width, height) }
        return held
    }

    /// The size a hardware stream would have now (`hardwareProbeSizeAsked`), as `startPipeline` holds it.
    private var hardwareProbeSize: (width: Int, height: Int) {
        let size = hardwareProbeSizeAsked
        return Self.hardwareFit(size.width, size.height)
    }

    /// The size a hardware stream would ask for now: the running one's at the full capture scale, or
    /// the Desktop's while nothing streams (a device asks for the Desktop first); either held to its
    /// display's own scale (CaptureScale), as the stream would be.
    private var hardwareProbeSizeAsked: (width: Int, height: Int) {
        if let size = Self.testProbeSize { return size }
        if active != .none, let enc = encoder {
            // The software encoder runs at points: the hardware's stream would run at the knob, both
            // held to the display's own scale (on a 1x display the two are one size).
            let hardware = CaptureScale.effective(knob: scale, displayScale: streamDisplayScale)
            let software = CaptureScale.effective(knob: min(scale, 1.0), displayScale: streamDisplayScale)
            let factor = enc.software ? hardware / software : 1
            return (evenPixels(CGFloat(enc.width) * factor), evenPixels(CGFloat(enc.height) * factor))
        }
        if synthetic { return (evenPixels(1512 * scale), evenPixels(949 * scale)) }
        if let d = catalog.display {
            let s = CaptureScale.effective(knob: scale, displayScale: Self.displayScale(of: SCContentFilter(display: d, excludingWindows: [])))
            return (evenPixels(CGFloat(d.width) * s), evenPixels(CGFloat(d.height) * s))
        }
        return (evenPixels(1920 * scale), evenPixels(1080 * scale))
    }

    /// A re-check found the hardware keeping up: the next pipeline uses it, and a running stream
    /// restarts on it now (one restart, like a settings change: Mac focus is left alone). Waits out
    /// a switch in flight first, which may be building a software encoder; false when it never
    /// settled, and the re-check tries again later.
    private func hardwareIsBack(measured: String, needed: Double) async -> Bool {
        var waited = 0
        while switching {
            guard waited < 50 else { return false }
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard useSoftwareEncoder, !shuttingDown else { return true }
        useSoftwareEncoder = false
        softwareRestarts = 0
        lastReturnAt = CFAbsoluteTimeGetCurrent()
        returnSerial = HEVCEncoder.latestSerial
        recheckHeldBack = false
        status.update { $0.softwareEncoder = false; $0.hardwareEncoderStuck = false }
        Stats.shared.bump("enc.hardwareBack")
        let test = "\(measured) in a test, \(Int(needed.rounded())) needed"
        if active != .none {
            print("Hardware encoder is back (\(test)); restarting the stream on it.")
            await select(active)   // nothing awaited since `switching` read false: this select runs
        } else {
            print("Hardware encoder is back (\(test)); the next stream uses it.")
        }
        return true
    }

    /// Out of "stuck": fewer than `maxStuckProbes` checks are still out, since one's frame came back
    /// (`seconds` after it went in, when the probe said). The menu stops asking for a restart of
    /// the Mac, and the log says so once, as it said "stuck" once.
    private func leaveStuck(cameBackAfter seconds: TimeInterval?) {
        guard recheckHeldBack else { return }
        recheckHeldBack = false
        status.update { $0.hardwareEncoderStuck = false }
        let after = seconds.map { " after \(String(format: "%.1f", $0)) s" } ?? ""
        print("Hardware encoder: a check's frame came back\(after), so it is not stuck; checks resume.")
    }

    /// A check's stalled frame came back (EncoderProbe's hook). While the re-check is held back as
    /// stuck and this brings the count under the limit, the menu stops saying "stuck" now, not when
    /// the held-back loop wakes (up to 300 s later, or never while no device is connected), and a
    /// check runs at once while a device is connected (the next device's first thing otherwise).
    private func stalledProbeCameBack(after seconds: TimeInterval) {
        guard recheckHeldBack, EncoderProbe.stuckProbes < Self.maxStuckProbes else { return }
        leaveStuck(cameBackAfter: seconds)
        recheckDue = CFAbsoluteTimeGetCurrent()
        recheckTask?.cancel()   // ends the held-back loop's sleep; its tail starts a new loop while a device is connected
    }

    private func windowsChanged(_ infos: [WindowInfo]) async {
        // The pointer's rectangle follows the catalog: the Desktop's display, a window's bounds.
        defer { pointer.setGeometry(pointerGeometry(), fps: fps) }
        // Locked, with no window streaming: the devices' list has no windows whatever changed, and no
        // launched app's window is picked (LockPolicy).
        if !lockAllowed.windows, !Self.isWindow(active) { return }
        if let pending = pendingLaunch, let w = infos.first(where: { $0.bundleID == pending }) {
            pendingLaunch = nil
            await select(.window(w.id), bringForward: true)   // launched from the device to use it: a pick
            return
        }
        if case .window(let id) = active {
            if await followTabSwap(for: id) { return }
            guard let w = infos.first(where: { $0.id == id }) else {
                // Alive on the virtual display even if the on-screen list dropped it.
                if virtualDisplay, stage.isStaged, Self.liveBounds(of: id) != nil { broadcastList(); return }
                // Leaving full screen, a window is off every list for a second or two. Give it
                // three polls before calling it closed, then restart so the stage re-places it.
                if virtualDisplay, stage.isStaged, stage.fullScreen {
                    missingPolls += 1
                    if missingPolls <= 3 { broadcastList(); return }
                    missingPolls = 0
                } else if !(virtualDisplay && stage.isStaged) {
                    // In regular mode too: one that was full screen when last listed, or that Sill fitted
                    // and Accessibility says is full screen now, keeps streaming through three looks, so a
                    // fitted window's way back is not decided mid-change (issue #57's review).
                    missingPolls += 1
                    var windows = WindowSizer.AXWindows(sizer: sizer)
                    if WindowRestore.keepsStreaming(fits.entries[id]?.handle, looks: missingPolls, wasFullScreen: listedFullScreen == id, on: &windows) {
                        broadcastList(); return
                    }
                    missingPolls = 0
                }
                await select(.none); return
            }
            missingPolls = 0
            if !(virtualDisplay && stage.isStaged), let scw = catalog.window(id: id) {
                listedFullScreen = WindowRestore.coversDisplay(scw.frame, WindowSizer.displayFrames()) ? id : nil
            }
            if virtualDisplay, stage.isStaged {
                // Full screen: the crop is a band of the display, not the window's frame. Stay put
                // while the window still covers the display; restart once it has left full screen.
                if stage.fullScreen {
                    if stage.windowStillFullScreen { broadcastList() } else { await select(active) }
                    return
                }
                // The crop differs from the window's frame, so the encoder-size check below would
                // restart every poll; compare against the display instead.
                if stage.windowLeftDisplay { await select(active); return }   // dragged off (Mission Control): re-place it
                if let live = stage.liveCaptureRect(),
                   abs(live.width - stage.captureRect.width) > 2 || abs(live.height - stage.captureRect.height) > 2 {
                    await select(active); return                              // the app resized itself: same display, new crop
                }
                broadcastList()
                return
            }
            // The encoder is fixed to one size, so a resized window means a fresh pipeline: when the
            // size `select` would ask for it now, at the scale its capture would run at and by the same
            // rounding, is not the encoder's (CaptureScale.windowNeedsRestart: a window whose odd side
            // was rounded up never restarts at every poll; a move to a display of another scale alone
            // is `catalogPolled`'s).
            if let scw = catalog.window(id: id) {
                if CaptureScale.windowNeedsRestart(encoder: encoderAsked, points: scw.frame.size,
                                                   knob: captureScale, displayScale: Self.displayScale(of: scw)) {
                    _ = w
                    await select(active)
                    return
                }
            }
        }
        broadcastList()
    }

    /// Re-targets the stream when the active window (`id`) was replaced in place by another native tab
    /// (#366). Waits while a switch is in flight so `tabSwaps[id]` is not consumed before `select` can
    /// take it (`catalogPolled` picks it up once `!switching`).
    private func followTabSwap(for id: CGWindowID) async -> Bool {
        guard !switching, !shuttingDown, active == .window(id),
              let nextID = catalog.tabSwaps[id], let nextW = catalog.window(id: nextID) else { return false }
        catalog.tabSwaps.removeValue(forKey: id)
        print("Tab switched in \(nextW.owningApplication?.applicationName ?? "?"): window \(id) → \(nextID) (\(nextW.title ?? "")).")
        if virtualDisplay, stage.isStaged, stage.placement?.windowID == id {
            _ = stage.adoptTab(nextW)
        }
        if fits.record(id) != nil, let nextPlacement = sizer.placement(for: nextW) {
            fits.transfer(from: id, to: nextID, handle: nextPlacement)
        }
        await select(.window(nextID))
        return true
    }

    /// The size the running encoder was asked for, before a hardware encoder's limit held it
    /// (EncoderLimit): what a window's new size is compared with, so a held one never restarts at every poll.
    private var encoderAsked = (width: 0, height: 0)

    // MARK: Trackpad gestures

    /// Posts gestures in arrival order, once a switch in flight is done (at most 2 s later): a
    /// gesture made while a window streamed comes right after the device's Desktop pick, the
    /// window may be on its way home from the virtual display, and the view should open over the
    /// Desktop, which is the only source that shows it.
    private func queueGesture(_ gesture: TrackpadGesture, from device: String, id: ObjectIdentifier) {
        pendingGestures.append((gesture, device, id))
        guard gestureDrain == nil else { return }
        gestureDrain = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = CFAbsoluteTimeGetCurrent() + 2
            while self.switching, CFAbsoluteTimeGetCurrent() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            while !self.pendingGestures.isEmpty {
                let next = self.pendingGestures.removeFirst()
                // Its device revoked or gone while the gesture waited for the switch: it acts no more.
                if self.revoked.contains(next.id) || self.routes[next.id] == nil { Stats.shared.bump("in.revoked"); continue }
                // This Mac locked meanwhile: no gesture (LockPolicy).
                if case .refuse(let why) = LockPolicy.decide(.gesture, reading: self.lockReading, paired: true) {
                    self.lockRefusals[why]?.count(why.rawValue)
                    Stats.shared.bump("lock.refused")
                    continue
                }
                self.performGesture(next.gesture, from: next.device, id: next.id)
            }
            self.gestureDrain = nil
        }
    }

    /// One gesture: the Mac's shortcut for it as its Keyboard Shortcuts are now (GestureChords),
    /// one line saying what it did, and the chord posted, behind input held for an activation; on
    /// a host that does not advertise, only counted. Nothing is raised or activated first: these
    /// views act on the whole Mac (App Exposé on the app in front), as they do from its keyboard.
    private func performGesture(_ gesture: TrackpadGesture, from device: String, id: ObjectIdentifier) {
        guard !shuttingDown else { return }
        let outcome = gestureChords.resolve(gesture.gesture, table: hotKeyTable())
        print(GestureChords.line(device: device, gesture: gesture.gesture, fingers: gesture.fingers,
                                 outcome: outcome, dryRun: gesturesDry))
        guard case .chord(_, _, let keyCode, let flags) = outcome else { return }
        if gesturesDry {
            Stats.shared.bump("in.gestureDry")
            return
        }
        if !heldInput.isEmpty || CFAbsoluteTimeGetCurrent() < holdUntil {
            heldInput.append(.chord(keyCode: keyCode, flags: flags, device: id))
            return
        }
        injector.chord(keyCode: keyCode, flags: flags)
    }

    /// A device's input as `GestureChords` weighs it: whether it can close a view a gesture opened.
    static func gestureInput(_ event: InputEvent) -> GestureChords.Input {
        switch event {
        case .pointer(let action, _, _):
            switch action {
            case .move: return .pointerMove
            case .leftDown, .rightDown: return .buttonDown
            case .leftUp, .rightUp: return .buttonUp
            }
        case .scroll, .scrollGesture: return .scroll
        case .key(_, let down, _): return down ? .keyDown : .keyUp
        case .text: return .text
        }
    }

    /// This Mac's Keyboard Shortcuts for the gestures, read now (SymbolicHotKeys); macOS 27's own
    /// when this macOS has no getters for them (said once); a test host's SILL_TEST_HOTKEYS table.
    private func hotKeyTable() -> [Int: HotKey] {
        if let testHotKeys { return testHotKeys }
        if let table = SymbolicHotKeys.read(GestureChords.hotKeyIDs) { return table }
        if !saidHotKeysMissing {
            saidHotKeysMissing = true
            print("Gestures: this macOS does not say what its keyboard shortcuts are; using macOS 27's own.")
        }
        return GestureChords.defaults
    }

    /// TEST ONLY: SILL_TEST_HOTKEYS, read once by a host that does not advertise: "defaults", or
    /// `ID=off` and `ID=KEYCODE:MODIFIERS` entries over them (GestureChords.testTable). A value that
    /// does not parse is ignored with one line.
    private static func testHotKeyTable() -> [Int: HotKey]? {
        guard let raw = ProcessInfo.processInfo.environment["SILL_TEST_HOTKEYS"], !raw.isEmpty else { return nil }
        guard let table = GestureChords.testTable(raw) else {
            print("SILL_TEST_HOTKEYS=\(raw) ignored: \"defaults\", or ID=off and ID=KEYCODE:MODIFIERS entries.")
            return nil
        }
        print("TEST: gestures use SILL_TEST_HOTKEYS=\(raw), not this Mac's keyboard shortcuts.")
        return table
    }

    // MARK: Catalog to clients

    /// The window list as each device is sent it (`broadcastList`, `sendCatalog`): in the off-console view
    /// (docs/off-console-plan.md) `view` is the view's list, with the windows and `offConsoleView`, for a device
    /// whose hello said it shows it, and `plain` the locked list for every other; else `view` is nil.
    private func listMessages() -> (view: StreamMessage?, plain: StreamMessage) {
        let plain = listMessage()
        guard lockGate.offConsoleView, lockReading == .offConsole else { return (nil, plain) }
        return (listMessage(offConsoleView: true), plain)
    }

    private func listMessage(offConsoleView: Bool = false) -> StreamMessage {
        var list = WindowList(macName: macName, windows: catalog.infos, active: active, launchID: launchID,
                              hostVersion: hostVersion, protocol: SillProtocol.current,
                              gestures: TrackpadGesture.generation, clipboard: clipboard.advertised)
        // This host repeats a device's held key (KeyRepeat), so a device sends it a hardware keyboard's
        // characters as keys.
        list.keyRepeat = KeyRepeat.generation
        // The Desktop's stops (DesktopDisplays), with two or more: a device's button reads "Desktop 2" and
        // steps with kind 47, and VoiceOver names the stop. None from a synthetic host, whose Desktop is the
        // test pattern, but under SILL_TEST_DISPLAYS; none while locked or off console (LockPolicy.list).
        let stops = catalog.desktopCandidates
        if !synthetic || catalog.testDisplays != nil, stops.count > 1 {
            list.desktopDisplays = stops.count
            list.desktopDisplay = DesktopDisplays.number(of: catalog.desktopDisplayID, in: stops)
            list.desktopDisplayNames = stops.map { SafeText.label($0.name ?? "", limit: 64) }
            // The Virtual Desktop's stop, while it is in the cycle (phase 2b): the button's "Virtual" there.
            list.desktopVirtual = DesktopDisplays.virtualNumber(in: stops)
        }
        // A locked Mac's list: no windows, no clipboard, `locked`, and off console `offConsole`
        // (LockPolicy); unlocked, as it is, byte for byte. Which went last, for `lockChanged`.
        let reading = lockReading
        lockedListSent = reading.locked
        return StreamMessage(kind: .windowList, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                             payload: Wire.encode(LockPolicy.list(list, reading: reading, offConsoleView: offConsoleView)))
    }

    private func broadcastList() {
        let lists = listMessages()
        if let view = lists.view { server.broadcastList(view: view, plain: lists.plain) } else { server.broadcast(lists.plain) }
    }

    private func sendCatalog(to connection: NWConnection) {
        let now = Date().timeIntervalSince1970
        // One reading for the whole catalog (the server's gate withholds the icons and apps anyway if the
        // Mac locks before they go).
        let shows = lockAllowed.appsAndIcons
        if shows {
            print("Catalog → \(connection.endpoint): \(catalog.infos.count) windows, \(catalog.allIcons.count) icons, \(catalog.installedApps.count) apps")
        } else {
            print("Catalog → \(connection.endpoint): no windows, icons or apps (this Mac is locked)")
        }
        let lists = listMessages()
        if let view = lists.view { server.sendList(view: view, plain: lists.plain, to: connection) } else { server.send(lists.plain, to: connection) }
        // What the settings are, silently (the line above is the only one printed on connect). An
        // older device skips the kind. Recorded as what this connection was last sent, and only
        // then does it join the publishes: none goes out ahead of its window list, and the catalog
        // keeps its order (2, 16, 18).
        let id = ObjectIdentifier(connection)
        let state = settingsState(for: id)
        server.send(settingsMessage(state), to: connection)
        lastPublished[id] = state
        connections[id] = connection
        // Who this Mac is and how to reach it from afar (kind 18, signed), on both doors, only from
        // a host with an identity. An older device skips it too.
        if let info = remote?.macInfoMessage() { server.send(info, to: connection) }
        // The icons and the installed apps say what runs and what is installed: none while this Mac is
        // locked (LockPolicy); a device that connected then gets them at the unlock
        // (`sendWithheldAppsAndIcons`).
        if shows {
            appsAndIconsSent.insert(id)
            for (id, png) in catalog.allIcons {
                server.send(StreamMessage(kind: .appIcon, timestamp: now, isKeyframe: false,
                                          payload: ImageBlob.encodeIcon(bundleID: id, png: png)), to: connection)
            }
            server.send(StreamMessage(kind: .appList, timestamp: now, isKeyframe: false,
                                      payload: Wire.encode(catalog.installedApps)), to: connection)
        }
        // The cursor's shape says what is under it: none while locked (the gate withholds it too).
        if lockAllowed.pointer, let shape = cursorShapes.current {
            server.send(StreamMessage(kind: .cursorShape, timestamp: now, isKeyframe: false, payload: shape), to: connection)
        }
    }

    /// A locked Mac's placeholder size: the Desktop's display's shape from the catalog's last look, with no
    /// new ScreenCaptureKit call (LockPolicy.placeholderSize).
    private func placeholderSize() -> (width: Int, height: Int) {
        // A test host's shown stop under SILL_TEST_DISPLAYS (the main display while locked).
        if catalog.testDisplays != nil, let stop = catalog.desktopStop {
            return LockPolicy.placeholderSize(display: (Int(stop.frame.width), Int(stop.frame.height)))
        }
        return LockPolicy.placeholderSize(display: catalog.display.map { ($0.width, $0.height) })
    }

    // MARK: Settings to devices

    /// The last state each connection was sent: at connect (`sendCatalog`) and by each publish.
    /// Answers never touch it.
    private var lastPublished: [ObjectIdentifier: HostSettingsState] = [:]

    /// Connection `id`'s state (docs/remote-bundle-plan.md §5.4): the pair its controls set (the
    /// away quality for a device away), the home and away qualities with which one is the target
    /// (`away`, from a host with an identity, `remote`: SillHost --pairing alone too, where no
    /// connection is ever away), whether its key is paired (`sessionPaired`), the Virtual Desktop as it
    /// sees it, and the rest shared. A pure function of the target, `awayWanted`, the connection's route
    /// and viewport, the status snapshot (its trust list too) and two constants (appKitLoop, whether the
    /// hook is set). The target changes only in `setTarget`, the snapshot only in `HostStatus.update`,
    /// `awayWanted` only in `routesChanged`, which updates the snapshot with it, and the viewport where a
    /// device sends one, which publishes while the Virtual Desktop's switch is on (the state reads it then
    /// alone); all four publish, so no change can be missed and none can stick. Never the
    /// pipeline's `awayRunning`: it changes in `adopt`, which publishes only through a snapshot
    /// change, and none comes while nothing streams.
    private func settingsState(for id: ObjectIdentifier, answering: Int? = nil) -> HostSettingsState {
        let t = target, s = status.snapshot
        let thisAway = routes[id]?.isAway ?? false
        // A report about the bitrate that runs while it is still the target's; one about a bitrate a
        // pick has just replaced is stale (the restart's reset clears it a moment later).
        let link = linkReports[id].flatMap { $0.bitrate == t.effective(away: awayWanted).bitrate ? $0 : nil }
        let away = remote.map { _ in
            AwayQuality(homeBitrate: t.bitrate, homeCaptureScale: Double(t.captureScale),
                        awayBitrate: t.awayBitrate, awayCaptureScale: Double(t.awayCaptureScale),
                        thisConnectionAway: thisAway, awayRunning: awayWanted)
        }
        var state = HostSettingsState(settings: t.streamSettings(away: thisAway),
                                      persistent: onDeviceSettingsChange != nil,
                                      virtualDisplayAvailable: appKitLoop,
                                      virtualDisplayNote: virtualDisplayNote(target: t, snapshot: s),
                                      softwareEncoder: s.softwareEncoder,
                                      stream: s.stream?.wire,
                                      answering: answering,
                                      away: away,
                                      link: link,
                                      audioNote: t.sendAudio ? s.audio?.note : nil,
                                      sessionPaired: sessionPaired(id))
        state.virtualDesktopState = virtualDesktopState(target: t, snapshot: s, viewport: viewports[id])
        return state
    }

    /// The Virtual Desktop as connection `id` sees it (kind 16's `virtualDesktopState`, phase 2b): whether this Mac can make
    /// it now and why not, whether the Desktop shows it, and, while its switch is on, the size and rate it has, or would
    /// have for this device (`virtualDesktopWanted`: the person's choice, This device's for its last viewport, none before
    /// it sent one). Pure of the target, the snapshot and the connection's viewport, each of which publishes when it
    /// changes (a viewport while the switch is on: `virtualDesktopViewport`), and for "Same as main display" of the main
    /// display's mode, read then.
    private func virtualDesktopState(target t: HostConfig, snapshot s: HostStatusSnapshot, viewport vp: Viewport?) -> VirtualDesktopState {
        var state = VirtualDesktopState(available: s.virtualDesktop.available, note: s.virtualDesktop.note, shown: s.virtualDesktop.shown)
        guard t.virtualDesktop else { return state }
        if let d = s.sillDisplay, d.virtualDesktop {
            state.size = VirtualDesktopState.size(widthPt: d.widthPt, heightPt: d.heightPt, scale: d.scale)
            state.hz = d.hz
        } else if vp != nil || VirtualDesktopSize.choice(t.virtualDesktopSize) != .device {
            let wanted = virtualDesktopWanted(target: t, viewport: vp)
            state.size = VirtualDesktopState.size(widthPt: wanted.size.widthPt, heightPt: wanted.size.heightPt, scale: wanted.size.scale)
            state.hz = wanted.hz
        }
        return state
    }

    /// Whether connection `id`'s key is on this Mac's trust list now, as the status snapshot lists it
    /// (RemoteAccess publishes every change of the list, and each change publishes the settings): the
    /// one judgement both of what the connection may set (Direct Wireless, `DeviceSettings.accepted`)
    /// and of what its state says (`sessionPaired`, so the device's panel disables what the Mac would
    /// refuse). A pure function of the route and the snapshot, as `settingsState` is. False at the
    /// plain door (no key), for an unpaired key at a door that lets any device in, on a host without
    /// an identity (no list), and for a route not known.
    private func sessionPaired(_ id: ObjectIdentifier) -> Bool {
        let trusted = status.snapshot.remote?.paired.compactMap { Base64URL.decode($0.id) } ?? []
        return DeviceSettings.paired(key: routes[id]?.fingerprint, trusted: trusted)
    }

    /// The Mac's Virtual Display pane in its order (SettingsPanes.swift, `statusText`), without the
    /// permission lines: permissions are polled, not event-driven, and a missing one still reaches
    /// the device as the fallback reason on the next pick.
    private func virtualDisplayNote(target t: HostConfig, snapshot s: HostStatusSnapshot) -> String? {
        if !appKitLoop { return "Start SillHost with --virtual-display to use it." }
        if s.virtualDisplayAPIMissing, let p = s.virtualDisplayProblem { return "Not available on this version of macOS: \(p)" }
        guard t.virtualDisplay else { return nil }
        if let p = s.virtualDisplayProblem { return "Off for this session: \(p). Turn it off and on to try again." }
        if let f = s.lastStageFailure { return "The last window streamed where it is: \(f)" }
        return nil
    }

    private func settingsMessage(_ state: HostSettingsState) -> StreamMessage {
        StreamMessage(kind: .hostSettings, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                      payload: Wire.encode(state))
    }

    /// To every device whose catalog went out, its own state, when that differs from the last one
    /// it was sent. Prints nothing, so the CLI's output only changes when a device sends a change.
    private func publishSettings() {
        var messages: [(NWConnection, StreamMessage)] = []
        for (id, connection) in connections {
            let state = settingsState(for: id)
            guard state != lastPublished[id] else { continue }
            lastPublished[id] = state
            messages.append((connection, settingsMessage(state)))
        }
        if !messages.isEmpty { server.send(each: messages) }
    }

    /// "iPad (iPad14,1)" once the device has sent its stats, its address until then.
    private func deviceName(_ connection: NWConnection) -> String {
        status.snapshot.devices.first { $0.id == ObjectIdentifier(connection) }?.name ?? "\(connection.endpoint)"
    }
}

extension ClientRoute {
    /// Away from home: the remote door from a VPN, the internet or a relay on this Mac
    /// (AwayPolicy.isAway). Its Quality and Resolution picks set the away quality, which runs while
    /// every connected device is away. Here, not beside ClientRoute in StreamServer.swift, which the
    /// pacing harness compiles without the coordinator's files.
    var isAway: Bool { AwayPolicy.isAway(remoteDoor: isRemote, origin: origin) }
}
