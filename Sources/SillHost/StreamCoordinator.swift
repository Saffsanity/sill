import Foundation
import AppKit
import Network
import ScreenCaptureKit
import StreamProtocol

/// Owns the pipeline for the life of the process and points it at whatever source the client
/// picks. Threading: this class is main-actor; frames flow capture queue → VT thread → network
/// queue without touching it. Network callbacks hop here with Task { @MainActor }.
@MainActor
final class StreamCoordinator {
    /// Ceiling for the stream rate (main.swift knob). Each device asks for its own panel's rate
    /// through the viewport: 120 on ProMotion, 60 elsewhere, 60 while Low Power Mode caps it.
    let maxFPS: Int
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
    /// The bitrate knob is per 60 fps; a faster stream gets proportionally more so each frame
    /// keeps its share of bits.
    private var streamBitrate: Int { bitrate * fps / 60 }
    let scale: CGFloat
    let bitrate: Int
    let prioritizeSpeed: Bool

    let server: StreamServer
    let catalog = WindowCatalog()
    let capture = WindowCapture()
    /// `--synthetic`: the Desktop source streams a test pattern instead of the screen.
    let synthetic: Bool
    let syntheticCapture = SyntheticCapture()
    let injector = InputInjector()
    let sizer = WindowSizer()
    /// `--virtual-display`: a picked window streams from its own HiDPI display (see VirtualStage).
    /// Every branch this adds is behind this flag; without it the coordinator behaves as before.
    let virtualDisplay: Bool
    let stage: VirtualStage
    /// Set by the signal handler: a select in flight when Ctrl-C lands must not stage anything new.
    private var shuttingDown = false
    private var stageLosses = 0
    private var encoder: HEVCEncoder? { didSet { encoderBox.current = encoder } }
    /// Hardware HEVC normally. When a session stops returning frames (the Mac's hardware encoder
    /// wedged system-wide on 2026-09-22 and stayed that way until a reboot), the source restarts
    /// on the software encoder at half the capture scale, slow but alive. Back to hardware on the
    /// next host launch.
    private var useSoftwareEncoder = false
    private var softwareRestarts = 0
    private var lastSoftwareHangAt: CFAbsoluteTime = 0
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
    private(set) var active: StreamSource = .none {
        didSet {
            if case .window(let id) = active { catalog.activeWindowID = id } else { catalog.activeWindowID = nil }
            server.setStreaming(active != .none)   // link keepalive ticks while a source is live
            cursorShapes.running = active != .none
        }
    }
    private var rectCache: (id: CGWindowID, rect: CGRect, at: CFAbsoluteTime)?
    private var pendingLaunch: String?
    private var switching = false
    /// The client's last stream panel size and text scale. One stream, so with several clients
    /// the last one to report wins.
    private var viewport: Viewport?
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

    init(maxFPS: Int, scale: CGFloat, bitrate: Int, prioritizeSpeed: Bool, synthetic: Bool = false, virtualDisplay: Bool = false) throws {
        self.maxFPS = maxFPS; self.scale = scale; self.bitrate = bitrate; self.prioritizeSpeed = prioritizeSpeed
        self.synthetic = synthetic
        self.virtualDisplay = virtualDisplay
        server = try StreamServer(advertise: !synthetic)   // the test pattern is for test clients, not devices
        stage = VirtualStage(sizer: sizer, catalog: catalog)
        catalog.preferMainDisplay = virtualDisplay   // the Desktop source must never capture the virtual display
        stage.onLost = { [weak self] in Task { @MainActor in await self?.stageLost() } }

        server.onClientConnected = { [weak self] connection in
            Task { @MainActor in
                guard let self else { return }
                // Catalog first: the client's UI needs it even if the keyframe is slow to come.
                self.catalog.thumbnailsWanted = true
                self.sendCatalog(to: connection)
                self.encoder?.requestKeyframe()
            }
        }
        server.onKeyframeNeeded = { [weak self] in
            // Network queue → encoder lock; requestKeyframe re-encodes the last frame right away.
            self?.encoderBox.current?.requestKeyframe()
        }
        server.onClientDisconnected = { [weak self] connection in
            Task { @MainActor in
                guard let self else { return }
                self.clientFPS[ObjectIdentifier(connection)] = nil
                // A 120 Hz device left a 60 Hz one behind: come down to its rate.
                if self.active != .none, self.catalog.clientCount > 1, self.effectiveFPS != self.fps { await self.select(self.active) }
            }
        }
        server.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                guard let self else { return }
                self.catalog.clientCount = count          // the catalog idles itself at 0
                // Nobody is watching: stop capturing and encoding. The next client picks afresh.
                if count == 0 { self.viewport = nil; self.clientFPS = [:] }   // the next device starts from scratch
                if count > 0 {
                    self.deselectWhenSettled = false
                } else if self.switching {
                    self.deselectWhenSettled = true     // `select` would refuse it now; its tail applies it
                } else if self.active != .none {
                    await self.select(.none)
                }
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
        server.onMessage = { [weak self] message, connection in
            Task { @MainActor in await self?.handle(message, from: connection) }
        }
        catalog.onWindowsChanged = { [weak self] infos in
            Task { @MainActor in await self?.windowsChanged(infos) }
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
            Task { @MainActor in await self?.select(.none) }
        }
    }

