import Foundation
import StreamProtocol

/// Reach from Anywhere's helper on the Mac (docs/relay-plan.md): runs `sill-net` (Helpers/sill-net,
/// in Sill.app/Contents/Helpers, with Headscale built in) while the Mac's user has Reach from Anywhere
/// and Remote Access on, and talks to it over its stdin and stdout, one JSON object a line. Its
/// stderr goes to this host's log, one line each, prefixed "sill-net:".
///
/// sill-net runs Headscale (the Mac's own tailnet control plane), registers it with a HeadFwd relay
/// (headfwd.net), and forwards its tailnet node's port 7455 to the relay door on loopback (RelayDoor),
/// whose address this tells it. It exits when its stdin closes, so it never outlives Sill; this
/// restarts it after a crash, waiting longer each time (2 s, doubling, at most 60 s).
///
/// Nothing secret passes through here but the preauth keys sill-net mints, each for one device that
/// asked over a paired session (kind 61): handed straight back as kind 60 and never logged.
///
/// Main actor. The process's pipes are read on their own queues and hop here per line.
@MainActor
package final class RelaySupervisor {
    /// What the pane and kind 18 show.
    package enum State: Equatable, Sendable {
        case off
        /// Starting Headscale, registering with the relay, bringing the tailnet node up.
        case starting
        /// The tailnet is up and the relay holds its tunnel: devices can join.
        case ready(RelayInfo)
        /// Up, but the relay's tunnel is down (sill-net retries by itself).
        case relayDown(RelayInfo)
        /// sill-net is missing, would not start, or said why it cannot.
        case failed(String)
    }

    /// The bundled helper: Contents/Helpers/sill-net. Nil when this build has none (a bare
    /// `swift build` of the CLI): the switch then says so.
    package static var helperURL: URL? {
        if let env = ProcessInfo.processInfo.environment["SILL_NET_BINARY"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sill-net")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        // SillHost run from .build: the helpers Scripts/make-helpers.sh leaves in .build/helpers.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for up in [2, 3] {
            var dir = exe.deletingLastPathComponent()
            for _ in 0..<up { dir.deleteLastPathComponent() }
            let candidate = dir.appendingPathComponent("helpers/sill-net")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private(set) package var state: State = .off { didSet { if state != oldValue { onState?(state) } } }
    package var onState: ((State) -> Void)?
    /// A key sill-net minted for a device (its fingerprint, base64url), to send as kind 60.
    var onInvite: ((_ device: String, _ invite: RelayInvite) -> Void)?

    private let dataDir: URL
    private let relayURL: String
    private var process: Process?
    private var stdin: FileHandle?
    private var wanted = false
    private var door: Int?
    private var backoff: TimeInterval = 2
    private var restart: Task<Void, Never>?
    private var pairedDevices: [String] = []
    private var reportedFailure: String?
    /// The last process `stop` let go of, until it has exited.
    private var stopping: Process?

    /// `dataDir`: sill-net's state (~/Library/Application Support/Sill/net in Sill.app). `relayURL`:
    /// the HeadFwd relay, https://headfwd.net unless `defaults write me.saffer.sill.mac RelayURL …`.
    package init(dataDir: URL, relayURL: String = "https://headfwd.net") {
        self.dataDir = dataDir
        self.relayURL = relayURL
    }

    /// Runs sill-net while `wanted`; the relay door's port goes to it as soon as it is known.
    func set(wanted: Bool, doorPort: Int?) {
        let doorChanged = doorPort != door
        door = doorPort
        self.wanted = wanted
        if !wanted {
            stop()
            state = .off
            return
        }
        if process == nil, restart == nil {
            if let old = stopping, old.isRunning {
                // Turned off and on again: the last sill-net (and its Headscale) is still letting go
                // of the same folder. Start once it has.
                restart = Task { @MainActor [weak self] in
                    for _ in 0..<160 where old.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
                    guard let self, !Task.isCancelled, self.wanted, self.process == nil else { return }
                    self.restart = nil
                    self.launch()
                }
            } else {
                launch()
            }
        } else if doorChanged, let p = doorPort { send(["cmd": "door", "door": "127.0.0.1:\(p)"]) }
    }

    /// The paired devices' fingerprints: sill-net removes the nodes of any device no longer here
    /// (removed while it was not running).
    func paired(_ fingerprints: [String]) {
        pairedDevices = fingerprints
        if process != nil { send(["cmd": "paired", "devices": fingerprints]) }
    }

    /// Mints a key for a paired device that asked (kind 61).
    func invite(device: String) {
        send(["cmd": "invite", "device": device])
    }

    /// A pairing window's QR key, under `pending:<window>` until a device pairs with it.
    func invite(window: String) {
        send(["cmd": "invite", "device": "pending:" + window])
    }

    /// The device that paired through `window` now owns the node that joined with its key.
    func claim(window: String, device: String) {
        send(["cmd": "claim", "from": "pending:" + window, "device": device])
    }

    /// `window` closed with no device paired through it: its key, and any node it joined, go.
    func forget(window: String) {
        send(["cmd": "forget", "device": "pending:" + window])
    }

    /// Removes a device's nodes from the tailnet (the Mac's Remove).
    func remove(device: String) {
        send(["cmd": "remove", "device": device])
    }

    package func shutdown() {
        wanted = false
        stop()
    }

    // MARK: The process

    private func launch() {
        restart = nil
        guard let url = Self.helperURL else {
            fail("this build of Sill has no relay helper (Scripts/make-helpers.sh builds it)")
            return
        }
        do { try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) } catch {
            fail("its folder couldn’t be made (\(error.localizedDescription))")
            return
        }
        let p = Process()
        p.executableURL = url
        var args = ["--data", dataDir.path, "--relay", relayURL]
        if let door { args += ["--door", "127.0.0.1:\(door)"] }
        p.arguments = args
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        lines(from: output.fileHandleForReading) { [weak self, weak p] line in
            // Lines from a process this supervisor already let go of change nothing.
            guard let self, let p, p === self.process else { return }
            self.event(line)
        }
        lines(from: errors.fileHandleForReading) { line in print(line) }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { @MainActor in self?.exited(proc, status: status) }
        }
        do { try p.run() } catch {
            fail("it couldn’t start (\(error.localizedDescription))")
            return
        }
        process = p
        stdin = input.fileHandleForWriting
        // A write after sill-net exited (before `exited` runs) must fail, not raise SIGPIPE: the CLI
        // does not ignore it, and would die of it.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        state = .starting
        send(["cmd": "paired", "devices": pairedDevices])
        print("Reach from Anywhere: starting (\(url.lastPathComponent), relay \(relayURL)).")
    }

    private func stop() {
        restart?.cancel(); restart = nil
        guard let p = process else { return }
        process = nil
        stopping = p
        send(["cmd": "stop"], to: stdin)
        try? stdin?.close()
        stdin = nil
        // Closing stdin stops it; a second's grace, then SIGTERM (sill-net stops Headscale either way).
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { p.terminate() } }
    }

    private func exited(_ p: Process, status: Int32) {
        guard p === process else { return }
        process = nil
        stdin = nil
        guard wanted else { state = .off; return }
        let wait = backoff
        backoff = min(backoff * 2, 60)
        fail("it stopped (status \(status)); starting it again in \(Int(wait)) s")
        restart = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self, !Task.isCancelled, self.wanted, self.process == nil else { return }
            self.launch()
        }
    }

    private func fail(_ why: String) {
        state = .failed(why)
        if reportedFailure != why {
            reportedFailure = why
            print("Reach from Anywhere: \(why).")
        }
    }

    // MARK: Lines

    private func send(_ object: [String: Any], to handle: FileHandle? = nil) {
        guard let h = handle ?? stdin, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? h.write(contentsOf: data)
    }

    /// Calls `each` on the main actor for every line `handle` writes.
    private nonisolated func lines(from handle: FileHandle, _ each: @escaping @MainActor (String) -> Void) {
        let buffer = LineBuffer()
        handle.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            for line in buffer.append(chunk) { Task { @MainActor in each(line) } }
        }
    }

    private func event(_ line: String) {
        guard let data = line.data(using: .utf8),
              let e = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = e["event"] as? String else { return }
        switch kind {
        case "status":
            let fp = e["fingerprint"] as? String ?? "", domain = e["domain"] as? String ?? ""
            let info = RelayInfo(fingerprint: fp, domain: domain)
            switch (e["state"] as? String, e["relay"] as? String) {
            case ("ready"?, "connected"?) where info.isWellFormed:
                backoff = 2
                reportedFailure = nil
                if state != .ready(info) { print("Reach from Anywhere: ready, through \(domain).") }
                state = .ready(info)
            case ("ready"?, _) where info.isWellFormed:
                if case .ready = state { print("Reach from Anywhere: the relay at \(domain) is unreachable; trying again.") }
                state = .relayDown(info)
            case ("error"?, _):
                fail(e["error"] as? String ?? "it reported an error")
            default:
                if case .failed = state {} else { state = .starting }
            }
        case "invite":
            guard let device = e["device"] as? String, let key = e["key"] as? String,
                  let fp = e["fingerprint"] as? String, let domain = e["domain"] as? String else { return }
            let invite = RelayInvite(relay: RelayInfo(fingerprint: fp, domain: domain), key: key)
            guard invite.isWellFormed else { return }
            onInvite?(device, invite)
        case "removed":
            let n = e["nodes"] as? Int ?? 0
            print("Reach from Anywhere: removed \(n) device node\(n == 1 ? "" : "s") from this Mac’s tailnet.")
        case "error":
            if let why = e["error"] as? String { print("Reach from Anywhere: \(why).") }
        default:
            break
        }
    }

    /// What kind 18 carries: the tailnet and its relay, while devices can join it (and while the relay
    /// is briefly down: a device that joined keeps its node either way).
    var advertised: RelayInfo? {
        if case .ready(let info) = state { return info }
        if case .relayDown(let info) = state { return info }
        return nil
    }
}

/// Bytes from a pipe, split into lines; a pipe's handler runs on its own queue.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    /// The whole lines `chunk` completes, without their newlines (empty ones dropped).
    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var out: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let line = String(decoding: data[data.startIndex..<nl], as: UTF8.self)
            data.removeSubrange(data.startIndex...nl)
            if !line.isEmpty { out.append(line) }
        }
        return out
    }
}
