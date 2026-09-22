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
    let fps: Int
    let scale: CGFloat
    let bitrate: Int
    let prioritizeSpeed: Bool

    let server: StreamServer
    let catalog = WindowCatalog()
    let capture = WindowCapture()
    let injector = InputInjector()
    private var encoder: HEVCEncoder? { didSet { encoderBox.current = encoder } }
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
    private(set) var active: StreamSource = .none
    private var rectCache: (id: CGWindowID, rect: CGRect, at: CFAbsoluteTime)?
    private var pendingLaunch: String?
    private var switching = false
    private let macName = Host.current().localizedName ?? "Mac"

    init(fps: Int, scale: CGFloat, bitrate: Int, prioritizeSpeed: Bool) throws {
        self.fps = fps; self.scale = scale; self.bitrate = bitrate; self.prioritizeSpeed = prioritizeSpeed
        server = try StreamServer()

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
        server.onMessage = { [weak self] message, _ in
            Task { @MainActor in await self?.handle(message) }
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
        InputInjector.ensureAccessibility()   // prompts once; input is dropped silently without it
        catalog.start()
        server.start()
        await catalog.refreshWindows()
        if let match = preselect?.lowercased(),
           let w = catalog.infos.first(where: { $0.appName.lowercased().contains(match) || $0.title.lowercased().contains(match) }) {
            await select(.window(w.id))
        }
    }

    // MARK: Client messages

    private func handle(_ message: StreamMessage) async {
        switch message.kind {
        case .selectSource:
            guard let source = Wire.decode(StreamSource.self, from: message.payload) else { return }
            await select(source)
        case .launchApp:
            guard let req = Wire.decode(LaunchApp.self, from: message.payload),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: req.bundleID) else { return }
            pendingLaunch = req.bundleID
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { print("Launch failed: \(error.localizedDescription)") }
            }
        case .input:
            guard let event = Wire.decode(InputEvent.self, from: message.payload),
                  let rect = currentSourceRect() else { return }
            injector.apply(event, in: rect)
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

    // MARK: Source switching

    func select(_ source: StreamSource) async {
        guard !switching else { return }
        switching = true
        defer { switching = false }

        await capture.stop()
        rectCache = nil
        encoder = nil                  // deinit invalidates the VT session
        server.resetForNewStream()          // every client waits for the next parameter sets + keyframe

        let filter: SCContentFilter
        let width: Int, height: Int
        var describe = ""
        switch source {
        case .none:
            active = .none
            broadcastList()
            return
        case .window(let id):
            guard let w = catalog.window(id: id) else { active = .none; broadcastList(); return }
            filter = SCContentFilter(desktopIndependentWindow: w)
            width = evenPixels(w.frame.width * scale); height = evenPixels(w.frame.height * scale)
            describe = "\(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "")"
            // Covered windows stop repainting on macOS, so bring the app forward as the client picks it.
            // NSRunningApplication.activate is a no-op from a non-frontmost process since macOS 14;
            // asking Launch Services to open the already-running app with activation does work.
            if let url = w.owningApplication.flatMap({ NSRunningApplication(processIdentifier: $0.processID)?.bundleURL }) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
            }
        case .desktop:
            guard let d = catalog.display else { active = .none; broadcastList(); return }
            filter = SCContentFilter(display: d, excludingWindows: [])
            width = evenPixels(CGFloat(d.width) * scale); height = evenPixels(CGFloat(d.height) * scale)
            describe = "the whole desktop"
        }

        do {
            let enc = try HEVCEncoder(width: width, height: height, fps: fps, bitrate: bitrate, prioritizeSpeed: prioritizeSpeed)
            let server = self.server
            enc.onEncoded = { data, isKey, parameterSets in
                let now = Date().timeIntervalSince1970
                if let ps = parameterSets {
                    server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: ps.encoded()))
                }
                server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: isKey, payload: data))
            }
            capture.onFrame = { pixelBuffer, pts in enc.encode(pixelBuffer, pts: pts) }
            try await capture.start(filter: filter, width: width, height: height, fps: fps)
            encoder = enc
            active = source
            print("Streaming \(describe) at \(width)×\(height), \(fps) fps, \(bitrate / 1_000_000) Mbps")
        } catch {
            print("Could not start streaming \(describe): \(error)")
            active = .none
        }
        broadcastList()
    }

    private func windowsChanged(_ infos: [WindowInfo]) async {
        if let pending = pendingLaunch, let w = infos.first(where: { $0.bundleID == pending }) {
            pendingLaunch = nil
            await select(.window(w.id))
            return
        }
        if case .window(let id) = active {
            guard let w = infos.first(where: { $0.id == id }) else { await select(.none); return }
            // The encoder is fixed to one size, so a resized window means a fresh pipeline.
            if let scw = catalog.window(id: id),
               evenPixels(scw.frame.width * scale) != encoderWidth || evenPixels(scw.frame.height * scale) != encoderHeight {
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
    }
}
