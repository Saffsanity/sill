import Foundation
import Network
import ScreenCaptureKit
import StreamProtocol

/// One iPad window's own capture and encoder. The shared stream (`StreamCoordinator.select`) is
/// untouched: a connection asks for this by sending `Hello.lane`, and only that connection is
/// sent this pipeline's frames. With Virtual Display on, the window sits on its own display, so
/// another window covering it on the main screen does not freeze the picture.
@MainActor
final class PrivateLane {
    struct Knobs {
        var fps: Int
        var bitrate: Int
        var captureScale: CGFloat
        var software: Bool
        var virtualDisplay: Bool
        var prioritizeSpeed: Bool
    }

    let connection: NWConnection
    let server: StreamServer
    let serial: UInt32
    weak var owner: StreamCoordinator?
    private let catalog: WindowCatalog
    private let capture = WindowCapture()
    private let stage: VirtualStage
    private(set) var source: StreamSource = .none
    private(set) var viewport: Viewport?
    /// Where this window's input lands, in CG global points. Nil-sized until a pipeline is up.
    private(set) var aim: CGRect = .zero
    var fits = WindowRestore.Ledger<WindowSizer.Placement>()
    private var encoder: HEVCEncoder?
    private(set) var switching = false
    private var generation = 0

    var askedFPS: Int { viewport?.fps ?? 60 }

    init(connection: NWConnection, server: StreamServer, sizer: WindowSizer, catalog: WindowCatalog, serial: UInt32) {
        self.connection = connection
        self.server = server
        self.catalog = catalog
        self.serial = serial
        stage = VirtualStage(sizer: sizer, catalog: catalog)
        stage.primary = false
        stage.displayName = "Sill \(serial)"
        stage.displaySerial = serial
    }

    func setViewport(_ v: Viewport) -> Bool {
        let old = viewport
        viewport = v
        guard source != .none else { return false }
        return old?.width != v.width || old?.height != v.height || old?.scale != v.scale || old?.fps != v.fps
    }

    func select(_ next: StreamSource, knobs: Knobs, bringForward: Bool) async {
        guard !switching else { return }
        switching = true
        defer { switching = false }
        let same = source == next
        await stopPipeline()
        if !same {
            let book = fits
            fits = WindowRestore.Ledger()
            if stage.isStaged { stage.release() }
            else { owner?.restorePrivate(book) }
        } else if stage.isStaged, !knobs.virtualDisplay {
            stage.release()
        }
        source = next
        aim = .zero
        guard case .none = next else {
            await start(next, knobs: knobs, bringForward: bringForward)
            return
        }
    }

    /// The window closed under us, or the connection is gone.
    func stop() async {
        let book = fits
        fits = WindowRestore.Ledger()
        await stopPipeline()
        if stage.isStaged { stage.release() }
        else { owner?.restorePrivate(book) }
        source = .none
        aim = .zero
    }

    func owns(_ enc: HEVCEncoder) -> Bool { encoder === enc }

    private func stopPipeline() async {
        generation += 1
        capture.onStopped = nil
        capture.onFrame = nil
        await capture.stop()
        encoder = nil
    }

    private func start(_ next: StreamSource, knobs: Knobs, bringForward: Bool) async {
        let gen = generation
        var filter: SCContentFilter?
        var sourceRect: CGRect?
        var width = 2
        var height = 2
        switch next {
        case .none:
            return
        case .desktop:
            guard let d = catalog.display else {
                print("Own stream: no display to capture.")
                source = .none
                return
            }
            if let own = catalog.ownApplication {
                filter = SCContentFilter(display: d, excludingApplications: [own], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: d, excludingWindows: [])
            }
            width = max(2, evenPixels(CGFloat(d.width) * knobs.captureScale))
            height = max(2, evenPixels(CGFloat(d.height) * knobs.captureScale))
            aim = d.frame
            print("Own stream: the Desktop.")
        case .window(let id):
            guard let w = catalog.window(id: id) else {
                print("Own stream: window \(id) is not in the list.")
                source = .none
                return
            }
            var size = w.frame.size
            var book = fits
            let fitted = owner?.fitWindow(w, using: viewport, book: &book)
            fits = book
            if fitted != nil {
                await catalog.refreshWindows()
                size = StreamCoordinator.liveBounds(of: id)?.size ?? fitted ?? size
            }
            if knobs.virtualDisplay, stage.disabledReason == nil, let owner {
                let want = VirtualStage.windowSize(for: viewport, own: size)
                let envelope = VirtualStage.envelope(for: viewport, windowSize: want)
                let home = owner.homeForStage(id, book: fits)
                do {
                    let prepared = try await stage.prepare(window: w, wanted: want, envelope: envelope,
                                                           captureScale: knobs.captureScale, refreshHz: knobs.fps, home: home)
                    _ = fits.take(id)
                    filter = prepared.filter
                    sourceRect = prepared.sourceRect
                    if let out = prepared.outputSize {
                        width = max(2, evenPixels(out.width))
                        height = max(2, evenPixels(out.height))
                    } else {
                        width = max(2, evenPixels(prepared.sourceRect.width * knobs.captureScale))
                        height = max(2, evenPixels(prepared.sourceRect.height * knobs.captureScale))
                    }
                    if let onScreen = stage.captureRectOnScreen { aim = onScreen }
                    print("Own stream: \(prepared.describe)")
                } catch {
                    print("Own stream: virtual display failed (\(error)). Streaming the real window.")
                    stage.release()
                }
            }
            if filter == nil {
                filter = SCContentFilter(desktopIndependentWindow: w)
                let live = StreamCoordinator.liveBounds(of: id) ?? w.frame
                aim = live
                width = max(2, evenPixels(live.width * knobs.captureScale))
                height = max(2, evenPixels(live.height * knobs.captureScale))
                if bringForward { owner?.activateAndRaise(window: w) }
                let title = w.owningApplication?.applicationName ?? "window"
                print("Own stream: \(title) on its real window. Turn on Virtual Display to keep the picture when another window covers it.")
            }
        }
        guard let filter, generation == gen else { return }
        do {
            let enc = try HEVCEncoder(width: width, height: height, fps: knobs.fps, bitrate: knobs.bitrate,
                                      prioritizeSpeed: knobs.prioritizeSpeed, software: knobs.software)
            let server = self.server
            let connection = self.connection
            enc.onEncoded = { data, isKey, parameterSets in
                let now = Date().timeIntervalSince1970
                if let ps = parameterSets {
                    server.send(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: ps.encoded()), to: connection)
                }
                server.send(StreamMessage(kind: .frame, timestamp: now, isKeyframe: isKey, payload: data), to: connection, isFrame: true)
            }
            enc.onHung = { [weak self] in
                Task { @MainActor in
                    guard let self, let enc = self.encoder else { return }
                    await self.owner?.encoderHung(enc)
                }
            }
            capture.onFrame = { pixelBuffer, pts in enc.encode(pixelBuffer, pts: pts) }
            capture.onStopped = { [weak self] error in
                Task { @MainActor in
                    guard let self, self.generation == gen else { return }
                    print("Own stream stopped: \(error)")
                    self.source = .none
                    self.aim = .zero
                    self.owner?.privateWindowClosed()
                }
            }
            encoder = enc
            try await capture.start(filter: filter, width: width, height: height, fps: knobs.fps, showsCursor: false, sourceRect: sourceRect)
        } catch {
            print("Own stream failed: \(error)")
            source = .none
        }
    }
}
