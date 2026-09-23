import Combine
import UIKit
import StreamProtocol

// MARK: - Client stats reporter

/// Sends what this device sees (fps, frame age, RTT) to the host once a second while connected,
/// so the Mac's log carries the device-side numbers. Created once by `ContentView`, next to the
/// app's `StreamClient`; runs in Release too, since it costs one tiny message a second.
///
/// Each report is one second the client closed (`StreamClient.linkStats`), sent as it closes. It
/// has no timer of its own: a second timer drifting against the client's would now and then send
/// a second twice or skip one. The client closes seconds only while connected, so nothing is sent
/// between sessions and nothing ticks in the background.
///
/// Holds the client weakly: the client is owned by `ContentView`'s `@StateObject`, and the sink
/// only captures `self` weakly, so nothing here keeps anything alive. Main thread.
final class ClientStatsReporter: ObservableObject {
    private weak var client: StreamClient?
    private var subscription: AnyCancellable?

    /// Idempotent: `onAppear` can fire more than once.
    func attach(to client: StreamClient) {
        guard self.client !== client else { return }
        self.client = client
        subscription = client.$linkStats
            .compactMap { $0 }   // nil is "not measured yet" or a teardown, never a report
            .sink { [weak self] stats in self?.report(stats) }
    }

    /// The wire keeps its first four fields for older hosts: medians there, -1 for a second without
    /// a sample; the maxima ride in the optional fields that only newer hosts read.
    private func report(_ s: StreamClient.LinkStats) {
        guard let client, client.connected else { return }
        let stats = ClientStats(fps: s.fps,
                                frameAgeMs: s.frameAge?.median ?? -1,
                                rttMs: s.rtt?.median ?? -1,
                                device: Self.deviceName,
                                frameAgeMaxMs: s.frameAge?.max ?? -1,
                                rttMaxMs: s.rtt?.max ?? -1)
        client.send(.clientStats, payload: Wire.encode(stats))
    }

    /// "iPad (iPad14,1)": the user-visible name is generic on iOS 16+ without an entitlement, so the
    /// hardware identifier is what tells an iPad Mini from a simulator in the Mac's log.
    static let deviceName: String = {
        let name = UIDevice.current.name
        let id = hardwareIdentifier
        return id.isEmpty ? name : "\(name) (\(id))"
    }()

    private static var hardwareIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) simulator"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

// MARK: - HUD (DEBUG only)

#if DEBUG
/// The on-screen readout: "58 fps · age 9/24 ms · rtt 7/80 ms · 3024×1898" in a translucent
/// capsule at the display view's top-right; each pair is the last second's median/max, "–" for a
/// second without a sample. Only built when launched with `-SillHUD 1`; never in Release.
/// Purely visual: it never takes a touch, so input still reaches the overlay underneath the stream.
final class DiagnosticsHUDView: UIView {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "SillHUD") }

    private static let inset: CGFloat = 8
    private static let padding = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerCurve = .continuous
        label.isUserInteractionEnabled = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 1
        addSubview(label)
        update(stats: nil, videoSize: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `stats` nil: no second measured yet.
    func update(stats: StreamClient.LinkStats?, videoSize: CGSize) {
        let size = videoSize == .zero ? "no video" : "\(Int(videoSize.width))×\(Int(videoSize.height))"
        label.text = "\(stats?.fps ?? 0) fps · age \(Self.text(stats?.frameAge)) · rtt \(Self.text(stats?.rtt)) · \(size)"
        superview?.setNeedsLayout()
    }

    /// "9/24 ms" (median/max) or "–".
    private static func text(_ spread: StreamClient.MedianMax?) -> String {
        guard let spread else { return "–" }
        return "\(spread.median)/\(spread.max) ms"
    }

    /// Called from the host view's `layoutSubviews`: pin to the top-right corner of `bounds`.
    func place(in bounds: CGRect) {
        let text = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let p = Self.padding
        let size = CGSize(width: ceil(text.width) + p.left + p.right, height: ceil(text.height) + p.top + p.bottom)
        frame = CGRect(x: bounds.maxX - Self.inset - size.width, y: bounds.minY + Self.inset,
                       width: size.width, height: size.height)
        label.frame = CGRect(x: p.left, y: p.top, width: ceil(text.width), height: ceil(text.height))
        layer.cornerRadius = size.height / 2
    }
}
#endif
