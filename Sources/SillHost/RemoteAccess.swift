import Foundation
import Network
import Security
import StreamProtocol

/// Remote access on one host (docs/remote-access-plan.md §4.10): the Mac's identity and trust
/// list, the pairing window, the addresses (Reachability, RouterAddress, AddressList), the remote
/// door (RemoteServer) and kind 18. The coordinator owns one: Sill.app always, SillHost only with
/// --remote. Main actor; the door runs on the network queue and reads only `trust`, a
/// lock-protected snapshot replaced whole on every change, so nothing there waits on this actor.
///
/// Only the Mac widens exposure: Remote Access, the port and internet access come from HostConfig
/// (the app's settings or the CLI's flags), never from a device. A pairing never turns Remote
/// Access on by itself.
///
/// Secrets: the pairing code and the QR secret leave this type only through `onPairingOffer` (the
/// app shows its window, the CLI prints). They are never in the status, a log line, kind 16 or 18,
/// or a TXT record.
///
/// TEST ONLY, on a host that does not advertise: SILL_TEST_PAIRING_TTL=<s> shortens the window,
/// SILL_TEST_NO_ROUTER=1 skips the router query, and the address list starts with 127.0.0.1.
@MainActor
package final class RemoteAccess {
    /// What the Mac shows to pair a device: the QR link, the typed code, until when, and why.
    package struct PairingOffer: Sendable {
        /// sill://pair?v=1&… (PairLink).
        package let url: String
        /// 12 digits; `groupedCode` shows them as "4829 1355 7208".
        package let code: String
        package var groupedCode: String { PairingCode.grouped(code) }
        package let expiresAt: Date
        /// A device's name when a device asked (kind 21); nil when opened on the Mac.
        package let requestedBy: String?
        /// The remote door's port, as devices dial it.
        package let port: Int
        /// This window's offer shown again (a second request while it is open).
        package let again: Bool
    }

    package let identity: HostIdentity?
    /// Why there is no identity (the keychain failed); remote access is then unavailable.
    package let identityProblem: String?
    private let store: IdentityStore?
    private(set) var paired: [PairedDevice] = []

    private var window = PairingWindow()
    let trust = TrustBox()
    private var remoteAccess = false
    private var remotePort = HostConfig.defaultRemotePort
    private var internetAccess = false
    private var addressName: ParsedAddress?
    private var addressNameText = ""

    private weak var server: StreamServer?
    private weak var status: HostStatus?
    private var door: RemoteServer?
    private var macName = "Mac"
    private var testHost = false
    private var reachability: Reachability?
    private var reach: Reachability.Snapshot?
    private var router: RouterAddress?
    private var routerInterface: String?
    private var routerState = RemoteStatus.Router.off
    private var listenerState = RemoteStatus.Listener.off
    private var pairingState = RemoteStatus.Pairing.closed
    private var lastBroadcast: MacInfo?
    private var lastSeen: [String: (at: Date, route: String)] = [:]
    /// An offer waiting for the door's port and the first address list (at most `offerWait`).
    private var offerPending: (requestedBy: String?, again: Bool)?
    private var offerDeadline: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    static let offerWait: TimeInterval = 3

    /// The app shows its pairing window; the CLI prints the link and the code.
    package var onPairingOffer: ((PairingOffer) -> Void)?
    /// The CLI: a fresh window after each use or expiry, for the whole run (not after five wrong
    /// codes, and not after Cancel). An expiry is then noticed at the next attempt, which is
    /// answered "expired" before the fresh window opens.
    package var reopensPairing = false
    /// The core's "Pairing window open …" line (the CLI prints its own from `onPairingOffer`).
    package var logsPairingWindows = true

    /// Loads (or creates) the identity and the trust list from `store`. A failure leaves the host
    /// without an identity: no TXT tag, no kind 18, no remote door; `identityProblem` says why.
    package init(store: IdentityStore) {
        var identity: HostIdentity?
        var problem: String?
        var paired: [PairedDevice] = []
        do {
            let key = try store.loadOrCreateKey()
            let recognition = try store.loadOrCreateRecognitionKey()
            guard let id = HostIdentity(privateKey: key, recognitionKey: recognition) else {
                throw IdentityStoreError("the key could not make a TLS identity")
            }
            identity = id
            paired = try store.loadPaired()
        } catch {
            problem = "\(error)"
        }
        self.identity = identity
        identityProblem = problem
        self.store = identity == nil ? nil : store
        self.paired = paired
    }

    /// Called by the coordinator's init, before the server starts: the TXT tag goes into the first
    /// registration.
    func attach(server: StreamServer, status: HostStatus, macName: String) {
        self.server = server
        self.status = status
        self.macName = SafeText.label(macName).isEmpty ? "Mac" : SafeText.label(macName)
        testHost = server.isTestHost
        guard let identity else { publish(); return }
        server.txtRecord = { identity.txtRecord() }
        let door = RemoteServer(server: server, identity: identity, trust: trust)
        door.onListener = { [weak self] state in Task { @MainActor in self?.listenerChanged(state) } }
        door.onPairAttempt = { [weak self] attempt, reply in
            Task { @MainActor in
                guard let self else { reply(PairResult(ok: false, reason: PairResult.closed)); return }
                reply(self.judge(attempt))
            }
        }
        self.door = door
        publishTrust()
        publish()
    }

    // MARK: Settings (the Mac's own)

    /// The three knobs from HostConfig: starts or stops the door, the watcher and the router
    /// query, and publishes. Turning Remote Access off closes an open pairing window and says
    /// goodbye to every remote session; turning the internet switch off, to those from the internet.
    package func apply(_ config: HostConfig) {
        guard identity != nil else { return }
        let wasOn = remoteAccess, wasInternet = internetAccess
        remoteAccess = config.remoteAccess
        remotePort = config.remotePort
        internetAccess = config.internetAccess
        if wasOn, !remoteAccess {
            if window.isOpen { window.close(.cancelled); windowClosed(.cancelled, reopen: false) }
            print("Remote access off.")
        }
        publishTrust()
        if wasOn, !remoteAccess {
            door?.closeSessions(Goodbye.remoteOff, matching: { _ in true },
                                line: { name, endpoint in "Remote access off: disconnecting \(name) at \(endpoint)." })
        }
        if wasInternet, !internetAccess {
            door?.closeSessions(Goodbye.internetOff, matching: { $0.origin == .internet },
                                line: { name, endpoint in "Internet access off: disconnecting \(name) at \(endpoint)." })
        }
        updateDoor()
        updateWatchers()
        publish()
        broadcastIfChanged()
    }

    /// The address name setting ("home.example.net" or "home.example.net:17455"), checked by the
    /// address parser; anything it refuses counts as none.
    package func setAddressName(_ text: String) {
        addressNameText = text
        if case .success(let a) = AddressParser.parse(text) { addressName = a } else { addressName = nil }
        publish()
        broadcastIfChanged()
    }

    // MARK: Pairing

    /// Opens a pairing window (5 minutes, one device) and offers it. Opening again while one is
    /// open keeps the same code and offers it again (the app brings its window forward, the CLI
    /// prints the code again). The door runs while a window is open, even with Remote Access off.
    package func openPairing(requestedBy: String?) {
        guard let identity else { return }
        if let w = window.current {
            makeOffer(requestedBy: w.requestedBy, again: true)
            return
        }
        var secret = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, secret.count, &secret) == errSecSuccess, let code = PairingCode.generate() else {
            print("Pairing could not start: the random source failed.")
            return
        }
        var lifetime = PairingWindow.lifetime
        if testHost, let v = ProcessInfo.processInfo.environment["SILL_TEST_PAIRING_TTL"], let s = Double(v), s > 0 { lifetime = s }
        let now = Date().timeIntervalSince1970
        window.open(secret: Data(secret), code: code, now: now, lifetime: lifetime, requestedBy: requestedBy)
        pairingState = .open(requestedBy: requestedBy, expiresAt: Date(timeIntervalSince1970: now + lifetime),
                             triesLeft: PairingWindow.maxFailures, lastWrongFrom: nil)
        if logsPairingWindows {
            let span = lifetime >= 60 ? "\(Int(lifetime / 60)) minute\(Int(lifetime / 60) == 1 ? "" : "s")" : "\(Int(lifetime)) s"
            print("Pairing window open for \(span) (\(requestedBy.map { "asked by \($0)" } ?? "opened on this Mac")).")
        }
        // K for the typed path, off the main actor (~0.1 s); a code proof before it is answered busy.
        let fp = identity.fingerprint
        Task { @MainActor [weak self] in
            let key = await Task.detached(priority: .userInitiated) { PairingProof.codeKey(code: code, macFingerprint: fp) }.value
            if let key { self?.window.setCodeKey(key, code: code) }
        }
        if !reopensPairing {
            let until = now + lifetime
            expiryTask?.cancel()
            expiryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0, until - Date().timeIntervalSince1970)))
                guard let self, !Task.isCancelled else { return }
                if self.window.expireIfDue(now: Date().timeIntervalSince1970) { self.windowClosed(.expired, reopen: false) }
            }
        }
        publishTrust()
        updateDoor()
        updateWatchers()
        publish()
        broadcastIfChanged()
        makeOffer(requestedBy: requestedBy, again: false)
    }

    /// Kind 21 from a device near the Mac (the coordinator checked the route): a window for it,
    /// or, on the CLI, the open window's code printed again. The app ignores it while one is open.
    func pairingWanted(by device: String) {
        guard identity != nil else { return }
        if window.isOpen {
            if reopensPairing { makeOffer(requestedBy: window.current?.requestedBy, again: true) }
            return
        }
        openPairing(requestedBy: device)
    }

    /// The Mac's user closed the pairing window: the code dies with it.
    package func cancelPairing() {
        guard window.isOpen else { return }
        window.close(.cancelled)
        windowClosed(.cancelled, reopen: false)
    }

    /// Removes a paired device: from the store, then the snapshot (its next handshake fails in the
    /// verify block), then every session of it gets goodbye `removed`.
    package func remove(fingerprint: String) {
        guard let i = paired.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        let device = paired.remove(at: i)
        save()
        publishTrust()
        publish()
        let fp = device.fingerprintData
        door?.closeSessions(Goodbye.removed, matching: { fp != nil && $0.fingerprint == fp }, done: { n in
            print("Removed \(device.displayName); closed \(n) connection\(n == 1 ? "" : "s").")
        })
    }

    /// Renames a paired device (the Mac's own label for it).
    package func rename(fingerprint: String, to name: String) {
        guard let i = paired.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        let clean = SafeText.label(name)
        guard !clean.isEmpty else { return }
        paired[i].name = clean
        paired[i].model = nil
        save()
        publishTrust()
        publish()
    }

    /// A remote session of this paired device started: for the pane's "last connected".
    func sessionStarted(fingerprint: Data, route: String) {
        lastSeen[Base64URL.encode(fingerprint)] = (Date(), route)
        publish()
    }

    /// Judges one kind 19 (RemoteServer hands it over; the reply goes back to the door).
    private func judge(_ attempt: RemoteServer.PairAttempt) -> PairResult {
        guard let identity else { return PairResult(ok: false, reason: PairResult.closed) }
        let wasOpen = window.isOpen
        let proof = Base64URL.decode(attempt.request.proof) ?? Data()
        let now = Date().timeIntervalSince1970
        let verdict = window.tryProof(method: attempt.request.method, proof: proof, fpDevice: attempt.deviceFingerprint,
                                      fpMac: identity.fingerprint, source: attempt.source, now: now)
        switch verdict {
        case .accept(let proofM):
            let name = SafeText.label(attempt.request.name)
            let model = attempt.request.model.map { SafeText.label($0) }.flatMap { $0.isEmpty ? nil : $0 }
            let device = PairedDevice(fingerprint: Base64URL.encode(attempt.deviceFingerprint), name: name, model: model,
                                      pairedAt: now, method: attempt.request.method)
            // Re-pairing the same key replaces its record. The snapshot is updated before kind 20
            // ok goes out, so the session dial that follows is admitted.
            paired.removeAll { $0.fingerprint == device.fingerprint }
            paired.append(device)
            save()
            publishTrust()
            print("Paired \(device.displayName) (key \(RemoteIdentity.shortName(attempt.deviceFingerprint))…) from \(attempt.source), "
                  + "with \(attempt.request.method == PairRequest.qr ? "the QR code" : "the code").")
            pairingState = .paired(device.displayName)
            windowClosed(.used, reopen: true)
            return PairResult(ok: true, proof: Base64URL.encode(proofM), macID: identity.macID, name: macName,
                              recognitionKey: Base64URL.encode(identity.recognitionKey))
        case .reject(let left):
            print("Pairing: a wrong code from \(attempt.source) (\(left) tr\(left == 1 ? "y" : "ies") left).")
            if case .open(let requestedBy, let expiresAt, _, _) = pairingState {
                pairingState = .open(requestedBy: requestedBy, expiresAt: expiresAt, triesLeft: left, lastWrongFrom: attempt.source)
            }
            publish()
            return PairResult(ok: false, reason: PairResult.code, triesLeft: left)
        case .busy(let after):
            return PairResult(ok: false, reason: PairResult.busy, retryAfter: (after * 10).rounded(.up) / 10)
        case .closed(let reason):
            if wasOpen && reason == .stopped {
                print("Pairing stopped after \(PairingWindow.maxFailures) wrong codes.")
                windowClosed(.stopped, reopen: true)
                return PairResult(ok: false, reason: PairResult.stopped)
            }
            if reason == .expired {
                if wasOpen { windowClosed(.expired, reopen: true) }
                return PairResult(ok: false, reason: PairResult.expired)
            }
            return PairResult(ok: false, reason: PairResult.closed)
        }
    }

    /// After a window closed: the snapshot, the door (it stops if Remote Access is off), the
    /// status. The CLI then opens a fresh one after a use or an expiry.
    private func windowClosed(_ reason: PairingWindow.CloseReason, reopen: Bool) {
        expiryTask?.cancel()
        expiryTask = nil
        offerPending = nil
        switch reason {
        case .used: break                       // pairingState already names the device
        case .stopped: pairingState = .stopped
        case .expired: pairingState = .expired
        case .cancelled, .none: pairingState = .closed
        }
        publishTrust()
        updateDoor()
        updateWatchers()
        publish()
        broadcastIfChanged()
        if reopen, reopensPairing, reason == .used || reason == .expired {
            openPairing(requestedBy: nil)
        }
    }

    /// The offer needs the door's port and an address list: made at once when both are known,
    /// else as soon as they are (at most `offerWait` later).
    private func makeOffer(requestedBy: String?, again: Bool) {
        offerPending = (requestedBy, again)
        deliverOfferIfReady(force: false)
        if offerPending != nil {
            offerDeadline?.cancel()
            offerDeadline = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.offerWait))
                guard !Task.isCancelled else { return }
                self?.deliverOfferIfReady(force: true)
            }
        }
    }

    private func deliverOfferIfReady(force: Bool) {
        guard let pendingOffer = offerPending, let identity, let w = window.current else { offerPending = nil; return }
        guard let port = doorPort, force || reach != nil else { return }
        offerPending = nil
        offerDeadline?.cancel()
        let links = addresses().prefix(PairLink.maxAddresses).compactMap { a -> ParsedAddress? in
            guard case .success(var p) = AddressParser.parse(a.host) else { return nil }
            p.port = a.port
            return p
        }
        let link = PairLink(fingerprint: identity.fingerprint, secret: w.secret, name: macName, port: port, addresses: Array(links))
        onPairingOffer?(PairingOffer(url: link.url, code: w.code, expiresAt: Date(timeIntervalSince1970: w.expiresAt),
                                     requestedBy: pendingOffer.requestedBy, port: port, again: pendingOffer.again))
    }

    // MARK: The door, the watchers, the status

    /// The port devices dial: the configured one, or the bound one when any port was asked for.
    private var doorPort: Int? {
        if case .listening(let p) = listenerState { return p }
        return remotePort == 0 ? nil : remotePort
    }

    private func updateDoor() {
        door?.set(wanted: remoteAccess || window.isOpen, port: remotePort)
    }

    /// Reachability runs with the door; the router is asked only with the internet switch on.
    private func updateWatchers() {
        let wanted = identity != nil && (remoteAccess || window.isOpen)
        if wanted, reachability == nil {
            let r = Reachability { [weak self] snapshot in self?.reachabilityChanged(snapshot) }
            reachability = r
            r.start()
        } else if !wanted, let r = reachability {
            r.stop()
            reachability = nil
        }
        let skipRouter = testHost && ProcessInfo.processInfo.environment["SILL_TEST_NO_ROUTER"] == "1"
        let routerWanted = wanted && internetAccess && !skipRouter
        let interface = reach.map { AddressList.routerInterface(Reachability.input($0)) } ?? nil
        if routerWanted, router == nil || interface != routerInterface {
            router?.stop()
            routerInterface = interface
            router = RouterAddress(interface: interface) { [weak self] r in
                self?.routerState = r
                self?.publish()
                self?.broadcastIfChanged()
            }
            routerState = router == nil ? .noAnswer : .asking
        } else if !routerWanted, let r = router {
            r.stop()
            router = nil
            routerState = .off
        } else if !routerWanted {
            routerState = .off
        }
    }

    private func reachabilityChanged(_ snapshot: Reachability.Snapshot) {
        guard reachability != nil else { return }
        let first = reach == nil
        reach = snapshot
        publishTrust()
        door?.retryNow()
        updateWatchers()
        publish()
        broadcastIfChanged()
        if first { deliverOfferIfReady(force: false) }
    }

    private func listenerChanged(_ state: RemoteStatus.Listener) {
        listenerState = state
        publish()
        broadcastIfChanged()
        if case .listening = state { deliverOfferIfReady(force: false) }
    }

    /// In dial order; empty while Remote Access is off and no window is open.
    private func addresses() -> [MacAddress] {
        guard remoteAccess || window.isOpen else { return [] }
        var input = reach.map(Reachability.input) ?? AddressList.Input()
        input.internet = internetAccess
        input.addressName = addressName
        if case .address(let a) = routerState { input.routerIPv4 = a }
        input.testLoopback = testHost
        return AddressList.build(input)
    }

    private func publishTrust() {
        var map: [Data: String] = [:]
        for d in paired { if let fp = d.fingerprintData { map[fp] = d.displayName } }
        let open = window.isOpen, on = remoteAccess, internet = internetAccess
        let names = reach?.serviceNames ?? [:]
        trust.update {
            $0.paired = map
            $0.pairingOpen = open
            $0.remoteAccess = on
            $0.internetAccess = internet
            $0.serviceNames = names
        }
    }

    private func publish() {
        guard let status else { return }
        let summaries = paired.sorted { $0.pairedAt < $1.pairedAt }.map { d -> PairedDeviceSummary in
            let seen = lastSeen[d.fingerprint]
            return PairedDeviceSummary(id: d.fingerprint, keyPrefix: d.fingerprintData.map(RemoteIdentity.shortName) ?? "?",
                                       name: d.displayName, model: d.model, pairedAt: Date(timeIntervalSince1970: d.pairedAt),
                                       method: d.method, lastSeen: seen?.at, lastRoute: seen?.route)
        }
        let input = reach.map(Reachability.input)
        let remote = RemoteStatus(remoteAccess: remoteAccess, internetAccess: internetAccess, listener: listenerState,
                                  addresses: addresses(),
                                  vpnDown: reach.map { AddressList.vpnDown(setupVPNs: $0.setupVPNs, services: $0.services) } ?? [],
                                  lanAddress: input.flatMap(AddressList.lanAddress), router: routerState,
                                  addressName: addressNameText, pairing: pairingState, paired: summaries,
                                  identityProblem: identityProblem)
        status.update { $0.remote = remote }
    }

    private func save() {
        do { try store?.savePaired(paired) } catch { print("Remote access: the paired devices could not be saved (\(error)).") }
    }

    // MARK: Kind 18

    /// Who this Mac is and how to reach it, as of now (issuedAt 0: the comparison ignores it).
    private func currentInfo() -> MacInfo? {
        guard let identity else { return nil }
        return MacInfo(macID: identity.macID, name: macName, issuedAt: 0, remoteAccess: remoteAccess,
                       remotePort: doorPort ?? remotePort, internet: internetAccess, addresses: addresses())
    }

    /// Kind 18, signed, issued now: in every catalog right after kind 16.
    func macInfoMessage() -> StreamMessage? {
        guard var info = currentInfo(), let identity else { return nil }
        info.issuedAt = Date().timeIntervalSince1970
        guard let signed = identity.sign(info) else { return nil }
        return StreamMessage(kind: .macInfo, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: Wire.encode(signed))
    }

    /// To every device, when anything but the time changed since the last broadcast.
    private func broadcastIfChanged() {
        guard let info = currentInfo(), info != lastBroadcast else { return }
        lastBroadcast = info
        if let m = macInfoMessage() { server?.broadcast(m) }
    }
}