    /// `preselect` is the optional command-line match; without it nothing streams until a client picks.
    func start(preselect: String?) async {
        if !synthetic { InputInjector.ensureAccessibility() }   // prompts once; input is dropped silently without it
        // One small frame through the hardware encoder before anything streams. If the Mac's
        // hardware encoder is wedged (it stays that way until a reboot) start on the software
        // encoder now, instead of hanging the first stream for 1.5 s and restarting it.
        let hardwareResponds = await Task.detached(priority: .userInitiated) { EncoderProbe.hardwareResponds() }.value
        if !hardwareResponds {
            useSoftwareEncoder = true
            Stats.shared.bump("enc.fallback")
            print("The Mac's hardware video encoder is not responding; streaming with the software encoder at half scale. A reboot brings it back.")
        }
        if virtualDisplay {
            // Decide once at launch whether the private API is there; a picked window falls back to
            // plain window capture (with a log line) when it is not.
            let problems = VirtualDisplay.checkPrivateAPI()
            if problems.isEmpty {
                print("Virtual display: private CGVirtualDisplay API present (\(VirtualDisplay.privateAPISurface.count) selectors); a picked window streams from its own HiDPI display.")
            } else {
                stage.disabledReason = problems.joined(separator: "; ")
                print("Virtual display unavailable: \(stage.disabledReason!). Streaming real windows as before.")
            }
        }
        catalog.start()
        server.start()
        await catalog.refreshWindows()
        if let match = preselect?.lowercased(),
           let w = catalog.infos.first(where: { $0.appName.lowercased().contains(match) || $0.title.lowercased().contains(match) }) {
            await select(.window(w.id), bringForward: true)   // a pick, made on the command line
        }
    }

    // MARK: Client messages

