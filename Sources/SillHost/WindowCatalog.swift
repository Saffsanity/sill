import Foundation
import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import StreamProtocol

/// Knows what is on the Mac: the on-screen windows, a small JPEG thumbnail of each, app icons,
/// and the installed apps for the drawer. Everything here runs on the main actor; callbacks fire
/// there too and the coordinator forwards to the network.
///
/// Idle means idle: with no client connected nothing here runs on a timer. The window list is
/// read once at startup (the coordinator's `refreshWindows()`, so the CLI can print a count) and
/// then only while at least one client is connected, every `pollInterval`, together with the
/// thumbnails. The installed-app scan runs once at startup, off the main thread. So after a spell
/// with no client the last look can be hours old and its display gone: the coordinator looks again
/// before it builds a capture from it (CatalogLook, `lookAge`).
@MainActor
final class WindowCatalog {
    private(set) var windows: [SCWindow] = []
    private(set) var infos: [WindowInfo] = []
    private(set) var display: SCDisplay?
    /// The successful raw look, before the thumbnail policy drops menus, sheets and small windows.
    /// A failed read leaves the previous snapshot intact; it never means an empty allowlist.
    struct CaptureSnapshot {
        let applications: [SCRunningApplication]
        let windows: [SCWindow]
        let startedAt: ContinuousClock.Instant

        static func plain(_ window: SCWindow) -> StageCaptureWindows.Window {
            StageCaptureWindows.Window(id: window.windowID, owner: window.owningApplication.map(plain))
        }

        static func plain(_ app: SCRunningApplication) -> StageCaptureWindows.Application {
            StageCaptureWindows.Application(pid: app.processID, bundleID: app.bundleIdentifier)
        }

        func membership(for selected: SCWindow) -> StageCaptureWindows {
            // Preparation reads the full list; polling usually reads only on-screen windows. Judge
            // both alike, or an off-screen auxiliary window would cause a restart every poll.
            StageCaptureWindows(selected: Self.plain(selected), applications: applications.map(Self.plain),
                                windows: windows.filter { $0.isOnScreen }.map(Self.plain))
        }
    }
    private(set) var captureSnapshot: CaptureSnapshot?
    private(set) var installedApps: [AppInfo] = []
    /// This process as ScreenCaptureKit lists it, from the last look: the Desktop stream leaves it
    /// out, so Sill's own windows (the pairing code above all) never reach a device. Nil when it
    /// is not listed (the CLI has no windows; see `resolveOwnApplication`).
    private(set) var ownApplication: SCRunningApplication?
    /// When the last look (`refreshWindows`) landed, on the clock that keeps counting while the Mac
    /// sleeps. Nil before the first. A capture is built from the look only while it will do
    /// (CatalogLook, the coordinator's `lookAgainIfStale`): after a spell with no device it can be a
    /// day old, its display gone (the black screen of 2026-10-28).
    private(set) var lookedAt: ContinuousClock.Instant?
    /// Seconds since the last look, nil before the first.
    var lookAge: TimeInterval? { lookedAt.map { CatalogLook.seconds(ContinuousClock.now - $0) } }

    /// Fires when the window list changes (new, closed, retitled, resized, reordered).
    var onWindowsChanged: (([WindowInfo]) -> Void)?
    /// Fires after every poll's window-list read (each `pollInterval` while a client is connected),
    /// changed or not: the Desktop's menus follow the frontmost app, and an app's menus that did
    /// not answer are read again (StreamCoordinator's `menusPolled`).
    var onPolled: (@MainActor () -> Void)?
    /// A fresh thumbnail for one window.
    var onThumbnail: ((UInt32, Data) -> Void)?
    /// An icon we have not announced yet (running or installed app). Only fires while a client is
    /// connected; with none it is just stored, and `allIcons` hands it to the next client.
    var onNewIcon: ((String, Data) -> Void)?
    /// The installed-app scan finished (it runs in the background after launch). A client that
    /// connected before this saw an empty "All apps" list; the coordinator re-sends it.
    var onInstalledAppsReady: (([AppInfo]) -> Void)?

