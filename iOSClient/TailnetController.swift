import Foundation
import Network
import UIKit
import StreamProtocol
#if canImport(SillTailnet)
import SillTailnet
#endif

/// Reach from Anywhere on the device (docs/relay-plan.md): one Mac's private tailnet, inside this
/// app, through SillTailnet.xcframework (Helpers/tailnet-mobile, ported from Frigate Launcher's,
/// itself from Bridge's). No VPN profile, no NetworkExtension: the tailnet exists only in this
/// process, beside any Tailscale the person runs.
///
/// What Sill dials is the framework's forwarder, 127.0.0.1:<port>, spliced to the Mac's door
/// (sill-mac:7455) on the tailnet: RemoteConnector dials it with the Mac's pin like any address, so
/// the tailnet is a path and never a trust anchor.
///
/// One tailnet at a time (the framework holds one), the one of the saved Mac being dialed or
/// streamed. Started when a dial wants it; joined with a key only from a kind 60 that arrived on a
/// session pinned to that Mac; the fingerprint and domain are kept on the saved Mac, never the key.
/// Suspends its loopback listeners in the background and recovers on a network change. Main thread,
/// as StreamClient (its calls into the framework return at once).
final class TailnetController: ObservableObject {
    static let shared = TailnetController()

    struct Status: Decodable, Equatable {
        var phase = "idle"
        var running = false
        var proxyAddr = ""
        var tailnetIP = ""
        var error = ""
        var relay = ""
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            phase = (try? c.decode(String.self, forKey: .phase)) ?? "idle"
            running = (try? c.decode(Bool.self, forKey: .running)) ?? false
            proxyAddr = (try? c.decode(String.self, forKey: .proxyAddr)) ?? ""
            tailnetIP = (try? c.decode(String.self, forKey: .tailnetIP)) ?? ""
            error = (try? c.decode(String.self, forKey: .error)) ?? ""
            relay = (try? c.decode(String.self, forKey: .relay)) ?? ""
        }
        private enum Keys: String, CodingKey { case phase, running, proxyAddr, tailnetIP, error, relay }
    }

    /// Whether this build carries the framework (every build from Scripts/make-tailnet.sh).
    static var available: Bool {
        #if canImport(SillTailnet)
        return true
        #else
        return false
        #endif
    }

    @Published private(set) var status = Status()
    /// The tailnet started now: its fingerprint.
    private(set) var current: String?
    private var poll: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var lastPath: String?

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let signature = path.status == .satisfied ? path.availableInterfaces.map { "\($0.type)" }.joined(separator: ",") : "down"
            DispatchQueue.main.async { self?.pathChanged(signature) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "sill.tailnet.path"))
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend()
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }
    }

    /// Where this tailnet keeps its state: Application Support, one folder per Mac's tailnet, out
    /// of backups (a restored node key on another device would be the same node twice).
    private static func stateDirectory(_ fingerprint: String) -> URL {
        var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SillTailnet/\(fingerprint)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    /// Starts (or keeps) the tailnet `relay` names; with `key`, joins it first (a kind 60).
    func start(_ relay: RelayInfo, key: String? = nil) {
        #if canImport(SillTailnet)
        guard relay.isWellFormed else { return }
        if current == relay.fingerprint, key == nil, status.running { return }
        current = relay.fingerprint
        var cfg: [String: String] = [
            "fingerprint": relay.fingerprint,
            "domain": relay.domain,
            "stateDir": Self.stateDirectory(relay.fingerprint).path,
            "hostname": UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
        ]
        if let key { cfg["preauthKey"] = key }
        guard let data = try? JSONSerialization.data(withJSONObject: cfg), let json = String(data: data, encoding: .utf8) else { return }
        _ = Self.call { json.withCString { SillTailnetStart(UnsafeMutablePointer(mutating: $0)) } }
        beginPolling()
        #endif
    }

    func stop() {
        #if canImport(SillTailnet)
        SillTailnetStop()
        #endif
        current = nil
        poll?.cancel(); poll = nil
        status = Status()
    }

    /// The forwarder Sill dials for the tailnet `relay` names, when that tailnet runs now.
    func forwarder(for relay: RelayInfo) -> (host: String, port: Int)? {
        guard current == relay.fingerprint, status.running else { return nil }
        let parts = status.proxyAddr.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]), port > 0 else { return nil }
        return (String(parts[0]), port)
    }

    /// Waits up to `seconds` for the tailnet `relay` names to run, then hands back its forwarder.
    @MainActor
    func forwarder(for relay: RelayInfo, within seconds: Double) async -> (host: String, port: Int)? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            refresh()
            if let f = forwarder(for: relay) { return f }
            if status.phase == "error" || status.phase == "removed" { return nil }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    // MARK: Lifecycle

    private func suspend() {
        #if canImport(SillTailnet)
        if current != nil { SillTailnetSuspend() }
        #endif
    }

    private func resume() {
        #if canImport(SillTailnet)
        guard current != nil else { return }
        SillTailnetResume()
        _ = Self.call { SillTailnetRecover() }
        #endif
    }

    private func pathChanged(_ signature: String) {
        defer { lastPath = signature }
        guard let previous = lastPath, previous != signature, signature != "down", current != nil else { return }
        #if canImport(SillTailnet)
        _ = Self.call { SillTailnetRecover() }
        #endif
    }

    private func beginPolling() {
        poll?.cancel()
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refresh() {
        #if canImport(SillTailnet)
        guard let text = Self.call({ SillTailnetStatus() }), let data = text.data(using: .utf8),
              let s = try? JSONDecoder().decode(Status.self, from: data) else { return }
        if s != status {
            #if DEBUG
            print("tailnet: \(s.phase) running=\(s.running) forwarder=\(s.proxyAddr) ip=\(s.tailnetIP) \(s.error)")
            #endif
            status = s
        }
        #endif
    }

    #if canImport(SillTailnet)
    /// One call that returns a string the framework allocated: copied, then freed.
    private static func call(_ body: () -> UnsafeMutablePointer<CChar>?) -> String? {
        guard let p = body() else { return nil }
        defer { SillTailnetFreeString(p) }
        return String(cString: p)
    }
    #endif
}
