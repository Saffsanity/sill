import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI
import SillHostCore
import StreamProtocol

/// The offer the pairing window shows: set by the controller, read by its view.
@MainActor @Observable
final class PairingWindowState {
    var offer: RemoteAccess.PairingOffer?
}

/// "Pair iPhone or iPad" (docs/remote-access-plan.md §6.2): a standalone window, not a sheet,
/// because a device near the Mac can open it (Pair This iPad…) while Settings is closed. One
/// instance: opening it again brings it forward with the same code. Closing it cancels the
/// pairing window, and the code dies with it.
///
/// `sharingType = .none` is a best effort only (ScreenCaptureKit is reported to ignore it from
/// macOS 15); what keeps the code off every device is the Desktop stream leaving Sill's own
/// windows out, and the window catalog skipping them.
@MainActor
final class PairDeviceWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private let state = PairingWindowState()

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        window.title = "Pair iPhone or iPad"
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.sharingType = .none
        super.init(window: window)
        let host = NSHostingController(rootView: LivePairDeviceView(model: model, state: state, close: { [weak self] in self?.close() }))
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Shows `offer`, centred the first time, and brings the window forward (a device's request
    /// arrives on a main-actor hop: this shows a window and runs no modal loop).
    func show(_ offer: RemoteAccess.PairingOffer) {
        guard let window else { return }
        let wasVisible = window.isVisible
        state.offer = offer
        if !wasVisible { window.center() }
        WindowPlacement.bringForward(window)
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelPairing()      // a no-op once the code was used, expired or stopped
        state.offer = nil
    }
}

/// The window's content, live: the offer, the host's remote status, the Remote Access setting.
private struct LivePairDeviceView: View {
    let model: AppModel
    let state: PairingWindowState
    let close: () -> Void

    var body: some View {
        if let offer = state.offer {
            let status = model.coordinator?.status.snapshot.remote ?? RemoteStatus()
            PairDeviceView(offer: offer, status: status, remoteAccess: model.settings.config.remoteAccess,
                           actions: PairDeviceView.Actions(turnOn: { model.turnOnRemoteAccess() },
                                                           newCode: { model.pairDevice() },
                                                           changePort: { model.showSettings?(.remoteAccess) },
                                                           close: close))
                // Remote Access turned off (or the pane's Cancel) closed the pairing: so does the window.
                .onChange(of: status.pairing) { _, pairing in
                    if pairing == .closed { close() }
                }
        }
    }
}

/// The QR code, the typed path's address and code, and the state of this pairing. Values in,
/// actions out, so the previews can draw every state.
struct PairDeviceView: View {
    struct Actions {
        var turnOn: () -> Void = {}
        var newCode: () -> Void = {}
        var changePort: () -> Void = {}
        var close: () -> Void = {}
    }

    let offer: RemoteAccess.PairingOffer
    let status: RemoteStatus
    let remoteAccess: Bool
    let actions: Actions
    /// The countdown's clock; fixed in the previews, live (once a second) otherwise.
    var now: Date?

    enum Phase: Equatable {
        case waiting(triesLeft: Int, wrongFrom: String?)
        case paired(String)
        case stopped
        case expired
        case closed
        /// The remote door is not listening: the port is taken, or it failed.
        case doorDown(String)
    }

    var phase: Phase {
        switch status.pairing {
        case .open(_, _, let triesLeft, let wrongFrom):
            switch status.listener {
            case .portInUse(let p): return .doorDown("Can’t pair while port \(p) is in use.")
            case .failed: return .doorDown("Can’t pair: remote access couldn’t start. Sill tries again every 30 seconds.")
            case .off, .listening: return .waiting(triesLeft: triesLeft, wrongFrom: wrongFrom)
            }
        case .paired(let name): return .paired(name)
        case .stopped: return .stopped
        case .expired: return .expired
        case .closed: return .closed
        }
    }