    /// Thumbnails cost a screenshot per window; only take them while someone is looking. They are
    /// taken inside the client-driven poll, so with `clientCount == 0` none are taken regardless.
    /// Setting this to true (even when already true) means "someone new is looking": the next
    /// pass re-sends every thumbnail, and it runs right away. The coordinator sets it in its
    /// client-connected callback, i.e. once the connection is ready and just before it sends the
    /// catalog, so the new client gets the list and icons first and then every thumbnail.
    var thumbnailsWanted = false {
        didSet { if thumbnailsWanted && clientCount > 0 { resendAllThumbnails() } }
    }

    /// This Mac's screen is locked (the coordinator's reading; LockPolicy, docs/locked-mac-plan.md): no
    /// thumbnail is taken, and none that a capture under way brings back is sent, no new icon goes out
    /// and the installed apps are not sent when their scan ends (`allIcons` and `installedApps` keep
    /// them for the unlock, which the coordinator sends). The window list is still read, so the unlock
    /// finds the windows as they are. Unlocked again: every thumbnail is taken and sent afresh.
    var locked = false {
        didSet { if oldValue && !locked { resendAllThumbnails() } }
    }
    /// The lock's gate now (SessionLock's, set on its own queue the moment a witness says locked): asked
    /// before each thumbnail, so none is taken after the lock even before the coordinator has set `locked`.
    var isLocked: () -> Bool = { false }
    /// Locked by either: what this catalog withholds by.
    private var withholding: Bool { locked || isLocked() }
    /// What `locked` withheld from the devices that were connected: the icons announced meanwhile, and
    /// whether the installed apps' scan ended meanwhile (`takeWithheld`).
    private var withheldIcons: [String] = []
    private var appsWithheld = false

    /// What was withheld while locked, once: the coordinator sends it at the unlock to the devices that
    /// were connected before the lock (one that connected while locked gets every icon and the apps).
    func takeWithheld() -> (icons: [(bundleID: String, png: Data)], apps: Bool) {
        defer { withheldIcons = []; appsWithheld = false }
        return (withheldIcons.compactMap { id in icons[id].map { (id, $0) } }, appsWithheld)
    }

    /// Connected clients, from the server. 0→N starts polling (with an immediate pass); N→0 stops
    /// it, so an idle host makes no ScreenCaptureKit calls at all.
    ///
    /// Ordering on connect: the server reports the new count when it admits the connection (at
    /// ready, once its origin passed), just before the coordinator's `sendCatalog` runs. The pass
    /// started here awaits `SCShareableContent` (tens of ms), so it usually finishes after
    /// `sendCatalog` has already sent the list as of the last look. That is fine: when the fresh
    /// list differs, `onWindowsChanged` fires and the coordinator broadcasts it, so the client is
    /// at most one round trip stale, never a poll interval. If the refresh lands before ready,
    /// `sendCatalog` simply sends the fresh list. New icons found by that pass are broadcast, and
    /// also stored first, so `allIcons` covers a client that was not ready for the broadcast.
    var clientCount = 0 {
        didSet {
            guard clientCount != oldValue else { return }
            Stats.shared.activeClients = clientCount
            if oldValue == 0 && clientCount > 0 {
                devicesArrived()
                startPolling()
            } else if oldValue > 0 && clientCount == 0 {
                devicesLeftAt = .now
                stopPolling()
            } else if clientCount > oldValue {
                resendAllThumbnails()      // another client joined; it has no thumbnails yet
            }
        }
    }

    /// The window being streamed, if the coordinator tells us. Its thumbnail refreshes every pass
    /// because its contents are the ones changing. Nil is fine: it is then treated like any other.
    var activeWindowID: UInt32?