    private func handle(_ message: StreamMessage, from connection: NWConnection) async {
        switch message.kind {
        case .selectSource:
            guard let source = Wire.decode(StreamSource.self, from: message.payload) else { return }
            // A pick from the device's switcher: the device never selects a window by itself (its
            // automatic requests are for the Desktop only).
            await select(source, bringForward: true)
        case .windowCommand:
            // The bar's long-press menu: the window's own traffic lights, pressed through
            // Accessibility. The staged window's element is already matched; others are looked up.
            guard let cmd = Wire.decode(WindowCommand.self, from: message.payload) else { return }
            let done: Bool
            if virtualDisplay, let p = stage.placement, p.windowID == cmd.id {
                done = WindowSizer.perform(cmd.action, element: p.element)
            } else if let w = catalog.window(id: cmd.id) {
                done = sizer.perform(cmd.action, on: w)
            } else {
                done = false
            }
            print("Window \(cmd.id) \(cmd.action.rawValue): \(done ? "done" : "refused")")
            Stats.shared.bump("win.\(cmd.action.rawValue)")
            await catalog.refreshWindows()      // show the result now, not at the next poll
        case .launchApp:
            guard let req = Wire.decode(LaunchApp.self, from: message.payload),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: req.bundleID) else { return }
            pendingLaunch = req.bundleID
            let config = NSWorkspace.OpenConfiguration()
            // The launch itself takes no focus on the Mac. Its first window is then picked for the
            // device (`windowsChanged`), which in regular mode brings it forward like any pick.
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { print("Launch failed: \(error.localizedDescription)") }
            }
        case .input:
            guard let event = Wire.decode(InputEvent.self, from: message.payload),
                  let rect = currentSourceRect() else { return }
            raiseIfInteracting(event)
            deliver(event, in: rect)
        case .viewport:
            guard let v = Wire.decode(Viewport.self, from: message.payload) else { return }
            viewport = v
            clientFPS[ObjectIdentifier(connection)] = v.fps ?? 60
            if switching { viewportArrivedWhileSwitching = true; return }
            await applyViewportToActiveWindow()
        default:
            break
        }
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
            return catalog.display?.frame
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

    // MARK: Fitting the window to the client

    /// Resizes the streamed window to the client's panel at its text scale, if one is set and the
    /// window is not already there. Returns the size the window actually took, or nil if nothing
    /// changed. Mac points throughout: the panel in device points divided by the scale (device
    /// points per Mac point). Scale nil means leave the window alone, and nothing ever restores
    /// an earlier size on its own.
    private func fitToViewport(_ window: SCWindow) -> CGSize? {
        guard let v = viewport, let textScale = v.scale, textScale > 0, v.width > 0, v.height > 0 else { return nil }
        let target = CGSize(width: (v.width / textScale).rounded(), height: (v.height / textScale).rounded())
        let current = Self.liveBounds(of: window.windowID)?.size ?? window.frame.size
        if abs(current.width - target.width) <= 2, abs(current.height - target.height) <= 2 { return nil }
        guard let actual = sizer.resize(window: window, to: target) else { return nil }
        // Asked again for a size the app already refused (its minimum): nothing moved.
        guard abs(actual.width - current.width) >= 1 || abs(actual.height - current.height) >= 1 else { return nil }
        Stats.shared.bump("win.resized")
        print("Resized \(window.owningApplication?.applicationName ?? "?") to \(Int(actual.width))×\(Int(actual.height)) pt "
              + "(asked \(Int(target.width))×\(Int(target.height)) for a \(Int(v.width))×\(Int(v.height)) panel at \(textScale)×)")
        return actual
    }

    /// A new viewport while a window streams. The encoder is fixed to the old size, but the
    /// catalog's resize check (`windowsChanged`) already restarts the pipeline when the window's
    /// size changes; refreshing now just saves waiting up to two seconds for its next poll.
    /// The desktop and nothing-streaming ignore viewports.
    private func applyViewportToActiveWindow() async {
        // A different rate (a ProMotion device joined, Low Power Mode toggled) needs a new capture
        // interval and encoder session: one restart, whatever the source.
        if active != .none, effectiveFPS != fps { await select(active); return }
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
        guard case .window(let id) = active, let w = catalog.window(id: id) else { return }
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

    /// Streams `source` in place of whatever streams now. Also how the host restarts the current
    /// source (a resize, a rate change, the encoder fallback, a lost virtual display).
    /// `bringForward` marks a pick instead: the device's switcher, the command line, an app
    /// launched from the device. In regular mode a picked window comes forward on the Mac, and a
    /// pick that falls back from the virtual display to the real window counts as regular mode;
    /// restarts leave Mac focus where it is, and so does staging a window on the virtual display.
    func select(_ source: StreamSource, bringForward: Bool = false) async {
        guard !switching, !shuttingDown else { return }
        switching = true
        defer {
            switching = false
            // Requests that arrived mid-switch, applied now that `switching` is clear again (every
            // return path, including the early ones). A last client leaving wins over a viewport:
            // there is nobody left to fit the window to.
            if deselectWhenSettled {
                deselectWhenSettled = false
                if catalog.clientCount == 0, active != .none {
                    viewportArrivedWhileSwitching = false
                    Task { @MainActor in await self.select(.none) }
                }
            }
            if viewportArrivedWhileSwitching {
                viewportArrivedWhileSwitching = false
                Task { @MainActor in await self.applyViewportToActiveWindow() }
            }
        }

        await capture.stop()
        await syntheticCapture.stop()
        capture.onFrame = nil; syntheticCapture.onFrame = nil   // both queues drained: let the old encoder go
        rectCache = nil
        heldInput = []; holdUntil = 0          // input held for the old source must not replay into the new one
        encoder = nil                  // deinit invalidates the VT session
        server.resetForNewStream()          // every client waits for the next parameter sets + keyframe
        fps = effectiveFPS             // the devices' panel rate (highest), or 60 before any has said

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
                await stage.leaveFullScreenIfNeeded()
                stage.release()
            }
        }

        var filter: SCContentFilter?     // nil only for the synthetic test pattern
        var sourceRect: CGRect? = nil    // set only when the window streams from the virtual display
        var picked: SCWindow?            // the resolved window, for the fallback after a failed start
        let width: Int, height: Int
        var describe = ""
        switch source {
        case .none:
            active = .none
            broadcastList()
            return
        case .window(let id):
            // On the virtual display the window may have left the on-screen list; look it up fully.
            var found = catalog.window(id: id)
            if found == nil, virtualDisplay { found = await catalog.resolveWindow(id: id) }
            guard let w = found else {
                if virtualDisplay { stage.release() }
                active = .none; broadcastList(); return
            }
            print("Selecting window \(w.windowID) \(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "") frame \(w.frame) onScreen \(w.isOnScreen) active \(w.isActive)")
            picked = w
            var size = w.frame.size
            if virtualDisplay, stage.disabledReason == nil {
                let want = wantedStage(for: w)
                do {
                    let prepared = try await stage.prepare(window: w, wanted: want.size, envelope: want.envelope, captureScale: captureScale, refreshHz: fps)
                    guard !shuttingDown else { stage.release(); active = .none; broadcastList(); return }
                    filter = prepared.filter
                    sourceRect = prepared.sourceRect
                    size = prepared.outputSize ?? prepared.sourceRect.size
                    describe = prepared.describe + (useSoftwareEncoder ? " (software encoder)" : "")
                } catch {
                    print("Virtual display fallback for \(w.owningApplication?.applicationName ?? "?"): \(error). Streaming the real window instead.")
                    Stats.shared.bump("vd.fallback")
                    stage.release()
                }
            }
            if sourceRect == nil {
                // Today's path: capture the window where it is.
                filter = SCContentFilter(desktopIndependentWindow: w)
                // Regular mode raises the picked window (2026-09-23, Noah: the Mac must show the
                // picked window). A covered window stops repainting, so it would stream frozen, and
                // keys go to the active app's key window. Done before capture starts, so the first
                // frames already show it uncovered. The virtual display's fallback lands here too.
                if bringForward, !shuttingDown { activateAndRaise(window: w) }
                // Fit the window to the client's panel before capture starts, so the stream comes up
                // at the new size instead of restarting once the catalog notices. `w` is a snapshot
                // with the old frame; the window server has the new one.
                if let resized = fitToViewport(w) { size = Self.liveBounds(of: id)?.size ?? resized }
                describe = "\(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "")\(useSoftwareEncoder ? " (software encoder)" : "")"
            }
            width = evenPixels(size.width * captureScale); height = evenPixels(size.height * captureScale)
            // Staged on the virtual display, nothing is activated or raised on select: the window
            // cannot be covered there, and the AX moves that put it there touch no focus.
        case .desktop:
            if synthetic {
                // A 1512×949-point test pattern: the same size as a typical streamed window, so the
                // encoder and the fallback see realistic load without Screen Recording.
                width = evenPixels(1512 * captureScale); height = evenPixels(949 * captureScale)
                describe = "a synthetic test pattern\(useSoftwareEncoder ? " (software encoder)" : "")"
            } else {
                guard let d = catalog.display else { active = .none; broadcastList(); return }
                filter = SCContentFilter(display: d, excludingWindows: [])
                width = evenPixels(CGFloat(d.width) * captureScale); height = evenPixels(CGFloat(d.height) * captureScale)
                describe = "the whole desktop\(useSoftwareEncoder ? " (software encoder)" : "")"
            }
        }

        do {
            try await startPipeline(source: source, filter: filter, sourceRect: sourceRect, width: width, height: height, describe: describe)
        } catch {
            // `picked`, not a catalog lookup: a staged window may have left the on-screen list.
            if virtualDisplay, stage.isStaged, let w = picked {
                // The display filter failed to start: send the window home and stream it there.
                print("Capture on the virtual display failed: \(error); retrying with the real window.")
                stage.release()
                if bringForward, !shuttingDown { activateAndRaise(window: w) }   // regular mode now: a pick comes forward
                let fallback = "\(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "")\(useSoftwareEncoder ? " (software encoder)" : "")"
                do {
                    try await startPipeline(source: source, filter: SCContentFilter(desktopIndependentWindow: w), sourceRect: nil,
                                            width: evenPixels(w.frame.width * captureScale), height: evenPixels(w.frame.height * captureScale),
                                            describe: fallback)
                } catch {
                    print("Could not start streaming \(fallback): \(error)")
                    active = .none
                }
            } else {
                print("Could not start streaming \(describe): \(error)")
                if virtualDisplay { stage.release() }   // nothing streams: never leave a window on the virtual display
                active = .none
            }
        }
        broadcastList()
        // Mid-switch requests (a viewport, the last client leaving) are applied by the defer.
    }

    /// Encoder, then capture (ScreenCaptureKit for a filter, the test pattern without one), then
    /// `active`. Throws with `active` untouched if either refuses; the caller decides what to do.
    private func startPipeline(source: StreamSource, filter: SCContentFilter?, sourceRect: CGRect?, width: Int, height: Int, describe: String) async throws {
        let enc = try HEVCEncoder(width: width, height: height, fps: fps, bitrate: streamBitrate, prioritizeSpeed: prioritizeSpeed,
                                  software: useSoftwareEncoder)
        enc.onHung = { [weak self, weak enc] in
            Task { @MainActor in
                guard let enc else { return }
                await self?.encoderHung(enc)
            }
        }
        let server = self.server
        enc.onEncoded = { data, isKey, parameterSets in
            let now = Date().timeIntervalSince1970
            if let ps = parameterSets {
                server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: ps.encoded()))
            }
            server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: isKey, payload: data))
        }
        if let filter {
            capture.onFrame = { pixelBuffer, pts in enc.encode(pixelBuffer, pts: pts) }
            try await capture.start(filter: filter, width: width, height: height, fps: fps, showsCursor: false, sourceRect: sourceRect)
        } else {
            syntheticCapture.onFrame = { pixelBuffer, pts in enc.encode(pixelBuffer, pts: pts) }
            syntheticCapture.start(width: width, height: height, fps: fps)
        }
        encoder = enc
        active = source
        print("Streaming \(describe) at \(width)×\(height), \(fps) fps, \(streamBitrate / 1_000_000) Mbps")
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
    /// Consecutive catalog polls the staged full-screen window has been missing from every list.
    private var missingPolls = 0
    private var lastRaiseCheck: CFAbsoluteTime = 0
    private var lastActivationAt: CFAbsoluteTime = 0
    private var heldInput: [(InputEvent, CGRect)] = []
    private var holdUntil: CFAbsoluteTime = 0
    /// How long held input waits for the app to become frontmost before it is replayed anyway.
    private static let activationTimeout: TimeInterval = 0.6

    private func deliver(_ event: InputEvent, in rect: CGRect) {
        // Queue while holding, and while anything is still queued, so order is never inverted.
        if !heldInput.isEmpty || CFAbsoluteTimeGetCurrent() < holdUntil { heldInput.append((event, rect)); return }
        logClick(event, in: rect)
        injector.apply(event, in: rect)
    }

    private func releaseHeldInput() {
        holdUntil = 0
        let held = heldInput
        heldInput = []
        for (event, rect) in held { logClick(event, in: rect); injector.apply(event, in: rect) }
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
        // under --virtual-display. Otherwise the active app is read off the window list: the owner
        // of the topmost layer-0 window. Covered = another app's window under the click point.
        let point = injectorProbePoint(event)
        let cover = point.flatMap { Self.topmostWindow(at: $0) }
        let covered = cover != nil && cover?.id != id            // any other window over the spot, same app or not
        // On the virtual display a cover is a stranger (a window left there by an earlier run):
        // move it off, then the click lands.
        if staged, covered { stage.evictForeignWindows() }
        let notActive = needsFocus && Self.activePID(trustAppKit: virtualDisplay) != pid
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
                let active = Self.activePID(trustAppKit: self.virtualDisplay) == pid
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
        let p = CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        let top = Self.topmostWindow(at: p)
        let verdict = top?.id == id ? "the streamed window" : "window \(top.map { String($0.id) } ?? "none"), not the streamed \(id)"
        print("Click at (\(Int(p.x)),\(Int(p.y))) in (\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width))×\(Int(rect.height))) → \(verdict)")
    }

    /// The screen point an interaction lands on (for the topmost-window check); nil for keys.
    private func injectorProbePoint(_ event: InputEvent) -> CGPoint? {
        guard let rect = currentSourceRect() else { return nil }
        switch event {
        case .pointer(_, let x, let y), .scroll(let x, let y, _, _), .scrollGesture(_, let x, let y):
            return CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
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

    /// The active app's pid. AppKit's answer only when this process runs the AppKit loop
    /// (--virtual-display); otherwise the owner of the frontmost normal window, which is what the
    /// window server considers active for input.
    private static func activePID(trustAppKit: Bool) -> pid_t? {
        if trustAppKit, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { return pid }
        return topmostWindow(at: nil)?.pid
    }

    /// Retina normally; points when the software encoder is carrying the stream.
    private var captureScale: CGFloat { useSoftwareEncoder ? min(scale, 1.0) : scale }

    // MARK: Virtual display lifecycle

    /// The window server removed the virtual display (sleep/wake, display arbitration). The stage
    /// has already put the window back; stage it again, or after repeated losses give up on the
    /// virtual display for this run and stream the real window.
    private func stageLost() async {
        stageLosses += 1
        print("The system removed the virtual display; the window is back on a real display.")
        if stageLosses > 2 { stage.disabledReason = "the system removed the virtual display \(stageLosses) times" }
        if case .window = active { await select(active) }
    }

    /// Called by HostShutdown on the main queue just before `exit`: window home, display gone.
    /// Capture and encoder need no stop; the process is about to end.
    func shutdownForExit() {
        shuttingDown = true
        stage.release()
    }

    /// An encoder's watchdog fired. A hardware hang is remembered whichever encoder reports it,
    /// but only the encoder carrying the stream may restart it: a replaced encoder whose frame is
    /// still stuck inside VideoToolbox times out later, and must not disturb its successor. First
    /// hang: switch to the software encoder and restart the source. If even that dies repeatedly,
    /// stop streaming rather than loop.
    private func encoderHung(_ enc: HEVCEncoder, attempt: Int = 0) async {
        if !enc.software, !useSoftwareEncoder {
            useSoftwareEncoder = true
            Stats.shared.bump("enc.fallback")
            print("Hardware HEVC encoder is not returning frames; switching to the software encoder at half scale. A reboot brings the hardware encoder back.")
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

    private func windowsChanged(_ infos: [WindowInfo]) async {
        if let pending = pendingLaunch, let w = infos.first(where: { $0.bundleID == pending }) {
            pendingLaunch = nil
            await select(.window(w.id), bringForward: true)   // launched from the device to use it: a pick
            return
        }
        if case .window(let id) = active {
            guard let w = infos.first(where: { $0.id == id }) else {
                // Alive on the virtual display even if the on-screen list dropped it.
                if virtualDisplay, stage.isStaged, Self.liveBounds(of: id) != nil { broadcastList(); return }
                // Leaving full screen, a window is off every list for a second or two. Give it
                // three polls before calling it closed, then restart so the stage re-places it.
                if virtualDisplay, stage.isStaged, stage.fullScreen {
                    missingPolls += 1
                    if missingPolls <= 3 { broadcastList(); return }
                    missingPolls = 0
                }
                await select(.none); return
            }
            missingPolls = 0
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
            // The encoder is fixed to one size, so a resized window means a fresh pipeline.
            if let scw = catalog.window(id: id),
               evenPixels(scw.frame.width * captureScale) != encoderWidth || evenPixels(scw.frame.height * captureScale) != encoderHeight {
                _ = w
                await select(active)
                return
            }
        }
        broadcastList()
    }

    private var encoderWidth: Int { encoder?.width ?? 0 }
    private var encoderHeight: Int { encoder?.height ?? 0 }

    // MARK: Catalog to clients

    private func listMessage() -> StreamMessage {
        StreamMessage(kind: .windowList, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                      payload: Wire.encode(WindowList(macName: macName, windows: catalog.infos, active: active)))
    }

    private func broadcastList() { server.broadcast(listMessage()) }

    private func sendCatalog(to connection: NWConnection) {
        let now = Date().timeIntervalSince1970
        print("Catalog → \(connection.endpoint): \(catalog.infos.count) windows, \(catalog.allIcons.count) icons, \(catalog.installedApps.count) apps")
        server.send(listMessage(), to: connection)
        for (id, png) in catalog.allIcons {
            server.send(StreamMessage(kind: .appIcon, timestamp: now, isKeyframe: false,
                                      payload: ImageBlob.encodeIcon(bundleID: id, png: png)), to: connection)
        }
        server.send(StreamMessage(kind: .appList, timestamp: now, isKeyframe: false,
                                  payload: Wire.encode(catalog.installedApps)), to: connection)
        if let shape = cursorShapes.current {
            server.send(StreamMessage(kind: .cursorShape, timestamp: now, isKeyframe: false, payload: shape), to: connection)
        }
    }
}