    private var isWaiting: Bool { if case .waiting = phase { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let who = offer.requestedBy {
                Text("\(who) on this network asked to pair.")
                    .font(.headline)
            }
            Text("In Sill on your iPhone or iPad, tap Add a Mac…, then point it at this code.")
                .fixedSize(horizontal: false, vertical: true)
            QRCodeView(text: offer.url)
                .opacity(isWaiting ? 1 : 0.2)
                .frame(maxWidth: .infinity)
            lower
            if !remoteAccess {
                Text("Remote Access is off. Paired devices can connect away from home once you turn it on.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(20)
        .frame(width: 440)
        .task(id: phase) {
            // Paired: closes itself after 3 s, unless the Turn On line still has something to say.
            guard case .paired = phase, remoteAccess, now == nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { actions.close() }
        }
    }

    // MARK: Under the code

    @ViewBuilder private var lower: some View {
        switch phase {
        case .waiting(let triesLeft, let wrongFrom):
            VStack(alignment: .leading, spacing: 10) {
                Text("Can’t scan? Tap Enter Code Instead, and type:")
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Address").foregroundStyle(.secondary)
                        Text(address).textSelection(.enabled)
                    }
                    GridRow {
                        Text("Code").foregroundStyle(.secondary)
                        Text(offer.groupedCode)
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                countdown
                if let wrongFrom {
                    Label("A wrong code came from \(wrongFrom). \(triesLeft) tr\(triesLeft == 1 ? "y" : "ies") left.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text("A paired device can see and control this Mac.")
                    .foregroundStyle(.secondary)
            }
        case .paired(let name):
            Label("Paired with \(name).", systemImage: "checkmark.circle.fill")
        case .stopped:
            Text("Pairing stopped after \(5) wrong codes.")
        case .expired:
            Text("This code expired.")
        case .closed:
            Text("This code no longer works.")
        case .doorDown(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    /// "Works once, for the next 4:58.", once a second. VoiceOver reads it when it gets there and
    /// does not announce every tick.
    @ViewBuilder private var countdown: some View {
        if let now {
            Text(Self.countdown(until: offer.expiresAt, now: now))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.countdown(until: offer.expiresAt, now: context.date))
            }
        }
    }

    static func countdown(until end: Date, now: Date) -> String {
        let left = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return "Works once, for the next \(left / 60):\(String(format: "%02d", left % 60))."
    }

    /// What to type on the device: this network's address first, else a VPN's name, else a VPN
    /// IP, with the port when it is not the usual one.
    private var address: String {
        let host = status.lanAddress
            ?? status.addresses.first { $0.kind == MacAddress.vpn }?.host
            ?? status.addresses.first?.host
            ?? "this Mac’s address"
        guard case .success(var parsed) = AddressParser.parse(host) else { return host }
        if offer.port != HostConfig.defaultRemotePort { parsed.port = offer.port }
        return parsed.text
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            Spacer()
            if !remoteAccess {
                Button("Turn On Remote Access", action: actions.turnOn)
            }
            switch phase {
            case .waiting, .closed:
                Button("Cancel", action: actions.close)
                    .keyboardShortcut(.cancelAction)
            case .paired:
                Button("Done", action: actions.close)
                    .keyboardShortcut(.defaultAction)
            case .stopped, .expired:
                Button("Cancel", action: actions.close)
                    .keyboardShortcut(.cancelAction)
                Button("New Code", action: actions.newCode)
                    .keyboardShortcut(.defaultAction)
            case .doorDown:
                Button("Cancel", action: actions.close)
                    .keyboardShortcut(.cancelAction)
                Button("Change Port…", action: actions.changePort)
            }
        }
    }
}

/// A QR code, always dark on white with a 4-module quiet zone, each module a whole number of
/// pixels: about 220 pt for the symbol. The bitmap is made at the screen's own pixel size and
/// shown 1:1, because a scaled image is smoothed on some drawing paths (`.interpolation(.none)`
/// was ignored when the previews rendered it), and a camera reads crisp edges best.
struct QRCodeView: View {
    let text: String
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = QRCode.screenImage(for: text, displayScale: displayScale) {
            // A whole number of points, so centring never lands the bitmap on half a pixel (which
            // smooths every module's edge); the spare pixel is more white quiet zone.
            let side = (CGFloat(image.width) / displayScale).rounded(.up)
            Image(decorative: image, scale: displayScale)
                .frame(width: side, height: side, alignment: .topLeading)
                .background(Color.white)
                .accessibilityElement()
                .accessibilityLabel("Pairing code image")
                .accessibilityAddTraits(.isImage)
        }
    }
}

/// The QR code's bitmaps.
@MainActor
enum QRCode {
    static let quietZone = 4
    /// The symbol's size on screen, before rounding down to whole pixels per module.
    static let symbolPoints: CGFloat = 220
    private static var cached: (text: String, scale: CGFloat, image: CGImage)?

    /// The code for `text` at `displayScale`, each module a whole number of pixels. The last one is
    /// kept: the window's view is drawn again every second while its countdown runs.
    static func screenImage(for text: String, displayScale: CGFloat) -> CGImage? {
        if let c = cached, c.text == text, c.scale == displayScale { return c.image }
        guard let base = image(for: text) else { return nil }
        let symbol = CGFloat(base.width - 2 * quietZone)
        let perModule = max(1, Int((symbolPoints * displayScale / symbol).rounded(.down)))
        let size = base.width * perModule
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let scaled = ctx.makeImage() else { return nil }
        cached = (text, displayScale, scaled)
        return scaled
    }

    /// CIQRCodeGenerator at level M. Its output has a 1-module margin; the symbol is cropped to
    /// its dark modules (the finder patterns reach three corners) and given the 4 the standard asks.
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let raw = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent),
              let bounds = darkBounds(raw) else { return nil }
        let size = Int(bounds.width) + 2 * quietZone
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let symbol = raw.cropping(to: bounds) else { return nil }
        let zone = CGFloat(quietZone)
        ctx.draw(symbol, in: CGRect(x: zone, y: zone, width: bounds.width, height: bounds.height))
        return ctx.makeImage()
    }

    /// The smallest rectangle holding every dark pixel, in the image's own (top-left) pixel space.
    private static func darkBounds(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where data[y * w + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