    /// The Desktop's stop a device stepped to (kind 47, DesktopDisplays), by its UUID: kept across sleeps,
    /// where a display's ID can change, while a device is connected and for DesktopDisplays.choiceGrace
    /// after the last one left (`clientCount`), so a reconnect or a move to the cable comes back to it and a
    /// later session begins on the main display. Nil until a device steps; while its display is unplugged
    /// the Desktop is on the main display, and back on it when it returns.
    private(set) var desktopDisplayUUID: String?
    /// When the last device left, on the clock that keeps counting while the Mac sleeps: the choice's span.
    private var devicesLeftAt: ContinuousClock.Instant?
    /// The Desktop's stops from the last look, in the cycle's order (DesktopDisplays.candidates: the main
    /// display first, never Sill's own display or macOS's stand-in, one per mirror set): the window list's
    /// `desktopDisplays`, `desktopDisplay` and `desktopDisplayNames`.
    private(set) var desktopCandidates: [DesktopDisplays.Display] = []
    /// The stop the Desktop shows, or comes back to while a window streams: `display`'s ID, or a test
    /// host's stop's (`testDisplays`). Nil with no display at all.
    private(set) var desktopDisplayID: UInt32?
    /// The displays the last look listed, which the stops are chosen among (where PR #200 puts its pool:
    /// a real display, else Sill's, else macOS's stand-in).
    private var lookedDisplays: [SCDisplay] = []
    /// The Desktop on the main display alone (DesktopDisplays.resolve's `mainOnly`): this Mac locked, or
    /// another user on its screen (the coordinator's lock reading). The choice is kept, and the Desktop
    /// goes back to it when this is cleared.
    var mainOnly = false {
        didSet { if mainOnly != oldValue { resolveDesktopDisplay() } }
    }
    /// The displays the stage made this run (VirtualStage: a picked window's own display), by ID: never one of the
    /// Desktop's stops, also once one has gone and reads no monitor (vendor 0xFFFFFFFF) while an old look still lists it
    /// (DesktopDisplays.role). Kept for the run; an ID that now reads another display's identity is that display.
    var stageDisplayIDs: Set<CGDirectDisplayID> = []
    /// TEST ONLY (SILL_TEST_DISPLAYS on a --synthetic host, DesktopDisplaysHook): the stops a test host
    /// lists in place of this Mac's displays, the first its main display. Nil on every other host.
    var testDisplays: [DesktopDisplays.Display]? {
        didSet { resolveDesktopDisplay() }
    }
    /// The Desktop's stops, which one it shows, or their names changed: the list goes out again, and a
    /// Desktop streaming another display restarts on the one it shows now.
    var onDesktopDisplaysChanged: (() -> Void)?

    /// `--virtual-display`: the window the coordinator has moved onto the virtual display. Set right
    /// after a successful placement, cleared on release. If ScreenCaptureKit stops treating it as
    /// on-screen there (unverified), it is fetched from the full window list so its tile stays in
    /// the client's bar and the coordinator can still find it.
    var stagedWindowID: CGWindowID?

    /// A window in the plain values CatalogWindows judges it by.
    static func plain(_ w: SCWindow) -> CatalogWindows.Window {
        CatalogWindows.Window(title: w.title, appName: w.owningApplication?.applicationName,
                              bundleID: w.owningApplication?.bundleIdentifier,
                              pid: w.owningApplication?.processID ?? -1, layer: w.windowLayer,
                              width: Double(w.frame.width), height: Double(w.frame.height))
    }

    /// The owners whose left-out windows Sill.log has named (CatalogWindows.leftOutLines): once each.
    private var leftOutNamed: Set<String> = []

    /// Window list and thumbnails, while a client is connected.
    static let pollInterval: Duration = .seconds(2)
    /// A window whose `WindowInfo` (title, app, size) has not changed since its last thumbnail,
    /// and which is not the active source, is re-shot only this often. Most windows on a Mac are
    /// static; re-screenshotting them every pass is the bulk of the catalog's cost in use.
    static let staticThumbnailInterval: Duration = .seconds(6)

    private var seenOrder: [UInt32] = []
    private var icons: [String: Data] = [:]
    private var announcedIcons: Set<String> = []
    private var started = false

    private var pollTask: Task<Void, Never>?
    /// The poll loop's current sleep, separate so a kick can end it early without cancelling the loop.
    private var sleeper: Task<Void, Never>?
    /// Set by a kick that arrives mid-pass: run another pass instead of sleeping.
    private var passOwed = false
    /// What each window looked like when its thumbnail was last taken, and when.
    private var thumbStamps: [UInt32: (info: WindowInfo, at: ContinuousClock.Instant)] = [:]
    /// Refreshes can overlap (startup call plus the first poll); only the newest result applies.
    private var refreshSeq = 0
    private var appliedSeq = 0

    static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// TEST ONLY (SILL_TEST_NO_SCREEN=1 on a --synthetic host, set by the coordinator): the catalog
    /// never touches ScreenCaptureKit: no window list (it stays empty), no thumbnails, no display
    /// lookup, so a test host that an agent runs with a client connected asks macOS for no screen
    /// recording (every ScreenCaptureKit call is checked against the responsible app's grant, and
    /// macOS reminds the person about it once a month and after every rebuilt binary). The Desktop
    /// is the test pattern anyway. Read off the main actor by the bounded lookup below.
    nonisolated(unsafe) static var screenless = false

    /// Starts the one-time installed-app scan, and polling if a client is already connected.
    /// Does not read the window list itself: the coordinator awaits `refreshWindows()` right after.
    func start() {
        guard !started else { return }
        started = true
        scanInstalledApps()
        if clientCount > 0 { startPolling() }
    }

    func window(id: UInt32) -> SCWindow? { windows.first { $0.windowID == id } }

    /// `window(id:)`, else one look at every window the system knows (on-screen or not). The
    /// coordinator uses it for the staged window, whose SCWindow must be fresh after the move: the
    /// probe refetched too before capturing on the virtual display. Never one of Sill's own
    /// windows, as in the catalog: a device may name any window ID in a pick, and one just above
    /// the newest it knows could be the pairing window with its code.
    func resolveWindow(id: UInt32) async -> SCWindow? {
        if let w = window(id: id) { return w }
        guard let all = await Self.shareableContent(excludingDesktopWindows: false, onScreenWindowsOnly: false, timeout: 3) else { return nil }
        return all.windows.first { $0.windowID == id && !Self.isOwn($0) }
    }

    /// `ownApplication`, else one look at every window (on screen or not) for this process. The
    /// on-screen look can miss Sill while it shows nothing on screen: its status item's window
    /// leaves the list while a full-screen app hides the menu bar, and a Desktop stream started
    /// then would leave nothing out, so a pairing window opened later would reach the devices. Nil
    /// when this process has no window at all (the CLI).
    func resolveOwnApplication() async -> SCRunningApplication? {
        if let own = ownApplication { return own }
        guard let all = await Self.shareableContent(excludingDesktopWindows: false, onScreenWindowsOnly: false, timeout: 3) else { return nil }
        return all.applications.first { $0.processID == Self.ownPID }
            ?? all.windows.first { Self.isOwn($0) }?.owningApplication
    }

    /// One of this process's own windows (Settings, the log, the pairing window with its code).
    static func isOwn(_ w: SCWindow) -> Bool { w.owningApplication?.processID == ownPID }

    /// The displays macOS has active now (connected, awake, drawable; Sill's own virtual display too
    /// while it exists), by ID: what the last look's display is judged against before a capture is
    /// built from it (CatalogLook). No ScreenCaptureKit call. Empty when the call fails.
    nonisolated static func activeDisplayIDs() -> [UInt32] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// `SCShareableContent`, but never for longer than `timeout`. Measured 2026-09-22: in a process
    /// without Screen Recording the call never returned once a virtual display existed (it returns
    /// promptly, with no windows, without one). The virtual-display paths use this so a hang there
    /// costs seconds and a fallback, not the coordinator's `switching` flag for good. The default
    /// path's `refreshWindows` keeps the plain call it always had.
    nonisolated static func shareableContent(excludingDesktopWindows: Bool, onScreenWindowsOnly: Bool, timeout: TimeInterval) async -> SCShareableContent? {
        if screenless { return nil }                 // TEST ONLY: ScreenCaptureKit never asked
        final class Once: @unchecked Sendable {
            private let lock = NSLock(); private var done = false
            func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
        let once = Once()
        return await withCheckedContinuation { (c: CheckedContinuation<SCShareableContent?, Never>) in
            SCShareableContent.getExcludingDesktopWindows(excludingDesktopWindows, onScreenWindowsOnly: onScreenWindowsOnly) { content, _ in
                if once.first() { c.resume(returning: content) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.first() { c.resume(returning: nil) }   // the late answer, if any, is dropped
            }
        }
    }

    /// Every icon we know, for a client that just connected.
    var allIcons: [(bundleID: String, png: Data)] { icons.map { ($0.key, $0.value) } }

    // MARK: Polling (only while a client is connected)

    private func startPolling() {
        guard started, pollTask == nil else { return }
        thumbStamps = [:]
        pollTask = Task { @MainActor [weak self] in await self?.pollLoop() }
    }

    private func stopPolling() {
        pollTask?.cancel()
        sleeper?.cancel()
        pollTask = nil
        thumbStamps = [:]
    }

    /// One pass right away, then one every `pollInterval`, until cancelled. A pass is a window
    /// list refresh followed by whichever thumbnails are due.
    private func pollLoop() async {
        while !Task.isCancelled {
            passOwed = false
            await refreshWindows()
            if Task.isCancelled { break }
            onPolled?()
            if thumbnailsWanted && !withholding { await refreshThumbnails() }
            if Task.isCancelled { break }
            if passOwed { continue }
            let nap = Task { _ = try? await Task.sleep(for: Self.pollInterval) }
            sleeper = nap
            await nap.value
            if sleeper == nap { sleeper = nil }
        }
    }

    /// Forget which thumbnails were sent and run a pass now (or right after the current one).
    private func resendAllThumbnails() {
        guard pollTask != nil else { return }
        thumbStamps = [:]
        passOwed = true
        sleeper?.cancel()
    }

    // MARK: Windows

    func refreshWindows() async {
        refreshSeq += 1
        let seq = refreshSeq
        let startedAt = ContinuousClock.now
        guard !Self.screenless else { return }      // TEST ONLY: ScreenCaptureKit never asked
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
        // The staged window, if the on-screen list dropped it: one extra SCShareableContent call per
        // poll, and only then. Fetched before the sequence check so its await cannot let an older
        // refresh overwrite a newer one.
        var pinned: SCWindow? = nil
        var captureContent = content
        var captureReadSucceeded = true
        if let id = stagedWindowID, !content.windows.contains(where: { $0.windowID == id }) {
            if let all = await Self.shareableContent(excludingDesktopWindows: false, onScreenWindowsOnly: false, timeout: 3) {
                captureContent = all
                if stagedWindowID == id { pinned = all.windows.first { $0.windowID == id && !Self.isOwn($0) } }
                if pinned != nil { print("Catalog: the staged window \(id) is not in the on-screen list; pinned it from the full list.") }
            } else {
                captureReadSucceeded = false
            }
        }
        guard seq > appliedSeq else { return }      // a newer refresh already landed; don't go backwards
        appliedSeq = seq
        if captureReadSucceeded {
            captureSnapshot = CaptureSnapshot(applications: captureContent.applications, windows: captureContent.windows,
                                              startedAt: startedAt)
        }
        lookedAt = .now
        ownApplication = content.applications.first { $0.processID == Self.ownPID }
        lookedDisplays = content.displays
        resolveDesktopDisplay()
        // An app's own windows only (CatalogWindows): no widgets, wallpaper or backstop, nothing of
        // Sill's, and no helper's window (LayerProbeParent, macOS's own interface, a tool's overlay).
        let plain = content.windows.map(Self.plain)
        var visible = zip(content.windows, plain).filter { CatalogWindows.lists($1, ownPID: Self.ownPID) }.map(\.0)
        for line in CatalogWindows.leftOutLines(plain, ownPID: Self.ownPID, named: &leftOutNamed) { print(line) }
        if let pinned, !visible.contains(where: { $0.windowID == pinned.windowID }) { visible.append(pinned) }
        // The system's order is not front-to-back and shuffles between polls. The brief wants a
        // fixed order in the bar, so keep first-seen order and append newcomers.
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.windowID, $0) })
        seenOrder = seenOrder.filter { byID[$0] != nil } + visible.map(\.windowID).filter { !seenOrder.contains($0) }
        let ordered = seenOrder.compactMap { byID[$0] }
        let newInfos = ordered.map { w in
            WindowInfo(id: w.windowID,
                       title: w.title ?? "",
                       appName: w.owningApplication?.applicationName ?? "",
                       bundleID: w.owningApplication?.bundleIdentifier ?? "",
                       width: Int(w.frame.width), height: Int(w.frame.height))
        }
        windows = ordered
        Stats.shared.windowCount = ordered.count
        for w in ordered { announceIconIfNeeded(for: w.owningApplication) }
        if newInfos != infos {
            infos = newInfos
            onWindowsChanged?(newInfos)
        }
    }

    /// Steps the Desktop to the stop after the one it shows (kind 47), from the last look: kept by its
    /// UUID, and `display` at once. Nil with fewer than two stops, or while only the main display shows.
    func chooseNextDesktopDisplay() -> DesktopDisplays.Display? {
        guard !mainOnly, let next = DesktopDisplays.next(after: desktopDisplayID, in: desktopCandidates) else { return nil }
        chooseDesktopDisplay(next.uuid)
        return next
    }

    /// The Desktop's stop by UUID (nil: none chosen, the main display), and `display` from the last look
    /// at once.
    func chooseDesktopDisplay(_ uuid: String?) {
        desktopDisplayUUID = uuid
        resolveDesktopDisplay()
    }

    /// The stop the Desktop shows now, if it is one.
    var desktopStop: DesktopDisplays.Display? { desktopCandidates.first { $0.id == desktopDisplayID } }

    /// The main display as the last look has it, whatever the Desktop shows: the Desktop's sound is built
    /// on it (the coordinator's `makeAudioSource`), so a step never restarts the sound. Else macOS's first.
    var mainDisplay: SCDisplay? { lookedDisplays.first { $0.displayID == CGMainDisplayID() } ?? lookedDisplays.first }

    /// A device is connected again after none was: a choice older than its span is forgotten, so the
    /// session begins on the main display (DesktopDisplays.keepsChoice).
    private func devicesArrived() {
        defer { devicesLeftAt = nil }
        guard desktopDisplayUUID != nil, let left = devicesLeftAt else { return }
        let gone = CatalogLook.seconds(ContinuousClock.now - left)
        if !DesktopDisplays.keepsChoice(devices: 0, leftAt: 0, now: gone) { chooseDesktopDisplay(nil) }
    }

    /// `display` from the last look (DesktopDisplays.resolve): the main display while `mainOnly`; else the
    /// stop a device stepped to while it is connected; else the main display, with Virtual Display on or
    /// off (issue #345). With no stop at all (every display Sill's own or macOS's stand-in): the main
    /// display, else macOS's first, as before.
    private func resolveDesktopDisplay() {
        let before = (desktopCandidates.map(\.id), desktopCandidates.map(\.name), desktopDisplayID)
        let stops = testDisplays ?? lookedDisplays.map(described)
        desktopCandidates = DesktopDisplays.candidates(stops, main: testDisplays?.first?.id ?? CGMainDisplayID())
        let id = DesktopDisplays.resolve(chosen: desktopDisplayUUID, among: desktopCandidates, mainOnly: mainOnly)?.id
        display = lookedDisplays.first { $0.displayID == id } ?? mainDisplay
        desktopDisplayID = testDisplays != nil ? id : display?.displayID
        if before != (desktopCandidates.map(\.id), desktopCandidates.map(\.name), desktopDisplayID) {
            onDesktopDisplaysChanged?()
        }
    }

    /// A display as DesktopDisplays judges it: its UUID, frame, what it is (the stage's by the IDs the stage made, or
    /// by its identity read now: DesktopDisplays.role), whether it is there now, the display it mirrors, its refresh
    /// rate and its name.
    private func described(_ d: SCDisplay) -> DesktopDisplays.Display {
        let id = d.displayID
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        let mirrors = CGDisplayMirrorsDisplay(id)
        let refresh = CGDisplayCopyDisplayMode(id).map { $0.refreshRate }
        let role = DesktopDisplays.role(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id),
                                        madeByStage: stageDisplayIDs.contains(id))
        return DesktopDisplays.Display(id: id, uuid: uuid ?? "display \(id)", frame: d.frame,
                                       role: role, online: CGDisplayIsOnline(id) > 0,   // a gone display's ID reads -1
                                       mirrors: mirrors == kCGNullDirectDisplay ? nil : mirrors,
                                       refreshHz: refresh.flatMap { $0 > 0 ? $0 : nil },
                                       name: VirtualStage.screen(for: id)?.localizedName)
    }

    /// Thumbnail cadence, per window: every pass (2 s) if its `WindowInfo` changed since its last
    /// thumbnail or it is the active source; otherwise every `staticThumbnailInterval` (6 s), which
    /// still catches content changing inside a window of fixed size and title. A window is
    /// stamped before the capture, so one that fails to capture also backs off to 6 s.
    private func refreshThumbnails() async {
        guard !Self.screenless else { return }      // TEST ONLY: no captures either
        // 2× the 104×66 pt tile in the client's bar. Fit each window's aspect inside that box.
        let box = CGSize(width: 208, height: 132)
        let now = ContinuousClock.now
        let infoByID = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })
        thumbStamps = thumbStamps.filter { infoByID[$0.key] != nil }      // forget closed windows
        for w in windows {
            if Task.isCancelled || withholding { return }   // locked meanwhile: no more captures
            guard let info = infoByID[w.windowID] else { continue }
            if let stamp = thumbStamps[w.windowID], stamp.info == info, w.windowID != activeWindowID,
               now - stamp.at < Self.staticThumbnailInterval { continue }
            thumbStamps[w.windowID] = (info, now)
            let sf = min(box.width / w.frame.width, box.height / w.frame.height)
            let config = SCStreamConfiguration()
            config.width = max(2, Int(w.frame.width * sf))
            config.height = max(2, Int(w.frame.height * sf))
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: w)
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  let jpeg = Self.jpeg(image, quality: 0.6) else { continue }
            // Locked while it was taken: dropped (the unlock takes every thumbnail afresh).
            if withholding { return }
            onThumbnail?(w.windowID, jpeg)
        }
    }

    // MARK: Icons

    private func announceIconIfNeeded(for app: SCRunningApplication?) {
        guard let app else { return }
        let id = app.bundleIdentifier
        guard !id.isEmpty, !announcedIcons.contains(id) else { return }
        let image = NSRunningApplication(processIdentifier: app.processID)?.icon
            ?? NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? "")
        guard let png = Self.png(image, size: 64) else { return }
        announce(bundleID: id, png: png)
    }

    private func announce(bundleID: String, png: Data) {
        icons[bundleID] = png
        announcedIcons.insert(bundleID)
        // With nobody connected a broadcast reaches no one; `allIcons` carries it to the next client.
        // While locked it waits for the unlock (`takeWithheld`).
        if clientCount > 0 && !withholding { onNewIcon?(bundleID, png) } else if withholding { withheldIcons.append(bundleID) }
    }

    // MARK: Installed apps

    /// Once at startup. Listing ~100 bundles and rendering their icons takes 150–300 ms, which on
    /// the main actor would hold up startup and the first window refresh, so all of it runs on a
    /// utility-priority thread and only the results hop back.
    private func scanInstalledApps() {
        Task.detached(priority: .utility) { [weak self] in
            let t0 = Date()
            let found = WindowCatalog.findInstalledApps()
            let t1 = Date()
            let rendered: [(bundleID: String, png: Data)] = found.compactMap { app in
                WindowCatalog.png(NSWorkspace.shared.icon(forFile: app.path), size: 64).map { (app.bundleID, $0) }
            }
            let t2 = Date()
            print("installed apps: \(found.count) in \(Int(t1.timeIntervalSince(t0) * 1000)) ms"
                  + " (+ icons \(Int(t2.timeIntervalSince(t1) * 1000)) ms, off the main thread)")
            await self?.installedAppsFound(found.map { AppInfo(name: $0.name, bundleID: $0.bundleID) }, icons: rendered)
        }
    }

    private func installedAppsFound(_ apps: [AppInfo], icons rendered: [(bundleID: String, png: Data)]) {
        installedApps = apps
        // A running app's icon, announced by a window refresh meanwhile, wins over the file icon.
        for (id, png) in rendered where !announcedIcons.contains(id) { announce(bundleID: id, png: png) }
        if clientCount > 0 && !withholding { onInstalledAppsReady?(apps) } else if withholding { appsWithheld = true }   // the unlock sends them
    }

    /// Sorted by display name, first bundle ID wins. Thread-safe (FileManager + Bundle only).
    nonisolated private static func findInstalledApps() -> [(name: String, bundleID: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Both Utilities folders are read twice, as a folder inside /Applications or /System/Applications
        // and as given: harmless, since the first bundle with an ID wins and the second read finds the same ones.
        return InstalledApps.find(in: ["/Applications", "/Applications/Utilities", "/System/Applications",
                                       "/System/Applications/Utilities", home.appendingPathComponent("Applications").path])
    }

    // MARK: Image encoding (thread-safe)

    nonisolated private static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Draws into its own bitmap context, so it is safe off the main thread.
    nonisolated private static func png(_ image: NSImage, size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
